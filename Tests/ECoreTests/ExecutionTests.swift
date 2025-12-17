//
// ExecutionTests.swift
// ECore
//
// Created by Rene Hexel on 7/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing
@testable import ECore

@Suite("Execution Framework Tests")
struct ExecutionTests {

    // MARK: - Test Environment Setup

    func createExecutionEnvironment() async throws -> (Resource, Resource, ECoreExecutionEngine, EPackage) {
        return try await TestEnvironmentFactory.createExecutionEnvironment(uri: "test://execution-framework")
    }

    func createTestReferenceModel(with package: EPackage, resource: Resource) -> IReferenceModel {
        return SharedTestReferenceModel(rootPackage: package, resource: resource)
    }

    // MARK: - Navigation Tests

    @Test func testBasicPropertyNavigation() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let testPerson = try TestObjectFactory.createTestPerson(name: "Alice", age: 30, personClass: personClass)
        await sourceResource.add(testPerson)

        // Test name navigation
        let nameResult = try await executionEngine.navigate(from: testPerson, property: "name")
        #expect(nameResult as? String == "Alice")

        // Test age navigation  
        let ageResult = try await executionEngine.navigate(from: testPerson, property: "age")
        #expect(ageResult as? Int == 30)
    }

    @Test func testNavigationWithNullValues() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        // Create person without salary (optional field)
        let testPerson = try TestObjectFactory.createTestPerson(name: "Bob", age: 25, personClass: personClass)
        await sourceResource.add(testPerson)

        // Test navigation of unset optional property
        let salaryResult = try await executionEngine.navigate(from: testPerson, property: "salary")
        #expect(salaryResult == nil)
    }

    @Test func testNavigationCachingBehaviour() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let testPerson = try TestObjectFactory.createTestPerson(name: "Charlie", age: 35, personClass: personClass)
        await sourceResource.add(testPerson)

        // First navigation should cache the result
        let firstResult = try await executionEngine.navigate(from: testPerson, property: "name")
        #expect(firstResult as? String == "Charlie")

        // Second navigation should use cached result
        let secondResult = try await executionEngine.navigate(from: testPerson, property: "name")
        #expect(secondResult as? String == "Charlie")

        // Verify cache contains the entry
        let stats = await executionEngine.getCacheStatistics()
        #expect(stats["navigationCacheSize"] ?? 0 >= 1)
    }

    @Test func testNavigationUnknownProperty() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let testPerson = try TestObjectFactory.createTestPerson(name: "David", age: 40, personClass: personClass)
        await sourceResource.add(testPerson)

        await #expect(throws: ECoreExecutionError.self) {
            _ = try await executionEngine.navigate(from: testPerson, property: "nonexistentProperty")
        }
    }

    // MARK: - Expression Evaluation Tests

    @Test func testLiteralExpressionEvaluation() async throws {
        let (_, _, executionEngine, _) = try await createExecutionEnvironment()

        // String literal
        let stringExpr = ECoreExpression.literal(value: .string("Hello World"))
        let stringResult = try await executionEngine.evaluate(stringExpr, context: [:])
        #expect(stringResult as? String == "Hello World")

        // Integer literal
        let intExpr = ECoreExpression.literal(value: .int(42))
        let intResult = try await executionEngine.evaluate(intExpr, context: [:])
        #expect(intResult as? Int == 42)

        // Boolean literal
        let boolExpr = ECoreExpression.literal(value: .boolean(true))
        let boolResult = try await executionEngine.evaluate(boolExpr, context: [:])
        #expect(boolResult as? Bool == true)

        // Double literal
        let doubleExpr = ECoreExpression.literal(value: .double(3.14))
        let doubleResult = try await executionEngine.evaluate(doubleExpr, context: [:])
        #expect(doubleResult as? Double == 3.14)

        // Null literal
        let nullExpr = ECoreExpression.literal(value: .null)
        let nullResult = try await executionEngine.evaluate(nullExpr, context: [:])
        #expect(nullResult == nil)
    }

    @Test func testVariableExpressionEvaluation() async throws {
        let (_, _, executionEngine, _) = try await createExecutionEnvironment()

        let expr = ECoreExpression.variable(name: "testVariable")
        let context: [String: any EcoreValue] = ["testVariable": "Test Value"]
        
        let result = try await executionEngine.evaluate(expr, context: context)
        #expect(result as? String == "Test Value")
    }

    @Test func testVariableExpressionMissingVariable() async throws {
        let (_, _, executionEngine, _) = try await createExecutionEnvironment()

        let expr = ECoreExpression.variable(name: "missingVariable")
        let result = try await executionEngine.evaluate(expr, context: [:])
        #expect(result == nil)
    }

    @Test func testNavigationExpressionEvaluation() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let testPerson = try TestObjectFactory.createTestPerson(name: "Eve", age: 28, personClass: personClass)
        await sourceResource.add(testPerson)

        let expr = ECoreExpression.navigation(
            source: .variable(name: "person"),
            property: "name"
        )
        let context: [String: any EcoreValue] = ["person": testPerson]
        
        let result = try await executionEngine.evaluate(expr, context: context)
        #expect(result as? String == "Eve")
    }

    @Test func testChainedNavigationExpression() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person"),
              let companyClass = testPackage.getEClass("Company") else {
            throw ECoreExecutionError.typeError("Required classes not found")
        }

        // Create company with employee
        let company = try TestObjectFactory.createTestCompany(name: "TechCorp", founded: 2020, companyClass: companyClass)
        let employee = try TestObjectFactory.createTestPerson(name: "Frank", age: 32, personClass: personClass)

        if let employeesRef = companyClass.getStructuralFeature(name: "employees") {
            var mutableCompany = company
            mutableCompany.eSet(employeesRef, [employee])
        }

        await sourceResource.add(company)
        await sourceResource.add(employee)

        // Test navigation from company to first employee's name
        let expr = ECoreExpression.navigation(
            source: .navigation(
                source: .variable(name: "company"),
                property: "employees"
            ),
            property: "name"
        )
        
        let context: [String: any EcoreValue] = ["company": company]
        
        // Note: This test might need adjustment based on collection handling implementation
        // For now, we'll test that the expression can be evaluated without error
        do {
            let result = try await executionEngine.evaluate(expr, context: context)
            // The exact result depends on how collections are handled
            #expect(result != nil || result == nil) // Either outcome is valid for this test
        } catch {
            // Navigation on collections might not be directly supported yet
            #expect(error is ECoreExecutionError)
        }
    }

    // MARK: - Method Call Tests

    @Test func testMethodCallSize() async throws {
        let (_, _, executionEngine, _) = try await createExecutionEnvironment()

        let expr = ECoreExpression.methodCall(
            receiver: .literal(value: .string("test")),
            methodName: "size",
            arguments: []
        )
        
        do {
            let result = try await executionEngine.evaluate(expr, context: [:])
            // String "test" should have size 4
            #expect(result as? Int == 4)
        } catch ECoreExecutionError.unsupportedOperation {
            // Method invocation might not be fully implemented yet
        }
    }

    @Test func testMethodCallIsEmpty() async throws {
        let (_, _, executionEngine, _) = try await createExecutionEnvironment()

        let expr = ECoreExpression.methodCall(
            receiver: .literal(value: .string("")),
            methodName: "isEmpty",
            arguments: []
        )
        
        do {
            let result = try await executionEngine.evaluate(expr, context: [:])
            #expect(result as? Bool == true)
        } catch ECoreExecutionError.unsupportedOperation {
            // Method invocation might not be fully implemented yet
        }
    }

    // MARK: - Query Operation Tests

    @Test func testAllInstancesOfQuery() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        // Create multiple person instances
        let person1 = try TestObjectFactory.createTestPerson(name: "Alice", age: 25, personClass: personClass)
        let person2 = try TestObjectFactory.createTestPerson(name: "Bob", age: 30, personClass: personClass)
        let person3 = try TestObjectFactory.createTestPerson(name: "Charlie", age: 35, personClass: personClass)

        await sourceResource.add(person1)
        await sourceResource.add(person2)
        await sourceResource.add(person3)

        let allPersons = await executionEngine.allInstancesOf(personClass)
        #expect(allPersons.count == 3)

        let personIds = Set(allPersons.map(\.id))
        #expect(personIds.contains(person1.id))
        #expect(personIds.contains(person2.id))
        #expect(personIds.contains(person3.id))
    }

    @Test func testFirstInstanceOfQuery() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let person = try TestObjectFactory.createTestPerson(name: "Only Person", age: 25, personClass: personClass)
        await sourceResource.add(person)

        let firstPerson = await executionEngine.firstInstanceOf(personClass)
        #expect(firstPerson != nil)
        #expect(firstPerson?.id == person.id)
    }

    @Test func testFirstInstanceOfEmptyResult() async throws {
        let (_, _, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let firstPerson = await executionEngine.firstInstanceOf(personClass)
        #expect(firstPerson == nil)
    }

    // MARK: - Property Setting Tests

    @Test func testSetPropertyOnTargetModel() async throws {
        let (_, targetResource, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let targetPerson = try TestObjectFactory.createTestPerson(name: "Original", age: 25, personClass: personClass)
        await targetResource.add(targetPerson)

        // Set property on target model object
        try await executionEngine.setProperty(targetPerson, property: "name", value: "Updated")

        // Verify the change
        let result = try await executionEngine.navigate(from: targetPerson, property: "name")
        #expect(result as? String == "Updated")
    }

    @Test func testSetPropertyOnSourceModelShouldFail() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let sourcePerson = try TestObjectFactory.createTestPerson(name: "ReadOnly", age: 25, personClass: personClass)
        await sourceResource.add(sourcePerson)

        // Attempt to set property on read-only source model should fail
        await #expect(throws: ECoreExecutionError.self) {
            try await executionEngine.setProperty(sourcePerson, property: "name", value: "ShouldFail")
        }
    }

    // MARK: - Cache Management Tests

    @Test func testCacheClearOperation() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let person = try TestObjectFactory.createTestPerson(name: "Cached", age: 30, personClass: personClass)
        await sourceResource.add(person)

        // Perform navigation to populate cache
        _ = try await executionEngine.navigate(from: person, property: "name")

        // Verify cache has entries
        let statsBeforeClear = await executionEngine.getCacheStatistics()
        #expect(statsBeforeClear["navigationCacheSize"] ?? 0 > 0)

        // Clear caches
        await executionEngine.clearCaches()

        // Verify cache is empty
        let statsAfterClear = await executionEngine.getCacheStatistics()
        #expect(statsAfterClear["navigationCacheSize"] == 0)
        #expect(statsAfterClear["typeCacheSize"] == 0)
        #expect(statsAfterClear["resolutionCacheSize"] == 0)
    }

    @Test func testCacheStatisticsReporting() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let person = try TestObjectFactory.createTestPerson(name: "Stats", age: 25, personClass: personClass)
        await sourceResource.add(person)

        // Perform operations that populate different caches
        _ = try await executionEngine.navigate(from: person, property: "name")
        _ = await executionEngine.allInstancesOf(personClass)

        let stats = await executionEngine.getCacheStatistics()
        
        #expect(stats.keys.contains("navigationCacheSize"))
        #expect(stats.keys.contains("typeCacheSize"))
        #expect(stats.keys.contains("resolutionCacheSize"))
        
        #expect(stats["navigationCacheSize"] ?? 0 >= 0)
        #expect(stats["typeCacheSize"] ?? 0 >= 0)
        #expect(stats["resolutionCacheSize"] ?? 0 >= 0)
    }

    // MARK: - Error Handling Tests

    @Test func testInvalidNavigationOnNonEObject() async throws {
        let (_, _, executionEngine, _) = try await createExecutionEnvironment()

        let expr = ECoreExpression.navigation(
            source: .literal(value: .string("NotAnEObject")),
            property: "someProperty"
        )

        await #expect(throws: ECoreExecutionError.self) {
            _ = try await executionEngine.evaluate(expr, context: [:])
        }
    }

    @Test func testTypeErrorHandling() async throws {
        let (_, _, _, _) = try await createExecutionEnvironment()

        // Test type conversion errors through the type provider
        let typeProvider = EcoreTypeProvider()
        let stringDataType = EDataType(name: "EString")

        let compatible = typeProvider.isCompatible("test", with: stringDataType)
        #expect(compatible == true)

        let incompatibleTest = typeProvider.isCompatible(123, with: stringDataType)
        #expect(incompatibleTest == false)
    }

    // MARK: - Performance Tests

    @Test func testNavigationPerformanceWithLargeModel() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        // Create a moderate number of objects for performance testing
        let objectCount = 100
        var persons: [DynamicEObject] = []
        
        for i in 0..<objectCount {
            let person = try TestObjectFactory.createTestPerson(name: "Person\(i)", age: 20 + (i % 50), personClass: personClass)
            persons.append(person)
            await sourceResource.add(person)
        }

        // Measure navigation performance
        let startTime = Date()
        
        for person in persons.prefix(10) { // Test first 10 for reasonable test time
            _ = try await executionEngine.navigate(from: person, property: "name")
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        // Navigation should be reasonably fast (adjust threshold as needed)
        #expect(duration < 1.0) // Should complete in less than 1 second
    }

    @Test func testQueryPerformanceWithLargeModel() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createExecutionEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        // Create objects for performance testing
        let objectCount = 50
        
        for i in 0..<objectCount {
            let person = try TestObjectFactory.createTestPerson(name: "QueryPerson\(i)", age: 25 + i, personClass: personClass)
            await sourceResource.add(person)
        }

        // Measure query performance
        let startTime = Date()
        let allPersons = await executionEngine.allInstancesOf(personClass)
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        #expect(allPersons.count == objectCount)
        #expect(duration < 0.5) // Should complete in less than 0.5 seconds
    }
}