//
// OCLTokenCursor.swift
// OCL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// The error thrown when OCL text does not follow the grammar.
public struct OCLSyntaxError: Error, Sendable, Hashable {
    /// The problem that stopped the parse.
    public var diagnostic: SourceDiagnostic

    /// Creates a syntax error.
    ///
    /// - Parameter diagnostic: The problem that stopped the parse.
    public init(_ diagnostic: SourceDiagnostic) {
        self.diagnostic = diagnostic
    }
}

/// A position in the significant tokens of OCL text.
///
/// Parsers of the OCL family share the cursor, so that a document parser can hand its
/// position to the expression parser and take it back afterwards. The cursor is a value:
/// saving and restoring it backtracks a speculative parse.
public struct OCLTokenCursor: Sendable {
    /// The tokens without comments, ending with an end-of-input token.
    public let tokens: [OCLToken]

    /// The UTF-8 bytes of the source text, for slicing the text of a range.
    public let source: [UInt8]

    /// The index of the current token.
    public var position: Int = 0

    /// Creates a cursor at the first token.
    ///
    /// - Parameters:
    ///   - tokens: The significant tokens, ending with an end-of-input token.
    ///   - source: The source text the tokens were read from.
    public init(tokens: [OCLToken], source: String) {
        precondition(tokens.last?.kind == .endOfInput, "The tokens must end with an end-of-input token")
        self.tokens = tokens
        self.source = Array(source.utf8)
    }

    /// The current token.
    public var current: OCLToken { tokens[Swift.min(position, tokens.count - 1)] }

    /// The token a number of places after the current one.
    ///
    /// - Parameter offset: How many tokens to look ahead.
    /// - Returns: The token, or the end-of-input token past the end.
    public func peek(_ offset: Int = 1) -> OCLToken { tokens[Swift.min(position + offset, tokens.count - 1)] }

    /// The token before the current one, if any.
    public var previous: OCLToken? { position > 0 ? tokens[position - 1] : nil }

    /// Whether the cursor is at the end of the text.
    public var isAtEnd: Bool { current.kind == .endOfInput }

    /// Moves to the next token.
    public mutating func advance() {
        if position < tokens.count - 1 { position += 1 }
    }

    /// The position at which the current token starts.
    public var startPosition: SourcePosition { current.range.start }

    /// The position just after the last token read.
    public var endPosition: SourcePosition { previous?.range.end ?? current.range.start }

    /// The range from a start position to the end of the last token read.
    ///
    /// - Parameter start: The position at which the construct started.
    /// - Returns: The range of the construct.
    public func range(from start: SourcePosition) -> SourceRange {
        SourceRange(start: start, end: Swift.max(start, endPosition))
    }

    /// The source text that a range covers.
    ///
    /// - Parameter range: A range of the source text.
    /// - Returns: The text, exactly as written.
    public func text(of range: SourceRange) -> String {
        let start = Swift.min(Swift.max(range.start.utf8Offset, 0), source.count)
        let end = Swift.min(Swift.max(range.end.utf8Offset, start), source.count)
        return String(decoding: source[start..<end], as: UTF8.self)
    }

    /// Whether the current token is the given word.
    ///
    /// - Parameter word: The word.
    /// - Returns: `true` if the current token is the simple name `word`.
    public func at(word: String) -> Bool { current.isWord(word) }

    /// Whether the current token is the given symbol.
    ///
    /// - Parameter symbol: The symbol.
    /// - Returns: `true` if the current token is the symbol.
    public func at(symbol: String) -> Bool { current.isSymbol(symbol) }

    /// Moves past the current token if it is the given word.
    ///
    /// - Parameter word: The word.
    /// - Returns: Whether the token was the word.
    @discardableResult
    public mutating func accept(word: String) -> Bool {
        guard at(word: word) else { return false }
        advance()
        return true
    }

    /// Moves past the current token if it is the given symbol.
    ///
    /// - Parameter symbol: The symbol.
    /// - Returns: Whether the token was the symbol.
    @discardableResult
    public mutating func accept(symbol: String) -> Bool {
        guard at(symbol: symbol) else { return false }
        advance()
        return true
    }

    /// Moves past the current token, which must be the given word.
    ///
    /// - Parameter word: The word.
    /// - Throws: ``OCLSyntaxError`` if the current token is not the word.
    public mutating func expect(word: String) throws {
        guard accept(word: word) else { throw error("Expected '\(word)'") }
    }

    /// Moves past the current token, which must be the given symbol.
    ///
    /// - Parameter symbol: The symbol.
    /// - Throws: ``OCLSyntaxError`` if the current token is not the symbol.
    public mutating func expect(symbol: String) throws {
        guard accept(symbol: symbol) else { throw error("Expected '\(symbol)'") }
    }

    /// Reads a name, simple or escaped.
    ///
    /// - Parameters:
    ///   - description: What the name denotes, for the error message.
    ///   - excluding: Simple words that may not be the name here.
    /// - Returns: The decoded name.
    /// - Throws: ``OCLSyntaxError`` if the current token is not a name.
    public mutating func expectName(_ description: String, excluding: Set<String> = []) throws -> String {
        let token = current
        guard token.isName, token.kind == .escapedIdentifier || !excluding.contains(token.text) else {
            throw error("Expected \(description)")
        }
        advance()
        return token.value
    }

    /// A description of the current token for messages.
    public var currentDescription: String {
        switch current.kind {
        case .endOfInput: return "end of text"
        case .string: return "string \(current.text)"
        default: return "'\(current.text)'"
        }
    }

    /// The error for the current token.
    ///
    /// - Parameter message: What was expected.
    /// - Returns: An error whose diagnostic covers the current token.
    public func error(_ message: String) -> OCLSyntaxError {
        let code = isAtEnd ? OCLDiagnosticCode.unexpectedEnd : OCLDiagnosticCode.unexpectedToken
        return OCLSyntaxError(
            SourceDiagnostic(
                severity: .error, code: code, message: message + " but found " + currentDescription,
                range: current.range))
    }
}
