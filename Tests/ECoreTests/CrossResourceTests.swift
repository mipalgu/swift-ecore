//
// CrossResourceTests.swift
// ECoreTests
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing
import Foundation
@testable import ECore

/// Test suite for cross-resource references
///
/// This test suite validates cross-resource reference handling:
/// - Loading related XMI files via ResourceSet
/// - ResourceProxy creation for external hrefs
/// - Automatic resource loading on proxy resolution
/// - Cross-resource XPath navigation
/// - Round-trip preservation of external references
@Suite("Cross-Resource Reference Tests")
struct CrossResourceTests {

    // MARK: - Helper Methods

    /// Get the URL for the test resources directory
    private func getResourcesURL() throws -> URL {
        guard let bundleResourcesURL = Bundle.module.resourceURL else {
            throw TestError.resourcesNotFound
        }

        let fm = FileManager.default
        let testResourcesURL = bundleResourcesURL.appendingPathComponent("Resources")
        var isDirectory = ObjCBool(false)

        if fm.fileExists(atPath: testResourcesURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return testResourcesURL
        } else {
            return bundleResourcesURL
        }
    }

    /// Test-specific errors
    private enum TestError: Error {
        case resourcesNotFound
        case fileNotFound(String)
    }

    // MARK: - Resource Proxy Tests

    /// Test ResourceProxy creation and basic properties
    @Test("ResourceProxy creation")
    func testResourceProxyCreation() {
        let proxy = ResourceProxy(uri: "department-b.xmi", fragment: "/")

        #expect(proxy.uri == "department-b.xmi")
        #expect(proxy.fragment == "/")
    }

    /// Test ResourceProxy equality and hashing
    @Test("ResourceProxy equality and hashing")
    func testResourceProxyEquality() {
        let proxy1 = ResourceProxy(uri: "dept.xmi", fragment: "//@employees.0")
        let proxy2 = ResourceProxy(uri: "dept.xmi", fragment: "//@employees.0")
        let proxy3 = ResourceProxy(uri: "other.xmi", fragment: "//@employees.0")

        #expect(proxy1 == proxy2)
        #expect(proxy1 != proxy3)
        #expect(proxy1.hashValue == proxy2.hashValue)
    }

    // MARK: - Cross-Resource Loading Tests

    /// Test loading two related XMI files
    @Test("Load cross-resource XMI files")
    func testLoadCrossResourceFiles() async throws {
        let resourcesURL = try getResourcesURL()
        let xmiDir = resourcesURL.appendingPathComponent("xmi")

        // Create ResourceSet
        let resourceSet = ResourceSet()

        // Load company-a.xmi (has reference to department-b.xmi)
        let companyURL = xmiDir.appendingPathComponent("company-a.xmi")

        guard FileManager.default.fileExists(atPath: companyURL.path) else {
            throw TestError.fileNotFound("company-a.xmi")
        }

        // Parse company-a.xmi with ResourceSet
        let parser = XMIParser(resourceSet: resourceSet)
        let companyResource = try await parser.parse(companyURL)

        // Verify company loaded
        let roots = await companyResource.getRootObjects()
        #expect(roots.count == 1)

        let company = roots[0] as? DynamicEObject
        #expect(company != nil)

        let companyName = await companyResource.eGet(objectId: company!.id, feature: "name") as? String
        #expect(companyName == "TechCorp")

        // Verify reference is stored as ResourceProxy
        let mainDeptRef = await companyResource.eGet(objectId: company!.id, feature: "mainDepartment")
        #expect(mainDeptRef is ResourceProxy, "External reference should be ResourceProxy")

        if let proxy = mainDeptRef as? ResourceProxy {
            #expect(proxy.uri.contains("department-b.xmi"), "Proxy should reference department-b.xmi")
            #expect(proxy.fragment == "/", "Proxy should reference root of department-b.xmi")
        }
    }

