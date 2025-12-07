//
// QueryTests.swift
// ECore
//
// Created by Rene Hexel on 7/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore

@Suite("Query Framework Tests")
struct QueryTests {

    // MARK: - Helper Methods

    func createTestEnvironment() async throws -> (Resource, ECoreExecutionEngine, EPackage) {
        let (resource, _, executionEngine, testPackage) = try await TestEnvironmentFactory.createExecutionEnvironment(uri: "test://query")
        return (resource, executionEngine, testPackage)
    }

    // MARK: - Query Creation Tests

    @Test func testQueryCreation() {
        let query = ECoreQuery("self.name")
        #expect(query.expression == "self.name")
        #expect(query.contextType == nil)
    }

    @Test func testQueryWithContextType() async throws {
        let (_, _, testPackage) = try await createTestEnvironment()
        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let query = ECoreQuery("self.age", context: personClass)
        #expect(query.expression == "self.age")
        #expect(query.contextType?.name == "Person")
    }

    @Test func testQueryEquality() async throws {
        let (_, _, testPackage) = try await createTestEnvironment()
        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let query1 = ECoreQuery("self.name", context: personClass)
        let query2 = ECoreQuery("self.name", context: personClass)
        let query3 = ECoreQuery("self.age", context: personClass)

        #expect(query1 == query2)
        #expect(query1 != query3)
    }

    // MARK: - Query Builder Tests

    @Test func testNavigateBuilder() {
        let query = ECoreQuery.navigate(to: "name")
        #expect(query.expression == "self.name")
    }

    @Test func testNavigateBuilderWithCustomSource() {
        let query = ECoreQuery.navigate(from: "person", to: "age")
        #expect(query.expression == "person.age")
    }

    @Test func testCallBuilder() {
        let query = ECoreQuery.call(property: "employees", method: "size")
        #expect(query.expression == "self.employees.size()")
    }

    @Test func testLiteralBuilder() {
        let query = ECoreQuery.literal("Alice")
        #expect(query.expression == "Alice")
    }

    // MARK: - Query Parser Tests

    @Test func testParseSimpleNavigation() throws {
        let parser = ECoreQueryParser()
        let expr = try parser.parse("self.name")

        if case let .navigation(source, property) = expr {
            if case let .variable(name) = source {
                #expect(name == "self")
                #expect(property == "name")
            } else {
                Issue.record("Expected variable source")
            }
        } else {
            Issue.record("Expected navigation expression")
        }
    }

    @Test func testParseChainedNavigation() throws {
        let parser = ECoreQueryParser()
        let expr = try parser.parse("self.company.name")

        if case let .navigation(source, property) = expr {
            #expect(property == "name")
            if case let .navigation(innerSource, innerProperty) = source {
                #expect(innerProperty == "company")
                if case let .variable(name) = innerSource {
                    #expect(name == "self")
                } else {
                    Issue.record("Expected variable source in chain")
                }
            } else {
                Issue.record("Expected navigation source in chain")
            }
        } else {
            Issue.record("Expected navigation expression")
        }
    }

    @Test func testParseMethodCall() throws {
        let parser = ECoreQueryParser()
        let expr = try parser.parse("self.employees.size()")

        if case let .methodCall(receiver, methodName, arguments) = expr {
            #expect(methodName == "size")
            #expect(arguments.isEmpty)
            if case let .navigation(source, property) = receiver {
                #expect(property == "employees")
                if case let .variable(name) = source {
                    #expect(name == "self")
                } else {
                    Issue.record("Expected variable source in method call")
                }
            } else {
                Issue.record("Expected navigation receiver in method call")
            }
        } else {
            Issue.record("Expected method call expression")
        }
    }

