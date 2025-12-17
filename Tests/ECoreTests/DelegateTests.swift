//
// DelegateTests.swift
// ECore
//
// Created by Rene Hexel on 7/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing
@testable import ECore

@Suite("Delegate Framework Tests", .serialized)
struct DelegateTests {

    // MARK: - Helper Methods

    func createTestEnvironment() async throws -> (Resource, ECoreExecutionEngine, EPackage) {
        return try await TestEnvironmentFactory.createSimpleEnvironment(uri: "test://delegate")
    }



    // MARK: - Delegate Registry Tests

    @Test func testRegistryInitialisation() async {
        let registry = ECoreDelegateRegistry.shared
        let stats = await registry.getStatistics()
        
        // Registry should exist and have zero delegates initially for this test
        #expect(stats["operationDelegates"] != nil)
        #expect(stats["validationDelegates"] != nil)
        #expect(stats["settingDelegates"] != nil)
    }

    @Test func testOperationDelegateRegistration() async throws {
        let testDelegate = MockOperationDelegate()
        let testURI = "http://test.example/operations"
        
        try await withCleanRegistry(uri: testURI) { registry in
            await registry.register(operationDelegate: testDelegate, forURI: testURI)
            
            let retrievedDelegate = await registry.getOperationDelegate(forURI: testURI)
            #expect(retrievedDelegate != nil)
        }
    }

    @Test func testValidationDelegateRegistration() async throws {
        let testDelegate = MockValidationDelegate()
        let testURI = "http://test.example/validation"
        
        try await withCleanRegistry(uri: testURI) { registry in
            await registry.register(validationDelegate: testDelegate, forURI: testURI)
            
            let retrievedDelegate = await registry.getValidationDelegate(forURI: testURI)
            #expect(retrievedDelegate != nil)
        }
    }

    @Test func testSettingDelegateRegistration() async throws {
        let testDelegate = MockSettingDelegate()
        let testURI = "http://test.example/setting"
        
        try await withCleanRegistry(uri: testURI) { registry in
            await registry.register(settingDelegate: testDelegate, forURI: testURI)
            
            let retrievedDelegate = await registry.getSettingDelegate(forURI: testURI)
            #expect(retrievedDelegate != nil)
        }
    }

    @Test func testDelegateNotFound() async {
        let registry = ECoreDelegateRegistry.shared
        let nonExistentURI = "http://nonexistent.example/test"
        
        let operationDelegate = await registry.getOperationDelegate(forURI: nonExistentURI)
        let validationDelegate = await registry.getValidationDelegate(forURI: nonExistentURI)
        let settingDelegate = await registry.getSettingDelegate(forURI: nonExistentURI)
        
        #expect(operationDelegate == nil)
        #expect(validationDelegate == nil)
        #expect(settingDelegate == nil)
    }

    @Test func testClearDelegates() async throws {
        let testURI = "http://test.example/clear"
        
        try await withCleanRegistry(uri: testURI) { registry in
            // Register delegates
            await registry.register(operationDelegate: MockOperationDelegate(), forURI: testURI)
            await registry.register(validationDelegate: MockValidationDelegate(), forURI: testURI)
            await registry.register(settingDelegate: MockSettingDelegate(), forURI: testURI)
            
            // Verify registration
            #expect(await registry.getOperationDelegate(forURI: testURI) != nil)
            #expect(await registry.getValidationDelegate(forURI: testURI) != nil)
            #expect(await registry.getSettingDelegate(forURI: testURI) != nil)
            
            // Clear delegates
            await registry.clearDelegates(forURI: testURI)
            
            // Verify clearing
            #expect(await registry.getOperationDelegate(forURI: testURI) == nil)
            #expect(await registry.getValidationDelegate(forURI: testURI) == nil)
            #expect(await registry.getSettingDelegate(forURI: testURI) == nil)
        }
    }

    @Test func testGetRegisteredURIs() async {
        let registry = ECoreDelegateRegistry.shared
        let uri1 = "http://test.example/uris1"
        let uri2 = "http://test.example/uris2"
        
        // Register delegates for different URIs
        await registry.register(operationDelegate: MockOperationDelegate(), forURI: uri1)
        await registry.register(validationDelegate: MockValidationDelegate(), forURI: uri2)
        
        let registeredURIs = await registry.getRegisteredURIs()
        #expect(registeredURIs.contains(uri1))
        #expect(registeredURIs.contains(uri2))
        
        // Clean up
        await registry.clearDelegates(forURI: uri1)
        await registry.clearDelegates(forURI: uri2)
    }

