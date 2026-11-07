//
// MetaDepthReader.swift
// MultiLevel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// What ``MetaDepthReader`` has read from a text.
public struct MetaDepthReadResult: Sendable {
    /// The deep model, or `nil` if the text holds no model.
    public var model: DeepModel?

    /// The problems found while reading, with their positions in the text.
    public var diagnostics: [SourceDiagnostic]

    /// Whether any diagnostic is an error.
    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}

/// Reads multi-level models written in the MetaDepth notation.
///
/// The supported notation covers a top model (`Model Store@2 { ... }`), instance models
/// (`Store MyStore { ... }`), node and edge clabjects with ontological or linguistic types
/// (`ProductType Book { ... }`, `Node Author { ... }`, `Edge Writes(Author.books, Book.authors) { ... }`),
/// `abstract` clabjects and supertypes (`: Super`), clabject potency (`@2`) and leap potency
/// (`@(2)`), features with potency, multiplicity, defaults and modifiers
/// (`vat@1 : double = 7.5;`, `authors : Author[*] {ordered};`, `nextCell : Cell[*] {next};`),
/// deep references (`elements : ElementKind@0[*];`), derived features
/// (`/total : double = $self.price * 2$;`), slots (`price = 35;`, `next = [c1, c2];`) and
/// constraints with potency (`posPrice@2 : $self.price > 0$`), whose bodies are AQL.
///
/// Two extensions select the further decisions of this implementation: a top model followed
/// by `melanee` uses Melanee potency, where `*` is an unbounded potency and a feature may give
/// its mutability after its durability (`price@2/1 : double;`); and the modifier `{level=1}`
/// declares a level-crossing reference whose targets reside at level 1.
///
/// Embedded-language blocks (`# EOL ... #`) and model imports are reported as unsupported.
public enum MetaDepthReader {
    /// Reads a deep model from MetaDepth text.
    ///
    /// - Parameters:
    ///   - text: The text.
    ///   - sourceName: The name of the document, recorded in the diagnostics (default none).
    ///   - schemes: The potency schemes that a model may select (default the built-in ones).
    /// - Returns: The model and the problems found.
    public static func parse(
        _ text: String, sourceName: String? = nil, schemes: [any PotencyScheme] = PotencySchemes.builtIn
    ) -> MetaDepthReadResult {
        let (tokens, lexical) = MetaDepthLexer.tokenise(text)
        var parser = MetaDepthParser(tokens: tokens)
        let parsed = parser.parseDocument()
        var resolver = MetaDepthResolver(models: parsed, schemes: schemes)
        let model = resolver.resolve()
        var diagnostics = lexical + parser.diagnostics + resolver.diagnostics
        if let sourceName {
            for index in diagnostics.indices { diagnostics[index].document = sourceName }
        }
        return MetaDepthReadResult(model: model, diagnostics: diagnostics)
    }

    /// Whether a text starts like a MetaDepth document: optional modifiers, then `Model`, a
    /// name and a potency.
    ///
    /// - Parameter text: The start of a document.
    /// - Returns: `true` if the text starts like a MetaDepth model.
    public static func looksLikeMetaDepth(_ text: String) -> Bool {
        let (tokens, _) = MetaDepthLexer.tokenise(String(text.prefix(4096)))
        var position = 0
        while position < tokens.count,
            tokens[position].isWord(MultiLevelSyntax.extensibleKeyword) || tokens[position].isWord(MultiLevelSyntax.strictKeyword)
        {
            position += 1
        }
        guard position + 3 < tokens.count else { return false }
        return tokens[position].isWord(MultiLevelSyntax.modelKeyword) && tokens[position + 1].kind == .identifier
            && tokens[position + 2].isSymbol(String(MultiLevelSyntax.potencyMarker))
    }
}

// MARK: - Syntax Tree

/// A value as written in the text.
enum ParsedValue {
    /// A literal value.
    case value(DeepValue)
    /// A name that is resolved to a clabject, or else read as a literal, together with where it was written.
    case name(String, SourceRange)
}

/// A potency as written: its value and whether it is a leap.
struct ParsedPotency {
    /// The potency value.
    var potency: Potency
    /// Whether the potency was written as a leap potency.
    var isLeap = false
    /// The mutability that follows the potency, if one was written.
    var mutability: Potency?
}

