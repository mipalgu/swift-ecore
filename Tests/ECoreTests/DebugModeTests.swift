//
// DebugModeTests.swift
// ECore
//
//  Created by Rene Hexel on 19/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing
@testable import ECore

@Suite("Debug Mode Tests")
struct DebugModeTests {

    // MARK: - Helper Methods

    func createTestEnvironment() async throws -> (Resource, Resource, ECoreExecutionEngine, EPackage) {
        return try await TestEnvironmentFactory.createExecutionEnvironment(uri: "test://debug")
    }

    // MARK: - Debug Output Tests

    @Test func testDebugOutputForMethodInvocation() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createTestEnvironment()

        await executionEngine.enableDebugging()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        // Create a test person
        let person = try TestObjectFactory.createTestPerson(name: "Test", age: 25, personClass: personClass)
        await sourceResource.add(person)

        // This should print debug output
        let expr = ECoreExpression.methodCall(
            receiver: .navigation(source: .variable(name: "self"), property: "name"),
            methodName: "oclIsUndefined",
            arguments: []
        )

        let context: [String: any EcoreValue] = ["self": person]
        _ = try await executionEngine.evaluate(expr, context: context)

        // Test passes if no exception thrown
    }

    @Test func testDebugOutputForNavigation() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createTestEnvironment()

        await executionEngine.enableDebugging(true)

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let person = try TestObjectFactory.createTestPerson(name: "Alice", age: 30, personClass: personClass)
        await sourceResource.add(person)

        // This should print debug output for navigation
        _ = try await executionEngine.navigate(from: person, property: "name")

        // Test passes if no exception thrown
    }

    @Test func testDebugOutputForVariableExpression() async throws {
        let (_, _, executionEngine, _) = try await createTestEnvironment()

        await executionEngine.enableDebugging(true)

        let expr = ECoreExpression.variable(name: "testVar")
        let context: [String: any EcoreValue] = ["testVar": "Test Value"]

        // This should print debug output for variable access
        _ = try await executionEngine.evaluate(expr, context: context)

        // Test passes if no exception thrown
    }

    @Test func testDebugOutputForLiteralExpression() async throws {
        let (_, _, executionEngine, _) = try await createTestEnvironment()

        await executionEngine.enableDebugging(true)

        let expr = ECoreExpression.literal(value: .string("Hello"))

        // This should print debug output for literal
        _ = try await executionEngine.evaluate(expr, context: [:])

        // Test passes if no exception thrown
    }

    @Test func testDebugModeDisabledByDefault() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createTestEnvironment()

        // Debug should be disabled by default, no output expected
        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let person = try TestObjectFactory.createTestPerson(name: "Bob", age: 35, personClass: personClass)
        await sourceResource.add(person)

        _ = try await executionEngine.navigate(from: person, property: "name")

        // Test passes if no exception thrown
    }

    @Test func testDebugModeCanBeToggled() async throws {
        let (sourceResource, _, executionEngine, testPackage) = try await createTestEnvironment()

        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let person = try TestObjectFactory.createTestPerson(name: "Charlie", age: 40, personClass: personClass)
        await sourceResource.add(person)

        // Enable debug
        await executionEngine.enableDebugging(true)
        _ = try await executionEngine.navigate(from: person, property: "name")

        // Disable debug
        await executionEngine.enableDebugging(false)
        _ = try await executionEngine.navigate(from: person, property: "age")

        // Enable again
        await executionEngine.enableDebugging(true)
        _ = try await executionEngine.navigate(from: person, property: "name")

        // Test passes if no exception thrown
    }
}
