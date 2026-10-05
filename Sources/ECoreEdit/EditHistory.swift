//
// EditHistory.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

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
    /// An opaque marker for a captured state of an edit history.
    ///
    /// Capture this marker with the state being written, then pass it to
    /// ``markSaved(at:)`` when that write succeeds. Later edits remain dirty.
    public struct SavePoint: Sendable, Hashable {
        fileprivate let historyIdentifier: UUID
        fileprivate let versionIdentifier: UUID
    }

    /// One recorded edit.
    private struct Step: Sendable {
        let label: String
        let before: State
        let beforeVersion: UUID
        let after: State
        let afterVersion: UUID
    }

    /// The current state.
    public private(set) var current: State

    /// The number of edits that the history keeps for undo; older edits are dropped.
    public var limit: Int {
        didSet { trim() }
    }

    private var undoSteps: [Step] = []
    private var redoSteps: [Step] = []
    private let historyIdentifier = UUID()
    private var currentVersion: UUID
    private var savedVersion: UUID

    /// Starts a history. The initial state counts as saved.
    ///
    /// - Parameters:
    ///   - initial: The state to start with.
    ///   - limit: The number of edits to keep for undo (at least one; 100 by default).
    public init(_ initial: State, limit: Int = 100) {
        self.current = initial
        self.limit = max(1, limit)
        let initialVersion = UUID()
        self.currentVersion = initialVersion
        self.savedVersion = initialVersion
    }

    /// Records an edit that led to a new state.
    ///
    /// Edits that were undone and could have been redone are forgotten.
    ///
    /// - Parameters:
    ///   - state: The state after the edit.
    ///   - label: What the edit did, as shown by undo and redo menu items.
    public mutating func record(_ state: State, label: String) {
        let nextVersion = UUID()
        undoSteps.append(
            Step(label: label, before: current, beforeVersion: currentVersion, after: state, afterVersion: nextVersion))
        redoSteps.removeAll()
        current = state
        currentVersion = nextVersion
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

    /// A marker for the current state, suitable for a pending save.
    ///
    /// The marker remains valid after further edits, undo, redo or history
    /// trimming. Capture it alongside the immutable state to be written.
    public var savePoint: SavePoint {
        SavePoint(historyIdentifier: historyIdentifier, versionIdentifier: currentVersion)
    }

    /// Records a previously captured state as saved.
    ///
    /// Current contents and undo or redo history are preserved. A marker from
    /// another history is rejected without changing the saved state.
    ///
    /// - Parameter point: The marker captured with the state that was written.
    /// - Returns: Whether the marker belongs to this history.
    @discardableResult
    public mutating func markSaved(at point: SavePoint) -> Bool {
        guard point.historyIdentifier == historyIdentifier else { return false }
        savedVersion = point.versionIdentifier
        return true
    }

    /// Whether the current state differs from the saved state.
    public var isDirty: Bool { savedVersion != currentVersion }

    /// Replaces the current state without recording an edit, and without changing what counts
    /// as saved; the state counts as a state of its own.
    ///
    /// - Parameter state: The new current state.
    public mutating func replaceCurrent(with state: State) {
        current = state
        currentVersion = UUID()
    }

    private mutating func trim() {
        let excess = undoSteps.count - max(1, limit)
        if excess > 0 { undoSteps.removeFirst(excess) }
    }
}
