//
// ContainerLookupScopeTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// The feature names of the node metamodel used by the scope tests.
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

/// The container and containing feature that a resource reports for an object in each scope.
private struct Lookup: Equatable {
    let container: EUUID?
    let feature: String?
}

/// Looks up the container and containing feature of an object in a scope.
private func lookup(_ object: any EObject, in resource: Resource, scope: ContainerLookupScope) async -> Lookup {
    Lookup(
        container: await resource.eContainer(of: object, scope: scope)?.id,
        feature: await resource.eContainingFeature(of: object, scope: scope)?.name)
}

/// Checks that the unscoped lookups answer as the legacy scope does.
private func expectLegacyAgreement(
    _ object: any EObject, in resource: Resource, sourceLocation: SourceLocation = #_sourceLocation
) async {
    let legacy = await lookup(object, in: resource, scope: .legacy)
    #expect(await resource.eContainer(of: object)?.id == legacy.container, sourceLocation: sourceLocation)
    #expect(await resource.eContainingFeature(of: object)?.name == legacy.feature, sourceLocation: sourceLocation)
}

@Suite("Container lookup scope")
struct ContainerLookupScopeTests {
    private let model = NodeModel()

    // MARK: - Presets

    @Test("the standard scope answers for any resource and the legacy scope for this resource only")
    func presets() {
        #expect(ContainerLookupScope() == .anyResource)
        #expect(ContainerLookupScope.standard == .anyResource)
        #expect(ContainerLookupScope.legacy == .thisResource)
        #expect(ContainerLookupScope.allCases == [.anyResource, .thisResource])
    }

    // MARK: - Roots

