//
// MetamodelEdit.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

/// An edit of a metamodel document.
///
/// Edits name elements by identifier. Applying an edit with
/// ``MetamodelDocument/apply(_:policy:)`` either changes the document completely or, if the
/// edit is refused, not at all.
public enum MetamodelEdit: Sendable {
    /// Creates an element and adds it to a container.
    ///
    /// - Parameters:
    ///   - kind: The metaclass of the new element.
    ///   - in: The identifier of the container.
    ///   - feature: The containment feature of the container that holds the element.
    ///   - at: The position within the feature; the element is appended if `nil`.
    ///   - name: The name of the new element (the key, for a detail entry); empty if `nil`.
    ///   - identifier: The identifier that the element gets; a new one if `nil`.
    case create(
        EcoreClassifier, in: EUUID, feature: EcoreFeatureName, at: Int? = nil, name: String? = nil,
        identifier: EUUID? = nil)

    /// Deletes elements with everything they contain, and cleans up every reference to them.
    ///
    /// Deleted classes are removed from the supertypes of other classes and from the
    /// exceptions of operations, deleted references are removed as opposites, and references
    /// from annotations are removed. A feature whose type was deleted gets the Ecore built-in
    /// `EObject` (a reference) or `EJavaObject` (an attribute) as its type; an operation
    /// whose type was deleted has no type, and a parameter gets `EObject` or `EJavaObject`
    /// according to the kind of the deleted type.
    case delete([EUUID])

    /// Moves elements into a container.
    ///
    /// The position is that in the feature after the moved elements have been taken out of it.
    ///
    /// - Parameters:
    ///   - ids: The elements to move; they keep their identifiers.
    ///   - to: The identifier of the new container.
    ///   - feature: The containment feature; the first feature that accepts the elements if `nil`.
    ///   - at: The position; the elements are appended if `nil`.
    case move([EUUID], to: EUUID, feature: EcoreFeatureName? = nil, at: Int? = nil)

    /// Sets a property.
    ///
    /// Strings, flags, and integers are given as such. A reference is given as the
    /// identifier (``EUUID``) of the element it refers to, or `nil`; a many-valued reference
    /// as an array of identifiers. Identifiers are resolved through the index of the document,
    /// and the built-in classifiers of Ecore are accepted. Renaming an element sets `name`.
    case set(EUUID, EcoreFeatureName, (any EcoreValue)?)

    /// Pairs two references as opposites of each other, or unpairs a reference.
    ///
    /// Both sides are kept consistent: the previous partners of both references are cleared,
    /// and the `container` flag of each side follows the `containment` flag of the other.
    case setOpposite(EUUID, EUUID?)

    /// Sets the value of an annotation detail, adding the detail if the key is new.
    ///
    /// - Parameters:
    ///   - annotation: The identifier of the annotation.
    ///   - key: The key of the detail.
    ///   - value: The new value.
    ///   - at: The position of a new detail; it is appended if `nil`.
    case setDetail(annotation: EUUID, key: String, value: String, at: Int? = nil)

    /// Renames the key of an annotation detail, keeping its position and value.
    case renameDetailKey(annotation: EUUID, from: String, to: String)

    /// Pastes the content of a clipboard into a container.
    ///
    /// - Parameters:
    ///   - clipboard: The copied elements; they receive new identifiers on every paste.
    ///   - into: The identifier of the container.
    ///   - feature: The containment feature; the first feature that accepts the elements if `nil`.
    ///   - at: The position; the elements are appended if `nil`.
    case paste(EcoreClipboard, into: EUUID, feature: EcoreFeatureName? = nil, at: Int? = nil)

    /// Applies several edits as one: they are applied in order, undone together, and refused
    /// together if any of them is refused.
    case compound(label: String, [MetamodelEdit])

    /// The text that undo and redo menu items show for the edit.
    public var label: String {
        switch self {
        case .create(let kind, _, _, _, _, _): return "\(EcoreEditLabels.create) \(kind.rawValue)"
        case .delete: return EcoreEditLabels.delete
        case .move: return EcoreEditLabels.move
        case .set(_, let feature, _):
            return feature == .name
                ? EcoreEditLabels.rename : "\(EcoreEditLabels.set) \(feature.rawValue)"
        case .setOpposite: return EcoreEditLabels.setOpposite
        case .setDetail: return EcoreEditLabels.setDetail
        case .renameDetailKey: return EcoreEditLabels.renameDetailKey
        case .paste: return EcoreEditLabels.paste
        case .compound(let label, _): return label
        }
    }
}
