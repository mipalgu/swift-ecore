//
// SDF3Parser.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// Reads the sorts, constructors and injections of an SDF3 or Stratego module.
///
/// The parser is a recursive-descent reader that knows the declarations that
/// define abstract syntax and skips the rest: priorities, restrictions,
/// template options, and Stratego rules and strategies. It recovers from
/// errors by skipping to the next production, signature entry or section.
struct SDF3Parser {
    /// The section the parser is in, which decides how statements are read.
    private enum Section {
        /// Before any section.
        case none
        /// A list of sorts, with the evidence that declaring a sort there gives,
        /// or `nil` for start symbols.
        case sortList(SDF3SortEvidence?)
        /// Productions, either lexical or context-free.
        case productions(lexical: Bool)
        /// A Stratego `signature` heading without a subsection yet.
        case signature
        /// The `constructors` of a Stratego signature.
        case signatureConstructors
        /// A section whose content does not define abstract syntax.
        case skipped
    }

    /// The significant tokens.
    private var cursor: GrammarTokenCursor

    /// The diagnostics found while parsing.
    private(set) var collector: DiagnosticCollector

    /// What has been read so far.
    private(set) var definition = SDF3Definition()

    /// The section the parser is in.
    private var section = Section.none

    /// The module outline node, once the module header has been read.
    private var moduleNode: OutlineNode?

    /// The section outline nodes, in order.
    private var sectionNodes: [OutlineNode] = []

    /// Outline nodes read before any section.
    private var looseNodes: [OutlineNode] = []

    /// Prepares to parse tokens.
    ///
    /// - Parameters:
    ///   - tokens: All tokens of the text, including comments.
    ///   - endRange: The empty range at the end of the text.
    ///   - document: The identifier of the document, for diagnostics.
    init(tokens: [ScannedToken], endRange: SourceRange, document: String?) {
        cursor = GrammarTokenCursor(tokens, endRange: endRange)
        collector = DiagnosticCollector(document: document)
    }

    /// The outline of what has been read.
    var outline: [OutlineNode] {
        let children = looseNodes + sectionNodes
        guard var module = moduleNode else { return children }
        module.children += children
        if let last = children.last { module.range = module.range.union(last.range) }
        return [module]
    }

    /// Parses every token.
    mutating func parse() {
        while let token = cursor.current {
            if token.isSectionKeyword {
                parseHeader()
                continue
            }
            switch section {
            case .none, .signature:
                unexpected(token, expectation: "a section such as 'context-free syntax' or 'signature'")
                cursor.advance()
                while let next = cursor.current, !next.isSectionKeyword { cursor.advance() }
            case .sortList(let evidence):
                parseSortListEntry(evidence: evidence)
            case .productions(let lexical):
                parseProduction(lexical: lexical)
            case .signatureConstructors:
                parseSignatureEntry()
            case .skipped:
                cursor.advance()
            }
        }
    }

    // MARK: Headers

    /// Reads a module header, an import list or a section heading.
    private mutating func parseHeader() {
        guard let keyword = cursor.advance() else { return }
        switch keyword.text {
        case SDF3Language.module:
            parseModule(keyword)
        case SDF3Language.imports:
            parseImports(keyword)
        case SDF3Language.contextFree, SDF3Language.lexical, SDF3Language.kernel:
            parseQualifiedSection(keyword)
        case SDF3Language.syntax, SDF3Language.templates:
            open(.productions(lexical: false), keyword)
        case SDF3Language.sorts:
            open(.sortList(.plainDeclaration), keyword)
        case SDF3Language.startSymbols:
            open(.sortList(nil), keyword)
        case SDF3Language.signature:
            if cursor.check(SDF3Language.sorts) || cursor.check(SDF3Language.constructors) {
                let next = cursor.advance()!
                open(next.text == SDF3Language.sorts ? .sortList(.plainDeclaration) : .signatureConstructors,
                     keyword, last: next)
            } else {
                open(.signature, keyword)
            }
        case SDF3Language.constructors:
            open(.signatureConstructors, keyword)
        case SDF3Language.template:
            let last = cursor.accept(SDF3Language.options)
            open(.skipped, keyword, last: last)
        case SDF3Language.exports, SDF3Language.hiddens:
            break
        default:
            open(.skipped, keyword)
        }
    }

