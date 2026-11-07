//
// OCLExpressionParser.swift
// OCL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// The outcome of parsing a piece of Essential OCL text.
public struct OCLExpressionParseResult: Sendable {
    /// The parsed expression, or `nil` if the text has a syntax error.
    public var expression: OCLExpression?

    /// The problems found, in order of position.
    public var diagnostics: [SourceDiagnostic]

    /// The tokens of the text, including comments.
    public var tokens: [SourceToken]

    /// Creates a parse result.
    ///
    /// - Parameters:
    ///   - expression: The parsed expression.
    ///   - diagnostics: The problems found.
    ///   - tokens: The tokens of the text.
    public init(expression: OCLExpression?, diagnostics: [SourceDiagnostic], tokens: [SourceToken]) {
        self.expression = expression
        self.diagnostics = diagnostics
        self.tokens = tokens
    }
}

/// Parses Essential OCL expressions.
///
/// The parser follows the `ExpCS` rule of the Eclipse OCL grammar, with the precedence of the
/// OCL standard library: navigation (`.`, `->`, `?.`, `?->`) binds tightest, then the unary
/// `-` and `not`, `*` and `/`, `+` and `-`, the relations `<`, `>`, `<=`, `>=`, the equalities
/// `=` and `<>`, then `and`, `or`, `xor` and finally `implies`. Every binary operator associates
/// to the left. Primary expressions are literals, names, calls, collection, tuple and map
/// literals, type literals, parenthesised expressions, `if ... endif` and `let ... in`.
///
/// An expression ends where the next token cannot continue it, so that a document parser can
/// read an expression embedded in a larger text and continue after it.
public struct OCLExpressionParser: Sendable {
    /// Whether Complete OCL message expressions (`^` and `^^`) are read.
    public var allowsMessages: Bool

    /// Creates a parser.
    ///
    /// - Parameter allowsMessages: Whether Complete OCL message expressions are read.
    public init(allowsMessages: Bool = false) {
        self.allowsMessages = allowsMessages
    }

    /// Parses text that holds exactly one expression.
    ///
    /// - Parameter source: The OCL text.
    /// - Returns: The expression, or `nil` with diagnostics; and the tokens of the text.
    public func parse(_ source: String) -> OCLExpressionParseResult {
        let tokenisation = OCLLexer.tokenise(source)
        var diagnostics = tokenisation.diagnostics
        var cursor = OCLTokenCursor(tokens: tokenisation.significantTokens, source: source)
        var expression: OCLExpression?
        do {
            let parsed = try parseExpression(&cursor)
            if cursor.isAtEnd {
                expression = parsed
            } else {
                throw cursor.error("Expected the end of the expression")
            }
        } catch let error as OCLSyntaxError {
            if !diagnostics.contains(where: { $0.range == error.diagnostic.range }) {
                diagnostics.append(error.diagnostic)
            }
        } catch {}
        if !diagnostics.isEmpty { expression = nil }
        diagnostics.sort { ($0.range?.start.utf8Offset ?? 0) < ($1.range?.start.utf8Offset ?? 0) }
        let tokens = OCLTokenClassifier.sourceTokens(of: tokenisation.tokens, keywords: OCLSyntax.reservedWords)
        return OCLExpressionParseResult(expression: expression, diagnostics: diagnostics, tokens: tokens)
    }

    /// Parses an expression starting at the cursor.
    ///
    /// On return the cursor is after the expression; on failure it is where the problem was found.
    ///
    /// - Parameter cursor: The tokens and position to read from.
    /// - Returns: The expression.
    /// - Throws: ``OCLSyntaxError`` if the tokens do not start with an expression.
    public func parseExpression(_ cursor: inout OCLTokenCursor) throws -> OCLExpression {
        var grammar = Grammar(cursor: cursor, allowsMessages: allowsMessages)
        defer { cursor = grammar.cursor }
        return try grammar.parseBinary(level: 0)
    }

