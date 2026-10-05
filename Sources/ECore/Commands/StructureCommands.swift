//
// StructureCommands.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

// MARK: - Move Command

/// Command to move a value within a feature, or to move an object into another container.
///
/// The reordering form changes the position of a value in a many-valued feature. The
/// re-parenting form moves an object into a containment reference of another object (or of
/// the same object), detaching it from its previous container. Undo and redo restore exact
/// snapshots.
@MainActor
public final class MoveCommand: ResourceEditCommand {

    private enum Plan {
        case reorder(from: Int, to: Int)
        case reparent(child: EUUID, at: Int?)
    }

    private let plan: Plan

    /// The object that is modified: the owner of the feature.
    public let objectId: EUUID

    /// The many-valued feature that receives the move.
    public let feature: any EStructuralFeature

    /// Creates a command that reorders a value within a many-valued feature.
    ///
    /// - Parameters:
    ///   - object: The object that owns the feature.
    ///   - feature: The many-valued feature.
    ///   - from: The current position of the value.
    ///   - to: The position the value takes.
    ///   - resource: The resource that holds the object, or `nil` to find it through an
    ///     editing domain.
    public init(
        object: any EObject, feature: any EStructuralFeature, from: Int, to: Int, in resource: Resource? = nil
    ) {
        self.objectId = object.id
        self.feature = feature
        self.plan = .reorder(from: from, to: to)
        super.init(bindingObjectID: object.id, resource: resource)
    }

    /// Creates a command that moves an object into a containment reference.
    ///
    /// - Parameters:
    ///   - child: The object to move.
    ///   - container: The object that receives it.
    ///   - reference: The many-valued containment reference of the container.
    ///   - index: The position to insert at, or `nil` to append.
    ///   - resource: The resource that holds the objects, or `nil` to find it through an
    ///     editing domain.
    public init(
        moving child: any EObject, to container: any EObject, reference: EReference,
        at index: Int? = nil, in resource: Resource? = nil
    ) {
        self.objectId = container.id
        self.feature = reference
        self.plan = .reparent(child: child.id, at: index)
        super.init(bindingObjectID: container.id, resource: resource)
    }

    public override var description: String {
        switch plan {
        case .reorder(let from, let to): return "Move \(feature.name) value from \(from) to \(to)"
        case .reparent: return "Move into \(feature.name)"
        }
    }

    override func perform(on resource: Resource) async throws -> (result: EMFCommandResult, changes: [ResourceChange]) {
        switch plan {
        case .reorder(let from, let to):
            return (.success, try await resource.eMove(objectId: objectId, feature: feature.name, from: from, to: to))
        case .reparent(let child, let index):
            return (.success, try await resource.eAdd(objectId: objectId, feature: feature.name, value: child, at: index))
        }
    }
}

// MARK: - Delete Command

/// Command to delete objects, together with their contents, from a resource.
///
/// References to the deleted objects are removed from the remaining objects unless reference
/// cleaning is turned off. Undo restores the deleted objects and the cleaned references
/// exactly.
@MainActor
public final class DeleteCommand: ResourceEditCommand {

    /// The identifiers of the objects to delete.
    public let objectIds: [EUUID]

    /// Whether references to the deleted objects are removed from the remaining objects.
    public let cleaningReferences: Bool

    /// Creates a command that deletes objects.
    ///
    /// - Parameters:
    ///   - objects: The objects to delete.
    ///   - cleaningReferences: Whether to remove references to them (default `true`).
    ///   - resource: The resource that holds the objects, or `nil` to find it through an
    ///     editing domain.
    public init(objects: [any EObject], cleaningReferences: Bool = true, in resource: Resource? = nil) {
        self.objectIds = objects.map(\.id)
        self.cleaningReferences = cleaningReferences
        super.init(bindingObjectID: objects.first?.id, resource: resource)
    }