    @Test("a root has no container in either scope")
    func roots() async {
        let child = model.make("child")
        let root = model.make("root", children: [child.id])
        let resource = Resource(uri: "test://scope-root")
        await resource.add(contentsOf: [root, child])
        for scope in ContainerLookupScope.allCases {
            #expect(await lookup(root, in: resource, scope: scope) == Lookup(container: nil, feature: nil))
            #expect(
                await lookup(child, in: resource, scope: scope)
                    == Lookup(container: root.id, feature: NodeFeature.children))
        }
        await expectLegacyAgreement(root, in: resource)
        await expectLegacyAgreement(child, in: resource)
    }

    // MARK: - Children of other resources

    @Test("a child of another resource is found only in the any-resource scope")
    func crossResourceChild() async {
        let set = ResourceSet()
        let containers = await set.createResource(uri: "test://scope-containers")
        let children = await set.createResource(uri: "test://scope-children")
        let child = model.make("child")
        let single = model.make("single")
        let parent = model.make("parent", children: [child.id], part: single.id)
        await children.add(contentsOf: [child, single])
        await containers.add(parent)
        #expect(
            await lookup(child, in: containers, scope: .anyResource)
                == Lookup(container: parent.id, feature: NodeFeature.children))
        #expect(
            await lookup(single, in: containers, scope: .anyResource)
                == Lookup(container: parent.id, feature: NodeFeature.part))
        #expect(await lookup(child, in: containers, scope: .thisResource) == Lookup(container: nil, feature: nil))
        #expect(await lookup(single, in: containers, scope: .thisResource) == Lookup(container: nil, feature: nil))
        for scope in ContainerLookupScope.allCases {
            #expect(await lookup(child, in: children, scope: scope) == Lookup(container: nil, feature: nil))
        }
        let found = await containers.container(ofIdentifier: child.id)
        #expect(found?.container.id == parent.id)
        #expect(found?.feature.name == NodeFeature.children)
        await expectLegacyAgreement(child, in: containers)
        await expectLegacyAgreement(single, in: containers)
    }

    @Test("a removed child keeps its container only in the any-resource scope")
    func removedChild() async {
        let child = model.make("child")
        let parent = model.make("parent", children: [child.id])
        let resource = Resource(uri: "test://scope-removed")
        await resource.add(contentsOf: [parent, child])
        #expect(await resource.remove(id: child.id))
        #expect(
            await lookup(child, in: resource, scope: .anyResource)
                == Lookup(container: parent.id, feature: NodeFeature.children))
        #expect(await lookup(child, in: resource, scope: .thisResource) == Lookup(container: nil, feature: nil))
        await expectLegacyAgreement(child, in: resource)
    }

    @Test("an unregistered child listed in an array value is found only in the any-resource scope")
    func arrayValueOfIdentifiers() async {
        let child = model.make("child")
        let parent = model.make("parent", children: EcoreValueArray([child.id]))
        let resource = Resource(uri: "test://scope-array")
        await resource.add(parent)
        #expect(
            await lookup(child, in: resource, scope: .anyResource)
                == Lookup(container: parent.id, feature: NodeFeature.children))
        #expect(await lookup(child, in: resource, scope: .thisResource) == Lookup(container: nil, feature: nil))
        await resource.register(child)
        #expect(
            await lookup(child, in: resource, scope: .thisResource)
                == Lookup(container: parent.id, feature: NodeFeature.children))
        await expectLegacyAgreement(child, in: resource)
    }

    // MARK: - Embedded objects

    @Test("an embedded child is found in either scope")
    func embeddedObjects() async {
        let set = ResourceSet()
        let resource = await set.createResource(uri: "test://scope-embedded")
        let elsewhere = await set.createResource(uri: "test://scope-embedded-elsewhere")
        let single = model.make("single")
        let listed = model.make("listed")
        let parent = model.make("parent", children: EcoreValueArray([listed]), part: single)
        await elsewhere.add(single)
        await resource.add(parent)
        for scope in ContainerLookupScope.allCases {
            #expect(
                await lookup(single, in: resource, scope: scope)
                    == Lookup(container: parent.id, feature: NodeFeature.part))
            #expect(
                await lookup(listed, in: resource, scope: scope)
                    == Lookup(container: parent.id, feature: NodeFeature.children))
        }
        await expectLegacyAgreement(single, in: resource)
        await expectLegacyAgreement(listed, in: resource)
    }

    // MARK: - Native metamodel objects

    @Test("native metamodel contents answer from their metamodel structure in either scope")
    func nativeMetamodelObjects() async {
        let attribute = EAttribute(name: "label", eType: EDataType(name: "EString"))
        let eClass = EClass(name: "Labelled", eStructuralFeatures: [attribute])
        let package = EPackage(
            name: "labels", nsURI: "http://example.org/labels", nsPrefix: "labels", eClassifiers: [eClass])
        let resource = Resource(uri: "test://scope-native")
        let other = Resource(uri: "test://scope-native-other")
        await resource.add(package)
        for scope in ContainerLookupScope.allCases {
            #expect(
                await lookup(eClass, in: resource, scope: scope)
                    == Lookup(container: package.id, feature: EcoreFeatureName.eClassifiers.rawValue))
            #expect(
                await lookup(attribute, in: resource, scope: scope)
                    == Lookup(container: eClass.id, feature: EcoreFeatureName.eStructuralFeatures.rawValue))
            #expect(await lookup(package, in: resource, scope: scope) == Lookup(container: nil, feature: nil))
            #expect(await lookup(eClass, in: other, scope: scope) == Lookup(container: nil, feature: nil))
        }
        await expectLegacyAgreement(eClass, in: resource)
        await expectLegacyAgreement(attribute, in: resource)
    }

    // MARK: - Competing claims

    @Test("the first claim wins in the any-resource scope, the first admitted claim in this-resource scope")
    func competingClaims() async {
        let child = model.make("child")
        let byIdentifier = model.make("byIdentifier", children: [child.id])
        let embedding = model.make("embedding", part: child)
        let resource = Resource(uri: "test://scope-competing")
        await resource.add(contentsOf: [byIdentifier, embedding])
        #expect(
            await lookup(child, in: resource, scope: .anyResource)
                == Lookup(container: byIdentifier.id, feature: NodeFeature.children))
        #expect(
            await lookup(child, in: resource, scope: .thisResource)
                == Lookup(container: embedding.id, feature: NodeFeature.part))
        await expectLegacyAgreement(child, in: resource)
        await resource.register(child)
        for scope in ContainerLookupScope.allCases {
            #expect(
                await lookup(child, in: resource, scope: scope)
                    == Lookup(container: byIdentifier.id, feature: NodeFeature.children))
        }
        await expectLegacyAgreement(child, in: resource)
    }

    @Test("a container holding a child twice reports its first containment reference in either scope")
    func sameContainerTwice() async {
        let child = model.make("child")
        let both = model.make("both", children: [child.id], part: child.id)
        let resource = Resource(uri: "test://scope-twice")
        await resource.add(contentsOf: [both, child])
        for scope in ContainerLookupScope.allCases {
            #expect(
                await lookup(child, in: resource, scope: scope)
                    == Lookup(container: both.id, feature: NodeFeature.children))
        }
    }

    // MARK: - Cost

    @Test("scoped lookups build the container index at most once", arguments: ContainerLookupScope.allCases)
    func scopedLookupsBuildOnce(scope: ContainerLookupScope) async {
        let resource = Resource(uri: "test://scope-cost")
        var nodes: [DynamicEObject] = (0..<300).map { model.make("n\($0)") }
        for index in nodes.indices {
            let kids = (1...3).map { index * 3 + $0 }.filter { $0 < nodes.count }.map { nodes[$0].id }
            if !kids.isEmpty { nodes[index].eSet(model.children, kids) }
        }
        await resource.add(contentsOf: nodes)
        let start = await resource.containerIndexBuilds
        for node in nodes { _ = await resource.eContainer(of: node, scope: scope) }
        for node in nodes { _ = await resource.eContainingFeature(of: node, scope: scope) }
        #expect(await resource.containerIndexBuilds - start <= 1)
    }
}
