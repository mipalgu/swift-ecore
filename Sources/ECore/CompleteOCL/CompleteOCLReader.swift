//
// CompleteOCLReader.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OCL

/// The result of reading a Complete OCL document.
public struct CompleteOCLParseResult: Sendable {
    /// The document, with every declaration that could be read.
    public var document: CompleteOCLDocument

    /// The problems found, in source order.
    public var diagnostics: [SourceDiagnostic]

    /// The lexical tokens of the document, including comments.
    public var tokens: [SourceToken]

    /// The outline of the document: imports, packages, contexts and their constraints, in source order.
    public var outline: [OutlineNode]

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - document: The document.
    ///   - diagnostics: The problems found.
    ///   - tokens: The lexical tokens.
    ///   - outline: The outline.
    public init(document: CompleteOCLDocument, diagnostics: [SourceDiagnostic], tokens: [SourceToken], outline: [OutlineNode]) {
        self.document = document
        self.diagnostics = diagnostics
        self.tokens = tokens
        self.outline = outline
    }

    /// Whether the document was read without errors.
    public var isValid: Bool { !diagnostics.contains { $0.severity == .error } }
}

/// Reads Complete OCL documents.
///
/// Complete OCL adds constraints to existing metamodels: `context` declarations name a
/// classifier, operation or property, optionally inside `package ... endpackage`, and list its
/// invariants (`inv`), definitions (`def`), preconditions (`pre`), postconditions (`post`),
/// bodies (`body`), initial values (`init`) and derivations (`derive`). The reader follows the
/// Eclipse OCL grammar and also accepts the OMG form `context name : Type inv: ...`. Each
/// expression is parsed, to find where it ends and to report errors, and kept verbatim.
///
/// Use ``CompleteOCLApplier`` to add the constraints of a document to Ecore packages.
public enum CompleteOCLReader {
    /// Reads a Complete OCL document.
    ///
    /// - Parameters:
    ///   - text: The document.
    ///   - sourceName: The name of the document, attached to each diagnostic.
    /// - Returns: The document, diagnostics, tokens and outline.
    public static func parse(_ text: String, sourceName: String? = nil) -> CompleteOCLParseResult {
        let tokenisation = OCLLexer.tokenise(text)
        var parser = Parser(cursor: OCLTokenCursor(tokens: tokenisation.significantTokens, source: text), document: sourceName)
        parser.parseDocument()
        var diagnostics = tokenisation.diagnostics.map { diagnostic in
            var located = diagnostic
            located.document = sourceName
            return located
        }
        for diagnostic in parser.diagnostics
        where !diagnostics.contains(where: { $0.range == diagnostic.range && $0.code == diagnostic.code }) {
            diagnostics.append(diagnostic)
        }
        diagnostics.sort { ($0.range?.start.utf8Offset ?? 0) < ($1.range?.start.utf8Offset ?? 0) }
        return CompleteOCLParseResult(
            document: parser.result, diagnostics: diagnostics,
            tokens: OCLTokenClassifier.sourceTokens(of: tokenisation.tokens, keywords: CompleteOCLSyntax.keywords),
            outline: parser.outline)
    }

    /// The parser state.
    struct Parser {
        /// The vocabulary of Complete OCL.
        typealias Syntax = CompleteOCLSyntax
        /// The kinds of outline node.
        typealias Kind = CompleteOCLOutlineKind

        /// The tokens being read.
        var cursor: OCLTokenCursor
        /// The name of the document, attached to each diagnostic.
        let document: String?
        /// The diagnostics collected so far.
        var diagnostics: [SourceDiagnostic] = []
        /// The document being built.
        var result = CompleteOCLDocument()
        /// The outline nodes of the top-level declarations.
        var outline: [OutlineNode] = []
        /// The parser of the expressions inside constraints.
        let expressions = OCLExpressionParser(allowsMessages: true)

        /// Creates a parser.
        ///
        /// - Parameters:
        ///   - cursor: The tokens to read.
        ///   - document: The name of the document, attached to each diagnostic.
        init(cursor: OCLTokenCursor, document: String?) {
            self.cursor = cursor
            self.document = document
        }

        /// Records a syntax error unless one is already recorded at the same place.
        ///
        /// - Parameters:
        ///   - error: The syntax error.
        ///   - code: A diagnostic code that replaces the one of the error, if any.
        mutating func report(_ error: OCLSyntaxError, code: String? = nil) {
            var diagnostic = error.diagnostic
            diagnostic.document = document
            if let code { diagnostic.code = code }
            if !diagnostics.contains(where: { $0.range == diagnostic.range }) { diagnostics.append(diagnostic) }
        }

