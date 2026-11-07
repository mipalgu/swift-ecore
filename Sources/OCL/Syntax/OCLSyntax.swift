//
// OCLSyntax.swift
// OCL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The codes of the diagnostics that the OCL readers, writers and translators report.
///
/// Every code is a dotted string whose first segment names the language that reports it, so
/// that a tool showing diagnostics from several languages can tell them apart.
public enum OCLDiagnosticCode {
    /// A token appeared where the grammar does not allow it.
    public static let unexpectedToken = "ocl.unexpectedToken"

    /// The text ended where more was required.
    public static let unexpectedEnd = "ocl.unexpectedEnd"

    /// A string literal has no closing quote.
    public static let unterminatedString = "ocl.unterminatedString"

    /// A block comment has no closing `*/`.
    public static let unterminatedComment = "ocl.unterminatedComment"

    /// A character that OCL does not use.
    public static let invalidCharacter = "ocl.invalidCharacter"

    /// An expression could not be read.
    public static let invalidExpression = "ocl.invalidExpression"

    /// A name refers to a type, package or feature that cannot be found.
    public static let unresolvedName = "ocl.unresolvedName"

    /// A declaration names an element that is already declared.
    public static let duplicateDeclaration = "ocl.duplicateDeclaration"

    /// The text uses a construct that is read but has no counterpart in Ecore.
    public static let unsupportedConstruct = "ocl.unsupportedConstruct"

    /// An element of a model cannot be written in the textual form.
    public static let unwritableElement = "ocl.unwritableElement"

    /// An OCL construct has no AQL translation.
    public static let untranslatable = "ocl.untranslatable"

    /// An OCL construct has an AQL translation whose meaning differs in some cases.
    public static let semanticGap = "ocl.semanticGap"

    /// A Complete OCL context names a classifier, operation or property that the metamodels lack.
    public static let unresolvedContext = "ocl.unresolvedContext"
}

/// The spellings of the words, operators and type names of Essential OCL.
///
/// Readers, writers and translators compare against these constants rather than spelling the
/// words themselves, so that every part of the package agrees on them.
public enum OCLSyntax {
    /// The separator of the segments of a qualified name.
    public static let pathSeparator = "::"

    /// The name of the variable that holds the context object.
    public static let selfKeyword = "self"

    /// The name of the variable that holds the result of an operation in a postcondition.
    public static let resultVariable = "result"

    /// The keyword that starts a conditional expression.
    public static let ifKeyword = "if"

    /// The keyword that separates the condition of a conditional from its first branch.
    public static let thenKeyword = "then"

    /// The keyword that starts a further condition of a conditional.
    public static let elseifKeyword = "elseif"

    /// The keyword that starts the last branch of a conditional.
    public static let elseKeyword = "else"

    /// The keyword that ends a conditional.
    public static let endifKeyword = "endif"

    /// The keyword that starts a let expression.
    public static let letKeyword = "let"

    /// The keyword that separates the variables of a let expression from its body.
    public static let inKeyword = "in"

    /// The Boolean literal `true`.
    public static let trueLiteral = "true"

    /// The Boolean literal `false`.
    public static let falseLiteral = "false"

    /// The null literal.
    public static let nullLiteral = "null"

    /// The invalid literal.
    public static let invalidLiteral = "invalid"

    /// The suffix that refers to the value of an expression before an operation.
    public static let preKeyword = "pre"

    /// The logical conjunction.
    public static let andKeyword = "and"

    /// The logical disjunction.
    public static let orKeyword = "or"

    /// The exclusive disjunction.
    public static let xorKeyword = "xor"

    /// The logical implication.
    public static let impliesKeyword = "implies"

    /// The logical negation.
    public static let notKeyword = "not"

    /// The words that Essential OCL reserves, which cannot name elements without escaping.
    public static let reservedWords: Set<String> = [
        andKeyword, "and2", elseKeyword, endifKeyword, ifKeyword, impliesKeyword, "implies2",
        inKeyword, letKeyword, notKeyword, "not2", orKeyword, "or2", thenKeyword, "with",
        xorKeyword, "xor2", elseifKeyword, selfKeyword, trueLiteral, falseLiteral, nullLiteral,
        invalidLiteral,
    ]

    /// The names of the collection types, which can start a collection literal.
    public static let collectionTypeNames: Set<String> = [
        "Collection", "Set", "OrderedSet", "Bag", "Sequence",
    ]

    /// The name of the tuple type, which can start a tuple literal.
    public static let tupleTypeName = "Tuple"

    /// The name of the map type, which can start a map literal.
    public static let mapTypeName = "Map"

    /// The name of the lambda literal.
    public static let lambdaName = "Lambda"

    /// The names of the primitive types of the OCL standard library.
    public static let primitiveTypeNames: Set<String> = [
        "Boolean", "Integer", "Real", "String", "UnlimitedNatural", "OclAny", "OclInvalid",
        "OclVoid", "OclMessage", "OclState",
    ]

    /// The binary operators, from the loosest binding to the tightest, as OCL defines them.
    ///
    /// Each inner array holds the operators of one precedence level.
    public static let binaryOperatorLevels: [[String]] = [
        [impliesKeyword, "implies2"],
        [xorKeyword, "xor2"],
        [orKeyword, "or2"],
        [andKeyword, "and2"],
        ["=", "<>"],
        ["<", ">", "<=", ">="],
        ["+", "-"],
        ["*", "/"],
    ]

    /// The unary operators.
    public static let unaryOperators: Set<String> = ["-", notKeyword, "not2"]

    /// The navigation operators that call an operation or navigate a property of one object.
    public static let objectNavigationOperators: Set<String> = [".", "?."]

    /// The navigation operators that apply to a collection.
    public static let collectionNavigationOperators: Set<String> = ["->", "?->"]

    /// The message operators of Complete OCL.
    public static let messageOperators: Set<String> = ["^", "^^"]

    /// The names of the iterations that take iterator variables.
    public static let iterationNames: Set<String> = [
        "any", "closure", "collect", "collectNested", "exists", "forAll", "isUnique", "iterate",
        "one", "reject", "select", "sortedBy", "collectBy", "selectByKind",
    ]
}
