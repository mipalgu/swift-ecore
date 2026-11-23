//
// ResourceSetPositionalFragmentTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests that a resource set resolves the positional fragments that the XMI writer produces.
@Suite("Resource set positional fragments")
struct ResourceSetPositionalFragmentTests {
    private static let documentURI = "test://positional.xmi"

    /// A small model: a container with many-valued items, each with one single-valued part.
    private struct World {
        let resourceSet = ResourceSet()
        let resource: Resource
        let container: DynamicEObject
        let items: [DynamicEObject]
        let parts: [DynamicEObject]
        let second: DynamicEObject

        init(secondRoot: Bool = false) async {
            let partClass = EClass(name: "Part")
            var itemClass = EClass(name: "Item")
            itemClass.eStructuralFeatures = [EReference(name: "part", eType: partClass, containment: true)]
            var containerClass = EClass(name: "Container")
            containerClass.eStructuralFeatures = [
                EReference(name: "items", eType: itemClass, upperBound: -1, containment: true)
            ]
            resource = await resourceSet.createResource(uri: ResourceSetPositionalFragmentTests.documentURI)
            container = DynamicEObject(eClass: containerClass)
            items = [DynamicEObject(eClass: itemClass), DynamicEObject(eClass: itemClass)]
            parts = [DynamicEObject(eClass: partClass), DynamicEObject(eClass: partClass)]
            second = DynamicEObject(eClass: containerClass)
            await resource.add(container)
            if secondRoot { await resource.add(second) }
            for object in items + parts { await resource.add(object) }
            await resource.eSet(objectId: container.id, feature: "items", value: items.map(\.id))
            for (item, part) in zip(items, parts) {
                await resource.eSet(objectId: item.id, feature: "part", value: part.id)
            }
        }

        func resolve(_ fragment: String) async -> EUUID? {
            await resourceSet.resolveByURI(ResourceSetPositionalFragmentTests.documentURI + "#" + fragment)?.id
        }
    }

    @Test("many-valued and nested single-valued positional fragments resolve")
    func positionalPaths() async {
        let w = await World()
        #expect(await w.resolve("/") == w.container.id)
        #expect(await w.resolve("//@items.0") == w.items[0].id)
        #expect(await w.resolve("//@items.1") == w.items[1].id)
        #expect(await w.resolve("//@items.1/@part") == w.parts[1].id)
        #expect(await w.resolve("//@items.2") == nil)
    }

    @Test("root positions select the roots of a resource with several roots")
    func rootPositions() async {
        let w = await World(secondRoot: true)
        #expect(await w.resolve("/0") == w.container.id)
        #expect(await w.resolve("/1") == w.second.id)
        #expect(await w.resolve("/0/@items.1") == w.items[1].id)
        #expect(await w.resolve("/0/@items.0/@part") == w.parts[0].id)
        #expect(await w.resolve("/2") == nil)
    }

    @Test("every fragment that the writer computes resolves back to its object")
    func writerFragmentsRoundTrip() async {
        for secondRoot in [false, true] {
            let w = await World(secondRoot: secondRoot)
            let fragments = await PositionalFragments.index(of: w.resource)
            #expect(fragments.count == 2 + w.items.count + w.parts.count - (secondRoot ? 0 : 1))
            for (id, fragment) in fragments {
                #expect(await w.resolve(fragment) == id, "\(fragment)")
            }
        }
    }

    @Test("identifier and name-based fragments still resolve")
    func otherFragments() async throws {
        let w = await World()
        #expect(await w.resolve(w.items[1].id.uuidString) == w.items[1].id)
        let library = EPackage(
            name: "library", nsURI: "http://example.org/library", nsPrefix: "lib", eClassifiers: [EClass(name: "Book")])
        let uri = "test://library.ecore"
        let resource = await w.resourceSet.createResource(uri: uri)
        await resource.registerNativePackage(library)
        let book = try #require(library.getEClass("Book"))
        #expect(await w.resourceSet.resolveByURI(uri + "#//Book")?.id == book.id)
    }
}
