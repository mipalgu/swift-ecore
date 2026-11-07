//
// SDF3Syntax.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Lexical analysis of SDF3 and Stratego signature text for tools such as editors.
public enum SDF3Syntax {
    /// The symbols that are classified as operators rather than punctuation.
    private static let operators: Set<String> = ["->", "-/-", "|", "*", "+", "?", "~", "\\/", "/\\", "!", "&"]

    /// Splits SDF3 or Stratego signature text into classified tokens.
    ///
    /// The tokeniser never fails: text that cannot be read becomes a token of
    /// kind ``SourceTokenKind/invalid``. Section and attribute keywords are
    /// keywords; sort names are type names; constructor names, labels and
    /// type variables are identifiers; string literals and character classes
    /// are strings; the literal text of templates is text; and comments are
    /// included. Whitespace is not reported. Positions count UTF-8 offsets,
    /// and lines and columns count from one.
    ///
    /// - Parameter text: The source text.
    /// - Returns: The tokens in source order.
    public static func tokens(in text: String) -> [SourceToken] {
        var lexer = SDF3Lexer(text)
        return classify(lexer.tokenise())
    }

    /// The number of characters at the start of a text that ``looksLikeSDF3(_:)`` scans.
    static let recognitionLength = 16 * 1024

    /// The symbols that may join the segments of a module name, as in `lang/Shapes`.
    static let moduleNameSeparators: Set<String> = ["/", "-", "."]

    /// Whether a text starts like an SDF3 syntax definition or a Stratego signature.
    ///
    /// After comments, the text must declare a module whose name, which may be a path such
    /// as `lang/Shapes`, is followed by a section such as `imports`, `sorts`,
    /// `context-free syntax`, `lexical syntax` or `signature`. An ASDL module, whose name is
    /// followed by its body in braces, is not taken for SDF3 (see
    /// ``ASDLSyntax/looksLikeASDL(_:)``). Only the start of the text is examined.
    ///
    /// - Parameter text: The text, or at least its beginning.
    /// - Returns: `true` if the text starts like an SDF3 module.
    public static func looksLikeSDF3(_ text: String) -> Bool {
        var lexer = SDF3Lexer(String(text.prefix(recognitionLength)))
        let tokens = lexer.tokenise().filter { !$0.isTrivia }
        guard tokens.count > 2, tokens[0].is(SDF3Language.module), tokens[1].kind == .identifier,
            !tokens[1].isSectionKeyword
        else { return false }
        var index = 2
        while index + 1 < tokens.count, tokens[index].kind == .punctuation,
            moduleNameSeparators.contains(tokens[index].text), tokens[index + 1].kind == .identifier
        {
            index += 2
        }
        guard index < tokens.count else { return false }
        return tokens[index].isSectionKeyword && !tokens[index].is(SDF3Language.module)
    }

    /// Classifies scanned tokens.
    ///
    /// An identifier right after `.` or right before `:` is a constructor or
    /// label; other identifiers are keywords, type names when capitalised, or
    /// plain identifiers.
    ///
    /// - Parameter scanned: The tokens, including comments.
    /// - Returns: The classified tokens.
    static func classify(_ scanned: [ScannedToken]) -> [SourceToken] {
        let significant = scanned.enumerated().filter { !$0.element.isTrivia }.map(\.offset)
        var position: [Int: Int] = [:]
        for (index, original) in significant.enumerated() { position[original] = index }
        return scanned.enumerated().map { index, token in
            let kind: SourceTokenKind
            switch token.kind {
            case .comment: kind = .comment
            case .documentation: kind = .documentation
            case .string, .regex: kind = .string
            case .number: kind = .number
            case .text: kind = .text
            case .invalid: kind = .invalid
            case .punctuation:
                kind = token.value == token.text && operators.contains(token.text) ? .operator : .punctuation
            case .identifier:
                let at = position[index] ?? 0
                let previous = at > 0 ? scanned[significant[at - 1]] : nil
                let next = at + 1 < significant.count ? scanned[significant[at + 1]] : nil
                if previous?.is(".") == true || next?.is(":") == true {
                    kind = .identifier
                } else if SDF3Language.sectionKeywords.contains(token.text)
                    || SDF3Language.attributeKeywords.contains(token.text)
                {
                    kind = .keyword
                } else if token.text.first?.isUppercase == true {
                    kind = .typeName
                } else {
                    kind = .identifier
                }
            }
            return SourceToken(kind: kind, range: token.range)
        }
    }
}
