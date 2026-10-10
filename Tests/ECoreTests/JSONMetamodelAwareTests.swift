//
// JSONMetamodelAwareTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests that the JSON resource format uses the metamodels registered with a resource set.
@Suite("JSON metamodel awareness")
struct JSONMetamodelAwareTests {
    private static let namespace = "http://example.org/jsonlibrary/1.0"
    private static let metamodelPath = "jsonmeta/JSONLibrary.ecore"
    private static let fragmentsPath = "jsonmeta/library-fragments.json"
    private static let pointersPath = "jsonmeta/library-pointers.json"
    private static let xmiPath = "jsonmeta/library-instance.xmi"

    // MARK: - Helpers

    private static func text(_ path: String) throws -> String {
        try String(
            contentsOf: try ReflectionFixtures.resourcesURL().appendingPathComponent(path),
            encoding: .utf8)
    }

    /// A resource set with the library metamodel registered.
    private static func resourceSetWithMetamodel() async throws -> ResourceSet {
        let resourceSet = ResourceSet()
        _ = try await resourceSet.loadEcoreResource(
            text: try text(metamodelPath), uri: "memory:/jsonlibrary.ecore")
        return resourceSet
    }

    private static func root(of resource: Resource) async throws -> DynamicEObject {
        try #require(await resource.getRootObjects().first as? DynamicEObject)
    }

    private static func objects(
        _ feature: String, of object: DynamicEObject, in resource: Resource
    ) async -> [DynamicEObject] {
        var result: [DynamicEObject] = []
        let value = object.eGet(feature)
        let identifiers = (value as? [EUUID]) ?? (value as? EUUID).map { [$0] } ?? []
        for identifier in identifiers {
            if let child = await resource.resolve(identifier) as? DynamicEObject { result.append(child) }
        }
        return result
    }

    /// The identifiers that a reference value holds, whether it is stored singly or as a list.
    private static func targets(_ value: (any EcoreValue)?) -> [EUUID] {
        (value as? [EUUID]) ?? (value as? EUUID).map { [$0] } ?? []
    }

