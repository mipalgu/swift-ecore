//
// InMemoryModelTests.swift
// ECore
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing
@testable import ECore
import Foundation

/// Phase 3: In-Memory Model Testing
///
/// These tests verify that models can be created programmatically and work correctly
/// without serialization. They test the core metamodel patterns from EMF.
@Suite("In-Memory Model Tests")
struct InMemoryModelTests {

    // MARK: - Step 3.3: Containment References (BinTree)

    /// Tests binary tree structure with containment references.
    ///
    /// This test implements the BinTree.ecore pattern where a BinTreeNode
    /// contains left and right child nodes through containment references.
    @Test func testBinTreeContainment() async throws {
        let resource = Resource(uri: "test://bintree.xmi")

        // Create BinTreeNode metamodel
        var nodeClass = EClass(name: "BinTreeNode")
        let valueAttr = EAttribute(name: "value", eType: EDataType(name: "EInt"))
        let leftRef = EReference(name: "left", eType: nodeClass, containment: true)
        let rightRef = EReference(name: "right", eType: nodeClass, containment: true)

        nodeClass.eStructuralFeatures = [valueAttr, leftRef, rightRef]

        // Create tree structure: root(5) with left(3) and right(7)
        let root = DynamicEObject(eClass: nodeClass)
        let leftNode = DynamicEObject(eClass: nodeClass)
        let rightNode = DynamicEObject(eClass: nodeClass)

        // Add to resource first
        await resource.add(root)
        await resource.add(leftNode)
        await resource.add(rightNode)

        // Set values and containment references using Resource API
        await resource.eSet(objectId: root.id, feature: "value", value: 5)
        await resource.eSet(objectId: leftNode.id, feature: "value", value: 3)
        await resource.eSet(objectId: rightNode.id, feature: "value", value: 7)
        await resource.eSet(objectId: root.id, feature: "left", value: leftNode.id)
        await resource.eSet(objectId: root.id, feature: "right", value: rightNode.id)

        // Verify containment structure
        #expect(leftRef.containment == true)
        #expect(rightRef.containment == true)

        let rootLeftId = await resource.eGet(objectId: root.id, feature: "left") as? EUUID
        let rootRightId = await resource.eGet(objectId: root.id, feature: "right") as? EUUID

        #expect(rootLeftId == leftNode.id)
        #expect(rootRightId == rightNode.id)

        // Verify values
        let leftValue = await resource.eGet(objectId: leftNode.id, feature: "value") as? Int
        let rightValue = await resource.eGet(objectId: rightNode.id, feature: "value") as? Int
        let rootValue = await resource.eGet(objectId: root.id, feature: "value") as? Int

        #expect(leftValue == 3)
        #expect(rightValue == 7)
        #expect(rootValue == 5)

        // Verify root object count (only root, children are contained)
        let roots = await resource.getRootObjects()
        #expect(roots.count == 1)
        #expect(roots.first?.id == root.id)
    }

    /// Tests deeper binary tree with multiple levels of containment.
    @Test func testBinTreeDeepContainment() async throws {
        let resource = Resource(uri: "test://bintree-deep.xmi")

        // Create BinTreeNode metamodel
        var nodeClass = EClass(name: "BinTreeNode")
        let valueAttr = EAttribute(name: "value", eType: EDataType(name: "EInt"))
        let leftRef = EReference(name: "left", eType: nodeClass, containment: true)
        let rightRef = EReference(name: "right", eType: nodeClass, containment: true)

        nodeClass.eStructuralFeatures = [valueAttr, leftRef, rightRef]

        // Create tree:
        //       5
        //      / \
        //     3   7
        //    /   / \
        //   1   6   9

        let root = DynamicEObject(eClass: nodeClass)
        let node3 = DynamicEObject(eClass: nodeClass)
        let node7 = DynamicEObject(eClass: nodeClass)
        let node1 = DynamicEObject(eClass: nodeClass)
        let node6 = DynamicEObject(eClass: nodeClass)
        let node9 = DynamicEObject(eClass: nodeClass)

        // Add all nodes to resource
        await resource.add(root)
        await resource.add(node3)
        await resource.add(node7)
        await resource.add(node1)
        await resource.add(node6)
        await resource.add(node9)

        // Set values
        await resource.eSet(objectId: root.id, feature: "value", value: 5)
        await resource.eSet(objectId: node3.id, feature: "value", value: 3)
        await resource.eSet(objectId: node7.id, feature: "value", value: 7)
        await resource.eSet(objectId: node1.id, feature: "value", value: 1)
        await resource.eSet(objectId: node6.id, feature: "value", value: 6)
        await resource.eSet(objectId: node9.id, feature: "value", value: 9)

        // Build tree structure
        await resource.eSet(objectId: root.id, feature: "left", value: node3.id)
        await resource.eSet(objectId: root.id, feature: "right", value: node7.id)
        await resource.eSet(objectId: node3.id, feature: "left", value: node1.id)
        await resource.eSet(objectId: node7.id, feature: "left", value: node6.id)
        await resource.eSet(objectId: node7.id, feature: "right", value: node9.id)

        // Verify only root is a root object
        let roots = await resource.getRootObjects()
        #expect(roots.count == 1)
        #expect(roots.first?.id == root.id)

        // Verify all nodes can be resolved
        #expect(await resource.resolve(root.id) != nil)
        #expect(await resource.resolve(node3.id) != nil)
        #expect(await resource.resolve(node7.id) != nil)
        #expect(await resource.resolve(node1.id) != nil)
        #expect(await resource.resolve(node6.id) != nil)
        #expect(await resource.resolve(node9.id) != nil)
    }