        /// Whether the current token starts a constraint or declaration.
        var atDeclaration: Bool {
            cursor.current.kind == .identifier && Syntax.declarationKeywords.contains(cursor.current.text)
        }

        /// Skips to the next declaration keyword after an error.
        mutating func recover(from start: Int) {
            while !cursor.isAtEnd {
                if cursor.position > start, atDeclaration { return }
                cursor.advance()
            }
        }

        // MARK: Document

        /// Reads every declaration of the document, recovering from errors at the next declaration.
        mutating func parseDocument() {
            var packagePath: [String] = []
            var packageStart: SourcePosition?
            var packageChildren: [OutlineNode] = []
            var packageNameRange: SourceRange?
            while !cursor.isAtEnd {
                let start = cursor.position
                do {
                    if cursor.at(word: Syntax.importKeyword) || cursor.at(word: Syntax.includeKeyword)
                        || cursor.at(word: Syntax.libraryKeyword)
                    {
                        let anImport = try parseImport()
                        result.imports.append(anImport)
                        if let range = anImport.range {
                            outline.append(OutlineNode(
                                id: Kind.import + ":" + anImport.target, kind: Kind.import, name: anImport.alias ?? anImport.target,
                                detail: anImport.target, range: range, selectionRange: range))
                        }
                    } else if cursor.at(word: Syntax.packageKeyword) {
                        if !packagePath.isEmpty { throw cursor.error("Expected 'endpackage'") }
                        packageStart = cursor.startPosition
                        cursor.advance()
                        let nameStart = cursor.startPosition
                        packagePath = try parsePath("package name")
                        packageNameRange = cursor.range(from: nameStart)
                        while cursor.at(word: Syntax.invKeyword) {
                            let range = cursor.current.range
                            cursor.advance()
                            _ = try parseConstraint()
                            diagnostics.append(SourceDiagnostic(
                                severity: .warning, code: OCLDiagnosticCode.unsupportedConstruct,
                                message: "Package invariants have no counterpart in Ecore", range: range, document: document))
                        }
                    } else if cursor.at(word: Syntax.endpackageKeyword) {
                        guard let start = packageStart, let nameRange = packageNameRange else {
                            throw cursor.error("Expected 'context' or 'package'")
                        }
                        cursor.advance()
                        let range = cursor.range(from: start)
                        result.packages.append(CompleteOCLPackageDeclaration(path: packagePath, range: range))
                        outline.append(OutlineNode(
                            id: Kind.package + ":" + packagePath.joined(separator: "::"), kind: Kind.package,
                            name: packagePath.joined(separator: "::"), range: range, selectionRange: nameRange,
                            children: packageChildren))
                        packagePath = []
                        packageChildren = []
                        packageStart = nil
                    } else if cursor.at(word: Syntax.contextKeyword) {
                        let node = try parseContext(packagePath: packagePath)
                        if packagePath.isEmpty { outline.append(node) } else { packageChildren.append(node) }
                    } else {
                        throw cursor.error("Expected 'import', 'package' or 'context'")
                    }
                } catch let error as OCLSyntaxError {
                    report(error)
                    recover(from: start)
                } catch {}
            }
            if !packagePath.isEmpty {
                report(cursor.error("Expected 'endpackage'"))
                if let start = packageStart, let nameRange = packageNameRange {
                    let range = cursor.range(from: start)
                    result.packages.append(CompleteOCLPackageDeclaration(path: packagePath, range: range))
                    outline.append(OutlineNode(
                        id: Kind.package + ":" + packagePath.joined(separator: "::"), kind: Kind.package,
                        name: packagePath.joined(separator: "::"), range: range, selectionRange: nameRange, children: packageChildren))
                }
            }
        }

        /// Reads a name path separated by `::`.
        ///
        /// - Parameter description: A description of the expected name, used in error messages.
        /// - Returns: The segments of the path.
        /// - Throws: ``OCLSyntaxError`` if a name is missing.
        mutating func parsePath(_ description: String) throws -> [String] {
            var path = [try cursor.expectName(description)]
            while cursor.at(symbol: OCLSyntax.pathSeparator) {
                cursor.advance()
                path.append(try cursor.expectName("name after '::'"))
            }
            return path
        }

