//
// OCLCollectionOperations.swift
// OCL
//
//  Created by Rene Hexel on 18/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

// MARK: - Collection Iterator Operations

/// Selects all elements from a collection that satisfy the given predicate.
///
/// The select operation filters a collection, returning a new collection containing only
/// those elements for which the predicate returns `true`. This operation preserves
/// the original order of elements.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 3, 4, 5] as [EInt]
/// let evens = try select(numbers) { ($0 as? EInt ?? 0) % 2 == 0 }
/// // Result: [2, 4]
/// ```
///
/// - Parameters:
///   - collection: The collection to filter
///   - predicate: A closure that takes an element and returns a Boolean value
/// - Returns: A new array containing elements that satisfy the predicate
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
/// - Throws: Any error thrown by the predicate
@inlinable
public func select(_ collection: any EcoreValue, _ predicate: (any EcoreValue) throws -> Bool) throws -> [any EcoreValue] {
    let elements = try extractElements(from: collection)
    return try elements.filter(predicate)
}

/// Rejects all elements from a collection that satisfy the given predicate.
///
/// The reject operation is the inverse of select, filtering a collection to exclude
/// elements for which the predicate returns `true`. This operation preserves
/// the original order of remaining elements.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 3, 4, 5] as [EInt]
/// let odds = try reject(numbers) { ($0 as? EInt ?? 0) % 2 == 0 }
/// // Result: [1, 3, 5]
/// ```
///
/// - Parameters:
///   - collection: The collection to filter
///   - predicate: A closure that takes an element and returns a Boolean value
/// - Returns: A new array containing elements that do not satisfy the predicate
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
/// - Throws: Any error thrown by the predicate
@inlinable
public func reject(_ collection: any EcoreValue, _ predicate: (any EcoreValue) throws -> Bool) throws -> [any EcoreValue] {
    let elements = try extractElements(from: collection)
    return try elements.filter { try !predicate($0) }
}

/// Transforms each element of a collection using the given transform function.
///
/// The collect operation applies a transformation to each element, creating a new
/// collection of the same size with the transformed elements. This is equivalent
/// to the map operation in functional programming.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 3] as [EInt]
/// let doubled = try collect(numbers) { ($0 as? EInt ?? 0) * 2 }
/// // Result: [2, 4, 6]
/// ```
///
/// - Parameters:
///   - collection: The collection to transform
///   - transform: A closure that takes an element and returns a transformed value
/// - Returns: A new array containing the transformed elements
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
/// - Throws: Any error thrown by the transform function
@inlinable
public func collect(_ collection: any EcoreValue, _ transform: (any EcoreValue) throws -> any EcoreValue) throws -> [any EcoreValue] {
    let elements = try extractElements(from: collection)
    return try elements.map(transform)
}

/// Tests whether at least one element in the collection satisfies the given predicate.
///
/// The exists operation returns `true` if any element in the collection satisfies
/// the predicate. If the collection is empty, it returns `false`.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 3, 4, 5] as [EInt]
/// let hasEven = try exists(numbers) { ($0 as? EInt ?? 0) % 2 == 0 }
/// // Result: true
/// ```
///
/// - Parameters:
///   - collection: The collection to test
///   - predicate: A closure that takes an element and returns a Boolean value
/// - Returns: `true` if any element satisfies the predicate, `false` otherwise
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
/// - Throws: Any error thrown by the predicate
@inlinable
public func exists(_ collection: any EcoreValue,_ predicate: (any EcoreValue) throws -> Bool) throws -> Bool {
    let elements = try extractElements(from: collection)
    return try elements.contains(where: predicate)
}

/// Tests whether all elements in the collection satisfy the given predicate.
///
/// The forAll operation returns `true` if every element in the collection satisfies
/// the predicate. If the collection is empty, it returns `true` (vacuous truth).
///
/// ## Examples
/// ```swift
/// let numbers = [2, 4, 6, 8] as [EInt]
/// let allEven = try forAll(numbers) { ($0 as? EInt ?? 0) % 2 == 0 }
/// // Result: true
/// ```
///
/// - Parameters:
///   - collection: The collection to test
///   - predicate: A closure that takes an element and returns a Boolean value
/// - Returns: `true` if all elements satisfy the predicate, `false` otherwise
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
/// - Throws: Any error thrown by the predicate
@inlinable
public func forAll(_ collection: any EcoreValue,_ predicate: (any EcoreValue) throws -> Bool) throws -> Bool {
    let elements = try extractElements(from: collection)
    return try elements.allSatisfy(predicate)
}

