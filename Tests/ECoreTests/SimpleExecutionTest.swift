//
// SimpleExecutionTest.swift
// ECore
//
// Created by Rene Hexel on 7/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore

@Suite("Simple Execution Tests")
struct SimpleExecutionTests {

    // MARK: - Helper Methods

    func createTestEnvironment() async throws -> (Resource, Resource, ECoreExecutionEngine, EPackage) {
        return try await TestEnvironmentFactory.createExecutionEnvironment(uri: "test://simple-execution")
    }

    // MARK: - Navigation Tests

    @Test func testBasicNavigation() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createTestEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        // Create test object
        let testObject = try TestObjectFactory.createTestPerson(name: "John", age: 30, personClass: personClass)
        await sourceResource.add(testObject)

        // Test property navigation
        let nameResult = try await executionEngine.navigate(from: testObject, property: "name")
        #expect(nameResult as? String == "John")

        let ageResult = try await executionEngine.navigate(from: testObject, property: "age")
        #expect(ageResult as? Int == 30)
    }

    @Test func testNavigationCaching() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createTestEnvironment()
        
        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let testObject = try TestObjectFactory.createTestPerson(name: "Alice", age: 25, personClass: personClass)
        await sourceResource.add(testObject)

        // First navigation
        let firstResult = try await executionEngine.navigate(from: testObject, property: "name")
        #expect(firstResult as? String == "Alice")

        // Second navigation (should use cache)
        let secondResult = try await executionEngine.navigate(from: testObject, property: "name")
        #expect(secondResult as? String == "Alice")

        // Verify cache statistics
        let stats = await executionEngine.getCacheStatistics()
        #expect(stats["navigationCacheSize"] ?? 0 >= 1)
    }

    @Test func testNavigationUnknownProperty() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createTestEnvironment()
        
        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let testObject = try TestObjectFactory.createTestPerson(name: "Bob", age: 35, personClass: personClass)
        await sourceResource.add(testObject)

        await #expect(throws: ECoreExecutionError.self) {
            _ = try await executionEngine.navigate(from: testObject, property: "unknownProperty")
        }
    }

    // MARK: - Expression Evaluation Tests

    @Test func testLiteralEvaluation() async throws {
        let (_, _, executionEngine, _) = try await createTestEnvironment()

        let stringExpr = ECoreExpression.literal(value: .string("Hello"))
        let stringResult = try await executionEngine.evaluate(stringExpr, context: [:])
        #expect(stringResult as? String == "Hello")

        let intExpr = ECoreExpression.literal(value: .int(42))
        let intResult = try await executionEngine.evaluate(intExpr, context: [:])
        #expect(intResult as? Int == 42)

        let boolExpr = ECoreExpression.literal(value: .boolean(true))
        let boolResult = try await executionEngine.evaluate(boolExpr, context: [:])
        #expect(boolResult as? Bool == true)
    }

    @Test func testVariableEvaluation() async throws {
        let (_, _, executionEngine, _) = try await createTestEnvironment()
        let expr = ECoreExpression.variable(name: "testVar")
        let context: [String: any EcoreValue] = ["testVar": "Test Value"]
        let result = try await executionEngine.evaluate(expr, context: context)
        #expect(result as? String == "Test Value")
    }

    @Test func testNavigationExpression() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createTestEnvironment()
        
        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let testObject = try TestObjectFactory.createTestPerson(name: "Charlie", age: 40, personClass: personClass)
        await sourceResource.add(testObject)

        let expr = ECoreExpression.navigation(
            source: .variable(name: "self"),
            property: "name"
        )
        let context: [String: any EcoreValue] = ["self": testObject]
        let result = try await executionEngine.evaluate(expr, context: context)
        #expect(result as? String == "Charlie")
    }

    // MARK: - Query Tests

    @Test func testAllInstancesOf() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createTestEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        // Create test objects
        let person1 = try TestObjectFactory.createTestPerson(name: "Alice", age: 25, personClass: personClass)
        let person2 = try TestObjectFactory.createTestPerson(name: "Bob", age: 30, personClass: personClass)

        await sourceResource.add(person1)
        await sourceResource.add(person2)

        // Query all Person instances
        let persons = await executionEngine.allInstancesOf(personClass)
        #expect(persons.count == 2)
    }

    @Test func testFirstInstanceOf() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createTestEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let person = try TestObjectFactory.createTestPerson(name: "Test", age: 25, personClass: personClass)
        await sourceResource.add(person)

        let firstPerson = await executionEngine.firstInstanceOf(personClass)
        #expect(firstPerson != nil)
        #expect(firstPerson?.id == person.id)
    }

    // MARK: - Error Handling Tests

    @Test func testInvalidNavigation() async throws {
        let (_, _, executionEngine, _) = try await createTestEnvironment()
        let expr = ECoreExpression.navigation(
            source: .literal(value: .string("NotAnObject")),
            property: "someProperty"
        )

        await #expect(throws: ECoreExecutionError.self) {
            _ = try await executionEngine.evaluate(expr, context: [:])
        }
    }

    @Test func testTypeQueries() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createTestEnvironment()

        guard let personClass = testPackage.getEClass("Person"),
              let companyClass = testPackage.getEClass("Company") else {
            throw ECoreExecutionError.typeError("Classes not found")
        }

        // Create test objects
        let person = try TestObjectFactory.createTestPerson(name: "Alice", age: 25, personClass: personClass)
        await sourceResource.add(person)

        // Test type queries
        let persons = await executionEngine.allInstancesOf(personClass)
        #expect(persons.count == 1)

        let companies = await executionEngine.allInstancesOf(companyClass)
        #expect(companies.count == 0)
    }
}

