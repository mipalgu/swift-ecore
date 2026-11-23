//
// EObjectExtentTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests that every object is an instance of `EObject` wherever instances of a class are sought.
@Suite("EObject as the universal supertype")
struct EObjectExtentTests {
    /// Ecore's `EObject` class.
    private static var eObject: EClass { EcorePackage.metaClass(.eObject) }

    @Test("a resource lists every object as an instance of EObject")
    func resourceInstances() async throws {
        let w = try await LibraryWorld()
        let all = await w.resource.getAllObjectsIncludingContents().map(\.id)
        #expect(all.count == 6)
        #expect(await w.resource.getAllInstancesOf(Self.eObject).map(\.id) == all)
        #expect(await w.resource.getAllInstancesOf(w.model.item).count == 3)
        #expect(await w.resource.getAllInstancesOf(w.model.book).count == 2)
    }

    @Test("an execution engine finds every object as an instance of EObject")
    func engineInstances() async throws {
        let w = try await LibraryWorld()
        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(w.resource, alias: "lib")
        let all = Set(await w.resource.getAllObjectsIncludingContents().map(\.id))
        #expect(Set(await engine.allInstancesOf(Self.eObject).map(\.id)) == all)
        #expect(await engine.allInstancesOf(Self.eObject).count == all.count)
        #expect(await engine.firstInstanceOf(Self.eObject) != nil)
        #expect(await engine.allInstancesOf(w.model.item).count == 3)
    }

    @Test("creating or deleting any object affects the extent of EObject")
    func impactExtents() async throws {
        let w = try await LibraryWorld()
        let extra = DynamicEObject(eClass: w.model.member)
        let creation = try await w.resource.eAdd(objectId: w.lib.id, feature: "members", value: extra)
        let created = await ModelChangeImpact(changes: creation, in: [w.resource])
        #expect(created.affectedExtents.contains(Self.eObject.name))
        var reader = ModelDependencies()
        reader.recordExtent(Self.eObject.name)
        #expect(reader.isAffected(by: created))
        var index = ModelDependencyIndex<String>()
        index.insert(reader, for: "all")
        #expect(index.dependents(affectedBy: created) == ["all"])

        let attribute = try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "New")
        let edited = await ModelChangeImpact(changes: attribute, in: [w.resource])
        #expect(edited.affectedExtents.isEmpty)
        #expect(reader.isAffected(by: edited) == false)
    }
}
