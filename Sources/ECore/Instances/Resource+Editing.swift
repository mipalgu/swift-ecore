//
// Resource+Editing.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation
import OrderedCollections

/// The outcome of re-pointing the objects of a resource at a new set of metamodels.
public struct RebindReport: Sendable, Equatable {
    /// The number of objects that now refer to a class of the new metamodels.
    public let rebound: Int

    /// The identifiers of objects whose class has no counterpart in the new metamodels.
    ///
    /// Such objects keep their previous class.
    public let unmatched: [EUUID]

    /// Creates a report.
    ///
    /// - Parameters:
    ///   - rebound: The number of rebound objects.
    ///   - unmatched: The identifiers of objects without a counterpart class.
    public init(rebound: Int, unmatched: [EUUID]) {
        self.rebound = rebound
        self.unmatched = unmatched
    }
}

/// A reference from one object to another, found by ``Resource/inverseReferences(to:)``.
public typealias InverseReference = (source: EUUID, feature: String)

extension Resource {

    // MARK: - Snapshots and recording

    /// Captures the current state of the resource.
    ///
    /// Taking a snapshot takes constant time. The snapshot is unaffected by later edits and
    /// can be given to ``restore(_:)`` to return the resource to this state exactly.
    ///
    /// - Returns: The snapshot.
    public func snapshot() -> ResourceSnapshot {
        ResourceSnapshot(
            uri: uri, storage: objects, rootIdentifiers: rootObjects,
            nativeContents: nativeContents, nativeContainers: nativeContainers,
            nativeOwned: nativeOwned)
    }

    /// Returns the resource to the state captured by a snapshot.
    ///
    /// Objects, their values, and the order of objects and roots are all restored exactly.
    ///
    /// - Parameter snapshot: A snapshot of this resource.
    public func restore(_ snapshot: ResourceSnapshot) {
        objects = snapshot.storage
        rootObjects = snapshot.rootIdentifiers
        nativeContents = snapshot.nativeContents
        nativeContainers = snapshot.nativeContainers
        nativeOwned = snapshot.nativeOwned
    }

    /// Runs operations on the resource and collects the changes that they make.
    ///
    /// Every change made by the editing operations of this resource while the body runs is
    /// returned, in order, together with the body's result.
    ///
    /// - Parameter body: The operations to run, isolated to this resource.
    /// - Returns: The body's result and the changes made.
    /// - Throws: Whatever the body throws; the changes made before the error are discarded.
    public func recordingChanges<T: Sendable>(
        _ body: @Sendable (isolated Resource) async throws -> T
    ) async rethrows -> (value: T, changes: [ResourceChange]) {
        let outer = changeJournal
        changeJournal = []
        defer { changeJournal = outer }
        let value = try await body(self)
        return (value, changeJournal ?? [])
    }

    // MARK: - Feature editing

    /// Sets a feature of a dynamic object and reports the changes.
    ///
    /// Opposite references are maintained, and a contained value is detached from its
    /// previous container.
    ///
    /// - Parameters:
    ///   - objectId: The identifier of the object to modify.
    ///   - featureName: The name of the feature to set.
    ///   - value: The new value; objects stand for their identifiers.
    /// - Returns: The changes made, empty if the value was already set.
    /// - Throws: ``ResourceEditError`` if the object or feature is unknown or the value
    ///   would make an object contain itself.
    @discardableResult
    public func eSetWithChanges(
        objectId: EUUID, feature featureName: String, value: (any EcoreValue)?
    ) async throws -> [ResourceChange] {
        let object = try editable(objectId)
        let feature = try structuralFeature(named: featureName, of: object)
        var changes: [ResourceChange] = []
        guard let reference = feature as? EReference else {
            if let change = store(objectId, feature, value) { changes.append(change) }
            return record(changes)
        }
        let newValue = try normalised(value, many: reference.isMany, &changes)
        let old = ReferenceValues.identifiers(object.eGet(reference))
        let new = ReferenceValues.identifiers(newValue)
        let added = new.filter { !old.contains($0) }
        let removed = old.filter { !new.contains($0) }
        if reference.containment {
            for id in added { try checkAcyclic(container: objectId, child: id) }
        }
        for id in removed {
            await link(reference, source: objectId, target: id, add: false, &changes)
        }
        if reference.containment {
            for id in added { await detach(id, &changes) }
        }
        if let change = store(objectId, reference, newValue) { changes.append(change) }
        if reference.containment { removed.forEach(orphan) }
        for id in added { await link(reference, source: objectId, target: id, add: true, &changes) }
        return record(changes)
    }

