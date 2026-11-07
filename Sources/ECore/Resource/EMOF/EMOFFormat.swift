//
// EMOFFormat.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Reads and writes metamodels in EMOF (`.emof`), as the Eclipse Modeling Framework does.
///
/// An EMOF document describes the same metamodel as an Ecore document in the vocabulary of
/// the OMG Meta Object Facility (see ``EMOFSyntax`` for the mapping). A document is read into
/// native packages, as an Ecore document is, and native packages are written in the form that
/// EMF's EMOF resource writes:
///
/// - an `xmi:XMI` element in the XMI 2.0 namespace of EMF, holding one `emof:Package` per root
///   package, followed by the tags of the metamodel;
/// - `xmi:type` naming the kind of each type, and an `xmi:id` on every element, made of the
///   names of the element and its containers joined by dots (`library.Book.title`);
/// - references within the document as identifiers, and references to other documents,
///   including the primitive types, as `href` child elements;
/// - everything that EMOF cannot express in an `xmi:Extension` whose `extender` is the Ecore
///   namespace.
///
/// The writer aims at documents that EMF loads with its EMOF resource factory. It assumes
/// that references to other metamodels are resolved by EMF through their URIs as written,
/// that is, a reference to another Ecore document keeps the Ecore fragment of its target,
/// and that identifiers made unique by a suffix (as for overloaded operations) are acceptable.
///
/// When reading, a property is an attribute if its type is a data type or an enumeration and a
/// reference otherwise, as in EMF. The `xmi:id` of every element is kept, as EMF keeps it. A tag
/// becomes an annotation, with the source of the EMOF namespace, of the first element it tags,
/// referring to the others. CMOF documents are recognised but not read.
///
/// ```swift
/// let read = try await EMOFFormat.read(url: emofURL, resourceSet: resourceSet)
/// let written = EMOFFormat.write(read.packages)
/// ```
public enum EMOFFormat {
    /// The conventional file extension of EMOF documents, without the leading dot.
    public static let fileExtension = EMOFSyntax.fileExtension

    // MARK: - Sniffing

    /// Whether a document is an EMOF document.
    ///
    /// The start of the document is examined: it is EMOF if its root element is in an EMOF
    /// namespace, or is an `xmi:XMI` element that declares one.
    ///
    /// - Parameter data: The document, or at least its beginning.
    /// - Returns: `true` if the document is an EMOF document.
    public static func sniff(data: Data) -> Bool {
        guard let root = UMLFormat.rootTag(of: data) else { return false }
        return isEMOF(root: root)
    }

    /// Whether the root element of a document makes it an EMOF document.
    ///
    /// - Parameter root: The start tag of the root element.
    /// - Returns: `true` if the element is in an EMOF namespace, or is an `xmi:XMI` element
    ///   that declares one.
    static func isEMOF(root: ModelFormatSniffing.StartTag) -> Bool {
        if root.isXMIWrapper || root.isOMGXMIWrapper {
            return root.namespaces.values.contains(where: EMOFSyntax.namespaceURIs.contains)
        }
        let prefix = XMLTree.parts(of: root.name).prefix
        return root.namespaces[prefix].map(EMOFSyntax.namespaceURIs.contains) ?? false
    }

    // MARK: - Reading

    /// Reads an EMOF document from a file or another location of the resource set.
    ///
    /// - Parameters:
    ///   - url: The location of the document.
    ///   - resourceSet: The resource set that receives the resource and the packages.
    ///   - options: The policies with which the metamodel is loaded (default policies).
    /// - Returns: The resource of the native packages, the packages, and what the reader reported.
    /// - Throws: The errors of ``read(data:uri:resourceSet:options:)`` or of the URI handler.
    public static func read(
        url: URL, resourceSet: ResourceSet, options: EcoreLoadOptions = EcoreLoadOptions()
    ) async throws -> ModelDocumentReadResult {
        let uri = URIReference.canonicalise(url.absoluteString)
        return try await read(
            data: try await resourceSet.readDocument(uri: uri), uri: uri, resourceSet: resourceSet, options: options)
    }

