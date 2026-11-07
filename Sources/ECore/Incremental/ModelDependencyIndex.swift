//
// ModelDependencyIndex.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// A reverse index from model parts to the computations that read them.
///
/// Incremental evaluators keep one ``ModelDependencies`` record per computation, such as a
/// query, a rule guard for a tuple of elements, or a binding of a target element. The index
/// answers which of these computations a set of changes affects in time proportional to the
/// size of the changes rather than to the number of computations, as the indexes of
/// incremental pattern matchers do.
///
/// ```swift
/// var index = ModelDependencyIndex<String>()
/// index.insert(dependencies, for: "fullName of Jim")
/// let stale = index.dependents(affectedBy: impact)
/// ```
public struct ModelDependencyIndex<Dependent: Hashable & Sendable>: Sendable {
    /// The record of each computation.
    private var records: [Dependent: ModelDependencies] = [:]

    /// The computations that read each feature.
    private var byFeature: [ModelFeatureKey: Set<Dependent>] = [:]

    /// The computations that read features of each object, by object.
    private var byFeatureObject: [EUUID: Set<Dependent>] = [:]

    /// The computations that read any part of each object.
    private var byObject: [EUUID: Set<Dependent>] = [:]

    /// The computations that enumerated the instances of each class.
    private var byExtent: [String: Set<Dependent>] = [:]

    /// The computations that read the container of each object.
    private var byContainer: [EUUID: Set<Dependent>] = [:]

    /// The computations that depend on the containment structure as a whole.
    private var structural: Set<Dependent> = []

    /// The computations that every change affects.
    private var unbounded: Set<Dependent> = []

    /// The total number of parts named by the records of all computations.
    ///
    /// It is the number of entries that the index keeps, summed over the
    /// ``ModelDependencies/count`` of every record.
    public private(set) var entryCount = 0

    /// Creates an empty index.
    public init() {}

    /// The number of computations in the index.
    public var count: Int { records.count }

    /// Whether the index holds no computation.
    public var isEmpty: Bool { records.isEmpty }

    /// The computations in the index.
    public var dependents: Dictionary<Dependent, ModelDependencies>.Keys { records.keys }

    /// The record of a computation.
    ///
    /// - Parameter dependent: The computation.
    /// - Returns: Its dependencies, or `nil` if the index does not hold it.
    public func dependencies(of dependent: Dependent) -> ModelDependencies? {
        records[dependent]
    }

    /// Records the dependencies of a computation, replacing any earlier record of it.
    ///
    /// - Parameters:
    ///   - dependencies: What the computation read.
    ///   - dependent: The computation.
    public mutating func insert(_ dependencies: ModelDependencies, for dependent: Dependent) {
        remove(dependent)
        records[dependent] = dependencies
        entryCount += dependencies.count
        for key in dependencies.features {
            byFeature[key, default: []].insert(dependent)
            byFeatureObject[key.objectID, default: []].insert(dependent)
        }
        for id in dependencies.objects { byObject[id, default: []].insert(dependent) }
        for name in dependencies.extents { byExtent[name, default: []].insert(dependent) }
        for id in dependencies.containers { byContainer[id, default: []].insert(dependent) }
        if dependencies.readsContainmentStructure { structural.insert(dependent) }
        if dependencies.isUnbounded { unbounded.insert(dependent) }
    }

    /// Removes a computation from the index.
    ///
    /// - Parameter dependent: The computation.
    /// - Returns: The record that the index held for it, if any.
    @discardableResult
    public mutating func remove(_ dependent: Dependent) -> ModelDependencies? {
        guard let old = records.removeValue(forKey: dependent) else { return nil }
        entryCount -= old.count
        for key in old.features {
            Self.remove(dependent, at: key, from: &byFeature)
            Self.remove(dependent, at: key.objectID, from: &byFeatureObject)
        }
        for id in old.objects { Self.remove(dependent, at: id, from: &byObject) }
        for name in old.extents { Self.remove(dependent, at: name, from: &byExtent) }
        for id in old.containers { Self.remove(dependent, at: id, from: &byContainer) }
        if old.readsContainmentStructure { structural.remove(dependent) }
        if old.isUnbounded { unbounded.remove(dependent) }
        return old
    }

    /// Removes every computation from the index.
    public mutating func removeAll() {
        self = ModelDependencyIndex()
    }

    /// Finds the computations that changes may affect.
    ///
    /// A computation is affected under the same conditions as
    /// ``ModelDependencies/isAffected(by:)`` describes.
    ///
    /// - Parameter impact: The summary of the changes.
    /// - Returns: The affected computations.
    public func dependents(affectedBy impact: ModelChangeImpact) -> Set<Dependent> {
        if impact.isEmpty { return [] }
        if impact.isUnbounded { return Set(records.keys) }
        var result = unbounded
        if impact.changesContainmentStructure { result.formUnion(structural) }
        for key in impact.changedFeatures {
            if let found = byFeature[key] { result.formUnion(found) }
        }
        for id in impact.replacedObjects {
            if let found = byFeatureObject[id] { result.formUnion(found) }
        }
        for id in impact.touchedObjects {
            if let found = byObject[id] { result.formUnion(found) }
        }
        for name in impact.affectedExtents {
            if let found = byExtent[name] { result.formUnion(found) }
        }
        for id in impact.movedObjects {
            if let found = byContainer[id] { result.formUnion(found) }
        }
        return result
    }

    /// Removes one computation from the set held under a key, dropping empty sets.
    private static func remove<Key: Hashable>(
        _ dependent: Dependent, at key: Key, from table: inout [Key: Set<Dependent>]
    ) {
        guard table[key]?.remove(dependent) != nil else { return }
        if table[key]?.isEmpty == true { table[key] = nil }
    }
}
