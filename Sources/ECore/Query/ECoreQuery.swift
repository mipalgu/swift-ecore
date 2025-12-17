//
// ECoreQuery.swift
// ECore
//
//  Created by Rene Hexel on 7/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Query framework for ECore models inspired by OCL.
///
/// The query framework provides a higher-level interface for model querying,
/// supporting OCL-like expressions whilst maintaining type safety and performance.
/// Queries are parsed into expression trees and evaluated using the core execution engine.
public struct ECoreQuery: Sendable, Equatable, Hashable {
    /// The query expression string.
    public let expression: String

    /// Optional context type for 'self' binding.
    public let contextType: EClass?

    /// Creates a new query with the given expression.
    ///
    /// - Parameters:
    ///   - expression: The query expression string
    ///   - context: Optional context type for 'self' references
    public init(_ expression: String, context: EClass? = nil) {
        self.expression = expression
        self.contextType = context
    }
}

/// Query evaluator that converts string expressions to executable code.
public actor ECoreQueryEvaluator: Sendable {
    private let executionEngine: ECoreExecutionEngine
    private let parser: ECoreQueryParser

    /// Creates a new query evaluator.
    ///
    /// - Parameter executionEngine: The execution engine to use for evaluation
    public init(executionEngine: ECoreExecutionEngine) {
        self.executionEngine = executionEngine
        self.parser = ECoreQueryParser()
    }

    /// Evaluate a query on the given object.
    ///
    /// - Parameters:
    ///   - query: The query to evaluate
    ///   - object: The object to evaluate the query against (becomes 'self')
    /// - Returns: The query result
    /// - Throws: `ECoreExecutionError` if evaluation fails
    public func evaluate(
        _ query: ECoreQuery,
        on object: any EObject
    ) async throws -> (any EcoreValue)? {
        let ast = try parser.parse(query.expression)
        let context: [String: any EcoreValue] = ["self": object]
        return try await executionEngine.evaluate(ast, context: context)
    }

    /// Evaluate a query with custom variable bindings.
    ///
    /// - Parameters:
    ///   - query: The query to evaluate
    ///   - context: Variable bindings for evaluation
    /// - Returns: The query result
    /// - Throws: `ECoreQueryError` if evaluation fails
    public func evaluate(
        _ query: ECoreQuery,
        context: [String: any EcoreValue]
    ) async throws -> (any EcoreValue)? {
        let ast = try parser.parse(query.expression)
        return try await executionEngine.evaluate(ast, context: context)
    }
}

/// Simple query parser for basic expressions.
///
/// This parser handles basic navigation expressions and can be extended
/// to support more complex OCL-like constructs.
public struct ECoreQueryParser: Sendable {
    /// Parse a query expression into an abstract syntax tree.
    ///
    /// - Parameter expression: The expression string to parse
    /// - Returns: The parsed expression tree
    /// - Throws: `ECoreQueryError` if parsing fails
    public func parse(_ expression: String) throws -> ECoreExpression {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle method calls like self.property.size()
        if let methodRange = trimmed.range(of: #"\.\w+\(\)$"#, options: .regularExpression) {
            let baseExpression = String(trimmed[..<methodRange.lowerBound])
            let methodCall = String(trimmed[methodRange])
            let methodName = String(methodCall.dropFirst().dropLast(2))  // Remove . and ()

            let baseExpr = try parse(baseExpression)
            return .methodCall(receiver: baseExpr, methodName: methodName, arguments: [])
        }

        // Handle simple navigation: self.property (but not chained like self.property.subproperty)
        if trimmed.hasPrefix("self.") && !trimmed.dropFirst(5).contains(".") {
            let property = String(trimmed.dropFirst(5))
            return .navigation(source: .variable(name: "self"), property: property)
        }

        // Handle string literals first (before variables)
        if trimmed.hasPrefix("'") && trimmed.hasSuffix("'") {
            let content = String(trimmed.dropFirst().dropLast())
            return .literal(value: .string(content))
        }

        // Handle string literals with double quotes
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
            let content = String(trimmed.dropFirst().dropLast())
            return .literal(value: .string(content))
        }

        // Handle boolean literals before other checks
        if trimmed == "true" {
            return .literal(value: .boolean(true))
        } else if trimmed == "false" {
            return .literal(value: .boolean(false))
        }

        // Handle null literal
        if trimmed == "null" {
            return .literal(value: .null)
        }

        // Handle integer literals
        if let intValue = Int(trimmed) {
            return .literal(value: .int(intValue))
        }

        // Handle double literals
        if let doubleValue = Double(trimmed) {
            return .literal(value: .double(doubleValue))
        }

        // Handle chained navigation: self.property.subproperty
        if trimmed.hasPrefix("self") && trimmed.contains(".") {
            let parts = trimmed.components(separatedBy: ".")
            guard parts.count >= 2 else {
                throw ECoreQueryError.parseError("Invalid navigation expression: \(trimmed)")
            }

            var expr: ECoreExpression = .variable(name: parts[0])
            for property in parts[1...] {
                expr = .navigation(source: expr, property: property)
            }
            return expr
        }

        // Handle variable references (last, after all literals)
        if trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
            return .variable(name: trimmed)
        }

        throw ECoreQueryError.parseError("Unsupported expression: \(expression)")
    }
}

/// Errors that can occur during query parsing.
public enum ECoreQueryError: Error, Sendable, Equatable, CustomStringConvertible {
    case parseError(String)
    case unsupportedConstruct(String)

    public var description: String {
        switch self {
        case .parseError(let message):
            return "Parse error: \(message)"
        case .unsupportedConstruct(let construct):
            return "Unsupported construct: \(construct)"
        }
    }
}

// MARK: - Convenience Query Builders

extension ECoreQuery {
    /// Create a navigation query.
    ///
    /// - Parameters:
    ///   - from: The starting variable (typically "self")
    ///   - property: The property to navigate to
    /// - Returns: A new query for the navigation
    public static func navigate(from: String = "self", to property: String) -> ECoreQuery {
        return ECoreQuery("\(from).\(property)")
    }

    /// Create a method call query.
    ///
    /// - Parameters:
    ///   - from: The starting variable (typically "self")
    ///   - property: The property to navigate to
    ///   - method: The method to call
    /// - Returns: A new query for the method call
    public static func call(from: String = "self", property: String, method: String) -> ECoreQuery {
        return ECoreQuery("\(from).\(property).\(method)()")
    }

    /// Create a literal value query.
    ///
    /// - Parameter value: The literal value
    /// - Returns: A new query for the literal
    public static func literal<T: EcoreValue>(_ value: T) -> ECoreQuery {
        return ECoreQuery("\(value)")
    }
}
