//
// OrderPreservationTests.swift
// ECoreTests
//
//  Created by Rene Hexel on 5/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
import Foundation
@testable import ECore

/// Tests for EMF-compliant order preservation in features, objects, and serialisation.
///
/// These tests verify that the Swift ECore implementation correctly preserves:
/// - Feature insertion order (like PyEcore's `test_deterministic_attribute_order`)
/// - Object insertion order in resources
/// - Containment path prioritisation over cross-references
/// - Deterministic XMI serialisation without hash randomisation issues
///
/// ## Context
///
/// This addresses the critical bug discovered in Phase 5 where Swift's hash randomisation
/// was causing non-deterministic behaviour in XMI serialisation and cross-reference resolution.
/// The fixes ensure EMF compliance by using OrderedCollections and proper metamodel-based
/// containment detection.
@Suite("EMF Order Preservation Tests")
struct OrderPreservationTests {

    // MARK: - Helper Methods

    /// Gets the test resources directory URL.
    ///
    /// - Returns: URL pointing to the test resources directory.
    /// - Throws: `TestError.resourcesNotFound` if the directory cannot be located.
    func getResourcesURL() throws -> URL {
        guard let resourcesURL = Bundle.module.resourceURL?.appendingPathComponent("Resources") else {
            throw TestError.resourcesNotFound("Test resources directory not found")
        }

        guard FileManager.default.fileExists(atPath: resourcesURL.path) else {
            throw TestError.resourcesNotFound("Test resources directory does not exist at: \(resourcesURL.path)")
        }

        return resourcesURL
    }

    /// Test-specific errors.
    enum TestError: Error {
        case resourcesNotFound(String)
        case fileNotFound(String)
        case invalidModelStructure(String)
    }

    // MARK: - Feature Order Preservation Tests

    @Test("Feature order preservation: features set in different orders should maintain insertion order")
    func testFeatureOrderPreservation() async throws {
        // Create a simple metamodel
        var personClass = EClass(name: "Person")
        let nameAttr = EAttribute(name: "name", eType: EDataType(name: "EString", instanceClassName: "String"))
        let locationAttr = EAttribute(name: "location", eType: EDataType(name: "EString", instanceClassName: "String"))
        let ageAttr = EAttribute(name: "age", eType: EDataType(name: "EInt", instanceClassName: "Int"))

        personClass.eStructuralFeatures = [nameAttr, locationAttr, ageAttr]

        // Create first person: set features in order name, location, age
        var person1 = DynamicEObject(eClass: personClass)
        person1.eSet("name", value: "Alice")
        person1.eSet("location", value: "Sydney")
        person1.eSet("age", value: 30)

        // Create second person: set features in different order age, name, location
        var person2 = DynamicEObject(eClass: personClass)
        person2.eSet("age", value: 25)
        person2.eSet("name", value: "Bob")
        person2.eSet("location", value: "Melbourne")

        // Create third person: set only some features location, name (no age)
        var person3 = DynamicEObject(eClass: personClass)
        person3.eSet("location", value: "Brisbane")
        person3.eSet("name", value: "Charlie")

        // Verify feature order is preserved as set, not metamodel order or alphabetical
        #expect(person1.getFeatureNames() == ["name", "location", "age"])
        #expect(person2.getFeatureNames() == ["age", "name", "location"])
        #expect(person3.getFeatureNames() == ["location", "name"])

        // Verify values are correct
        #expect(person1.eGet("name") as? String == "Alice")
        #expect(person1.eGet("location") as? String == "Sydney")
        #expect(person1.eGet("age") as? Int == 30)

        #expect(person2.eGet("name") as? String == "Bob")
        #expect(person2.eGet("location") as? String == "Melbourne")
        #expect(person2.eGet("age") as? Int == 25)

        #expect(person3.eGet("name") as? String == "Charlie")
        #expect(person3.eGet("location") as? String == "Brisbane")
        #expect(person3.eGet("age") == nil)
    }

