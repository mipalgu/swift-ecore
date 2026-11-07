//
// TokenCursor.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// A position in a token sequence that a recursive-descent parser reads from.
///
/// The cursor never moves past the end-of-file token, so a parser can always look at the
/// current token, and every expectation that fails records a diagnostic instead of
/// throwing, so that parsing recovers and carries on.
struct TokenCursor {
    /// The tokens being read, ending with an end-of-file token.
    let tokens: [TextToken]

    /// The index of the current token.
    private(set) var position = 0

    /// The diagnostics recorded so far.
    var diagnostics: [SourceDiagnostic] = []

    /// The factory that creates diagnostics in the namespace of the notation.
    let factory: DiagnosticFactory

    /// Creates a cursor at the start of a token sequence.
    ///
    /// - Parameters:
    ///   - tokens: The tokens to read; an end-of-file token is added if missing.
    ///   - factory: The factory that creates diagnostics.
    init(tokens: [TextToken], factory: DiagnosticFactory) {
        var tokens = tokens
        if tokens.last?.kind != .endOfFile {
            let end = tokens.last?.range.end ?? .start
            tokens.append(TextToken(kind: .endOfFile, text: "", range: SourceRange(start: end, end: end)))
        }
        self.tokens = tokens
        self.factory = factory
    }

    /// The current token.
    var current: TextToken { tokens[position] }

    /// Whether the cursor is at the end of the text.
    var isAtEnd: Bool { current.kind == .endOfFile }

    /// The token at a distance from the current one, or the end-of-file token.
    ///
    /// - Parameter distance: The number of tokens to look ahead.
    /// - Returns: The token at that distance.
    func peek(_ distance: Int = 0) -> TextToken {
        tokens[min(position + distance, tokens.count - 1)]
    }

    /// The token before the current one, if any.
    var previous: TextToken? { position > 0 ? tokens[position - 1] : nil }

    /// Moves to the next token unless at the end, and returns the token moved past.
    @discardableResult
    mutating func advance() -> TextToken {
        let token = current
        if !isAtEnd { position += 1 }
        return token
    }

    /// Moves past the current token if it is the given punctuation.
    ///
    /// - Parameter symbol: The punctuation symbol.
    /// - Returns: `true` if the token was consumed.
    @discardableResult
    mutating func accept(_ symbol: String) -> Bool {
        guard current.isPunctuation(symbol) else { return false }
        advance()
        return true
    }

    /// Moves past the current token if it is the given unescaped word.
    ///
    /// - Parameter word: The keyword.
    /// - Returns: `true` if the token was consumed.
    @discardableResult
    mutating func acceptWord(_ word: String) -> Bool {
        guard current.isWord(word) else { return false }
        advance()
        return true
    }

    /// Moves past the given punctuation, or records an error if it is missing.
    ///
    /// The cursor does not move when the punctuation is missing, so that the parser can
    /// carry on as if it had been present.
    ///
    /// - Parameters:
    ///   - symbol: The expected punctuation symbol.
    ///   - context: A phrase that says where the symbol is expected.
    /// - Returns: `true` if the symbol was present.
    @discardableResult
    mutating func expect(_ symbol: String, _ context: String) -> Bool {
        if accept(symbol) { return true }
        unexpected("'\(symbol)' \(context)")
        return false
    }

    /// Moves past the given word, or records an error if it is missing.
    ///
    /// - Parameters:
    ///   - word: The expected keyword.
    ///   - context: A phrase that says where the keyword is expected.
    /// - Returns: `true` if the keyword was present.
    @discardableResult
    mutating func expectWord(_ word: String, _ context: String) -> Bool {
        if acceptWord(word) { return true }
        unexpected("'\(word)' \(context)")
        return false
    }

    /// Records an error that something else was expected at the current token.
    ///
    /// Two consecutive errors at the same token are reported only once.
    ///
    /// - Parameter expectation: What the grammar expects, such as `"a name"`.
    mutating func unexpected(_ expectation: String) {
        let token = current
        let found = token.kind == .endOfFile ? "end of text" : "'\(token.text)'"
        let diagnostic = factory.error(.unexpectedToken, "Expected \(expectation) but found \(found)", at: token.range)
        if let last = diagnostics.last, last.code == diagnostic.code, last.range == diagnostic.range { return }
        diagnostics.append(diagnostic)
    }

    /// Records a diagnostic.
    ///
    /// - Parameter diagnostic: The diagnostic to record.
    mutating func report(_ diagnostic: SourceDiagnostic) {
        diagnostics.append(diagnostic)
    }

