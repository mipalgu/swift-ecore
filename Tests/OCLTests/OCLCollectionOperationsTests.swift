//
// OCLCollectionOperationsTests.swift
// OCLTests
//
// Created by Rene Hexel on 18/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//

import EMFBase
import Testing

@testable import OCL

@Suite("OCL Collection Operations")
struct OCLCollectionOperationsTests {

    // MARK: - Collection Iterator Operations Tests

    @Test("Select filters elements correctly")
    func testSelect() throws {
        let numbers = EcoreValueArray([1, 2, 3, 4, 5])
        let evens = try select(numbers) { ($0 as? Int ?? 0) % 2 == 0 }

        #expect(evens.count == 2)
        #expect(evens[0] as? Int == 2)
        #expect(evens[1] as? Int == 4)
    }

    @Test("Select with empty result")
    func testSelectEmptyResult() throws {
        let numbers = EcoreValueArray([1, 3, 5])
        let evens = try select(numbers) { ($0 as? Int ?? 0) % 2 == 0 }

        #expect(evens.isEmpty)
    }

    @Test("Select with all elements matching")
    func testSelectAllMatch() throws {
        let numbers = EcoreValueArray([2, 4, 6])
        let evens = try select(numbers) { ($0 as? Int ?? 0) % 2 == 0 }

        #expect(evens.count == 3)
        #expect(evens[0] as? Int == 2)
        #expect(evens[1] as? Int == 4)
        #expect(evens[2] as? Int == 6)
    }

    @Test("Reject filters elements correctly")
    func testReject() throws {
        let numbers = EcoreValueArray([1, 2, 3, 4, 5])
        let odds = try reject(numbers) { ($0 as? Int ?? 0) % 2 == 0 }

        #expect(odds.count == 3)
        #expect(odds[0] as? Int == 1)
        #expect(odds[1] as? Int == 3)
        #expect(odds[2] as? Int == 5)
    }

    @Test("Reject with empty result")
    func testRejectEmptyResult() throws {
        let numbers = EcoreValueArray([2, 4, 6])
        let odds = try reject(numbers) { ($0 as? Int ?? 0) % 2 == 0 }

        #expect(odds.isEmpty)
    }

    @Test("Collect transforms elements")
    func testCollect() throws {
        let numbers = EcoreValueArray([1, 2, 3])
        let doubled = try collect(numbers) { ($0 as? Int ?? 0) * 2 }

        #expect(doubled.count == 3)
        #expect(doubled[0] as? Int == 2)
        #expect(doubled[1] as? Int == 4)
        #expect(doubled[2] as? Int == 6)
    }

    @Test("Collect with type transformation")
    func testCollectTypeTransformation() throws {
        let numbers = EcoreValueArray([1, 2, 3])
        let strings = try collect(numbers) { "Number: \($0)" }

        #expect(strings.count == 3)
        #expect(strings[0] as? String == "Number: 1")
        #expect(strings[1] as? String == "Number: 2")
        #expect(strings[2] as? String == "Number: 3")
    }

    @Test("Exists returns true when element found")
    func testExistsTrue() throws {
        let numbers = EcoreValueArray([1, 2, 3, 4, 5])
        let hasEven = try exists(numbers) { ($0 as? Int ?? 0) % 2 == 0 }

        #expect(hasEven == true)
    }

    @Test("Exists returns false when no element found")
    func testExistsFalse() throws {
        let numbers = EcoreValueArray([1, 3, 5])
        let hasEven = try exists(numbers) { ($0 as? Int ?? 0) % 2 == 0 }

        #expect(hasEven == false)
    }

    @Test("Exists returns false for empty collection")
    func testExistsEmpty() throws {
        let empty = EcoreValueArray([])
        let hasAny = try exists(empty) { _ in true }

        #expect(hasAny == false)
    }

    @Test("ForAll returns true when all elements match")
    func testForAllTrue() throws {
        let numbers = EcoreValueArray([2, 4, 6])
        let allEven = try forAll(numbers) { ($0 as? Int ?? 0) % 2 == 0 }

        #expect(allEven == true)
    }

