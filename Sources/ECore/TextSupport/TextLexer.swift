//
// TextLexer.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// The lexical conventions of one textual metamodel notation.
///
/// The notations that the package reads share C-style comments, quoted strings and
/// decimal numbers, and differ in their punctuation, in the character that escapes a
/// keyword used as a name, and in the quotes they accept.
struct LexicalConfiguration: Sendable {
    /// The character that, written before a name, stops it being read as a keyword.
    var identifierEscape: Character?

    /// The punctuation and operator symbols, longest first.
    var punctuation: [String]

    /// The characters that open and close a string literal.
    var stringDelimiters: Set<Character>

    /// The character that opens and closes a character literal, if the notation has one.
    var characterDelimiter: Character?

    /// The characters, other than letters, digits and `_`, that may appear in a name.
    var extraIdentifierCharacters: Set<Character>

    /// Whether the value of a quoted literal has its escape sequences decoded.
    ///
    /// When escapes are not decoded, the value of a literal is the text between its
    /// delimiters, exactly as written.
    var decodesEscapes: Bool

    /// Creates a lexical configuration.
    ///
    /// - Parameters:
    ///   - identifierEscape: The character that escapes a keyword used as a name.
    ///   - punctuation: The punctuation and operator symbols of the notation.
    ///   - stringDelimiters: The characters that delimit string literals.
    ///   - characterDelimiter: The character that delimits character literals, if any.
    ///   - extraIdentifierCharacters: Further characters allowed in names.
    ///   - decodesEscapes: Whether the escape sequences of literals are decoded.
    init(
        identifierEscape: Character?, punctuation: [String], stringDelimiters: Set<Character>,
        characterDelimiter: Character? = nil, extraIdentifierCharacters: Set<Character> = [],
        decodesEscapes: Bool = true
    ) {
        self.identifierEscape = identifierEscape
        self.punctuation = punctuation.sorted { $0.count > $1.count }
        self.stringDelimiters = stringDelimiters
        self.characterDelimiter = characterDelimiter
        self.extraIdentifierCharacters = extraIdentifierCharacters
        self.decodesEscapes = decodesEscapes
    }
}

/// Splits the text of a textual metamodel notation into tokens.
///
/// The lexer never fails: a character that cannot start a token, an unterminated literal
/// or an unterminated comment is reported as a problem and scanning carries on, so every
/// part of the text is accounted for. Positions count UTF-8 offsets, lines from one and
/// columns in Unicode scalars from one; `\r\n`, `\r` and `\n` each end one line.
struct TextLexer {
    /// The symbols that start and end comments and the escape character of literals.
    enum Syntax {
        /// The start of a line comment.
        static let lineComment = "//"

        /// The start of a block comment.
        static let blockCommentStart = "/*"

        /// The start of a documentation comment.
        static let documentationStart = "/**"

        /// The end of a block or documentation comment.
        static let blockCommentEnd = "*/"

        /// The character that introduces an escape sequence in a literal.
        static let escape: Character = "\\"
    }

    /// The Unicode scalars of the text.
    private let scalars: [Unicode.Scalar]
    /// The UTF-8 offset of each scalar, with one extra entry for the end of the text.
    private let offsets: [Int]
    /// The line table that converts offsets to positions.
    private let lines: LineTable
    /// The configuration of the notation.
    private let configuration: LexicalConfiguration
    /// The index of the next scalar to scan.
    private var index = 0
    /// The tokens and problems found so far.
    private var scan = LexicalScan()

    /// Creates a lexer for a text.
    ///
    /// - Parameters:
    ///   - text: The text to scan.
    ///   - configuration: The lexical conventions of the notation.
    init(_ text: String, configuration: LexicalConfiguration) {
        scalars = Array(text.unicodeScalars)
        var offsets: [Int] = []
        offsets.reserveCapacity(scalars.count + 1)
        var offset = 0
        for scalar in scalars {
            offsets.append(offset)
            offset += scalar.utf8.count
        }
        offsets.append(offset)
        self.offsets = offsets
        lines = LineTable(text)
        self.configuration = configuration
    }

