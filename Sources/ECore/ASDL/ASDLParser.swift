//
// ASDLParser.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// A field of a constructor or product type, or an attribute.
struct ASDLField: Sendable, Hashable {
    /// The module that qualifies the type name, as in `M.t`, if any.
    var module: String?

    /// The name of the field's type.
    var typeName: String

    /// The quantifiers as written, such as `?`, `*` or `?*`.
    var quantifiers: String

    /// The name of the field, if given.
    var name: String?

    /// The whole field.
    var range: SourceRange

    /// The type name.
    var typeRange: SourceRange

    /// The field name, if given, otherwise the type name.
    var nameRange: SourceRange
}

/// A constructor of a sum type.
struct ASDLConstructor: Sendable, Hashable {
    /// The name of the constructor.
    var name: String

    /// The fields, in order.
    var fields: [ASDLField]

    /// The whole constructor.
    var range: SourceRange

    /// The constructor name.
    var nameRange: SourceRange
}

/// The right-hand side of a type definition.
enum ASDLTypeBody: Sendable, Hashable {
    /// A sum of constructors.
    case sum([ASDLConstructor])
    /// A product of fields.
    case product([ASDLField])
}

/// A type definition.
struct ASDLDefinition: Sendable, Hashable {
    /// The name of the type.
    var name: String

    /// The constructors or fields.
    var body: ASDLTypeBody

    /// The attributes, in order.
    var attributes: [ASDLField]

    /// The whole definition.
    var range: SourceRange

    /// The type name.
    var nameRange: SourceRange
}

/// A module.
struct ASDLModule: Sendable, Hashable {
    /// The name of the module.
    var name: String

    /// The version string, if declared.
    var version: String?

    /// The modules imported in the asdlGen dialect.
    var imports: [String]

    /// The type definitions, in order.
    var definitions: [ASDLDefinition]

    /// The whole module.
    var range: SourceRange

    /// The module name.
    var nameRange: SourceRange
}

/// A recursive-descent parser for ASDL that recovers from errors.
///
/// The parser accepts the grammar of the
/// [ASDL paper](https://www.usenix.org/conference/dsl-97/zephyr-abstract-syntax-description-language)
/// and CPython's dialect,
/// which adds attributes on product types and repeated quantifiers, together
/// with a module's `version` string, several modules in one text, the
/// asdlGen import list `module M (imports N) { ... }` and qualified type
/// names `N.t`. On an unexpected token it reports an error and resumes at the
/// next definition.
struct ASDLParser {
    /// The significant tokens.
    private var cursor: GrammarTokenCursor

    /// The diagnostics found so far.
    private(set) var collector: DiagnosticCollector

    /// The refined kinds of tokens, by the UTF-8 offset at which they start.
    private(set) var roles: [Int: SourceTokenKind] = [:]

    /// Prepares to parse.
    ///
    /// - Parameters:
    ///   - tokens: All tokens of the text, including comments.
    ///   - endRange: The empty range at the end of the text.
    ///   - document: The identifier of the document, for diagnostics.
    init(tokens: [ScannedToken], endRange: SourceRange, document: String?) {
        cursor = GrammarTokenCursor(tokens, endRange: endRange)
        collector = DiagnosticCollector(document: document)
    }

    /// Parses every module of the text.
    ///
    /// - Returns: The modules in source order.
    mutating func parseModules() -> [ASDLModule] {
        var modules: [ASDLModule] = []
        while let token = cursor.current {
            if token.is(ASDLSyntax.Keyword.module) {
                modules.append(parseModule())
            } else {
                collector.error(
                    ASDLDiagnosticCode.unexpectedToken.rawValue,
                    "Expected 'module' but found '\(token.text)'", at: token.range)
                cursor.advance()
                cursor.skip(until: [ASDLSyntax.Keyword.module])
            }
        }
        if modules.isEmpty {
            collector.error(
                ASDLDiagnosticCode.missingModule.rawValue, "The text has no module declaration",
                at: cursor.endRange)
        }
        return modules
    }

