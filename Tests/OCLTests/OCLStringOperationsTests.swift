//
// OCLStringOperationsTests.swift
// OCLTests
//
// Created by Rene Hexel on 18/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//

import EMFBase
import Testing

@testable import OCL

@Suite("OCL String Operations")
struct OCLStringOperationsTests {

    // MARK: - String Case Conversion Tests

    @Test("toUpperCase converts string to uppercase")
    func testToUpperCase() throws {
        let text = "hello world" as String
        let result = try toUpperCase(text)

        #expect(result == "HELLO WORLD")
    }

    @Test("toUpperCase handles mixed case")
    func testToUpperCaseMixed() throws {
        let text = "Hello WoRLd" as String
        let result = try toUpperCase(text)

        #expect(result == "HELLO WORLD")
    }

    @Test("toUpperCase handles empty string")
    func testToUpperCaseEmpty() throws {
        let text = "" as String
        let result = try toUpperCase(text)

        #expect(result == "")
    }

    @Test("toUpperCase throws error for non-string")
    func testToUpperCaseError() throws {
        let notString = 42 as Int

        #expect(throws: OCLError.invalidArguments("toUpperCase requires a string, got Int")) {
            try toUpperCase(notString)
        }
    }

    @Test("toLowerCase converts string to lowercase")
    func testToLowerCase() throws {
        let text = "HELLO WORLD" as String
        let result = try toLowerCase(text)

        #expect(result == "hello world")
    }

    @Test("toLowerCase handles mixed case")
    func testToLowerCaseMixed() throws {
        let text = "HeLLo WoRLd" as String
        let result = try toLowerCase(text)

        #expect(result == "hello world")
    }

    @Test("toLowerCase handles empty string")
    func testToLowerCaseEmpty() throws {
        let text = "" as String
        let result = try toLowerCase(text)

        #expect(result == "")
    }

    @Test("toLowerCase throws error for non-string")
    func testToLowerCaseError() throws {
        let notString = true as Bool

        #expect(throws: OCLError.invalidArguments("toLowerCase requires a string, got Bool")) {
            try toLowerCase(notString)
        }
    }

    // MARK: - Substring Extraction Tests

    @Test("substring extracts correct portion")
    func testSubstring() throws {
        let text = "Hello World" as String
        let result = try substring(text, 1, 6)  // "Hello"

        #expect(result == "Hello")
    }

    @Test("substring extracts middle portion")
    func testSubstringMiddle() throws {
        let text = "Hello World" as String
        let result = try substring(text, 7, 12)  // "World"

        #expect(result == "World")
    }

    @Test("substring handles single character")
    func testSubstringSingleChar() throws {
        let text = "Hello" as String
        let result = try substring(text, 2, 3)  // "e"

        #expect(result == "e")
    }

    @Test("substring handles empty result")
    func testSubstringEmpty() throws {
        let text = "Hello" as String
        let result = try substring(text, 3, 3)  // empty

        #expect(result == "")
    }

    @Test("substring throws error for invalid start index")
    func testSubstringInvalidStart() throws {
        let text = "Hello" as String

        #expect(throws: OCLError.indexOutOfBounds(0, 5)) {
            try substring(text, 0, 3)
        }
    }

    @Test("substring throws error for invalid end index")
    func testSubstringInvalidEnd() throws {
        let text = "Hello" as String

        #expect(throws: OCLError.indexOutOfBounds(10, 5)) {
            try substring(text, 1, 10)
        }
    }

    @Test("substring throws error for non-string")
    func testSubstringNotString() throws {
        let notString = 42 as Int

        #expect(throws: OCLError.invalidArguments("substring requires a string, got Int")) {
            try substring(notString, 1, 3)
        }
    }

    @Test("substring throws error for non-integer indices")
    func testSubstringNotInteger() throws {
        let text = "Hello" as String

        #expect(
            throws: OCLError.invalidArguments(
                "substring start index must be an integer, got String")
        ) {
            try substring(text, "1" as String, 3)
        }
    }

    // MARK: - String Concatenation Tests

    @Test("concat joins two strings")
    func testConcat() throws {
        let left = "Hello" as String
        let right = " World" as String
        let result = try concat(left, right)

        #expect(result == "Hello World")
    }

    @Test("concat handles empty strings")
    func testConcatEmpty() throws {
        let left = "" as String
        let right = "Hello" as String
        let result = try concat(left, right)

        #expect(result == "Hello")
    }

    @Test("concat throws error for non-string left")
    func testConcatNotStringLeft() throws {
        let notString = 42 as Int
        let right = "World" as String

        #expect(throws: OCLError.invalidArguments("concat left operand must be a string, got Int"))
        {
            try concat(notString, right)
        }
    }

    @Test("concat throws error for non-string right")
    func testConcatNotStringRight() throws {
        let left = "Hello" as String
        let notString = true as Bool

        #expect(
            throws: OCLError.invalidArguments("concat right operand must be a string, got Bool")
        ) {
            try concat(left, notString)
        }
    }

    // MARK: - String Search Tests

    @Test("indexOf finds substring")
    func testIndexOf() throws {
        let text = "Hello World" as String
        let result = try indexOf(text, "World")

        #expect(result == 7)  // 1-based index
    }

    @Test("indexOf finds substring at start")
    func testIndexOfStart() throws {
        let text = "Hello World" as String
        let result = try indexOf(text, "Hello")

        #expect(result == 1)
    }

    @Test("indexOf returns 0 when not found")
    func testIndexOfNotFound() throws {
        let text = "Hello World" as String
        let result = try indexOf(text, "xyz")

        #expect(result == 0)
    }

    @Test("indexOf handles empty substring")
    func testIndexOfEmpty() throws {
        let text = "Hello World" as String
        let result = try indexOf(text, "")

        #expect(result == 1)  // Empty string found at start
    }

    @Test("indexOf throws error for non-string")
    func testIndexOfNotString() throws {
        let notString = 42 as Int

        #expect(throws: OCLError.invalidArguments("indexOf requires a string, got Int")) {
            try indexOf(notString, "test")
        }
    }

    @Test("at returns character at position")
    func testAt() throws {
        let text = "Hello" as String
        let result = try at(text, 2)

        #expect(result == "e")
    }

    @Test("at returns first character")
    func testAtFirst() throws {
        let text = "Hello" as String
        let result = try at(text, 1)

        #expect(result == "H")
    }

    @Test("at returns last character")
    func testAtLast() throws {
        let text = "Hello" as String
        let result = try at(text, 5)

        #expect(result == "o")
    }

    @Test("at throws error for invalid index")
    func testAtInvalidIndex() throws {
        let text = "Hello" as String

        #expect(throws: OCLError.indexOutOfBounds(10, 5)) {
            try at(text, 10)
        }
    }

    @Test("at throws error for zero index")
    func testAtZeroIndex() throws {
        let text = "Hello" as String

        #expect(throws: OCLError.indexOutOfBounds(0, 5)) {
            try at(text, 0)
        }
    }

    // MARK: - String Prefix and Suffix Tests

    @Test("startsWith returns true for valid prefix")
    func testStartsWithTrue() throws {
        let text = "Hello World" as String
        let result = try startsWith(text, "Hello")

        #expect(result == true)
    }

    @Test("startsWith returns false for invalid prefix")
    func testStartsWithFalse() throws {
        let text = "Hello World" as String
        let result = try startsWith(text, "World")

        #expect(result == false)
    }

    @Test("startsWith handles empty prefix")
    func testStartsWithEmpty() throws {
        let text = "Hello World" as String
        let result = try startsWith(text, "")

        #expect(result == true)  // All strings start with empty string
    }

    @Test("endsWith returns true for valid suffix")
    func testEndsWithTrue() throws {
        let text = "Hello World" as String
        let result = try endsWith(text, "World")

        #expect(result == true)
    }

    @Test("endsWith returns false for invalid suffix")
    func testEndsWithFalse() throws {
        let text = "Hello World" as String
        let result = try endsWith(text, "Hello")

        #expect(result == false)
    }

    @Test("endsWith handles empty suffix")
    func testEndsWithEmpty() throws {
        let text = "Hello World" as String
        let result = try endsWith(text, "")

        #expect(result == true)  // All strings end with empty string
    }

    // MARK: - String Manipulation Tests

    @Test("trim removes leading and trailing whitespace")
    func testTrim() throws {
        let text = "  Hello World  " as String
        let result = try trim(text)

        #expect(result == "Hello World")
    }

    @Test("trim handles tabs and newlines")
    func testTrimSpecialChars() throws {
        let text = "\t\nHello World\n\t" as String
        let result = try trim(text)

        #expect(result == "Hello World")
    }

    @Test("trim handles no whitespace")
    func testTrimNoWhitespace() throws {
        let text = "Hello World" as String
        let result = try trim(text)

        #expect(result == "Hello World")
    }

    @Test("replaceAll replaces all occurrences")
    func testReplaceAll() throws {
        let text = "Hello Hello World" as String
        let result = try replaceAll(text, "Hello", "Hi")

        #expect(result == "Hi Hi World")
    }

    @Test("replaceAll handles no matches")
    func testReplaceAllNoMatch() throws {
        let text = "Hello World" as String
        let result = try replaceAll(text, "xyz", "abc")

        #expect(result == "Hello World")
    }

    @Test("replaceAll handles empty replacement")
    func testReplaceAllEmpty() throws {
        let text = "Hello, World!" as String
        let result = try replaceAll(text, ",", "")

        #expect(result == "Hello World!")
    }

    // MARK: - String Splitting Tests

    @Test("split divides string by delimiter")
    func testSplit() throws {
        let text = "apple,banana,cherry" as String
        let result = try split(text, ",")

        #expect(result.count == 3)
        #expect(result[0] as? String == "apple")
        #expect(result[1] as? String == "banana")
        #expect(result[2] as? String == "cherry")
    }

    @Test("split handles no delimiter")
    func testSplitNoDelimiter() throws {
        let text = "hello" as String
        let result = try split(text, ",")

        #expect(result.count == 1)
        #expect(result[0] as? String == "hello")
    }

    @Test("split handles empty parts")
    func testSplitEmptyParts() throws {
        let text = "a,,b" as String
        let result = try split(text, ",")

        #expect(result.count == 3)
        #expect(result[0] as? String == "a")
        #expect(result[1] as? String == "")
        #expect(result[2] as? String == "b")
    }

    @Test("split handles multi-character delimiter")
    func testSplitMultiChar() throws {
        let text = "apple::banana::cherry" as String
        let result = try split(text, "::")

        #expect(result.count == 3)
        #expect(result[0] as? String == "apple")
        #expect(result[1] as? String == "banana")
        #expect(result[2] as? String == "cherry")
    }

    // MARK: - String Contains Tests

    @Test("contains returns true when substring found")
    func testContainsTrue() throws {
        let text = "Hello World" as String
        let result = try contains(text, "World")

        #expect(result == true)
    }

    @Test("contains returns false when substring not found")
    func testContainsFalse() throws {
        let text = "Hello World" as String
        let result = try contains(text, "xyz")

        #expect(result == false)
    }

    @Test("contains handles empty substring")
    func testContainsEmpty() throws {
        let text = "Hello World" as String
        let result = try contains(text, "")

        #expect(result == true)  // All strings contain empty string
    }

    @Test("contains is case sensitive")
    func testContainsCaseSensitive() throws {
        let text = "Hello World" as String
        let result = try contains(text, "hello")

        #expect(result == false)
    }

    @Test("contains throws error for non-string")
    func testContainsNotString() throws {
        let notString = 42 as Int

        #expect(throws: OCLError.invalidArguments("contains requires a string, got Int")) {
            try contains(notString, "test")
        }
    }

    // MARK: - Edge Cases and Error Handling

    @Test("String operations handle Unicode")
    func testUnicodeSupport() throws {
        let text = "Hello 🌍" as String

        let upperResult = try toUpperCase(text)
        #expect(upperResult == "HELLO 🌍")

        let lowerResult = try toLowerCase(text)
        #expect(lowerResult == "hello 🌍")

        let sizeResult = try size(text)
        #expect(sizeResult == 7)  // 6 ASCII characters + 1 emoji = 7 total
    }

    @Test("String operations handle special characters")
    func testSpecialCharacters() throws {
        let text = "Hello\nWorld\t!" as String

        let containsNewline = try contains(text, "\n")
        #expect(containsNewline == true)

        let containsTab = try contains(text, "\t")
        #expect(containsTab == true)

        let trimmed = try trim("  \(text)  ")
        #expect(trimmed == text)
    }

    @Test("String operations preserve immutability")
    func testImmutability() throws {
        let original = "hello world" as String

        let upper = try toUpperCase(original)
        #expect(upper == "HELLO WORLD")
        #expect(original == "hello world")  // Original unchanged

        let trimmed = try trim("  \(original)  ")
        #expect(trimmed == original)

        let replaced = try replaceAll(original, "world", "Swift")
        #expect(replaced == "hello Swift")
        #expect(original == "hello world")  // Original unchanged
    }
}
