//
// OCLIntegrationTests.swift
// OCL
//
//  Created by Rene Hexel on 18/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//

import EMFBase
import Testing

@testable import OCL

@Suite("OCL Integration Tests")
struct OCLIntegrationTests {

    // MARK: - Collection and Binary Operation Integration

    @Test("Filter and count with binary operations")
    func testFilterAndCountWithBinary() throws {
        let numbers = EcoreValueArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])

        // Filter even numbers: select(n | n mod 2 = 0)
        let evenNumbers = try select(numbers) { element in
            let modResult = try modulo(element, 2 as EInt)
            return equals(modResult, 0 as EInt)
        }

        // Count should be 5 (2, 4, 6, 8, 10)
        let count = try size(EcoreValueArray(evenNumbers))
        #expect(count == 5)

        // Check that first element is 2
        let firstEven = try first(EcoreValueArray(evenNumbers))
        #expect(firstEven as? EInt == 2)
    }

    @Test("Complex mathematical operations on collections")
    func testComplexMathOperations() throws {
        let values = EcoreValueArray([1.0, 2.0, 3.0, 4.0, 5.0])

        // Transform each value: collect(v | v * v + 1)
        let transformed = try collect(values) { element in
            let squared = try multiply(element, element)
            return try add(squared, 1.0 as EDouble)
        }

        // Results should be [2, 5, 10, 17, 26]
        #expect(transformed.count == 5)
        #expect(transformed[0] as? EDouble == 2.0)
        #expect(transformed[1] as? EDouble == 5.0)
        #expect(transformed[2] as? EDouble == 10.0)
        #expect(transformed[3] as? EDouble == 17.0)
        #expect(transformed[4] as? EDouble == 26.0)

        // Find maximum value
        let maxValue = try iterate(EcoreValueArray(transformed), 0.0 as EDouble) { acc, element in
            return try max(acc, element)
        }
        #expect(maxValue as? EDouble == 26.0)
    }

    // MARK: - String and Collection Integration

    @Test("String operations with collections")
    func testStringCollectionIntegration() throws {
        let words = EcoreValueArray(["hello", "world", "swift", "ecore"])

        // Convert all to uppercase: collect(w | w.toUpperCase())
        let uppercaseWords = try collect(words) { word in
            return try toUpperCase(word)
        }

        // Concatenate into single string
        let sentence = try iterate(EcoreValueArray(uppercaseWords), "" as EString) { acc, word in
            if try isEmpty(acc) {
                return word
            } else {
                let withSpace = try concat(acc, " " as EString)
                return try concat(withSpace, word)
            }
        }

        #expect(sentence as? EString == "HELLO WORLD SWIFT ECORE")

        // Check total character count
        let totalLength = try size(sentence)
        #expect(totalLength == 23)  // Including spaces
    }

    @Test("String filtering and validation")
    func testStringFilteringValidation() throws {
        let inputs = EcoreValueArray(["", "a", "ab", "abc", "abcd", "abcde"])

        // Filter strings longer than 2 characters
        let longStrings = try select(inputs) { str in
            let length = try size(str)
            return try greaterThan(length, 2 as EInt)
        }

        #expect(longStrings.count == 3)  // "abc", "abcd", "abcde"

        // Check all results contain 'a'
        let allContainA = try forAll(EcoreValueArray(longStrings)) { str in
            return try contains(str, "a" as EString)
        }
        #expect(allContainA == true)

        // Find the longest string
        let longestString = try iterate(EcoreValueArray(longStrings), "" as EString) { acc, element in
            let accLength = try size(acc)
            let elemLength = try size(element)
            let isLonger = try greaterThan(elemLength, accLength)
            return isLonger ? element : acc
        }
        #expect(longestString as? EString == "abcde")
    }

    // MARK: - Numeric and Type Operation Integration

    @Test("Numeric operations with type checking")
    func testNumericTypeIntegration() throws {
        let mixedValues = EcoreValueArray([
            1 as EInt,
            2.5 as EDouble,
            3.0 as EFloat,
            "not a number" as EString,
            4 as EInt,
        ])

        // Filter only numeric values
        let numericValues = try select(mixedValues) { value in
            let isInt = try oclIsKindOf(value, EInt.self)
            let isDouble = try oclIsKindOf(value, EDouble.self)
            let isFloat = try oclIsKindOf(value, EFloat.self)
            return try or(or(isInt, isDouble), isFloat)
        }

        #expect(numericValues.count == 4)  // All except the string

        // Calculate sum using type-safe operations
        var sum = 0.0
        for value in numericValues {
            if try oclIsKindOf(value, EInt.self) {
                let intVal = try oclAsType(value, EInt.self)
                sum += Double(intVal)
            } else if try oclIsKindOf(value, EDouble.self) {
                let doubleVal = try oclAsType(value, EDouble.self)
                sum += doubleVal
            } else if try oclIsKindOf(value, EFloat.self) {
                let floatVal = try oclAsType(value, EFloat.self)
                sum += Double(floatVal)
            }
        }

        #expect(sum == 10.5)  // 1 + 2.5 + 3.0 + 4 = 10.5
    }

    // MARK: - Complex Business Logic Scenarios

    @Test("Employee data processing scenario")
    func testEmployeeScenario() throws {
        // Simulate employee data: [name, age, salary]
        let employees = EcoreValueArray([
            EcoreValueArray(["Alice", 30, 50000]),
            EcoreValueArray(["Bob", 25, 45000]),
            EcoreValueArray(["Charlie", 35, 60000]),
            EcoreValueArray(["Diana", 28, 52000]),
            EcoreValueArray(["Eve", 32, 58000]),
        ])

        // Find employees over 30 with salary > 50000
        let qualifiedEmployees = try select(employees) { employee in
            guard let emp = employee as? EcoreValueArray,
                emp.values.count >= 3
            else { return false }

            let age = emp.values[1]
            let salary = emp.values[2]

            let ageCheck = try greaterThan(age, 30 as EInt)
            let salaryCheck = try greaterThan(salary, 50000 as EInt)

            return try and(ageCheck, salaryCheck)
        }

        #expect(qualifiedEmployees.count == 2)  // Charlie and Eve

        // Calculate average salary of qualified employees
        let totalSalary = try iterate(EcoreValueArray(qualifiedEmployees), 0 as EInt) { acc, employee in
            guard let emp = employee as? EcoreValueArray,
                emp.values.count >= 3
            else { return acc }

            return try add(acc, emp.values[2])
        }

        let averageSalary = try divide(totalSalary, qualifiedEmployees.count as EInt)
        #expect(averageSalary as? EInt == 59000)  // (60000 + 58000) / 2
    }

    @Test("Data validation and transformation pipeline")
    func testDataValidationPipeline() throws {
        let rawData = EcoreValueArray([
            "123",
            "45.6",
            "invalid",
            "78",
            "",
            "90.1",
        ])

        // Step 1: Filter out empty strings
        let nonEmpty = try reject(rawData) { str in
            return try isEmpty(str)
        }

        #expect(nonEmpty.count == 5)

        // Step 2: Validate numeric strings (contains only digits and optionally one dot)
        let validNumbers = try select(EcoreValueArray(nonEmpty)) { str in
            guard let string = str as? EString else { return false }

            // Simple validation: check if it contains only valid characters
            let hasInvalidChars = try contains(string, "invalid")
            return try not(hasInvalidChars)
        }

        #expect(validNumbers.count == 4)  // Excludes "invalid"

        // Step 3: Transform to descriptions
        let descriptions = try collect(EcoreValueArray(validNumbers)) { str in
            let length = try size(str)
            let isLong = try greaterThanOrEqual(length, 4 as EInt)

            if isLong {
                return try concat("Long number: " as EString, str)
            } else {
                return try concat("Short number: " as EString, str)
            }
        }

        // Verify all descriptions start with either "Long" or "Short"
        let allValid = try forAll(EcoreValueArray(descriptions)) { desc in
            let startsWithLong = try startsWith(desc, "Long")
            let startsWithShort = try startsWith(desc, "Short")
            return try or(startsWithLong, startsWithShort)
        }

        #expect(allValid == true)
    }

    // MARK: - Error Handling Integration

    @Test("Error propagation in complex operations")
    func testErrorPropagation() throws {
        let validData = EcoreValueArray([1, 2, 3, 4, 5])
        let invalidData = EcoreValueArray(["not", "numbers"])

        // This should work fine
        let validSum = try iterate(validData, 0 as EInt) { acc, element in
            return try add(acc, element)
        }
        #expect(validSum as? EInt == 15)

        // This should throw an error when trying to add strings
        #expect(throws: OCLError.invalidArguments("Cannot add values of types Int and String")) {
            try iterate(invalidData, 0 as EInt) { acc, element in
                return try add(acc, element)  // Should fail on string addition
            }
        }
    }

    // MARK: - Performance and Edge Cases

    @Test("Large collection operations")
    func testLargeCollectionOperations() throws {
        // Create a large collection
        let largeCollection = EcoreValueArray(Array(1...1000).map { $0 as any EcoreValue })

        // Filter even numbers
        let evenNumbers = try select(largeCollection) { element in
            let modResult = try modulo(element, 2 as EInt)
            return equals(modResult, 0 as EInt)
        }

        #expect(evenNumbers.count == 500)  // Half should be even

        // Calculate sum of squares of first 10 even numbers
        let firstTenEven = EcoreValueArray(Array(evenNumbers.prefix(10)))
        let sumOfSquares = try iterate(firstTenEven, 0 as EInt) { acc, element in
            let squared = try multiply(element, element)
            return try add(acc, squared)
        }

        // 2² + 4² + 6² + 8² + 10² + 12² + 14² + 16² + 18² + 20² = 1540
        #expect(sumOfSquares as? EInt == 1540)
    }

    @Test("Empty and boundary condition handling")
    func testBoundaryConditions() throws {
        let emptyCollection = EcoreValueArray([])
        let singleElement = EcoreValueArray([42])

        // Empty collection operations
        #expect(try isEmpty(emptyCollection) == true)
        #expect(try notEmpty(emptyCollection) == false)
        #expect(try size(emptyCollection) == 0)

        // ForAll should return true for empty collection (vacuous truth)
        let allPositive = try forAll(emptyCollection) { element in
            return try greaterThan(element, 0 as EInt)
        }
        #expect(allPositive == true)

        // Exists should return false for empty collection
        let anyPositive = try exists(emptyCollection) { element in
            return try greaterThan(element, 0 as EInt)
        }
        #expect(anyPositive == false)

        // Single element operations
        #expect(try size(singleElement) == 1)
        #expect(try first(singleElement) as? EInt == 42)
        #expect(try last(singleElement) as? EInt == 42)

        let singleElementSum = try iterate(singleElement, 0 as EInt) { acc, element in
            return try add(acc, element)
        }
        #expect(singleElementSum as? EInt == 42)
    }

    // MARK: - Cross-Category Operation Tests

    @Test("All operation categories working together")
    func testAllCategoriesTogether() throws {
        let testData = EcoreValueArray([
            EcoreValueArray(["Alice", 25, 3.14]),
            EcoreValueArray(["Bob", 30, 2.71]),
            EcoreValueArray(["Charlie", 35, 1.41]),
        ])

        // Step 1: Use collection operations to filter
        let adults = try select(testData) { person in
            guard let p = person as? EcoreValueArray, p.values.count >= 2 else { return false }
            return try greaterThanOrEqual(p.values[1], 30 as EInt)
        }

        // Step 2: Use string operations to create descriptions
        let descriptions = try collect(EcoreValueArray(adults)) { person in
            guard let p = person as? EcoreValueArray,
                p.values.count >= 3,
                let name = p.values[0] as? EString
            else {
                return "Unknown" as EString
            }

            let upperName = try toUpperCase(name)
            let prefix = "ADULT: " as EString
            return try concat(prefix, upperName)
        }

        // Step 3: Use numeric operations on the score values
        let scores = try collect(EcoreValueArray(adults)) { person in
            guard let p = person as? EcoreValueArray,
                p.values.count >= 3
            else { return 0.0 as EDouble }
            return p.values[2]
        }

        let maxScore = try iterate(EcoreValueArray(scores), 0.0 as EDouble) { acc, score in
            return try max(acc, score)
        }

        let minScore = try iterate(EcoreValueArray(scores), Double.greatestFiniteMagnitude as EDouble) {
            acc, score in
            return try min(acc, score)
        }

        // Step 4: Use type operations to verify results
        let allDescriptionsAreStrings = try forAll(EcoreValueArray(descriptions)) { desc in
            return try oclIsKindOf(desc, EString.self)
        }

        let allScoresAreNumeric = try forAll(EcoreValueArray(scores)) { score in
            let isDouble = try oclIsKindOf(score, EDouble.self)
            let isFloat = try oclIsKindOf(score, EFloat.self)
            return try or(isDouble, isFloat)
        }

        // Verify results
        #expect(adults.count == 2)  // Bob and Charlie
        #expect(descriptions.count == 2)
        #expect(try contains(descriptions[0], "ADULT:"))
        #expect(maxScore as? EDouble == 2.71)
        #expect(minScore as? EDouble == 1.41)
        #expect(allDescriptionsAreStrings == true)
        #expect(allScoresAreNumeric == true)
    }
}
