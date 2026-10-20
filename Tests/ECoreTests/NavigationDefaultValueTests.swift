//
// NavigationDefaultValueTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests that navigation reads the unset attributes of loaded documents as their defaults.
///
/// The objects come from an XMI document loaded against a metamodel read from an `.ecore`
/// document, so the attribute types are those the metamodel loader produces. Navigation
/// reads defaults once they are enabled on the execution engine.
@Suite("Navigating unset attributes of loaded documents")
struct NavigationDefaultValueTests {

    /// A loaded document with an engine that reads unset attributes as their defaults.
    private struct Fixture {
        /// The resource loaded from the wrapped document.
        let resource: Resource

        /// The execution engine with default reads enabled.
        let engine: ECoreExecutionEngine

        /// The classifiers of the root package in document order.
        let classifiers: [DynamicEObject]

        /// Loads the wrapped classifier document and prepares the engine.
        init() async throws {
            let (set, _) = try await WrappedDocumentLoadingTests.makeResourceSet()
            resource = try await WrappedDocumentLoadingTests.load("classifiers-wrapped.xmi", in: set)
            let root = try #require(await resource.getRootObjects().first as? DynamicEObject)
            classifiers = try await WrappedDocumentLoadingTests.objects("classifiers", of: root, in: resource)
            engine = ECoreExecutionEngine(models: [:])
            await engine.registerResource(resource, alias: "IN")
            await engine.enableDefaultValues()
        }

        /// The class without any explicit attribute values.
        var author: DynamicEObject { classifiers[2] }

        /// The class with explicit attribute values.
        var book: DynamicEObject { classifiers[3] }
    }

    @Test("an unset Boolean reads as false and its negation as true")
    func unsetBoolean() async throws {
        let fixture = try await Fixture()
        let value = try await fixture.engine.navigate(from: fixture.author, property: "isAbstract")
        let flag = try #require(value as? Bool)
        #expect(flag == false)
        #expect(!flag == true)
        #expect(try await fixture.engine.navigate(from: fixture.book, property: "isAbstract") as? Bool == true)
    }

    @Test("unset numbers read as zero")
    func unsetNumbers() async throws {
        let fixture = try await Fixture()
        #expect(try await fixture.engine.navigate(from: fixture.author, property: "rank") as? Int == 0)
        #expect(try await fixture.engine.navigate(from: fixture.author, property: "weight") as? Double == 0)
        #expect(try await fixture.engine.navigate(from: fixture.book, property: "rank") as? Int == 3)
    }

    @Test("an unset attribute with a default value literal reads as the literal")
    func literalDefault() async throws {
        let fixture = try await Fixture()
        let value = try await fixture.engine.navigate(from: fixture.author, property: "visibility")
        #expect(value as? String == "public")
    }

    @Test("an unset string without a literal stays undefined")
    func unsetString() async throws {
        let fixture = try await Fixture()
        #expect(try await fixture.engine.navigate(from: fixture.author, property: "comment") == nil)
    }

    @Test("reading defaults leaves the features unset and unsaved")
    func defaultsStayUnset() async throws {
        let fixture = try await Fixture()
        for property in ["isAbstract", "rank", "weight", "visibility", "comment"] {
            _ = try await fixture.engine.navigate(from: fixture.author, property: property)
        }
        let author = try #require(await fixture.resource.resolve(fixture.author.id) as? DynamicEObject)
        for property in ["isAbstract", "rank", "weight", "visibility", "comment"] {
            #expect(!author.eIsSet(property), "\(property)")
        }
        let text = try await XMISerializer(options: .emf).serialize(fixture.resource)
        #expect(!text.contains("isAbstract=\"false\""))
        #expect(!text.contains("rank=\"0\""))
        #expect(!text.contains("weight="))
        #expect(!text.contains("visibility="))
    }
}