    @Test func testRegistryStatistics() async throws {
        let testURI = "http://test.example/stats"
        
        try await withCleanRegistry(uri: testURI) { registry in
            // Register multiple types of delegates
            await registry.register(operationDelegate: MockOperationDelegate(), forURI: testURI)
            await registry.register(validationDelegate: MockValidationDelegate(), forURI: testURI)
            await registry.register(settingDelegate: MockSettingDelegate(), forURI: testURI)
            
            let stats = await registry.getStatistics()
            #expect(stats["operationDelegates"] ?? 0 >= 1)
            #expect(stats["validationDelegates"] ?? 0 >= 1)
            #expect(stats["settingDelegates"] ?? 0 >= 1)
            #expect(stats["totalURIs"] ?? 0 >= 1)
        }
    }

    // MARK: - Validation Error Tests

    @Test func testValidationErrorCreation() {
        let objectId = EUUID()
        let error = ECoreValidationError(
            message: "Test validation error",
            objectId: objectId,
            feature: "name",
            severity: .error
        )
        
        #expect(error.message == "Test validation error")
        #expect(error.objectId == objectId)
        #expect(error.feature == "name")
        #expect(error.severity == .error)
    }

    @Test func testValidationErrorSeverities() {
        let objectId = EUUID()
        
        let errorSeverity = ECoreValidationError(message: "Error", objectId: objectId, severity: .error)
        let warningSeverity = ECoreValidationError(message: "Warning", objectId: objectId, severity: .warning)
        let infoSeverity = ECoreValidationError(message: "Info", objectId: objectId, severity: .info)
        
        #expect(errorSeverity.severity == .error)
        #expect(warningSeverity.severity == .warning)
        #expect(infoSeverity.severity == .info)
    }

    @Test func testValidationErrorDescription() {
        let objectId = EUUID()
        let error = ECoreValidationError(
            message: "Test error",
            objectId: objectId,
            feature: "age",
            severity: .warning
        )
        
        let description = error.description
        #expect(description.contains("Test error"))
        #expect(description.contains("warning"))
        #expect(description.contains("age"))
        #expect(description.contains(objectId.uuidString))
    }

    @Test func testValidationErrorEquality() {
        let objectId = EUUID()
        let error1 = ECoreValidationError(message: "Test", objectId: objectId, severity: .error)
        let error2 = ECoreValidationError(message: "Test", objectId: objectId, severity: .error)
        let error3 = ECoreValidationError(message: "Different", objectId: objectId, severity: .error)
        
        #expect(error1 == error2)
        #expect(error1 != error3)
    }

    // MARK: - Operation Info Tests

    @Test func testEOperationInfoCreation() {
        let param1 = EParameterInfo(name: "param1", eTypeName: "EString")
        let param2 = EParameterInfo(name: "param2", eTypeName: "EInt", lowerBound: 0, upperBound: 1)
        
        let operation = EOperationInfo(
            name: "testOperation",
            parameters: [param1, param2],
            returnTypeName: "EBoolean"
        )
        
        #expect(operation.name == "testOperation")
        #expect(operation.parameters.count == 2)
        #expect(operation.returnTypeName == "EBoolean")
        #expect(operation.parameters[0].name == "param1")
        #expect(operation.parameters[1].lowerBound == 0)
    }

    @Test func testEParameterInfoEquality() {
        let param1 = EParameterInfo(name: "test", eTypeName: "EString", lowerBound: 1, upperBound: 1)
        let param2 = EParameterInfo(name: "test", eTypeName: "EString", lowerBound: 1, upperBound: 1)
        let param3 = EParameterInfo(name: "different", eTypeName: "EString", lowerBound: 1, upperBound: 1)
        
        #expect(param1 == param2)
        #expect(param1 != param3)
    }

    // MARK: - Mock Delegate Behavior Tests

    @Test func testMockOperationDelegate() async throws {
        let (resource, _, testPackage) = try await createTestEnvironment()
        
        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }
        
        let person = try TestObjectFactory.createTestPerson(name: "Alice", age: 30, personClass: personClass)
        await resource.add(person)
        
        let delegate = MockOperationDelegate()
        let operation = EOperationInfo(name: "getFullName", returnTypeName: "EString")
        
