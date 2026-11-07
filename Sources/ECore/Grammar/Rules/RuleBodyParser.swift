//
// RuleBodyParser.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// The state shared by the Xtext and Langium parsers: tokens, diagnostics and highlighting hints.
///
/// The methods of this type parse the parts that both notations share, chiefly
/// the bodies of parser rules, whose syntax Langium inherited from Xtext. The
/// notation-specific parsers wrap a state and parse their own declarations.
struct RuleParserState: Sendable {
    /// The notation being parsed.
    let dialect: RuleGrammarDialect

    /// The significant tokens.
    var cursor: GrammarTokenCursor

    /// The problems found.
    var collector: DiagnosticCollector

    /// The start offsets of identifiers that name types, for highlighting.
    var typeNameOffsets: Set<Int> = []

    /// Creates a state for a token list.
    ///
    /// - Parameters:
    ///   - dialect: The notation being parsed.
    ///   - tokens: All tokens of the text, comments included.
    ///   - endRange: The empty range at the end of the text.
    ///   - collector: The collector that already holds the lexical problems.
    init(
        dialect: RuleGrammarDialect, tokens: [ScannedToken], endRange: SourceRange, collector: DiagnosticCollector
    ) {
        self.dialect = dialect
        self.cursor = GrammarTokenCursor(tokens, endRange: endRange)
        self.collector = collector
    }

    // MARK: Utilities

    /// Reports that the current token is not what the grammar expects.
    ///
    /// - Parameter expectation: A description of what was expected.
    mutating func unexpected(_ expectation: String) {
        let found = cursor.current.map { "'\($0.text)'" } ?? "the end of the text"
        collector.error(
            dialect.code(.unexpectedToken), "Expected \(expectation) but found \(found)", at: cursor.currentRange)
    }

    /// Consumes a symbol or reports that it is missing.
    ///
    /// - Parameter text: The expected spelling.
    /// - Returns: `true` if the symbol was present.
    @discardableResult
    mutating func expect(_ text: String) -> Bool {
        if cursor.accept(text) != nil { return true }
        unexpected("'\(text)'")
        return false
    }

    /// Consumes an identifier or reports that it is missing.
    ///
    /// - Parameter description: What the identifier names, for the message.
    /// - Returns: The identifier token, or `nil` if it is missing.
    mutating func expectIdentifier(_ description: String) -> ScannedToken? {
        if let token = cursor.accept(.identifier) { return token }
        unexpected(description)
        return nil
    }

    /// Skips a bracketed region whose opening bracket is the current token.
    ///
    /// - Parameters:
    ///   - open: The opening bracket.
    ///   - close: The closing bracket.
    mutating func skipBalanced(_ open: String, _ close: String) {
        var depth = 0
        while let token = cursor.current {
            if token.is(open) { depth += 1 }
            if token.is(close) { depth -= 1 }
            cursor.advance()
            if depth <= 0 { return }
            if token.is(";") && open != "(" { return }
        }
    }

    /// Skips the rest of a declaration up to and including its terminating semicolon.
    mutating func recoverToSemicolon() {
        while let token = cursor.current, !token.is(";") { cursor.advance() }
        cursor.accept(";")
    }

    /// Records that an identifier token names a type.
    ///
    /// - Parameter token: The identifier.
    mutating func markType(_ token: ScannedToken) {
        typeNameOffsets.insert(token.range.start.utf8Offset)
    }

    /// Parses a type reference `Name` or `alias::Name`.
    ///
    /// - Returns: The reference, or `nil` (after reporting) if no name is present.
    mutating func parseTypeReference() -> RuleTypeReference? {
        guard let first = expectIdentifier("a type name") else { return nil }
        if cursor.accept("::") != nil {
            guard let second = expectIdentifier("a type name after '::'") else { return nil }
            markType(second)
            return RuleTypeReference(
                alias: first.value, name: second.value,
                range: SourceRange(start: first.range.start, end: second.range.end))
        }
        markType(first)
        return RuleTypeReference(name: first.value, range: first.range)
    }

    /// Reads an optional cardinality operator.
    ///
    /// - Returns: The cardinality; `.one` if no operator follows.
    mutating func parseCardinality() -> RuleCardinality {
        if let token = cursor.current, token.kind == .punctuation, let cardinality = RuleCardinality(operator: token.text) {
            cursor.advance()
            return cardinality
        }
        return .one
    }

    // MARK: Rule bodies

