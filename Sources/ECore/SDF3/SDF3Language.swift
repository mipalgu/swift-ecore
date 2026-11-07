//
// SDF3Language.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The fixed vocabulary of SDF3 and of Stratego signatures.
///
/// Every spelling with a meaning to the reader is defined here once.
enum SDF3Language {
    /// The notation name that prefixes diagnostic codes and default namespace URIs.
    static let notation = "sdf3"

    /// Keywords that begin or name a section, together with the module header keywords.
    static let sectionKeywords: Set<String> = [
        module, imports, sorts, contextFree, lexical, kernel, syntax, templates, startSymbols, priorities,
        restrictions, template, options, signature, constructors, rules, strategies, overlays, variables,
        exports, hiddens, aliases,
    ]

    /// Keywords of production attributes, which tokens are classified as keywords.
    static let attributeKeywords: Set<String> = [
        "left", "right", "assoc", "non-assoc", "bracket", "reject", "prefer", "avoid", "cons",
        "case-insensitive", "deprecated", "keyword", "tokenize",
    ]

    /// The `module` keyword.
    static let module = "module"
    /// The `imports` keyword.
    static let imports = "imports"
    /// The `sorts` keyword.
    static let sorts = "sorts"
    /// The `context-free` keyword.
    static let contextFree = "context-free"
    /// The `lexical` keyword.
    static let lexical = "lexical"
    /// The `kernel` keyword.
    static let kernel = "kernel"
    /// The `syntax` keyword.
    static let syntax = "syntax"
    /// The `templates` keyword of early SDF3, a synonym of `context-free syntax`.
    static let templates = "templates"
    /// The `start-symbols` keyword.
    static let startSymbols = "start-symbols"
    /// The `priorities` keyword.
    static let priorities = "priorities"
    /// The `restrictions` keyword.
    static let restrictions = "restrictions"
    /// The `template` keyword of `template options`.
    static let template = "template"
    /// The `options` keyword of `template options`.
    static let options = "options"
    /// The `signature` keyword of Stratego.
    static let signature = "signature"
    /// The `constructors` keyword of Stratego signatures.
    static let constructors = "constructors"
    /// The `rules` keyword of Stratego.
    static let rules = "rules"
    /// The `strategies` keyword of Stratego.
    static let strategies = "strategies"
    /// The `overlays` keyword of Stratego.
    static let overlays = "overlays"
    /// The `variables` keyword.
    static let variables = "variables"
    /// The `exports` keyword of SDF2 modules, accepted and ignored.
    static let exports = "exports"
    /// The `hiddens` keyword of SDF2 modules, accepted and ignored.
    static let hiddens = "hiddens"
    /// The `aliases` keyword.
    static let aliases = "aliases"

    /// The attribute of productions that only add parentheses.
    static let bracketAttribute = "bracket"
    /// The attribute of productions that reject sentences.
    static let rejectAttribute = "reject"
    /// The SDF2 attribute that names a constructor, as in `{cons("Add")}`.
    static let consAttribute = "cons"

    /// The reserved sort of layout, which never becomes a classifier.
    static let layoutSort = "LAYOUT"
    /// The suffix of kernel sorts that marks a context-free sort.
    static let contextFreeSuffix = "-CF"
    /// The suffix of kernel sorts that marks a lexical sort.
    static let lexicalSuffix = "-LEX"
    /// The suffix of the placeholder constructors that the SDF3 signature generator adds.
    static let placeholderSuffix = "-Plhdr"
    /// The sort of completion insertions that the SDF3 signature generator adds.
    static let completionSort = "COMPLETION-INSERTION"

    /// The Stratego list type constructor.
    static let listType = "List"
    /// The Stratego option type constructor.
    static let optionType = "Option"

    /// The Stratego built-in types and the Ecore data types they map to.
    static let builtinTypes: [String: EcoreDataType] = [
        "string": .eString, "String": .eString, "int": .eInt, "Int": .eInt, "real": .eDouble, "Real": .eDouble,
    ]

    /// The class name of the values of data types made from lexical sorts.
    static let lexicalInstanceClassName = "java.lang.String"

    /// The name of the feature of a class that wraps an injected lexical sort.
    static let wrapperFeatureName = "value"

    /// The punctuation symbols, longest first where they share a prefix.
    static let punctuation = [
        "-/-", "->", "\\/", "/\\", "=", ".", ":", ",", "*", "+", "?", "|", "(", ")", "{", "}", "<", ">", "~",
        "/", ";", "!", "&", "#", "@", "$",
    ]

    /// The decoded values that mark template and placeholder delimiters among the tokens.
    enum Marker {
        /// The opening delimiter of a template.
        static let templateOpen = "\u{0}template-open"
        /// The closing delimiter of a template.
        static let templateClose = "\u{0}template-close"
        /// The opening delimiter of a placeholder.
        static let placeholderOpen = "\u{0}placeholder-open"
        /// The closing delimiter of a placeholder.
        static let placeholderClose = "\u{0}placeholder-close"
    }

    /// Whether a sort name is spelt entirely in capitals, as lexical sorts conventionally are.
    ///
    /// - Parameter name: The sort name.
    /// - Returns: `true` if the name has a letter and no lower-case letter.
    static func isConventionallyLexical(_ name: String) -> Bool {
        name.contains(where: \.isLetter) && !name.contains(where: \.isLowercase)
    }
}