    /// Reads `module name`.
    ///
    /// - Parameter keyword: The `module` keyword.
    private mutating func parseModule(_ keyword: ScannedToken) {
        guard let (name, range) = parseModuleName() else {
            collector.error(
                SDF3DiagnosticCode.expectedToken.rawValue, "Expected a module name after 'module'",
                at: cursor.currentRange)
            return
        }
        if definition.moduleName != nil {
            collector.warning(
                SDF3DiagnosticCode.multipleModules.rawValue,
                "Only one module per source is read; '\(name)' is read as part of the first module", at: range)
            return
        }
        definition.moduleName = name
        moduleNode = OutlineNode(
            id: "module", kind: SDF3OutlineKind.module, name: name, range: keyword.range.union(range),
            selectionRange: range)
        section = .none
    }

    /// Reads the module names that follow `imports`.
    ///
    /// - Parameter keyword: The `imports` keyword.
    private mutating func parseImports(_ keyword: ScannedToken) {
        open(.skipped, keyword)
        while let (name, range) = parseModuleName() {
            definition.imports.append(name)
            addToSection(OutlineNode(
                id: "", kind: SDF3OutlineKind.importedModule, name: name, range: range, selectionRange: range))
        }
        section = .none
    }

    /// Reads a module name such as `syntax/Expressions`, whose parts touch each other.
    ///
    /// The last part may be `-`, which Stratego uses to import every module of a directory.
    ///
    /// - Returns: The name and its source text, or `nil` if no name is current.
    private mutating func parseModuleName() -> (String, SourceRange)? {
        guard let first = cursor.current, first.kind == .identifier, !first.isSectionKeyword else { return nil }
        cursor.advance()
        var name = first.text
        var range = first.range
        while let slash = cursor.current, slash.is("/"), slash.range.start == range.end,
            let part = cursor.peek(1), part.kind == .identifier || part.text == "-",
            part.range.start == slash.range.end
        {
            cursor.advance()
            cursor.advance()
            name += "/" + part.text
            range = range.union(part.range)
        }
        return (name, range)
    }

    /// Reads a section heading that starts with `context-free`, `lexical` or `kernel`.
    ///
    /// - Parameter keyword: The first keyword of the heading.
    private mutating func parseQualifiedSection(_ keyword: ScannedToken) {
        let isLexical = keyword.text == SDF3Language.lexical
        guard let next = cursor.current, next.isSectionKeyword else {
            collector.error(
                SDF3DiagnosticCode.expectedToken.rawValue,
                "Expected 'syntax', 'sorts', 'start-symbols', 'priorities' or 'restrictions' after '\(keyword.text)'",
                at: cursor.currentRange)
            open(.skipped, keyword)
            return
        }
        cursor.advance()
        switch next.text {
        case SDF3Language.syntax:
            open(.productions(lexical: isLexical), keyword, last: next)
        case SDF3Language.sorts:
            open(.sortList(isLexical ? .lexicalDeclaration : .contextFreeDeclaration), keyword, last: next)
        case SDF3Language.startSymbols:
            open(.sortList(nil), keyword, last: next)
        default:
            open(.skipped, keyword, last: next)
        }
    }

    /// Enters a section and adds its outline node.
    ///
    /// - Parameters:
    ///   - newSection: The section to enter.
    ///   - first: The first keyword of the heading.
    ///   - last: The last keyword of the heading, if it has more than one.
    private mutating func open(_ newSection: Section, _ first: ScannedToken, last: ScannedToken? = nil) {
        section = newSection
        let range = first.range.union(last?.range ?? first.range)
        let name = last.map { first.text + " " + $0.text } ?? first.text
        sectionNodes.append(OutlineNode(
            id: "section\(sectionNodes.count)", kind: SDF3OutlineKind.section, name: name, range: range,
            selectionRange: range))
    }

    /// Adds an outline node to the current section, extending the section's range.
    ///
    /// - Parameter node: The node, whose identifier is assigned here.
    private mutating func addToSection(_ node: OutlineNode) {
        var node = node
        guard !sectionNodes.isEmpty else {
            node.id = "item\(looseNodes.count)"
            looseNodes.append(node)
            return
        }
        let index = sectionNodes.count - 1
        node.id = sectionNodes[index].id + "/\(sectionNodes[index].children.count)"
        sectionNodes[index].children.append(node)
        sectionNodes[index].range = sectionNodes[index].range.union(node.range)
    }

