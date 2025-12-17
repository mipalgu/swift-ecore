//
// BasicEditingDomain.swift
// ECore
//
//  Created by Rene Hexel on 8/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Actor providing basic editing domain functionality for model modification coordination.
///
/// The BasicEditingDomain serves as the central coordinator for all model modifications,
/// integrating command execution, change notification, and resource management. It
/// provides a unified interface for creating and executing commands while maintaining
/// model consistency and enabling undo/redo capabilities.
///
/// ## Overview
///
/// The editing domain manages several key aspects of model editing:
/// - **Command Creation**: Factory methods for common editing operations
/// - **Command Execution**: Coordinated execution through the command stack
/// - **Change Notification**: Broadcasting of model changes to observers
/// - **Resource Management**: Coordination with resource sets and persistence
/// - **Transaction Support**: Atomic operation grouping (future enhancement)
///
/// ## Concurrency Model
///
/// The BasicEditingDomain is implemented as an actor to ensure thread-safe
/// access to the command stack and editing state. All model modifications
/// are serialised through the actor's message queue to prevent race conditions.
///
/// ## Example Usage
///
/// ```swift
/// let editingDomain = BasicEditingDomain(resourceSet: myResourceSet)
///
/// // Create and execute a set command
/// let command = editingDomain.createSetCommand(
///     object: person,
///     feature: nameAttribute,
///     value: "John Doe"
/// )
/// let result = try await editingDomain.execute(command)
///
/// // Undo the change
/// try await editingDomain.undo()
/// ```
///
/// - Note: This implementation provides basic editing domain functionality.
///   Advanced features like change recording, adapter factories, and clipboard
///   operations may be added in future versions.
@MainActor
public final class BasicEditingDomain {

    // MARK: - Properties

    /// The command stack managing command execution and history.
    public let commandStack: CommandStack

    /// The resource set containing the models being edited.
    public let resourceSet: ResourceSet

    /// Observers for change notifications.
    private var changeObservers: [any EditingDomainObserver] = []

    /// Flag indicating if the editing domain is read-only.
    public private(set) var isReadOnly: Bool = false

    /// Current editing session statistics.
    public private(set) var statistics: EditingDomainStatistics

    // MARK: - Initialisation

    /// Creates a new basic editing domain.
    ///
    /// - Parameters:
    ///   - resourceSet: The resource set to manage
    ///   - maxCommandHistory: Maximum command history size (default: 50)
    public init(resourceSet: ResourceSet, maxCommandHistory: Int = 50) {
        self.resourceSet = resourceSet
        self.commandStack = CommandStack(maxHistorySize: maxCommandHistory)
        self.statistics = EditingDomainStatistics()
    }

    // MARK: - Command Creation

    /// Create a command to set a property value on an object.
    ///
    /// - Parameters:
    ///   - object: The EObject to modify
    ///   - feature: The structural feature to set
    ///   - value: The new value to assign
    /// - Returns: A configured SetCommand
    public func createSetCommand(
        object: any EObject,
        feature: any EStructuralFeature,
        value: (any EcoreValue)?
    ) -> SetCommand {
        return SetCommand(object: object, feature: feature, value: value)
    }

    /// Create a command to add a value to a many-valued feature.
    ///
    /// - Parameters:
    ///   - object: The EObject to modify
    ///   - feature: The many-valued structural feature
    ///   - value: The value to add
    /// - Returns: A configured AddCommand
    public func createAddCommand(
        object: any EObject,
        feature: any EStructuralFeature,
        value: any EcoreValue
    ) -> AddCommand {
        return AddCommand(object: object, feature: feature, value: value)
    }

    /// Create a command to remove a value from a many-valued feature.
    ///
    /// - Parameters:
    ///   - object: The EObject to modify
    ///   - feature: The many-valued structural feature
    ///   - value: The value to remove
    /// - Returns: A configured RemoveCommand
    public func createRemoveCommand(
        object: any EObject,
        feature: any EStructuralFeature,
        value: any EcoreValue
    ) -> RemoveCommand {
        return RemoveCommand(object: object, feature: feature, value: value)
    }

    /// Create a compound command from multiple commands.
    ///
    /// - Parameter commands: Array of commands to combine
    /// - Returns: A CompoundCommand that executes all commands atomically
    public func createCompoundCommand(_ commands: [EMFCommand]) -> CompoundCommand {
        return CompoundCommand(commands: commands)
    }

    // MARK: - Command Execution

