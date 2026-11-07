//
// SourceScanner.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// The lexical category of a scanned token.
///
/// The categories are deliberately coarse: whether an identifier is a keyword
/// depends on the grammar notation, so each notation classifies identifiers
/// when it converts scanned tokens into ``SourceToken`` values.
enum ScannedTokenKind: Sendable, Hashable {
    /// A name made of letters, digits and underscores.
    case identifier
    /// A quoted string literal.
    case string
    /// A numeric literal.
    case number
    /// An operator or punctuation symbol.
    case punctuation
    /// An ordinary comment.
    case comment
    /// A documentation comment.
    case documentation
    /// A regular expression literal.
    case regex
    /// Free text, such as the literal parts of a template.
    case text
    /// Text that could not be tokenised.
    case invalid
}

/// A token read from grammar source text.
///
/// A token keeps both its source text and its decoded value, so that a string
/// literal can be shown as written and used without its quotes and escapes.
struct ScannedToken: Sendable, Hashable {
    /// The lexical category.
    var kind: ScannedTokenKind

    /// The source text the token covers.
    var text: String

    /// The decoded value: the content of a string literal, an identifier
    /// without its escape marker, or the source text for other tokens.
    var value: String

    /// The text the token covers.
    var range: SourceRange

    /// Whether a string literal or block comment reached its closing delimiter.
    var isTerminated: Bool

    /// Creates a token.
    ///
    /// - Parameters:
    ///   - kind: The lexical category.
    ///   - text: The source text the token covers.
    ///   - value: The decoded value; defaults to the source text.
    ///   - range: The text the token covers.
    ///   - isTerminated: Whether a delimited token reached its closing delimiter.
    init(
        kind: ScannedTokenKind, text: String, value: String? = nil, range: SourceRange,
        isTerminated: Bool = true
    ) {
        self.kind = kind
        self.text = text
        self.value = value ?? text
        self.range = range
        self.isTerminated = isTerminated
    }

    /// Whether the token is a comment that parsers skip.
    var isTrivia: Bool { kind == .comment || kind == .documentation }

    /// Whether the token is the punctuation symbol or identifier spelt `text`.
    ///
    /// - Parameter text: The spelling to compare with.
    /// - Returns: `true` for an identifier or punctuation token with that spelling.
    func `is`(_ text: String) -> Bool {
        (kind == .punctuation || kind == .identifier) && self.text == text
    }
}

/// A cursor over the bytes of a source text that recognises common token shapes.
///
/// Grammar notations differ in their comments, quotes and operators but share
/// most token shapes. The scanner offers one method per shape and leaves the
/// choice of shape to the notation's tokeniser. It works on UTF-8 bytes, since
/// the syntax of every supported notation is ASCII; other characters may only
/// occur inside literals and comments. Ranges follow ``LineTable``: offsets
/// count UTF-8 bytes, and lines and columns count from one.
struct SourceScanner {
    /// The UTF-8 bytes of the text.
    let bytes: [UInt8]

    /// The line table that converts offsets to positions.
    let lines: LineTable

    /// The offset of the next unread byte.
    var offset = 0

    /// Prepares to scan a text.
    ///
    /// - Parameter text: The source text.
    init(_ text: String) {
        bytes = Array(text.utf8)
        lines = LineTable(text)
    }

    /// Whether every byte has been read.
    var isAtEnd: Bool { offset >= bytes.count }

    /// The byte at a distance from the current offset.
    ///
    /// - Parameter distance: How far ahead to look; zero is the next unread byte.
    /// - Returns: The byte, or `nil` beyond the end of the text.
    func peek(_ distance: Int = 0) -> UInt8? {
        let index = offset + distance
        return index >= 0 && index < bytes.count ? bytes[index] : nil
    }

    /// Whether the unread text starts with a given ASCII string.
    ///
    /// - Parameter prefix: The string to look for.
    /// - Returns: `true` if the bytes at the current offset spell `prefix`.
    func hasPrefix(_ prefix: String) -> Bool {
        var index = offset
        for byte in prefix.utf8 {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
        }
        return true
    }

    /// The source range between two offsets.
    ///
    /// - Parameters:
    ///   - start: The inclusive start offset.
    ///   - end: The exclusive end offset.
    /// - Returns: The range with line and column positions.
    func range(_ start: Int, _ end: Int) -> SourceRange {
        lines.range(fromUTF8Offset: start, to: end)
    }

