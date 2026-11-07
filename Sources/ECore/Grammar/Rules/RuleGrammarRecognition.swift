//
// RuleGrammarRecognition.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// Tells Xtext and Langium grammars apart from the start of a text.
///
/// Both notations start with `grammar` and a name. An Xtext grammar has a qualified name
/// (`grammar org.example.Arith`) or, with a simple name, declares its metamodels next
/// (`generate`, `import "uri" as alias`, or `hidden(...)`). A Langium grammar has a simple
/// name, optionally followed by `with` and the grammars it uses, and then its imports or
/// declarations, such as `entry`, `interface`, `type` or a rule.
enum RuleGrammarRecognition {
    /// The notation of a rule grammar.
    enum Notation {
        /// An Xtext grammar.
        case xtext
        /// A Langium grammar.
        case langium
    }

    /// The number of characters at the start of a text that are scanned.
    static let scannedLength = 16 * 1024

    /// The keyword that declares a grammar.
    static let grammarKeyword = "grammar"

    /// The keyword that names the grammars a grammar uses.
    static let withKeyword = "with"

    /// The Xtext keyword that generates a package.
    static let generateKeyword = "generate"

    /// The keyword of an import.
    static let importKeyword = "import"

    /// The Xtext keyword that names the alias of an imported package.
    static let aliasKeyword = "as"

    /// The keyword that declares the hidden tokens of a grammar.
    static let hiddenKeyword = "hidden"

    /// The symbol that separates the parts of a qualified name.
    static let nameSeparator = "."

    /// The symbol that separates the grammars after `with`.
    static let listSeparator = ","

    /// The symbol that opens the hidden tokens of an Xtext grammar.
    static let argumentsOpener = "("

    /// The symbol that ends a Langium import.
    static let statementTerminator = ";"

    /// The notation of a text that starts with a grammar declaration.
    ///
    /// Comments before the declaration are skipped. Only the first ``scannedLength``
    /// characters are scanned.
    ///
    /// - Parameter text: The text, or at least its beginning.
    /// - Returns: The notation, or `nil` if the text does not start with a grammar declaration.
    static func notation(of text: String) -> Notation? {
        var collector = DiagnosticCollector(document: nil)
        let tokens = RuleGrammarLexer.scan(
            String(text.prefix(scannedLength)), dialect: XtextSyntax.dialect, collector: &collector
        ).tokens.filter { !$0.isTrivia }
        var index = 0
        func isWord(_ word: String, at position: Int) -> Bool {
            position < tokens.count && tokens[position].kind == .identifier && tokens[position].text == word
        }
        func isSymbol(_ symbol: String, at position: Int) -> Bool {
            position < tokens.count && tokens[position].kind == .punctuation && tokens[position].text == symbol
        }
        func isName(at position: Int) -> Bool {
            position < tokens.count && tokens[position].kind == .identifier
        }
        guard isWord(grammarKeyword, at: 0), isName(at: 1) else { return nil }
        index = 2
        var isQualified = false
        while isSymbol(nameSeparator, at: index), isName(at: index + 1) {
            isQualified = true
            index += 2
        }
        if isQualified { return .xtext }
        if isWord(withKeyword, at: index) {
            index += 1
            while true {
                guard isName(at: index) else { return nil }
                index += 1
                while isSymbol(nameSeparator, at: index), isName(at: index + 1) {
                    isQualified = true
                    index += 2
                }
                guard isSymbol(listSeparator, at: index) else { break }
                index += 1
            }
            if isQualified { return .xtext }
        }
        guard index < tokens.count else { return nil }
        if isWord(generateKeyword, at: index) { return .xtext }
        if isWord(hiddenKeyword, at: index) && isSymbol(argumentsOpener, at: index + 1) { return .xtext }
        if isWord(importKeyword, at: index) {
            guard index + 1 < tokens.count, tokens[index + 1].kind == .string else { return nil }
            return isWord(aliasKeyword, at: index + 2) ? .xtext : .langium
        }
        return isName(at: index) || isSymbol(statementTerminator, at: index) ? .langium : nil
    }
}