/// Tests whether exactly one element in the collection satisfies the given predicate.
///
/// The one operation returns `true` if exactly one element in the collection
/// satisfies the predicate. If zero elements or more than one element satisfies
/// the predicate, it returns `false`.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 3, 4] as [EInt]
/// let exactlyOneEven = try one(numbers) { ($0 as? EInt ?? 0) == 3 }
/// // Result: true
/// ```
///
/// - Parameters:
///   - collection: The collection to test
///   - predicate: A closure that takes an element and returns a Boolean value
/// - Returns: `true` if exactly one element satisfies the predicate, `false` otherwise
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
/// - Throws: Any error thrown by the predicate
@inlinable
public func one(_ collection: any EcoreValue,_ predicate: (any EcoreValue) throws -> Bool) throws -> Bool {
    let elements = try extractElements(from: collection)
    var count = 0
    for element in elements {
        if try predicate(element) {
            count += 1
            if count > 1 {
                return false
            }
        }
    }
    return count == 1
}

/// Accumulates elements of a collection using the given accumulator function.
///
/// The iterate operation performs a fold/reduce operation, starting with an initial
/// value and applying the accumulator function to each element in sequence.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 3, 4] as [EInt]
/// let sum = try iterate(numbers, 0 as EInt) { acc, elem in
///     (acc as? EInt ?? 0) + (elem as? EInt ?? 0)
/// }
/// // Result: 10
/// ```
///
/// - Parameters:
///   - collection: The collection to iterate over
///   - initial: The initial value for the accumulation
///   - accumulator: A closure that takes the current accumulated value and an element
/// - Returns: The final accumulated value
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
/// - Throws: Any error thrown by the accumulator function
@inlinable
public func iterate(_ collection: any EcoreValue, _ initial: any EcoreValue, _ accumulator: (any EcoreValue, any EcoreValue) throws -> any EcoreValue) throws -> any EcoreValue {
    let elements = try extractElements(from: collection)
    return try elements.reduce(initial, accumulator)
}

// MARK: - Collection Query Operations

/// Returns the number of elements in a collection or characters in a string.
///
/// The size operation works with collections, strings, and wrapped arrays.
/// For collections, it returns the element count. For strings, it returns
/// the character count.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 3] as [EInt]
/// let count = try size(numbers)  // Result: 3
///
/// let text = "Hello" as EString
/// let length = try size(text)    // Result: 5
/// ```
///
/// - Parameter value: The collection or string to measure
/// - Returns: The size as an integer
/// - Throws: `OCLError.invalidArguments` if the value cannot be measured
@inlinable
public func size(_ value: any EcoreValue) throws -> EInt {
    switch value {
    case let array as [any EcoreValue]:
        return array.count
    case let string as EString:
        return string.count
    case let wrapper as EcoreValueArray:
        return wrapper.values.count
    default:
        throw OCLError.invalidArguments("Cannot get size of \(type(of: value))")
    }
}

/// Tests whether a collection or string is empty.
///
/// The isEmpty operation returns `true` if the collection has no elements
/// or if the string has no characters.
///
/// ## Examples
/// ```swift
/// let empty: [EInt] = []
/// let result = try isEmpty(empty)  // Result: true
///
/// let text = "" as EString
/// let result2 = try isEmpty(text)  // Result: true
/// ```
///
/// - Parameter value: The collection or string to check
/// - Returns: `true` if empty, `false` otherwise
/// - Throws: `OCLError.invalidArguments` if the value cannot be checked for emptiness
@inlinable
public func isEmpty(_ value: any EcoreValue) throws -> EBoolean {
    switch value {
    case let array as [any EcoreValue]:
        return array.isEmpty
    case let string as EString:
        return string.isEmpty
    case let wrapper as EcoreValueArray:
        return wrapper.values.isEmpty
    default:
        throw OCLError.invalidArguments("Cannot check isEmpty of \(type(of: value))")
    }
}

