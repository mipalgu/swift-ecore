//
// EPackageOrigin.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Where a loaded package came from and which other documents it refers to.
///
/// Native classes are value types that do not know which document they were loaded from.
/// When a package refers to a classifier of another document, the package therefore records
/// the document URI of that classifier and its fragment, keyed by the classifier's identifier.
/// The serialiser uses this record to write `other.ecore#//Name` rather than a bare name.
///
/// A package that is built in code, rather than loaded from a document, has no origin.
public struct EPackageOrigin: Sendable, Hashable {
    /// The absolute URI of the document that the package was loaded from.
    public var documentURI: String

    /// The classifiers of other documents that the package refers to.
    ///
    /// Each entry maps the identifier of a classifier to a proxy that holds the absolute URI
    /// of its document and its fragment within that document.
    public var externalReferences: [EUUID: ResourceProxy]

    /// The types of other documents that could not be loaded, keyed by the typed element.
    ///
    /// An element whose type lies in a document that is not available keeps a default type
    /// (`EString` or `EObject`). This record keeps the reference as it was written, so that the
    /// serialiser can write it back unchanged. Each entry maps the identifier of an attribute,
    /// reference, operation, or parameter to the proxy that holds the URI, fragment, and kind
    /// qualifier of its type.
    public var unresolvedTypes: [EUUID: ResourceProxy]

    /// The opposites that lie in other documents, keyed by the reference that names them.
    ///
    /// A reference whose opposite is declared in another document has no local opposite. This
    /// record keeps the reference to it, as the proxy of the opposite, so that the serialiser can
    /// write it back.
    public var externalOpposites: [EUUID: ResourceProxy]

    /// Creates an origin.
    ///
    /// - Parameters:
    ///   - documentURI: The absolute URI of the document that the package was loaded from.
    ///   - externalReferences: The classifiers of other documents that the package refers to.
    ///   - unresolvedTypes: The types that could not be loaded, keyed by the typed element.
    ///   - externalOpposites: The opposites in other documents, keyed by the reference.
    public init(
        documentURI: String, externalReferences: [EUUID: ResourceProxy] = [:],
        unresolvedTypes: [EUUID: ResourceProxy] = [:],
        externalOpposites: [EUUID: ResourceProxy] = [:]
    ) {
        self.documentURI = documentURI
        self.externalReferences = externalReferences
        self.unresolvedTypes = unresolvedTypes
        self.externalOpposites = externalOpposites
    }
}
