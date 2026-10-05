//
// EcoreClipboard.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

/// Copied metamodel elements, ready to paste into compatible containers.
///
/// A clipboard is made by ``MetamodelDocument/copy(_:)``. Pasting gives every pasted element,
/// and everything it contains, a new identifier, so the same clipboard can be pasted
/// repeatedly, into any container that accepts the copied kinds, in any document. References
/// between the pasted elements refer to the pasted copies; references to elements that were
/// not copied (supertypes, types, exceptions, and annotation references) are kept, and refer
/// to the original elements. A pasted reference whose opposite was not copied has no opposite.
public struct EcoreClipboard: Sendable {
    /// The copied elements, in the order in which they were copied.
    public let elements: [EcoreElement]

    /// The identifier of each copy, by the identifier of the original, for every copied
    /// element and everything it contained.
    public let identifiers: [EUUID: EUUID]

    /// Creates a clipboard.
    ///
    /// - Parameters:
    ///   - elements: The copied elements.
    ///   - identifiers: The identifier of each copy by the identifier of its original.
    public init(elements: [EcoreElement], identifiers: [EUUID: EUUID]) {
        self.elements = elements
        self.identifiers = identifiers
    }

    /// Whether the clipboard holds nothing.
    public var isEmpty: Bool { elements.isEmpty }

    /// The metaclasses of the copied elements, in order.
    public var kinds: [EcoreClassifier] { elements.map(\.kind) }

    /// Whether a container can take the content of the clipboard.
    ///
    /// - Parameters:
    ///   - container: The identifier of the container.
    ///   - feature: The containment feature, or `nil` for any feature that accepts every copied kind.
    ///   - document: The document that holds the container.
    /// - Returns: `true` if the clipboard is not empty and the container accepts every copied element.
    public func canPaste(into container: EUUID, feature: EcoreFeatureName? = nil, in document: MetamodelDocument) -> Bool {
        guard !isEmpty, let element = document.index.element(container),
            !document.index.isExternal(container)
        else { return false }
        if let feature {
            return kinds.allSatisfy { EcoreEditSchema.accepts(container: element.kind, feature: feature, kind: $0) }
        }
        return EcoreEditSchema.feature(of: element.kind, accepting: kinds) != nil
    }
}
