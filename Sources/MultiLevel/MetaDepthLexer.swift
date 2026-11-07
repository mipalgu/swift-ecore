//
// MetaDepthLexer.swift
// MultiLevel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// The kinds of token of the MetaDepth notation.
enum MetaDepthTokenKind: Hashable, Sendable {
    /// A name or keyword.
    case identifier
    /// An integer literal.
    case integer
    /// A real literal.
    case real
    /// A string literal; the value is decoded.
    case string
    /// An expression between `$` delimiters; the value is the text in between.
    case expression
    /// An embedded-language block between `#` lines; the value is the language name.
    case embeddedBlock
    /// A punctuation symbol; the value is the symbol.
    case symbol
    /// The end of the text.
    case end
}

/// A token of the MetaDepth notation.
struct MetaDepthToken: Sendable {
    /// The kind of the token.
    let kind: MetaDepthTokenKind
    /// The text or decoded value of the token.
    let value: String
    /// Where the token is in the source.
    let range: SourceRange

    /// Whether the token is a given symbol.
    func isSymbol(_ symbol: String) -> Bool { kind == .symbol && value == symbol }

    /// Whether the token is a given keyword or name.
    func isWord(_ word: String) -> Bool { kind == .identifier && value == word }
}

/// The diagnostic codes of multi-level models.
public enum MultiLevelDiagnosticCode {
    /// A syntax error in MetaDepth text.
    public static let syntax = "multilevel.syntax"
    /// A construct of MetaDepth that is not supported.
    public static let unsupported = "multilevel.unsupported"
    /// A name that denotes nothing.
    public static let unresolvedName = "multilevel.unresolvedName"
    /// A name declared twice where it must be unique.
    public static let duplicateName = "multilevel.duplicateName"
    /// The level models do not form one instantiation chain.
    public static let levelChain = "multilevel.levelChain"
    /// A clabject is typed by a clabject at an inadmissible level.
    public static let typeLevel = "multilevel.typeLevel"
    /// A clabject instantiates a type that cannot be instantiated.
    public static let notInstantiable = "multilevel.notInstantiable"
    /// A potency is inadmissible.
    public static let potency = "multilevel.potency"
    /// Generalisation crosses levels, potencies or forms a cycle.
    public static let inheritance = "multilevel.inheritance"
    /// A linguistic extension in a model that rejects them.
    public static let linguisticExtension = "multilevel.linguisticExtension"
    /// A slot for a feature that is not visible, or not mutable, at the clabject.
    public static let slot = "multilevel.slot"
    /// A value of the wrong type.
    public static let valueType = "multilevel.valueType"
    /// A slot with too few or too many values.
    public static let multiplicity = "multilevel.multiplicity"
    /// A reference that crosses levels without being declared to.
    public static let levelCrossing = "multilevel.levelCrossing"
    /// A reference value that is not an instance of the reference's target.
    public static let referenceTarget = "multilevel.referenceTarget"
    /// An edge whose ends do not fit.
    public static let edge = "multilevel.edge"
    /// A constraint that is not satisfied.
    public static let constraintViolated = "multilevel.constraintViolated"
    /// A constraint that could not be evaluated.
    public static let constraintError = "multilevel.constraintError"
    /// A constraint body in a language other than AQL.
    public static let constraintLanguage = "multilevel.constraintLanguage"
}

/// Splits MetaDepth text into tokens.
///
/// Line comments (`//`) and block comments are skipped. An expression between `$` delimiters
/// is a single token. A line that starts with `#` opens an embedded-language block that the
/// next such line closes; the block is a single token so that the reader can reject it.
struct MetaDepthLexer {
    /// The symbols, longest first.
    static let symbols = ["..", "{", "}", "(", ")", "[", "]", ":", ";", ",", "=", "@", "*", "/", ".", "-"]

    /// The UTF-8 bytes of the text being scanned.
    private let bytes: [UInt8]
    /// The offset in `bytes` of the next byte to scan.
    private var offset = 0
    /// The one-based line number of the next byte to scan.
    private var line = 1
    /// The one-based column number of the next byte to scan.
    private var column = 1
    /// The tokens scanned so far.
    private(set) var tokens: [MetaDepthToken] = []
    /// The lexical problems found so far.
    private(set) var diagnostics: [SourceDiagnostic] = []

    /// Creates a lexer.
    init(_ text: String) {
        bytes = Array(text.utf8)
    }

