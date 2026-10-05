//
// InstanceCommandTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@MainActor
@Suite("Instance commands")
struct InstanceCommandTests {

    /// Executes a command, undoes it, and redoes it, checking the exact states between.
    func roundTrip(_ command: EMFCommand, _ w: LibraryWorld, expecting check: () async throws -> Void) async throws {
        let initial = describe(await w.resource.snapshot())
        _ = try await command.execute()
        let executed = describe(await w.resource.snapshot())
        #expect(executed != initial)
        try await check()
        try await command.undo()
        #expect(describe(await w.resource.snapshot()) == initial)
        _ = try await command.redo()
        #expect(describe(await w.resource.snapshot()) == executed)
        try await check()
        try await command.undo()
        #expect(describe(await w.resource.snapshot()) == initial)
    }

    // MARK: - Set

    @Test("set command changes an attribute and undoes exactly")
    func setAttribute() async throws {
        let w = try await LibraryWorld()
        let command = SetCommand(object: w.book1, feature: w.model.title, value: "Dune II", in: w.resource)
        try await roundTrip(command, w) {
            #expect(await w.value(w.book1, "title") as? String == "Dune II")
        }
        #expect(command.canUndo && command.canRedo)
    }

    @Test("set command reports the previous value and its changes")
    func setResult() async throws {
        let w = try await LibraryWorld()
        let command = SetCommand(object: w.book1, feature: w.model.title, value: "New", in: w.resource)
        let result = try await command.execute()
        #expect(result as? EMFCommandResult == .modified(previous: "Dune"))
        #expect(command.changes.count == 1)
        try await command.undo()
        #expect(command.changes == command.changes.map(\.inverted).map(\.inverted))
        #expect(command.changes.first?.newValue as? String == "Dune")
    }

    @Test("set command maintains opposites and restores them on undo")
    func setReference() async throws {
        let w = try await LibraryWorld()
        let command = SetCommand(object: w.book1, feature: w.model.borrower, value: w.alice, in: w.resource)
        try await roundTrip(command, w) {
            #expect(await w.ids(w.alice, "loans") == [w.book1.id])
        }
    }

    // MARK: - Add and remove

    @Test("add command inserts, maintaining opposites")
    func add() async throws {
        let w = try await LibraryWorld()
        let extra = DynamicEObject(eClass: w.model.dvd)
        let command = AddCommand(object: w.other, feature: w.model.items, value: extra, at: 0, in: w.resource)
        try await roundTrip(command, w) {
            #expect(await w.ids(w.other, "items") == [extra.id])
            #expect(await w.value(extra, "library") as? EUUID == w.other.id)
        }
        #expect(await w.resource.contains(id: extra.id) == false)
    }

    @Test("add command moves a contained object to another container")
    func addMovesContainment() async throws {
        let w = try await LibraryWorld()
        let command = AddCommand(object: w.other, feature: w.model.items, value: w.book1, in: w.resource)
        try await roundTrip(command, w) {
            #expect(await w.ids(w.lib, "items") == [w.book2.id, w.dvd.id])
            #expect(await w.value(w.book1, "library") as? EUUID == w.other.id)
        }
        #expect(await w.ids(w.lib, "items") == [w.book1.id, w.book2.id, w.dvd.id])
    }

    @Test("remove command removes and restores at the original position")
    func remove() async throws {
        let w = try await LibraryWorld()
        let command = RemoveCommand(object: w.lib, feature: w.model.items, value: w.book2, in: w.resource)
        try await roundTrip(command, w) {
            #expect(await w.ids(w.lib, "items") == [w.book1.id, w.dvd.id])
            #expect(await w.value(w.book2, "library") == nil)
        }
        #expect(await w.ids(w.lib, "items") == [w.book1.id, w.book2.id, w.dvd.id])
    }

