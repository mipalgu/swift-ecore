//
// LegacyTypeQualifierTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for the `xsi:type` of contained objects whose class differs from the declared type,
/// and for references that untyped documents hold.
@Suite("Type qualifiers and untyped references")
struct LegacyTypeQualifierTests {
    /// The URL of the fixture with two package roots.
    static func twoRoots() throws -> URL {
        try ReflectionFixtures.resourcesURL().appendingPathComponent("xmi/classifiers-two-roots.xmi")
    }

    /// Resolves the objects that a feature of an object holds.
    static func objects(_ feature: String, of object: DynamicEObject, in resource: Resource) async throws
        -> [DynamicEObject]
    {
        try await ConversionDiagnosticsTests.objects(feature, of: object, in: resource)
    }

    @Test(
        "the XMI writers qualify contained objects of a subclass",
        arguments: [XMISerializationOptions.legacy, .emf])
    func subclassesAreQualified(options: XMISerializationOptions) async throws {
        let (set, _) = try await WrappedDocumentLoadingTests.makeResourceSet()
        let resource = try await set.loadXMIResource(uri: try Self.twoRoots().absoluteString)
        var diagnostics = ConversionDiagnostics()
        let text = try await XMISerializer(options: options).serialize(resource, diagnostics: &diagnostics)
        #expect(diagnostics.isEmpty, "\(diagnostics.warnings)")
        #expect(text.contains("xsi:type=\"cls:DataType\""), "\(text)")
        #expect(text.contains("xsi:type=\"cls:Class\""), "\(text)")
        #expect(text.contains("xmlns:xsi=\"\(EcoreURI.xsiNamespace.rawValue)\""), "\(text)")
        #expect(!text.contains("<attributes xsi:type"), "\(text)")
        let reloaded = try await XMIParser(resourceSet: set).parse(text, uri: "memory:/qualified-\(options == .legacy).xmi")
        let roots = await reloaded.getRootObjects().compactMap { $0 as? DynamicEObject }
        try #require(roots.count == 2)
        let library = try await Self.objects("classifiers", of: roots[0], in: reloaded)
        let shop = try await Self.objects("classifiers", of: roots[1], in: reloaded)
        #expect(library.map(\.eClass.name) == ["DataType", "Class"], "\(text)")
        #expect(shop.map(\.eClass.name) == ["Class", "DataType"], "\(text)")
        try #require(library.count == 2)
        #expect(library[1].eGet("isAbstract") as? Bool == true, "\(text)")
        let attributes = try await Self.objects("attributes", of: library[1], in: reloaded)
        #expect(attributes.map { $0.eGet("name") as? String } == ["title"], "\(text)")
        #expect(ReferenceValues.identifiers(attributes.first?.eGet("type")) == [library[0].id], "\(text)")
    }

