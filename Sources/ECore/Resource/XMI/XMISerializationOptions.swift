//
// XMISerializationOptions.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// Options that control how ``XMISerializer`` lays out a document.
///
/// The default, ``legacy``, reproduces the layout this package has always written.
/// The ``emf`` preset writes the layout of the Eclipse Modeling Framework:
/// non-containment references as attributes holding `uri#fragment` values,
/// type qualifiers where the referenced class differs from the declared type,
/// name-based fragments for Ecore elements, relative URIs, omitted default values,
/// many-valued attributes as repeated child elements, and a deterministic
/// namespace declaration order. Any other combination of settings also selects the
/// EMF-style writer, with the individual switches applied.
public struct XMISerializationOptions: Sendable, Equatable {
    /// Writes non-containment references as attributes (`ecoreClass="lib.ecore#//Book"`)
    /// instead of `href` child elements.
    public var attributeStyleReferences: Bool

    /// Prefixes a reference with the type of its target (`ecore:EAttribute lib.ecore#//Book/title`)
    /// when that type differs from the declared type of the reference.
    public var typeQualifiers: Bool

    /// Identifies Ecore elements by their names (`#//Book/title`) rather than by position.
    public var nameBasedFragments: Bool

    /// Writes the URI of another resource relative to the URI of the written resource.
    public var relativeURIs: Bool

    /// Leaves out attributes whose value equals the default of the attribute.
    public var omitDefaultValues: Bool

    /// Writes many-valued attributes as one child element per value instead of one
    /// space-separated attribute.
    public var manyValuedAttributesAsElements: Bool

    /// Creates a set of options.
    ///
    /// - Parameters:
    ///   - attributeStyleReferences: Whether references are written as attributes.
    ///   - typeQualifiers: Whether type qualifiers are written.
    ///   - nameBasedFragments: Whether Ecore elements are identified by name.
    ///   - relativeURIs: Whether URIs are written relative to the document.
    ///   - omitDefaultValues: Whether default values are left out.
    ///   - manyValuedAttributesAsElements: Whether many-valued attributes become child elements.
    public init(
        attributeStyleReferences: Bool = false,
        typeQualifiers: Bool = false,
        nameBasedFragments: Bool = false,
        relativeURIs: Bool = false,
        omitDefaultValues: Bool = false,
        manyValuedAttributesAsElements: Bool = false
    ) {
        self.attributeStyleReferences = attributeStyleReferences
        self.typeQualifiers = typeQualifiers
        self.nameBasedFragments = nameBasedFragments
        self.relativeURIs = relativeURIs
        self.omitDefaultValues = omitDefaultValues
        self.manyValuedAttributesAsElements = manyValuedAttributesAsElements
    }

    /// The layout this package has always written (all switches off).
    public static let legacy = XMISerializationOptions()

    /// The layout of the Eclipse Modeling Framework (all switches on).
    public static let emf = XMISerializationOptions(
        attributeStyleReferences: true,
        typeQualifiers: true,
        nameBasedFragments: true,
        relativeURIs: true,
        omitDefaultValues: true,
        manyValuedAttributesAsElements: true
    )
}