    /// Parses a type reference starting at the cursor, such as `Set(Book)[*]`.
    ///
    /// - Parameters:
    ///   - cursor: The tokens and position to read from.
    ///   - allowsMultiplicity: Whether a multiplicity may follow the type.
    /// - Returns: The type reference.
    /// - Throws: ``OCLSyntaxError`` if the tokens do not start with a type.
    public func parseType(_ cursor: inout OCLTokenCursor, allowsMultiplicity: Bool = true) throws -> OCLTypeReference {
        var grammar = Grammar(cursor: cursor, allowsMessages: allowsMessages)
        defer { cursor = grammar.cursor }
        return try grammar.parseType(allowsMultiplicity: allowsMultiplicity)
    }

    /// Parses a multiplicity such as `[?]`, `[*]`, `[1..5]` or `[1..*|1]`, starting at `[`.
    ///
    /// - Parameter cursor: The tokens and position to read from.
    /// - Returns: The multiplicity.
    /// - Throws: ``OCLSyntaxError`` if the tokens do not form a multiplicity.
    public static func parseMultiplicity(_ cursor: inout OCLTokenCursor) throws -> OCLMultiplicity {
        try cursor.expect(symbol: "[")
        var multiplicity: OCLMultiplicity
        if cursor.accept(symbol: "*") {
            multiplicity = OCLMultiplicity(lower: 0, upper: OCLMultiplicity.unbounded)
        } else if cursor.accept(symbol: "+") {
            multiplicity = OCLMultiplicity(lower: 1, upper: OCLMultiplicity.unbounded)
        } else if cursor.accept(symbol: "?") {
            multiplicity = OCLMultiplicity(lower: 0, upper: 1)
        } else {
            let lower = try integer(&cursor)
            multiplicity = OCLMultiplicity(lower: lower, upper: lower)
            if cursor.accept(symbol: "..") {
                multiplicity.upper = cursor.accept(symbol: "*") ? OCLMultiplicity.unbounded : try integer(&cursor)
            }
        }
        if cursor.at(symbol: "|") {
            cursor.advance()
            if cursor.accept(symbol: "?") {
                multiplicity.isNullFree = false
            } else if cursor.current.kind == .integer, cursor.current.text == "1" {
                cursor.advance()
                multiplicity.isNullFree = true
            } else {
                throw cursor.error("Expected '?' or '1' after '|'")
            }
        }
        try cursor.expect(symbol: "]")
        return multiplicity
    }

    /// Reads a whole number.
    private static func integer(_ cursor: inout OCLTokenCursor) throws -> Int {
        guard cursor.current.kind == .integer, let value = Int(cursor.current.text) else {
            throw cursor.error("Expected a whole number")
        }
        cursor.advance()
        return value
    }

    // MARK: - Grammar

    /// The recursive-descent grammar over a cursor.
    private struct Grammar {
        /// The tokens being read.
        var cursor: OCLTokenCursor
        /// Whether `message` clauses are accepted after constraints.
        let allowsMessages: Bool

        /// Creates an expression node that spans from a position to the current token.
        ///
        /// - Parameters:
        ///   - kind: The kind of expression.
        ///   - start: The position where the expression starts.
        /// - Returns: The expression.
        func node(_ kind: OCLExpressionKind, from start: SourcePosition) -> OCLExpression {
            OCLExpression(kind, range: cursor.range(from: start))
        }

        // MARK: Operators

        /// Reads a binary expression at a level of operator precedence.
        ///
        /// - Parameter level: The precedence level, from the loosest binding.
        /// - Returns: The expression.
        /// - Throws: ``OCLSyntaxError`` if the expression is malformed.
        mutating func parseBinary(level: Int) throws -> OCLExpression {
            guard level < OCLSyntax.binaryOperatorLevels.count else { return try parseUnary() }
            let start = cursor.startPosition
            if cursor.at(word: OCLSyntax.letKeyword) { return try parseUnary() }
            var left = try parseBinary(level: level + 1)
            let operators = OCLSyntax.binaryOperatorLevels[level]
            while let op = binaryOperator(in: operators) {
                cursor.advance()
                let right: OCLExpression
                if cursor.at(word: OCLSyntax.letKeyword) || isUnaryLet() {
                    right = try parseBinary(level: 0)
                } else {
                    right = try parseBinary(level: level + 1)
                }
                left = node(.infix(operator: op, left: left, right: right), from: start)
            }
            return left
        }

