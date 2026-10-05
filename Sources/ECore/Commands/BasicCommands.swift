//
// BasicCommands.swift
// ECore
//
//  Created by Rene Hexel on 8/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

// MARK: - Set Command

/// Command to set a property value on an EObject.
///
/// SetCommand modifies a single-valued structural feature on a dynamic instance,
/// maintaining opposite references and containment. Undo and redo restore the exact
/// state of the resource before and after the change.
///
/// ## Example Usage
///
/// ```swift
/// let command = SetCommand(object: person, feature: nameAttribute, value: "John Doe")
///
/// _ = try await editingDomain.execute(command)
/// try await editingDomain.undo() // Restores previous value
/// ```
@MainActor
public final class SetCommand: ResourceEditCommand {

    // MARK: - Properties

    /// The object to modify.
    public let objectId: EUUID

    /// The feature to set.
    public let feature: any EStructuralFeature

    /// The new value to set.
    public let newValue: (any EcoreValue)?

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
        super.init(bindingObjectID: object.id, resource: nil)
    }

    /// Creates a new set command that edits a given resource.
    ///
    /// - Parameters:
    ///   - object: The EObject to modify
    ///   - feature: The structural feature to set
    ///   - value: The new value to assign
    ///   - resource: The resource that holds the object
    public init(
        object: any EObject, feature: any EStructuralFeature, value: (any EcoreValue)?,
        in resource: Resource
    ) {
        self.objectId = object.id
        self.feature = feature
        self.newValue = value
        super.init(bindingObjectID: object.id, resource: resource)
    }

    // MARK: - EMFCommand Implementation

    public override var description: String {
        let valueDesc = String(describing: newValue ?? "nil")
        return "Set \(feature.name) = \(valueDesc)"
    }

    override func perform(on resource: Resource) async throws -> (result: EMFCommandResult, changes: [ResourceChange]) {
        let changes = try await resource.eSetWithChanges(
            objectId: objectId, feature: feature.name, value: newValue)
        let previous = changes.first { $0.objectID == objectId && $0.feature == feature.name }?.oldValue
        return (.modified(previous: previous), changes)
    }
}

// MARK: - Add Command

/// Command to add a value to a many-valued structural feature.
///
/// AddCommand inserts an element into a collection-valued feature of a dynamic instance,
/// maintaining opposite references. Adding to a containment reference moves the element
/// out of its previous container. Undo and redo restore exact snapshots.
///
/// ## Example Usage
///
/// ```swift
/// let command = AddCommand(object: company, feature: employeesReference, value: newEmployee)
///
/// _ = try await editingDomain.execute(command)
/// try await editingDomain.undo() // Removes the added employee
/// ```
@MainActor
public final class AddCommand: ResourceEditCommand {

    // MARK: - Properties

    /// The object to modify.
    public let objectId: EUUID

    /// The many-valued feature to add to.
    public let feature: any EStructuralFeature

    /// The value to add.
    public let value: any EcoreValue

    /// The position to insert at, or `nil` to append.
    public let index: Int?

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
        self.index = nil
        super.init(bindingObjectID: object.id, resource: nil)
    }

    /// Creates a new add command that edits a given resource.
    ///
    /// - Parameters:
    ///   - object: The EObject to modify
    ///   - feature: The many-valued structural feature to add to
    ///   - value: The value to add to the collection
    ///   - index: The position to insert at, or `nil` to append
    ///   - resource: The resource that holds the object
    public init(
        object: any EObject, feature: any EStructuralFeature, value: any EcoreValue,
        at index: Int? = nil, in resource: Resource
    ) {
        self.objectId = object.id
        self.feature = feature
        self.value = value
        self.index = index
        super.init(bindingObjectID: object.id, resource: resource)
    }

    // MARK: - EMFCommand Implementation

    public override var description: String {
        return "Add \(value) to \(feature.name)"
    }

    override func perform(on resource: Resource) async throws -> (result: EMFCommandResult, changes: [ResourceChange]) {
        let changes = try await resource.eAdd(
            objectId: objectId, feature: feature.name, value: value, at: index)
        return (.success, changes)
    }
}

// MARK: - Remove Command

/// Command to remove a value from a many-valued structural feature.
///
/// RemoveCommand removes an element from a collection-valued feature of a dynamic
/// instance, maintaining opposite references. Undo restores the element at its original
/// position. An element removed from a containment reference remains in the resource as a
/// root object.
///
/// ## Example Usage
///
/// ```swift
/// let command = RemoveCommand(object: company, feature: employeesReference, value: employee)
///
/// _ = try await editingDomain.execute(command)
/// try await editingDomain.undo() // Restores the removed employee
/// ```
@MainActor
public final class RemoveCommand: ResourceEditCommand {

    // MARK: - Properties

    /// The object to modify.
    public let objectId: EUUID

    /// The many-valued feature to remove from.
    public let feature: any EStructuralFeature

    /// The value to remove.
    public let value: any EcoreValue

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
        super.init(bindingObjectID: object.id, resource: nil)
    }

    /// Creates a new remove command that edits a given resource.
    ///
    /// - Parameters:
    ///   - object: The EObject to modify
    ///   - feature: The many-valued structural feature to remove from
    ///   - value: The value to remove from the collection
    ///   - resource: The resource that holds the object
    public init(
        object: any EObject, feature: any EStructuralFeature, value: any EcoreValue,
        in resource: Resource
    ) {
        self.objectId = object.id
        self.feature = feature
        self.value = value
        super.init(bindingObjectID: object.id, resource: resource)
    }

    // MARK: - EMFCommand Implementation

    public override var description: String {
        return "Remove \(value) from \(feature.name)"
    }

    override func perform(on resource: Resource) async throws -> (result: EMFCommandResult, changes: [ResourceChange]) {
        guard let removal = try await resource.removeValue(objectId: objectId, feature: feature.name, value: value)
        else {
            throw ResourceEditError.valueNotFound(feature.name)
        }
        return (.success, removal.changes)
    }
}