    // MARK: - Step 3.4: Cross-References (Company Model)

    /// Tests non-containment cross-references using Company model.
    ///
    /// This test implements the Company.ecore pattern where a Department
    /// has a non-containment reference to a manager Employee.
    @Test func testCompanyCrossReferences() async throws {
        let resource = Resource(uri: "test://company.xmi")

        // Create Company metamodel
        var companyClass = EClass(name: "Company")
        var departmentClass = EClass(name: "Department")
        var employeeClass = EClass(name: "Employee")

        // Company attributes
        let companyNameAttr = EAttribute(name: "name", eType: EDataType(name: "EString"))
        let departmentsRef = EReference(name: "departments", eType: departmentClass, upperBound: -1, containment: true)
        companyClass.eStructuralFeatures = [companyNameAttr, departmentsRef]

        // Employee attributes
        let employeeNameAttr = EAttribute(name: "name", eType: EDataType(name: "EString"))
        let employeeSalaryAttr = EAttribute(name: "salary", eType: EDataType(name: "EInt"))
        employeeClass.eStructuralFeatures = [employeeNameAttr, employeeSalaryAttr]

        // Department attributes and references
        let deptNameAttr = EAttribute(name: "name", eType: EDataType(name: "EString"))
        let employeesRef = EReference(name: "employees", eType: employeeClass, upperBound: -1, containment: true)
        let managerRef = EReference(name: "manager", eType: employeeClass, lowerBound: 1) // Non-containment cross-reference
        departmentClass.eStructuralFeatures = [deptNameAttr, employeesRef, managerRef]

        // Create model instances
        let company = DynamicEObject(eClass: companyClass)
        let engineering = DynamicEObject(eClass: departmentClass)
        let sales = DynamicEObject(eClass: departmentClass)
        let alice = DynamicEObject(eClass: employeeClass)
        let bob = DynamicEObject(eClass: employeeClass)
        let charlie = DynamicEObject(eClass: employeeClass)
        let diana = DynamicEObject(eClass: employeeClass)

        // Add to resource
        await resource.add(company)
        await resource.add(engineering)
        await resource.add(sales)
        await resource.add(alice)
        await resource.add(bob)
        await resource.add(charlie)
        await resource.add(diana)

        // Set attributes
        await resource.eSet(objectId: company.id, feature: "name", value: "TechCorp")
        await resource.eSet(objectId: engineering.id, feature: "name", value: "Engineering")
        await resource.eSet(objectId: sales.id, feature: "name", value: "Sales")
        await resource.eSet(objectId: alice.id, feature: "name", value: "Alice")
        await resource.eSet(objectId: alice.id, feature: "salary", value: 100000)
        await resource.eSet(objectId: bob.id, feature: "name", value: "Bob")
        await resource.eSet(objectId: bob.id, feature: "salary", value: 90000)
        await resource.eSet(objectId: charlie.id, feature: "name", value: "Charlie")
        await resource.eSet(objectId: charlie.id, feature: "salary", value: 85000)
        await resource.eSet(objectId: diana.id, feature: "name", value: "Diana")
        await resource.eSet(objectId: diana.id, feature: "salary", value: 95000)

        // Build containment hierarchy
        await resource.eSet(objectId: company.id, feature: "departments", value: [engineering.id, sales.id])
        await resource.eSet(objectId: engineering.id, feature: "employees", value: [alice.id, bob.id])
        await resource.eSet(objectId: sales.id, feature: "employees", value: [charlie.id, diana.id])

        // Set cross-references (non-containment)
        await resource.eSet(objectId: engineering.id, feature: "manager", value: alice.id)
        await resource.eSet(objectId: sales.id, feature: "manager", value: diana.id)

        // Verify cross-references
        #expect(managerRef.containment == false)
        #expect(managerRef.isRequired == true)

        let engManagerId = await resource.eGet(objectId: engineering.id, feature: "manager") as? EUUID
        let salesManagerId = await resource.eGet(objectId: sales.id, feature: "manager") as? EUUID

        #expect(engManagerId == alice.id)
        #expect(salesManagerId == diana.id)

        // Verify that managers are also in the employees list (cross-reference, not duplicate)
        let engEmployees = await resource.eGet(objectId: engineering.id, feature: "employees") as? [EUUID]
        let salesEmployees = await resource.eGet(objectId: sales.id, feature: "employees") as? [EUUID]

        #expect(engEmployees?.contains(alice.id) == true)
        #expect(salesEmployees?.contains(diana.id) == true)

        // Verify only company is root
        let roots = await resource.getRootObjects()
        #expect(roots.count == 1)
        #expect(roots.first?.id == company.id)
    }