        /// Whether the current token starts a chain of unary operators applied to `let`.
        func isUnaryLet() -> Bool {
            var offset = 0
            while true {
                let token = cursor.peek(offset)
                if token.isWord(OCLSyntax.letKeyword) { return offset > 0 }
                guard isUnaryOperator(token) else { return false }
                offset += 1
            }
        }

        /// Whether a token is a prefix operator.
        ///
        /// - Parameter token: The token.
        /// - Returns: `true` if the token is `-` or `not`.
        func isUnaryOperator(_ token: OCLToken) -> Bool {
            token.isSymbol("-") || token.isWord(OCLSyntax.notKeyword) || token.isWord("not2")
        }

        /// The binary operator at the current token, if it is one of a set.
        ///
        /// - Parameter operators: The operators to accept.
        /// - Returns: The operator, or `nil` if the current token is not one of them.
        func binaryOperator(in operators: [String]) -> String? {
            let token = cursor.current
            guard token.kind == .symbol || token.kind == .identifier else { return nil }
            return operators.contains(token.text) ? token.text : nil
        }

        /// Reads a unary expression, with any prefix operators.
        ///
        /// - Returns: The expression.
        /// - Throws: ``OCLSyntaxError`` if the expression is malformed.
        mutating func parseUnary() throws -> OCLExpression {
            let start = cursor.startPosition
            if isUnaryOperator(cursor.current) {
                let op = cursor.current.text
                cursor.advance()
                let operand = try parseUnary()
                return node(.prefix(operator: op, operand: operand), from: start)
            }
            if cursor.at(word: OCLSyntax.letKeyword) { return try parseLet() }
            return try parsePostfix()
        }

        // MARK: Navigation

        /// Reads a primary expression followed by any navigations.
        ///
        /// - Returns: The expression.
        /// - Throws: ``OCLSyntaxError`` if the expression is malformed.
        mutating func parsePostfix() throws -> OCLExpression {
            let start = cursor.startPosition
            var expression = try parsePrimary()
            while true {
                let token = cursor.current
                if token.kind == .symbol,
                    OCLSyntax.objectNavigationOperators.contains(token.text)
                        || OCLSyntax.collectionNavigationOperators.contains(token.text)
                {
                    cursor.advance()
                    expression = try parseNavigation(from: expression, operator: token.text, start: start)
                } else if allowsMessages, token.kind == .symbol, OCLSyntax.messageOperators.contains(token.text) {
                    cursor.advance()
                    let name = try cursor.expectName("message name")
                    let arguments = try parseArguments()
                    expression = node(
                        .message(target: expression, operator: token.text, name: name, arguments: arguments.arguments),
                        from: start)
                } else {
                    return expression
                }
            }
        }

        /// Reads the navigation that follows an object or collection operator.
        ///
        /// - Parameters:
        ///   - source: The expression being navigated.
        ///   - op: The navigation operator that was read.
        ///   - start: The position where the whole expression starts.
        /// - Returns: The navigation expression.
        /// - Throws: ``OCLSyntaxError`` if the navigation is malformed.
        mutating func parseNavigation(
            from source: OCLExpression, operator op: String, start: SourcePosition
        ) throws -> OCLExpression {
            var segments = [try cursor.expectName("property or operation name after '\(op)'")]
            while cursor.at(symbol: OCLSyntax.pathSeparator) {
                cursor.advance()
                segments.append(try cursor.expectName("name after '::'"))
            }
            let arguments = cursor.at(symbol: "(") ? try parseArguments() : nil
            let isPre = try parsePre()
            let call = OCLCall(
                source: source, navigation: op, qualifier: Array(segments.dropLast()), name: segments[segments.count - 1],
                arguments: arguments, isPre: isPre)
            return node(.call(call), from: start)
        }

