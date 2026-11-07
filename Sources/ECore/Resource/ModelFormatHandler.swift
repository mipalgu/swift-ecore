//
// ModelFormatHandler.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// What a document format holds: metamodels, models, or either.
public enum ModelFormatRole: Sendable, Hashable, CaseIterable {
    /// The format holds metamodel packages, as an Ecore document does.
    case metamodel

    /// The format holds model instances, as an XMI document does.
    case model

    /// The format holds either metamodel packages or model instances, as JSON does.
    case both
}

/// The order in which handlers examine a document whose format is to be recognised.
///
/// When neither an explicit format nor a file extension determines the format of a
/// document, ``ModelFormatRegistry/handler(recognising:)`` asks the handlers in descending
/// order of priority whether they recognise its first bytes. A format with a distinctive
/// start, such as a keyword, has ``specific`` priority and is therefore recognised before
/// the ``generic`` formats, XMI and JSON, which accept any XML or JSON document.
///
/// ```swift
/// struct NotationHandler: ModelFormatHandler {
///     var priority: ModelFormatPriority { .specific }
///     // ...
/// }
/// ```
public struct ModelFormatPriority: RawRepresentable, Sendable, Hashable, Comparable {
    /// The rank of the priority; a handler of higher rank examines a document first.
    public var rawValue: Int

    /// Creates a priority of a given rank.
    ///
    /// - Parameter rawValue: The rank; ranks between and beyond ``generic`` and ``specific``
    ///   order handlers more finely.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The priority of a format that accepts any document of a general syntax.
    ///
    /// The built-in XMI, JSON and Ecore formats have this priority.
    public static let generic = ModelFormatPriority(rawValue: 0)

    /// The priority of a format that recognises documents by a distinctive start.
    ///
    /// This is the default priority of a ``ModelFormatHandler``.
    public static let specific = ModelFormatPriority(rawValue: 100)

