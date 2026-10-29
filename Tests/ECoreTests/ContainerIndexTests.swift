//
// ContainerIndexTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// A tree metamodel with many- and single-valued containment and a plain reference.
private struct TreeModel {
    let node: EClass
    let childrenID = EUUID()
    let parentID = EUUID()

    var children: EReference { node.getEReference(name: "children")! }
    var part: EReference { node.getEReference(name: "part")! }

    init() {
        let nodeID = EUUID()
        let stub = EClass(id: nodeID, name: "Node")
        let name = EAttribute(name: "name", eType: EDataType(name: "EString", instanceClassName: "String"))
        let children = EReference(
            id: childrenID, name: "children", eType: stub, upperBound: -1, containment: true, opposite: parentID)
        let parent = EReference(id: parentID, name: "parent", eType: stub, opposite: childrenID)
        let part = EReference(name: "part", eType: stub, containment: true)
        let links = EReference(name: "links", eType: stub, upperBound: -1)
        node = EClass(id: nodeID, name: "Node", eStructuralFeatures: [name, children, parent, part, links])
    }

    /// Creates a node holding the given children.
    func make(_ name: String, children ids: [EUUID] = [], part: EUUID? = nil) -> DynamicEObject {
        var object = DynamicEObject(eClass: node)
        object.eSet("name", value: name)
        if !ids.isEmpty { object.eSet(children, ids) }
        if let part { object.eSet(self.part, part) }
        return object
    }
}

/// A deterministic generator, so that a failing randomised run can be repeated.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The identifiers that a containment value holds, in order, by identifier or as embedded objects.
private func heldIdentifiers(_ value: (any EcoreValue)?) -> [EUUID] {
    switch value {
    case let id as EUUID: return [id]
    case let ids as [EUUID]: return ids
    case let array as EcoreValueArray: return array.values.flatMap { heldIdentifiers($0) }
    case let object as any EObject: return [object.id]
    case let values as [Any]: return values.compactMap { $0 as? EUUID }
    default: return []
    }
}

/// Finds the container of an identifier by scanning every object, the reference behaviour.
private func bruteForceContainer(of id: EUUID, in objects: [any EObject]) -> (container: EUUID, feature: String)? {
    for candidate in objects {
        guard let eClass = candidate.eClass as? EClass else { continue }
        for reference in eClass.eAllReferences where reference.containment {
            if heldIdentifiers(candidate.eGet(reference)).contains(id) { return (candidate.id, reference.name) }
        }
    }
    return nil
}

/// Checks that every container lookup of a resource agrees with a full scan.
private func expectAgreement(
    _ resource: Resource, extra: [EUUID] = [], sourceLocation: SourceLocation = #_sourceLocation
) async {
    let objects = await resource.getAllObjects()
    for id in objects.map(\.id) + extra {
        let expected = bruteForceContainer(of: id, in: objects)
        let actual = await resource.container(ofIdentifier: id)
        #expect(actual?.container.id == expected?.container, sourceLocation: sourceLocation)
        #expect(actual?.feature.name == expected?.feature, sourceLocation: sourceLocation)
    }
    for object in objects {
        let expected = bruteForceContainer(of: object.id, in: objects)
        #expect(await resource.eContainer(of: object)?.id == expected?.container, sourceLocation: sourceLocation)
        #expect(await resource.eContainingFeature(of: object)?.name == expected?.feature, sourceLocation: sourceLocation)
    }
}

@Suite("Container index")
struct ContainerIndexTests {
    private let model = TreeModel()

    // MARK: - Adding and registering

    @Test("a container added after its child is found, and the child stays a root")
    func childAddedFirst() async {
        let child = model.make("child")
        let parent = model.make("parent", children: [child.id])
        let resource = Resource(uri: "test://child-first")
        await resource.add(child)
        #expect(await resource.eContainer(of: child) == nil)
        await resource.add(parent)
        #expect(await resource.eContainer(of: child)?.id == parent.id)
        #expect(await resource.eContainingFeature(of: child)?.name == "children")
        #expect(await resource.getRootObjects().map(\.id) == [child.id, parent.id])
        await expectAgreement(resource)
    }