    /// Inserts a value into a many-valued feature of a dynamic object.
    ///
    /// Opposite references are maintained. Adding to a containment reference detaches the
    /// value from its previous container, so the same call re-parents an object.
    ///
    /// - Parameters:
    ///   - objectId: The identifier of the object to modify.
    ///   - featureName: The name of the many-valued feature.
    ///   - value: The value to add; objects stand for their identifiers, and objects that the
    ///     resource does not hold yet are added to it.
    ///   - index: The position to insert at; the end by default.
    /// - Returns: The changes made.
    /// - Throws: ``ResourceEditError`` if the object or feature is unknown, the feature is
    ///   not many-valued, the position is out of range, a duplicate is not allowed, or the
    ///   addition would make an object contain itself.
    @discardableResult
    public func eAdd(
        objectId: EUUID, feature featureName: String, value: any EcoreValue, at index: Int? = nil
    ) async throws -> [ResourceChange] {
        let object = try editable(objectId)
        let feature = try structuralFeature(named: featureName, of: object)
        guard feature.manyValued else { throw ResourceEditError.notMultiValued(featureName) }
        var changes: [ResourceChange] = []
        var element = value
        let reference = feature as? EReference
        if let reference, let id = try referenceTarget(value, &changes) {
            element = id
            if reference.containment {
                try checkAcyclic(container: objectId, child: id)
                await detach(id, &changes)
            } else if reference.unique, contains(try editable(objectId), feature, element) {
                throw ResourceEditError.duplicateValue(featureName)
            }
        } else if reference != nil, !(value is ResourceProxy) {
            throw ResourceEditError.invalidValue(featureName)
        } else if feature.uniqueValued, contains(try editable(objectId), feature, element) {
            throw ResourceEditError.duplicateValue(featureName)
        }
        let current = try editable(objectId).eGet(feature)
        var list = ValueList.elements(of: current)
        let position = index ?? list.count
        guard position >= 0, position <= list.count else { throw ResourceEditError.indexOutOfRange(position) }
        list.insert(element, at: position)
        store(objectId, feature, ValueList.make(list, like: current ?? EcoreDefaultValue.value(for: feature)))
        changes.append(
            ResourceChange(kind: .add, objectID: objectId, feature: featureName, newValue: element, index: position))
        if let reference, let id = element as? EUUID {
            await link(reference, source: objectId, target: id, add: true, &changes)
        }
        return record(changes)
    }

    /// Removes a value from a many-valued feature of a dynamic object.
    ///
    /// Opposite references are maintained. An object removed from a containment reference
    /// stays in the resource as a root object.
    ///
    /// - Parameters:
    ///   - objectId: The identifier of the object to modify.
    ///   - featureName: The name of the many-valued feature.
    ///   - value: The value to remove; objects stand for their identifiers.
    /// - Returns: The position that the value had, or `nil` if the value was not present.
    /// - Throws: ``ResourceEditError`` if the object or feature is unknown or the feature
    ///   is not many-valued.
    @discardableResult
    public func eRemove(objectId: EUUID, feature featureName: String, value: any EcoreValue) async throws -> Int? {
        try await removeValue(objectId: objectId, feature: featureName, value: value)?.index
    }

