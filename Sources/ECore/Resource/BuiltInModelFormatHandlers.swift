//
// BuiltInModelFormatHandlers.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

extension ModelFormat {
    /// The handler with which ``ModelIO`` reads, and where it can, writes documents in the format.
    var builtInHandler: any ModelFormatHandler {
        switch self {
        case .xmi: return XMIFormatHandler()
        case .json: return JSONFormatHandler()
        case .ecore: return EcoreFormatHandler()
        case .km3: return KM3FormatHandler()
        case .emof: return EMOFFormatHandler()
        case .uml: return UMLFormatHandler()
        case .emfatic: return EmfaticFormatHandler()
        case .xcore: return XcoreFormatHandler()
        case .oclinecore: return OCLinEcoreFormatHandler()
        case .asdl: return ASDLFormatHandler()
        case .langium: return LangiumFormatHandler()
        case .xtext: return XtextFormatHandler()
        case .sdf3: return SDF3FormatHandler()
        case .metadepth: return MetaDepthPlaceholderHandler()
        }
    }
}

/// The properties that the handlers of the formats named by ``ModelFormat`` share.
protocol BuiltInModelFormatHandler: ModelFormatHandler {
    /// The format that the handler reads and writes.
    var builtInFormat: ModelFormat { get }
}

extension BuiltInModelFormatHandler {
    /// The raw value of the format.
    var identifier: String { builtInFormat.rawValue }

    /// The prose name of the format.
    var name: String { builtInFormat.description }

    /// The conventional file extension of the format.
    var fileExtensions: [String] { [builtInFormat.fileExtension] }

    /// The generic priority, as the format accepts any document of its syntax.
    ///
    /// A format that recognises documents by a distinctive start overrides this.
    var priority: ModelFormatPriority { .generic }

    /// Whether ``ModelFormat/detect(data:)`` detects the format.
    ///
    /// - Parameter prefix: The start of the document.
    /// - Returns: `true` if the document is detected as being in the format.
    func recognises(_ prefix: Data) -> Bool {
        ModelFormat.detect(data: prefix) == builtInFormat
    }
}

/// Reads and writes model instances as XMI.
///
/// A resource whose root objects are all packages is written as an Ecore document.
struct XMIFormatHandler: BuiltInModelFormatHandler, WritableModelFormatHandler {
    var builtInFormat: ModelFormat { .xmi }
    var role: ModelFormatRole { .model }

    /// Reads a document with an ``XMIParser``.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: The resource of the document with the warnings of the parser.
    /// - Throws: The error of the parser.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        let options = request.options
        let parser = XMIParser(
            resourceSet: request.resourceSet, enableDebugging: options.enableDebugging,
            referenceParsing: options.referenceParsing, ecoreLoadOptions: options.ecoreLoadOptions)
        let resource = try await parser.parse(request.data, uri: request.uri)
        return .resource(resource, diagnostics: await parser.diagnostics)
    }

    /// Writes a resource with an ``XMISerializer``.
    ///
    /// - Parameters:
    ///   - resource: The resource to write.
    ///   - documentURL: The location of the document, or `nil`.
    ///   - xmiOptions: The options of the serialiser.
    ///   - diagnostics: Receives what cannot be kept.
    /// - Returns: The text of the document.
    /// - Throws: The error of the serialiser.
    func write(
        _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        let serializer = XMISerializer(options: xmiOptions)
        if let packages = await ModelIO.metamodelPackages(of: resource) {
            return serializer.serialize(packages, relativeTo: documentURL)
        }
        if let documentURL {
            return try await serializer.serialize(resource, relativeTo: documentURL, diagnostics: &diagnostics)
        }
        return try await serializer.serialize(resource, diagnostics: &diagnostics)
    }
}

/// Reads and writes model instances and metamodels as JSON.
struct JSONFormatHandler: BuiltInModelFormatHandler, WritableModelFormatHandler {
    var builtInFormat: ModelFormat { .json }
    var role: ModelFormatRole { .both }

