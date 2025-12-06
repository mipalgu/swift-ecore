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
        try jsonString.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Serialize a Resource to a JSON string
    ///
    /// - Parameter resource: The Resource containing objects to serialize
    /// - Returns: JSON string
    /// - Throws: `JSONError` if serialization fails
    public func serialize(_ resource: Resource) async throws -> String {
        let roots = await resource.getRootObjects()

        guard !roots.isEmpty else {
            throw JSONError.emptyResource
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data: Data
        if roots.count == 1 {
            // Single root object
            guard let dynamicObject = roots[0] as? DynamicEObject else {
                throw JSONError.unsupportedObjectType
            }
            data = try encoder.encode(dynamicObject)
        } else {
            // Multiple root objects
            let dynamicObjects = roots.compactMap { $0 as? DynamicEObject }
            guard dynamicObjects.count == roots.count else {
                throw JSONError.unsupportedObjectType
            }
            data = try encoder.encode(dynamicObjects)
        }

        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw JSONError.encodingFailed
        }

        return jsonString
    }
}

/// Errors that can occur during JSON serialization
public enum JSONSerializationError: Error, Sendable {
    case emptyResource
    case unsupportedObjectType
    case encodingFailed
}

// Extend JSONError to include serialization errors
extension JSONError {
    static let emptyResource = JSONError.parseError("Resource contains no root objects")
    static let unsupportedObjectType = JSONError.parseError("Resource contains non-DynamicEObject objects")
    static let encodingFailed = JSONError.parseError("Failed to encode JSON to string")
}
