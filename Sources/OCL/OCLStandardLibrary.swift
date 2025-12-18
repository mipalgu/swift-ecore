//
// OCLStandardLibrary.swift
// OCL
//
//  Created by Rene Hexel on 18/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

// MARK: - Method Type Enums

/// Enumeration of OCL unary methods (methods that take only a receiver, no arguments).
public enum OCLUnaryMethod: String, CaseIterable, Sendable {
    // Collection query operations
    case size = "size"
    case isEmpty = "isEmpty"
    case notEmpty = "notEmpty"
    case first = "first"
    case last = "last"

    // Numeric operations
    case abs = "abs"
    case floor = "floor"
    case ceiling = "ceiling"
    case round = "round"

    // String operations
    case toUpperCase = "toUpperCase"
    case toLowerCase = "toLowerCase"
    case trim = "trim"

    // Logical operations
    case not = "not"

    // Type operations
    case oclIsUndefined = "oclIsUndefined"

    // Collection type conversions
    case asSet = "asSet"
    case asSequence = "asSequence"
    case asBag = "asBag"
    case asOrderedSet = "asOrderedSet"
    case flatten = "flatten"
}

/// Enumeration of OCL binary methods (methods that take a receiver and one argument).
public enum OCLBinaryMethod: String, CaseIterable, Sendable {
    // Arithmetic operations
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case modulo = "mod"

    // Comparison operations
    case equals = "="
    case notEquals = "<>"
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="

    // Logical operations
    case and = "and"
    case or = "or"
    case implies = "implies"

    // Numeric operations
    case max = "max"
    case min = "min"
    case power = "power"

    // String operations
    case concat = "concat"
    case indexOf = "indexOf"
    case contains = "contains"
    case startsWith = "startsWith"
    case endsWith = "endsWith"
    case at = "at"

    // Collection set operations
    case union = "union"
    case intersection = "intersection"
    case difference = "difference"
    case includes = "includes"
    case excludes = "excludes"
    case including = "including"
    case excluding = "excluding"
}

/// Enumeration of OCL ternary methods (methods that take a receiver and two arguments).
public enum OCLTernaryMethod: String, CaseIterable, Sendable {
    // String operations
    case substring = "substring"
    case replaceAll = "replaceAll"
}

// MARK: - OCL Standard Library

// OCL Standard Library - Type-safe method dispatch for dynamic invocation.
//
// This library provides strongly-typed method dispatch functionality using enums
// to categorise methods by their argument count. The execution engine can interrogate
// these enums to determine method availability and invoke them safely.
//
// ## Usage Example
//
// ```swift
// import OCL
//
// // Check if a method exists and invoke it
// if let size = OCLUnaryMethod(rawValue: "size") {
//     let result = try invokeUnaryMethod(size, on: collection)
//     print("Collection size: \(result)")
// }
// ```

// MARK: - Method Invocation

/// Invokes a unary method on a receiver value.
///
/// - Parameters:
///   - method: The unary method to invoke
///   - receiver: The receiver value
/// - Returns: The result of the method invocation
/// - Throws: OCLError if the method execution fails
public func invokeUnaryMethod(_ method: OCLUnaryMethod, on receiver: any EcoreValue) throws
    -> any EcoreValue
{
    switch method {
    // Collection query operations
    case .size:
        return try size(receiver) as any EcoreValue
    case .isEmpty:
        return try isEmpty(receiver) as any EcoreValue
    case .notEmpty:
        return try notEmpty(receiver) as any EcoreValue
    case .first:
        return try first(receiver)
    case .last:
        return try last(receiver)

    // Numeric operations
    case .abs:
        return try abs(receiver)
    case .floor:
        return try floor(receiver) as any EcoreValue
    case .ceiling:
        return try ceiling(receiver) as any EcoreValue
    case .round:
        return try round(receiver) as any EcoreValue

    // String operations
    case .toUpperCase:
        return try toUpperCase(receiver)
    case .toLowerCase:
        return try toLowerCase(receiver)
    case .trim:
        return try trim(receiver)

    // Logical operations
    case .not:
        return try not(receiver) as any EcoreValue

    // Type operations
    case .oclIsUndefined:
        // For non-nil receiver, oclIsUndefined always returns false
        return false as any EcoreValue

    // Collection type conversions
    case .asSet:
        return EcoreValueArray(try asSet(receiver))
    case .asSequence:
        return EcoreValueArray(try asSequence(receiver))
    case .asBag:
        return EcoreValueArray(try asBag(receiver))
    case .asOrderedSet:
        return EcoreValueArray(try asOrderedSet(receiver))
    case .flatten:
        return EcoreValueArray(try flatten(receiver))
    }
}