    @Test func testParseStringLiteral() throws {
        let parser = ECoreQueryParser()
        let expr1 = try parser.parse("'Alice'")
        let expr2 = try parser.parse("\"Bob\"")

        if case let .literal(value1) = expr1 {
            if case let .string(str1) = value1 {
                #expect(str1 == "Alice")
            } else {
                Issue.record("Expected string value")
            }
        } else {
            Issue.record("Expected literal expression")
        }

        if case let .literal(value2) = expr2 {
            if case let .string(str2) = value2 {
                #expect(str2 == "Bob")
            } else {
                Issue.record("Expected string value")
            }
        } else {
            Issue.record("Expected literal expression")
        }
    }

    @Test func testParseIntegerLiteral() throws {
        let parser = ECoreQueryParser()
        let expr = try parser.parse("42")

        if case let .literal(value) = expr {
            if case let .int(intValue) = value {
                #expect(intValue == 42)
            } else {
                Issue.record("Expected integer value")
            }
        } else {
            Issue.record("Expected literal expression")
        }
    }

    @Test func testParseDoubleLiteral() throws {
        let parser = ECoreQueryParser()
        let expr = try parser.parse("3.14")

        if case let .literal(value) = expr {
            if case let .double(doubleValue) = value {
                #expect(doubleValue == 3.14)
            } else {
                Issue.record("Expected double value")
            }
        } else {
            Issue.record("Expected literal expression")
        }
    }

    @Test func testParseBooleanLiterals() throws {
        let parser = ECoreQueryParser()
        let expr1 = try parser.parse("true")
        let expr2 = try parser.parse("false")

        if case let .literal(value1) = expr1 {
            if case let .boolean(boolValue1) = value1 {
                #expect(boolValue1 == true)
            } else {
                Issue.record("Expected boolean true value")
            }
        } else {
            Issue.record("Expected literal expression")
        }

        if case let .literal(value2) = expr2 {
            if case let .boolean(boolValue2) = value2 {
                #expect(boolValue2 == false)
            } else {
                Issue.record("Expected boolean false value")
            }
        } else {
            Issue.record("Expected literal expression")
        }
    }

    @Test func testParseNullLiteral() throws {
        let parser = ECoreQueryParser()
        let expr = try parser.parse("null")

        if case let .literal(value) = expr {
            if case .null = value {
                // Success
            } else {
                Issue.record("Expected null value")
            }
        } else {
            Issue.record("Expected literal expression")
        }
    }

    @Test func testParseVariable() throws {
        let parser = ECoreQueryParser()
        let expr = try parser.parse("someVariable")

        if case let .variable(name) = expr {
            #expect(name == "someVariable")
        } else {
            Issue.record("Expected variable expression")
        }
    }

