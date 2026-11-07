//
// OCLExpression.swift
// OCL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// A multiplicity such as `[1]`, `[0..*]`, `[?]` or `[1..*|1]`.
public struct OCLMultiplicity: Sendable, Hashable {
    /// The value of an unbounded upper bound, as Ecore writes it.
    public static let unbounded = -1

    /// The lowest number of values.
    public var lower: Int

    /// The highest number of values, or ``unbounded``.
    public var upper: Int

    /// Whether the values may not be null (`|1`), may be null (`|?`), or are left unstated (`nil`).
    public var isNullFree: Bool?

    /// Creates a multiplicity.
    ///
    /// - Parameters:
    ///   - lower: The lowest number of values.
    ///   - upper: The highest number of values, or ``unbounded``.
    ///   - isNullFree: Whether the values may not be null, if stated.
    public init(lower: Int, upper: Int, isNullFree: Bool? = nil) {
        self.lower = lower
        self.upper = upper
        self.isNullFree = isNullFree
    }

    /// The multiplicity of exactly one value, which OCLinEcore assumes when none is written.
    public static let one = OCLMultiplicity(lower: 1, upper: 1)

    /// The shortest OCLinEcore spelling of the multiplicity, such as `[?]`, `[*]` or `[2..5]`.
    public var text: String {
        let bounds: String
        switch (lower, upper) {
        case (0, 1): bounds = "?"
        case (0, Self.unbounded): bounds = "*"
        case (1, Self.unbounded): bounds = "+"
        case (_, Self.unbounded): bounds = "\(lower)..*"
        case _ where lower == upper: bounds = "\(lower)"
        default: bounds = "\(lower)..\(upper)"
        }
        let nullity = isNullFree.map { $0 ? "|1" : "|?" } ?? ""
        return "[" + bounds + nullity + "]"
    }
}

/// A reference to a type, such as `String`, `ecore::EDate`, `Set(Book)` or `Tuple(a : Integer)`.
public struct OCLTypeReference: Sendable, Hashable {
    /// A named part of a tuple type.
    public struct Part: Sendable, Hashable {
        /// The name of the part.
        public var name: String

        /// The type of the part.
        public var type: OCLTypeReference

        /// Creates a part of a tuple type.
        ///
        /// - Parameters:
        ///   - name: The name of the part.
        ///   - type: The type of the part.
        public init(name: String, type: OCLTypeReference) {
            self.name = name
            self.type = type
        }
    }

    /// The segments of the qualified name of the type, such as `["ecore", "EDate"]`.
    public var path: [String]

    /// The type arguments, such as the element type of a collection or the key and value types of a map.
    public var arguments: [OCLTypeReference]

    /// The parts of a tuple type.
    public var parts: [Part]

    /// The multiplicity written after the type, if any.
    public var multiplicity: OCLMultiplicity?

    /// The source range of the reference.
    public var range: SourceRange?

    /// Creates a type reference.
    ///
    /// - Parameters:
    ///   - path: The segments of the qualified name of the type.
    ///   - arguments: The type arguments.
    ///   - parts: The parts of a tuple type.
    ///   - multiplicity: The multiplicity written after the type.
    ///   - range: The source range of the reference.
    public init(
        path: [String], arguments: [OCLTypeReference] = [], parts: [Part] = [],
        multiplicity: OCLMultiplicity? = nil, range: SourceRange? = nil
    ) {
        self.path = path
        self.arguments = arguments
        self.parts = parts
        self.multiplicity = multiplicity
        self.range = range
    }

    /// The last segment of the qualified name.
    public var name: String { path.last ?? "" }

    /// The type written in OCL, without its multiplicity.
    public var text: String {
        var result = path.joined(separator: OCLSyntax.pathSeparator)
        if !parts.isEmpty {
            result += "(" + parts.map { $0.name + " : " + $0.type.textWithMultiplicity }.joined(separator: ", ") + ")"
        } else if !arguments.isEmpty {
            result += "(" + arguments.map(\.textWithMultiplicity).joined(separator: ", ") + ")"
        }
        return result
    }

    /// The type written in OCL, followed by its multiplicity if it has one.
    public var textWithMultiplicity: String { text + (multiplicity?.text ?? "") }
}

