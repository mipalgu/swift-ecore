//
// MetamodelEditingDomain.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
import Foundation

/// A token that ends an observation of a ``MetamodelEditingDomain`` when cancelled.
@MainActor
public final class MetamodelObservation {
    private weak var domain: MetamodelEditingDomain?
    private let identifier: UUID

    fileprivate init(domain: MetamodelEditingDomain, identifier: UUID) {
        self.domain = domain
        self.identifier = identifier
    }

    /// Whether the observation has ended.
    public var isCancelled: Bool { domain?.handlers[identifier] == nil }

    /// Ends the observation; the handler is not called again.
    public func cancel() {
        domain?.handlers.removeValue(forKey: identifier)
    }
}

/// Owns a metamodel document and its undo history, for view models on the main actor.
///
/// Views read ``document`` synchronously, edit it with ``perform(_:policy:)``, and learn what
/// changed either through a closure registered with ``observe(_:)`` or from the stream
/// that ``changes()`` returns. Both are told about every edit, undo, and redo, on the main
/// actor, before the call returns.
///
/// ```swift
/// let domain = MetamodelEditingDomain(document: document)
/// let token = domain.observe { changes in refresh(changes.labelsAffected) }
/// try domain.perform(.set(classID, .name, "Book"))
/// domain.undo()
/// ```
@MainActor
public final class MetamodelEditingDomain {
    /// The document, with every edit applied.
    public private(set) var document: MetamodelDocument

    private var history: EditHistory<MetamodelDocument>
    private var undoChanges: [MetamodelChangeSet] = []
    private var redoChanges: [MetamodelChangeSet] = []
    fileprivate var handlers: [UUID: @MainActor (MetamodelChangeSet) -> Void] = [:]
    private var continuations: [UUID: AsyncStream<MetamodelChangeSet>.Continuation] = [:]

    /// Creates a domain.
    ///
    /// - Parameters:
    ///   - document: The document to edit; it counts as saved.
    ///   - historyLimit: The number of edits to keep for undo.
    public init(document: MetamodelDocument, historyLimit: Int = 100) {
        self.document = document
        self.history = EditHistory(document, limit: historyLimit)
    }

    // MARK: Editing

    /// Applies an edit and records it for undo.
    ///
    /// An edit that changes nothing is not recorded and is not reported to observers.
    ///
    /// - Parameters:
    ///   - edit: The edit to apply.
    ///   - policy: What to do about edits that break rules of Ecore.
    /// - Returns: What the edit changed.
    /// - Throws: ``MetamodelEditError`` if the edit is refused; the document is not changed.
    @discardableResult
    public func perform(_ edit: MetamodelEdit, policy: EditPolicy = .default) throws(MetamodelEditError)
        -> MetamodelChangeSet
    {
        let changes = try applying(edit, policy: policy)
        if !changes.isEmpty {
            history.record(document, label: changes.label)
            undoChanges.append(changes)
            redoChanges.removeAll()
            if undoChanges.count > history.limit { undoChanges.removeFirst(undoChanges.count - history.limit) }
        }
        return changes
    }

    /// Applies an edit without recording it, and reports it.
    fileprivate func applying(_ edit: MetamodelEdit, policy: EditPolicy) throws(MetamodelEditError)
        -> MetamodelChangeSet
    {
        var updated = document
        let changes = try updated.apply(edit, policy: policy)
        guard !changes.isEmpty else { return changes }
        document = updated
        deliver(changes)
        return changes
    }

    /// Whether there is an edit to undo.
    public var canUndo: Bool { history.canUndo }

    /// Whether there is an edit to redo.
    public var canRedo: Bool { history.canRedo }

    /// The label of the edit that undo would reverse.
    public var undoLabel: String? { history.undoLabel }

    /// The label of the edit that redo would repeat.
    public var redoLabel: String? { history.redoLabel }

    /// Reverses the latest edit.
    ///
    /// - Returns: What undoing changed: the inverse of the change set of the edit; `nil` if
    ///   there is nothing to undo.
    @discardableResult
    public func undo() -> MetamodelChangeSet? {
        guard let label = history.undoLabel, let state = history.undo() else { return nil }
        guard let recorded = undoChanges.popLast() else { return transition(to: state, label: label) }
        redoChanges.append(recorded)
        document = state
        let changes = recorded.inverted()
        deliver(changes)
        return changes
    }

