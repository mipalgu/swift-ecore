//
// InstanceEditingDomainTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@MainActor
@Suite("Instance editing domain")
struct InstanceEditingDomainTests {

    func makeDomain() async throws -> (InstanceEditingDomain, LibraryWorld) {
        let w = try await LibraryWorld()
        let domain = await InstanceEditingDomain(resource: w.resource, resourceSet: w.resourceSet)
        return (domain, w)
    }

    @Test("the snapshot is readable synchronously and follows every change")
    func snapshotFollows() async throws {
        let (domain, w) = try await makeDomain()
        #expect(domain.snapshot.value(of: w.book1.id, feature: "title") as? String == "Dune")
        try await domain.perform(domain.setCommand(object: w.book1, feature: w.model.title, value: "Changed"))
        #expect(domain.snapshot.value(of: w.book1.id, feature: "title") as? String == "Changed")
        try await domain.undo()
        #expect(domain.snapshot.value(of: w.book1.id, feature: "title") as? String == "Dune")
        try await domain.redo()
        #expect(domain.snapshot.value(of: w.book1.id, feature: "title") as? String == "Changed")
        #expect(domain.resource == w.resource)
    }

    @Test("undo and redo availability and labels follow the history")
    func history() async throws {
        let (domain, w) = try await makeDomain()
        #expect(!domain.canUndo && !domain.canRedo)
        #expect(domain.undoLabel == nil && domain.redoLabel == nil)
        try await domain.perform(domain.setCommand(object: w.book1, feature: w.model.title, value: "A"))
        #expect(domain.canUndo && !domain.canRedo)
        #expect(domain.undoLabel == "Set title = A")
        try await domain.undo()
        #expect(!domain.canUndo && domain.canRedo)
        #expect(domain.redoLabel == "Set title = A")
    }

    @Test("every command kind can be created through the domain")
    func factories() async throws {
        let (domain, w) = try await makeDomain()
        let descriptor = try #require(domain.legalChildren(of: w.other).first { $0.eClass.name == "Dvd" })
        try await domain.perform(domain.createChildCommand(container: w.other, descriptor: descriptor))
        try await domain.perform(domain.createRootCommand(eClass: w.model.library))
        try await domain.perform(domain.addCommand(object: w.other, feature: w.model.items, value: w.dvd, at: 0))
        try await domain.perform(domain.removeCommand(object: w.other, feature: w.model.items, value: w.dvd))
        try await domain.perform(domain.deleteCommand(objects: [w.alice]))
        #expect(domain.snapshot.contains(id: w.alice.id) == false)
        #expect(domain.snapshot.rootIDs.count == 4)
    }

    @Test("dirty tracking follows the saved state")
    func dirty() async throws {
        let (domain, w) = try await makeDomain()
        #expect(!domain.isDirty)
        try await domain.perform(domain.setCommand(object: w.book1, feature: w.model.title, value: "A"))
        #expect(domain.isDirty)
        domain.markSaved()
        #expect(!domain.isDirty)
        try await domain.perform(domain.setCommand(object: w.book1, feature: w.model.title, value: "B"))
        #expect(domain.isDirty)
        try await domain.undo()
        #expect(!domain.isDirty)
        try await domain.undo()
        #expect(domain.isDirty)
        try await domain.redo()
        #expect(!domain.isDirty)
    }

    @Test("running a command after undoing past the saved state keeps the model dirty")
    func dirtyAfterBranch() async throws {
        let (domain, w) = try await makeDomain()
        try await domain.perform(domain.setCommand(object: w.book1, feature: w.model.title, value: "A"))
        domain.markSaved()
        try await domain.undo()
        try await domain.perform(domain.setCommand(object: w.book1, feature: w.model.title, value: "B"))
        try await domain.undo()
        #expect(domain.isDirty)
    }

    @Test("observers receive changes after the snapshot has been updated until cancelled")
    func observation() async throws {
        let (domain, w) = try await makeDomain()
        var received: [ResourceChangeSet] = []
        var titles: [String?] = []
        let token = domain.observe { changes in
            received.append(changes)
            titles.append(domain.snapshot.value(of: w.book1.id, feature: "title") as? String)
        }
        #expect(!token.isCancelled)
        try await domain.perform(domain.setCommand(object: w.book1, feature: w.model.title, value: "A"))
        try await domain.undo()
        #expect(received.map(\.origin) == [.execute, .undo])
        #expect(titles == ["A", "Dune"])
        token.cancel()
        #expect(token.isCancelled)
        try await domain.redo()
        #expect(received.count == 2)
    }

    @Test("legal children follow the remaining capacity")
    func legalChildren() async throws {
        let (domain, w) = try await makeDomain()
        let kinds = domain.legalChildren(of: w.lib).map { "\($0.reference.name):\($0.eClass.name)" }
        #expect(kinds == ["items:Book", "items:Dvd", "members:Member", "manager:Member"])
        try await domain.perform(domain.createChildCommand(
            container: w.lib, descriptor: InstanceChildDescriptor(reference: w.model.manager, eClass: w.model.member)))
        let after = domain.legalChildren(of: w.lib).map { "\($0.reference.name):\($0.eClass.name)" }
        #expect(after == ["items:Book", "items:Dvd", "members:Member"])
        #expect(domain.legalChildren(of: w.dvd).isEmpty)
    }

    @Test("reloading picks up changes made outside the domain")
    func reload() async throws {
        let (domain, w) = try await makeDomain()
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "Outside")
        #expect(domain.snapshot.value(of: w.book1.id, feature: "title") as? String == "Dune")
        await domain.reload()
        #expect(domain.snapshot.value(of: w.book1.id, feature: "title") as? String == "Outside")
        #expect(domain.metamodels.count == 1)
    }

    @Test("a domain for a resource outside any set still edits it")
    func standalone() async throws {
        let resource = Resource(uri: "memory:/standalone")
        let model = LibraryModel()
        let lib = DynamicEObject(eClass: model.library)
        await resource.add(lib)
        let domain = await InstanceEditingDomain(resource: resource)
        try await domain.perform(domain.setCommand(object: lib, feature: model.libraryName, value: "Solo"))
        #expect(domain.snapshot.value(of: lib.id, feature: "name") as? String == "Solo")
        #expect(domain.metamodels.isEmpty)
        #expect(domain.legalChildren(of: lib).map(\.eClass.name) == ["Member", "Member"])
    }

    @Test("legal children fall back to the reference type when no metamodel lists it")
    func legalChildrenFallback() {
        let model = LibraryModel()
        let lib = DynamicEObject(eClass: model.library)
        let children = InstanceChildDescriptor.legalChildren(of: lib, in: [])
        #expect(children.map(\.eClass.name) == ["Member", "Member"])
        let abstractOnly = InstanceChildDescriptor.legalChildren(of: DynamicEObject(eClass: model.member), in: [])
        #expect(abstractOnly.isEmpty)
        #expect(Set(children.map(\.reference.name)) == ["members", "manager"])
    }

    @Test("the domain validates the model")
    func validates() async throws {
        let (domain, w) = try await makeDomain()
        #expect(domain.validate().contains { $0.code == .lowerBound && $0.objectID == w.dvd.id } == false)
        try await domain.perform(domain.setCommand(object: w.book1, feature: w.model.title, value: nil))
        #expect(domain.validate().contains { $0.code == .lowerBound && $0.objectID == w.book1.id })
    }
}