    /// Parses a module, starting at its keyword.
    ///
    /// - Returns: The module, with every definition that could be read.
    private mutating func parseModule() -> ASDLModule {
        let keyword = cursor.advance()!
        roles[keyword.range.start.utf8Offset] = .keyword
        var name = ""
        var nameRange = cursor.currentRange
        if let identifier = cursor.accept(.identifier) {
            name = identifier.value
            nameRange = identifier.range
            roles[identifier.range.start.utf8Offset] = .typeName
        } else {
            expected("a module name")
        }
        var version: String?
        if let versionKeyword = cursor.accept(ASDLSyntax.Keyword.version) {
            roles[versionKeyword.range.start.utf8Offset] = .keyword
            if let text = cursor.accept(.string) {
                version = text.value
            } else {
                expected("a version string")
            }
        }
        var imports: [String] = []
        if cursor.accept(ASDLSyntax.Symbol.openParenthesis) != nil {
            while let token = cursor.current, !token.is(ASDLSyntax.Symbol.closeParenthesis),
                !token.is(ASDLSyntax.Symbol.openBrace)
            {
                cursor.advance()
                guard token.kind == .identifier else { continue }
                if token.text == ASDLSyntax.Keyword.imports {
                    roles[token.range.start.utf8Offset] = .keyword
                } else {
                    roles[token.range.start.utf8Offset] = .typeName
                    imports.append(token.value)
                }
            }
            if cursor.accept(ASDLSyntax.Symbol.closeParenthesis) == nil { expected("')'") }
        }
        var definitions: [ASDLDefinition] = []
        if cursor.accept(ASDLSyntax.Symbol.openBrace) == nil {
            expected("'{'")
        }
        while let token = cursor.current, !token.is(ASDLSyntax.Symbol.closeBrace) {
            if token.is(ASDLSyntax.Keyword.module) && cursor.peek(1)?.kind == .identifier { break }
            if let definition = parseDefinition() {
                definitions.append(definition)
            } else {
                synchronise()
            }
        }
        if cursor.accept(ASDLSyntax.Symbol.closeBrace) == nil { expected("'}' to close module '\(name)'") }
        return ASDLModule(
            name: name, version: version, imports: imports, definitions: definitions,
            range: cursor.range(from: keyword.range), nameRange: nameRange)
    }

    /// Parses a type definition.
    ///
    /// - Returns: The definition, or `nil` after reporting an error.
    private mutating func parseDefinition() -> ASDLDefinition? {
        guard let name = cursor.accept(.identifier) else {
            expected("a type name")
            return nil
        }
        roles[name.range.start.utf8Offset] = .typeName
        checkConvention(name, isType: true)
        guard cursor.accept(ASDLSyntax.Symbol.equals) != nil else {
            expected("'=' after type name '\(name.value)'")
            return nil
        }
        let body: ASDLTypeBody
        if cursor.check(ASDLSyntax.Symbol.openParenthesis) {
            guard let fields = parseFields(kind: "field") else { return nil }
            body = .product(fields)
        } else {
            var constructors: [ASDLConstructor] = []
            repeat {
                guard let constructor = parseConstructor() else { return nil }
                constructors.append(constructor)
            } while cursor.accept(ASDLSyntax.Symbol.bar) != nil
            body = .sum(constructors)
        }
        var attributes: [ASDLField] = []
        if let keyword = cursor.accept(ASDLSyntax.Keyword.attributes) {
            roles[keyword.range.start.utf8Offset] = .keyword
            guard let fields = parseFields(kind: "attribute") else { return nil }
            attributes = fields
        }
        return ASDLDefinition(
            name: name.value, body: body, attributes: attributes, range: cursor.range(from: name.range),
            nameRange: name.range)
    }

    /// Parses a constructor and its optional fields.
    ///
    /// - Returns: The constructor, or `nil` after reporting an error.
    private mutating func parseConstructor() -> ASDLConstructor? {
        guard let name = cursor.accept(.identifier) else {
            expected("a constructor name")
            return nil
        }
        roles[name.range.start.utf8Offset] = .identifier
        checkConvention(name, isType: false)
        var fields: [ASDLField] = []
        if cursor.check(ASDLSyntax.Symbol.openParenthesis) {
            guard let parsed = parseFields(kind: "field") else { return nil }
            fields = parsed
        }
        return ASDLConstructor(
            name: name.value, fields: fields, range: cursor.range(from: name.range), nameRange: name.range)
    }