/// Tests whether a collection or string is not empty.
///
/// The notEmpty operation is the logical inverse of isEmpty, returning `true`
/// if the collection has at least one element or if the string has at least
/// one character.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 3] as [EInt]
/// let result = try notEmpty(numbers)  // Result: true
/// ```
///
/// - Parameter value: The collection or string to check
/// - Returns: `true` if not empty, `false` otherwise
/// - Throws: `OCLError.invalidArguments` if the value cannot be checked for emptiness
@inlinable
public func notEmpty(_ value: any EcoreValue) throws -> EBoolean {
    return try !isEmpty(value)
}

/// Returns the first element of a collection.
///
/// The first operation returns the first element of a non-empty collection.
/// If the collection is empty, it throws an error.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 3] as [EInt]
/// let firstNum = try first(numbers)  // Result: 1
/// ```
///
/// - Parameter collection: The collection to get the first element from
/// - Returns: The first element of the collection
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
/// - Throws: `OCLError.emptyCollection` if the collection is empty
@inlinable
public func first(_ collection: any EcoreValue) throws -> any EcoreValue {
    let elements = try extractElements(from: collection)
    guard let firstElement = elements.first else {
        throw OCLError.emptyCollection("first")
    }
    return firstElement
}

/// Returns the last element of a collection.
///
/// The last operation returns the last element of a non-empty collection.
/// If the collection is empty, it throws an error.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 3] as [EInt]
/// let lastNum = try last(numbers)  // Result: 3
/// ```
///
/// - Parameter collection: The collection to get the last element from
/// - Returns: The last element of the collection
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
/// - Throws: `OCLError.emptyCollection` if the collection is empty
@inlinable
public func last(_ collection: any EcoreValue) throws -> any EcoreValue {
    let elements = try extractElements(from: collection)
    guard let lastElement = elements.last else {
        throw OCLError.emptyCollection("last")
    }
    return lastElement
}

// MARK: - Collection Set Operations

/// Returns the union of two collections.
///
/// The union operation combines two collections, removing duplicates.
/// The result contains all unique elements from both collections.
///
/// ## Examples
/// ```swift
/// let set1 = [1, 2, 3] as [EInt]
/// let set2 = [3, 4, 5] as [EInt]
/// let combined = try union(set1, set2)  // Result: [1, 2, 3, 4, 5]
/// ```
///
/// - Parameters:
///   - left: The first collection
///   - right: The second collection
/// - Returns: A new array containing the union of both collections
/// - Throws: `OCLError.invalidArguments` if either value is not a collection
@inlinable
public func union(_ left: any EcoreValue, _ right: any EcoreValue) throws -> [any EcoreValue] {
    let leftElements = try extractElements(from: left)
    let rightElements = try extractElements(from: right)

    var result: [any EcoreValue] = []
    var seen = Set<String>()

    for element in leftElements + rightElements {
        let key = elementKey(element)
        if !seen.contains(key) {
            result.append(element)
            seen.insert(key)
        }
    }

    return result
}

/// Returns the intersection of two collections.
///
/// The intersection operation returns elements that appear in both collections,
/// with duplicates removed.
///
/// ## Examples
/// ```swift
/// let set1 = [1, 2, 3] as [EInt]
/// let set2 = [2, 3, 4] as [EInt]
/// let common = try intersection(set1, set2)  // Result: [2, 3]
/// ```
///
/// - Parameters:
///   - left: The first collection
///   - right: The second collection
/// - Returns: A new array containing elements present in both collections
/// - Throws: `OCLError.invalidArguments` if either value is not a collection
@inlinable
public func intersection(_ left: any EcoreValue, _ right: any EcoreValue) throws -> [any EcoreValue] {
    let leftElements = try extractElements(from: left)
    let rightElements = try extractElements(from: right)

    let rightKeys = Set(rightElements.map(elementKey))
    var result: [any EcoreValue] = []
    var seen = Set<String>()

    for element in leftElements {
        let key = elementKey(element)
        if rightKeys.contains(key) && !seen.contains(key) {
            result.append(element)
            seen.insert(key)
        }
    }

    return result
}

