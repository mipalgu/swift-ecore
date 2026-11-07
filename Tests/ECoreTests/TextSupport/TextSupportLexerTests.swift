//
// TextSupportLexerTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore



/// A lexical configuration resembling a small shop-domain notation, used by the lexer tests.
private func shopConfiguration(decodesEscapes: Bool = true) -> LexicalConfiguration {
    LexicalConfiguration(
        identifierEscape: "~",
        punctuation: ["{", "}", "[", "]", ";", ":", ",", ".", "..", "<", ">", "?", "*", "+", "=", "@", "->", "-"],
        stringDelimiters: ["\""], characterDelimiter: "'", extraIdentifierCharacters: ["$"],
        decodesEscapes: decodesEscapes)
}

/// Scans the text with the shop configuration.
private func scan(_ text: String, decodesEscapes: Bool = true) -> LexicalScan {
    TextLexer.scan(text, configuration: shopConfiguration(decodesEscapes: decodesEscapes))
}

/// Scans the text and returns the tokens other than the end-of-file token.
private func tokens(_ text: String) -> [TextToken] {
    Array(scan(text).tokens.dropLast())
}

/// Tests for the scanning of identifiers, literals, comments and punctuation.
@Suite("Text lexer")
struct LexerTests {
    /// Plain identifiers, underscores, digits and the extra identifier characters are accepted.
    @Test func scansIdentifiers() {
        let result = tokens("Book _shelf item2 $price")
        #expect(result.map(\.kind) == [.identifier, .identifier, .identifier, .identifier])
        #expect(result.map(\.text) == ["Book", "_shelf", "item2", "$price"])
        #expect(result.allSatisfy { !$0.isEscaped })
    }

    /// An escaped identifier drops its escape character from the value but not from the text.
    @Test func scansEscapedIdentifiers() throws {
        let token = try #require(tokens("~class").first)
        #expect(token.kind == .identifier)
        #expect(token.text == "~class")
        #expect(token.value == "class")
        #expect(token.isEscaped)
        #expect(!token.isWord("class"))
    }

    /// An escape character that is not followed by an identifier start is unexpected.
    @Test func escapeWithoutIdentifierIsUnexpected() {
        let result = scan("~ 1")
        #expect(result.tokens.first?.kind == .invalid)
        #expect(result.problems.first?.kind == .unexpectedCharacter)
    }

    /// An unescaped word is recognised by `isWord`, and punctuation by `isPunctuation`.
    @Test func tokenPredicates() throws {
        let result = tokens("class {")
        #expect(result[0].isWord("class"))
        #expect(!result[0].isWord("other"))
        #expect(result[1].isPunctuation("{"))
        #expect(!result[1].isPunctuation("}"))
        #expect(!result[0].isPunctuation("class"))
        #expect(!result[0].isComment)
    }

    /// Strings decode their escapes by default.
    @Test func decodesStringEscapes() throws {
        let token = try #require(tokens(#""a\tb\"c\\d""#).first)
        #expect(token.kind == .string)
        #expect(token.value == "a\tb\"c\\d")
        #expect(token.text == #""a\tb\"c\\d""#)
    }

    /// Strings keep their raw escapes when decoding is disabled.
    @Test func keepsRawEscapesWhenNotDecoding() throws {
        let token = try #require(scan(#""a\nb""#, decodesEscapes: false).tokens.first)
        #expect(token.value == #"a\nb"#)
    }

    /// Strings may span several lines.
    @Test func scansMultiLineStrings() throws {
        let result = scan("\"one\ntwo\" next")
        let token = try #require(result.tokens.first)
        #expect(token.value == "one\ntwo")
        #expect(token.range.end.line == 2)
        #expect(result.tokens[1].range.start.line == 2)
        #expect(result.problems.isEmpty)
    }

