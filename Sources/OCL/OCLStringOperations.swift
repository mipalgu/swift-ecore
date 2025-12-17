//
// OCLStringOperations.swift
// OCL
//
//  Created by Rene Hexel on 18/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

// MARK: - String Operations

/// Converts a string to uppercase.
///
/// The toUpperCase operation returns a new string with all characters converted
/// to their uppercase equivalents using the current locale.
///
/// ## Examples
/// ```swift
/// let text = "hello world" as EString
/// let upper = try toUpperCase(text)  // Result: "HELLO WORLD"
/// ```
///
/// - Parameter string: The string to convert
/// - Returns: A new string with all characters in uppercase
/// - Throws: `OCLError.invalidArguments` if the value is not a string
@inlinable
public func toUpperCase(_ string: any EcoreValue) throws -> EString {
    guard let str = string as? EString else {
        throw OCLError.invalidArguments("toUpperCase requires a string, got \(type(of: string))")
    }
    return str.uppercased()
}

/// Converts a string to lowercase.
///
/// The toLowerCase operation returns a new string with all characters converted
/// to their lowercase equivalents using the current locale.
///
/// ## Examples
/// ```swift
/// let text = "HELLO WORLD" as EString
/// let lower = try toLowerCase(text)  // Result: "hello world"
/// ```
///
/// - Parameter string: The string to convert
/// - Returns: A new string with all characters in lowercase
/// - Throws: `OCLError.invalidArguments` if the value is not a string
@inlinable
public func toLowerCase(_ string: any EcoreValue) throws -> EString {
    guard let str = string as? EString else {
        throw OCLError.invalidArguments("toLowerCase requires a string, got \(type(of: string))")
    }
    return str.lowercased()
}

/// Extracts a substring from a string.
///
/// The substring operation returns a portion of the original string, starting
/// at the specified start index and ending before the end index. Indices are
/// 1-based as per OCL specification.
///
/// ## Examples
/// ```swift
/// let text = "Hello World" as EString
/// let sub = try substring(text, 1, 5)  // Result: "Hell"
/// let sub2 = try substring(text, 7, 12)  // Result: "World"
/// ```
///
/// - Parameters:
///   - string: The source string
///   - start: The starting index (1-based, inclusive)
///   - end: The ending index (1-based, exclusive)
/// - Returns: The extracted substring
/// - Throws: `OCLError.invalidArguments` if the value is not a string
/// - Throws: `OCLError.indexOutOfBounds` if indices are invalid
@inlinable
public func substring(
    _ string: any EcoreValue,
    _ start: any EcoreValue,
    _ end: any EcoreValue
) throws -> EString {
    guard let str = string as? EString else {
        throw OCLError.invalidArguments("substring requires a string, got \(type(of: string))")
    }

    guard let startIdx = start as? EInt else {
        throw OCLError.invalidArguments(
            "substring start index must be an integer, got \(type(of: start))")
    }

    guard let endIdx = end as? EInt else {
        throw OCLError.invalidArguments(
            "substring end index must be an integer, got \(type(of: end))")
    }

    // Convert from 1-based OCL indices to 0-based Swift indices
    let swiftStart = startIdx - 1
    let swiftEnd = endIdx - 1

    // Validate indices
    guard swiftStart >= 0 && swiftStart <= str.count else {
        throw OCLError.indexOutOfBounds(startIdx, str.count)
    }

    guard swiftEnd >= swiftStart && swiftEnd <= str.count else {
        throw OCLError.indexOutOfBounds(endIdx, str.count)
    }

    let startIndex = str.index(str.startIndex, offsetBy: swiftStart)
    let endIndex = str.index(str.startIndex, offsetBy: swiftEnd)

    return String(str[startIndex..<endIndex])
}

/// Concatenates two strings.
///
/// The concat operation returns a new string that is the result of appending
/// the second string to the first string.
///
/// ## Examples
/// ```swift
/// let hello = "Hello" as EString
/// let world = " World" as EString
/// let greeting = try concat(hello, world)  // Result: "Hello World"
/// ```
///
/// - Parameters:
///   - left: The first string
///   - right: The second string
/// - Returns: The concatenated string
/// - Throws: `OCLError.invalidArguments` if either value is not a string
@inlinable
public func concat(
    _ left: any EcoreValue,
    _ right: any EcoreValue
) throws -> EString {
    guard let leftStr = left as? EString else {
        throw OCLError.invalidArguments(
            "concat left operand must be a string, got \(type(of: left))")
    }

    guard let rightStr = right as? EString else {
        throw OCLError.invalidArguments(
            "concat right operand must be a string, got \(type(of: right))")
    }

    return leftStr + rightStr
}