/// Returns the difference between two collections.
///
/// The difference operation returns elements that are in the left collection
/// but not in the right collection.
///
/// ## Examples
/// ```swift
/// let set1 = [1, 2, 3, 4] as [EInt]
/// let set2 = [2, 3] as [EInt]
/// let diff = try difference(set1, set2)  // Result: [1, 4]
/// ```
///
/// - Parameters:
///   - left: The first collection (minuend)
///   - right: The second collection (subtrahend)
/// - Returns: A new array containing elements in left but not in right
/// - Throws: `OCLError.invalidArguments` if either value is not a collection
@inlinable
public func difference(_ left: any EcoreValue, _ right: any EcoreValue) throws -> [any EcoreValue] {
    let leftElements = try extractElements(from: left)
    let rightElements = try extractElements(from: right)

    let rightKeys = Set(rightElements.map(elementKey))
    var result: [any EcoreValue] = []
    var seen = Set<String>()

    for element in leftElements {
        let key = elementKey(element)
        if !rightKeys.contains(key) && !seen.contains(key) {
            result.append(element)
            seen.insert(key)
        }
    }

    return result
}

// MARK: - Collection Membership Operations

/// Tests whether a collection contains a specific element.
///
/// The includes operation returns `true` if the element is present in
/// the collection, using equality comparison.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 3] as [EInt]
/// let hasTwo = try includes(numbers, 2 as EInt)  // Result: true
/// ```
///
/// - Parameters:
///   - collection: The collection to search in
///   - element: The element to search for
/// - Returns: `true` if the element is found, `false` otherwise
/// - Throws: `OCLError.invalidArguments` if the first value is not a collection
@inlinable
public func includes(_ collection: any EcoreValue, _ element: any EcoreValue) throws -> Bool {
    let elements = try extractElements(from: collection)
    return elements.contains { areEqual($0, element) }
}

/// Tests whether a collection does not contain a specific element.
///
/// The excludes operation is the logical inverse of includes, returning `true`
/// if the element is not present in the collection.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 3] as [EInt]
/// let hasNoFour = try excludes(numbers, 4 as EInt)  // Result: true
/// ```
///
/// - Parameters:
///   - collection: The collection to search in
///   - element: The element to search for
/// - Returns: `true` if the element is not found, `false` otherwise
/// - Throws: `OCLError.invalidArguments` if the first value is not a collection
@inlinable
public func excludes(_ collection: any EcoreValue, _ element: any EcoreValue) throws -> Bool {
    return try !includes(collection, element)
}

// MARK: - Collection Type Conversion Operations

/// Converts a collection to a set by removing duplicates.
///
/// The asSet operation creates a new collection with duplicate elements
/// removed, preserving the order of first occurrence.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 2, 3, 3, 3] as [EInt]
/// let uniqueNums = try asSet(numbers)  // Result: [1, 2, 3]
/// ```
///
/// - Parameter collection: The collection to convert
/// - Returns: A new array with duplicates removed
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
@inlinable
public func asSet(_ collection: any EcoreValue) throws -> [any EcoreValue] {
    let elements = try extractElements(from: collection)
    var result: [any EcoreValue] = []
    var seen = Set<String>()

    for element in elements {
        let key = elementKey(element)
        if !seen.contains(key) {
            result.append(element)
            seen.insert(key)
        }
    }

    return result
}

/// Converts a collection to a sequence.
///
/// The asSequence operation returns the collection as an ordered sequence.
/// This is effectively a no-op in this implementation but provided for
/// OCL compatibility.
///
/// - Parameter collection: The collection to convert
/// - Returns: A new array representing the sequence
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
@inlinable
public func asSequence(_ collection: any EcoreValue) throws -> [any EcoreValue] {
    return try extractElements(from: collection)
}

/// Converts a collection to a bag (allowing duplicates).
///
/// The asBag operation returns the collection as is, since bags allow
/// duplicates. This is effectively a no-op but provided for OCL compatibility.
///
/// - Parameter collection: The collection to convert
/// - Returns: A new array representing the bag
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
@inlinable
public func asBag(_ collection: any EcoreValue) throws -> [any EcoreValue] {
    return try extractElements(from: collection)
}

