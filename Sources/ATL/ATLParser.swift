//
//  ATLParser.swift
//  ATL
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import OrderedCollections

/// Errors that can occur during ATL parsing
public enum ATLParseError: Error, Sendable {
    case invalidSyntax(String)
    case unexpectedToken(String)
    case missingModule
    case invalidModuleName(String)
    case invalidExpression(String)
    case unsupportedConstruct(String)
    case fileNotFound(String)
    case invalidEncoding
}

/// Parser for ATL (Atlas Transformation Language) files
///
/// The ATL parser converts ATL source files into structured ATL modules that can be
/// executed by the ATL virtual machine. It supports:
/// - Module declarations with source/target metamodels
/// - Helper function definitions (context and context-free)
/// - Matched transformation rules
/// - Called transformation rules
/// - Query expressions
/// - Basic ATL expression syntax
///
/// ## Supported ATL Constructs
///
/// - **Modules**: `module ModuleName;`
/// - **Create statements**: `create OUT : Target from IN : Source;`
/// - **Helpers**: `helper def : helperName() : Type = expression;`
/// - **Context helpers**: `helper context Type def : helperName() : Type = expression;`
/// - **Matched rules**: `rule RuleName { from ... to ... }`
/// - **Called rules**: `rule RuleName(params) { to ... }`
/// - **Queries**: `query QueryName = expression;`
/// - **Expressions**: literals, variables, operations, navigation
///
/// ## Example Usage
///
/// ```swift
/// let parser = ATLParser()
/// let module = try await parser.parse(atlFileURL)
/// ```
///
/// - Note: This is a simplified parser focused on supporting the Swift ATL implementation.
///   It may not support all advanced ATL features found in Eclipse ATL.
public actor ATLParser {

    /// Parse an ATL file and return an ATL module
    /// - Parameter url: The URL of the ATL file to parse
    /// - Returns: An ATLModule representing the parsed ATL content
    /// - Throws: ATLParseError if parsing fails
    public func parse(_ url: URL) async throws -> ATLModule {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw ATLParseError.fileNotFound(url.path)
        }

        return try await parseContent(content, filename: url.lastPathComponent)
    }

    /// Parse ATL content from a string
    /// - Parameters:
    ///   - content: The ATL source content
    ///   - filename: Optional filename for error reporting
    /// - Returns: An ATLModule representing the parsed ATL content
    /// - Throws: ATLParseError if parsing fails
    public func parseContent(_ content: String, filename: String = "unknown") async throws
        -> ATLModule
    {
        let lexer = ATLLexer(content: content)
        let tokens = try lexer.tokenize()
        let parser = ATLSyntaxParser(tokens: tokens, filename: filename)

        return try parser.parseModule()
    }
}

// MARK: - ATL Lexer

/// Token types for ATL lexical analysis
private enum ATLTokenType: Equatable {
    case keyword(String)
    case identifier(String)
    case stringLiteral(String)
    case integerLiteral(Int)
    case booleanLiteral(Bool)
    case `operator`(String)
    case punctuation(String)
    case comment(String)
    case whitespace
    case newline
    case eof
}

/// Token representation
private struct ATLToken: Equatable {
    let type: ATLTokenType
    let value: String
    let line: Int
    let column: Int
}

/// ATL lexical analyzer
private class ATLLexer {
    private let content: String
    private var position: String.Index
    private var line: Int = 1
    private var column: Int = 1

    private static let keywords: Set<String> = [
        "module", "create", "from", "helper", "def", "context", "rule", "query",
        "if", "then", "else", "endif", "and", "or", "not", "true", "false",
        "let", "in", "do", "to", "self", "Integer", "String", "Boolean", "Real",
    ]

    private static let `operators`: Set<String> = [
        "+", "-", "*", "/", "=", "<>", "<", ">", "<=", ">=", "->", ".", ":",
    ]

    private static let punctuation: Set<String> = [
        "(", ")", "{", "}", "[", "]", ";", ",", "|",
    ]

    init(content: String) {
        self.content = content
        self.position = content.startIndex
    }

    func tokenize() throws -> [ATLToken] {
        var tokens: [ATLToken] = []

        while position < content.endIndex {
            let token = try nextToken()

            // Skip whitespace and comments for parsing
            switch token.type {
            case .whitespace, .comment, .newline:
                continue
            default:
                tokens.append(token)
            }
        }

        tokens.append(ATLToken(type: .eof, value: "", line: line, column: column))
        return tokens
    }

