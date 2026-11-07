//
// KM3Lexer.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// The kinds of token that the KM3 lexer produces.
enum KM3TokenKind: Equatable {
    /// A reserved word written without quotes.
    case keyword(KM3Keyword)

    /// A name, with its text after quotes and escapes have been removed.
    ///
    /// The flag tells whether the name was written in double quotes.
    case name(String, quoted: Bool)

    /// A whole number.
    case integer(Int)

    /// A number with a fractional part, which the grammar never uses.
    case float

    /// A string in single quotes, which the grammar never uses.
    case string

    /// A symbol such as `{` or `;`.
    case symbol(String)

    /// A comment, with its text after the comment marker.
    case comment(String)

    /// Text that cannot start a token.
    case invalid

    /// The end of the text.
    case eof
}

/// A token of KM3 text with its source range.
struct KM3Token: Equatable {
    /// The kind of token and its decoded value.
    let kind: KM3TokenKind

    /// The source text of the token.
    let text: String

    /// The text the token covers.
    let range: SourceRange

    /// The decoded name of a name token, or `nil` for any other token.
    var name: String? {
        if case .name(let name, _) = kind { return name }
        return nil
    }

    /// Whether the token is the given symbol.
    ///
    /// - Parameter symbol: The symbol text.
    /// - Returns: `true` if the token is that symbol.
    func isSymbol(_ symbol: String) -> Bool { kind == .symbol(symbol) }

    /// Whether the token is the given reserved word.
    ///
    /// - Parameter keyword: The reserved word.
    /// - Returns: `true` if the token is that reserved word.
    func isKeyword(_ keyword: KM3Keyword) -> Bool { kind == .keyword(keyword) }
}

/// The result of scanning KM3 text.
struct KM3Scan {
    /// The tokens that the parser reads, without comments, ending with an end-of-file token.
    var tokens: [KM3Token] = []

    /// The comments, in source order.
    var comments: [KM3Token] = []

    /// The lexical problems, in source order.
    var diagnostics: [SourceDiagnostic] = []
}

/// Splits KM3 text into tokens.
///
/// The lexer follows the lexical rules of the original KM3 grammar: comments run from
/// `--` to the end of the line, names are letters, digits and underscores that do not
/// start with a digit, or any text in double quotes with backslash escapes, and numbers
/// are decimal. It works on Unicode scalars and records the UTF-8 offset, line and column
/// of every token; `\r\n`, a lone `\r` and `\n` each end one line. The lexer never fails:
/// a character that cannot start a token becomes an invalid token with a diagnostic.
struct KM3Lexer {
    /// The scalars of the text.
    private let scalars: [Unicode.Scalar]

    /// The name of the document, for diagnostics.
    private let document: String?

    /// The index of the next scalar.
    private var index = 0

    /// The UTF-8 offset of the next scalar.
    private var offset = 0

    /// The line of the next scalar.
    private var line = 1

    /// The column of the next scalar.
    private var column = 1

    /// The scan being built.
    private var scan = KM3Scan()

    /// Creates a lexer.
    ///
    /// - Parameters:
    ///   - text: The KM3 text.
    ///   - document: The name of the document, which diagnostics carry.
    init(_ text: String, document: String? = nil) {
        self.scalars = Array(text.unicodeScalars)
        self.document = document
    }

    /// Scans the whole text.
    ///
    /// - Returns: The tokens, comments and lexical problems of the text.
    mutating func scanAll() -> KM3Scan {
        while let scalar = peek() {
            let start = position
            switch scalar {
            case " ", "\t", "\u{0C}", "\r", "\n":
                advance()
            case "-" where peek(1) == "-":
                scanComment(from: start)
            case "\"":
                scanQuotedName(from: start)
            case "'":
                scanString(from: start)
            case _ where Self.isDigit(scalar):
                scanNumber(from: start)
            case _ where Self.isNameStart(scalar):
                scanName(from: start)
            default:
                scanSymbol(from: start)
            }
        }
        scan.tokens.append(KM3Token(kind: .eof, text: "", range: SourceRange(start: position, end: position)))
        return scan
    }

    // MARK: Token scanners

