//
// EmptyDocumentTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for writing and reading resources that hold no root objects.
///
/// EMF writes an empty resource as an XMI document that consists of the wrapper
/// element alone. Both XMI writers do the same, the JSON writer writes an empty
/// array, and both parsers read these documents back as empty resources.
@Suite("Empty documents")
struct EmptyDocumentTests {
    /// The document that EMF writes for a resource without roots.
    static let emptyXMI = """
        <?xml version="1.0" encoding="UTF-8"?>
        <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"/>

        """

    @Test(
        "an empty resource is written as the XMI wrapper element",
        arguments: [XMISerializationOptions.legacy, .emf, .emfWrapped])
    func emptyXMIDocument(options: XMISerializationOptions) async throws {
        let empty = Resource(uri: "file:///models/empty.xmi")
        let text = try await XMISerializer(options: options).serialize(empty)
        #expect(text == Self.emptyXMI)
        #expect(XMIDocumentSyntax.emptyDocument == Self.emptyXMI)
    }

    @Test("the XMI wrapper element alone reads as an empty resource")
    func readsEmptyXMIDocument() async throws {
        let resource = try await XMIParser().parse(Self.emptyXMI, uri: "memory:/empty.xmi")
        #expect(await resource.getRootObjects().isEmpty)
        #expect(await resource.getAllObjects().isEmpty)
        let loaded = try await ResourceSet().loadXMIResource(text: Self.emptyXMI, uri: "memory:/loaded-empty.xmi")
        #expect(await loaded.getRootObjects().isEmpty)
    }

    @Test("an empty XMI document survives a round trip", arguments: [XMISerializationOptions.legacy, .emf])
    func emptyXMIRoundTrip(options: XMISerializationOptions) async throws {
        let resource = try await XMIParser().parse(Self.emptyXMI, uri: "memory:/round-trip.xmi")
        #expect(try await XMISerializer(options: options).serialize(resource) == Self.emptyXMI)
    }

    @Test("an empty resource is written as an empty JSON array")
    func emptyJSONDocument() async throws {
        let text = try await JSONSerializer().serialize(Resource(uri: "file:///models/empty.json"))
        #expect(text == "[]")
        #expect(text == JSONSyntax.emptyDocument)
    }

    @Test("an empty JSON array reads as an empty resource")
    func readsEmptyJSONDocument() async throws {
        let resource = try await JSONParser().parse(Data("[]".utf8), uri: "memory:/empty.json")
        #expect(await resource.getRootObjects().isEmpty)
        let required = JSONParser(options: JSONParseOptions(requiresMetamodel: true))
        let strict = try await required.parse(Data("[]".utf8), uri: "memory:/strict-empty.json")
        #expect(await strict.getRootObjects().isEmpty)
        let loaded = try await ResourceSet().loadJSONResource(text: "[ ]", uri: "memory:/loaded-empty.json")
        #expect(try await JSONSerializer().serialize(loaded) == "[]")
    }
}