    @Test("a child added after its container does not become a root")
    func containerAddedFirst() async {
        let child = model.make("child")
        let parent = model.make("parent", part: child.id)
        let resource = Resource(uri: "test://container-first")
        await resource.add(parent)
        await resource.add(child)
        #expect(await resource.eContainer(of: child)?.id == parent.id)
        #expect(await resource.eContainingFeature(of: child)?.name == "part")
        #expect(await resource.getRootObjects().map(\.id) == [parent.id])
        await expectAgreement(resource)
    }

    @Test("registered children are found and only uncontained objects become roots")
    func registerThenAdd() async {
        let leaf = model.make("leaf")
        let middle = model.make("middle", children: [leaf.id])
        let top = model.make("top", children: [middle.id])
        let resource = Resource(uri: "test://register")
        await resource.register(leaf)
        await resource.register(middle)
        #expect(await resource.eContainer(of: leaf)?.id == middle.id)
        await resource.add(top)
        await resource.add(middle)
        #expect(await resource.eContainer(of: middle)?.id == top.id)
        #expect(await resource.getRootObjects().map(\.id) == [top.id])
        await expectAgreement(resource)
    }

    @Test("adding several objects at once makes only the uncontained ones roots")
    func addContentsOf() async {
        let a = model.make("a")
        let b = model.make("b")
        let parent = model.make("parent", children: [b.id, a.id])
        let loose = model.make("loose")
        let resource = Resource(uri: "test://batch")
        _ = await resource.eContainer(of: a)
        #expect(await resource.add(contentsOf: [a, parent, b, loose]) == 4)
        #expect(await resource.getRootObjects().map(\.id) == [parent.id, loose.id])
        #expect(await resource.eContainer(of: a)?.id == parent.id)
        await expectAgreement(resource)
    }

    @Test("replacing a stored object updates the containment it claims")
    func replaceStoredObject() async {
        let child = model.make("child")
        let parent = model.make("parent", children: [child.id])
        let resource = Resource(uri: "test://replace")
        await resource.add(contentsOf: [parent, child])
        #expect(await resource.eContainer(of: child)?.id == parent.id)
        var emptied = parent
        emptied.eSet(model.children, [EUUID]())
        await resource.add(emptied)
        #expect(await resource.eContainer(of: child) == nil)
        await resource.register(parent)
        #expect(await resource.eContainer(of: child)?.id == parent.id)
        await expectAgreement(resource)
    }

    // MARK: - Removing

    @Test("removing a container leaves its children uncontained")
    func removeContainer() async {
        let child = model.make("child")
        let parent = model.make("parent", children: [child.id])
        let resource = Resource(uri: "test://remove-container")
        await resource.add(contentsOf: [parent, child])
        #expect(await resource.eContainer(of: child)?.id == parent.id)
        #expect(await resource.remove(parent))
        #expect(await resource.eContainer(of: child) == nil)
        #expect(await resource.container(ofIdentifier: child.id) == nil)
        await expectAgreement(resource)
    }

    @Test("removing a child keeps its identifier answerable while its container holds it")
    func removeChild() async {
        let child = model.make("child")
        let parent = model.make("parent", children: [child.id])
        let resource = Resource(uri: "test://remove-child")
        await resource.add(contentsOf: [parent, child])
        #expect(await resource.remove(id: child.id))
        #expect(await resource.container(ofIdentifier: child.id)?.container.id == parent.id)
        #expect(await resource.eContainer(of: child)?.id == parent.id)
        await expectAgreement(resource, extra: [child.id])
    }

    @Test("clearing a resource forgets all containment")
    func clearResource() async {
        let child = model.make("child")
        let parent = model.make("parent", children: [child.id])
        let resource = Resource(uri: "test://clear")
        await resource.add(contentsOf: [parent, child])
        #expect(await resource.eContainer(of: child)?.id == parent.id)
        await resource.clear()
        #expect(await resource.eContainer(of: child) == nil)
        #expect(await resource.container(ofIdentifier: child.id) == nil)
        await resource.add(contentsOf: [child, parent])
        #expect(await resource.eContainer(of: child)?.id == parent.id)
    }

