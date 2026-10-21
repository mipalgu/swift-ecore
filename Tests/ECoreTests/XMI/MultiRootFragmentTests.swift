//
// MultiRootFragmentTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for the positional fragments of resources with one or several roots.
///
/// EMF identifies the only root of a resource by `/` and its contents by
/// `//@feature.index/...`. In a resource with several roots, root `n` is `/n` and
/// its contents are `/n/@feature.index/...`, including for the first root. These
/// tests check that fragments are computed, written and resolved by that rule,
/// and that the container side of a containment reference is never written.
@Suite("Multi-root XMI fragments")
struct MultiRootFragmentTests {
    /// The fixture with two package roots.
    static let twoRootsDocument = "classifiers-two-roots.xmi"

    /// The fixture with a single package root.
    static let singleRootDocument = "classifiers-wrapped.xmi"

    /// A document with two roots whose references point into the second root.
    static let crossRootDocument = """
        <?xml version="1.0" encoding="UTF-8"?>
        <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:cls="http://example.org/classifiers"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <cls:Package name="library">
            <classifiers xsi:type="cls:Class" name="Book">
              <attributes name="price" type="/1/@classifiers.1"/>
            </classifiers>
          </cls:Package>
          <cls:Package name="shop">
            <classifiers xsi:type="cls:Class" name="Order">
              <attributes name="total" type="/1/@classifiers.1"/>
            </classifiers>
            <classifiers xsi:type="cls:DataType" name="Money"/>
          </cls:Package>
        </xmi:XMI>

        """

    /// The roots of a resource as dynamic objects.
    ///
    /// - Parameter resource: The resource.
    /// - Returns: The dynamic root objects in order.
    private static func roots(of resource: Resource) async -> [DynamicEObject] {
        await resource.getRootObjects().compactMap { $0 as? DynamicEObject }
    }

    /// Loads the two-root fixture with its package contents.
    ///
    /// - Returns: The resource set, the resource, the two roots, and the classifiers of each root.
    private static func loadTwoRoots() async throws -> (
        set: ResourceSet, resource: Resource, roots: [DynamicEObject],
        library: [DynamicEObject], shop: [DynamicEObject]
    ) {
        let (set, _) = try await WrappedDocumentLoadingTests.makeResourceSet()
        let resource = try await WrappedDocumentLoadingTests.load(twoRootsDocument, in: set)
        let roots = await roots(of: resource)
        try #require(roots.count == 2)
        let library = try await WrappedDocumentLoadingTests.objects("classifiers", of: roots[0], in: resource)
        let shop = try await WrappedDocumentLoadingTests.objects("classifiers", of: roots[1], in: resource)
        try #require(library.count == 2 && shop.count == 2)
        return (set, resource, roots, library, shop)
    }

    // MARK: - Computing fragments