        /// Accepts an `@pre` marker.
        ///
        /// - Returns: `true` if the marker was read.
        /// - Throws: ``OCLSyntaxError`` if the marker is malformed.
        mutating func parsePre() throws -> Bool {
            guard cursor.at(symbol: "@"), cursor.peek().isWord(OCLSyntax.preKeyword) else { return false }
            cursor.advance()
            cursor.advance()
            return true
        }

        // MARK: Arguments

        /// Parses `( ... )` after an operation or iteration name.
        mutating func parseArguments() throws -> OCLArguments {
            try cursor.expect(symbol: "(")
            if cursor.accept(symbol: ")") { return OCLArguments() }
            var result = OCLArguments()
            let saved = cursor
            if let header = try? parseIteratorHeader() {
                result.iterators = header.iterators
                result.accumulators = header.accumulators
                result.hasBody = true
                result.arguments = [try parseBinary(level: 0)]
            } else {
                cursor = saved
                while true {
                    result.arguments.append(try parseBinary(level: 0))
                    guard cursor.accept(symbol: ",") else { break }
                }
            }
            try cursor.expect(symbol: ")")
            return result
        }

        /// Parses the iterators and accumulators of an iteration up to and including `|`.
        mutating func parseIteratorHeader() throws -> (iterators: [OCLVariableDeclaration], accumulators: [OCLVariableDeclaration]) {
            var iterators: [OCLVariableDeclaration] = []
            var accumulators: [OCLVariableDeclaration] = []
            repeat {
                iterators.append(try parseVariable(requiresInitialiser: false))
            } while cursor.accept(symbol: ",")
            if cursor.accept(symbol: ";") {
                repeat {
                    accumulators.append(try parseVariable(requiresInitialiser: true))
                } while cursor.accept(symbol: ",")
            }
            try cursor.expect(symbol: "|")
            return (iterators, accumulators)
        }

        /// Reads a variable declaration with an optional type and initialiser.
        ///
        /// - Parameter requiresInitialiser: Whether an initialiser must follow.
        /// - Returns: The declaration.
        /// - Throws: ``OCLSyntaxError`` if the declaration is malformed.
        mutating func parseVariable(requiresInitialiser: Bool) throws -> OCLVariableDeclaration {
            let start = cursor.startPosition
            let name = try cursor.expectName("variable name", excluding: OCLSyntax.reservedWords)
            var declaration = OCLVariableDeclaration(name: name)
            if cursor.accept(symbol: ":") { declaration.type = try parseType(allowsMultiplicity: true) }
            if requiresInitialiser {
                try cursor.expect(symbol: "=")
                declaration.initialiser = try parseBinary(level: 0)
            }
            declaration.range = cursor.range(from: start)
            return declaration
        }

        // MARK: Primary expressions

        /// Reads a literal, name, parenthesised expression or other primary expression.
        ///
        /// - Returns: The expression.
        /// - Throws: ``OCLSyntaxError`` if the expression is malformed.
        mutating func parsePrimary() throws -> OCLExpression {
            let start = cursor.startPosition
            let token = cursor.current
            switch token.kind {
            case .integer:
                cursor.advance()
                return node(.integerLiteral(token.text), from: start)
            case .real:
                cursor.advance()
                return node(.realLiteral(token.text), from: start)
            case .string:
                var value = ""
                while cursor.current.kind == .string {
                    value += cursor.current.value
                    cursor.advance()
                }
                return node(.stringLiteral(value: value, source: cursor.text(of: cursor.range(from: start))), from: start)
            case .symbol:
                return try parseSymbolPrimary(from: start)
            case .identifier:
                return try parseWordPrimary(token.text, from: start)
            case .escapedIdentifier:
                return try parseName(from: start)
            default:
                throw cursor.error("Expected an expression")
            }
        }

        /// Reads a primary expression that starts with a symbol.
        ///
        /// - Parameter start: The position where the expression starts.
        /// - Returns: The expression.
        /// - Throws: ``OCLSyntaxError`` if the expression is malformed.
        mutating func parseSymbolPrimary(from start: SourcePosition) throws -> OCLExpression {
            if cursor.accept(symbol: "(") {
                let inner = try parseBinary(level: 0)
                try cursor.expect(symbol: ")")
                return node(.parenthesised(inner), from: start)
            }
            if cursor.accept(symbol: "*") { return node(.unlimitedLiteral, from: start) }
            if allowsMessages, cursor.accept(symbol: "?") { return node(.unspecifiedValue, from: start) }
            throw cursor.error("Expected an expression")
        }