    /// Repeats the edit that was undone last.
    ///
    /// - Returns: What redoing changed: the change set of the edit; `nil` if there is nothing
    ///   to redo.
    @discardableResult
    public func redo() -> MetamodelChangeSet? {
        guard let label = history.redoLabel, let state = history.redo() else { return nil }
        guard let recorded = redoChanges.popLast() else { return transition(to: state, label: label) }
        undoChanges.append(recorded)
        document = state
        deliver(recorded)
        return recorded
    }

    /// Replaces the document by another state of the same document, and reports the difference.
    fileprivate func transition(to state: MetamodelDocument, label: String) -> MetamodelChangeSet {
        let changes = MetamodelDiff.changeSet(from: document, to: state, label: label)
        document = state
        deliver(changes)
        return changes
    }

    /// Replaces the document without recording an edit (for commands that keep their own history).
    fileprivate func restore(_ state: MetamodelDocument, label: String) {
        history.replaceCurrent(with: state)
        _ = transition(to: state, label: label)
    }

    // MARK: Saving

    /// Notes that the current document has been saved.
    public func markSaved() { history.markSaved() }

    /// Whether the document differs from the one that was last saved.
    ///
    /// Undoing past the saved state makes the document dirty again, and so does redoing away from it.
    public var isDirty: Bool { history.isDirty }

    // MARK: Observing

    /// Registers a closure that is called with every change set.
    ///
    /// - Parameter handler: The closure to call, on the main actor, after each edit, undo, and redo.
    /// - Returns: A token; cancel it to end the observation.
    public func observe(_ handler: @escaping @MainActor (MetamodelChangeSet) -> Void) -> MetamodelObservation {
        let identifier = UUID()
        handlers[identifier] = handler
        return MetamodelObservation(domain: self, identifier: identifier)
    }

    /// A stream of every change set from now on.
    ///
    /// Each call returns an independent stream. The stream ends when its consumer stops
    /// iterating or the domain goes away.
    public func changes() -> AsyncStream<MetamodelChangeSet> {
        let identifier = UUID()
        let (stream, continuation) = AsyncStream<MetamodelChangeSet>.makeStream()
        continuations[identifier] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations.removeValue(forKey: identifier) }
        }
        return stream
    }

    private func deliver(_ changes: MetamodelChangeSet) {
        for handler in Array(handlers.values) { handler(changes) }
        for continuation in continuations.values { continuation.yield(changes) }
    }

    // MARK: Commands

    /// A command that applies an edit through this domain, for a ``CommandStack``.
    ///
    /// The command keeps the document from before and after the edit, so undoing and redoing
    /// restore them exactly. The domain's own history does not record edits that run as commands.
    ///
    /// - Parameters:
    ///   - edit: The edit to apply when the command executes.
    ///   - policy: What to do about edits that break rules of Ecore.
    /// - Returns: The command; its result is the ``MetamodelChangeSet`` of the edit.
    public func command(for edit: MetamodelEdit, policy: EditPolicy = .default) -> EMFCommand {
        MetamodelEditCommand(domain: self, edit: edit, policy: policy)
    }
}

/// Runs a metamodel edit as an ``EMFCommand``.
@MainActor
private final class MetamodelEditCommand: EMFCommand {
    private let domain: MetamodelEditingDomain
    private let edit: MetamodelEdit
    private let policy: EditPolicy
    private var before: MetamodelDocument?
    private var after: MetamodelDocument?

    init(domain: MetamodelEditingDomain, edit: MetamodelEdit, policy: EditPolicy) {
        self.domain = domain
        self.edit = edit
        self.policy = policy
        super.init()
    }

    override var description: String { edit.label }

    override func execute() async throws -> any Sendable {
        let start = domain.document
        do {
            let changes = try domain.applying(edit, policy: policy)
            before = start
            after = domain.document
            return changes
        } catch {
            throw EMFCommandError.executionFailed(error.description)
        }
    }

    override func undo() async throws {
        guard let before else { throw EMFCommandError.invalidState("The command has not been executed.") }
        domain.restore(before, label: edit.label)
    }

    override func redo() async throws -> any Sendable {
        guard let after else { throw EMFCommandError.invalidState("The command has not been executed.") }
        domain.restore(after, label: edit.label)
        return MetamodelDiff.changeSet(from: before ?? after, to: after, label: edit.label)
    }
}
