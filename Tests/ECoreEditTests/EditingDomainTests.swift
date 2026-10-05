//
// EditingDomainTests.swift
// ECoreEditTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ECoreEdit

/// Collects change sets that an observer receives.
@MainActor
private final class Recorder {
    var received: [MetamodelChangeSet] = []
}

@MainActor
@Suite("Editing Domain")
struct EditingDomainTests {
    @Test("undo and redo report the difference between the two states")
    func undoRedoChangeSets() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let item = fixture.id("Item")
        let edit = try domain.perform(.set(item, .name, "Thing"))
        #expect(domain.undoLabel == "Rename" && domain.canUndo && !domain.canRedo)
        let undone = try #require(domain.undo())
        #expect(undone.label == "Rename")
        #expect(undone.modified == edit.modified)
        #expect(undone.changes == [MetamodelChange(kind: .set, element: item, feature: .name, oldValue: .string("Thing"), newValue: .string("Item"))])
        #expect(undone.labelsAffected == edit.labelsAffected)
        #expect(domain.redoLabel == "Rename")
        let redone = try #require(domain.redo())
        #expect(redone.changes == edit.changes)
        #expect(domain.undo() != nil)
        #expect(domain.undo() == nil)
        #expect(domain.redo() != nil)
        #expect(domain.redo() == nil)
    }

    @Test("undo and redo of creation, deletion, and moves report added, removed, and moved elements")
    func structuralUndo() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let created = try domain.perform(.create(.eClass, in: fixture.rootID, feature: .eClassifiers, name: "Book")).createdIDs[0]
        #expect(try #require(domain.undo()).removed == [created])
        #expect(try #require(domain.redo()).added == [created])
        let deleted = try domain.perform(.delete([fixture.id("Item")]))
        let restored = try #require(domain.undo())
        #expect(restored.added == deleted.removed)
        #expect(restored.modified[fixture.id("items", in: "Owner")] == [.eType, .eOpposite])
        #expect(restored.structureChanged.contains(fixture.rootID))
        domain.redo()
        let moved = try domain.perform(.move([fixture.id("Failure")], to: fixture.id("sub")))
        let back = try #require(domain.undo())
        #expect(back.changes.map(\.kind) == [.move])
        #expect(back.changes[0].oldValue == .identifier(fixture.id("sub")))
        #expect(back.structureChanged == moved.structureChanged)
        #expect(back.changes[0].index == 2)
    }

    @Test("a long editing session can be undone to the start and redone to the end exactly")
    func session() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        var snapshots = [domain.document]
        let edits: [MetamodelEdit] = [
            .set(fixture.id("Item"), .name, "Thing"),
            .create(.eClass, in: fixture.rootID, feature: .eClassifiers, name: "Book"),
            .setOpposite(fixture.id("owner", in: "Item"), nil),
            .move([fixture.id("Failure")], to: fixture.id("sub")),
            .setDetail(annotation: fixture.annotationID, key: "c", value: "3"),
            .delete([fixture.id("Special")]),
            .compound(label: "Two", [.set(fixture.id("Owner"), .abstract, false), .set(fixture.id("Owner"), .name, "Boss")]),
        ]
        for edit in edits {
            try domain.perform(edit)
            snapshots.append(domain.document)
        }
        for expected in snapshots.dropLast().reversed() {
            domain.undo()
            #expect(domain.document == expected)
        }
        for expected in snapshots.dropFirst() {
            domain.redo()
            #expect(domain.document == expected)
        }
    }

    @Test("a refused edit leaves the document and the history alone")
    func refusedEdit() {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        #expect(throws: MetamodelEditError.self) { try domain.perform(.set(fixture.id("Item"), .name, 3)) }
        #expect(domain.document == fixture.document)
        #expect(!domain.canUndo)
        #expect(!domain.isDirty)
    }

    @Test("observers receive every change set until cancelled")
    func observers() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let first = Recorder()
        let second = Recorder()
        let token = domain.observe { first.received.append($0) }
        let other = domain.observe { second.received.append($0) }
        #expect(!token.isCancelled)
        try domain.perform(.set(fixture.id("Item"), .name, "Thing"))
        domain.undo()
        domain.redo()
        #expect(first.received.map(\.label) == ["Rename", "Rename", "Rename"])
        #expect(first.received.count == 3 && second.received.count == 3)
        token.cancel()
        #expect(token.isCancelled && !other.isCancelled)
        try domain.perform(.set(fixture.id("Item"), .name, "Other"))
        #expect(first.received.count == 3 && second.received.count == 4)
        try domain.perform(.set(fixture.id("Item"), .name, "Other"))
        #expect(second.received.count == 4, "an edit that changes nothing is not reported")
        other.cancel()
        other.cancel()
    }

    @Test("an observer sees the new document when it is called")
    func observerSeesNewDocument() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let names = Recorder()
        _ = domain.observe { _ in names.received.append(MetamodelChangeSet(label: domain.document.label(for: fixture.id("Item")).text)) }
        try domain.perform(.set(fixture.id("Item"), .name, "Thing"))
        #expect(names.received.map(\.label) == ["Thing"])
    }

    @Test("the change stream delivers change sets in order to every consumer")
    func stream() async throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let first = domain.changes()
        let second = domain.changes()
        try domain.perform(.set(fixture.id("Item"), .name, "Thing"))
        domain.undo()
        try domain.perform(.create(.eClass, in: fixture.rootID, feature: .eClassifiers, name: "Book"))
        var one = first.makeAsyncIterator()
        var two = second.makeAsyncIterator()
        var labels: [String] = []
        for _ in 0..<3 {
            let a = await one.next()
            let b = await two.next()
            #expect(a == b)
            labels.append(try #require(a).label)
        }
        #expect(labels == ["Rename", "Rename", "Create EClass"])
    }

    @Test("a stream whose consumer stops is released")
    func streamTermination() async throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        do {
            let stream = domain.changes()
            var iterator = stream.makeAsyncIterator()
            try domain.perform(.set(fixture.id("Item"), .name, "Thing"))
            #expect(await iterator.next()?.label == "Rename")
        }
        await Task.yield()
        try domain.perform(.set(fixture.id("Item"), .name, "Other"))
        #expect(domain.document.label(for: fixture.id("Item")).text == "Other")
    }

    @Test("the document is dirty from the first edit until it is saved, and after undoing past the saved state")
    func dirty() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        #expect(!domain.isDirty)
        try domain.perform(.set(fixture.id("Item"), .name, "One"))
        #expect(domain.isDirty)
        domain.markSaved()
        #expect(!domain.isDirty)
        try domain.perform(.set(fixture.id("Item"), .name, "Two"))
        domain.undo()
        #expect(!domain.isDirty)
        domain.undo()
        #expect(domain.isDirty)
        domain.redo()
        #expect(!domain.isDirty)
    }

    @Test("the history limit bounds undo")
    func historyLimit() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document, historyLimit: 2)
        for name in ["A1", "A2", "A3", "A4"] { try domain.perform(.set(fixture.id("Item"), .name, name)) }
        domain.undo()
        domain.undo()
        #expect(domain.undo() == nil)
        #expect(domain.document.label(for: fixture.id("Item")).text == "A2")
    }

    // MARK: Command adapter

    @Test("a command applies an edit through the domain and the command stack undoes and redoes it")
    func command() async throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let stack = CommandStack()
        let command = domain.command(for: .set(fixture.id("Item"), .name, "Thing"))
        #expect(command.description == "Rename")
        let observed = Recorder()
        _ = domain.observe { observed.received.append($0) }
        let result = try await stack.execute(command)
        let changes = try #require(result as? MetamodelChangeSet)
        #expect(changes.modified == [fixture.id("Item"): [.name]])
        #expect(domain.document.label(for: fixture.id("Item")).text == "Thing")
        #expect(!domain.canUndo, "the domain's own history does not record commands")
        try await stack.undo()
        #expect(domain.document == fixture.document)
        try await stack.redo()
        #expect(domain.document.label(for: fixture.id("Item")).text == "Thing")
        #expect(observed.received.count == 3)
        #expect(domain.isDirty)
    }

    @Test("a command whose edit is refused fails and an unexecuted command cannot be undone")
    func commandFailure() async throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let bad = domain.command(for: .set(fixture.id("Item"), .name, 3))
        await #expect(throws: EMFCommandError.self) { try await bad.execute() }
        await #expect(throws: EMFCommandError.self) { try await bad.undo() }
        await #expect(throws: EMFCommandError.self) { try await bad.redo() }
        let policy = domain.command(for: .set(fixture.id("Item"), .eSuperTypes, [fixture.id("Inner")]), policy: .permissive)
        _ = try await policy.execute()
        #expect(domain.document.label(for: fixture.id("Item")).text == "Item -> Inner")
    }

    @Test("a command redo returns the change set again")
    func commandRedoResult() async throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let command = domain.command(for: .create(.eClass, in: fixture.rootID, feature: .eClassifiers, name: "Book"))
        let created = try #require(try await command.execute() as? MetamodelChangeSet).createdIDs[0]
        try await command.undo()
        let redone = try #require(try await command.redo() as? MetamodelChangeSet)
        #expect(redone.added == [created])
    }
}

