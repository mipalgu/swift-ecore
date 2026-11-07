//
// RootBookkeepingTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// A metamodel of folders that contain items, singly and in lists.
private struct FolderModel {
    let folder: EClass
    let item: EClass

    init() {
        let string = EDataType(name: "EString", instanceClassName: "String")
        let item = EClass(name: "Item", eStructuralFeatures: [EAttribute(name: "name", eType: string)])
        folder = EClass(
            name: "Folder",
            eStructuralFeatures: [
                EReference(name: "items", eType: item, upperBound: -1, containment: true),
                EReference(name: "cover", eType: item, containment: true),
                EReference(name: "links", eType: item, upperBound: -1),
            ])
        self.item = item
    }

    func makeItem(_ name: String) -> DynamicEObject {
        var object = DynamicEObject(eClass: item)
        object.eSet("name", value: name)
        return object
    }
}

/// Checks the root objects of a resource as objects are added, contained and removed.
///
/// Building a model one object at a time and then containing the objects must take time
/// in proportion to the number of objects, so the tests count how often the root objects
/// are searched one by one rather than measuring time.
@Suite("Root Bookkeeping Tests")
struct RootBookkeepingTests {
    private let model = FolderModel()

    @Test("adding objects one by one does not search the roots for each object")
    func addingDoesNotScan() async {
        let resource = Resource(uri: "test://roots")
        let start = await resource.rootListScans
        for index in 0..<200 { await resource.add(model.makeItem("i\(index)")) }
        #expect(await resource.rootListScans - start <= 1)
        #expect(await resource.getRootObjects().count == 200)
    }

    @Test("containing many roots searches the roots at most once")
    func containingDoesNotScanPerObject() async {
        let resource = Resource(uri: "test://roots")
        let folder = DynamicEObject(eClass: model.folder)
        await resource.add(folder)
        let items = (0..<200).map { model.makeItem("i\($0)") }
        for item in items { await resource.add(item) }
        let start = await resource.rootListScans
        _ = await resource.eSet(objectId: folder.id, feature: "items", value: items.map(\.id))
        #expect(await resource.rootListScans - start <= 1)
        #expect(await resource.getRootObjects().map(\.id) == [folder.id])
    }

    @Test("containing objects keeps the order of the remaining roots")
    func containingKeepsOrder() async {
        let resource = Resource(uri: "test://roots")
        let items = (0..<6).map { model.makeItem("i\($0)") }
        let folder = DynamicEObject(eClass: model.folder)
        for item in items { await resource.add(item) }
        await resource.add(folder)
        _ = await resource.eSet(objectId: folder.id, feature: "items", value: [items[4].id, items[1].id])
        _ = await resource.eSet(objectId: folder.id, feature: "cover", value: items[2].id)
        let expected = [items[0].id, items[3].id, items[5].id, folder.id]
        #expect(await resource.getRootObjects().map(\.id) == expected)
    }

    @Test("a plain reference does not take objects out of the roots")
    func plainReferenceKeepsRoots() async {
        let resource = Resource(uri: "test://roots")
        let folder = DynamicEObject(eClass: model.folder)
        let item = model.makeItem("linked")
        await resource.add(folder)
        await resource.add(item)
        _ = await resource.eSet(objectId: folder.id, feature: "links", value: [item.id])
        #expect(await resource.getRootObjects().map(\.id) == [folder.id, item.id])
    }

    @Test("adding an object again neither duplicates nor moves its root entry")
    func addingAgainKeepsOneEntry() async {
        let resource = Resource(uri: "test://roots")
        let first = model.makeItem("first")
        var second = model.makeItem("second")
        await resource.add(first)
        await resource.add(second)
        second.eSet("name", value: "renamed")
        #expect(await resource.add(second) == false)
        await resource.add(contentsOf: [first, second])
        #expect(await resource.getRootObjects().map(\.id) == [first.id, second.id])
    }

    @Test("removing and deleting objects takes them out of the roots")
    func removingUpdatesRoots() async {
        let resource = Resource(uri: "test://roots")
        let items = (0..<5).map { model.makeItem("i\($0)") }
        for item in items { await resource.add(item) }
        await resource.remove(id: items[1].id)
        await resource.delete([items[3].id, items[0].id])
        #expect(await resource.getRootObjects().map(\.id) == [items[2].id, items[4].id])
        await resource.add(items[1])
        #expect(await resource.getRootObjects().map(\.id) == [items[2].id, items[4].id, items[1].id])
    }

    @Test("snapshots restore the roots in their order")
    func snapshotsRestoreRoots() async {
        let resource = Resource(uri: "test://roots")
        let items = (0..<4).map { model.makeItem("i\($0)") }
        for item in items { await resource.add(item) }
        let snapshot = await resource.snapshot()
        #expect(snapshot.rootIDs == items.map(\.id))
        await resource.remove(id: items[0].id)
        await resource.restore(snapshot)
        #expect(await resource.getRootObjects().map(\.id) == items.map(\.id))
    }
}