    /// Reads a document with a ``JSONParser`` and registers a metamodel.
    ///
    /// Unless the options say otherwise, the classes of the document must be defined by a
    /// registered metamodel whenever the resource set has one. A document whose roots are
    /// all packages is a metamodel, whose packages are registered. A document that refers to
    /// classes of the UML metamodel, such as a UML model converted to JSON, is read with the
    /// bundled UML metamodel (see ``UMLMetamodel/registerIfReferenced(by:in:)``), so that its
    /// objects keep their UML classes.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: The resource of the document with its registered packages and the
    ///   warnings of the parser.
    /// - Throws: The error of the parser.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        let resourceSet = request.resourceSet
        let requiresMetamodel: Bool
        if let required = request.options.requiresMetamodel {
            requiresMetamodel = required
        } else {
            requiresMetamodel = !(await resourceSet.getMetamodelURIs().isEmpty)
        }
        _ = try? await UMLMetamodel.registerIfReferenced(by: request.data, in: resourceSet)
        let parser = JSONParser(resourceSet: resourceSet, options: JSONParseOptions(requiresMetamodel: requiresMetamodel))
        let resource = try await parser.parse(request.data, uri: request.uri)
        let packages = await ModelIO.metamodelPackages(of: resource) != nil
            ? await ModelIO.registerRootPackages(of: resource, in: resourceSet) : []
        return .resource(resource, packages: packages, diagnostics: await parser.diagnostics)
    }

    /// Writes a resource with a ``JSONSerializer``, as a metamodel if its roots are all packages.
    ///
    /// - Parameters:
    ///   - resource: The resource to write.
    ///   - documentURL: The location of the document, or `nil`.
    ///   - xmiOptions: Not used.
    ///   - diagnostics: Receives what cannot be kept.
    /// - Returns: The text of the document.
    /// - Throws: The error of the serialiser.
    func write(
        _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        if let packages = await ModelIO.metamodelPackages(of: resource) {
            return JSONSerializer().serialize(packages, relativeTo: documentURL)
        }
        return try await JSONSerializer().serialize(resource, diagnostics: &diagnostics)
    }
}

/// Reads and writes metamodels as Ecore documents.
struct EcoreFormatHandler: BuiltInModelFormatHandler, WritableModelFormatHandler {
    var builtInFormat: ModelFormat { .ecore }
    var role: ModelFormatRole { .metamodel }

    /// Reads a document as native packages and registers them as metamodels.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: The resource of the document with its registered packages.
    /// - Throws: The error of loading the document.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        let options = request.options
        let resource = try await request.resourceSet.loadEcoreResource(
            data: request.data, uri: request.uri, enableDebugging: options.enableDebugging,
            options: options.ecoreLoadOptions)
        return .resource(resource, packages: await ModelIO.registerRootPackages(of: resource, in: request.resourceSet))
    }

    /// Writes the packages of a resource as an Ecore document.
    ///
    /// - Parameters:
    ///   - resource: The resource to write.
    ///   - documentURL: The location of the document, or `nil`.
    ///   - xmiOptions: The options of the serialiser.
    ///   - diagnostics: Not used.
    /// - Returns: The text of the document.
    /// - Throws: ``ModelIOError/notAMetamodel(_:)`` if a root object is not a package.
    func write(
        _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        guard let packages = await ModelIO.metamodelPackages(of: resource) else {
            throw ModelIOError.notAMetamodel(documentURL?.absoluteString ?? resource.uri)
        }
        return XMISerializer(options: xmiOptions).serialize(packages, relativeTo: documentURL)
    }
}

/// Reads and writes metamodels as KM3 text.
///
/// A document is decoded as text (see ``ModelFormatReadRequest/decodedText()``) and read by
/// ``KM3Reader`` with the ``EcoreLoadOptions/km3Options`` of the load options. KM3 starts
/// with a keyword, so the handler examines a document before the generic formats, and
/// recognises it only if it is neither XML nor JSON.
struct KM3FormatHandler: BuiltInModelFormatHandler, WritableModelFormatHandler {
    var builtInFormat: ModelFormat { .km3 }
    var role: ModelFormatRole { .metamodel }

    /// The specific priority, as KM3 documents start with the keyword `package`.
    var priority: ModelFormatPriority { .specific }

