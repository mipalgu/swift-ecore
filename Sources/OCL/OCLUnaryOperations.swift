//
// OCLUnaryOperations.swift
// OCL
//
//  Created by Rene Hexel on 18/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

// MARK: - Logical Operations

/// Performs logical NOT operation on a boolean value.
///
/// The operand must be a boolean value. The result is the logical negation of the operand.
///
/// - Parameter operand: The boolean operand to negate
/// - Returns: The logical negation of the operand
/// - Throws: `OCLError.typeError` if the operand is not a boolean
@inlinable
public func not(_ operand: any EcoreValue) throws -> EBoolean {
    guard let boolValue = operand as? EBoolean else {
        throw OCLError.typeError("Operand of 'not' must be boolean, got \(type(of: operand))")
    }
    return !boolValue
}

// MARK: - Arithmetic Operations

/// Performs numeric negation on a numeric value.
///
/// Supports negation of all numeric types (Int, Double, Float) and returns
/// the same type as the input operand.
///
/// - Parameter operand: The numeric operand to negate
/// - Returns: The numeric negation of the operand
/// - Throws: `OCLError.typeError` if the operand is not numeric
@inlinable
public func negate(_ operand: any EcoreValue) throws -> any EcoreValue {
    switch operand {
    case let intValue as EInt:
        return -intValue
    case let doubleValue as EDouble:
        return -doubleValue
    case let floatValue as EFloat:
        return -floatValue
    case let byteValue as EByte:
        return -byteValue
    case let shortValue as EShort:
        return -shortValue
    case let longValue as ELong:
        return -longValue
    default:
        throw OCLError.typeError("Operand of negation must be numeric, got \(type(of: operand))")
    }
}