/// Invokes a binary method on a receiver value with one argument.
///
/// - Parameters:
///   - method: The binary method to invoke
///   - receiver: The receiver value
///   - argument: The argument value
/// - Returns: The result of the method invocation
/// - Throws: OCLError if the method execution fails
public func invokeBinaryMethod(
    _ method: OCLBinaryMethod, on receiver: any EcoreValue, with argument: any EcoreValue
) throws -> any EcoreValue {
    switch method {
    // Arithmetic operations
    case .add:
        return try add(receiver, argument)
    case .subtract:
        return try subtract(receiver, argument)
    case .multiply:
        return try multiply(receiver, argument)
    case .divide:
        return try divide(receiver, argument)
    case .modulo:
        return try modulo(receiver, argument)

    // Comparison operations
    case .equals:
        return equals(receiver, argument) as any EcoreValue
    case .notEquals:
        return notEquals(receiver, argument) as any EcoreValue
    case .lessThan:
        return try lessThan(receiver, argument) as any EcoreValue
    case .lessThanOrEqual:
        return try lessThanOrEqual(receiver, argument) as any EcoreValue
    case .greaterThan:
        return try greaterThan(receiver, argument) as any EcoreValue
    case .greaterThanOrEqual:
        return try greaterThanOrEqual(receiver, argument) as any EcoreValue

    // Logical operations
    case .and:
        return try and(receiver, argument) as any EcoreValue
    case .or:
        return try or(receiver, argument) as any EcoreValue
    case .implies:
        return try implies(receiver, argument) as any EcoreValue

    // Numeric operations
    case .max:
        return try max(receiver, argument)
    case .min:
        return try min(receiver, argument)
    case .power:
        return try power(receiver, argument)

    // String operations
    case .concat:
        return try concat(receiver, argument)
    case .indexOf:
        return try indexOf(receiver, argument) as any EcoreValue
    case .contains:
        return try contains(receiver, argument) as any EcoreValue
    case .startsWith:
        return try startsWith(receiver, argument) as any EcoreValue
    case .endsWith:
        return try endsWith(receiver, argument) as any EcoreValue
    case .at:
        return try at(receiver, argument)

    // Collection set operations
    case .union:
        return EcoreValueArray(try union(receiver, argument))
    case .intersection:
        return EcoreValueArray(try intersection(receiver, argument))
    case .difference:
        return EcoreValueArray(try difference(receiver, argument))
    case .includes:
        return try includes(receiver, argument) as any EcoreValue
    case .excludes:
        return try excludes(receiver, argument) as any EcoreValue
    case .including:
        return EcoreValueArray(try including(receiver, argument))
    case .excluding:
        return EcoreValueArray(try excluding(receiver, argument))
    }
}

/// Invokes a ternary method on a receiver value with two arguments.
///
/// - Parameters:
///   - method: The ternary method to invoke
///   - receiver: The receiver value
///   - arg1: The first argument value
///   - arg2: The second argument value
/// - Returns: The result of the method invocation
/// - Throws: OCLError if the method execution fails
public func invokeTernaryMethod(
    _ method: OCLTernaryMethod, on receiver: any EcoreValue, with arg1: any EcoreValue,
    and arg2: any EcoreValue
) throws -> any EcoreValue {
    switch method {
    // String operations
    case .substring:
        return try substring(receiver, arg1, arg2)
    case .replaceAll:
        return try replaceAll(receiver, arg1, arg2)
    }
}
