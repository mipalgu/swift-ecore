//
// LangiumParser.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// A type expression of a Langium declaration, such as `@Person[]` or `A | B`.
indirect enum LangiumTypeExpression: Sendable, Hashable {
    /// A type named by an identifier.
    case named(String, range: SourceRange)
    /// A primitive type such as `string`.
    case primitive(String)
    /// A string literal type such as `'+'`.
    case literal(String)
    /// A choice of types.
    case union([LangiumTypeExpression])
    /// A list of the element type.
    case array(LangiumTypeExpression)
    /// A cross-reference to the target type; `isMulti` marks `@T+`.
    case reference(LangiumTypeExpression, isMulti: Bool)

    /// The alternatives of a union, or the expression itself.
    var alternatives: [LangiumTypeExpression] {
        if case .union(let members) = self { return members.flatMap(\.alternatives) }
        return [self]
    }
}

/// A property of a declared interface.
struct LangiumAttribute: Sendable, Hashable {
    /// The property name.
    var name: String
    /// Whether the property is optional (`name?:`).
    var isOptional: Bool
    /// The property type.
    var type: LangiumTypeExpression
    /// The default value as text, if given.
    var defaultValue: String?
    /// The text of the property.
    var range: SourceRange
}

/// A declared interface.
struct LangiumInterface: Sendable, Hashable {
    /// The interface name.
    var name: String
    /// The names of the extended interfaces, with their text.
    var superTypes: [(name: String, range: SourceRange)]
    /// The properties.
    var attributes: [LangiumAttribute]
    /// The text of the interface name.
    var nameRange: SourceRange

    /// Compares interfaces by their content.
    ///
    /// - Parameters:
    ///   - lhs: One interface.
    ///   - rhs: The other interface.
    /// - Returns: `true` if both have the same name, supertypes and properties.
    static func == (lhs: LangiumInterface, rhs: LangiumInterface) -> Bool {
        lhs.name == rhs.name && lhs.superTypes.map(\.name) == rhs.superTypes.map(\.name)
            && lhs.attributes == rhs.attributes
    }

    /// Hashes the interface's name.
    ///
    /// - Parameter hasher: The hasher.
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

/// A declared type `type T = ...`.
struct LangiumTypeDeclaration: Sendable, Hashable {
    /// The type name.
    var name: String
    /// What the type stands for.
    var type: LangiumTypeExpression
    /// The text of the type name.
    var nameRange: SourceRange
}

/// The parsed declarations of a Langium grammar.
struct LangiumGrammar: Sendable {
    /// The grammar name, if declared.
    var name: String?
    /// The text of the grammar name.
    var nameRange: SourceRange?
    /// The imported grammar files.
    var imports: [String] = []
    /// The declared interfaces.
    var interfaces: [LangiumInterface] = []
    /// The declared types.
    var types: [LangiumTypeDeclaration] = []
    /// The rules, in order.
    var rules: [GrammarRule] = []
    /// The outline nodes of the declarations and rules.
    var outlineChildren: [OutlineNode] = []
}

/// Parses the text of a Langium grammar into declarations and rules.
///
/// The parser follows Langium's grammar of grammars (`langium-grammar.langium`).
/// It recovers from an error in a declaration or rule by skipping to the next
/// semicolon or, between declarations, to the next token that starts one.
struct LangiumParser {
    /// The shared parsing state.
    var state: RuleParserState

    /// What has been parsed.
    var grammar = LangiumGrammar()

    /// Creates a parser for a scanned text.
    ///
    /// - Parameters:
    ///   - tokens: All tokens, comments included.
    ///   - endRange: The empty range at the end of the text.
    ///   - collector: The collector with the lexical problems.
    init(tokens: [ScannedToken], endRange: SourceRange, collector: DiagnosticCollector) {
        state = RuleParserState(dialect: LangiumSyntax.dialect, tokens: tokens, endRange: endRange, collector: collector)
    }

    /// Parses the whole grammar.
    mutating func parse() {
        if state.cursor.check("grammar") { parseHeader() }
        while !state.cursor.isAtEnd {
            let before = state.cursor.index
            parseDeclaration()
            if state.cursor.index == before {
                state.unexpected("a rule, interface or type")
                state.cursor.advance()
            }
        }
    }