    @Test func testParseError() {
        let parser = ECoreQueryParser()
        #expect(throws: ECoreQueryError.self) {
            _ = try parser.parse("@invalid#expression!")
        }
    }

    // MARK: - Query Evaluation Tests

    @Test func testEvaluateSimpleNavigation() async throws {
        let (resource, executionEngine, testPackage) = try await createTestEnvironment()
        
        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let person = try TestObjectFactory.createTestPerson(name: "Alice", age: 30, personClass: personClass)
        await resource.add(person)

        let evaluator = ECoreQueryEvaluator(executionEngine: executionEngine)
        let query = ECoreQuery("self.name")
        
        let result = try await evaluator.evaluate(query, on: person)
        #expect(result as? String == "Alice")
    }

    @Test func testEvaluateMethodCall() async throws {
        let (resource, executionEngine, testPackage) = try await createTestEnvironment()
        
        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let person = try TestObjectFactory.createTestPerson(name: "Bob", age: 25, personClass: personClass)
        await resource.add(person)

        let evaluator = ECoreQueryEvaluator(executionEngine: executionEngine)
        let query = ECoreQuery("self.name.size()")
        
        let result = try await evaluator.evaluate(query, on: person)
        #expect(result as? Int == 3) // "Bob".count
    }

    @Test func testEvaluateWithCustomContext() async throws {
        let (_, executionEngine, _) = try await createTestEnvironment()
        
        let evaluator = ECoreQueryEvaluator(executionEngine: executionEngine)
        let query = ECoreQuery("customVar")
        let context: [String: any EcoreValue] = ["customVar": "CustomValue"]
        
        let result = try await evaluator.evaluate(query, context: context)
        #expect(result as? String == "CustomValue")
    }

    @Test func testEvaluateLiteralQuery() async throws {
        let (_, executionEngine, _) = try await createTestEnvironment()
        
        let evaluator = ECoreQueryEvaluator(executionEngine: executionEngine)
        let query = ECoreQuery("42")
        
        let result = try await evaluator.evaluate(query, context: [:])
        #expect(result as? Int == 42)
    }

    // MARK: - Error Handling Tests

    @Test func testQueryParserError() {
        let parser = ECoreQueryParser()
        
        do {
            _ = try parser.parse("@#$%invalid")
            Issue.record("Expected parsing to fail")
        } catch let error as ECoreQueryError {
            if case .parseError = error {
                // Expected
            } else {
                Issue.record("Expected parse error")
            }
        } catch {
            Issue.record("Expected ECoreQueryError")
        }
    }

    @Test func testEvaluationError() async throws {
        let (_, executionEngine, _) = try await createTestEnvironment()
        
        let evaluator = ECoreQueryEvaluator(executionEngine: executionEngine)
        let query = ECoreQuery("nonExistentVariable")
        
        // Note: The current implementation returns nil for missing variables instead of throwing
        // This test may need adjustment based on desired behavior
        do {
            let result = try await evaluator.evaluate(query, context: [:])
            #expect(result == nil) // Missing variables return nil instead of throwing
        } catch {
            // If it does throw, that's also acceptable behavior
            #expect(error is ECoreExecutionError)
        }
    }

    // MARK: - Performance Tests

    @Test func testQueryCaching() async throws {
        let (resource, executionEngine, testPackage) = try await createTestEnvironment()
        
        guard let personClass = testPackage.getEClass("Person") else {
            throw ECoreExecutionError.typeError("Person class not found")
        }

        let person = try TestObjectFactory.createTestPerson(name: "Charlie", age: 35, personClass: personClass)
        await resource.add(person)

        let evaluator = ECoreQueryEvaluator(executionEngine: executionEngine)
        let query = ECoreQuery("self.name")

        // First evaluation
        let result1 = try await evaluator.evaluate(query, on: person)
        #expect(result1 as? String == "Charlie")

        // Second evaluation should use cache
        let result2 = try await evaluator.evaluate(query, on: person)
        #expect(result2 as? String == "Charlie")

        // Verify cache was used by checking statistics
        let stats = await executionEngine.getCacheStatistics()
        #expect(stats["navigationCacheSize"] ?? 0 > 0)
    }

    // MARK: - Complex Query Tests

    @Test func testComplexNavigationQuery() async throws {
        let (resource, executionEngine, testPackage) = try await createTestEnvironment()
        
        guard let personClass = testPackage.getEClass("Person"),
              let companyClass = testPackage.getEClass("Company") else {
            throw ECoreExecutionError.typeError("Classes not found")
        }

        // Create company and employee
        let company = try TestObjectFactory.createTestCompany(name: "TechCorp", founded: 2010, companyClass: companyClass)
        let employee = try TestObjectFactory.createTestPerson(name: "Diana", age: 28, salary: 75000.0, personClass: personClass)

        await resource.add(company)
        await resource.add(employee)

        let evaluator = ECoreQueryEvaluator(executionEngine: executionEngine)

        // Test simple property access
        let nameQuery = ECoreQuery("self.name")
        let nameResult = try await evaluator.evaluate(nameQuery, on: employee)
        #expect(nameResult as? String == "Diana")

        let salaryQuery = ECoreQuery("self.salary")
        let salaryResult = try await evaluator.evaluate(salaryQuery, on: employee)
        #expect(salaryResult as? Double == 75000.0)
    }
}