    /// Scans a text into tokens.
    ///
    /// - Parameters:
    ///   - text: The text to scan.
    ///   - configuration: The lexical conventions of the notation.
    /// - Returns: The tokens, comments and problems of the text.
    static func scan(_ text: String, configuration: LexicalConfiguration) -> LexicalScan {
        var lexer = TextLexer(text, configuration: configuration)
        return lexer.scanAll()
    }

    /// Scans the whole text.
    ///
    /// - Returns: The tokens, ending with an end-of-file token, the comments and the problems.
    mutating func scanAll() -> LexicalScan {
        while index < scalars.count { scanToken() }
        let end = range(from: scalars.count, to: scalars.count)
        scan.tokens.append(TextToken(kind: .endOfFile, text: "", range: end))
        return scan
    }

    // MARK: Helpers

    /// The scalar at a distance from the current one.
    ///
    /// - Parameter distance: The number of scalars ahead of the current one.
    /// - Returns: The scalar, or `nil` past the end of the text.
    private func scalar(at distance: Int) -> Unicode.Scalar? {
        let target = index + distance
        return target < scalars.count ? scalars[target] : nil
    }

    /// The character at a distance from the current one.
    ///
    /// - Parameter distance: The number of scalars ahead of the current one.
    /// - Returns: The character, or `nil` past the end of the text.
    private func character(at distance: Int) -> Character? {
        scalar(at: distance).map(Character.init)
    }

    /// Whether the text continues with a prefix.
    ///
    /// - Parameter text: The prefix to look for.
    /// - Returns: `true` if the remaining text starts with the prefix.
    private func hasPrefix(_ text: String) -> Bool {
        var distance = 0
        for expected in text.unicodeScalars {
            guard scalar(at: distance) == expected else { return false }
            distance += 1
        }
        return true
    }

    /// The source range between two scalar indexes.
    ///
    /// - Parameters:
    ///   - start: The index of the first scalar.
    ///   - end: The index after the last scalar.
    /// - Returns: The source range.
    private func range(from start: Int, to end: Int) -> SourceRange {
        lines.range(fromUTF8Offset: offsets[start], to: offsets[end])
    }

    /// The text between two scalar indexes.
    ///
    /// - Parameters:
    ///   - start: The index of the first scalar.
    ///   - end: The index after the last scalar.
    /// - Returns: The text.
    private func text(from start: Int, to end: Int) -> String {
        var result = String.UnicodeScalarView()
        result.append(contentsOf: scalars[start..<end])
        return String(result)
    }

    /// Records a token that ends at the current scalar.
    ///
    /// - Parameters:
    ///   - kind: The kind of the token.
    ///   - start: The index of the first scalar of the token.
    ///   - value: The decoded value of the token, if it differs from its text.
    ///   - isEscaped: Whether the token was written in escaped form.
    private mutating func emit(_ kind: TextTokenKind, from start: Int, value: String? = nil, isEscaped: Bool = false) {
        let token = TextToken(
            kind: kind, text: text(from: start, to: index), value: value, range: range(from: start, to: index),
            isEscaped: isEscaped)
        if token.isComment { scan.comments.append(token) } else { scan.tokens.append(token) }
    }

    /// Records a lexical problem that ends at the current scalar.
    ///
    /// - Parameters:
    ///   - kind: The kind of the problem.
    ///   - message: The description of the problem.
    ///   - start: The index of the first scalar of the problematic text.
    private mutating func problem(_ kind: TextDiagnosticKind, _ message: String, from start: Int) {
        scan.problems.append(LexicalProblem(kind: kind, message: message, range: range(from: start, to: index)))
    }

