//
// DerivedFeatureTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Derived features and default reads")
struct DerivedFeatureTests {
    /// A shelf that contains books, with a transient container reference and a derived count.
    private struct Library {
        let resourceSet = ResourceSet()
        let resource: Resource
        let engine: ECoreExecutionEngine
        let shelfClass: EClass
        let bookClass: EClass
        let shelf: DynamicEObject
        let first: DynamicEObject
        let second: DynamicEObject
        let shelfFeature: EReference
        let derivedBooks: EReference
        let derivedFlag: EAttribute

        init(readsDefaults: Bool = false) async {
            let booksID = EUUID()
            let shelfID = EUUID()
            let stub = EClass(name: "Shelf")
            let bookStub = EClass(name: "Book")
            let books = EReference(
                id: booksID, name: "books", eType: bookStub, upperBound: -1, containment: true,
                opposite: shelfID)
            let owner = EReference(
                id: shelfID, name: "shelf", eType: stub, transient: true, opposite: booksID)
            let allBooks = EReference(
                name: "allBooks", eType: bookStub, upperBound: -1, volatile: true, transient: true,
                derived: true)
            let flag = EAttribute(
                name: "hasBooks", eType: EDataType(name: "EBoolean"), volatile: true,
                transient: true, derived: true)
            let weight = EAttribute(name: "weight", eType: EDataType(name: "EInt"))
            bookClass = EClass(name: "Book", eStructuralFeatures: [owner, weight])
            shelfClass = EClass(name: "Shelf", eStructuralFeatures: [books, allBooks, flag])
            shelfFeature = owner
            derivedBooks = allBooks
            derivedFlag = flag
            let package = EPackage(
                name: "lib", nsURI: "http://example.org/lib", nsPrefix: "lib",
                eClassifiers: [shelfClass, bookClass])
            await resourceSet.registerMetamodel(package, uri: package.nsURI)
            resource = await resourceSet.createResource(uri: "memory:/lib.xmi")
            var first = DynamicEObject(eClass: bookClass)
            var second = DynamicEObject(eClass: bookClass)
            first.eSet("weight", value: 2)
            second.eSet("weight", value: 3)
            var shelf = DynamicEObject(eClass: shelfClass)
            shelf.eSet("books", value: [first.id, second.id])
            self.first = first
            self.second = second
            self.shelf = shelf
            for object in [shelf, first, second] { _ = await resource.add(object) }
            engine = ECoreExecutionEngine(models: [:])
            await engine.registerResource(resource, alias: "lib")
            if readsDefaults { await engine.enableDefaultValues() }
        }
    }

    @Test("a rule computes the value of a derived feature from the resource")
    func ruleComputesValue() async throws {
        let library = await Library()
        await library.resourceSet.registerDerivedFeatureRule(
            DerivedFeatureRule(className: "Shelf", featureName: "allBooks") { object, _ in
                object.eGet("books")
            })
        let value = await library.resource.eGetComputed(
            objectId: library.shelf.id, feature: "allBooks")
        #expect(value as? [EUUID] == [library.first.id, library.second.id])
        let navigated = try await library.engine.navigate(from: library.shelf, property: "allBooks")
        let objects = try #require(navigated as? EcoreValueArray)
        #expect(objects.values.compactMap { ($0 as? DynamicEObject)?.id } == [library.first.id, library.second.id])
    }

    @Test("rules apply to subclasses and the most specific class wins")
    func ruleInheritance() async throws {
        let library = await Library()
        let special = EClass(name: "Special", eSuperTypes: [library.shelfClass])
        let object = DynamicEObject(eClass: special)
        _ = await library.resource.add(object)
        await library.resourceSet.registerDerivedFeatureRule(
            DerivedFeatureRule(className: "Shelf", featureName: "hasBooks") { _, _ in false })
        await library.resourceSet.registerDerivedFeatureRule(
            DerivedFeatureRule(className: "Special", featureName: "hasBooks") { _, _ in true })
        let inherited = await library.resource.eGetComputed(
            objectId: library.shelf.id, feature: "hasBooks")
        let overridden = await library.resource.eGetComputed(
            objectId: object.id, feature: "hasBooks")
        #expect(inherited as? Bool == false)
        #expect(overridden as? Bool == true)
    }

    @Test("a rule can be replaced by registering another for the same feature")
    func ruleReplacement() async throws {
        let library = await Library()
        await library.resourceSet.registerDerivedFeatureRule(
            DerivedFeatureRule(className: "Shelf", featureName: "hasBooks") { _, _ in false })
        await library.resourceSet.registerDerivedFeatureRule(
            DerivedFeatureRule(className: "Shelf", featureName: "hasBooks") { _, _ in true })
        let value = await library.resource.eGetComputed(
            objectId: library.shelf.id, feature: "hasBooks")
        #expect(value as? Bool == true)
    }

    @Test("an unset transient container reference reads as the container")
    func containerOpposite() async throws {
        let library = await Library()
        let value = await library.resource.eGetComputed(
            objectId: library.first.id, feature: "shelf")
        #expect(value as? EUUID == library.shelf.id)
        let navigated = try await library.engine.navigate(from: library.second, property: "shelf")
        #expect((navigated as? DynamicEObject)?.id == library.shelf.id)
    }

    @Test("a container reference of a root object has no value")
    func containerOfRoot() async throws {
        let library = await Library()
        let orphan = DynamicEObject(eClass: library.bookClass)
        _ = await library.resource.add(orphan)
        let value = await library.resource.eGetComputed(objectId: orphan.id, feature: "shelf")
        #expect(value == nil)
    }

    @Test("stored values and unknown objects are handled")
    func storedAndUnknown() async throws {
        let library = await Library()
        let stored = await library.resource.eGetComputed(
            objectId: library.first.id, feature: "weight")
        #expect(stored as? Int == 2)
        let missing = await library.resource.eGetComputed(objectId: EUUID(), feature: "weight")
        #expect(missing == nil)
        let unset = await library.resource.eGetComputed(
            objectId: library.shelf.id, feature: "hasBooks")
        #expect(unset == nil)
    }

    @Test("navigation reads unset attributes as nil unless defaults are enabled")
    func engineDefaults() async throws {
        let plain = await Library()
        let bare = DynamicEObject(eClass: plain.bookClass)
        _ = await plain.resource.add(bare)
        #expect(try await plain.engine.navigate(from: bare, property: "weight") == nil)
        let defaulting = await Library(readsDefaults: true)
        let other = DynamicEObject(eClass: defaulting.bookClass)
        _ = await defaulting.resource.add(other)
        let value = try await defaulting.engine.navigate(from: other, property: "weight")
        #expect(value as? Int == 0)
        let list = try await defaulting.engine.navigate(from: defaulting.first, property: "shelf")
        #expect((list as? DynamicEObject)?.id == defaulting.shelf.id)
        await defaulting.engine.enableDefaultValues(false)
        let off = DynamicEObject(eClass: defaulting.bookClass)
        _ = await defaulting.resource.add(off)
        #expect(try await defaulting.engine.navigate(from: off, property: "weight") == nil)
    }
}
