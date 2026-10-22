//
// ModelIO.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// Loads and saves models and metamodels in any of the supported document formats.
///
/// `ModelIO` chooses the parser or serialiser from a ``ModelFormat``, which is either given
/// explicitly or detected from the file name and, failing that, from the contents of the
/// document. It registers metamodels with a ``ResourceSet`` before a model is read, so that
/// the model is read with the classes of those metamodels, and it collects what a conversion
/// could not keep as ``ConversionDiagnostics``.
///
/// - An Ecore document is loaded as native packages (see ``ResourceSet/loadEcoreResource(uri:)``)
///   and every root package is registered as a metamodel, together with its nested packages.
/// - An XMI document is read by an ``XMIParser`` with the resource set.
/// - A JSON document is read by a ``JSONParser`` with the resource set. Unless
///   ``LoadOptions/requiresMetamodel`` says otherwise, a registered metamodel must then
///   define the classes of the document whenever the resource set has a metamodel registered.
///
/// ## Example
///
/// ```swift
/// let resourceSet = ResourceSet()
/// let loaded = try await ModelIO.load(
///     url: modelURL, resourceSet: resourceSet, metamodels: [metamodelURL])
/// var diagnostics = loaded.diagnostics
/// try await ModelIO.save(loaded.resource, to: jsonURL, diagnostics: &diagnostics)
/// for warning in diagnostics.warnings { print(warning) }
/// ```
public enum ModelIO {
    /// Options that control how a document is read.
    public struct LoadOptions: Sendable, Equatable {
        /// How the reference attributes of an XMI document are read.
        public var referenceParsing: XMIReferenceParsing

        /// Whether the classes of a JSON document must be defined by a registered metamodel.
        ///
        /// `nil`, the default, requires a metamodel exactly when the resource set has a
        /// metamodel registered once the given metamodels have been registered. `true` always
        /// requires one and `false` never does, so that classes which no registered metamodel
        /// defines are synthesised from the document. See ``JSONParseOptions/requiresMetamodel``.
        public var requiresMetamodel: Bool?

        /// The policies with which Ecore documents, including metamodels, are loaded.
        public var ecoreLoadOptions: EcoreLoadOptions

        /// Whether the parsers print a trace of what they read.
        public var enableDebugging: Bool

        /// Creates load options.
        ///
        /// - Parameters:
        ///   - referenceParsing: How XMI reference attributes are read (default
        ///     ``XMIReferenceParsing/interpreted``).
        ///   - requiresMetamodel: Whether JSON classes must come from a registered metamodel;
        ///     `nil` (the default) requires one whenever a metamodel is registered.
        ///   - ecoreLoadOptions: The policies for loading Ecore documents (default policies).
        ///   - enableDebugging: Whether the parsers print a trace (default `false`).
        public init(
            referenceParsing: XMIReferenceParsing = .interpreted,
            requiresMetamodel: Bool? = nil,
            ecoreLoadOptions: EcoreLoadOptions = EcoreLoadOptions(),
            enableDebugging: Bool = false
        ) {
            self.referenceParsing = referenceParsing
            self.requiresMetamodel = requiresMetamodel
            self.ecoreLoadOptions = ecoreLoadOptions
            self.enableDebugging = enableDebugging
        }
    }

    /// A document that has been loaded.
    public struct Loaded: Sendable {
        /// The resource that holds the objects of the document.
        ///
        /// For an Ecore document, the root objects of the resource are its native packages.
        public let resource: Resource

        /// The format in which the document was read.
        public let format: ModelFormat

        /// What the parser could not keep, such as classes that no metamodel defines.
        public let diagnostics: ConversionDiagnostics

        /// The root packages of an Ecore document, in document order.
        ///
        /// Each of them has been registered as a metamodel. The list is empty for a model
        /// instance document.
        public let packages: [EPackage]

        /// Creates the description of a loaded document.
        ///
        /// - Parameters:
        ///   - resource: The resource that holds the objects of the document.
        ///   - format: The format in which the document was read.
        ///   - diagnostics: What the parser could not keep.
        ///   - packages: The root packages of an Ecore document, or none for a model instance.
        public init(
            resource: Resource, format: ModelFormat, diagnostics: ConversionDiagnostics = ConversionDiagnostics(),
            packages: [EPackage] = []
        ) {
            self.resource = resource
            self.format = format
            self.diagnostics = diagnostics
            self.packages = packages
        }
    }

    // MARK: - Metamodels

    /// Loads Ecore documents and registers their packages as metamodels.
    ///
    /// Each document is loaded into the resource set as native packages, and every root
    /// package with a namespace URI is registered under that URI, together with its nested
    /// packages. A package registered later replaces an earlier one with the same URI.
    ///
    /// - Parameters:
    ///   - urls: The locations of the Ecore documents, in registration order.
    ///   - resourceSet: The resource set with which the metamodels are registered.
    ///   - options: The policies with which the documents are loaded (default policies).
    /// - Returns: The root packages of all documents, in order.
    /// - Throws: The error of the first document that cannot be read or loaded.
    @discardableResult
    public static func registerMetamodels(
        at urls: [URL], in resourceSet: ResourceSet, options: EcoreLoadOptions = EcoreLoadOptions()
    ) async throws -> [EPackage] {
        var packages: [EPackage] = []
        for url in urls {
            let resource = try await resourceSet.loadEcoreResource(
                uri: URIReference.canonicalise(url.absoluteString), options: options)
            packages += await register(resource, in: resourceSet)
        }
        return packages
    }

