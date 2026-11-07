//
// OCLLexer.swift
// OCL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// A lexical token of OCL text.
///
/// The OCL family of languages (Essential OCL, OCLinEcore and Complete OCL) shares one lexical
/// structure. Words are not classified as keywords by the lexer, because most keywords of
/// OCLinEcore and Complete OCL may also name elements; the parsers decide from the context.
public struct OCLToken: Sendable, Hashable {
    /// The lexical category of a token.
    public enum Kind: Sendable, Hashable {
        /// A simple name such as `Library`, `self` or `invariant`.
        case identifier

        /// A name written as `_'text'`, which may hold any character and is never a keyword.
        case escapedIdentifier

        /// A single-quoted string such as `'text'`.
        case string

        /// A multi-line string written between `/'` and `'/`, as in annotation details.
        case multiLineString

        /// A whole number such as `42`.
        case integer

        /// A number with a fraction or an exponent such as `4.2` or `1e3`.
        case real

        /// An operator or punctuation symbol such as `->`, `::` or `;`.
        case symbol

        /// A `--` line comment or a `/* ... */` block comment.
        case comment

        /// Text that is not a token of OCL, such as an unterminated string.
        case invalid

        /// The empty token at the end of the text.
        case endOfInput
    }

    /// The lexical category of the token.
    public var kind: Kind

    /// The source text of the token, exactly as written.
    public var text: String

    /// The value of the token: the decoded name or string, or the source text otherwise.
    public var value: String

    /// The source range the token covers.
    public var range: SourceRange

    /// Creates a token.
    ///
    /// - Parameters:
    ///   - kind: The lexical category of the token.
    ///   - text: The source text of the token.
    ///   - value: The decoded value of the token, by default its text.
    ///   - range: The source range the token covers.
    public init(kind: Kind, text: String, value: String? = nil, range: SourceRange) {
        self.kind = kind
        self.text = text
        self.value = value ?? text
        self.range = range
    }

    /// Whether the token is a name, simple or escaped.
    public var isName: Bool { kind == .identifier || kind == .escapedIdentifier }

    /// Whether the token is the given word, written as a simple name.
    ///
    /// An escaped name such as `_'class'` is never a keyword, so it does not match.
    ///
    /// - Parameter word: The word to compare with.
    /// - Returns: `true` if the token is the simple name `word`.
    public func isWord(_ word: String) -> Bool { kind == .identifier && text == word }

    /// Whether the token is the given symbol.
    ///
    /// - Parameter symbol: The symbol to compare with.
    /// - Returns: `true` if the token is the symbol.
    public func isSymbol(_ symbol: String) -> Bool { kind == .symbol && text == symbol }

    /// Whether the token is a comment.
    public var isComment: Bool { kind == .comment }
}

/// The result of splitting OCL text into tokens.
public struct OCLTokenisation: Sendable {
    /// Every token of the text in order, including comments and invalid tokens, and ending with
    /// an end-of-input token.
    public var tokens: [OCLToken]

    /// The lexical problems found, in order of position.
    public var diagnostics: [SourceDiagnostic]

    /// The table that maps offsets in the text to lines and columns.
    public var lineTable: LineTable

    /// The tokens that a parser reads: every token except comments.
    public var significantTokens: [OCLToken] { tokens.filter { !$0.isComment } }
}

/// Splits OCL text into tokens.
///
/// The lexer follows the terminals of the Eclipse OCL Base grammar: simple names of ASCII
/// letters, digits and underscores, escaped names `_'...'`, single-quoted strings with
/// backslash escapes, multi-line strings `/'...'/`, whole and real numbers, `--` line comments
/// and `/* */` block comments. A number followed by `..` stays whole, so that `1..5` is a
/// range. The lexer never fails: text it cannot read becomes an ``OCLToken/Kind/invalid``
/// token with a diagnostic.
public enum OCLLexer {
    /// The symbols of two or three characters, longest first.
    static let compoundSymbols = ["?->", "->", "?.", "::", "..", "<>", "<=", ">=", "<-", "++", "&&", "^^"]

    /// The symbols of one character.
    static let simpleSymbols: Set<UInt8> = Set("()[]{},;:.=<>+-*/|@#?!^&".utf8)

    /// Splits text into tokens.
    ///
    /// - Parameter source: The OCL text.
    /// - Returns: The tokens, the lexical problems and the line table of the text.
    public static func tokenise(_ source: String) -> OCLTokenisation {
        var scanner = Scanner(source)
        scanner.scanAll()
        return OCLTokenisation(tokens: scanner.tokens, diagnostics: scanner.diagnostics, lineTable: scanner.table)
    }

    /// The state of a scan over the UTF-8 bytes of a text.
    private struct Scanner {
        /// The UTF-8 bytes of the source.
        let bytes: [UInt8]
        /// The table that converts offsets to line and column positions.
        let table: LineTable
        /// The offset of the next byte to scan.
        var index = 0
        /// The tokens scanned so far.
        var tokens: [OCLToken] = []
        /// The diagnostics collected so far.
        var diagnostics: [SourceDiagnostic] = []