    /// Reads a document with a ``KM3Reader``.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: The root packages of the document with the diagnostics of decoding and reading.
    /// - Throws: `TextDecodingError.malformed(_:)` if the bytes are not valid in an explicit
    ///   text encoding.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        let options = request.options.ecoreLoadOptions.km3Options
        return try readPackages(from: request) { text, sourceName in
            let result = KM3Reader.parse(text, sourceName: sourceName, options: options)
            return (result.packages, result.diagnostics)
        }
    }

    /// Writes the packages of a resource with a ``KM3Writer``.
    ///
    /// - Parameters:
    ///   - resource: The resource to write.
    ///   - documentURL: The location of the document, or `nil`; it names the document in an error.
    ///   - xmiOptions: Not used.
    ///   - diagnostics: Receives what KM3 cannot express.
    /// - Returns: The KM3 text.
    /// - Throws: ``ModelIOError/notAMetamodel(_:)`` if a root object is not a package, or the
    ///   first diagnostic of the writer that is an error.
    func write(
        _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        try await writePackages(of: resource, relativeTo: documentURL, diagnostics: &diagnostics) {
            KM3Writer.write($0)
        }
    }
}

/// Reads and writes metamodels as EMOF documents.
///
/// A document is read by ``EMOFFormat/read(data:uri:resourceSet:options:)`` with the
/// ``ModelIO/LoadOptions/ecoreLoadOptions`` of the load options, and written as
/// ``EMOFFormat`` writes the packages of a resource. EMOF is XML, so a document is decoded as
/// its XML declaration prescribes and the ``ModelIO/LoadOptions/textEncoding`` does not apply.
///
/// EMOF documents are recognised by their namespace, so the handler examines a document
/// before the generic formats. An EMOF document is therefore read as EMOF even from a file
/// whose extension names a generic format, such as `.xmi` (see
/// ``ModelFormatRegistry/handler(for:contents:)``).
struct EMOFFormatHandler: BuiltInModelFormatHandler, WritableModelFormatHandler {
    var builtInFormat: ModelFormat { .emof }
    var role: ModelFormatRole { .metamodel }

    /// The specific priority, as EMOF documents are recognised by their namespace.
    var priority: ModelFormatPriority { .specific }

    /// Reads a document as native packages and registers them as metamodels.
    ///
    /// As for other metamodel formats, a root package without a namespace URI is registered
    /// under its name, with a warning. The diagnostics of the translation and of the load
    /// become the ``Resource/loadDiagnostics`` of the resource.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: The resource of the document with its registered packages.
    /// - Throws: ``EMOFError`` if the document is not EMOF or is CMOF, or ``XMIError`` if it
    ///   is not well-formed or its metamodel cannot be loaded.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        let read = try await EMOFFormat.read(
            data: request.data, uri: request.uri, resourceSet: request.resourceSet,
            options: request.options.ecoreLoadOptions)
        let warnings = await ModelIO.registerUnnamespacedPackages(
            read.packages, of: request.uri, in: request.resourceSet)
        await read.resource.setLoadDiagnostics(read.diagnostics + warnings)
        return .resource(read.resource, packages: read.packages)
    }

    /// Writes the packages of a resource as an EMOF document.
    ///
    /// - Parameters:
    ///   - resource: The resource to write.
    ///   - documentURL: The location of the document, or `nil`.
    ///   - xmiOptions: Not used; EMOF is written in the layout of EMF's EMOF resource.
    ///   - diagnostics: Not used.
    /// - Returns: The text of the document.
    /// - Throws: ``ModelIOError/notAMetamodel(_:)`` if a root object is not a package.
    func write(
        _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        try await EMOFFormat.write(resource, relativeTo: documentURL).text
    }
}

