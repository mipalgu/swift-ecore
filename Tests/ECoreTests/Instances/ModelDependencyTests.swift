//
// ModelDependencyTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Model dependencies")
struct ModelDependencyTests {

    /// Runs an edit and summarises its changes.
    private func impact(
        _ w: LibraryWorld, _ edit: @Sendable (isolated Resource) async throws -> Void
    ) async throws -> ModelChangeImpact {
        let (_, changes) = try await w.resource.recordingChanges { resource in try await edit(resource) }
        return await ModelChangeImpact(changes: changes, in: [w.resource])
    }

    // MARK: - Records

    @Test("a record names what was read and unions with others")
    func recordContents() {
        let id = EUUID()
        var record = ModelDependencies()
        #expect(record.isEmpty)
        record.recordFeature("name", of: id)
        record.recordObject(id)
        record.recordExtent("Book")
        record.recordContainer(of: id)
        #expect(record.features == [ModelFeatureKey(objectID: id, feature: "name")])
        #expect(record.objects == [id] && record.extents == ["Book"] && record.containers == [id])
        var other = ModelDependencies()
        other.recordContainmentStructure()
        other.recordUnbounded()
        let union = record.union(other)
        #expect(union.readsContainmentStructure && union.isUnbounded)
        #expect(union.features.count == 1)
        #expect(record.isEmpty == false)
        #expect(ModelFeatureKey(objectID: id, feature: "x").description == "\(id.uuidString).x")
    }

    // MARK: - Impacts