/// A variable declared by a let expression, an iteration or a tuple literal.
public struct OCLVariableDeclaration: Sendable, Hashable {
    /// The name of the variable.
    public var name: String

    /// The declared type of the variable, if any.
    public var type: OCLTypeReference?

    /// The expression that gives the variable its value, if any.
    public var initialiser: OCLExpression?

    /// The source range of the declaration.
    public var range: SourceRange?

    /// Creates a variable declaration.
    ///
    /// - Parameters:
    ///   - name: The name of the variable.
    ///   - type: The declared type of the variable.
    ///   - initialiser: The expression that gives the variable its value.
    ///   - range: The source range of the declaration.
    public init(name: String, type: OCLTypeReference? = nil, initialiser: OCLExpression? = nil, range: SourceRange? = nil) {
        self.name = name
        self.type = type
        self.initialiser = initialiser
        self.range = range
    }
}

/// The parenthesised arguments of an operation call or iteration.
///
/// For an iteration such as `books->forAll(b1, b2 | b1 <> b2)` the iterators are `b1` and
/// `b2` and the only argument is the body; for `iterate(x; sum : Integer = 0 | sum + x)` the
/// accumulator is `sum`. An operation call such as `max(3)` has arguments only.
public struct OCLArguments: Sendable, Hashable {
    /// The iterator variables declared before `|`.
    public var iterators: [OCLVariableDeclaration]

    /// The accumulator variables declared after `;`.
    public var accumulators: [OCLVariableDeclaration]

    /// The arguments, or the body of an iteration.
    public var arguments: [OCLExpression]

    /// Whether the arguments end with a body after `|`.
    public var hasBody: Bool

    /// Creates the arguments of a call.
    ///
    /// - Parameters:
    ///   - iterators: The iterator variables.
    ///   - accumulators: The accumulator variables.
    ///   - arguments: The arguments, or the body of an iteration.
    ///   - hasBody: Whether the arguments end with a body after `|`.
    public init(
        iterators: [OCLVariableDeclaration] = [], accumulators: [OCLVariableDeclaration] = [],
        arguments: [OCLExpression] = [], hasBody: Bool = false
    ) {
        self.iterators = iterators
        self.accumulators = accumulators
        self.arguments = arguments
        self.hasBody = hasBody
    }
}

/// A navigation or operation call, with or without a source.
///
/// `name.size()` is a call of `size` on the source `name` with the `.` operator; `size()` alone
/// has no source; `name` alone is a ``OCLExpressionKind/name(_:isPre:)`` expression instead.
public struct OCLCall: Sendable, Hashable {
    /// The expression whose value is navigated, or `nil` for an implicit source.
    public var source: OCLExpression?

    /// The navigation operator (`.`, `->`, `?.` or `?->`), or `nil` without a source.
    public var navigation: String?

    /// The qualifying segments of the name, such as `["Kind"]` in `Kind::of()`.
    public var qualifier: [String]

    /// The name of the property or operation.
    public var name: String

    /// The parenthesised arguments, or `nil` for a property navigation.
    public var arguments: OCLArguments?

    /// Whether the call is followed by `@pre`.
    public var isPre: Bool

    /// Creates a call.
    ///
    /// - Parameters:
    ///   - source: The expression whose value is navigated.
    ///   - navigation: The navigation operator.
    ///   - qualifier: The qualifying segments of the name.
    ///   - name: The name of the property or operation.
    ///   - arguments: The parenthesised arguments.
    ///   - isPre: Whether the call is followed by `@pre`.
    public init(
        source: OCLExpression?, navigation: String?, qualifier: [String] = [], name: String,
        arguments: OCLArguments? = nil, isPre: Bool = false
    ) {
        self.source = source
        self.navigation = navigation
        self.qualifier = qualifier
        self.name = name
        self.arguments = arguments
        self.isPre = isPre
    }
}

/// A part of a collection literal: one element or a range of integers.
public enum OCLCollectionPart: Sendable, Hashable {
    /// A single element.
    case element(OCLExpression)

    /// The integers from the first expression to the last, as in `1..5`.
    case range(OCLExpression, OCLExpression)
}

