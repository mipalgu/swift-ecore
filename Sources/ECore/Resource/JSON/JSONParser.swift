//
// JSONParser.swift
// ECore
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

/// Options that control how a ``JSONParser`` reads a document.
public struct JSONParseOptions: Sendable, Equatable {
    /// Whether the classes of a document must come from a registered metamodel.
    ///
    /// When `true`, parsing fails with ``JSONError/unresolvedMetamodel(_:)`` if the `eClass` of
    /// the document does not name a class of a metamodel registered with the parser's resource
    /// set. When `false` (the default), the parser fabricates a class from the document instead.
    public var requiresMetamodel: Bool

    /// Creates parse options.
    ///
    /// - Parameter requiresMetamodel: Whether registered metamodels are required (default `false`).
    public init(requiresMetamodel: Bool = false) {
        self.requiresMetamodel = requiresMetamodel
    }
}

/// Parser for JSON files in emfjson/pyecore format
///
/// The JSON parser converts JSON files into EMF-compatible object graphs stored in Resources.
/// It handles:
/// - Single root objects and arrays of root objects
/// - Nested containment references
/// - Cross-references (using $ref)
/// - Type information via eClass field
/// - Compatible with pyecore and emfjson-jackson formats
///
/// ## Metamodels
///
/// If the parser has a resource set and the `eClass` of the document names a class of a
/// metamodel registered with that set (`"<nsURI>#//<Name>"`, or a bare `"<Name>"` that is
/// searched in the registered packages in the order of their URIs), objects are built from
/// the metamodel: attribute values are converted by their data types, enumerations hold
/// literal names, nested objects take the class of their containment reference (or their
/// own `eClass` if it names a subclass), and `$ref` values are resolved to the objects they
/// denote (see ``JSONFragments``). Otherwise the parser synthesises classes from the document,
/// unless ``JSONParseOptions/requiresMetamodel`` asks for an error: each class takes the keys
/// of its objects as features, nested objects become contained objects, and `$ref` values
/// become references. Either way every object, including every nested one, is registered
/// with the resource, and contained objects are held by their identifiers. A document that
/// is an empty array yields an empty resource.
///
/// ## JSON Format
///
/// Single root object:
/// ```json
/// {
///   "eClass": "http://package.uri#//ClassName",
///   "attribute": "value",
///   "reference": { ... }
/// }
/// ```
///
/// Multiple root objects:
/// ```json
/// [
///   { "eClass": "...", ... },
///   { "eClass": "...", ... }
/// ]
/// ```
///
/// ## Usage Example
///
/// ```swift
/// let parser = JSONParser()
/// let resource = try await parser.parse(jsonURL)
/// let roots = await resource.getRootObjects()
/// ```
public actor JSONParser {
    private let resourceSet: ResourceSet?
    private let options: JSONParseOptions

    /// The warnings recorded while the most recent document was parsed.
    ///
    /// The parser records a ``ConversionWarning/Kind/untypedClass(name:)`` warning for each
    /// class that it synthesises because no registered metamodel defines it, a
    /// ``ConversionWarning/Kind/droppedFeature(name:className:)`` warning for a value that
    /// its class does not define and that is not a primitive, and a
    /// ``ConversionWarning/Kind/unresolvedProxy(uri:fragment:)`` warning for a reference
    /// into the document that names no object. Each parse starts with no warnings.
    public private(set) var diagnostics = ConversionDiagnostics()

    /// Initializes a new JSON parser
    ///
    /// - Parameters:
    ///   - resourceSet: Optional ResourceSet that provides the registered metamodels and
    ///     receives the parsed resource.
    ///   - options: The options that control parsing (default: no required metamodel).
    public init(resourceSet: ResourceSet? = nil, options: JSONParseOptions = JSONParseOptions()) {
        self.resourceSet = resourceSet
        self.options = options
    }

    /// Parse a JSON file and return a Resource containing the objects
    /// - Parameter url: The URL of the JSON file to parse
    /// - Returns: A Resource containing the parsed objects
    /// - Throws: JSONError or DecodingError if parsing fails
    public func parse(_ url: URL) async throws -> Resource {
        let uri = URIReference.canonicalise(url.absoluteString)
        let data: Data
        if let resourceSet {
            data = try await resourceSet.readDocument(uri: uri)
        } else {
            data = try await FileURIHandler().read(uri)
        }
        return try await parse(data, uri: uri)
    }

    /// Parses the bytes of a JSON document.
    ///
    /// - Parameters:
    ///   - data: The JSON document.
    ///   - uri: The URI that the document has.
    /// - Returns: A resource with the URI that contains the parsed objects.
    /// - Throws: ``JSONError`` or a decoding error if parsing fails.
    public func parse(_ data: Data, uri documentURI: String) async throws -> Resource {
        let uri = URIReference.canonicalise(documentURI)

        // Create resource via ResourceSet if available, otherwise create directly
        let resource: Resource
        if let resourceSet = resourceSet {
            resource = await resourceSet.createResource(uri: uri)
        } else {
            resource = Resource(uri: uri)
        }

        diagnostics = ConversionDiagnostics()
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let documents = (json as? [[String: Any]]) ?? (json as? [String: Any]).map({ [$0] }) else {
            throw JSONError.invalidFormat("JSON must be an object with eClass field")
        }
        if let first = documents.first,
            let classes = await MetamodelClasses(resourceSet: resourceSet),
            let identifier = first[JSONSyntax.eClassKey] as? String, classes.resolve(identifier) != nil
        {
            var builder = JSONModelBuilder(classes: classes)
            try await builder.populate(resource, from: documents)
            diagnostics.merge(builder.diagnostics)
            return resource
        }
        if options.requiresMetamodel, !documents.isEmpty {
            let identifier = documents[0][JSONSyntax.eClassKey] as? String
            throw JSONError.unresolvedMetamodel(
                "No registered metamodel defines the class \(identifier ?? "(missing eClass)") of \(uri)")
        }

        // No registered metamodel defines the classes: synthesise them from the document
        let classes = SynthesisedClasses(documents: documents)
        for name in classes.names { diagnostics.record(.untypedClass(name: name)) }
        var builder = JSONModelBuilder(classes: classes)
        try await builder.populate(resource, from: documents)
        diagnostics.merge(builder.diagnostics)
        return resource
    }
}

/// Errors that can occur during JSON parsing
public enum JSONError: Error, Sendable {
    /// The document does not have the structure of a JSON resource.
    ///
    /// The associated value describes what was found instead.
    case invalidFormat(String)

    /// An object of the document has no `eClass` entry and no containment reference implies its class.
    case missingEClass

    /// A value of the document could not be read, or the resource could not be written.
    ///
    /// The associated value describes the value and the feature involved.
    case parseError(String)

    /// A registered metamodel was required but does not define the class of the document.
    ///
    /// The associated value describes the class that could not be found.
    case unresolvedMetamodel(String)
}

extension JSONError: CustomStringConvertible, LocalizedError {
    /// A sentence that describes the error, naming the class or feature involved.
    public var description: String {
        switch self {
        case .invalidFormat(let detail): return "Invalid JSON resource: \(detail)"
        case .missingEClass: return "A JSON object has no '\(JSONSyntax.eClassKey)' entry that names its class"
        case .parseError(let detail): return detail
        case .unresolvedMetamodel(let detail): return detail
        }
    }

    /// The ``description`` of the error.
    public var errorDescription: String? { description }
}
