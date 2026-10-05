//
// FixtureInstanceTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@MainActor
@Suite("Instance editing of loaded models")
struct FixtureInstanceTests {

    private enum FixtureError: Error { case missing(String) }

    private func xmiURL(_ name: String) throws -> URL {
        let base = try #require(Bundle.module.resourceURL)
        var url = base.appendingPathComponent("Resources")
        if !FileManager.default.fileExists(atPath: url.path) { url = base }
        return url.appendingPathComponent("xmi").appendingPathComponent(name)
    }

    /// Loads a metamodel document, registers its package, and returns the package.
    private func registerMetamodel(_ name: String, in set: ResourceSet) async throws -> EPackage {
        let resource = try await set.loadEcoreResource(uri: try xmiURL(name).absoluteString)
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        await set.registerMetamodel(package, uri: package.nsURI)
        return package
    }

    /// Loads an instance document into the resource set.
    private func loadInstances(_ name: String, in set: ResourceSet) async throws -> Resource {
        try await set.loadXMIResource(uri: try xmiURL(name).absoluteString)
    }

    @Test("team.xmi: edit, delete the leader, validate, and undo")
    func team() async throws {
        let set = ResourceSet()
        let package = try await registerMetamodel("organisation.ecore", in: set)
        let resource = try await loadInstances("team.xmi", in: set)
        let domain = await InstanceEditingDomain(resource: resource, resourceSet: set)
        let teamClass = try #require(package.eClassifiers.first { $0.name == "Team" } as? EClass)
        let team = try #require(domain.snapshot.roots.first as? DynamicEObject)
        #expect(team.eClass.name == "Team")
        #expect(domain.validate().isEmpty)

        let members = ReferenceValues.identifiers(team.eGet("members"))
        #expect(members.count == 3)
        let alice = try #require(domain.snapshot.object(id: members[0]) as? DynamicEObject)
        let nameFeature = try #require(alice.eClass.getEAttribute(name: "name"))
        try await domain.perform(domain.setCommand(object: alice, feature: nameFeature, value: "Alicia"))
        #expect(domain.snapshot.value(of: alice.id, feature: "name") as? String == "Alicia")

        // Alice is the leader: deleting her clears the required leader reference.
        try await domain.perform(domain.deleteCommand(objects: [alice]))
        #expect(domain.snapshot.contains(id: alice.id) == false)
        let problems = domain.validate()
        #expect(problems.map(\.code) == [.lowerBound])
        #expect(problems.first?.feature == "leader")
        #expect(problems.first?.objectID == team.id)

        try await domain.undo()
        #expect(domain.validate().isEmpty)
        #expect(ReferenceValues.identifiers(domain.snapshot.value(of: team.id, feature: "members")).first == alice.id)
        #expect(ReferenceValues.identifiers(domain.snapshot.value(of: team.id, feature: "leader")) == [alice.id])
        try await domain.undo()
        #expect(domain.snapshot.value(of: alice.id, feature: "name") as? String == "Alice")

        let members3 = domain.legalChildren(of: team).map { "\($0.reference.name):\($0.eClass.name)" }
        #expect(members3 == ["members:Person"])
        #expect(teamClass.name == "Team")
    }

    @Test("team.xmi: creating a member and moving members keeps the model valid")
    func teamEdits() async throws {
        let set = ResourceSet()
        _ = try await registerMetamodel("organisation.ecore", in: set)
        let resource = try await loadInstances("team.xmi", in: set)
        let domain = await InstanceEditingDomain(resource: resource, resourceSet: set)
        let team = try #require(domain.snapshot.roots.first as? DynamicEObject)
        let descriptor = try #require(domain.legalChildren(of: team).first)
        try await domain.perform(domain.createChildCommand(container: team, descriptor: descriptor))
        var members = ReferenceValues.identifiers(domain.snapshot.value(of: team.id, feature: "members"))
        #expect(members.count == 4)
        let membersReference = try #require(team.eClass.getEReference(name: "members"))
        try await domain.perform(MoveCommand(object: team, feature: membersReference, from: 3, to: 0))
        let reordered = ReferenceValues.identifiers(domain.snapshot.value(of: team.id, feature: "members"))
        #expect(reordered.first == members[3])
        members = reordered
        try await domain.undo()
        try await domain.undo()
        #expect(ReferenceValues.identifiers(domain.snapshot.value(of: team.id, feature: "members")).count == 3)
        #expect(domain.validate().isEmpty)
    }

