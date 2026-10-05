//
// EditHistory.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The undo and redo history of a state that is edited as a whole.
///
/// The history keeps the states that came before and after each recorded edit, so undoing and
/// redoing restore exact states and never have to reverse an edit. The state is a value (a
/// ``MetamodelDocument``, or an application's document that pairs a metamodel with diagram
/// layouts, so that one history covers both).
///
/// The history also knows whether the current state has been saved: ``markSaved()`` notes
/// the current state, and ``isDirty`` is `true` whenever the current state is another one, which
/// includes states reached by undoing past the saved state.
///
/// ```swift
/// var history = EditHistory(initialDocument)
/// history.record(editedDocument, label: "Rename")
/// let previous = history.undo()
/// ```
public struct EditHistory<State: Sendable>: Sendable {
    /// One recorded edit.
    private struct Step: Sendable {
        let label: String
        let before: State
        let beforeVersion: Int
        let after: State
        let afterVersion: Int
    }

    /// The current state.
    public private(set) var current: State

    /// The number of edits that the history keeps for undo; older edits are dropped.
    public var limit: Int {
        didSet { trim() }
    }

    private var undoSteps: [Step] = []
    private var redoSteps: [Step] = []
    private var currentVersion = 0
    private var savedVersion: Int? = 0
    private var latestVersion = 0

    /// Starts a history. The initial state counts as saved.
    ///
    /// - Parameters:
    ///   - initial: The state to start with.
    ///   - limit: The number of edits to keep for undo (at least one; 100 by default).
    public init(_ initial: State, limit: Int = 100) {
        self.current = initial
        self.limit = max(1, limit)
    }

    /// Records an edit that led to a new state.
    ///
    /// Edits that were undone and could have been redone are forgotten.
    ///
    /// - Parameters:
    ///   - state: The state after the edit.
    ///   - label: What the edit did, as shown by undo and redo menu items.
    public mutating func record(_ state: State, label: String) {
        latestVersion += 1
        undoSteps.append(
            Step(label: label, before: current, beforeVersion: currentVersion, after: state, afterVersion: latestVersion))
        redoSteps.removeAll()
        current = state
        currentVersion = latestVersion
        trim()
    }

    /// Whether there is an edit to undo.
    public var canUndo: Bool { !undoSteps.isEmpty }

    /// Whether there is an edit to redo.
    public var canRedo: Bool { !redoSteps.isEmpty }

    /// The label of the edit that undo would reverse.
    public var undoLabel: String? { undoSteps.last?.label }

    /// The label of the edit that redo would repeat.
    public var redoLabel: String? { redoSteps.last?.label }

    /// Goes back to the state before the latest edit.
    ///
    /// - Returns: The state after undoing, or `nil` if there is nothing to undo.
    @discardableResult
    public mutating func undo() -> State? {
        guard let step = undoSteps.popLast() else { return nil }
        redoSteps.append(step)
        current = step.before
        currentVersion = step.beforeVersion
        return current
    }

    /// Goes forward to the state after the edit that was undone last.
    ///
    /// - Returns: The state after redoing, or `nil` if there is nothing to redo.
    @discardableResult
    public mutating func redo() -> State? {
        guard let step = redoSteps.popLast() else { return nil }
        undoSteps.append(step)
        current = step.after
        currentVersion = step.afterVersion
        return current
    }

    /// Notes that the current state has been saved.
    public mutating func markSaved() {
        savedVersion = currentVersion
    }

    /// Whether the current state differs from the saved state.
    public var isDirty: Bool { savedVersion != currentVersion }

    /// Replaces the current state without recording an edit, and without changing what counts
    /// as saved; the state counts as a state of its own.
    ///
    /// - Parameter state: The new current state.
    public mutating func replaceCurrent(with state: State) {
        latestVersion += 1
        current = state
        currentVersion = latestVersion
    }

    private mutating func trim() {
        let excess = undoSteps.count - max(1, limit)
        if excess > 0 { undoSteps.removeFirst(excess) }
    }
}
