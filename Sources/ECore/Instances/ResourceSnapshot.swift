//
// ResourceSnapshot.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation
import OrderedCollections

/// An immutable copy of the objects of a resource at one moment.
///
/// A snapshot is a value that can be read from any isolation domain. Copying it takes
/// constant time, because the underlying storage is shared until the resource is edited, so
/// snapshots serve both for exact undo and for synchronous reads by view models.
public struct ResourceSnapshot: Sendable {
    /// The URI of the resource that the snapshot was taken from.
    public let uri: String

    let storage: OrderedDictionary<EUUID, any EObject>
    let rootIdentifiers: [EUUID]
    let nativeContents: OrderedDictionary<EUUID, any EObject>
    let nativeContainers: [EUUID: EUUID]
    let nativeOwned: [EUUID: [EUUID]]

    init(
        uri: String, storage: OrderedDictionary<EUUID, any EObject>, rootIdentifiers: [EUUID],
        nativeContents: OrderedDictionary<EUUID, any EObject>,
        nativeContainers: [EUUID: EUUID], nativeOwned: [EUUID: [EUUID]]
    ) {
        self.uri = uri
        self.storage = storage
        self.rootIdentifiers = rootIdentifiers
        self.nativeContents = nativeContents
        self.nativeContainers = nativeContainers
        self.nativeOwned = nativeOwned
    }

    /// All objects, in the order in which the resource holds them.
    public var objects: [any EObject] { Array(storage.values) }

    /// The identifiers of the root objects, in order.
    public var rootIDs: [EUUID] { rootIdentifiers }

    /// The root objects, in order.
    public var roots: [any EObject] { rootIdentifiers.compactMap { storage[$0] } }

    /// The number of objects.
    public var count: Int { storage.count }

    /// Finds an object by identifier.
    ///
    /// - Parameter id: The identifier to look up.
    /// - Returns: The object, or `nil` if the snapshot holds none with that identifier.
    public func object(id: EUUID) -> (any EObject)? { storage[id] ?? nativeContents[id] }

    /// Whether the snapshot holds an object with the identifier.
    ///
    /// - Parameter id: The identifier to look up.
    public func contains(id: EUUID) -> Bool { object(id: id) != nil }

    /// Reads a feature value of an object by feature name.
    ///
    /// - Parameters:
    ///   - id: The identifier of the object.
    ///   - feature: The name of the feature.
    /// - Returns: The stored value, or `nil` if the object or value is missing.
    public func value(of id: EUUID, feature: String) -> (any EcoreValue)? {
        (storage[id] as? DynamicEObject)?.eGet(feature)
    }

    /// The identifiers of the objects that an object refers to through a reference.
    ///
    /// - Parameters:
    ///   - object: The referring object.
    ///   - reference: The reference to read.
    /// - Returns: The identifiers of the targets, in order.
    public func targets(of object: any EObject, _ reference: EReference) -> [EUUID] {
        ReferenceValues.identifiers(object.eGet(reference))
    }

    /// The objects directly contained by an object, in containment feature order.
    ///
    /// - Parameter object: The containing object.
    /// - Returns: The contained objects that the snapshot holds.
    public func contents(of object: any EObject) -> [any EObject] {
        guard let eClass = object.eClass as? EClass else { return [] }
        return eClass.eAllReferences.filter(\.containment).flatMap { reference in
            targets(of: object, reference).compactMap { storage[$0] }
        }
    }

    /// All objects contained by an object, transitively and depth first.
    ///
    /// - Parameter object: The containing object.
    /// - Returns: The contained objects.
    public func allContents(of object: any EObject) -> [any EObject] {
        var result: [any EObject] = []
        var visited: Set<EUUID> = [object.id]
        func collect(_ parent: any EObject) {
            for child in contents(of: parent) where visited.insert(child.id).inserted {
                result.append(child)
                collect(child)
            }
        }
        collect(object)
        return result
    }

    /// The containing object and containment feature of every contained object.
    ///
    /// Building the index takes time proportional to the size of the snapshot, so callers
    /// that look up many objects should build it once.
    ///
    /// - Returns: A dictionary from the identifier of each contained object to its container
    ///   and the name of the containment feature.
    public func containmentIndex() -> [EUUID: (container: EUUID, feature: String)] {
        var index: [EUUID: (container: EUUID, feature: String)] = [:]
        for object in storage.values {
            guard let eClass = object.eClass as? EClass else { continue }
            for reference in eClass.eAllReferences where reference.containment {
                for id in targets(of: object, reference) {
                    index[id] = (object.id, reference.name)
                }
            }
        }
        return index
    }

    /// The container of an object.
    ///
    /// - Parameter object: The contained object.
    /// - Returns: The container, or `nil` for roots and unknown objects.
    public func container(of object: any EObject) -> (any EObject)? {
        guard let slot = containmentIndex()[object.id] else { return nil }
        return storage[slot.container]
    }
}

/// Helpers for reading reference values, which hold identifiers or, across resources, proxies.
enum ReferenceValues {
    /// The identifiers held by a reference value.
    static func identifiers(_ value: (any EcoreValue)?) -> [EUUID] {
        guard let value else { return [] }
        if let id = value as? EUUID { return [id] }
        if let ids = value as? [EUUID] { return ids }
        if let array = value as? EcoreValueArray { return array.values.flatMap { identifiers($0) } }
        return []
    }
}

/// Helpers for reading and rebuilding many-valued feature values.
enum ValueList {
    /// The elements of a many-valued feature value.
    static func elements(of value: (any EcoreValue)?) -> [any EcoreValue] {
        guard let value else { return [] }
        if let array = value as? EcoreValueArray { return array.values }
        if let array = value as? [any EcoreValue] { return array }
        return []
    }

    /// Rebuilds a value of the same array type as a template from elements.
    static func make(_ elements: [any EcoreValue], like template: (any EcoreValue)?) -> any EcoreValue {
        if template is EcoreValueArray { return EcoreValueArray(elements) }
        if let first = elements.first {
            if elements.allSatisfy({ type(of: $0) == type(of: first) }) {
                return typed(first, from: elements)
            }
            return EcoreValueArray(elements)
        }
        return empty(like: template)
    }

    private static func typed<T: EcoreValue>(_ sample: T, from elements: [any EcoreValue]) -> any EcoreValue {
        elements.compactMap { $0 as? T }
    }

    private static func empty(like template: (any EcoreValue)?) -> any EcoreValue {
        switch template {
        case is [String]: return [String]()
        case is [Int]: return [Int]()
        case is [Bool]: return [Bool]()
        case is [Double]: return [Double]()
        case is [Float]: return [Float]()
        case is [Int8]: return [Int8]()
        case is [Int16]: return [Int16]()
        case is [Int64]: return [Int64]()
        case is [Character]: return [Character]()
        case is [Date]: return [Date]()
        case is [Decimal]: return [Decimal]()
        default: return [EUUID]()
        }
    }
}
