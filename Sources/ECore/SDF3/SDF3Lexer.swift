//
// SDF3Lexer.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// Splits SDF3 and Stratego signature text into tokens.
///
/// SDF3 is context sensitive: the right-hand side of a context-free production
/// may be a template, whose text is free and whose placeholders hold symbols,
/// while `[` in lexical syntax starts a character class. The lexer therefore
/// follows the section headers it passes. In context-free sections, a `<` or
/// `[` right after `=` opens a template; template text becomes ``ScannedTokenKind/text``
/// tokens, and template and placeholder delimiters are punctuation tokens
/// whose values are the markers of ``SDF3Language/Marker``. Everywhere else a
/// `[` starts a character class, which becomes a ``ScannedTokenKind/regex``
/// token.
struct SDF3Lexer {
    /// The kind of section the lexer is in, which decides how `<` and `[` are read.
    private enum Mode {
        /// Context-free syntax, where productions may have templates.
        case contextFree
        /// Lexical syntax, where `[` starts a character class.
        case lexical
        /// Any other section.
        case other
    }

    /// The scanner over the source text.
    private var scanner: SourceScanner

    /// The tokens read so far, including comments.
    private var tokens: [ScannedToken] = []

    /// The section kind the lexer is in.
    private var mode = Mode.other

    /// Prepares to tokenise a text.
    ///
    /// - Parameter text: The source text.
    init(_ text: String) {
        scanner = SourceScanner(text)
    }

    /// The empty range at the end of the text.
    var endRange: SourceRange { scanner.endRange }

    /// Tokenises the whole text.
    ///
    /// - Returns: Every token in source order, including comments.
    mutating func tokenise() -> [ScannedToken] {
        while true {
            scanner.skipWhitespace()
            guard let byte = scanner.peek() else { break }
            if scanner.hasPrefix("//") {
                tokens.append(scanner.scanLineComment())
            } else if scanner.hasPrefix("/*") {
                tokens.append(scanner.scanBlockComment())
            } else if (byte == UInt8(ascii: "<") || byte == UInt8(ascii: "[")) && mode == .contextFree
                && lastSignificant?.is("=") == true
            {
                scanTemplate()
            } else {
                append(scanSymbolToken())
            }
        }
        return tokens
    }

    /// The last token that is not a comment.
    private var lastSignificant: ScannedToken? { tokens.last { !$0.isTrivia } }

    /// Appends a token and follows section headers.
    ///
    /// - Parameter token: The token to append.
    private mutating func append(_ token: ScannedToken) {
        if token.kind == .identifier {
            switch token.text {
            case SDF3Language.syntax, SDF3Language.templates:
                mode = lastSignificant?.is(SDF3Language.lexical) == true ? .lexical : .contextFree
            case SDF3Language.sorts, SDF3Language.priorities, SDF3Language.restrictions, SDF3Language.options,
                SDF3Language.signature, SDF3Language.rules, SDF3Language.strategies, SDF3Language.imports,
                SDF3Language.module, SDF3Language.startSymbols, SDF3Language.variables, SDF3Language.constructors,
                SDF3Language.aliases:
                mode = .other
            default: break
            }
        }
        tokens.append(token)
    }

    /// Reads one token outside template text.
    ///
    /// - Returns: The token; a character that starts no token becomes an invalid token.
    private mutating func scanSymbolToken() -> ScannedToken {
        guard let byte = scanner.peek() else { return scanner.scanInvalid() }
        if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") { return scanner.scanString() }
        if byte == UInt8(ascii: "[") { return scanCharacterClass() }
        if let identifier = scanner.scanIdentifier(extraParts: [UInt8(ascii: "-")]) { return identifier }
        if let number = scanner.scanNumber() { return number }
        if let symbol = scanner.scanPunctuation(SDF3Language.punctuation) { return symbol }
        return scanner.scanInvalid()
    }