    /// Character literals use their own delimiter and decode escapes.
    @Test func scansCharacterLiterals() throws {
        let result = tokens(#"'x' '\n'"#)
        #expect(result.map(\.kind) == [.character, .character])
        #expect(result.map(\.value) == ["x", "\n"])
    }

    /// An unterminated string is invalid and records a problem.
    @Test func unterminatedStringIsReported() {
        let result = scan("\"open")
        #expect(result.tokens.first?.kind == .invalid)
        #expect(result.problems.map(\.kind) == [.unterminatedString])
        #expect(result.tokens.last?.kind == .endOfFile)
    }

    /// A backslash at the very end of an unterminated string does not crash the scan.
    @Test func trailingBackslashInStringIsUnterminated() {
        let result = scan("\"open\\")
        #expect(result.problems.map(\.kind) == [.unterminatedString])
    }

    /// Integers, reals, hexadecimal numbers and suffixes are classified.
    @Test func scansNumbers() {
        let result = tokens("42 1_000 3.14 1e5 2E-3 1.5e+2 0x1F 0XaB 10L 2d 3f 4bi 5bd 0x1F#L")
        let expected: [TextTokenKind] = [
            .integer, .integer, .real, .real, .real, .real, .integer, .integer, .integer, .real, .real, .integer,
            .real, .integer,
        ]
        #expect(result.map(\.kind) == expected)
        #expect(result.map(\.text).first == "42")
        #expect(result.last?.text == "0x1F#L")
    }

    /// A dot that is not followed by a digit is not part of the number.
    @Test func dotWithoutDigitEndsTheNumber() {
        let result = tokens("1..4")
        #expect(result.map(\.text) == ["1", "..", "4"])
        #expect(result.map(\.kind) == [.integer, .punctuation, .integer])
    }

    /// An exponent marker without digits is treated as an invalid suffix.
    @Test func exponentWithoutDigitsIsInvalid() {
        let result = scan("1e")
        #expect(result.tokens.first?.kind == .invalid)
        #expect(result.problems.map(\.kind) == [.invalidNumber])
    }

    /// Unknown number suffixes are invalid numbers.
    @Test func invalidNumberSuffixIsReported() throws {
        let result = scan("12abc 7")
        #expect(result.tokens[0].kind == .invalid)
        #expect(result.tokens[0].text == "12abc")
        #expect(result.problems.first?.kind == .invalidNumber)
        #expect(result.problems.first?.message.contains("12abc") == true)
        #expect(result.tokens[1].kind == .integer)
    }

    /// Unexpected characters are recorded and scanning continues.
    @Test func unexpectedCharactersAreRecorded() {
        let result = scan("a # b % c")
        #expect(result.tokens.map(\.kind) == [.identifier, .invalid, .identifier, .invalid, .identifier, .endOfFile])
        #expect(result.problems.count == 2)
        #expect(result.problems.allSatisfy { $0.kind == .unexpectedCharacter })
        #expect(result.problems[0].message.contains("#"))
    }

    /// Line comments run up to, but exclude, the line ending.
    @Test func scansLineComments() {
        let result = scan("a // note\r\nb")
        #expect(result.comments.map(\.text) == ["// note"])
        #expect(result.comments.first?.kind == .lineComment)
        #expect(result.tokens.map(\.text) == ["a", "b", ""])
    }

    /// Block and documentation comments are told apart, and `/**/` is not documentation.
    @Test func scansBlockAndDocumentationComments() {
        let result = scan("/* a */ /** doc */ /**/ /***/ x")
        #expect(
            result.comments.map(\.kind)
                == [.blockComment, .documentationComment, .blockComment, .documentationComment])
        #expect(result.comments.allSatisfy { $0.isComment })
        #expect(result.tokens.map(\.text) == ["x", ""])
    }

    /// An unterminated block comment records a problem but keeps the comment.
    @Test func unterminatedCommentsAreReported() {
        let plain = scan("a /* open")
        #expect(plain.problems.map(\.kind) == [.unterminatedComment])
        #expect(plain.comments.first?.kind == .blockComment)
        let documentation = scan("/** open")
        #expect(documentation.comments.first?.kind == .documentationComment)
        #expect(documentation.problems.map(\.kind) == [.unterminatedComment])
    }

    /// Punctuation matches the longest symbol first.
    @Test func punctuationUsesLongestMatch() {
        let result = tokens("a..b -> c - d")
        #expect(result.map(\.text) == ["a", "..", "b", "->", "c", "-", "d"])
        #expect(result[1].kind == .punctuation)
    }

    /// The configuration sorts its punctuation by decreasing length.
    @Test func configurationSortsPunctuation() {
        let configuration = shopConfiguration()
        #expect(configuration.punctuation.first == "..")
        #expect(configuration.punctuation.map(\.count) == configuration.punctuation.map(\.count).sorted(by: >))
    }

    /// Token ranges carry exact offsets, lines and columns.
    @Test func tracksSourcePositions() throws {
        let result = tokens("ab\n  cd")
        let first = try #require(result.first)
        #expect(first.range.start == SourcePosition(utf8Offset: 0, line: 1, column: 1))
        #expect(first.range.end == SourcePosition(utf8Offset: 2, line: 1, column: 3))
        let second = result[1]
        #expect(second.range.start == SourcePosition(utf8Offset: 5, line: 2, column: 3))
        #expect(second.range.end == SourcePosition(utf8Offset: 7, line: 2, column: 5))
    }

