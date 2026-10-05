//
// ResourceEditCommand.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Base class of the commands that edit the dynamic instances of a resource.
///
/// A resource edit command runs against the resource that holds the object it edits. The
/// resource is given when the command is created, or found through the resource set when
/// an editing domain executes the command. Before running, the command captures a snapshot
/// of the resource, so undo restores the exact previous state, and redo restores the exact
/// state that execution produced. Executing a command that is not connected to a resource
/// throws ``EMFCommandError/resourceUnavailable(_:)``.
@MainActor
public class ResourceEditCommand: EMFCommand {

    /// The resource that the command edits, once known.
    public internal(set) var resource: Resource?

    private let bindingObjectID: EUUID?
    private var before: ResourceSnapshot?
    private var after: ResourceSnapshot?
    private var forwardChanges: [ResourceChange] = []
    private var forwardResult: EMFCommandResult = .success
    private(set) var hasExecuted = false

    /// Creates a command.
    ///
    /// - Parameters:
    ///   - bindingObjectID: The identifier of an object of the resource to edit, used to
    ///     find the resource through a resource set.
    ///   - resource: The resource to edit, if known.
    init(bindingObjectID: EUUID?, resource: Resource?) {
        self.bindingObjectID = bindingObjectID
        self.resource = resource
        super.init()
    }

    public override var canUndo: Bool { hasExecuted }
    public override var canRedo: Bool { hasExecuted }

    public override func bind(in resourceSet: ResourceSet) async {
        guard resource == nil, let bindingObjectID else { return }
        resource = await resourceSet.resolve(bindingObjectID)?.resource
    }

    public override func bind(to resource: Resource) {
        if self.resource == nil { self.resource = resource }
    }

    /// Carries out the edit.
    ///
    /// Subclasses override this to make their changes.
    ///
    /// - Parameter resource: The resource to edit.
    /// - Returns: The result of the command and the changes it made.
    /// - Throws: ``ResourceEditError`` if the edit cannot be made.
    func perform(on resource: Resource) async throws -> (result: EMFCommandResult, changes: [ResourceChange]) {
        (.success, [])
    }

    public override func execute() async throws -> any Sendable {
        guard let resource else {
            throw EMFCommandError.resourceUnavailable("No resource is available for '\(description)'")
        }
        let start = await resource.snapshot()
        do {
            let outcome = try await perform(on: resource)
            before = start
            after = await resource.snapshot()
            forwardChanges = outcome.changes
            forwardResult = outcome.result
            changes = outcome.changes
            hasExecuted = true
            return outcome.result
        } catch let error as ResourceEditError {
            await resource.restore(start)
            if case .objectNotFound = error {
                throw EMFCommandError.resourceUnavailable(error.description)
            }
            throw EMFCommandError.executionFailed(error.description)
        } catch {
            await resource.restore(start)
            throw error
        }
    }

    public override func undo() async throws {
        guard hasExecuted, let resource, let before else {
            throw EMFCommandError.invalidState("Command has not been executed")
        }
        await resource.restore(before)
        changes = forwardChanges.reversed().map(\.inverted)
    }

    public override func redo() async throws -> any Sendable {
        guard hasExecuted, let resource, let after else {
            throw EMFCommandError.invalidState("Command has not been executed")
        }
        await resource.restore(after)
        changes = forwardChanges
        return forwardResult
    }
}
