//
// JSONSerializer.swift
// ECore
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

/// Serializes EMF objects to JSON format (emfjson/pyecore compatible)
///
/// The JSON serializer converts in-memory object graphs stored in Resources to JSON files.
/// It handles:
/// - Single root objects and multiple root objects
/// - Nested containment references
/// - Cross-references (using $ref)
/// - Compatible with pyecore and emfjson-jackson formats
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
/// let serializer = JSONSerializer()
/// try await serializer.serialize(resource, to: outputURL)
/// ```
public struct JSONSerializer: Sendable {

    /// Initialize a new JSON serializer
    public init() {}

    /// Serialize a Resource to a JSON file
    ///
    /// - Parameters:
    ///   - resource: The Resource containing objects to serialize
    ///   - url: The URL where the JSON file should be written
    /// - Throws: `JSONError` if serialization fails or I/O errors occur
    public func serialize(_ resource: Resource, to url: URL) async throws {
        let jsonString = try await serialize(resource)
        try jsonString.write(to: url, atomically: FileURIHandler.writesAtomically, encoding: .utf8)
    }

    /// Serialize a Resource to a JSON string
    ///
    /// Every `eClass` is written as `"<nsURI>#//<Name>"` when the class belongs to a metamodel
    /// registered with the resource's resource set. Non-containment references are written as
    /// `{"$ref": "<fragment>"}` (an array of such objects for many-valued features), and
    /// references to objects of other documents as `{"$ref": "<uri>#<fragment>"}`. The
    /// container side of a containment reference is implied by the nesting and left out of
    /// nested objects.
    /// Keys are sorted.
    ///
    /// A resource without root objects is written as an empty array (`[]`).
    ///
    /// - Parameter resource: The Resource containing objects to serialize
    /// - Returns: JSON string
    /// - Throws: `JSONError` if serialization fails
    public func serialize(_ resource: Resource) async throws -> String {
        var diagnostics = ConversionDiagnostics()
        return try await serialize(resource, diagnostics: &diagnostics)
    }

    /// Serialise a Resource to a JSON string, recording what cannot be kept
    ///
    /// The document is the one that ``serialize(_:)`` writes. The serialiser records a
    /// ``ConversionWarning`` wherever it writes a value less faithfully than it is held: a
    /// class of no registered package by its name alone, a reference to an object without a
    /// fragment as the object's identifier, a contained object that the resource does not
    /// hold, and a proxy into the written document that names no object.
    ///
    /// - Parameters:
    ///   - resource: The Resource containing objects to serialise
    ///   - diagnostics: Receives the warnings, in the order in which they first occur
    /// - Returns: JSON string
    /// - Throws: `JSONError` if serialisation fails
    public func serialize(_ resource: Resource, diagnostics: inout ConversionDiagnostics) async throws -> String {
        let roots = await resource.getRootObjects()

        guard !roots.isEmpty else { return JSONSyntax.emptyDocument }
        let dynamicRoots = roots.compactMap { $0 as? DynamicEObject }
        guard dynamicRoots.count == roots.count else {
            throw JSONError.unsupportedObjectType
        }

        var context = await JSONWritingContext(resource: resource)
        var documents: [[String: Any]] = []
        for root in dynamicRoots {
            documents.append(try await context.dictionary(for: root))
        }
        diagnostics.merge(context.diagnostics)
        let document: Any = documents.count == 1 ? documents[0] : documents

        let data = try JSONSerialization.data(
            withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw JSONError.encodingFailed
        }

        return jsonString
    }
}

/// Errors that can occur during JSON serialization
public enum JSONSerializationError: Error, Sendable {
    @available(*, deprecated, message: "An empty resource is written as an empty array, so this error is never thrown")
    case emptyResource
    case unsupportedObjectType
    case encodingFailed
}

// Extend JSONError to include serialization errors
extension JSONError {
    @available(*, deprecated, message: "An empty resource is written as an empty array, so this error is never thrown")
    static let emptyResource = JSONError.parseError("Resource contains no root objects")
    static let unsupportedObjectType = JSONError.parseError("Resource contains non-DynamicEObject objects")
    static let encodingFailed = JSONError.parseError("Failed to encode JSON to string")
}
