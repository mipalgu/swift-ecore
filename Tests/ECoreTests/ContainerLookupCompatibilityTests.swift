//
// ContainerLookupCompatibilityTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// The feature names of the node metamodel used by the compatibility tests.
private enum NodeFeature {
    static let name = "name"
    static let children = "children"
    static let part = "part"
}

/// A node metamodel with many- and single-valued containment.
private struct NodeModel {
    let node: EClass

    var children: EReference { node.getEReference(name: NodeFeature.children)! }
    var part: EReference { node.getEReference(name: NodeFeature.part)! }

    init() {
        let nodeID = EUUID()
        let stub = EClass(id: nodeID, name: "Node")
        let name = EAttribute(name: NodeFeature.name, eType: EDataType(name: "EString", instanceClassName: "String"))
        let children = EReference(name: NodeFeature.children, eType: stub, upperBound: -1, containment: true)
        let part = EReference(name: NodeFeature.part, eType: stub, containment: true)
        node = EClass(id: nodeID, name: "Node", eStructuralFeatures: [name, children, part])
    }

    /// Creates a node whose containment references hold the given values as stored.
    func make(_ name: String, children: (any EcoreValue)? = nil, part: (any EcoreValue)? = nil) -> DynamicEObject {
        var object = DynamicEObject(eClass: node)
        object.eSet(NodeFeature.name, value: name)
        if let children { object.eSet(self.children, children) }
        if let part { object.eSet(self.part, part) }
        return object
    }
}

/// Pins the results of the container lookups and root determination released in 0.6.
///
/// The tests use only the API of that release, so that they describe its behaviour exactly.
@Suite("Container lookup compatibility with 0.6")
struct ContainerLookupCompatibilityTests {
    private let model = NodeModel()

    // MARK: - Roots

    @Test("a root has neither a container nor a containing feature")
    func rootHasNoContainer() async {
        let child = model.make("child")
        let root = model.make("root", children: [child.id])
        let resource = Resource(uri: "test://compat-root")
        await resource.add(contentsOf: [root, child])
        #expect(await resource.eContainer(of: root) == nil)
        #expect(await resource.eContainingFeature(of: root) == nil)
        #expect(await resource.eContainer(of: child)?.id == root.id)
        #expect(await resource.eContainingFeature(of: child)?.name == NodeFeature.children)
    }

    // MARK: - Children of other resources

    @Test("a child held by identifier but registered in another resource has no container")
    func crossResourceChildByIdentifier() async {
        let set = ResourceSet()
        let containers = await set.createResource(uri: "test://compat-containers")
        let children = await set.createResource(uri: "test://compat-children")
        let child = model.make("child")
        let single = model.make("single")
        let parent = model.make("parent", children: [child.id], part: single.id)
        await children.add(contentsOf: [child, single])
        await containers.add(parent)
        #expect(await containers.eContainer(of: child) == nil)
        #expect(await containers.eContainingFeature(of: child) == nil)
        #expect(await containers.eContainer(of: single) == nil)
        #expect(await containers.eContainingFeature(of: single) == nil)
        #expect(await children.eContainer(of: child) == nil)
        #expect(await children.eContainingFeature(of: child) == nil)
    }

    @Test("a child removed from the resource of its container has no container")
    func removedChild() async {
        let child = model.make("child")
        let parent = model.make("parent", children: [child.id])
        let resource = Resource(uri: "test://compat-removed")
        await resource.add(contentsOf: [parent, child])
        #expect(await resource.eContainer(of: child)?.id == parent.id)
        #expect(await resource.remove(id: child.id))
        #expect(await resource.eContainer(of: child) == nil)
        #expect(await resource.eContainingFeature(of: child) == nil)
    }

    // MARK: - Embedded objects

    @Test("a child embedded as an object value is found without being registered")
    func embeddedObjects() async {
        let single = model.make("single")
        let listed = model.make("listed")
        let parent = model.make("parent", children: EcoreValueArray([listed]), part: single)
        let resource = Resource(uri: "test://compat-embedded")
        await resource.add(parent)
        #expect(await resource.eContainer(of: single)?.id == parent.id)
        #expect(await resource.eContainingFeature(of: single)?.name == NodeFeature.part)
        #expect(await resource.eContainer(of: listed)?.id == parent.id)
        #expect(await resource.eContainingFeature(of: listed)?.name == NodeFeature.children)
    }

    @Test("an embedded child registered in another resource is still found")
    func embeddedObjectOfAnotherResource() async {
        let set = ResourceSet()
        let containers = await set.createResource(uri: "test://compat-embedding")
        let children = await set.createResource(uri: "test://compat-embedded-children")
        let child = model.make("child")
        let parent = model.make("parent", part: child)
        await children.add(child)
        await containers.add(parent)
        #expect(await containers.eContainer(of: child)?.id == parent.id)
        #expect(await containers.eContainingFeature(of: child)?.name == NodeFeature.part)
    }

    // MARK: - Native metamodel objects