/// Reads and writes UML models as instances of the bundled Eclipse UML2 metamodel.
///
/// A document is read as ``UMLFormat/read(data:uri:resourceSet:options:)`` reads it: the
/// warnings about profiles that cannot be found or read become the
/// ``Resource/loadDiagnostics`` of the resource, and what the XMI parser could not keep is
/// returned as the conversion diagnostics, as for XMI. A model is written in the layout of
/// Eclipse UML2 (``XMISerializationOptions/uml``). UML is XML, so a document is decoded as its
/// XML declaration prescribes and the ``ModelIO/LoadOptions/textEncoding`` does not apply.
///
/// UML models are recognised by their namespace, so the handler examines a document before
/// the generic formats. A model in an OMG UML namespace is therefore read as UML even from
/// an `.xmi` file (see ``ModelFormatRegistry/handler(for:contents:)``), while every XMI
/// document in another namespace is still read as XMI.
///
/// A UML class model given as a metamodel is converted into an Ecore metamodel by
/// ``UMLToEcore/read(data:uri:resourceSet:options:modelResourceSet:)``.
struct UMLFormatHandler: BuiltInModelFormatHandler, WritableModelFormatHandler, MetamodelConvertingModelFormatHandler {
    var builtInFormat: ModelFormat { .uml }
    var role: ModelFormatRole { .model }

    /// The specific priority, as UML models are recognised by their namespace.
    var priority: ModelFormatPriority { .specific }

    /// Reads a document as a UML model.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: The resource of the model with what the XMI parser could not keep.
    /// - Throws: ``XMIError`` if the document is not well-formed XMI, or the error of
    ///   ``UMLMetamodel/register(in:)``.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        let read = try await UMLFormat.readResource(
            data: request.data, uri: request.uri, resourceSet: request.resourceSet, options: request.options)
        if !read.profileDiagnostics.isEmpty {
            await read.resource.setLoadDiagnostics(read.profileDiagnostics + (await read.resource.loadDiagnostics))
        }
        return .resource(read.resource, diagnostics: read.conversion)
    }

    /// Reads a UML class model as an Ecore metamodel.
    ///
    /// The model is read into a resource set of its own and converted with the standard
    /// options of ``UMLToEcore``. The metamodel is loaded into the resource set of the request
    /// under the URI of the document, its packages are registered there, and what the reader
    /// and the conversion reported becomes the ``Resource/loadDiagnostics`` of its resource.
    ///
    /// - Parameter request: The document and the resource set that receives the metamodel.
    /// - Returns: The resource of the metamodel with its root packages.
    /// - Throws: ``XMIError`` if the document is not well-formed XMI or the metamodel cannot
    ///   be loaded, or ``UMLToEcoreError/noPackage(_:)`` if the document holds no UML package.
    func readMetamodel(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        let read = try await UMLToEcore.read(data: request.data, uri: request.uri, resourceSet: request.resourceSet)
        await read.resource.setLoadDiagnostics(read.diagnostics)
        return .resource(read.resource, packages: read.packages)
    }

    /// Writes a resource in the layout of Eclipse UML2.
    ///
    /// - Parameters:
    ///   - resource: The resource to write.
    ///   - documentURL: The location of the document, or `nil`.
    ///   - xmiOptions: Not used; UML models are written with ``XMISerializationOptions/uml``.
    ///   - diagnostics: Receives what cannot be kept.
    /// - Returns: The text of the document.
    /// - Throws: The error of the ``XMISerializer``.
    func write(
        _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        try await UMLFormat.serialise(resource, relativeTo: documentURL, options: .uml, diagnostics: &diagnostics)
    }
}

/// A textual metamodel notation whose handler refuses binary documents.
protocol TextMetamodelFormatHandler: BuiltInModelFormatHandler {}

extension TextMetamodelFormatHandler {
    /// The specific priority, as the documents of the notation start with a keyword.
    var priority: ModelFormatPriority { .specific }

    /// Reads the packages of a text document, refusing binary data.
    ///
    /// - Parameters:
    ///   - request: The document to read.
    ///   - parse: Parses the text of the document.
    /// - Returns: The packages and diagnostics of the document.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if the start of the document
    ///   is binary rather than text, `TextDecodingError.malformed(_:)` if the bytes are not
    ///   valid in an explicit encoding, or the error of the parser.
    func readTextPackages(
        from request: ModelFormatReadRequest,
        parse: (_ text: String, _ sourceName: String) throws -> (packages: [EPackage], diagnostics: [SourceDiagnostic])
    ) throws -> ModelFormatReadResult {
        guard ModelFormatSniffing.isText(request.data.prefix(ModelFormatSniffing.prefixLength)) else {
            throw ModelFormatError.undetectableFormat(request.uri)
        }
        return try readPackages(from: request, parse: parse)
    }
}

