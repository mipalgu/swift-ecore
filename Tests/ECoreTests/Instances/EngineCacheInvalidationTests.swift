//
// EngineCacheInvalidationTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Execution engine cache invalidation")
struct EngineCacheInvalidationTests {

    @Test("invalidation discards the navigated values of changed features only")
    func invalidatesChangedFeatures() async throws {
        let w = try await LibraryWorld()
        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(w.resource, alias: "lib")
        #expect(try await engine.navigate(from: w.book1, property: "title") as? String == "Dune")
        #expect(try await engine.navigate(from: w.book2, property: "title") as? String == "Emma")
        #expect(await engine.getCacheStatistics()["navigationCacheSize"] == 2)

        let changes = try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "Arrakis")
        #expect(try await engine.navigate(from: w.book1, property: "title") as? String == "Dune")
        await engine.invalidateCaches(for: changes)
        #expect(await engine.getCacheStatistics()["navigationCacheSize"] == 1)
        #expect(try await engine.navigate(from: w.book1, property: "title") as? String == "Arrakis")
        await engine.invalidateCaches(for: [])
        #expect(await engine.getCacheStatistics()["navigationCacheSize"] == 2)
    }

    @Test("creating an object discards the cached instances of types")
    func invalidatesTypeExtents() async throws {
        let w = try await LibraryWorld()
        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(w.resource, alias: "lib")
        #expect(await engine.allInstancesOf(w.model.member).count == 1)
        let bob = DynamicEObject(eClass: w.model.member)
        let changes = try await w.resource.eAdd(objectId: w.lib.id, feature: "members", value: bob)
        #expect(await engine.allInstancesOf(w.model.member).count == 1)
        await engine.invalidateCaches(for: changes)
        #expect(await engine.allInstancesOf(w.model.member).count == 2)
    }

    @Test("deleting an object discards everything cached for it")
    func invalidatesDeletedObjects() async throws {
        let w = try await LibraryWorld()
        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(w.resource, alias: "lib")
        _ = try await engine.navigate(from: w.book2, property: "title")
        _ = try await engine.navigate(from: w.book2, property: "isbn")
        let changes = await w.resource.delete([w.book2.id])
        await engine.invalidateCaches(for: changes)
        #expect(await engine.getCacheStatistics()["navigationCacheSize"] == 0)
    }

    @Test("computed values are discarded on any change")
    func invalidatesComputedValues() async throws {
        let w = try await LibraryWorld()
        await w.resourceSet.registerDerivedFeatureRule(
            DerivedFeatureRule(className: "Member", featureName: "name") { _, _ in "Computed" })
        let bob = DynamicEObject(eClass: w.model.member)
        try await w.resource.eAdd(objectId: w.lib.id, feature: "members", value: bob)
        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(w.resource, alias: "lib")
        #expect(try await engine.navigate(from: bob, property: "name") as? String == "Computed")
        _ = try await engine.navigate(from: w.book2, property: "title")
        #expect(await engine.getCacheStatistics()["navigationCacheSize"] == 2)
        let changes = try await w.resource.eSetWithChanges(objectId: w.alice.id, feature: "name", value: "Al")
        await engine.invalidateCaches(for: changes)
        #expect(await engine.getCacheStatistics()["navigationCacheSize"] == 1)
        await engine.clearCaches()
        #expect(await engine.getCacheStatistics()["navigationCacheSize"] == 0)
    }
}
