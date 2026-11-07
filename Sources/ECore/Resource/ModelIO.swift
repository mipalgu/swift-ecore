//
// ModelIO.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Loads and saves models and metamodels in any of the supported document formats.
///
/// `ModelIO` reads and writes a document through the ``ModelFormatHandler`` of its format,
/// which a ``ModelFormatRegistry`` (by default ``ModelFormatRegistry/shared``) provides. The
/// format is either given explicitly or found from the file name and, failing that, from the
/// contents of the document. `ModelIO` registers metamodels with a ``ResourceSet`` before a
/// model is read, so that the model is read with the classes of those metamodels, and it
/// collects what a conversion could not keep as ``ConversionDiagnostics``.
///
/// - An Ecore document is loaded as native packages (see ``ResourceSet/loadEcoreResource(uri:)``)
///   and every root package is registered as a metamodel, together with its nested packages.
/// - An XMI document is read by an ``XMIParser`` with the resource set.
/// - A JSON document is read by a ``JSONParser`` with the resource set. Unless
///   ``LoadOptions/requiresMetamodel`` says otherwise, a registered metamodel must then
///   define the classes of the document whenever the resource set has a metamodel registered.
///   A JSON document whose roots are Ecore packages is a metamodel: it is loaded as native
///   packages, which are registered as an Ecore document's are.
/// - A KM3 document is read by ``KM3Reader`` with the ``EcoreLoadOptions/km3Options`` of
///   the load options.
/// - An EMOF document is read by ``EMOFFormat`` into native packages, which are registered
///   as an Ecore document's are, and a UML model by ``UMLFormat`` with the bundled UML
///   metamodel.
/// - A document in a registered format is read by its handler. The packages of a metamodel
///   format, such as KM3, become the roots of the resource of the document and are
///   registered as an Ecore document's are; the diagnostics of the handler, such as syntax
///   errors, are recorded in ``Resource/loadDiagnostics``. As in the ATL tool chain, a root
///   package of such a format that has no namespace URI is registered under its name with
///   the resource set, with a warning, so that the models of the same load can refer to it.
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

        /// The encoding in which a document in a text format is read, or `nil` to detect it.
        ///
        /// Without an explicit encoding, a text document is read as UTF-8 and, if it is not
        /// valid UTF-8, as ISO-8859-1 with a warning (see `DecodedText`). This applies to KM3
        /// documents, but not to the metamodels that are registered before a document is read.
        /// XMI, Ecore, EMOF, UML and JSON documents are decoded as their own rules prescribe
        /// and ignore this option.
        public var textEncoding: TextEncoding?

        /// Creates load options.
        ///
        /// - Parameters:
        ///   - referenceParsing: How XMI reference attributes are read (default
        ///     ``XMIReferenceParsing/interpreted``).
        ///   - requiresMetamodel: Whether JSON classes must come from a registered metamodel;
        ///     `nil` (the default) requires one whenever a metamodel is registered.
        ///   - ecoreLoadOptions: The policies for loading Ecore documents (default policies).
        ///   - enableDebugging: Whether the parsers print a trace (default `false`).
        ///   - textEncoding: The encoding of a document in a text format, or `nil` (the
        ///     default) to detect it.
        public init(
            referenceParsing: XMIReferenceParsing = .interpreted,
            requiresMetamodel: Bool? = nil,
            ecoreLoadOptions: EcoreLoadOptions = EcoreLoadOptions(),
            enableDebugging: Bool = false,
            textEncoding: TextEncoding? = nil
        ) {
            self.referenceParsing = referenceParsing
            self.requiresMetamodel = requiresMetamodel
            self.ecoreLoadOptions = ecoreLoadOptions
            self.enableDebugging = enableDebugging
            self.textEncoding = textEncoding
        }
    }

    /// A document that has been loaded.
    public struct Loaded: Sendable {
        /// The resource that holds the objects of the document.
        ///
        /// For an Ecore document, the root objects of the resource are its native packages.
        public let resource: Resource

        /// The format in which the document was read.
        ///
        /// For a registered format that ``ModelFormat`` does not name, this is the built-in
        /// format whose content the document matches: ``ModelFormat/ecore`` for a document
        /// that holds metamodel packages and ``ModelFormat/xmi`` for one that holds model
        /// instances. ``formatIdentifier`` names the format itself.
        public let format: ModelFormat

        /// The identifier of the format in which the document was read.
        ///
        /// This is the ``ModelFormatHandler/identifier`` of the handler that read the
        /// document, which for a format that ``ModelFormat`` names is its raw value.
        public let formatIdentifier: String

        /// What the parser could not keep, such as classes that no metamodel defines.
        public let diagnostics: ConversionDiagnostics

        /// The root packages of an Ecore document, a JSON metamodel or a metamodel in another
        /// format, such as KM3, in document order.
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
        ///   - formatIdentifier: The identifier of the format, or `nil` (the default) for the
        ///     raw value of `format`.
        public init(
            resource: Resource, format: ModelFormat, diagnostics: ConversionDiagnostics = ConversionDiagnostics(),
            packages: [EPackage] = [], formatIdentifier: String? = nil
        ) {
            self.resource = resource
            self.format = format
            self.formatIdentifier = formatIdentifier ?? format.rawValue
            self.diagnostics = diagnostics
            self.packages = packages
        }
    }

    // MARK: - Metamodels

    /// Loads metamodel documents and registers their packages as metamodels.
    ///
    /// Each document is loaded into the resource set as native packages, and every root
    /// package with a namespace URI is registered under that URI, together with its nested
    /// packages. A package registered later replaces an earlier one with the same URI. A
    /// document may be an `.ecore` document, a metamodel in JSON, a KM3 document, a document
    /// in another metamodel format of the registry, or a model that the handler of its format
    /// converts into a metamodel (see ``MetamodelConvertingModelFormatHandler``), such as a
    /// UML class model.
    ///
    /// The format of a document is the one whose handler claims its file extension, else the
    /// one whose handler recognises its contents (see
    /// ``ModelFormatRegistry/handler(for:contents:)``). A document in a metamodel format other than
    /// Ecore and JSON, such as KM3, is read by its handler, and a root package of it that has
    /// no namespace URI is registered under its name, with a warning in
    /// ``Resource/loadDiagnostics``. Any other document is loaded as an Ecore document (see
    /// ``ResourceSet/loadEcoreResource(uri:options:)``). A document that has been loaded into
    /// the resource set already is not read again.
    ///
    /// - Parameters:
    ///   - urls: The locations of the metamodel documents, in registration order.
    ///   - resourceSet: The resource set with which the metamodels are registered.
    ///   - options: The policies with which the documents are loaded (default policies).
    ///   - registry: The registry that provides the format handlers (default
    ///     ``ModelFormatRegistry/shared``).
    /// - Returns: The root packages of all documents, in order.
    /// - Throws: The error of the first document that cannot be read or loaded.
    @discardableResult
    public static func registerMetamodels(
        at urls: [URL], in resourceSet: ResourceSet, options: EcoreLoadOptions = EcoreLoadOptions(),
        registry: ModelFormatRegistry = .shared
    ) async throws -> [EPackage] {
        var packages: [EPackage] = []
        for url in urls {
            packages += try await registerMetamodel(at: url, in: resourceSet, options: options, registry: registry)
        }
        return packages
    }

    /// Loads a metamodel document and registers its packages as metamodels.
    ///
    /// - Parameters:
    ///   - url: The location of the document.
    ///   - resourceSet: The resource set with which the metamodels are registered.
    ///   - options: The policies with which the document is loaded.
    ///   - registry: The registry that provides the format handlers.
    /// - Returns: The root packages of the document, in order.
    /// - Throws: The error of the document if it cannot be read or loaded.
    private static func registerMetamodel(
        at url: URL, in resourceSet: ResourceSet, options: EcoreLoadOptions, registry: ModelFormatRegistry
    ) async throws -> [EPackage] {
        let uri = URIReference.canonicalise(url.absoluteString)
        if let existing = await resourceSet.resources[uri] {
            return await registerRootPackages(of: existing, in: resourceSet)
        }
        let claiming = await registry.handler(for: url)
        let data: Data
        let handler: any ModelFormatHandler
        if let claiming, claiming.priority > .generic {
            guard readsAsMetamodelFormat(claiming) else {
                return await registerRootPackages(
                    of: try await resourceSet.loadEcoreResource(uri: uri, options: options), in: resourceSet)
            }
            data = try await resourceSet.readDocument(uri: uri)
            handler = claiming
        } else {
            guard let read = try? await resourceSet.readDocument(uri: uri) else {
                return await registerRootPackages(
                    of: try await resourceSet.loadEcoreResource(uri: uri, options: options), in: resourceSet)
            }
            guard let recognised = await registry.handler(for: url, contents: read), readsAsMetamodelFormat(recognised)
            else {
                let resource = try await resourceSet.loadEcoreResource(
                    data: read, uri: uri, enableDebugging: false, options: options)
                return await registerRootPackages(of: resource, in: resourceSet)
            }
            data = read
            handler = recognised
        }
        if let converting = handler as? any MetamodelConvertingModelFormatHandler {
            let request = ModelFormatReadRequest(
                data: data, uri: uri, resourceSet: resourceSet, options: LoadOptions(ecoreLoadOptions: options))
            return try await place(converting.readMetamodel(request), uri: uri, in: resourceSet).packages
        }
        return try await load(
            data: data, uri: uri, handler: handler, resourceSet: resourceSet,
            options: LoadOptions(ecoreLoadOptions: options), registry: registry
        ).packages
    }

    /// Whether ``registerMetamodels(at:in:options:registry:)`` reads a document through a handler.
    ///
    /// Documents of the built-in XMI, JSON and Ecore formats, and of formats that hold only
    /// models, are loaded as Ecore documents instead, unless the handler converts them into
    /// metamodels (see ``MetamodelConvertingModelFormatHandler``), as the UML handler does.
    ///
    /// - Parameter handler: The handler of the format of a document.
    /// - Returns: `true` if the handler reads the document as a metamodel.
    private static func readsAsMetamodelFormat(_ handler: any ModelFormatHandler) -> Bool {
        if handler is any MetamodelConvertingModelFormatHandler { return true }
        guard handler.role != .model else { return false }
        switch handler.format {
        case .xmi?, .json?, .ecore?: return false
        case .km3?, .emof?, .emfatic?, .xcore?, .oclinecore?, .asdl?, .langium?, .xtext?, .sdf3?, nil: return true
        case .uml?, .metadepth?: return false
        }
    }

    /// Registers the root packages of a resource as metamodels.
    ///
    /// Each root package with a namespace URI is registered under that URI, replacing a
    /// package registered earlier. A root package without one is not registered here; see
    /// ``registerUnnamespacedPackages(_:of:in:)``.
    ///
    /// - Parameters:
    ///   - resource: The resource whose root packages are registered.
    ///   - resourceSet: The resource set with which they are registered.
    /// - Returns: The root packages of the resource, in order.
    static func registerRootPackages(of resource: Resource, in resourceSet: ResourceSet) async -> [EPackage] {
        let packages = await resource.getRootObjects().compactMap { $0 as? EPackage }
        for package in packages where !package.nsURI.isEmpty {
            await resourceSet.registerMetamodel(package)
        }
        return packages
    }

    /// Registers the root packages without a namespace URI under their names.
    ///
    /// This is how the ATL tool chain makes the packages of a metamodel without a namespace
    /// URI available: a model of the metamodel names the package as its namespace. A package
    /// keeps its empty namespace URI, replaces a package registered earlier under its name,
    /// and is reported with a warning. A package without a name is not registered.
    ///
    /// - Parameters:
    ///   - packages: The root packages of a document.
    ///   - uri: The URI of the document, which the warnings name.
    ///   - resourceSet: The resource set with which the packages are registered.
    /// - Returns: The warnings, one for each package registered under its name.
    static func registerUnnamespacedPackages(
        _ packages: [EPackage], of uri: String, in resourceSet: ResourceSet
    ) async -> [SourceDiagnostic] {
        var warnings: [SourceDiagnostic] = []
        for package in packages where package.nsURI.isEmpty && !package.name.isEmpty {
            await resourceSet.registerMetamodel(package, uri: package.name)
            warnings.append(EcoreLoadDiagnostic.registeredUnderNameWarning(package: package.name, document: uri))
        }
        return warnings
    }

    /// The root packages of a resource that holds a metamodel.
    ///
    /// - Parameter resource: The resource.
    /// - Returns: The root objects of the resource if there are some and all of them are
    ///   packages, or `nil` otherwise.
    static func metamodelPackages(of resource: Resource) async -> [EPackage]? {
        let roots = await resource.getRootObjects()
        let packages = roots.compactMap { $0 as? EPackage }
        return !roots.isEmpty && packages.count == roots.count ? packages : nil
    }

    // MARK: - Loading

    /// Loads a model or metamodel document.
    ///
    /// The metamodels are registered first (see ``registerMetamodels(at:in:options:registry:)``).
    /// The format is the given one, else the one whose handler claims the file extension,
    /// else the one whose handler recognises the contents of the document (see
    /// ``ModelFormatRegistry/handler(for:contents:)``). A file whose extension names a
    /// generic format, such as `.xmi`, is read in a more specific format whose handler
    /// recognises its contents, so that an OMG UML model in an `.xmi` file is read as UML. The document is read through the URI handlers of the
    /// resource set and its resource is added to the set.
    ///
    /// - Parameters:
    ///   - url: The location of the document.
    ///   - format: The format of the document, or `nil` (the default) to detect it.
    ///   - resourceSet: The resource set that provides the metamodels and receives the resource.
    ///   - metamodels: The locations of metamodel documents to register before the document is read.
    ///   - options: The options that control reading (default options).
    ///   - registry: The registry that provides the format handlers (default
    ///     ``ModelFormatRegistry/shared``).
    /// - Returns: The loaded document with its resource, format and diagnostics.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if the format cannot be
    ///   determined, ``ModelFormatError/unsupportedFormat(_:)`` if the registry has no handler
    ///   for the given format, or the error of the file system or of the handler.
    public static func load(
        url: URL,
        format: ModelFormat? = nil,
        resourceSet: ResourceSet,
        metamodels: [URL] = [],
        options: LoadOptions = LoadOptions(),
        registry: ModelFormatRegistry = .shared
    ) async throws -> Loaded {
        try await registerMetamodels(
            at: metamodels, in: resourceSet, options: options.ecoreLoadOptions, registry: registry)
        let uri = URIReference.canonicalise(url.absoluteString)
        let data = try await resourceSet.readDocument(uri: uri)
        let handler: (any ModelFormatHandler)?
        if let format {
            handler = try await registry.requiredHandler(for: format)
        } else {
            handler = await registry.handler(for: url, contents: data)
        }
        return try await load(data: data, uri: uri, handler: handler, resourceSet: resourceSet, options: options, registry: registry)
    }

    /// Loads a model or metamodel document from its bytes.
    ///
    /// The metamodels are registered first (see ``registerMetamodels(at:in:options:registry:)``).
    /// Without an explicit format, the format is the one whose handler recognises the
    /// contents of the document (see ``ModelFormatRegistry/handler(recognising:)``).
    ///
    /// - Parameters:
    ///   - data: The bytes of the document.
    ///   - uri: The URI that the document has; relative references are resolved against it.
    ///   - format: The format of the document, or `nil` (the default) to detect it.
    ///   - resourceSet: The resource set that provides the metamodels and receives the resource.
    ///   - metamodels: The locations of metamodel documents to register before the document is read.
    ///   - options: The options that control reading (default options).
    ///   - registry: The registry that provides the format handlers (default
    ///     ``ModelFormatRegistry/shared``).
    /// - Returns: The loaded document with its resource, format and diagnostics.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if the format cannot be
    ///   determined, ``ModelFormatError/unsupportedFormat(_:)`` if the registry has no handler
    ///   for the given format, or the error of the handler.
    public static func load(
        data: Data,
        uri: String,
        format: ModelFormat? = nil,
        resourceSet: ResourceSet,
        metamodels: [URL] = [],
        options: LoadOptions = LoadOptions(),
        registry: ModelFormatRegistry = .shared
    ) async throws -> Loaded {
        try await registerMetamodels(
            at: metamodels, in: resourceSet, options: options.ecoreLoadOptions, registry: registry)
        var handler: (any ModelFormatHandler)?
        if let format { handler = try await registry.requiredHandler(for: format) }
        return try await load(
            data: data, uri: URIReference.canonicalise(uri), handler: handler, resourceSet: resourceSet,
            options: options, registry: registry)
    }

    /// Reads a document through a handler, or through the handler that recognises it.
    ///
    /// - Parameters:
    ///   - data: The bytes of the document.
    ///   - uri: The canonical URI of the document.
    ///   - handler: The handler of the format of the document, or `nil` to recognise it.
    ///   - resourceSet: The resource set that provides the metamodels and receives the resource.
    ///   - options: The options that control reading.
    ///   - registry: The registry that recognises the document.
    /// - Returns: The loaded document.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if no handler is given and none
    ///   recognises the document, or the error of the handler.
    private static func load(
        data: Data, uri: String, handler: (any ModelFormatHandler)?, resourceSet: ResourceSet,
        options: LoadOptions, registry: ModelFormatRegistry
    ) async throws -> Loaded {
        let recognised: (any ModelFormatHandler)?
        if let handler { recognised = handler } else { recognised = await registry.handler(recognising: data) }
        guard let handler = recognised else { throw ModelFormatError.undetectableFormat(uri) }
        let request = ModelFormatReadRequest(data: data, uri: uri, resourceSet: resourceSet, options: options)
        let placed = try await place(handler.read(request), uri: uri, in: resourceSet)
        let format = handler.format ?? (placed.packages.isEmpty ? .xmi : .ecore)
        return Loaded(
            resource: placed.resource, format: format, diagnostics: placed.diagnostics, packages: placed.packages,
            formatIdentifier: handler.identifier)
    }

    /// Places what a handler has read in the resource set.
    ///
    /// Metamodel packages become the roots of a new resource of the document and are
    /// registered, those without a namespace URI under their names, with the diagnostics of
    /// the handler and the warnings of that registration as the ``Resource/loadDiagnostics``
    /// of the resource. A resource that the handler has created is taken as it is.
    ///
    /// - Parameters:
    ///   - result: What the handler has read.
    ///   - uri: The canonical URI of the document.
    ///   - resourceSet: The resource set that receives the resource.
    /// - Returns: The resource of the document, its registered root packages, and what the
    ///   handler could not keep.
    private static func place(_ result: ModelFormatReadResult, uri: String, in resourceSet: ResourceSet) async
        -> (resource: Resource, packages: [EPackage], diagnostics: ConversionDiagnostics)
    {
        switch result {
        case .packages(let roots, let sourceDiagnostics):
            let resource = await resourceSet.createResource(uri: uri)
            for package in roots { await resource.registerNativePackage(package) }
            let packages = await registerRootPackages(of: resource, in: resourceSet)
            let warnings = await registerUnnamespacedPackages(packages, of: uri, in: resourceSet)
            await resource.setLoadDiagnostics(sourceDiagnostics + warnings)
            return (resource, packages, ConversionDiagnostics())
        case .resource(let read, let registered, let warnings):
            return (read, registered, warnings)
        }
    }

    // MARK: - Saving

    /// Renders a resource as the text of a document in a given format.
    ///
    /// The resource is written by the handler of the format. With the built-in handlers, a
    /// resource whose root objects are all native packages is written as an Ecore document
    /// in the XMI and Ecore formats and as a JSON metamodel (see
    /// ``JSONSerializer/serialize(_:relativeTo:)``) in the JSON format. Other resources are
    /// written by an ``XMISerializer`` with the given options or by a ``JSONSerializer``.
    ///
    /// - Parameters:
    ///   - resource: The resource to render.
    ///   - format: The format of the document.
    ///   - documentURL: The location that the document will have, against which relative
    ///     references are computed, or `nil` to compute them against the resource itself.
    ///   - xmiOptions: The options with which XMI is written (default
    ///     ``XMISerializationOptions/legacy``).
    ///   - registry: The registry that provides the format handlers (default
    ///     ``ModelFormatRegistry/shared``).
    ///   - diagnostics: Receives a ``ConversionWarning`` for everything that cannot be kept.
    /// - Returns: The text of the document.
    /// - Throws: ``ModelIOError/notAMetamodel(_:)`` if the Ecore format is asked for and a
    ///   root object is not a native package, ``ModelFormatError/unsupportedFormat(_:)`` if
    ///   the registry has no handler for the format, ``ModelFormatError/unwritableFormat(_:)``
    ///   if its handler cannot write, or the error of the serialiser.
    public static func serialise(
        _ resource: Resource,
        format: ModelFormat,
        relativeTo documentURL: URL? = nil,
        xmiOptions: XMISerializationOptions = .legacy,
        registry: ModelFormatRegistry = .shared,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        let handler = try await registry.requiredHandler(for: format)
        return try await serialise(
            resource, handler: handler, relativeTo: documentURL, xmiOptions: xmiOptions, diagnostics: &diagnostics)
    }

    /// Renders a resource through a handler that must be able to write.
    ///
    /// - Parameters:
    ///   - resource: The resource to render.
    ///   - handler: The handler of the format.
    ///   - documentURL: The location of the document, or `nil`.
    ///   - xmiOptions: The options with which XMI is written.
    ///   - diagnostics: Receives what cannot be kept.
    /// - Returns: The text of the document.
    /// - Throws: ``ModelFormatError/unwritableFormat(_:)`` if the handler cannot write, or
    ///   the error of the handler.
    private static func serialise(
        _ resource: Resource, handler: any ModelFormatHandler, relativeTo documentURL: URL?,
        xmiOptions: XMISerializationOptions, diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        guard let writer = handler as? any WritableModelFormatHandler else {
            throw ModelFormatError.unwritableFormat(handler.name)
        }
        return try await writer.write(resource, relativeTo: documentURL, xmiOptions: xmiOptions, diagnostics: &diagnostics)
    }

    /// Saves a resource as a document.
    ///
    /// The format is the given one, else the one whose handler claims the file extension.
    /// The document is rendered as by
    /// ``serialise(_:format:relativeTo:xmiOptions:registry:diagnostics:)`` with relative
    /// references computed against the location, and is then written in UTF-8. No file is
    /// written if the resource cannot be rendered.
    ///
    /// - Parameters:
    ///   - resource: The resource to save.
    ///   - url: The location of the file to write.
    ///   - format: The format of the document, or `nil` (the default) to take it from the
    ///     file extension.
    ///   - xmiOptions: The options with which XMI is written (default
    ///     ``XMISerializationOptions/legacy``).
    ///   - registry: The registry that provides the format handlers (default
    ///     ``ModelFormatRegistry/shared``).
    ///   - diagnostics: Receives a ``ConversionWarning`` for everything that cannot be kept.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if no format is given and no
    ///   handler claims the extension, ``ModelFormatError/unsupportedFormat(_:)`` if the
    ///   registry has no handler for the given format,
    ///   ``ModelFormatError/unwritableFormat(_:)`` if the handler cannot write,
    ///   ``ModelIOError/notAMetamodel(_:)`` if an Ecore document is asked for a resource of
    ///   model instances, or the error of the serialiser or the file system.
    public static func save(
        _ resource: Resource,
        to url: URL,
        format: ModelFormat? = nil,
        xmiOptions: XMISerializationOptions = .legacy,
        registry: ModelFormatRegistry = .shared,
        diagnostics: inout ConversionDiagnostics
    ) async throws {
        let handler: any ModelFormatHandler
        if let format {
            handler = try await registry.requiredHandler(for: format)
        } else if let claiming = await registry.handler(for: url) {
            handler = claiming
        } else {
            throw ModelFormatError.undetectableFormat(url.absoluteString)
        }
        let text = try await serialise(
            resource, handler: handler, relativeTo: url, xmiOptions: xmiOptions, diagnostics: &diagnostics)
        try text.write(to: url, atomically: FileURIHandler.writesAtomically, encoding: .utf8)
    }

    /// Saves a resource as a document and returns what could not be kept.
    ///
    /// This is ``save(_:to:format:xmiOptions:registry:diagnostics:)`` with a fresh
    /// collection of warnings.
    ///
    /// - Parameters:
    ///   - resource: The resource to save.
    ///   - url: The location of the file to write.
    ///   - format: The format of the document, or `nil` (the default) to take it from the
    ///     file extension.
    ///   - xmiOptions: The options with which XMI is written (default
    ///     ``XMISerializationOptions/legacy``).
    ///   - registry: The registry that provides the format handlers (default
    ///     ``ModelFormatRegistry/shared``).
    /// - Returns: The warnings recorded while the resource was written.
    /// - Throws: The errors of ``save(_:to:format:xmiOptions:registry:diagnostics:)``.
    @discardableResult
    public static func save(
        _ resource: Resource,
        to url: URL,
        format: ModelFormat? = nil,
        xmiOptions: XMISerializationOptions = .legacy,
        registry: ModelFormatRegistry = .shared
    ) async throws -> ConversionDiagnostics {
        var diagnostics = ConversionDiagnostics()
        try await save(
            resource, to: url, format: format, xmiOptions: xmiOptions, registry: registry, diagnostics: &diagnostics)
        return diagnostics
    }
}

/// Errors raised while models are loaded or saved through ``ModelIO``.
public enum ModelIOError: Error, Sendable, Equatable {
    /// An Ecore document was asked for a resource whose root objects are not all packages.
    ///
    /// The associated value is the location of the document.
    case notAMetamodel(String)

    /// OCL constraints were to be added to a resource whose root objects are not all packages.
    ///
    /// The associated value is the URI of the resource.
    case unconstrainableResource(String)
}

extension ModelIOError: CustomStringConvertible, LocalizedError {
    /// A sentence that describes the error and names the document involved.
    public var description: String {
        switch self {
        case .notAMetamodel(let location):
            return "Cannot write \(location) as an Ecore document: its root objects are not all packages"
        case .unconstrainableResource(let location):
            return "Cannot add OCL constraints to \(location): its root objects are not all packages"
        }
    }

    /// The ``description`` of the error.
    public var errorDescription: String? { description }
}
