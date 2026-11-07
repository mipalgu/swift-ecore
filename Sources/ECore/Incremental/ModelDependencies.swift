//
// ModelDependencies.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// A feature of a particular object, the unit of a fine-grained model read.
public struct ModelFeatureKey: Hashable, Sendable, CustomStringConvertible {
    /// The identifier of the object whose feature was read.
    public let objectID: EUUID

    /// The name of the feature that was read.
    public let feature: String

    /// Creates a key for a feature of an object.
    ///
    /// - Parameters:
    ///   - objectID: The identifier of the object.
    ///   - feature: The name of the feature.
    public init(objectID: EUUID, feature: String) {
        self.objectID = objectID
        self.feature = feature
    }

    /// A description of the key, naming the object and the feature.
    public var description: String { "\(objectID.uuidString).\(feature)" }
}

/// The parts of the models that a computation read, so that it can be redone when they change.
///
/// Incremental evaluators record what a query, guard or binding reads while it is evaluated,
/// in the manner of the dependency tracking of incremental query engines such as
/// VIATRA/IncQuery and NMF Expressions. The record distinguishes:
///
/// - **Features**: a feature of an object was read (``ModelFeatureKey``). A change of that
///   feature, or the deletion or rebinding of the object, affects the computation.
/// - **Objects**: everything about an object may have been read, such as its contents. Any
///   change of the object affects the computation.
/// - **Extents**: the instances of a class were enumerated (by class name, as `allInstances`
///   does). Creating, deleting or rebinding an instance of the class or of a subclass
///   affects the computation.
/// - **Containers**: the container of an object was read. Moving the object to another
///   container, or out of one, affects the computation.
/// - **Containment structure**: the computation depends on the arrangement of the whole
///   containment tree, such as the order of all contents or a positional path. Any change of
///   a containment reference, and any creation or deletion, affects it.
/// - **Unbounded**: the computation read something that cannot be described more precisely,
///   so every change affects it.
///
/// A record over-approximates what a computation depends on: it may name parts whose
/// change turns out not to alter the result, but it never omits a part that could.
public struct ModelDependencies: Sendable, Equatable {
    /// The features read, by object and feature name.
    public private(set) var features: Set<ModelFeatureKey> = []

    /// The objects any part of which may have been read.
    public private(set) var objects: Set<EUUID> = []

    /// The names of the classes whose instances were enumerated.
    public private(set) var extents: Set<String> = []

    /// The objects whose container was read.
    public private(set) var containers: Set<EUUID> = []

    /// Whether the computation depends on the containment structure as a whole.
    public private(set) var readsContainmentStructure = false

    /// Whether every change affects the computation.
    public private(set) var isUnbounded = false

    /// Creates an empty record.
    public init() {}

    /// The number of parts that the record names.
    ///
    /// Each feature, object, extent and container counts once, and a dependency on the
    /// containment structure or on everything counts once more.
    public var count: Int {
        features.count + objects.count + extents.count + containers.count
            + (readsContainmentStructure ? 1 : 0) + (isUnbounded ? 1 : 0)
    }

    /// Whether the record names nothing, so that no change affects the computation.
    public var isEmpty: Bool {
        features.isEmpty && objects.isEmpty && extents.isEmpty && containers.isEmpty
            && !readsContainmentStructure && !isUnbounded
    }

    /// Records the read of a feature of an object.
    ///
    /// - Parameters:
    ///   - feature: The name of the feature.
    ///   - objectID: The identifier of the object.
    public mutating func recordFeature(_ feature: String, of objectID: EUUID) {
        features.insert(ModelFeatureKey(objectID: objectID, feature: feature))
    }

    /// Records that any part of an object may have been read.
    ///
    /// - Parameter objectID: The identifier of the object.
    public mutating func recordObject(_ objectID: EUUID) {
        objects.insert(objectID)
    }

    /// Records the enumeration of the instances of a class.
    ///
    /// - Parameter className: The name of the class.
    public mutating func recordExtent(_ className: String) {
        extents.insert(className)
    }

    /// Records the read of the container of an object.
    ///
    /// - Parameter objectID: The identifier of the contained object.
    public mutating func recordContainer(of objectID: EUUID) {
        containers.insert(objectID)
    }

    /// Records a dependency on the containment structure as a whole.
    public mutating func recordContainmentStructure() {
        readsContainmentStructure = true
    }

    /// Records that every change affects the computation.
    public mutating func recordUnbounded() {
        isUnbounded = true
    }

    /// Adds the dependencies of another record to this one.
    ///
    /// - Parameter other: The record to add.
    public mutating func formUnion(_ other: ModelDependencies) {
        features.formUnion(other.features)
        objects.formUnion(other.objects)
        extents.formUnion(other.extents)
        containers.formUnion(other.containers)
        readsContainmentStructure = readsContainmentStructure || other.readsContainmentStructure
        isUnbounded = isUnbounded || other.isUnbounded
    }

    /// The union of this record and another.
    ///
    /// - Parameter other: The record to add.
    /// - Returns: A record naming the dependencies of both.
    public func union(_ other: ModelDependencies) -> ModelDependencies {
        var result = self
        result.formUnion(other)
        return result
    }

    /// Decides whether changes described by an impact may alter the computation.
    ///
    /// - Parameter impact: The summary of the changes.
    /// - Returns: `true` if some part that the computation read was changed.
    public func isAffected(by impact: ModelChangeImpact) -> Bool {
        if impact.isEmpty { return false }
        if isUnbounded || impact.isUnbounded { return true }
        if readsContainmentStructure && impact.changesContainmentStructure { return true }
        if !impact.changedFeatures.isEmpty {
            if features.count <= impact.changedFeatures.count {
                if features.contains(where: impact.changedFeatures.contains) { return true }
            } else if impact.changedFeatures.contains(where: features.contains) {
                return true
            }
        }
        if !impact.replacedObjects.isEmpty,
            features.contains(where: { impact.replacedObjects.contains($0.objectID) })
        {
            return true
        }
        if !objects.isDisjoint(with: impact.touchedObjects) { return true }
        if !extents.isDisjoint(with: impact.affectedExtents) { return true }
        if !containers.isDisjoint(with: impact.movedObjects) { return true }
        return false
    }
}
