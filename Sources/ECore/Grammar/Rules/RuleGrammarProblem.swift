//
// RuleGrammarProblem.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The kinds of problem that reading and inferring a rule grammar can find.
///
/// The raw value is the last segment of a diagnostic code; the full code is
/// prefixed with the notation, for example `xtext.unknownRule`. The public
/// diagnostic code enumerations of the Xtext and Langium importers mirror
/// every case.
enum RuleGrammarProblem: String, Sendable, CaseIterable {
    /// A token appears where the grammar does not allow it.
    case unexpectedToken
    /// A character cannot start any token.
    case unexpectedCharacter
    /// A string literal has no closing quote.
    case unterminatedString
    /// A block comment has no closing delimiter.
    case unterminatedComment
    /// A regular expression literal has no closing slash.
    case unterminatedRegex
    /// A rule is defined twice; the later definition replaces the earlier one.
    case duplicateRule
    /// A called rule is not defined in the grammar.
    case unknownRule
    /// A type belongs to a package that is referred to but not generated.
    case externalType
    /// Features would have to be added to a type that is not generated.
    case sealedType
    /// A type name resolves to no package that can hold it.
    case unresolvedTypeReference
    /// A feature is assigned with a different cardinality or containment than before.
    case featureConflict
    /// A feature is assigned values whose types have no common type.
    case incompatibleTypes
    /// A rule changes the type of the current object twice.
    case typeChangedTwice
    /// A rule call or assignment is not allowed where it appears.
    case invalidRuleCall
    /// An assignment names a property that the declared type does not have.
    case undeclaredProperty
    /// A type is inferred where only declared types are allowed.
    case inferredTypeNotAllowed
    /// A construct is accepted but approximated in the metamodel.
    case approximation
}