        /// Reads a primary expression that starts with a word.
        ///
        /// - Parameters:
        ///   - word: The word at the current token.
        ///   - start: The position where the expression starts.
        /// - Returns: The expression.
        /// - Throws: ``OCLSyntaxError`` if the expression is malformed.
        mutating func parseWordPrimary(_ word: String, from start: SourcePosition) throws -> OCLExpression {
            switch word {
            case OCLSyntax.ifKeyword: return try parseConditional()
            case OCLSyntax.letKeyword: return try parseLet()
            case OCLSyntax.selfKeyword:
                cursor.advance()
                return node(.selfReference, from: start)
            case OCLSyntax.trueLiteral, OCLSyntax.falseLiteral:
                cursor.advance()
                return node(.booleanLiteral(word == OCLSyntax.trueLiteral), from: start)
            case OCLSyntax.nullLiteral:
                cursor.advance()
                return node(.nullLiteral, from: start)
            case OCLSyntax.invalidLiteral:
                cursor.advance()
                return node(.invalidLiteral, from: start)
            case OCLSyntax.tupleTypeName where cursor.peek().isSymbol("{"):
                return try parseTupleLiteral()
            case OCLSyntax.lambdaName where cursor.peek().isSymbol("{"):
                cursor.advance()
                cursor.advance()
                let body = try parseBinary(level: 0)
                try cursor.expect(symbol: "}")
                return node(.lambda(body), from: start)
            case OCLSyntax.mapTypeName:
                let type = try parseType(allowsMultiplicity: false)
                guard cursor.at(symbol: "{") else { return node(.typeLiteral(type), from: start) }
                return try parseMapLiteral(type: type, from: start)
            case _ where OCLSyntax.collectionTypeNames.contains(word):
                let type = try parseType(allowsMultiplicity: false)
                guard cursor.at(symbol: "{") else { return node(.typeLiteral(type), from: start) }
                return try parseCollectionLiteral(type: type, from: start)
            case OCLSyntax.tupleTypeName:
                return node(.typeLiteral(try parseType(allowsMultiplicity: false)), from: start)
            case _ where OCLSyntax.primitiveTypeNames.contains(word) && !cursor.peek().isSymbol(OCLSyntax.pathSeparator):
                cursor.advance()
                return node(.typeLiteral(OCLTypeReference(path: [word], range: cursor.range(from: start))), from: start)
            case _ where OCLSyntax.reservedWords.contains(word):
                throw cursor.error("Expected an expression")
            default:
                return try parseName(from: start)
            }
        }

        /// Reads a possibly qualified name, with any call or literal that follows it.
        ///
        /// - Parameter start: The position where the expression starts.
        /// - Returns: The expression.
        /// - Throws: ``OCLSyntaxError`` if the expression is malformed.
        mutating func parseName(from start: SourcePosition) throws -> OCLExpression {
            var segments = [try cursor.expectName("name")]
            while cursor.at(symbol: OCLSyntax.pathSeparator) {
                cursor.advance()
                segments.append(try cursor.expectName("name after '::'"))
            }
            var expression: OCLExpression
            if cursor.at(symbol: "(") {
                let arguments = try parseArguments()
                let isPre = try parsePre()
                let call = OCLCall(
                    source: nil, navigation: nil, qualifier: Array(segments.dropLast()), name: segments[segments.count - 1],
                    arguments: arguments, isPre: isPre)
                expression = node(.call(call), from: start)
            } else if cursor.at(symbol: "{"), isShadowClause() {
                expression = try parseShadow(type: segments, from: start)
            } else {
                expression = node(.name(segments, isPre: try parsePre()), from: start)
            }
            while cursor.at(symbol: "[") {
                cursor.advance()
                var terms = [try parseBinary(level: 0)]
                while cursor.accept(symbol: ",") { terms.append(try parseBinary(level: 0)) }
                try cursor.expect(symbol: "]")
                expression = node(.indexed(source: expression, terms: terms), from: start)
            }
            return expression
        }

