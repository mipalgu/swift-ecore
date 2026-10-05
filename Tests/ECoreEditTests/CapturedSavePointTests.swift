import Testing
@testable import ECoreEdit

@Suite("Captured edit history save points")
struct CapturedSavePointTests {
    @Test("Saving a captured state preserves later edits and history")
    func delayedSave() {
        var history = EditHistory(0)
        history.record(1, label: "One")
        let saved = history.savePoint
        history.record(2, label: "Two")
        #expect(history.markSaved(at: saved) == true)
        #expect(history.current == 2)
        #expect(history.isDirty)
        #expect(history.undoLabel == "Two")
        #expect(history.undo() == 1)
        #expect(!history.isDirty)
        #expect(history.redo() == 2)
        #expect(history.isDirty)
    }

    @Test("Foreign histories cannot change the saved state")
    func foreignHistory() {
        var history = EditHistory(0)
        let foreign = EditHistory(0).savePoint
        history.record(1, label: "One")
        #expect(history.markSaved(at: foreign) == false)
        #expect(history.isDirty)
        history.undo()
        #expect(!history.isDirty)
    }

    @Test("A discarded saved branch remains dirty")
    func discardedBranch() {
        var history = EditHistory(0)
        history.record(1, label: "One")
        let saved = history.savePoint
        history.undo()
        history.record(2, label: "Two")
        #expect(history.markSaved(at: saved) == true)
        #expect(history.isDirty)
        history.undo()
        #expect(history.isDirty)
        history.redo()
        #expect(history.isDirty)
    }

    @Test("Captured points survive undo history trimming")
    func trimming() {
        var history = EditHistory(0, limit: 1)
        history.record(1, label: "One")
        let saved = history.savePoint
        history.record(2, label: "Two")
        #expect(history.markSaved(at: saved) == true)
        #expect(history.undo() == 1)
        #expect(!history.isDirty)
        #expect(!history.canUndo)
        history.record(3, label: "Three")
        history.record(4, label: "Four")
        history.undo()
        #expect(history.isDirty)
    }

    @Test("Replacing a state has a distinct captured identity")
    func replacement() {
        var history = EditHistory(0)
        let initial = history.savePoint
        history.replaceCurrent(with: 1)
        let replaced = history.savePoint
        #expect(replaced != initial)
        #expect(Set([initial, replaced]).count == 2)
        #expect(history.markSaved(at: initial) == true)
        #expect(history.isDirty)
        #expect(history.markSaved(at: replaced) == true)
        #expect(!history.isDirty)
    }

    @Test("Divergent value copies never reuse a captured state identity")
    func divergentCopies() {
        var first = EditHistory(0)
        var second = first
        first.record(1, label: "One")
        second.record(2, label: "Two")
        #expect(first.savePoint != second.savePoint)
        #expect(second.markSaved(at: first.savePoint) == true)
        #expect(second.isDirty)
    }
}
