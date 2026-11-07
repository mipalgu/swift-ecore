//
// XtextParser.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// A `generate` declaration of an Xtext grammar.
struct XtextGeneratedPackage: Sendable, Hashable {
    /// The package name.
    var name: String
    /// The namespace URI.
    var nsURI: String
    /// The alias by which rules refer to the package, if any.
    var alias: String?
    /// The text of the declaration.
    var range: SourceRange
}

/// An `import` declaration of an Xtext grammar.
struct XtextImportedPackage: Sendable, Hashable {
    /// The namespace URI of the imported package.
    var nsURI: String
    /// The alias by which rules refer to the package, if any.
    var alias: String?
    /// The text of the declaration.
    var range: SourceRange
}

/// The parsed declarations of an Xtext grammar.
struct XtextGrammar: Sendable {
    /// The qualified name of the grammar.
    var name: String?
    /// The qualified names of the grammars it extends (`with`).
    var usedGrammars: [String] = []
    /// The generated packages.
    var generated: [XtextGeneratedPackage] = []
    /// The imported packages.
    var imported: [XtextImportedPackage] = []
    /// The rules, in order.
    var rules: [GrammarRule] = []
    /// The outline nodes of the declarations and rules.
    var outlineChildren: [OutlineNode] = []
    /// The text of the grammar name.
    var nameRange: SourceRange?
}

/// Parses the text of an Xtext grammar into declarations and rules.
///
/// The parser follows the grammar language of `Xtext.xtext`. It recovers from
/// an error in a declaration or rule by skipping to the next semicolon.
struct XtextParser {
    /// The shared parsing state.
    var state: RuleParserState

    /// What has been parsed.
    var grammar = XtextGrammar()

    /// Creates a parser for a scanned text.
    ///
    /// - Parameters:
    ///   - tokens: All tokens, comments included.
    ///   - endRange: The empty range at the end of the text.
    ///   - collector: The collector with the lexical problems.
    init(tokens: [ScannedToken], endRange: SourceRange, collector: DiagnosticCollector) {
        state = RuleParserState(
            dialect: XtextSyntax.dialect, tokens: tokens, endRange: endRange, collector: collector)
    }

    /// Parses the whole grammar.
    mutating func parse() {
        parseHeader()
        while !state.cursor.isAtEnd {
            let before = state.cursor.index
            parseDeclaration()
            if state.cursor.index == before { state.cursor.advance() }
        }
    }

    /// Parses `grammar a.b.C with X, Y hidden(...)`.
    private mutating func parseHeader() {
        guard state.cursor.accept("grammar") != nil else {
            state.unexpected("'grammar'")
            return
        }
        let start = state.cursor.currentRange
        grammar.name = parseQualifiedName()
        grammar.nameRange = state.cursor.range(from: start)
        if state.cursor.accept("with") != nil {
            repeat {
                if let used = parseQualifiedName() { grammar.usedGrammars.append(used) }
            } while state.cursor.accept(",") != nil
        }
        if state.cursor.check("hidden") {
            state.cursor.advance()
            if state.cursor.check("(") { state.skipBalanced("(", ")") }
        }
    }

    /// Parses a dotted name such as `org.example.Grammar`.
    ///
    /// - Returns: The name, or `nil` after reporting that it is missing.
    private mutating func parseQualifiedName() -> String? {
        guard let first = state.expectIdentifier("a name") else { return nil }
        var name = first.value
        while state.cursor.check("."), state.cursor.peek(1)?.kind == .identifier {
            state.cursor.advance()
            name += "." + (state.cursor.advance()?.value ?? "")
        }
        return name
    }

    /// Parses a metamodel declaration or a rule.
    private mutating func parseDeclaration() {
        if state.cursor.check("generate") {
            parseGenerate()
        } else if state.cursor.check("import") {
            parseImport()
        } else {
            parseRule()
        }
    }

    /// Parses `generate name "nsURI" (as alias)?`.
    private mutating func parseGenerate() {
        let start = state.cursor.currentRange
        state.cursor.advance()
        guard let name = state.expectIdentifier("the name of the generated package") else { return }
        guard let uri = state.cursor.accept(.string) else {
            state.unexpected("the namespace URI of the generated package")
            return
        }
        var alias: String?
        if state.cursor.accept("as") != nil { alias = state.expectIdentifier("an alias")?.value }
        let range = state.cursor.range(from: start)
        grammar.generated.append(XtextGeneratedPackage(name: name.value, nsURI: uri.value, alias: alias, range: range))
        grammar.outlineChildren.append(OutlineNode(
            id: "generate/\(name.value)", kind: XtextOutlineKind.generate, name: name.value, detail: uri.value,
            range: range, selectionRange: name.range))
    }

    /// Parses `import "nsURI" (as alias)?`.
    private mutating func parseImport() {
        let start = state.cursor.currentRange
        state.cursor.advance()
        guard let uri = state.cursor.accept(.string) else {
            state.unexpected("the namespace URI of the imported package")
            return
        }
        var alias: String?
        if state.cursor.accept("as") != nil { alias = state.expectIdentifier("an alias")?.value }
        let range = state.cursor.range(from: start)
        grammar.imported.append(XtextImportedPackage(nsURI: uri.value, alias: alias, range: range))
        grammar.outlineChildren.append(OutlineNode(
            id: "import/\(uri.value)", kind: XtextOutlineKind.import, name: alias ?? uri.value, detail: uri.value,
            range: range, selectionRange: uri.range))
    }

