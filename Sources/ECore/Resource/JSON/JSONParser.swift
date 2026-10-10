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
/// denote (see ``JSONFragments``). Otherwise the parser fabricates classes from the document,
/// unless ``JSONParseOptions/requiresMetamodel`` asks for an error.
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

        // Try to decode as array first, then fall back to single object
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Check if JSON is an array or single object
        let json = try JSONSerialization.jsonObject(with: data, options: [])

        let documents: [[String: Any]]? = (json as? [[String: Any]]) ?? (json as? [String: Any]).map { [$0] }
        if let documents, let first = documents.first,
            let classes = await MetamodelClasses(resourceSet: resourceSet),
            let identifier = first[JSONSyntax.eClassKey] as? String, classes.resolve(identifier) != nil
        {
            var builder = JSONModelBuilder(classes: classes)
            try await builder.populate(resource, from: documents)
            return resource
        }
        if options.requiresMetamodel, let documents, !documents.isEmpty {
            let identifier = documents[0][JSONSyntax.eClassKey] as? String
            throw JSONError.unresolvedMetamodel(
                "No registered metamodel defines the class \(identifier ?? "(missing eClass)") of \(uri)")
        }

        if let jsonArray = json as? [[String: Any]] {
            // Multiple root objects
            var rootObjects: [any EObject] = []
            for jsonObject in jsonArray {
                let objectData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
                rootObjects.append(try await parseSingleObject(from: objectData, decoder: decoder, in: resource))
            }
            await resource.add(contentsOf: rootObjects)
        } else {
            // Single root object
            let dynamicObject = try await parseSingleObject(from: data, decoder: decoder, in: resource)
            await resource.add(dynamicObject)
        }

        return resource
    }

    /// Parse a single JSON object into a DynamicEObject
    private func parseSingleObject(from data: Data, decoder: JSONDecoder, in resource: Resource) async throws -> DynamicEObject {
        // Extract eClass to determine metamodel
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let jsonDict = json as? [String: Any] else {
            throw JSONError.invalidFormat("JSON must be an object with eClass field")
        }

        guard let eClassString = jsonDict[JSONSyntax.eClassKey] as? String else {
            throw JSONError.missingEClass
        }

        // No registered metamodel defines the class: fabricate one from the document
        let eClass = DynamicEObject.createDynamicEClass(from: eClassString, jsonDict: jsonDict)

        // Set up decoder with EClass context
        decoder.userInfo[.eClassKey] = eClass

        // Decode the DynamicEObject
        let dynamicObject = try decoder.decode(DynamicEObject.self, from: data)

        return dynamicObject
    }
}

/// Errors that can occur during JSON parsing
public enum JSONError: Error, Sendable {
    case invalidFormat(String)
    case missingEClass
    case parseError(String)

    /// A registered metamodel was required but does not define the class of the document.
    ///
    /// The associated value describes the class that could not be found.
    case unresolvedMetamodel(String)
}
