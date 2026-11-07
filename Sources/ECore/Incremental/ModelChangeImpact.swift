//
// ModelChangeImpact.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// A summary of resource changes in the terms that ``ModelDependencies`` are recorded in.
///
/// An impact is computed from the ``ResourceChange`` values that editing operations report,
/// and tells incremental evaluators which recorded computations the changes may affect (see
/// ``ModelDependencies/isAffected(by:)`` and ``ModelDependencyIndex/dependents(affectedBy:)``).
///
/// Changes of a containment reference are recognised from the metamodel of the changed
/// object. When the class of a changed object cannot be found, for example because the
/// object was deleted by a later change of the same batch, a change whose values are object
/// identifiers is treated as a change of a containment reference, which errs on the side of
/// recomputation. Rebinding an object to another class makes the impact unbounded.
public struct ModelChangeImpact: Sendable, Equatable {
    /// The features whose values changed, by object and feature name.
    public private(set) var changedFeatures: Set<ModelFeatureKey> = []

    /// The objects that were changed in any way, created, deleted or rebound.
    public private(set) var touchedObjects: Set<EUUID> = []

    /// The objects that were deleted or rebound, so that every feature read from them is
    /// affected.
    public private(set) var replacedObjects: Set<EUUID> = []

    /// The objects that were created.
    public private(set) var createdObjects: Set<EUUID> = []

    /// The objects that were deleted.
    public private(set) var deletedObjects: Set<EUUID> = []

    /// The names of the classes whose sets of instances changed, including superclasses.
    public private(set) var affectedExtents: Set<String> = []

    /// The objects whose container changed, including deleted objects.
    public private(set) var movedObjects: Set<EUUID> = []

    /// Whether a containment reference changed or an object was created or deleted.
    public private(set) var changesContainmentStructure = false

    /// Whether the changes may affect every computation.
    public private(set) var isUnbounded = false

    /// Creates an impact of no changes.
    public init() {}

    /// An impact that affects every computation.
    public static var unbounded: ModelChangeImpact {
        var impact = ModelChangeImpact()
        impact.isUnbounded = true
        impact.changesContainmentStructure = true
        return impact
    }

    /// Whether the impact describes no change at all.
    public var isEmpty: Bool {
        !isUnbounded && touchedObjects.isEmpty && changedFeatures.isEmpty && affectedExtents.isEmpty
            && movedObjects.isEmpty && !changesContainmentStructure
    }

    /// Computes the impact of changes made to resources.
    ///
    /// The resources are consulted, in order, for the classes of the changed objects. They
    /// should hold the objects in their state after the changes.
    ///
    /// - Parameters:
    ///   - changes: The changes, in the order in which they were made.
    ///   - resources: The resources that the changes were made to.
    public init(changes: [ResourceChange], in resources: [Resource]) async {
        var classes: [EUUID: EClass] = [:]
        for change in changes {
            switch change.kind {
            case .create:
                if let eClass = (change.newValue as? any EObject)?.eClass as? EClass { classes[change.objectID] = eClass }
            case .delete:
                if let eClass = (change.oldValue as? any EObject)?.eClass as? EClass { classes[change.objectID] = eClass }
            default:
                break
            }
        }
        for change in changes where classes[change.objectID] == nil && change.feature != nil {
            for resource in resources {
                if let eClass = await resource.resolve(change.objectID)?.eClass as? EClass {
                    classes[change.objectID] = eClass
                    break
                }
            }
        }
        self.init()
        for change in changes { add(change, objectClass: classes[change.objectID]) }
    }

    /// Adds one change to the impact.
    ///
    /// - Parameters:
    ///   - change: The change to add.
    ///   - objectClass: The class of the changed object, if known. Without it, a change whose
    ///     values are object identifiers counts as a change of a containment reference.
    public mutating func add(_ change: ResourceChange, objectClass: EClass?) {
        touchedObjects.insert(change.objectID)
        switch change.kind {
        case .create:
            createdObjects.insert(change.objectID)
            changesContainmentStructure = true
            addExtents(of: objectClass)
            if objectClass == nil { isUnbounded = true }
        case .delete:
            deletedObjects.insert(change.objectID)
            replacedObjects.insert(change.objectID)
            movedObjects.insert(change.objectID)
            changesContainmentStructure = true
            addExtents(of: objectClass)
            if objectClass == nil { isUnbounded = true }
        case .rebind:
            replacedObjects.insert(change.objectID)
            isUnbounded = true
        case .set, .add, .remove, .move:
            guard let feature = change.feature else {
                isUnbounded = true
                return
            }
            changedFeatures.insert(ModelFeatureKey(objectID: change.objectID, feature: feature))
            let containment: Bool
            if let objectClass {
                containment = (objectClass.getStructuralFeature(name: feature) as? EReference)?.containment ?? false
            } else {
                containment = !Self.identifiers(change.oldValue).isEmpty || !Self.identifiers(change.newValue).isEmpty
            }
            guard containment else { return }
            changesContainmentStructure = true
            guard change.kind != .move else { return }
            movedObjects.formUnion(Self.identifiers(change.oldValue))
            movedObjects.formUnion(Self.identifiers(change.newValue))
        }
    }

    /// Adds the effects of other changes to this impact.
    ///
    /// - Parameter other: The impact of the other changes.
    public mutating func formUnion(_ other: ModelChangeImpact) {
        changedFeatures.formUnion(other.changedFeatures)
        touchedObjects.formUnion(other.touchedObjects)
        replacedObjects.formUnion(other.replacedObjects)
        createdObjects.formUnion(other.createdObjects)
        deletedObjects.formUnion(other.deletedObjects)
        affectedExtents.formUnion(other.affectedExtents)
        movedObjects.formUnion(other.movedObjects)
        changesContainmentStructure = changesContainmentStructure || other.changesContainmentStructure
        isUnbounded = isUnbounded || other.isUnbounded
    }

    /// Adds the names of a class and of all its superclasses to the affected extents.
    private mutating func addExtents(of eClass: EClass?) {
        guard let eClass else { return }
        affectedExtents.insert(eClass.name)
        for superType in eClass.allSuperTypes { affectedExtents.insert(superType.name) }
    }

    /// The object identifiers held by a change value.
    private static func identifiers(_ value: (any EcoreValue)?) -> [EUUID] {
        guard let value else { return [] }
        if let object = value as? any EObject { return [object.id] }
        if let ids = value as? [EUUID] { return ids }
        if let array = value as? EcoreValueArray {
            return array.values.flatMap { identifiers($0) }
        }
        if let id = value as? EUUID { return [id] }
        return []
    }
}