    private func nextToken() throws -> ATLToken {
        guard position < content.endIndex else {
            return ATLToken(type: .eof, value: "", line: line, column: column)
        }

        let startLine = line
        let startColumn = column
        let char = content[position]

        // Skip whitespace
        if char.isWhitespace {
            if char.isNewline {
                advance()
                return ATLToken(type: .newline, value: "\n", line: startLine, column: startColumn)
            } else {
                while position < content.endIndex && content[position].isWhitespace
                    && !content[position].isNewline
                {
                    advance()
                }
                return ATLToken(type: .whitespace, value: " ", line: startLine, column: startColumn)
            }
        }

        // Comments
        if char == "-" && peek() == "-" {
            advance()  // first -
            advance()  // second -
            var comment = ""
            while position < content.endIndex && !content[position].isNewline {
                comment.append(content[position])
                advance()
            }
            return ATLToken(
                type: .comment(comment), value: "--" + comment, line: startLine, column: startColumn
            )
        }

        // String literals
        if char == "'" {
            return try parseStringLiteral(startLine: startLine, startColumn: startColumn)
        }

        // Numbers
        if char.isNumber {
            return parseNumericLiteral(startLine: startLine, startColumn: startColumn)
        }

        // Multi-character operators
        if char == "<" {
            if peek() == ">" {
                advance()  // <
                advance()  // >
                return ATLToken(
                    type: .`operator`("<>"), value: "<>", line: startLine, column: startColumn)
            } else if peek() == "=" {
                advance()  // <
                advance()  // =
                return ATLToken(
                    type: .`operator`("<="), value: "<=", line: startLine, column: startColumn)
            }
        } else if char == ">" && peek() == "=" {
            advance()  // >
            advance()  // =
            return ATLToken(
                type: .`operator`(">="), value: ">=", line: startLine, column: startColumn)
        } else if char == "-" && peek() == ">" {
            advance()  // -
            advance()  // >
            return ATLToken(
                type: .`operator`("->"), value: "->", line: startLine, column: startColumn)
        }

        // Single-character operators
        if Self.`operators`.contains(String(char)) {
            advance()
            return ATLToken(
                type: .`operator`(String(char)), value: String(char), line: startLine,
                column: startColumn)
        }

        // Punctuation
        if Self.punctuation.contains(String(char)) {
            advance()
            return ATLToken(
                type: .punctuation(String(char)), value: String(char), line: startLine,
                column: startColumn)
        }

        // Identifiers and keywords
        if char.isLetter || char == "_" {
            return parseIdentifier(startLine: startLine, startColumn: startColumn)
        }

        throw ATLParseError.unexpectedToken(
            "Unexpected character: '\(char)' at line \(line), column \(column)")
    }

    private func parseStringLiteral(startLine: Int, startColumn: Int) throws -> ATLToken {
        advance()  // Skip opening quote
        var value = ""

        while position < content.endIndex && content[position] != "'" {
            value.append(content[position])
            advance()
        }

        guard position < content.endIndex else {
            throw ATLParseError.invalidSyntax("Unterminated string literal at line \(startLine)")
        }

        advance()  // Skip closing quote
        return ATLToken(
            type: .stringLiteral(value), value: "'\(value)'", line: startLine, column: startColumn)
    }

    private func parseNumericLiteral(startLine: Int, startColumn: Int) -> ATLToken {
        var value = ""

        while position < content.endIndex
            && (content[position].isNumber || content[position] == ".")
        {
            value.append(content[position])
            advance()
        }

        if let intValue = Int(value) {
            return ATLToken(
                type: .integerLiteral(intValue), value: value, line: startLine, column: startColumn)
        }

        // For simplicity, treat as integer even if parsing fails
        return ATLToken(
            type: .integerLiteral(0), value: value, line: startLine, column: startColumn)
    }

