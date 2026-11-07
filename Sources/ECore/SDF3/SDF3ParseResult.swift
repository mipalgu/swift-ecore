//
// SDF3ParseResult.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// The result of reading an SDF3 definition or a Stratego signature.
///
/// Reading recovers from errors, so the packages hold everything that could be
/// read, and the diagnostics describe what could not.
public struct SDF3ParseResult: Sendable {
    /// The packages made from the source; one per module.
    public var packages: [EPackage]

    /// The problems found, ordered by their position in the source.
    public var diagnostics: [SourceDiagnostic]

    /// The lexical tokens of the source, including comments.
    public var tokens: [SourceToken]

    /// The outline of the source.
    ///
    /// A module node holds the sections, which hold their sorts, productions
    /// and constructors. A source without a module declaration has the
    /// sections at the top level.
    public var outline: [OutlineNode]

    /// Creates a parse result.
    ///
    /// - Parameters:
    ///   - packages: The packages made from the source.
    ///   - diagnostics: The problems found.
    ///   - tokens: The lexical tokens of the source.
    ///   - outline: The outline of the source.
    public init(packages: [EPackage], diagnostics: [SourceDiagnostic], tokens: [SourceToken], outline: [OutlineNode]) {
        self.packages = packages
        self.diagnostics = diagnostics
        self.tokens = tokens
        self.outline = outline
    }
}

/// The stable codes of the diagnostics that reading SDF3 and Stratego signatures reports.
///
/// Each code is a dotted identifier that tools can match on without depending
/// on the wording of a message.
public enum SDF3DiagnosticCode: String, Sendable, CaseIterable, Hashable {
    /// A token appears where the syntax does not allow it.
    case unexpectedToken = "sdf3.unexpectedToken"

    /// A required token, such as `=` or a name, is missing.
    case expectedToken = "sdf3.expectedToken"

    /// A character cannot start any token.
    case invalidCharacter = "sdf3.invalidCharacter"

    /// A string literal has no closing quote.
    case unterminatedString = "sdf3.unterminatedString"

    /// A block comment has no closing `*/`.
    case unterminatedComment = "sdf3.unterminatedComment"

    /// A character class has no closing `]`.
    case unterminatedCharacterClass = "sdf3.unterminatedCharacterClass"

    /// A template has no closing delimiter.
    case unterminatedTemplate = "sdf3.unterminatedTemplate"

    /// A template placeholder has no closing delimiter.
    case unterminatedPlaceholder = "sdf3.unterminatedPlaceholder"

    /// A symbol cannot be represented as a feature, such as a sequence in a context-free production.
    case unsupportedSymbol = "sdf3.unsupportedSymbol"

    /// A sort is used but defined nowhere in the source, typically because it comes from an import.
    case undefinedSort = "sdf3.undefinedSort"

    /// A sort is defined both lexically and context-free; it is treated as context-free.
    case sortKindConflict = "sdf3.sortKindConflict"

    /// A constructor name clashes with another classifier and was renamed.
    case constructorRenamed = "sdf3.constructorRenamed"

    /// A lexical sort is injected into a context-free sort and was wrapped in a class.
    case lexicalInjection = "sdf3.lexicalInjection"

    /// The source declares more than one module; everything is read into the first.
    case multipleModules = "sdf3.multipleModules"

    /// Two classifiers of a package have the same name.
    case duplicateClassifier = "sdf3.duplicateClassifier"

    /// A class declares two features with the same name.
    case duplicateFeature = "sdf3.duplicateFeature"

    /// A type name resolves to no classifier.
    case unresolvedType = "sdf3.unresolvedType"

    /// A supertype is not a class, or would make inheritance circular.
    case invalidSupertype = "sdf3.invalidSupertype"
}

/// The kinds of node in the outline of an SDF3 definition or Stratego signature.
///
/// The kinds are the values of ``OutlineNode/kind`` in the outline that
/// ``SDF3ParseResult`` carries.
public enum SDF3OutlineKind {
    /// The module declaration, which contains every other node.
    public static let module = "module"

    /// An imported module.
    public static let importedModule = "import"

    /// A section, such as `context-free syntax` or `signature constructors`.
    public static let section = "section"

    /// A declared sort.
    public static let sort = "sort"

    /// A production or signature entry that defines a constructor.
    public static let constructor = "constructor"

    /// A production or signature entry without a constructor, such as an injection.
    public static let injection = "injection"
}
