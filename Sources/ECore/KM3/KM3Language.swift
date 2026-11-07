//
// KM3Language.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The reserved words of KM3.
///
/// A reserved word is recognised only when it is written without quotes. A name that
/// is spelt like a reserved word is written in double quotes, as in
/// `reference "operation" : Operation;`.
public enum KM3Keyword: String, Sendable, CaseIterable, Hashable {
    /// Starts a package declaration.
    case package

    /// Starts a data type declaration.
    case datatype

    /// Starts an enumeration declaration.
    case enumeration

    /// Starts an enumeration literal declaration.
    case literal

    /// Marks a class as abstract.
    case abstract

    /// Starts a class declaration.
    case `class`

    /// Introduces the supertypes of a class.
    case extends

    /// Starts an attribute declaration.
    case attribute

    /// Starts a reference declaration.
    case reference

    /// Starts an operation declaration.
    case operation

    /// Marks a feature as ordered.
    case ordered

    /// Marks an attribute as unique.
    case unique

    /// Marks a reference as a containment.
    case container

    /// Introduces the features that a reference subsets.
    case subsets

    /// Introduces the opposite of a reference.
    case oppositeOf
}

/// The punctuation of KM3 and the other symbols that its lexer recognises.
public enum KM3Symbol {
    /// Opens the body of a package, class or enumeration.
    public static let openBrace = "{"

    /// Closes the body of a package, class or enumeration.
    public static let closeBrace = "}"

    /// Opens the parameter list of an operation.
    public static let openParenthesis = "("

    /// Closes the parameter list of an operation.
    public static let closeParenthesis = ")"

    /// Opens a multiplicity.
    public static let openBracket = "["

    /// Closes a multiplicity.
    public static let closeBracket = "]"

    /// Ends a declaration.
    public static let semicolon = ";"

    /// Separates a name from its type.
    public static let colon = ":"

    /// Separates the entries of a list.
    public static let comma = ","

    /// Separates the bounds of a multiplicity.
    public static let minus = "-"

    /// Denotes an unbounded upper bound.
    public static let star = "*"

    /// The symbols of two characters that the lexer reads as one token.
    static let compound: [String] = ["::", "->", "<-", "<=", ">=", "<>"]

    /// The symbols of one character that the lexer reads as one token.
    static let single: Set<Character> = [
        "{", "}", "(", ")", "[", "]", ";", ":", ",", "-", "*", "!", "|", "#", "?", ".", "/", "+",
        "=", "<", ">",
    ]
}

/// The comment syntax of KM3 and the directives that comments can carry.
public enum KM3Directive {
    /// Starts a comment that extends to the end of the line.
    public static let commentMarker = "--"

    /// Starts the name of a directive inside a comment, as in `-- @nsURI`.
    public static let marker: Character = "@"

    /// Gives the namespace URI of the package that follows.
    public static let nsURI = "nsURI"

    /// Gives the namespace prefix of the package that follows.
    public static let nsPrefix = "nsPrefix"
}

/// The conventional file name extension and other facts about KM3 documents.
public enum KM3Format {
    /// The conventional file name extension of KM3 documents, without the leading dot.
    public static let fileExtension = "km3"

    /// The name of the package that holds the primitive data types of a KM3 document.
    public static let primitiveTypesPackageName = "PrimitiveTypes"
}

/// The kinds of node in the outline of a KM3 document.
///
/// The kinds are the values of ``OutlineNode/kind`` in the outline that
/// ``KM3ParseResult`` carries.
public enum KM3OutlineKind {
    /// A package, whose children are its classifiers and nested packages.
    public static let package = "package"

    /// A class, whose children are its attributes, references and operations.
    public static let `class` = "class"

    /// A data type.
    public static let dataType = "datatype"

    /// An enumeration, whose children are its literals.
    public static let enumeration = "enumeration"

    /// An enumeration literal.
    public static let literal = "literal"

    /// An attribute.
    public static let attribute = "attribute"

    /// A reference.
    public static let reference = "reference"

    /// An operation.
    public static let operation = "operation"
}

/// The stable codes of the diagnostics that reading and writing KM3 report.
///
/// Each code is a dotted identifier that tools can match on without depending on
/// the wording of a message.
public enum KM3DiagnosticCode: String, Sendable, CaseIterable, Hashable {
    /// A character cannot start any token.
    case unexpectedCharacter = "km3.unexpectedCharacter"

    /// A quoted name or a string has no closing quote.
    case unterminatedString = "km3.unterminatedString"

    /// A number is too large or otherwise unreadable.
    case invalidNumber = "km3.invalidNumber"

    /// A token appears where the grammar does not allow it.
    case unexpectedToken = "km3.unexpectedToken"

    /// A token that the grammar requires is missing.
    case missingToken = "km3.missingToken"

    /// A multiplicity is malformed or its bounds contradict each other.
    case invalidMultiplicity = "km3.invalidMultiplicity"

    /// A modifier does not apply to the declaration it is written on.
    case inapplicableModifier = "km3.inapplicableModifier"

    /// A directive is malformed, empty or repeated.
    case invalidDirective = "km3.invalidDirective"

    /// A construct of KM3 has no counterpart in Ecore and is ignored.
    case unsupportedConstruct = "km3.unsupportedConstruct"

    /// Two classifiers of the same package share a name.
    case duplicateClassifier = "km3.duplicateClassifier"

    /// Classifiers of different packages share a name, so that the name is ambiguous.
    case ambiguousClassifier = "km3.ambiguousClassifier"

    /// Two members of a class, two literals of an enumeration, or two packages share a name.
    case duplicateMember = "km3.duplicateMember"

    /// A type name refers to no classifier.
    case unresolvedType = "km3.unresolvedType"

    /// A supertype name refers to no class.
    case unresolvedSupertype = "km3.unresolvedSupertype"

    /// A class inherits from itself, directly or indirectly.
    case cyclicInheritance = "km3.cyclicInheritance"

    /// An opposite name refers to no reference of the referenced class.
    case unresolvedOpposite = "km3.unresolvedOpposite"

    /// Two references name each other inconsistently as opposites.
    case inconsistentOpposite = "km3.inconsistentOpposite"

    /// A reference or a supertype refers to a classifier of the wrong kind.
    case invalidTypeKind = "km3.invalidTypeKind"

    /// An Ecore element has a property that KM3 cannot express; writing drops it.
    case inexpressible = "km3.write.inexpressible"

    /// An Ecore element refers to a classifier outside the written packages.
    case externalType = "km3.write.externalType"

    /// An Ecore element has a name that KM3 cannot keep apart from another one.
    case ambiguousName = "km3.write.ambiguousName"
}