    /// Reads a character class such as `[a-zA-Z\_]`.
    ///
    /// A backslash escapes the next character. A class without a closing
    /// bracket ends at the end of its line.
    ///
    /// - Returns: The class as a regular expression token.
    private mutating func scanCharacterClass() -> ScannedToken {
        let start = scanner.offset
        scanner.offset += 1
        var terminated = false
        while let byte = scanner.peek(), byte != 0x0A && byte != 0x0D {
            if byte == UInt8(ascii: "\\") && scanner.peek(1) != nil {
                scanner.offset += 2
                continue
            }
            scanner.offset += 1
            if byte == UInt8(ascii: "]") {
                terminated = true
                break
            }
        }
        return scanner.token(.regex, from: start, isTerminated: terminated)
    }

    /// Reads a template that opens at the current offset, with its text and placeholders.
    ///
    /// The template's own delimiters and its placeholder delimiters are the
    /// same characters: `<` and `>` or `[` and `]`. A backslash escapes the
    /// next character of template text. An unterminated template runs to the
    /// end of the text without a closing token.
    private mutating func scanTemplate() {
        let open = scanner.peek()!
        let close = open == UInt8(ascii: "<") ? UInt8(ascii: ">") : UInt8(ascii: "]")
        appendDelimiter(SDF3Language.Marker.templateOpen)
        var textStart: Int?
        /// Appends the pending run of template text, if any, as a text token.
        ///
        /// - Parameter lexer: The lexer that receives the token.
        func flush(_ lexer: inout SDF3Lexer) {
            if let start = textStart {
                lexer.tokens.append(lexer.scanner.token(.text, from: start))
                textStart = nil
            }
        }
        while let byte = scanner.peek() {
            if byte == UInt8(ascii: "\\") && scanner.peek(1) != nil {
                if textStart == nil { textStart = scanner.offset }
                scanner.offset += 2
            } else if byte == open {
                flush(&self)
                scanPlaceholder(close: close)
            } else if byte == close {
                flush(&self)
                appendDelimiter(SDF3Language.Marker.templateClose)
                return
            } else if SourceScanner.isWhitespace(byte) {
                flush(&self)
                scanner.offset += 1
            } else {
                if textStart == nil { textStart = scanner.offset }
                scanner.offset += 1
            }
        }
        flush(&self)
    }

    /// Reads a placeholder that opens at the current offset.
    ///
    /// - Parameter close: The byte that closes the placeholder.
    private mutating func scanPlaceholder(close: UInt8) {
        appendDelimiter(SDF3Language.Marker.placeholderOpen)
        while true {
            scanner.skipWhitespace()
            guard let byte = scanner.peek() else { return }
            if byte == close {
                appendDelimiter(SDF3Language.Marker.placeholderClose)
                return
            }
            if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                tokens.append(scanner.scanString())
            } else if let identifier = scanner.scanIdentifier(extraParts: [UInt8(ascii: "-")]) {
                tokens.append(identifier)
            } else if let number = scanner.scanNumber() {
                tokens.append(number)
            } else if let symbol = scanner.scanPunctuation(SDF3Language.punctuation.filter { $0.utf8.first != close }) {
                tokens.append(symbol)
            } else {
                tokens.append(scanner.scanInvalid())
            }
        }
    }

    /// Appends a one-character delimiter token whose value is a marker.
    ///
    /// - Parameter marker: The marker that tells the parser what the delimiter does.
    private mutating func appendDelimiter(_ marker: String) {
        let start = scanner.offset
        scanner.offset += 1
        tokens.append(scanner.token(.punctuation, from: start, value: marker))
    }
}

/// Queries about scanned tokens that only SDF3 needs.
extension ScannedToken {
    /// Whether the token is a template or placeholder delimiter with a marker.
    ///
    /// - Parameter marker: One of the markers of ``SDF3Language/Marker``.
    /// - Returns: `true` if the token carries that marker.
    func isMarker(_ marker: String) -> Bool { kind == .punctuation && value == marker }

    /// Whether the token is an identifier that is a section keyword.
    var isSectionKeyword: Bool { kind == .identifier && SDF3Language.sectionKeywords.contains(text) }
}