    /// Execute a command through the editing domain.
    ///
    /// This method coordinates command execution with change notification
    /// and validation, ensuring proper integration with the editing domain's
    /// lifecycle and observer pattern.
    ///
    /// - Parameter command: The command to execute
    /// - Returns: The result of command execution
    /// - Throws: `EMFCommandError` if execution fails or domain is read-only
    public func execute(_ command: EMFCommand) async throws -> any Sendable {
        guard !isReadOnly else {
            throw EMFCommandError.executionFailed("Editing domain is read-only")
        }

        statistics.commandsExecuted += 1
        let startTime = Date()

        // Notify observers of pending change
        await notifyObservers(.aboutToExecute(command.description))

        do {
            let result = try await commandStack.execute(command)

            statistics.successfulExecutions += 1
            statistics.totalExecutionTime += Date().timeIntervalSince(startTime)

            // Notify observers of successful execution
            await notifyObservers(.executed(command.description))

            return result

        } catch {
            statistics.failedExecutions += 1

            // Notify observers of execution failure
            await notifyObservers(.executionFailed(command.description, error))

            throw error
        }
    }

    /// Undo the most recent command.
    ///
    /// - Throws: `EMFCommandError` if undo fails or is not available
    public func undo() async throws {
        guard !isReadOnly else {
            throw EMFCommandError.undoFailed("Editing domain is read-only")
        }

        let description = commandStack.nextUndoDescription ?? "Unknown"

        // Notify observers of pending undo
        await notifyObservers(.aboutToUndo(description))

        try await commandStack.undo()

        statistics.undoOperations += 1

        // Notify observers of successful undo
        await notifyObservers(.undone(description))
    }

    /// Redo the most recent undone command.
    ///
    /// - Throws: `EMFCommandError` if redo fails or is not available
    public func redo() async throws {
        guard !isReadOnly else {
            throw EMFCommandError.redoFailed("Editing domain is read-only")
        }

        let description = commandStack.nextRedoDescription ?? "Unknown"

        // Notify observers of pending redo
        await notifyObservers(.aboutToRedo(description))

        try await commandStack.redo()

        statistics.redoOperations += 1

        // Notify observers of successful redo
        await notifyObservers(.redone(description))
    }

    // MARK: - State Management

    /// Check if undo operation is available.
    public func canUndo() async -> Bool {
        let stackCanUndo = commandStack.canUndo
        return !isReadOnly && stackCanUndo
    }

    /// Check if redo operation is available.
    public func canRedo() async -> Bool {
        let stackCanRedo = commandStack.canRedo
        return !isReadOnly && stackCanRedo
    }

    /// Get description of the next command that would be undone.
    public func nextUndoDescription() async -> String? {
        return commandStack.nextUndoDescription
    }

    /// Get description of the next command that would be redone.
    public func nextRedoDescription() async -> String? {
        return commandStack.nextRedoDescription
    }

    /// Set the read-only state of the editing domain.
    ///
    /// - Parameter readOnly: `true` to make the domain read-only
    public func setReadOnly(_ readOnly: Bool) {
        isReadOnly = readOnly
    }

    /// Get the current read-only state.
    public var readOnly: Bool {
        return isReadOnly
    }

    /// Flush the command stack, clearing all history.
    public func flushCommandStack() async {
        commandStack.flush()
        await notifyObservers(.commandStackFlushed)
    }

    /// Get current editing domain statistics.
    public func getStatistics() -> EditingDomainStatistics {
        return statistics
    }

    // MARK: - Observer Management

    /// Add an observer for editing domain changes.
    ///
    /// - Parameter observer: The observer to add
    public func addObserver(_ observer: any EditingDomainObserver) {
        changeObservers.append(observer)
    }

    /// Remove an observer from editing domain changes.
    ///
    /// - Parameter observer: The observer to remove
    public func removeObserver(_ observer: any EditingDomainObserver) {
        changeObservers.removeAll { existingObserver in
            // Compare by object identity since observers are reference types
            existingObserver === observer
        }
    }

    /// Reset editing domain statistics.
    public func resetStatistics() {
        statistics = EditingDomainStatistics()
    }

    // MARK: - Private Implementation

    /// Notify all observers of an editing domain event.
    ///
    /// - Parameter event: The event to broadcast to observers
    private func notifyObservers(_ event: EditingDomainEvent) async {
        for observer in changeObservers {
            await observer.handle(event)
        }
    }
}

// MARK: - Compound Command

/// Command that executes multiple commands as a single atomic operation.
///
/// CompoundCommand allows multiple individual commands to be grouped together
/// and executed as a single unit, with all-or-nothing semantics for undo/redo.
@MainActor
public final class CompoundCommand: EMFCommand {

    // MARK: - Properties

    /// The individual commands to execute.
    private let commands: [EMFCommand]

    /// Results from executed commands (for undo).
    private var results: [EMFCommandResult] = []

    /// Flag indicating if all commands have been executed.
    private var hasExecuted: Bool = false

    // MARK: - Initialisation

    /// Creates a new compound command.
    ///
    /// - Parameter commands: Array of commands to execute together
    public init(commands: [EMFCommand]) {
        self.commands = commands
        self.results = []
        self.hasExecuted = false
        super.init()
    }