    // MARK: Sorts

    /// Reads one sort of a sort list or start symbol list.
    ///
    /// - Parameter evidence: What declaring a sort here says about it, or `nil` for start symbols.
    private mutating func parseSortListEntry(evidence: SDF3SortEvidence?) {
        guard let token = cursor.current, token.kind == .identifier else {
            unexpected(cursor.current!, expectation: "a sort name")
            cursor.advance()
            return
        }
        cursor.advance()
        if let evidence {
            let name = definition.note(token.text, evidence, at: token.range)
            if name != SDF3Language.layoutSort {
                addToSection(OutlineNode(
                    id: "", kind: SDF3OutlineKind.sort, name: name, range: token.range, selectionRange: token.range))
            }
        } else {
            definition.startSymbols.append(SDF3Definition.baseName(token.text))
        }
    }

    // MARK: Productions

    /// Whether the current token starts a new statement: a section heading or a production.
    private var atStatementStart: Bool {
        guard let token = cursor.current else { return true }
        if token.isSectionKeyword { return true }
        guard token.kind == .identifier else { return false }
        if cursor.peek(1)?.is("=") == true { return true }
        return cursor.peek(1)?.is(".") == true && cursor.peek(2)?.kind == .identifier
            && cursor.peek(3)?.is("=") == true
    }

    /// Skips tokens up to the start of the next statement.
    private mutating func skipStatement() {
        cursor.advance()
        while !atStatementStart { cursor.advance() }
    }

    /// Reports a token that the syntax does not allow where it is.
    ///
    /// - Parameters:
    ///   - token: The offending token.
    ///   - expectation: A description of what was expected.
    private mutating func unexpected(_ token: ScannedToken, expectation: String) {
        if !reportLexicalProblem(token) {
            collector.error(
                SDF3DiagnosticCode.unexpectedToken.rawValue,
                "Unexpected '\(token.text)'; expected \(expectation)", at: token.range)
        }
    }

    /// Reports a token that the lexer could not read completely.
    ///
    /// - Parameter token: The token to check.
    /// - Returns: `true` if a problem was reported.
    @discardableResult
    private mutating func reportLexicalProblem(_ token: ScannedToken) -> Bool {
        switch token.kind {
        case .invalid:
            collector.error(
                SDF3DiagnosticCode.invalidCharacter.rawValue, "The character '\(token.text)' cannot start a token",
                at: token.range)
        case .string where !token.isTerminated:
            collector.error(
                SDF3DiagnosticCode.unterminatedString.rawValue, "The string literal has no closing quote",
                at: token.range)
        case .regex where !token.isTerminated:
            collector.error(
                SDF3DiagnosticCode.unterminatedCharacterClass.rawValue, "The character class has no closing ']'",
                at: token.range)
        default:
            return false
        }
        return true
    }

