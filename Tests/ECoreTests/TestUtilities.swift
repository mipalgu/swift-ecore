//
// TestUtilities.swift
// ECore
//
// Created by Rene Hexel on 7/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation
import OrderedCollections
@testable import ECore

// MARK: - Shared Test Reference Model

/// Shared reference model implementation for tests to avoid duplication.
public struct SharedTestReferenceModel: IReferenceModel {
    public let rootPackage: EPackage
    public let resource: Resource
    public var isTarget: Bool = false
    
    public var referenceModel: IReferenceModel { self }

    public init(rootPackage: EPackage, resource: Resource) {
        self.rootPackage = rootPackage
        self.resource = resource
    }

    public func createElement(ofType metaElement: EClass) throws -> any EObject {
        throw ECoreExecutionError.readOnlyModel
    }

    public func getElementsByType(_ metaElement: EClass) async -> OrderedSet<EUUID> {
        return OrderedSet()  // Metamodels don't contain instance data
    }

    public func isModelOf(_ object: any EObject) async -> Bool {
        return false  // Metamodels don't contain instance data
    }

    public func getClassifier(_ name: String) -> (any EClassifier)? {
        return rootPackage.getClassifier(name)
    }

    public func getClassifiers(matching pattern: String) -> [any EClassifier] {
        return rootPackage.eClassifiers.filter { classifier in
            classifier.name.contains(pattern)
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rootPackage.name)
        hasher.combine(rootPackage.nsURI)
    }

    public static func == (lhs: SharedTestReferenceModel, rhs: SharedTestReferenceModel) -> Bool {
        return lhs.rootPackage.nsURI == rhs.rootPackage.nsURI
    }
}

// MARK: - Test Package Factory

/// Factory for creating consistent test packages across different test suites.
public struct TestPackageFactory {
    
    /// Creates a basic Person/Company test package.
    public static func createPersonCompanyPackage() -> EPackage {
        let stringType = EDataType(name: "EString")
        let intType = EDataType(name: "EInt")
        let doubleType = EDataType(name: "EDouble")
        
        // Person class
        let nameAttr = EAttribute(name: "name", eType: stringType, lowerBound: 1, upperBound: 1)
        let ageAttr = EAttribute(name: "age", eType: intType, lowerBound: 1, upperBound: 1)
        let salaryAttr = EAttribute(name: "salary", eType: doubleType, lowerBound: 0, upperBound: 1)
        
        let personClass = EClass(
            name: "Person",
            eStructuralFeatures: [nameAttr, ageAttr, salaryAttr]
        )

        // Company class
        let companyNameAttr = EAttribute(name: "name", eType: stringType, lowerBound: 1, upperBound: 1)
        let foundedAttr = EAttribute(name: "founded", eType: intType, lowerBound: 0, upperBound: 1)
        
        // Employee reference
        let employeesRef = EReference(
            name: "employees",
            eType: personClass,
            lowerBound: 0,
            upperBound: -1,
            containment: true
        )
        
        let companyClass = EClass(
            name: "Company",
            eStructuralFeatures: [companyNameAttr, foundedAttr, employeesRef]
        )

        let testPackage = EPackage(
            name: "testModel",
            nsURI: "http://test.example/testModel",
            nsPrefix: "test",
            eClassifiers: [personClass, companyClass]
        )

        return testPackage
    }
    
    /// Creates a simple Person-only package for basic tests.
    public static func createPersonPackage() -> EPackage {
        let stringType = EDataType(name: "EString")
        let intType = EDataType(name: "EInt")
        let doubleType = EDataType(name: "EDouble")
        
        // Person class
        let nameAttr = EAttribute(name: "name", eType: stringType, lowerBound: 1, upperBound: 1)
        let ageAttr = EAttribute(name: "age", eType: intType, lowerBound: 1, upperBound: 1)
        let salaryAttr = EAttribute(name: "salary", eType: doubleType, lowerBound: 0, upperBound: 1)
        
        let personClass = EClass(
            name: "Person",
            eStructuralFeatures: [nameAttr, ageAttr, salaryAttr]
        )

        let testPackage = EPackage(
            name: "personTest",
            nsURI: "http://test.example/personTest",
            nsPrefix: "pt",
            eClassifiers: [personClass]
        )

        return testPackage
    }
}

// MARK: - Test Object Factory

/// Factory for creating test objects consistently across test suites.
public struct TestObjectFactory {
    
    /// Creates a test person with the given attributes.
    public static func createTestPerson(
        name: String,
        age: Int,
        salary: Double? = nil,
        personClass: EClass
    ) throws -> DynamicEObject {
        var person = DynamicEObject(eClass: personClass)

        if let nameFeature = personClass.getStructuralFeature(name: "name") {
            person.eSet(nameFeature, name)
        }
        if let ageFeature = personClass.getStructuralFeature(name: "age") {
            person.eSet(ageFeature, age)
        }
        if let salary = salary, let salaryFeature = personClass.getStructuralFeature(name: "salary") {
            person.eSet(salaryFeature, salary)
        }

        return person
    }
    
    /// Creates a test company with the given attributes.
    public static func createTestCompany(
        name: String,
        founded: Int? = nil,
        companyClass: EClass
    ) throws -> DynamicEObject {
        var company = DynamicEObject(eClass: companyClass)

        if let nameFeature = companyClass.getStructuralFeature(name: "name") {
            company.eSet(nameFeature, name)
        }
        if let founded = founded, let foundedFeature = companyClass.getStructuralFeature(name: "founded") {
            company.eSet(foundedFeature, founded)
        }

        return company
    }
}

// MARK: - Test Environment Factory

/// Factory for creating complete test environments with resources, engines, and packages.
public struct TestEnvironmentFactory {
    
    /// Creates a complete test environment for execution tests.
    public static func createExecutionEnvironment(
        uri: String = "test://execution"
    ) async throws -> (Resource, Resource, ECoreExecutionEngine, EPackage) {
        let sourceResource = Resource(uri: "\(uri)/source")
        let targetResource = Resource(uri: "\(uri)/target")

        let testPackage = TestPackageFactory.createPersonCompanyPackage()
        let referenceModel = SharedTestReferenceModel(rootPackage: testPackage, resource: sourceResource)

        let sourceModel = EcoreModel(resource: sourceResource, referenceModel: referenceModel, isTarget: false)
        let targetModel = EcoreModel(resource: targetResource, referenceModel: referenceModel, isTarget: true)

        let executionEngine = ECoreExecutionEngine(
            models: ["source": sourceModel, "target": targetModel]
        )

        return (sourceResource, targetResource, executionEngine, testPackage)
    }
    
    /// Creates a simple test environment with a single resource.
    public static func createSimpleEnvironment(
        uri: String = "test://simple"
    ) async throws -> (Resource, ECoreExecutionEngine, EPackage) {
        let resource = Resource(uri: uri)
        let testPackage = TestPackageFactory.createPersonPackage()
        let referenceModel = SharedTestReferenceModel(rootPackage: testPackage, resource: resource)
        let model = EcoreModel(resource: resource, referenceModel: referenceModel, isTarget: false)
        let executionEngine = ECoreExecutionEngine(models: ["test": model])
        return (resource, executionEngine, testPackage)
    }
}