    /// Parses `grammar Name (with A, B)?`.
    private mutating func parseHeader() {
        state.cursor.advance()
        guard let name = state.expectIdentifier("the grammar name") else { return }
        grammar.name = name.value
        grammar.nameRange = name.range
        if state.cursor.accept("with") != nil {
            repeat { _ = state.expectIdentifier("a grammar name") } while state.cursor.accept(",") != nil
        }
        if state.cursor.check("hidden") && state.cursor.peek(1)?.is("(") == true {
            state.cursor.advance()
            state.skipBalanced("(", ")")
        }
    }

    /// Parses an import, interface, type or rule.
    private mutating func parseDeclaration() {
        let token = state.cursor.current
        let next = state.cursor.peek(1)
        if token?.is("import") == true && next?.kind == .string {
            parseImport()
        } else if token?.is("interface") == true && next?.kind == .identifier {
            parseInterface()
        } else if token?.is("type") == true && next?.kind == .identifier && state.cursor.peek(2)?.is("=") == true {
            parseTypeDeclaration()
        } else if token?.is("terminal") == true || (token?.is("hidden") == true && next?.is("terminal") == true) {
            parseTerminalRule()
        } else if token?.is("infix") == true && next?.kind == .identifier {
            parseInfixRule()
        } else if token?.kind == .identifier {
            parseParserRule()
        }
    }

    /// Parses `import './file';`.
    private mutating func parseImport() {
        let start = state.cursor.currentRange
        state.cursor.advance()
        guard let path = state.cursor.advance() else { return }
        state.cursor.accept(";")
        grammar.imports.append(path.value)
        grammar.outlineChildren.append(OutlineNode(
            id: "import/\(path.value)", kind: LangiumOutlineKind.import, name: path.value,
            range: state.cursor.range(from: start), selectionRange: path.range))
    }

    /// Parses `interface Name (extends A, B)? { attributes } ;?`.
    private mutating func parseInterface() {
        let start = state.cursor.currentRange
        state.cursor.advance()
        guard let name = state.cursor.advance() else { return }
        state.markType(name)
        var superTypes: [(name: String, range: SourceRange)] = []
        if state.cursor.accept("extends") != nil {
            repeat {
                guard let superType = state.expectIdentifier("an interface name") else { break }
                state.markType(superType)
                superTypes.append((superType.value, superType.range))
            } while state.cursor.accept(",") != nil
        }
        var attributes: [LangiumAttribute] = []
        if state.expect("{") {
            while let token = state.cursor.current, !token.is("}") {
                guard let attribute = parseAttribute() else {
                    while let skipped = state.cursor.current, !skipped.is("}"), !skipped.is(";") {
                        state.cursor.advance()
                    }
                    state.cursor.accept(";")
                    continue
                }
                attributes.append(attribute)
            }
            state.expect("}")
        }
        state.cursor.accept(";")
        let range = state.cursor.range(from: start)
        grammar.interfaces.append(LangiumInterface(
            name: name.value, superTypes: superTypes, attributes: attributes, nameRange: name.range))
        grammar.outlineChildren.append(OutlineNode(
            id: "interface/\(name.value)", kind: LangiumOutlineKind.interface, name: name.value,
            detail: superTypes.isEmpty ? nil : superTypes.map(\.name).joined(separator: ", "), range: range,
            selectionRange: name.range,
            children: attributes.map { attribute in
                OutlineNode(
                    id: "interface/\(name.value)/\(attribute.name)", kind: LangiumOutlineKind.attribute,
                    name: attribute.name, range: attribute.range, selectionRange: attribute.range)
            }))
    }