/// Finds the index of the first occurrence of a substring within a string.
///
/// The indexOf operation searches for the first occurrence of the specified
/// substring and returns its 1-based index. If the substring is not found,
/// it returns 0 (following OCL conventions).
///
/// ## Examples
/// ```swift
/// let text = "Hello World" as EString
/// let index = try indexOf(text, "World")  // Result: 7
/// let notFound = try indexOf(text, "xyz")  // Result: 0
/// ```
///
/// - Parameters:
///   - string: The string to search in
///   - substring: The substring to search for
/// - Returns: The 1-based index of the first occurrence, or 0 if not found
/// - Throws: `OCLError.invalidArguments` if either value is not a string
@inlinable
public func indexOf(
    _ string: any EcoreValue,
    _ substring: any EcoreValue
) throws -> EInt {
    guard let str = string as? EString else {
        throw OCLError.invalidArguments("indexOf requires a string, got \(type(of: string))")
    }

    guard let subStr = substring as? EString else {
        throw OCLError.invalidArguments(
            "indexOf substring must be a string, got \(type(of: substring))")
    }

    // Handle empty substring - OCL spec: empty string is found at position 1
    if subStr.isEmpty {
        return 1
    }

    guard let range = str.range(of: subStr) else {
        return 0  // Not found
    }

    let index = str.distance(from: str.startIndex, to: range.lowerBound)
    return index + 1  // Convert to 1-based index
}

/// Returns the character at a specific position in a string.
///
/// The at operation returns the character at the specified 1-based index
/// in the string. This is useful for character-level string manipulation.
///
/// ## Examples
/// ```swift
/// let text = "Hello" as EString
/// let char = try at(text, 2)  // Result: "e"
/// let firstChar = try at(text, 1)  // Result: "H"
/// ```
///
/// - Parameters:
///   - string: The source string
///   - index: The position of the character (1-based)
/// - Returns: A single-character string
/// - Throws: `OCLError.invalidArguments` if the value is not a string or index is not an integer
/// - Throws: `OCLError.indexOutOfBounds` if the index is invalid
@inlinable
public func at(
    _ string: any EcoreValue,
    _ index: any EcoreValue
) throws -> EString {
    guard let str = string as? EString else {
        throw OCLError.invalidArguments("at requires a string, got \(type(of: string))")
    }

    guard let idx = index as? EInt else {
        throw OCLError.invalidArguments("at index must be an integer, got \(type(of: index))")
    }

    // Convert from 1-based OCL index to 0-based Swift index
    let swiftIndex = idx - 1

    guard swiftIndex >= 0 && swiftIndex < str.count else {
        throw OCLError.indexOutOfBounds(idx, str.count)
    }

    let stringIndex = str.index(str.startIndex, offsetBy: swiftIndex)
    return String(str[stringIndex])
}

/// Checks if a string starts with a specified prefix.
///
/// The startsWith operation tests whether the string begins with the
/// specified prefix string.
///
/// ## Examples
/// ```swift
/// let text = "Hello World" as EString
/// let startsWithHello = try startsWith(text, "Hello")  // Result: true
/// let startsWithWorld = try startsWith(text, "World")  // Result: false
/// ```
///
/// - Parameters:
///   - string: The string to test
///   - prefix: The prefix to check for
/// - Returns: `true` if the string starts with the prefix, `false` otherwise
/// - Throws: `OCLError.invalidArguments` if either value is not a string
@inlinable
public func startsWith(
    _ string: any EcoreValue,
    _ prefix: any EcoreValue
) throws -> EBoolean {
    guard let str = string as? EString else {
        throw OCLError.invalidArguments("startsWith requires a string, got \(type(of: string))")
    }

    guard let prefixStr = prefix as? EString else {
        throw OCLError.invalidArguments(
            "startsWith prefix must be a string, got \(type(of: prefix))")
    }

    return str.hasPrefix(prefixStr)
}

/// Checks if a string ends with a specified suffix.
///
/// The endsWith operation tests whether the string ends with the
/// specified suffix string.
///
/// ## Examples
/// ```swift
/// let text = "Hello World" as EString
/// let endsWithWorld = try endsWith(text, "World")  // Result: true
/// let endsWithHello = try endsWith(text, "Hello")  // Result: false
/// ```
///
/// - Parameters:
///   - string: The string to test
///   - suffix: The suffix to check for
/// - Returns: `true` if the string ends with the suffix, `false` otherwise
/// - Throws: `OCLError.invalidArguments` if either value is not a string
@inlinable
public func endsWith(
    _ string: any EcoreValue,
    _ suffix: any EcoreValue
) throws -> EBoolean {
    guard let str = string as? EString else {
        throw OCLError.invalidArguments("endsWith requires a string, got \(type(of: string))")
    }

    guard let suffixStr = suffix as? EString else {
        throw OCLError.invalidArguments("endsWith suffix must be a string, got \(type(of: suffix))")
    }

    return str.hasSuffix(suffixStr)
}