/// A feature as written.
struct ParsedFeature {
    /// The name of the feature.
    var name: String
    /// The source range of the name.
    var range: SourceRange
    /// Whether the feature is derived.
    var isDerived = false
    /// The potency of the feature, if one was written.
    var potency: ParsedPotency?
    /// The name of the feature's type.
    var typeName = ""
    /// The source range of the type name.
    var typeRange: SourceRange
    /// The potency written after the type name, if any.
    var targetPotency: Potency?
    /// The lower bound of the multiplicity.
    var lowerBound = 0
    /// The upper bound of the multiplicity, or `-1` if it is unbounded.
    var upperBound = 1
    /// The default values.
    var defaults: [ParsedValue] = []
    /// The derivation expression, if any.
    var derivation: String?
    /// Whether the values of the feature are ordered.
    var isOrdered = true
    /// Whether the values of the feature are unique.
    var isUnique = true
    /// Whether the feature is a containment.
    var isContainment = false
    /// The level of the target, if one was written.
    var targetLevel: Int?
    /// The name of the instantiated feature, if one was written, with its source range.
    var ontologicalTypeName: (String, SourceRange)?
}

/// A slot as written.
struct ParsedSlot {
    /// The name of the feature that the slot fills.
    var feature: String
    /// The source range of the feature name.
    var range: SourceRange
    /// The values of the slot.
    var values: [ParsedValue]
}

/// An edge end as written.
struct ParsedEnd {
    /// The name of the clabject at the end.
    var clabject: String
    /// The name of the reference on that clabject, if one was written.
    var feature: String?
    /// The source range of the end.
    var range: SourceRange
}

/// A clabject as written.
struct ParsedClabject {
    /// The name of the clabject's type.
    var typeName: String
    /// The source range of the type name.
    var typeRange: SourceRange
    /// The name of the clabject.
    var name: String
    /// The source range of the clabject name.
    var range: SourceRange
    /// The potency of the clabject, if one was written.
    var potency: ParsedPotency?
    /// Whether the clabject is abstract.
    var isAbstract = false
    /// The names of the supertypes, with their source ranges.
    var supertypes: [(String, SourceRange)] = []
    /// The source and target ends, if the clabject is an edge.
    var ends: (ParsedEnd, ParsedEnd)?
    /// The features declared in the clabject.
    var features: [ParsedFeature] = []
    /// The slots declared in the clabject.
    var slots: [ParsedSlot] = []
    /// The constraints declared in the clabject.
    var constraints: [DeepConstraint] = []
    /// The source ranges of the constraint names, in the order of `constraints`.
    var constraintRanges: [SourceRange] = []
}

/// A model as written.
struct ParsedModel {
    /// The name of the model.
    var name: String
    /// The source range of the model name.
    var range: SourceRange
    /// The name of the model that this model instantiates, or `nil` for a top model.
    var typeModel: String?
    /// The potency of the model, if one was written.
    var potency: Potency?
    /// The name of the potency variant, if one was written, with its source range.
    var variant: (String, SourceRange)?
    /// Whether the model may contain linguistic extensions.
    var isExtensible = true
    /// The clabjects declared in the model.
    var clabjects: [ParsedClabject] = []
    /// The constraints declared in the model.
    var constraints: [DeepConstraint] = []
    /// The source ranges of the constraint names, in the order of `constraints`.
    var constraintRanges: [SourceRange] = []
}

// MARK: - Parser

/// Parses tokens into the syntax tree of a document.
struct MetaDepthParser {
    /// The tokens to parse, ending with an end token.
    private let tokens: [MetaDepthToken]
    /// The index in `tokens` of the current token.
    private var position = 0
    /// The syntax problems found so far.
    private(set) var diagnostics: [SourceDiagnostic] = []

    /// Creates a parser.
    ///
    /// - Parameter tokens: The tokens to parse, ending with an end token.
    init(tokens: [MetaDepthToken]) {
        self.tokens = tokens
    }

    /// The token at the current position, or the last token if the position is past the end.
    private var current: MetaDepthToken { tokens[min(position, tokens.count - 1)] }
    /// The token at a distance from the current position.
    ///
    /// - Parameter distance: The number of tokens ahead of the current one.
    /// - Returns: The token, or the last token if the distance reaches past the end.
    private func lookahead(_ distance: Int) -> MetaDepthToken { tokens[min(position + distance, tokens.count - 1)] }
    /// Whether the current token is the end token.
    private var atEnd: Bool { current.kind == .end }

    /// Moves to the next token, unless at the end.
    private mutating func advance() { if !atEnd { position += 1 } }