    /// Test automatic loading of referenced resource
    @Test("Resolve cross-resource proxy")
    func testResolveCrossResourceProxy() async throws {
        let resourcesURL = try getResourcesURL()
        let xmiDir = resourcesURL.appendingPathComponent("xmi")

        // Create ResourceSet
        let resourceSet = ResourceSet()

        // Load company-a.xmi
        let companyURL = xmiDir.appendingPathComponent("company-a.xmi")

        guard FileManager.default.fileExists(atPath: companyURL.path) else {
            throw TestError.fileNotFound("company-a.xmi")
        }

        let parser = XMIParser(resourceSet: resourceSet)
        let companyResource = try await parser.parse(companyURL)

        let roots = await companyResource.getRootObjects()
        let company = roots[0] as? DynamicEObject
        #expect(company != nil)

        // Get the proxy
        guard let proxy = await companyResource.eGet(objectId: company!.id, feature: "mainDepartment") as? ResourceProxy else {
            Issue.record("mainDepartment should be a ResourceProxy")
            return
        }

        // Resolve the proxy - this should automatically load department-b.xmi
        guard let resolvedId = await proxy.resolve(in: resourceSet) else {
            Issue.record("Failed to resolve proxy")
            return
        }

        // Get the department resource
        guard let deptResource = await resourceSet.getResource(uri: proxy.uri) else {
            Issue.record("Department resource should be loaded")
            return
        }

        // Verify department object
        guard let dept = await deptResource.resolve(resolvedId) as? DynamicEObject else {
            Issue.record("Resolved object should be a DynamicEObject")
            return
        }

        let deptName = await deptResource.eGet(objectId: dept.id, feature: "name") as? String
        #expect(deptName == "Engineering", "Department name should be Engineering")

        // Verify department has employees
        let employees = await deptResource.eGet(objectId: dept.id, feature: "employees") as? [EUUID]
        #expect(employees?.count == 2, "Department should have 2 employees")
    }

    /// Test cross-resource navigation through multiple files
    @Test("Navigate across resources")
    func testCrossResourceNavigation() async throws {
        let resourcesURL = try getResourcesURL()
        let xmiDir = resourcesURL.appendingPathComponent("xmi")

        let resourceSet = ResourceSet()

        // Load company-a.xmi
        let companyURL = xmiDir.appendingPathComponent("company-a.xmi")
        guard FileManager.default.fileExists(atPath: companyURL.path) else {
            throw TestError.fileNotFound("company-a.xmi")
        }

        let parser = XMIParser(resourceSet: resourceSet)
        let companyResource = try await parser.parse(companyURL)

        let company = (await companyResource.getRootObjects())[0] as! DynamicEObject

        // Get and resolve the proxy
        let proxy = await companyResource.eGet(objectId: company.id, feature: "mainDepartment") as! ResourceProxy
        let deptId = await proxy.resolve(in: resourceSet)!

        // Now we have both resources loaded
        #expect(await resourceSet.count() == 2, "Should have 2 resources loaded")

        // Navigate from company to department to employees
        let deptResource = await resourceSet.getResource(uri: proxy.uri)!
        let dept = await deptResource.resolve(deptId) as! DynamicEObject

        let employeeIds = await deptResource.eGet(objectId: dept.id, feature: "employees") as! [EUUID]
        let firstEmployeeId = employeeIds[0]

        let firstEmployee = await deptResource.resolve(firstEmployeeId) as! DynamicEObject
        let employeeName = await deptResource.eGet(objectId: firstEmployee.id, feature: "name") as? String
        #expect(employeeName == "Alice", "First employee should be Alice")
    }

    // MARK: - Relative URI Resolution Tests

    /// Test that relative URIs are resolved correctly
    @Test("Relative URI resolution")
    func testRelativeURIResolution() async throws {
        let resourcesURL = try getResourcesURL()
        let xmiDir = resourcesURL.appendingPathComponent("xmi")

        let resourceSet = ResourceSet()

        // Load company-a.xmi
        let companyURL = xmiDir.appendingPathComponent("company-a.xmi")
        guard FileManager.default.fileExists(atPath: companyURL.path) else {
            throw TestError.fileNotFound("company-a.xmi")
        }

        let parser = XMIParser(resourceSet: resourceSet)
        let companyResource = try await parser.parse(companyURL)

        let company = (await companyResource.getRootObjects())[0] as! DynamicEObject
        let proxy = await companyResource.eGet(objectId: company.id, feature: "mainDepartment") as! ResourceProxy

        // The proxy URI should be resolved relative to company-a.xmi
        // Since both files are in the same directory, it should resolve to the full path
        #expect(proxy.uri.contains("department-b.xmi"), "Proxy URI should contain department-b.xmi")

        // The resolved URI should be a full path
        #expect(proxy.uri.contains("/") || proxy.uri.contains("file://"), "Proxy URI should be an absolute path")
    }

