//
// OCLBinaryOperations.swift
// OCL
//
//  Created by Rene Hexel on 18/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import BigInt
public import EMFBase
import Foundation

// MARK: - Arithmetic Operations

/// Adds two values together.
///
/// Supports addition of numeric types (Int, Double, Float) with automatic type coercion.
/// String concatenation is also supported when both operands are strings.
///
/// ## Type Coercion Rules
/// - Int + Int → Int
/// - Double + Double → Double
/// - Int + Double → Double (Int is promoted to Double)
/// - String + String → String (concatenation)
///
/// - Parameters:
///   - left: The left operand
///   - right: The right operand
/// - Returns: The sum of the operands
/// - Throws: `OCLError.invalidArguments` if operands cannot be added
@inlinable
public func add(_ left: any EcoreValue, _ right: any EcoreValue) throws -> any EcoreValue {
    switch (left, right) {
    // String concatenation
    case (let l as EString, let r as EString):
        return l + r

    // Integer-Integer combinations - promote to largest type
    case (let l as EByte, let r as EByte):
        return l + r
    case (let l as EByte, let r as EShort):
        return EShort(l) + r
    case (let l as EShort, let r as EByte):
        return l + EShort(r)
    case (let l as EShort, let r as EShort):
        return l + r
    case (let l as EByte, let r as EInt):
        return EInt(l) + r
    case (let l as EInt, let r as EByte):
        return l + EInt(r)
    case (let l as EShort, let r as EInt):
        return EInt(l) + r
    case (let l as EInt, let r as EShort):
        return l + EInt(r)
    case (let l as EInt, let r as EInt):
        return l + r
    case (let l as EByte, let r as ELong):
        return ELong(l) + r
    case (let l as ELong, let r as EByte):
        return l + ELong(r)
    case (let l as EShort, let r as ELong):
        return ELong(l) + r
    case (let l as ELong, let r as EShort):
        return l + ELong(r)
    case (let l as EInt, let r as ELong):
        return ELong(l) + r
    case (let l as ELong, let r as EInt):
        return l + ELong(r)
    case (let l as ELong, let r as ELong):
        return l + r

    // BigInteger combinations - BigInteger dominates
    case (let l as EBigInteger, let r as EBigInteger):
        return l + r
    case (let l as EByte, let r as EBigInteger):
        return EBigInteger(l) + r
    case (let l as EBigInteger, let r as EByte):
        return l + EBigInteger(r)
    case (let l as EShort, let r as EBigInteger):
        return EBigInteger(l) + r
    case (let l as EBigInteger, let r as EShort):
        return l + EBigInteger(r)
    case (let l as EInt, let r as EBigInteger):
        return EBigInteger(l) + r
    case (let l as EBigInteger, let r as EInt):
        return l + EBigInteger(r)
    case (let l as ELong, let r as EBigInteger):
        return EBigInteger(l) + r
    case (let l as EBigInteger, let r as ELong):
        return l + EBigInteger(r)

    // Real-Real combinations - promote to most precise type
    case (let l as EFloat, let r as EFloat):
        return l + r
    case (let l as EFloat, let r as EDouble):
        return EDouble(l) + r
    case (let l as EDouble, let r as EFloat):
        return l + EDouble(r)
    case (let l as EDouble, let r as EDouble):
        return l + r
    case (let l as EFloat, let r as EBigDecimal):
        return EBigDecimal(Double(l)) + r
    case (let l as EBigDecimal, let r as EFloat):
        return l + EBigDecimal(Double(r))
    case (let l as EDouble, let r as EBigDecimal):
        return EBigDecimal(l) + r
    case (let l as EBigDecimal, let r as EDouble):
        return l + EBigDecimal(r)
    case (let l as EBigDecimal, let r as EBigDecimal):
        return l + r

    // Integer-Real combinations - promote to Real
    case (let l as EByte, let r as EFloat):
        return EFloat(l) + r
    case (let l as EFloat, let r as EByte):
        return l + EFloat(r)
    case (let l as EShort, let r as EFloat):
        return EFloat(l) + r
    case (let l as EFloat, let r as EShort):
        return l + EFloat(r)
    case (let l as EInt, let r as EFloat):
        return EFloat(l) + r
    case (let l as EFloat, let r as EInt):
        return l + EFloat(r)
    case (let l as ELong, let r as EFloat):
        return EFloat(l) + r
    case (let l as EFloat, let r as ELong):
        return l + EFloat(r)
    case (let l as EByte, let r as EDouble):
        return EDouble(l) + r
    case (let l as EDouble, let r as EByte):
        return l + EDouble(r)
    case (let l as EShort, let r as EDouble):
        return EDouble(l) + r
    case (let l as EDouble, let r as EShort):
        return l + EDouble(r)
    case (let l as EInt, let r as EDouble):
        return EDouble(l) + r
    case (let l as EDouble, let r as EInt):
        return l + EDouble(r)
    case (let l as ELong, let r as EDouble):
        return EDouble(l) + r
    case (let l as EDouble, let r as ELong):
        return l + EDouble(r)
    case (let l as EByte, let r as EBigDecimal):
        return EBigDecimal(Int(l)) + r
    case (let l as EBigDecimal, let r as EByte):
        return l + EBigDecimal(Int(r))
    case (let l as EShort, let r as EBigDecimal):
        return EBigDecimal(Int(l)) + r
    case (let l as EBigDecimal, let r as EShort):
        return l + EBigDecimal(Int(r))
    case (let l as EInt, let r as EBigDecimal):
        return EBigDecimal(l) + r
    case (let l as EBigDecimal, let r as EInt):
        return l + EBigDecimal(r)
    case (let l as ELong, let r as EBigDecimal):
        return EBigDecimal(Double(l)) + r
    case (let l as EBigDecimal, let r as ELong):
        return l + EBigDecimal(Double(r))

    // BigInteger-Real combinations - promote to Real
    case (let l as EBigInteger, let r as EFloat):
        let doubleVal = Double(l.description) ?? 0
        return EFloat(doubleVal) + r
    case (let l as EFloat, let r as EBigInteger):
        let doubleVal = Double(r.description) ?? 0
        return l + EFloat(doubleVal)
    case (let l as EBigInteger, let r as EDouble):
        let doubleVal = Double(l.description) ?? 0
        return doubleVal + r
    case (let l as EDouble, let r as EBigInteger):
        let doubleVal = Double(r.description) ?? 0
        return l + doubleVal
    case (let l as EBigInteger, let r as EBigDecimal):
        let decimalVal = EBigDecimal(Double(l.description) ?? 0)
        return decimalVal + r
    case (let l as EBigDecimal, let r as EBigInteger):
        let decimalVal = EBigDecimal(Double(r.description) ?? 0)
        return l + decimalVal

    default:
        throw OCLError.invalidArguments(
            "Cannot add values of types \(type(of: left)) and \(type(of: right))")
    }
}

