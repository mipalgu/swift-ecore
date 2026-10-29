//
// ObjectTable.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OrderedCollections

/// How a containment value holds a contained object.
enum ContainmentForm: Sendable {
    /// The value is the identifier of the contained object.
    case identifier

    /// The value is an array of identifiers that includes the contained object's.
    case identifierList

    /// The value is an array of another element type that includes the contained object's identifier.
    case mixedList

    /// The value is the contained object itself.
    case object
}

/// A containment reference of one object that holds another object.
struct ContainmentClaim: Sendable {
    /// The identifier of the containing object.
    let container: EUUID

    /// The containment reference that holds the contained object.
    let reference: EReference

    /// How the value of the reference holds the contained object.
    let form: ContainmentForm

    /// Whether the holding value lies within an ``EcoreValueArray`` of the reference value.
    let nested: Bool
}

/// The objects of a resource in insertion order, together with an index of their containment.
///
/// The table is the only place where the objects of a resource are stored, so every change to
/// them passes through it. Once the containment index has been built, each change records the
/// object it touched, and the next lookup brings the index up to date for those objects only,
/// so that the container of an object is found without scanning the table.
struct ObjectTable: Sendable {
    /// The objects, keyed by identifier, in insertion order.
    private var storage = OrderedDictionary<EUUID, any EObject>()

    /// The containment index, or `nil` until it is first needed.
    private var index: ContainmentIndex?

    /// The identifiers of the objects stored or removed since the index was last brought up to date.
    private var changed = Set<EUUID>()

    /// Creates an empty table.
    init() {}

    /// The objects in insertion order.
    var values: OrderedDictionary<EUUID, any EObject>.Values { storage.values }

    /// The identifiers of the objects in insertion order.
    var keys: OrderedSet<EUUID> { storage.keys }

    /// The number of objects.
    var count: Int { storage.count }

    /// Whether the table holds no objects.
    var isEmpty: Bool { storage.isEmpty }

    /// The object with an identifier.
    ///
    /// Storing an object under an identifier that the table already holds replaces the object
    /// in place; a new identifier is appended. Storing `nil` removes the object.
    subscript(id: EUUID) -> (any EObject)? {
        get { storage[id] }
        set {
            if let newValue {
                storage[id] = newValue
                noteChange(of: id)
            } else {
                removeValue(forKey: id)
            }
        }
    }

    /// Removes the object with an identifier.
    ///
    /// - Parameter id: The identifier of the object to remove.
    /// - Returns: The removed object, or `nil` if the table held none with that identifier.
    @discardableResult
    mutating func removeValue(forKey id: EUUID) -> (any EObject)? {
        guard let removed = storage.removeValue(forKey: id) else { return nil }
        noteChange(of: id)
        return removed
    }

    /// Removes all objects.
    mutating func removeAll() {
        storage.removeAll()
        index = nil
        changed.removeAll()
    }

    /// The containment references that hold an identifier, in table order.
    ///
    /// Claims are ordered by the position of their container in the table, then by the order
    /// of the container's containment references, then by position within each reference.
    /// The index is built on first use and brought up to date with any changes since.
    ///
    /// - Parameter id: The identifier of the contained object, which need not be in the table.
    /// - Returns: The claims, and whether the index had to be built from scratch.
    mutating func containmentClaims(on id: EUUID) -> (claims: [ContainmentClaim], built: Bool) {
        let built = prepareIndex()
        return (index?.claims[id] ?? [], built)
    }

    /// Records that the object with an identifier was stored or removed.
    private mutating func noteChange(of id: EUUID) {
        if index != nil { changed.insert(id) }
    }