    /// Removes a value from a many-valued feature and reports the changes.
    ///
    /// - Parameters:
    ///   - objectId: The identifier of the object to modify.
    ///   - featureName: The name of the many-valued feature.
    ///   - value: The value to remove; objects stand for their identifiers.
    /// - Returns: The position that the value had and the changes made, or `nil` if the
    ///   value was not present.
    /// - Throws: ``ResourceEditError`` if the object or feature is unknown or the feature
    ///   is not many-valued.
    public func removeValue(
        objectId: EUUID, feature featureName: String, value: any EcoreValue
    ) async throws -> (index: Int, changes: [ResourceChange])? {
        let object = try editable(objectId)
        let feature = try structuralFeature(named: featureName, of: object)
        guard feature.manyValued else { throw ResourceEditError.notMultiValued(featureName) }
        let reference = feature as? EReference
        let needle: any EcoreValue = reference != nil ? ((value as? any EObject)?.id ?? value) : value
        let current = object.eGet(feature)
        var list = ValueList.elements(of: current)
        guard let position = list.firstIndex(where: { areEqual($0, needle) }) else { return nil }
        let removed = list.remove(at: position)
        store(objectId, feature, ValueList.make(list, like: current))
        var changes = [
            ResourceChange(kind: .remove, objectID: objectId, feature: featureName, oldValue: removed, index: position)
        ]
        if let reference, let id = removed as? EUUID {
            await link(reference, source: objectId, target: id, add: false, &changes)
            if reference.containment { orphan(id) }
        }
        return (position, record(changes))
    }

    /// Moves a value to another position within a many-valued feature.
    ///
    /// - Parameters:
    ///   - objectId: The identifier of the object to modify.
    ///   - featureName: The name of the many-valued feature.
    ///   - from: The current position of the value.
    ///   - to: The position that the value takes once moved.
    /// - Returns: The changes made, empty if the positions are equal.
    /// - Throws: ``ResourceEditError`` if the object or feature is unknown, the feature is
    ///   not many-valued, or a position is out of range.
    @discardableResult
    public func eMove(objectId: EUUID, feature featureName: String, from: Int, to: Int) async throws -> [ResourceChange] {
        let object = try editable(objectId)
        let feature = try structuralFeature(named: featureName, of: object)
        guard feature.manyValued else { throw ResourceEditError.notMultiValued(featureName) }
        let current = object.eGet(feature)
        var list = ValueList.elements(of: current)
        guard list.indices.contains(from) else { throw ResourceEditError.indexOutOfRange(from) }
        guard list.indices.contains(to) else { throw ResourceEditError.indexOutOfRange(to) }
        guard from != to else { return [] }
        let element = list.remove(at: from)
        list.insert(element, at: to)
        store(objectId, feature, ValueList.make(list, like: current))
        return record([
            ResourceChange(
                kind: .move, objectID: objectId, feature: featureName, oldValue: element, newValue: element,
                index: to, oldIndex: from)
        ])
    }

    // MARK: - References

    /// Finds the references that point at an object.
    ///
    /// - Parameter id: The identifier of the target object.
    /// - Returns: The referring objects and the names of the referring features, in object
    ///   order. Containment references are included.
    public func inverseReferences(to id: EUUID) -> [InverseReference] {
        var result: [InverseReference] = []
        for object in objects.values {
            guard let eClass = object.eClass as? EClass else { continue }
            for reference in eClass.eAllReferences
            where ReferenceValues.identifiers(object.eGet(reference)).contains(id) {
                result.append((object.id, reference.name))
            }
        }
        return result
    }

    /// Deletes objects together with everything they contain.
    ///
    /// Each object is detached from its container and removed from the resource along with
    /// its contained objects. With reference cleaning, references from the remaining
    /// objects to any deleted object are removed too, so none dangles.
    ///
    /// - Parameters:
    ///   - ids: The identifiers of the objects to delete; unknown identifiers are ignored.
    ///   - cleaningReferences: Whether to remove references to the deleted objects.
    /// - Returns: The changes made.
    @discardableResult
    public func delete(_ ids: [EUUID], cleaningReferences: Bool = true) async -> [ResourceChange] {
        var doomed = OrderedSet<EUUID>()
        for id in ids where objects[id] != nil { doomed.formUnion(subtree(of: id)) }
        guard !doomed.isEmpty else { return [] }
        var changes: [ResourceChange] = []
        for id in doomed {
            if let slot = findContainer(of: id), !doomed.contains(slot.container) {
                await detach(id, &changes, unlinking: false)
            }
            rootObjects.removeAll { $0 == id }
        }
        if cleaningReferences {
            for object in Array(objects.values) where !doomed.contains(object.id) {
                guard let eClass = object.eClass as? EClass else { continue }
                for reference in eClass.eAllReferences {
                    changes.append(contentsOf: removeReferences(to: doomed, from: object.id, reference))
                }
            }
        }
        for id in doomed {
            guard let object = objects[id] else { continue }
            changes.append(ResourceChange(kind: .delete, objectID: id, oldValue: object))
            objects.removeValue(forKey: id)
            rootObjects.removeAll { $0 == id }
        }
        return record(changes)
    }

