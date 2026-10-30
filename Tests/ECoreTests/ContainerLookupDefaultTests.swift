//
// ContainerLookupDefaultTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// The feature names of the node metamodel used by the default scope tests.
private enum NodeFeature {
    static let name = "name"
    static let children = "children"
}

/// A node metamodel with many-valued containment.
private struct NodeModel {
    let node: EClass

    var children: EReference { node.getEReference(name: NodeFeature.children)! }

    init() {
        let nodeID = EUUID()
        let stub = EClass(id: nodeID, name: "Node")
        let name = EAttribute(name: NodeFeature.name, eType: EDataType(name: "EString", instanceClassName: "String"))
        let children = EReference(name: NodeFeature.children, eType: stub, upperBound: -1, containment: true)
        node = EClass(id: nodeID, name: "Node", eStructuralFeatures: [name, children])
    }

    /// Creates a node whose children reference holds the given value as stored.
    func make(_ name: String, children: (any EcoreValue)? = nil) -> DynamicEObject {
        var object = DynamicEObject(eClass: node)
        object.eSet(NodeFeature.name, value: name)
        if let children { object.eSet(self.children, children) }
        return object
    }
}

/// A parent in one resource whose child belongs to another resource of the same set.
///
/// The container of the child is found in the ``ContainerLookupScope/anyResource`` scope
/// only, so the unscoped lookups reveal the scope that the containers resource uses.
private struct SplitModel {
    let set: ResourceSet
    let containers: Resource
    let children: Resource
    let parent: DynamicEObject
    let child: DynamicEObject

    init(set: ResourceSet = ResourceSet(), model: NodeModel = NodeModel()) async {
        self.set = set
        containers = await set.createResource(uri: "test://default-containers")
        children = await set.createResource(uri: "test://default-children")
        child = model.make("child")
        parent = model.make("parent", children: [child.id])
        await children.add(child)
        await containers.add(parent)
    }

    /// The identifier of the container that the unscoped lookup reports for the child.
    var unscopedContainer: EUUID? {
        get async { await containers.eContainer(of: child)?.id }
    }

    /// The name of the feature that the unscoped lookup reports for the child.
    var unscopedFeature: String? {
        get async { await containers.eContainingFeature(of: child)?.name }
    }
}

@Suite("Container lookup defaults")
struct ContainerLookupDefaultTests {
    private let model = NodeModel()

    // MARK: - Built-in default

    @Test("the built-in default is the scope of version 0.6")
    func builtInDefault() {
        #expect(ContainerLookupScope.builtInDefault == .thisResource)
        #expect(ContainerLookupScope.builtInDefault == .legacy)
    }

    @Test("the scopes are spelt as on the command line")
    func spellings() {
        #expect(ContainerLookupScope.anyResource.rawValue == "any-resource")
        #expect(ContainerLookupScope.thisResource.rawValue == "this-resource")
        #expect(ContainerLookupScope(rawValue: "any-resource") == .anyResource)
        #expect(ContainerLookupScope(rawValue: "this-resource") == .thisResource)
        #expect(ContainerLookupScope(rawValue: "anyResource") == nil)
    }

    @Test("a standalone resource uses the built-in default")
    func standaloneResource() async {
        let child = model.make("child")
        let parent = model.make("parent", children: [child.id])
        let resource = Resource(uri: "test://default-standalone")
        await resource.add(contentsOf: [parent, child])
        #expect(await resource.remove(id: child.id))
        #expect(await resource.containerLookupScopeOverride == nil)
        #expect(await resource.configuredContainerLookupScope == nil)
        #expect(await resource.containerLookupScope == .thisResource)
        #expect(await resource.eContainer(of: child) == nil)
        #expect(await resource.eContainingFeature(of: child) == nil)
        await resource.setContainerLookupScope(.anyResource)
        #expect(await resource.containerLookupScopeOverride == .anyResource)
        #expect(await resource.configuredContainerLookupScope == .anyResource)
        #expect(await resource.containerLookupScope == .anyResource)
        #expect(await resource.eContainer(of: child)?.id == parent.id)
        #expect(await resource.eContainingFeature(of: child)?.name == NodeFeature.children)
    }

