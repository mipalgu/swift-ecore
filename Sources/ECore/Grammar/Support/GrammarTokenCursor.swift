//
// GrammarTokenCursor.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Collects the diagnostics of one document.
struct DiagnosticCollector: Sendable {
    /// The identifier of the document that the diagnostics refer to.
    let document: String?

    /// The diagnostics collected so far, in the order they were reported.
    private(set) var diagnostics: [SourceDiagnostic] = []

    /// Creates an empty collector.
    ///
    /// - Parameter document: The identifier of the document, if known.
    init(document: String?) {
        self.document = document
    }

    /// Records a diagnostic.
    ///
    /// - Parameters:
    ///   - severity: How serious the problem is.
    ///   - code: The stable identifier of the kind of problem.
    ///   - message: A human-readable description.
    ///   - range: The affected text, if any.
    mutating func report(
        _ severity: DiagnosticSeverity, _ code: String, _ message: String, at range: SourceRange?
    ) {
        diagnostics.append(SourceDiagnostic(
            severity: severity, code: code, message: message, range: range, document: document))
    }

    /// Records an error.
    ///
    /// - Parameters:
    ///   - code: The stable identifier of the kind of problem.
    ///   - message: A human-readable description.
    ///   - range: The affected text, if any.
    mutating func error(_ code: String, _ message: String, at range: SourceRange?) {
        report(.error, code, message, at: range)
    }

    /// Records a warning.
    ///
    /// - Parameters:
    ///   - code: The stable identifier of the kind of problem.
    ///   - message: A human-readable description.
    ///   - range: The affected text, if any.
    mutating func warning(_ code: String, _ message: String, at range: SourceRange?) {
        report(.warning, code, message, at: range)
    }

    /// Records an informational note.
    ///
    /// - Parameters:
    ///   - code: The stable identifier of the kind of problem.
    ///   - message: A human-readable description.
    ///   - range: The affected text, if any.
    mutating func information(_ code: String, _ message: String, at range: SourceRange?) {
        report(.information, code, message, at: range)
    }

    /// Appends diagnostics reported elsewhere, such as by the metamodel assembler.
    ///
    /// - Parameter other: The diagnostics to append.
    mutating func append(contentsOf other: [SourceDiagnostic]) {
        diagnostics.append(contentsOf: other)
    }

    /// The diagnostics ordered by their position, with document-wide ones last.
    ///
    /// Diagnostics at the same position keep the order in which they were reported.
    var sorted: [SourceDiagnostic] {
        diagnostics.enumerated().sorted { lhs, rhs in
            let left = lhs.element.range?.start.utf8Offset ?? Int.max
            let right = rhs.element.range?.start.utf8Offset ?? Int.max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }
}

/// A recursive-descent parser's view of the significant tokens of a text.
///
/// Comments are left out. The cursor never moves past the end, and asking for
/// a token there answers `nil`, so parsers recover from truncated input
/// without special cases.
struct GrammarTokenCursor: Sendable {
    /// The significant tokens in source order.
    let tokens: [ScannedToken]

    /// The position of the current token.
    var index = 0

    /// The empty range at the end of the text.
    let endRange: SourceRange

    /// Creates a cursor over the significant tokens among a list of tokens.
    ///
    /// - Parameters:
    ///   - tokens: All tokens of the text, including comments.
    ///   - endRange: The empty range at the end of the text.
    init(_ tokens: [ScannedToken], endRange: SourceRange) {
        self.tokens = tokens.filter { !$0.isTrivia }
        self.endRange = endRange
    }

    /// Whether every token has been consumed.
    var isAtEnd: Bool { index >= tokens.count }

    /// The current token, or `nil` at the end.
    var current: ScannedToken? { peek() }

    /// A token at a distance from the current one.
    ///
    /// - Parameter distance: How far ahead to look; zero is the current token.
    /// - Returns: The token, or `nil` beyond the end.
    func peek(_ distance: Int = 0) -> ScannedToken? {
        let position = index + distance
        return position >= 0 && position < tokens.count ? tokens[position] : nil
    }

    /// The range of the current token, or the end of the text.
    var currentRange: SourceRange { current?.range ?? endRange }

    /// The token consumed last, if any.
    var previous: ScannedToken? { index > 0 && index <= tokens.count ? tokens[index - 1] : nil }

    /// Whether the current token is the symbol or identifier spelt `text`.
    ///
    /// - Parameter text: The spelling to compare with.
    /// - Returns: `true` if it is.
    func check(_ text: String) -> Bool { current?.is(text) ?? false }

    /// Whether the current token is of a kind.
    ///
    /// - Parameter kind: The lexical category.
    /// - Returns: `true` if it is.
    func check(_ kind: ScannedTokenKind) -> Bool { current?.kind == kind }

    /// Consumes the current token.
    ///
    /// - Returns: The token, or `nil` at the end.
    @discardableResult
    mutating func advance() -> ScannedToken? {
        guard let token = current else { return nil }
        index += 1
        return token
    }

    /// Consumes the current token if it is spelt `text`.
    ///
    /// - Parameter text: The expected spelling.
    /// - Returns: The token, or `nil` if the current token differs.
    @discardableResult
    mutating func accept(_ text: String) -> ScannedToken? {
        check(text) ? advance() : nil
    }

    /// Consumes the current token if it is of a kind.
    ///
    /// - Parameter kind: The expected lexical category.
    /// - Returns: The token, or `nil` if the current token differs.
    @discardableResult
    mutating func accept(_ kind: ScannedTokenKind) -> ScannedToken? {
        check(kind) ? advance() : nil
    }

    /// The range from the start of a token to the end of the token consumed last.
    ///
    /// - Parameter start: The range of the first token of the construct.
    /// - Returns: The range of the whole construct.
    func range(from start: SourceRange) -> SourceRange {
        guard let previous, previous.range.end.utf8Offset >= start.start.utf8Offset else {
            return SourceRange(start: start.start, end: start.start)
        }
        return SourceRange(start: start.start, end: previous.range.end)
    }

    /// Skips tokens until one of a set of spellings is current, or the end.
    ///
    /// - Parameter spellings: The spellings at which to stop.
    mutating func skip(until spellings: Set<String>) {
        while let token = current, !(spellings.contains(token.text) && token.kind != .string) {
            index += 1
        }
    }
}