    /// Orders priorities by their rank.
    ///
    /// - Parameters:
    ///   - lhs: The first priority.
    ///   - rhs: The second priority.
    /// - Returns: `true` if `lhs` ranks below `rhs`.
    public static func < (lhs: ModelFormatPriority, rhs: ModelFormatPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A document to be read by a ``ModelFormatHandler``, with the context in which it is read.
///
/// The document is passed as raw bytes. A text format decodes them with ``decodedText()``,
/// which applies the ``ModelIO/LoadOptions/textEncoding`` of the options or, without one,
/// reads UTF-8 with an ISO-8859-1 fallback (see `DecodedText`), so that every text format
/// decodes documents alike. ``ModelFormatHandler/readPackages(from:parse:)`` does this for
/// a text metamodel format and reports the fallback as a diagnostic.
public struct ModelFormatReadRequest: Sendable {
    /// The bytes of the document.
    public var data: Data

    /// The canonical URI of the document, against which relative references are resolved.
    public var uri: String

    /// The resource set that provides the metamodels and receives the resource.
    public var resourceSet: ResourceSet

    /// The options that control reading.
    public var options: ModelIO.LoadOptions

    /// Creates a read request.
    ///
    /// - Parameters:
    ///   - data: The bytes of the document.
    ///   - uri: The canonical URI of the document.
    ///   - resourceSet: The resource set that provides the metamodels and receives the resource.
    ///   - options: The options that control reading (default options).
    public init(data: Data, uri: String, resourceSet: ResourceSet, options: ModelIO.LoadOptions = ModelIO.LoadOptions()) {
        self.data = data
        self.uri = uri
        self.resourceSet = resourceSet
        self.options = options
    }

    /// The encoding in which a text document is to be read, or `nil` to detect it.
    public var encoding: TextEncoding? { options.textEncoding }

    /// Decodes the document as text.
    ///
    /// With an explicit ``encoding``, the bytes are decoded in that encoding alone.
    /// Otherwise they are read as UTF-8 and, if they are not valid UTF-8, as ISO-8859-1,
    /// and the `DecodedText.warning` of the result then names the document by its ``uri``.
    ///
    /// - Returns: The text of the document with the encoding in which it was read.
    /// - Throws: `TextDecodingError.malformed(_:)` if the bytes are not valid in the
    ///   explicit encoding.
    public func decodedText() throws -> DecodedText {
        try DecodedText(decoding: data, encoding: encoding, document: uri)
    }
}

/// What a ``ModelFormatHandler`` has read from a document.
public enum ModelFormatReadResult: Sendable {
    /// Metamodel packages read from the document, with what the reader found wrong.
    ///
    /// ``ModelIO`` places the packages as the roots of the resource of the document in the
    /// resource set, registers each package that has a namespace URI as a metamodel, and
    /// records the diagnostics in ``Resource/loadDiagnostics``.
    ///
    /// - Parameters:
    ///   - packages: The root packages of the document, in document order.
    ///   - diagnostics: The problems found while reading, such as syntax errors.
    case packages([EPackage], diagnostics: [SourceDiagnostic] = [])

    /// A resource that the reader has created in the resource set.
    ///
    /// - Parameters:
    ///   - resource: The resource that holds the objects of the document.
    ///   - packages: The root packages of the document that the reader has registered as
    ///     metamodels, or none for a document of model instances.
    ///   - diagnostics: What the reader could not keep.
    case resource(Resource, packages: [EPackage] = [], diagnostics: ConversionDiagnostics = ConversionDiagnostics())
}

/// A document format that ``ModelIO`` reads through a ``ModelFormatRegistry``.
///
/// A handler names its format, claims file extensions, may recognise documents by their
/// first bytes, and reads a document either into metamodel packages or into a resource of
/// model instances. A handler that can also write documents conforms to
/// ``WritableModelFormatHandler``. Register a handler with
/// ``ModelFormatRegistry/register(_:)`` to make its format available to ``ModelIO``.
///
/// The ``identifier`` of a handler for a format that ``ModelFormat`` names is the raw value
/// of that case, so ``format`` relates the two.
///
/// ## Example
///
/// A text metamodel format plugs in with a reader and a writer:
///
/// ```swift
/// struct NotationHandler: WritableModelFormatHandler {
///     var identifier: String { "notation" }
///     var name: String { "Notation" }
///     var fileExtensions: [String] { ["notation"] }
///     var role: ModelFormatRole { .metamodel }
///
///     func recognises(_ prefix: Data) -> Bool {
///         String(decoding: prefix, as: UTF8.self).hasPrefix("notation ")
///     }
///
///     func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
///         try readPackages(from: request) { text, sourceName in
///             let result = NotationReader.parse(text, sourceName: sourceName)
///             return (result.packages, result.diagnostics)
///         }
///     }
///
///     func write(_ resource: Resource, relativeTo documentURL: URL?,
///                xmiOptions: XMISerializationOptions,
///                diagnostics: inout ConversionDiagnostics) async throws -> String {
///         try await writePackages(of: resource, relativeTo: documentURL, diagnostics: &diagnostics) {
///             NotationWriter.write($0)
///         }
///     }
/// }
///
/// await ModelFormatRegistry.shared.register(NotationHandler())
/// ```
public protocol ModelFormatHandler: Sendable {
    /// The identifier of the format, in lower case, such as `xmi` or `ecore`.
    ///
    /// A registry holds one handler per identifier, compared regardless of case.
    var identifier: String { get }

    /// The name of the format as it is written in prose, such as `XMI` or `Ecore`.
    var name: String { get }

    /// The file extensions of the format, without the leading dot.
    var fileExtensions: [String] { get }

    /// Whether the format holds metamodels, models, or either.
    var role: ModelFormatRole { get }

    /// The order in which the handler examines a document whose format is to be recognised.
    ///
    /// The default is ``ModelFormatPriority/specific``.
    var priority: ModelFormatPriority { get }

    /// Whether a document is in the format, judged from its first bytes.
    ///
    /// The bytes are at most ``ModelFormatRegistry/recognitionPrefixLength`` long, so the
    /// document may be cut off anywhere. The default recognises no document, so that the
    /// format is found only by name or file extension.
    ///
    /// - Parameter prefix: The start of the document.
    /// - Returns: `true` if the document is in the format.
    func recognises(_ prefix: Data) -> Bool

    /// Reads a document.
    ///
    /// - Parameter request: The document and the context in which it is read.
    /// - Returns: The metamodel packages or the resource read from the document.
    /// - Throws: An error if the document cannot be read.
    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult
}

/// A document format that ``ModelIO`` can also write.
public protocol WritableModelFormatHandler: ModelFormatHandler {
    /// Renders a resource as the text of a document in the format.
    ///
    /// - Parameters:
    ///   - resource: The resource to render.
    ///   - documentURL: The location that the document will have, against which relative
    ///     references are computed, or `nil` to compute them against the resource itself.
    ///   - xmiOptions: The options with which XML is written, for formats based on XMI.
    ///   - diagnostics: Receives a ``ConversionWarning`` for everything that cannot be kept.
    /// - Returns: The text of the document.
    /// - Throws: ``ModelIOError/notAMetamodel(_:)`` if a metamodel format is asked to write
    ///   model instances, or the error of the writer.
    func write(
        _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String
}

/// A document format of models whose documents can also serve as metamodels, once converted.
///
/// A document of a format that holds models, such as a UML class model, describes classes
/// that other documents can instantiate. When such a document is given as a metamodel, as
/// to ``ModelIO/registerMetamodels(at:in:options:registry:)`` or among the `metamodels` of
/// ``ModelIO/load(url:format:resourceSet:metamodels:options:registry:)``, ``ModelIO`` reads it
/// with ``readMetamodel(_:)`` rather than ``ModelFormatHandler/read(_:)``. The built-in UML
/// handler converts a UML class model in this way (see ``UMLToEcore``).
///
/// ```swift
/// let resourceSet = ResourceSet()
/// try await ModelIO.registerMetamodels(at: [classModelURL], in: resourceSet)
/// let model = try await ModelIO.load(url: instanceURL, resourceSet: resourceSet)
/// ```
public protocol MetamodelConvertingModelFormatHandler: ModelFormatHandler {
    /// Reads a document in the role of a metamodel.
    ///
    /// A handler either returns the converted root packages, which ``ModelIO`` places in a
    /// resource of the document and registers as it registers the packages of a metamodel
    /// format, or a resource of the document that it has loaded into the resource set of the
    /// request, with the packages it has registered there. What the conversion reports
    /// belongs in the ``Resource/loadDiagnostics`` of that resource.
    ///
    /// - Parameter request: The document and the resource set that receives the metamodel.
    /// - Returns: The metamodel packages, or the resource of the metamodel with its packages.
    /// - Throws: An error if the document cannot be read or converted.
    func readMetamodel(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult
}

extension ModelFormatHandler {
    /// The specific priority, with which a handler examines a document before the generic formats.
    public var priority: ModelFormatPriority { .specific }

    /// Recognises no document, so that the format is found only by name or file extension.
    ///
    /// - Parameter prefix: The start of the document.
    /// - Returns: `false`.
    public func recognises(_ prefix: Data) -> Bool { false }

    /// The case of ``ModelFormat`` whose raw value is the ``identifier``, if there is one.
    public var format: ModelFormat? { ModelFormat(rawValue: identifier.lowercased()) }

    /// Reads a text document into metamodel packages with a parser of text.
    ///
    /// The document is decoded with ``ModelFormatReadRequest/decodedText()``. A warning that
    /// it was not valid UTF-8 precedes the diagnostics of the parser in the result.
    ///
    /// - Parameters:
    ///   - request: The document to read.
    ///   - parse: Parses the text of a document whose URI is given as its source name, and
    ///     returns its root packages and the problems found.
    /// - Returns: The packages and diagnostics of the document.
    /// - Throws: `TextDecodingError.malformed(_:)` if the bytes are not valid in an
    ///   explicit encoding, or the error of the parser.
    public func readPackages(
        from request: ModelFormatReadRequest,
        parse: (_ text: String, _ sourceName: String) throws -> (packages: [EPackage], diagnostics: [SourceDiagnostic])
    ) throws -> ModelFormatReadResult {
        let decoded = try request.decodedText()
        let parsed = try parse(decoded.text, request.uri)
        return .packages(parsed.packages, diagnostics: (decoded.warning.map { [$0] } ?? []) + parsed.diagnostics)
    }
}

extension WritableModelFormatHandler {
    /// Writes the metamodel packages of a resource with a writer of text.
    ///
    /// The first diagnostic of the writer that is an error is thrown. Otherwise every
    /// diagnostic of the writer is recorded as a ``ConversionWarning/Kind/sourceDiagnostic(_:)``.
    ///
    /// - Parameters:
    ///   - resource: The resource whose root packages are written.
    ///   - documentURL: The location that the document will have, or `nil`; it names the
    ///     document in an error.
    ///   - diagnostics: Receives the warnings of the writer.
    ///   - write: Writes packages as text and returns the text and the problems found.
    /// - Returns: The text of the document.
    /// - Throws: ``ModelIOError/notAMetamodel(_:)`` if a root object of the resource is not
    ///   a package, the first diagnostic of the writer that is an error, or the error of
    ///   the writer.
    public func writePackages(
        of resource: Resource, relativeTo documentURL: URL?, diagnostics: inout ConversionDiagnostics,
        write: ([EPackage]) throws -> (text: String, diagnostics: [SourceDiagnostic])
    ) async throws -> String {
        guard let packages = await ModelIO.metamodelPackages(of: resource) else {
            throw ModelIOError.notAMetamodel(documentURL?.absoluteString ?? resource.uri)
        }
        let written = try write(packages)
        if let error = written.diagnostics.first(where: { $0.severity == .error }) { throw error }
        for diagnostic in written.diagnostics { diagnostics.record(.sourceDiagnostic(diagnostic)) }
        return written.text
    }
}