    @Test("ForAll returns false when some elements don't match")
    func testForAllFalse() throws {
        let numbers = EcoreValueArray([2, 3, 4])
        let allEven = try forAll(numbers) { ($0 as? Int ?? 0) % 2 == 0 }

        #expect(allEven == false)
    }

    @Test("ForAll returns true for empty collection")
    func testForAllEmpty() throws {
        let empty = EcoreValueArray([])
        let allEven = try forAll(empty) { ($0 as? Int ?? 0) % 2 == 0 }

        #expect(allEven == true)  // Vacuous truth
    }

    @Test("One returns true when exactly one element matches")
    func testOneTrue() throws {
        let numbers = EcoreValueArray([1, 2, 3])
        let exactlyOneTwo = try one(numbers) { ($0 as? Int ?? 0) == 2 }

        #expect(exactlyOneTwo == true)
    }

    @Test("One returns false when no elements match")
    func testOneFalseNone() throws {
        let numbers = EcoreValueArray([1, 3, 5])
        let exactlyOneEven = try one(numbers) { ($0 as? Int ?? 0) % 2 == 0 }

        #expect(exactlyOneEven == false)
    }

    @Test("One returns false when multiple elements match")
    func testOneFalseMultiple() throws {
        let numbers = EcoreValueArray([2, 4, 6])
        let exactlyOneEven = try one(numbers) { ($0 as? Int ?? 0) % 2 == 0 }

        #expect(exactlyOneEven == false)
    }

    @Test("Iterate accumulates values correctly")
    func testIterate() throws {
        let numbers = EcoreValueArray([1, 2, 3, 4])
        let sum = try iterate(numbers, 0 as Int) { acc, elem in
            (acc as? Int ?? 0) + (elem as? Int ?? 0)
        }

        #expect(sum as? Int == 10)
    }

    @Test("Iterate with string concatenation")
    func testIterateStrings() throws {
        let words = EcoreValueArray(["Hello", " ", "World"])
        let sentence = try iterate(words, "" as String) { acc, elem in
            (acc as? String ?? "") + (elem as? String ?? "")
        }

        #expect(sentence as? String == "Hello World")
    }

    // MARK: - Collection Query Operations Tests

    @Test("Size returns correct count for array")
    func testSizeArray() throws {
        let numbers = EcoreValueArray([1, 2, 3, 4, 5])
        let count = try size(numbers)

        #expect(count == 5)
    }

    @Test("Size returns correct count for string")
    func testSizeString() throws {
        let text = "Hello" as String
        let length = try size(text)

        #expect(length == 5)
    }

    @Test("Size returns zero for empty array")
    func testSizeEmptyArray() throws {
        let empty = EcoreValueArray([])
        let count = try size(empty)

        #expect(count == 0)
    }

    @Test("Size returns zero for empty string")
    func testSizeEmptyString() throws {
        let empty = "" as String
        let length = try size(empty)

        #expect(length == 0)
    }

    @Test("IsEmpty returns true for empty array")
    func testIsEmptyArrayTrue() throws {
        let empty = EcoreValueArray([])
        let result = try isEmpty(empty)

        #expect(result == true)
    }

    @Test("IsEmpty returns false for non-empty array")
    func testIsEmptyArrayFalse() throws {
        let numbers = EcoreValueArray([1, 2, 3])
        let result = try isEmpty(numbers)

        #expect(result == false)
    }

    @Test("IsEmpty returns true for empty string")
    func testIsEmptyStringTrue() throws {
        let empty = "" as String
        let result = try isEmpty(empty)

        #expect(result == true)
    }

    @Test("IsEmpty returns false for non-empty string")
    func testIsEmptyStringFalse() throws {
        let text = "Hello" as String
        let result = try isEmpty(text)

        #expect(result == false)
    }

    @Test("NotEmpty returns false for empty array")
    func testNotEmptyArrayFalse() throws {
        let empty = EcoreValueArray([])
        let result = try notEmpty(empty)

        #expect(result == false)
    }