    // MARK: - Setting features

    @Test("setting a containment reference moves a child between containers")
    func eSetMovesChild() async {
        let child = model.make("child")
        let first = model.make("first", children: [child.id])
        let second = model.make("second")
        let resource = Resource(uri: "test://move")
        await resource.add(contentsOf: [first, second, child])
        #expect(await resource.eContainer(of: child)?.id == first.id)
        #expect(await resource.eSet(objectId: first.id, feature: "children", value: [EUUID]()))
        #expect(await resource.eContainer(of: child) == nil)
        #expect(await resource.eSet(objectId: second.id, feature: "children", value: [child.id]))
        #expect(await resource.eContainer(of: child)?.id == second.id)
        #expect(await resource.eGet(objectId: child.id, feature: "parent") as? EUUID == second.id)
        await expectAgreement(resource)
    }

    @Test("clearing a single-valued containment releases the child")
    func eSetClearsPart() async {
        let child = model.make("child")
        let parent = model.make("parent", part: child.id)
        let resource = Resource(uri: "test://part")
        await resource.add(contentsOf: [parent, child])
        #expect(await resource.eContainer(of: child)?.id == parent.id)
        #expect(await resource.eSet(objectId: parent.id, feature: "part", value: nil))
        #expect(await resource.eContainer(of: child) == nil)
        #expect(await resource.eContainingFeature(of: child) == nil)
        await expectAgreement(resource)
    }

    @Test("setting a non-containment reference does not contain its target")
    func eSetPlainReference() async {
        let target = model.make("target")
        let source = model.make("source")
        let resource = Resource(uri: "test://links")
        await resource.add(contentsOf: [source, target])
        #expect(await resource.eSet(objectId: source.id, feature: "links", value: [target.id]))
        #expect(await resource.eContainer(of: target) == nil)
        await expectAgreement(resource)
    }

    // MARK: - Competing claims

    @Test("the first container in object order wins when several claim a child")
    func firstClaimWins() async {
        let child = model.make("child")
        let first = model.make("first", children: [child.id])
        let second = model.make("second", part: child.id)
        let resource = Resource(uri: "test://claims")
        await resource.add(contentsOf: [first, second, child])
        #expect(await resource.eContainer(of: child)?.id == first.id)
        #expect(await resource.eSet(objectId: second.id, feature: "name", value: "renamed"))
        #expect(await resource.eContainer(of: child)?.id == first.id)
        #expect(await resource.remove(first))
        #expect(await resource.eContainer(of: child)?.id == second.id)
        await resource.add(first)
        #expect(await resource.eContainer(of: child)?.id == second.id)
        #expect(await resource.eContainingFeature(of: child)?.name == "part")
        await expectAgreement(resource)
    }

    @Test("a container holding a child twice reports its first containment reference")
    func sameContainerTwice() async {
        let child = model.make("child")
        let parent = model.make("parent", children: [child.id], part: child.id)
        let resource = Resource(uri: "test://twice")
        await resource.add(contentsOf: [parent, child])
        #expect(await resource.eContainingFeature(of: child)?.name == "children")
        #expect(await resource.eSet(objectId: parent.id, feature: "children", value: [EUUID]()))
        #expect(await resource.eContainingFeature(of: child)?.name == "part")
        await expectAgreement(resource)
    }

    // MARK: - Editing operations