    /// Records a syntax problem.
    ///
    /// - Parameters:
    ///   - message: A description of the problem.
    ///   - range: The source range of the problem.
    ///   - code: The diagnostic code, defaulting to the syntax code.
    private mutating func error(_ message: String, at range: SourceRange, code: String = MultiLevelDiagnosticCode.syntax) {
        diagnostics.append(SourceDiagnostic(severity: .error, code: code, message: message, range: range))
    }

    /// Moves past the current token if it is the given symbol.
    ///
    /// - Parameter symbol: The symbol to accept.
    /// - Returns: `true` if the token was the symbol and was consumed.
    @discardableResult
    private mutating func accept(_ symbol: String) -> Bool {
        guard current.isSymbol(symbol) else { return false }
        advance()
        return true
    }

    /// Moves past the given symbol, reporting a syntax problem if the current token is something else.
    ///
    /// - Parameter symbol: The symbol that is required.
    private mutating func expect(_ symbol: String) {
        if !accept(symbol) { error("expected '\(symbol)' but found '\(current.value)'", at: current.range) }
    }

    /// Reads an identifier, reporting a syntax problem if the current token is something else.
    ///
    /// - Parameter what: A description of the expected identifier, used in the diagnostic.
    /// - Returns: The identifier and its source range, or `nil` if the current token is not an identifier.
    private mutating func expectIdentifier(_ what: String) -> (String, SourceRange)? {
        guard current.kind == .identifier else {
            error("expected \(what) but found '\(current.value)'", at: current.range)
            return nil
        }
        defer { advance() }
        return (current.value, current.range)
    }

    /// Reports an embedded-language block as unsupported and moves past it.
    private mutating func rejectEmbeddedBlock() {
        error(
            "embedded \(current.value.isEmpty ? "language" : current.value) blocks are not supported; constraints are written in AQL",
            at: current.range, code: MultiLevelDiagnosticCode.unsupported)
        advance()
    }

    /// Parses every model of the document.
    mutating func parseDocument() -> [ParsedModel] {
        var models: [ParsedModel] = []
        while !atEnd {
            if current.kind == .embeddedBlock {
                rejectEmbeddedBlock()
                continue
            }
            let start = position
            if let model = parseModel() { models.append(model) }
            if position == start { advance() }
        }
        return models
    }

    /// Parses a model header, its optional import list and its body.
    ///
    /// - Returns: The parsed model, or `nil` if the header is malformed.
    private mutating func parseModel() -> ParsedModel? {
        var isExtensible = true
        while current.isWord(MultiLevelSyntax.extensibleKeyword) || current.isWord(MultiLevelSyntax.strictKeyword) {
            isExtensible = current.isWord(MultiLevelSyntax.extensibleKeyword)
            advance()
        }
        var model: ParsedModel
        if current.isWord(MultiLevelSyntax.modelKeyword) {
            advance()
            guard let (name, range) = expectIdentifier("a model name") else { return nil }
            model = ParsedModel(name: name, range: range)
            guard accept(String(MultiLevelSyntax.potencyMarker)) else {
                error("the top model '\(name)' needs a potency, as in '\(name)@2'", at: range, code: MultiLevelDiagnosticCode.potency)
                return nil
            }
            model.potency = parsePotency()?.potency
            if current.kind == .identifier, !current.isWord(MultiLevelSyntax.importsKeyword) {
                model.variant = (current.value, current.range)
                advance()
            }
        } else {
            guard let (typeModel, _) = expectIdentifier("a model") else { return nil }
            guard let (name, range) = expectIdentifier("a model name") else { return nil }
            model = ParsedModel(name: name, range: range, typeModel: typeModel)
            if accept(String(MultiLevelSyntax.potencyMarker)) { model.potency = parsePotency()?.potency }
        }
        model.isExtensible = isExtensible
        if current.isWord(MultiLevelSyntax.importsKeyword) {
            error("model imports are not supported yet", at: current.range, code: MultiLevelDiagnosticCode.unsupported)
            advance()
            while current.kind == .identifier {
                advance()
                if !accept(",") { break }
            }
        }
        expect("{")
        while !atEnd, !current.isSymbol("}") {
            let start = position
            parseModelMember(into: &model)
            if position == start {
                error("unexpected '\(current.value)'", at: current.range)
                advance()
            }
        }
        expect("}")
        return model
    }

