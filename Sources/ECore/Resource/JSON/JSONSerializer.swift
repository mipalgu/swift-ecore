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
/// ## Metamodels
///
/// Metamodels are written as instances of the Ecore metamodel, following the conventions
/// of emfjson for Ecore models (see ``serialize(_:relativeTo:)``):
///
/// ```json
/// {
///   "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EPackage",
///   "name": "shop",
///   "nsURI": "http://example.org/shop",
///   "nsPrefix": "shop",
///   "eClassifiers": [
///     {
///       "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EClass",
///       "name": "Order",
///       "eStructuralFeatures": [
///         {
///           "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EAttribute",
///           "name": "total",
///           "eType": {
///             "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EDataType",
///             "$ref": "http://www.eclipse.org/emf/2002/Ecore#//EInt"
///           }
///         }
///       ]
///     }
///   ]
/// }
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
    /// A resource without root objects is written as an empty array (`[]`). A resource whose
    /// root objects are all native packages is written as a metamodel, as
    /// ``serialize(_:relativeTo:)`` writes it with references to other documents relative to
    /// the document from which the first package was loaded.
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
    /// A resource whose root objects are all native packages is written as a metamodel, which
    /// keeps everything that the packages hold.
    ///
    /// - Parameters:
    ///   - resource: The Resource containing objects to serialise
    ///   - diagnostics: Receives the warnings, in the order in which they first occur
    /// - Returns: JSON string
    /// - Throws: `JSONError` if serialisation fails
    public func serialize(_ resource: Resource, diagnostics: inout ConversionDiagnostics) async throws -> String {
        let roots = await resource.getRootObjects()

        guard !roots.isEmpty else { return JSONSyntax.emptyDocument }
        let packages = roots.compactMap { $0 as? EPackage }
        if packages.count == roots.count { return serialize(packages) }
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

    // MARK: - Metamodels

    /// Serialises native packages as a JSON metamodel.
    ///
    /// The document holds what the `.ecore` document that ``XMISerializer`` writes for the
    /// packages holds, as an instance of the Ecore metamodel in the conventions of emfjson:
    ///
    /// - Every object starts with an `eClass` member that names its metaclass, such as
    ///   `"http://www.eclipse.org/emf/2002/Ecore#//EClass"`; the other members follow in a
    ///   fixed order, so the same packages are always written as the same text.
    /// - Contained elements are nested under their containment feature (`eClassifiers`,
    ///   `eSubpackages`, `eStructuralFeatures`, `eOperations`, `eParameters`, `eLiterals`,
    ///   `eAnnotations`, `eTypeParameters`, and the generic type features).
    /// - Attributes are written with their Ecore names and JSON types, and only where they
    ///   differ from their defaults (the name, `nsURI`, and `nsPrefix` of a package are always
    ///   written).
    /// - References are `$ref` objects: `{"$ref": "//Book/author"}` for an element of the
    ///   document (by its name-based fragment), `{"$ref": "http://www.eclipse.org/emf/2002/Ecore#//EString"}`
    ///   for a class or data type of Ecore, and `{"$ref": "other.ecore#//Name"}` for an
    ///   element of another document, relative to the written document. A reference whose
    ///   target is not of the declared type of the feature (such as the type of a typed
    ///   element, which can be a class, data type, or enumeration) also names the class of the
    ///   target in an `eClass` member.
    /// - The details of an annotation are a JSON object from keys to values, in order.
    /// - One package is written as an object; several packages as an array, whose elements
    ///   are referred to as `/0/Name`, `/1/Name`, and so on.
    ///
    /// XML comments and `xmi:id` values of a document from which the packages were loaded
    /// have no place in JSON and are not written.
    ///
    /// - Parameters:
    ///   - packages: The root packages, in document order.
    ///   - documentURL: The location that the document will have, against which references to
    ///     other documents are made relative, or `nil` to use the location of the document
    ///     from which the first package was loaded.
    /// - Returns: The text of the document, ending in a newline, or an empty array (`[]`) if
    ///   there are no packages.
    public func serialize(_ packages: [EPackage], relativeTo documentURL: URL? = nil) -> String {
        guard !packages.isEmpty else { return JSONSyntax.emptyDocument }
        let writer = JSONMetamodelWriter(
            roots: packages, documentURI: documentURL.map { URIReference.canonicalise($0.absoluteString) })
        return writer.document.document
    }

    /// Serialises a native package as a JSON metamodel file.
    ///
    /// References to other documents are written relative to the file; see
    /// ``serialize(_:relativeTo:)`` for the format.
    ///
    /// - Parameters:
    ///   - package: The root package to serialise.
    ///   - url: The location of the file to write.
    /// - Throws: An error if the file cannot be written.
    public func serialize(_ package: EPackage, to url: URL) throws {
        try serialize([package], relativeTo: url)
            .write(to: url, atomically: FileURIHandler.writesAtomically, encoding: .utf8)
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