    @Test("Resource object order preservation: objects should maintain insertion order, not UUID order")
    func testResourceObjectOrderPreservation() async throws {
        let resource = Resource(uri: "test://object-order")

        // Create simple objects
        var objectClass = EClass(name: "TestObject")
        let nameAttr = EAttribute(name: "name", eType: EDataType(name: "EString", instanceClassName: "String"))
        objectClass.eStructuralFeatures = [nameAttr]

        var obj1 = DynamicEObject(eClass: objectClass)
        obj1.eSet("name", value: "First")

        var obj2 = DynamicEObject(eClass: objectClass)
        obj2.eSet("name", value: "Second")

        var obj3 = DynamicEObject(eClass: objectClass)
        obj3.eSet("name", value: "Third")

        // Add in specific order
        _ = await resource.add(obj1)
        _ = await resource.add(obj2)
        _ = await resource.add(obj3)

        // Verify order is preserved, not sorted by UUID
        let objects = await resource.getAllObjects()
        #expect(objects.count == 3)
        #expect(objects[0].id == obj1.id, "First object should be obj1")
        #expect(objects[1].id == obj2.id, "Second object should be obj2")
        #expect(objects[2].id == obj3.id, "Third object should be obj3")

        // Verify root objects also maintain order
        let rootObjects = await resource.getRootObjects()
        #expect(rootObjects.count == 3)
        #expect(rootObjects[0].id == obj1.id)
        #expect(rootObjects[1].id == obj2.id)
        #expect(rootObjects[2].id == obj3.id)
    }

    // MARK: - Containment Path Priority Tests

    @Test("Containment path priority: cross-references should use containment paths, not recursive references")
    func testContainmentPathPriority() async throws {
        // Create team metamodel
        var teamClass = EClass(name: "Team")
        var personClass = EClass(name: "Person")

        let nameAttr = EAttribute(name: "name", eType: EDataType(name: "EString", instanceClassName: "String"))
        teamClass.eStructuralFeatures = [nameAttr]
        personClass.eStructuralFeatures = [nameAttr]

        // Create containment reference: team contains members
        let membersRef = EReference(name: "members", eType: personClass, upperBound: -1, containment: true)
        // Create cross-reference: team references leader (who is also in members)
        let leaderRef = EReference(name: "leader", eType: personClass, containment: false)

        teamClass.eStructuralFeatures.append(membersRef)
        teamClass.eStructuralFeatures.append(leaderRef)

        // Create objects
        var team = DynamicEObject(eClass: teamClass)
        team.eSet("name", value: "Engineering")

        var alice = DynamicEObject(eClass: personClass)
        alice.eSet("name", value: "Alice")

        var bob = DynamicEObject(eClass: personClass)
        bob.eSet("name", value: "Bob")

        // Set up containment: Alice and Bob are members
        team.eSet("members", value: [alice.id, bob.id])
        // Set up cross-reference: Alice is also the leader
        team.eSet("leader", value: alice.id)

        // Add to resource
        let resource = Resource(uri: "test://team")
        _ = await resource.add(team)
        _ = await resource.register(alice)
        _ = await resource.register(bob)

        // Serialize to XMI
        let serializer = XMISerializer()
        let xmiString = try await serializer.serialize(resource)

        // Verify leader reference uses containment path, not recursive reference
        #expect(xmiString.contains("leader href=\"#//@members.0\""), "Leader should reference first member via containment path")
        #expect(!xmiString.contains("leader href=\"#//@leader\""), "Leader should not reference itself recursively")

        // Verify Alice appears as contained element, not duplicated
        let aliceOccurrences = xmiString.components(separatedBy: "Alice").count - 1
        #expect(aliceOccurrences == 1, "Alice should appear exactly once in XMI (as contained member)")
    }

    @Test("XMI round-trip determinism: multiple runs should produce identical results")
    func testXMIRoundTripDeterminism() async throws {
        let resourcesURL = try getResourcesURL()
        let inputURL = resourcesURL.appendingPathComponent("xmi").appendingPathComponent("team.xmi")

        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw TestError.fileNotFound("team.xmi")
        }

