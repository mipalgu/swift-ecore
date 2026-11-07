//
// UMLFormat.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation
import SwiftXML

/// Reads and writes UML models (`.uml`) as instances of the bundled Eclipse UML2 metamodel.
///
/// A UML model is an XMI document whose objects are instances of the classes of UML. It is
/// read with the Eclipse UML2 5.x metamodel that this package ships (see ``UMLMetamodel``),
/// whichever of the Eclipse UML2 or OMG UML namespaces it uses (see ``UMLNamespaces``), and in
/// either the EMF or the OMG dialect of XMI (see ``XMIVersion``). Its objects can then be
/// inspected and queried like those of any other model.
///
/// ## Profiles and stereotype applications
///
/// A stereotype application is a root object of the document, next to the model, whose class
/// is a stereotype of a profile, defined by the Ecore package that Eclipse UML2 generates for
/// the profile. The application is read as an instance of the class of that package if the
/// package is
///
/// - registered with the resource set under its namespace URI,
/// - embedded in a profile in the same document, or
/// - embedded in a profile in the document that the `xsi:schemaLocation` of the model names
///   for its namespace.
///
/// Otherwise it is read as an object of a class made up from the document, as an XMI parser
/// reads an object of an unknown class, and a warning with the code
/// ``ModelDocumentDiagnostic/unresolvedProfile`` names its namespace. The read does not fail.
/// Packages found in documents are registered with the resource set.
///
/// ## Writing
///
/// A model is written in the layout of Eclipse UML2 5.x (``XMISerializationOptions/uml``):
/// XMI 2.5 with `xmi:type`, keeping the `xmi:id` of every object that was read with one, so
/// that references between the objects of the model are written by identifier.
///
/// ```swift
/// let resourceSet = ResourceSet()
/// let read = try await UMLFormat.read(url: modelURL, resourceSet: resourceSet)
/// for diagnostic in read.diagnostics { print(diagnostic.message) }
/// let written = try await UMLFormat.write(read.resource, relativeTo: copyURL)
/// ```
///
/// CMOF metamodels (the complete MOF form in which the OMG publishes the UML metamodel
/// itself) are not read.
public enum UMLFormat {
    /// The conventional file extension of UML models, without the leading dot.
    public static let fileExtension = UMLNamespaces.fileExtension

    /// The attribute in which a document names the documents that define its namespaces.
    static let schemaLocationAttribute = "xsi:schemaLocation"

    /// The namespaces of a UML model that are not those of profiles.
    static var nonProfileNamespaces: Set<String> {
        XMIVersion.namespaceURIs.union([
            EcoreURI.xsiNamespace.rawValue, EcoreURI.ecoreNamespace.rawValue, UMLNamespaces.uml,
            UMLNamespaces.types,
        ]).union(UMLNamespaces.metamodelAliases)
    }

    // MARK: - Sniffing

    /// Whether a document is a UML model.
    ///
    /// The start of the document is examined: it is a UML model if its root element is in
    /// a UML namespace (see ``UMLNamespaces``) or is an `xmi:XMI` element that declares one.
    ///
    /// - Parameter data: The document, or at least its beginning.
    /// - Returns: `true` if the document is a UML model.
    public static func sniff(data: Data) -> Bool {
        guard let root = rootTag(of: data) else { return false }
        return isUML(root: root)
    }

    /// Whether the root element of a document makes it a UML model.
    ///
    /// - Parameter root: The start tag of the root element.
    /// - Returns: `true` if the element is in a UML namespace, or is an `xmi:XMI` element that
    ///   declares one.
    static func isUML(root: ModelFormatSniffing.StartTag) -> Bool {
        let umlNamespaces = Set([UMLNamespaces.uml] + UMLNamespaces.metamodelAliases)
        if root.isXMIWrapper || root.isOMGXMIWrapper {
            return root.namespaces.values.contains { umlNamespaces.contains($0) }
        }
        let prefix = root.name.split(separator: CrossReferenceSyntax.qualifierSeparator).dropLast().first
            .map(String.init) ?? ""
        return root.namespaces[prefix].map(umlNamespaces.contains) ?? false
    }