    /// Reads an EMOF document from its bytes.
    ///
    /// The document is translated into the Ecore document it describes, which is loaded as
    /// native packages into the resource set under the URI of the document. Every root
    /// package with a namespace URI is registered as a metamodel.
    ///
    /// - Parameters:
    ///   - data: The bytes of the document.
    ///   - uri: The URI of the document.
    ///   - resourceSet: The resource set that receives the resource and the packages.
    ///   - options: The policies with which the metamodel is loaded (default policies).
    /// - Returns: The resource of the native packages, the packages, and what the reader reported.
    /// - Throws: ``EMOFError`` if the document is not EMOF or is CMOF, or ``XMIError`` if it
    ///   is not well-formed or its metamodel cannot be loaded.
    public static func read(
        data: Data, uri: String, resourceSet: ResourceSet, options: EcoreLoadOptions = EcoreLoadOptions()
    ) async throws -> ModelDocumentReadResult {
        let uri = URIReference.canonicalise(uri)
        let ecore = try translate(data: data, uri: uri)
        let resource = try await resourceSet.loadEcoreResource(
            data: Data(ecore.text.utf8), uri: uri, enableDebugging: false, options: options)
        let packages = await resource.getRootObjects().compactMap { $0 as? EPackage }
        for package in packages where !package.nsURI.isEmpty {
            await resourceSet.registerMetamodel(package)
        }
        return ModelDocumentReadResult(
            resource: resource, packages: packages, diagnostics: ecore.diagnostics + (await resource.loadDiagnostics))
    }

    /// Translates an EMOF document into the text of the Ecore document it describes.
    ///
    /// - Parameters:
    ///   - data: The bytes of the EMOF document.
    ///   - uri: The URI of the document, for diagnostics.
    /// - Returns: The Ecore text and what the translation could not keep.
    /// - Throws: ``EMOFError`` if the document is not EMOF or is CMOF, or ``XMIError`` if it
    ///   is not well-formed.
    public static func translate(data: Data, uri: String) throws -> ModelDocumentWriteResult {
        var reader = EMOFReader(document: uri)
        let text = try reader.translate(XMLTree.root(of: data))
        return ModelDocumentWriteResult(text: text, diagnostics: reader.diagnostics)
    }

    // MARK: - Writing

    /// Writes native packages as an EMOF document.
    ///
    /// The packages are written as an Ecore document first (see
    /// ``XMISerializer/serialize(_:relativeTo:)-(_,URL?)``), which is then translated into EMOF.
    ///
    /// - Parameters:
    ///   - packages: The root packages, in document order.
    ///   - documentURL: The location that the document will have, against which references
    ///     to other documents are computed, or `nil`.
    /// - Returns: The text of the EMOF document; writing reports nothing.
    public static func write(_ packages: [EPackage], relativeTo documentURL: URL? = nil) -> ModelDocumentWriteResult {
        guard !packages.isEmpty else { return ModelDocumentWriteResult(text: "") }
        let ecore = XMISerializer(options: .emf).serialize(packages, relativeTo: documentURL)
        guard let root = try? XMLTree.root(of: Data(ecore.utf8)) else { return ModelDocumentWriteResult(text: "") }
        var writer = EMOFWriter()
        return ModelDocumentWriteResult(text: writer.translate(root))
    }

    /// Writes the native packages of a resource as an EMOF document.
    ///
    /// - Parameters:
    ///   - resource: A resource whose root objects are all native packages.
    ///   - documentURL: The location that the document will have, or `nil`.
    /// - Returns: The text of the EMOF document.
    /// - Throws: ``ModelIOError/notAMetamodel(_:)`` if a root object is not a native package.
    public static func write(_ resource: Resource, relativeTo documentURL: URL? = nil) async throws
        -> ModelDocumentWriteResult
    {
        let roots = await resource.getRootObjects()
        let packages = roots.compactMap { $0 as? EPackage }
        guard !roots.isEmpty, packages.count == roots.count else {
            throw ModelIOError.notAMetamodel(documentURL?.absoluteString ?? resource.uri)
        }
        return write(packages, relativeTo: documentURL)
    }
}
