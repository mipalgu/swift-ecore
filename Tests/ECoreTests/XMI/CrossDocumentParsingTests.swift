//
// CrossDocumentParsingTests.swift
// ECoreTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for parsing and resolving references that point into other documents.
@Suite("Cross-Document Reference Parsing")
struct CrossDocumentParsingTests {

    // MARK: - Reference syntax

    @Test("Parses unqualified and qualified references")
    func parsesQualifiedReferences() {
        let references = CrossReference.parseList(
            "ecore:EAttribute library.ecore#//Book/title ../x/Other.genmodel#//ecore #//Local")
        #expect(references.count == 3)
        #expect(references[0] == CrossReference(qualifier: "ecore:EAttribute", uri: "library.ecore", fragment: "//Book/title"))
        #expect(references[1] == CrossReference(uri: "../x/Other.genmodel", fragment: "//ecore"))
        #expect(references[2] == CrossReference(uri: "", fragment: "//Local"))
        #expect(references[0].href == "library.ecore#//Book/title")
    }

    @Test("Parses positional paths and identifiers")
    func parsesPositionalReferences() {
        let references = CrossReference.parseList("//@entries.1 \n\t//@entries.0/@x identifier")
        #expect(references.map(\.fragment) == ["//@entries.1", "//@entries.0/@x", "identifier"])
        #expect(references.allSatisfy { $0.uri.isEmpty })
        #expect(CrossReference.parseList("   ").isEmpty)
    }

    // MARK: - URI handling

    @Test("Resolves relative URIs against the referring resource")
    func resolvesRelativeURIs() {
        let base = "file:///models/a/b/doc.xmi"
        #expect(URIReference.resolve("library.ecore", against: base) == "file:///models/a/b/library.ecore")
        #expect(URIReference.resolve("../../ecore/Ecore.genmodel", against: base) == "file:///models/ecore/Ecore.genmodel")
        #expect(URIReference.resolve("./x/../y.ecore", against: base) == "file:///models/a/b/y.ecore")
        #expect(URIReference.resolve("/abs/z.ecore", against: base) == "file:///abs/z.ecore")
        #expect(URIReference.resolve("http://www.eclipse.org/emf/2002/Ecore", against: base) == "http://www.eclipse.org/emf/2002/Ecore")
        #expect(URIReference.resolve("", against: base) == base)
        #expect(URIReference.resolve("../../../../../up.ecore", against: base) == "file:///up.ecore")
    }

    @Test("Relativises URIs between resources")
    func relativisesURIs() {
        let base = "file:///models/a/b/doc.xmi"
        #expect(URIReference.relativise("file:///models/a/b/library.ecore", against: base) == "library.ecore")
        #expect(URIReference.relativise("file:///models/ecore/Ecore.genmodel", against: base) == "../../ecore/Ecore.genmodel")
        #expect(URIReference.relativise("file:///models/a/b/sub/x.ecore", against: base) == "sub/x.ecore")
        #expect(URIReference.relativise("file:///other/x.ecore", against: base) == "../../../other/x.ecore")
        #expect(URIReference.relativise("http://host/x.ecore", against: base) == "http://host/x.ecore")
        #expect(URIReference.relativise("file://host/x.ecore", against: base) == "file://host/x.ecore")
        #expect(URIReference.relativise("resource://abc", against: base) == "resource://abc")
        #expect(URIReference.relativise("urn:x", against: "urn:y") == "urn:x")
    }

    @Test("Splits references at the fragment separator")
    func splitsReferences() {
        #expect(URIReference.split("a.ecore#//B").uri == "a.ecore")
        #expect(URIReference.split("a.ecore#//B").fragment == "//B")
        #expect(URIReference.split("a.ecore").fragment == nil)
        #expect(URIReference.split("#x").uri.isEmpty)
    }

    // MARK: - Instance parsing

    @Test("Attribute references to other documents become proxies")
    func parsesAttributeReferences() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadMapping()

        let roots = await resource.getRootObjects()
        let root = try #require(roots.first as? DynamicEObject)
        #expect(root.eClass.name == "Mapping")

        let library = fixtures.uri("library.ecore")
        let package = try #require(await resource.eGet(objectId: root.id, feature: "ecorePackage") as? ResourceProxy)
        #expect(package == ResourceProxy(uri: library, fragment: "/"))

