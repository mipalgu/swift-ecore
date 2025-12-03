//
// XMIParser.swift
// ECore
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation
import SwiftXML

/// Errors that can occur during XMI parsing
public enum XMIError: Error, Sendable {
    case invalidEncoding
    case missingRequiredAttribute(String)
    case unsupportedXMIVersion(String)
    case invalidReference(String)
    case parseError(String)
    case unknownElement(String)
}

/// Parser for XMI (XML Metadata Interchange) files
///
/// The XMI parser converts XMI files into EMF-compatible object graphs stored in Resources.
/// It handles:
/// - Metamodel (.ecore) files
/// - Model instance (.xmi) files
/// - Cross-resource references via href attributes
/// - XPath-style fragment identifiers
public actor XMIParser {
    private let resourceSet: ResourceSet?

    public init(resourceSet: ResourceSet? = nil) {
        self.resourceSet = resourceSet
    }

    /// Parse an XMI file and return a Resource containing the objects
    /// - Parameter url: The URL of the XMI file to parse
    /// - Returns: A Resource containing the parsed objects
    /// - Throws: XMIError if parsing fails
    public func parse(_ url: URL) async throws -> Resource {
        let data = try Data(contentsOf: url)
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw XMIError.invalidEncoding
        }

        let document = try parseXML(fromText: xmlString)

        // Create resource via ResourceSet if available, otherwise create directly
        let resource: Resource
        if let resourceSet = resourceSet {
            resource = await resourceSet.createResource(uri: url.absoluteString)
        } else {
            resource = Resource(uri: url.absoluteString)
        }

        // Parse XMI content
        try await parseXMIContent(document, into: resource)

        return resource
    }

    /// Parse XML document content into a Resource
    /// - Parameters:
    ///   - document: The parsed XML document
    ///   - resource: The Resource to populate with objects
    private func parseXMIContent(_ document: XDocument, into resource: Resource) async throws {
        // Check XMI version if present in root element
        if let xmiVersion = document.children.first?["xmi:version"] {
            // Accept XMI 2.0 and later
            if let version = Double(xmiVersion), version < 2.0 {
                throw XMIError.unsupportedXMIVersion(xmiVersion)
            }
        }

        // Parse all child elements as root objects
        for child in document.children.children {
            if let object = try await parseElement(child, in: resource) {
                await resource.add(object)
            }
        }
    }

    /// Parse an XML element into an EObject
    /// - Parameters:
    ///   - element: The XML element to parse
    ///   - resource: The Resource for context
    /// - Returns: The parsed EObject, or nil if the element should be skipped
    private func parseElement(_ element: XElement, in resource: Resource) async throws -> (any EObject)? {
        // TODO: Implement element parsing
        // For now, create a basic DynamicEObject placeholder
        // This will be expanded in Step 4.2 (Metamodel Deserialization)
        return nil
    }
}
