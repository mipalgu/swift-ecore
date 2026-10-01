//
// GenModelNamingTests.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Testing

@testable import GenModel

@Suite("GenModel naming")
struct GenModelNamingTests {
    @Test(
        "capName capitalises the first character only",
        arguments: [
            ("", ""), ("a", "A"), ("loanDays", "LoanDays"), ("Already", "Already"),
            ("éclair", "Éclair"),
        ])
    func capName(input: String, expected: String) {
        #expect(GenModelNaming.capName(input) == expected)
    }

    @Test(
        "uncapName lowercases the first character only",
        arguments: [("", ""), ("Book", "book"), ("XML", "xML"), ("book", "book")])
    func uncapName(input: String, expected: String) {
        #expect(GenModelNaming.uncapName(input) == expected)
    }

    @Test(
        "uncapPrefixedName lowers a leading capital run",
        arguments: [
            ("", ""), ("XSDElementContent", "xsdElementContent"), ("CPU", "cpu"), ("Book", "book"),
            ("book", "book"), ("A", "a"), ("XMLHttp2", "xmlHttp2"),
        ])
    func uncapPrefixedName(input: String, expected: String) {
        #expect(GenModelNaming.uncapPrefixedName(input) == expected)
    }

    @Test("uncapPrefixedName can force a different result")
    func uncapPrefixedNameForced() {
        #expect(GenModelNaming.uncapPrefixedName("book", forceDifferent: true) == "_book")
        #expect(GenModelNaming.uncapPrefixedName("Book", forceDifferent: true) == "book")
    }

    @Test(
        "upperName joins words with underscores in upper case",
        arguments: [
            ("loanDays", "LOAN_DAYS"), ("isbn", "ISBN"), ("XSDElement", "XSD_ELEMENT"),
            ("BookCategory", "BOOK_CATEGORY"), ("_private", "_PRIVATE"), ("name", "NAME"),
            ("a", "A"), ("eClassifiers", "ECLASSIFIERS"), ("UTF8Encoding", "UTF8_ENCODING"),
            ("x2", "X2"), ("a_b_c", "ABC"), ("", ""),
        ])
    func upperName(input: String, expected: String) {
        #expect(GenModelNaming.upperName(input) == expected)
    }

    @Test(
        "parseName splits at case changes and separators",
        arguments: [
            ("BookCategory", ["Book", "Category"]), ("XSDElement", ["XSD", "Element"]),
            ("a_b_c", ["a", "b", "c"]), ("__x", ["x"]), ("simple", ["simple"]),
        ])
    func parseName(input: String, expected: [String]) {
        #expect(GenModelNaming.parseName(input, separator: "_") == expected)
    }

    @Test("format treats a recognised prefix as a word")
    func formatPrefix() {
        #expect(
            GenModelNaming.format(
                "LibraryBook", separator: "_", prefix: "Library", includePrefix: true,
                includeLeadingSeparator: true) == "Library_Book")
        #expect(
            GenModelNaming.format(
                "LibraryBook", separator: "_", prefix: "Library", includePrefix: false) == "Book")
        #expect(
            GenModelNaming.format("Library", separator: "_", prefix: "Library", includePrefix: true)
                == "Library")
        #expect(
            GenModelNaming.format("Libraryan", separator: "-", prefix: "Library", includePrefix: true)
                == "Libraryan")
        #expect(GenModelNaming.format("", separator: "_", prefix: "P", includePrefix: true) == "P")
        #expect(
            GenModelNaming.format("BookCategory", separator: "-", prefix: nil, includePrefix: false)
                == "Book-Category")
    }

    @Test("format keeps leading underscores as one when asked")
    func formatLeadingSeparator() {
        #expect(
            GenModelNaming.format(
                "__fooBar", separator: "_", prefix: nil, includePrefix: false,
                includeLeadingSeparator: true) == "_foo_Bar")
        #expect(
            GenModelNaming.format(
                "__fooBar", separator: "_", prefix: nil, includePrefix: false,
                includeLeadingSeparator: false) == "foo_Bar")
    }
}