    /// Parses a clabject or model potency: either a leap potency in parentheses, or a value with an optional mutability.
    ///
    /// - Returns: The parsed potency, or `nil` if it is malformed.
    private mutating func parsePotency() -> ParsedPotency? {
        if accept("(") {
            guard current.kind == .integer, let value = Int(current.value) else {
                error("expected a leap potency", at: current.range, code: MultiLevelDiagnosticCode.potency)
                return nil
            }
            advance()
            expect(")")
            return ParsedPotency(potency: Potency(value), isLeap: true)
        }
        guard let potency = parsePotencyValue() else { return nil }
        var parsed = ParsedPotency(potency: potency)
        if current.isSymbol(String(MultiLevelSyntax.mutabilitySeparator)),
            lookahead(1).kind == .integer || lookahead(1).isSymbol(MultiLevelSyntax.unboundedPotency)
        {
            advance()
            parsed.mutability = parsePotencyValue()
        }
        return parsed
    }

    /// Parses a single potency value: a non-negative integer or the unbounded marker.
    ///
    /// - Returns: The potency, or `nil` if the current token is neither.
    private mutating func parsePotencyValue() -> Potency? {
        if accept(MultiLevelSyntax.unboundedPotency) { return .unbounded }
        guard current.kind == .integer, let value = Int(current.value) else {
            error("expected a potency but found '\(current.value)'", at: current.range, code: MultiLevelDiagnosticCode.potency)
            return nil
        }
        advance()
        return Potency(value)
    }

    /// Parses one member of a model body: a clabject or a constraint.
    ///
    /// - Parameter model: The model to add the member to.
    private mutating func parseModelMember(into model: inout ParsedModel) {
        if current.kind == .embeddedBlock {
            rejectEmbeddedBlock()
            return
        }
        var isAbstract = false
        while current.isWord(MultiLevelSyntax.abstractKeyword) || current.isWord(MultiLevelSyntax.extensibleKeyword)
            || current.isWord(MultiLevelSyntax.strictKeyword)
        {
            if current.isWord(MultiLevelSyntax.abstractKeyword) { isAbstract = true }
            advance()
        }
        guard current.kind == .identifier else { return }
        if lookahead(1).kind == .identifier {
            if var clabject = parseClabject() {
                clabject.isAbstract = isAbstract
                model.clabjects.append(clabject)
            }
        } else if let (constraint, range) = parseConstraintOrNil() {
            model.constraints.append(constraint)
            model.constraintRanges.append(range)
        }
    }

    /// Parses a constraint declaration in a model body.
    ///
    /// - Returns: The constraint and the source range of its name, or `nil` if it is malformed.
    private mutating func parseConstraintOrNil() -> (DeepConstraint, SourceRange)? {
        guard let (name, range) = expectIdentifier("a constraint name") else { return nil }
        var potency: Potency?
        if accept(String(MultiLevelSyntax.potencyMarker)) { potency = parsePotency()?.potency }
        expect(":")
        guard current.kind == .expression else {
            error("expected a constraint body between '$' delimiters", at: current.range)
            return nil
        }
        let body = current.value
        advance()
        accept(";")
        return (DeepConstraint(name: name, potency: potency, body: body), range)
    }

    /// Parses a clabject declaration, with its potency, edge ends, supertypes and body.
    ///
    /// - Returns: The parsed clabject, or `nil` if its header is malformed.
    private mutating func parseClabject() -> ParsedClabject? {
        guard let (typeName, typeRange) = expectIdentifier("a type"),
            let (name, range) = expectIdentifier("a clabject name")
        else { return nil }
        var clabject = ParsedClabject(typeName: typeName, typeRange: typeRange, name: name, range: range)
        if accept(String(MultiLevelSyntax.potencyMarker)) { clabject.potency = parsePotency() }
        if accept("(") {
            if let source = parseEnd() {
                expect(",")
                if let target = parseEnd() { clabject.ends = (source, target) }
            }
            expect(")")
        }
        if accept(":") {
            repeat {
                if let supertype = expectIdentifier("a supertype") { clabject.supertypes.append(supertype) }
            } while accept(",")
        }
        expect("{")
        while !atEnd, !current.isSymbol("}") {
            let start = position
            parseClabjectMember(into: &clabject)
            if position == start {
                error("unexpected '\(current.value)'", at: current.range)
                advance()
            }
        }
        expect("}")
        return clabject
    }

    /// Parses one end of an edge: a clabject name with an optional reference.
    ///
    /// - Returns: The parsed end, or `nil` if no name is present.
    private mutating func parseEnd() -> ParsedEnd? {
        guard let (name, range) = expectIdentifier("an edge end") else { return nil }
        var end = ParsedEnd(clabject: name, range: range)
        if accept(String(MultiLevelSyntax.memberSeparator)) { end.feature = expectIdentifier("a reference")?.0 }
        return end
    }