    /// Reads a production `Sort.Constructor = symbols {attributes}` or `Sort = symbols {attributes}`.
    ///
    /// - Parameter lexical: Whether the production is in lexical syntax.
    private mutating func parseProduction(lexical: Bool) {
        guard let sortToken = cursor.current, sortToken.kind == .identifier else {
            unexpected(cursor.current!, expectation: "a production such as 'Sort.Constructor = ...'")
            skipStatement()
            return
        }
        cursor.advance()
        var constructorToken: ScannedToken?
        if cursor.accept(".") != nil {
            guard let name = cursor.accept(.identifier) else {
                collector.error(
                    SDF3DiagnosticCode.expectedToken.rawValue, "Expected a constructor name after '.'",
                    at: cursor.currentRange)
                skipStatement()
                return
            }
            constructorToken = name
        }
        guard cursor.accept("=") != nil else {
            collector.error(
                SDF3DiagnosticCode.expectedToken.rawValue, "Expected '=' after '\(sortToken.text)'",
                at: cursor.currentRange)
            skipStatement()
            return
        }
        if lexical {
            definition.note(sortToken.text, .lexicalProduction, at: sortToken.range)
            while !atStatementStart {
                if let token = cursor.current { reportLexicalProblem(token) }
                cursor.advance()
            }
            return
        }
        let sort = SDF3Definition.baseName(sortToken.text)
        definition.note(sortToken.text, .contextFreeProduction, at: sortToken.range)
        var arguments: [SDF3Argument]
        if let open = cursor.current, open.isMarker(SDF3Language.Marker.templateOpen) {
            arguments = parseTemplate()
        } else {
            arguments = parsePlainSymbols()
        }
        let attributes = parseAttributes()
        while !atStatementStart {
            if let token = cursor.current { unexpected(token, expectation: "the end of the production") }
            cursor.advance()
        }
        let range = cursor.range(from: sortToken.range)
        guard sort != SDF3Language.layoutSort else { return }
        if attributes.names.contains(SDF3Language.bracketAttribute) || attributes.names.contains(SDF3Language.rejectAttribute) {
            return
        }
        arguments = arguments.filter { $0.type.element != .sort(SDF3Language.layoutSort) }
        let constructorName = constructorToken?.text ?? attributes.constructor
        if let constructorName {
            let nameRange = constructorToken?.range ?? sortToken.range
            definition.constructors.append(SDF3Constructor(
                name: constructorName, sort: sort, arguments: arguments, nameRange: nameRange, range: range))
            addToSection(OutlineNode(
                id: "", kind: SDF3OutlineKind.constructor, name: sort + "." + constructorName,
                detail: describe(arguments), range: range, selectionRange: nameRange))
        } else if arguments.count == 1 && arguments[0].type.bounds == (1, 1) {
            definition.injections.append(SDF3Injection(source: arguments[0].type, target: sort, range: range))
            addToSection(OutlineNode(
                id: "", kind: SDF3OutlineKind.injection, name: sort, detail: describe(arguments), range: range,
                selectionRange: sortToken.range))
        } else if !arguments.isEmpty {
            collector.warning(
                SDF3DiagnosticCode.unsupportedSymbol.rawValue,
                "The production of '\(sort)' has no constructor, so its arguments are not represented", at: range)
        }
    }

    /// Reads the symbols of a template, from its opening delimiter to its closing one.
    ///
    /// - Returns: The arguments that the placeholders define.
    private mutating func parseTemplate() -> [SDF3Argument] {
        let open = cursor.advance()!
        var arguments: [SDF3Argument] = []
        while let token = cursor.current {
            if token.isMarker(SDF3Language.Marker.templateClose) {
                cursor.advance()
                return arguments
            }
            if token.isMarker(SDF3Language.Marker.placeholderOpen) {
                cursor.advance()
                if let argument = parsePlaceholder(open: token) { arguments.append(argument) }
            } else {
                cursor.advance()
            }
        }
        collector.error(
            SDF3DiagnosticCode.unterminatedTemplate.rawValue, "The template has no closing '\(closing(of: open))'",
            at: open.range)
        return arguments
    }

    /// The closing delimiter that matches an opening one.
    ///
    /// - Parameter open: The opening delimiter token.
    /// - Returns: `>` for `<` and `]` for `[`.
    private func closing(of open: ScannedToken) -> String { open.text == "<" ? ">" : "]" }

    /// Reads a placeholder after its opening delimiter, up to and including its closing one.
    ///
    /// - Parameter open: The opening delimiter, for diagnostics.
    /// - Returns: The argument, or `nil` if the placeholder holds no sort.
    private mutating func parsePlaceholder(open: ScannedToken) -> SDF3Argument? {
        let argument = parseSymbol()
        var inOptions = false
        var reported = false
        while let token = cursor.current {
            if token.isMarker(SDF3Language.Marker.placeholderClose) {
                cursor.advance()
                return argument
            }
            if token.isMarker(SDF3Language.Marker.templateClose) || token.isMarker(SDF3Language.Marker.placeholderOpen) {
                break
            }
            if token.is(";") {
                // Placeholder options such as `; hide` do not change the abstract syntax.
                inOptions = true
            } else if !inOptions && !reported {
                unexpected(token, expectation: "'\(closing(of: open))'")
                reported = true
            }
            cursor.advance()
        }
        collector.error(
            SDF3DiagnosticCode.unterminatedPlaceholder.rawValue,
            "The placeholder has no closing '\(closing(of: open))'", at: open.range)
        return argument
    }

    /// Reads the symbols of a plain production up to its attributes or the next statement.
    ///
    /// - Returns: The arguments that the sort symbols define.
    private mutating func parsePlainSymbols() -> [SDF3Argument] {
        var arguments: [SDF3Argument] = []
        while !atStatementStart, !isAttributeBlock {
            let before = cursor.index
            if let argument = parseSymbol() { arguments.append(argument) }
            if cursor.index == before {
                if let token = cursor.current { unexpected(token, expectation: "a symbol") }
                cursor.advance()
            }
        }
        return arguments
    }

