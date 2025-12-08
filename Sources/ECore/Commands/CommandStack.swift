//
// CommandStack.swift
// ECore
//
// Created by Rene Hexel on 8/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

/// Actor managing the execution and undo/redo history of EMF commands.
///
/// The CommandStack provides centralised command execution with full undo/redo
/// capabilities. It maintains separate stacks for undo and redo operations,
/// ensuring thread-safe access to command history and execution state.
///
/// ## Overview
///
/// The CommandStack follows a traditional undo/redo model:
/// - **Execution**: Commands are executed and added to the undo stack
/// - **Undo**: Commands are popped from undo stack and moved to redo stack
/// - **Redo**: Commands are popped from redo stack and moved back to undo stack
/// - **Flush**: Both stacks can be cleared to reset command history
///
/// ## Concurrency Model
///
/// The CommandStack is implemented as an actor to ensure thread-safe access
/// to command stacks and execution state. All command operations are serialised
/// through the actor's message queue, preventing race conditions and ensuring
/// consistent state transitions.
///
/// ## Example Usage
///
/// ```swift
/// let commandStack = CommandStack(maxHistorySize: 100)
///
/// let result = try await commandStack.execute(setCommand)
/// try await commandStack.undo()  // Reverses the set command
/// try await commandStack.redo()  // Re-applies the set command
/// ```
///
/// - Note: Commands are stored as `any EMFCommand<EMFCommandResult>` to allow
///   mixed command types in the same stack while maintaining type safety.
@MainActor
public final class CommandStack {

    // MARK: - Properties

    /// Stack of commands that can be undone.
    ///
    /// Commands are pushed onto this stack when executed and popped
    /// when undone. The most recently executed command is at the top.
    private var undoStack: [EMFCommand] = []
    
    /// Stack of commands that can be redone.
    ///
    /// Commands are pushed onto this stack when undone and popped
    /// when redone. The most recently undone command is at the top.
    private var redoStack: [EMFCommand] = []

    /// Maximum number of commands to retain in history.
    ///
    /// When this limit is reached, the oldest commands are removed
    /// from the bottom of the undo stack to free memory.
    public let maxHistorySize: Int

    /// Current execution statistics for performance monitoring.
    public private(set) var statistics: CommandStackStatistics

    // MARK: - Initialisation

    /// Creates a new command stack with the specified history size.
    ///
    /// - Parameter maxHistorySize: Maximum commands to retain (default: 50)
    public init(maxHistorySize: Int = 50) {
        self.maxHistorySize = max(1, maxHistorySize)
        self.statistics = CommandStackStatistics()
    }

    // MARK: - Command Execution

    /// Execute a command and add it to the undo stack.
    ///
    /// This method executes the provided command and, if successful,
    /// adds it to the undo stack for potential reversal. Any existing
    /// redo stack is cleared since new execution invalidates redo history.
    ///
    /// - Parameter command: The command to execute
    /// - Returns: The result of command execution
    /// - Throws: `EMFCommandError` if execution fails
    public func execute(_ command: EMFCommand) async throws -> any Sendable {
        statistics.executionCount += 1
        let startTime = Date()

        do {
            let result = try await command.execute()

            // Clear redo stack since new execution invalidates redo history
            redoStack.removeAll()

            // Add to undo stack if command supports undo
            if command.canUndo {
                undoStack.append(command)
                
                // Trim history if needed
                trimHistoryIfNeeded()
            }

            statistics.successCount += 1
            statistics.totalExecutionTime += Date().timeIntervalSince(startTime)

            return result

        } catch {
            statistics.failureCount += 1
            throw error
        }
    }

    /// Undo the most recent command.
    ///
    /// This method reverses the most recently executed command,
    /// moving it from the undo stack to the redo stack.
    ///
    /// - Throws: `EMFCommandError` if undo fails or no commands available
    public func undo() async throws {
        guard let command = undoStack.popLast() else {
            throw EMFCommandError.undoNotSupported
        }

        guard command.canUndo else {
            undoStack.append(command) // Put it back
            throw EMFCommandError.undoNotSupported
        }

        statistics.undoCount += 1
        let startTime = Date()

        do {
            try await command.undo()

            // Move to redo stack if command supports redo
            if command.canRedo {
                redoStack.append(command)
            }

            statistics.totalExecutionTime += Date().timeIntervalSince(startTime)

        } catch {
            undoStack.append(command) // Put it back on failure
            statistics.failureCount += 1
            throw error
        }
    }