    /// Parses one member of a clabject body: a feature, a slot or a constraint.
    ///
    /// - Parameter clabject: The clabject to add the member to.
    private mutating func parseClabjectMember(into clabject: inout ParsedClabject) {
        if current.kind == .embeddedBlock {
            rejectEmbeddedBlock()
            return
        }
        let isDerived = accept(String(MultiLevelSyntax.derivedMarker))
        guard let (name, range) = expectIdentifier("a feature, slot or constraint") else { return }
        var potency: ParsedPotency?
        if accept(String(MultiLevelSyntax.potencyMarker)) { potency = parsePotency() }
        if potency?.isLeap == true {
            error("leap potency applies to clabjects only", at: range, code: MultiLevelDiagnosticCode.potency)
        }
        if accept(":") {
            if current.kind == .expression {
                if isDerived { error("a derived feature needs a type", at: range) }
                clabject.constraints.append(DeepConstraint(name: name, potency: potency?.potency, body: current.value))
                clabject.constraintRanges.append(range)
                advance()
                accept(";")
                return
            }
            var feature = ParsedFeature(name: name, range: range, isDerived: isDerived, potency: potency, typeRange: current.range)
            parseFeatureType(into: &feature)
            clabject.features.append(feature)
        } else if accept("=") {
            if isDerived { error("a slot cannot be derived", at: range) }
            if potency != nil { error("a slot has no potency", at: range, code: MultiLevelDiagnosticCode.potency) }
            clabject.slots.append(ParsedSlot(feature: name, range: range, values: parseValues()))
            accept(";")
        } else {
            error("expected ':' or '=' after '\(name)'", at: current.range)
        }
    }

    /// Parses the type of a feature, with its multiplicity, defaults, derivation and modifiers.
    ///
    /// - Parameter feature: The feature to fill in.
    private mutating func parseFeatureType(into feature: inout ParsedFeature) {
        guard let (typeName, typeRange) = expectIdentifier("a type") else { return }
        feature.typeName = typeName
        feature.typeRange = typeRange
        if accept(String(MultiLevelSyntax.potencyMarker)) { feature.targetPotency = parsePotencyValue() }
        if accept("[") {
            let lower = parseBound()
            var upper = lower
            if accept(MultiLevelSyntax.rangeSeparator) { upper = parseBound() }
            if lower < 0 {
                feature.lowerBound = 0
                feature.upperBound = -1
            } else {
                feature.lowerBound = lower
                feature.upperBound = upper
            }
            expect("]")
        }
        while true {
            if accept("=") {
                if current.kind == .expression {
                    feature.derivation = current.value
                    advance()
                } else {
                    feature.defaults = parseValues()
                }
            } else if accept("{") {
                parseModifiers(into: &feature)
                expect("}")
            } else {
                break
            }
        }
        accept(";")
    }

    /// Parses a multiplicity bound: a non-negative integer or the unbounded marker.
    ///
    /// - Returns: The bound, `-1` if it is unbounded, or `0` if it is malformed.
    private mutating func parseBound() -> Int {
        if accept(MultiLevelSyntax.unboundedPotency) { return -1 }
        guard current.kind == .integer, let value = Int(current.value) else {
            error("expected a bound but found '\(current.value)'", at: current.range)
            return 0
        }
        advance()
        return value
    }

    /// Parses a comma-separated list of feature modifiers.
    ///
    /// A word that is not a known modifier names the feature that this feature instantiates.
    ///
    /// - Parameter feature: The feature to apply the modifiers to.
    private mutating func parseModifiers(into feature: inout ParsedFeature) {
        repeat {
            guard let (word, range) = expectIdentifier("a modifier") else { return }
            switch word {
            case MultiLevelSyntax.orderedModifier: feature.isOrdered = true
            case MultiLevelSyntax.uniqueModifier: feature.isUnique = true
            case MultiLevelSyntax.containmentModifier: feature.isContainment = true
            case MultiLevelSyntax.levelModifier:
                expect(String(MultiLevelSyntax.modifierValueSeparator))
                if current.kind == .integer, let level = Int(current.value) {
                    feature.targetLevel = level
                    advance()
                } else {
                    error("expected a level", at: current.range)
                }
            default:
                if feature.ontologicalTypeName != nil {
                    error("a feature instantiates at most one feature", at: range)
                }
                feature.ontologicalTypeName = (word, range)
            }
        } while accept(",")
    }

