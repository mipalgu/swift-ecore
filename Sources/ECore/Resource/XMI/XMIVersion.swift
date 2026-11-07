//
// XMIVersion.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// The versions of XMI in which documents are read and written, with their namespaces.
///
/// The Eclipse Modeling Framework writes XMI 2.0, whose namespace `http://www.omg.org/XMI` it
/// keeps for every document it writes. Documents of other tools, and of Eclipse UML2, are
/// written in later versions of XMI, each of which the Object Management Group (OMG)
/// publishes under its own namespace. The raw value of each case is the text of the
/// `xmi:version` attribute that documents of that version carry.
///
/// | Version | `xmi:version` | Namespace URI |
/// |---|---|---|
/// | XMI 2.0 (EMF) | `2.0` | `http://www.omg.org/XMI` |
/// | XMI 2.1 | `2.1` | `http://schema.omg.org/spec/XMI/2.1` |
/// | XMI 2.4 | `20100901` | `http://www.omg.org/spec/XMI/20100901` |
/// | XMI 2.4.1 | `20110701` | `http://www.omg.org/spec/XMI/20110701` |
/// | XMI 2.5 and 2.5.1 | `20131001` | `http://www.omg.org/spec/XMI/20131001` |
///
/// A document is read in the OMG dialect when its XMI namespace is that of a version later
/// than 2.0 (see ``isOMG``): its `xmi:Documentation` and `xmi:Extension` elements are then
/// skipped rather than read as objects.
public enum XMIVersion: String, CaseIterable, Sendable {
    /// XMI 2.0, the version that the Eclipse Modeling Framework reads and writes.
    case v2_0 = "2.0"

    /// XMI 2.1.
    case v2_1 = "2.1"

    /// XMI 2.4.
    case v2_4 = "20100901"

    /// XMI 2.4.1.
    case v2_4_1 = "20110701"

    /// XMI 2.5 and XMI 2.5.1, which share a namespace.
    case v2_5 = "20131001"

    /// The namespace URI of the version.
    public var namespaceURI: String {
        switch self {
        case .v2_0: return EcoreURI.xmiNamespace.rawValue
        case .v2_1: return "http://schema.omg.org/spec/XMI/2.1"
        case .v2_4, .v2_4_1, .v2_5: return "http://www.omg.org/spec/XMI/" + rawValue
        }
    }

    /// The text of the `xmi:version` attribute of documents of this version.
    public var versionText: String { rawValue }

    /// Whether documents of this version are read and written in the OMG dialect.
    ///
    /// Every version except ``v2_0``, the version of the Eclipse Modeling Framework, is.
    public var isOMG: Bool { self != .v2_0 }

    /// Creates the version whose namespace a URI is.
    ///
    /// - Parameter namespaceURI: The URI bound to the `xmi` prefix of a document.
    /// - Returns: The version, or `nil` if the URI is not the namespace of a known version.
    public init?(namespaceURI: String) {
        guard let version = Self.allCases.first(where: { $0.namespaceURI == namespaceURI }) else { return nil }
        self = version
    }

    /// The namespace URIs of all known versions.
    public static let namespaceURIs: Set<String> = Set(allCases.map(\.namespaceURI))
}

/// The attribute that names the class of an element whose class differs from the declared type.
///
/// EMF writes `xsi:type` by default and reads both attributes; Eclipse UML2 and documents in
/// the OMG dialect use `xmi:type`. The raw value of each case is the qualified attribute name.
public enum XMITypeAttribute: String, CaseIterable, Sendable {
    /// The `xsi:type` attribute of XML Schema, which EMF writes by default.
    case xsi = "xsi:type"

    /// The `xmi:type` attribute of XMI, which Eclipse UML2 and other tools write.
    case xmi = "xmi:type"
}

/// The elements and attributes of the XMI namespace that only the OMG dialect uses.
enum XMIDialectSyntax {
    /// The local names of the elements that document the exporter of a document.
    ///
    /// XMI 2.1 spells the element `Documentation`; some exporters spell it in lower case.
    static let documentationElements: Set<String> = ["Documentation", "documentation"]

    /// The local name of the element that holds a tool-specific extension, as XMI spells it.
    static let extensionElement = "Extension"

    /// The local names of the elements that hold tool-specific extensions.
    static let extensionElements: Set<String> = [extensionElement, "extension"]

    /// The attribute of an element that refers to an object of the same document by identifier.
    static let idref = "xmi:idref"

    /// The attribute of an element that names a tool whose extension the element holds.
    static let extender = "extender"

    /// Whether an element of the XMI namespace holds documentation or an extension.
    ///
    /// - Parameter qualifiedName: The qualified name of an element, such as `xmi:Extension`.
    /// - Returns: `true` if the prefix is `xmi` and the local name names documentation or an extension.
    static func isDocumentationOrExtension(_ qualifiedName: String) -> Bool {
        let prefix = CrossReferenceSyntax.xmiPrefix + String(CrossReferenceSyntax.qualifierSeparator)
        guard qualifiedName.hasPrefix(prefix) else { return false }
        let local = String(qualifiedName.dropFirst(prefix.count))
        return documentationElements.contains(local) || extensionElements.contains(local)
    }
}