@Suite("Change Sets and Documents")
struct ChangeSetTests {
    @Test("an empty change set is empty and inverts to an empty change set")
    func empty() {
        let changes = MetamodelChangeSet(label: "Nothing")
        #expect(changes.isEmpty)
        #expect(changes.inverted().isEmpty)
    }

    @Test("inverting a change set reverses the order and swaps old and new values")
    func inverted() throws {
        let fixture = Fixture()
        var document = fixture.document
        let changes = try document.apply(.compound(label: "Both", [
            .create(.eClass, in: fixture.rootID, feature: .eClassifiers, name: "Book"),
            .set(fixture.id("Item"), .name, "Thing"),
            .move([fixture.id("Failure")], to: fixture.id("sub")),
            .delete([fixture.id("Kind")]),
        ]))
        let inverse = changes.inverted()
        #expect(inverse.label == "Both")
        #expect(inverse.changes.map(\.kind) == [.add, .move, .set, .remove])
        #expect(inverse.added == changes.removed && inverse.removed == changes.added)
        #expect(inverse.modified == changes.modified && inverse.structureChanged == changes.structureChanged)
        #expect(inverse.createdIDs.isEmpty && inverse.diagnostics.isEmpty)
        #expect(inverse.inverted().changes == changes.changes)
        #expect(inverse.changes[2].oldValue == .string("Thing") && inverse.changes[2].newValue == .string("Item"))
        #expect(inverse.changes[1].oldIndex == changes.changes[2].index && inverse.changes[1].oldFeature == .eClassifiers)
    }