    /// Tests cross-references with multiple departments sharing employees.
    @Test func testCompanySharedReferences() async throws {
        let resource = Resource(uri: "test://company-shared.xmi")

        // Create simplified metamodel
        var departmentClass = EClass(name: "Department")
        var employeeClass = EClass(name: "Employee")

        let deptNameAttr = EAttribute(name: "name", eType: EDataType(name: "EString"))
        let employeesRef = EReference(name: "employees", eType: employeeClass, upperBound: -1, containment: true)
        let managerRef = EReference(name: "manager", eType: employeeClass) // Cross-reference
        let consultantsRef = EReference(name: "consultants", eType: employeeClass, upperBound: -1) // Cross-references
        departmentClass.eStructuralFeatures = [deptNameAttr, employeesRef, managerRef, consultantsRef]

        let empNameAttr = EAttribute(name: "name", eType: EDataType(name: "EString"))
        employeeClass.eStructuralFeatures = [empNameAttr]

        // Create instances
        let engineering = DynamicEObject(eClass: departmentClass)
        let research = DynamicEObject(eClass: departmentClass)
        let alice = DynamicEObject(eClass: employeeClass)
        let bob = DynamicEObject(eClass: employeeClass)
        let charlie = DynamicEObject(eClass: employeeClass)

        await resource.add(engineering)
        await resource.add(research)
        await resource.add(alice)
        await resource.add(bob)
        await resource.add(charlie)

        // Set attributes
        await resource.eSet(objectId: engineering.id, feature: "name", value: "Engineering")
        await resource.eSet(objectId: research.id, feature: "name", value: "Research")
        await resource.eSet(objectId: alice.id, feature: "name", value: "Alice")
        await resource.eSet(objectId: bob.id, feature: "name", value: "Bob")
        await resource.eSet(objectId: charlie.id, feature: "name", value: "Charlie")

        // Engineering contains Alice and Bob
        await resource.eSet(objectId: engineering.id, feature: "employees", value: [alice.id, bob.id])
        await resource.eSet(objectId: engineering.id, feature: "manager", value: alice.id)

        // Research contains only Charlie but has Bob as consultant (cross-reference)
        await resource.eSet(objectId: research.id, feature: "employees", value: [charlie.id])
        await resource.eSet(objectId: research.id, feature: "manager", value: charlie.id)
        await resource.eSet(objectId: research.id, feature: "consultants", value: [alice.id, bob.id])

        // Verify consultants are cross-references
        #expect(consultantsRef.containment == false)
        let consultants = await resource.eGet(objectId: research.id, feature: "consultants") as? [EUUID]
        #expect(consultants?.count == 2)
        #expect(consultants?.contains(alice.id) == true)
        #expect(consultants?.contains(bob.id) == true)
    }