/// Subtracts the right value from the left value.
///
/// Supports subtraction of numeric types with automatic type coercion.
///
/// - Parameters:
///   - left: The left operand (minuend)
///   - right: The right operand (subtrahend)
/// - Returns: The difference of the operands
/// - Throws: `OCLError.invalidArguments` if operands cannot be subtracted
@inlinable
public func subtract(_ left: any EcoreValue, _ right: any EcoreValue) throws -> any EcoreValue {
    switch (left, right) {
    // Integer-Integer combinations - promote to largest type
    case (let l as EByte, let r as EByte):
        return l - r
    case (let l as EByte, let r as EShort):
        return EShort(l) - r
    case (let l as EShort, let r as EByte):
        return l - EShort(r)
    case (let l as EShort, let r as EShort):
        return l - r
    case (let l as EByte, let r as EInt):
        return EInt(l) - r
    case (let l as EInt, let r as EByte):
        return l - EInt(r)
    case (let l as EShort, let r as EInt):
        return EInt(l) - r
    case (let l as EInt, let r as EShort):
        return l - EInt(r)
    case (let l as EInt, let r as EInt):
        return l - r
    case (let l as EByte, let r as ELong):
        return ELong(l) - r
    case (let l as ELong, let r as EByte):
        return l - ELong(r)
    case (let l as EShort, let r as ELong):
        return ELong(l) - r
    case (let l as ELong, let r as EShort):
        return l - ELong(r)
    case (let l as EInt, let r as ELong):
        return ELong(l) - r
    case (let l as ELong, let r as EInt):
        return l - ELong(r)
    case (let l as ELong, let r as ELong):
        return l - r

    // BigInteger combinations - BigInteger dominates
    case (let l as EBigInteger, let r as EBigInteger):
        return l - r
    case (let l as EByte, let r as EBigInteger):
        return EBigInteger(l) - r
    case (let l as EBigInteger, let r as EByte):
        return l - EBigInteger(r)
    case (let l as EShort, let r as EBigInteger):
        return EBigInteger(l) - r
    case (let l as EBigInteger, let r as EShort):
        return l - EBigInteger(r)
    case (let l as EInt, let r as EBigInteger):
        return EBigInteger(l) - r
    case (let l as EBigInteger, let r as EInt):
        return l - EBigInteger(r)
    case (let l as ELong, let r as EBigInteger):
        return EBigInteger(l) - r
    case (let l as EBigInteger, let r as ELong):
        return l - EBigInteger(r)

    // Real-Real combinations - promote to most precise type
    case (let l as EFloat, let r as EFloat):
        return l - r
    case (let l as EFloat, let r as EDouble):
        return EDouble(l) - r
    case (let l as EDouble, let r as EFloat):
        return l - EDouble(r)
    case (let l as EDouble, let r as EDouble):
        return l - r
    case (let l as EFloat, let r as EBigDecimal):
        return EBigDecimal(Double(l)) - r
    case (let l as EBigDecimal, let r as EFloat):
        return l - EBigDecimal(Double(r))
    case (let l as EDouble, let r as EBigDecimal):
        return EBigDecimal(l) - r
    case (let l as EBigDecimal, let r as EDouble):
        return l - EBigDecimal(r)
    case (let l as EBigDecimal, let r as EBigDecimal):
        return l - r

    // Integer-Real combinations - promote to Real
    case (let l as EByte, let r as EFloat):
        return EFloat(l) - r
    case (let l as EFloat, let r as EByte):
        return l - EFloat(r)
    case (let l as EShort, let r as EFloat):
        return EFloat(l) - r
    case (let l as EFloat, let r as EShort):
        return l - EFloat(r)
    case (let l as EInt, let r as EFloat):
        return EFloat(l) - r
    case (let l as EFloat, let r as EInt):
        return l - EFloat(r)
    case (let l as ELong, let r as EFloat):
        return EFloat(l) - r
    case (let l as EFloat, let r as ELong):
        return l - EFloat(r)
    case (let l as EByte, let r as EDouble):
        return EDouble(l) - r
    case (let l as EDouble, let r as EByte):
        return l - EDouble(r)
    case (let l as EShort, let r as EDouble):
        return EDouble(l) - r
    case (let l as EDouble, let r as EShort):
        return l - EDouble(r)
    case (let l as EInt, let r as EDouble):
        return EDouble(l) - r
    case (let l as EDouble, let r as EInt):
        return l - EDouble(r)
    case (let l as ELong, let r as EDouble):
        return EDouble(l) - r
    case (let l as EDouble, let r as ELong):
        return l - EDouble(r)
    case (let l as EByte, let r as EBigDecimal):
        return EBigDecimal(Int(l)) - r
    case (let l as EBigDecimal, let r as EByte):
        return l - EBigDecimal(Int(r))
    case (let l as EShort, let r as EBigDecimal):
        return EBigDecimal(Int(l)) - r
    case (let l as EBigDecimal, let r as EShort):
        return l - EBigDecimal(Int(r))
    case (let l as EInt, let r as EBigDecimal):
        return EBigDecimal(l) - r
    case (let l as EBigDecimal, let r as EInt):
        return l - EBigDecimal(r)
    case (let l as ELong, let r as EBigDecimal):
        return EBigDecimal(Double(l)) - r
    case (let l as EBigDecimal, let r as ELong):
        return l - EBigDecimal(Double(r))

    // BigInteger-Real combinations - promote to Real
    case (let l as EBigInteger, let r as EFloat):
        let doubleVal = Double(l.description) ?? 0
        return EFloat(doubleVal) - r
    case (let l as EFloat, let r as EBigInteger):
        let doubleVal = Double(r.description) ?? 0
        return l - EFloat(doubleVal)
    case (let l as EBigInteger, let r as EDouble):
        let doubleVal = Double(l.description) ?? 0
        return doubleVal - r
    case (let l as EDouble, let r as EBigInteger):
        let doubleVal = Double(r.description) ?? 0
        return l - doubleVal
    case (let l as EBigInteger, let r as EBigDecimal):
        let decimalVal = EBigDecimal(Double(l.description) ?? 0)
        return decimalVal - r
    case (let l as EBigDecimal, let r as EBigInteger):
        let decimalVal = EBigDecimal(Double(r.description) ?? 0)
        return l - decimalVal

    default:
        throw OCLError.invalidArguments(
            "Cannot subtract values of types \(type(of: left)) and \(type(of: right))")
    }
}