    /// The start tag of the root element of a document.
    ///
    /// - Parameter data: The document, or at least its beginning.
    /// - Returns: The start tag, or `nil` if the document does not start like XML.
    static func rootTag(of data: Data) -> ModelFormatSniffing.StartTag? {
        let text = String(decoding: data.prefix(ModelFormatSniffing.prefixLength), as: UTF8.self)
        var scanner = ModelFormatSniffing.Scanner(text)
        scanner.skipByteOrderMark()
        scanner.skipWhitespace()
        guard scanner.current == ModelFormatSniffing.tagOpener else { return nil }
        return scanner.nextStartTag()
    }

    // MARK: - Reading

    /// Reads a UML model from a file or another location of the resource set.
    ///
    /// - Parameters:
    ///   - url: The location of the model.
    ///   - resourceSet: The resource set that receives the resource and the metamodels.
    ///   - options: The options with which the XMI parser reads (default options).
    /// - Returns: The resource of the model and what the reader reported.
    /// - Throws: The error of the URI handler, of ``UMLMetamodel/register(in:)``, or of the
    ///   XMI parser.
    public static func read(
        url: URL, resourceSet: ResourceSet, options: ModelIO.LoadOptions = ModelIO.LoadOptions()
    ) async throws -> ModelDocumentReadResult {
        let uri = URIReference.canonicalise(url.absoluteString)
        return try await read(
            data: try await resourceSet.readDocument(uri: uri), uri: uri, resourceSet: resourceSet, options: options)
    }

    /// Reads a UML model from its bytes.
    ///
    /// The UML metamodel is registered with the resource set first (see
    /// ``UMLMetamodel/register(in:)``), then the profiles of the stereotype applications are
    /// looked for (see ``UMLFormat``), and the document is read by an ``XMIParser``.
    ///
    /// - Parameters:
    ///   - data: The bytes of the document.
    ///   - uri: The URI of the document, against which relative references are resolved.
    ///   - resourceSet: The resource set that receives the resource and the metamodels.
    ///   - options: The options with which the XMI parser reads (default options).
    /// - Returns: The resource of the model and what the reader reported.
    /// - Throws: ``XMIError`` if the document is not well-formed XMI, or the error of
    ///   ``UMLMetamodel/register(in:)``.
    public static func read(
        data: Data, uri: String, resourceSet: ResourceSet, options: ModelIO.LoadOptions = ModelIO.LoadOptions()
    ) async throws -> ModelDocumentReadResult {
        let uri = URIReference.canonicalise(uri)
        let read = try await readResource(data: data, uri: uri, resourceSet: resourceSet, options: options)
        var diagnostics = read.profileDiagnostics
        diagnostics += await read.resource.loadDiagnostics
        diagnostics += ModelDocumentDiagnostic.diagnostics(from: read.conversion, document: uri)
        return ModelDocumentReadResult(resource: read.resource, diagnostics: diagnostics)
    }

    /// Reads a UML model into a resource, keeping the kinds of diagnostics apart.
    ///
    /// - Parameters:
    ///   - data: The bytes of the document.
    ///   - uri: The canonical URI of the document.
    ///   - resourceSet: The resource set that receives the resource and the metamodels.
    ///   - options: The options with which the XMI parser reads.
    /// - Returns: The resource, the warnings about profiles that cannot be found or read, and
    ///   what the XMI parser could not keep.
    /// - Throws: ``XMIError`` if the document is not well-formed XMI, or the error of
    ///   ``UMLMetamodel/register(in:)``.
    static func readResource(
        data: Data, uri: String, resourceSet: ResourceSet, options: ModelIO.LoadOptions
    ) async throws -> (resource: Resource, profileDiagnostics: [SourceDiagnostic], conversion: ConversionDiagnostics) {
        try await UMLMetamodel.register(in: resourceSet)
        let profileDiagnostics = await resolveProfiles(of: data, uri: uri, in: resourceSet)
        let parser = XMIParser(
            resourceSet: resourceSet, enableDebugging: options.enableDebugging,
            referenceParsing: options.referenceParsing, ecoreLoadOptions: options.ecoreLoadOptions)
        await parser.retainFabricatedNamespaces()
        let resource = try await parser.parse(data, uri: uri)
        return (resource, profileDiagnostics, await parser.diagnostics)
    }

    // MARK: - Writing

