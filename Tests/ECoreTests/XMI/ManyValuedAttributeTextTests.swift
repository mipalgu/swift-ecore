//
// ManyValuedAttributeTextTests.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// A metamodel whose class has many-valued attributes of several data types.
private enum ProfileFixture {
    static let metamodel = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="profiles"
            nsURI="http://example.org/profiles" nsPrefix="profiles">
          <eClassifiers xsi:type="ecore:EClass" name="Profile">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="name"
                eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="skills" upperBound="-1"
                eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="scores" upperBound="3"
                eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EInt"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="ratios" upperBound="-1"
                eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EDouble"/>
          </eClassifiers>
        </ecore:EPackage>
        """

    /// An instance document whose root carries the given attributes.
    static func instance(_ attributes: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <profiles:Profile xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:profiles="http://example.org/profiles" \(attributes)/>
        """
    }

    /// Parses an instance document, with the metamodel registered unless told otherwise.
    ///
    /// - Parameters:
    ///   - text: The instance document.
    ///   - withMetamodel: Whether the metamodel is registered with the resource set.
    /// - Returns: The root object of the document.
    static func root(of text: String, withMetamodel: Bool = true) async throws -> DynamicEObject {
        let set = ResourceSet()
        if withMetamodel {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let metamodelURL = directory.appendingPathComponent("profiles.ecore")
            try metamodel.write(to: metamodelURL, atomically: testWritesAtomically, encoding: .utf8)
            let package = try await EPackage(url: metamodelURL)
            await set.registerMetamodel(package, uri: package.nsURI)
        }
        let resource = try await XMIParser(resourceSet: set).parse(text, uri: "file:///models/profile.xmi")
        return try #require(await resource.getRootObjects().first as? DynamicEObject)
    }
}

@Suite("Many-valued attributes written as one XML attribute")
struct ManyValuedAttributeTextTests {
    @Test("splits a many-valued string attribute on white space")
    func strings() async throws {
        let root = try await ProfileFixture.root(of: ProfileFixture.instance(#"skills="Swift Java  Python""#))

        #expect(root.eGet("skills") as? [String] == ["Swift", "Java", "Python"])
    }

    @Test("splits and converts a many-valued integer attribute")
    func integers() async throws {
        let root = try await ProfileFixture.root(of: ProfileFixture.instance(#"scores="3 14 -2""#))

        #expect(root.eGet("scores") as? [Int] == [3, 14, -2])
    }

    @Test("splits and converts a many-valued double attribute")
    func doubles() async throws {
        let root = try await ProfileFixture.root(of: ProfileFixture.instance(#"ratios="0.5 1.25""#))

        #expect(root.eGet("ratios") as? [Double] == [0.5, 1.25])
    }

    @Test("reads an empty value as no values")
    func empty() async throws {
        let root = try await ProfileFixture.root(of: ProfileFixture.instance(#"skills="" scores="""#))

        #expect(root.eGet("skills") as? [String] == [])
        #expect((root.eGet("scores") as? [Int])?.isEmpty == true)
    }

    @Test("keeps a single-valued string attribute with spaces as one value")
    func singleValued() async throws {
        let root = try await ProfileFixture.root(of: ProfileFixture.instance(#"name="Ada Lovelace""#))

        #expect(root.eGet("name") as? String == "Ada Lovelace")
    }

    @Test("keeps the text as one value without a metamodel")
    func withoutMetamodel() async throws {
        let root = try await ProfileFixture.root(
            of: ProfileFixture.instance(#"skills="Swift Java Python""#), withMetamodel: false)

        #expect(root.eGet("skills") as? String == "Swift Java Python")
    }

    @Test("round trips through both layouts of many-valued attributes")
    func roundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let metamodelURL = directory.appendingPathComponent("profiles.ecore")
        try ProfileFixture.metamodel.write(to: metamodelURL, atomically: testWritesAtomically, encoding: .utf8)
        let set = ResourceSet()
        let package = try await EPackage(url: metamodelURL)
        await set.registerMetamodel(package, uri: package.nsURI)
        let text = ProfileFixture.instance(#"name="Ada" skills="Swift Java" scores="3 14" ratios="0.5 1.25""#)
        let resource = try await XMIParser(resourceSet: set).parse(text, uri: "file:///models/profile.xmi")

        for asElements in [false, true] {
            var options = XMISerializationOptions.emf
            options.manyValuedAttributesAsElements = asElements
            let written = try await XMISerializer(options: options).serialize(resource)
            if !asElements {
                #expect(written.contains(#"skills="Swift Java""#))
                #expect(written.contains(#"scores="3 14""#))
            }
            let reread = try await XMIParser(resourceSet: set).parse(written, uri: "file:///models/again.xmi")
            let root = try #require(await reread.getRootObjects().first as? DynamicEObject)
            #expect(root.eGet("skills") as? [String] == ["Swift", "Java"], "\(written)")
            #expect(root.eGet("scores") as? [Int] == [3, 14], "\(written)")
            #expect(root.eGet("ratios") as? [Double] == [0.5, 1.25], "\(written)")
            #expect(root.eGet("name") as? String == "Ada")
        }
    }
}
