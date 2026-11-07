//
// LangiumSyntax.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Lexical analysis of Langium grammars for tools such as editors.
public enum LangiumSyntax {
    /// The reserved words of the grammar language, highlighted as keywords.
    public static let keywords: Set<String> = [
        "grammar", "with", "import", "entry", "fragment", "hidden", "terminal", "returns", "infers", "infer",
        "interface", "extends", "type", "current", "infix", "on", "assoc", "left", "right", "EOF",
    ]

    /// Langium's primitive types and the Ecore data types they map to.
    ///
    /// `number` is a JavaScript number, a double-precision value, so it maps
    /// to `EDouble`; `bigint` maps to `EBigInteger`.
    public static let primitiveTypes: [String: EcoreDataType] = [
        "string": .eString, "number": .eDouble, "boolean": .eBoolean, "bigint": .eBigInteger, "Date": .eDate,
    ]

    /// The implementing classes of the primitive types, for data types that alias them.
    static let primitiveInstanceClasses: [String: String] = [
        "string": "java.lang.String", "number": "java.lang.Double", "boolean": "java.lang.Boolean",
        "bigint": "java.math.BigInteger", "Date": "java.util.Date",
    ]

    /// The notation settings shared with the rule-grammar engine.
    static let dialect = RuleGrammarDialect(
        codePrefix: "langium", hasRegexLiterals: true, keywords: keywords, crossReferenceSeparators: [":", "|"])

    /// Splits Langium grammar text into classified tokens.
    ///
    /// The tokeniser never fails: text that cannot be read becomes a token of
    /// kind ``SourceTokenKind/invalid``. Comments (`//` and `/* */`) are
    /// included, regular expressions such as `/[a-z]+/` are string tokens, and
    /// white space is not reported. Positions follow ``LineTable``.
    ///
    /// - Parameter text: The grammar text.
    /// - Returns: The tokens in source order.
    public static func tokens(in text: String) -> [SourceToken] {
        var collector = DiagnosticCollector(document: nil)
        let scanned = RuleGrammarLexer.scan(text, dialect: dialect, collector: &collector)
        return RuleGrammarLexer.sourceTokens(scanned.tokens, dialect: dialect)
    }

    /// Whether a text starts like a Langium grammar.
    ///
    /// After comments, the text must declare a grammar with a simple name
    /// (`grammar Arith`), optionally followed by `with` and the grammars it uses, and then
    /// by an import or a declaration such as `entry`, `interface`, `type` or a rule. An Xtext
    /// grammar, which has a qualified name or declares its metamodels with `generate` or
    /// `import "uri" as alias`, is not taken for Langium (see
    /// ``XtextSyntax/looksLikeXtext(_:)``). Only the start of the text is examined.
    ///
    /// - Parameter text: The text, or at least its beginning.
    /// - Returns: `true` if the text starts like a Langium grammar.
    public static func looksLikeLangium(_ text: String) -> Bool {
        RuleGrammarRecognition.notation(of: text) == .langium
    }
}