    /// Parses `name?: Type = default;`.
    ///
    /// - Returns: The attribute, or `nil` after reporting a problem.
    private mutating func parseAttribute() -> LangiumAttribute? {
        let start = state.cursor.currentRange
        guard let name = state.expectIdentifier("a property name") else { return nil }
        let isOptional = state.cursor.accept("?") != nil
        guard state.expect(":"), let type = parseTypeExpression() else { return nil }
        var defaultValue: String?
        if state.cursor.accept("=") != nil {
            if state.cursor.check("[") {
                state.skipBalanced("[", "]")
            } else if let value = state.cursor.advance() {
                defaultValue = value.kind == .string ? value.value : value.text
                if value.is("-"), let number = state.cursor.accept(.number) { defaultValue = "-" + number.text }
            }
        }
        state.cursor.accept(";")
        return LangiumAttribute(
            name: name.value, isOptional: isOptional, type: type, defaultValue: defaultValue,
            range: state.cursor.range(from: start))
    }

    /// Parses a type expression: alternatives of arrays of references or simple types.
    ///
    /// - Returns: The expression, or `nil` after reporting a problem.
    private mutating func parseTypeExpression() -> LangiumTypeExpression? {
        guard let first = parseArrayType() else { return nil }
        var members = [first]
        while state.cursor.accept("|") != nil {
            guard let member = parseArrayType() else { return nil }
            members.append(member)
        }
        return members.count == 1 ? first : .union(members)
    }

    /// Parses a reference or simple type with an optional `[]`.
    ///
    /// - Returns: The expression, or `nil` after reporting a problem.
    private mutating func parseArrayType() -> LangiumTypeExpression? {
        var type: LangiumTypeExpression
        if state.cursor.accept("@") != nil {
            guard let target = parseSimpleType() else { return nil }
            type = .reference(target, isMulti: state.cursor.accept("+") != nil)
        } else {
            guard let simple = parseSimpleType() else { return nil }
            type = simple
        }
        while state.cursor.check("["), state.cursor.peek(1)?.is("]") == true {
            state.cursor.advance()
            state.cursor.advance()
            type = .array(type)
        }
        return type
    }

    /// Parses a parenthesised type, a type name, a primitive or a string literal type.
    ///
    /// - Returns: The expression, or `nil` after reporting a problem.
    private mutating func parseSimpleType() -> LangiumTypeExpression? {
        if state.cursor.accept("(") != nil {
            guard let inner = parseTypeExpression(), state.expect(")") else { return nil }
            return inner
        }
        if let literal = state.cursor.accept(.string) { return .literal(literal.value) }
        guard let name = state.expectIdentifier("a type") else { return nil }
        if LangiumSyntax.primitiveTypes[name.value] != nil { return .primitive(name.value) }
        state.markType(name)
        return .named(name.value, range: name.range)
    }

    /// Parses `type Name = TypeExpression ;?`.
    private mutating func parseTypeDeclaration() {
        let start = state.cursor.currentRange
        state.cursor.advance()
        guard let name = state.cursor.advance() else { return }
        state.markType(name)
        state.cursor.advance()
        guard let type = parseTypeExpression() else {
            state.recoverToSemicolon()
            return
        }
        state.cursor.accept(";")
        grammar.types.append(LangiumTypeDeclaration(name: name.value, type: type, nameRange: name.range))
        grammar.outlineChildren.append(OutlineNode(
            id: "type/\(name.value)", kind: LangiumOutlineKind.type, name: name.value,
            range: state.cursor.range(from: start), selectionRange: name.range))
    }

    /// Parses `(returns Type | infers Type)?`.
    ///
    /// - Returns: The declared return type, if any.
    private mutating func parseReturnClause() -> RuleTypeReference? {
        if state.cursor.accept("returns") != nil {
            guard let name = state.expectIdentifier("a type") else { return nil }
            if LangiumSyntax.primitiveTypes[name.value] == nil { state.markType(name) }
            return RuleTypeReference(name: name.value, range: name.range)
        }
        if state.cursor.accept("infers") != nil {
            guard let name = state.expectIdentifier("a type") else { return nil }
            state.markType(name)
            return RuleTypeReference(name: name.value, isInferred: true, range: name.range)
        }
        return nil
    }