    private static func jsonObject(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    // MARK: - Parsing

    @Test("the registered class is used for the root object")
    func parserUsesRegisteredClassForRoot() async throws {
        let resourceSet = try await Self.resourceSetWithMetamodel()
        let package = try #require(await resourceSet.getMetamodel(uri: Self.namespace))
        let resource = try await resourceSet.loadJSONResource(
            text: try Self.text(Self.fragmentsPath), uri: "memory:/library.json")
        let root = try await Self.root(of: resource)
        #expect(root.eClass.id == package.getEClass("Library")?.id)
        #expect(root.eGet("name") as? String == "City Library")
    }

    @Test("a bare class name is found in the registered packages")
    func bareClassNameResolves() async throws {
        let resourceSet = try await Self.resourceSetWithMetamodel()
        let package = try #require(await resourceSet.getMetamodel(uri: Self.namespace))
        let resource = try await resourceSet.loadJSONResource(
            text: #"{"eClass": "Author", "name": "Ada"}"#, uri: "memory:/bare.json")
        let root = try await Self.root(of: resource)
        #expect(root.eClass.id == package.getEClass("Author")?.id)
        #expect(root.eGet("name") as? String == "Ada")
    }

    @Test("nested objects take the class of their reference or their own eClass")
    func nestedContainmentUsesTargetClass() async throws {
        let resourceSet = try await Self.resourceSetWithMetamodel()
        let package = try #require(await resourceSet.getMetamodel(uri: Self.namespace))
        let resource = try await resourceSet.loadJSONResource(
            text: try Self.text(Self.fragmentsPath), uri: "memory:/library.json")
        let library = try await Self.root(of: resource)

        let items = await Self.objects("items", of: library, in: resource)
        #expect(items.map(\.eClass.name) == ["Book", "Periodical"])
        #expect(items[0].eClass.id == package.getEClass("Book")?.id)
        #expect(items[0].eGet("title") as? String == "Engines")
        #expect(items[1].eGet("issue") as? Int == 7)

        let authors = await Self.objects("authors", of: library, in: resource)
        #expect(authors.map(\.eClass.name) == ["Author", "Author"])

        let chapters = await Self.objects("chapters", of: items[0], in: resource)
        #expect(chapters.map(\.eClass.name) == ["Chapter", "Chapter"])
        #expect(chapters.map { $0.eGet("heading") as? String } == ["One", "Two"])
        #expect(chapters.map { $0.eGet("number") as? Int } == [1, 2])
    }

    @Test("attributes convert by data type and enumerations hold literal names")
    func enumAttributesDecodeToLiteralNames() async throws {
        let resourceSet = try await Self.resourceSetWithMetamodel()
        let resource = try await resourceSet.loadJSONResource(
            text: try Self.text(Self.fragmentsPath), uri: "memory:/library.json")
        let library = try await Self.root(of: resource)
        let book = try #require(await Self.objects("items", of: library, in: resource).first)
        #expect(book.eGet("genre") as? String == "SCIENCE")
        #expect(book.eGet("pages") as? Int == 320)
        #expect(book.eGet("price") as? Double == 24.5)
        #expect(book.eGet("available") as? Bool == true)
        #expect(book.eGet("tags") as? [String] == ["maths", "history"])
    }

    @Test("an enumeration value may be given by its number")
    func enumerationByNumber() async throws {
        let resourceSet = try await Self.resourceSetWithMetamodel()
        let text = #"{"eClass": "Book", "title": "T", "genre": 1}"#
        let resource = try await resourceSet.loadJSONResource(text: text, uri: "memory:/number.json")
        #expect(try await Self.root(of: resource).eGet("genre") as? String == "MYSTERY")
    }

    @Test("EMF fragment references resolve to objects")
    func crossReferencesResolveByFragment() async throws {
        let resourceSet = try await Self.resourceSetWithMetamodel()
        let resource = try await resourceSet.loadJSONResource(
            text: try Self.text(Self.fragmentsPath), uri: "memory:/library.json")
        try await expectLibraryReferences(in: resource)
    }

    @Test("JSON pointer references resolve to objects")
    func crossReferencesResolveByJSONPointer() async throws {
        let resourceSet = try await Self.resourceSetWithMetamodel()
        let resource = try await resourceSet.loadJSONResource(
            text: try Self.text(Self.pointersPath), uri: "memory:/library.json")
        try await expectLibraryReferences(in: resource)
    }

    private func expectLibraryReferences(in resource: Resource) async throws {
        let library = try await Self.root(of: resource)
        let authors = await Self.objects("authors", of: library, in: resource)
        let book = try #require(await Self.objects("items", of: library, in: resource).first)
        #expect(book.eGet("author") as? EUUID == authors[0].id)
        #expect(book.eGet("coauthors") as? [EUUID] == [authors[1].id])
        #expect(library.eGet("featured") as? EUUID == book.id)
    }

    @Test("a reference to another document becomes a proxy")
    func crossResourceReferenceBecomesProxy() async throws {
        let resourceSet = try await Self.resourceSetWithMetamodel()
        let text = #"{"eClass": "Library", "name": "L", "featured": {"$ref": "other.json#//@items.0"}}"#
        let resource = try await resourceSet.loadJSONResource(text: text, uri: "memory:/docs/lib.json")
        let proxy = try #require(try await Self.root(of: resource).eGet("featured") as? ResourceProxy)
        #expect(proxy.uri == "memory:/docs/other.json")
        #expect(proxy.fragment == "//@items.0")
    }

    @Test("an unknown class is an error when a metamodel is required")
    func unknownClassThrowsWhenRequired() async throws {
        let resourceSet = try await Self.resourceSetWithMetamodel()
        let data = Data(#"{"eClass": "http://example.org/none#//Thing", "name": "x"}"#.utf8)
        let strict = JSONParser(
            resourceSet: resourceSet, options: JSONParseOptions(requiresMetamodel: true))
        await #expect(throws: JSONError.self) {
            _ = try await strict.parse(data, uri: "memory:/strict.json")
        }
        let withoutSet = JSONParser(options: JSONParseOptions(requiresMetamodel: true))
        await #expect(throws: JSONError.self) {
            _ = try await withoutSet.parse(data, uri: "memory:/strict2.json")
        }
        let lenient = JSONParser(resourceSet: resourceSet)
        let resource = try await lenient.parse(data, uri: "memory:/lenient.json")
        #expect(try await Self.root(of: resource).eClass.name == "Thing")
    }

    @Test("without a metamodel the class is fabricated from the document")
    func fallbackFabricatesWithoutMetamodel() async throws {
        let resource = try await ResourceSet().loadJSONResource(
            text: try Self.text(Self.fragmentsPath), uri: "memory:/library.json")
        let root = try await Self.root(of: resource)
        #expect(root.eClass.name == "Library")
        #expect(root.eGet("name") as? String == "City Library")
        let parsed = try await JSONParser().parse(
            Data(try Self.text(Self.fragmentsPath).utf8), uri: "memory:/plain.json")
        #expect(try await Self.root(of: parsed).eClass.name == "Library")
    }

    // MARK: - Serialising

    @Test("the serialiser writes package-qualified classes and reference objects")
    func serializerWritesPackageQualifiedEClassAndRefs() async throws {
        let resourceSet = try await Self.resourceSetWithMetamodel()
        let resource = try await resourceSet.loadJSONResource(
            text: try Self.text(Self.fragmentsPath), uri: "memory:/library.json")
        let text = try await JSONSerializer().serialize(resource)
        let json = try Self.jsonObject(text)

        #expect(json["eClass"] as? String == "\(Self.namespace)#//Library")
        #expect(json["featured"] as? [String: String] == ["$ref": "//@items.0"])
        let items = try #require(json["items"] as? [[String: Any]])
        #expect(items.map { $0["eClass"] as? String } == [
            "\(Self.namespace)#//Book", "\(Self.namespace)#//Periodical",
        ])
        #expect(items[0]["author"] as? [String: String] == ["$ref": "//@authors.0"])
        #expect(items[0]["coauthors"] as? [[String: String]] == [["$ref": "//@authors.1"]])
        #expect(items[0]["genre"] as? String == "SCIENCE")
        let chapters = try #require(items[0]["chapters"] as? [[String: Any]])
        #expect(chapters.first?["eClass"] as? String == "\(Self.namespace)#//Chapter")

