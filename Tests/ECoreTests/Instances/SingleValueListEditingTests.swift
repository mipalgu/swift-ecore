//
// SingleValueListEditingTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Editing a single value held by a many-valued feature")
struct SingleValueListEditingTests {
    let model = ShelfModel()

    /// A shelf whose picks and tags each hold one value without a list, and two books.
    private struct World {
        /// The resource that holds the shelf and the books.
        let resource: Resource
        /// The identifier of the shelf.
        let shelf: EUUID
        /// The identifier of the book that the shelf picks.
        let emma: EUUID
        /// The identifier of a book that the shelf does not pick.
        let atlas: EUUID
    }

    /// Creates the world of these tests.
    private func world() async -> World {
        let emma = model.book("Emma")
        let atlas = model.book("Atlas")
        var shelf = DynamicEObject(eClass: model.shelf)
        shelf.eSet("picks", value: emma.id)
        shelf.eSet("tags", value: "classics")
        let resource = await model.resource(with: [shelf, emma, atlas])
        return World(resource: resource, shelf: shelf.id, emma: emma.id, atlas: atlas.id)
    }

    /// The tags of the shelf of a world.
    private func tags(_ w: World) async -> [String]? {
        await w.resource.eGet(objectId: w.shelf, feature: "tags") as? [String]
    }

    /// The identifiers that a reference of an object holds.
    private func ids(_ resource: Resource, _ id: EUUID, _ feature: String) async -> [EUUID] {
        ReferenceValues.identifiers(await resource.eGet(objectId: id, feature: feature))
    }

    @Test("adding to a single attribute value appends after it")
    func addAfter() async throws {
        let w = await world()
        let changes = try await w.resource.eAdd(objectId: w.shelf, feature: "tags", value: "novels")
        #expect(await tags(w) == ["classics", "novels"])
        #expect(changes.map(\.index) == [1])
    }

    @Test("adding at the start inserts before the single value")
    func addBefore() async throws {
        let w = await world()
        try await w.resource.eAdd(objectId: w.shelf, feature: "tags", value: "novels", at: 0)
        #expect(await tags(w) == ["novels", "classics"])
        await #expect(throws: ResourceEditError.indexOutOfRange(4)) {
            try await w.resource.eAdd(objectId: w.shelf, feature: "tags", value: "loans", at: 4)
        }
    }

    @Test("adding the single value again is a duplicate")
    func addDuplicate() async throws {
        let w = await world()
        await #expect(throws: ResourceEditError.duplicateValue("tags")) {
            try await w.resource.eAdd(objectId: w.shelf, feature: "tags", value: "classics")
        }
        await #expect(throws: ResourceEditError.duplicateValue("picks")) {
            try await w.resource.eAdd(objectId: w.shelf, feature: "picks", value: w.emma)
        }
    }

    @Test("removing the single value leaves an empty list of its type")
    func removeSingle() async throws {
        let w = await world()
        let index = try await w.resource.eRemove(objectId: w.shelf, feature: "tags", value: "classics")
        #expect(index == 0)
        #expect(await tags(w) == [])
        let position = try await w.resource.eRemove(objectId: w.shelf, feature: "picks", value: w.emma)
        #expect(position == 0)
        #expect(await w.resource.eGet(objectId: w.shelf, feature: "picks") as? [EUUID] == [])
    }

    @Test("a value other than the single value is not removed")
    func removeAbsent() async throws {
        let w = await world()
        #expect(try await w.resource.eRemove(objectId: w.shelf, feature: "tags", value: "novels") == nil)
        #expect(try await w.resource.eRemove(objectId: w.shelf, feature: "picks", value: w.atlas) == nil)
        #expect(await ids(w.resource, w.shelf, "picks") == [w.emma])
    }

    @Test("the single value can be moved to its own position only")
    func moveSingle() async throws {
        let w = await world()
        #expect(try await w.resource.eMove(objectId: w.shelf, feature: "tags", from: 0, to: 0) == [])
        await #expect(throws: ResourceEditError.indexOutOfRange(1)) {
            try await w.resource.eMove(objectId: w.shelf, feature: "tags", from: 0, to: 1)
        }
    }

    @Test("a single value moves once another value has been added")
    func moveAfterAdding() async throws {
        let w = await world()
        try await w.resource.eAdd(objectId: w.shelf, feature: "picks", value: w.atlas)
        #expect(await ids(w.resource, w.shelf, "picks") == [w.emma, w.atlas])
        try await w.resource.eMove(objectId: w.shelf, feature: "picks", from: 0, to: 1)
        #expect(await ids(w.resource, w.shelf, "picks") == [w.atlas, w.emma])
    }

    @Test("deleting the single target of a reference removes it from the list")
    func deleteTarget() async throws {
        let w = await world()
        let changes = await w.resource.delete([w.emma])
        #expect(await ids(w.resource, w.shelf, "picks") == [])
        #expect(changes.contains { $0.kind == .remove && $0.feature == "picks" && $0.index == 0 })
    }

    @Test("a single contained child stays contained when another child is added or it moves away")
    func containment() async throws {
        let resource = try await model.read(
            """
                favourite="//@books.0" picks="//@books.0" tags="classics">
              <books title="Emma" kind="fiction" pages="474"/>
              <sign/>
            </shelf:Shelf>
            """)
        let shelf = try #require(await resource.getRootObjects().first as? DynamicEObject)
        let emma = try #require(await ids(resource, shelf.id, "books").first)
        try await resource.eAdd(objectId: shelf.id, feature: "books", value: model.book("Atlas"))
        let books = await ids(resource, shelf.id, "books")
        #expect(books.count == 2)
        #expect(books.first == emma)
        let other = DynamicEObject(eClass: model.shelf)
        _ = await resource.add(other)
        try await resource.eAdd(objectId: other.id, feature: "books", value: emma)
        #expect(await ids(resource, shelf.id, "books") == [books[1]])
        #expect(await ids(resource, other.id, "books") == [emma])
    }

    @Test("a single child moved into another container leaves an empty list behind")
    func detachSingleChild() async throws {
        let resource = try await model.read(
            """
                favourite="//@books.0" picks="//@books.0" tags="classics">
              <books title="Emma" kind="fiction" pages="474"/>
              <sign/>
            </shelf:Shelf>
            """)
        let shelf = try #require(await resource.getRootObjects().first as? DynamicEObject)
        let emma = try #require(await ids(resource, shelf.id, "books").first)
        let other = DynamicEObject(eClass: model.shelf)
        _ = await resource.add(other)
        let changes = try await resource.eAdd(objectId: other.id, feature: "books", value: emma)
        #expect(await ids(resource, shelf.id, "books") == [])
        #expect(changes.contains { $0.kind == .remove && $0.objectID == shelf.id && $0.index == 0 })
    }

    @Test("an opposite that holds a single value gains the new source as a second element")
    func opposite() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eSetWithChanges(objectId: w.alice.id, feature: "loans", value: w.book1.id)
        try await w.resource.eSetWithChanges(objectId: w.book2.id, feature: "borrower", value: w.alice.id)
        #expect(await w.ids(w.alice, "loans") == [w.book1.id, w.book2.id])
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "borrower", value: nil)
        #expect(await w.ids(w.alice, "loans") == [w.book2.id])
    }
}
