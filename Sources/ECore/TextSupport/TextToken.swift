//
// TextToken.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// The lexical category of a token in a textual metamodel notation.
///
/// The categories are shared by every textual notation that the package reads, so that
/// the parsers, the token classifiers and the diagnostics can be written once.
enum TextTokenKind: Sendable, Hashable {
    /// A name, possibly escaped so that it can spell a keyword.
    case identifier

    /// A string literal; the token value holds the decoded text.
    case string

    /// A character literal; the token value holds the decoded character.
    case character

    /// An integer literal without a sign.
    case integer

    /// A floating-point literal without a sign.
    case real

    /// One of the punctuation or operator symbols of the notation.
    case punctuation

    /// A comment that runs to the end of its line.
    case lineComment

    /// A comment enclosed in `/*` and `*/`.
    case blockComment

    /// A documentation comment enclosed in `/**` and `*/`.
    case documentationComment

    /// Text that cannot start any token, or a literal that is malformed.
    case invalid

    /// The end of the text.
    case endOfFile
}

/// A token of a textual metamodel notation, with its source range.
///
/// A token keeps both its source text and its decoded value: the value of a string literal
/// has its escapes resolved, and the value of an escaped identifier drops the escape
/// character, so that a parser can compare values while diagnostics can quote text.
struct TextToken: Sendable, Hashable {
    /// The lexical category of the token.
    var kind: TextTokenKind

    /// The text of the token exactly as it appears in the source.
    var text: String

    /// The decoded value of the token.
    var value: String

    /// The source range that the token covers.
    var range: SourceRange

    /// Whether the token is an identifier written with an escape character.
    ///
    /// An escaped identifier is never read as a keyword.
    var isEscaped: Bool

    /// Creates a token.
    ///
    /// - Parameters:
    ///   - kind: The lexical category of the token.
    ///   - text: The source text of the token.
    ///   - value: The decoded value of the token, by default its source text.
    ///   - range: The source range that the token covers.
    ///   - isEscaped: Whether the token is an escaped identifier.
    init(
        kind: TextTokenKind, text: String, value: String? = nil, range: SourceRange,
        isEscaped: Bool = false
    ) {
        self.kind = kind
        self.text = text
        self.value = value ?? text
        self.range = range
        self.isEscaped = isEscaped
    }

    /// Whether the token is the given punctuation symbol.
    ///
    /// - Parameter symbol: The symbol to compare with.
    /// - Returns: `true` if the token is punctuation spelt as `symbol`.
    func isPunctuation(_ symbol: String) -> Bool {
        kind == .punctuation && text == symbol
    }

    /// Whether the token is the given unescaped word.
    ///
    /// Keywords of the textual notations are reserved only in some positions, so a parser
    /// recognises a keyword by comparing an unescaped identifier with its spelling.
    ///
    /// - Parameter word: The word to compare with.
    /// - Returns: `true` if the token is an unescaped identifier spelt as `word`.
    func isWord(_ word: String) -> Bool {
        kind == .identifier && !isEscaped && text == word
    }

    /// Whether the token is a comment of any kind.
    var isComment: Bool {
        kind == .lineComment || kind == .blockComment || kind == .documentationComment
    }
}

/// A problem found while scanning text into tokens.
struct LexicalProblem: Sendable, Hashable {
    /// The kind of problem.
    var kind: TextDiagnosticKind

    /// A message that describes the problem.
    var message: String

    /// The source range that the problem covers.
    var range: SourceRange
}

/// The result of scanning a text: the tokens a parser reads, the comments and the problems.
struct LexicalScan: Sendable {
    /// The tokens without comments, ending with an end-of-file token.
    var tokens: [TextToken] = []

    /// The comments in source order.
    var comments: [TextToken] = []

    /// The lexical problems in source order.
    var problems: [LexicalProblem] = []

    /// Every token and comment in source order, without the end-of-file token.
    var allTokens: [TextToken] {
        var merged: [TextToken] = []
        merged.reserveCapacity(tokens.count + comments.count)
        var commentIndex = 0
        for token in tokens where token.kind != .endOfFile {
            while commentIndex < comments.count,
                comments[commentIndex].range.start.utf8Offset < token.range.start.utf8Offset
            {
                merged.append(comments[commentIndex])
                commentIndex += 1
            }
            merged.append(token)
        }
        merged.append(contentsOf: comments[commentIndex...])
        return merged
    }
}