    /// Splits a text into tokens.
    static func tokenise(_ text: String) -> (tokens: [MetaDepthToken], diagnostics: [SourceDiagnostic]) {
        var lexer = MetaDepthLexer(text)
        lexer.scan()
        return (lexer.tokens, lexer.diagnostics)
    }

    /// The source position of the next byte to scan.
    private var position: SourcePosition { SourcePosition(utf8Offset: offset, line: line, column: column) }

    /// The byte at a distance from the current offset.
    ///
    /// - Parameter distance: The number of bytes ahead of the current offset.
    /// - Returns: The byte, or `nil` if it lies beyond the end of the text.
    private func peek(_ distance: Int = 0) -> UInt8? {
        offset + distance < bytes.count ? bytes[offset + distance] : nil
    }

    /// Moves past the current byte, updating the line and column.
    ///
    /// A newline starts a new line; continuation bytes of a multi-byte character do not advance the column.
    private mutating func advance() {
        guard let byte = peek() else { return }
        offset += 1
        if byte == UInt8(ascii: "\n") {
            line += 1
            column = 1
        } else if byte & 0xC0 != 0x80 {
            column += 1
        }
    }

    /// The text between two byte offsets.
    ///
    /// - Parameters:
    ///   - start: The offset of the first byte.
    ///   - end: The offset after the last byte.
    /// - Returns: The bytes decoded as UTF-8.
    private func text(from start: Int, to end: Int) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// Whether only spaces and tabs separate the current offset from the start of its line.
    private var atLineStart: Bool {
        var index = offset - 1
        while index >= 0, bytes[index] == UInt8(ascii: " ") || bytes[index] == UInt8(ascii: "\t") { index -= 1 }
        return index < 0 || bytes[index] == UInt8(ascii: "\n")
    }

    /// Scans the whole text, appending tokens and diagnostics, and finishes with an end token.
    private mutating func scan() {
        while let byte = peek() {
            let start = position
            switch byte {
            case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r"), UInt8(ascii: "\n"):
                advance()
            case UInt8(ascii: "/") where peek(1) == UInt8(ascii: "/"):
                while let next = peek(), next != UInt8(ascii: "\n") { advance() }
            case UInt8(ascii: "/") where peek(1) == UInt8(ascii: "*"):
                advance(); advance()
                while peek() != nil, !(peek() == UInt8(ascii: "*") && peek(1) == UInt8(ascii: "/")) { advance() }
                if peek() == nil { problem("unterminated comment", from: start) } else { advance(); advance() }
            case UInt8(ascii: "#") where atLineStart:
                scanEmbeddedBlock(from: start)
            case UInt8(ascii: "$"):
                scanExpression(from: start)
            case UInt8(ascii: "\""), UInt8(ascii: "'"):
                scanString(from: start, delimiter: byte)
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                scanNumber(from: start)
            case _ where Self.isIdentifierStart(byte):
                let first = offset
                while let next = peek(), Self.isIdentifierPart(next) { advance() }
                emit(.identifier, text(from: first, to: offset), from: start)
            default:
                if let symbol = Self.symbols.first(where: { matches($0) }) {
                    for _ in symbol.utf8 { advance() }
                    emit(.symbol, symbol, from: start)
                } else {
                    advance()
                    problem("unexpected character '\(text(from: start.utf8Offset, to: offset))'", from: start)
                }
            }
        }
        emit(.end, "", from: position)
    }

    /// Whether the text at the current offset starts with a symbol.
    ///
    /// - Parameter symbol: The symbol to look for.
    /// - Returns: `true` if every byte of the symbol matches.
    private func matches(_ symbol: String) -> Bool {
        for (index, byte) in symbol.utf8.enumerated() where peek(index) != byte { return false }
        return true
    }