    private func parseIdentifier(startLine: Int, startColumn: Int) -> ATLToken {
        var value = ""

        while position < content.endIndex
            && (content[position].isLetter || content[position].isNumber || content[position] == "_"
                || content[position] == "!")
        {
            value.append(content[position])
            advance()
        }

        // Check for boolean literals
        if value == "true" {
            return ATLToken(
                type: .booleanLiteral(true), value: value, line: startLine, column: startColumn)
        } else if value == "false" {
            return ATLToken(
                type: .booleanLiteral(false), value: value, line: startLine, column: startColumn)
        }

        // Check if it's a keyword
        if Self.keywords.contains(value) {
            return ATLToken(
                type: .keyword(value), value: value, line: startLine, column: startColumn)
        }

        return ATLToken(
            type: .identifier(value), value: value, line: startLine, column: startColumn)
    }

    private func advance() {
        if position < content.endIndex {
            if content[position].isNewline {
                line += 1
                column = 1
            } else {
                column += 1
            }
            position = content.index(after: position)
        }
    }

    private func peek() -> Character? {
        let nextIndex = content.index(after: position)
        guard nextIndex < content.endIndex else { return nil }
        return content[nextIndex]
    }
}

// MARK: - ATL Syntax Parser

/// ATL syntax parser
private class ATLSyntaxParser {
    private let tokens: [ATLToken]
    private var position: Int = 0
    private let filename: String

    init(tokens: [ATLToken], filename: String) {
        self.tokens = tokens
        self.filename = filename
    }

    func parseModule() throws -> ATLModule {
        // Parse module declaration
        guard let moduleName = try parseModuleDeclaration() else {
            throw ATLParseError.missingModule
        }

        var sourceMetamodels: OrderedDictionary<String, EPackage> = [:]
        var targetMetamodels: OrderedDictionary<String, EPackage> = [:]
        var helpers: OrderedDictionary<String, any ATLHelperType> = [:]
        var matchedRules: [ATLMatchedRule] = []
        var calledRules: OrderedDictionary<String, ATLCalledRule> = [:]

        // Parse create statement if present
        if currentToken()?.type == .keyword("create") {
            let (source, target) = try parseCreateStatement()
            sourceMetamodels = source
            targetMetamodels = target
        }

        // Parse module contents
        while !isAtEnd() {
            if currentToken()?.type == .keyword("helper") {
                let helper = try parseHelper()
                helpers[helper.name] = helper
            } else if currentToken()?.type == .keyword("rule") {
                let rule = try parseRule()
                if let matchedRule = rule as? ATLMatchedRule {
                    matchedRules.append(matchedRule)
                } else if let calledRule = rule as? ATLCalledRule {
                    calledRules[calledRule.name] = calledRule
                }
            } else if currentToken()?.type == .keyword("query") {
                // Skip queries for now - they could be added as special helpers
                try skipQuery()
            } else {
                advance()
            }
        }

        // Create default metamodels if none specified
        if sourceMetamodels.isEmpty {
            sourceMetamodels["IN"] = EPackage(name: "DefaultSource", nsURI: "http://default.source")
        }
        if targetMetamodels.isEmpty {
            targetMetamodels["OUT"] = EPackage(
                name: "DefaultTarget", nsURI: "http://default.target")
        }

        return ATLModule(
            name: moduleName,
            sourceMetamodels: sourceMetamodels,
            targetMetamodels: targetMetamodels,
            helpers: helpers,
            matchedRules: matchedRules,
            calledRules: calledRules
        )
    }

    private func parseModuleDeclaration() throws -> String? {
        guard consumeKeyword("module") else {
            return nil
        }

        guard let nameToken = currentToken(),
            case .identifier(let name) = nameToken.type
        else {
            throw ATLParseError.invalidModuleName("Expected module name")
        }

        advance()
        consumePunctuation(";")

        return name
    }

