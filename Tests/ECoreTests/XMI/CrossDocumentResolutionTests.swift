//
// CrossDocumentResolutionTests.swift
// ECoreTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for resolving name-based fragments and cross-resource proxies.
@Suite("Cross-Document Reference Resolution")
struct CrossDocumentResolutionTests {

    /// Resolves a fragment in a resource and returns the element name.
    private func name(_ fragment: String, in resource: Resource) async -> String? {
        guard let object = await XPathResolver(resource: resource).resolveObject(fragment) else { return nil }
        return FragmentNavigator.name(of: object)
    }

    // MARK: - Dynamic Ecore graphs

    @Test("Name-based fragments resolve in a dynamic Ecore resource")
    func resolvesInDynamicEcore() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.resourceSet.loadXMIResource(uri: fixtures.uri("library.ecore"))

        #expect(await name("#/", in: resource) == "library")
        #expect(await name("#//Book", in: resource) == "Book")
        #expect(await name("#//Book/title", in: resource) == "title")
        #expect(await name("//Book/author", in: resource) == "author")
        #expect(await name("#//BookCategory/Mystery", in: resource) == "Mystery")
        #expect(await name("#//archive", in: resource) == "archive")
        #expect(await name("#//archive/Record", in: resource) == "Record")
        #expect(await name("#//archive/Record/year", in: resource) == "year")
        #expect(await name("#//Book/borrow", in: resource) == "borrow")
        #expect(await name("#//Book/borrow/days", in: resource) == "days")
        #expect(await name("#//Book/missing", in: resource) == nil)
        #expect(await name("#//Nothing", in: resource) == nil)
        #expect(await name("#/x", in: resource) == nil)
    }

    @Test("Positional fragments keep working beside name-based ones")
    func positionalFragmentsStillResolve() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadMapping()
        let resolver = XPathResolver(resource: resource)
        let entry = try #require(await resolver.resolveObject("#//@entries.1") as? DynamicEObject)
        #expect(entry.eGet("label") as? String == "author")
    }

    @Test("Fragments are computed for dynamic Ecore elements")
    func computesFragmentsForDynamicEcore() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.resourceSet.loadXMIResource(uri: fixtures.uri("library.ecore"))
        let navigator = FragmentNavigator(resource: resource)

        for fragment in ["/", "//Book", "//Book/title", "//BookCategory/Mystery", "//archive/Record/year", "//Book/borrow/days"] {
            let object = try #require(await navigator.resolve(fragment))
            #expect(await navigator.fragment(for: object.id) == fragment)
        }
        #expect(await navigator.fragment(for: EUUID()) == nil)
    }

    // MARK: - Native Ecore objects

    @Test("Name-based fragments resolve to native objects")
    func resolvesNativeObjects() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.resourceSet.loadEcoreResource(uri: fixtures.uri("library.ecore"))
        let resolver = XPathResolver(resource: resource)

        #expect(try #require(await resolver.resolveObject("#/") as? EPackage).name == "library")
        #expect(try #require(await resolver.resolveObject("#//Book") as? EClass).name == "Book")
        #expect(try #require(await resolver.resolveObject("#//Book/title") as? EAttribute).name == "title")
        #expect(try #require(await resolver.resolveObject("#//Book/author") as? EReference).name == "author")
        #expect(try #require(await resolver.resolveObject("#//BookCategory") as? EEnum).literals.count == 3)
        #expect(try #require(await resolver.resolveObject("#//BookCategory/Mystery") as? EEnumLiteral).name == "Mystery")
        #expect(try #require(await resolver.resolveObject("#//archive") as? EPackage).name == "archive")
        #expect(try #require(await resolver.resolveObject("#//archive/Record") as? EClass).name == "Record")
        #expect(try #require(await resolver.resolveObject("#//archive/Record/year") as? EAttribute).name == "year")
        #expect(await resolver.resolveObject("#//Book/nothing") == nil)
    }

    @Test("Native resources register their package as a metamodel")
    func nativeResourceRegistersMetamodel() async throws {
        let fixtures = try await CrossDocumentFixtures()
        _ = try await fixtures.resourceSet.loadEcoreResource(uri: fixtures.uri("library.ecore"))
        let registered = await fixtures.resourceSet.getMetamodel(uri: "http://swift-modelling.org/test/library")
        #expect(registered?.name == "library")

        let again = try await fixtures.resourceSet.loadEcoreResource(uri: fixtures.uri("library.ecore"))
        #expect(await again.getRootObjects().count == 1)
    }

    @Test("Native loading rejects invalid URIs")
    func nativeLoadingRejectsBadURIs() async throws {
        let fixtures = try await CrossDocumentFixtures()
        await #expect(throws: (any Error).self) {
            _ = try await fixtures.resourceSet.loadEcoreResource(uri: "not a uri")
        }
    }

    @Test("Duplicate names carry an index in fragments")
    func duplicateNamesAreIndexed() async throws {
        let first = EClass(name: "Dup")
        let second = EClass(name: "Dup")
        let package = EPackage(name: "p", nsURI: "http://x/p", nsPrefix: "p", eClassifiers: [first, second])
        let resource = Resource(uri: "file:///tmp/p.ecore")
        await resource.registerNativePackage(package)

        let resolver = XPathResolver(resource: resource)
        #expect(await resolver.resolve("#//Dup") == first.id)
        #expect(await resolver.resolve("#//Dup.1") == second.id)
        #expect(await resolver.resolve("#//Dup.2") == nil)
        let navigator = FragmentNavigator(resource: resource)
        #expect(await navigator.fragment(for: second.id) == "//Dup.1")
        #expect(await navigator.fragment(for: first.id) == "//Dup")
    }

    // MARK: - Proxy resolution

    @Test("Proxies resolve to elements of the target resource")
    func proxiesResolveToTargets() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let proxy = ResourceProxy(uri: fixtures.uri("library.ecore"), fragment: "//Book/title")
        let object = try #require(await proxy.resolveObject(in: fixtures.resourceSet))
        #expect(FragmentNavigator.name(of: object) == "title")
        #expect(await ResourceProxy(uri: fixtures.uri("missing.ecore"), fragment: "/").resolve(in: fixtures.resourceSet) == nil)
        #expect(await ResourceProxy(uri: fixtures.uri("missing.ecore"), fragment: "/").resolveObject(in: fixtures.resourceSet) == nil)
        #expect(await ResourceProxy(uri: fixtures.uri("library.ecore"), fragment: "//Nope").resolveObject(in: fixtures.resourceSet) == nil)
    }

    @Test("Resolving all proxies replaces them with direct references")
    func resolvesAllProxies() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadMapping()
        let report = await fixtures.resourceSet.resolveAllProxies()

        // ecorePackage plus the class and feature of the first entry plus six references of the second
        #expect(report.resolved == 1 + 2 + 6)
        // usedPackages refers to a document that does not exist
        #expect(report.unresolved.count == 2)

        let entries = await fixtures.objects(of: "Entry", in: resource)
        let book = try #require(entries.first { $0.eGet("label") as? String == "book" })
        let target = try #require(await resource.eGet(objectId: book.id, feature: "ecoreFeature") as? EUUID)
        let resolved = try #require(await fixtures.resourceSet.resolve(target))
        #expect(FragmentNavigator.name(of: resolved.object) == "title")
        #expect(await resolved.resource.uri == fixtures.uri("library.ecore"))

        // A second run has nothing left to resolve apart from the unresolvable ones
        let again = await resource.resolveProxies()
        #expect(again.resolved == 0)
        #expect(again.unresolved.count == 2)
    }

    @Test("Resolving on access replaces single and multiple proxies")
    func resolvesOnAccess() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadMapping()
        let root = try #require(await resource.getRootObjects().first)

        let single = try #require(await resource.eGetResolving(objectId: root.id, feature: "ecorePackage") as? EUUID)
        #expect(await resource.eGet(objectId: root.id, feature: "ecorePackage") as? EUUID == single)

        // The list refers to a missing document, so it stays as proxies
        #expect(await resource.eGetResolving(objectId: root.id, feature: "usedPackages") is [ResourceProxy])
        #expect(await resource.eGetResolving(objectId: root.id, feature: "name") as? String == "Library")

        let entries = await fixtures.objects(of: "Entry", in: resource)
        let book = try #require(entries.first { $0.eGet("label") as? String == "book" })
        #expect(await resource.eGetResolving(objectId: book.id, feature: "ecoreClass") is EUUID)
        #expect(await resource.eGetResolving(objectId: book.id, feature: "ecoreEnum") == nil)
    }

    @Test("Multi-valued proxy lists resolve when every target exists")
    func resolvesProxyLists() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadMapping()
        let root = try #require(await resource.getRootObjects().first)
        let library = fixtures.uri("library.ecore")
        await resource.eSet(objectId: root.id, feature: "usedPackages", value: [
            ResourceProxy(uri: library, fragment: "/"),
            ResourceProxy(uri: resource.uri, fragment: "//@entries.0"),
            ResourceProxy(uri: library, fragment: "//archive"),
        ])
        let ids = try #require(await resource.eGetResolving(objectId: root.id, feature: "usedPackages") as? [EUUID])
        #expect(ids.count == 3)
        let local = try #require(await resource.resolve(ids[1]) as? DynamicEObject)
        #expect(local.eGet("label") as? String == "book")
    }
}