    /// Parses `(hidden)? terminal (fragment NAME | NAME (returns Type)?) : ... ;`, skipping the body.
    private mutating func parseTerminalRule() {
        let start = state.cursor.currentRange
        state.cursor.accept("hidden")
        state.cursor.advance()
        let isFragment = state.cursor.check("fragment") && state.cursor.peek(1)?.kind == .identifier
        if isFragment { state.cursor.advance() }
        guard let name = state.expectIdentifier("the name of the terminal rule") else {
            state.recoverToSemicolon()
            return
        }
        let returnType = isFragment ? nil : parseReturnClause()
        state.expect(":")
        state.recoverToSemicolon()
        let range = state.cursor.range(from: start)
        grammar.rules.append(GrammarRule(
            kind: .terminal, name: name.value, returnType: returnType, isFragment: isFragment, nameRange: name.range,
            range: range))
        grammar.outlineChildren.append(OutlineNode(
            id: "rule/\(name.value)", kind: LangiumOutlineKind.terminalRule, name: name.value,
            detail: returnType?.name, range: range, selectionRange: name.range))
    }

    /// Parses `infix Name on Operand (returns | infers Type)? : ops > ops ;`.
    private mutating func parseInfixRule() {
        let start = state.cursor.currentRange
        state.cursor.advance()
        guard let name = state.cursor.advance() else { return }
        if state.cursor.check("<") { state.skipBalanced("<", ">") }
        var operand: String?
        if state.expect("on"), let call = state.expectIdentifier("the operand rule") {
            operand = call.value
            if state.cursor.check("<") { state.skipBalanced("<", ">") }
        }
        let returnType = parseReturnClause()
        var operators: [String] = []
        if state.expect(":") {
            while let token = state.cursor.current, !token.is(";") {
                if token.kind == .string { operators.append(token.value) }
                state.cursor.advance()
            }
            state.expect(";")
        } else {
            state.recoverToSemicolon()
        }
        let range = state.cursor.range(from: start)
        grammar.rules.append(GrammarRule(
            kind: .infix, name: name.value, returnType: returnType, infixOperand: operand, infixOperators: operators,
            nameRange: name.range, range: range))
        grammar.outlineChildren.append(OutlineNode(
            id: "rule/\(name.value)", kind: LangiumOutlineKind.infixRule, name: name.value, detail: operand,
            range: range, selectionRange: name.range))
    }

    /// Parses `(entry | fragment)? Name (<params>)? (returns | infers Type)? : body ;`.
    private mutating func parseParserRule() {
        let start = state.cursor.currentRange
        var isFragment = false
        if (state.cursor.check("entry") || state.cursor.check("fragment")), state.cursor.peek(1)?.kind == .identifier {
            isFragment = state.cursor.check("fragment")
            state.cursor.advance()
        }
        guard let name = state.expectIdentifier("the name of the rule") else {
            state.recoverToSemicolon()
            return
        }
        if state.cursor.check("<") { state.skipBalanced("<", ">") }
        let returnType = parseReturnClause()
        if state.cursor.check("hidden") && state.cursor.peek(1)?.is("(") == true {
            state.cursor.advance()
            state.skipBalanced("(", ")")
        }
        var body: RuleElement?
        if state.expect(":") {
            body = state.parseAlternatives()
            if body == nil {
                state.recoverToSemicolon()
            } else if !state.expect(";") && !startsDeclaration {
                state.recoverToSemicolon()
            }
        } else {
            state.recoverToSemicolon()
        }
        let range = state.cursor.range(from: start)
        grammar.rules.append(GrammarRule(
            kind: .parser, name: name.value, returnType: returnType, isFragment: isFragment, body: body,
            nameRange: name.range, range: range))
        grammar.outlineChildren.append(OutlineNode(
            id: "rule/\(name.value)", kind: isFragment ? LangiumOutlineKind.fragment : LangiumOutlineKind.parserRule,
            name: name.value, detail: returnType?.name, range: range, selectionRange: name.range))
    }

    /// Whether the current token evidently starts a declaration or rule.
    private var startsDeclaration: Bool {
        guard let token = state.cursor.current else { return true }
        if ["interface", "type", "terminal", "hidden", "entry", "fragment", "infix", "import"].contains(token.text) {
            return true
        }
        guard token.kind == .identifier, let next = state.cursor.peek(1) else { return false }
        return next.is(":") || next.is("returns") || next.is("infers") || next.is("<")
    }
}
