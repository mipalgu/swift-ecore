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
/// that cannot be found is replaced by a default type, and a document without a name is
/// rejected. As in EMF, a root package without a namespace URI or prefix loads in either
/// mode; the omission is reported in ``Resource/loadDiagnostics``.
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

    /// Whether a document that lacks a name is loaded nonetheless.
    ///
    /// A missing package name is then reported in ``Resource/loadDiagnostics`` instead of
    /// aborting the load, and an element without a name is loaded with an empty name. In
    /// tolerant mode, a missing namespace URI or prefix of a root package is reported as an
    /// error; otherwise it is reported as a warning.
    public var tolerant: Bool

    /// How a metamodel in KM3 is read.
    ///
    /// ``ModelIO`` reads KM3 documents, including the metamodels it registers, with these
    /// options. By default, the primitive types of KM3 stand for the built-in Ecore data
    /// types; ``KM3ReadOptions/declaredDataTypes`` keeps every declared data type instead.
    public var km3Options: KM3ReadOptions

    /// How a metamodel is imported from an ASDL description.
    ///
    /// ``ModelIO`` reads ASDL documents with these options, which supply the package name,
    /// namespace URI and prefix where a description has none, and the mapping of ASDL types.
    public var asdlOptions: ASDLImportOptions

    /// How a metamodel is inferred from a Langium grammar.
    ///
    /// ``ModelIO`` reads Langium grammars with these options, which supply the package name,
    /// namespace URI and prefix where a grammar has none.
    public var langiumOptions: LangiumImportOptions

    /// How the generated packages of an Xtext grammar are imported.
    ///
    /// ``ModelIO`` reads Xtext grammars with these options, which can override the name,
    /// namespace URI and prefix of the generated package.
    public var xtextOptions: XtextImportOptions

    /// How a metamodel is imported from an SDF3 syntax definition or a Stratego signature.
    ///
    /// ``ModelIO`` reads SDF3 documents with these options, which supply the package name,
    /// namespace URI and prefix where a module has none.
    public var sdf3Options: SDF3ImportOptions

    /// Creates load options.
    ///
    /// - Parameters:
    ///   - unresolvedReferences: How unresolved classifier references load (default: ``UnresolvedReferences/useDefaults``).
    ///   - tolerant: Whether missing names are reported instead of aborting the load (default: `false`).
    ///   - km3Options: How a metamodel in KM3 is read (default: ``KM3ReadOptions/standard``).
    ///   - asdlOptions: How a metamodel is imported from ASDL (default options).
    ///   - langiumOptions: How a metamodel is inferred from a Langium grammar (default options).
    ///   - xtextOptions: How the packages of an Xtext grammar are imported (default options).
    ///   - sdf3Options: How a metamodel is imported from SDF3 (default options).
    public init(
        unresolvedReferences: UnresolvedReferences = .useDefaults, tolerant: Bool = false,
        km3Options: KM3ReadOptions = .standard, asdlOptions: ASDLImportOptions = ASDLImportOptions(),
        langiumOptions: LangiumImportOptions = LangiumImportOptions(),
        xtextOptions: XtextImportOptions = XtextImportOptions(), sdf3Options: SDF3ImportOptions = SDF3ImportOptions()
    ) {
        self.unresolvedReferences = unresolvedReferences
        self.tolerant = tolerant
        self.km3Options = km3Options
        self.asdlOptions = asdlOptions
        self.langiumOptions = langiumOptions
        self.xtextOptions = xtextOptions
        self.sdf3Options = sdf3Options
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
    /// A package without a namespace URI is registered under its name.
    public static let registeredUnderName = "ecore.load.registeredUnderName"

    /// The warning that a root package has no namespace URI or prefix.
    ///
    /// As in EMF, such a package loads with an empty value and is not registered under a
    /// namespace; the constraint `WellFormedNsURI` of the validator reports a missing URI.
    ///
    /// - Parameters:
    ///   - feature: ``EcoreFeatureName/nsURI`` or ``EcoreFeatureName/nsPrefix``.
    ///   - package: The name of the package.
    ///   - document: The URI of the document.
    /// - Returns: A warning with ``missingNamespaceURI`` or ``missingNamespacePrefix`` as its code.
    static func missingNamespace(_ feature: EcoreFeatureName, package: String, document: String) -> SourceDiagnostic {
        SourceDiagnostic(
            severity: .warning, code: feature == .nsURI ? missingNamespaceURI : missingNamespacePrefix,
            message: "The package '\(package)' has no '\(feature.rawValue)' and is not registered under a namespace",
            document: document)
    }

    /// The warning that a root package without a namespace URI is registered under its name.
    ///
    /// As the ATL tool chain does, ``ModelIO`` registers a root package of a text metamodel,
    /// such as KM3, that has no namespace URI under its name with the resource set, so that
    /// documents of the same load can refer to it. The package itself keeps its empty URI.
    ///
    /// - Parameters:
    ///   - package: The name of the package.
    ///   - document: The URI of the document.
    /// - Returns: A warning with ``registeredUnderName`` as its code.
    static func registeredUnderNameWarning(package: String, document: String) -> SourceDiagnostic {
        SourceDiagnostic(
            severity: .warning, code: registeredUnderName,
            message: "The package '\(package)' has no '\(EcoreFeatureName.nsURI.rawValue)' "
                + "and is registered under its name in this resource set",
            document: document)
    }
}