        /// Reads an `import`, `include` or `library` declaration.
        ///
        /// - Returns: The import.
        /// - Throws: ``OCLSyntaxError`` if the declaration is malformed.
        mutating func parseImport() throws -> CompleteOCLImport {
            let start = cursor.startPosition
            let keyword = cursor.current.text
            cursor.advance()
            var alias: String?
            if cursor.current.isName, cursor.peek().isSymbol(":") {
                alias = cursor.current.value
                cursor.advance()
                cursor.advance()
            }
            var target: String
            if cursor.current.kind == .string {
                target = cursor.current.value
                cursor.advance()
            } else {
                target = try cursor.expectName("imported name")
            }
            var isAll = false
            while cursor.accept(symbol: OCLSyntax.pathSeparator) {
                if cursor.accept(symbol: "*") {
                    isAll = true
                    break
                }
                target += OCLSyntax.pathSeparator + (try cursor.expectName("name after '::'"))
            }
            cursor.accept(symbol: ";")
            return CompleteOCLImport(keyword: keyword, alias: alias, target: target, isAll: isAll, range: cursor.range(from: start))
        }

        // MARK: Contexts

        /// Skips a template signature in parentheses or angle brackets.
        ///
        /// - Throws: ``OCLSyntaxError`` if the signature is not closed.
        mutating func skipTemplateSignature() throws {
            guard cursor.at(symbol: "(") || cursor.at(symbol: "<") else { return }
            let closing = cursor.at(symbol: "(") ? ")" : ">"
            cursor.advance()
            while !cursor.accept(symbol: closing) {
                if cursor.isAtEnd { throw cursor.error("Expected '\(closing)'") }
                cursor.advance()
            }
        }

        /// Reads a `context` declaration and its constraints.
        ///
        /// - Parameter packagePath: The path of the enclosing package.
        /// - Returns: The outline node of the context.
        /// - Throws: ``OCLSyntaxError`` if the declaration is malformed.
        mutating func parseContext(packagePath: [String]) throws -> OutlineNode {
            let start = cursor.startPosition
            try cursor.expect(word: Syntax.contextKeyword)
            if cursor.at(symbol: "<") { try skipTemplateSignature() }
            var nameStart = cursor.startPosition
            var path = try parsePath("context name")
            var nameRange = cursor.range(from: nameStart)
            var selfName: String?
            if cursor.at(symbol: "(") {
                return try parseOperationContext(packagePath: packagePath, path: path, start: start, nameRange: nameRange)
            }
            if cursor.accept(symbol: ":") {
                let typeStart = cursor.startPosition
                let type = try expressions.parseType(&cursor)
                if cursor.at(word: Syntax.invKeyword) || cursor.at(word: Syntax.defKeyword) || cursor.at(word: Syntax.staticKeyword) {
                    guard path.count == 1 else { throw cursor.error("Expected 'init' or 'derive'") }
                    selfName = path[0]
                    path = type.path
                    nameRange = cursor.range(from: typeStart)
                } else {
                    return try parsePropertyContext(packagePath: packagePath, path: path, type: type, start: start, nameRange: nameRange)
                }
            } else if cursor.current.isName, !atDeclaration {
                guard path.count == 1 else { throw cursor.error("Expected 'inv' or 'def'") }
                selfName = path[0]
                nameStart = cursor.startPosition
                path = try parsePath("classifier name")
                nameRange = cursor.range(from: nameStart)
            }
            var context = CompleteOCLClassifierContext(packagePath: packagePath, path: path, selfName: selfName, nameRange: nameRange)
            var children: [OutlineNode] = []
            let contextPath = packagePath + path
            if !(cursor.at(word: Syntax.invKeyword) || cursor.at(word: Syntax.defKeyword) || cursor.at(word: Syntax.staticKeyword)) {
                diagnostics.append(SourceDiagnostic(
                    severity: .warning, code: OCLDiagnosticCode.unexpectedToken,
                    message: "The context '\(path.joined(separator: "::"))' has no invariants or definitions",
                    range: nameRange, document: document))
            }
            while cursor.at(word: Syntax.invKeyword) || cursor.at(word: Syntax.defKeyword) || cursor.at(word: Syntax.staticKeyword) {
                if cursor.accept(word: Syntax.invKeyword) {
                    let constraint = try parseConstraint()
                    context.invariants.append(constraint)
                    children.append(node(Kind.invariant, constraint, path: contextPath))
                } else if cursor.at(word: Syntax.defKeyword) || cursor.at(word: Syntax.staticKeyword) {
                    let definition = try parseDefinition()
                    context.definitions.append(definition)
                    if let range = definition.range {
                        children.append(OutlineNode(
                            id: Kind.definition + ":" + (contextPath + [definition.name]).joined(separator: "::"),
                            kind: Kind.definition, name: definition.name, detail: definition.specification.expression,
                            range: range, selectionRange: range))
                    }
                }
            }
            context.range = cursor.range(from: start)
            result.classifierContexts.append(context)
            return OutlineNode(
                id: Kind.classifier + ":" + contextPath.joined(separator: "::"), kind: Kind.classifier,
                name: path.joined(separator: "::"), detail: selfName, range: cursor.range(from: start), selectionRange: nameRange,
                children: children)
        }