    /// Scans a comment up to the end of its line.
    ///
    /// - Parameter start: The position of the comment marker.
    private mutating func scanComment(from start: SourcePosition) {
        advance()
        advance()
        var body = String.UnicodeScalarView()
        while let scalar = peek(), scalar != "\n", scalar != "\r" {
            body.append(scalar)
            advance()
        }
        let text = KM3Directive.commentMarker + String(body)
        scan.comments.append(KM3Token(kind: .comment(String(body)), text: text, range: range(from: start)))
    }

    /// Scans a name in double quotes, decoding its escapes.
    ///
    /// A name without a closing quote extends to the end of its line and is reported.
    ///
    /// - Parameter start: The position of the opening quote.
    private mutating func scanQuotedName(from start: SourcePosition) {
        let startIndex = index
        advance()
        var value = String.UnicodeScalarView()
        var closed = false
        while let scalar = peek() {
            if scalar == "\"" {
                advance()
                closed = true
                break
            }
            if scalar == "\n" || scalar == "\r" { break }
            if scalar == "\\" {
                value.append(contentsOf: scanEscape().unicodeScalars)
                continue
            }
            value.append(scalar)
            advance()
        }
        let tokenRange = range(from: start)
        if !closed {
            report(.unterminatedString, "The quoted name has no closing '\"'", tokenRange)
        }
        scan.tokens.append(
            KM3Token(kind: .name(String(value), quoted: true), text: text(from: startIndex), range: tokenRange))
    }

    /// Scans a string in single quotes, which the grammar never uses.
    ///
    /// - Parameter start: The position of the opening quote.
    private mutating func scanString(from start: SourcePosition) {
        let startIndex = index
        advance()
        var closed = false
        while let scalar = peek(), scalar != "\n", scalar != "\r" {
            if scalar == "\\" {
                _ = scanEscape()
                continue
            }
            advance()
            if scalar == "'" {
                closed = true
                break
            }
        }
        let tokenRange = range(from: start)
        if !closed { report(.unterminatedString, "The string has no closing \"'\"", tokenRange) }
        scan.tokens.append(KM3Token(kind: .string, text: text(from: startIndex), range: tokenRange))
    }

    /// Scans a backslash escape and returns the text it denotes.
    ///
    /// The escapes are those of the original grammar: `\n`, `\r`, `\t`, `\b`, `\f`, `\"`,
    /// `\'`, `\\` and up to three octal digits. Any other escaped character stands for itself.
    ///
    /// - Returns: The decoded text.
    private mutating func scanEscape() -> String {
        advance()
        guard let scalar = peek() else { return "\\" }
        let simple: [Unicode.Scalar: String] = [
            "n": "\n", "r": "\r", "t": "\t", "b": "\u{08}", "f": "\u{0C}", "\"": "\"", "'": "'",
            "\\": "\\",
        ]
        if let decoded = simple[scalar] {
            advance()
            return decoded
        }
        if ("0"..."7").contains(scalar) {
            let maximumDigits = ("0"..."3").contains(scalar) ? 3 : 2
            var code: UInt32 = 0
            var digits = 0
            while digits < maximumDigits, let digit = peek(), ("0"..."7").contains(digit) {
                code = code * 8 + (digit.value - 48)
                digits += 1
                advance()
            }
            return Unicode.Scalar(code).map { String(Character($0)) } ?? ""
        }
        advance()
        return String(Character(scalar))
    }

    /// Scans a whole number or a number with a fractional part.
    ///
    /// - Parameter start: The position of the first digit.
    private mutating func scanNumber(from start: SourcePosition) {
        let startIndex = index
        while let scalar = peek(), Self.isDigit(scalar) { advance() }
        if peek() == ".", let next = peek(1), Self.isDigit(next) {
            advance()
            while let scalar = peek(), Self.isDigit(scalar) { advance() }
            scan.tokens.append(KM3Token(kind: .float, text: text(from: startIndex), range: range(from: start)))
            return
        }
        let digits = text(from: startIndex)
        let tokenRange = range(from: start)
        guard let value = Int(digits) else {
            report(.invalidNumber, "The number \(digits) is too large", tokenRange)
            scan.tokens.append(KM3Token(kind: .invalid, text: digits, range: tokenRange))
            return
        }
        scan.tokens.append(KM3Token(kind: .integer(value), text: digits, range: tokenRange))
    }