        /// Whether `{` at the cursor starts a curly-bracketed clause of property values.
        func isShadowClause() -> Bool {
            let next = cursor.peek()
            if next.isSymbol("}") || next.kind == .string { return true }
            return next.isName && cursor.peek(2).isSymbol("=")
        }

        /// Reads the braced parts of a shadow object expression.
        ///
        /// - Parameters:
        ///   - type: The qualified name of the type being instantiated.
        ///   - start: The position where the expression starts.
        /// - Returns: The expression.
        /// - Throws: ``OCLSyntaxError`` if the expression is malformed.
        mutating func parseShadow(type: [String], from start: SourcePosition) throws -> OCLExpression {
            try cursor.expect(symbol: "{")
            var parts: [OCLVariableDeclaration] = []
            if !cursor.at(symbol: "}") {
                repeat {
                    let partStart = cursor.startPosition
                    if cursor.current.kind == .string {
                        let value = try parsePrimary()
                        parts.append(OCLVariableDeclaration(name: "", initialiser: value, range: cursor.range(from: partStart)))
                    } else {
                        let name = try cursor.expectName("property name")
                        try cursor.expect(symbol: "=")
                        let value = try parseBinary(level: 0)
                        parts.append(OCLVariableDeclaration(name: name, initialiser: value, range: cursor.range(from: partStart)))
                    }
                } while cursor.accept(symbol: ",")
            }
            try cursor.expect(symbol: "}")
            return node(.shadow(type: type, parts: parts), from: start)
        }

        /// Reads an `if` expression with its `then`, `elseif` and `else` branches.
        ///
        /// - Returns: The expression.
        /// - Throws: ``OCLSyntaxError`` if the expression is malformed.
        mutating func parseConditional() throws -> OCLExpression {
            let start = cursor.startPosition
            try cursor.expect(word: OCLSyntax.ifKeyword)
            var branches: [OCLConditionalBranch] = []
            let condition = try parseBinary(level: 0)
            try cursor.expect(word: OCLSyntax.thenKeyword)
            branches.append(OCLConditionalBranch(condition: condition, value: try parseBinary(level: 0)))
            while cursor.accept(word: OCLSyntax.elseifKeyword) {
                let condition = try parseBinary(level: 0)
                try cursor.expect(word: OCLSyntax.thenKeyword)
                branches.append(OCLConditionalBranch(condition: condition, value: try parseBinary(level: 0)))
            }
            try cursor.expect(word: OCLSyntax.elseKeyword)
            let otherwise = try parseBinary(level: 0)
            try cursor.expect(word: OCLSyntax.endifKeyword)
            return node(.conditional(branches: branches, otherwise: otherwise), from: start)
        }

        /// Reads a `let` expression.
        ///
        /// - Returns: The expression.
        /// - Throws: ``OCLSyntaxError`` if the expression is malformed.
        mutating func parseLet() throws -> OCLExpression {
            let start = cursor.startPosition
            try cursor.expect(word: OCLSyntax.letKeyword)
            var variables: [OCLVariableDeclaration] = []
            repeat {
                variables.append(try parseVariable(requiresInitialiser: true))
            } while cursor.accept(symbol: ",")
            try cursor.expect(word: OCLSyntax.inKeyword)
            let body = try parseBinary(level: 0)
            return node(.letExpression(variables: variables, body: body), from: start)
        }

        /// Reads the braced parts of a collection literal.
        ///
        /// - Parameters:
        ///   - type: The type of the collection.
        ///   - start: The position where the expression starts.
        /// - Returns: The expression.
        /// - Throws: ``OCLSyntaxError`` if the literal is malformed.
        mutating func parseCollectionLiteral(type: OCLTypeReference, from start: SourcePosition) throws -> OCLExpression {
            try cursor.expect(symbol: "{")
            var parts: [OCLCollectionPart] = []
            if !cursor.at(symbol: "}") {
                repeat {
                    let first = try parseBinary(level: 0)
                    if cursor.accept(symbol: "..") {
                        parts.append(.range(first, try parseBinary(level: 0)))
                    } else {
                        parts.append(.element(first))
                    }
                } while cursor.accept(symbol: ",")
            }
            try cursor.expect(symbol: "}")
            return node(.collectionLiteral(type: type, parts: parts), from: start)
        }