    /// Whether the current token can start a token of a rule body.
    private var startsToken: Bool {
        guard let token = cursor.current else { return false }
        switch token.kind {
        case .string: return true
        case .identifier:
            guard let next = cursor.peek(1) else { return true }
            return !(next.is(":") || next.is("returns") || next.is("infers"))
        case .punctuation: return ["(", "{", "=>", "->", "."].contains(token.text)
        default: return false
        }
    }

    /// Parses alternatives separated by `|`, as in the body of a parser rule.
    ///
    /// - Returns: The element, or `nil` if not even one branch could be read.
    mutating func parseAlternatives() -> RuleElement? {
        let start = cursor.currentRange
        guard let first = parseConditionalBranch() else { return nil }
        var branches = [first]
        while cursor.accept("|") != nil {
            guard let branch = parseConditionalBranch() else { return nil }
            branches.append(branch)
        }
        return branches.count == 1 ? first : RuleElement(.alternatives(branches), range: cursor.range(from: start))
    }

    /// Parses a branch, which may start with a guard condition `<...>`.
    ///
    /// - Returns: The branch, or `nil` after reporting a problem.
    private mutating func parseConditionalBranch() -> RuleElement? {
        if cursor.check("<") { skipBalanced("<", ">") }
        return parseUnorderedGroup()
    }

    /// Parses groups separated by `&`.
    ///
    /// - Returns: The element, or `nil` after reporting a problem.
    private mutating func parseUnorderedGroup() -> RuleElement? {
        let start = cursor.currentRange
        guard let first = parseGroup() else { return nil }
        var groups = [first]
        while cursor.accept("&") != nil {
            guard let group = parseGroup() else { return nil }
            groups.append(group)
        }
        return groups.count == 1 ? first : RuleElement(.unorderedGroup(groups), range: cursor.range(from: start))
    }

    /// Parses a sequence of tokens.
    ///
    /// - Returns: The element, or `nil` after reporting a problem.
    private mutating func parseGroup() -> RuleElement? {
        let start = cursor.currentRange
        var elements: [RuleElement] = []
        while startsToken {
            guard let element = parseToken() else { return nil }
            elements.append(element)
        }
        guard !elements.isEmpty else {
            unexpected("a rule element")
            return nil
        }
        return elements.count == 1 ? elements[0] : RuleElement(.group(elements), range: cursor.range(from: start))
    }

    /// Parses an action, an assignment or a terminal, with its cardinality.
    ///
    /// - Returns: The element, or `nil` after reporting a problem.
    private mutating func parseToken() -> RuleElement? {
        if cursor.check("{") { return parseAction() }
        let start = cursor.currentRange
        var element: RuleElement
        if isAtAssignment {
            guard let assignment = parseAssignment() else { return nil }
            element = assignment
        } else {
            guard let terminal = parseAbstractTerminal() else { return nil }
            element = terminal
        }
        element.cardinality = parseCardinality()
        element.range = cursor.range(from: start)
        return element
    }

    /// Whether an assignment starts here: an optional predicate, a name and an assignment operator.
    private var isAtAssignment: Bool {
        var distance = 0
        if let token = cursor.peek(), token.is("=>") || token.is("->") { distance = 1 }
        guard cursor.peek(distance)?.kind == .identifier, let op = cursor.peek(distance + 1) else { return false }
        return op.kind == .punctuation && (op.text == "=" || op.text == "+=" || op.text == "?=")
    }

    /// Parses an assignment `feature op terminal`.
    ///
    /// - Returns: The assignment, or `nil` after reporting a problem.
    private mutating func parseAssignment() -> RuleElement? {
        let start = cursor.currentRange
        if cursor.check("=>") || cursor.check("->") { cursor.advance() }
        guard let feature = cursor.advance(), let op = cursor.advance(),
            let assignment = RuleAssignmentOperator(rawValue: op.text)
        else { return nil }
        guard let terminal = parseAssignableTerminal() else { return nil }
        return RuleElement(
            .assignment(feature: feature.value, operator: assignment, terminal: terminal),
            range: cursor.range(from: start))
    }