    @Test("an attribute change affects readers of that feature only")
    func attributeImpact() async throws {
        let w = try await LibraryWorld()
        let impact = try await impact(w) { try await $0.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "New") }
        #expect(impact.changedFeatures == [ModelFeatureKey(objectID: w.book1.id, feature: "title")])
        #expect(impact.changesContainmentStructure == false)
        #expect(impact.movedObjects.isEmpty && impact.affectedExtents.isEmpty)
        var reader = ModelDependencies()
        reader.recordFeature("title", of: w.book1.id)
        var other = ModelDependencies()
        other.recordFeature("title", of: w.book2.id)
        other.recordFeature("isbn", of: w.book1.id)
        #expect(reader.isAffected(by: impact))
        #expect(other.isAffected(by: impact) == false)
        var whole = ModelDependencies()
        whole.recordObject(w.book1.id)
        #expect(whole.isAffected(by: impact))
    }

    @Test("adding a new contained object changes extents, containers and structure")
    func creationImpact() async throws {
        let w = try await LibraryWorld()
        let extra = DynamicEObject(eClass: w.model.book)
        let impact = try await impact(w) { try await $0.eAdd(objectId: w.lib.id, feature: "items", value: extra) }
        #expect(impact.createdObjects == [extra.id])
        #expect(impact.affectedExtents == ["Book", "Item"])
        #expect(impact.movedObjects.contains(extra.id))
        #expect(impact.changesContainmentStructure)
        var extent = ModelDependencies()
        extent.recordExtent("Item")
        #expect(extent.isAffected(by: impact))
        var structure = ModelDependencies()
        structure.recordContainmentStructure()
        #expect(structure.isAffected(by: impact))
        var container = ModelDependencies()
        container.recordContainer(of: extra.id)
        #expect(container.isAffected(by: impact))
        var unrelated = ModelDependencies()
        unrelated.recordExtent("Member")
        #expect(unrelated.isAffected(by: impact) == false)
    }

    @Test("deleting an object affects every reader of its features")
    func deletionImpact() async throws {
        let w = try await LibraryWorld()
        let impact = try await impact(w) { _ = await $0.delete([w.book2.id]) }
        #expect(impact.deletedObjects == [w.book2.id])
        #expect(impact.replacedObjects == [w.book2.id])
        #expect(impact.movedObjects.contains(w.book2.id))
        var reader = ModelDependencies()
        reader.recordFeature("isbn", of: w.book2.id)
        #expect(reader.isAffected(by: impact))
    }

    @Test("moving within a containment list changes the structure but no container")
    func moveImpact() async throws {
        let w = try await LibraryWorld()
        let impact = try await impact(w) { try await $0.eMove(objectId: w.lib.id, feature: "items", from: 0, to: 2) }
        #expect(impact.changesContainmentStructure)
        #expect(impact.movedObjects.isEmpty)
        var container = ModelDependencies()
        container.recordContainer(of: w.book1.id)
        #expect(container.isAffected(by: impact) == false)
    }

    @Test("rebinding and unclassifiable creations make the impact unbounded")
    func unboundedImpacts() async throws {
        let w = try await LibraryWorld()
        let rebound = try await impact(w) { _ = $0.rebind(to: [w.model.package], from: [w.model.package]) }
        #expect(rebound.isUnbounded)
        let unknown = await ModelChangeImpact(
            changes: [ResourceChange(kind: .create, objectID: EUUID())], in: [w.resource])
        #expect(unknown.isUnbounded)
        let featureless = await ModelChangeImpact(
            changes: [ResourceChange(kind: .set, objectID: EUUID())], in: [w.resource])
        #expect(featureless.isUnbounded)
        var anything = ModelDependencies()
        anything.recordExtent("Nothing")
        #expect(anything.isAffected(by: .unbounded))
        #expect(ModelDependencies().isAffected(by: ModelChangeImpact()) == false)
    }

    @Test("a reference change on an unknown object counts as a containment change")
    func unknownReferenceChange() async {
        let child = EUUID()
        let change = ResourceChange(kind: .add, objectID: EUUID(), feature: "children", newValue: child, index: 0)
        let impact = await ModelChangeImpact(changes: [change], in: [])
        #expect(impact.changesContainmentStructure)
        #expect(impact.movedObjects == [child])
        var combined = ModelChangeImpact()
        combined.formUnion(impact)
        #expect(combined == impact)
        #expect(combined.isEmpty == false)
        #expect(ModelChangeImpact().isEmpty)
    }

    @Test("an unbounded record is affected by any change")
    func unboundedRecord() async throws {
        let w = try await LibraryWorld()
        let impact = try await impact(w) { try await $0.eSetWithChanges(objectId: w.alice.id, feature: "name", value: "Al") }
        var record = ModelDependencies()
        record.recordUnbounded()
        #expect(record.isAffected(by: impact))
    }

    // MARK: - Index

    @Test("the index finds the computations that changes affect")
    func indexLookup() async throws {
        let w = try await LibraryWorld()
        var index = ModelDependencyIndex<String>()
        #expect(index.isEmpty)
        var title = ModelDependencies()
        title.recordFeature("title", of: w.book1.id)
        var books = ModelDependencies()
        books.recordExtent("Book")
        var tree = ModelDependencies()
        tree.recordContainmentStructure()
        var any = ModelDependencies()
        any.recordUnbounded()
        var whole = ModelDependencies()
        whole.recordObject(w.alice.id)
        var parent = ModelDependencies()
        parent.recordContainer(of: w.dvd.id)
        index.insert(title, for: "title")
        index.insert(books, for: "books")
        index.insert(tree, for: "tree")
        index.insert(any, for: "any")
        index.insert(whole, for: "alice")
        index.insert(parent, for: "parent")
        #expect(index.count == 6)
        #expect(index.entryCount == 6)
        #expect(title.count == 1 && any.count == 1 && ModelDependencies().count == 0)
        #expect(index.dependencies(of: "title") == title)

        let rename = try await impact(w) { try await $0.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "X") }
        #expect(index.dependents(affectedBy: rename) == ["title", "any"])
        let created = try await impact(w) {
            try await $0.eAdd(objectId: w.lib.id, feature: "items", value: DynamicEObject(eClass: w.model.book))
        }
        #expect(index.dependents(affectedBy: created) == ["books", "tree", "any"])
        let renamed = try await impact(w) { try await $0.eSetWithChanges(objectId: w.alice.id, feature: "name", value: "A") }
        #expect(index.dependents(affectedBy: renamed) == ["alice", "any"])
        let moved = try await impact(w) { try await $0.eAdd(objectId: w.other.id, feature: "items", value: w.dvd.id) }
        #expect(index.dependents(affectedBy: moved).isSuperset(of: ["parent", "tree", "any"]))
        let deleted = try await impact(w) { _ = await $0.delete([w.book1.id]) }
        #expect(index.dependents(affectedBy: deleted).contains("title"))
        #expect(index.dependents(affectedBy: .unbounded).count == 6)
        #expect(index.dependents(affectedBy: ModelChangeImpact()).isEmpty)

        index.insert(books, for: "title")
        #expect(index.dependents(affectedBy: rename) == ["any"])
        #expect(index.remove("any") == any)
        #expect(index.remove("any") == nil)
        #expect(index.dependents(affectedBy: rename).isEmpty)
        #expect(Set(index.dependents) == ["title", "books", "tree", "alice", "parent"])
        #expect(index.entryCount == 5)
        index.removeAll()
        #expect(index.isEmpty && index.entryCount == 0)
    }

    // MARK: - Recorder

    @Test("nested frames add their reads to the enclosing frame")
    func recorderNesting() {
        let id = EUUID()
        var recorder = ModelDependencyRecorder()
        #expect(recorder.isRecording == false)
        recorder.recordFeature("ignored", of: id)
        #expect(recorder.end().isEmpty)
        recorder.begin()
        recorder.recordFeature("outer", of: id)
        recorder.begin()
        #expect(recorder.depth == 2)
        recorder.recordFeature("inner", of: id)
        recorder.recordObject(id)
        recorder.recordExtent("Book")
        recorder.recordContainer(of: id)
        recorder.recordContainmentStructure()
        let inner = recorder.end()
        #expect(inner.features.map(\.feature) == ["inner"])
        var cached = ModelDependencies()
        cached.recordUnbounded()
        recorder.merge(cached)
        let outer = recorder.end()
        #expect(Set(outer.features.map(\.feature)) == ["outer", "inner"])
        #expect(outer.objects == [id] && outer.extents == ["Book"] && outer.containers == [id])
        #expect(outer.readsContainmentStructure && outer.isUnbounded)
        #expect(recorder.isRecording == false)
        recorder.recordObject(id)
        recorder.recordExtent("X")
        recorder.recordContainer(of: id)
        recorder.recordContainmentStructure()
        recorder.recordUnbounded()
        recorder.merge(cached)
        #expect(recorder.depth == 0)
    }
}
