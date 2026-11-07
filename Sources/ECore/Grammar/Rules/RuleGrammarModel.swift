//
// RuleGrammarModel.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// How often a grammar element may occur.
enum RuleCardinality: Sendable, Hashable {
    /// Exactly once (no operator).
    case one
    /// At most once (`?`).
    case optional
    /// Any number of times (`*`).
    case zeroOrMore
    /// At least once (`+`).
    case oneOrMore

    /// Whether the element may be absent (`?` or `*`).
    var isOptional: Bool { self == .optional || self == .zeroOrMore }

    /// Whether the element may repeat (`*` or `+`).
    var isMultiple: Bool { self == .zeroOrMore || self == .oneOrMore }

    /// The cardinality written as an operator.
    ///
    /// - Parameter text: The operator, `?`, `*` or `+`.
    /// - Returns: The cardinality, or `nil` for any other text.
    init?(operator text: String) {
        switch text {
        case "?": self = .optional
        case "*": self = .zeroOrMore
        case "+": self = .oneOrMore
        default: return nil
        }
    }
}

/// A reference to a type, written as `Name` or `alias::Name`.
struct RuleTypeReference: Sendable, Hashable {
    /// The alias of the package that holds the type, if written.
    var alias: String?

    /// The name of the type.
    var name: String

    /// Whether the reference was written with Langium's `infer` or `infers`.
    var isInferred: Bool

    /// Whether the reference was not written but derived from a rule name.
    var isImplicit: Bool

    /// The text of the reference, for diagnostics.
    var range: SourceRange?

    /// Creates a type reference.
    ///
    /// - Parameters:
    ///   - alias: The alias of the package that holds the type.
    ///   - name: The name of the type.
    ///   - isInferred: Whether the reference was written with `infer` or `infers`.
    ///   - isImplicit: Whether the reference was derived from a rule name.
    ///   - range: The text of the reference.
    init(
        alias: String? = nil, name: String, isInferred: Bool = false, isImplicit: Bool = false,
        range: SourceRange? = nil
    ) {
        self.alias = alias
        self.name = name
        self.isInferred = isInferred
        self.isImplicit = isImplicit
        self.range = range
    }

    /// The reference as written, such as `ecore::EString`.
    var displayName: String { alias.map { "\($0)::\(name)" } ?? name }
}

/// The operator of an assignment or assigned action.
enum RuleAssignmentOperator: String, Sendable, Hashable {
    /// `=`: assigns a single value.
    case assign = "="
    /// `+=`: adds a value to a list.
    case add = "+="
    /// `?=`: records whether the assigned element occurred.
    case flag = "?="
}

/// The kind and content of a grammar element.
indirect enum RuleElementKind: Sendable, Hashable {
    /// A keyword, such as `'entity'`.
    case keyword(String)
    /// A call of another rule by name.
    case ruleCall(String)
    /// An assignment of the value of `terminal` to a feature.
    case assignment(feature: String, operator: RuleAssignmentOperator, terminal: RuleElement)
    /// A cross-reference `[Type|TERMINAL]`; `isMulti` marks Langium's `[+Type]`.
    case crossReference(type: RuleTypeReference, terminal: String?, isMulti: Bool)
    /// An action `{Type}` or an assigned action `{Type.feature=current}`.
    case action(type: RuleTypeReference, feature: String?, operator: RuleAssignmentOperator?)
    /// A sequence of elements.
    case group([RuleElement])
    /// A choice between elements.
    case alternatives([RuleElement])
    /// Elements that may occur in any order, separated by `&`.
    case unorderedGroup([RuleElement])
    /// An element without significance for the metamodel, such as a wildcard or `EOF`.
    case other
}

/// An element of a rule body.
struct RuleElement: Sendable, Hashable {
    /// The kind and content of the element.
    var kind: RuleElementKind

    /// How often the element may occur.
    var cardinality: RuleCardinality

    /// The text of the element.
    var range: SourceRange?

    /// Creates an element.
    ///
    /// - Parameters:
    ///   - kind: The kind and content.
    ///   - cardinality: How often the element may occur; defaults to once.
    ///   - range: The text of the element.
    init(_ kind: RuleElementKind, cardinality: RuleCardinality = .one, range: SourceRange? = nil) {
        self.kind = kind
        self.cardinality = cardinality
        self.range = range
    }