    @Test("zoo.xmi: enumeration values are validated")
    func zoo() async throws {
        let set = ResourceSet()
        _ = try await registerMetamodel("animals.ecore", in: set)
        let resource = try await loadInstances("zoo.xmi", in: set)
        let domain = await InstanceEditingDomain(resource: resource, resourceSet: set)
        let animal = try #require(domain.snapshot.roots.first as? DynamicEObject)
        #expect(animal.eClass.name == "Animal")
        #expect(domain.validate().isEmpty)
        let species = try #require(animal.eClass.getEAttribute(name: "species"))
        try await domain.perform(domain.setCommand(object: animal, feature: species, value: "dog"))
        #expect(domain.validate().isEmpty)
        try await domain.perform(domain.setCommand(object: animal, feature: species, value: "fish"))
        #expect(domain.validate().map(\.code) == [.invalidEnumLiteral])
        try await domain.undo()
        #expect(domain.validate().isEmpty)
        #expect(domain.isDirty)
    }

    @Test("company-a and department-b: commands find the right resource in the set")
    func crossResource() async throws {
        let set = ResourceSet()
        let string = EDataType(name: "EString", instanceClassName: "String")
        let int = EDataType(name: "EInt", instanceClassName: "Int")
        let person = EClass(name: "Person", eStructuralFeatures: [EAttribute(name: "name", eType: string), EAttribute(name: "age", eType: int)])
        let department = EClass(
            name: "Department",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EReference(name: "employees", eType: person, upperBound: -1, containment: true),
            ])
        let company = EClass(
            name: "Company",
            eStructuralFeatures: [EAttribute(name: "name", eType: string), EReference(name: "mainDepartment", eType: department)])
        let package = EPackage(
            name: "organisation", nsURI: "http://swift-modelling.org/test/organisation", nsPrefix: "org",
            eClassifiers: [person, department, company])
        await set.registerMetamodel(package, uri: package.nsURI)
        let companyResource = try await loadInstances("company-a.xmi", in: set)
        let departmentResource = try await loadInstances("department-b.xmi", in: set)

        let departmentObject = try #require(await departmentResource.getRootObjects().first as? DynamicEObject)
        let employees = ReferenceValues.identifiers(departmentObject.eGet("employees"))
        #expect(employees.count == 2)
        let bob = try #require(await departmentResource.resolve(employees[1]) as? DynamicEObject)

        let domain = BasicEditingDomain(resourceSet: set)
        let rename = domain.createSetCommand(object: bob, feature: try #require(person.getEAttribute(name: "name")), value: "Robert")
        _ = try await domain.execute(rename)
        #expect(await departmentResource.eGet(objectId: bob.id, feature: "name") as? String == "Robert")
        try await domain.undo()
        #expect(await departmentResource.eGet(objectId: bob.id, feature: "name") as? String == "Bob")

        let companyObject = try #require(await companyResource.getRootObjects().first as? DynamicEObject)
        let delete = domain.createDeleteCommand(objects: [bob])
        _ = try await domain.execute(delete)
        #expect(await departmentResource.contains(id: bob.id) == false)
        #expect(await companyResource.contains(id: companyObject.id))
        try await domain.undo()
        #expect(await departmentResource.contains(id: bob.id))
        #expect(await companyResource.eGet(objectId: companyObject.id, feature: "mainDepartment") is ResourceProxy)
        let validation = ModelValidator(metamodels: [package]).validate(await companyResource.snapshot())
        #expect(validation.isEmpty)
    }
}