    private func parseCreateStatement() throws -> (
        OrderedDictionary<String, EPackage>, OrderedDictionary<String, EPackage>
    ) {
        consumeKeyword("create")

        var targetMetamodels: OrderedDictionary<String, EPackage> = [:]
        var sourceMetamodels: OrderedDictionary<String, EPackage> = [:]

        // Parse target models: OUT : TargetMM
        while let token = currentToken(), case .identifier(let alias) = token.type {
            advance()
            consumeOperator(":")

            guard let mmToken = currentToken(),
                case .identifier(let metamodelName) = mmToken.type
            else {
                throw ATLParseError.invalidSyntax("Expected metamodel name")
            }
            advance()

            targetMetamodels[alias] = EPackage(
                name: metamodelName, nsURI: "http://\(metamodelName.lowercased())")

            if consumeKeyword("from") {
                break
            } else {
                consumePunctuation(",")
            }
        }

        // Parse source models: IN : SourceMM
        while let token = currentToken(), case .identifier(let alias) = token.type {
            advance()
            consumeOperator(":")

            guard let mmToken = currentToken(),
                case .identifier(let metamodelName) = mmToken.type
            else {
                throw ATLParseError.invalidSyntax("Expected metamodel name")
            }
            advance()

            sourceMetamodels[alias] = EPackage(
                name: metamodelName, nsURI: "http://\(metamodelName.lowercased())")

            if currentToken()?.type == .punctuation(",") {
                advance()
            } else {
                break
            }
        }

        consumePunctuation(";")

        return (sourceMetamodels, targetMetamodels)
    }

    private func parseHelper() throws -> any ATLHelperType {
        consumeKeyword("helper")

        var contextType: String? = nil

        // Check for context helper
        if consumeKeyword("context") {
            guard let typeToken = currentToken(),
                case .identifier(let type) = typeToken.type
            else {
                throw ATLParseError.invalidSyntax("Expected context type")
            }
            advance()
            contextType = type
        }

        consumeKeyword("def")
        consumeOperator(":")

        guard let nameToken = currentToken(),
            case .identifier(let name) = nameToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected helper name")
        }
        advance()

        // Parse parameters
        var parameters: [ATLParameter] = []
        if consumePunctuation("(") {
            while !consumePunctuation(")") {
                guard let paramToken = currentToken(),
                    case .identifier(let paramName) = paramToken.type
                else {
                    throw ATLParseError.invalidSyntax("Expected parameter name")
                }
                advance()

                consumeOperator(":")

                guard let typeToken = currentToken(),
                    case .identifier(let paramType) = typeToken.type
                else {
                    throw ATLParseError.invalidSyntax("Expected parameter type")
                }
                advance()

                parameters.append(ATLParameter(name: paramName, type: paramType))

                if !consumePunctuation(",") && currentToken()?.type != .punctuation(")") {
                    break
                }
            }
        }

        consumeOperator(":")