/// Converts a collection to an ordered set.
///
/// The asOrderedSet operation creates a new collection with duplicates removed
/// whilst preserving the original order of first occurrence.
///
/// - Parameter collection: The collection to convert
/// - Returns: A new array with duplicates removed in original order
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
@inlinable
public func asOrderedSet(_ collection: any EcoreValue) throws -> [any EcoreValue] {
    return try asSet(collection)  // Same implementation as asSet
}

/// Flattens a nested collection structure.
///
/// The flatten operation takes a collection of collections and returns a single
/// flat collection containing all elements from the nested collections.
///
/// ## Examples
/// ```swift
/// let nested = [[1, 2], [3, 4], [5]] as [[EInt]]
/// let flat = try flatten(nested)  // Result: [1, 2, 3, 4, 5]
/// ```
///
/// - Parameter collection: The nested collection to flatten
/// - Returns: A new flattened array
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
@inlinable
public func flatten(_ collection: any EcoreValue) throws -> [any EcoreValue] {
    let elements = try extractElements(from: collection)
    var result: [any EcoreValue] = []

    for element in elements {
        do {
            let subElements = try extractElements(from: element)
            result.append(contentsOf: subElements)
        } catch {
            // If element is not a collection, add it directly
            result.append(element)
        }
    }

    return result
}

// MARK: - Collection Modification Operations

/// Returns a new collection with an element added.
///
/// The including operation creates a new collection containing all elements
/// from the original collection plus the new element. If the element already
/// exists, it may appear multiple times.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 3] as [EInt]
/// let withFour = try including(numbers, 4 as EInt)  // Result: [1, 2, 3, 4]
/// ```
///
/// - Parameters:
///   - collection: The original collection
///   - element: The element to add
/// - Returns: A new array with the element added
/// - Throws: `OCLError.invalidArguments` if the first value is not a collection
@inlinable
public func including(
    _ collection: any EcoreValue,
    _ element: any EcoreValue
) throws -> [any EcoreValue] {
    var elements = try extractElements(from: collection)
    elements.append(element)
    return elements
}

/// Returns a new collection with all occurrences of an element removed.
///
/// The excluding operation creates a new collection containing all elements
/// from the original collection except those equal to the specified element.
///
/// ## Examples
/// ```swift
/// let numbers = [1, 2, 2, 3] as [EInt]
/// let withoutTwos = try excluding(numbers, 2 as EInt)  // Result: [1, 3]
/// ```
///
/// - Parameters:
///   - collection: The original collection
///   - element: The element to remove
/// - Returns: A new array with the element removed
/// - Throws: `OCLError.invalidArguments` if the first value is not a collection
@inlinable
public func excluding(_ collection: any EcoreValue, _ element: any EcoreValue) throws -> [any EcoreValue] {
    let elements = try extractElements(from: collection)
    return elements.filter { !areEqual($0, element) }
}

// MARK: - Helper Functions

/// Extracts an array of elements from various collection types.
///
/// This helper function normalises different collection representations
/// into a standard array format for processing by other operations.
///
/// - Parameter value: The collection value to extract elements from
/// - Returns: An array of elements
/// - Throws: `OCLError.invalidArguments` if the value is not a collection
@inlinable
func extractElements(from value: any EcoreValue) throws -> [any EcoreValue] {
    switch value {
    case let array as [any EcoreValue]:
        return array
    case let wrapper as EcoreValueArray:
        return wrapper.values
    default:
        throw OCLError.invalidArguments("Value of type \(type(of: value)) is not a collection")
    }
}

/// Creates a unique string key for an element for use in set operations.
///
/// This helper function creates a consistent string representation of any
/// EcoreValue for use in deduplication and comparison operations.
///
/// - Parameter element: The element to create a key for
/// - Returns: A string key representing the element
@inlinable
func elementKey(_ element: any EcoreValue) -> String {
    switch element {
    case let string as String:
        return "String:\(string)"
    case let int as Int:
        return "Int:\(int)"
    case let double as Double:
        return "Double:\(double)"
    case let bool as Bool:
        return "Bool:\(bool)"
    case let float as Float:
        return "Float:\(float)"
    default:
        return "Unknown:\(String(describing: element))"
    }
}