/// Reads and writes metamodels as Emfatic text.
///
/// A document is decoded as text (see ``ModelFormatReadRequest/decodedText()``) and read by
/// ``EmfaticReader``. Emfatic documents have the extension `.emf`, which Windows metafiles
/// share, so a document whose start is binary is refused rather than read as text, and is
/// never recognised as Emfatic by its contents.
struct EmfaticFormatHandler: TextMetamodelFormatHandler, WritableModelFormatHandler {
    var builtInFormat: ModelFormat { .emfatic }
    var role: ModelFormatRole { .metamodel }

    /// Reads a document with an ``EmfaticReader``.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: The root packages of the document with the diagnostics of decoding and reading.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if the document is binary, or
    ///   `TextDecodingError.malformed(_:)` if the bytes are not valid in an explicit encoding.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        try readTextPackages(from: request) { text, sourceName in
            let result = EmfaticReader.parse(text, sourceName: sourceName)
            return (result.packages, result.diagnostics)
        }
    }

    /// Writes the packages of a resource with an ``EmfaticWriter``.
    ///
    /// - Parameters:
    ///   - resource: The resource to write.
    ///   - documentURL: The location of the document, or `nil`; it names the document in an error.
    ///   - xmiOptions: Not used.
    ///   - diagnostics: Receives what Emfatic cannot express.
    /// - Returns: The Emfatic text.
    /// - Throws: ``ModelIOError/notAMetamodel(_:)`` if a root object is not a package, or the
    ///   first diagnostic of the writer that is an error.
    func write(
        _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        try await writePackages(of: resource, relativeTo: documentURL, diagnostics: &diagnostics) {
            EmfaticWriter.write($0)
        }
    }
}

/// Reads and writes metamodels as Xcore text.
///
/// A document is decoded as text (see ``ModelFormatReadRequest/decodedText()``) and read by
/// ``XcoreReader``; a document whose start is binary is refused. The bodies of operations
/// and derived features are kept as text in annotations but are not executed.
struct XcoreFormatHandler: TextMetamodelFormatHandler, WritableModelFormatHandler {
    var builtInFormat: ModelFormat { .xcore }
    var role: ModelFormatRole { .metamodel }

    /// Reads a document with an ``XcoreReader``.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: The root packages of the document with the diagnostics of decoding and reading.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if the document is binary, or
    ///   `TextDecodingError.malformed(_:)` if the bytes are not valid in an explicit encoding.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        try readTextPackages(from: request) { text, sourceName in
            let result = XcoreReader.parse(text, sourceName: sourceName)
            return (result.packages, result.diagnostics)
        }
    }

    /// Writes the packages of a resource with an ``XcoreWriter``.
    ///
    /// - Parameters:
    ///   - resource: The resource to write.
    ///   - documentURL: The location of the document, or `nil`; it names the document in an error.
    ///   - xmiOptions: Not used.
    ///   - diagnostics: Receives what Xcore cannot express.
    /// - Returns: The Xcore text.
    /// - Throws: ``ModelIOError/notAMetamodel(_:)`` if a root object is not a package, or the
    ///   first diagnostic of the writer that is an error.
    func write(
        _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        try await writePackages(of: resource, relativeTo: documentURL, diagnostics: &diagnostics) {
            XcoreWriter.write($0)
        }
    }
}

/// Reads and writes metamodels with OCL constraints as OCLinEcore text.
///
/// A document is decoded as text (see ``ModelFormatReadRequest/decodedText()``) and read by
/// ``OCLinEcoreReader``; a document whose start is binary is refused. Its imports may name the
/// metamodels registered with the resource set, by namespace URI or name. The constraints
/// become the annotations that Eclipse OCL writes, so that they are kept when the metamodel
/// is written as an Ecore document.
struct OCLinEcoreFormatHandler: TextMetamodelFormatHandler, WritableModelFormatHandler {
    var builtInFormat: ModelFormat { .oclinecore }
    var role: ModelFormatRole { .metamodel }