    // MARK: - In-Memory Verification Tests

    /// Test in-memory model consistency across resources
    @Test("In-memory consistency across resources")
    func testInMemoryConsistency() async throws {
        let resourcesURL = try getResourcesURL()
        let xmiDir = resourcesURL.appendingPathComponent("xmi")

        let resourceSet = ResourceSet()

        // Load both files
        let companyURL = xmiDir.appendingPathComponent("company-a.xmi")
        let deptURL = xmiDir.appendingPathComponent("department-b.xmi")

        guard FileManager.default.fileExists(atPath: companyURL.path) &&
              FileManager.default.fileExists(atPath: deptURL.path) else {
            throw TestError.fileNotFound("cross-resource test files")
        }

        let parser = XMIParser(resourceSet: resourceSet)

        // Load company first
        let companyResource = try await parser.parse(companyURL)

        // Verify company in memory
        let companyRoots = await companyResource.getRootObjects()
        #expect(companyRoots.count == 1, "Company resource should have 1 root")

        // Load department manually
        let deptResource = try await parser.parse(deptURL)

        // Verify department in memory
        let deptRoots = await deptResource.getRootObjects()
        #expect(deptRoots.count == 1, "Department resource should have 1 root")

        let dept = deptRoots[0] as! DynamicEObject
        let deptName = await deptResource.eGet(objectId: dept.id, feature: "name") as? String
        #expect(deptName == "Engineering")

        let employees = await deptResource.eGet(objectId: dept.id, feature: "employees") as? [EUUID]
        #expect(employees?.count == 2, "Should have 2 employees in memory")

        // Verify both resources in ResourceSet
        #expect(await resourceSet.count() == 2, "ResourceSet should contain 2 resources")
    }

    // MARK: - Round-Trip Tests

    /// Test round-trip serialization of cross-resource references
    @Test("Cross-resource round-trip serialization")
    func testCrossResourceRoundTrip() async throws {
        let resourcesURL = try getResourcesURL()
        let xmiDir = resourcesURL.appendingPathComponent("xmi")

        let resourceSet = ResourceSet()

        // Load company-a.xmi
        let companyURL = xmiDir.appendingPathComponent("company-a.xmi")
        guard FileManager.default.fileExists(atPath: companyURL.path) else {
            throw TestError.fileNotFound("company-a.xmi")
        }

        let parser = XMIParser(resourceSet: resourceSet)
        let companyResource = try await parser.parse(companyURL)

        // Get the company object and verify it has the cross-resource reference
        let company = (await companyResource.getRootObjects())[0] as! DynamicEObject
        let originalProxy = await companyResource.eGet(objectId: company.id, feature: "mainDepartment") as! ResourceProxy

        #expect(originalProxy.uri.contains("department-b.xmi"), "Original should reference department-b.xmi")
        #expect(originalProxy.fragment == "/", "Original should reference root")

        // Serialize to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("company-roundtrip-\(UUID().uuidString).xmi")

        let serializer = XMISerializer()
        try await serializer.serialize(companyResource, to: tempURL)

        // Read the serialized XML to verify the href format
        let serializedXML = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(serializedXML.contains("department-b.xmi#/"), "Serialized XML should contain external href")

        // Reload the serialized file
        let newResourceSet = ResourceSet()
        let newParser = XMIParser(resourceSet: newResourceSet)
        let reloadedResource = try await newParser.parse(tempURL)

        // Verify the cross-resource reference is preserved
        let reloadedCompany = (await reloadedResource.getRootObjects())[0] as! DynamicEObject
        let reloadedName = await reloadedResource.eGet(objectId: reloadedCompany.id, feature: "name") as? String
        #expect(reloadedName == "TechCorp", "Company name should be preserved")

        let reloadedProxy = await reloadedResource.eGet(objectId: reloadedCompany.id, feature: "mainDepartment")
        #expect(reloadedProxy is ResourceProxy, "Reloaded reference should be ResourceProxy")

        if let proxy = reloadedProxy as? ResourceProxy {
            #expect(proxy.uri.contains("department-b.xmi"), "Reloaded proxy should reference department-b.xmi")
            #expect(proxy.fragment == "/", "Reloaded proxy should reference root")
        }

        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
}