    /// Scans a name or a reserved word.
    ///
    /// - Parameter start: The position of the first character.
    private mutating func scanName(from start: SourcePosition) {
        let startIndex = index
        while let scalar = peek(), Self.isNameStart(scalar) || Self.isDigit(scalar) { advance() }
        let word = text(from: startIndex)
        let kind: KM3TokenKind = KM3Keyword(rawValue: word).map { .keyword($0) } ?? .name(word, quoted: false)
        scan.tokens.append(KM3Token(kind: kind, text: word, range: range(from: start)))
    }

    /// Scans a symbol, or reports a character that cannot start a token.
    ///
    /// - Parameter start: The position of the character.
    private mutating func scanSymbol(from start: SourcePosition) {
        let startIndex = index
        if let first = peek(), let second = peek(1) {
            let pair = String(Character(first)) + String(Character(second))
            if KM3Symbol.compound.contains(pair) {
                advance()
                advance()
                scan.tokens.append(KM3Token(kind: .symbol(pair), text: pair, range: range(from: start)))
                return
            }
        }
        guard let scalar = peek() else { return }
        advance()
        let character = Character(scalar)
        let text = text(from: startIndex)
        let tokenRange = range(from: start)
        if KM3Symbol.single.contains(character) {
            scan.tokens.append(KM3Token(kind: .symbol(text), text: text, range: tokenRange))
        } else {
            report(.unexpectedCharacter, "The character '\(text)' cannot start a token", tokenRange)
            scan.tokens.append(KM3Token(kind: .invalid, text: text, range: tokenRange))
        }
    }

    // MARK: Positions

    /// The position of the next scalar.
    private var position: SourcePosition { SourcePosition(utf8Offset: offset, line: line, column: column) }

    /// The range from a start position to the position of the next scalar.
    ///
    /// - Parameter start: The start of the range.
    /// - Returns: The range.
    private func range(from start: SourcePosition) -> SourceRange { SourceRange(start: start, end: position) }

    /// The text from a scalar index to the next scalar.
    ///
    /// - Parameter startIndex: The index of the first scalar.
    /// - Returns: The text.
    private func text(from startIndex: Int) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[startIndex..<index])
        return String(view)
    }

    /// The scalar a number of places ahead of the next one.
    ///
    /// - Parameter distance: How far ahead to look.
    /// - Returns: The scalar, or `nil` beyond the end of the text.
    private func peek(_ distance: Int = 0) -> Unicode.Scalar? {
        index + distance < scalars.count ? scalars[index + distance] : nil
    }

    /// Moves past the next scalar, keeping track of lines and columns.
    ///
    /// A `\r` followed by `\n` ends one line, at the `\n`.
    private mutating func advance() {
        guard index < scalars.count else { return }
        let scalar = scalars[index]
        index += 1
        offset += UTF8.width(scalar)
        if scalar == "\n" || (scalar == "\r" && peek() != "\n") {
            line += 1
            column = 1
        } else {
            column += 1
        }
    }

    /// Records a lexical problem.
    ///
    /// - Parameters:
    ///   - code: The code of the problem.
    ///   - message: The description of the problem.
    ///   - range: The text the problem concerns.
    private mutating func report(_ code: KM3DiagnosticCode, _ message: String, _ range: SourceRange) {
        scan.diagnostics.append(
            SourceDiagnostic(severity: .error, code: code.rawValue, message: message, range: range, document: document))
    }

    // MARK: Character classes

    /// Whether a scalar is a decimal digit.
    ///
    /// - Parameter scalar: The scalar.
    /// - Returns: `true` for `0` to `9`.
    static func isDigit(_ scalar: Unicode.Scalar) -> Bool { ("0"..."9").contains(scalar) }

    /// Whether a scalar can start a name.
    ///
    /// The original grammar admits ASCII letters, the underscore and the Latin-1 letters;
    /// every other Unicode letter is admitted as well.
    ///
    /// - Parameter scalar: The scalar.
    /// - Returns: `true` for a letter or an underscore.
    static func isNameStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || scalar.properties.isAlphabetic
    }

    /// Whether a text can be written as a name without quotes.
    ///
    /// - Parameter text: The text.
    /// - Returns: `true` if the text is a non-empty name that is not a reserved word.
    static func isPlainName(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, isNameStart(first), KM3Keyword(rawValue: text) == nil else {
            return false
        }
        return text.unicodeScalars.allSatisfy { isNameStart($0) || isDigit($0) }
    }
}
