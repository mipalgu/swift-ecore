//
// ModelDocumentResult.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// What a reader of a model or metamodel document produces.
///
/// The readers of the formats beyond the native XMI, Ecore and JSON formats, such as
/// ``EMOFFormat`` and ``UMLFormat``, return their contents in this one shape, so that they can
/// be used interchangeably: the resource that holds the objects of the document, the root
/// packages if the document is a metamodel, and what the reader reported.
public struct ModelDocumentReadResult: Sendable {
    /// The resource that holds the objects of the document.
    ///
    /// For a metamodel, the root objects of the resource are its native packages.
    public let resource: Resource

    /// The root packages of a metamodel document in document order, or none for a model.
    public let packages: [EPackage]

    /// What the reader reported, such as classes that no metamodel defines or profiles that
    /// cannot be found; none of them prevented the document from being read.
    public let diagnostics: [SourceDiagnostic]

    /// Creates the result of a read.
    ///
    /// - Parameters:
    ///   - resource: The resource that holds the objects of the document.
    ///   - packages: The root packages of a metamodel document, or none for a model.
    ///   - diagnostics: What the reader reported.
    public init(resource: Resource, packages: [EPackage] = [], diagnostics: [SourceDiagnostic] = []) {
        self.resource = resource
        self.packages = packages
        self.diagnostics = diagnostics
    }
}

/// What a writer of a model or metamodel document produces.
public struct ModelDocumentWriteResult: Sendable, Equatable {
    /// The text of the document.
    public let text: String

    /// What the writer could not keep, or wrote less faithfully than it is held.
    public let diagnostics: [SourceDiagnostic]

    /// Creates the result of a write.
    ///
    /// - Parameters:
    ///   - text: The text of the document.
    ///   - diagnostics: What the writer reported.
    public init(text: String, diagnostics: [SourceDiagnostic] = []) {
        self.text = text
        self.diagnostics = diagnostics
    }
}

/// The diagnostic codes of the readers and writers of documents in further formats.
public enum ModelDocumentDiagnostic {
    /// A warning of the XMI parser or serialiser, such as a class that no metamodel defines.
    public static let conversionWarning = "document.conversion"

    /// A stereotype application whose profile is neither in the document nor registered.
    public static let unresolvedProfile = "uml.profile.unresolved"

    /// A profile definition that was found but could not be read.
    public static let unreadableProfile = "uml.profile.unreadable"

    /// An EMOF element or value that has no equivalent in Ecore and was left out.
    public static let unsupportedEMOF = "emof.unsupported"

    /// Converts the warnings of a conversion into diagnostics.
    ///
    /// - Parameters:
    ///   - warnings: The warnings of the XMI parser or serialiser.
    ///   - document: The URI of the document, if known.
    /// - Returns: One warning diagnostic with the code ``conversionWarning`` per warning.
    static func diagnostics(from warnings: ConversionDiagnostics, document: String?) -> [SourceDiagnostic] {
        warnings.warnings.map {
            SourceDiagnostic(severity: .warning, code: conversionWarning, message: $0.message, document: document)
        }
    }
}
