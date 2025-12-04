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
}
