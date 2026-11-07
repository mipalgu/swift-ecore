//
// OCLLexerTests.swift
// OCLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import OCL


@Suite("OCL lexer")
struct OCLLexerTests {
    /// The kinds and texts of the tokens of a text, without the end of input.
    static func kinds(_ text: String) -> [(OCLToken.Kind, String)] {
        OCLLexer.tokenise(text).tokens.dropLast().map { ($0.kind, $0.text) }
    }

    @Test("Names, numbers and symbols are separated")
    func basicTokens() {
        let tokens = Self.kinds("self.books->size() <= 2.5")
        #expect(tokens.map(\.1) == ["self", ".", "books", "->", "size", "(", ")", "<=", "2.5"])
        #expect(tokens.map(\.0) == [.identifier, .symbol, .identifier, .symbol, .identifier, .symbol, .symbol, .symbol, .real])
    }

    @Test("A whole number before '..' stays whole", arguments: [
        ("1..5", ["1", "..", "5"]), ("1.5", ["1.5"]), ("2e3", ["2e3"]), ("2E-3", ["2E-3"]), ("3.x", ["3", ".", "x"]),
    ])
    func numbers(_ text: String, _ expected: [String]) {
        #expect(Self.kinds(text).map(\.1) == expected)
    }

    @Test("Compound symbols are read longest first")
    func compoundSymbols() {
        #expect(Self.kinds("a?->b?.c::d<>e<-f++g&&h^^i").map(\.1).filter { !$0.allSatisfy(\.isLetter) }
            == ["?->", "?.", "::", "<>", "<-", "++", "&&", "^^"])
    }

    @Test("Strings decode their escapes")
    func strings() {
        let token = OCLLexer.tokenise(#"'it\'s\nA\\'"#).tokens[0]
        #expect(token.kind == .string)
        #expect(token.value == "it's\nA\\")
        #expect(token.text == #"'it\'s\nA\\'"#)
    }

    @Test("Escaped names may hold any character and are never keywords")
    func escapedNames() {
        let token = OCLLexer.tokenise("_'class name'").tokens[0]
        #expect(token.kind == .escapedIdentifier)
        #expect(token.value == "class name")
        #expect(!OCLLexer.tokenise("_'class'").tokens[0].isWord("class"))
        #expect(OCLLexer.tokenise("class").tokens[0].isWord("class"))
    }

    @Test("Multi-line strings keep their text")
    func multiLineStrings() {
        let token = OCLLexer.tokenise("/'first\nsecond'/").tokens[0]
        #expect(token.kind == .multiLineString)
        #expect(token.value == "first\nsecond")
    }

    @Test("Comments are tokens that parsers skip")
    func comments() {
        let tokenisation = OCLLexer.tokenise("a -- note\n/* block\n */ b")
        #expect(tokenisation.tokens.map(\.kind) == [.identifier, .comment, .comment, .identifier, .endOfInput])
        #expect(tokenisation.significantTokens.map(\.text) == ["a", "b", ""])
    }

    @Test("Positions count lines and columns from one")
    func positions() {
        let tokens = OCLLexer.tokenise("a\n  'é' c").tokens
        #expect(tokens[1].range.start == SourcePosition(utf8Offset: 4, line: 2, column: 3))
        #expect(tokens[2].range.start.column == 7)
        #expect(tokens[2].range.start.utf8Offset == 9)
    }

    @Test("Problems become invalid tokens with diagnostics", arguments: [
        ("'open", OCLDiagnosticCode.unterminatedString), ("a $ b", OCLDiagnosticCode.invalidCharacter),
        ("/* open", OCLDiagnosticCode.unterminatedComment), ("/'open", OCLDiagnosticCode.unterminatedString),
    ])
    func problems(_ text: String, _ code: String) {
        let tokenisation = OCLLexer.tokenise(text)
        #expect(tokenisation.diagnostics.map(\.code) == [code])
        #expect(tokenisation.tokens.contains { $0.kind == .invalid })
    }

    @Test("Tokens are classified for highlighting")
    func classification() {
        let tokens = OCLLexer.tokenise("if true then 'a' else Set{1} endif -- c\n/** d */ $").tokens
        let kinds = OCLTokenClassifier.sourceTokens(of: tokens, keywords: OCLSyntax.reservedWords).map(\.kind)
        #expect(kinds == [.keyword, .boolean, .keyword, .string, .keyword, .typeName, .punctuation, .number, .punctuation,
            .keyword, .comment, .documentation, .invalid])
    }
}
