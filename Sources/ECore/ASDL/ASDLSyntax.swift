//
// ASDLSyntax.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Lexical analysis of ASDL descriptions for tools such as editors, and the
/// spellings that reading and writing share.
public enum ASDLSyntax {
    /// The source of the annotations that keep ASDL details Ecore cannot express.
    ///
    /// Features record the built-in or external ASDL type they were read from
    /// (`type`), whether they come from an `attributes` clause (`attribute`),
    /// whether their name was generated (`generatedName`) and quantifiers that
    /// Ecore approximates (`quantifiers`). Packages record a module's `version` and `imports`.
    /// ``ASDLWriter`` reads these details back.
    public static let annotationSource = "http://asdl.sourceforge.net/"

    /// The keys of the annotation details.
    public enum AnnotationKey {
        /// The ASDL type of an attribute, such as `identifier`.
        public static let type = "type"
        /// Marks a feature that comes from an `attributes` clause.
        public static let attribute = "attribute"
        /// Marks a feature whose name was generated because the field had none.
        public static let generatedName = "generatedName"
        /// The quantifiers of a field that Ecore approximates, such as `?*`.
        public static let quantifiers = "quantifiers"
        /// The version string of a module.
        public static let version = "version"
        /// The modules that a module imports, separated by spaces.
        public static let imports = "imports"
    }

    /// The value of a detail that marks a feature.
    public static let markerValue = "true"

    /// The keywords of ASDL.
    public enum Keyword {
        /// Starts a module.
        public static let module = "module"
        /// Starts the attributes shared by the constructors of a type.
        public static let attributes = "attributes"
        /// Introduces the version string of a module.
        public static let version = "version"
        /// Introduces imported modules in the asdlGen dialect.
        public static let imports = "imports"
    }

    /// The punctuation of ASDL.
    enum Symbol {
        /// Separates a type name from its definition.
        static let equals = "="
        /// Separates constructors.
        static let bar = "|"
        /// Opens a field list.
        static let openParenthesis = "("
        /// Closes a field list.
        static let closeParenthesis = ")"
        /// Separates fields.
        static let comma = ","
        /// Marks an optional field.
        static let optional = "?"
        /// Marks a sequence field.
        static let sequence = "*"
        /// Opens the body of a module.
        static let openBrace = "{"
        /// Closes the body of a module.
        static let closeBrace = "}"
        /// Separates a module name from a type name.
        static let dot = "."
        /// Every punctuation symbol.
        static let all = [equals, bar, openParenthesis, closeParenthesis, comma, optional, sequence, openBrace, closeBrace, dot]
    }

    /// The prefix of a comment, which runs to the end of the line.
    static let commentPrefix = "--"

    /// Splits ASDL text into classified tokens.
    ///
    /// The tokeniser never fails: text that cannot be read becomes a token of
    /// kind ``SourceTokenKind/invalid``. Comments are included and white space
    /// is not. The text is parsed as well, so that type names, including the
    /// built-in types, are of kind ``SourceTokenKind/typeName``, constructors
    /// and field names of kind ``SourceTokenKind/identifier``, and keywords of
    /// kind ``SourceTokenKind/keyword``. Positions follow ``LineTable``.
    ///
    /// - Parameter text: The ASDL text.
    /// - Returns: The tokens in source order.
    public static func tokens(in text: String) -> [SourceToken] {
        ASDLReader.parse(text).tokens
    }

    /// Scans ASDL text into tokens, including comments.
    ///
    /// - Parameter text: The ASDL text.
    /// - Returns: The tokens in source order and the empty range at the end of the text.
    /// The number of characters at the start of a text that ``looksLikeASDL(_:)`` scans.
    static let recognitionLength = 16 * 1024

    /// Whether a text starts like an ASDL description.
    ///
    /// After comments, the text must declare a module whose name is followed by its body,
    /// optionally after a `version` string and an asdlGen import list:
    /// `module Arith {` or `module Python version "1.0" {`. An SDF3 module, whose name is
    /// followed by sections such as `imports` or `context-free syntax`, is not taken for
    /// ASDL (see ``SDF3Syntax/looksLikeSDF3(_:)``). Only the start of the text is examined.
    ///
    /// - Parameter text: The text, or at least its beginning.
    /// - Returns: `true` if the text starts like an ASDL description.
    public static func looksLikeASDL(_ text: String) -> Bool {
        let tokens = scan(String(text.prefix(recognitionLength))).tokens.filter { !$0.isTrivia }
        guard tokens.count > 2, tokens[0].is(Keyword.module), tokens[1].kind == .identifier,
            !tokens[1].is(Keyword.module)
        else { return false }
        var index = 2
        if tokens[index].is(Keyword.version) {
            guard index + 1 < tokens.count, tokens[index + 1].kind == .string else { return false }
            index += 2
        }
        if index < tokens.count, tokens[index].is(Symbol.openParenthesis) {
            while index < tokens.count, !tokens[index].is(Symbol.closeParenthesis) { index += 1 }
            index += 1
        }
        return index < tokens.count && tokens[index].is(Symbol.openBrace)
    }

    static func scan(_ text: String) -> (tokens: [ScannedToken], endRange: SourceRange) {
        var scanner = SourceScanner(text)
        var tokens: [ScannedToken] = []
        while true {
            scanner.skipWhitespace()
            guard let byte = scanner.peek() else { break }
            if scanner.hasPrefix(commentPrefix) {
                tokens.append(scanner.scanLineComment())
            } else if byte == UInt8(ascii: "\"") {
                tokens.append(scanner.scanString())
            } else if let identifier = scanner.scanIdentifier() {
                tokens.append(identifier)
            } else if let symbol = scanner.scanPunctuation(Symbol.all) {
                tokens.append(symbol)
            } else {
                tokens.append(scanner.scanInvalid())
            }
        }
        return (tokens, scanner.endRange)
    }

    /// The default classification of a scanned token, before parsing refines it.
    ///
    /// - Parameter token: The scanned token.
    /// - Returns: The kind of source token.
    static func defaultKind(of token: ScannedToken) -> SourceTokenKind {
        switch token.kind {
        case .identifier:
            [Keyword.module, Keyword.attributes].contains(token.text) ? .keyword : .identifier
        case .string: .string
        case .number: .number
        case .punctuation: .punctuation
        case .comment: .comment
        case .documentation: .documentation
        case .regex: .string
        case .text: .text
        case .invalid: .invalid
        }
    }
}
