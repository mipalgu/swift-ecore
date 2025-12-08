//
// EMFCommand.swift
// ECore
//
// Created by Rene Hexel on 8/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

/// Protocol defining a command that can be executed, undone, and redone.
///
/// EMF commands encapsulate model modifications in a reversible manner, enabling
/// undo/redo functionality and transactional operations. Commands follow the
/// Command pattern, providing a uniform interface for all model modifications.
///
/// ## Overview
///
/// Commands represent atomic operations on model elements that can be:
/// - **Executed**: Applied to modify the model state
/// - **Undone**: Reversed to restore previous model state
/// - **Redone**: Re-applied after being undone
///
/// All commands must be thread-safe and work correctly in concurrent environments.
/// The execution model ensures that command operations are serialised through
/// actors to maintain model consistency.
///
/// ## Command Lifecycle
///
/// 1. **Creation**: Command is created with necessary context
/// 2. **Execution**: `execute()` is called to apply changes
/// 3. **Undo**: `undo()` reverses the changes (optional)
/// 4. **Redo**: `redo()` re-applies the changes after undo (optional)
///
/// ## Example Usage
///
/// ```swift
/// let command = SetCommand(
///     object: person,
///     feature: nameAttribute,
///     value: "John Doe"
/// )
///
/// let result = try await command.execute()
/// try await command.undo()    // Reverses the change
/// try await command.redo()    // Re-applies the change
/// ```
///
/// ## Subclassing
///
/// Concrete commands should inherit from this base class and override
/// the necessary methods. The base class provides default implementations
/// that can be overridden as needed.
///
/// - Note: Commands should store only the minimum information required
///   for execution and reversal. All command operations are MainActor-isolated.
@MainActor
public class EMFCommand {

    /// A human-readable description of the command.
    ///
    /// This description is used for debugging, logging, and potentially
    /// for user interface elements showing command history.
    public var description: String {
        return "EMF Command"
    }

    /// Indicates whether the command can be undone.
    ///
    /// Some commands may not support undo operations, particularly those
    /// involving external resources or irreversible actions.
    public var canUndo: Bool {
        return true
    }

    /// Indicates whether the command can be redone after being undone.
    ///
    /// Commands that can be undone should generally support redo,
    /// but this may not always be the case.
    public var canRedo: Bool {
        return canUndo
    }

    /// Initialise a new command.
    public init() {}

    /// Execute the command, applying its changes to the model.
    ///
    /// This method performs the primary operation of the command,
    /// modifying the target model elements as specified.
    ///
    /// - Returns: The result of command execution
    /// - Throws: `EMFCommandError` if execution fails
    public func execute() async throws -> any Sendable {
        throw EMFCommandError.executionFailed("Abstract method must be implemented by subclasses")
    }

    /// Undo the command, reversing its changes to the model.
    ///
    /// This method should restore the model to the exact state it was in
    /// before the command was executed. It should only be called on commands
    /// where `canUndo` returns `true`.
    ///
    /// - Throws: `EMFCommandError` if undo fails or is not supported
    public func undo() async throws {
        throw EMFCommandError.undoNotSupported
    }

    /// Redo the command, re-applying its changes after undo.
    ///
    /// This method should re-apply the command's changes, typically
    /// producing the same result as the original execution. It should
    /// only be called after `undo()` and where `canRedo` returns `true`.
    ///
    /// - Returns: The result of command re-execution
    /// - Throws: `EMFCommandError` if redo fails or is not supported
    public func redo() async throws -> any Sendable {
        throw EMFCommandError.redoNotSupported
    }
}

// MARK: - Default Implementations

// Default implementations are now provided in the base class above

// MARK: - Command Errors

/// Errors that can occur during command execution, undo, or redo operations.
public enum EMFCommandError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The command execution failed.
    case executionFailed(String)

    /// The command cannot be undone.
    case undoNotSupported

    /// The command cannot be redone.
    case redoNotSupported

    /// The undo operation failed.
    case undoFailed(String)

    /// The redo operation failed.
    case redoFailed(String)

    /// The command is in an invalid state.
    case invalidState(String)

    /// A required resource or object is not available.
    case resourceUnavailable(String)

    /// The command conflicts with the current model state.
    case stateConflict(String)

    public var description: String {
        switch self {
        case .executionFailed(let message):
            return "Command execution failed: \(message)"
        case .undoNotSupported:
            return "Undo operation is not supported for this command"
        case .redoNotSupported:
            return "Redo operation is not supported for this command"
        case .undoFailed(let message):
            return "Undo operation failed: \(message)"
        case .redoFailed(let message):
            return "Redo operation failed: \(message)"
        case .invalidState(let message):
            return "Command is in invalid state: \(message)"
        case .resourceUnavailable(let message):
            return "Required resource unavailable: \(message)"
        case .stateConflict(let message):
            return "Command conflicts with current state: \(message)"
        }
    }
}

// MARK: - Command Result Types

/// Common result types for EMF commands.
public enum EMFCommandResult: Sendable, Equatable, Hashable {
    /// Command completed successfully with no specific result.
    case success

    /// Command returned an ECore value.
    case value(any EcoreValue)

    /// Command returned multiple ECore values.
    case values([any EcoreValue])

    /// Command created a new object.
    case created(EUUID)

    /// Command removed an object.
    case removed(EUUID)

    /// Command modified a property, returning the previous value.
    case modified(previous: (any EcoreValue)?)

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .success:
            hasher.combine(0)
        case .value(let value):
            hasher.combine(1)
            ECore.hash(value, into: &hasher)
        case .values(let values):
            hasher.combine(2)
            hasher.combine(values.count)
            for value in values {
                ECore.hash(value, into: &hasher)
            }
        case .created(let id):
            hasher.combine(3)
            hasher.combine(id)
        case .removed(let id):
            hasher.combine(4)
            hasher.combine(id)
        case .modified(let previous):
            hasher.combine(5)
            if let prev = previous {
                ECore.hash(prev, into: &hasher)
            }
        }
    }

    public static func == (lhs: EMFCommandResult, rhs: EMFCommandResult) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success):
            return true
        case (.value(let lvalue), .value(let rvalue)):
            return areEqual(lvalue, rvalue)
        case (.values(let lvalues), .values(let rvalues)):
            return lvalues.count == rvalues.count && zip(lvalues, rvalues).allSatisfy(areEqual)
        case (.created(let lid), .created(let rid)):
            return lid == rid
        case (.removed(let lid), .removed(let rid)):
            return lid == rid
        case (.modified(let lprev), .modified(let rprev)):
            if let lp = lprev, let rp = rprev {
                return areEqual(lp, rp)
            }
            return lprev == nil && rprev == nil
        default:
            return false
        }
    }
}

// MARK: - Command State

/// The current state of a command in its lifecycle.
public enum EMFCommandState: Sendable, Equatable, CaseIterable {

    /// Command has been created but not executed.
    case ready

    /// Command has been executed successfully.
    case executed

    /// Command has been undone.
    case undone

    /// Command has been redone after undo.
    case redone

    /// Command execution failed.
    case failed

    /// Command is in an invalid state.
    case invalid
}
