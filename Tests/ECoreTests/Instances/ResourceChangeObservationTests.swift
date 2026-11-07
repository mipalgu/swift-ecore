//
// ResourceChangeObservationTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Synchronization
import Testing

@testable import ECore

/// Collects the change batches delivered to an observer.
private final class DeliveryLog: Sendable {
    private let batches = Mutex<[[ResourceChange]]>([])

    func append(_ changes: [ResourceChange]) { batches.withLock { $0.append(changes) } }

    var all: [[ResourceChange]] { batches.withLock { $0 } }

    var flattened: [ResourceChange] { all.flatMap { $0 } }
}

@Suite("Resource change observation")
struct ResourceChangeObservationTests {

    @Test("an observer receives the changes of an edit, in order, as the edit reports them")
    func receivesSetChanges() async throws {
        let w = try await LibraryWorld()
        let log = DeliveryLog()
        await w.resource.addChangeObserver { log.append($0) }
        let changes = try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "Changed")
        #expect(log.all == [changes])
        #expect(changes.first?.kind == .set)
        #expect(await w.resource.changeObserverCount == 1)
    }

    @Test("adding a new object reports its creation and its insertion")
    func receivesCreation() async throws {
        let w = try await LibraryWorld()
        let log = DeliveryLog()
        await w.resource.addChangeObserver { log.append($0) }
        let extra = DynamicEObject(eClass: w.model.book)
        let changes = try await w.resource.eAdd(objectId: w.lib.id, feature: "items", value: extra)
        #expect(log.flattened == changes)
        #expect(log.flattened.map(\.kind) == [.create, .add, .set])
    }

    @Test("deleting, removing, moving, creating and rebinding are all delivered")
    func receivesEveryKind() async throws {
        let w = try await LibraryWorld()
        let log = DeliveryLog()
        await w.resource.addChangeObserver { log.append($0) }
        try await w.resource.eMove(objectId: w.lib.id, feature: "items", from: 0, to: 1)
        _ = try await w.resource.removeValue(objectId: w.lib.id, feature: "items", value: w.dvd.id)
        await w.resource.delete([w.book2.id])
        let loose = DynamicEObject(eClass: w.model.member)
        await w.resource.eCreate(loose)
        await w.resource.rebind(to: [w.model.package], from: [w.model.package])
        let kinds = Set(log.flattened.map(\.kind))
        #expect(kinds.isSuperset(of: [.move, .remove, .delete, .create, .rebind]))
        #expect(log.all.count == 5)
        #expect(log.flattened.filter { $0.kind == .create }.map(\.objectID) == [loose.id])
    }

    @Test("an edit that changes nothing delivers nothing")
    func silentWithoutChange() async throws {
        let w = try await LibraryWorld()
        let log = DeliveryLog()
        await w.resource.addChangeObserver { log.append($0) }
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "Dune")
        #expect(log.all.isEmpty)
    }

    @Test("operations that do not report changes do not call observers")
    func legacyOperationsAreSilent() async throws {
        let w = try await LibraryWorld()
        let log = DeliveryLog()
        await w.resource.addChangeObserver { log.append($0) }
        await w.resource.eSet(objectId: w.book1.id, feature: "title", value: "Quiet")
        await w.resource.add(DynamicEObject(eClass: w.model.member))
        #expect(log.all.isEmpty)
    }

    @Test("every registered observer receives each batch, and removal ends delivery")
    func removalEndsDelivery() async throws {
        let w = try await LibraryWorld()
        let first = DeliveryLog()
        let second = DeliveryLog()
        let observation = await w.resource.addChangeObserver { first.append($0) }
        await w.resource.addChangeObserver { second.append($0) }
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "One")
        #expect(await w.resource.removeChangeObserver(observation))
        #expect(await w.resource.removeChangeObserver(observation) == false)
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "Two")
        #expect(first.all.count == 1)
        #expect(second.all.count == 2)
        #expect(await w.resource.changeObserverCount == 1)
    }

    @Test("a change queue collects changes until drained")
    func queueCollectsChanges() async throws {
        let w = try await LibraryWorld()
        let queue = ResourceChangeQueue()
        #expect(queue.isEmpty)
        let observation = await queue.observe(w.resource)
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: "A")
        try await w.resource.eSetWithChanges(objectId: w.book2.id, feature: "title", value: "B")
        #expect(queue.count == 2)
        #expect(queue.isEmpty == false)
        let drained = queue.drain()
        #expect(drained.map(\.objectID) == [w.book1.id, w.book2.id])
        #expect(queue.isEmpty)
        #expect(queue.drain().isEmpty)
        await w.resource.removeChangeObserver(observation)
        queue.enqueue([ResourceChange(kind: .create, objectID: w.lib.id)])
        #expect(queue.count == 1)
        #expect(ResourceChangeObservation(identifier: observation.identifier) == observation)
    }

    @Test("root objects can be rearranged")
    func reorderRoots() async throws {
        let w = try await LibraryWorld()
        let roots = await w.resource.rootIdentifiers()
        #expect(roots == [w.lib.id, w.other.id])
        #expect(await w.resource.reorderRoots([w.other.id, EUUID(), w.book1.id]))
        #expect(await w.resource.rootIdentifiers() == [w.other.id, w.lib.id])
        #expect(await w.resource.reorderRoots([w.other.id]) == false)
        #expect(await w.resource.getRootObjects().map(\.id) == [w.other.id, w.lib.id])
    }
}