        /// Reads a tuple literal.
        ///
        /// - Returns: The expression.
        /// - Throws: ``OCLSyntaxError`` if the literal is malformed.
        mutating func parseTupleLiteral() throws -> OCLExpression {
            let start = cursor.startPosition
            cursor.advance()
            try cursor.expect(symbol: "{")
            var parts: [OCLVariableDeclaration] = []
            repeat {
                let partStart = cursor.startPosition
                let name = try cursor.expectName("tuple part name")
                var part = OCLVariableDeclaration(name: name)
                if cursor.accept(symbol: ":") { part.type = try parseType(allowsMultiplicity: true) }
                try cursor.expect(symbol: "=")
                part.initialiser = try parseBinary(level: 0)
                part.range = cursor.range(from: partStart)
                parts.append(part)
            } while cursor.accept(symbol: ",")
            try cursor.expect(symbol: "}")
            return node(.tupleLiteral(parts), from: start)
        }

        /// Reads the braced parts of a map literal.
        ///
        /// - Parameters:
        ///   - type: The type of the map.
        ///   - start: The position where the expression starts.
        /// - Returns: The expression.
        /// - Throws: ``OCLSyntaxError`` if the literal is malformed.
        mutating func parseMapLiteral(type: OCLTypeReference, from start: SourcePosition) throws -> OCLExpression {
            try cursor.expect(symbol: "{")
            var parts: [OCLMapPart] = []
            if !cursor.at(symbol: "}") {
                repeat {
                    let key = try parseBinary(level: 0)
                    guard cursor.accept(word: "with") || cursor.accept(symbol: "<-") else {
                        throw cursor.error("Expected 'with'")
                    }
                    parts.append(OCLMapPart(key: key, value: try parseBinary(level: 0)))
                } while cursor.accept(symbol: ",")
            }
            try cursor.expect(symbol: "}")
            return node(.mapLiteral(type: type, parts: parts), from: start)
        }

        // MARK: Types

        /// Reads a type reference.
        ///
        /// - Parameter allowsMultiplicity: Whether a multiplicity may follow the type name.
        /// - Returns: The type reference.
        /// - Throws: ``OCLSyntaxError`` if the type is malformed.
        mutating func parseType(allowsMultiplicity: Bool) throws -> OCLTypeReference {
            let start = cursor.startPosition
            var segments = [try cursor.expectName("type name")]
            while cursor.at(symbol: OCLSyntax.pathSeparator) {
                cursor.advance()
                segments.append(try cursor.expectName("name after '::'"))
            }
            var type = OCLTypeReference(path: segments)
            if segments == [OCLSyntax.tupleTypeName], cursor.accept(symbol: "(") {
                if !cursor.at(symbol: ")") {
                    repeat {
                        let name = try cursor.expectName("tuple part name")
                        try cursor.expect(symbol: ":")
                        type.parts.append(OCLTypeReference.Part(name: name, type: try parseType(allowsMultiplicity: true)))
                    } while cursor.accept(symbol: ",")
                }
                try cursor.expect(symbol: ")")
            } else if cursor.at(symbol: "(") || cursor.at(symbol: "<") {
                let closing = cursor.at(symbol: "(") ? ")" : ">"
                cursor.advance()
                repeat {
                    type.arguments.append(try parseType(allowsMultiplicity: true))
                } while cursor.accept(symbol: ",")
                try cursor.expect(symbol: closing)
            }
            if allowsMultiplicity, cursor.at(symbol: "[") {
                type.multiplicity = try OCLExpressionParser.parseMultiplicity(&cursor)
            }
            type.range = cursor.range(from: start)
            return type
        }
    }
}
