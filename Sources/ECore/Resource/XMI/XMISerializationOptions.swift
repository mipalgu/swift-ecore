//
// XMISerializationOptions.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// How the start tag of a document's root element is wrapped when a line width is set.
///
/// Documents written by different releases of the Eclipse Modeling Framework wrap the root
/// element differently. Both layouts are reproduced so that a document can be written back
/// in the layout it was read in.
public enum XMIRootLayout: Sendable, Equatable, CaseIterable {
    /// The namespace declarations follow `xmi:version` on the same line.
    ///
    /// A declaration starts a new line when the line has grown beyond the line width. The
    /// element's own attributes are laid out as though the declarations were absent, except
    /// that the first of them starts a new line if the declarations ended beyond the width.
    case standard

    /// The namespace declarations start on a new line after `xmi:version`.
    ///
    /// Later declarations start a new line when the line has grown beyond the line width.
    /// The first of the element's own attributes stays on the line of the last declaration,
    /// the second always starts a new line, and the others follow the usual rule.
    case versionFirst

    /// Detects the layout in which a document's root element was written.
    ///
    /// - Parameter text: The text of the document.
    /// - Returns: ``versionFirst`` if the line after the line holding `xmi:version` starts with
    ///   a namespace declaration, otherwise ``standard``.
    public static func detect(in text: String) -> XMIRootLayout {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let index = lines.firstIndex(where: { $0.contains("xmi:version=") }) else { return .standard }
        let line = lines[index]
        guard line.hasSuffix("\"") || line.hasSuffix(">"), !line.contains("xmlns:"),
            lines.indices.contains(index + 1), lines[index + 1].hasPrefix("xmlns:")
        else { return .standard }
        return .versionFirst
    }
}

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

    /// The width, in characters, after which an element's attributes continue on a new line.
    ///
    /// A value of `nil` writes all attributes of an element on one line. EMF's editors
    /// wrap lines at ``emfLineWidth``: an attribute that starts after the line has grown
    /// beyond the width begins a new line, indented four spaces further than the element.
    /// The width applies to metamodel (`.ecore`) documents.
    public var lineWidth: Int?

    /// How the root element's start tag is wrapped when ``lineWidth`` is set.
    public var rootLayout: XMIRootLayout

    /// The line width that EMF's editors use when they write `.ecore` documents.
    public static let emfLineWidth = 80

    /// Creates a set of options.
    ///
    /// - Parameters:
    ///   - attributeStyleReferences: Whether references are written as attributes.
    ///   - typeQualifiers: Whether type qualifiers are written.
    ///   - nameBasedFragments: Whether Ecore elements are identified by name.
    ///   - relativeURIs: Whether URIs are written relative to the document.
    ///   - omitDefaultValues: Whether default values are left out.
    ///   - manyValuedAttributesAsElements: Whether many-valued attributes become child elements.
    ///   - lineWidth: The width after which attributes continue on a new line, or `nil` for none.
    ///   - rootLayout: How the root element's start tag is wrapped.
    public init(
        attributeStyleReferences: Bool = false,
        typeQualifiers: Bool = false,
        nameBasedFragments: Bool = false,
        relativeURIs: Bool = false,
        omitDefaultValues: Bool = false,
        manyValuedAttributesAsElements: Bool = false,
        lineWidth: Int? = nil,
        rootLayout: XMIRootLayout = .standard
    ) {
        self.attributeStyleReferences = attributeStyleReferences
        self.typeQualifiers = typeQualifiers
        self.nameBasedFragments = nameBasedFragments
        self.relativeURIs = relativeURIs
        self.omitDefaultValues = omitDefaultValues
        self.manyValuedAttributesAsElements = manyValuedAttributesAsElements
        self.lineWidth = lineWidth
        self.rootLayout = rootLayout
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

    /// The layout of the Eclipse Modeling Framework including its line wrapping.
    ///
    /// This is ``emf`` with the lines wrapped at ``emfLineWidth``, which reproduces
    /// the text that EMF's editors write.
    public static let emfWrapped = XMISerializationOptions(
        attributeStyleReferences: true,
        typeQualifiers: true,
        nameBasedFragments: true,
        relativeURIs: true,
        omitDefaultValues: true,
        manyValuedAttributesAsElements: true,
        lineWidth: emfLineWidth
    )
}