    // MARK: - EMFCommand Implementation

    public override var description: String {
        if commands.isEmpty {
            return "Empty compound command"
        } else if commands.count == 1 {
            return commands[0].description
        } else {
            return "Compound command (\(commands.count) operations)"
        }
    }

    public override var canUndo: Bool {
        // Empty compound commands can always be "undone" (no-op)
        if commands.isEmpty {
            return true
        }
        return hasExecuted && commands.allSatisfy { $0.canUndo }
    }

    public override var canRedo: Bool {
        // Empty compound commands can always be "redone" (no-op)
        if commands.isEmpty {
            return true
        }
        return hasExecuted && commands.allSatisfy { $0.canRedo }
    }

    public override func execute() async throws -> any Sendable {
        var executedResults: [EMFCommandResult] = []

        // Execute all commands in order
        for i in 0..<commands.count {
            do {
                let result = try await commands[i].execute()
                if let emfResult = result as? EMFCommandResult {
                    executedResults.append(emfResult)
                } else {
                    executedResults.append(.success)
                }
            } catch {
                // Undo any commands that were already executed
                for j in (0..<executedResults.count).reversed() {
                    if commands[j].canUndo {
                        try? await commands[j].undo()
                    }
                }
                throw error
            }
        }

        results = executedResults
        hasExecuted = true

        return EMFCommandResult.success
    }

    public override func undo() async throws {
        guard hasExecuted else {
            throw EMFCommandError.invalidState("Compound command has not been executed")
        }

        // Undo commands in reverse order
        for i in (0..<commands.count).reversed() {
            if commands[i].canUndo {
                try await commands[i].undo()
            }
        }
    }

    public override func redo() async throws -> any Sendable {
        guard hasExecuted else {
            throw EMFCommandError.invalidState("Compound command has not been executed")
        }

        // Redo commands in original order
        for i in 0..<commands.count {
            if commands[i].canRedo {
                _ = try await commands[i].redo()
            }
        }

        return EMFCommandResult.success
    }
}

// MARK: - Observer Protocol

/// Protocol for observing editing domain changes.
public protocol EditingDomainObserver: AnyObject, Sendable {

    /// Handle an editing domain event.
    ///
    /// - Parameter event: The event that occurred in the editing domain
    func handle(_ event: EditingDomainEvent) async
}

// MARK: - Editing Domain Events

/// Events that can occur in an editing domain.
public enum EditingDomainEvent: Sendable, Equatable {

    /// About to execute a command.
    case aboutToExecute(String)

    /// Command was executed successfully.
    case executed(String)

    /// Command execution failed.
    case executionFailed(String, Error)

    /// About to undo a command.
    case aboutToUndo(String)

    /// Command was undone successfully.
    case undone(String)

    /// About to redo a command.
    case aboutToRedo(String)

    /// Command was redone successfully.
    case redone(String)

    /// Command stack was flushed.
    case commandStackFlushed

    public static func == (lhs: EditingDomainEvent, rhs: EditingDomainEvent) -> Bool {
        switch (lhs, rhs) {
        case (.aboutToExecute(let lDesc), .aboutToExecute(let rDesc)),
            (.executed(let lDesc), .executed(let rDesc)),
            (.aboutToUndo(let lDesc), .aboutToUndo(let rDesc)),
            (.undone(let lDesc), .undone(let rDesc)),
            (.aboutToRedo(let lDesc), .aboutToRedo(let rDesc)),
            (.redone(let lDesc), .redone(let rDesc)):
            return lDesc == rDesc
        case (.executionFailed(let lDesc, _), .executionFailed(let rDesc, _)):
            return lDesc == rDesc
        case (.commandStackFlushed, .commandStackFlushed):
            return true
        default:
            return false
        }
    }
}

// MARK: - Statistics

/// Statistics for editing domain operations.
public struct EditingDomainStatistics: Sendable, Equatable {

    /// Total number of commands executed.
    public var commandsExecuted: Int = 0

    /// Number of successful command executions.
    public var successfulExecutions: Int = 0

    /// Number of failed command executions.
    public var failedExecutions: Int = 0

    /// Number of undo operations.
    public var undoOperations: Int = 0

    /// Number of redo operations.
    public var redoOperations: Int = 0

    /// Total time spent executing commands.
    public var totalExecutionTime: TimeInterval = 0.0

    /// Average execution time per command.
    public var averageExecutionTime: TimeInterval {
        guard commandsExecuted > 0 else { return 0.0 }
        return totalExecutionTime / Double(commandsExecuted)
    }

    /// Success rate of command executions.
    public var successRate: Double {
        guard commandsExecuted > 0 else { return 0.0 }
        return Double(successfulExecutions) / Double(commandsExecuted)
    }

    public init() {}
}

// MARK: - Thread-Safe Box for Mutable State

/// Thread-safe box for mutable state in Sendable types
