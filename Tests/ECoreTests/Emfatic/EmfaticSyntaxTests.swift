//
// EmfaticSyntaxTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// Tests the tokens, outline and error recovery of the Emfatic reader.
@Suite("Emfatic syntax")
struct EmfaticSyntaxTests {
    /// The text of a token.
    private func text(of token: SourceToken, in source: String) -> String {
        let bytes = Array(source.utf8)
        return String(decoding: bytes[token.range.start.utf8Offset..<token.range.end.utf8Offset], as: UTF8.self)
    }

    /// Tokens are classified by their lexical kind and their role in the declaration.
    @Test func tokenKinds() {
        let source = """
            @GenModel(documentation="x") package p; // note
            /* block */ class A<T> extends B { attr String[*] s = 1; ref A#r r; attr boolean f = true; }
            enum E { one = 1; } class B {}
            """
        let tokens = EmfaticSyntax.tokens(in: source)
        let kinds = Dictionary(tokens.map { (text(of: $0, in: source), $0.kind) }, uniquingKeysWith: { first, _ in first })
        #expect(kinds["@"] == .directive)
        #expect(kinds["GenModel"] == .directive)
        #expect(kinds["\"x\""] == .string)
        #expect(kinds["package"] == .keyword)
        #expect(kinds["// note"] == .comment)
        #expect(kinds["/* block */"] == .comment)
        #expect(kinds["String"] == .typeName)
        #expect(kinds["B"] == .typeName)
        #expect(kinds["1"] == .number)
        #expect(kinds["true"] == .boolean)
        #expect(kinds["one"] == .enumLiteral)
        #expect(kinds["#"] == .operator)
        #expect(kinds["{"] == .punctuation)
        #expect(tokens == EmfaticReader.parse(source).tokens)
        #expect(zip(tokens, tokens.dropFirst()).allSatisfy { $0.range.start.utf8Offset < $1.range.start.utf8Offset })
    }

    /// Text that cannot be read becomes invalid tokens with diagnostics.
    @Test func invalidTokens() {
        let source = "package p; class A { attr String s = \"open\n; } ` 12ab"
        let result = EmfaticReader.parse(source)
        #expect(result.tokens.contains { $0.kind == .invalid })
        #expect(result.reports(.unterminatedString))
    }

    /// The outline lists packages, classifiers and members with stable identifiers.
    @Test func outline() throws {
        let result = parseCleanEmfatic(EmfaticFixtures.library)
        let root = try #require(result.outline.first)
        #expect(root.id == "package:library")
        #expect(root.kind == "package")
        #expect(root.detail == "http://example.org/library")
        let item = try #require(root.children.first)
        #expect(item.id == "package:library/class:Item")
        #expect(item.children.map(\.kind).contains("operation"))
        let identifier = try #require(item.children.first)
        #expect(identifier.id == "package:library/class:Item/attribute:identifier")
        #expect(identifier.detail == "String")
        #expect(root.children.map(\.kind).contains("interface"))
        #expect(root.children.map(\.kind).contains("enum"))
        #expect(root.children.map(\.kind).contains("datatype"))
        #expect(root.children.last?.kind == "package")
        let tags = try #require(item.children.first { $0.name == "tags" })
        #expect(tags.detail == "String[*]")
        #expect(tags.selectionRange.start.line == 10)
        #expect(tags.range.contains(tags.selectionRange))
    }

    /// Errors are reported with positions and reading carries on after them.
    @Test func recovery() throws {
        let source = """
            package shop;
            class Broken {
                attr String name
                banana split;
                ref Broken[1.. other;
                attr int count;
            }
            class Fine { attr String label; }
            weird stuff here;
            enum Colour { red; green }
            """
        let result = EmfaticReader.parse(source)
        #expect(!result.errors.isEmpty)
        #expect(result.errors.allSatisfy { $0.range != nil })
        let lines = Set(result.errors.compactMap { $0.range?.start.line })
        #expect(lines.contains(4))
        #expect(lines.contains(9))
        #expect(result.attribute("Fine", "label") != nil)
        #expect(result.attribute("Broken", "count") != nil)
        #expect(result.package?.getEEnum("Colour")?.literals.count == 2)
    }

    /// A document without a package declaration is reported but its classes are read.
    @Test func missingPackage() throws {
        let empty = EmfaticReader.parse("   // nothing\n")
        #expect(empty.packages.isEmpty)
        #expect(empty.reports(.missingPackage))
        let orphan = EmfaticReader.parse("class Lost { attr String name; }")
        #expect(orphan.reports(.missingPackage))
        #expect(orphan.eClass("Lost") != nil)
    }

    /// Imports after declarations and stray braces are reported.
    @Test func misplacedConstructs() {
        let result = EmfaticReader.parse("package p; class A {} import \"x\"; } class B {}")
        #expect(result.errors.count == 2)
        #expect(result.eClass("B") != nil)
    }

    /// An unterminated block comment is reported.
    @Test func unterminatedComment() {
        let result = EmfaticReader.parse("package p; /* never closed")
        #expect(result.reports(.unterminatedComment))
    }
}
