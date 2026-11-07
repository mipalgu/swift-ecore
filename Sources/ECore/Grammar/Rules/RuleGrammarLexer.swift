//
// RuleGrammarLexer.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// The lexical differences between the Xtext and Langium grammar notations.
struct RuleGrammarDialect: Sendable, Hashable {
    /// The prefix of diagnostic codes, such as `xtext`.
    var codePrefix: String

    /// Whether a lone `/` starts a regular expression literal, as in Langium terminal rules.
    var hasRegexLiterals: Bool

    /// The words that are classified as keywords for highlighting.
    var keywords: Set<String>

    /// The separator between the type and the terminal of a cross-reference (`|` or `:`).
    var crossReferenceSeparators: Set<String>

    /// Creates a dialect.
    ///
    /// - Parameters:
    ///   - codePrefix: The prefix of diagnostic codes.
    ///   - hasRegexLiterals: Whether a lone `/` starts a regular expression.
    ///   - keywords: The words classified as keywords.
    ///   - crossReferenceSeparators: The separators allowed in cross-references.
    init(
        codePrefix: String, hasRegexLiterals: Bool, keywords: Set<String>, crossReferenceSeparators: Set<String>
    ) {
        self.codePrefix = codePrefix
        self.hasRegexLiterals = hasRegexLiterals
        self.keywords = keywords
        self.crossReferenceSeparators = crossReferenceSeparators
    }

    /// The full diagnostic code of a problem.
    ///
    /// - Parameter problem: The kind of problem.
    /// - Returns: The code, prefixed with the notation.
    func code(_ problem: RuleGrammarProblem) -> String { codePrefix + "." + problem.rawValue }
}

/// Splits Xtext and Langium grammar text into tokens.
enum RuleGrammarLexer {
    /// The punctuation symbols of both notations.
    static let punctuation = [
        "::", "+=", "?=", "=>", "->", "..", "?!", "?<=", "?<!", "=", ":", ";", "|", "&", "(", ")", "[", "]",
        "{", "}", "<", ">", ",", ".", "?", "*", "+", "!", "@", "#",
    ]

    /// The operators among the punctuation symbols, for highlighting.
    static let operators: Set<String> = ["+=", "?=", "=", "=>", "->", "..", "|", "&", "?", "*", "+", "!"]

    /// Scans a text into tokens, comments included, and reports lexical problems.
    ///
    /// - Parameters:
    ///   - text: The grammar text.
    ///   - dialect: The notation.
    ///   - collector: Receives the lexical problems.
    /// - Returns: The tokens in source order and the empty range at the end of the text.
    static func scan(
        _ text: String, dialect: RuleGrammarDialect, collector: inout DiagnosticCollector
    ) -> (tokens: [ScannedToken], end: SourceRange) {
        var scanner = SourceScanner(text)
        var tokens: [ScannedToken] = []
        while true {
            scanner.skipWhitespace()
            guard let byte = scanner.peek() else { break }
            if scanner.hasPrefix("//") {
                tokens.append(scanner.scanLineComment())
            } else if scanner.hasPrefix("/*") {
                let comment = scanner.scanBlockComment()
                if !comment.isTerminated {
                    collector.error(
                        dialect.code(.unterminatedComment), "The block comment is not closed with '*/'",
                        at: comment.range)
                }
                tokens.append(comment)
            } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                let string = scanner.scanString()
                if !string.isTerminated {
                    collector.error(
                        dialect.code(.unterminatedString), "The string literal is not closed", at: string.range)
                }
                tokens.append(string)
            } else if dialect.hasRegexLiterals && byte == UInt8(ascii: "/") {
                let regex = scanRegex(&scanner)
                if !regex.isTerminated {
                    collector.error(
                        dialect.code(.unterminatedRegex), "The regular expression is not closed with '/'",
                        at: regex.range)
                }
                tokens.append(regex)
            } else if let identifier = scanner.scanIdentifier(escape: UInt8(ascii: "^")) {
                tokens.append(identifier)
            } else if let number = scanner.scanNumber() {
                tokens.append(number)
            } else if let symbol = scanner.scanPunctuation(punctuation) {
                tokens.append(symbol)
            } else {
                let invalid = scanner.scanInvalid()
                collector.error(
                    dialect.code(.unexpectedCharacter), "The character '\(invalid.text)' cannot start a token",
                    at: invalid.range)
                tokens.append(invalid)
            }
        }
        return (tokens, scanner.endRange)
    }

    /// Reads a regular expression literal such as `/[a-z]+/i`.
    ///
    /// A slash inside a character class or after a backslash does not end the
    /// literal. A literal that reaches the end of its line is unterminated.
    ///
    /// - Parameter scanner: The scanner, positioned at the opening slash.
    /// - Returns: The literal.
    private static func scanRegex(_ scanner: inout SourceScanner) -> ScannedToken {
        let start = scanner.offset
        scanner.offset += 1
        var inClass = false
        var terminated = false
        while let byte = scanner.peek(), byte != 0x0A && byte != 0x0D {
            if byte == UInt8(ascii: "\\") {
                scanner.offset += min(2, scanner.bytes.count - scanner.offset)
                continue
            }
            scanner.offset += 1
            if byte == UInt8(ascii: "[") {
                inClass = true
            } else if byte == UInt8(ascii: "]") {
                inClass = false
            } else if byte == UInt8(ascii: "/") && !inClass {
                terminated = true
                break
            }
        }
        if terminated {
            while let flag = scanner.peek(), flag >= UInt8(ascii: "a") && flag <= UInt8(ascii: "z") {
                scanner.offset += 1
            }
        }
        return scanner.token(.regex, from: start, isTerminated: terminated)
    }

    /// Converts scanned tokens into classified tokens for highlighting.
    ///
    /// - Parameters:
    ///   - tokens: The scanned tokens, comments included.
    ///   - dialect: The notation, whose keywords are highlighted.
    ///   - typeNameOffsets: The start offsets of identifiers known to name types.
    /// - Returns: The classified tokens in source order.
    static func sourceTokens(
        _ tokens: [ScannedToken], dialect: RuleGrammarDialect, typeNameOffsets: Set<Int> = []
    ) -> [SourceToken] {
        tokens.map { token in
            let kind: SourceTokenKind
            switch token.kind {
            case .identifier:
                if typeNameOffsets.contains(token.range.start.utf8Offset) {
                    kind = .typeName
                } else if token.text == "true" || token.text == "false" {
                    kind = .boolean
                } else {
                    kind = dialect.keywords.contains(token.text) ? .keyword : .identifier
                }
            case .string, .regex: kind = .string
            case .number: kind = .number
            case .punctuation: kind = operators.contains(token.text) ? .operator : .punctuation
            case .comment: kind = .comment
            case .documentation: kind = .documentation
            case .text: kind = .text
            case .invalid: kind = .invalid
            }
            return SourceToken(kind: kind, range: token.range)
        }
    }
}
