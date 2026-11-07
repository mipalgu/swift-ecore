//
// LangiumTypes.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Which types a Langium grammar may use.
///
/// Langium 4 introduced a strict mode, set with `"validation": { "types": "strict" }`
/// in `langium-config.json`, in which every type must be declared with
/// `interface` or `type` so that the metamodel cannot change unnoticed when the
/// grammar's rules change.
public enum LangiumTypeMode: String, Sendable, Hashable, CaseIterable {
    /// Declared and inferred types are allowed (Langium's default).
    case normal
    /// Only declared types are allowed; every inferred type is an error.
    case strict
}

/// Settings for importing a Langium grammar.
///
/// Langium grammars have no namespace, so the package takes its name from the
/// grammar (`grammar Name`), or else from ``packageName``, or else from the
/// source name; the namespace URI and prefix come from the options or are
/// derived from the package name.
public struct LangiumImportOptions: Sendable, Hashable {
    /// The package name to use when the grammar has no `grammar` declaration.
    public var packageName: String?

    /// The namespace URI of the package; by default `urn:langium:<name>`.
    public var nsURI: String?

    /// The namespace prefix of the package; by default the package name in lower case.
    public var nsPrefix: String?

    /// Which types the grammar may use.
    public var typeMode: LangiumTypeMode

    /// Creates import settings.
    ///
    /// - Parameters:
    ///   - packageName: The package name to use when the grammar declares none.
    ///   - nsURI: The namespace URI of the package.
    ///   - nsPrefix: The namespace prefix of the package.
    ///   - typeMode: Which types the grammar may use; defaults to ``LangiumTypeMode/normal``.
    public init(
        packageName: String? = nil, nsURI: String? = nil, nsPrefix: String? = nil, typeMode: LangiumTypeMode = .normal
    ) {
        self.packageName = packageName
        self.nsURI = nsURI
        self.nsPrefix = nsPrefix
        self.typeMode = typeMode
    }
}

/// The result of importing a Langium grammar.
///
/// Importing recovers from errors, so the package holds everything that could
/// be inferred, and the diagnostics describe what could not.
public struct LangiumParseResult: Sendable {
    /// The package of the grammar's types; empty only if nothing could be read.
    public var packages: [EPackage]

    /// The problems found, ordered by position.
    public var diagnostics: [SourceDiagnostic]

    /// The lexical tokens of the grammar, comments included.
    public var tokens: [SourceToken]

    /// The outline: one grammar node whose children are the imports, declared types and rules.
    public var outline: [OutlineNode]

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - packages: The packages.
    ///   - diagnostics: The problems found.
    ///   - tokens: The lexical tokens.
    ///   - outline: The outline.
    public init(packages: [EPackage], diagnostics: [SourceDiagnostic], tokens: [SourceToken], outline: [OutlineNode]) {
        self.packages = packages
        self.diagnostics = diagnostics
        self.tokens = tokens
        self.outline = outline
    }
}

/// The stable codes of the diagnostics that importing a Langium grammar reports.
public enum LangiumDiagnosticCode: String, Sendable, CaseIterable, Hashable {
    /// A token appears where the grammar language does not allow it.
    case unexpectedToken = "langium.unexpectedToken"
    /// A character cannot start any token.
    case unexpectedCharacter = "langium.unexpectedCharacter"
    /// A string literal has no closing quote.
    case unterminatedString = "langium.unterminatedString"
    /// A block comment has no closing delimiter.
    case unterminatedComment = "langium.unterminatedComment"
    /// A regular expression literal has no closing slash.
    case unterminatedRegex = "langium.unterminatedRegex"
    /// A rule is defined twice.
    case duplicateRule = "langium.duplicateRule"
    /// A called rule is not defined in the grammar.
    case unknownRule = "langium.unknownRule"
    /// A type is not defined in the grammar, for example because an imported grammar defines it.
    case externalType = "langium.externalType"
    /// Features would have to be added to a type that is not defined here.
    case sealedType = "langium.sealedType"
    /// A type reference cannot be resolved.
    case unresolvedTypeReference = "langium.unresolvedTypeReference"
    /// A property is assigned with a different cardinality or containment than before.
    case featureConflict = "langium.featureConflict"
    /// A property is assigned values whose types have no common type.
    case incompatibleTypes = "langium.incompatibleTypes"
    /// A rule changes the type of the current object twice.
    case typeChangedTwice = "langium.typeChangedTwice"
    /// A rule call is not allowed where it appears.
    case invalidRuleCall = "langium.invalidRuleCall"
    /// An assignment names a property that the declared type does not have.
    case undeclaredProperty = "langium.undeclaredProperty"
    /// A type is inferred in strict mode, where only declared types are allowed.
    case inferredTypeNotAllowed = "langium.inferredTypeNotAllowed"
    /// A construct is accepted but approximated in the metamodel.
    case approximation = "langium.approximation"
    /// Two classifiers of a package have the same name.
    case duplicateClassifier = "langium.duplicateClassifier"
    /// A class declares two features with the same name.
    case duplicateFeature = "langium.duplicateFeature"
    /// A type name resolves to no classifier.
    case unresolvedType = "langium.unresolvedType"
    /// A supertype is not a class, or would make inheritance circular.
    case invalidSupertype = "langium.invalidSupertype"
}

/// The kinds of node in the outline of a Langium grammar.
public enum LangiumOutlineKind {
    /// The grammar, which contains every other node.
    public static let grammar = "grammar"
    /// An `import` of another grammar file.
    public static let `import` = "import"
    /// A declared interface.
    public static let interface = "interface"
    /// A property of a declared interface.
    public static let attribute = "attribute"
    /// A declared type (`type T = ...`).
    public static let type = "type"
    /// A parser rule.
    public static let parserRule = "parserRule"
    /// A parser fragment.
    public static let fragment = "fragment"
    /// An infix rule.
    public static let infixRule = "infixRule"
    /// A terminal rule or terminal fragment.
    public static let terminalRule = "terminalRule"
}
