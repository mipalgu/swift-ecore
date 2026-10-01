//
// DynamicMetamodelTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Dynamic Metamodel and Container Navigation Tests")
struct DynamicMetamodelTests {
    private func parse(_ relativePath: String) async throws -> Resource {
        let url = try ReflectionFixtures.resourcesURL().appendingPathComponent(relativePath)
        return try await XMIParser().parse(url)
    }

    private func engine(for resource: Resource) async -> ECoreExecutionEngine {
        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(resource, alias: "MM")
        return engine
    }

    private func dynamicNames(_ value: (any EcoreValue)?) -> [String] {
        guard let array = value as? EcoreValueArray else { return [] }
        return array.values.compactMap { ($0 as? DynamicEObject)?.eGet("name") as? String }
    }

    // MARK: - Parsed resources use the Ecore descriptors

    @Test("Parsed metamodel elements are typed by the Ecore descriptors")
    func parsedDescriptors() async throws {
        let resource = try await parse("xmi/organisation.ecore")
        let root = try #require(await resource.getRootObjects().first as? DynamicEObject)
        #expect(root.eClass.id == EcorePackage.metaClass(.ePackage).id)
        for object in await resource.getAllObjects() {
            let eClass = try #require(object.eClass as? EClass)
            #expect(EcorePackage.isMetaClass(eClass))
        }
    }

    @Test("getAllInstancesOf counts parsed metamodel elements exactly")
    func parsedInstanceCounts() async throws {
        let resource = try await parse("xmi/organisation.ecore")
        #expect(await resource.getAllInstancesOf(EcorePackage.metaClass(.ePackage)).count == 1)
        #expect(await resource.getAllInstancesOf(EcorePackage.metaClass(.eClass)).count == 3)
        let attributes = await resource.getAllInstancesOf(EcorePackage.metaClass(.eAttribute))
        let references = await resource.getAllInstancesOf(EcorePackage.metaClass(.eReference))
        let features = await resource.getAllInstancesOf(EcorePackage.metaClass(.eStructuralFeature))
        #expect(attributes.count > 0 && references.count > 0)
        #expect(features.count == attributes.count + references.count)
        let named = await resource.getAllInstancesOf(EcorePackage.metaClass(.eNamedElement))
        #expect(named.count >= 1 + 3 + features.count)
    }

