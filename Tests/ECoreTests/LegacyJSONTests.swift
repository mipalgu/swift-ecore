//
// LegacyJSONTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests that JSON documents in the shapes written by earlier releases load, with and
/// without a registered metamodel, and convert to XMI.
///
/// Releases up to 0.3 encoded objects through `Codable`: unqualified `eClass` names,
/// escaped slashes, nested objects inline, and references (including containment held by
/// identifier) as bare UUID strings, with one object or an array of roots at the top.
/// Later releases write package-qualified classes and `$ref` fragments, and wrote the
/// container side of containments as `$ref` entries as well.
@Suite("Legacy JSON documents")
struct LegacyJSONTests {
    /// The namespace URI of the catalogue package.
    static let catalogueURI = "http://www.example.org/catalogue"

    /// The legacy fixtures.
    static let fixtures = ["codable-single-root.json", "codable-several-roots.json", "fragments-container-side.json"]

    /// A catalogue metamodel with sections that contain items.
    static func cataloguePackage() -> EPackage {
        let string = EcorePackage.dataType(.eString) ?? EDataType(name: "EString")
        let double = EcorePackage.dataType(.eDouble) ?? EDataType(name: "EDouble")
        let date = EcorePackage.dataType(.eDate) ?? EDataType(name: "EDate")
        let sectionsID = EUUID(), catalogueID = EUUID(), itemsID = EUUID(), sectionID = EUUID()
        var item = EClass(name: "Item")
        item.eStructuralFeatures = [
            EAttribute(name: "code", eType: string, isID: true),
            EAttribute(name: "label", eType: string),
            EAttribute(name: "price", eType: double),
        ]
        item.eStructuralFeatures.append(EReference(name: "related", eType: item, upperBound: -1))
        var section = EClass(name: "Section", eStructuralFeatures: [EAttribute(name: "name", eType: string)])
        section.eStructuralFeatures.append(
            EReference(id: itemsID, name: "items", eType: item, upperBound: -1, containment: true, opposite: sectionID))
        item.eStructuralFeatures.append(EReference(id: sectionID, name: "section", eType: section, opposite: itemsID))
        var catalogue = EClass(
            name: "Catalogue",
            eStructuralFeatures: [
                EAttribute(name: "title", eType: string), EAttribute(name: "homepage", eType: string),
                EAttribute(name: "issued", eType: date),
                EReference(id: sectionsID, name: "sections", eType: section, upperBound: -1, containment: true,
                    opposite: catalogueID),
                EReference(name: "highlight", eType: item), EReference(name: "featured", eType: item, upperBound: -1),
            ])
        section.eStructuralFeatures.append(
            EReference(id: catalogueID, name: "catalogue", eType: catalogue, opposite: sectionsID))
        catalogue.eStructuralFeatures[3] = EReference(
            id: sectionsID, name: "sections", eType: section, upperBound: -1, containment: true, opposite: catalogueID)
        return EPackage(
            name: "catalogue", nsURI: catalogueURI, nsPrefix: "catalogue", eClassifiers: [catalogue, section, item])
    }

    /// A resource set with the catalogue metamodel registered.
    static func catalogueSet() async -> ResourceSet {
        let set = ResourceSet()
        let package = cataloguePackage()
        await set.registerMetamodel(package, uri: package.nsURI)
        return set
    }