    /// Builds the containment index, or brings it up to date with the recorded changes.
    ///
    /// - Returns: `true` if the index was built from scratch.
    private mutating func prepareIndex() -> Bool {
        guard index != nil else {
            var built = ContainmentIndex()
            for (position, (id, object)) in storage.enumerated() {
                built.place(Self.claims(of: object, as: id), at: position) { _ in nil }
            }
            index = built
            changed.removeAll()
            return true
        }
        guard !changed.isEmpty else { return false }
        for id in changed { index?.withdrawClaims(of: id) }
        let positions = storage
        for id in changed {
            guard let position = positions.index(forKey: id) else { continue }
            let claims = Self.claims(of: positions.values[position], as: id)
            index?.place(claims, at: position) { positions.index(forKey: $0) }
        }
        changed.removeAll()
        return false
    }

    /// The containment claims that an object makes, in containment reference order.
    private static func claims(of object: any EObject, as id: EUUID) -> [(child: EUUID, claim: ContainmentClaim)] {
        guard let eClass = object.eClass as? EClass else { return [] }
        var result: [(child: EUUID, claim: ContainmentClaim)] = []
        for reference in eClass.eAllReferences where reference.containment {
            collect(object.eGet(reference), container: id, reference: reference, nested: false, into: &result)
        }
        return result
    }

    /// Appends the claims of one containment value.
    private static func collect(
        _ value: (any EcoreValue)?, container: EUUID, reference: EReference, nested: Bool,
        into result: inout [(child: EUUID, claim: ContainmentClaim)]
    ) {
        func claim(_ child: EUUID, _ form: ContainmentForm) {
            result.append((child, ContainmentClaim(container: container, reference: reference, form: form, nested: nested)))
        }
        switch value {
        case let id as EUUID:
            claim(id, .identifier)
        case let ids as [EUUID]:
            for id in ids { claim(id, .identifierList) }
        case let array as EcoreValueArray:
            for element in array.values {
                collect(element, container: container, reference: reference, nested: true, into: &result)
            }
        case let object as any EObject:
            claim(object.id, .object)
        case let values as [Any]:
            for case let id as EUUID in values { claim(id, .mixedList) }
        default:
            break
        }
    }
}

/// The containment claims of the objects of a table, keyed by contained identifier.
private struct ContainmentIndex: Sendable {
    /// The claims on each contained identifier, in table order.
    var claims: [EUUID: [ContainmentClaim]] = [:]

    /// The identifiers that each container claims.
    var claimed: [EUUID: [EUUID]] = [:]

    /// Records the claims of an object at its position in the table.
    ///
    /// Claims of objects that come later in the table stay after the new claims, and the
    /// claims of one object keep their order.
    ///
    /// - Parameters:
    ///   - newClaims: The claims of the object, in containment reference order.
    ///   - position: The position of the object in the table.
    ///   - positionOf: Finds the table position of another indexed container.
    mutating func place(
        _ newClaims: [(child: EUUID, claim: ContainmentClaim)], at position: Int,
        positionOf: (EUUID) -> Int?
    ) {
        guard let container = newClaims.first?.claim.container else { return }
        for (child, claim) in newClaims {
            Self.insert(claim, at: position, into: &claims[child, default: []], positionOf: positionOf)
        }
        claimed[container] = newClaims.map(\.child)
    }

    /// Removes the claims of an object.
    mutating func withdrawClaims(of container: EUUID) {
        guard let children = claimed.removeValue(forKey: container) else { return }
        for child in children {
            guard var list = claims.removeValue(forKey: child) else { continue }
            list.removeAll { $0.container == container }
            if !list.isEmpty { claims[child] = list }
        }
    }

    /// Inserts a claim after every claim whose container does not come later in the table.
    private static func insert(
        _ claim: ContainmentClaim, at position: Int, into list: inout [ContainmentClaim],
        positionOf: (EUUID) -> Int?
    ) {
        guard !list.isEmpty else {
            list.append(claim)
            return
        }
        let slot = list.firstIndex { (positionOf($0.container) ?? position) > position } ?? list.endIndex
        list.insert(claim, at: slot)
    }
}