    /// Redo the most recent undone command.
    ///
    /// This method re-executes the most recently undone command,
    /// moving it from the redo stack back to the undo stack.
    ///
    /// - Throws: `EMFCommandError` if redo fails or no commands available
    public func redo() async throws {
        guard let command = redoStack.popLast() else {
            throw EMFCommandError.redoNotSupported
        }

        guard command.canRedo else {
            redoStack.append(command) // Put it back
            throw EMFCommandError.redoNotSupported
        }

        statistics.redoCount += 1
        let startTime = Date()

        do {
            _ = try await command.redo()

            // Move back to undo stack
            undoStack.append(command)

            // Trim history if needed
            trimHistoryIfNeeded()

            statistics.totalExecutionTime += Date().timeIntervalSince(startTime)

        } catch {
            redoStack.append(command) // Put it back on failure
            statistics.failureCount += 1
            throw error
        }
    }

    // MARK: - Stack Management

    /// Check if undo operation is possible.
    ///
    /// - Returns: `true` if there are commands that can be undone
    public var canUndo: Bool {
        return !undoStack.isEmpty && (undoStack.last?.canUndo ?? false)
    }

    /// Check if redo operation is possible.
    ///
    /// - Returns: `true` if there are commands that can be redone
    public var canRedo: Bool {
        return !redoStack.isEmpty && (redoStack.last?.canRedo ?? false)
    }

    /// Get the description of the next command that would be undone.
    ///
    /// - Returns: Description of the top undo command, or `nil` if none available
    public var nextUndoDescription: String? {
        return undoStack.last?.description
    }

    /// Get the description of the next command that would be redone.
    ///
    /// - Returns: Description of the top redo command, or `nil` if none available
    public var nextRedoDescription: String? {
        return redoStack.last?.description
    }

    /// Clear all command history.
    ///
    /// This method removes all commands from both undo and redo stacks,
    /// effectively resetting the command history.
    public func flush() {
        undoStack.removeAll()
        redoStack.removeAll()
        statistics.flushCount += 1
    }

    /// Get the current number of commands in the undo stack.
    public var undoStackSize: Int {
        return undoStack.count
    }

    /// Get the current number of commands in the redo stack.
    public var redoStackSize: Int {
        return redoStack.count
    }

    /// Get execution statistics for performance monitoring.
    ///
    /// - Returns: Current command stack statistics
    public func getStatistics() -> CommandStackStatistics {
        return statistics
    }

    /// Reset execution statistics.
    public func resetStatistics() {
        statistics = CommandStackStatistics()
    }

    // MARK: - Private Implementation

    /// Trim the undo stack if it exceeds the maximum history size.
    private func trimHistoryIfNeeded() {
        while undoStack.count > maxHistorySize {
            undoStack.removeFirst()
        }
    }
}



// MARK: - Command Stack Statistics

/// Performance and usage statistics for command stack operations.
public struct CommandStackStatistics: Sendable, Equatable {

    /// Total number of commands executed.
    public var executionCount: Int = 0

    /// Number of successful command executions.
    public var successCount: Int = 0

    /// Number of failed command executions.
    public var failureCount: Int = 0

    /// Number of undo operations performed.
    public var undoCount: Int = 0

    /// Number of redo operations performed.
    public var redoCount: Int = 0

    /// Number of times the stack was flushed.
    public var flushCount: Int = 0

    /// Total time spent executing commands (in seconds).
    public var totalExecutionTime: TimeInterval = 0.0

    /// Average execution time per command.
    public var averageExecutionTime: TimeInterval {
        guard executionCount > 0 else { return 0.0 }
        return totalExecutionTime / Double(executionCount)
    }

    /// Success rate of command executions.
    public var successRate: Double {
        guard executionCount > 0 else { return 0.0 }
        return Double(successCount) / Double(executionCount)
    }

    public init() {}
}