    @Test("a single root with a contained subclass declares the XML Schema instance namespace")
    func singleRootDeclaresXSI() async throws {
        let (set, package) = try await WrappedDocumentLoadingTests.makeResourceSet()
        var root = DynamicEObject(eClass: try #require(package.getEClass("Package")))
        root.eSet("name", value: "solo")
        var dataType = DynamicEObject(eClass: try #require(package.getEClass("DataType")))
        dataType.eSet("name", value: "Text")
        root.eSet("classifiers", value: [dataType.id])
        let resource = await set.createResource(uri: "file:///solo.xmi")
        await resource.register(dataType)
        await resource.add(root)
        let text = try await XMISerializer().serialize(resource)
        #expect(
            text == """
                <?xml version="1.0" encoding="UTF-8"?>
                <cls:Package xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:cls="http://example.org/classifiers" name="solo">
                    <classifiers xsi:type="cls:DataType" name="Text"/>
                </cls:Package>

                """, "\(text)")
    }

    @Test("a contained subclass of no known package is qualified and reported")
    func unknownSubclassIsReported() async throws {
        let base = EClass(name: "Shape", isAbstract: true)
        let circle = EClass(name: "Circle", eSuperTypes: [base])
        let drawing = EClass(
            name: "Drawing", eStructuralFeatures: [EReference(name: "shapes", eType: base, upperBound: -1, containment: true)])
        let resource = Resource(uri: "file:///drawing.xmi")
        var shape = DynamicEObject(eClass: circle)
        shape.eSet("radius", value: 2)
        var root = DynamicEObject(eClass: drawing)
        root.eSet("shapes", value: [shape.id])
        await resource.register(shape)
        await resource.add(root)
        var diagnostics = ConversionDiagnostics()
        let text = try await XMISerializer().serialize(resource, diagnostics: &diagnostics)
        #expect(text.contains("<shapes xsi:type=\"circle:Circle\" radius=\"2\"/>"), "\(text)")
        #expect(text.contains("xmlns:circle=\"\(XMIDocumentSyntax.fallbackNamespaceBase)circle\""), "\(text)")
        #expect(diagnostics.warnings.map(\.kind).contains(.untypedClass(name: "Circle")))
    }

    // MARK: - References of untyped documents

    @Test("an untyped document writes its references to contained objects as fragments")
    func untypedReferencesAsFragments() async throws {
        let original = try await XMIParser().parse(try Self.twoRoots())
        var diagnostics = ConversionDiagnostics()
        let json = try await JSONSerializer().serialize(original, diagnostics: &diagnostics)
        #expect(json.contains("\"$ref\" : \"/0/@classifiers.0\"") || json.contains("\"$ref\": \"/0/@classifiers.0\""), "\(json)")
        #expect(!diagnostics.warnings.map(\.kind).contains { if case .referenceWithoutFragment = $0 { true } else { false } },
            "\(diagnostics.warnings)")
        let fromJSON = try await JSONParser().parse(Data(json.utf8), uri: "memory:/untyped.json")
        for options in [XMISerializationOptions.legacy, .emf] {
            var xmiDiagnostics = ConversionDiagnostics()
            let xmi = try await XMISerializer(options: options).serialize(fromJSON, diagnostics: &xmiDiagnostics)
            #expect(xmi.contains("/0/@classifiers.0\""), "\(xmi)")
            #expect(!xmiDiagnostics.warnings.map(\.kind).contains { if case .referenceWithoutFragment = $0 { true } else { false } })
            let reloaded = try await XMIParser().parse(xmi, uri: "memory:/untyped-again-\(options == .legacy).xmi")
            let roots = await reloaded.getRootObjects().compactMap { $0 as? DynamicEObject }
            try #require(roots.count == 2, "\(xmi)")
            let library = try await Self.objects("classifiers", of: roots[0], in: reloaded)
            try #require(library.count == 2, "\(xmi)")
            let attributes = try await Self.objects("attributes", of: library[1], in: reloaded)
            #expect(ReferenceValues.identifiers(attributes.first?.eGet("type")) == [library[0].id], "\(xmi)")
        }
    }

    @Test("identifiers of objects without a fragment are reported by every writer")
    func identifiersWithoutFragmentAreReported() async throws {
        let resource = Resource(uri: "file:///loose.xmi")
        let string = EcorePackage.dataType(.eString) ?? EDataType(name: "EString")
        let gadget = EClass(name: "Gadget", eStructuralFeatures: [EAttribute(name: "part", eType: string)])
        let orphan = DynamicEObject(eClass: EClass(name: "Part"))
        var object = DynamicEObject(eClass: gadget)
        object.eSet("part", value: orphan.id)
        object.eSet("spare", value: orphan.id)
        await resource.register(orphan)
        await resource.add(object)
        for options in [XMISerializationOptions.legacy, .emf] {
            var diagnostics = ConversionDiagnostics()
            let text = try await XMISerializer(options: options).serialize(resource, diagnostics: &diagnostics)
            let kinds = diagnostics.warnings.map(\.kind)
            #expect(
                !text.contains("\"\(orphan.id.uuidString)\"") || kinds.contains(.referenceWithoutFragment(feature: "part", className: "Gadget")),
                "\(text)")
            #expect(
                kinds.contains(.referenceWithoutFragment(feature: "part", className: "Gadget"))
                    || kinds.contains(.droppedFeature(name: "part", className: "Gadget")), "\(kinds)")
        }
        var diagnostics = ConversionDiagnostics()
        _ = try await JSONSerializer().serialize(resource, diagnostics: &diagnostics)
        let kinds = diagnostics.warnings.map(\.kind)
        #expect(kinds.contains(.referenceWithoutFragment(feature: "part", className: "Gadget")), "\(kinds)")
        #expect(kinds.contains(.referenceWithoutFragment(feature: "spare", className: "Gadget")), "\(kinds)")
    }
}