    // MARK: - Metamodel changes

    /// Re-points the objects of the resource at the classes of edited metamodels.
    ///
    /// Each dynamic object receives the class of the new metamodels that matches its
    /// current class by identifier or, failing that, by the namespace URI of its package
    /// and its name. Values are carried over by feature identifier or, failing that, by
    /// name.
    ///
    /// - Parameters:
    ///   - packages: The new metamodels.
    ///   - previous: The metamodels that the objects' classes belong to now, used to find
    ///     the package of a class. If a class's package is unknown, a class name that is
    ///     unique among the new metamodels matches.
    /// - Returns: How many objects were rebound and which found no counterpart.
    @discardableResult
    public func rebind(to packages: [EPackage], from previous: [EPackage] = []) -> RebindReport {
        let target = ClassCatalogue(packages)
        let old = ClassCatalogue(previous)
        var rebound = 0
        var unmatched: [EUUID] = []
        var changes: [ResourceChange] = []
        for case let object as DynamicEObject in Array(objects.values) {
            let oldClass = object.eClass
            let key = old.packageURI[oldClass.id].map { "\($0)#\(oldClass.name)" }
            let match =
                target.byID[oldClass.id] ?? key.flatMap { target.byKey[$0] }
                ?? (target.byName[oldClass.name]?.count == 1 ? target.byName[oldClass.name]?.first : nil)
            guard let newClass = match else {
                unmatched.append(object.id)
                continue
            }
            objects[object.id] = Self.migrated(object, to: newClass)
            changes.append(ResourceChange(kind: .rebind, objectID: object.id, oldValue: oldClass.eReferenceName, newValue: newClass.eReferenceName))
            rebound += 1
        }
        _ = record(changes)
        return RebindReport(rebound: rebound, unmatched: unmatched)
    }

    // MARK: - Private helpers

    private func record(_ changes: [ResourceChange]) -> [ResourceChange] {
        if changeJournal != nil { changeJournal?.append(contentsOf: changes) }
        return changes
    }

    private func editable(_ id: EUUID) throws -> DynamicEObject {
        guard let object = objects[id] else { throw ResourceEditError.objectNotFound(id) }
        guard let dynamic = object as? DynamicEObject else { throw ResourceEditError.notEditable(id) }
        return dynamic
    }

    private func structuralFeature(named name: String, of object: DynamicEObject) throws -> any EStructuralFeature {
        guard let feature = object.eClass.getStructuralFeature(name: name) else {
            throw ResourceEditError.featureNotFound(feature: name, className: object.eClass.name)
        }
        return feature
    }

    /// Writes a value and describes the change; `nil` if nothing changed.
    @discardableResult
    private func store(_ id: EUUID, _ feature: any EStructuralFeature, _ value: (any EcoreValue)?) -> ResourceChange? {
        guard var object = objects[id] as? DynamicEObject else { return nil }
        let old = object.eGet(feature)
        if areEqualOptional(old, value) { return nil }
        object.eSet(feature, value)
        objects[id] = object
        return ResourceChange(kind: .set, objectID: id, feature: feature.name, oldValue: old, newValue: value)
    }

    private func contains(_ object: DynamicEObject, _ feature: any EStructuralFeature, _ element: any EcoreValue) -> Bool {
        ValueList.elements(of: object.eGet(feature)).contains { areEqual($0, element) }
    }

    /// The identifier of the object that a value stands for, adding unknown objects.
    private func referenceTarget(_ value: any EcoreValue, _ changes: inout [ResourceChange]) throws -> EUUID? {
        if let id = value as? EUUID { return id }
        guard let object = value as? any EObject else { return nil }
        if objects[object.id] == nil {
            add(object)
            changes.append(ResourceChange(kind: .create, objectID: object.id, newValue: object))
        }
        return object.id
    }