    // MARK: - Combined Model Test

    /// Tests a comprehensive model combining containment, cross-references, and enums.
    @Test func testCompleteInMemoryModel() async throws {
        let resource = Resource(uri: "test://complete-model.xmi")

        // Create enumeration for employee status
        let activeStatus = EEnumLiteral(name: "Active", value: 0)
        let inactiveStatus = EEnumLiteral(name: "Inactive", value: 1)
        let onLeaveStatus = EEnumLiteral(name: "OnLeave", value: 2)
        let statusEnum = EEnum(name: "EmployeeStatus", literals: [activeStatus, inactiveStatus, onLeaveStatus])

        // Create Organization metamodel
        var orgClass = EClass(name: "Organization")
        var deptClass = EClass(name: "Department")
        var personClass = EClass(name: "Person")

        // Organization structure
        let orgNameAttr = EAttribute(name: "name", eType: EDataType(name: "EString"))
        let deptsRef = EReference(name: "departments", eType: deptClass, upperBound: -1, containment: true)
        orgClass.eStructuralFeatures = [orgNameAttr, deptsRef]

        // Department structure
        let deptNameAttr = EAttribute(name: "name", eType: EDataType(name: "EString"))
        let membersRef = EReference(name: "members", eType: personClass, upperBound: -1, containment: true)
        let headRef = EReference(name: "head", eType: personClass) // Cross-reference
        deptClass.eStructuralFeatures = [deptNameAttr, membersRef, headRef]

        // Person structure with enum
        let personNameAttr = EAttribute(name: "name", eType: EDataType(name: "EString"))
        let statusAttr = EAttribute(name: "status", eType: statusEnum)
        personClass.eStructuralFeatures = [personNameAttr, statusAttr]

        // Create model instance
        let org = DynamicEObject(eClass: orgClass)
        let engineering = DynamicEObject(eClass: deptClass)
        let hr = DynamicEObject(eClass: deptClass)
        let alice = DynamicEObject(eClass: personClass)
        let bob = DynamicEObject(eClass: personClass)
        let carol = DynamicEObject(eClass: personClass)

        await resource.add(org)
        await resource.add(engineering)
        await resource.add(hr)
        await resource.add(alice)
        await resource.add(bob)
        await resource.add(carol)

        // Set attributes
        await resource.eSet(objectId: org.id, feature: "name", value: "ACME Corp")
        await resource.eSet(objectId: engineering.id, feature: "name", value: "Engineering")
        await resource.eSet(objectId: hr.id, feature: "name", value: "Human Resources")
        await resource.eSet(objectId: alice.id, feature: "name", value: "Alice")
        await resource.eSet(objectId: alice.id, feature: "status", value: 0)
        await resource.eSet(objectId: bob.id, feature: "name", value: "Bob")
        await resource.eSet(objectId: bob.id, feature: "status", value: 2)
        await resource.eSet(objectId: carol.id, feature: "name", value: "Carol")
        await resource.eSet(objectId: carol.id, feature: "status", value: 0)

        // Build model
        await resource.eSet(objectId: org.id, feature: "departments", value: [engineering.id, hr.id])
        await resource.eSet(objectId: engineering.id, feature: "members", value: [alice.id, bob.id])
        await resource.eSet(objectId: engineering.id, feature: "head", value: alice.id)
        await resource.eSet(objectId: hr.id, feature: "members", value: [carol.id])
        await resource.eSet(objectId: hr.id, feature: "head", value: carol.id)

        // Verify complete model structure
        let roots = await resource.getRootObjects()
        #expect(roots.count == 1)

        // Verify enum usage
        let aliceStatus = await resource.eGet(objectId: alice.id, feature: "status") as? Int
        let bobStatus = await resource.eGet(objectId: bob.id, feature: "status") as? Int
        #expect(aliceStatus == 0) // Active
        #expect(bobStatus == 2) // OnLeave

        // Verify containment vs cross-reference
        #expect(deptsRef.containment == true)
        #expect(membersRef.containment == true)
        #expect(headRef.containment == false)

        // Verify cross-references work
        let engHead = await resource.eGet(objectId: engineering.id, feature: "head") as? EUUID
        let hrHead = await resource.eGet(objectId: hr.id, feature: "head") as? EUUID
        #expect(engHead == alice.id)
        #expect(hrHead == carol.id)
    }
}