/// Trims whitespace from both ends of a string.
///
/// The trim operation removes leading and trailing whitespace characters
/// (spaces, tabs, newlines) from the string.
///
/// ## Examples
/// ```swift
/// let text = "  Hello World  " as EString
/// let trimmed = try trim(text)  // Result: "Hello World"
/// ```
///
/// - Parameter string: The string to trim
/// - Returns: A new string with leading and trailing whitespace removed
/// - Throws: `OCLError.invalidArguments` if the value is not a string
@inlinable
public func trim(_ string: any EcoreValue) throws -> EString {
    guard let str = string as? EString else {
        throw OCLError.invalidArguments("trim requires a string, got \(type(of: string))")
    }
    return str.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Replaces all occurrences of a substring with another string.
///
/// The replaceAll operation creates a new string where all occurrences
/// of the search string are replaced with the replacement string.
///
/// ## Examples
/// ```swift
/// let text = "Hello Hello World" as EString
/// let replaced = try replaceAll(text, "Hello", "Hi")  // Result: "Hi Hi World"
/// ```
///
/// - Parameters:
///   - string: The source string
///   - search: The substring to search for
///   - replacement: The string to replace with
/// - Returns: A new string with all occurrences replaced
/// - Throws: `OCLError.invalidArguments` if any value is not a string
@inlinable
public func replaceAll(
    _ string: any EcoreValue,
    _ search: any EcoreValue,
    _ replacement: any EcoreValue
) throws -> EString {
    guard let str = string as? EString else {
        throw OCLError.invalidArguments("replaceAll requires a string, got \(type(of: string))")
    }

    guard let searchStr = search as? EString else {
        throw OCLError.invalidArguments(
            "replaceAll search must be a string, got \(type(of: search))")
    }

    guard let replacementStr = replacement as? EString else {
        throw OCLError.invalidArguments(
            "replaceAll replacement must be a string, got \(type(of: replacement))")
    }

    return str.replacingOccurrences(of: searchStr, with: replacementStr)
}

/// Splits a string into an array of substrings using a delimiter.
///
/// The split operation divides the string into parts based on the specified
/// delimiter string, returning an array of the resulting substrings.
///
/// ## Examples
/// ```swift
/// let text = "apple,banana,cherry" as EString
/// let parts = try split(text, ",")  // Result: ["apple", "banana", "cherry"]
/// ```
///
/// - Parameters:
///   - string: The string to split
///   - delimiter: The delimiter to split on
/// - Returns: An array of substring parts
/// - Throws: `OCLError.invalidArguments` if either value is not a string
@inlinable
public func split(
    _ string: any EcoreValue,
    _ delimiter: any EcoreValue
) throws -> [any EcoreValue] {
    guard let str = string as? EString else {
        throw OCLError.invalidArguments("split requires a string, got \(type(of: string))")
    }

    guard let delimiterStr = delimiter as? EString else {
        throw OCLError.invalidArguments(
            "split delimiter must be a string, got \(type(of: delimiter))")
    }

    let parts = str.components(separatedBy: delimiterStr)
    return parts.map { $0 as any EcoreValue }
}

/// Checks if a string contains a specified substring.
///
/// The contains operation tests whether the string contains the specified
/// substring anywhere within it.
///
/// ## Examples
/// ```swift
/// let text = "Hello World" as EString
/// let containsWorld = try contains(text, "World")  // Result: true
/// let containsXyz = try contains(text, "xyz")  // Result: false
/// ```
///
/// - Parameters:
///   - string: The string to search in
///   - substring: The substring to search for
/// - Returns: `true` if the substring is found, `false` otherwise
/// - Throws: `OCLError.invalidArguments` if either value is not a string
@inlinable
public func contains(
    _ string: any EcoreValue,
    _ substring: any EcoreValue
) throws -> EBoolean {
    guard let str = string as? EString else {
        throw OCLError.invalidArguments("contains requires a string, got \(type(of: string))")
    }

    guard let subStr = substring as? EString else {
        throw OCLError.invalidArguments(
            "contains substring must be a string, got \(type(of: substring))")
    }

    // Handle empty substring - OCL spec: empty string is contained in all strings
    if subStr.isEmpty {
        return true
    }

    return str.contains(subStr)
}