    /// Replaces objects in a reference value with their identifiers.
    private func normalised(_ value: (any EcoreValue)?, many: Bool, _ changes: inout [ResourceChange]) throws -> (any EcoreValue)? {
        guard let value else { return nil }
        if many {
            if value is EcoreValueArray { return value }
            if let objectsList = value as? [any EObject] {
                return try objectsList.compactMap { try referenceTarget($0, &changes) }
            }
            return value
        }
        return try referenceTarget(value, &changes) ?? value
    }

    private func findContainer(of id: EUUID) -> (container: EUUID, reference: EReference)? {
        for object in objects.values {
            guard let eClass = object.eClass as? EClass else { continue }
            for reference in eClass.eAllReferences
            where reference.containment && ReferenceValues.identifiers(object.eGet(reference)).contains(id) {
                return (object.id, reference)
            }
        }
        return nil
    }

    private func subtree(of root: EUUID) -> [EUUID] {
        var result: [EUUID] = []
        var seen = Set<EUUID>()
        func visit(_ id: EUUID) {
            guard seen.insert(id).inserted, let object = objects[id] else { return }
            result.append(id)
            guard let eClass = object.eClass as? EClass else { return }
            for reference in eClass.eAllReferences where reference.containment {
                ReferenceValues.identifiers(object.eGet(reference)).forEach(visit)
            }
        }
        visit(root)
        return result
    }

    private func checkAcyclic(container: EUUID, child: EUUID) throws {
        if subtree(of: child).contains(container) { throw ResourceEditError.containmentCycle(child) }
    }

    /// Makes an object that lost its container a root object.
    private func orphan(_ id: EUUID) {
        if objects[id] != nil, !rootObjects.contains(id), findContainer(of: id) == nil {
            rootObjects.append(id)
        }
    }

    /// Removes an object from its container and from the roots.
    private func detach(_ id: EUUID, _ changes: inout [ResourceChange], unlinking: Bool = true) async {
        rootObjects.removeAll { $0 == id }
        guard let slot = findContainer(of: id), let container = objects[slot.container] as? DynamicEObject else { return }
        let current = container.eGet(slot.reference)
        if slot.reference.isMany {
            var list = ValueList.elements(of: current)
            guard let position = list.firstIndex(where: { ($0 as? EUUID) == id }) else { return }
            list.remove(at: position)
            store(slot.container, slot.reference, ValueList.make(list, like: current))
            changes.append(
                ResourceChange(
                    kind: .remove, objectID: slot.container, feature: slot.reference.name, oldValue: id, index: position))
        } else if let change = store(slot.container, slot.reference, nil) {
            changes.append(change)
        }
        if unlinking { await link(slot.reference, source: slot.container, target: id, add: false, &changes) }
    }

    private func oppositeReference(of reference: EReference, in target: DynamicEObject) -> EReference? {
        let references = target.eClass.eAllReferences
        if let id = reference.opposite, let match = references.first(where: { $0.id == id }) { return match }
        return references.first { $0.opposite == reference.id }
    }

    /// Adds or removes the source on the opposite side of a bidirectional reference.
    private func link(
        _ reference: EReference, source: EUUID, target: EUUID, add: Bool, _ changes: inout [ResourceChange]
    ) async {
        guard reference.opposite != nil || reference.container else { return }
        guard let targetObject = objects[target] as? DynamicEObject else {
            if let oppositeID = reference.opposite, let resourceSet {
                await resourceSet.updateOpposite(targetId: target, oppositeRefId: oppositeID, sourceId: source, add: add)
            }
            return
        }
        guard let opposite = oppositeReference(of: reference, in: targetObject) else { return }
        let current = targetObject.eGet(opposite)
        if opposite.isMany {
            var list = ValueList.elements(of: current)
            if add {
                guard !list.contains(where: { ($0 as? EUUID) == source }) else { return }
                list.append(source)
                store(target, opposite, ValueList.make(list, like: current ?? EcoreDefaultValue.value(for: opposite)))
                changes.append(
                    ResourceChange(kind: .add, objectID: target, feature: opposite.name, newValue: source, index: list.count - 1))
            } else if let position = list.firstIndex(where: { ($0 as? EUUID) == source }) {
                list.remove(at: position)
                store(target, opposite, ValueList.make(list, like: current))
                changes.append(
                    ResourceChange(kind: .remove, objectID: target, feature: opposite.name, oldValue: source, index: position))
            }
        } else if add {
            if let change = store(target, opposite, source) { changes.append(change) }
        } else if (current as? EUUID) == source, let change = store(target, opposite, nil) {
            changes.append(change)
        }
    }