    /// Offsets count UTF-8 bytes while columns count characters.
    @Test func tracksNonASCIIPositions() {
        let result = tokens("é x")
        #expect(result[0].text == "é")
        #expect(result[0].range.end == SourcePosition(utf8Offset: 2, line: 1, column: 2))
        #expect(result[1].range.start == SourcePosition(utf8Offset: 3, line: 1, column: 3))
    }

    /// Carriage-return and line-feed pairs count as a single line ending.
    @Test func tracksCRLFLineEndings() {
        let result = tokens("a\r\nb\rc\nd")
        #expect(result[1].range.start == SourcePosition(utf8Offset: 3, line: 2, column: 1))
        #expect(result[2].range.start == SourcePosition(utf8Offset: 5, line: 3, column: 1))
        #expect(result[3].range.start == SourcePosition(utf8Offset: 7, line: 4, column: 1))
    }

    /// The scan always ends with an empty end-of-file token at the end of the text.
    @Test func endsWithEndOfFileToken() throws {
        let empty = scan("")
        #expect(empty.tokens.count == 1)
        let end = try #require(scan("ab\n").tokens.last)
        #expect(end.kind == .endOfFile)
        #expect(end.text.isEmpty)
        #expect(end.range.start == SourcePosition(utf8Offset: 3, line: 2, column: 1))
    }

    /// Tokens and comments merge in source order, without the end-of-file token.
    @Test func allTokensMergesInSourceOrder() {
        let result = scan("/* a */ x // b\n y /** c */")
        #expect(result.allTokens.map(\.text) == ["/* a */", "x", "// b", "y", "/** c */"])
        #expect(scan("// only").allTokens.map(\.text) == ["// only"])
    }

    /// Text tokens built without an explicit value use their text as the value.
    @Test func tokenValueDefaultsToText() {
        let range = SourceRange(start: .start, end: .start)
        #expect(TextToken(kind: .identifier, text: "abc", range: range).value == "abc")
        #expect(TextToken(kind: .identifier, text: "~abc", value: "abc", range: range).value == "abc")
    }
}

/// Tests for decoding and quoting of string escapes.
@Suite("String escapes")
struct StringEscapesTests {
    /// The single-character escapes decode to control characters.
    @Test func decodesControlEscapes() {
        #expect(StringEscapes.decode(#"\n\t\r\b\f\0"#) == "\n\t\r\u{8}\u{C}\0")
    }

    /// Four hexadecimal digits decode a Unicode scalar.
    @Test func decodesUnicodeEscapes() {
        #expect(StringEscapes.decode(#"\u0041\u00e9x"#) == "Aéx")
    }

    /// An invalid unicode escape falls back to the escaped letter.
    @Test func invalidUnicodeEscapeFallsBack() {
        #expect(StringEscapes.decode(#"\u12"#) == "u12")
        #expect(StringEscapes.decode(#"\uZZZZ"#) == "uZZZZ")
        #expect(StringEscapes.decode(#"\uD800"#) == "uD800")
    }

    /// Unknown escapes keep the escaped character, and a lone trailing backslash is kept.
    @Test func unknownEscapesKeepTheCharacter() {
        #expect(StringEscapes.decode(#"\q\"\\"#) == "q\"\\")
        #expect(StringEscapes.decode("end\\") == "end\\")
    }

    /// Quoting surrounds the text with the delimiter and escapes the delimiter and backslash.
    @Test func quotesDelimitersAndBackslashes() {
        #expect(StringEscapes.quoted(#"a"b\c"#) == #""a\"b\\c""#)
        #expect(StringEscapes.quoted("it's", delimiter: "'") == #"'it\'s'"#)
        #expect(StringEscapes.quoted("say \"hi\"", delimiter: "'") == #"'say "hi"'"#)
    }

    /// Control characters round trip through quoting and decoding.
    @Test func quotingRoundTripsControlCharacters() {
        let text = "a\nb\tc\rd\u{8}e\u{C}f\0g\u{1}h\r\ni\"j\\k'l é"
        for delimiter: Character in ["\"", "'"] {
            let quoted = StringEscapes.quoted(text, delimiter: delimiter)
            #expect(!quoted.contains("\n"))
            let inner = String(quoted.dropFirst().dropLast())
            #expect(StringEscapes.decode(inner) == text)
        }
        #expect(StringEscapes.quoted("\u{1}") == "\"\\u0001\"")
        #expect(StringEscapes.quoted("\r\n") == "\"\\r\\n\"")
    }

    /// A quoted string scans back to its original value.
    @Test func quotedStringsScanBack() throws {
        let text = "Line one\nTab\there \"quoted\" \\ done"
        let token = try #require(scan(StringEscapes.quoted(text)).tokens.first)
        #expect(token.value == text)
    }
}