    /// Whether a character can start an identifier.
    ///
    /// - Parameter character: The character to test.
    /// - Returns: `true` if the character can start an identifier.
    private func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_" || configuration.extraIdentifierCharacters.contains(character)
    }

    /// Whether a character can continue an identifier.
    ///
    /// - Parameter character: The character to test.
    /// - Returns: `true` if the character can continue an identifier.
    private func isIdentifierPart(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }

    /// Whether a character is an ASCII digit.
    ///
    /// - Parameter character: The character to test, if any.
    /// - Returns: `true` if the character is a digit.
    private func isDigit(_ character: Character?) -> Bool {
        guard let character, character.isASCII else { return false }
        return character.isNumber
    }

    // MARK: Scanning

    /// Scans the next token or skips the next run of white space.
    private mutating func scanToken() {
        guard let current = character(at: 0) else { return }
        if current.isWhitespace {
            index += 1
            return
        }
        let start = index
        if hasPrefix(Syntax.lineComment) {
            scanLineComment(from: start)
        } else if hasPrefix(Syntax.blockCommentStart) {
            scanBlockComment(from: start)
        } else if configuration.stringDelimiters.contains(current) {
            scanQuoted(from: start, delimiter: current, kind: .string)
        } else if current == configuration.characterDelimiter {
            scanQuoted(from: start, delimiter: current, kind: .character)
        } else if isDigit(current) {
            scanNumber(from: start)
        } else if current == configuration.identifierEscape, let next = character(at: 1), isIdentifierStart(next) {
            index += 1
            scanIdentifier(from: start, escaped: true)
        } else if isIdentifierStart(current) {
            scanIdentifier(from: start, escaped: false)
        } else if let symbol = configuration.punctuation.first(where: hasPrefix) {
            index += symbol.unicodeScalars.count
            emit(.punctuation, from: start)
        } else {
            index += 1
            emit(.invalid, from: start)
            problem(.unexpectedCharacter, "Unexpected character '\(current)'", from: start)
        }
    }

    /// Scans a line comment.
    ///
    /// - Parameter start: The index of the first scalar of the comment.
    private mutating func scanLineComment(from start: Int) {
        while let next = character(at: 0), next != "\n", next != "\r" { index += 1 }
        emit(.lineComment, from: start)
    }

    /// Scans a block or documentation comment.
    ///
    /// - Parameter start: The index of the first scalar of the comment.
    private mutating func scanBlockComment(from start: Int) {
        let isDocumentation = hasPrefix(Syntax.documentationStart) && !hasPrefix(Syntax.documentationStart + "/")
        index += Syntax.blockCommentStart.unicodeScalars.count
        while index < scalars.count, !hasPrefix(Syntax.blockCommentEnd) { index += 1 }
        guard index < scalars.count else {
            emit(isDocumentation ? .documentationComment : .blockComment, from: start)
            problem(.unterminatedComment, "Unterminated comment", from: start)
            return
        }
        index += Syntax.blockCommentEnd.unicodeScalars.count
        emit(isDocumentation ? .documentationComment : .blockComment, from: start)
    }

    /// Scans a quoted literal and decodes its escape sequences.
    ///
    /// - Parameters:
    ///   - start: The index of the first scalar of the literal.
    ///   - delimiter: The character that closes the literal.
    ///   - kind: The kind of the token to record.
    private mutating func scanQuoted(from start: Int, delimiter: Character, kind: TextTokenKind) {
        index += 1
        var raw = ""
        while let next = character(at: 0), next != delimiter {
            if next == Syntax.escape, let escaped = character(at: 1) {
                raw.append(next)
                raw.append(escaped)
                index += 2
                continue
            }
            raw.append(next)
            index += 1
        }
        guard character(at: 0) == delimiter else {
            emit(.invalid, from: start)
            problem(.unterminatedString, "Unterminated literal", from: start)
            return
        }
        index += 1
        emit(kind, from: start, value: configuration.decodesEscapes ? StringEscapes.decode(raw) : raw)
    }

    /// Scans an integer or real number.
    ///
    /// - Parameter start: The index of the first scalar of the number.
    private mutating func scanNumber(from start: Int) {
        if character(at: 0) == "0", let marker = character(at: 1), marker == "x" || marker == "X" {
            index += 2
            while let next = character(at: 0), next.isHexDigit || next == "_" { index += 1 }
            if character(at: 0) == "#", let suffix = character(at: 1), isIdentifierStart(suffix) {
                index += 1
            }
            finishNumber(from: start, isReal: false)
            return
        }
        while isDigit(character(at: 0)) || character(at: 0) == "_" { index += 1 }
        var isReal = false
        if character(at: 0) == ".", isDigit(character(at: 1)) {
            isReal = true
            index += 1
            while isDigit(character(at: 0)) || character(at: 0) == "_" { index += 1 }
        }
        if let marker = character(at: 0), marker == "e" || marker == "E" {
            let sign = character(at: 1) == "+" || character(at: 1) == "-"
            if isDigit(character(at: sign ? 2 : 1)) {
                isReal = true
                index += sign ? 2 : 1
                while isDigit(character(at: 0)) || character(at: 0) == "_" { index += 1 }
            }
        }
        finishNumber(from: start, isReal: isReal)
    }

    /// The type suffixes that a numeric literal may end with, in lower case.
    private static let numberSuffixes: Set<String> = ["l", "d", "f", "bi", "bd"]

    /// Completes a number by reading and checking its suffix.
    ///
    /// - Parameters:
    ///   - start: The index of the first scalar of the number.
    ///   - isReal: Whether the number has a fractional or exponent part.
    private mutating func finishNumber(from start: Int, isReal: Bool) {
        let suffixStart = index
        while let next = character(at: 0), isIdentifierPart(next) { index += 1 }
        let suffix = text(from: suffixStart, to: index).lowercased()
        guard suffix.isEmpty || Self.numberSuffixes.contains(suffix) else {
            emit(.invalid, from: start)
            problem(.invalidNumber, "Invalid number '\(text(from: start, to: index))'", from: start)
            return
        }
        emit(isReal || suffix == "d" || suffix == "f" || suffix == "bd" ? .real : .integer, from: start)
    }

    /// Scans an identifier.
    ///
    /// - Parameters:
    ///   - start: The index of the first scalar of the identifier.
    ///   - escaped: Whether the identifier was written in escaped form.
    private mutating func scanIdentifier(from start: Int, escaped: Bool) {
        let nameStart = index
        while let next = character(at: 0), isIdentifierPart(next) { index += 1 }
        emit(.identifier, from: start, value: text(from: nameStart, to: index), isEscaped: escaped)
    }
}