    /// Registers the root packages of a native Ecore resource as metamodels.
    private static func register(_ resource: Resource, in resourceSet: ResourceSet) async -> [EPackage] {
        let packages = await resource.getRootObjects().compactMap { $0 as? EPackage }
        for package in packages where !package.nsURI.isEmpty {
            await resourceSet.registerMetamodel(package)
        }
        return packages
    }

    // MARK: - Loading

    /// Loads a model or metamodel document.
    ///
    /// The metamodels are registered first (see ``registerMetamodels(at:in:options:)``).
    /// The format is the given one, else the one that the file extension names, else the one
    /// detected from the contents of the document (see ``ModelFormat``). The document is
    /// read through the URI handlers of the resource set and its resource is added to the set.
    ///
    /// - Parameters:
    ///   - url: The location of the document.
    ///   - format: The format of the document, or `nil` (the default) to detect it.
    ///   - resourceSet: The resource set that provides the metamodels and receives the resource.
    ///   - metamodels: The locations of Ecore documents to register before the document is read.
    ///   - options: The options that control reading (default options).
    /// - Returns: The loaded document with its resource, format and diagnostics.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if the format cannot be
    ///   determined, or the error of the file system or of the parser.
    public static func load(
        url: URL,
        format: ModelFormat? = nil,
        resourceSet: ResourceSet,
        metamodels: [URL] = [],
        options: LoadOptions = LoadOptions()
    ) async throws -> Loaded {
        try await registerMetamodels(at: metamodels, in: resourceSet, options: options.ecoreLoadOptions)
        let uri = URIReference.canonicalise(url.absoluteString)
        let data = try await resourceSet.readDocument(uri: uri)
        let format = format ?? ModelFormat.detect(url: url)
        return try await load(data: data, uri: uri, format: format, resourceSet: resourceSet, options: options)
    }

    /// Loads a model or metamodel document from its bytes.
    ///
    /// The metamodels are registered first (see ``registerMetamodels(at:in:options:)``).
    /// Without an explicit format, the format is detected from the contents of the document
    /// (see ``ModelFormat/detect(data:)``).
    ///
    /// - Parameters:
    ///   - data: The bytes of the document.
    ///   - uri: The URI that the document has; relative references are resolved against it.
    ///   - format: The format of the document, or `nil` (the default) to detect it.
    ///   - resourceSet: The resource set that provides the metamodels and receives the resource.
    ///   - metamodels: The locations of Ecore documents to register before the document is read.
    ///   - options: The options that control reading (default options).
    /// - Returns: The loaded document with its resource, format and diagnostics.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if the format cannot be
    ///   determined, or the error of the parser.
    public static func load(
        data: Data,
        uri: String,
        format: ModelFormat? = nil,
        resourceSet: ResourceSet,
        metamodels: [URL] = [],
        options: LoadOptions = LoadOptions()
    ) async throws -> Loaded {
        try await registerMetamodels(at: metamodels, in: resourceSet, options: options.ecoreLoadOptions)
        let uri = URIReference.canonicalise(uri)
        guard let format = format ?? ModelFormat.detect(data: data) else {
            throw ModelFormatError.undetectableFormat(uri)
        }
        switch format {
        case .ecore:
            let resource = try await resourceSet.loadEcoreResource(
                data: data, uri: uri, enableDebugging: options.enableDebugging, options: options.ecoreLoadOptions)
            let packages = await register(resource, in: resourceSet)
            return Loaded(resource: resource, format: format, packages: packages)
        case .xmi:
            let parser = XMIParser(
                resourceSet: resourceSet, enableDebugging: options.enableDebugging,
                referenceParsing: options.referenceParsing, ecoreLoadOptions: options.ecoreLoadOptions)
            let resource = try await parser.parse(data, uri: uri)
            return Loaded(resource: resource, format: format, diagnostics: await parser.diagnostics)
        case .json:
            let requiresMetamodel: Bool
            if let required = options.requiresMetamodel {
                requiresMetamodel = required
            } else {
                requiresMetamodel = !(await resourceSet.getMetamodelURIs().isEmpty)
            }
            let parser = JSONParser(
                resourceSet: resourceSet, options: JSONParseOptions(requiresMetamodel: requiresMetamodel))
            let resource = try await parser.parse(data, uri: uri)
            return Loaded(resource: resource, format: format, diagnostics: await parser.diagnostics)
        }
    }

    // MARK: - Saving