    /// Parses a parenthesised list of fields.
    ///
    /// - Parameter kind: What the fields are, for messages.
    /// - Returns: The fields, or `nil` after reporting an error.
    private mutating func parseFields(kind: String) -> [ASDLField]? {
        let open = cursor.advance()!
        if open.text != ASDLSyntax.Symbol.openParenthesis {
            expected("'('")
            return nil
        }
        var fields: [ASDLField] = []
        if let close = cursor.accept(ASDLSyntax.Symbol.closeParenthesis) {
            collector.warning(
                ASDLDiagnosticCode.emptyFields.rawValue, "An empty \(kind) list is not valid ASDL",
                at: SourceRange(start: open.range.start, end: close.range.end))
            return fields
        }
        repeat {
            guard let field = parseField() else { return nil }
            fields.append(field)
        } while cursor.accept(ASDLSyntax.Symbol.comma) != nil
        guard cursor.accept(ASDLSyntax.Symbol.closeParenthesis) != nil else {
            expected("',' or ')' in \(kind) list")
            return nil
        }
        return fields
    }

    /// Parses a field: a possibly qualified type, quantifiers and an optional name.
    ///
    /// - Returns: The field, or `nil` after reporting an error.
    private mutating func parseField() -> ASDLField? {
        guard var type = cursor.accept(.identifier) else {
            expected("a field type")
            return nil
        }
        let start = type.range
        var module: String?
        if cursor.check(ASDLSyntax.Symbol.dot), cursor.peek(1)?.kind == .identifier {
            cursor.advance()
            roles[type.range.start.utf8Offset] = .typeName
            module = type.value
            type = cursor.advance()!
        }
        roles[type.range.start.utf8Offset] = .typeName
        var quantifiers = ""
        while let token = cursor.current,
            token.is(ASDLSyntax.Symbol.optional) || token.is(ASDLSyntax.Symbol.sequence)
        {
            quantifiers += token.text
            cursor.advance()
        }
        var name: String?
        var nameRange = type.range
        if let identifier = cursor.accept(.identifier) {
            name = identifier.value
            nameRange = identifier.range
            roles[identifier.range.start.utf8Offset] = .identifier
        }
        return ASDLField(
            module: module, typeName: type.value, quantifiers: quantifiers, name: name,
            range: cursor.range(from: start), typeRange: type.range, nameRange: nameRange)
    }

    /// Warns about a name that breaks ASDL's naming convention.
    ///
    /// - Parameters:
    ///   - token: The name.
    ///   - isType: Whether the name is a type, which starts in lower case, or a
    ///     constructor, which starts in upper case.
    private mutating func checkConvention(_ token: ScannedToken, isType: Bool) {
        guard let first = token.value.first, first.isLetter, first.isUppercase == isType else { return }
        collector.warning(
            ASDLDiagnosticCode.namingConvention.rawValue,
            isType
                ? "The type name '\(token.value)' should start with a lower-case letter"
                : "The constructor name '\(token.value)' should start with an upper-case letter",
            at: token.range)
    }

    /// Reports that the current token is not what the grammar expects.
    ///
    /// Characters that cannot start a token and unterminated strings are not
    /// reported again, since scanning reports them.
    ///
    /// - Parameter what: A description of what was expected.
    private mutating func expected(_ what: String) {
        if let token = cursor.current {
            // Lexical problems are reported once, when the text is scanned.
            guard token.kind != .invalid, token.isTerminated else { return }
            collector.error(
                ASDLDiagnosticCode.unexpectedToken.rawValue, "Expected \(what) but found '\(token.text)'",
                at: token.range)
        } else {
            collector.error(
                ASDLDiagnosticCode.unexpectedToken.rawValue, "Expected \(what) but the text ended",
                at: cursor.endRange)
        }
    }

    /// Skips to the start of the next definition, the end of the module or the next module.
    ///
    /// A failed definition has always consumed at least its name unless the
    /// current token cannot start one, so stopping at a definition that starts
    /// at the current token cannot loop.
    private mutating func synchronise() {
        if !startsDefinition() && !cursor.isAtEnd { cursor.advance() }
        while let token = cursor.current {
            if token.is(ASDLSyntax.Symbol.closeBrace) || token.is(ASDLSyntax.Keyword.module) { return }
            if startsDefinition() { return }
            cursor.advance()
        }
    }

    /// Whether the current token is a type name followed by `=`.
    ///
    /// - Returns: `true` if a definition starts at the current token.
    private func startsDefinition() -> Bool {
        cursor.check(.identifier) && cursor.peek(1)?.is(ASDLSyntax.Symbol.equals) == true
    }
}