    /// Parses a single value or a bracketed list of values.
    ///
    /// - Returns: The values that could be parsed.
    private mutating func parseValues() -> [ParsedValue] {
        if accept("[") {
            var values: [ParsedValue] = []
            while !atEnd, !current.isSymbol("]") {
                if let value = parseValue() { values.append(value) }
                if !accept(",") { break }
            }
            expect("]")
            return values
        }
        return parseValue().map { [$0] } ?? []
    }

    /// Parses a literal or a name, with an optional minus sign before a number.
    ///
    /// - Returns: The parsed value, or `nil` if the current token is not a value.
    private mutating func parseValue() -> ParsedValue? {
        let token = current
        switch token.kind {
        case .string:
            advance()
            return .value(.string(token.value))
        case .integer:
            advance()
            return Int(token.value).map { .value(.integer($0)) }
        case .real:
            advance()
            return Double(token.value).map { .value(.real($0)) }
        case .identifier where token.value == MultiLevelSyntax.trueLiteral:
            advance()
            return .value(.boolean(true))
        case .identifier where token.value == MultiLevelSyntax.falseLiteral:
            advance()
            return .value(.boolean(false))
        case .identifier:
            advance()
            return .name(token.value, token.range)
        case .symbol where token.value == "-":
            advance()
            let number = current
            advance()
            if number.kind == .integer, let value = Int(number.value) { return .value(.integer(-value)) }
            if number.kind == .real, let value = Double(number.value) { return .value(.real(-value)) }
            error("expected a number after '-'", at: number.range)
            return nil
        default:
            error("expected a value but found '\(token.value)'", at: token.range)
            advance()
            return nil
        }
    }
}

// MARK: - Resolver

/// Resolves the names of a parsed document into a deep model.
struct MetaDepthResolver {
    /// The parsed models, in document order.
    private let models: [ParsedModel]
    /// The potency schemes that can be selected by a model's variant.
    private let schemes: [any PotencyScheme]
    /// The resolution problems found so far.
    private(set) var diagnostics: [SourceDiagnostic] = []

    /// The parsed models in chain order, from the top down.
    private var chain: [ParsedModel] = []

    /// The identifiers of the clabjects of each level model, by name.
    private var names: [[String: EUUID]] = []

    /// Creates a resolver.
    ///
    /// - Parameters:
    ///   - models: The parsed models of a document.
    ///   - schemes: The potency schemes that a model's variant can select.
    init(models: [ParsedModel], schemes: [any PotencyScheme]) {
        self.models = models
        self.schemes = schemes
    }

    /// Records a resolution problem.
    ///
    /// - Parameters:
    ///   - message: A description of the problem.
    ///   - range: The source range of the problem, if known.
    ///   - code: The diagnostic code, defaulting to the unresolved-name code.
    ///   - severity: The severity, defaulting to an error.
    private mutating func error(
        _ message: String, at range: SourceRange?, code: String = MultiLevelDiagnosticCode.unresolvedName,
        severity: DiagnosticSeverity = .error
    ) {
        diagnostics.append(SourceDiagnostic(severity: severity, code: code, message: message, range: range))
    }

    /// Resolves the document into a deep model.
    mutating func resolve() -> DeepModel? {
        guard orderChain() else { return nil }
        let top = chain[0]
        var scheme: any PotencyScheme = MetaDepthPotencyScheme()
        if let (variant, range) = top.variant {
            if let selected = PotencySchemes.scheme(for: PotencyVariant(rawValue: variant), among: schemes) {
                scheme = selected
            } else {
                error("unknown potency variant '\(variant)'", at: range, code: MultiLevelDiagnosticCode.potency)
            }
        }
        assignIdentifiers()
        var model = DeepModel(potencyScheme: scheme)
        model.levels = chain.map {
            LevelModel(
                name: $0.name, potency: $0.potency, typeModel: $0.typeModel, isExtensible: $0.isExtensible,
                constraints: $0.constraints)
        }
        for (modelIndex, parsedModel) in chain.enumerated() {
            for (constraint, range) in zip(parsedModel.constraints, parsedModel.constraintRanges) {
                checkLanguage(of: constraint.body, at: range)
            }
            model.levels[modelIndex].clabjects = parsedModel.clabjects.compactMap {
                resolveHeader(of: $0, inModelAt: modelIndex)
            }
        }
        for (modelIndex, parsedModel) in chain.enumerated() {
            for parsed in parsedModel.clabjects {
                guard let id = names[modelIndex][parsed.name],
                    let position = model.levels[modelIndex].clabjects.firstIndex(where: { $0.id == id })
                else { continue }
                let index = DeepIndex(model)
                var clabject = model.levels[modelIndex].clabjects[position]
                clabject.features = parsed.features.map { resolveFeature($0, of: clabject, inModelAt: modelIndex, index: index) }
                model.levels[modelIndex].clabjects[position] = clabject
            }
        }
        let index = DeepIndex(model)
        for (modelIndex, parsedModel) in chain.enumerated() {
            for parsed in parsedModel.clabjects {
                guard let id = names[modelIndex][parsed.name],
                    let position = model.levels[modelIndex].clabjects.firstIndex(where: { $0.id == id })
                else { continue }
                model.levels[modelIndex].clabjects[position].slots = parsed.slots.map { slot in
                    let feature = index.visibleFeatures(of: id).first { $0.feature.name == slot.feature }
                    return DeepSlot(
                        feature: slot.feature,
                        values: slot.values.map {
                            resolveValue($0, expectingObject: feature?.feature.type.target != nil, inModelAt: modelIndex)
                        })
                }
            }
        }
        return model
    }

