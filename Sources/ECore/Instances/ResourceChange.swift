//
// ResourceChange.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// The kind of modification that a ``ResourceChange`` describes.
public enum ResourceChangeKind: String, Sendable, Hashable, CaseIterable {
    /// A feature was given a new value.
    case set
    /// A value was inserted into a many-valued feature.
    case add
    /// A value was removed from a many-valued feature.
    case remove
    /// A value was moved within a many-valued feature.
    case move
    /// An object was created and added to the resource.
    case create
    /// An object was removed from the resource.
    case delete
    /// An object was re-pointed to a different metaclass.
    case rebind
}

/// A single modification of an object in a resource.
///
/// Mutating operations on ``Resource`` report the modifications that they made as a list
/// of changes (the change journal). Each change names the object and, for feature
/// modifications, the feature, together with the old and new values and the position within
/// a many-valued feature where one applies. The inverse of a change swaps its old and new
/// values, which is how undo and redo report what they restored.
public struct ResourceChange: Sendable, Equatable {
    /// The kind of modification.
    public let kind: ResourceChangeKind

    /// The identifier of the modified object.
    public let objectID: EUUID

    /// The name of the modified feature, or `nil` for changes to a whole object.
    public let feature: String?

    /// The value before the change (an object for ``ResourceChangeKind/delete``), if any.
    public let oldValue: (any EcoreValue)?

    /// The value after the change (an object for ``ResourceChangeKind/create``), if any.
    public let newValue: (any EcoreValue)?

    /// The position affected within a many-valued feature, if any.
    ///
    /// For ``ResourceChangeKind/move`` this is the destination position.
    public let index: Int?

    /// The original position of a ``ResourceChangeKind/move``, if any.
    public let oldIndex: Int?

    /// Creates a change description.
    ///
    /// - Parameters:
    ///   - kind: The kind of modification.
    ///   - objectID: The identifier of the modified object.
    ///   - feature: The name of the modified feature, if any.
    ///   - oldValue: The value before the change.
    ///   - newValue: The value after the change.
    ///   - index: The position affected within a many-valued feature.
    ///   - oldIndex: The original position of a move.
    public init(
        kind: ResourceChangeKind, objectID: EUUID, feature: String? = nil,
        oldValue: (any EcoreValue)? = nil, newValue: (any EcoreValue)? = nil,
        index: Int? = nil, oldIndex: Int? = nil
    ) {
        self.kind = kind
        self.objectID = objectID
        self.feature = feature
        self.oldValue = oldValue
        self.newValue = newValue
        self.index = index
        self.oldIndex = oldIndex
    }

    /// The change that reverses this one.
    ///
    /// Additions and removals, creations and deletions exchange their kinds, and the old and
    /// new values and positions are swapped.
    public var inverted: ResourceChange {
        let invertedKind: ResourceChangeKind
        switch kind {
        case .add: invertedKind = .remove
        case .remove: invertedKind = .add
        case .create: invertedKind = .delete
        case .delete: invertedKind = .create
        case .set, .move, .rebind: invertedKind = kind
        }
        if kind == .move {
            return ResourceChange(
                kind: .move, objectID: objectID, feature: feature,
                oldValue: newValue, newValue: oldValue, index: oldIndex, oldIndex: index)
        }
        return ResourceChange(
            kind: invertedKind, objectID: objectID, feature: feature,
            oldValue: newValue, newValue: oldValue, index: index)
    }

    public static func == (lhs: ResourceChange, rhs: ResourceChange) -> Bool {
        lhs.kind == rhs.kind && lhs.objectID == rhs.objectID && lhs.feature == rhs.feature
            && lhs.index == rhs.index && lhs.oldIndex == rhs.oldIndex
            && areEqualOptional(lhs.oldValue, rhs.oldValue)
            && areEqualOptional(lhs.newValue, rhs.newValue)
    }
}

/// The modifications made by one execution, undo, or redo, as delivered to observers.
public struct ResourceChangeSet: Sendable, Equatable {
    /// What caused a change set.
    public enum Origin: String, Sendable, Hashable {
        /// A command was executed.
        case execute
        /// A command was undone.
        case undo
        /// A command was redone.
        case redo
    }

    /// The description of the command that caused the changes.
    public let label: String

    /// What caused the changes.
    public let origin: Origin

    /// The individual modifications, in the order in which they were made.
    public let changes: [ResourceChange]

    /// Creates a change set.
    ///
    /// - Parameters:
    ///   - label: The description of the causing command.
    ///   - origin: What caused the changes.
    ///   - changes: The modifications in order.
    public init(label: String, origin: Origin, changes: [ResourceChange]) {
        self.label = label
        self.origin = origin
        self.changes = changes
    }

    /// The identifiers of all objects that the changes touched, without duplicates.
    public var affectedObjectIDs: [EUUID] {
        var seen = Set<EUUID>()
        return changes.map(\.objectID).filter { seen.insert($0).inserted }
    }
}

/// Reasons why an editing operation on a resource cannot be carried out.
public enum ResourceEditError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The resource holds no object with the identifier.
    case objectNotFound(EUUID)
    /// The object is not a dynamic instance and cannot be edited.
    case notEditable(EUUID)
    /// The object's class has no feature of the name.
    case featureNotFound(feature: String, className: String)
    /// The operation needs a many-valued feature.
    case notMultiValued(String)
    /// The position lies outside the feature's values.
    case indexOutOfRange(Int)
    /// The value is not among the feature's values.
    case valueNotFound(String)
    /// The feature does not allow duplicate values.
    case duplicateValue(String)
    /// The operation would make an object contain itself.
    case containmentCycle(EUUID)
    /// The value cannot be stored in the feature.
    case invalidValue(String)

    public var description: String {
        switch self {
        case .objectNotFound(let id): return "No object with identifier \(id) in the resource"
        case .notEditable(let id): return "Object \(id) is not a dynamic instance"
        case .featureNotFound(let feature, let className):
            return "Class \(className) has no feature named \(feature)"
        case .notMultiValued(let feature): return "Feature \(feature) is not many-valued"
        case .indexOutOfRange(let index): return "Position \(index) is out of range"
        case .valueNotFound(let feature): return "Value not found in feature \(feature)"
        case .duplicateValue(let feature): return "Feature \(feature) does not allow duplicates"
        case .containmentCycle(let id): return "Object \(id) would contain itself"
        case .invalidValue(let feature): return "Invalid value for feature \(feature)"
        }
    }
}
