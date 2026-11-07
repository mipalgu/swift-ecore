//
// SDF3Definition.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// How a sort is declared or used, as evidence of whether it is lexical or context-free.
struct SDF3SortEvidence: OptionSet, Hashable {
    /// The raw bits.
    let rawValue: Int

    /// Declared in `lexical sorts` or with the kernel suffix `-LEX`.
    static let lexicalDeclaration = SDF3SortEvidence(rawValue: 1 << 0)
    /// The left-hand side of a lexical production.
    static let lexicalProduction = SDF3SortEvidence(rawValue: 1 << 1)
    /// The target of a Stratego injection of a built-in type, such as `: string -> ID`.
    static let lexicalInjection = SDF3SortEvidence(rawValue: 1 << 2)
    /// Declared in `context-free sorts` or with the kernel suffix `-CF`.
    static let contextFreeDeclaration = SDF3SortEvidence(rawValue: 1 << 3)
    /// The left-hand side of a context-free production, or the result of a signature constructor.
    static let contextFreeProduction = SDF3SortEvidence(rawValue: 1 << 4)
    /// Declared in a plain `sorts` section of SDF3 or of a Stratego signature.
    static let plainDeclaration = SDF3SortEvidence(rawValue: 1 << 5)
    /// Used as an argument or injected into another sort.
    static let reference = SDF3SortEvidence(rawValue: 1 << 6)

    /// The evidence that a sort is lexical.
    static let lexical: SDF3SortEvidence = [.lexicalDeclaration, .lexicalProduction, .lexicalInjection]
    /// The evidence that a sort is context-free.
    static let contextFree: SDF3SortEvidence = [.contextFreeDeclaration, .contextFreeProduction]
    /// The evidence that a sort is defined in the source.
    static let definition: SDF3SortEvidence = [.lexical, .contextFree, .plainDeclaration]
}

/// The type of a constructor argument.
indirect enum SDF3Type: Hashable {
    /// A sort, by its name as written, without kernel suffix.
    case sort(String)
    /// A built-in Stratego type, such as `string`.
    case builtin(String)
    /// A Stratego type variable, such as `a` in `Some : a -> Option(a)`.
    case variable(String)
    /// A list of values, written `Exp*`, `{Exp ","}*` or `List(Exp)`, with its least length.
    case list(SDF3Type, atLeastOne: Bool)
    /// An optional value, written `Exp?` or `Option(Exp)`.
    case optional(SDF3Type)
    /// A type that has no feature representation, such as a tuple.
    case unsupported(String)

    /// The innermost element type.
    var element: SDF3Type {
        switch self {
        case .list(let inner, _), .optional(let inner): inner.element
        default: self
        }
    }

    /// The lower and upper bound of a feature of this type, where `-1` is unbounded.
    var bounds: (lower: Int, upper: Int) {
        switch self {
        case .list(let inner, let atLeastOne):
            (atLeastOne && inner.bounds.lower > 0 ? 1 : 0, -1)
        case .optional(let inner):
            (0, inner.bounds.upper)
        default:
            (1, 1)
        }
    }

    /// The name used to generate positional feature names, such as `Exp` for `{Exp ","}*`.
    var nameForGeneratedFeature: String {
        switch element {
        case .sort(let name), .builtin(let name), .variable(let name), .unsupported(let name): name
        default: "value"
        }
    }
}

/// An argument of a constructor.
struct SDF3Argument: Hashable {
    /// The type of the argument.
    var type: SDF3Type
    /// The SDF3 label of the argument, if any.
    var label: String?
    /// The source text of the argument.
    var range: SourceRange
}

/// A constructor, from a named SDF3 production or a Stratego signature entry.
struct SDF3Constructor: Hashable {
    /// The constructor name as written.
    var name: String
    /// The sort the constructor builds, as written without kernel suffix.
    var sort: String
    /// The arguments, in order.
    var arguments: [SDF3Argument]
    /// The source text of the constructor name.
    var nameRange: SourceRange
    /// The source text of the whole production or signature entry.
    var range: SourceRange
}

/// An injection of one sort or type into a sort, which defines no constructor.
struct SDF3Injection: Hashable {
    /// The injected type.
    var source: SDF3Type
    /// The sort that receives the injection, as written without kernel suffix.
    var target: String
    /// The source text of the production or signature entry.
    var range: SourceRange
}

/// Everything the parser learnt from one SDF3 or Stratego module.
struct SDF3Definition {
    /// The module name as written, such as `syntax/Expressions`.
    var moduleName: String?
    /// The imported module names.
    var imports: [String] = []
    /// The sorts in order of first appearance, by name without kernel suffix.
    var sortOrder: [String] = []
    /// The evidence collected for every sort.
    var evidence: [String: SDF3SortEvidence] = [:]
    /// The source text where each sort first appears.
    var sortRanges: [String: SourceRange] = [:]
    /// The constructors, in source order.
    var constructors: [SDF3Constructor] = []
    /// The injections, in source order.
    var injections: [SDF3Injection] = []
    /// The declared start symbols.
    var startSymbols: [String] = []

    /// Records evidence about a sort.
    ///
    /// Kernel suffixes are removed and turned into evidence of their own, and
    /// the layout sort is ignored.
    ///
    /// - Parameters:
    ///   - written: The sort name as written.
    ///   - evidence: What the occurrence says about the sort.
    ///   - range: The source text of the occurrence.
    /// - Returns: The sort name without kernel suffix.
    @discardableResult
    mutating func note(_ written: String, _ evidence: SDF3SortEvidence, at range: SourceRange) -> String {
        var name = written
        var evidence = evidence
        if name.hasSuffix(SDF3Language.contextFreeSuffix) {
            name.removeLast(SDF3Language.contextFreeSuffix.count)
            if evidence.contains(.plainDeclaration) { evidence = .contextFreeDeclaration }
        } else if name.hasSuffix(SDF3Language.lexicalSuffix) {
            name.removeLast(SDF3Language.lexicalSuffix.count)
            evidence = evidence.contains(.reference) ? evidence : .lexicalDeclaration
        }
        guard name != SDF3Language.layoutSort else { return name }
        if self.evidence[name] == nil {
            sortOrder.append(name)
            sortRanges[name] = range
        }
        self.evidence[name, default: []].formUnion(evidence)
        return name
    }

    /// The name of a sort without kernel suffix.
    ///
    /// - Parameter written: The sort name as written.
    /// - Returns: The name without `-CF` or `-LEX`.
    static func baseName(_ written: String) -> String {
        for suffix in [SDF3Language.contextFreeSuffix, SDF3Language.lexicalSuffix] where written.hasSuffix(suffix) {
            return String(written.dropLast(suffix.count))
        }
        return written
    }
}