/// A condition and the expression chosen when it holds, as in an `elseif` branch.
public struct OCLConditionalBranch: Sendable, Hashable {
    /// The condition of the branch.
    public var condition: OCLExpression

    /// The expression chosen when the condition holds.
    public var value: OCLExpression

    /// Creates a branch.
    ///
    /// - Parameters:
    ///   - condition: The condition of the branch.
    ///   - value: The expression chosen when the condition holds.
    public init(condition: OCLExpression, value: OCLExpression) {
        self.condition = condition
        self.value = value
    }
}

/// A key and value of a map literal.
public struct OCLMapPart: Sendable, Hashable {
    /// The key.
    public var key: OCLExpression

    /// The value.
    public var value: OCLExpression

    /// Creates a part of a map literal.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - value: The value.
    public init(key: OCLExpression, value: OCLExpression) {
        self.key = key
        self.value = value
    }
}

/// An Essential OCL expression with its source range.
///
/// The tree keeps every construct of the concrete syntax that Eclipse OCL reads, so that
/// tools can analyse, translate or report on an expression without re-reading its text.
public indirect enum OCLExpressionKind: Sendable, Hashable {
    /// A whole number, with its digits as written.
    case integerLiteral(String)

    /// A real number, as written.
    case realLiteral(String)

    /// A string, with its decoded value and its source text including quotes.
    case stringLiteral(value: String, source: String)

    /// `true` or `false`.
    case booleanLiteral(Bool)

    /// `null`.
    case nullLiteral

    /// `invalid`.
    case invalidLiteral

    /// The unlimited natural `*`.
    case unlimitedLiteral

    /// `self`.
    case selfReference

    /// A simple or qualified name such as `name`, `Kind::red` or `ecore::EString`.
    case name([String], isPre: Bool)

    /// A navigation or operation call.
    case call(OCLCall)

    /// A unary operation such as `not a` or `-x`.
    case prefix(operator: String, operand: OCLExpression)

    /// A binary operation such as `a and b` or `x + 1`.
    case infix(operator: String, left: OCLExpression, right: OCLExpression)

    /// `if c1 then v1 elseif c2 then v2 else v3 endif`.
    case conditional(branches: [OCLConditionalBranch], otherwise: OCLExpression)

    /// `let a = 1, b = 2 in body`.
    case letExpression(variables: [OCLVariableDeclaration], body: OCLExpression)

    /// A collection literal such as `Set{1, 2}` or `Sequence{1..5}`.
    case collectionLiteral(type: OCLTypeReference, parts: [OCLCollectionPart])

    /// A tuple literal such as `Tuple{a = 1, b : String = 'x'}`.
    case tupleLiteral([OCLVariableDeclaration])

    /// A map literal such as `Map{1 with 'one'}`.
    case mapLiteral(type: OCLTypeReference, parts: [OCLMapPart])

    /// A type used as a value, such as `Set(String)` or `Integer`.
    case typeLiteral(OCLTypeReference)

    /// An expression in parentheses.
    case parenthesised(OCLExpression)

    /// A name followed by square-bracketed terms, such as `a[1]`.
    case indexed(source: OCLExpression, terms: [OCLExpression])

    /// A name followed by a curly-bracketed list of property values, such as `Point{x = 1}`.
    case shadow(type: [String], parts: [OCLVariableDeclaration])

    /// A lambda literal, `Lambda{body}`.
    case lambda(OCLExpression)

    /// A Complete OCL message expression such as `target^signal(1)` or `target^^signal(?)`.
    case message(target: OCLExpression, operator: String, name: String, arguments: [OCLExpression])

    /// The `?` placeholder for an unspecified message argument.
    case unspecifiedValue
}

/// An Essential OCL expression and the source range it covers.
public struct OCLExpression: Sendable, Hashable {
    /// The construct and its parts.
    public var kind: OCLExpressionKind

    /// The source range of the expression.
    public var range: SourceRange

    /// Creates an expression.
    ///
    /// - Parameters:
    ///   - kind: The construct and its parts.
    ///   - range: The source range of the expression.
    public init(_ kind: OCLExpressionKind, range: SourceRange) {
        self.kind = kind
        self.range = range
    }
}