    @Test("editing operations keep containment current")
    func editingOperations() async throws {
        let a = model.make("a")
        let b = model.make("b")
        let first = model.make("first", children: [a.id, b.id])
        let second = model.make("second")
        let resource = Resource(uri: "test://editing")
        await resource.add(contentsOf: [first, second, a, b])
        try await resource.eAdd(objectId: second.id, feature: "children", value: a.id)
        #expect(await resource.eContainer(of: a)?.id == second.id)
        await expectAgreement(resource)
        try await resource.eRemove(objectId: first.id, feature: "children", value: b.id)
        #expect(await resource.eContainer(of: b) == nil)
        #expect(await resource.getRootObjects().map(\.id).contains(b.id))
        try await resource.eSetWithChanges(objectId: first.id, feature: "part", value: b.id)
        #expect(await resource.eContainer(of: b)?.id == first.id)
        #expect(await resource.getRootObjects().map(\.id).contains(b.id) == false)
        let extra = model.make("extra")
        try await resource.eAdd(objectId: second.id, feature: "children", value: extra, at: 0)
        #expect(await resource.eContainer(of: extra)?.id == second.id)
        try await resource.eMove(objectId: second.id, feature: "children", from: 0, to: 1)
        #expect(await resource.eContainer(of: extra)?.id == second.id)
        await expectAgreement(resource)
        await resource.delete([second.id])
        #expect(await resource.container(ofIdentifier: a.id) == nil)
        #expect(await resource.container(ofIdentifier: extra.id) == nil)
        await expectAgreement(resource, extra: [a.id, extra.id])
    }

    @Test("restoring a snapshot restores containment")
    func snapshotRestore() async throws {
        let child = model.make("child")
        let first = model.make("first", children: [child.id])
        let second = model.make("second")
        let resource = Resource(uri: "test://snapshot")
        await resource.add(contentsOf: [first, second, child])
        let unindexed = await resource.snapshot()
        #expect(await resource.eContainer(of: child)?.id == first.id)
        let indexed = await resource.snapshot()
        try await resource.eAdd(objectId: second.id, feature: "children", value: child.id)
        #expect(await resource.eContainer(of: child)?.id == second.id)
        await resource.restore(indexed)
        #expect(await resource.eContainer(of: child)?.id == first.id)
        try await resource.eAdd(objectId: second.id, feature: "children", value: child.id)
        await resource.restore(unindexed)
        #expect(await resource.eContainer(of: child)?.id == first.id)
        await expectAgreement(resource)
    }

    @Test("undoing a recorded command restores containment")
    @MainActor
    func undoCommand() async throws {
        let child = model.make("child")
        let first = model.make("first", children: [child.id])
        let second = model.make("second")
        let resource = Resource(uri: "test://undo")
        await resource.add(contentsOf: [first, second, child])
        let domain = await InstanceEditingDomain(resource: resource)
        _ = try await domain.perform(domain.addCommand(object: second, feature: model.children, value: child.id))
        #expect(await resource.eContainer(of: child)?.id == second.id)
        try await domain.undo()
        #expect(await resource.eContainer(of: child)?.id == first.id)
        try await domain.redo()
        #expect(await resource.eContainer(of: child)?.id == second.id)
        await expectAgreement(resource)
    }

    @Test("rebinding objects to new classes keeps containment current")
    func rebind() async {
        let child = model.make("child")
        let parent = model.make("parent", children: [child.id])
        let resource = Resource(uri: "test://rebind")
        await resource.add(contentsOf: [parent, child])
        #expect(await resource.eContainer(of: child)?.id == parent.id)
        let plain = EClass(id: model.node.id, name: "Node", eStructuralFeatures: [
            EReference(name: "children", eType: EClass(name: "Node"), upperBound: -1)
        ])
        let package = EPackage(name: "plain", nsURI: "http://example.org/plain", nsPrefix: "plain", eClassifiers: [plain])
        await resource.rebind(to: [package])
        #expect(await resource.eContainer(of: child) == nil)
        await expectAgreement(resource)
    }

    // MARK: - Loading