    /// Renders a resource as the text of a document in a given format.
    ///
    /// A resource whose root objects are all native packages is written as an Ecore document
    /// in the XMI and Ecore formats. Other resources are written by an ``XMISerializer`` with
    /// the given options or by a ``JSONSerializer``.
    ///
    /// - Parameters:
    ///   - resource: The resource to render.
    ///   - format: The format of the document.
    ///   - documentURL: The location that the document will have, against which relative
    ///     references are computed, or `nil` to compute them against the resource itself.
    ///   - xmiOptions: The options with which XMI is written (default
    ///     ``XMISerializationOptions/legacy``).
    ///   - diagnostics: Receives a ``ConversionWarning`` for everything that cannot be kept.
    /// - Returns: The text of the document.
    /// - Throws: ``ModelIOError/notAMetamodel(_:)`` if the Ecore format is asked for and a
    ///   root object is not a native package, or the error of the serialiser.
    public static func serialise(
        _ resource: Resource,
        format: ModelFormat,
        relativeTo documentURL: URL? = nil,
        xmiOptions: XMISerializationOptions = .legacy,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        let roots = await resource.getRootObjects()
        let packages = roots.compactMap { $0 as? EPackage }
        let holdsMetamodel = !roots.isEmpty && packages.count == roots.count
        if format != .json, holdsMetamodel {
            return XMISerializer(options: xmiOptions).serialize(packages, relativeTo: documentURL)
        }
        switch format {
        case .ecore:
            let location: String
            if let documentURL { location = documentURL.absoluteString } else { location = await resource.uri }
            throw ModelIOError.notAMetamodel(location)
        case .xmi:
            let serializer = XMISerializer(options: xmiOptions)
            if let documentURL {
                return try await serializer.serialize(resource, relativeTo: documentURL, diagnostics: &diagnostics)
            }
            return try await serializer.serialize(resource, diagnostics: &diagnostics)
        case .json:
            return try await JSONSerializer().serialize(resource, diagnostics: &diagnostics)
        }
    }

    /// Saves a resource as a document.
    ///
    /// The format is the given one, else the one that the file extension names. The document
    /// is rendered as by ``serialise(_:format:relativeTo:xmiOptions:diagnostics:)`` with
    /// relative references computed against the location, and is then written in UTF-8. No
    /// file is written if the resource cannot be rendered.
    ///
    /// - Parameters:
    ///   - resource: The resource to save.
    ///   - url: The location of the file to write.
    ///   - format: The format of the document, or `nil` (the default) to take it from the
    ///     file extension.
    ///   - xmiOptions: The options with which XMI is written (default
    ///     ``XMISerializationOptions/legacy``).
    ///   - diagnostics: Receives a ``ConversionWarning`` for everything that cannot be kept.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if no format is given and the
    ///   extension names none, ``ModelIOError/notAMetamodel(_:)`` if an Ecore document is
    ///   asked for a resource of model instances, or the error of the serialiser or the file
    ///   system.
    public static func save(
        _ resource: Resource,
        to url: URL,
        format: ModelFormat? = nil,
        xmiOptions: XMISerializationOptions = .legacy,
        diagnostics: inout ConversionDiagnostics
    ) async throws {
        guard let format = format ?? ModelFormat.detect(url: url) else {
            throw ModelFormatError.undetectableFormat(url.absoluteString)
        }
        let text = try await serialise(
            resource, format: format, relativeTo: url, xmiOptions: xmiOptions, diagnostics: &diagnostics)
        try text.write(to: url, atomically: FileURIHandler.writesAtomically, encoding: .utf8)
    }

    /// Saves a resource as a document and returns what could not be kept.
    ///
    /// This is ``save(_:to:format:xmiOptions:diagnostics:)`` with a fresh collection of
    /// warnings.
    ///
    /// - Parameters:
    ///   - resource: The resource to save.
    ///   - url: The location of the file to write.
    ///   - format: The format of the document, or `nil` (the default) to take it from the
    ///     file extension.
    ///   - xmiOptions: The options with which XMI is written (default
    ///     ``XMISerializationOptions/legacy``).
    /// - Returns: The warnings recorded while the resource was written.
    /// - Throws: The errors of ``save(_:to:format:xmiOptions:diagnostics:)``.
    @discardableResult
    public static func save(
        _ resource: Resource,
        to url: URL,
        format: ModelFormat? = nil,
        xmiOptions: XMISerializationOptions = .legacy
    ) async throws -> ConversionDiagnostics {
        var diagnostics = ConversionDiagnostics()
        try await save(resource, to: url, format: format, xmiOptions: xmiOptions, diagnostics: &diagnostics)
        return diagnostics
    }
}

/// Errors raised while models are loaded or saved through ``ModelIO``.
public enum ModelIOError: Error, Sendable, Equatable {
    /// An Ecore document was asked for a resource whose root objects are not all packages.
    ///
    /// The associated value is the location of the document.
    case notAMetamodel(String)
}

extension ModelIOError: CustomStringConvertible, LocalizedError {
    /// A sentence that describes the error and names the document involved.
    public var description: String {
        switch self {
        case .notAMetamodel(let location):
            return "Cannot write \(location) as an Ecore document: its root objects are not all packages"
        }
    }

    /// The ``description`` of the error.
    public var errorDescription: String? { description }
}
