//
// TextSupportCursorTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore




/// The namespace used for the diagnostics that the cursor tests produce.
private let shopNamespace = "shop"

/// Creates a cursor over the tokens of the given text.
private func makeCursor(_ text: String) -> TokenCursor {
    let configuration = LexicalConfiguration(
        identifierEscape: "~", punctuation: ["{", "}", "[", "]", ";", ":", ",", "..", "*", "+", "?", "="],
        stringDelimiters: ["\""])
    let scan = TextLexer.scan(text, configuration: configuration)
    return TokenCursor(tokens: scan.tokens, factory: DiagnosticFactory(namespace: shopNamespace, document: "shop.txt"))
}

/// Tests for the token cursor's navigation, expectations and recovery.
@Suite("Token cursor")
struct CursorTests {
    /// A cursor appends an end-of-file token when the tokens lack one.
    @Test func appendsMissingEndOfFile() {
        let factory = DiagnosticFactory(namespace: shopNamespace)
        let empty = TokenCursor(tokens: [], factory: factory)
        #expect(empty.isAtEnd)
        #expect(empty.current.range.start == .start)
        let range = SourceRange(
            start: SourcePosition(utf8Offset: 1, line: 1, column: 2),
            end: SourcePosition(utf8Offset: 3, line: 1, column: 4))
        let word = TextToken(kind: .identifier, text: "ab", range: range)
        let cursor = TokenCursor(tokens: [word], factory: factory)
        #expect(cursor.tokens.count == 2)
        #expect(cursor.tokens.last?.range.start == range.end)
    }

    /// Peeking looks ahead without consuming, and clamps at the end of the text.
    @Test func peeksAndClamps() {
        let cursor = makeCursor("a b")
        #expect(cursor.peek().text == "a")
        #expect(cursor.peek(1).text == "b")
        #expect(cursor.peek(99).kind == .endOfFile)
        #expect(cursor.position == 0)
        #expect(cursor.previous == nil)
    }

    /// Advancing returns the consumed token and stops at the end of the text.
    @Test func advancesUntilTheEnd() {
        var cursor = makeCursor("a")
        let first = cursor.advance()
        #expect(first.text == "a")
        #expect(cursor.previous?.text == "a")
        #expect(cursor.isAtEnd)
        let last = cursor.advance()
        #expect(last.kind == .endOfFile)
        #expect(cursor.position == 1)
    }

    /// Accepting consumes only matching punctuation or unescaped words.
    @Test func acceptsSymbolsAndWords() {
        var cursor = makeCursor("class ~class { x")
        let outcome1 = cursor.accept("class")
        #expect(!outcome1)
        let outcome2 = cursor.acceptWord("package")
        #expect(!outcome2)
        let outcome3 = cursor.acceptWord("class")
        #expect(outcome3)
        let outcome4 = cursor.acceptWord("class")
        #expect(!outcome4)
        cursor.advance()
        let outcome5 = cursor.accept("}")
        #expect(!outcome5)
        let outcome6 = cursor.accept("{")
        #expect(outcome6)
        #expect(cursor.diagnostics.isEmpty)
    }