    /// Whether the current `{` opens production attributes rather than a list symbol.
    ///
    /// A list symbol `{Exp ","}*` ends in `}` followed by `*` or `+`.
    private var isAttributeBlock: Bool {
        guard cursor.check("{") else { return false }
        var distance = 1
        while let token = cursor.peek(distance), !token.is("}") {
            if token.isSectionKeyword { return true }
            distance += 1
        }
        guard let after = cursor.peek(distance + 1) else { return true }
        return !(after.is("*") || after.is("+"))
    }

    /// Reads one symbol, with an optional label and postfix operators.
    ///
    /// - Returns: The argument the symbol defines, or `nil` for a literal,
    ///   a character class or a symbol that cannot be represented.
    private mutating func parseSymbol() -> SDF3Argument? {
        guard let start = cursor.current else { return nil }
        var label: String?
        if start.kind == .identifier, cursor.peek(1)?.is(":") == true {
            label = start.text
            cursor.advance()
            cursor.advance()
        }
        guard let token = cursor.current else { return nil }
        var type: SDF3Type?
        if token.kind == .identifier && !token.isSectionKeyword {
            cursor.advance()
            type = .sort(SDF3Definition.baseName(token.text))
            definition.note(token.text, .reference, at: token.range)
        } else if token.kind == .string || token.kind == .regex {
            reportLexicalProblem(token)
            cursor.advance()
        } else if token.is("{") {
            type = parseListSymbol()
        } else if token.is("(") {
            parseGroup()
        } else if token.is("~") {
            cursor.advance()
            _ = parseSymbol()
        } else {
            return nil
        }
        while let postfix = cursor.current, postfix.is("?") || postfix.is("*") || postfix.is("+") {
            cursor.advance()
            guard let inner = type else { continue }
            switch postfix.text {
            case "?": type = .optional(inner)
            case "*": type = .list(inner, atLeastOne: false)
            default: type = .list(inner, atLeastOne: true)
            }
        }
        guard let type else { return nil }
        return SDF3Argument(type: type, label: label, range: cursor.range(from: start.range))
    }

    /// Reads a separated list symbol `{Exp ","}*` or `{Exp ","}+`.
    ///
    /// - Returns: The list type, or `nil` if the element is not a sort.
    private mutating func parseListSymbol() -> SDF3Type? {
        let open = cursor.advance()!
        let element = parseSymbol()
        while let token = cursor.current, !token.is("}") {
            if token.isSectionKeyword || token.isMarker(SDF3Language.Marker.placeholderClose) { break }
            if token.kind != .string { unexpected(token, expectation: "a separator literal or '}'") }
            cursor.advance()
        }
        guard cursor.accept("}") != nil else {
            collector.error(
                SDF3DiagnosticCode.expectedToken.rawValue, "The list symbol has no closing '}'", at: open.range)
            return nil
        }
        let atLeastOne = cursor.check("+")
        guard cursor.accept("*") != nil || cursor.accept("+") != nil else {
            collector.error(
                SDF3DiagnosticCode.expectedToken.rawValue, "Expected '*' or '+' after the list symbol",
                at: cursor.currentRange)
            return nil
        }
        guard let element else { return nil }
        return .list(element.type, atLeastOne: atLeastOne)
    }

    /// Skips a parenthesised sequence of symbols, warning if it holds sorts.
    private mutating func parseGroup() {
        let open = cursor.advance()!
        var holdsSorts = false
        while let token = cursor.current, !token.is(")") {
            if atStatementStart { break }
            if parseSymbol() != nil { holdsSorts = true } else if cursor.current?.is(")") != true { cursor.advance() }
        }
        if cursor.accept(")") == nil {
            collector.error(SDF3DiagnosticCode.expectedToken.rawValue, "The sequence has no closing ')'", at: open.range)
        }
        if holdsSorts {
            collector.warning(
                SDF3DiagnosticCode.unsupportedSymbol.rawValue,
                "Sequences of symbols are not represented as features", at: cursor.range(from: open.range))
        }
    }