    /// Orders the parsed models into one instantiation chain.
    private mutating func orderChain() -> Bool {
        let tops = models.filter { $0.typeModel == nil }
        guard let top = tops.first else {
            if let first = models.first {
                error("no top model ('Model Name@n') is declared", at: first.range, code: MultiLevelDiagnosticCode.levelChain)
            }
            return false
        }
        for extra in tops.dropFirst() {
            error(
                "only one top model is supported; '\(extra.name)' is ignored", at: extra.range,
                code: MultiLevelDiagnosticCode.levelChain)
        }
        chain = [top]
        var seen: Set<String> = [top.name]
        while let last = chain.last {
            let instances = models.filter { $0.typeModel == last.name }
            guard let next = instances.first else { break }
            for extra in instances.dropFirst() {
                error(
                    "only one instance model per model is supported; '\(extra.name)' is ignored", at: extra.range,
                    code: MultiLevelDiagnosticCode.levelChain)
            }
            guard seen.insert(next.name).inserted else { break }
            chain.append(next)
        }
        for model in models where model.typeModel != nil && !seen.contains(model.name) {
            if let typeModel = model.typeModel, !models.contains(where: { $0.name == typeModel }) {
                error("unknown type model '\(typeModel)' of '\(model.name)'", at: model.range)
            }
        }
        return true
    }

    /// Gives every clabject its identifier and reports duplicate names.
    private mutating func assignIdentifiers() {
        let deepName = chain[0].name
        names = chain.map { _ in [:] }
        for (modelIndex, model) in chain.enumerated() {
            for clabject in model.clabjects {
                if names[modelIndex][clabject.name] != nil {
                    error(
                        "'\(clabject.name)' is declared twice in '\(model.name)'", at: clabject.range,
                        code: MultiLevelDiagnosticCode.duplicateName)
                    continue
                }
                names[modelIndex][clabject.name] = MultiLevelIdentifiers.clabjectIdentifier(
                    named: clabject.name, inLevelModel: model.name, of: deepName)
            }
        }
    }

    /// Looks up a clabject by name: in a model, then in the models above, then below.
    private func lookup(_ name: String, from modelIndex: Int) -> EUUID? {
        if let id = names[modelIndex][name] { return id }
        for index in stride(from: modelIndex - 1, through: 0, by: -1) {
            if let id = names[index][name] { return id }
        }
        for index in (modelIndex + 1)..<max(modelIndex + 1, names.count) {
            if let id = names[index][name] { return id }
        }
        return nil
    }

    /// Looks up a type in the models above a model.
    private func lookupAbove(_ name: String, from modelIndex: Int) -> EUUID? {
        for index in stride(from: modelIndex - 1, through: 0, by: -1) {
            if let id = names[index][name] { return id }
        }
        return nil
    }