        /// Creates a scanner.
        ///
        /// - Parameter source: The source text.
        init(_ source: String) {
            bytes = Array(source.utf8)
            table = LineTable(source)
        }

        /// The byte at an offset.
        ///
        /// - Parameter offset: The offset.
        /// - Returns: The byte, or `nil` if the offset is beyond the end of the source.
        func byte(at offset: Int) -> UInt8? { offset < bytes.count ? bytes[offset] : nil }

        /// Whether a byte can start or continue an identifier.
        ///
        /// - Parameter byte: The byte.
        /// - Returns: `true` for an ASCII letter or an underscore.
        static func isLetter(_ byte: UInt8) -> Bool {
            (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F
        }

        /// Whether a byte is an ASCII digit.
        ///
        /// - Parameter byte: The byte.
        /// - Returns: `true` for a digit.
        static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

        /// The source text between two offsets.
        ///
        /// - Parameters:
        ///   - start: The offset of the first byte.
        ///   - end: The offset after the last byte.
        /// - Returns: The text.
        func text(from start: Int, to end: Int) -> String {
            String(decoding: bytes[start..<end], as: UTF8.self)
        }

        /// Adds a token that ends at the current offset.
        ///
        /// - Parameters:
        ///   - kind: The kind of token.
        ///   - start: The offset where the token starts.
        ///   - value: The value of the token, if it differs from its text.
        mutating func emit(_ kind: OCLToken.Kind, from start: Int, value: String? = nil) {
            let range = table.range(fromUTF8Offset: start, to: index)
            tokens.append(OCLToken(kind: kind, text: text(from: start, to: index), value: value, range: range))
        }

        /// Records an error that ends at the current offset.
        ///
        /// - Parameters:
        ///   - code: The diagnostic code.
        ///   - message: The description of the error.
        ///   - start: The offset where the erroneous text starts.
        mutating func report(_ code: String, _ message: String, from start: Int) {
            diagnostics.append(
                SourceDiagnostic(
                    severity: .error, code: code, message: message,
                    range: table.range(fromUTF8Offset: start, to: index)))
        }

        /// Scans the whole source into tokens.
        mutating func scanAll() {
            while index < bytes.count {
                let current = bytes[index]
                let start = index
                switch current {
                case 0x20, 0x09, 0x0A, 0x0D, 0x0C:
                    index += 1
                case UInt8(ascii: "-") where byte(at: index + 1) == UInt8(ascii: "-"):
                    while index < bytes.count, bytes[index] != 0x0A, bytes[index] != 0x0D { index += 1 }
                    emit(.comment, from: start)
                case UInt8(ascii: "/") where byte(at: index + 1) == UInt8(ascii: "*"):
                    scanBlockComment(from: start)
                case UInt8(ascii: "/") where byte(at: index + 1) == UInt8(ascii: "'"):
                    scanMultiLineString(from: start)
                case UInt8(ascii: "'"):
                    scanString(from: start, kind: .string)
                case UInt8(ascii: "_") where byte(at: index + 1) == UInt8(ascii: "'"):
                    index += 1
                    scanString(from: start, kind: .escapedIdentifier)
                case _ where Self.isLetter(current):
                    while let next = byte(at: index), Self.isLetter(next) || Self.isDigit(next) { index += 1 }
                    emit(.identifier, from: start)
                case _ where Self.isDigit(current):
                    scanNumber(from: start)
                default:
                    scanSymbol(from: start)
                }
            }
            let end = table.range(fromUTF8Offset: bytes.count, to: bytes.count)
            tokens.append(OCLToken(kind: .endOfInput, text: "", range: end))
        }

        /// Scans a block comment, reporting one that is not closed.
        ///
        /// - Parameter start: The offset where the comment starts.
        mutating func scanBlockComment(from start: Int) {
            index += 2
            while index < bytes.count {
                if bytes[index] == UInt8(ascii: "*"), byte(at: index + 1) == UInt8(ascii: "/") {
                    index += 2
                    emit(.comment, from: start)
                    return
                }
                index += 1
            }
            emit(.invalid, from: start)
            report(OCLDiagnosticCode.unterminatedComment, "Unterminated block comment", from: start)
        }

        /// Scans a multi-line string, reporting one that is not closed.
        ///
        /// - Parameter start: The offset where the string starts.
        mutating func scanMultiLineString(from start: Int) {
            index += 2
            while index < bytes.count {
                if bytes[index] == UInt8(ascii: "'"), byte(at: index + 1) == UInt8(ascii: "/") {
                    index += 2
                    emit(.multiLineString, from: start, value: text(from: start + 2, to: index - 2))
                    return
                }
                index += 1
            }
            emit(.invalid, from: start)
            report(OCLDiagnosticCode.unterminatedString, "Unterminated multi-line string", from: start)
        }

        /// Scans a quoted string whose opening quote is at the current index.
        mutating func scanString(from start: Int, kind: OCLToken.Kind) {
            index += 1
            var decoded: [UInt8] = []
            while index < bytes.count {
                let current = bytes[index]
                if current == UInt8(ascii: "'") {
                    index += 1
                    emit(kind, from: start, value: String(decoding: decoded, as: UTF8.self))
                    return
                }
                if current == 0x0A || current == 0x0D { break }
                if current == UInt8(ascii: "\\"), let escaped = byte(at: index + 1) {
                    index += 2
                    decoded.append(contentsOf: decode(escape: escaped))
                    continue
                }
                decoded.append(current)
                index += 1
            }
            emit(.invalid, from: start)
            report(OCLDiagnosticCode.unterminatedString, "Unterminated string literal", from: start)
        }

        /// Decodes the escape sequence whose character follows a backslash.
        mutating func decode(escape: UInt8) -> [UInt8] {
            switch escape {
            case UInt8(ascii: "n"): return [0x0A]
            case UInt8(ascii: "t"): return [0x09]
            case UInt8(ascii: "r"): return [0x0D]
            case UInt8(ascii: "b"): return [0x08]
            case UInt8(ascii: "f"): return [0x0C]
            case UInt8(ascii: "u"):
                let digits = (0..<4).compactMap { byte(at: index + $0) }
                let hex = String(decoding: digits, as: UTF8.self)
                if digits.count == 4, let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                    index += 4
                    return Array(String(Character(scalar)).utf8)
                }
                return [UInt8(ascii: "u")]
            default: return [escape]
            }
        }

