//
// XtextTypes.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Settings for importing an Xtext grammar.
///
/// An Xtext grammar names its generated packages itself, with
/// `generate name "nsURI"`, and Xtext uses the name as namespace prefix. The
/// namespace settings here override those of the default generated package
/// (the one without an alias, or else the first one) when they are set, for
/// example to give an imported metamodel a different identity. They do not
/// make a grammar without a `generate` declaration produce a package, since
/// only generated packages are imported.
public struct XtextImportOptions: Sendable, Hashable {
    /// The name to give the default generated package instead of the declared one.
    public var packageName: String?

    /// The namespace URI to give the default generated package instead of the declared one.
    public var nsURI: String?

    /// The namespace prefix to give the default generated package instead of its name.
    public var nsPrefix: String?

    /// Creates import settings.
    ///
    /// - Parameters:
    ///   - packageName: The name for the default generated package, if it should differ.
    ///   - nsURI: The namespace URI for the default generated package, if it should differ.
    ///   - nsPrefix: The namespace prefix for the default generated package, if it should differ.
    public init(packageName: String? = nil, nsURI: String? = nil, nsPrefix: String? = nil) {
        self.packageName = packageName
        self.nsURI = nsURI
        self.nsPrefix = nsPrefix
    }
}

/// The result of importing an Xtext grammar.
///
/// Importing recovers from errors, so the packages hold everything that could
/// be inferred, and the diagnostics describe what could not.
public struct XtextParseResult: Sendable {
    /// The generated packages, one per `generate` declaration, in declaration order.
    public var packages: [EPackage]

    /// The problems found, ordered by position.
    public var diagnostics: [SourceDiagnostic]

    /// The lexical tokens of the grammar, comments included.
    public var tokens: [SourceToken]

    /// The outline: one grammar node whose children are the metamodel declarations and rules.
    public var outline: [OutlineNode]

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - packages: The generated packages.
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

/// The stable codes of the diagnostics that importing an Xtext grammar reports.
public enum XtextDiagnosticCode: String, Sendable, CaseIterable, Hashable {
    /// A token appears where the grammar language does not allow it.
    case unexpectedToken = "xtext.unexpectedToken"
    /// A character cannot start any token.
    case unexpectedCharacter = "xtext.unexpectedCharacter"
    /// A string literal has no closing quote.
    case unterminatedString = "xtext.unterminatedString"
    /// A block comment has no closing delimiter.
    case unterminatedComment = "xtext.unterminatedComment"
    /// A regular expression literal has no closing slash (not used by Xtext itself).
    case unterminatedRegex = "xtext.unterminatedRegex"
    /// A rule is defined twice.
    case duplicateRule = "xtext.duplicateRule"
    /// A called rule is not defined in the grammar or its known super grammars.
    case unknownRule = "xtext.unknownRule"
    /// A type belongs to an imported package, which is not generated.
    case externalType = "xtext.externalType"
    /// Features would have to be added to a type of an imported package.
    case sealedType = "xtext.sealedType"
    /// A type reference names an undeclared alias or a type that cannot be created.
    case unresolvedTypeReference = "xtext.unresolvedTypeReference"
    /// A feature is assigned with a different cardinality or containment than before.
    case featureConflict = "xtext.featureConflict"
    /// A feature is assigned values whose types have no common type.
    case incompatibleTypes = "xtext.incompatibleTypes"
    /// A rule changes the type of the current object twice.
    case typeChangedTwice = "xtext.typeChangedTwice"
    /// A rule call is not allowed where it appears.
    case invalidRuleCall = "xtext.invalidRuleCall"
    /// An assignment names a property that a declared type does not have (not used by Xtext itself).
    case undeclaredProperty = "xtext.undeclaredProperty"
    /// A type is inferred where only declared types are allowed (not used by Xtext itself).
    case inferredTypeNotAllowed = "xtext.inferredTypeNotAllowed"
    /// A construct is accepted but approximated in the metamodel.
    case approximation = "xtext.approximation"
    /// Two classifiers of a package have the same name.
    case duplicateClassifier = "xtext.duplicateClassifier"
    /// A class declares two features with the same name.
    case duplicateFeature = "xtext.duplicateFeature"
    /// A type name resolves to no classifier.
    case unresolvedType = "xtext.unresolvedType"
    /// A supertype is not a class, or would make inheritance circular.
    case invalidSupertype = "xtext.invalidSupertype"
    /// The grammar declares no generated package, so nothing is imported.
    case noGeneratedPackage = "xtext.noGeneratedPackage"
}

/// The kinds of node in the outline of an Xtext grammar.
public enum XtextOutlineKind {
    /// The grammar, which contains every other node.
    public static let grammar = "grammar"
    /// A `generate` declaration.
    public static let generate = "generate"
    /// An `import` declaration.
    public static let `import` = "import"
    /// A parser rule.
    public static let parserRule = "parserRule"
    /// A parser fragment.
    public static let fragment = "fragment"
    /// A terminal rule or terminal fragment.
    public static let terminalRule = "terminalRule"
    /// An enum rule.
    public static let enumRule = "enumRule"
}
