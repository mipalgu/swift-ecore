//
// XcoreSyntaxTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// Tests the tokens, outline and error recovery of the Xcore reader.
@Suite("Xcore syntax")
struct XcoreSyntaxTests {
    /// The text of a token.
    private func text(of token: SourceToken, in source: String) -> String {
        let bytes = Array(source.utf8)
        return String(decoding: bytes[token.range.start.utf8Offset..<token.range.end.utf8Offset], as: UTF8.self)
    }

    /// Tokens are classified by their lexical kind and their role in the declaration.
    @Test func tokenKinds() {
        let source = """
            @GenModel(documentation="x") package p // note
            /** Docs. */ class A<T> extends B { String[*] s = "v" refers A r op int f() { 1 + 2 } }
            enum E { one = 1 } class B {}
            """
        let tokens = XcoreSyntax.tokens(in: source)
        let kinds = Dictionary(tokens.map { (text(of: $0, in: source), $0.kind) }, uniquingKeysWith: { first, _ in first })
        #expect(kinds["@"] == .directive)
        #expect(kinds["GenModel"] == .directive)
        #expect(kinds["package"] == .keyword)
        #expect(kinds["// note"] == .comment)
        #expect(kinds["/** Docs. */"] == .documentation)
        #expect(kinds["String"] == .typeName)
        #expect(kinds["B"] == .typeName)
        #expect(kinds["\"v\""] == .string)
        #expect(kinds["one"] == .enumLiteral)
        #expect(kinds["1"] == .number)
        #expect(kinds["+"] == .operator)
        #expect(tokens == XcoreReader.parse(source).tokens)
    }

    /// The outline lists the package, classifiers and members.
    @Test func outline() throws {
        let result = XcoreReader.parse(XcoreFixtures.library)
        let root = try #require(result.outline.first)
        #expect(root.id == "package:library")
        #expect(root.detail == "http://example.org/library")
        let item = try #require(root.children.first)
        #expect(item.id == "package:library/class:Item")
        #expect(item.children.map(\.name).contains("isLoanable"))
        let genre = try #require(root.children.first { $0.name == "Genre" })
        #expect(genre.kind == "enum")
        #expect(genre.children.map(\.detail) == ["0", "1", "5"])
        #expect(root.children.contains { $0.kind == "interface" && $0.name == "Described" })
    }

    /// Errors are reported with positions and reading carries on after them.
    @Test func recovery() throws {
        let source = """
            package shop
            class Broken {
                String
                refers Broken[1.. other
                int count
                % junk
            }
            class Fine { String label }
            weird stuff here
            enum Colour { red, green }
            """
        let result = XcoreReader.parse(source)
        #expect(!result.errors.isEmpty)
        #expect(result.errors.allSatisfy { $0.range != nil })
        let lines = Set(result.errors.compactMap { $0.range?.start.line })
        #expect(lines.contains(9))
        #expect(result.attribute("Fine", "label") != nil)
        #expect(result.attribute("Broken", "count") != nil)
        #expect(result.package?.getEEnum("Colour")?.literals.count == 2)
    }

    /// A document without a package declaration is reported but its classes are read.
    @Test func missingPackage() {
        let empty = XcoreReader.parse("/* nothing */")
        #expect(empty.packages.isEmpty)
        #expect(empty.reports(.missingPackage))
        let orphan = XcoreReader.parse("class Lost { String name }")
        #expect(orphan.reports(.missingPackage))
        #expect(orphan.eClass("Lost") != nil)
        #expect(orphan.package?.name == "_")
    }

    /// Imports after classifiers and malformed directives are reported.
    @Test func misplacedHeader() {
        let result = XcoreReader.parse("package p class A {} import x.Y annotation \"u\" Alias class B {}")
        #expect(result.errors.count >= 2)
        #expect(result.eClass("B") != nil)
    }

    /// Lexical problems outside bodies are errors; an unterminated body is reported.
    @Test func lexicalProblems() {
        #expect(XcoreReader.parse("package p class A { String s = \"open }").reports(.unterminatedString))
        #expect(XcoreReader.parse("package p class A { op void f() { ").reports(.unexpectedToken))
    }
}
