//
// CrossDocumentFixtures.swift
// ECoreTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

@testable import ECore

/// Loads the cross-document fixtures (`library.ecore`, `mapping.ecore`, `library.mapping`).
struct CrossDocumentFixtures {
    /// Test failures specific to fixture loading.
    enum FixtureError: Error {
        case missing(String)
    }

    /// The directory that holds the fixture files.
    let directory: URL

    /// The resource set into which fixtures are loaded.
    let resourceSet: ResourceSet

    /// Locates the fixtures and creates a resource set that knows the mapping metamodel.
    ///
    /// - Throws: ``FixtureError/missing(_:)`` if the fixture directory cannot be found.
    init() async throws {
        guard let base = Bundle.module.resourceURL else { throw FixtureError.missing("bundle") }
        let candidates = [
            base.appendingPathComponent("Resources").appendingPathComponent("crossref"),
            base.appendingPathComponent("crossref"),
        ]
        guard let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw FixtureError.missing(candidates.map(\.path).joined(separator: ", "))
        }
        directory = found
        resourceSet = ResourceSet()
        let mapping = try await EPackage(url: directory.appendingPathComponent("mapping.ecore"))
        await resourceSet.registerMetamodel(mapping, uri: mapping.nsURI)
    }

    /// The absolute URI of a fixture file.
    ///
    /// - Parameter name: The file name.
    /// - Returns: The `file:` URI string.
    func uri(_ name: String) -> String {
        directory.appendingPathComponent(name).absoluteString
    }

    /// Loads the instance document `library.mapping` into the resource set.
    ///
    /// - Returns: The parsed resource.
    /// - Throws: Any parsing error.
    func loadMapping() async throws -> Resource {
        try await resourceSet.loadXMIResource(uri: uri("library.mapping"))
    }

    /// Loads a document of the fixture directory with the given reference parsing.
    ///
    /// - Parameters:
    ///   - name: The file name.
    ///   - parsing: How reference attributes are read.
    /// - Returns: The parsed resource.
    /// - Throws: Any parsing error.
    func loadXMI(_ name: String, parsing: XMIReferenceParsing) async throws -> Resource {
        try await resourceSet.loadXMIResource(uri: uri(name), referenceParsing: parsing)
    }

    /// Returns the objects of a resource in registration order that are instances of a class.
    ///
    /// - Parameters:
    ///   - className: The class name.
    ///   - resource: The resource to search.
    /// - Returns: The matching objects.
    func objects(of className: String, in resource: Resource) async -> [DynamicEObject] {
        await resource.getAllObjects().compactMap { $0 as? DynamicEObject }.filter {
            $0.eClass.name == className
        }
    }
}