    @Test("native metamodel contents answer from their metamodel structure")
    func nativeMetamodelObjects() async {
        let attribute = EAttribute(name: "label", eType: EDataType(name: "EString"))
        let eClass = EClass(name: "Labelled", eStructuralFeatures: [attribute])
        let package = EPackage(
            name: "labels", nsURI: "http://example.org/labels", nsPrefix: "labels", eClassifiers: [eClass])
        let resource = Resource(uri: "test://compat-native")
        let other = Resource(uri: "test://compat-native-other")
        await resource.add(package)
        #expect(await resource.eContainer(of: eClass)?.id == package.id)
        #expect(await resource.eContainingFeature(of: eClass)?.name == EcoreFeatureName.eClassifiers.rawValue)
        #expect(await resource.eContainer(of: attribute)?.id == eClass.id)
        #expect(
            await resource.eContainingFeature(of: attribute)?.name == EcoreFeatureName.eStructuralFeatures.rawValue)
        #expect(await resource.eContainer(of: package) == nil)
        #expect(await resource.eContainingFeature(of: package) == nil)
        #expect(await other.eContainer(of: eClass) == nil)
        #expect(await other.eContainingFeature(of: eClass) == nil)
    }

    // MARK: - Competing claims

    @Test("the first container in object order wins when several claim a child")
    func firstContainerWins() async {
        let child = model.make("child")
        let first = model.make("first", children: [child.id])
        let second = model.make("second", part: child.id)
        let both = model.make("both", children: [child.id], part: child.id)
        let resource = Resource(uri: "test://compat-claims")
        await resource.add(contentsOf: [second, first, child])
        #expect(await resource.eContainer(of: child)?.id == second.id)
        #expect(await resource.eContainingFeature(of: child)?.name == NodeFeature.part)
        let twice = Resource(uri: "test://compat-twice")
        await twice.add(contentsOf: [both, child])
        #expect(await twice.eContainer(of: child)?.id == both.id)
        #expect(await twice.eContainingFeature(of: child)?.name == NodeFeature.children)
    }

    @Test("an unresolved claim by identifier yields to a later claim by object value")
    func embeddingBeatsUnresolvedIdentifier() async {
        let child = model.make("child")
        let byIdentifier = model.make("byIdentifier", children: [child.id])
        let embedding = model.make("embedding", part: child)
        let resource = Resource(uri: "test://compat-competing")
        await resource.add(contentsOf: [byIdentifier, embedding])
        #expect(await resource.eContainer(of: child)?.id == embedding.id)
        #expect(await resource.eContainingFeature(of: child)?.name == NodeFeature.part)
        await resource.register(child)
        #expect(await resource.eContainer(of: child)?.id == byIdentifier.id)
        #expect(await resource.eContainingFeature(of: child)?.name == NodeFeature.children)
    }

    // MARK: - Value forms

    @Test("children listed in an array value are found when registered")
    func arrayValueOfIdentifiers() async {
        let child = model.make("child")
        let parent = model.make("parent", children: EcoreValueArray([child.id]))
        let resource = Resource(uri: "test://compat-array")
        await resource.add(contentsOf: [parent, child])
        #expect(await resource.eContainer(of: child)?.id == parent.id)
        #expect(await resource.eContainingFeature(of: child)?.name == NodeFeature.children)
    }

    @Test("a child listed in an array value becomes a root when added")
    func arrayValueRoots() async {
        let child = model.make("child")
        let parent = model.make("parent", children: EcoreValueArray([child.id]))
        let single = Resource(uri: "test://compat-array-single")
        await single.add(parent)
        await single.add(child)
        #expect(await single.getRootObjects().map(\.id) == [parent.id, child.id])
        let batch = Resource(uri: "test://compat-array-batch")
        await batch.add(contentsOf: [parent, child])
        #expect(await batch.getRootObjects().map(\.id) == [parent.id, child.id])
    }

    @Test("a lone identifier in a many-valued containment contains only for batch adds")
    func loneIdentifierInManyValuedContainment() async {
        let child = model.make("child")
        let parent = model.make("parent", children: child.id)
        let single = Resource(uri: "test://compat-lone-single")
        await single.add(parent)
        await single.add(child)
        #expect(await single.getRootObjects().map(\.id) == [parent.id, child.id])
        #expect(await single.eContainer(of: child)?.id == parent.id)
        let batch = Resource(uri: "test://compat-lone-batch")
        await batch.add(contentsOf: [parent, child])
        #expect(await batch.getRootObjects().map(\.id) == [parent.id])
    }

    @Test("an identifier list in a single-valued containment contains only for batch adds")
    func identifierListInSingleValuedContainment() async {
        let child = model.make("child")
        let parent = model.make("parent", part: [child.id])
        let single = Resource(uri: "test://compat-list-single")
        await single.add(parent)
        await single.add(child)
        #expect(await single.getRootObjects().map(\.id) == [parent.id, child.id])
        #expect(await single.eContainer(of: child)?.id == parent.id)
        let batch = Resource(uri: "test://compat-list-batch")
        await batch.add(contentsOf: [parent, child])
        #expect(await batch.getRootObjects().map(\.id) == [parent.id])
    }

    @Test("deleting a child listed in an array value detaches it from its container")
    func deleteFromArrayValue() async {
        let first = model.make("first")
        let second = model.make("second")
        let parent = model.make("parent", children: EcoreValueArray([first.id, second.id]))
        let resource = Resource(uri: "test://compat-delete")
        await resource.add(contentsOf: [parent, first, second])
        let changes = await resource.delete([first.id])
        #expect(changes.contains { $0.objectID == parent.id && $0.feature == NodeFeature.children })
        #expect(await resource.resolve(first.id) == nil)
        let remaining = await resource.eGet(objectId: parent.id, feature: NodeFeature.children)
        #expect(remaining as? EcoreValueArray == EcoreValueArray([second.id]))
        #expect(await resource.getRootObjects().map(\.id) == [parent.id, second.id])
    }

    @Test("an embedded object never stops an object from becoming a root")
    func embeddedObjectRoots() async {
        let child = model.make("child")
        let parent = model.make("parent", part: child)
        let single = Resource(uri: "test://compat-embedded-single")
        await single.add(parent)
        await single.add(child)
        #expect(await single.getRootObjects().map(\.id) == [parent.id, child.id])
        let batch = Resource(uri: "test://compat-embedded-batch")
        await batch.add(contentsOf: [parent, child])
        #expect(await batch.getRootObjects().map(\.id) == [parent.id, child.id])
    }
}