    /// Skips tokens until one of the given symbols or words, or a balanced closing brace.
    ///
    /// Nested braces are skipped as a whole, so that recovery inside a declaration does not
    /// leave the enclosing block. The stopping token is not consumed.
    ///
    /// - Parameters:
    ///   - symbols: Punctuation at which to stop.
    ///   - words: Keywords at which to stop.
    mutating func skip(untilAny symbols: Set<String>, orWords words: Set<String> = []) {
        var depth = 0
        while !isAtEnd {
            let token = current
            if depth == 0 {
                if token.kind == .punctuation, symbols.contains(token.text) { return }
                if token.kind == .identifier, !token.isEscaped, words.contains(token.text) { return }
                if token.isPunctuation("}") { return }
            }
            if token.isPunctuation("{") { depth += 1 }
            if token.isPunctuation("}") { depth -= 1 }
            advance()
        }
    }

    /// Skips a balanced block that starts at the current `{` and returns its range.
    ///
    /// - Returns: The range from the opening to the closing brace, or `nil` if the current
    ///   token is not an opening brace.
    mutating func skipBlock() -> SourceRange? {
        guard current.isPunctuation("{") else { return nil }
        let start = current.range.start
        var depth = 0
        var end = current.range.end
        while !isAtEnd {
            let token = advance()
            end = token.range.end
            if token.isPunctuation("{") { depth += 1 }
            if token.isPunctuation("}") {
                depth -= 1
                if depth == 0 { return SourceRange(start: start, end: end) }
            }
        }
        unexpected("'}' to close the block")
        return SourceRange(start: start, end: end)
    }

    /// The range from a start position to the end of the previous token.
    ///
    /// - Parameter start: The start of the range.
    /// - Returns: The covered range.
    func range(from start: SourcePosition) -> SourceRange {
        let end = previous.map { max($0.range.end, start) } ?? start
        return SourceRange(start: start, end: end)
    }
}

// MARK: - Multiplicities

extension TokenCursor {
    /// Reads a bracketed multiplicity if the current token opens one.
    ///
    /// Both notations write a multiplicity as `[]`, `[*]`, `[+]`, `[?]`, `[n]`, `[n..m]`,
    /// `[n..*]` or `[n..?]`. An empty pair of brackets and `*` stand for any number of
    /// values, `+` for one or more, `?` for an optional value, and `?` as an upper bound
    /// for an unspecified bound. When the lower bound is a symbol, any upper bound is
    /// ignored.
    ///
    /// - Returns: The lower and upper bounds, or `nil` if the current token is not `[`.
    mutating func multiplicity() -> (lower: Int, upper: Int)? {
        guard accept("[") else { return nil }
        if accept("]") { return (0, MultiplicityText.unboundedValue) }
        guard let first = boundToken() else {
            unexpected("a multiplicity bound")
            skipToClosingBracket()
            return (0, 1)
        }
        var result: (lower: Int, upper: Int)
        switch first {
        case MultiplicityText.unbounded: result = (0, MultiplicityText.unboundedValue)
        case MultiplicityText.oneOrMore: result = (1, MultiplicityText.unboundedValue)
        case MultiplicityText.optional: result = (0, 1)
        default:
            let value = MultiplicityText.value(of: first) ?? 0
            result = (value, value)
        }
        if accept(MultiplicityText.rangeSeparator) {
            guard let second = boundToken() else {
                unexpected("an upper bound")
                skipToClosingBracket()
                return result
            }
            if Int(first.replacingOccurrences(of: "_", with: "")) != nil {
                result.upper = MultiplicityText.value(of: second) ?? result.upper
            }
        }
        expect("]", "to close the multiplicity")
        return result
    }

    /// Skips past the `]` of a malformed multiplicity if it closes on the same line.
    ///
    /// Recovery stops at the end of the line and at `;`, `{` and `}`, so that a missing
    /// bracket does not swallow the declarations that follow.
    private mutating func skipToClosingBracket() {
        let line = current.range.start.line
        var distance = 0
        while true {
            let token = peek(distance)
            if token.kind == .endOfFile || token.range.start.line != line { return }
            if token.kind == .punctuation, [";", "{", "}"].contains(token.text) { return }
            if token.isPunctuation("]") { break }
            distance += 1
        }
        for _ in 0...distance { advance() }
    }

    /// Reads the next token as a bound of a multiplicity.
    ///
    /// - Returns: The text of the bound, or `nil` if the next token is no bound.
    private mutating func boundToken() -> String? {
        let token = current
        if token.kind == .integer { return advance().text }
        if token.kind == .punctuation,
            [MultiplicityText.unbounded, MultiplicityText.oneOrMore, MultiplicityText.optional].contains(token.text)
        {
            return advance().text
        }
        return nil
    }
}