    /// Reads a document with an ``OCLinEcoreReader``.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: The root packages of the document with the diagnostics of decoding and reading.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if the document is binary, or
    ///   `TextDecodingError.malformed(_:)` if the bytes are not valid in an explicit encoding.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        let externals = await Self.registeredPackages(of: request.resourceSet)
        return try readTextPackages(from: request) { text, sourceName in
            let result = OCLinEcoreReader.parse(text, sourceName: sourceName, importing: externals)
            return (result.packages, result.diagnostics)
        }
    }

    /// Writes the packages of a resource with an ``OCLinEcoreWriter``.
    ///
    /// - Parameters:
    ///   - resource: The resource to write.
    ///   - documentURL: The location of the document, or `nil`; it names the document in an error.
    ///   - xmiOptions: Not used.
    ///   - diagnostics: Receives what OCLinEcore cannot express.
    /// - Returns: The OCLinEcore text.
    /// - Throws: ``ModelIOError/notAMetamodel(_:)`` if a root object is not a package, or the
    ///   first diagnostic of the writer that is an error.
    func write(
        _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        try await writePackages(of: resource, relativeTo: documentURL, diagnostics: &diagnostics) {
            OCLinEcoreWriter.write($0)
        }
    }

    /// The distinct packages registered with a resource set, in the order of their URIs.
    ///
    /// - Parameter resourceSet: The resource set.
    /// - Returns: Each registered root package once.
    static func registeredPackages(of resourceSet: ResourceSet) async -> [EPackage] {
        var packages: [EPackage] = []
        var seen: Set<EUUID> = []
        for uri in await resourceSet.getMetamodelURIs().sorted() {
            guard let package = await resourceSet.getMetamodel(uri: uri), seen.insert(package.id).inserted else { continue }
            packages.append(package)
        }
        return packages
    }
}

/// Reads and writes metamodels as ASDL descriptions.
///
/// A document is decoded as text (see ``ModelFormatReadRequest/decodedText()``) and read by
/// ``ASDLReader`` with the ``EcoreLoadOptions/asdlOptions`` of the load options; a document
/// whose start is binary is refused. Packages are written by ``ASDLWriter``, as far as
/// ASDL can express them.
struct ASDLFormatHandler: TextMetamodelFormatHandler, WritableModelFormatHandler {
    var builtInFormat: ModelFormat { .asdl }
    var role: ModelFormatRole { .metamodel }

    /// Reads a document with an ``ASDLReader``.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: The root packages of the document with the diagnostics of decoding and reading.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if the document is binary, or
    ///   `TextDecodingError.malformed(_:)` if the bytes are not valid in an explicit encoding.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        let options = request.options.ecoreLoadOptions.asdlOptions
        return try readTextPackages(from: request) { text, sourceName in
            let result = ASDLReader.parse(text, sourceName: sourceName, options: options)
            return (result.packages, result.diagnostics)
        }
    }

    /// Writes the packages of a resource with an ``ASDLWriter``.
    ///
    /// - Parameters:
    ///   - resource: The resource to write.
    ///   - documentURL: The location of the document, or `nil`; it names the document in an error.
    ///   - xmiOptions: Not used.
    ///   - diagnostics: Receives what ASDL cannot express.
    /// - Returns: The ASDL text.
    /// - Throws: ``ModelIOError/notAMetamodel(_:)`` if a root object is not a package, or the
    ///   first diagnostic of the writer that is an error.
    func write(
        _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        try await writePackages(of: resource, relativeTo: documentURL, diagnostics: &diagnostics) {
            ASDLWriter.write($0)
        }
    }
}

/// Reads metamodels inferred from Langium grammars.
///
/// A document is decoded as text and read by ``LangiumReader`` with the
/// ``EcoreLoadOptions/langiumOptions`` of the load options; a document whose start is binary
/// is refused. Langium grammars are not written.
struct LangiumFormatHandler: TextMetamodelFormatHandler {
    var builtInFormat: ModelFormat { .langium }
    var role: ModelFormatRole { .metamodel }