        let result = try await delegate.invoke(operation: operation, on: person, arguments: [])
        #expect(result as? String == "Mock operation result for getFullName")
    }

    @Test func testMockValidationDelegate() async throws {
        let (resource, _, testPackage) = try await createTestEnvironment()
        
        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }
        
        let person = try TestObjectFactory.createTestPerson(name: "Bob", age: -5, personClass: personClass) // Invalid age
        await resource.add(person)
        
        let delegate = MockValidationDelegate()
        let errors = try await delegate.validate(person)
        
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("Age cannot be negative"))
        #expect(errors[0].severity == .error)
    }

    @Test func testMockSettingDelegate() async throws {
        let (resource, _, testPackage) = try await createTestEnvironment()
        
        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }
        
        let person = try TestObjectFactory.createTestPerson(name: "Charlie", age: 25, personClass: personClass)
        await resource.add(person)
        
        let delegate = MockSettingDelegate()
        
        if let nameFeature = personClass.getStructuralFeature(name: "name") {
            let result = try await delegate.getValue(for: nameFeature, from: person)
            #expect(result as? String == "Derived value for name")
        } else {
            Issue.record("Name feature not found")
        }
    }

    // MARK: - Integration Tests

    @Test func testDelegateRegistryIntegration() async throws {
        let testURI = "http://test.example/integration"
        let (resource, _, testPackage) = try await createTestEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        try await withCleanRegistry(uri: testURI) { registry in
            // Register delegates
            await registry.register(operationDelegate: MockOperationDelegate(), forURI: testURI)
            await registry.register(validationDelegate: MockValidationDelegate(), forURI: testURI)
            await registry.register(settingDelegate: MockSettingDelegate(), forURI: testURI)
            
            // Create test object
            let person = try TestObjectFactory.createTestPerson(name: "Integration", age: 40, personClass: personClass)
            await resource.add(person)
            
            // Test operation delegate
            if let operationDelegate = await registry.getOperationDelegate(forURI: testURI) {
                let operation = EOperationInfo(name: "testOp")
                let result = try await operationDelegate.invoke(operation: operation, on: person, arguments: [])
                #expect(result as? String == "Mock operation result for testOp")
            } else {
                Issue.record("Operation delegate not found")
            }
            
            // Test validation delegate
            if let validationDelegate = await registry.getValidationDelegate(forURI: testURI) {
                let errors = try await validationDelegate.validate(person)
                // Should be valid (age is positive)
                #expect(errors.isEmpty)
            } else {
                Issue.record("Validation delegate not found")
            }
            
            // Test setting delegate
            if let settingDelegate = await registry.getSettingDelegate(forURI: testURI) {
                if let nameFeature = personClass.getStructuralFeature(name: "name") {
                    let result = try await settingDelegate.getValue(for: nameFeature, from: person)
                    #expect(result as? String == "Derived value for name")
                } else {
                    Issue.record("Name feature not found")
                }
            } else {
                Issue.record("Setting delegate not found")
            }
        }
    }

    @Test func testClearAllDelegates() async {
        let registry = ECoreDelegateRegistry.shared
        
        // Register some delegates
        await registry.register(operationDelegate: MockOperationDelegate(), forURI: "http://test1.example/clear")
        await registry.register(validationDelegate: MockValidationDelegate(), forURI: "http://test2.example/clear")
        
        let statsBefore = await registry.getStatistics()
        #expect(statsBefore["totalURIs"] ?? 0 > 0)
        
        // Clear all
        await registry.clearAll()
        
        let statsAfter = await registry.getStatistics()
        #expect(statsAfter["operationDelegates"] ?? -1 == 0)
        #expect(statsAfter["validationDelegates"] ?? -1 == 0)
        #expect(statsAfter["settingDelegates"] ?? -1 == 0)
        #expect(statsAfter["totalURIs"] ?? -1 == 0)
    }
}

// MARK: - Mock Delegate Implementations

struct MockOperationDelegate: ECoreOperationDelegate {
    func invoke(operation: EOperationInfo, 
               on object: any EObject, 
               arguments: [Any?]) async throws -> Any? {
        // Simple mock implementation
        return "Mock operation result for \(operation.name)"
    }
}

struct MockValidationDelegate: ECoreValidationDelegate {
    func validate(_ object: any EObject) async throws -> [ECoreValidationError] {
        var errors: [ECoreValidationError] = []
        
        // Example validation: check if age is negative
        if let eClass = object.eClass as? EClass,
           let ageFeature = eClass.getStructuralFeature(name: "age") as? EAttribute {
            if let age = object.eGet(ageFeature) as? Int, age < 0 {
                errors.append(ECoreValidationError(
                    message: "Age cannot be negative",
                    objectId: object.id,
                    feature: "age",
                    severity: .error
                ))
            }
        }
        
        return errors
    }
}

struct MockSettingDelegate: ECoreSettingDelegate {
    func getValue(for feature: any EStructuralFeature,
                 from object: any EObject) async throws -> Any? {
        // Simple mock implementation
        return "Derived value for \(feature.name)"
    }
}

// MARK: - Helper Functions

/// Helper function to run tests with clean registry state
func withCleanRegistry(uri: String, operation: (ECoreDelegateRegistry) async throws -> Void) async throws {
    let registry = ECoreDelegateRegistry.shared
    
    // Clean up before test
    await registry.clearDelegates(forURI: uri)
    
    // Run test
    try await operation(registry)
    
    // Clean up after test
    await registry.clearDelegates(forURI: uri)
}