    /// Removes every reference of one feature that points into a set of identifiers.
    private func removeReferences(to doomed: OrderedSet<EUUID>, from id: EUUID, _ reference: EReference) -> [ResourceChange] {
        guard let object = objects[id] else { return [] }
        let current = object.eGet(reference)
        guard ReferenceValues.identifiers(current).contains(where: doomed.contains) else { return [] }
        guard reference.isMany else {
            return store(id, reference, nil).map { [$0] } ?? []
        }
        var kept: [any EcoreValue] = []
        var changes: [ResourceChange] = []
        for (position, element) in ValueList.elements(of: current).enumerated() {
            if let target = element as? EUUID, doomed.contains(target) {
                changes.append(
                    ResourceChange(kind: .remove, objectID: id, feature: reference.name, oldValue: target, index: position))
            } else {
                kept.append(element)
            }
        }
        store(id, reference, ValueList.make(kept, like: current))
        return changes
    }

    /// Builds a copy of an object that belongs to another class, carrying the values over.
    private static func migrated(_ object: DynamicEObject, to newClass: EClass) -> DynamicEObject {
        var result = DynamicEObject(id: object.id, eClass: newClass)
        let oldFeatures = object.eClass.allStructuralFeatures
        for name in object.getFeatureNames() {
            guard let value = object.eGet(name) else { continue }
            let byID = oldFeatures.first { $0.name == name }.flatMap { old in
                newClass.allStructuralFeatures.first { $0.id == old.id }
            }
            result.eSet(byID?.name ?? name, value: value)
        }
        return result
    }
}

/// An index of the classes of a set of packages.
private struct ClassCatalogue {
    var byID: [EUUID: EClass] = [:]
    var byKey: [String: EClass] = [:]
    var byName: [String: [EClass]] = [:]
    var packageURI: [EUUID: String] = [:]

    init(_ packages: [EPackage]) {
        for package in packages { add(package) }
    }

    private mutating func add(_ package: EPackage) {
        for case let eClass as EClass in package.eClassifiers {
            byID[eClass.id] = eClass
            byKey["\(package.nsURI)#\(eClass.name)"] = eClass
            byName[eClass.name, default: []].append(eClass)
            packageURI[eClass.id] = package.nsURI
        }
        for subpackage in package.eSubpackages { add(subpackage) }
    }
}

extension EClass {
    /// The class's name as a value, used to describe rebinding in change journals.
    fileprivate var eReferenceName: String { name }
}

extension EStructuralFeature {
    /// Whether the feature holds several values.
    var manyValued: Bool {
        switch self {
        case let attribute as EAttribute: return attribute.isMany
        case let reference as EReference: return reference.isMany
        default: return false
        }
    }

    /// Whether the feature forbids duplicate values.
    var uniqueValued: Bool {
        switch self {
        case let attribute as EAttribute: return attribute.unique
        case let reference as EReference: return reference.unique
        default: return false
        }
    }
}

extension Resource {
    /// Adds a newly created object to the resource as a root object and reports the change.
    ///
    /// - Parameter object: The object to add.
    /// - Returns: The creation change, empty if the resource already holds the object.
    @discardableResult
    public func eCreate(_ object: any EObject) -> [ResourceChange] {
        guard add(object) else { return [] }
        let change = [ResourceChange(kind: .create, objectID: object.id, newValue: object)]
        if changeJournal != nil { changeJournal?.append(contentsOf: change) }
        return change
    }
}