    /// The bytes of a legacy fixture.
    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: try ReflectionFixtures.resourcesURL().appendingPathComponent("json/legacy/\(name)"))
    }

    /// Loads a legacy fixture.
    ///
    /// - Parameters:
    ///   - name: The file name of the fixture.
    ///   - set: The resource set with the metamodel, or `nil` to load without one.
    /// - Returns: The resource and the parser's warnings.
    static func load(_ name: String, in set: ResourceSet?) async throws -> (Resource, [ConversionWarning.Kind]) {
        let parser = JSONParser(resourceSet: set)
        let resource = try await parser.parse(try data(name), uri: "memory:/\(name)")
        return (resource, await parser.diagnostics.warnings.map(\.kind))
    }

    /// The roots of a resource as dynamic objects.
    static func roots(_ resource: Resource) async -> [DynamicEObject] {
        await resource.getRootObjects().compactMap { $0 as? DynamicEObject }
    }

    /// Resolves the objects that a feature of an object holds.
    static func objects(_ feature: String, of object: DynamicEObject, in resource: Resource) async throws
        -> [DynamicEObject]
    {
        try await ConversionDiagnosticsTests.objects(feature, of: object, in: resource)
    }

    // MARK: - Releases up to 0.3

    @Test("a single-root Codable document loads as typed objects")
    func codableSingleRootTyped() async throws {
        let set = await Self.catalogueSet()
        let (resource, warnings) = try await Self.load("codable-single-root.json", in: set)
        let package = try #require(await set.getMetamodel(uri: Self.catalogueURI))
        let roots = await Self.roots(resource)
        try #require(roots.count == 1)
        let catalogue = roots[0]
        #expect(catalogue.eClass.id == package.getEClass("Catalogue")?.id)
        #expect(catalogue.eGet("homepage") as? String == "http://www.example.org/catalogue")
        let issued = try #require(catalogue.eGet("issued") as? Date)
        #expect(EcoreDateCoding.fractionalString(from: issued) == "2026-01-02T03:04:05.123000Z")
        let sections = try await Self.objects("sections", of: catalogue, in: resource)
        try #require(sections.count == 1)
        #expect(sections[0].eClass.id == package.getEClass("Section")?.id)
        let items = try await Self.objects("items", of: sections[0], in: resource)
        #expect(items.map { $0.eGet("label") as? String } == ["Lamp", "Desk"])
        #expect(items.map(\.eClass.name) == ["Item", "Item"])
        try #require(items.count == 2)
        #expect(items[1].eGet("price") as? Double == 80)
        #expect(ReferenceValues.identifiers(items[1].eGet("related")) == [items[0].id])
        #expect(await resource.getAllObjects().count == 4)
        #expect(warnings.contains(.referenceWithoutFragment(feature: "featured", className: "Catalogue")))
        #expect(warnings.contains(.referenceWithoutFragment(feature: "highlight", className: "Catalogue")))
        #expect(!warnings.contains { if case .untypedClass = $0 { true } else { false } })
    }

    @Test("a Codable document with several roots and identifier containment loads with warnings")
    func codableSeveralRootsTyped() async throws {
        let set = await Self.catalogueSet()
        let (resource, warnings) = try await Self.load("codable-several-roots.json", in: set)
        let roots = await Self.roots(resource)
        #expect(roots.map(\.eClass.name) == ["Catalogue", "Item"])
        #expect(roots.first?.eGet("title") as? String == "Summer")
        #expect(roots.last?.eGet("price") as? Double == 45.25)
        #expect(warnings.contains(.referenceWithoutFragment(feature: "sections", className: "Catalogue")))
        #expect(warnings.contains(.referenceWithoutFragment(feature: "related", className: "Item")))
    }

    // MARK: - Later releases

    @Test("a fragment document with container-side references loads without duplicates")
    func fragmentsContainerSideTyped() async throws {
        let set = await Self.catalogueSet()
        let (resource, warnings) = try await Self.load("fragments-container-side.json", in: set)
        let roots = await Self.roots(resource)
        try #require(roots.count == 2)
        let autumn = try await Self.objects("sections", of: roots[0], in: resource)
        try #require(autumn.count == 1)
        let items = try await Self.objects("items", of: autumn[0], in: resource)
        #expect(items.map { $0.eGet("label") as? String } == ["Rug", "Mirror"])
        try #require(items.count == 2)
        let winter = try await Self.objects("sections", of: roots[1], in: resource)
        try #require(winter.count == 1)
        let vase = try await Self.objects("items", of: winter[0], in: resource)
        #expect(ReferenceValues.identifiers(items[1].eGet("related")) == vase.map(\.id))
        #expect(ReferenceValues.identifiers(roots[0].eGet("highlight")) == [items[1].id])
        #expect(warnings == [.referenceWithoutFragment(feature: "featured", className: "Catalogue")], "\(warnings)")
    }

    // MARK: - Without a metamodel

    @Test("every legacy document loads without a metamodel", arguments: fixtures)
    func untyped(name: String) async throws {
        let (resource, warnings) = try await Self.load(name, in: nil)
        let roots = await Self.roots(resource)
        #expect(!roots.isEmpty)
        #expect(warnings.contains(.untypedClass(name: "Catalogue")))
        if name != "codable-several-roots.json" {
            let sections = try await Self.objects("sections", of: roots[0], in: resource)
            try #require(sections.count == 1)
            let items = try await Self.objects("items", of: sections[0], in: resource)
            #expect(items.count == 2)
        } else {
            #expect(roots.map(\.eClass.name) == ["Catalogue", "Item"])
            #expect(roots[0].eGet("title") as? String == "Summer")
            #expect(roots[0].eGet("sections") as? [String] == [
                "6F1C2B4E-0D0A-4C47-9E6B-2B8E7B5C9A11", "6F1C2B4E-0D0A-4C47-9E6B-2B8E7B5C9A12",
            ])
            #expect(roots[1].eGet("code") as? String == "B1")
            #expect(roots[1].eGet("price") as? Double == 45.25)
            #expect(roots[1].eGet("related") as? [String] == ["6F1C2B4E-0D0A-4C47-9E6B-2B8E7B5C9A13"])
        }
        if name == "codable-single-root.json" {
            #expect(roots[0].eGet("homepage") as? String == "http://www.example.org/catalogue")
            #expect(roots[0].eGet("highlight") as? String == "6F1C2B4E-0D0A-4C47-9E6B-2B8E7B5C9A02")
        }
    }

    // MARK: - Conversion to XMI

    @Test(
        "legacy documents convert to XMI and load back",
        arguments: fixtures, [true, false])
    func convertToXMI(name: String, typed: Bool) async throws {
        let set = typed ? await Self.catalogueSet() : nil
        let (resource, _) = try await Self.load(name, in: set)
        let original = await Self.roots(resource)
        for (index, options) in [XMISerializationOptions.legacy, .emf].enumerated() {
            let xmi = try await XMISerializer(options: options).serialize(resource)
            let reloaded = try await XMIParser(resourceSet: set).parse(xmi, uri: "memory:/\(name).\(index).xmi")
            let roots = await Self.roots(reloaded)
            #expect(roots.count == original.count, "\(xmi)")
            #expect(roots.first?.eGet("title") as? String == original.first?.eGet("title") as? String)
            if name == "codable-single-root.json" {
                let issued = options == .legacy || !typed ? "2026-01-02T03:04:05.123000Z" : "2026-01-02T03:04:05.123+0000"
                #expect(xmi.contains("issued=\"\(issued)\""), "\(xmi)")
            }
            guard name != "codable-several-roots.json", let first = roots.first else { continue }
            let sections = try await Self.objects("sections", of: first, in: reloaded)
            try #require(sections.count == 1, "\(xmi)")
            let items = try await Self.objects("items", of: sections[0], in: reloaded)
            #expect(items.count == 2, "\(xmi)")
            #expect(Set(items.compactMap { $0.eGet("label") as? String }).count == 2, "\(xmi)")
        }
    }
}
