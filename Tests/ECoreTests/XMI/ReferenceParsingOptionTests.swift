//
// ReferenceParsingOptionTests.swift
// ECoreTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for the reference parsing option and for fragment segment rules.
@Suite("Reference Parsing Options and Fragment Rules")
struct ReferenceParsingOptionTests {
    private let entryRule = FragmentSegmentRule(className: "Entry") { object, _ in
        object.eGet("label") as? String
    }

    @Test("Interpreted parsing is the default")
    func interpretedByDefault() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadXMI("library.mapping", parsing: .interpreted)
        let entry = try #require(await fixtures.objects(of: "Entry", in: resource).first)
        #expect(await resource.eGet(objectId: entry.id, feature: "ecoreClass") is ResourceProxy)
    }

    @Test("Raw text parsing keeps reference attributes exactly as written")
    func rawTextKeepsAttributes() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadXMI("library.mapping", parsing: .rawText)
        let entries = await fixtures.objects(of: "Entry", in: resource)
        let first = try #require(entries.first)
        #expect(await resource.eGet(objectId: first.id, feature: "ecoreClass") as? String == "library.ecore#//Book")
        #expect(
            await resource.eGet(objectId: first.id, feature: "ecoreFeature") as? String
                == "ecore:EAttribute library.ecore#//Book/title")
        let root = try #require(await resource.getRootObjects().first as? DynamicEObject)
        #expect(
            await resource.eGet(objectId: root.id, feature: "usedPackages") as? String
                == "library.ecore#//archive other/Other.ecore#/")
    }

    @Test("A registered rule names objects in fragments")
    func ruleResolvesAndWrites() async throws {
        let fixtures = try await CrossDocumentFixtures()
        await fixtures.resourceSet.registerFragmentSegmentRule(entryRule)
        let resource = try await fixtures.loadMapping()
        let navigator = FragmentNavigator(resource: resource)
        let author = try #require(await fixtures.objects(of: "Entry", in: resource).last)

        #expect(await navigator.resolve("//author")?.id == author.id)
        #expect(await navigator.resolve("//missing") == nil)
        #expect(await navigator.fragment(for: author.id) == "//author")
        #expect(await navigator.segmentName(of: author) == "author")
        #expect(await fixtures.resourceSet.fragmentSegmentRule(forClass: "Entry") != nil)
        #expect(await fixtures.resourceSet.fragmentSegmentRule(forClass: "Mapping") == nil)
    }

    @Test("Without a rule, objects of the class take no part in name-based fragments")
    func noRuleNoFragment() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadMapping()
        let navigator = FragmentNavigator(resource: resource)
        let entry = try #require(await fixtures.objects(of: "Entry", in: resource).first)
        #expect(await navigator.resolve("//book") == nil)
        #expect(await navigator.fragment(for: entry.id) == nil)
    }

    @Test("The EMF layout writes rule-named fragments for references")
    func ruleDrivesSerialisation() async throws {
        let fixtures = try await CrossDocumentFixtures()
        await fixtures.resourceSet.registerFragmentSegmentRule(entryRule)
        let resource = try await fixtures.loadMapping()
        let text = try await XMISerializer(options: .emf).serialize(resource)
        #expect(text.contains("related=\"#//author\""))
        #expect(text.contains("related=\"#//book #//author\""))
    }

    @Test("Relative URIs are computed against the location that is written")
    func relativeToWrittenLocation() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadMapping()
        await resource.resolveProxies()
        let directory = fixtures.directory.appendingPathComponent("nested-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("copy.mapping")
        try await XMISerializer(options: .emf).serialize(resource, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("ecoreClass=\"../library.ecore#//Book\""))
    }
}