    /// Parses a parser, terminal or enum rule, with leading annotations such as `@Override`.
    private mutating func parseRule() {
        let start = state.cursor.currentRange
        while state.cursor.check("@"), state.cursor.peek(1)?.kind == .identifier {
            state.cursor.advance()
            state.cursor.advance()
        }
        if state.cursor.check("terminal") {
            parseTerminalRule(start: start)
        } else if state.cursor.check("enum") {
            parseEnumRule(start: start)
        } else if state.cursor.check(.identifier) {
            parseParserRule(start: start)
        } else {
            state.unexpected("a rule")
            state.recoverToSemicolon()
        }
    }

    /// Consumes the semicolon that ends a rule.
    ///
    /// When it is missing, the problem is reported and tokens are skipped up to
    /// the next semicolon, unless the next rule evidently starts already.
    private mutating func finishRule() {
        guard !state.expect(";") else { return }
        if !startsRule { state.recoverToSemicolon() }
    }

    /// Whether the current token evidently starts a rule or declaration.
    private var startsRule: Bool {
        guard let token = state.cursor.current else { return true }
        if ["terminal", "enum", "fragment", "@", "generate", "import"].contains(token.text) { return true }
        guard token.kind == .identifier, let next = state.cursor.peek(1) else { return false }
        return next.is(":") || next.is("returns") || next.is("<") || next.is("hidden")
    }

    /// Parses an optional `returns Type` clause.
    ///
    /// - Returns: The type reference, if present.
    private mutating func parseReturns() -> RuleTypeReference? {
        guard state.cursor.accept("returns") != nil else { return nil }
        return state.parseTypeReference()
    }

    /// Parses `terminal (fragment)? NAME (returns Type)? : ... ;`, skipping the body.
    ///
    /// - Parameter start: The range of the rule's first token.
    private mutating func parseTerminalRule(start: SourceRange) {
        state.cursor.advance()
        let isFragment = state.cursor.accept("fragment") != nil
        guard let name = state.expectIdentifier("the name of the terminal rule") else {
            state.recoverToSemicolon()
            return
        }
        let returnType = isFragment ? nil : parseReturns()
        guard state.expect(":") else {
            state.recoverToSemicolon()
            return
        }
        state.recoverToSemicolon()
        let range = state.cursor.range(from: start)
        grammar.rules.append(GrammarRule(
            kind: .terminal, name: name.value, returnType: returnType, isFragment: isFragment,
            nameRange: name.range, range: range))
        grammar.outlineChildren.append(OutlineNode(
            id: "rule/\(name.value)", kind: XtextOutlineKind.terminalRule, name: name.value,
            detail: returnType?.displayName, range: range, selectionRange: name.range))
    }

    /// Parses `enum NAME (returns Type)? : a = 'A' | b ;`.
    ///
    /// - Parameter start: The range of the rule's first token.
    private mutating func parseEnumRule(start: SourceRange) {
        state.cursor.advance()
        guard let name = state.expectIdentifier("the name of the enum rule") else {
            state.recoverToSemicolon()
            return
        }
        let returnType = parseReturns()
        guard state.expect(":") else {
            state.recoverToSemicolon()
            return
        }
        var literals: [RuleEnumLiteral] = []
        repeat {
            let literalStart = state.cursor.currentRange
            guard let literal = state.expectIdentifier("an enumeration literal") else { break }
            var keyword: String?
            if state.cursor.accept("=") != nil {
                guard let text = state.cursor.accept(.string) else {
                    state.unexpected("the keyword of the literal")
                    break
                }
                keyword = text.value
            }
            literals.append(RuleEnumLiteral(
                name: literal.value, keyword: keyword, range: state.cursor.range(from: literalStart)))
        } while state.cursor.accept("|") != nil
        finishRule()
        let range = state.cursor.range(from: start)
        grammar.rules.append(GrammarRule(
            kind: .enumeration, name: name.value, returnType: returnType, literals: literals, nameRange: name.range,
            range: range))
        grammar.outlineChildren.append(OutlineNode(
            id: "rule/\(name.value)", kind: XtextOutlineKind.enumRule, name: name.value,
            detail: returnType?.displayName, range: range, selectionRange: name.range))
    }

    /// Parses `(fragment)? NAME (<params>)? (* | returns Type)? (hidden(...))? : body ;`.
    ///
    /// - Parameter start: The range of the rule's first token.
    private mutating func parseParserRule(start: SourceRange) {
        let isFragment = state.cursor.check("fragment") && state.cursor.peek(1)?.kind == .identifier
        if isFragment { state.cursor.advance() }
        guard let name = state.expectIdentifier("the name of the rule") else {
            state.recoverToSemicolon()
            return
        }
        if state.cursor.check("<") { state.skipBalanced("<", ">") }
        var isWildcard = false
        var returnType: RuleTypeReference?
        if isFragment && state.cursor.accept("*") != nil {
            isWildcard = true
        } else {
            returnType = parseReturns()
        }
        if state.cursor.check("hidden") {
            state.cursor.advance()
            if state.cursor.check("(") { state.skipBalanced("(", ")") }
        }
        var body: RuleElement?
        if state.expect(":") {
            body = state.parseAlternatives()
            if body == nil {
                state.recoverToSemicolon()
            } else {
                finishRule()
            }
        } else {
            state.recoverToSemicolon()
        }
        let range = state.cursor.range(from: start)
        grammar.rules.append(GrammarRule(
            kind: .parser, name: name.value, returnType: returnType, isFragment: isFragment,
            isWildcardFragment: isWildcard, body: body, nameRange: name.range, range: range))
        grammar.outlineChildren.append(OutlineNode(
            id: "rule/\(name.value)", kind: isFragment ? XtextOutlineKind.fragment : XtextOutlineKind.parserRule,
            name: name.value, detail: returnType?.displayName, range: range, selectionRange: name.range))
    }
}