    @Test("removing an absent value fails and changes nothing")
    func removeAbsent() async throws {
        let w = try await LibraryWorld()
        let before = describe(await w.resource.snapshot())
        let command = RemoveCommand(object: w.other, feature: w.model.items, value: w.book1, in: w.resource)
        await #expect(throws: EMFCommandError.executionFailed("Value not found in feature items")) {
            _ = try await command.execute()
        }
        #expect(describe(await w.resource.snapshot()) == before)
        #expect(command.canUndo == false)
    }

    @Test("a failing edit leaves the resource untouched")
    func failedEditRestores() async throws {
        let w = try await LibraryWorld()
        let before = describe(await w.resource.snapshot())
        let command = AddCommand(object: w.lib, feature: w.model.libraryName, value: "x", in: w.resource)
        await #expect(throws: EMFCommandError.self) { _ = try await command.execute() }
        #expect(describe(await w.resource.snapshot()) == before)
        await #expect(throws: EMFCommandError.invalidState("Command has not been executed")) {
            try await command.undo()
        }
        await #expect(throws: EMFCommandError.invalidState("Command has not been executed")) {
            _ = try await command.redo()
        }
    }

    // MARK: - Move

    @Test("move command reorders and undoes")
    func moveReorder() async throws {
        let w = try await LibraryWorld()
        let command = MoveCommand(object: w.lib, feature: w.model.items, from: 2, to: 0, in: w.resource)
        try await roundTrip(command, w) {
            #expect(await w.ids(w.lib, "items") == [w.dvd.id, w.book1.id, w.book2.id])
        }
        #expect(command.description.contains("items"))
    }

    @Test("move command re-parents a contained object")
    func moveReparent() async throws {
        let w = try await LibraryWorld()
        let command = MoveCommand(moving: w.dvd, to: w.other, reference: w.model.items, at: 0, in: w.resource)
        try await roundTrip(command, w) {
            #expect(await w.ids(w.other, "items") == [w.dvd.id])
            #expect(await w.ids(w.lib, "items") == [w.book1.id, w.book2.id])
            #expect(await w.value(w.dvd, "library") as? EUUID == w.other.id)
        }
        #expect(command.description.contains("items"))
    }

    @Test("moving into a descendant is refused")
    func moveCycle() async throws {
        let w = try await LibraryWorld()
        let command = MoveCommand(moving: w.lib, to: w.lib, reference: w.model.items, in: w.resource)
        await #expect(throws: EMFCommandError.self) { _ = try await command.execute() }
    }

    // MARK: - Delete

    @Test("delete command removes objects and cleans references, and undo restores them")
    func delete() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eAdd(objectId: w.alice.id, feature: "loans", value: w.book1)
        let command = DeleteCommand(object: w.book1, in: w.resource)
        try await roundTrip(command, w) {
            #expect(await w.resource.contains(id: w.book1.id) == false)
            #expect(await w.ids(w.alice, "loans").isEmpty)
            #expect(await w.ids(w.lib, "items") == [w.book2.id, w.dvd.id])
        }
        #expect(await w.ids(w.alice, "loans") == [w.book1.id])
        #expect(command.description == "Delete object")
    }

    @Test("delete command deletes a whole subtree")
    func deleteSubtree() async throws {
        let w = try await LibraryWorld()
        let command = DeleteCommand(objects: [w.lib, w.other], in: w.resource)
        try await roundTrip(command, w) {
            #expect(await w.resource.count() == 0)
        }
        #expect(command.description == "Delete 2 objects")
    }

    @Test("deleting an unknown object fails")
    func deleteUnknown() async throws {
        let w = try await LibraryWorld()
        let stranger = DynamicEObject(eClass: w.model.book)
        let command = DeleteCommand(object: stranger, in: w.resource)
        await #expect(throws: EMFCommandError.resourceUnavailable("No object with identifier \(stranger.id) in the resource")) {
            _ = try await command.execute()
        }
    }

    // MARK: - Create

    @Test("create child command makes an instance with default values in a container")
    func createChild() async throws {
        let w = try await LibraryWorld()
        let command = CreateChildCommand(
            container: w.lib, reference: w.model.items, eClass: w.model.book, index: 0, in: w.resource)
        let result = try await command.execute()
        let createdID = try #require(command.createdID)
        #expect(result as? EMFCommandResult == .created(createdID))
        #expect(await w.ids(w.lib, "items").first == createdID)
        let created = try #require(await w.resource.resolve(createdID) as? DynamicEObject)
        #expect(created.eClass.id == w.model.book.id)
        #expect(created.eGet("pages") as? Int == 0)
        #expect(created.eGet("state") as? String == "available")
        #expect(created.eGet("title") == nil)
        #expect(command.createdClass.name == "Book")
        try await command.undo()
        #expect(await w.resource.contains(id: createdID) == false)
        _ = try await command.redo()
        #expect(await w.resource.contains(id: createdID))
        #expect(command.description == "Create Book in items")
    }

    @Test("create child command fills a single-valued containment reference")
    func createSingle() async throws {
        let w = try await LibraryWorld()
        let command = CreateChildCommand(container: w.lib, reference: w.model.manager, eClass: w.model.member, in: w.resource)
        try await roundTrip(command, w) {
            #expect(await w.ids(w.lib, "manager").count == 1)
        }
    }

    @Test("create child command can create a root object")
    func createRoot() async throws {
        let w = try await LibraryWorld()
        let command = CreateChildCommand(rootClass: w.model.library, in: w.resource)
        try await roundTrip(command, w) {
            #expect(await w.resource.getRootObjects().count == 3)
        }
        #expect(command.description == "Create Library")
    }

    // MARK: - Compound and binding

    @Test("compound command undoes in reverse order")
    func compound() async throws {
        let w = try await LibraryWorld()
        let first = SetCommand(object: w.book1, feature: w.model.title, value: "One", in: w.resource)
        let second = SetCommand(object: w.book1, feature: w.model.title, value: "Two", in: w.resource)
        let third = MoveCommand(object: w.lib, feature: w.model.items, from: 0, to: 2, in: w.resource)
        let compound = CompoundCommand(commands: [first, second, third])
        try await roundTrip(compound, w) {
            #expect(await w.value(w.book1, "title") as? String == "Two")
            #expect(await w.ids(w.lib, "items") == [w.book2.id, w.dvd.id, w.book1.id])
        }
        _ = try await compound.execute()
        #expect(compound.changes.count == 3)
        try await compound.undo()
        #expect(compound.changes.map(\.kind) == [.move, .set, .set])
        #expect(compound.changes.map(\.newValue).prefix(3).count == 3)
        #expect(compound.changes[1].newValue as? String == "One")
        #expect(compound.changes[2].newValue as? String == "Dune")
    }

    @Test("a failing member rolls the compound command back")
    func compoundFailure() async throws {
        let w = try await LibraryWorld()
        let before = describe(await w.resource.snapshot())
        let good = SetCommand(object: w.book1, feature: w.model.title, value: "One", in: w.resource)
        let bad = RemoveCommand(object: w.other, feature: w.model.items, value: w.book1, in: w.resource)
        let compound = CompoundCommand(commands: [good, bad])
        await #expect(throws: EMFCommandError.self) { _ = try await compound.execute() }
        #expect(describe(await w.resource.snapshot()) == before)
    }

    @Test("an unbound command throws resource unavailable")
    func unbound() async throws {
        let w = try await LibraryWorld()
        let commands: [EMFCommand] = [
            SetCommand(object: w.book1, feature: w.model.title, value: "x"),
            AddCommand(object: w.lib, feature: w.model.items, value: w.dvd),
            RemoveCommand(object: w.lib, feature: w.model.items, value: w.dvd),
            MoveCommand(object: w.lib, feature: w.model.items, from: 0, to: 1),
            DeleteCommand(object: w.dvd),
            CreateChildCommand(container: w.lib, reference: w.model.items, eClass: w.model.dvd),
        ]
        for command in commands {
            await #expect(throws: EMFCommandError.resourceUnavailable("No resource is available for '\(command.description)'")) {
                _ = try await command.execute()
            }
            #expect(command.canUndo == false)
        }
    }

    @Test("an editing domain binds commands through the resource set")
    func domainBinds() async throws {
        let w = try await LibraryWorld()
        let domain = BasicEditingDomain(resourceSet: w.resourceSet)
        let command = domain.createSetCommand(object: w.book1, feature: w.model.title, value: "Bound")
        _ = try await domain.execute(command)
        #expect(await w.value(w.book1, "title") as? String == "Bound")
        let compound = domain.createCompoundCommand([
            domain.createMoveCommand(object: w.lib, feature: w.model.items, from: 0, to: 1),
            domain.createAddCommand(object: w.other, feature: w.model.items, value: w.dvd),
            domain.createRemoveCommand(object: w.other, feature: w.model.items, value: w.dvd),
            domain.createChildCommand(container: w.lib, reference: w.model.items, eClass: w.model.dvd),
            domain.createDeleteCommand(objects: [w.alice]),
        ])
        _ = try await domain.execute(compound)
        #expect(await w.resource.contains(id: w.alice.id) == false)
        try await domain.undo()
        #expect(await w.resource.contains(id: w.alice.id))
        try await domain.undo()
        #expect(await w.value(w.book1, "title") as? String == "Dune")
    }

    // MARK: - Observers

    @MainActor
    final class Recorder: EditingDomainObserver {
        private(set) var sets: [ResourceChangeSet] = []
        func handle(_ event: EditingDomainEvent) async {}
        func changed(_ changeSet: ResourceChangeSet) async { sets.append(changeSet) }
    }

    @MainActor
    final class EventsOnly: EditingDomainObserver {
        private(set) var events = 0
        func handle(_ event: EditingDomainEvent) async { events += 1 }
    }

    @Test("observers receive the change journal for execute, undo, and redo")
    func observers() async throws {
        let w = try await LibraryWorld()
        let domain = BasicEditingDomain(resourceSet: w.resourceSet)
        let recorder = Recorder()
        let legacy = EventsOnly()
        domain.addObserver(recorder)
        domain.addObserver(legacy)
        let command = domain.createSetCommand(object: w.book1, feature: w.model.title, value: "Seen")
        _ = try await domain.execute(command)
        try await domain.undo()
        try await domain.redo()
        #expect(recorder.sets.map(\.origin) == [.execute, .undo, .redo])
        #expect(recorder.sets[0].changes.first?.newValue as? String == "Seen")
        #expect(recorder.sets[1].changes.first?.newValue as? String == "Dune")
        #expect(recorder.sets[2].affectedObjectIDs == [w.book1.id])
        #expect(recorder.sets[0].label.contains("title"))
        #expect(legacy.events == 6)
        let noop = domain.createSetCommand(object: w.book1, feature: w.model.title, value: "Seen")
        _ = try await domain.execute(noop)
        #expect(recorder.sets.count == 3)
    }
}