        /// Reads the constraints of an operation context.
        ///
        /// - Parameters:
        ///   - packagePath: The path of the enclosing package.
        ///   - path: The qualified name of the operation.
        ///   - start: The position where the context starts.
        ///   - nameRange: The source range of the operation name.
        /// - Returns: The outline node of the context.
        /// - Throws: ``OCLSyntaxError`` if the context is malformed.
        mutating func parseOperationContext(
            packagePath: [String], path: [String], start: SourcePosition, nameRange: SourceRange
        ) throws -> OutlineNode {
            var context = CompleteOCLOperationContext(packagePath: packagePath, path: path, nameRange: nameRange)
            try cursor.expect(symbol: "(")
            if !cursor.at(symbol: ")") {
                repeat {
                    var name: String?
                    if cursor.current.isName, cursor.peek().isSymbol(":") {
                        name = cursor.current.value
                        cursor.advance()
                        cursor.advance()
                    }
                    context.parameters.append(CompleteOCLParameter(name: name, type: try expressions.parseType(&cursor)))
                } while cursor.accept(symbol: ",")
            }
            try cursor.expect(symbol: ")")
            if cursor.accept(symbol: ":"), !atDeclaration {
                context.resultType = try expressions.parseType(&cursor)
            }
            var children: [OutlineNode] = []
            let contextPath = packagePath + path
            while true {
                if cursor.accept(word: Syntax.preKeyword) {
                    let constraint = try parseConstraint()
                    context.preconditions.append(constraint)
                    children.append(node(Kind.precondition, constraint, path: contextPath))
                } else if cursor.accept(word: Syntax.postKeyword) {
                    let constraint = try parseConstraint()
                    context.postconditions.append(constraint)
                    children.append(node(Kind.postcondition, constraint, path: contextPath))
                } else if cursor.accept(word: Syntax.bodyKeyword) {
                    let constraint = try parseConstraint(allowsMessage: false)
                    context.bodies.append(constraint)
                    children.append(node(Kind.body, constraint, path: contextPath))
                } else {
                    break
                }
            }
            context.range = cursor.range(from: start)
            result.operationContexts.append(context)
            let signature = "(" + context.parameters.map(\.type.textWithMultiplicity).joined(separator: ", ") + ")"
                + (context.resultType.map { " : " + $0.textWithMultiplicity } ?? "")
            return OutlineNode(
                id: Kind.operation + ":" + contextPath.joined(separator: "::"), kind: Kind.operation,
                name: path.joined(separator: "::"), detail: signature, range: cursor.range(from: start), selectionRange: nameRange,
                children: children)
        }

        /// Reads the constraints of a property context.
        ///
        /// - Parameters:
        ///   - packagePath: The path of the enclosing package.
        ///   - path: The qualified name of the property.
        ///   - type: The declared type of the property.
        ///   - start: The position where the context starts.
        ///   - nameRange: The source range of the property name.
        /// - Returns: The outline node of the context.
        /// - Throws: ``OCLSyntaxError`` if the context is malformed.
        mutating func parsePropertyContext(
            packagePath: [String], path: [String], type: OCLTypeReference, start: SourcePosition, nameRange: SourceRange
        ) throws -> OutlineNode {
            var context = CompleteOCLPropertyContext(packagePath: packagePath, path: path, type: type, nameRange: nameRange)
            var children: [OutlineNode] = []
            let contextPath = packagePath + path
            while true {
                if cursor.accept(word: Syntax.initKeyword) {
                    let constraint = try parseConstraint(allowsMessage: false)
                    context.initialisers.append(constraint)
                    children.append(node(Kind.initial, constraint, path: contextPath))
                } else if cursor.accept(word: Syntax.deriveKeyword) {
                    let constraint = try parseConstraint(allowsMessage: false)
                    context.derivations.append(constraint)
                    children.append(node(Kind.derivation, constraint, path: contextPath))
                } else {
                    break
                }
            }
            if children.isEmpty { throw cursor.error("Expected 'init' or 'derive'") }
            context.range = cursor.range(from: start)
            result.propertyContexts.append(context)
            return OutlineNode(
                id: Kind.property + ":" + contextPath.joined(separator: "::"), kind: Kind.property,
                name: path.joined(separator: "::"), detail: type.textWithMultiplicity, range: cursor.range(from: start),
                selectionRange: nameRange, children: children)
        }

