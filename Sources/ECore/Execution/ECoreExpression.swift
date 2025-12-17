//
// ECoreExpression.swift
// ECore
//
//  Created by Rene Hexel on 7/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Expression types supported by the execution engine.
///
/// These expressions provide the basic building blocks for model querying
/// and transformation operations, supporting navigation, variables, literals,
/// and method calls in a type-safe manner.
public indirect enum ECoreExpression: Sendable, Equatable, Hashable {
    /// Property navigation expression (object.property).
    case navigation(source: ECoreExpression, property: String)

    /// Variable reference expression.
    case variable(name: String)

    /// Literal value expression.
    case literal(value: ECoreExpressionValue)

    /// Method call expression.
    case methodCall(receiver: ECoreExpression, methodName: String, arguments: [ECoreExpression])

    /// Collection filter expression.
    case filter(collection: ECoreExpression, condition: ECoreExpression)

    /// Collection select expression.
    case select(collection: ECoreExpression, mapper: ECoreExpression)
}

/// Wrapper for EcoreValue types in expressions.
public enum ECoreExpressionValue: Sendable, Equatable, Hashable {
    case string(String)
    case int(Int)
    case boolean(Bool)
    case double(Double)
    case float(Float)
    case uuid(EUUID)
    case null

    /// Convert to Any for runtime usage.
    public var anyValue: Any? {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .boolean(let value): return value
        case .double(let value): return value
        case .float(let value): return value
        case .uuid(let value): return value
        case .null: return nil
        }
    }
}

extension ECoreExpression {
    /// Create a literal expression from an EcoreValue.
    public static func literal(_ value: any EcoreValue) -> ECoreExpression {
        let wrappedValue: ECoreExpressionValue

        switch value {
        case let stringValue as String:
            wrappedValue = .string(stringValue)
        case let intValue as Int:
            wrappedValue = .int(intValue)
        case let boolValue as Bool:
            wrappedValue = .boolean(boolValue)
        case let doubleValue as Double:
            wrappedValue = .double(doubleValue)
        case let floatValue as Float:
            wrappedValue = .float(floatValue)
        case let uuidValue as EUUID:
            wrappedValue = .uuid(uuidValue)
        default:
            // Fallback to string representation
            wrappedValue = .string(String(describing: value))
        }

        return .literal(value: wrappedValue)
    }
}

/// Errors that can occur during execution.
public enum ECoreExecutionError: Error, Sendable, Equatable, CustomStringConvertible {
    case unknownProperty(String, String)
    case invalidNavigation(String)
    case typeError(String)
    case readOnlyModel
    case readOnlyObject(EUUID)
    case unsupportedOperation(String)
    case evaluationError(String)

    public var description: String {
        switch self {
        case .unknownProperty(let property, let className):
            return "Unknown property '\(property)' on class '\(className)'"
        case .invalidNavigation(let message):
            return "Invalid navigation: \(message)"
        case .typeError(let message):
            return "Type error: \(message)"
        case .readOnlyModel:
            return "Cannot modify read-only model"
        case .readOnlyObject(let id):
            return "Cannot modify object in read-only model: \(id)"
        case .unsupportedOperation(let operation):
            return "Unsupported operation: \(operation)"
        case .evaluationError(let message):
            return "Evaluation error: \(message)"
        }
    }
}

/// Type provider for ECore type operations.
public struct EcoreTypeProvider: Sendable {
    /// Check if a value is compatible with a given EDataType.
    ///
    /// - Parameters:
    ///   - value: The value to check
    ///   - dataType: The target EDataType
    /// - Returns: `true` if the value is compatible
    public func isCompatible(_ value: Any?, with dataType: EDataType) -> Bool {
        guard let value = value else { return true }  // null is always compatible

        switch dataType.name {
        case "EString":
            return value is String
        case "EInt":
            return value is Int
        case "EBoolean":
            return value is Bool
        case "EDouble":
            return value is Double
        case "EFloat":
            return value is Float
        default:
            return true  // Default to compatible for custom types
        }
    }

    /// Convert a value to the appropriate Swift type for an EDataType.
    ///
    /// - Parameters:
    ///   - value: The value to convert
    ///   - dataType: The target EDataType
    /// - Returns: The converted value
    /// - Throws: `ECoreExecutionError` if conversion fails
    public func convert(_ value: Any?, to dataType: EDataType) throws -> Any? {
        guard let value = value else { return nil }

        switch dataType.name {
        case "EString":
            return String(describing: value)
        case "EInt":
            if let intValue = value as? Int {
                return intValue
            } else if let stringValue = value as? String, let intValue = Int(stringValue) {
                return intValue
            }
            throw ECoreExecutionError.typeError("Cannot convert \(value) to EInt")
        case "EBoolean":
            if let boolValue = value as? Bool {
                return boolValue
            } else if let stringValue = value as? String {
                return stringValue.lowercased() == "true"
            }
            throw ECoreExecutionError.typeError("Cannot convert \(value) to EBoolean")
        default:
            return value
        }
    }
}