/// Multiplies two values together.
///
/// Supports multiplication of numeric types with automatic type coercion.
///
/// - Parameters:
///   - left: The left operand
///   - right: The right operand
/// - Returns: The product of the operands
/// - Throws: `OCLError.invalidArguments` if operands cannot be multiplied
@inlinable
public func multiply(_ left: any EcoreValue, _ right: any EcoreValue) throws -> any EcoreValue {
    switch (left, right) {
    case (let l as EInt, let r as EInt):
        return l * r
    case (let l as EDouble, let r as EDouble):
        return l * r
    case (let l as EFloat, let r as EFloat):
        return l * r
    case (let l as EInt, let r as EDouble):
        return EDouble(l) * r
    case (let l as EDouble, let r as EInt):
        return l * EDouble(r)
    case (let l as EInt, let r as EFloat):
        return EFloat(l) * r
    case (let l as EFloat, let r as EInt):
        return l * EFloat(r)
    case (let l as EFloat, let r as EDouble):
        return EDouble(l) * r
    case (let l as EDouble, let r as EFloat):
        return l * EDouble(r)
    default:
        throw OCLError.invalidArguments(
            "Cannot multiply values of types \(type(of: left)) and \(type(of: right))")
    }
}

/// Divides the left value by the right value.
///
/// Supports division of numeric types with automatic type coercion.
/// Division by zero throws an error.
///
/// - Parameters:
///   - left: The left operand (dividend)
///   - right: The right operand (divisor)
/// - Returns: The quotient of the operands
/// - Throws: `OCLError.divisionByZero` if right operand is zero
/// - Throws: `OCLError.invalidArguments` if operands cannot be divided
@inlinable
public func divide(_ left: any EcoreValue, _ right: any EcoreValue) throws -> any EcoreValue {
    switch (left, right) {
    case (let l as EInt, let r as EInt):
        guard r != 0 else { throw OCLError.divisionByZero }
        return l / r
    case (let l as EDouble, let r as EDouble):
        guard r != 0.0 else { throw OCLError.divisionByZero }
        return l / r
    case (let l as EFloat, let r as EFloat):
        guard r != 0.0 else { throw OCLError.divisionByZero }
        return l / r
    case (let l as EInt, let r as EDouble):
        guard r != 0.0 else { throw OCLError.divisionByZero }
        return EDouble(l) / r
    case (let l as EDouble, let r as EInt):
        guard r != 0 else { throw OCLError.divisionByZero }
        return l / EDouble(r)
    case (let l as EInt, let r as EFloat):
        guard r != 0.0 else { throw OCLError.divisionByZero }
        return EFloat(l) / r
    case (let l as EFloat, let r as EInt):
        guard r != 0 else { throw OCLError.divisionByZero }
        return l / EFloat(r)
    case (let l as EFloat, let r as EDouble):
        guard r != 0.0 else { throw OCLError.divisionByZero }
        return EDouble(l) / r
    case (let l as EDouble, let r as EFloat):
        guard r != 0.0 else { throw OCLError.divisionByZero }
        return l / EDouble(r)
    default:
        throw OCLError.invalidArguments(
            "Cannot divide values of types \(type(of: left)) and \(type(of: right))")
    }
}