    /// Creates a command that deletes one object.
    ///
    /// - Parameters:
    ///   - object: The object to delete.
    ///   - cleaningReferences: Whether to remove references to it (default `true`).
    ///   - resource: The resource that holds the object, or `nil` to find it through an
    ///     editing domain.
    public convenience init(object: any EObject, cleaningReferences: Bool = true, in resource: Resource? = nil) {
        self.init(objects: [object], cleaningReferences: cleaningReferences, in: resource)
    }

    public override var description: String {
        objectIds.count == 1 ? "Delete object" : "Delete \(objectIds.count) objects"
    }

    override func perform(on resource: Resource) async throws -> (result: EMFCommandResult, changes: [ResourceChange]) {
        for id in objectIds where !(await resource.contains(id: id)) {
            throw ResourceEditError.objectNotFound(id)
        }
        let changes = await resource.delete(objectIds, cleaningReferences: cleaningReferences)
        return (.success, changes)
    }
}

// MARK: - Create Child Command

/// Command to create a new instance of a class and add it to a model.
///
/// The instance is created through the factory, receives the default values of its features
/// (see ``EcoreDefaultValue``), and is added to a containment reference of an existing
/// object, or to the resource as a root object. Undo removes it again and redo restores the
/// same instance.
@MainActor
public final class CreateChildCommand: ResourceEditCommand {

    private enum Placement {
        case child(container: EUUID, reference: EReference, index: Int?)
        case root
    }

    private let placement: Placement
    private let eClass: EClass
    private let factory: EFactory?

    /// The class of the object to create.
    public var createdClass: EClass { eClass }

    /// The identifier of the created object, once the command has executed.
    public private(set) var createdID: EUUID?

    /// Creates a command that creates an object inside a container.
    ///
    /// - Parameters:
    ///   - container: The object that will contain the new object.
    ///   - reference: The containment reference to add it to.
    ///   - eClass: The class to instantiate.
    ///   - factory: The factory that creates the instance; one for the class is used if `nil`.
    ///   - index: The position within a many-valued reference, or `nil` to append.
    ///   - resource: The resource that holds the container, or `nil` to find it through an
    ///     editing domain.
    public init(
        container: any EObject, reference: EReference, eClass: EClass, factory: EFactory? = nil,
        index: Int? = nil, in resource: Resource? = nil
    ) {
        self.placement = .child(container: container.id, reference: reference, index: index)
        self.eClass = eClass
        self.factory = factory
        super.init(bindingObjectID: container.id, resource: resource)
    }

    /// Creates a command that creates a root object.
    ///
    /// - Parameters:
    ///   - eClass: The class to instantiate.
    ///   - factory: The factory that creates the instance; one for the class is used if `nil`.
    ///   - resource: The resource to add the new root object to.
    public init(rootClass eClass: EClass, factory: EFactory? = nil, in resource: Resource) {
        self.placement = .root
        self.eClass = eClass
        self.factory = factory
        super.init(bindingObjectID: nil, resource: resource)
    }

    public override var description: String {
        switch placement {
        case .child(_, let reference, _): return "Create \(eClass.name) in \(reference.name)"
        case .root: return "Create \(eClass.name)"
        }
    }

    override func perform(on resource: Resource) async throws -> (result: EMFCommandResult, changes: [ResourceChange]) {
        var object = (factory ?? Self.defaultFactory(for: eClass)).create(eClass)
        for feature in eClass.eAllStructuralFeatures {
            if let value = EcoreDefaultValue.value(for: feature) { object.eSet(feature, value) }
        }
        createdID = object.id
        switch placement {
        case .root:
            return (.created(object.id), await resource.eCreate(object))
        case .child(let container, let reference, let index):
            let changes: [ResourceChange]
            if reference.isMany {
                changes = try await resource.eAdd(objectId: container, feature: reference.name, value: object, at: index)
            } else {
                changes = try await resource.eSetWithChanges(objectId: container, feature: reference.name, value: object)
            }
            return (.created(object.id), changes)
        }
    }

    private static func defaultFactory(for eClass: EClass) -> EFactory {
        EFactory(ePackage: EPackage(name: eClass.name, nsURI: "", nsPrefix: ""))
    }
}