    /// The text between two offsets.
    ///
    /// - Parameters:
    ///   - start: The inclusive start offset.
    ///   - end: The exclusive end offset.
    /// - Returns: The decoded text, with invalid UTF-8 repaired.
    func text(_ start: Int, _ end: Int) -> String {
        String(decoding: bytes[max(0, start)..<min(end, bytes.count)], as: UTF8.self)
    }

    /// Makes a token of the text from an offset to the current offset.
    ///
    /// - Parameters:
    ///   - kind: The lexical category.
    ///   - start: The offset at which the token starts.
    ///   - value: The decoded value; defaults to the source text.
    ///   - isTerminated: Whether a delimited token reached its closing delimiter.
    /// - Returns: The token.
    func token(
        _ kind: ScannedTokenKind, from start: Int, value: String? = nil, isTerminated: Bool = true
    ) -> ScannedToken {
        ScannedToken(
            kind: kind, text: text(start, offset), value: value, range: range(start, offset),
            isTerminated: isTerminated)
    }

    /// Whether a byte is ASCII white space.
    ///
    /// - Parameter byte: The byte to test.
    /// - Returns: `true` for space, tab, line feed, carriage return, form feed and vertical tab.
    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C || byte == 0x0B
    }

    /// Whether a byte is an ASCII letter or an underscore.
    ///
    /// - Parameter byte: The byte to test.
    /// - Returns: `true` if the byte can start an identifier.
    static func isIdentifierStart(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F
    }

    /// Whether a byte is an ASCII digit.
    ///
    /// - Parameter byte: The byte to test.
    /// - Returns: `true` for `0` to `9`.
    static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

    /// Whether a byte can continue an identifier.
    ///
    /// - Parameter byte: The byte to test.
    /// - Returns: `true` for letters, digits and underscores.
    static func isIdentifierPart(_ byte: UInt8) -> Bool {
        isIdentifierStart(byte) || isDigit(byte)
    }

    /// Skips white space.
    mutating func skipWhitespace() {
        while let byte = peek(), Self.isWhitespace(byte) { offset += 1 }
    }

    /// Reads an identifier if one starts at the current offset.
    ///
    /// - Parameters:
    ///   - escape: A byte that may precede the identifier to escape a keyword,
    ///     such as `^` in Xtext and Langium; the escape is left out of the value.
    ///   - extraParts: Bytes besides letters, digits and underscores that may
    ///     continue the identifier, such as `-` in SDF3 sort names.
    /// - Returns: The identifier, or `nil` if none starts here.
    mutating func scanIdentifier(escape: UInt8? = nil, extraParts: Set<UInt8> = []) -> ScannedToken? {
        let start = offset
        var valueStart = offset
        if let escape, peek() == escape, let next = peek(1), Self.isIdentifierStart(next) {
            offset += 1
            valueStart = offset
        }
        guard let first = peek(), Self.isIdentifierStart(first) else {
            offset = start
            return nil
        }
        offset += 1
        while let byte = peek() {
            if Self.isIdentifierPart(byte) {
                offset += 1
            } else if extraParts.contains(byte), let next = peek(1), Self.isIdentifierPart(next) {
                offset += 1
            } else {
                break
            }
        }
        return token(.identifier, from: start, value: text(valueStart, offset))
    }

    /// Reads a decimal number, with an optional fraction and exponent.
    ///
    /// - Returns: The number, or `nil` if no digit starts here.
    mutating func scanNumber() -> ScannedToken? {
        guard let first = peek(), Self.isDigit(first) else { return nil }
        let start = offset
        while let byte = peek(), Self.isDigit(byte) { offset += 1 }
        if peek() == UInt8(ascii: "."), let next = peek(1), Self.isDigit(next) {
            offset += 1
            while let byte = peek(), Self.isDigit(byte) { offset += 1 }
        }
        if let marker = peek(), marker == UInt8(ascii: "e") || marker == UInt8(ascii: "E") {
            var look = 1
            if let sign = peek(1), sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") { look = 2 }
            if let digit = peek(look), Self.isDigit(digit) {
                offset += look
                while let byte = peek(), Self.isDigit(byte) { offset += 1 }
            }
        }
        return token(.number, from: start)
    }

    /// Reads a string literal delimited by the quote at the current offset.
    ///
    /// Backslash escapes are decoded: `\n`, `\t`, `\r`, `\b`, `\f`, `\0`, `\uXXXX`,
    /// and a backslash before any other character stands for that character.
    /// A literal ends at its closing quote or, if unterminated, at the end of
    /// the line.
    ///
    /// - Parameter allowsNewlines: Whether the literal may span lines.
    /// - Returns: The literal; check ``ScannedToken/isTerminated`` for a missing quote.
    mutating func scanString(allowsNewlines: Bool = false) -> ScannedToken {
        let start = offset
        let quote = bytes[offset]
        offset += 1
        var value: [UInt8] = []
        var terminated = false
        while let byte = peek() {
            if byte == quote {
                offset += 1
                terminated = true
                break
            }
            if !allowsNewlines && (byte == 0x0A || byte == 0x0D) { break }
            if byte == UInt8(ascii: "\\"), let escaped = peek(1) {
                offset += 2
                switch escaped {
                case UInt8(ascii: "n"): value.append(0x0A)
                case UInt8(ascii: "t"): value.append(0x09)
                case UInt8(ascii: "r"): value.append(0x0D)
                case UInt8(ascii: "b"): value.append(0x08)
                case UInt8(ascii: "f"): value.append(0x0C)
                case UInt8(ascii: "0"): value.append(0x00)
                case UInt8(ascii: "u"):
                    let digits = text(offset, min(offset + 4, bytes.count))
                    if digits.utf8.count == 4, let code = UInt32(digits, radix: 16),
                        let scalar = Unicode.Scalar(code)
                    {
                        value.append(contentsOf: Array(String(Character(scalar)).utf8))
                        offset += 4
                    } else {
                        value.append(escaped)
                    }
                default: value.append(escaped)
                }
                continue
            }
            value.append(byte)
            offset += 1
        }
        return token(.string, from: start, value: String(decoding: value, as: UTF8.self), isTerminated: terminated)
    }

    /// Reads a comment from the current offset to the end of the line.
    ///
    /// - Returns: The comment, without its line end.
    mutating func scanLineComment() -> ScannedToken {
        let start = offset
        while let byte = peek(), byte != 0x0A && byte != 0x0D { offset += 1 }
        return token(.comment, from: start)
    }

    /// Reads a block comment that starts at the current offset.
    ///
    /// A comment that opens with `/**` (but is not `/**/`) is a documentation comment.
    ///
    /// - Parameters:
    ///   - open: The opening delimiter, such as `/*`.
    ///   - close: The closing delimiter, such as `*/`.
    /// - Returns: The comment; check ``ScannedToken/isTerminated`` for a missing delimiter.
    mutating func scanBlockComment(open: String = "/*", close: String = "*/") -> ScannedToken {
        let start = offset
        let isDocumentation = open == "/*" && hasPrefix("/**") && !hasPrefix("/**/")
        offset += open.utf8.count
        var terminated = false
        while !isAtEnd {
            if hasPrefix(close) {
                offset += close.utf8.count
                terminated = true
                break
            }
            offset += 1
        }
        return token(isDocumentation ? .documentation : .comment, from: start, isTerminated: terminated)
    }

    /// Reads the longest of a set of punctuation symbols that starts at the current offset.
    ///
    /// - Parameter symbols: The symbols of the notation.
    /// - Returns: The symbol, or `nil` if none starts here.
    mutating func scanPunctuation(_ symbols: [String]) -> ScannedToken? {
        var best: String?
        for symbol in symbols where hasPrefix(symbol) && symbol.utf8.count > (best?.utf8.count ?? 0) {
            best = symbol
        }
        guard let best else { return nil }
        let start = offset
        offset += best.utf8.count
        return token(.punctuation, from: start)
    }

    /// Reads one character that cannot start any token.
    ///
    /// - Returns: An invalid token covering the whole Unicode scalar.
    mutating func scanInvalid() -> ScannedToken {
        let start = offset
        offset += 1
        while let byte = peek(), byte & 0xC0 == 0x80 { offset += 1 }
        return token(.invalid, from: start)
    }

    /// The empty range at the end of the text, where a missing token is reported.
    var endRange: SourceRange { range(bytes.count, bytes.count) }
}
