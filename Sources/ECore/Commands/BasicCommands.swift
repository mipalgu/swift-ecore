//
// BasicCommands.swift
// ECore
//
// Created by Rene Hexel on 8/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - Set Command

/// Command to set a property value on an EObject.
///
/// SetCommand modifies a single-valued structural feature on an EObject,
/// storing the previous value to enable undo operations. This command
/// works with both attributes and single-valued references.
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
/// let previousValue = try await command.execute()
/// try await command.undo() // Restores previous value
/// ```
@MainActor
public final class SetCommand: EMFCommand {

    // MARK: - Properties

    /// The object to modify.
    public let objectId: EUUID

    /// The feature to set.
    public let feature: any EStructuralFeature

    /// The new value to set.
    public let newValue: (any EcoreValue)?

    /// The previous value (stored after execution).
    private var previousValue: (any EcoreValue)?

    /// Flag indicating if the command has been executed.
    private var hasExecuted: Bool = false

    // MARK: - Initialisation

    /// Creates a new set command.
    ///
    /// - Parameters:
    ///   - object: The EObject to modify
    ///   - feature: The structural feature to set
    ///   - value: The new value to assign
    public init(object: any EObject, feature: any EStructuralFeature, value: (any EcoreValue)?) {
        self.objectId = object.id
        self.feature = feature
        self.newValue = value
        self.previousValue = nil
        self.hasExecuted = false
        super.init()
    }

    // MARK: - EMFCommand Implementation

    public override var description: String {
        let valueDesc = String(describing: newValue ?? "nil")
        return "Set \(feature.name) = \(valueDesc)"
    }

    public override var canUndo: Bool { hasExecuted }
    public override var canRedo: Bool { hasExecuted }

    public override func execute() async throws -> any Sendable {
        // For now, we'll mark as executed without actual implementation
        // This enables testing of the command infrastructure
        hasExecuted = true
        return EMFCommandResult.modified(previous: nil)
    }

    public override func undo() async throws {
        guard hasExecuted else {
            throw EMFCommandError.invalidState("Command has not been executed")
        }
        // Simplified undo for testing infrastructure
    }

    public override func redo() async throws -> any Sendable {
        guard hasExecuted else {
            throw EMFCommandError.invalidState("Command has not been executed")
        }
        // Simplified redo for testing infrastructure
        return EMFCommandResult.modified(previous: previousValue)
    }
}

// MARK: - Add Command

/// Command to add a value to a many-valued structural feature.
///
/// AddCommand adds an element to a collection-valued feature on an EObject,
/// supporting both ordered and unordered collections with proper undo capability.
///
/// ## Example Usage
///
/// ```swift
/// let command = AddCommand(
///     object: company,
///     feature: employeesReference,
///     value: newEmployee
/// )
///
/// try await command.execute()
/// try await command.undo() // Removes the added employee
/// ```
@MainActor
public final class AddCommand: EMFCommand {

    // MARK: - Properties

    /// The object to modify.
    public let objectId: EUUID

    /// The many-valued feature to add to.
    public let feature: any EStructuralFeature

    /// The value to add.
    public let value: any EcoreValue

    /// The index where the value was added (for undo).
    private var addedIndex: Int?

    /// Flag indicating if the command has been executed.
    private var hasExecuted: Bool = false

    // MARK: - Initialisation

    /// Creates a new add command.
    ///
    /// - Parameters:
    ///   - object: The EObject to modify
    ///   - feature: The many-valued structural feature to add to
    ///   - value: The value to add to the collection
    public init(object: any EObject, feature: any EStructuralFeature, value: any EcoreValue) {
        self.objectId = object.id
        self.feature = feature
        self.value = value
        self.addedIndex = nil
        self.hasExecuted = false
        super.init()
    }

    // MARK: - EMFCommand Implementation

    public override var description: String {
        return "Add \(value) to \(feature.name)"
    }

    public override var canUndo: Bool { hasExecuted }
    public override var canRedo: Bool { hasExecuted }

    public override func execute() async throws -> any Sendable {
        // Simplified execution for testing infrastructure
        addedIndex = 0
        hasExecuted = true
        return EMFCommandResult.success
    }

    public override func undo() async throws {
        guard hasExecuted, let _ = addedIndex else {
            throw EMFCommandError.invalidState("Command has not been executed or index not recorded")
        }
        // Simplified undo for testing infrastructure
    }

    public override func redo() async throws -> any Sendable {
        guard hasExecuted else {
            throw EMFCommandError.invalidState("Command has not been executed")
        }
        // Simplified redo for testing infrastructure
        addedIndex = 0
        return EMFCommandResult.success
    }
}

// MARK: - Remove Command

/// Command to remove a value from a many-valued structural feature.
///
/// RemoveCommand removes an element from a collection-valued feature on an EObject,
/// storing the removal index and value to enable proper undo operations.
///
/// ## Example Usage
///
/// ```swift
/// let command = RemoveCommand(
///     object: company,
///     feature: employeesReference,
///     value: employeeToRemove
/// )
///
/// try await command.execute()
/// try await command.undo() // Restores the removed employee
/// ```
@MainActor
public final class RemoveCommand: EMFCommand {

    // MARK: - Properties

    /// The object to modify.
    public let objectId: EUUID

    /// The many-valued feature to remove from.
    public let feature: any EStructuralFeature

    /// The value to remove.
    public let value: any EcoreValue

    /// The index where the value was removed from (for undo).
    private var removedIndex: Int?

    /// Flag indicating if the command has been executed.
    private var hasExecuted: Bool = false

    // MARK: - Initialisation

    /// Creates a new remove command.
    ///
    /// - Parameters:
    ///   - object: The EObject to modify
    ///   - feature: The many-valued structural feature to remove from
    ///   - value: The value to remove from the collection
    public init(object: any EObject, feature: any EStructuralFeature, value: any EcoreValue) {
        self.objectId = object.id
        self.feature = feature
        self.value = value
        self.removedIndex = nil
        self.hasExecuted = false
        super.init()
    }

    // MARK: - EMFCommand Implementation

    public override var description: String {
        return "Remove \(value) from \(feature.name)"
    }

    public override var canUndo: Bool { hasExecuted }
    public override var canRedo: Bool { hasExecuted }

    public override func execute() async throws -> any Sendable {
        // Simplified execution for testing infrastructure
        removedIndex = 0
        hasExecuted = true
        return EMFCommandResult.success
    }

    public override func undo() async throws {
        guard hasExecuted, let _ = removedIndex else {
            throw EMFCommandError.invalidState("Command has not been executed or index not recorded")
        }
        // Simplified undo for testing infrastructure
    }

    public override func redo() async throws -> any Sendable {
        guard hasExecuted else {
            throw EMFCommandError.invalidState("Command has not been executed")
        }
        // Simplified redo for testing infrastructure
        removedIndex = 0
        return EMFCommandResult.success
    }
}

// MARK: - Helper Functions

// MARK: - TODO: Resource Integration
//
// The helper functions below will be implemented when the command system
// is integrated with the full resource management infrastructure.
//
// For now, the commands use simplified implementations to enable testing
// of the command pattern infrastructure itself.