    /// Parses what an assignment assigns: a keyword, rule call, cross-reference or parenthesised choice.
    ///
    /// - Returns: The element, or `nil` after reporting a problem.
    private mutating func parseAssignableTerminal() -> RuleElement? {
        let start = cursor.currentRange
        if cursor.check("=>") || cursor.check("->") { cursor.advance() }
        if let keyword = cursor.accept(.string) {
            return RuleElement(.keyword(keyword.value), range: keyword.range)
        }
        if cursor.check("[") { return parseCrossReference() }
        if cursor.accept("(") != nil {
            guard let first = parseAssignableTerminal() else { return nil }
            var choices = [first]
            while cursor.accept("|") != nil {
                guard let choice = parseAssignableTerminal() else { return nil }
                choices.append(choice)
            }
            guard expect(")") else { return nil }
            return choices.count == 1
                ? choices[0] : RuleElement(.alternatives(choices), range: cursor.range(from: start))
        }
        if cursor.check(.identifier) { return parseRuleCall() }
        unexpected("a keyword, rule call, cross-reference or '('")
        return nil
    }

    /// Parses a cross-reference `[Type]`, `[Type|TERMINAL]`, `[Type:TERMINAL]` or `[+Type:TERMINAL]`.
    ///
    /// - Returns: The cross-reference, or `nil` after reporting a problem.
    private mutating func parseCrossReference() -> RuleElement? {
        let start = cursor.currentRange
        cursor.advance()
        let isMulti = cursor.accept("+") != nil
        guard let type = parseTypeReference() else { return nil }
        var terminal: String?
        if let separator = cursor.current, dialect.crossReferenceSeparators.contains(separator.text),
            separator.kind == .punctuation
        {
            cursor.advance()
            if let keyword = cursor.accept(.string) {
                terminal = keyword.value
            } else if let call = expectIdentifier("the terminal of the cross-reference") {
                terminal = call.value
                while cursor.accept("::") != nil, let next = cursor.accept(.identifier) { terminal = next.value }
            } else {
                return nil
            }
        }
        guard expect("]") else { return nil }
        return RuleElement(
            .crossReference(type: type, terminal: terminal, isMulti: isMulti), range: cursor.range(from: start))
    }

    /// Parses a rule call, with an optional qualifier `super::` and arguments `<...>`.
    ///
    /// - Returns: The rule call, or `nil` after reporting a problem.
    private mutating func parseRuleCall() -> RuleElement? {
        let start = cursor.currentRange
        guard var name = expectIdentifier("a rule name")?.value else { return nil }
        while cursor.check("::"), cursor.peek(1)?.kind == .identifier {
            cursor.advance()
            name = cursor.advance()?.value ?? name
        }
        if cursor.check("<") { skipBalanced("<", ">") }
        return RuleElement(.ruleCall(name), range: cursor.range(from: start))
    }

    /// Parses a keyword, rule call, wildcard or parenthesised element, with an optional predicate.
    ///
    /// - Returns: The element, or `nil` after reporting a problem.
    private mutating func parseAbstractTerminal() -> RuleElement? {
        let start = cursor.currentRange
        if cursor.check("=>") || cursor.check("->") { cursor.advance() }
        if let keyword = cursor.accept(.string) {
            return RuleElement(.keyword(keyword.value), range: keyword.range)
        }
        if cursor.accept(".") != nil { return RuleElement(.other, range: cursor.range(from: start)) }
        if cursor.accept("(") != nil {
            guard var inner = parseAlternatives(), expect(")") else { return nil }
            if inner.cardinality != .one {
                inner = RuleElement(.group([inner]), range: inner.range)
            }
            inner.range = cursor.range(from: start)
            return inner
        }
        if cursor.check("EOF") {
            cursor.advance()
            return RuleElement(.other, range: cursor.range(from: start))
        }
        if cursor.check(.identifier) { return parseRuleCall() }
        unexpected("a rule element")
        return nil
    }

    /// Parses an action `{Type}`, `{infer Type}` or `{Type.feature=current}`.
    ///
    /// - Returns: The action, or `nil` after reporting a problem.
    private mutating func parseAction() -> RuleElement? {
        let start = cursor.currentRange
        cursor.advance()
        let inferred = cursor.check("infer") && cursor.peek(1)?.kind == .identifier
        if inferred { cursor.advance() }
        guard var type = parseTypeReference() else { return nil }
        type.isInferred = inferred
        var feature: String?
        var op: RuleAssignmentOperator?
        if cursor.accept(".") != nil {
            guard let name = expectIdentifier("a feature name") else { return nil }
            feature = name.value
            if let token = cursor.current, token.is("=") || token.is("+=") {
                op = RuleAssignmentOperator(rawValue: token.text)
                cursor.advance()
            } else {
                unexpected("'=' or '+='")
                return nil
            }
            guard expect("current") else { return nil }
        }
        guard expect("}") else { return nil }
        return RuleElement(.action(type: type, feature: feature, operator: op), range: cursor.range(from: start))
    }
}
