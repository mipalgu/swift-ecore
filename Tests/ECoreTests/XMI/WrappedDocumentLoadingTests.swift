//
// WrappedDocumentLoadingTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests that instance documents load the same whether or not their roots are wrapped.
///
/// Eclipse EMF writes an `xmi:XMI` wrapper around the root objects of a resource with
/// several roots. The objects inside the wrapper carry namespace-prefixed element names
/// and `xsi:type` qualifiers whose prefixes are declared on the wrapper, on the element
/// itself, or on any element in between. These tests load each layout against the same
/// metamodel and check the classes and feature values of the loaded objects.
@Suite("Loading wrapped XMI documents")
struct WrappedDocumentLoadingTests {

    /// The documents that hold the same single package in different layouts.
    static let singlePackageDocuments = [
        "classifiers-unwrapped.xmi",
        "classifiers-wrapped.xmi",
        "classifiers-wrapped-scoped.xmi",
        "classifiers-wrapped-default.xmi",
    ]

    /// Locates a document of the XMI test fixtures.
    ///
    /// - Parameter name: The file name of the fixture.
    /// - Returns: The file URL of the fixture.
    private static func fixtureURL(_ name: String) throws -> URL {
        let base = try #require(Bundle.module.resourceURL)
        var url = base.appendingPathComponent("Resources")
        if !FileManager.default.fileExists(atPath: url.path) { url = base }
        return url.appendingPathComponent("xmi").appendingPathComponent(name)
    }

    /// Creates a resource set with the classifier metamodel registered.
    ///
    /// - Returns: The resource set and the registered metamodel package.
    static func makeResourceSet() async throws -> (set: ResourceSet, package: EPackage) {
        let set = ResourceSet()
        let metamodel = try await set.loadEcoreResource(uri: try fixtureURL("classifiers.ecore").absoluteString)
        let package = try #require(await metamodel.getRootObjects().first as? EPackage)
        await set.registerMetamodel(package, uri: package.nsURI)
        return (set, package)
    }

    /// Loads an instance document of the classifier metamodel.
    ///
    /// - Parameters:
    ///   - name: The file name of the fixture.
    ///   - set: The resource set with the registered metamodel.
    /// - Returns: The loaded resource.
    static func load(_ name: String, in set: ResourceSet) async throws -> Resource {
        try await set.loadXMIResource(uri: try fixtureURL(name).absoluteString)
    }