    @Test("a resource of an unconfigured set uses the built-in default")
    func unconfiguredSet() async {
        let split = await SplitModel(model: model)
        #expect(await split.set.defaultContainerLookupScope == nil)
        #expect(await split.containers.configuredContainerLookupScope == nil)
        #expect(await split.containers.containerLookupScope == .thisResource)
        #expect(await split.unscopedContainer == nil)
        #expect(await split.unscopedFeature == nil)
    }

    // MARK: - Resource set default

    @Test("the resources of a set inherit its default, including resources created earlier")
    func setDefaultIsInherited() async {
        let split = await SplitModel(model: model)
        await split.set.setDefaultContainerLookupScope(.anyResource)
        #expect(await split.set.defaultContainerLookupScope == .anyResource)
        #expect(await split.containers.containerLookupScopeOverride == nil)
        #expect(await split.containers.configuredContainerLookupScope == .anyResource)
        #expect(await split.containers.containerLookupScope == .anyResource)
        #expect(await split.unscopedContainer == split.parent.id)
        #expect(await split.unscopedFeature == NodeFeature.children)
        let later = await split.set.createResource(uri: "test://default-later")
        #expect(await later.containerLookupScope == .anyResource)
        await split.set.setDefaultContainerLookupScope(nil)
        #expect(await split.set.defaultContainerLookupScope == nil)
        #expect(await split.containers.configuredContainerLookupScope == nil)
        #expect(await split.unscopedContainer == nil)
    }

    @Test("a set can be created with a default scope", arguments: ContainerLookupScope.allCases)
    func setCreatedWithDefault(scope: ContainerLookupScope) async {
        let set = ResourceSet(defaultContainerLookupScope: scope)
        #expect(await set.defaultContainerLookupScope == scope)
        let resource = await set.createResource(uri: "test://default-created")
        #expect(await resource.configuredContainerLookupScope == scope)
        #expect(await resource.containerLookupScope == scope)
    }

    @Test("a resource override takes precedence over the default of its set")
    func resourceOverrideWins() async {
        let split = await SplitModel(set: ResourceSet(defaultContainerLookupScope: .anyResource), model: model)
        await split.containers.setContainerLookupScope(.thisResource)
        #expect(await split.containers.containerLookupScopeOverride == .thisResource)
        #expect(await split.containers.configuredContainerLookupScope == .thisResource)
        #expect(await split.unscopedContainer == nil)
        #expect(await split.unscopedFeature == nil)
        await split.containers.setContainerLookupScope(nil)
        #expect(await split.containers.containerLookupScopeOverride == nil)
        #expect(await split.containers.configuredContainerLookupScope == .anyResource)
        #expect(await split.unscopedContainer == split.parent.id)
        #expect(await split.unscopedFeature == NodeFeature.children)
    }

    @Test("a resource that leaves its set reverts to the built-in default")
    func leavingTheSet() async {
        let split = await SplitModel(set: ResourceSet(defaultContainerLookupScope: .anyResource), model: model)
        await split.containers.setResourceSet(nil)
        #expect(await split.containers.configuredContainerLookupScope == nil)
        #expect(await split.containers.containerLookupScope == .thisResource)
        #expect(await split.unscopedContainer == nil)
        let other = ResourceSet(defaultContainerLookupScope: .anyResource)
        await split.containers.setResourceSet(other)
        #expect(await split.containers.configuredContainerLookupScope == .anyResource)
        #expect(await split.unscopedContainer == split.parent.id)
    }

    @Test("a resource keeps the default of its set once the set has been released")
    func releasedSet() async {
        var set: ResourceSet? = ResourceSet(defaultContainerLookupScope: .anyResource)
        let resource = try? #require(await set?.createResource(uri: "test://default-released"))
        set = nil
        #expect(await resource?.lostResourceSet == true)
        #expect(await resource?.configuredContainerLookupScope == .anyResource)
        #expect(await resource?.containerLookupScope == .anyResource)
    }

    // MARK: - Explicit scopes