    @Test("Parsed metamodel is navigable by feature name")
    func parsedNavigation() async throws {
        let resource = try await parse("xmi/organisation.ecore")
        let engine = await engine(for: resource)
        let root = try #require(await resource.getRootObjects().first)
        #expect(try await engine.navigate(from: root, property: "name") as? String == "organisation")
        #expect(
            try await engine.navigate(from: root, property: "nsURI") as? String
                == "http://swift-modelling.org/test/organisation")
        let classifiers = try await engine.navigate(from: root, property: "eClassifiers")
        #expect(dynamicNames(classifiers) == ["Person", "Team", "Organisation"])
        let team = try #require(
            (classifiers as? EcoreValueArray)?.values.compactMap { $0 as? DynamicEObject }
                .first { $0.eGet("name") as? String == "Team" })
        let features = try await engine.navigate(from: team, property: "eStructuralFeatures")
        #expect(dynamicNames(features) == ["name", "members", "leader"])
        let members = try #require(
            (features as? EcoreValueArray)?.values.compactMap { $0 as? DynamicEObject }
                .first { $0.eGet("name") as? String == "members" })
        #expect(try await engine.navigate(from: members, property: "containment") as? Bool == true)
        #expect(try await engine.navigate(from: members, property: "upperBound") as? Int == -1)
    }

    @Test("Parsed metamodel container navigation")
    func parsedContainment() async throws {
        let resource = try await parse("xmi/organisation.ecore")
        let engine = await engine(for: resource)
        let root = try #require(await resource.getRootObjects().first)
        let classes = await resource.getAllInstancesOf(EcorePackage.metaClass(.eClass))
        let team = try #require(
            classes.compactMap { $0 as? DynamicEObject }.first { $0.eGet("name") as? String == "Team" })
        let container = try await engine.navigate(from: team, property: "eContainer")
        #expect((container as? any EObject)?.id == root.id)
        let feature = try await engine.navigate(from: team, property: "eContainingFeature") as? EReference
        #expect(feature?.name == "eClassifiers")
        #expect(try await engine.navigate(from: root, property: "eContainer") == nil)

        let contents = try #require(
            try await engine.navigate(from: root, property: "eContents") as? EcoreValueArray)
        #expect(dynamicNames(contents) == ["Person", "Team", "Organisation"])
        let all = try #require(
            try await engine.navigate(from: root, property: "eAllContents") as? EcoreValueArray)
        let features = await resource.getAllInstancesOf(EcorePackage.metaClass(.eStructuralFeature))
        #expect(all.values.count == 3 + features.count)
        // Depth first: the first class is followed by its features
        let firstFeatureOwner = try #require(all.values[1] as? DynamicEObject)
        #expect(firstFeatureOwner.eClass.name == "EAttribute")
        #expect(await resource.eAllContents(of: root).count == all.values.count)
    }

    @Test("Parsed families metamodel exposes containment references")
    func parsedFamilies() async throws {
        let resource = try await parse("metamodels/Families.ecore")
        let references = await resource.getAllInstancesOf(EcorePackage.metaClass(.eReference))
        let containments = try references.compactMap { $0 as? DynamicEObject }.filter {
            try ReflectionFixtures.value(of: $0, "containment") as? Bool == true
        }
        #expect(references.count == 8)
        #expect(containments.count == 4)
    }

    // MARK: - Instance models

    private func makeTreeMetamodel() -> (node: EClass, children: EReference, parent: EReference) {
        let nodeID = EUUID()
        let childrenID = EUUID()
        let parentID = EUUID()
        let children = EReference(
            id: childrenID, name: "children", eType: EClass(id: nodeID, name: "Node"),
            upperBound: -1, containment: true, opposite: parentID)
        let parent = EReference(
            id: parentID, name: "parent", eType: EClass(id: nodeID, name: "Node"),
            opposite: childrenID)
        let label = EAttribute(name: "label", eType: EDataType(name: "EString"))
        let node = EClass(
            id: nodeID, name: "Node", eStructuralFeatures: [label, children, parent])
        return (node, children, parent)
    }

    @Test("Dynamic objects expose container navigation")
    func dynamicContainment() async throws {
        let (node, children, _) = makeTreeMetamodel()
        var root = DynamicEObject(eClass: node)
        var middle = DynamicEObject(eClass: node)
        let leaf = DynamicEObject(eClass: node)
        var other = DynamicEObject(eClass: node)
        middle.eSet(children, [leaf.id])
        root.eSet(children, [middle.id])
        other.eSet("label", value: "other")
        let resource = Resource(uri: "test://tree")
        for object in [leaf, middle, root, other] { await resource.add(object) }

        #expect(await resource.eContainer(of: leaf)?.id == middle.id)
        #expect(await resource.eContainer(of: middle)?.id == root.id)
        #expect(await resource.eContainer(of: root) == nil)
        #expect(await resource.eContainer(of: other) == nil)
        #expect(await resource.eContainingFeature(of: leaf)?.name == "children")
        #expect(await resource.eContainingFeature(of: root) == nil)
        #expect(await resource.eContents(of: root).map(\.id) == [middle.id])
        #expect(await resource.eAllContents(of: root).map(\.id) == [middle.id, leaf.id])
        #expect(await resource.eContents(of: leaf).isEmpty)

        let engine = await engine(for: resource)
        let container = try await engine.navigate(from: leaf, property: "eContainer") as? DynamicEObject
        #expect(container?.id == middle.id)
        let feature = try await engine.navigate(from: leaf, property: "eContainingFeature") as? EReference
        #expect(feature?.name == "children")
        let contents = try await engine.navigate(from: root, property: "eAllContents") as? EcoreValueArray
        #expect(contents?.values.count == 2)
        let direct = try await engine.navigate(from: root, property: "eContents") as? EcoreValueArray
        #expect(direct?.values.count == 1)
    }

    @Test("Direct object values are treated as contents")
    func directValues() async throws {
        let (node, children, _) = makeTreeMetamodel()
        let leaf = DynamicEObject(eClass: node)
        var root = DynamicEObject(eClass: node)
        root.eSet(children, EcoreValueArray([leaf]))
        let resource = Resource(uri: "test://direct")
        await resource.add(root)
        #expect(await resource.eContents(of: root).map(\.id) == [leaf.id])
        var single = DynamicEObject(eClass: node)
        single.eSet(children, leaf)
        await resource.add(single)
        #expect(await resource.eContents(of: single).map(\.id) == [leaf.id])
        var unknown = DynamicEObject(eClass: node)
        unknown.eSet(children, 5)
        #expect(await resource.eContents(of: unknown).isEmpty)
    }

    @Test("Container navigation without a registered resource")
    func unregisteredDynamic() async throws {
        let (node, _, _) = makeTreeMetamodel()
        let orphan = DynamicEObject(eClass: node)
        let engine = ECoreExecutionEngine(models: [:])
        #expect(try await engine.navigate(from: orphan, property: "eContainer") == nil)
        #expect(try await engine.navigate(from: orphan, property: "eContainingFeature") == nil)
        let contents = try await engine.navigate(from: orphan, property: "eContents") as? EcoreValueArray
        #expect(contents?.values.isEmpty == true)
        let allContents = try await engine.navigate(from: orphan, property: "eAllContents") as? EcoreValueArray
        #expect(allContents?.values.isEmpty == true)
    }

    @Test("A feature named like a navigation property takes precedence")
    func featureShadowsNavigation() async throws {
        let shadow = EAttribute(name: "eContents", eType: EDataType(name: "EString"))
        let eClass = EClass(name: "Shadow", eStructuralFeatures: [shadow])
        var object = DynamicEObject(eClass: eClass)
        object.eSet(shadow, "own value")
        let resource = Resource(uri: "test://shadow")
        await resource.add(object)
        let engine = await engine(for: resource)
        #expect(try await engine.navigate(from: object, property: "eContents") as? String == "own value")
    }
}