    @Test("a single root is / and its contents start with //")
    func singleRootFragments() async throws {
        let (set, _) = try await WrappedDocumentLoadingTests.makeResourceSet()
        let resource = try await WrappedDocumentLoadingTests.load(Self.singleRootDocument, in: set)
        let root = try #require(await Self.roots(of: resource).first)
        let classifiers = try await WrappedDocumentLoadingTests.objects("classifiers", of: root, in: resource)
        try #require(classifiers.count == 4)
        #expect(await PositionalFragments.fragment(for: root.id, in: resource) == "/")
        #expect(await PositionalFragments.fragment(for: classifiers[1].id, in: resource) == "//@classifiers.1")
        let attributes = try await WrappedDocumentLoadingTests.objects("attributes", of: classifiers[3], in: resource)
        try #require(attributes.count == 3)
        #expect(
            await PositionalFragments.fragment(for: attributes[2].id, in: resource)
                == "//@classifiers.3/@attributes.2")
        #expect(PositionalFragments.rootSegment(0, rootCount: 1) == "/")
    }

    @Test("each of several roots is /n and its contents start with /n")
    func severalRootFragments() async throws {
        let (_, resource, roots, library, shop) = try await Self.loadTwoRoots()
        let index = await PositionalFragments.index(of: resource)
        #expect(index[roots[0].id] == "/0")
        #expect(index[roots[1].id] == "/1")
        #expect(index[library[1].id] == "/0/@classifiers.1")
        #expect(index[shop[0].id] == "/1/@classifiers.0")
        let title = try await WrappedDocumentLoadingTests.objects("attributes", of: library[1], in: resource)
        #expect(index[try #require(title.first).id] == "/0/@classifiers.1/@attributes.0")
        #expect(PositionalFragments.rootSegment(0, rootCount: 2) == "/0")
        #expect(PositionalFragments.rootSegment(1, rootCount: 2) == "/1")
    }

    @Test("contents of a later root have fragments below that root")
    func laterRootContents() async throws {
        let (set, _) = try await WrappedDocumentLoadingTests.makeResourceSet()
        let resource = try await XMIParser(resourceSet: set).parse(Self.crossRootDocument, uri: "memory:/cross-root.xmi")
        let roots = await Self.roots(of: resource)
        try #require(roots.count == 2)
        let shop = try await WrappedDocumentLoadingTests.objects("classifiers", of: roots[1], in: resource)
        try #require(shop.count == 2)
        let total = try #require(
            try await WrappedDocumentLoadingTests.objects("attributes", of: shop[0], in: resource).first)
        #expect(
            await PositionalFragments.fragment(for: total.id, in: resource) == "/1/@classifiers.0/@attributes.0")
    }

    @Test("JSON keeps // for a single root and /n for several roots")
    func jsonRootSpelling() async throws {
        let (set, _) = try await WrappedDocumentLoadingTests.makeResourceSet()
        let single = try await WrappedDocumentLoadingTests.load(Self.singleRootDocument, in: set)
        let root = try #require(await Self.roots(of: single).first)
        #expect(await JSONFragments.fragment(for: root.id, in: single) == "//")
        let (_, resource, roots, library, _) = try await Self.loadTwoRoots()
        #expect(await JSONFragments.fragment(for: roots[1].id, in: resource) == "/1")
        #expect(await JSONFragments.fragment(for: library[1].id, in: resource) == "/0/@classifiers.1")
    }

    // MARK: - Writing fragments

    @Test("the EMF writer writes a same-document reference in the encoded attribute style")
    func emfWriterEncodedReference() async throws {
        let (_, resource, _, _, _) = try await Self.loadTwoRoots()
        let text = try await XMISerializer(options: .emf).serialize(resource)
        #expect(text.contains("type=\"cls:DataType #/0/@classifiers.0\""), "\(text)")
        #expect(!text.contains("//@classifiers"), "\(text)")
    }

    @Test("the plain reference style combines with type qualifiers")
    func plainWriterQualifiedReference() async throws {
        let (_, resource, _, _, _) = try await Self.loadTwoRoots()
        var options = XMISerializationOptions.emf
        options.referenceStyle = .plain
        let text = try await XMISerializer(options: options).serialize(resource)
        #expect(text.contains("type=\"cls:DataType /0/@classifiers.0\""), "\(text)")
        #expect(!text.contains("#/0"), "\(text)")
    }

    @Test("a plain reference to the only root parses as a reference")
    func plainRootReference() {
        #expect(CrossReference.parseList("/") == [CrossReference(uri: "", fragment: "/")])
        #expect(
            CrossReference.parseList("cls:Package /")
                == [CrossReference(qualifier: "cls:Package", uri: "", fragment: "/")])
        #expect(
            CrossReference.parseList("cls:Package / //@classifiers.0")
                == [
                    CrossReference(qualifier: "cls:Package", uri: "", fragment: "/"),
                    CrossReference(uri: "", fragment: "//@classifiers.0"),
                ])
    }

    @Test("the legacy writer writes a same-document reference as an href with #")
    func legacyWriterHref() async throws {
        let (_, resource, _, _, _) = try await Self.loadTwoRoots()
        let text = try await XMISerializer(options: .legacy).serialize(resource)
        #expect(text.contains("href=\"#/0/@classifiers.0\""), "\(text)")
        #expect(!text.contains("//@classifiers"), "\(text)")
    }

    @Test(
        "the container side of a containment is never written",
        arguments: [XMISerializationOptions.legacy, .emf])
    func containerSideOmitted(options: XMISerializationOptions) async throws {
        let (_, resource, _, _, _) = try await Self.loadTwoRoots()
        let text = try await XMISerializer(options: options).serialize(resource)
        for name in ["package", "owner"] {
            #expect(!text.contains(" \(name)=\""), "\(text)")
            #expect(!text.contains("<\(name) "), "\(text)")
        }
    }

    @Test(
        "a reference into a resource with several roots names the root position",
        arguments: [XMISerializationOptions.legacy, .emf])
    func crossResourceReference(options: XMISerializationOptions) async throws {
        let (set, resource, _, _, shop) = try await Self.loadTwoRoots()
        let package = try #require(await set.getMetamodel(uri: "http://example.org/classifiers"))
        let attributeClass = try #require(package.getEClass("Attribute"))
        let base = try #require(URL(string: resource.uri)).deletingLastPathComponent()
        let referrer = await set.createResource(uri: base.appendingPathComponent("referrer.xmi").absoluteString)
        var attribute = DynamicEObject(eClass: attributeClass)
        attribute.eSet("name", value: "shipment")
        attribute.eSet("type", value: shop[0].id)
        await referrer.add(attribute)
        let text = try await XMISerializer(options: options).serialize(referrer)
        #expect(text.contains(Self.twoRootsDocument + "#/1/@classifiers.0\""), "\(text)")
    }

    // MARK: - Resolving fragments

    @Test("the XPath resolver selects a root by its position")
    func resolverSelectsRoot() async throws {
        let (_, resource, roots, library, shop) = try await Self.loadTwoRoots()
        let resolver = XPathResolver(resource: resource)
        #expect(await resolver.resolve("/0") == roots[0].id)
        #expect(await resolver.resolve("/1") == roots[1].id)
        #expect(await resolver.resolve("#/1/@classifiers.0") == shop[0].id)
        #expect(await resolver.resolve("/0/@classifiers.1") == library[1].id)
        #expect(await resolver.resolve("//@classifiers.0") == library[0].id)
        #expect(await resolver.resolve("/2") == nil)
        #expect(await resolver.resolve("/5/@classifiers.0") == nil)
    }

    @Test("an idref that names a later root is parsed as a reference")
    func idrefNamesLaterRoot() {
        #expect(CrossReference.parseList("/1/@classifiers.0") == [CrossReference(uri: "", fragment: "/1/@classifiers.0")])
        #expect(
            CrossReference.parseList("ecore:EClass /1")
                == [CrossReference(qualifier: "ecore:EClass", uri: "", fragment: "/1")])
        #expect(
            CrossReference.parseList("cls:Class /1/@classifiers.0 /0")
                == [
                    CrossReference(qualifier: "cls:Class", uri: "", fragment: "/1/@classifiers.0"),
                    CrossReference(uri: "", fragment: "/0"),
                ])
    }

    @Test("loading resolves idrefs into a later root")
    func loadingResolvesLaterRoot() async throws {
        let (set, _) = try await WrappedDocumentLoadingTests.makeResourceSet()
        let resource = try await XMIParser(resourceSet: set).parse(Self.crossRootDocument, uri: "memory:/cross-root.xmi")
        let roots = await Self.roots(of: resource)
        try #require(roots.count == 2)
        let library = try await WrappedDocumentLoadingTests.objects("classifiers", of: roots[0], in: resource)
        let shop = try await WrappedDocumentLoadingTests.objects("classifiers", of: roots[1], in: resource)
        try #require(library.count == 1 && shop.count == 2)
        let price = try #require(
            try await WrappedDocumentLoadingTests.objects("attributes", of: library[0], in: resource).first)
        let total = try #require(
            try await WrappedDocumentLoadingTests.objects("attributes", of: shop[0], in: resource).first)
        #expect(ReferenceValues.identifiers(price.eGet("type")) == [shop[1].id])
        #expect(ReferenceValues.identifiers(total.eGet("type")) == [shop[1].id])
    }

    @Test(
        "a save of later-root references reloads them",
        arguments: [
            XMISerializationOptions.legacy, .emf,
            XMISerializationOptions(attributeStyleReferences: true, typeQualifiers: true, referenceStyle: .plain),
        ])
    func laterRootRoundTrip(options: XMISerializationOptions) async throws {
        let (set, _) = try await WrappedDocumentLoadingTests.makeResourceSet()
        let resource = try await XMIParser(resourceSet: set).parse(Self.crossRootDocument, uri: "memory:/cross-root.xmi")
        let text = try await XMISerializer(options: options).serialize(resource)
        let reloaded = try await XMIParser(resourceSet: set).parse(text, uri: "memory:/cross-root-reloaded.xmi")
        let roots = await Self.roots(of: reloaded)
        try #require(roots.count == 2)
        let library = try await WrappedDocumentLoadingTests.objects("classifiers", of: roots[0], in: reloaded)
        let shop = try await WrappedDocumentLoadingTests.objects("classifiers", of: roots[1], in: reloaded)
        #expect(library.compactMap { $0.eGet("name") as? String } == ["Book"])
        #expect(shop.compactMap { $0.eGet("name") as? String } == ["Order", "Money"])
        try #require(library.count == 1 && shop.count == 2)
        let price = try #require(
            try await WrappedDocumentLoadingTests.objects("attributes", of: library[0], in: reloaded).first)
        #expect(ReferenceValues.identifiers(price.eGet("type")) == [shop[1].id])
    }

    // MARK: - Container side

    /// Builds a parent class whose `children` reference has a `parent` opposite in the child class.
    ///
    /// - Parameter containment: Whether `children` is a containment reference.
    /// - Returns: The `parent` reference of the child class, declared without the container flag.
    private static func parentReference(containment: Bool) -> EReference {
        let childrenID = EUUID()
        let parentID = EUUID()
        let child = EClass(name: "Child")
        let children = EReference(
            id: childrenID, name: "children", eType: child, upperBound: -1, containment: containment,
            opposite: parentID)
        let parent = EClass(name: "Parent", eStructuralFeatures: [children])
        return EReference(id: parentID, name: "parent", eType: parent, opposite: childrenID)
    }

    @Test("a reference flagged as container is the container side")
    func containerSideByFlag() {
        let reference = EReference(name: "owner", eType: EClass(name: "Owner"), container: true)
        #expect(reference.isContainerSide)
    }

    @Test("a reference whose opposite in its type is a containment is the container side")
    func containerSideByOpposite() {
        let reference = Self.parentReference(containment: true)
        #expect(!reference.container)
        #expect(reference.isContainerSide)
    }

    @Test("a plain bidirectional reference is not the container side")
    func plainBidirectionalReference() {
        #expect(!Self.parentReference(containment: false).isContainerSide)
        #expect(!EReference(name: "loose", eType: EClass(name: "Loose")).isContainerSide)
    }
}