    @Test("comparing two documents finds the same changes as the edit that led from one to the other")
    func differenceMatchesEdit() throws {
        let fixture = Fixture()
        let entry = fixture.document.index.children(of: fixture.annotationID)[0].id
        let edits: [MetamodelEdit] = [
            .set(fixture.id("Item"), .name, "Thing"),
            .create(.eClass, in: fixture.rootID, feature: .eClassifiers, name: "Book"),
            .delete([fixture.id("Item")]),
            .delete([fixture.id("Failure"), fixture.id("Kind")]),
            .move([fixture.id("Failure")], to: fixture.id("sub")),
            .move([fixture.id("Kind")], to: fixture.rootID, at: 0),
            .setOpposite(fixture.id("owner", in: "Item"), nil),
            .setDetail(annotation: fixture.annotationID, key: "c", value: "3"),
            .set(entry, .value, "x"),
            .set(fixture.id("Special"), .eSuperTypes, [fixture.id("Owner")]),
            .set(fixture.id("level"), .eType, builtIn(.eString)),
        ]
        for edit in edits {
            var document = fixture.document
            let changes = try document.apply(edit)
            let difference = MetamodelDiff.changeSet(from: fixture.document, to: document, label: changes.label)
            #expect(difference.added == changes.added, "\(edit.label)")
            #expect(difference.removed == changes.removed, "\(edit.label)")
            #expect(difference.modified == changes.modified, "\(edit.label)")
            #expect(difference.structureChanged == changes.structureChanged, "\(edit.label)")
            #expect(difference.labelsAffected == changes.labelsAffected, "\(edit.label)")
            // reordering within a container is reported as a structure change only
            if !difference.changes.isEmpty || edit.label != "Move" {
                #expect(Set(difference.changes.map(\.element)) == Set(changes.changes.map(\.element)), "\(edit.label)")
            }
            let reverse = MetamodelDiff.changeSet(from: document, to: fixture.document, label: "")
            #expect(reverse.added == changes.removed && reverse.removed == changes.added)
        }
        #expect(MetamodelDiff.changeSet(from: fixture.document, to: fixture.document, label: "").isEmpty)
    }

    @Test("a compound edit reports one summary for all of its edits")
    func compoundSummary() throws {
        let fixture = Fixture()
        var document = fixture.document
        let created = EUUID()
        let changes = try document.apply(.compound(label: "Mixed", [
            .create(.eClass, in: fixture.rootID, feature: .eClassifiers, name: "Temp", identifier: created),
            .set(created, .name, "Renamed"),
            .delete([created]),
            .set(fixture.id("Item"), .abstract, true),
        ]))
        #expect(changes.added.isEmpty && changes.removed.isEmpty && changes.createdIDs.isEmpty)
        #expect(changes.modified == [fixture.id("Item"): [.abstract]])
        #expect(changes.structureChanged == [fixture.rootID])
    }

    @Test("documents with the same content are equal and any difference makes them unequal")
    func equality() throws {
        let fixture = Fixture()
        var document = fixture.document
        #expect(document == fixture.document)
        try document.apply(.set(fixture.id("Item"), .name, "Thing"))
        #expect(document != fixture.document)
        try document.apply(.set(fixture.id("Item"), .name, "Item"))
        #expect(document == fixture.document)
        var moved = fixture.document
        try moved.apply(.move([fixture.id("Kind")], to: fixture.rootID, at: 0))
        #expect(moved != fixture.document)
        var relocated = fixture.document
        relocated.uri = "memory:other.ecore"
        #expect(relocated != fixture.document)
        var removed = fixture.document
        try removed.apply(.delete([fixture.id("Kind")]))
        #expect(removed != fixture.document && fixture.document != removed)
        #expect(MetamodelDocument(roots: []) == MetamodelDocument(roots: []))
    }

    @Test("the documents and elements are exposed")
    func accessors() {
        let fixture = Fixture()
        #expect(fixture.document.elements.count == fixture.document.index.allElements.count)
        #expect(fixture.document.roots.count == 1)
    }
}