    /// The attributes of a production.
    private struct Attributes {
        /// The attribute names, such as `left` or `bracket`.
        var names: Set<String> = []
        /// The constructor that an SDF2 `cons("Name")` attribute gives.
        var constructor: String?
    }

    /// Reads production attributes such as `{left, prefer}`, if present.
    ///
    /// - Returns: The attributes, empty when there are none.
    private mutating func parseAttributes() -> Attributes {
        var result = Attributes()
        guard isAttributeBlock, let open = cursor.advance() else { return result }
        while let token = cursor.current, !token.is("}") {
            if token.isSectionKeyword { break }
            cursor.advance()
            guard token.kind == .identifier else { continue }
            result.names.insert(token.text)
            if cursor.check("(") {
                cursor.advance()
                if token.text == SDF3Language.consAttribute, let name = cursor.accept(.string) {
                    result.constructor = name.value
                }
                while let inner = cursor.current, !inner.is(")"), !inner.is("}") { cursor.advance() }
                cursor.accept(")")
            }
        }
        if cursor.accept("}") == nil {
            collector.error(SDF3DiagnosticCode.expectedToken.rawValue, "The attributes have no closing '}'", at: open.range)
        }
        return result
    }

    // MARK: Stratego signatures

    /// Whether the current token starts a signature entry or a section.
    private var atSignatureEntryStart: Bool {
        guard let token = cursor.current else { return true }
        if token.isSectionKeyword || token.is(":") { return true }
        return token.kind == .identifier && cursor.peek(1)?.is(":") == true
    }

    /// Reads a signature entry `Name : T1 * T2 -> Sort`, `Name : Sort` or `: T -> Sort`.
    private mutating func parseSignatureEntry() {
        guard let first = cursor.current else { return }
        var nameToken: ScannedToken?
        if first.kind == .identifier || first.kind == .string, cursor.peek(1)?.is(":") == true {
            nameToken = cursor.advance()
        } else if !first.is(":") {
            unexpected(first, expectation: "a constructor declaration such as 'Name : Sort'")
            cursor.advance()
            while !atSignatureEntryStart { cursor.advance() }
            return
        }
        cursor.advance()
        var arguments: [(SDF3Type, SourceRange)] = []
        let typeStart = cursor.currentRange
        guard let firstType = parseType() else {
            recoverSignatureEntry("Expected a type after ':'")
            return
        }
        arguments.append((firstType, cursor.range(from: typeStart)))
        while cursor.check("*") {
            cursor.advance()
            let start = cursor.currentRange
            guard let type = parseType() else {
                recoverSignatureEntry("Expected a type after '*'")
                return
            }
            arguments.append((type, cursor.range(from: start)))
        }
        var resultType: SDF3Type
        var resultRange: SourceRange
        if cursor.accept("->") != nil {
            let start = cursor.currentRange
            guard let type = parseType() else {
                recoverSignatureEntry("Expected the result sort after '->'")
                return
            }
            resultType = type
            resultRange = cursor.range(from: start)
        } else if arguments.count == 1 && nameToken != nil {
            (resultType, resultRange) = arguments.removeFirst()
        } else {
            recoverSignatureEntry("Expected '->' and the result sort")
            return
        }
        let range = cursor.range(from: first.range)
        if case .variable(let name) = resultType { resultType = .sort(name) }
        guard case .sort(let resultSort) = resultType else {
            collector.warning(
                SDF3DiagnosticCode.unsupportedSymbol.rawValue,
                "The result of a signature entry must be a sort", at: resultRange)
            return
        }
        let isGenerated = resultSort == SDF3Language.completionSort
            || nameToken?.value.hasSuffix(SDF3Language.placeholderSuffix) == true
            || arguments.contains { $0.0.element == .sort(SDF3Language.completionSort) }
        guard !isGenerated else { return }
        let detail = arguments.map { describe($0.0) }.joined(separator: " * ")
            + (arguments.isEmpty ? "" : " -> ") + resultSort
        if let nameToken {
            definition.note(resultSort, .contextFreeProduction, at: resultRange)
            for (type, range) in arguments { noteReferences(type, at: range) }
            definition.constructors.append(SDF3Constructor(
                name: nameToken.value, sort: SDF3Definition.baseName(resultSort),
                arguments: arguments.map { SDF3Argument(type: $0.0, label: nil, range: $0.1) },
                nameRange: nameToken.range, range: range))
            addToSection(OutlineNode(
                id: "", kind: SDF3OutlineKind.constructor, name: nameToken.value, detail: detail, range: range,
                selectionRange: nameToken.range))
        } else {
            guard arguments.count == 1 else {
                collector.warning(
                    SDF3DiagnosticCode.unsupportedSymbol.rawValue, "An injection takes exactly one type", at: range)
                return
            }
            let source = arguments[0].0
            if case .builtin = source {
                definition.note(resultSort, .lexicalInjection, at: resultRange)
            } else {
                definition.note(resultSort, .contextFreeProduction, at: resultRange)
                noteReferences(source, at: arguments[0].1)
            }
            definition.injections.append(SDF3Injection(
                source: source, target: SDF3Definition.baseName(resultSort), range: range))
            addToSection(OutlineNode(
                id: "", kind: SDF3OutlineKind.injection, name: resultSort, detail: detail, range: range,
                selectionRange: resultRange))
        }
    }