    /// Writes a UML model in the layout of Eclipse UML2 5.x.
    ///
    /// - Parameters:
    ///   - resource: The resource of the model.
    ///   - documentURL: The location that the document will have, against which relative
    ///     references are computed, or `nil` to compute them against the resource itself.
    ///   - options: The layout (default ``XMISerializationOptions/uml``).
    /// - Returns: The text of the document and what could not be kept.
    /// - Throws: The error of the ``XMISerializer``.
    public static func write(
        _ resource: Resource, relativeTo documentURL: URL? = nil, options: XMISerializationOptions = .uml
    ) async throws -> ModelDocumentWriteResult {
        var warnings = ConversionDiagnostics()
        let text = try await serialise(resource, relativeTo: documentURL, options: options, diagnostics: &warnings)
        let document = documentURL.map { URIReference.canonicalise($0.absoluteString) } ?? resource.uri
        return ModelDocumentWriteResult(
            text: text, diagnostics: ModelDocumentDiagnostic.diagnostics(from: warnings, document: document))
    }

    /// Renders a UML model as text, recording what cannot be kept.
    ///
    /// - Parameters:
    ///   - resource: The resource of the model.
    ///   - documentURL: The location that the document will have, or `nil`.
    ///   - options: The layout.
    ///   - diagnostics: Receives a ``ConversionWarning`` for everything that cannot be kept.
    /// - Returns: The text of the document.
    /// - Throws: The error of the ``XMISerializer``.
    static func serialise(
        _ resource: Resource, relativeTo documentURL: URL?, options: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        let serializer = XMISerializer(options: options)
        if let documentURL {
            return try await serializer.serialize(resource, relativeTo: documentURL, diagnostics: &diagnostics)
        }
        return try await serializer.serialize(resource, diagnostics: &diagnostics)
    }

    // MARK: - Profiles

    /// Registers the Ecore packages of the profiles that a document applies, where they can be found.
    ///
    /// - Parameters:
    ///   - data: The bytes of the document.
    ///   - uri: The URI of the document.
    ///   - resourceSet: The resource set with which the packages are registered.
    /// - Returns: A warning for every profile namespace whose package cannot be found.
    static func resolveProfiles(of data: Data, uri: String, in resourceSet: ResourceSet) async -> [SourceDiagnostic] {
        guard let root = try? XMLTree.root(of: data) else { return [] }
        let declared = XMLTree.declaredNamespaces(of: root)
        var diagnostics: [SourceDiagnostic] = []
        var pending: [String] = []
        for (_, namespace) in declared.sorted(by: { $0.key < $1.key })
        where !nonProfileNamespaces.contains(namespace) && !pending.contains(namespace) {
            if await resourceSet.getMetamodel(uri: namespace) != nil { continue }
            if let eclipse = UMLNamespaces.eclipseNamespace(for: namespace),
                await resourceSet.getMetamodel(uri: eclipse) != nil
            {
                continue
            }
            pending.append(namespace)
        }
        guard !pending.isEmpty else { return [] }
        var definitions = profileDefinitions(in: root)
        let locations = schemaLocations(of: root)
        for namespace in pending where definitions[namespace] == nil {
            guard let location = locations[namespace] else { continue }
            let documentURI = URIReference.resolve(
                String(location.split(separator: CrossReferenceSyntax.fragmentSeparator).first ?? ""), against: uri)
            guard let profileData = try? await resourceSet.readDocument(uri: documentURI),
                let profileRoot = try? XMLTree.root(of: profileData)
            else { continue }
            for (found, element) in profileDefinitions(in: profileRoot) where definitions[found] == nil {
                definitions[found] = element
            }
        }
        for namespace in pending {
            guard let element = definitions[namespace] else {
                diagnostics.append(SourceDiagnostic(
                    severity: .warning, code: ModelDocumentDiagnostic.unresolvedProfile,
                    message: "The profile of the namespace '\(namespace)' is neither registered nor found; "
                        + "its stereotype applications are read without their profile",
                    document: uri))
                continue
            }
            do {
                let package = try await profilePackage(from: element, namespace: namespace)
                await resourceSet.registerMetamodel(package, uri: namespace)
            } catch {
                diagnostics.append(SourceDiagnostic(
                    severity: .warning, code: ModelDocumentDiagnostic.unreadableProfile,
                    message: "The profile of the namespace '\(namespace)' cannot be read: \(error)", document: uri))
            }
        }
        return diagnostics
    }

    /// The documents that the `xsi:schemaLocation` of an element names, by namespace.
    ///
    /// - Parameter element: The root element of a document.
    /// - Returns: The location, possibly with a fragment, for each namespace listed.
    static func schemaLocations(of element: XElement) -> [String: String] {
        guard let value = element[schemaLocationAttribute] else { return [:] }
        let words = value.split(whereSeparator: \.isWhitespace).map(String.init)
        var locations: [String: String] = [:]
        for index in stride(from: 0, to: words.count - 1, by: 2) {
            locations[words[index]] = words[index + 1]
        }
        return locations
    }

