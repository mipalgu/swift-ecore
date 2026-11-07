//
// XtextSyntax.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Lexical analysis of Xtext grammars for tools such as editors.
public enum XtextSyntax {
    /// The namespace URI of Ecore, whose data types an Xtext grammar uses by importing it.
    public static let ecoreNamespaceURI = "http://www.eclipse.org/emf/2002/Ecore"

    /// The grammar that defines Xtext's common terminals.
    public static let commonTerminalsGrammar = "org.eclipse.xtext.common.Terminals"

    /// The reserved words of the grammar language, highlighted as keywords.
    public static let keywords: Set<String> = [
        "grammar", "with", "hidden", "generate", "import", "as", "returns", "terminal", "enum", "fragment",
        "current", "EOF",
    ]

    /// The notation settings shared with the rule-grammar engine.
    static let dialect = RuleGrammarDialect(
        codePrefix: "xtext", hasRegexLiterals: false, keywords: keywords, crossReferenceSeparators: ["|"])

    /// Splits Xtext grammar text into classified tokens.
    ///
    /// The tokeniser never fails: text that cannot be read becomes a token of
    /// kind ``SourceTokenKind/invalid``. Comments (`//` and `/* */`) are
    /// included, keywords of rule bodies are string tokens, and white space is
    /// not reported. Positions follow ``LineTable``.
    ///
    /// - Parameter text: The grammar text.
    /// - Returns: The tokens in source order.
    public static func tokens(in text: String) -> [SourceToken] {
        var collector = DiagnosticCollector(document: nil)
        let scanned = RuleGrammarLexer.scan(text, dialect: dialect, collector: &collector)
        return RuleGrammarLexer.sourceTokens(scanned.tokens, dialect: dialect)
    }

    /// Whether a text starts like an Xtext grammar.
    ///
    /// After comments, the text must declare a grammar with a qualified name
    /// (`grammar org.example.Arith`), or with a simple name followed by the grammars it
    /// uses with qualified names, or by `generate`, `import "uri" as alias` or `hidden(...)`.
    /// A Langium grammar is not taken for Xtext (see ``LangiumSyntax/looksLikeLangium(_:)``).
    /// Only the start of the text is examined.
    ///
    /// - Parameter text: The text, or at least its beginning.
    /// - Returns: `true` if the text starts like an Xtext grammar.
    public static func looksLikeXtext(_ text: String) -> Bool {
        RuleGrammarRecognition.notation(of: text) == .xtext
    }
}
