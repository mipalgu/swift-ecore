//
// XMIParserTests.swift
// ECoreTests
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
import Foundation
@testable import ECore

/// Test suite for XMI parsing functionality
///
/// This test suite validates XMI (XML Metadata Interchange) parsing with:
/// - Metamodel (.ecore) file parsing
/// - Model instance (.xmi) file parsing
/// - Cross-resource references
/// - Round-trip serialisation
@Suite("XMI Parser Tests")
struct XMIParserTests {

    // MARK: - Helper Methods

    /// Get the URL for the test resources directory
    ///
    /// This helper locates the Resources directory within the test bundle,
    /// handling different build configurations appropriately.
    ///
    /// - Returns: URL pointing to the Resources directory
    /// - Throws: TestError.resourcesNotFound if the resources directory cannot be located
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

    // MARK: - Basic Parsing Tests

    /// Test parsing a minimal XMI document
    @Test("Parse minimal XMI structure")
    func testParseMinimalXMI() async throws {
        let xmi = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage
            xmi:version="2.0"
            xmlns:xmi="http://www.omg.org/XMI"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
            name="test"
            nsURI="http://test"
            nsPrefix="test">
        </ecore:EPackage>
        """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".ecore")
        try xmi.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parser = XMIParser()
        let resource = try await parser.parse(tempURL)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)
    }

    // MARK: - Metamodel Parsing Tests

    /// Test parsing a simple empty package
    ///
    /// This test validates:
    /// - Basic EPackage parsing
    /// - Namespace attributes (name, nsURI, nsPrefix)
    @Test("Parse simple.ecore metamodel")
    func testParseSimpleEcore() async throws {
        let resourcesURL = try getResourcesURL()
        let url = resourcesURL.appendingPathComponent("xmi").appendingPathComponent("simple.ecore")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestError.fileNotFound("simple.ecore")
        }

        let parser = XMIParser()
        let resource = try await parser.parse(url)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        // Verify package attributes
        let pkg = roots[0] as? DynamicEObject
        #expect(pkg != nil)

        let pkgName = await resource.eGet(objectId: pkg!.id, feature: "name") as? String
        #expect(pkgName == "simple")

        let nsURI = await resource.eGet(objectId: pkg!.id, feature: "nsURI") as? String
        #expect(nsURI == "http://swift-modelling.org/test/simple")

        let nsPrefix = await resource.eGet(objectId: pkg!.id, feature: "nsPrefix") as? String
        #expect(nsPrefix == "simple")
    }

    /// Test parsing animals.ecore with enumerations
    ///
    /// This test validates:
    /// - EPackage parsing with namespace attributes
    /// - EEnum parsing with literals
    /// - EClass parsing with attributes
    /// - Default value literals
    /// - Reference to enum types
    @Test("Parse animals.ecore metamodel with enumerations")
    func testParseAnimalsEcore() async throws {
        let resourcesURL = try getResourcesURL()
        let url = resourcesURL.appendingPathComponent("xmi").appendingPathComponent("animals.ecore")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestError.fileNotFound("animals.ecore")
        }

        let parser = XMIParser()
        let resource = try await parser.parse(url)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        // Verify package attributes
        let pkg = roots[0] as? DynamicEObject
        #expect(pkg != nil)

        let pkgName = await resource.eGet(objectId: pkg!.id, feature: "name") as? String
        #expect(pkgName == "animals")

        let nsURI = await resource.eGet(objectId: pkg!.id, feature: "nsURI") as? String
        #expect(nsURI == "http://swift-modelling.org/test/animals")

        // Verify classifiers were parsed
        let classifiers = await resource.eGet(objectId: pkg!.id, feature: "eClassifiers") as? [EUUID]
        #expect(classifiers != nil)
        #expect(classifiers?.count == 2) // Animal class and Species enum
    }

    /// Test parsing organisation.ecore with references
    ///
    /// This test validates:
    /// - EClass with EAttribute and EReference
    /// - Containment references
    /// - Cross-references (non-containment)
    /// - Multiplicity (lowerBound, upperBound)
    @Test("Parse organisation.ecore metamodel with references")
    func testParseOrganisationEcore() async throws {
        let resourcesURL = try getResourcesURL()
        let url = resourcesURL.appendingPathComponent("xmi").appendingPathComponent("organisation.ecore")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestError.fileNotFound("organisation.ecore")
        }

        let parser = XMIParser()
        let resource = try await parser.parse(url)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        let pkg = roots[0] as? DynamicEObject
        #expect(pkg != nil)

        let pkgName = await resource.eGet(objectId: pkg!.id, feature: "name") as? String
        #expect(pkgName == "organisation")

        // Verify classifiers were parsed
        let classifiers = await resource.eGet(objectId: pkg!.id, feature: "eClassifiers") as? [EUUID]
        #expect(classifiers != nil)
        #expect(classifiers?.count == 3) // Person, Team, Organisation
    }

    // MARK: - Instance Parsing Tests

    /// Test parsing a simple instance file
    ///
    /// This test validates:
    /// - Instance XMI parsing
    /// - Attribute values on instances
    /// - Namespace-based type resolution
    @Test("Parse simple animal instance")
    func testParseSimpleInstance() async throws {
        let resourcesURL = try getResourcesURL()
        let url = resourcesURL.appendingPathComponent("xmi").appendingPathComponent("zoo.xmi")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestError.fileNotFound("zoo.xmi")
        }

        let parser = XMIParser()
        let resource = try await parser.parse(url)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        // Verify instance attributes
        let animal = roots[0] as? DynamicEObject
        #expect(animal != nil)

        let name = await resource.eGet(objectId: animal!.id, feature: "name") as? String
        #expect(name == "Fluffy")

        let species = await resource.eGet(objectId: animal!.id, feature: "species") as? String
        #expect(species == "cat")
    }

    /// Test parsing instance with containment references
    ///
    /// This test validates:
    /// - Containment reference parsing
    /// - Multiple contained objects
    /// - Cross-references within same resource
    /// - XPath reference resolution (leader href="#//@members.0")
    @Test("Parse team instance with members and references")
    func testParseTeamInstance() async throws {
        let resourcesURL = try getResourcesURL()
        let url = resourcesURL.appendingPathComponent("xmi").appendingPathComponent("team.xmi")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestError.fileNotFound("team.xmi")
        }

        let parser = XMIParser()
        let resource = try await parser.parse(url)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        // Verify team attributes
        let team = roots[0] as? DynamicEObject
        #expect(team != nil)

        let teamName = await resource.eGet(objectId: team!.id, feature: "name") as? String
        #expect(teamName == "Engineering")

        // Verify contained members
        let members = await resource.eGet(objectId: team!.id, feature: "members") as? [EUUID]
        #expect(members != nil)
        #expect(members?.count == 3)

        // Verify first member's name
        if let firstMemberId = members?.first {
            let memberName = await resource.eGet(objectId: firstMemberId, feature: "name") as? String
            #expect(memberName == "Alice")

            // Verify XPath reference resolution - leader should point to first member
            let leaderId = await resource.eGet(objectId: team!.id, feature: "leader") as? EUUID
            #expect(leaderId != nil, "Leader reference should be resolved")
            #expect(leaderId == firstMemberId, "Leader should reference the first member (Alice)")

            // Verify leader's name is Alice
            if let leaderId = leaderId {
                let leaderName = await resource.eGet(objectId: leaderId, feature: "name") as? String
                #expect(leaderName == "Alice", "Leader's name should be Alice")
            }
        }
    }

    /// Test parsing XMI with arbitrary attributes
    ///
    /// This test validates:
    /// - Dynamic attribute iteration using `element.attributeNames`
    /// - Type inference for Int, Double, Bool, and String
    /// - Arbitrary user-defined attribute names
    /// - No data loss for unmapped attributes
    @Test("Parse XMI with arbitrary attributes and type inference")
    func testArbitraryAttributes() async throws {
        let resourcesURL = try getResourcesURL()
        let url = resourcesURL.appendingPathComponent("xmi").appendingPathComponent("arbitrary-attributes.xmi")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestError.fileNotFound("arbitrary-attributes.xmi")
        }

        let parser = XMIParser()
        let resource = try await parser.parse(url)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        let record = roots[0] as? DynamicEObject
        #expect(record != nil)

        // Verify all attributes were captured with correct types
        let id = await resource.eGet(objectId: record!.id, feature: "id") as? String
        #expect(id == "R001")

        let name = await resource.eGet(objectId: record!.id, feature: "name") as? String
        #expect(name == "Test Record")

        let email = await resource.eGet(objectId: record!.id, feature: "email") as? String
        #expect(email == "test@example.com")

        // Verify Int type inference
        let count = await resource.eGet(objectId: record!.id, feature: "count") as? Int
        #expect(count == 42)

        // Verify Double type inference
        let ratio = await resource.eGet(objectId: record!.id, feature: "ratio") as? Double
        #expect(ratio == 3.14)

        // Verify Bool type inference (true)
        let active = await resource.eGet(objectId: record!.id, feature: "active") as? Bool
        #expect(active == true)

        // Verify Bool type inference (false)
        let inactive = await resource.eGet(objectId: record!.id, feature: "inactive") as? Bool
        #expect(inactive == false)

        // Verify String fallback for non-parseable values
        let status = await resource.eGet(objectId: record!.id, feature: "status") as? String
        #expect(status == "pending")
    }
}