    /// The Ecore packages embedded in the profiles of a document, by namespace URI.
    ///
    /// Eclipse UML2 keeps the Ecore package of each version of a profile as the `contents`
    /// of an annotation of the profile. Every element that is or is typed `ecore:EPackage` and
    /// has a namespace URI is taken as such a package; the first of a namespace is kept.
    ///
    /// - Parameter root: The root element of a document.
    /// - Returns: The elements of the embedded packages.
    static func profileDefinitions(in root: XElement) -> [String: XElement] {
        let packageType = CrossReferenceSyntax.ecorePrefix + String(CrossReferenceSyntax.qualifierSeparator)
            + EcoreClassifier.ePackage.rawValue
        var definitions: [String: XElement] = [:]
        var stack = [root]
        while let element = stack.popLast() {
            if element.name == packageType || XMIParser.typeQualifier(of: element) == packageType,
                let namespace = element[EcoreFeatureName.nsURI.rawValue], definitions[namespace] == nil
            {
                definitions[namespace] = element
            }
            stack += element.children.reversed()
        }
        return definitions
    }

    /// Reads the embedded Ecore package of a profile as a native package.
    ///
    /// The package is read as an Ecore document of its own. Its references to the classes of
    /// UML, written as references into an Eclipse UML2 namespace, resolve to the classes of
    /// the bundled UML metamodel.
    ///
    /// - Parameters:
    ///   - element: The element of the embedded package.
    ///   - namespace: The namespace URI of the package.
    /// - Returns: The native package.
    /// - Throws: ``XMIError`` if the package cannot be read.
    static func profilePackage(from element: XElement, namespace: String) async throws -> EPackage {
        let (uml, types) = try await UMLMetamodel.packages()
        let profileSet = ResourceSet()
        for uri in [UMLNamespaces.uml] + UMLNamespaces.metamodelAliases {
            await profileSet.createResource(uri: uri).registerNativePackage(uml)
        }
        await profileSet.createResource(uri: UMLNamespaces.types).registerNativePackage(types)
        let text = XMIDocumentSyntax.xmlDeclaration + "\n" + standaloneText(of: element)
        let resource = try await profileSet.loadEcoreResource(
            data: Data(text.utf8), uri: namespace, enableDebugging: false,
            options: EcoreLoadOptions(unresolvedReferences: .keepAsProxies, tolerant: true))
        guard let package = await resource.getRootObjects().first as? EPackage else { throw XMIError.noRootObject }
        return package
    }

    /// The text of an element as the root of a document of its own.
    ///
    /// The namespaces of XMI, XML Schema instances and Ecore are declared on the element
    /// unless it declares them itself.
    ///
    /// - Parameter element: The element.
    /// - Returns: The text of the element with the namespace declarations it needs.
    static func standaloneText(of element: XElement) -> String {
        let text = element.serialized
        let required = [
            (CrossReferenceSyntax.xmiPrefix, EcoreURI.xmiNamespace.rawValue),
            (CrossReferenceSyntax.xsiPrefix, EcoreURI.xsiNamespace.rawValue),
            (CrossReferenceSyntax.ecorePrefix, EcoreURI.ecoreNamespace.rawValue),
        ]
        let declarations = required.filter { element[CrossReferenceSyntax.namespaceAttribute(for: $0.0)] == nil }
            .map { " \(CrossReferenceSyntax.namespaceAttribute(for: $0.0))=\"\($0.1)\"" }.joined()
        let nameEnd = text.index(text.startIndex, offsetBy: 1 + element.name.count)
        return String(text[..<nameEnd]) + declarations + String(text[nameEnd...])
    }
}

extension ModelFormatSniffing.StartTag {
    /// Whether the element is an `xmi:XMI` wrapper in the namespace of an OMG version of XMI.
    var isOMGXMIWrapper: Bool {
        guard name == CrossReferenceSyntax.xmiPrefix + String(CrossReferenceSyntax.qualifierSeparator)
            + XMIDocumentSyntax.multipleRootElement
        else { return false }
        return namespaces[CrossReferenceSyntax.xmiPrefix].map(XMIVersion.namespaceURIs.contains) ?? false
    }
}