    /// Reads a document with a ``LangiumReader``.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: The inferred package with the diagnostics of decoding and reading.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if the document is binary, or
    ///   `TextDecodingError.malformed(_:)` if the bytes are not valid in an explicit encoding.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        let options = request.options.ecoreLoadOptions.langiumOptions
        return try readTextPackages(from: request) { text, sourceName in
            let result = LangiumReader.parse(text, sourceName: sourceName, options: options)
            return (result.packages, result.diagnostics)
        }
    }
}

/// Reads the packages that Xtext grammars generate.
///
/// A document is decoded as text and read by ``XtextReader`` with the
/// ``EcoreLoadOptions/xtextOptions`` of the load options; a document whose start is binary is
/// refused. Xtext grammars are not written.
struct XtextFormatHandler: TextMetamodelFormatHandler {
    var builtInFormat: ModelFormat { .xtext }
    var role: ModelFormatRole { .metamodel }

    /// Reads a document with an ``XtextReader``.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: The generated packages with the diagnostics of decoding and reading.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if the document is binary, or
    ///   `TextDecodingError.malformed(_:)` if the bytes are not valid in an explicit encoding.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        let options = request.options.ecoreLoadOptions.xtextOptions
        return try readTextPackages(from: request) { text, sourceName in
            let result = XtextReader.parse(text, sourceName: sourceName, options: options)
            return (result.packages, result.diagnostics)
        }
    }
}

/// Reads metamodels imported from SDF3 syntax definitions and Stratego signatures.
///
/// A document is decoded as text and read by ``SDF3Reader`` with the
/// ``EcoreLoadOptions/sdf3Options`` of the load options; a document whose start is binary is
/// refused. SDF3 documents are not written.
struct SDF3FormatHandler: TextMetamodelFormatHandler {
    var builtInFormat: ModelFormat { .sdf3 }
    var role: ModelFormatRole { .metamodel }

    /// Reads a document with an ``SDF3Reader``.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: The imported package with the diagnostics of decoding and reading.
    /// - Throws: ``ModelFormatError/undetectableFormat(_:)`` if the document is binary, or
    ///   `TextDecodingError.malformed(_:)` if the bytes are not valid in an explicit encoding.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        let options = request.options.ecoreLoadOptions.sdf3Options
        return try readTextPackages(from: request) { text, sourceName in
            let result = SDF3Reader.parse(text, sourceName: sourceName, options: options)
            return (result.packages, result.diagnostics)
        }
    }
}

/// Stands for the MetaDepth format until the MultiLevel module registers its handler.
///
/// The MetaDepth notation is implemented by the MultiLevel module, which depends on this
/// one, so the built-in handler only names the format and claims its extension. Reading or
/// writing throws ``ModelFormatError/unsupportedFormat(_:)`` until a handler with the same
/// identifier replaces this one.
struct MetaDepthPlaceholderHandler: BuiltInModelFormatHandler, WritableModelFormatHandler {
    var builtInFormat: ModelFormat { .metadepth }
    var role: ModelFormatRole { .model }

    /// Recognises no document, as the notation is recognised by the registered handler.
    ///
    /// - Parameter prefix: The start of the document.
    /// - Returns: `false`.
    func recognises(_ prefix: Data) -> Bool { false }

    /// Throws, as no handler for the notation is registered.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: Never.
    /// - Throws: ``ModelFormatError/unsupportedFormat(_:)``.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        throw ModelFormatError.unsupportedFormat(builtInFormat.rawValue)
    }

    /// Throws, as no handler for the notation is registered.
    ///
    /// - Parameters:
    ///   - resource: The resource to write.
    ///   - documentURL: Not used.
    ///   - xmiOptions: Not used.
    ///   - diagnostics: Not used.
    /// - Returns: Never.
    /// - Throws: ``ModelFormatError/unsupportedFormat(_:)``.
    func write(
        _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        throw ModelFormatError.unsupportedFormat(builtInFormat.rawValue)
    }
}