    /// Resolves the type, supertypes and ends of a clabject.
    private mutating func resolveHeader(of parsed: ParsedClabject, inModelAt modelIndex: Int) -> Clabject? {
        guard let id = names[modelIndex][parsed.name] else { return nil }
        var type: EUUID?
        let isLinguistic = parsed.typeName == MultiLevelSyntax.nodeKeyword || parsed.typeName == MultiLevelSyntax.edgeKeyword
        if !isLinguistic {
            type = lookupAbove(parsed.typeName, from: modelIndex)
            if type == nil {
                error("unknown type '\(parsed.typeName)' of '\(parsed.name)'", at: parsed.typeRange)
            }
        }
        var supertypes: [EUUID] = []
        for (name, range) in parsed.supertypes {
            if let supertype = names[modelIndex][name] {
                supertypes.append(supertype)
            } else {
                error("unknown supertype '\(name)' of '\(parsed.name)'", at: range)
            }
        }
        var ends: EdgeEnds?
        if let (source, target) = parsed.ends {
            if let sourceID = lookup(source.clabject, from: modelIndex), let targetID = lookup(target.clabject, from: modelIndex) {
                ends = EdgeEnds(
                    source: EdgeEnd(clabject: sourceID, feature: source.feature),
                    target: EdgeEnd(clabject: targetID, feature: target.feature))
            } else {
                error("unknown end of edge '\(parsed.name)'", at: source.range)
            }
        } else if parsed.typeName == MultiLevelSyntax.edgeKeyword {
            error("edge '\(parsed.name)' needs two ends", at: parsed.range, code: MultiLevelDiagnosticCode.edge)
        }
        for (constraint, range) in zip(parsed.constraints, parsed.constraintRanges) {
            checkLanguage(of: constraint.body, at: range)
        }
        return Clabject(
            id: id, name: parsed.name, type: type, potency: parsed.potency?.potency,
            isLeap: parsed.potency?.isLeap ?? false, isAbstract: parsed.isAbstract, supertypes: supertypes, ends: ends,
            constraints: parsed.constraints)
    }

    /// Resolves a feature of a clabject whose header is resolved.
    private mutating func resolveFeature(
        _ parsed: ParsedFeature, of clabject: Clabject, inModelAt modelIndex: Int, index: DeepIndex
    ) -> DeepFeature {
        let type: DeepFeatureType
        if let target = lookup(parsed.typeName, from: modelIndex),
            MultiLevelSyntax.dataTypes[parsed.typeName] == nil || names[modelIndex][parsed.typeName] != nil
        {
            type = .reference(target)
        } else {
            if MultiLevelSyntax.dataTypes[parsed.typeName] == nil {
                error("unknown type '\(parsed.typeName)' of feature '\(parsed.name)'", at: parsed.typeRange)
            }
            type = .data(parsed.typeName)
        }
        var ontologicalType: FeatureReference?
        let typeFeatures = clabject.type.map { index.visibleFeatures(of: $0) } ?? []
        if let (name, range) = parsed.ontologicalTypeName {
            if let typeFeature = typeFeatures.first(where: { $0.feature.name == name }) {
                ontologicalType = typeFeature.reference
            } else {
                error("'\(name)' is not a feature of the type of '\(clabject.name)'", at: range)
            }
        } else if let refined = typeFeatures.first(where: { $0.feature.name == parsed.name && $0.role.isDefinition }) {
            ontologicalType = refined.reference
        }
        if let derivation = parsed.derivation { checkLanguage(of: derivation, at: parsed.range) }
        return DeepFeature(
            name: parsed.name, type: type, potency: parsed.potency?.potency, mutability: parsed.potency?.mutability,
            lowerBound: parsed.lowerBound, upperBound: parsed.upperBound, isContainment: parsed.isContainment,
            isOrdered: parsed.isOrdered, isUnique: parsed.isUnique, isDerived: parsed.isDerived,
            derivation: parsed.derivation,
            defaultValues: parsed.defaults.map { resolveValue($0, expectingObject: type.target != nil, inModelAt: modelIndex) },
            ontologicalType: ontologicalType, targetPotency: parsed.targetPotency, targetLevel: parsed.targetLevel)
    }

    /// Resolves a value: a name denotes a clabject if one has it, and otherwise a literal.
    private mutating func resolveValue(_ value: ParsedValue, expectingObject: Bool, inModelAt modelIndex: Int)
        -> DeepValue
    {
        switch value {
        case .value(let resolved):
            return resolved
        case .name(let name, let range):
            if let id = lookup(name, from: modelIndex) { return .object(id) }
            if expectingObject { error("unknown clabject '\(name)'", at: range) }
            return .literal(name)
        }
    }

    /// Reports a body that uses constructs of EOL rather than AQL.
    private mutating func checkLanguage(of body: String, at range: SourceRange) {
        guard let marker = MultiLevelSyntax.eolOnlyMarkers.first(where: { body.contains($0) }) else { return }
        error(
            "the expression uses '\(marker.trimmingCharacters(in: .whitespaces))', which is EOL; expressions are written in AQL",
            at: range, code: MultiLevelDiagnosticCode.constraintLanguage)
    }
}
