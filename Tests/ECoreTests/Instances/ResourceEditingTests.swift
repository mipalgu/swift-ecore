//
// ResourceEditingTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Resource editing")
struct ResourceEditingTests {

    // MARK: - Snapshots

    @Test("restoring a snapshot returns the resource to the exact earlier state")
    func snapshotRestore() async throws {
        let w = try await LibraryWorld()
        let before = await w.resource.snapshot()
        let description = describe(before)
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "Changed")
        await w.resource.delete([w.lib.id])
        #expect(describe(await w.resource.snapshot()) != description)
        await w.resource.restore(before)
        #expect(describe(await w.resource.snapshot()) == description)
        #expect(await w.resource.getRootObjects().map(\.id) == before.rootIDs)
    }

    @Test("a snapshot is unaffected by later edits")
    func snapshotIsolation() async throws {
        let w = try await LibraryWorld()
        let before = await w.resource.snapshot()
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "Changed")
        #expect(before.value(of: w.book1.id, feature: "title") as? String == "Dune")
        #expect(before.count == 6)
        #expect(before.contains(id: w.dvd.id))
        #expect(before.object(id: w.dvd.id) != nil)
        #expect(before.roots.count == before.rootIDs.count)
    }

    @Test("snapshots answer containment questions")
    func snapshotContainment() async throws {
        let w = try await LibraryWorld()
        let snapshot = await w.resource.snapshot()
        let lib = try #require(snapshot.object(id: w.lib.id))
        #expect(snapshot.contents(of: lib).map(\.id) == [w.book1.id, w.book2.id, w.dvd.id, w.alice.id])
        #expect(snapshot.allContents(of: lib).count == 4)
        #expect(snapshot.container(of: try #require(snapshot.object(id: w.book1.id)))?.id == w.lib.id)
        #expect(snapshot.container(of: lib) == nil)
        #expect(snapshot.containmentIndex()[w.alice.id]?.feature == "members")
        #expect(snapshot.targets(of: lib, w.model.items) == [w.book1.id, w.book2.id, w.dvd.id])
    }

    // MARK: - Add

    @Test("adding to a containment reference maintains the container opposite")
    func addMaintainsOpposite() async throws {
        let w = try await LibraryWorld()
        let extra = DynamicEObject(eClass: w.model.book)
        let changes = try await w.resource.eAdd(objectId: w.other.id, feature: "items", value: extra, at: 0)
        #expect(await w.ids(w.other, "items") == [extra.id])
        #expect(await w.value(extra, "library") as? EUUID == w.other.id)
        #expect(changes.map(\.kind) == [.create, .add, .set])
        #expect(changes.contains { $0.kind == .add && $0.objectID == w.other.id && $0.index == 0 })
        #expect(await w.resource.getRootObjects().map(\.id).contains(extra.id) == false)
    }

    @Test("adding at a position inserts there")
    func addAtIndex() async throws {
        let w = try await LibraryWorld()
        let extra = DynamicEObject(eClass: w.model.dvd)
        try await w.resource.eAdd(objectId: w.lib.id, feature: "items", value: extra, at: 1)
        #expect(await w.ids(w.lib, "items") == [w.book1.id, extra.id, w.book2.id, w.dvd.id])
    }

    @Test("adding a contained object elsewhere moves it between containers")
    func addMovesContainment() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eAdd(objectId: w.other.id, feature: "items", value: w.book1.id)
        #expect(await w.ids(w.lib, "items") == [w.book2.id, w.dvd.id])
        #expect(await w.ids(w.other, "items") == [w.book1.id])
        #expect(await w.value(w.book1, "library") as? EUUID == w.other.id)
    }

    @Test("adding to a non-containment many reference maintains the single-valued opposite")
    func addNonContainment() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eAdd(objectId: w.alice.id, feature: "loans", value: w.book1)
        #expect(await w.value(w.book1, "borrower") as? EUUID == w.alice.id)
        try await w.resource.eAdd(objectId: w.alice.id, feature: "tags", value: "vip")
        try await w.resource.eAdd(objectId: w.alice.id, feature: "tags", value: "staff", at: 0)
        #expect(await w.value(w.alice, "tags") as? [String] == ["staff", "vip"])
    }

    @Test("invalid additions are rejected")
    func addErrors() async throws {
        let w = try await LibraryWorld()
        let missing = EUUID()
        await #expect(throws: ResourceEditError.objectNotFound(missing)) {
            try await w.resource.eAdd(objectId: missing, feature: "items", value: w.book1.id)
        }
        await #expect(throws: ResourceEditError.featureNotFound(feature: "nope", className: "Library")) {
            try await w.resource.eAdd(objectId: w.lib.id, feature: "nope", value: "x")
        }
        await #expect(throws: ResourceEditError.notMultiValued("name")) {
            try await w.resource.eAdd(objectId: w.lib.id, feature: "name", value: "x")
        }
        await #expect(throws: ResourceEditError.indexOutOfRange(9)) {
            try await w.resource.eAdd(objectId: w.lib.id, feature: "items", value: w.book1.id, at: 9)
        }
        await #expect(throws: ResourceEditError.duplicateValue("loans")) {
            try await w.resource.eAdd(objectId: w.alice.id, feature: "loans", value: w.book1.id)
            try await w.resource.eAdd(objectId: w.alice.id, feature: "loans", value: w.book1.id)
        }
        await #expect(throws: ResourceEditError.invalidValue("loans")) {
            try await w.resource.eAdd(objectId: w.alice.id, feature: "loans", value: "not an object")
        }
    }

    @Test("an object cannot be added to its own subtree")
    func containmentCycle() async throws {
        let w = try await LibraryWorld()
        await #expect(throws: ResourceEditError.containmentCycle(w.lib.id)) {
            try await w.resource.eAdd(objectId: w.lib.id, feature: "items", value: w.lib.id)
        }
    }

    @Test("dynamic objects only are editable")
    func notEditable() async throws {
        let w = try await LibraryWorld()
        let native = EClass(name: "Native")
        await w.resource.add(native)
        await #expect(throws: ResourceEditError.notEditable(native.id)) {
            try await w.resource.eAdd(objectId: native.id, feature: "name", value: "x")
        }
    }

    // MARK: - Remove and move

    @Test("removing a value returns its position and clears the opposite")
    func removeValue() async throws {
        let w = try await LibraryWorld()
        let index = try await w.resource.eRemove(objectId: w.lib.id, feature: "items", value: w.book2)
        #expect(index == 1)
        #expect(await w.ids(w.lib, "items") == [w.book1.id, w.dvd.id])
        #expect(await w.value(w.book2, "library") == nil)
        #expect(await w.resource.getRootObjects().map(\.id).contains(w.book2.id))
        let again = try await w.resource.eRemove(objectId: w.lib.id, feature: "items", value: w.book2)
        #expect(again == nil)
    }

    @Test("removing from a non-containment reference clears the opposite and keeps roots")
    func removeNonContainment() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eAdd(objectId: w.alice.id, feature: "loans", value: w.book1)
        let roots = await w.resource.getRootObjects().map(\.id)
        try await w.resource.eRemove(objectId: w.alice.id, feature: "loans", value: w.book1)
        #expect(await w.value(w.book1, "borrower") == nil)
        #expect(await w.resource.getRootObjects().map(\.id) == roots)
        await #expect(throws: ResourceEditError.notMultiValued("name")) {
            try await w.resource.eRemove(objectId: w.lib.id, feature: "name", value: "Main")
        }
    }

    @Test("moving reorders values")
    func moveValue() async throws {
        let w = try await LibraryWorld()
        let changes = try await w.resource.eMove(objectId: w.lib.id, feature: "items", from: 0, to: 2)
        #expect(await w.ids(w.lib, "items") == [w.book2.id, w.dvd.id, w.book1.id])
        #expect(changes.first?.kind == .move)
        #expect(changes.first?.index == 2)
        #expect(changes.first?.oldIndex == 0)
        #expect(try await w.resource.eMove(objectId: w.lib.id, feature: "items", from: 1, to: 1).isEmpty)
        await #expect(throws: ResourceEditError.indexOutOfRange(7)) {
            try await w.resource.eMove(objectId: w.lib.id, feature: "items", from: 0, to: 7)
        }
        await #expect(throws: ResourceEditError.indexOutOfRange(-1)) {
            try await w.resource.eMove(objectId: w.lib.id, feature: "items", from: -1, to: 0)
        }
        await #expect(throws: ResourceEditError.notMultiValued("name")) {
            try await w.resource.eMove(objectId: w.lib.id, feature: "name", from: 0, to: 0)
        }
    }

    // MARK: - Set

    @Test("setting a single reference maintains the many-valued opposite")
    func setReference() async throws {
        let w = try await LibraryWorld()
        let changes = try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "borrower", value: w.alice)
        #expect(await w.ids(w.alice, "loans") == [w.book1.id])
        #expect(changes.map(\.objectID).contains(w.alice.id))
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "borrower", value: nil)
        #expect(await w.ids(w.alice, "loans").isEmpty)
        #expect(try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "borrower", value: nil).isEmpty)
    }

    @Test("setting a many-valued reference links new and unlinks removed targets")
    func setManyReference() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eSetWithChanges(objectId: w.alice.id, feature: "loans", value: [w.book1.id, w.book2.id])
        #expect(await w.value(w.book2, "borrower") as? EUUID == w.alice.id)
        try await w.resource.eSetWithChanges(objectId: w.alice.id, feature: "loans", value: [w.book2])
        #expect(await w.value(w.book1, "borrower") == nil)
        #expect(await w.ids(w.alice, "loans") == [w.book2.id])
    }

    @Test("setting a single containment reference orphans the previous child as a root")
    func setContainment() async throws {
        let w = try await LibraryWorld()
        let bob = DynamicEObject(eClass: w.model.member)
        try await w.resource.eSetWithChanges(objectId: w.lib.id, feature: "manager", value: w.alice)
        #expect(await w.ids(w.lib, "members").isEmpty)
        #expect(await w.ids(w.lib, "manager") == [w.alice.id])
        #expect(await w.ids(w.lib, "members").contains(w.alice.id) == false)
        try await w.resource.eSetWithChanges(objectId: w.lib.id, feature: "manager", value: bob)
        #expect(await w.resource.getRootObjects().map(\.id).contains(w.alice.id))
        #expect(await w.resource.getRootObjects().map(\.id).contains(bob.id) == false)
    }

    @Test("setting an attribute reports the old and new values")
    func setAttribute() async throws {
        let w = try await LibraryWorld()
        let changes = try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "Dune II")
        #expect(changes == [ResourceChange(kind: .set, objectID: w.book1.id, feature: "title", oldValue: "Dune", newValue: "Dune II")])
        #expect(try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "Dune II").isEmpty)
    }

    // MARK: - Inverse references and delete

    @Test("inverse references lists every referring feature")
    func inverseReferences() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eAdd(objectId: w.alice.id, feature: "loans", value: w.book1)
        let inverse = await w.resource.inverseReferences(to: w.book1.id)
        let described = inverse.map { "\($0.source)/\($0.feature)" }.sorted()
        #expect(described == ["\(w.alice.id)/loans", "\(w.lib.id)/items"].sorted())
        #expect(await w.resource.inverseReferences(to: EUUID()).isEmpty)
    }

    @Test("deleting removes the subtree and clears references to it")
    func deleteCleans() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eAdd(objectId: w.alice.id, feature: "loans", value: w.book1)
        let changes = await w.resource.delete([w.book1.id])
        #expect(await w.resource.contains(id: w.book1.id) == false)
        #expect(await w.ids(w.lib, "items") == [w.book2.id, w.dvd.id])
        #expect(await w.ids(w.alice, "loans").isEmpty)
        #expect(changes.filter { $0.kind == .delete }.map(\.objectID) == [w.book1.id])
        #expect(await w.resource.inverseReferences(to: w.book1.id).isEmpty)
    }

    @Test("deleting a container deletes its contents")
    func deleteSubtree() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eAdd(objectId: w.alice.id, feature: "loans", value: w.book1)
        let changes = await w.resource.delete([w.lib.id])
        #expect(await w.resource.count() == 1)
        #expect(await w.resource.getRootObjects().map(\.id) == [w.other.id])
        #expect(changes.filter { $0.kind == .delete }.count == 5)
        #expect(await w.resource.delete([EUUID()]).isEmpty)
    }

    @Test("deleting without cleaning leaves references dangling")
    func deleteWithoutCleaning() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eAdd(objectId: w.alice.id, feature: "loans", value: w.book1)
        await w.resource.delete([w.book1.id], cleaningReferences: false)
        #expect(await w.ids(w.alice, "loans") == [w.book1.id])
        #expect(await w.ids(w.lib, "items") == [w.book2.id, w.dvd.id])
    }

    // MARK: - Journal

    @Test("recordingChanges collects the changes of every operation inside it")
    func recording() async throws {
        let w = try await LibraryWorld()
        let (index, changes) = try await w.resource.recordingChanges { resource in
            try await resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "A")
            try await resource.eMove(objectId: w.lib.id, feature: "items", from: 0, to: 1)
            return try await resource.eRemove(objectId: w.lib.id, feature: "items", value: w.dvd.id)
        }
        #expect(index == 2)
        #expect(changes.map(\.kind) == [.set, .move, .remove, .set])
        let outside = await w.resource.recordingChanges { _ in 0 }
        #expect(outside.changes.isEmpty)
    }

    @Test("inverting a change swaps its values and kind")
    func inversion() {
        let id = EUUID()
        let add = ResourceChange(kind: .add, objectID: id, feature: "f", newValue: "x", index: 2)
        #expect(add.inverted == ResourceChange(kind: .remove, objectID: id, feature: "f", oldValue: "x", index: 2))
        let move = ResourceChange(kind: .move, objectID: id, feature: "f", index: 3, oldIndex: 1)
        #expect(move.inverted.index == 1)
        #expect(move.inverted.oldIndex == 3)
        let set = ResourceChange(kind: .set, objectID: id, feature: "f", oldValue: 1, newValue: 2)
        #expect(set.inverted.oldValue as? Int == 2)
        #expect(ResourceChange(kind: .create, objectID: id).inverted.kind == .delete)
        #expect(ResourceChange(kind: .delete, objectID: id).inverted.kind == .create)
        #expect(ResourceChange(kind: .rebind, objectID: id).inverted.kind == .rebind)
        let set1 = ResourceChangeSet(label: "x", origin: .undo, changes: [add, set, move])
        #expect(set1.affectedObjectIDs == [id])
    }

    // MARK: - Rebind

    @Test("rebinding by class identifier carries values over to the edited class")
    func rebindByID() async throws {
        let w = try await LibraryWorld()
        var edited = w.model.book
        edited.eStructuralFeatures.append(EAttribute(name: "extra", eType: EDataType(name: "EString")))
        let package = EPackage(
            name: "lib", nsURI: w.model.package.nsURI, nsPrefix: "lib",
            eClassifiers: [w.model.library, w.model.item, edited, w.model.dvd, w.model.member])
        let report = await w.resource.rebind(to: [package])
        #expect(report.unmatched.isEmpty)
        #expect(report.rebound == 6)
        let rebound = try #require(await w.resource.resolve(w.book1.id) as? DynamicEObject)
        #expect(rebound.eClass.getEAttribute(name: "extra") != nil)
        #expect(rebound.eGet("title") as? String == "Dune")
        #expect(rebound.eGet("isbn") as? String == "111")
    }

    @Test("rebinding falls back to package URI and class name when identifiers differ")
    func rebindByName() async throws {
        let w = try await LibraryWorld()
        let fresh = LibraryModel()
        let report = await w.resource.rebind(to: [fresh.package], from: [w.model.package])
        #expect(report.rebound == 6)
        let rebound = try #require(await w.resource.resolve(w.book1.id) as? DynamicEObject)
        #expect(rebound.eClass.id == fresh.book.id)
        #expect(rebound.eClass.id != w.model.book.id)
        #expect(rebound.eGet("title") as? String == "Dune")
    }

    @Test("rebinding by a unique class name works without previous metamodels")
    func rebindByUniqueName() async throws {
        let w = try await LibraryWorld()
        let fresh = LibraryModel()
        let report = await w.resource.rebind(to: [fresh.package])
        #expect(report.rebound == 6)
    }

    @Test("objects without a counterpart class are reported and keep their class")
    func rebindUnmatched() async throws {
        let w = try await LibraryWorld()
        let package = EPackage(name: "lib", nsURI: w.model.package.nsURI, eClassifiers: [w.model.library])
        let report = await w.resource.rebind(to: [package])
        #expect(report.rebound == 2)
        #expect(Set(report.unmatched) == [w.book1.id, w.book2.id, w.dvd.id, w.alice.id])
        let kept = try #require(await w.resource.resolve(w.book1.id) as? DynamicEObject)
        #expect(kept.eClass.id == w.model.book.id)
    }
}