    @Test("NotEmpty returns true for non-empty array")
    func testNotEmptyArrayTrue() throws {
        let numbers = EcoreValueArray([1, 2, 3])
        let result = try notEmpty(numbers)

        #expect(result == true)
    }

    @Test("First returns first element")
    func testFirst() throws {
        let numbers = EcoreValueArray([1, 2, 3])
        let firstNum = try first(numbers)

        #expect(firstNum as? Int == 1)
    }

    @Test("First throws error for empty collection")
    func testFirstEmpty() throws {
        let empty = EcoreValueArray([])

        #expect(throws: OCLError.emptyCollection("first")) {
            try first(empty)
        }
    }

    @Test("Last returns last element")
    func testLast() throws {
        let numbers = EcoreValueArray([1, 2, 3])
        let lastNum = try last(numbers)

        #expect(lastNum as? Int == 3)
    }

    @Test("Last throws error for empty collection")
    func testLastEmpty() throws {
        let empty = EcoreValueArray([])

        #expect(throws: OCLError.emptyCollection("last")) {
            try last(empty)
        }
    }

    // MARK: - Collection Set Operations Tests

    @Test("Union combines collections without duplicates")
    func testUnion() throws {
        let set1 = EcoreValueArray([1, 2, 3])
        let set2 = EcoreValueArray([3, 4, 5])
        let combined = try union(set1, set2)

        #expect(combined.count == 5)
        #expect(combined.contains { ($0 as? Int) == 1 })
        #expect(combined.contains { ($0 as? Int) == 2 })
        #expect(combined.contains { ($0 as? Int) == 3 })
        #expect(combined.contains { ($0 as? Int) == 4 })
        #expect(combined.contains { ($0 as? Int) == 5 })
    }

    @Test("Union with empty collections")
    func testUnionEmpty() throws {
        let set1 = EcoreValueArray([1, 2])
        let empty = EcoreValueArray([])
        let result = try union(set1, empty)

        #expect(result.count == 2)
        #expect(result[0] as? Int == 1)
        #expect(result[1] as? Int == 2)
    }

    @Test("Intersection returns common elements")
    func testIntersection() throws {
        let set1 = EcoreValueArray([1, 2, 3, 4])
        let set2 = EcoreValueArray([3, 4, 5, 6])
        let common = try intersection(set1, set2)

        #expect(common.count == 2)
        #expect(common.contains { ($0 as? Int) == 3 })
        #expect(common.contains { ($0 as? Int) == 4 })
    }

    @Test("Intersection with no common elements")
    func testIntersectionEmpty() throws {
        let set1 = EcoreValueArray([1, 2])
        let set2 = EcoreValueArray([3, 4])
        let common = try intersection(set1, set2)

        #expect(common.isEmpty)
    }

    @Test("Difference returns elements in first but not second")
    func testDifference() throws {
        let set1 = EcoreValueArray([1, 2, 3, 4])
        let set2 = EcoreValueArray([2, 3])
        let diff = try difference(set1, set2)

        #expect(diff.count == 2)
        #expect(diff.contains { ($0 as? Int) == 1 })
        #expect(diff.contains { ($0 as? Int) == 4 })
    }

    @Test("Difference with no elements to remove")
    func testDifferenceNone() throws {
        let set1 = EcoreValueArray([1, 2, 3])
        let set2 = EcoreValueArray([4, 5, 6])
        let diff = try difference(set1, set2)

        #expect(diff.count == 3)
        #expect(diff[0] as? Int == 1)
        #expect(diff[1] as? Int == 2)
        #expect(diff[2] as? Int == 3)
    }

    // MARK: - Collection Membership Operations Tests

    @Test("Includes returns true when element present")
    func testIncludesTrue() throws {
        let numbers = EcoreValueArray([1, 2, 3])
        let hasTwo = try includes(numbers, 2 as Int)

        #expect(hasTwo == true)
    }

    @Test("Includes returns false when element absent")
    func testIncludesFalse() throws {
        let numbers = EcoreValueArray([1, 2, 3])
        let hasFour = try includes(numbers, 4 as Int)

        #expect(hasFour == false)
    }

    @Test("Includes with different types")
    func testIncludesDifferentTypes() throws {
        let mixed = EcoreValueArray([1, "hello", true])
        let hasString = try includes(mixed, "hello" as String)
        let hasBool = try includes(mixed, true as Bool)

        #expect(hasString == true)
        #expect(hasBool == true)
    }

    @Test("Excludes returns false when element present")
    func testExcludesFalse() throws {
        let numbers = EcoreValueArray([1, 2, 3])
        let excludesTwo = try excludes(numbers, 2 as Int)

        #expect(excludesTwo == false)
    }

    @Test("Excludes returns true when element absent")
    func testExcludesTrue() throws {
        let numbers = EcoreValueArray([1, 2, 3])
        let excludesFour = try excludes(numbers, 4 as Int)

        #expect(excludesFour == true)
    }

    // MARK: - Collection Type Conversion Operations Tests

    @Test("AsSet removes duplicates")
    func testAsSet() throws {
        let numbers = EcoreValueArray([1, 2, 2, 3, 3, 3])
        let uniqueNums = try asSet(numbers)

        #expect(uniqueNums.count == 3)
        #expect(uniqueNums[0] as? Int == 1)
        #expect(uniqueNums[1] as? Int == 2)
        #expect(uniqueNums[2] as? Int == 3)
    }

    @Test("AsSet preserves order of first occurrence")
    func testAsSetOrder() throws {
        let numbers = EcoreValueArray([3, 1, 2, 1, 3, 2])
        let uniqueNums = try asSet(numbers)

        #expect(uniqueNums.count == 3)
        #expect(uniqueNums[0] as? Int == 3)
        #expect(uniqueNums[1] as? Int == 1)
        #expect(uniqueNums[2] as? Int == 2)
    }

    @Test("AsSequence returns elements in order")
    func testAsSequence() throws {
        let numbers = EcoreValueArray([3, 1, 2])
        let sequence = try asSequence(numbers)

        #expect(sequence.count == 3)
        #expect(sequence[0] as? Int == 3)
        #expect(sequence[1] as? Int == 1)
        #expect(sequence[2] as? Int == 2)
    }

    @Test("AsBag returns all elements including duplicates")
    func testAsBag() throws {
        let numbers = EcoreValueArray([1, 2, 2, 3])
        let bag = try asBag(numbers)

        #expect(bag.count == 4)
        #expect(bag[0] as? Int == 1)
        #expect(bag[1] as? Int == 2)
        #expect(bag[2] as? Int == 2)
        #expect(bag[3] as? Int == 3)
    }

    @Test("AsOrderedSet removes duplicates whilst preserving order")
    func testAsOrderedSet() throws {
        let numbers = EcoreValueArray([3, 1, 2, 1, 3])
        let orderedSet = try asOrderedSet(numbers)

        #expect(orderedSet.count == 3)
        #expect(orderedSet[0] as? Int == 3)
        #expect(orderedSet[1] as? Int == 1)
        #expect(orderedSet[2] as? Int == 2)
    }

    @Test("Flatten flattens nested collections")
    func testFlatten() throws {
        let nested = EcoreValueArray([
            EcoreValueArray([1, 2]),
            EcoreValueArray([3, 4]),
            EcoreValueArray([5]),
        ])

        let flat = try flatten(nested)

        #expect(flat.count == 5)
        #expect(flat[0] as? Int == 1)
        #expect(flat[1] as? Int == 2)
        #expect(flat[2] as? Int == 3)
        #expect(flat[3] as? Int == 4)
        #expect(flat[4] as? Int == 5)
    }

    @Test("Flatten handles mixed nested and non-nested elements")
    func testFlattenMixed() throws {
        let mixed = EcoreValueArray([
            EcoreValueArray([1, 2]),
            3 as Int,
            EcoreValueArray([4, 5]),
        ])

        let flat = try flatten(mixed)

        #expect(flat.count == 5)
        #expect(flat[0] as? Int == 1)
        #expect(flat[1] as? Int == 2)
        #expect(flat[2] as? Int == 3)
        #expect(flat[3] as? Int == 4)
        #expect(flat[4] as? Int == 5)
    }

    // MARK: - Collection Modification Operations Tests

    @Test("Including adds element to collection")
    func testIncluding() throws {
        let numbers = EcoreValueArray([1, 2, 3])
        let withFour = try including(numbers, 4 as Int)

        #expect(withFour.count == 4)
        #expect(withFour[0] as? Int == 1)
        #expect(withFour[1] as? Int == 2)
        #expect(withFour[2] as? Int == 3)
        #expect(withFour[3] as? Int == 4)
    }

    @Test("Including allows duplicates")
    func testIncludingDuplicate() throws {
        let numbers = EcoreValueArray([1, 2, 3])
        let withDuplicateTwo = try including(numbers, 2 as Int)

        #expect(withDuplicateTwo.count == 4)
        #expect(withDuplicateTwo[3] as? Int == 2)  // Duplicate added at end
    }

    @Test("Excluding removes all occurrences of element")
    func testExcluding() throws {
        let numbers = EcoreValueArray([1, 2, 2, 3, 2])
        let withoutTwos = try excluding(numbers, 2 as Int)

        #expect(withoutTwos.count == 2)
        #expect(withoutTwos[0] as? Int == 1)
        #expect(withoutTwos[1] as? Int == 3)
    }

    @Test("Excluding with non-existent element")
    func testExcludingNonExistent() throws {
        let numbers = EcoreValueArray([1, 2, 3])
        let withoutFours = try excluding(numbers, 4 as Int)

        #expect(withoutFours.count == 3)
        #expect(withoutFours[0] as? Int == 1)
        #expect(withoutFours[1] as? Int == 2)
        #expect(withoutFours[2] as? Int == 3)
    }

    // MARK: - Error Cases Tests

    @Test("Operations throw error for non-collection input")
    func testNonCollectionErrors() throws {
        let notACollection = 42 as Int

        #expect(throws: OCLError.invalidArguments("Value of type Int is not a collection")) {
            try select(notACollection) { _ in true }
        }

        #expect(throws: OCLError.invalidArguments("Value of type Int is not a collection")) {
            try first(notACollection)
        }

        #expect(throws: OCLError.invalidArguments("Value of type Int is not a collection")) {
            try includes(notACollection, 1)
        }
    }

    @Test("Size throws error for unsupported types")
    func testSizeError() throws {
        let notSizable = true as Bool

        #expect(throws: OCLError.invalidArguments("Cannot get size of Bool")) {
            try size(notSizable)
        }
    }

    @Test("IsEmpty throws error for unsupported types")
    func testIsEmptyError() throws {
        let notCheckable = 42 as Int

        #expect(throws: OCLError.invalidArguments("Cannot check isEmpty of Int")) {
            try isEmpty(notCheckable)
        }
    }

    // MARK: - EcoreValueArray Tests

    @Test("Operations work with EcoreValueArray")
    func testEcoreValueArray() throws {
        let array = EcoreValueArray([1, 2, 3])

        let sizeResult = try size(array)
        #expect(sizeResult == 3)

        let isEmptyResult = try isEmpty(array)
        #expect(isEmptyResult == false)

        let firstResult = try first(array)
        #expect(firstResult as? Int == 1)

        let selected = try select(array) { ($0 as? Int ?? 0) > 1 }
        #expect(selected.count == 2)
    }

    @Test("Operations work with empty EcoreValueArray")
    func testEmptyEcoreValueArray() throws {
        let array = EcoreValueArray([])

        let sizeResult = try size(array)
        #expect(sizeResult == 0)

        let isEmptyResult = try isEmpty(array)
        #expect(isEmptyResult == true)

        #expect(throws: OCLError.emptyCollection("first")) {
            try first(array)
        }
    }
}