    @Test("containment of a loaded XMI document agrees with a full scan")
    func xmiLoad() async throws {
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <tree:Node xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
            xmlns:tree="http://example.org/tree" name="root">
              <children name="a">
                <children name="a1"/>
                <children name="a2"/>
              </children>
              <children name="b"/>
            </tree:Node>
            """
        let resource = try await XMIParser().parse(text, uri: "memory:/tree.xmi")
        let objects = await resource.getAllObjects()
        func named(_ name: String) -> (any EObject)? {
            objects.first { ($0 as? DynamicEObject)?.eGet("name") as? String == name }
        }
        let root = try #require(named("root"))
        let a = try #require(named("a"))
        let a2 = try #require(named("a2"))
        #expect(await resource.eContainer(of: root) == nil)
        #expect(await resource.eContainer(of: a)?.id == root.id)
        #expect(await resource.eContainer(of: a2)?.id == a.id)
        #expect(await resource.getRootObjects().map(\.id) == [root.id])
        await expectAgreement(resource)
    }

    @Test("containment of a loaded JSON document agrees with a full scan")
    func jsonLoad() async throws {
        let text = """
            {"eClass": "http://example.org/family#//Person", "name": "Alice",
             "children": [{"eClass": "http://example.org/family#//Person", "name": "Bob"},
                          {"eClass": "http://example.org/family#//Person", "name": "Carol"}]}
            """
        let resource = try await JSONParser().parse(Data(text.utf8), uri: "memory:/family.json")
        let objects = await resource.getAllObjects()
        let root = try #require(await resource.getRootObjects().first)
        let others = objects.filter { $0.id != root.id }
        #expect(others.count == 2)
        for child in others { #expect(await resource.eContainer(of: child)?.id == root.id) }
        await expectAgreement(resource)
    }

    // MARK: - Across resources

    @Test("a container answers for children held by another resource")
    func crossResourceLookup() async {
        let set = ResourceSet()
        let containers = await set.createResource(uri: "test://containers")
        let children = await set.createResource(uri: "test://children")
        let child = model.make("child")
        let parent = model.make("parent")
        await children.add(child)
        await containers.add(parent)
        #expect(await containers.eSet(objectId: parent.id, feature: "children", value: [child.id]))
        #expect(await children.eGet(objectId: child.id, feature: "parent") as? EUUID == parent.id)
        #expect(await containers.container(ofIdentifier: child.id)?.container.id == parent.id)
        #expect(await containers.container(ofIdentifier: child.id)?.feature.name == "children")
        #expect(await containers.eContainer(of: child)?.id == parent.id)
        #expect(await children.container(ofIdentifier: child.id) == nil)
        let found = await set.container(ofIdentifier: child.id)
        #expect(found?.container.id == parent.id)
        #expect(found?.feature.name == "children")
        #expect(found?.resource === containers)
        #expect(await containers.eSet(objectId: parent.id, feature: "children", value: [EUUID]()))
        #expect(await set.container(ofIdentifier: child.id) == nil)
        #expect(await children.eGet(objectId: child.id, feature: "parent") == nil)
    }

    @Test("native metamodel contents answer by identifier")
    func nativeLookup() async throws {
        let attribute = EAttribute(name: "label", eType: EDataType(name: "EString"))
        let eClass = EClass(name: "Labelled", eStructuralFeatures: [attribute])
        let package = EPackage(name: "labels", nsURI: "http://example.org/labels", nsPrefix: "labels", eClassifiers: [eClass])
        let resource = Resource(uri: "test://native")
        await resource.add(package)
        let classSlot = try #require(await resource.container(ofIdentifier: eClass.id))
        #expect(classSlot.container.id == package.id)
        #expect(classSlot.feature.name == EcoreFeatureName.eClassifiers.rawValue)
        let attributeSlot = try #require(await resource.container(ofIdentifier: attribute.id))
        #expect(attributeSlot.container.id == eClass.id)
        #expect(attributeSlot.feature.name == EcoreFeatureName.eStructuralFeatures.rawValue)
        #expect(await resource.container(ofIdentifier: package.id) == nil)
    }

    // MARK: - Agreement on random edits

    @Test("container lookups agree with a full scan after random edits", arguments: [1, 7, 42, 2026] as [UInt64])
    func randomisedAgreement(seed: UInt64) async throws {
        var generator = SplitMix64(state: seed)
        let resource = Resource(uri: "test://random-\(seed)")
        var pool: [EUUID] = []
        var saved: ResourceSnapshot?
        for step in 0..<150 {
            let known = pool
            func someIDs(_ limit: Int) -> [EUUID] {
                guard !known.isEmpty else { return [] }
                return (0..<Int.random(in: 0...limit, using: &generator)).map { _ in
                    known.randomElement(using: &generator)!
                }
            }
            switch Int.random(in: 0..<11, using: &generator) {
            case 0, 1:
                let object = model.make("n\(step)", children: Array(Set(someIDs(3))))
                pool.append(object.id)
                await resource.add(object)
            case 2:
                let object = model.make("r\(step)", part: someIDs(1).first)
                pool.append(object.id)
                await resource.register(object)
            case 3:
                guard let id = someIDs(1).first else { continue }
                _ = await resource.eSet(objectId: id, feature: "children", value: Array(Set(someIDs(3))))
            case 4:
                guard let id = someIDs(1).first else { continue }
                _ = await resource.eSet(objectId: id, feature: "part", value: someIDs(1).first)
            case 5:
                guard let id = someIDs(1).first else { continue }
                _ = await resource.remove(id: id)
            case 6:
                guard let id = someIDs(1).first, let child = someIDs(1).first else { continue }
                _ = try? await resource.eAdd(objectId: id, feature: "children", value: child)
            case 7:
                guard let id = someIDs(1).first, let child = someIDs(1).first else { continue }
                _ = try? await resource.eSetWithChanges(objectId: id, feature: "part", value: child)
            case 8:
                await resource.delete(someIDs(1))
            case 9:
                if let snapshot = saved, Bool.random(using: &generator) {
                    await resource.restore(snapshot)
                } else {
                    saved = await resource.snapshot()
                }
            default:
                guard let id = someIDs(1).first else { continue }
                _ = await resource.eSet(objectId: id, feature: "name", value: "s\(step)")
            }
            if step.isMultiple(of: 3) {
                await expectAgreement(resource, extra: pool)
            }
        }
        await expectAgreement(resource, extra: pool)
    }

    // MARK: - Cost

    @Test("repeated lookups build the container index at most once")
    func lookupsBuildOnce() async {
        let resource = Resource(uri: "test://cost")
        var nodes: [DynamicEObject] = (0..<300).map { model.make("n\($0)") }
        for index in nodes.indices {
            let kids = (1...3).map { index * 3 + $0 }.filter { $0 < nodes.count }.map { nodes[$0].id }
            if !kids.isEmpty { nodes[index].eSet(model.children, kids) }
        }
        await resource.add(contentsOf: nodes)
        let start = await resource.containerIndexBuilds
        for node in nodes { _ = await resource.eContainer(of: node) }
        for node in nodes { _ = await resource.eContainingFeature(of: node) }
        for node in nodes { _ = await resource.container(ofIdentifier: node.id) }
        #expect(await resource.containerIndexBuilds - start <= 1)
        let afterLookups = await resource.containerIndexBuilds
        _ = await resource.eSet(objectId: nodes[0].id, feature: "children", value: [nodes[299].id])
        for node in nodes { _ = await resource.eContainer(of: node) }
        #expect(await resource.containerIndexBuilds - afterLookups <= 1)
    }

    @Test("interleaving edits and lookups does not rebuild the container index on every edit")
    func interleavedEditsStayIncremental() async throws {
        let resource = Resource(uri: "test://interleaved")
        let root = model.make("root")
        await resource.add(root)
        _ = await resource.eContainer(of: root)
        let start = await resource.containerIndexBuilds
        var children: [EUUID] = []
        for index in 0..<100 {
            let child = model.make("c\(index)")
            await resource.add(child)
            children.append(child.id)
            _ = await resource.eSet(objectId: root.id, feature: "children", value: children)
            try await resource.eSetWithChanges(objectId: child.id, feature: "name", value: "d\(index)")
            #expect(await resource.eContainer(of: child)?.id == root.id)
        }
        #expect(await resource.containerIndexBuilds - start <= 1)
    }
}
