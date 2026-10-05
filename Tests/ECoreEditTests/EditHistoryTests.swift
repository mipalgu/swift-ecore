//
// EditHistoryTests.swift
// ECoreEditTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Testing

@testable import ECoreEdit

@Suite("Edit History")
struct EditHistoryTests {
    @Test("a new history has nothing to undo or redo and is clean")
    func initialState() {
        let history = EditHistory(0)
        #expect(!history.canUndo && !history.canRedo)
        #expect(history.undoLabel == nil && history.redoLabel == nil)
        #expect(!history.isDirty)
        #expect(history.current == 0)
    }

    @Test("recording, undoing, and redoing move between exact states and report labels")
    func undoRedo() {
        var history = EditHistory(0)
        history.record(1, label: "One")
        history.record(2, label: "Two")
        #expect(history.current == 2)
        #expect(history.undoLabel == "Two")
        #expect(history.undo() == 1)
        #expect(history.redoLabel == "Two")
        #expect(history.undoLabel == "One")
        #expect(history.undo() == 0)
        #expect(history.undo() == nil)
        #expect(!history.canUndo)
        #expect(history.redo() == 1)
        #expect(history.redo() == 2)
        #expect(history.redo() == nil)
        #expect(!history.canRedo)
    }

    @Test("recording after an undo forgets the redo steps")
    func recordClearsRedo() {
        var history = EditHistory(0)
        history.record(1, label: "One")
        history.undo()
        history.record(5, label: "Five")
        #expect(!history.canRedo)
        #expect(history.current == 5)
        #expect(history.undoLabel == "Five")
    }

    @Test("the limit drops the oldest edits")
    func limit() {
        var history = EditHistory(0, limit: 2)
        for value in 1...5 { history.record(value, label: "Edit \(value)") }
        #expect(history.undo() == 4)
        #expect(history.undo() == 3)
        #expect(history.undo() == nil)
        history.limit = 1
        #expect(history.redo() == 4)
        #expect(history.limit == 1)
    }

    @Test("a limit below one is raised to one")
    func minimumLimit() {
        var history = EditHistory(0, limit: 0)
        history.record(1, label: "One")
        history.record(2, label: "Two")
        #expect(history.undo() == 1)
        #expect(history.undo() == nil)
    }

    @Test("the history is dirty after an edit and clean after saving")
    func dirtyAfterEdit() {
        var history = EditHistory(0)
        history.record(1, label: "One")
        #expect(history.isDirty)
        history.markSaved()
        #expect(!history.isDirty)
    }

    @Test("undoing back to the saved state is clean; undoing past it is dirty")
    func dirtyAroundSavedPoint() {
        var history = EditHistory(0)
        history.record(1, label: "One")
        history.record(2, label: "Two")
        history.markSaved()
        history.undo()
        #expect(history.isDirty)
        history.redo()
        #expect(!history.isDirty)
        history.undo()
        history.undo()
        #expect(history.isDirty)
        history.redo()
        history.redo()
        #expect(!history.isDirty)
    }

    @Test("a new edit after undoing past the saved state stays dirty")
    func dirtyAfterDivergence() {
        var history = EditHistory(0)
        history.record(1, label: "One")
        history.markSaved()
        history.undo()
        history.record(9, label: "Nine")
        #expect(history.isDirty)
        history.undo()
        #expect(history.isDirty)
    }

    @Test("an edit that was dropped by the limit leaves the history dirty")
    func dirtyAfterTrim() {
        var history = EditHistory(0, limit: 1)
        history.record(1, label: "One")
        history.markSaved()
        history.record(2, label: "Two")
        history.record(3, label: "Three")
        history.undo()
        #expect(history.isDirty)
    }

    @Test("replacing the current state makes the history dirty without recording an edit")
    func replaceCurrent() {
        var history = EditHistory(0)
        history.replaceCurrent(with: 7)
        #expect(history.current == 7)
        #expect(history.isDirty)
        #expect(!history.canUndo)
    }
}
