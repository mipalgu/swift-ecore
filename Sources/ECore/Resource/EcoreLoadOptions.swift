//
// EcoreLoadOptions.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Options that govern how an Ecore document is loaded as a native metamodel.
///
/// The default options load as ``ResourceSet/loadEcoreResource(uri:)`` always has: a type
/// that cannot be found is replaced by a default type, and a document without a name or a
/// namespace is rejected.
///
/// ```swift
/// let options = EcoreLoadOptions(unresolvedReferences: .keepAsProxies, tolerant: true)
/// let resource = try await resourceSet.loadEcoreResource(uri: uri, options: options)
/// ```
public struct EcoreLoadOptions: Sendable, Hashable {
    /// How a reference to a classifier that cannot be found is loaded.
    public enum UnresolvedReferences: Sendable, Hashable {
        /// The element receives a default type: `EString` for an attribute and `EObject` for a
        /// reference. The original reference is still written back unchanged.
        case useDefaults

        /// The element receives a placeholder classifier named after the target of the reference.
        ///
        /// The reference is written back exactly as it was read, and the constraint
        /// `EveryProxyResolves` of the validator reports it.
        case keepAsProxies
    }

    /// How a reference to a classifier that cannot be found is loaded.
    public var unresolvedReferences: UnresolvedReferences

    /// Whether a document that lacks a name or a namespace is loaded nonetheless.
    ///
    /// A missing package name, namespace URI, or namespace prefix is then reported in
    /// ``Resource/loadDiagnostics`` instead of aborting the load, and an element without a
    /// name is loaded with an empty name.
    public var tolerant: Bool

    /// Creates load options.
    ///
    /// - Parameters:
    ///   - unresolvedReferences: How unresolved classifier references load (default: ``UnresolvedReferences/useDefaults``).
    ///   - tolerant: Whether missing names are reported instead of aborting the load (default: `false`).
    public init(unresolvedReferences: UnresolvedReferences = .useDefaults, tolerant: Bool = false) {
        self.unresolvedReferences = unresolvedReferences
        self.tolerant = tolerant
    }

    /// The namespace from which the identifiers of placeholder classifiers derive.
    static let placeholderNamespace = EUUID(uuidString: "5C0E0D2A-6A1F-4B7E-9C57-0F3E1B2A4D68") ?? EUUID()
}

/// The diagnostic codes that loading an Ecore document can report.
public enum EcoreLoadDiagnostic {
    /// A package has no name.
    public static let missingPackageName = "ecore.load.missingPackageName"
    /// A package has no namespace URI.
    public static let missingNamespaceURI = "ecore.load.missingNamespaceURI"
    /// A package has no namespace prefix.
    public static let missingNamespacePrefix = "ecore.load.missingNamespacePrefix"
    /// A named element has no name.
    public static let missingElementName = "ecore.load.missingElementName"
}
