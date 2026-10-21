//
// JSONSynthesisTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for the classes that the JSON parser synthesises for documents without a metamodel,
/// and for how the builder reads references.
@Suite("JSON class synthesis")
struct JSONSynthesisTests {
    /// Parses a JSON text without a metamodel.
    ///
    /// - Parameter text: The JSON document.
    /// - Returns: The resource, its roots, and the parser's warnings.
    static func parse(_ text: String, uri: String = "memory:/synthesis.json") async throws
        -> (resource: Resource, roots: [DynamicEObject], warnings: [ConversionWarning.Kind])
    {
        let parser = JSONParser()
        let resource = try await parser.parse(Data(text.utf8), uri: uri)
        let roots = await resource.getRootObjects().compactMap { $0 as? DynamicEObject }
        return (resource, roots, await parser.diagnostics.warnings.map(\.kind))
    }

    /// Resolves the objects that a feature of an object holds.
    static func objects(_ feature: String, of object: DynamicEObject, in resource: Resource) async throws
        -> [DynamicEObject]
    {
        try await ConversionDiagnosticsTests.objects(feature, of: object, in: resource)
    }

    @Test("a key that holds only UUID text stays a string attribute")
    func uuidValuedAttributes() async throws {
        let guid = "6F1C2B4E-0D0A-4C47-9E6B-2B8E7B5C9A31"
        let (_, roots, warnings) = try await Self.parse(
            #"{"eClass": "Device", "guid": "\#(guid)", "aliases": ["\#(guid)"]}"#)
        let device = try #require(roots.first)
        #expect(device.eGet("guid") as? String == guid)
        #expect(device.eGet("aliases") as? [String] == [guid])
        #expect(device.eClass.getStructuralFeature(name: "guid") is EAttribute)
        #expect(warnings == [.untypedClass(name: "Device")])
        let json = try await JSONSerializer().serialize(try await Self.parse(
            #"{"eClass": "Device", "guid": "\#(guid)"}"#).resource)
        #expect(!json.contains(JSONSyntax.referenceKey), "\(json)")
    }

    @Test("a class nested in itself keeps the keys of every level")
    func sameClassRecursion() async throws {
        let text = """
            {"eClass": "Folder", "name": "root", "items": [
              {"eClass": "Folder", "name": "inner", "items": [
                {"eClass": "Folder", "name": "leaf", "size": 3, "tags": ["a"]}]}]}
            """
        let (resource, roots, _) = try await Self.parse(text)
        let root = try #require(roots.first)
        let names = Set(root.eClass.eStructuralFeatures.map(\.name))
        #expect(names == ["items", "name", "size", "tags"])
        #expect((root.eClass.getStructuralFeature(name: "items") as? EReference)?.containment == true)
        #expect((root.eClass.getStructuralFeature(name: "items") as? EReference)?.eType.name == "Folder")
        let inner = try await Self.objects("items", of: root, in: resource)
        let leaf = try await Self.objects("items", of: try #require(inner.first), in: resource)
        #expect(leaf.first?.eGet("size") as? Int == 3)
        #expect(leaf.first?.eGet("tags") as? [String] == ["a"])
    }

    @Test("empty arrays, mixed arrays, and untyped siblings are read")
    func edgeCases() async throws {
        let text = """
            {"eClass": "Box", "empty": [], "mixed": [{"eClass": "Part", "n": 1}, 2, "three"],
             "parts": [{"eClass": "Part", "n": 4}, {"n": 5}],
             "loose": [{"eClass": "Part", "n": 6}, {"eClass": "Gear", "teeth": 7}, {"n": 8}]}
            """
        let (resource, roots, warnings) = try await Self.parse(text)
        let box = try #require(roots.first)
        #expect(box.eClass.getStructuralFeature(name: "empty") == nil)
        let mixed = try await Self.objects("mixed", of: box, in: resource)
        #expect(mixed.map(\.eClass.name) == ["Part"])
        let parts = try await Self.objects("parts", of: box, in: resource)
        #expect(parts.map(\.eClass.name) == ["Part", "Part"])
        #expect(parts.map { $0.eGet("n") as? Int } == [4, 5])
        let loose = try await Self.objects("loose", of: box, in: resource)
        #expect(loose.map(\.eClass.name) == ["Part", "Gear", XMIDocumentSyntax.untypedClassName])
        #expect(loose.last?.eGet("n") as? Int == 8)
        #expect(warnings.contains(.untypedClass(name: XMIDocumentSyntax.untypedClassName)))
        #expect(!FragmentNavigator.isEcoreMetaclass(XMIDocumentSyntax.untypedClassName))
        let xmi = try await XMISerializer(options: .emf).serialize(resource)
        #expect(!xmi.contains("ecore:"), "\(xmi)")
    }

    @Test("references are bare identifiers only without a fragment, URI, or path")
    func identifierReferences() {
        #expect(JSONModelBuilder.isIdentifierReference("A1"))
        #expect(JSONModelBuilder.isIdentifierReference("6F1C2B4E-0D0A-4C47-9E6B-2B8E7B5C9A31"))
        #expect(!JSONModelBuilder.isIdentifierReference(""))
        #expect(!JSONModelBuilder.isIdentifierReference("other.json#//@items.0"))
        #expect(!JSONModelBuilder.isIdentifierReference("//@items.0"))
        #expect(!JSONModelBuilder.isIdentifierReference("http://www.example.org/a"))
        #expect(!JSONModelBuilder.isIdentifierReference("../other.json"))
    }

    @Test("a $ref to another document without a fragment stays a reference to that document")
    func referenceToOtherDocument() async throws {
        let set = ResourceSet()
        let package = ConversionDiagnosticsTests.shelfPackage()
        await set.registerMetamodel(package, uri: package.nsURI)
        let text = #"{"eClass": "\#(ConversionDiagnosticsTests.shelfURI)#//Shelf", "favourite": {"$ref": "other.json"}}"#
        let parser = JSONParser(resourceSet: set)
        let resource = try await parser.parse(Data(text.utf8), uri: "memory:/dir/shelf.json")
        let shelf = try #require(await resource.getRootObjects().first as? DynamicEObject)
        let proxy = try #require(shelf.eGet("favourite") as? ResourceProxy)
        #expect(proxy.uri == "memory:/dir/other.json")
        let warnings = await parser.diagnostics.warnings
        #expect(warnings.isEmpty, "\(warnings)")
    }

    @Test("a large untyped document is read in reasonable time")
    func largeDocument() async throws {
        let items = (0..<5000).map { #"{"eClass": "Entry", "index": \#($0), "label": "entry \#($0)"}"# }
        let text = #"{"eClass": "Log", "entries": [\#(items.joined(separator: ","))]}"#
        let clock = ContinuousClock()
        let start = clock.now
        let (resource, roots, _) = try await Self.parse(text)
        let elapsed = clock.now - start
        #expect(await resource.getAllObjects().count == 5001)
        #expect(ReferenceValues.identifiers(roots.first?.eGet("entries")).count == 5000)
        #expect(elapsed < .seconds(20), "\(elapsed)")
    }
}
