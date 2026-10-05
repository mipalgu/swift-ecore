//
// MetamodelChangeSet.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

/// The kind of modification that a ``MetamodelChange`` describes.
public enum MetamodelChangeKind: String, Sendable, Hashable, CaseIterable {
    /// An element was added to a container.
    case add
    /// An element was removed from its container.
    case remove
    /// An element was moved to another place.
    case move
    /// A property of an element was given a new value.
    case set
}

/// One modification that an edit made to a metamodel document.
public struct MetamodelChange: Sendable, Hashable {
    /// The kind of modification.
    public let kind: MetamodelChangeKind

    /// The element that was added, removed, moved, or modified.
    public let element: EUUID

    /// The property that was set, or the containment feature that holds an added, removed,
    /// or moved element (after the move, for a move).
    public let feature: EcoreFeatureName?

    /// The value before the change: the previous value of a property, or, for a removal or
    /// move, the identifier of the previous container (`nil` for a root package).
    public let oldValue: EditValue?

    /// The value after the change: the new value of a property, or, for an addition or move,
    /// the identifier of the new container.
    public let newValue: EditValue?

    /// The position in the containment feature after the change, for additions and moves,
    /// and the position before the change, for removals.
    public let index: Int?

    /// The position in the containment feature before a move.
    public let oldIndex: Int?

    /// The feature that held the element before a move.
    public let oldFeature: EcoreFeatureName?

    /// Creates a change.
    ///
    /// - Parameters:
    ///   - kind: The kind of modification.
    ///   - element: The element that was modified.
    ///   - feature: The property or containment feature.
    ///   - oldValue: The value before the change.
    ///   - newValue: The value after the change.
    ///   - index: The position within the containment feature.
    ///   - oldIndex: The position before a move.
    ///   - oldFeature: The containment feature before a move.
    public init(
        kind: MetamodelChangeKind, element: EUUID, feature: EcoreFeatureName? = nil,
        oldValue: EditValue? = nil, newValue: EditValue? = nil, index: Int? = nil,
        oldIndex: Int? = nil, oldFeature: EcoreFeatureName? = nil
    ) {
        self.kind = kind
        self.element = element
        self.feature = feature
        self.oldValue = oldValue
        self.newValue = newValue
        self.index = index
        self.oldIndex = oldIndex
        self.oldFeature = oldFeature
    }

    /// The change that reverses this one.
    public var inverted: MetamodelChange {
        switch kind {
        case .add:
            return MetamodelChange(
                kind: .remove, element: element, feature: feature, oldValue: newValue, index: index)
        case .remove:
            return MetamodelChange(
                kind: .add, element: element, feature: feature, newValue: oldValue, index: index)
        case .move:
            return MetamodelChange(
                kind: .move, element: element, feature: oldFeature ?? feature, oldValue: newValue,
                newValue: oldValue, index: oldIndex, oldIndex: index, oldFeature: feature)
        case .set:
            return MetamodelChange(
                kind: .set, element: element, feature: feature, oldValue: newValue, newValue: oldValue)
        }
    }
}

/// Everything that an edit changed in a metamodel document, for views to update themselves.
///
/// A change set lists the individual changes in the order in which they were made, and
/// summarises them: which elements appeared and disappeared, which properties were modified,
/// which containers have different children, and which labels may read differently now.
public struct MetamodelChangeSet: Sendable, Hashable {
    /// What the edit did, as shown by undo and redo menu items.
    public var label: String

    /// The individual changes, in the order in which they were made.
    public var changes: [MetamodelChange]

    /// The elements that were added, including everything that they contain.
    public var added: Set<EUUID>

    /// The elements that were removed, including everything that they contained.
    public var removed: Set<EUUID>

    /// The properties that were modified, by element. Added and removed elements are not listed.
    public var modified: [EUUID: Set<EcoreFeatureName>]

    /// The containers whose children changed: elements were added, removed, moved, or reordered.
    public var structureChanged: Set<EUUID>

    /// The elements whose label or decoration may read differently after the edit.
    ///
    /// Besides the modified elements, these are the elements that refer to a renamed element
    /// (features typed by a renamed class, and subclasses of it), and the operations whose
    /// parameters changed.
    public var labelsAffected: Set<EUUID>

    /// The identifiers of the elements that the edit created, in the order of creation.
    public var createdIDs: [EUUID]

    /// The problems that the edit allowed under its policy.
    public var diagnostics: [SourceDiagnostic]

    /// Creates a change set.
    ///
    /// - Parameters:
    ///   - label: What the edit did.
    ///   - changes: The individual changes.
    ///   - added: The elements that were added.
    ///   - removed: The elements that were removed.
    ///   - modified: The modified properties by element.
    ///   - structureChanged: The containers whose children changed.
    ///   - labelsAffected: The elements whose labels may differ.
    ///   - createdIDs: The identifiers of the created elements.
    ///   - diagnostics: The problems that the edit allowed.
    public init(
        label: String = "", changes: [MetamodelChange] = [], added: Set<EUUID> = [],
        removed: Set<EUUID> = [], modified: [EUUID: Set<EcoreFeatureName>] = [:],
        structureChanged: Set<EUUID> = [], labelsAffected: Set<EUUID> = [],
        createdIDs: [EUUID] = [], diagnostics: [SourceDiagnostic] = []
    ) {
        self.label = label
        self.changes = changes
        self.added = added
        self.removed = removed
        self.modified = modified
        self.structureChanged = structureChanged
        self.labelsAffected = labelsAffected
        self.createdIDs = createdIDs
        self.diagnostics = diagnostics
    }

    /// Whether the edit changed nothing.
    public var isEmpty: Bool {
        changes.isEmpty && added.isEmpty && removed.isEmpty && modified.isEmpty && structureChanged.isEmpty
    }

    /// The change set that describes reversing this one.
    ///
    /// The changes are reversed and inverted, additions become removals and the other way
    /// around. The result describes what undoing the edit does; it creates nothing, so its
    /// ``createdIDs`` and ``diagnostics`` are empty.
    public func inverted() -> MetamodelChangeSet {
        MetamodelChangeSet(
            label: label, changes: changes.reversed().map(\.inverted), added: removed,
            removed: added, modified: modified, structureChanged: structureChanged,
            labelsAffected: labelsAffected)
    }
}