    @Test("an explicit scope overrides the configured default", arguments: ContainerLookupScope.allCases)
    func explicitScopeOverrides(configured: ContainerLookupScope) async {
        let split = await SplitModel(set: ResourceSet(defaultContainerLookupScope: configured), model: model)
        #expect(await split.containers.eContainer(of: split.child, scope: .anyResource)?.id == split.parent.id)
        #expect(await split.containers.eContainer(of: split.child, scope: .thisResource) == nil)
        #expect(
            await split.containers.eContainingFeature(of: split.child, scope: .anyResource)?.name
                == NodeFeature.children)
        #expect(await split.containers.eContainingFeature(of: split.child, scope: .thisResource) == nil)
    }

    @Test("a nil scope uses the configured default", arguments: ContainerLookupScope.allCases)
    func nilScopeUsesDefault(configured: ContainerLookupScope) async {
        let split = await SplitModel(set: ResourceSet(defaultContainerLookupScope: configured), model: model)
        let expectedContainer = configured == .anyResource ? split.parent.id : nil
        let expectedFeature = configured == .anyResource ? NodeFeature.children : nil
        #expect(await split.containers.eContainer(of: split.child, scope: nil)?.id == expectedContainer)
        #expect(await split.containers.eContainingFeature(of: split.child, scope: nil)?.name == expectedFeature)
        #expect(await split.unscopedContainer == expectedContainer)
        #expect(await split.unscopedFeature == expectedFeature)
    }

    @Test("a non-optional scope value is accepted as before", arguments: ContainerLookupScope.allCases)
    func nonOptionalScope(scope: ContainerLookupScope) async {
        let split = await SplitModel(model: model)
        let expectedContainer = scope == .anyResource ? split.parent.id : nil
        #expect(await split.containers.eContainer(of: split.child, scope: scope)?.id == expectedContainer)
        #expect(await split.containers.eContainer(of: split.child, scope: .standard)?.id == split.parent.id)
        #expect(await split.containers.eContainer(of: split.child, scope: .legacy) == nil)
        #expect(await split.containers.eContainer(of: split.child, scope: ContainerLookupScope()) != nil)
    }

    @Test("an identifier lookup without a configured scope answers for any resource")
    func identifierLookupUnconfigured() async {
        let split = await SplitModel(model: model)
        #expect(await split.containers.container(ofIdentifier: split.child.id)?.container.id == split.parent.id)
        #expect(await split.containers.container(ofIdentifier: split.child.id, scope: nil)?.feature.name == NodeFeature.children)
        #expect(await split.set.container(ofIdentifier: split.child.id)?.container.id == split.parent.id)
        #expect(await split.set.container(ofIdentifier: split.child.id)?.resource === split.containers)
    }

    @Test("an identifier lookup uses the configured scope", arguments: ContainerLookupScope.allCases)
    func identifierLookupConfigured(configured: ContainerLookupScope) async {
        let split = await SplitModel(set: ResourceSet(defaultContainerLookupScope: configured), model: model)
        let expected = configured == .anyResource ? split.parent.id : nil
        #expect(await split.containers.container(ofIdentifier: split.child.id)?.container.id == expected)
        #expect(await split.set.container(ofIdentifier: split.child.id)?.container.id == expected)
        await split.containers.setContainerLookupScope(.anyResource)
        #expect(await split.containers.container(ofIdentifier: split.child.id)?.container.id == split.parent.id)
        #expect(await split.set.container(ofIdentifier: split.child.id)?.container.id == split.parent.id)
    }

    @Test("an explicit scope overrides the configured scope of an identifier lookup", arguments: ContainerLookupScope.allCases)
    func identifierLookupExplicit(configured: ContainerLookupScope) async {
        let split = await SplitModel(set: ResourceSet(defaultContainerLookupScope: configured), model: model)
        #expect(
            await split.containers.container(ofIdentifier: split.child.id, scope: .anyResource)?.container.id
                == split.parent.id)
        #expect(await split.containers.container(ofIdentifier: split.child.id, scope: .thisResource) == nil)
        #expect(await split.set.container(ofIdentifier: split.child.id, scope: .anyResource)?.container.id == split.parent.id)
        #expect(await split.set.container(ofIdentifier: split.child.id, scope: .thisResource) == nil)
    }
}