/// Computes the remainder of dividing the left value by the right value.
///
/// Supports modulo of integer types only. Division by zero throws an error.
///
/// - Parameters:
///   - left: The left operand (dividend)
///   - right: The right operand (divisor)
/// - Returns: The remainder of the division
/// - Throws: `OCLError.divisionByZero` if right operand is zero
/// - Throws: `OCLError.invalidArguments` if operands are not integers
@inlinable
public func modulo(_ left: any EcoreValue, _ right: any EcoreValue) throws -> any EcoreValue {
    switch (left, right) {
    case (let l as EInt, let r as EInt):
        guard r != 0 else { throw OCLError.divisionByZero }
        return l % r
    default:
        throw OCLError.invalidArguments(
            "Modulo operation requires integer operands, got \(type(of: left)) and \(type(of: right))"
        )
    }
}

// MARK: - Comparison Operations

/// Tests whether the left value is less than the right value.
///
/// Supports comparison of numeric and string types with automatic type coercion for numbers.
///
/// - Parameters:
///   - left: The left operand
///   - right: The right operand
/// - Returns: `true` if left is less than right, `false` otherwise
/// - Throws: `OCLError.invalidArguments` if operands cannot be compared
@inlinable
public func lessThan(_ left: any EcoreValue, _ right: any EcoreValue) throws -> EBoolean {
    switch (left, right) {
    case (let l as EInt, let r as EInt):
        return l < r
    case (let l as EDouble, let r as EDouble):
        return l < r
    case (let l as EFloat, let r as EFloat):
        return l < r
    case (let l as EString, let r as EString):
        return l < r
    case (let l as EInt, let r as EDouble):
        return EDouble(l) < r
    case (let l as EDouble, let r as EInt):
        return l < EDouble(r)
    case (let l as EInt, let r as EFloat):
        return EFloat(l) < r
    case (let l as EFloat, let r as EInt):
        return l < EFloat(r)
    case (let l as EFloat, let r as EDouble):
        return EDouble(l) < r
    case (let l as EDouble, let r as EFloat):
        return l < EDouble(r)
    default:
        throw OCLError.invalidArguments(
            "Cannot compare values of types \(type(of: left)) and \(type(of: right))")
    }
}