        let authorsIndex = try #require(text.range(of: "\"authors\""))
        let eClassIndex = try #require(text.range(of: "\"eClass\""))
        let featuredIndex = try #require(text.range(of: "\"featured\""))
        #expect(authorsIndex.lowerBound < eClassIndex.lowerBound)
        #expect(eClassIndex.lowerBound < featuredIndex.lowerBound)
    }

    @Test("a proxy is written as a document reference")
    func serializerWritesProxyReferences() async throws {
        let resourceSet = try await Self.resourceSetWithMetamodel()
        let text = #"{"eClass": "Library", "name": "L", "featured": {"$ref": "other.json#//@items.0"}}"#
        let resource = try await resourceSet.loadJSONResource(text: text, uri: "memory:/docs/lib.json")
        let json = try Self.jsonObject(try await JSONSerializer().serialize(resource))
        #expect(json["featured"] as? [String: String] == ["$ref": "other.json#//@items.0"])
    }

    @Test("several root objects are written as an array with root-indexed references")
    func multipleRootsRoundTrip() async throws {
        let resourceSet = try await Self.resourceSetWithMetamodel()
        let text = """
            [{"eClass": "Author", "name": "Ada"},
             {"eClass": "Book", "title": "T", "author": {"$ref": "/0"}}]
            """
        let resource = try await resourceSet.loadJSONResource(text: text, uri: "memory:/multi.json")
        let roots = await resource.getRootObjects()
        #expect(roots.count == 2)
        #expect((roots[1] as? DynamicEObject)?.eGet("author") as? EUUID == roots[0].id)

        let output = try await JSONSerializer().serialize(resource)
        let reloaded = try await resourceSet.loadJSONResource(text: output, uri: "memory:/multi2.json")
        let again = await reloaded.getRootObjects()
        #expect(again.count == 2)
        #expect((again[1] as? DynamicEObject)?.eGet("author") as? EUUID == again[0].id)
    }

    @Test("XMI to JSON to XMI keeps values and reference targets")
    func xmiToJSONToXMIRoundTripPreservesValues() async throws {
        let resourceSet = try await Self.resourceSetWithMetamodel()
        let xmi = try await resourceSet.loadXMIResource(
            text: try Self.text(Self.xmiPath), uri: "memory:/library.xmi")
        let json = try await JSONSerializer().serialize(xmi)
        let reloaded = try await resourceSet.loadJSONResource(text: json, uri: "memory:/library.json")
        let again = try await JSONSerializer().serialize(reloaded)
        #expect(again == json)

        let xmiText = try await XMISerializer().serialize(reloaded)
        let final = try await resourceSet.loadXMIResource(text: xmiText, uri: "memory:/library2.xmi")

        for resource in [reloaded, final] {
            let library = try await Self.root(of: resource)
            #expect(library.eGet("name") as? String == "City Library")
            let authors = await Self.objects("authors", of: library, in: resource)
            #expect(authors.map { $0.eGet("name") as? String } == ["Ada", "Brian"])
            let items = await Self.objects("items", of: library, in: resource)
            let book = try #require(items.first)
            #expect(book.eGet("title") as? String == "Engines")
            #expect(book.eGet("pages") as? Int == 320)
            #expect(book.eGet("price") as? Double == 24.5)
            #expect(book.eGet("available") as? Bool == true)
            #expect(book.eGet("genre") as? String == "SCIENCE")
            #expect(book.eGet("author") as? EUUID == authors[0].id)
            #expect(Self.targets(book.eGet("coauthors")) == [authors[1].id])
            #expect(library.eGet("featured") as? EUUID == book.id)
            #expect(items[1].eGet("issue") as? Int == 7)
            let chapters = await Self.objects("chapters", of: book, in: resource)
            #expect(chapters.map { $0.eGet("heading") as? String } == ["One", "Two"])
        }
    }
}
