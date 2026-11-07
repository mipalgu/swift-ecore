//
// KM3Syntax.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Lexical analysis of KM3 text for tools such as editors.
public enum KM3Syntax {
    /// Splits KM3 text into classified tokens.
    ///
    /// The tokeniser never fails: text that cannot be read becomes a token of kind
    /// ``SourceTokenKind/invalid``. Comments are included, and a comment that holds a
    /// directive such as `-- @nsURI http://example.org/library` is of kind
    /// ``SourceTokenKind/directive``. Reserved words are keywords; the names of declared
    /// classifiers and the names used as types or supertypes are type names; enumeration
    /// literal names are enumeration literals; other names are identifiers. Whitespace is
    /// not reported. Positions count UTF-8 offsets, lines from one and columns in Unicode
    /// scalars from one, and the line terminators `\r\n`, `\r` and `\n` each end one line.
    ///
    /// - Parameter text: The KM3 text.
    /// - Returns: The tokens in source order.
    public static func tokens(in text: String) -> [SourceToken] {
        var lexer = KM3Lexer(text)
        return sourceTokens(of: lexer.scanAll())
    }

    /// Tells whether a text looks like a KM3 document.
    ///
    /// A text looks like KM3 if, after comments and whitespace, it starts with the reserved
    /// word `package`, a name and an opening brace. The test reads only the first tokens, so
    /// it is cheap enough for detecting the format of a document.
    ///
    /// - Parameter text: The text to examine.
    /// - Returns: `true` if the text starts like a KM3 document.
    public static func looksLikeKM3(_ text: String) -> Bool {
        var lexer = KM3Lexer(String(text.prefix(4096)))
        let tokens = lexer.scanAll().tokens
        guard tokens.count >= 3 else { return false }
        return tokens[0].isKeyword(.package) && tokens[1].name != nil && tokens[2].isSymbol(KM3Symbol.openBrace)
    }

    /// Classifies the tokens and comments of a scan.
    ///
    /// - Parameter scan: The result of scanning KM3 text.
    /// - Returns: The tokens in source order, with comments.
    static func sourceTokens(of scan: KM3Scan) -> [SourceToken] {
        var result: [SourceToken] = []
        var commentIndex = 0
        var previous: KM3Token?
        var inSupertypes = false
        for token in scan.tokens where token.kind != .eof {
            while commentIndex < scan.comments.count,
                scan.comments[commentIndex].range.start.utf8Offset < token.range.start.utf8Offset
            {
                result.append(commentToken(scan.comments[commentIndex]))
                commentIndex += 1
            }
            if token.isKeyword(.extends) { inSupertypes = true }
            if token.isSymbol(KM3Symbol.openBrace) { inSupertypes = false }
            result.append(SourceToken(kind: kind(of: token, after: previous, inSupertypes: inSupertypes), range: token.range))
            previous = token
        }
        for comment in scan.comments[commentIndex...] { result.append(commentToken(comment)) }
        return result
    }

    /// Classifies a comment as a directive or an ordinary comment.
    ///
    /// - Parameter comment: The comment token.
    /// - Returns: The classified token.
    private static func commentToken(_ comment: KM3Token) -> SourceToken {
        guard case .comment(let body) = comment.kind, KM3Parser.directive(in: body) != nil else {
            return SourceToken(kind: .comment, range: comment.range)
        }
        return SourceToken(kind: .directive, range: comment.range)
    }

    /// Classifies a token by its kind and the token before it.
    ///
    /// - Parameters:
    ///   - token: The token.
    ///   - previous: The token before it, if any.
    ///   - inSupertypes: Whether the token is in the supertype list of a class.
    /// - Returns: The lexical category.
    private static func kind(of token: KM3Token, after previous: KM3Token?, inSupertypes: Bool) -> SourceTokenKind {
        switch token.kind {
        case .keyword: return .keyword
        case .name: return nameKind(after: previous, inSupertypes: inSupertypes)
        case .integer, .float: return .number
        case .string: return .string
        case .symbol(let symbol):
            return symbol == KM3Symbol.star || symbol == KM3Symbol.minus ? .operator : .punctuation
        case .comment: return .comment
        case .invalid: return .invalid
        case .eof: return .text
        }
    }

    /// Classifies a name by the token before it.
    ///
    /// - Parameters:
    ///   - previous: The token before the name, if any.
    ///   - inSupertypes: Whether the name is in the supertype list of a class.
    /// - Returns: The lexical category of the name.
    private static func nameKind(after previous: KM3Token?, inSupertypes: Bool) -> SourceTokenKind {
        guard let previous else { return .identifier }
        switch previous.kind {
        case .keyword(.class), .keyword(.datatype), .keyword(.enumeration), .keyword(.extends):
            return .typeName
        case .keyword(.literal):
            return .enumLiteral
        case .symbol(KM3Symbol.colon):
            return .typeName
        case .symbol(KM3Symbol.comma) where inSupertypes:
            return .typeName
        default:
            return .identifier
        }
    }
}