    /// Records the sorts that a signature type refers to.
    ///
    /// - Parameters:
    ///   - type: The type.
    ///   - range: The source text of the type.
    private mutating func noteReferences(_ type: SDF3Type, at range: SourceRange) {
        if case .sort(let name) = type.element { definition.note(name, .reference, at: range) }
    }

    /// Reports a malformed signature entry and skips to the next entry.
    ///
    /// - Parameter message: The description of what was expected.
    private mutating func recoverSignatureEntry(_ message: String) {
        collector.error(SDF3DiagnosticCode.expectedToken.rawValue, message, at: cursor.currentRange)
        while !atSignatureEntryStart { cursor.advance() }
    }

    /// Reads a Stratego type: a sort, a built-in type, a type variable,
    /// `List(T)`, `Option(T)` or a parenthesised tuple.
    ///
    /// - Returns: The type, or `nil` if no type is current.
    private mutating func parseType() -> SDF3Type? {
        guard let token = cursor.current else { return nil }
        if token.is("(") {
            cursor.advance()
            var parts: [SDF3Type] = []
            while let part = parseType() {
                parts.append(part)
                guard cursor.accept("*") != nil || cursor.accept(",") != nil else { break }
            }
            if cursor.accept(")") == nil {
                collector.error(SDF3DiagnosticCode.expectedToken.rawValue, "Expected ')'", at: cursor.currentRange)
            }
            return parts.count == 1 ? parts[0] : .unsupported("tuple")
        }
        guard token.kind == .identifier, !token.isSectionKeyword else { return nil }
        cursor.advance()
        if cursor.check("(") {
            cursor.advance()
            var parameters: [SDF3Type] = []
            while let parameter = parseType() {
                parameters.append(parameter)
                guard cursor.accept(",") != nil else { break }
            }
            if cursor.accept(")") == nil {
                collector.error(SDF3DiagnosticCode.expectedToken.rawValue, "Expected ')'", at: cursor.currentRange)
            }
            switch (token.text, parameters.count) {
            case (SDF3Language.listType, 1): return .list(parameters[0], atLeastOne: false)
            case (SDF3Language.optionType, 1): return .optional(parameters[0])
            default: return .unsupported(token.text)
            }
        }
        if SDF3Language.builtinTypes[token.text] != nil { return .builtin(token.text) }
        if token.text.first?.isLowercase == true { return .variable(token.text) }
        return .sort(SDF3Definition.baseName(token.text))
    }

    // MARK: Descriptions

    /// A short description of a list of arguments, for outline details.
    ///
    /// - Parameter arguments: The arguments.
    /// - Returns: The argument types separated by `*`, or `nil` if there are none.
    private func describe(_ arguments: [SDF3Argument]) -> String? {
        arguments.isEmpty ? nil : arguments.map { describe($0.type) }.joined(separator: " * ")
    }

    /// A short description of a type in Stratego notation.
    ///
    /// - Parameter type: The type.
    /// - Returns: The description, such as `List(Exp)`.
    private func describe(_ type: SDF3Type) -> String {
        switch type {
        case .sort(let name), .builtin(let name), .variable(let name), .unsupported(let name): name
        case .list(let inner, _): SDF3Language.listType + "(" + describe(inner) + ")"
        case .optional(let inner): SDF3Language.optionType + "(" + describe(inner) + ")"
        }
    }
}