    /// Resolves the objects held by a reference or containment feature.
    ///
    /// - Parameters:
    ///   - feature: The name of the feature.
    ///   - object: The object that holds the feature.
    ///   - resource: The resource that contains the referenced objects.
    /// - Returns: The referenced objects in feature order.
    static func objects(
        _ feature: String, of object: DynamicEObject, in resource: Resource
    ) async throws -> [DynamicEObject] {
        var result: [DynamicEObject] = []
        for id in ReferenceValues.identifiers(object.eGet(feature)) {
            result.append(try #require(await resource.resolve(id) as? DynamicEObject))
        }
        return result
    }

    @Test("every layout yields the classes of the metamodel", arguments: singlePackageDocuments)
    func classesFromMetamodel(document: String) async throws {
        let (set, package) = try await Self.makeResourceSet()
        let resource = try await Self.load(document, in: set)
        let roots = await resource.getRootObjects()
        #expect(roots.count == 1)
        let root = try #require(roots.first as? DynamicEObject)
        #expect(root.eClass.name == "Package")
        #expect(root.eGet("name") as? String == "library")

        let classifiers = try await Self.objects("classifiers", of: root, in: resource)
        #expect(classifiers.map(\.eClass.name) == ["DataType", "DataType", "Class", "Class"])
        #expect(classifiers.compactMap { $0.eGet("name") as? String } == ["Integer", "String", "Author", "Book"])
        let classClass = try #require(package.getEClass("Class"))
        #expect(classifiers[3].eClass.id == classClass.id)
        #expect(classifiers[3].eClass.getStructuralFeature(name: "isAbstract") != nil)
    }

    @Test("every layout converts attribute values to their declared types", arguments: singlePackageDocuments)
    func typedAttributeValues(document: String) async throws {
        let (set, _) = try await Self.makeResourceSet()
        let resource = try await Self.load(document, in: set)
        let root = try #require(await resource.getRootObjects().first as? DynamicEObject)
        let classifiers = try await Self.objects("classifiers", of: root, in: resource)
        try #require(classifiers.count == 4)
        let book = classifiers[3]
        #expect(book.eGet("isAbstract") as? Bool == true)
        #expect(book.eGet("rank") as? Int == 3)
        #expect(!classifiers[2].eIsSet("isAbstract"))

        let attributes = try await Self.objects("attributes", of: book, in: resource)
        #expect(attributes.map(\.eClass.name) == ["Attribute", "Attribute", "Attribute"])
        #expect(attributes.compactMap { $0.eGet("name") as? String } == ["title", "pages", "authors"])
        #expect(attributes[2].eGet("multiValued") as? Bool == true)
        #expect(!attributes[0].eIsSet("multiValued"))
    }

    @Test("every layout resolves positional references within the root", arguments: singlePackageDocuments)
    func positionalReferences(document: String) async throws {
        let (set, _) = try await Self.makeResourceSet()
        let resource = try await Self.load(document, in: set)
        let root = try #require(await resource.getRootObjects().first as? DynamicEObject)
        let classifiers = try await Self.objects("classifiers", of: root, in: resource)
        try #require(classifiers.count == 4)
        let attributes = try await Self.objects("attributes", of: classifiers[3], in: resource)
        try #require(attributes.count == 3)
        #expect(ReferenceValues.identifiers(attributes[0].eGet("type")) == [classifiers[1].id])
        #expect(ReferenceValues.identifiers(attributes[1].eGet("type")) == [classifiers[0].id])
        #expect(ReferenceValues.identifiers(attributes[2].eGet("type")) == [classifiers[2].id])
        #expect(ReferenceValues.identifiers(attributes[0].eGet("owner")) == [classifiers[3].id])
        #expect(ReferenceValues.identifiers(classifiers[0].eGet("package")) == [root.id])
    }

    @Test("namespace declarations do not become feature values", arguments: singlePackageDocuments)
    func declarationsAreNotFeatures(document: String) async throws {
        let (set, _) = try await Self.makeResourceSet()
        let resource = try await Self.load(document, in: set)
        let root = try #require(await resource.getRootObjects().first as? DynamicEObject)
        let classifiers = try await Self.objects("classifiers", of: root, in: resource)
        for object in [root] + classifiers {
            let names = object.getFeatureNames()
            #expect(!names.contains { $0.hasPrefix(XMLNamespace.xmlns) }, "\(names)")
            #expect(!names.contains { $0.hasPrefix(CrossReferenceSyntax.xsiPrefix) }, "\(names)")
        }
    }

    @Test("the ATL layer sees every class instance of a wrapped document")
    func allInstancesInWrappedDocument() async throws {
        let (set, package) = try await Self.makeResourceSet()
        let resource = try await Self.load("classifiers-wrapped.xmi", in: set)
        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(resource, alias: "IN")
        let classClass = try #require(package.getEClass("Class"))
        let instances = await engine.allInstancesOf(classClass)
        #expect(instances.count == 2)
        let dataTypes = await engine.allInstancesOf(try #require(package.getEClass("DataType")))
        #expect(dataTypes.count == 2)
    }

    @Test("several wrapped roots keep their classes and contents")
    func severalRoots() async throws {
        let (set, _) = try await Self.makeResourceSet()
        let resource = try await Self.load("classifiers-two-roots.xmi", in: set)
        let roots = await resource.getRootObjects().compactMap { $0 as? DynamicEObject }
        #expect(roots.map(\.eClass.name) == ["Package", "Package"])
        #expect(roots.compactMap { $0.eGet("name") as? String } == ["library", "shop"])
        try #require(roots.count == 2)
        let library = try await Self.objects("classifiers", of: roots[0], in: resource)
        let shop = try await Self.objects("classifiers", of: roots[1], in: resource)
        #expect(library.map(\.eClass.name) == ["DataType", "Class"])
        #expect(shop.map(\.eClass.name) == ["Class", "DataType"])
        try #require(library.count == 2)
        let title = try await Self.objects("attributes", of: library[1], in: resource)
        #expect(title.map(\.eClass.name) == ["Attribute"])
        #expect(ReferenceValues.identifiers(title.first?.eGet("type")) == [library[0].id])
    }

    @Test("saving several roots writes the wrapper", arguments: [XMISerializationOptions.legacy, .emf])
    func severalRootsWriteWrapper(options: XMISerializationOptions) async throws {
        let (set, _) = try await Self.makeResourceSet()
        let resource = try await Self.load("classifiers-two-roots.xmi", in: set)
        let text = try await XMISerializer(options: options).serialize(resource)
        let wrapper = CrossReferenceSyntax.xmiPrefix + ":" + XMIDocumentSyntax.multipleRootElement
        #expect(text.contains("<" + wrapper))
        #expect(text.contains("</" + wrapper + ">"))
    }

    @Test("an EMF-style save of several roots reloads with the same classes")
    func severalRootsRoundTrip() async throws {
        let (set, _) = try await Self.makeResourceSet()
        let resource = try await Self.load("classifiers-two-roots.xmi", in: set)
        let text = try await XMISerializer(options: .emf).serialize(resource)
        #expect(text.contains("xsi:type=\"cls:Class\""))

        let reloaded = try await XMIParser(resourceSet: set).parse(text, uri: "memory:/reloaded.xmi")
        let roots = await reloaded.getRootObjects().compactMap { $0 as? DynamicEObject }
        #expect(roots.map(\.eClass.name) == ["Package", "Package"])
        #expect(roots.compactMap { $0.eGet("name") as? String } == ["library", "shop"])
        try #require(roots.count == 2)
        let library = try await Self.objects("classifiers", of: roots[0], in: reloaded)
        let shop = try await Self.objects("classifiers", of: roots[1], in: reloaded)
        #expect(library.first?.eClass.name == "DataType")
        #expect(library.dropFirst().first?.eGet("isAbstract") as? Bool == true)
        #expect(library.map(\.eClass.name) == ["DataType", "Class"])
        #expect(shop.map(\.eClass.name) == ["Class", "DataType"])
    }

    @Test("saving a single root writes no wrapper")
    func singleRootHasNoWrapper() async throws {
        let (set, _) = try await Self.makeResourceSet()
        let resource = try await Self.load("classifiers-wrapped.xmi", in: set)
        let text = try await XMISerializer(options: .emf).serialize(resource)
        let wrapper = CrossReferenceSyntax.xmiPrefix + ":" + XMIDocumentSyntax.multipleRootElement
        #expect(!text.contains("<" + wrapper))
        #expect(text.contains("xsi:type=\"cls:Class\""))
        #expect(!text.contains("isAbstract=\"false\""))
    }
}
