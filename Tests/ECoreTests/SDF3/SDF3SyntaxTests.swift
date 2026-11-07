//
// SDF3SyntaxTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// Tests of tokens and outlines.
@Suite("SDF3 tokens and outline")
struct SDF3SyntaxTests {
    /// A short module with a template, a comment and a lexical section.
    static let source = """
        module m
        context-free syntax
          Exp.Add = <<lhs:Exp> + <Exp>> // sum
        lexical syntax
          ID = [a-z]+
        """

    /// The source text that a token covers.
    ///
    /// - Parameters:
    ///   - token: The token.
    ///   - text: The whole source text.
    /// - Returns: The covered text.
    private func text(of token: SourceToken, in text: String) -> String {
        let bytes = Array(text.utf8)
        return String(decoding: bytes[token.range.start.utf8Offset..<token.range.end.utf8Offset], as: UTF8.self)
    }

    /// Tokens are classified by their role.
    @Test func classification() throws {
        let tokens = SDF3Syntax.tokens(in: Self.source)
        let pairs = tokens.map { (text(of: $0, in: Self.source), $0.kind) }
        let expected: [(String, SourceTokenKind)] = [
            ("module", .keyword), ("m", .identifier), ("context-free", .keyword), ("syntax", .keyword),
            ("Exp", .typeName), (".", .punctuation), ("Add", .identifier), ("=", .punctuation),
            ("<", .punctuation), ("<", .punctuation), ("lhs", .identifier), (":", .punctuation),
            ("Exp", .typeName), (">", .punctuation), ("+", .text), ("<", .punctuation), ("Exp", .typeName),
            (">", .punctuation), (">", .punctuation), ("// sum", .comment), ("lexical", .keyword),
            ("syntax", .keyword), ("ID", .typeName), ("=", .punctuation), ("[a-z]", .string), ("+", .operator),
        ]
        #expect(pairs.count == expected.count)
        for (actual, wanted) in zip(pairs, expected) {
            #expect(actual.0 == wanted.0)
            #expect(actual.1 == wanted.1)
        }
        let add = try #require(tokens.first { text(of: $0, in: Self.source) == "Add" })
        #expect(add.range.start.line == 3)
        #expect(add.range.start.column == 7)
    }

    /// The parse result carries the same tokens as the tokeniser.
    @Test func resultTokens() {
        #expect(read(Self.source).tokens == SDF3Syntax.tokens(in: Self.source))
    }

    /// Stratego constructors and invalid characters are classified.
    @Test func strategoTokens() {
        let source = "signature constructors\n  Add : Exp * Exp -> Exp %"
        let kinds = SDF3Syntax.tokens(in: source).map(\.kind)
        #expect(kinds == [
            .keyword, .keyword, .identifier, .punctuation, .typeName, .operator, .typeName, .operator, .typeName,
            .invalid,
        ])
    }

    /// The outline holds the module, its sections and their entries.
    @Test func outline() throws {
        let result = read("""
            module lang/Exprs
            imports Common
            context-free sorts Exp
            context-free syntax
              Exp.Add = <<Exp> + <Exp>>
              Exp = Term
            signature constructors
              Neg : Exp -> Exp
            """)
        let module = try #require(result.outline.first)
        #expect(result.outline.count == 1)
        #expect(module.kind == SDF3OutlineKind.module)
        #expect(module.name == "lang/Exprs")
        #expect(module.children.map(\.name) == [
            "imports", "context-free sorts", "context-free syntax", "signature constructors",
        ])
        #expect(module.children.map(\.kind).allSatisfy { $0 == SDF3OutlineKind.section })
        #expect(module.children[0].children.map(\.kind) == [SDF3OutlineKind.importedModule])
        #expect(module.children[1].children.map(\.name) == ["Exp"])
        #expect(module.children[1].children.map(\.kind) == [SDF3OutlineKind.sort])
        let syntax = module.children[2].children
        #expect(syntax.map(\.kind) == [SDF3OutlineKind.constructor, SDF3OutlineKind.injection])
        #expect(syntax.first?.name == "Exp.Add")
        #expect(syntax.first?.detail == "Exp * Exp")
        #expect(syntax.first?.selectionRange.start.column == 7)
        let signature = module.children[3].children
        #expect(signature.first?.name == "Neg")
        #expect(signature.first?.detail == "Exp -> Exp")
        let identifiers = module.children.flatMap { [$0.id] + $0.children.map(\.id) }
        #expect(Set(identifiers).count == identifiers.count)
        #expect(module.range.end.line == 8)
    }
}