/// Tests whether the left value is less than or equal to the right value.
///
/// Supports comparison of numeric and string types with automatic type coercion for numbers.
///
/// - Parameters:
///   - left: The left operand
///   - right: The right operand
/// - Returns: `true` if left is less than or equal to right, `false` otherwise
/// - Throws: `OCLError.invalidArguments` if operands cannot be compared
@inlinable
public func lessThanOrEqual(_ left: any EcoreValue, _ right: any EcoreValue) throws -> EBoolean {
    switch (left, right) {
    case (let l as EInt, let r as EInt):
        return l <= r
    case (let l as EDouble, let r as EDouble):
        return l <= r
    case (let l as EFloat, let r as EFloat):
        return l <= r
    case (let l as EString, let r as EString):
        return l <= r
    case (let l as EInt, let r as EDouble):
        return EDouble(l) <= r
    case (let l as EDouble, let r as EInt):
        return l <= EDouble(r)
    case (let l as EInt, let r as EFloat):
        return EFloat(l) <= r
    case (let l as EFloat, let r as EInt):
        return l <= EFloat(r)
    case (let l as EFloat, let r as EDouble):
        return EDouble(l) <= r
    case (let l as EDouble, let r as EFloat):
        return l <= EDouble(r)
    default:
        throw OCLError.invalidArguments(
            "Cannot compare values of types \(type(of: left)) and \(type(of: right))")
    }
}

/// Tests whether the left value is greater than the right value.
///
/// Supports comparison of numeric and string types with automatic type coercion for numbers.
///
/// - Parameters:
///   - left: The left operand
///   - right: The right operand
/// - Returns: `true` if left is greater than right, `false` otherwise
/// - Throws: `OCLError.invalidArguments` if operands cannot be compared
@inlinable
public func greaterThan(_ left: any EcoreValue, _ right: any EcoreValue) throws -> EBoolean {
    switch (left, right) {
    case (let l as EInt, let r as EInt):
        return l > r
    case (let l as EDouble, let r as EDouble):
        return l > r
    case (let l as EFloat, let r as EFloat):
        return l > r
    case (let l as EString, let r as EString):
        return l > r
    case (let l as EInt, let r as EDouble):
        return EDouble(l) > r
    case (let l as EDouble, let r as EInt):
        return l > EDouble(r)
    case (let l as EInt, let r as EFloat):
        return EFloat(l) > r
    case (let l as EFloat, let r as EInt):
        return l > EFloat(r)
    case (let l as EFloat, let r as EDouble):
        return EDouble(l) > r
    case (let l as EDouble, let r as EFloat):
        return l > EDouble(r)
    default:
        throw OCLError.invalidArguments(
            "Cannot compare values of types \(type(of: left)) and \(type(of: right))")
    }
}