    /// A failed expectation reports an unexpected-token error that names the token found.
    @Test func expectReportsFoundToken() throws {
        var cursor = makeCursor("book ;")
        let outcome7 = cursor.expect("{", "to open the shop")
        #expect(!outcome7)
        let diagnostic = try #require(cursor.diagnostics.first)
        #expect(diagnostic.code == "shop.unexpectedToken")
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.document == "shop.txt")
        #expect(diagnostic.message == "Expected '{' to open the shop but found 'book'")
        #expect(diagnostic.range == cursor.current.range)
    }

    /// A failed expectation at the end of the text says so.
    @Test func expectWordReportsEndOfText() throws {
        var cursor = makeCursor("")
        let outcome8 = cursor.expectWord("shop", "at the start")
        #expect(!outcome8)
        let message = try #require(cursor.diagnostics.first?.message)
        #expect(message == "Expected 'shop' at the start but found end of text")
    }

    /// Successful expectations consume the token without a diagnostic.
    @Test func successfulExpectationsAreSilent() {
        var cursor = makeCursor("shop {")
        let outcome9 = cursor.expectWord("shop", "first")
        #expect(outcome9)
        let outcome10 = cursor.expect("{", "second")
        #expect(outcome10)
        #expect(cursor.diagnostics.isEmpty)
    }

    /// Repeated errors at the same token are reported once.
    @Test func suppressesDuplicateErrorsAtTheSameToken() {
        var cursor = makeCursor("a b")
        cursor.unexpected("one")
        cursor.unexpected("two")
        #expect(cursor.diagnostics.count == 1)
        cursor.advance()
        cursor.unexpected("two")
        #expect(cursor.diagnostics.count == 2)
    }

    /// Reported diagnostics are appended unchanged.
    @Test func reportsDiagnostics() {
        var cursor = makeCursor("")
        let diagnostic = DiagnosticFactory(namespace: "x").warning(.lossyWrite, "Lossy", at: nil)
        cursor.report(diagnostic)
        cursor.report(diagnostic)
        #expect(cursor.diagnostics == [diagnostic, diagnostic])
    }

    /// Skipping stops at a wanted symbol, ignoring symbols inside nested braces.
    @Test func skipsToSymbolWithNestedBraces() {
        var cursor = makeCursor("a { b ; { c ; } } d ; e")
        cursor.skip(untilAny: [";"])
        #expect(cursor.current.text == ";")
        #expect(cursor.previous?.text == "d")
    }

    /// Skipping stops at a wanted unescaped word, but not at an escaped one.
    @Test func skipsToWord() {
        var cursor = makeCursor("a ~class b class c")
        cursor.skip(untilAny: [], orWords: ["class"])
        #expect(cursor.current.text == "class")
        #expect(cursor.previous?.text == "b")
    }

    /// Skipping stops at an unmatched closing brace and at the end of the text.
    @Test func skipsToClosingBraceOrEnd() {
        var cursor = makeCursor("a b } c")
        cursor.skip(untilAny: [";"])
        #expect(cursor.current.text == "}")
        var other = makeCursor("a b")
        other.skip(untilAny: [";"])
        #expect(other.isAtEnd)
    }

    /// Skipping a balanced block consumes it and returns its range.
    @Test func skipsBalancedBlock() throws {
        var cursor = makeCursor("{ a { b } c } d")
        let found11 = cursor.skipBlock()
        let range = try #require(found11)
        #expect(cursor.current.text == "d")
        #expect(range.start.utf8Offset == 0)
        #expect(range.end.utf8Offset == 13)
        #expect(cursor.diagnostics.isEmpty)
    }

    /// Skipping a block does nothing when the cursor is not at an opening brace.
    @Test func skipBlockRequiresOpeningBrace() {
        var cursor = makeCursor("a")
        let outcome12 = cursor.skipBlock()
        #expect(outcome12 == nil)
        #expect(cursor.position == 0)
    }

    /// An unterminated block reports an error and still returns a range.
    @Test func unterminatedBlockReportsError() throws {
        var cursor = makeCursor("{ a { b }")
        let found13 = cursor.skipBlock()
        let range = try #require(found13)
        #expect(cursor.isAtEnd)
        #expect(range.start.utf8Offset == 0)
        #expect(range.end.utf8Offset == 9)
        let message = try #require(cursor.diagnostics.first?.message)
        #expect(message.contains("'}' to close the block"))
        #expect(message.contains("end of text"))
    }

    /// Ranges run from a start position to the end of the previous token.
    @Test func rangeFromStart() {
        var cursor = makeCursor("ab cd")
        let start = cursor.current.range.start
        #expect(cursor.range(from: start).isEmpty)
        cursor.advance()
        cursor.advance()
        let range = cursor.range(from: start)
        #expect(range.start == start)
        #expect(range.end.utf8Offset == 5)
        let later = SourcePosition(utf8Offset: 99, line: 1, column: 100)
        #expect(cursor.range(from: later).end == later)
    }

    /// Multiplicities without brackets are not consumed.
    @Test func absentMultiplicityIsNil() {
        var cursor = makeCursor("name")
        let outcome14 = cursor.multiplicity()
        #expect(outcome14 == nil)
        #expect(cursor.position == 0)
    }

    /// Each supported multiplicity form yields the expected bounds.
    @Test(arguments: [
        ("[]", 0, -1), ("[*]", 0, -1), ("[+]", 1, -1), ("[?]", 0, 1), ("[3]", 3, 3), ("[1..4]", 1, 4),
        ("[2..*]", 2, -1), ("[2..?]", 2, -2), ("[*..3]", 0, -1), ("[0..1]", 0, 1), ("[1_0]", 10, 10),
    ])
    func readsMultiplicities(text: String, lower: Int, upper: Int) throws {
        var cursor = makeCursor(text + " next")
        let found15 = cursor.multiplicity()
        let bounds = try #require(found15)
        #expect(bounds.lower == lower)
        #expect(bounds.upper == upper)
        #expect(cursor.current.text == "next")
        #expect(cursor.diagnostics.isEmpty)
    }

    /// A malformed lower bound recovers to the default multiplicity.
    @Test func malformedLowerBoundRecovers() throws {
        var cursor = makeCursor("[x] next")
        let found16 = cursor.multiplicity()
        let bounds = try #require(found16)
        #expect(bounds.lower == 0)
        #expect(bounds.upper == 1)
        #expect(cursor.current.text == "next")
        #expect(cursor.diagnostics.first?.message.contains("a multiplicity bound") == true)
    }

    /// A missing upper bound keeps the lower bound and recovers.
    @Test func missingUpperBoundRecovers() throws {
        var cursor = makeCursor("[1..] next")
        let found17 = cursor.multiplicity()
        let bounds = try #require(found17)
        #expect(bounds.lower == 1)
        #expect(bounds.upper == 1)
        #expect(cursor.current.text == "next")
        #expect(cursor.diagnostics.first?.message.contains("an upper bound") == true)
    }

    /// A missing closing bracket is reported.
    @Test func missingClosingBracketIsReported() throws {
        var cursor = makeCursor("[3 next")
        let found18 = cursor.multiplicity()
        let bounds = try #require(found18)
        #expect(bounds.lower == 3)
        #expect(cursor.diagnostics.first?.message.contains("to close the multiplicity") == true)
    }
}