        /// Scans an integer or real number.
        ///
        /// - Parameter start: The offset where the number starts.
        mutating func scanNumber(from start: Int) {
            while let next = byte(at: index), Self.isDigit(next) { index += 1 }
            var isReal = false
            if byte(at: index) == UInt8(ascii: "."), let after = byte(at: index + 1), Self.isDigit(after) {
                isReal = true
                index += 1
                while let next = byte(at: index), Self.isDigit(next) { index += 1 }
            }
            if let marker = byte(at: index), marker == UInt8(ascii: "e") || marker == UInt8(ascii: "E") {
                var lookahead = index + 1
                if let sign = byte(at: lookahead), sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") {
                    lookahead += 1
                }
                if let digit = byte(at: lookahead), Self.isDigit(digit) {
                    isReal = true
                    index = lookahead
                    while let next = byte(at: index), Self.isDigit(next) { index += 1 }
                }
            }
            emit(isReal ? .real : .integer, from: start)
        }

        /// Scans an operator or punctuation symbol, preferring the longest match.
        ///
        /// - Parameter start: The offset where the symbol starts.
        mutating func scanSymbol(from start: Int) {
            for symbol in OCLLexer.compoundSymbols {
                let utf8 = Array(symbol.utf8)
                if index + utf8.count <= bytes.count, Array(bytes[index..<index + utf8.count]) == utf8 {
                    index += utf8.count
                    emit(.symbol, from: start)
                    return
                }
            }
            if OCLLexer.simpleSymbols.contains(bytes[index]) {
                index += 1
                emit(.symbol, from: start)
                return
            }
            index += 1
            while index < bytes.count, bytes[index] & 0xC0 == 0x80 { index += 1 }
            emit(.invalid, from: start)
            report(OCLDiagnosticCode.invalidCharacter, "Unexpected character '\(text(from: start, to: index))'", from: start)
        }
    }
}

/// Classifies OCL tokens for syntax highlighting.
public enum OCLTokenClassifier {
    /// Classifies tokens into the shared kinds of source tokens.
    ///
    /// A simple name is a keyword if it is one of `keywords`, a Boolean if it is `true` or
    /// `false`, a type name if it names a primitive or collection type of OCL, and an identifier
    /// otherwise. Comments that start with `/**` are documentation.
    ///
    /// - Parameters:
    ///   - tokens: The tokens to classify; the end-of-input token is left out.
    ///   - keywords: The words that the language treats as keywords.
    /// - Returns: The classified tokens in order.
    public static func sourceTokens(of tokens: [OCLToken], keywords: Set<String>) -> [SourceToken] {
        tokens.compactMap { token in
            let kind: SourceTokenKind
            switch token.kind {
            case .endOfInput: return nil
            case .identifier:
                if token.text == OCLSyntax.trueLiteral || token.text == OCLSyntax.falseLiteral {
                    kind = .boolean
                } else if keywords.contains(token.text) {
                    kind = .keyword
                } else if OCLSyntax.primitiveTypeNames.contains(token.text)
                    || OCLSyntax.collectionTypeNames.contains(token.text)
                {
                    kind = .typeName
                } else {
                    kind = .identifier
                }
            case .escapedIdentifier: kind = .identifier
            case .string, .multiLineString: kind = .string
            case .integer, .real: kind = .number
            case .symbol:
                kind = token.text.utf8.allSatisfy({ "()[]{},;".utf8.contains($0) }) ? .punctuation : .operator
            case .comment: kind = token.text.hasPrefix("/**") ? .documentation : .comment
            case .invalid: kind = .invalid
            }
            return SourceToken(kind: kind, range: token.range)
        }
    }
}