        /// Creates the outline node of a constraint.
        ///
        /// - Parameters:
        ///   - kind: The kind of outline node.
        ///   - constraint: The constraint.
        ///   - path: The qualified name of the context.
        /// - Returns: The outline node.
        func node(_ kind: String, _ constraint: CompleteOCLConstraint, path: [String]) -> OutlineNode {
            let range = constraint.range ?? cursor.current.range
            let name = constraint.name ?? kind
            return OutlineNode(
                id: kind + ":" + (path + [name]).joined(separator: "::"), kind: kind, name: name, detail: constraint.expression,
                range: range, selectionRange: range)
        }

        // MARK: Constraints

        /// Parses `name? ('(' message ')')? ':' expression` after a constraint keyword.
        mutating func parseConstraint(allowsMessage: Bool = true) throws -> CompleteOCLConstraint {
            let start = cursor.previous?.range.start ?? cursor.startPosition
            var name: String?
            var message: String?
            if cursor.current.isName, !cursor.at(symbol: ":") {
                name = cursor.current.value
                cursor.advance()
                if allowsMessage, cursor.accept(symbol: "(") {
                    let messageExpression = try expressions.parseExpression(&cursor)
                    message = cursor.text(of: messageExpression.range)
                    try cursor.expect(symbol: ")")
                }
            }
            try cursor.expect(symbol: ":")
            var constraint = try parseSpecification()
            constraint.name = name
            constraint.message = message
            constraint.range = cursor.range(from: start)
            return constraint
        }

        /// Parses an expression and keeps its text, recovering to the next declaration on error.
        mutating func parseSpecification() throws -> CompleteOCLConstraint {
            let start = cursor.position
            let startPosition = cursor.startPosition
            do {
                var probe = cursor
                let expression = try expressions.parseExpression(&probe)
                guard probe.isAtEnd || probe.current.kind == .identifier && Syntax.declarationKeywords.contains(probe.current.text) else {
                    throw probe.error("Expected the end of the expression")
                }
                cursor = probe
                return CompleteOCLConstraint(expression: cursor.text(of: expression.range), parsedExpression: expression)
            } catch let error as OCLSyntaxError {
                report(error, code: OCLDiagnosticCode.invalidExpression)
                cursor.position = start
                recover(from: start)
                let text = cursor.text(of: cursor.range(from: startPosition))
                return CompleteOCLConstraint(expression: text)
            }
        }

        /// Reads a `def` declaration.
        ///
        /// - Returns: The definition.
        /// - Throws: ``OCLSyntaxError`` if the declaration is malformed.
        mutating func parseDefinition() throws -> CompleteOCLDefinition {
            let start = cursor.startPosition
            let isStatic = cursor.accept(word: Syntax.staticKeyword)
            try cursor.expect(word: Syntax.defKeyword)
            if cursor.current.isName, cursor.peek().isSymbol(":") { cursor.advance() }
            try cursor.expect(symbol: ":")
            if cursor.at(symbol: "<") { try skipTemplateSignature() }
            let name = try cursor.expectName("definition name")
            var parameters: [CompleteOCLParameter]?
            if cursor.accept(symbol: "(") {
                var list: [CompleteOCLParameter] = []
                if !cursor.at(symbol: ")") {
                    repeat {
                        let parameterName = try cursor.expectName("parameter name")
                        try cursor.expect(symbol: ":")
                        list.append(CompleteOCLParameter(name: parameterName, type: try expressions.parseType(&cursor)))
                    } while cursor.accept(symbol: ",")
                }
                try cursor.expect(symbol: ")")
                parameters = list
            }
            try cursor.expect(symbol: ":")
            var type: OCLTypeReference?
            if !cursor.at(symbol: "=") { type = try expressions.parseType(&cursor) }
            try cursor.expect(symbol: "=")
            var specification = try parseSpecification()
            specification.name = name
            specification.range = cursor.range(from: start)
            return CompleteOCLDefinition(
                isStatic: isStatic, name: name, parameters: parameters, type: type, specification: specification,
                range: cursor.range(from: start))
        }
    }
}