    /// The elements this element directly contains, if it is compound.
    var children: [RuleElement] {
        switch kind {
        case .group(let elements), .alternatives(let elements), .unorderedGroup(let elements): elements
        case .assignment(_, _, let terminal): [terminal]
        default: []
        }
    }

    /// Whether the element or anything it contains satisfies a condition.
    ///
    /// - Parameter predicate: The condition.
    /// - Returns: `true` if any element of the tree satisfies it.
    func contains(where predicate: (RuleElement) -> Bool) -> Bool {
        predicate(self) || children.contains { $0.contains(where: predicate) }
    }
}

/// The kind of a grammar rule.
enum GrammarRuleKind: Sendable, Hashable {
    /// A parser rule, which yields objects or, without assignments and actions, values.
    case parser
    /// A terminal (lexer) rule, which yields values.
    case terminal
    /// An enum rule, which yields enumeration literals.
    case enumeration
    /// A Langium infix rule, which yields binary expressions.
    case infix
}

/// A literal of an enum rule.
struct RuleEnumLiteral: Sendable, Hashable {
    /// The name of the literal.
    var name: String

    /// The keyword that spells the literal, if given.
    var keyword: String?

    /// The text of the literal.
    var range: SourceRange?

    /// Creates an enum rule literal.
    ///
    /// - Parameters:
    ///   - name: The name of the literal.
    ///   - keyword: The keyword that spells the literal.
    ///   - range: The text of the literal.
    init(name: String, keyword: String? = nil, range: SourceRange? = nil) {
        self.name = name
        self.keyword = keyword
        self.range = range
    }
}

/// A rule of an Xtext or Langium grammar.
struct GrammarRule: Sendable, Hashable {
    /// The kind of rule.
    var kind: GrammarRuleKind

    /// The name of the rule.
    var name: String

    /// The declared return type (`returns` or `infers`), if any.
    var returnType: RuleTypeReference?

    /// Whether the rule is a parser fragment or terminal fragment.
    var isFragment: Bool

    /// Whether the rule is an Xtext wildcard fragment (`fragment F*`), whose body is inlined.
    var isWildcardFragment: Bool

    /// The body of a parser rule.
    var body: RuleElement?

    /// The literals of an enum rule.
    var literals: [RuleEnumLiteral]

    /// The operand rule of an infix rule.
    var infixOperand: String?

    /// The operator keywords of an infix rule.
    var infixOperators: [String]

    /// Whether the rule was predefined rather than written in the grammar.
    var isInherited: Bool

    /// The text of the rule's name.
    var nameRange: SourceRange?

    /// The text of the whole rule.
    var range: SourceRange?

    /// Creates a rule.
    ///
    /// - Parameters:
    ///   - kind: The kind of rule.
    ///   - name: The name of the rule.
    ///   - returnType: The declared return type.
    ///   - isFragment: Whether the rule is a fragment.
    ///   - isWildcardFragment: Whether the rule is an Xtext wildcard fragment.
    ///   - body: The body of a parser rule.
    ///   - literals: The literals of an enum rule.
    ///   - infixOperand: The operand rule of an infix rule.
    ///   - infixOperators: The operator keywords of an infix rule.
    ///   - isInherited: Whether the rule was predefined.
    ///   - nameRange: The text of the rule's name.
    ///   - range: The text of the whole rule.
    init(
        kind: GrammarRuleKind, name: String, returnType: RuleTypeReference? = nil, isFragment: Bool = false,
        isWildcardFragment: Bool = false, body: RuleElement? = nil, literals: [RuleEnumLiteral] = [],
        infixOperand: String? = nil, infixOperators: [String] = [], isInherited: Bool = false,
        nameRange: SourceRange? = nil, range: SourceRange? = nil
    ) {
        self.kind = kind
        self.name = name
        self.returnType = returnType
        self.isFragment = isFragment
        self.isWildcardFragment = isWildcardFragment
        self.body = body
        self.literals = literals
        self.infixOperand = infixOperand
        self.infixOperators = infixOperators
        self.isInherited = isInherited
        self.nameRange = nameRange
        self.range = range
    }

    /// The reference to the rule's type: its declared return type, or its name.
    var typeReference: RuleTypeReference {
        returnType ?? RuleTypeReference(name: name, isImplicit: true, range: nameRange)
    }
}