        let used = try #require(await resource.eGet(objectId: root.id, feature: "usedPackages") as? [ResourceProxy])
        #expect(used == [
            ResourceProxy(uri: library, fragment: "//archive"),
            ResourceProxy(uri: fixtures.directory.appendingPathComponent("other/Other.ecore").absoluteString, fragment: "/"),
        ])
    }

    @Test("Type qualifiers are accepted and many-valued references keep their order")
    func parsesQualifiedAttributeReferences() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadMapping()
        let entries = await fixtures.objects(of: "Entry", in: resource)
        #expect(entries.count == 2)
        let first = try #require(entries.first { $0.eGet("label") as? String == "book" })

        let library = fixtures.uri("library.ecore")
        #expect(await resource.eGet(objectId: first.id, feature: "ecoreClass") as? ResourceProxy
            == ResourceProxy(uri: library, fragment: "//Book"))
        #expect(await resource.eGet(objectId: first.id, feature: "ecoreFeature") as? ResourceProxy
            == ResourceProxy(uri: library, fragment: "//Book/title"))
    }

    @Test("Same-document references resolve to identifiers")
    func parsesLocalReferences() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadMapping()
        let entries = await fixtures.objects(of: "Entry", in: resource)
        let book = try #require(entries.first { $0.eGet("label") as? String == "book" })
        let author = try #require(entries.first { $0.eGet("label") as? String == "author" })

        #expect(await resource.eGet(objectId: book.id, feature: "related") as? [EUUID] == [author.id])
        #expect(await resource.eGet(objectId: author.id, feature: "related") as? [EUUID] == [book.id, author.id])
    }

    @Test("Many-valued attributes written as child elements and string typing")
    func parsesChildElementAttributes() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadMapping()
        let root = try #require(await resource.getRootObjects().first)

        #expect(await resource.eGet(objectId: root.id, feature: "notes") as? [String] == ["first note", "second & last note"])
        #expect(await resource.eGet(objectId: root.id, feature: "name") as? String == "Library")
        #expect(await resource.eGet(objectId: root.id, feature: "priority") as? Int == 3)
    }

    @Test("Child elements with href are stored under the declared reference")
    func parsesChildElementReferences() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <map:Entry xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:map="http://swift-modelling.org/test/mapping">
              <ecoreClass href="library.ecore#//Book"/>
              <related href="#/"/>
              <related href="other.mapping#/"/>
            </map:Entry>
            """
        let resource = try await parse(xml, with: fixtures)

        let root = try #require(await resource.getRootObjects().first)
        #expect(await resource.eGet(objectId: root.id, feature: "ecoreClass") as? ResourceProxy
            == ResourceProxy(uri: URIReference.resolve("library.ecore", against: resource.uri), fragment: "//Book"))
        let related = try #require(await resource.eGet(objectId: root.id, feature: "related") as? [ResourceProxy])
        #expect(related.count == 2)
        #expect(related[0] == ResourceProxy(uri: resource.uri, fragment: "/"))
        #expect(related[1].fragment == "/")
    }

    @Test("Unregistered classes keep their inferred behaviour")
    func unregisteredClassesKeepInference() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <un:Thing xmlns:un="http://example.org/unregistered" label="7" ratio="1.5" flag="true" ref="library.ecore#//Book"/>
            """
        let resource = try await parse(xml, with: fixtures)
        let root = try #require(await resource.getRootObjects().first)
        #expect(await resource.eGet(objectId: root.id, feature: "label") as? Int == 7)
        #expect(await resource.eGet(objectId: root.id, feature: "ratio") as? Double == 1.5)
        #expect(await resource.eGet(objectId: root.id, feature: "flag") as? Bool == true)
        #expect(await resource.eGet(objectId: root.id, feature: "ref") as? String == "library.ecore#//Book")
    }

    // MARK: - Helpers

    /// Parses XML text stored in a temporary file, within the fixtures' resource set.
    private func parse(_ xml: String, with fixtures: CrossDocumentFixtures) async throws -> Resource {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("xmi-parse-\(UUID().uuidString).xml")
        try xml.write(to: scratch, atomically: testWritesAtomically, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let parser = XMIParser(resourceSet: fixtures.resourceSet)
        return try await parser.parse(scratch)
    }
}