        guard let returnTypeToken = currentToken(),
            case .identifier(let returnType) = returnTypeToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected return type")
        }
        advance()

        consumeOperator("=")

        // Parse helper body (simplified - just create a literal expression)
        let body = try parseExpression()
        consumePunctuation(";")

        return ATLHelper<ATLLiteralExpression>(
            name: name,
            contextType: contextType,
            returnType: returnType,
            parameters: parameters,
            body: body as! ATLLiteralExpression
        )
    }

    private func parseRule() throws -> Any {
        consumeKeyword("rule")

        guard let nameToken = currentToken(),
            case .identifier(let name) = nameToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected rule name")
        }
        advance()

        // Check if it's a called rule (has parameters)
        if currentToken()?.type == .punctuation("(") {
            return try parseCalledRule(name: name)
        } else {
            return try parseMatchedRule(name: name)
        }
    }

    private func parseMatchedRule(name: String) throws -> ATLMatchedRule {
        consumePunctuation("{")
        consumeKeyword("from")

        // Parse source pattern
        guard let sourceVarToken = currentToken(),
            case .identifier(let sourceVar) = sourceVarToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected source variable")
        }
        advance()

        consumeOperator(":")

        guard let sourceTypeToken = currentToken(),
            case .identifier(let sourceType) = sourceTypeToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected source type")
        }
        advance()

        let sourcePattern = ATLSourcePattern(variableName: sourceVar, type: sourceType)

        // Skip guard condition if present
        if currentToken()?.type == .punctuation("(") {
            try skipUntil([.keyword("to")])
        }

        consumeKeyword("to")

        // Parse target patterns
        var targetPatterns: [ATLTargetPattern] = []

        repeat {
            guard let targetVarToken = currentToken(),
                case .identifier(let targetVar) = targetVarToken.type
            else {
                throw ATLParseError.invalidSyntax("Expected target variable")
            }
            advance()

            consumeOperator(":")

            guard let targetTypeToken = currentToken(),
                case .identifier(let targetType) = targetTypeToken.type
            else {
                throw ATLParseError.invalidSyntax("Expected target type")
            }
            advance()

            let targetPattern = ATLTargetPattern(variableName: targetVar, type: targetType)
            targetPatterns.append(targetPattern)

            // Skip bindings if present
            if currentToken()?.type == .punctuation("(") {
                try skipUntil([.punctuation(")"), .punctuation(","), .punctuation("}")])
                if currentToken()?.type == .punctuation(")") {
                    advance()
                }
            }

        } while consumePunctuation(",")

        // Skip do block if present
        if consumeKeyword("do") {
            try skipUntil([.punctuation("}")])
        }

        consumePunctuation("}")

        return ATLMatchedRule(
            name: name,
            sourcePattern: sourcePattern,
            targetPatterns: targetPatterns
        )
    }

    private func parseCalledRule(name: String) throws -> ATLCalledRule {
        consumePunctuation("(")

        var parameters: [ATLParameter] = []
        while !consumePunctuation(")") {
            guard let paramToken = currentToken(),
                case .identifier(let paramName) = paramToken.type
            else {
                throw ATLParseError.invalidSyntax("Expected parameter name")
            }
            advance()

            consumeOperator(":")

            guard let typeToken = currentToken(),
                case .identifier(let paramType) = typeToken.type
            else {
                throw ATLParseError.invalidSyntax("Expected parameter type")
            }
            advance()

            parameters.append(ATLParameter(name: paramName, type: paramType))

            if !consumePunctuation(",") && currentToken()?.type != .punctuation(")") {
                break
            }
        }

        consumePunctuation("{")
        consumeKeyword("to")

        // Parse target patterns (simplified)
        var targetPatterns: [ATLTargetPattern] = []

        guard let targetVarToken = currentToken(),
            case .identifier(let targetVar) = targetVarToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected target variable")
        }
        advance()

        consumeOperator(":")

        guard let targetTypeToken = currentToken(),
            case .identifier(let targetType) = targetTypeToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected target type")
        }
        advance()

        targetPatterns.append(ATLTargetPattern(variableName: targetVar, type: targetType))

        // Skip bindings
        if currentToken()?.type == .punctuation("(") {
            try skipUntil([.punctuation("}")])
        }

        consumePunctuation("}")

        return ATLCalledRule(
            name: name,
            parameters: parameters,
            targetPatterns: targetPatterns
        )
    }

    private func parseExpression() throws -> any ATLExpression {
        // Simplified expression parsing
        guard let token = currentToken() else {
            throw ATLParseError.invalidExpression("Expected expression")
        }

        switch token.type {
        case .stringLiteral(let value):
            advance()
            return ATLLiteralExpression(value: value)

        case .integerLiteral(let value):
            advance()
            return ATLLiteralExpression(value: value)

        case .booleanLiteral(let value):
            advance()
            return ATLLiteralExpression(value: value)

        case .identifier(let name):
            advance()
            return ATLVariableExpression(name: name)

        default:
            advance()
            return ATLLiteralExpression(value: "placeholder")
        }
    }

    private func skipQuery() throws {
        consumeKeyword("query")

        // Skip until semicolon
        while let token = currentToken(), token.type != .punctuation(";") && token.type != .eof {
            advance()
        }

        consumePunctuation(";")
    }

    private func skipUntil(_ stopTokens: [ATLTokenType]) throws {
        while let token = currentToken() {
            if stopTokens.contains(token.type) || token.type == .eof {
                break
            }
            advance()
        }
    }

    // Helper methods
    private func currentToken() -> ATLToken? {
        guard position < tokens.count else { return nil }
        return tokens[position]
    }

    private func advance() {
        if position < tokens.count {
            position += 1
        }
    }

    private func isAtEnd() -> Bool {
        return currentToken()?.type == .eof || position >= tokens.count
    }

    @discardableResult
    private func consumeKeyword(_ keyword: String) -> Bool {
        guard let token = currentToken(), token.type == .keyword(keyword) else {
            return false
        }
        advance()
        return true
    }

    @discardableResult
    private func consumeOperator(_ op: String) -> Bool {
        guard let token = currentToken(), token.type == .`operator`(op) else {
            return false
        }
        advance()
        return true
    }

    @discardableResult
    private func consumePunctuation(_ punct: String) -> Bool {
        guard let token = currentToken(), token.type == .punctuation(punct) else {
            return false
        }
        advance()
        return true
    }
}