/// Decodes and encodes the escape sequences of quoted literals.
enum StringEscapes {
    /// Decodes the escape sequences of the body of a quoted literal.
    ///
    /// The sequences `\n`, `\t`, `\r`, `\b`, `\f`, `\0`, `\uXXXX` and a backslash before any
    /// other character (which stands for that character) are recognised.
    ///
    /// - Parameter raw: The text between the delimiters.
    /// - Returns: The decoded text.
    static func decode(_ raw: String) -> String {
        var result = ""
        var characters = raw.makeIterator()
        while let character = characters.next() {
            guard character == TextLexer.Syntax.escape, let escaped = characters.next() else {
                result.append(character)
                continue
            }
            switch escaped {
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "r": result.append("\r")
            case "b": result.append("\u{8}")
            case "f": result.append("\u{C}")
            case "0": result.append("\0")
            case "u":
                var digits = ""
                var lookahead = characters
                while digits.count < 4, let digit = lookahead.next(), digit.isHexDigit {
                    digits.append(digit)
                }
                if digits.count == 4, let value = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(value) {
                    result.unicodeScalars.append(scalar)
                    characters = lookahead
                } else {
                    result.append(escaped)
                }
            default: result.append(escaped)
            }
        }
        return result
    }

    /// Encodes a text as a quoted literal.
    ///
    /// Backslashes, the delimiter and control characters are escaped, so that ``decode(_:)``
    /// restores the original text.
    ///
    /// - Parameters:
    ///   - text: The text to quote.
    ///   - delimiter: The character that opens and closes the literal.
    /// - Returns: The quoted literal, including its delimiters.
    static func quoted(_ text: String, delimiter: Character = "\"") -> String {
        var result = String(delimiter)
        for character in text {
            switch character {
            case TextLexer.Syntax.escape: result += "\\\\"
            case delimiter: result += "\\" + String(delimiter)
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            case "\r\n": result += "\\r\\n"
            case "\u{8}": result += "\\b"
            case "\u{C}": result += "\\f"
            default:
                if let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
                    scalar.value < 0x20
                {
                    let hex = String(scalar.value, radix: 16, uppercase: true)
                    result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    result.append(character)
                }
            }
        }
        result.append(delimiter)
        return result
    }
}