    /// Whether a byte can start an identifier.
    ///
    /// - Parameter byte: The byte to test.
    /// - Returns: `true` for a letter, an underscore, a caret or a non-ASCII byte.
    private static func isIdentifierStart(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
            || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "^") || byte >= 0x80
    }

    /// Whether a byte can continue an identifier.
    ///
    /// - Parameter byte: The byte to test.
    /// - Returns: `true` for an identifier-start byte or a digit.
    private static func isIdentifierPart(_ byte: UInt8) -> Bool {
        isIdentifierStart(byte) || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
    }

    /// Appends a token that ends at the current position.
    ///
    /// - Parameters:
    ///   - kind: The kind of token.
    ///   - value: The text of the token.
    ///   - start: The position where the token starts.
    private mutating func emit(_ kind: MetaDepthTokenKind, _ value: String, from start: SourcePosition) {
        tokens.append(MetaDepthToken(kind: kind, value: value, range: SourceRange(start: start, end: position)))
    }

    /// Records a syntax error that ends at the current position.
    ///
    /// - Parameters:
    ///   - message: A description of the problem.
    ///   - start: The position where the problem starts.
    private mutating func problem(_ message: String, from start: SourcePosition) {
        diagnostics.append(
            SourceDiagnostic(
                severity: .error, code: MultiLevelDiagnosticCode.syntax, message: message,
                range: SourceRange(start: start, end: position)))
    }

    /// Scans an embedded-language block as a single token whose value is the language name.
    ///
    /// The block runs to the next line that starts with `#`, or to the end of the text.
    ///
    /// - Parameter start: The position of the opening `#`.
    private mutating func scanEmbeddedBlock(from start: SourcePosition) {
        advance()
        let nameStart = offset
        while let next = peek(), next != UInt8(ascii: "\n") { advance() }
        let language = text(from: nameStart, to: offset).trimmingCharacters(in: .whitespaces)
        while peek() != nil {
            advance()
            if peek() == UInt8(ascii: "#"), atLineStart {
                advance()
                break
            }
        }
        emit(.embeddedBlock, language, from: start)
    }

    /// Scans an expression between `$` delimiters as a single token whose value is the expression body.
    ///
    /// An unterminated expression is reported as a syntax error.
    ///
    /// - Parameter start: The position of the opening `$`.
    private mutating func scanExpression(from start: SourcePosition) {
        advance()
        let first = offset
        while let next = peek(), next != UInt8(ascii: "$") { advance() }
        guard peek() != nil else {
            problem("unterminated expression", from: start)
            return
        }
        let body = text(from: first, to: offset)
        advance()
        emit(.expression, body, from: start)
    }

    /// Scans a quoted string as a single token with its escape sequences decoded.
    ///
    /// An unterminated string, or one that reaches the end of its line, is reported as a syntax error.
    ///
    /// - Parameters:
    ///   - start: The position of the opening quotation mark.
    ///   - delimiter: The quotation mark that closes the string.
    private mutating func scanString(from start: SourcePosition, delimiter: UInt8) {
        advance()
        var decoded: [UInt8] = []
        while let next = peek(), next != delimiter, next != UInt8(ascii: "\n") {
            if next == UInt8(ascii: "\\"), let escaped = peek(1) {
                advance(); advance()
                switch escaped {
                case UInt8(ascii: "n"): decoded.append(UInt8(ascii: "\n"))
                case UInt8(ascii: "t"): decoded.append(UInt8(ascii: "\t"))
                case UInt8(ascii: "r"): decoded.append(UInt8(ascii: "\r"))
                default: decoded.append(escaped)
                }
            } else {
                decoded.append(next)
                advance()
            }
        }
        guard peek() == delimiter else {
            problem("unterminated string", from: start)
            return
        }
        advance()
        emit(.string, String(decoding: decoded, as: UTF8.self), from: start)
    }

    /// Scans an integer or real number as a single token.
    ///
    /// A fractional part or an exponent makes the token real.
    ///
    /// - Parameter start: The position of the first digit.
    private mutating func scanNumber(from start: SourcePosition) {
        let first = offset
        var isReal = false
        while let next = peek(), next >= UInt8(ascii: "0"), next <= UInt8(ascii: "9") { advance() }
        if peek() == UInt8(ascii: "."), let after = peek(1), after >= UInt8(ascii: "0"), after <= UInt8(ascii: "9") {
            isReal = true
            advance()
            while let next = peek(), next >= UInt8(ascii: "0"), next <= UInt8(ascii: "9") { advance() }
        }
        if peek() == UInt8(ascii: "e") || peek() == UInt8(ascii: "E") {
            let sign = peek(1) == UInt8(ascii: "-") || peek(1) == UInt8(ascii: "+") ? 1 : 0
            if let digit = peek(1 + sign), digit >= UInt8(ascii: "0"), digit <= UInt8(ascii: "9") {
                isReal = true
                for _ in 0...sign { advance() }
                while let next = peek(), next >= UInt8(ascii: "0"), next <= UInt8(ascii: "9") { advance() }
            }
        }
        emit(isReal ? .real : .integer, text(from: first, to: offset), from: start)
    }
}
