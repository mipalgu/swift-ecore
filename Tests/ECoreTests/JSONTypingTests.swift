//
// JSONTypingTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for the classes of nested JSON objects, the container side of containments in
/// JSON output, and the descriptions of JSON errors.
@Suite("JSON typing and errors")
struct JSONTypingTests {
    /// The namespace URI of the classifier metamodel.
    static let classifiersURI = "http://example.org/classifiers"

    /// The URL of an XMI fixture.
    static func fixture(_ name: String) throws -> URL {
        try ReflectionFixtures.resourcesURL().appendingPathComponent("xmi").appendingPathComponent(name)
    }

    /// Resolves the objects that a feature of an object holds.
    static func objects(_ feature: String, of object: DynamicEObject, in resource: Resource) async throws
        -> [DynamicEObject]
    {
        try await ConversionDiagnosticsTests.objects(feature, of: object, in: resource)
    }

    @Test("an XMI document of a registered metamodel keeps its classes through JSON")
    func typedXMIJSONXMIRoundTrip() async throws {
        let (set, _) = try await WrappedDocumentLoadingTests.makeResourceSet()
        let original = try await set.loadXMIResource(uri: try Self.fixture("classifiers-two-roots.xmi").absoluteString)
        let json = try await JSONSerializer().serialize(original)
        let fromJSON = try await JSONParser(resourceSet: set).parse(Data(json.utf8), uri: "memory:/classifiers.json")
        let xmi = try await XMISerializer(options: .emf).serialize(fromJSON)
        #expect(xmi.contains("<classifiers xsi:type=\"cls:DataType\" name=\"String\"/>"), "\(xmi)")
        #expect(xmi.contains("<classifiers xsi:type=\"cls:Class\" name=\"Book\" isAbstract=\"true\">"), "\(xmi)")
        #expect(xmi.contains("<classifiers xsi:type=\"cls:Class\" name=\"Order\"/>"), "\(xmi)")
        #expect(xmi.contains("<classifiers xsi:type=\"cls:DataType\" name=\"Money\"/>"), "\(xmi)")
        let reloaded = try await XMIParser(resourceSet: set).parse(xmi, uri: "memory:/classifiers-again.xmi")
        let roots = await reloaded.getRootObjects().compactMap { $0 as? DynamicEObject }
        try #require(roots.count == 2)
        let library = try await Self.objects("classifiers", of: roots[0], in: reloaded)
        let shop = try await Self.objects("classifiers", of: roots[1], in: reloaded)
        #expect(library.map(\.eClass.name) == ["DataType", "Class"])
        #expect(shop.map(\.eClass.name) == ["Class", "DataType"])
        try #require(library.count == 2)
        let attributes = try await Self.objects("attributes", of: library[1], in: reloaded)
        #expect(attributes.map { $0.eGet("name") as? String } == ["title"])
        let type = try #require(attributes.first?.eGet("type") as? EUUID)
        #expect(type == library[0].id)
    }

    @Test("a nested object takes the class that its own eClass names")
    func nestedObjectsTakeTheirOwnClass() async throws {
        let (set, _) = try await WrappedDocumentLoadingTests.makeResourceSet()
        let text = """
            {"eClass": "\(Self.classifiersURI)#//Package", "name": "p",
             "classifiers": [
               {"eClass": "\(Self.classifiersURI)#//Class", "name": "A", "isAbstract": true},
               {"eClass": "DataType", "name": "B"},
               {"eClass": "Class", "name": "C", "rank": 3}]}
            """
        let resource = try await JSONParser(resourceSet: set).parse(Data(text.utf8), uri: "memory:/nested.json")
        let root = try #require(await resource.getRootObjects().first as? DynamicEObject)
        let classifiers = try await Self.objects("classifiers", of: root, in: resource)
        #expect(classifiers.map(\.eClass.name) == ["Class", "DataType", "Class"])
        try #require(classifiers.count == 3)
        #expect(classifiers[0].eGet("isAbstract") as? Bool == true)
        #expect(classifiers[2].eGet("rank") as? Int == 3)
    }

    @Test("the JSON writer leaves out the container side of containments")
    func containerSideOmitted() async throws {
        let (set, _) = try await WrappedDocumentLoadingTests.makeResourceSet()
        let resource = try await set.loadXMIResource(uri: try Self.fixture("classifiers-two-roots.xmi").absoluteString)
        let json = try await JSONSerializer().serialize(resource)
        #expect(!json.contains("\"package\""), "\(json)")
        #expect(!json.contains("\"owner\""), "\(json)")
        #expect(json.contains("\"classifiers\""), "\(json)")
        let fromJSON = try await JSONParser(resourceSet: set).parse(Data(json.utf8), uri: "memory:/container.json")
        let again = try await JSONSerializer().serialize(fromJSON)
        #expect(!again.contains("\"package\""), "\(again)")
        #expect(!again.contains("\"owner\""), "\(again)")
        #expect(again.contains("\"attributes\""), "\(again)")
    }

    @Test("a nested object's simple class name is looked up below the reference type first")
    func simpleNameWithinReferenceType() async throws {
        let (set, _) = try await WrappedDocumentLoadingTests.makeResourceSet()
        let other = EPackage(
            name: "aardvark", nsURI: "http://example.org/aardvark", nsPrefix: "aardvark",
            eClassifiers: [EClass(name: "Class"), EClass(name: "DataType")])
        await set.registerMetamodel(other, uri: other.nsURI)
        let text = """
            {"eClass": "\(Self.classifiersURI)#//Package", "name": "p",
             "classifiers": [{"eClass": "Class", "name": "C", "rank": 3}, {"eClass": "DataType", "name": "D"}]}
            """
        let resource = try await JSONParser(resourceSet: set).parse(Data(text.utf8), uri: "memory:/simple.json")
        let root = try #require(await resource.getRootObjects().first as? DynamicEObject)
        let classifiers = try await Self.objects("classifiers", of: root, in: resource)
        try #require(classifiers.count == 2)
        let package = try #require(await set.getMetamodel(uri: Self.classifiersURI))
        #expect(classifiers[0].eClass.id == package.getEClass("Class")?.id)
        #expect(classifiers[1].eClass.id == package.getEClass("DataType")?.id)
        #expect(classifiers[0].eGet("rank") as? Int == 3)
    }

    @Test("JSON errors describe what went wrong")
    func errorDescriptions() async throws {
        let parser = JSONParser(resourceSet: ResourceSet(), options: JSONParseOptions(requiresMetamodel: true))
        do {
            _ = try await parser.parse(Data(#"{"eClass": "http://www.example.org/gadgets#//Gadget"}"#.utf8), uri: "memory:/g.json")
            Issue.record("parsing without a metamodel succeeded")
        } catch let error as JSONError {
            #expect(error.description.contains("Gadget"), "\(error)")
            #expect(error.errorDescription == error.description)
            #expect(error.localizedDescription.contains("Gadget"), "\(error.localizedDescription)")
        }
        let errors: [JSONError] = [
            .invalidFormat("not an object"), .missingEClass, .parseError("bad value"),
            .unresolvedMetamodel("No registered metamodel defines the class Gadget"),
        ]
        let descriptions = errors.map(\.description)
        #expect(Set(descriptions).count == errors.count)
        #expect(descriptions[0].contains("not an object"))
        #expect(descriptions[1].contains(JSONSyntax.eClassKey))
        #expect(descriptions[2].contains("bad value"))
        #expect(!descriptions.contains { $0.contains("JSONError") })
    }
}