/// Tests whether the left value is greater than or equal to the right value.
///
/// Supports comparison of numeric and string types with automatic type coercion for numbers.
///
/// - Parameters:
///   - left: The left operand
///   - right: The right operand
/// - Returns: `true` if left is greater than or equal to right, `false` otherwise
/// - Throws: `OCLError.invalidArguments` if operands cannot be compared
@inlinable
public func greaterThanOrEqual(_ left: any EcoreValue, _ right: any EcoreValue) throws -> EBoolean {
    switch (left, right) {
    case (let l as EInt, let r as EInt):
        return l >= r
    case (let l as EDouble, let r as EDouble):
        return l >= r
    case (let l as EFloat, let r as EFloat):
        return l >= r
    case (let l as EString, let r as EString):
        return l >= r
    case (let l as EInt, let r as EDouble):
        return EDouble(l) >= r
    case (let l as EDouble, let r as EInt):
        return l >= EDouble(r)
    case (let l as EInt, let r as EFloat):
        return EFloat(l) >= r
    case (let l as EFloat, let r as EInt):
        return l >= EFloat(r)
    case (let l as EFloat, let r as EDouble):
        return EDouble(l) >= r
    case (let l as EDouble, let r as EFloat):
        return l >= EDouble(r)
    default:
        throw OCLError.invalidArguments(
            "Cannot compare values of types \(type(of: left)) and \(type(of: right))")
    }
}

/// Tests whether two values are equal.
///
/// Uses the EMFBase `areEqual` function to perform type-safe equality comparison
/// across all EcoreValue types.
///
/// - Parameters:
///   - left: The left operand
///   - right: The right operand
/// - Returns: `true` if the values are equal, `false` otherwise
@inlinable
public func equals(_ left: any EcoreValue, _ right: any EcoreValue) -> EBoolean {
    return areEqual(left, right)
}

/// Tests whether two values are not equal.
///
/// Uses the EMFBase `areEqual` function to perform type-safe equality comparison
/// and returns the negation of the result.
///
/// - Parameters:
///   - left: The left operand
///   - right: The right operand
/// - Returns: `true` if the values are not equal, `false` otherwise
@inlinable
public func notEquals(_ left: any EcoreValue, _ right: any EcoreValue) -> EBoolean {
    return !areEqual(left, right)
}

// MARK: - Logical Operations

/// Performs logical AND operation on two boolean values.
///
/// Both operands must be boolean values. The result is `true` only if both operands are `true`.
///
/// - Parameters:
///   - left: The left boolean operand
///   - right: The right boolean operand
/// - Returns: The logical AND of the operands
/// - Throws: `OCLError.typeError` if either operand is not a boolean
@inlinable
public func and(_ left: any EcoreValue, _ right: any EcoreValue) throws -> EBoolean {
    guard let leftBool = left as? EBoolean else {
        throw OCLError.typeError("Left operand of 'and' must be boolean, got \(type(of: left))")
    }
    guard let rightBool = right as? EBoolean else {
        throw OCLError.typeError("Right operand of 'and' must be boolean, got \(type(of: right))")
    }
    return leftBool && rightBool
}

/// Performs logical OR operation on two boolean values.
///
/// Both operands must be boolean values. The result is `true` if at least one operand is `true`.
///
/// - Parameters:
///   - left: The left boolean operand
///   - right: The right boolean operand
/// - Returns: The logical OR of the operands
/// - Throws: `OCLError.typeError` if either operand is not a boolean
@inlinable
public func or(_ left: any EcoreValue, _ right: any EcoreValue) throws -> EBoolean {
    guard let leftBool = left as? EBoolean else {
        throw OCLError.typeError("Left operand of 'or' must be boolean, got \(type(of: left))")
    }
    guard let rightBool = right as? EBoolean else {
        throw OCLError.typeError("Right operand of 'or' must be boolean, got \(type(of: right))")
    }
    return leftBool || rightBool
}

/// Performs logical implication operation on two boolean values.
///
/// The implication `left implies right` is equivalent to `not left or right`.
/// It returns `false` only when the left operand is `true` and the right operand is `false`.
///
/// - Parameters:
///   - left: The left boolean operand (antecedent)
///   - right: The right boolean operand (consequent)
/// - Returns: The logical implication of the operands
/// - Throws: `OCLError.typeError` if either operand is not a boolean
@inlinable
public func implies(_ left: any EcoreValue, _ right: any EcoreValue) throws -> EBoolean {
    guard let leftBool = left as? EBoolean else {
        throw OCLError.typeError("Left operand of 'implies' must be boolean, got \(type(of: left))")
    }
    guard let rightBool = right as? EBoolean else {
        throw OCLError.typeError(
            "Right operand of 'implies' must be boolean, got \(type(of: right))")
    }
    return !leftBool || rightBool
}