        let parser = XMIParser()
        let serializer = XMISerializer()

        // Run the same round-trip test 10 times to verify determinism
        var outputs: [String] = []

        for run in 1...10 {
            // Parse XMI
            let resource = try await parser.parse(inputURL)

            // Verify consistent structure
            let roots = await resource.getRootObjects()
            #expect(roots.count == 1, "Run \(run): Should have exactly one root")

            let team = roots[0] as? DynamicEObject
            #expect(team != nil, "Run \(run): Root should be DynamicEObject")

            // Check cross-reference consistency
            let members = await resource.eGet(objectId: team!.id, feature: "members") as? [EUUID]
            let leaderId = await resource.eGet(objectId: team!.id, feature: "leader") as? EUUID

            #expect(members?.count == 3, "Run \(run): Should have 3 members")
            #expect(leaderId != nil, "Run \(run): Should have leader")
            #expect(leaderId == members?.first, "Run \(run): Leader should be first member")

            // Serialise to XMI
            let xmiOutput = try await serializer.serialize(resource)
            outputs.append(xmiOutput)
        }

        // Verify all outputs are identical (deterministic)
        let firstOutput = outputs[0]
        for (index, output) in outputs.enumerated() {
            #expect(output == firstOutput, "Run \(index + 1): Output should be identical to first run")
        }
    }

    @Test("Feature order preservation after round-trip: serialisation and deserialisation should preserve feature order")
    func testFeatureOrderRoundTrip() async throws {
        // Create objects with features set in specific orders
        var personClass = EClass(name: "Person")
        let nameAttr = EAttribute(name: "name", eType: EDataType(name: "EString", instanceClassName: "String"))
        let locationAttr = EAttribute(name: "location", eType: EDataType(name: "EString", instanceClassName: "String"))
        let ageAttr = EAttribute(name: "age", eType: EDataType(name: "EInt", instanceClassName: "Int"))

        personClass.eStructuralFeatures = [nameAttr, locationAttr, ageAttr]

        // Create person with specific feature order
        var person = DynamicEObject(eClass: personClass)
        person.eSet("age", value: 35)  // Set age first
        person.eSet("name", value: "Diana")  // Then name
        person.eSet("location", value: "Perth")  // Finally location

        // Verify initial order
        let initialOrder = person.getFeatureNames()
        #expect(initialOrder == ["age", "name", "location"])

        // Add to resource and serialise
        let resource = Resource(uri: "test://feature-order")
        _ = await resource.add(person)

        let serializer = XMISerializer()
        let xmiString = try await serializer.serialize(resource)
        
        // Debug: Print the serialized XMI
        print("=== SERIALIZED XMI ===")
        print(xmiString)
        print("====================")

        // Write to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".xmi")
        try xmiString.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Parse back from XMI
        let parser = XMIParser()
        let deserializedResource = try await parser.parse(tempURL)
        let deserializedRoots = await deserializedResource.getRootObjects()

        #expect(deserializedRoots.count == 1)
        let deserializedPerson = deserializedRoots[0] as? DynamicEObject
        #expect(deserializedPerson != nil)

        // Verify feature order is preserved after round-trip
        let deserializedOrder = deserializedPerson!.getFeatureNames()
        #expect(deserializedOrder == initialOrder, "Feature order should be preserved after round-trip")

        // Verify values are correct
        #expect(await deserializedResource.eGet(objectId: deserializedPerson!.id, feature: "name") as? String == "Diana")
        #expect(await deserializedResource.eGet(objectId: deserializedPerson!.id, feature: "location") as? String == "Perth")
        #expect(await deserializedResource.eGet(objectId: deserializedPerson!.id, feature: "age") as? Int == 35)
    }

    @Test("Metamodel-based containment detection: XMI serialiser should use EReference.containment, not hardcoded names")
    func testMetamodelBasedContainmentDetection() async throws {
        // Create a metamodel with various reference types
        var departmentClass = EClass(name: "Department")
        var employeeClass = EClass(name: "Employee")

        let nameAttr = EAttribute(name: "name", eType: EDataType(name: "EString", instanceClassName: "String"))
        departmentClass.eStructuralFeatures = [nameAttr]
        employeeClass.eStructuralFeatures = [nameAttr]

        // Create containment reference (employees are contained)
        let employeesRef = EReference(name: "employees", eType: employeeClass, upperBound: -1, containment: true)
        // Create non-containment reference (manager is a reference, not contained)
        let managerRef = EReference(name: "manager", eType: employeeClass, containment: false)
        // Create another non-containment reference with a name that might be mistaken for containment
        let supervisorRef = EReference(name: "supervisor", eType: employeeClass, containment: false)

        departmentClass.eStructuralFeatures.append(employeesRef)
        departmentClass.eStructuralFeatures.append(managerRef)
        departmentClass.eStructuralFeatures.append(supervisorRef)

        // Create objects
        var dept = DynamicEObject(eClass: departmentClass)
        dept.eSet("name", value: "Engineering")

        var emp1 = DynamicEObject(eClass: employeeClass)
        emp1.eSet("name", value: "Alice")

        var emp2 = DynamicEObject(eClass: employeeClass)
        emp2.eSet("name", value: "Bob")

        // Set up relationships
        dept.eSet("employees", value: [emp1.id, emp2.id])  // Containment
        dept.eSet("manager", value: emp1.id)  // Cross-reference to contained employee
        dept.eSet("supervisor", value: emp2.id)  // Another cross-reference

        // Add to resource
        let resource = Resource(uri: "test://metamodel-containment")
        _ = await resource.add(dept)
        _ = await resource.register(emp1)
        _ = await resource.register(emp2)

        // Serialize to XMI
        let serializer = XMISerializer()
        let xmiString = try await serializer.serialize(resource)

        // Verify containment is handled correctly (nested elements)
        #expect(xmiString.contains("<employees name=\"Alice\"/>"), "Alice should be serialised as nested element in employees")
        #expect(xmiString.contains("<employees name=\"Bob\"/>"), "Bob should be serialised as nested element in employees")

        // Verify cross-references use href attributes pointing to containment paths
        #expect(xmiString.contains("manager href=\"#//@employees.0\""), "Manager should reference Alice via containment path")
        #expect(xmiString.contains("supervisor href=\"#//@employees.1\""), "Supervisor should reference Bob via containment path")

        // Verify no hardcoded feature name logic - these should work regardless of names
        #expect(!xmiString.contains("<manager name=\"Alice\"/>"), "Manager should not be serialised as nested element")
        #expect(!xmiString.contains("<supervisor name=\"Bob\"/>"), "Supervisor should not be serialised as nested element")
    }

    @Test("Dynamic features order preservation: features without metamodel should maintain insertion order")
    func testDynamicFeaturesOrderPreservation() async throws {
        // Create object with minimal metamodel
        let simpleClass = EClass(name: "SimpleObject")
        var obj = DynamicEObject(eClass: simpleClass)

        // Set dynamic features in specific order (these don't have EStructuralFeature definitions)
        obj.eSet("dynamicProperty1", value: "first")
        obj.eSet("dynamicProperty2", value: 42)
        obj.eSet("dynamicProperty3", value: true)

        // Verify order is preserved
        let featureNames = obj.getFeatureNames()
        #expect(featureNames == ["dynamicProperty1", "dynamicProperty2", "dynamicProperty3"])

        // Verify values
        #expect(obj.eGet("dynamicProperty1") as? String == "first")
        #expect(obj.eGet("dynamicProperty2") as? Int == 42)
        #expect(obj.eGet("dynamicProperty3") as? Bool == true)

        // Add more features and verify order is maintained
        obj.eSet("dynamicProperty4", value: "fourth")
        let updatedFeatureNames = obj.getFeatureNames()
        #expect(updatedFeatureNames == ["dynamicProperty1", "dynamicProperty2", "dynamicProperty3", "dynamicProperty4"])
    }
}
