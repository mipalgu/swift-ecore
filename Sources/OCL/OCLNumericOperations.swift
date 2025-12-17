import BigInt
//
// OCLNumericOperations.swift
// OCL
//
//  Created by Rene Hexel on 18/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

// MARK: - Numeric Operations

/// Returns the absolute value of a number.
///
/// Computes the absolute value (magnitude) of the given numeric value.
/// Follows OCL type rules: Integer→Integer, Real→Real.
///
/// ## Examples
/// ```swift
/// let result1 = try abs(-5 as EInt)      // Result: 5 as EInt
/// let result2 = try abs(-3.14 as EDouble) // Result: 3.14 as EDouble
/// ```
///
/// - Parameter value: The numeric value to compute absolute value for
/// - Returns: The absolute value with the same type as input
/// - Throws: `OCLError.invalidArguments` if the value is not numeric
@inlinable
public func abs(_ value: any EcoreValue) throws -> any EcoreValue {
    switch value {
    case let int as EInt:
        return Swift.abs(int)
    case let double as EDouble:
        return Swift.abs(double)
    case let float as EFloat:
        return Swift.abs(float)
    case let byte as EByte:
        return Swift.abs(byte)
    case let short as EShort:
        return Swift.abs(short)
    case let long as ELong:
        return Swift.abs(long)
    case let bigInt as EBigInteger:
        return bigInt < 0 ? -bigInt : bigInt
    case let bigDecimal as EBigDecimal:
        return Swift.abs(bigDecimal)
    default:
        throw OCLError.invalidArguments("abs requires a numeric value, got \(type(of: value))")
    }
}

/// Returns the largest integer less than or equal to the value (OCL Real.floor()).
///
/// Computes the floor function as defined in OCL specification.
/// Only accepts Real (Double) values as per OCL standard.
///
/// ## Examples
/// ```swift
/// let result1 = try floor(3.7 as EDouble)  // Result: 3
/// let result2 = try floor(-2.3 as EDouble) // Result: -3
/// ```
///
/// - Parameter value: The Real value to compute floor for
/// - Returns: The floor as an Integer
/// - Throws: `OCLError.invalidArguments` if the value is not a Real
@inlinable
public func floor(_ value: any EcoreValue) throws -> EInt {
    switch value {
    case let double as EDouble:
        return EInt(Foundation.floor(double))
    case let float as EFloat:
        return EInt(Foundation.floor(EDouble(float)))
    case let bigDecimal as EBigDecimal:
        return EInt(Foundation.floor(Double(bigDecimal.description) ?? 0))
    default:
        throw OCLError.invalidArguments("floor requires a Real value, got \(type(of: value))")
    }
}

/// Returns the rounded value to the nearest integer (OCL Real.round()).
///
/// Computes rounding as defined in OCL specification: "The integer that is closest to self.
/// When there are two such integers, the largest one."
/// Only accepts Real (Double) values as per OCL standard.
///
/// ## Examples
/// ```swift
/// let result1 = try round(3.6 as EDouble)  // Result: 4
/// let result2 = try round(3.5 as EDouble)  // Result: 4 (ties go to larger)
/// let result3 = try round(-2.3 as EDouble) // Result: -2
/// ```
///
/// - Parameter value: The Real value to round
/// - Returns: The rounded value as an Integer
/// - Throws: `OCLError.invalidArguments` if the value is not a Real
@inlinable
public func round(_ value: any EcoreValue) throws -> EInt {
    switch value {
    case let double as EDouble:
        // OCL round: ties go to larger integer
        return EInt(Foundation.round(double))
    case let float as EFloat:
        return EInt(Foundation.round(EDouble(float)))
    case let bigDecimal as EBigDecimal:
        return EInt(Foundation.round(Double(bigDecimal.description) ?? 0))
    default:
        throw OCLError.invalidArguments("round requires a Real value, got \(type(of: value))")
    }
}

/// Returns the ceiling (smallest integer not smaller than the input) of a real value.
///
/// Computes the ceiling as defined in OCL specification: "The smallest integer that is not less than self."
/// Only accepts Real (Float, Double, BigDecimal) values as per OCL standard.
///
/// ## Examples
/// ```swift
/// let result1 = try ceiling(3.2 as EDouble)   // Result: 4
/// let result2 = try ceiling(-2.7 as EDouble)  // Result: -2
/// let result3 = try ceiling(5.0 as EDouble)   // Result: 5
/// ```
///
/// - Parameter value: The Real value to compute ceiling for
/// - Returns: The ceiling value as an Integer
/// - Throws: `OCLError.invalidArguments` if the value is not a Real
@inlinable
public func ceiling(_ value: any EcoreValue) throws -> EInt {
    switch value {
    case let double as EDouble:
        return EInt(Foundation.ceil(double))
    case let float as EFloat:
        return EInt(Foundation.ceil(EDouble(float)))
    case let bigDecimal as EBigDecimal:
        return EInt(Foundation.ceil(Double(bigDecimal.description) ?? 0))
    default:
        throw OCLError.invalidArguments("ceiling requires a Real value, got \(type(of: value))")
    }
}

/// Returns the maximum of two numeric values (OCL Integer/Real.max()).
///
/// Compares two numeric values and returns the larger one.
/// Follows OCL type coercion rules: Integer conformsTo Real.
///
/// ## Type Coercion Rules
/// - Integer types (EByte, EShort, EInt, ELong) promote to largest type
/// - Real types (EFloat, EDouble, EBigDecimal) promote to most precise type
/// - Integer + Real → Real (Integer promoted to Real)
///
/// ## Examples
/// ```swift
/// let result1 = try max(5 as EInt, 3 as EInt)         // Result: 5 as EInt
/// let result2 = try max(2.5 as EDouble, 3.1 as EDouble) // Result: 3.1 as EDouble
/// let result3 = try max(7 as EInt, 6.5 as EDouble)    // Result: 7.0 as EDouble
/// ```
///
/// - Parameters:
///   - left: The first numeric value
///   - right: The second numeric value
/// - Returns: The maximum of the two values
/// - Throws: `OCLError.invalidArguments` if either value is not numeric
@inlinable
public func max(_ left: any EcoreValue, _ right: any EcoreValue) throws -> any EcoreValue {
    // Handle all integer type combinations - promote to largest integer type
    switch (left, right) {
    // EInt combinations
    case (let l as EInt, let r as EInt):
        return Swift.max(l, r)
    case (let l as EInt, let r as EByte):
        return Swift.max(l, EInt(r))
    case (let l as EByte, let r as EInt):
        return Swift.max(EInt(l), r)
    case (let l as EInt, let r as EShort):
        return Swift.max(l, EInt(r))
    case (let l as EShort, let r as EInt):
        return Swift.max(EInt(l), r)
    case (let l as EInt, let r as ELong):
        return Swift.max(l, EInt(r))
    case (let l as ELong, let r as EInt):
        return Swift.max(EInt(l), r)

    // EByte combinations
    case (let l as EByte, let r as EByte):
        return Swift.max(l, r)
    case (let l as EByte, let r as EShort):
        return Swift.max(EShort(l), r)
    case (let l as EShort, let r as EByte):
        return Swift.max(l, EShort(r))
    case (let l as EByte, let r as ELong):
        return Swift.max(ELong(l), r)
    case (let l as ELong, let r as EByte):
        return Swift.max(l, ELong(r))

    // EShort combinations
    case (let l as EShort, let r as EShort):
        return Swift.max(l, r)
    case (let l as EShort, let r as ELong):
        return Swift.max(ELong(l), r)
    case (let l as ELong, let r as EShort):
        return Swift.max(l, ELong(r))

    // ELong combinations
    case (let l as ELong, let r as ELong):
        return Swift.max(l, r)

    // Real type combinations - promote to most precise real type
    case (let l as EFloat, let r as EFloat):
        return Swift.max(l, r)
    case (let l as EDouble, let r as EDouble):
        return Swift.max(l, r)
    case (let l as EBigDecimal, let r as EBigDecimal):
        return Swift.max(l, r)
    case (let l as EFloat, let r as EDouble):
        return Swift.max(EDouble(l), r)
    case (let l as EDouble, let r as EFloat):
        return Swift.max(l, EDouble(r))
    case (let l as EFloat, let r as EBigDecimal):
        return Swift.max(EBigDecimal(Double(l)), r)
    case (let l as EBigDecimal, let r as EFloat):
        return Swift.max(l, EBigDecimal(Double(r)))
    case (let l as EDouble, let r as EBigDecimal):
        return Swift.max(EBigDecimal(l), r)
    case (let l as EBigDecimal, let r as EDouble):
        return Swift.max(l, EBigDecimal(r))

    // Integer + Real combinations - promote to Real
    case (let l as EInt, let r as EFloat):
        return Swift.max(EFloat(l), r)
    case (let l as EFloat, let r as EInt):
        return Swift.max(l, EFloat(r))
    case (let l as EInt, let r as EDouble):
        return Swift.max(EDouble(l), r)
    case (let l as EDouble, let r as EInt):
        return Swift.max(l, EDouble(r))
    case (let l as EInt, let r as EBigDecimal):
        return Swift.max(EBigDecimal(l), r)
    case (let l as EBigDecimal, let r as EInt):
        return Swift.max(l, EBigDecimal(r))

    // Other integer + Real combinations
    case (let l as EByte, let r as EFloat):
        return Swift.max(EFloat(l), r)
    case (let l as EFloat, let r as EByte):
        return Swift.max(l, EFloat(r))
    case (let l as EByte, let r as EDouble):
        return Swift.max(EDouble(l), r)
    case (let l as EDouble, let r as EByte):
        return Swift.max(l, EDouble(r))

    case (let l as EShort, let r as EFloat):
        return Swift.max(EFloat(l), r)
    case (let l as EFloat, let r as EShort):
        return Swift.max(l, EFloat(r))
    case (let l as EShort, let r as EDouble):
        return Swift.max(EDouble(l), r)
    case (let l as EDouble, let r as EShort):
        return Swift.max(l, EDouble(r))

    case (let l as ELong, let r as EFloat):
        return Swift.max(EFloat(l), r)
    case (let l as EFloat, let r as ELong):
        return Swift.max(l, EFloat(r))
    case (let l as ELong, let r as EDouble):
        return Swift.max(EDouble(l), r)
    case (let l as EDouble, let r as ELong):
        return Swift.max(l, EDouble(r))

    // BigInteger combinations
    case (let l as EBigInteger, let r as EBigInteger):
        return Swift.max(l, r)
    case (let l as EBigInteger, let r as EInt):
        return Swift.max(EInt(l), r)
    case (let l as EInt, let r as EBigInteger):
        return Swift.max(l, EInt(r))
    case (let l as EBigInteger, let r as EByte):
        return Swift.max(l, EBigInteger(r))
    case (let l as EByte, let r as EBigInteger):
        return Swift.max(EBigInteger(l), r)
    case (let l as EBigInteger, let r as EShort):
        return Swift.max(l, EBigInteger(r))
    case (let l as EShort, let r as EBigInteger):
        return Swift.max(EBigInteger(l), r)
    case (let l as EBigInteger, let r as ELong):
        return Swift.max(l, EBigInteger(r))
    case (let l as ELong, let r as EBigInteger):
        return Swift.max(EBigInteger(l), r)
    case (let l as EBigInteger, let r as EFloat):
        return Swift.max(EFloat(l), r)
    case (let l as EFloat, let r as EBigInteger):
        return Swift.max(l, EFloat(r))
    case (let l as EBigInteger, let r as EDouble):
        return Swift.max(EDouble(l), r)
    case (let l as EDouble, let r as EBigInteger):
        return Swift.max(l, EDouble(r))
    case (let l as EBigInteger, let r as EBigDecimal):
        return Swift.max(EBigDecimal(l), r)
    case (let l as EBigDecimal, let r as EBigInteger):
        return Swift.max(l, EBigDecimal(r))

    // Mixed BigDecimal combinations with smaller integer types
    case (let l as EByte, let r as EBigDecimal):
        return Swift.max(EBigDecimal(Int(l)), r)
    case (let l as EBigDecimal, let r as EByte):
        return Swift.max(l, EBigDecimal(Int(r)))
    case (let l as EShort, let r as EBigDecimal):
        return Swift.max(EBigDecimal(Int(l)), r)
    case (let l as EBigDecimal, let r as EShort):
        return Swift.max(l, EBigDecimal(Int(r)))
    case (let l as ELong, let r as EBigDecimal):
        return Swift.max(EBigDecimal(Int(l)), r)
    case (let l as EBigDecimal, let r as ELong):
        return Swift.max(l, EBigDecimal(Int(r)))

    default:
        throw OCLError.invalidArguments(
            "max requires numeric values, got \(type(of: left)) and \(type(of: right))")
    }
}

/// Returns the minimum of two numeric values (OCL Integer/Real.min()).
///
/// Compares two numeric values and returns the smaller one.
/// Follows OCL type coercion rules: Integer conformsTo Real.
///
/// ## Type Coercion Rules
/// - Integer types (EByte, EShort, EInt, ELong) promote to largest type
/// - Real types (EFloat, EDouble, EBigDecimal) promote to most precise type
/// - Integer + Real → Real (Integer promoted to Real)
///
/// ## Examples
/// ```swift
/// let result1 = try min(5 as EInt, 3 as EInt)         // Result: 3 as EInt
/// let result2 = try min(2.5 as EDouble, 3.1 as EDouble) // Result: 2.5 as EDouble
/// let result3 = try min(7 as EInt, 6.5 as EDouble)    // Result: 6.5 as EDouble
/// ```
///
/// - Parameters:
///   - left: The first numeric value
///   - right: The second numeric value
/// - Returns: The minimum of the two values
/// - Throws: `OCLError.invalidArguments` if either value is not numeric
@inlinable
public func min(_ left: any EcoreValue, _ right: any EcoreValue) throws -> any EcoreValue {
    // Handle all integer type combinations - promote to largest integer type
    switch (left, right) {
    // EInt combinations
    case (let l as EInt, let r as EInt):
        return Swift.min(l, r)
    case (let l as EInt, let r as EByte):
        return Swift.min(l, EInt(r))
    case (let l as EByte, let r as EInt):
        return Swift.min(EInt(l), r)
    case (let l as EInt, let r as EShort):
        return Swift.min(l, EInt(r))
    case (let l as EShort, let r as EInt):
        return Swift.min(EInt(l), r)
    case (let l as EInt, let r as ELong):
        return Swift.min(l, EInt(r))
    case (let l as ELong, let r as EInt):
        return Swift.min(EInt(l), r)

    // EByte combinations
    case (let l as EByte, let r as EByte):
        return Swift.min(l, r)
    case (let l as EByte, let r as EShort):
        return Swift.min(EShort(l), r)
    case (let l as EShort, let r as EByte):
        return Swift.min(l, EShort(r))
    case (let l as EByte, let r as ELong):
        return Swift.min(ELong(l), r)
    case (let l as ELong, let r as EByte):
        return Swift.min(l, ELong(r))

    // EShort combinations
    case (let l as EShort, let r as EShort):
        return Swift.min(l, r)
    case (let l as EShort, let r as ELong):
        return Swift.min(ELong(l), r)
    case (let l as ELong, let r as EShort):
        return Swift.min(l, ELong(r))

    // ELong combinations
    case (let l as ELong, let r as ELong):
        return Swift.min(l, r)

    // Real type combinations - promote to most precise real type
    case (let l as EFloat, let r as EFloat):
        return Swift.min(l, r)
    case (let l as EDouble, let r as EDouble):
        return Swift.min(l, r)
    case (let l as EBigDecimal, let r as EBigDecimal):
        return Swift.min(l, r)
    case (let l as EFloat, let r as EDouble):
        return Swift.min(EDouble(l), r)
    case (let l as EDouble, let r as EFloat):
        return Swift.min(l, EDouble(r))
    case (let l as EFloat, let r as EBigDecimal):
        return Swift.min(EBigDecimal(Double(l)), r)
    case (let l as EBigDecimal, let r as EFloat):
        return Swift.min(l, EBigDecimal(Double(r)))
    case (let l as EDouble, let r as EBigDecimal):
        return Swift.min(EBigDecimal(l), r)
    case (let l as EBigDecimal, let r as EDouble):
        return Swift.min(l, EBigDecimal(r))

    // Integer + Real combinations - promote to Real
    case (let l as EInt, let r as EFloat):
        return Swift.min(EFloat(l), r)
    case (let l as EFloat, let r as EInt):
        return Swift.min(l, EFloat(r))
    case (let l as EInt, let r as EDouble):
        return Swift.min(EDouble(l), r)
    case (let l as EDouble, let r as EInt):
        return Swift.min(l, EDouble(r))
    case (let l as EInt, let r as EBigDecimal):
        return Swift.min(EBigDecimal(l), r)
    case (let l as EBigDecimal, let r as EInt):
        return Swift.min(l, EBigDecimal(r))

    // Other integer + Real combinations
    case (let l as EByte, let r as EFloat):
        return Swift.min(EFloat(l), r)
    case (let l as EFloat, let r as EByte):
        return Swift.min(l, EFloat(r))
    case (let l as EByte, let r as EDouble):
        return Swift.min(EDouble(l), r)
    case (let l as EDouble, let r as EByte):
        return Swift.min(l, EDouble(r))

    case (let l as EShort, let r as EFloat):
        return Swift.min(EFloat(l), r)
    case (let l as EFloat, let r as EShort):
        return Swift.min(l, EFloat(r))
    case (let l as EShort, let r as EDouble):
        return Swift.min(EDouble(l), r)
    case (let l as EDouble, let r as EShort):
        return Swift.min(l, EDouble(r))

    case (let l as ELong, let r as EFloat):
        return Swift.min(EFloat(l), r)
    case (let l as EFloat, let r as ELong):
        return Swift.min(l, EFloat(r))
    case (let l as ELong, let r as EDouble):
        return Swift.min(EDouble(l), r)
    case (let l as EDouble, let r as ELong):
        return Swift.min(l, EDouble(r))

    // BigInteger combinations
    case (let l as EBigInteger, let r as EBigInteger):
        return Swift.min(l, r)
    case (let l as EBigInteger, let r as EInt):
        return Swift.min(EInt(l), r)
    case (let l as EInt, let r as EBigInteger):
        return Swift.min(l, EInt(r))
    case (let l as EBigInteger, let r as EByte):
        return Swift.min(l, EBigInteger(r))
    case (let l as EByte, let r as EBigInteger):
        return Swift.min(EBigInteger(l), r)
    case (let l as EBigInteger, let r as EShort):
        return Swift.min(l, EBigInteger(r))
    case (let l as EShort, let r as EBigInteger):
        return Swift.min(EBigInteger(l), r)
    case (let l as EBigInteger, let r as ELong):
        return Swift.min(l, EBigInteger(r))
    case (let l as ELong, let r as EBigInteger):
        return Swift.min(EBigInteger(l), r)
    case (let l as EBigInteger, let r as EFloat):
        return Swift.min(EFloat(l), r)
    case (let l as EFloat, let r as EBigInteger):
        return Swift.min(l, EFloat(r))
    case (let l as EBigInteger, let r as EDouble):
        return Swift.min(EDouble(l), r)
    case (let l as EDouble, let r as EBigInteger):
        return Swift.min(l, EDouble(r))
    case (let l as EBigInteger, let r as EBigDecimal):
        return Swift.min(EBigDecimal(l), r)
    case (let l as EBigDecimal, let r as EBigInteger):
        return Swift.min(l, EBigDecimal(r))

    // Mixed BigDecimal combinations with smaller integer types
    case (let l as EByte, let r as EBigDecimal):
        return Swift.min(EBigDecimal(Int(l)), r)
    case (let l as EBigDecimal, let r as EByte):
        return Swift.min(l, EBigDecimal(Int(r)))
    case (let l as EShort, let r as EBigDecimal):
        return Swift.min(EBigDecimal(Int(l)), r)
    case (let l as EBigDecimal, let r as EShort):
        return Swift.min(l, EBigDecimal(Int(r)))
    case (let l as ELong, let r as EBigDecimal):
        return Swift.min(EBigDecimal(Int(l)), r)
    case (let l as EBigDecimal, let r as ELong):
        return Swift.min(l, EBigDecimal(Int(r)))

    default:
        throw OCLError.invalidArguments(
            "min requires numeric arguments, got \(type(of: left)) and \(type(of: right))")
    }
}

/// Raises a numeric value to the power of another numeric value.
///
/// Computes the power operation as defined in OCL specification.
/// Supports all numeric types with appropriate type coercion.
/// Result type follows OCL rules: if either operand is Real, result is Real; otherwise Integer.
///
/// ## Type Coercion Rules
/// - Integer ^ Integer → Integer (if result fits in ELong range)
/// - Real ^ Any → Real
/// - Any ^ Real → Real
/// - Large integer results promote to EBigInteger
///
/// ## Examples
/// ```swift
/// let result1 = try power(2 as EInt, 3 as EInt)        // Result: 8 as EInt
/// let result2 = try power(2.5 as EDouble, 2 as EInt)   // Result: 6.25 as EDouble
/// let result3 = try power(4 as EInt, 0.5 as EDouble)   // Result: 2.0 as EDouble
/// ```
///
/// - Parameters:
///   - base: The base value
///   - exponent: The exponent value
/// - Returns: The result of base raised to the power of exponent
/// - Throws: `OCLError.invalidArguments` if operands are not numeric
@inlinable
public func power(_ base: any EcoreValue, _ exponent: any EcoreValue) throws -> any EcoreValue {
    // Handle Real base or Real exponent -> Real result
    switch (base, exponent) {
    // Real base cases
    case (let b as EDouble, let e as EDouble):
        return Foundation.pow(b, e)
    case (let b as EDouble, let e as EFloat):
        return Foundation.pow(b, EDouble(e))
    case (let b as EFloat, let e as EDouble):
        return Foundation.pow(EDouble(b), e)
    case (let b as EFloat, let e as EFloat):
        return Foundation.pow(EDouble(b), EDouble(e))
    case (let b as EBigDecimal, let e as EDouble):
        let baseDouble = Double(b.description) ?? 0
        return Foundation.pow(baseDouble, e)
    case (let b as EDouble, let e as EBigDecimal):
        let expDouble = Double(e.description) ?? 0
        return Foundation.pow(b, expDouble)
    case (let b as EBigDecimal, let e as EBigDecimal):
        let baseDouble = Double(b.description) ?? 0
        let expDouble = Double(e.description) ?? 0
        return Foundation.pow(baseDouble, expDouble)

    // Real base with integer exponent
    case (let b as EDouble, let e as EInt):
        return Foundation.pow(b, EDouble(e))
    case (let b as EDouble, let e as EByte):
        return Foundation.pow(b, EDouble(e))
    case (let b as EDouble, let e as EShort):
        return Foundation.pow(b, EDouble(e))
    case (let b as EDouble, let e as ELong):
        return Foundation.pow(b, EDouble(e))
    case (let b as EFloat, let e as EInt):
        return Foundation.pow(EDouble(b), EDouble(e))
    case (let b as EFloat, let e as EByte):
        return Foundation.pow(EDouble(b), EDouble(e))
    case (let b as EFloat, let e as EShort):
        return Foundation.pow(EDouble(b), EDouble(e))
    case (let b as EFloat, let e as ELong):
        return Foundation.pow(EDouble(b), EDouble(e))

    // Integer base with Real exponent -> Real result
    case (let b as EInt, let e as EDouble):
        return Foundation.pow(EDouble(b), e)
    case (let b as EInt, let e as EFloat):
        return Foundation.pow(EDouble(b), EDouble(e))
    case (let b as EByte, let e as EDouble):
        return Foundation.pow(EDouble(b), e)
    case (let b as EByte, let e as EFloat):
        return Foundation.pow(EDouble(b), EDouble(e))
    case (let b as EShort, let e as EDouble):
        return Foundation.pow(EDouble(b), e)
    case (let b as EShort, let e as EFloat):
        return Foundation.pow(EDouble(b), EDouble(e))
    case (let b as ELong, let e as EDouble):
        return Foundation.pow(EDouble(b), e)
    case (let b as ELong, let e as EFloat):
        return Foundation.pow(EDouble(b), EDouble(e))

    // Integer ^ Integer cases -> Integer result (if possible)
    case (let b as EInt, let e as EInt):
        if e >= 0 {
            let result = Foundation.pow(EDouble(b), EDouble(e))
            // Check if result fits in ELong
            if result <= EDouble(ELong.max) && result >= EDouble(ELong.min)
                && result.truncatingRemainder(dividingBy: 1) == 0
            {
                return ELong(result)
            } else {
                // Convert to BigInteger for large results
                return EBigInteger(String(Int64(result))) ?? EBigInteger(0)
            }
        } else {
            // Negative exponent -> Real result
            return Foundation.pow(EDouble(b), EDouble(e))
        }

    case (let b as EByte, let e as EByte):
        let result = Foundation.pow(EDouble(b), EDouble(e))
        return EInt(result)
    case (let b as EByte, let e as EShort):
        let result = Foundation.pow(EDouble(b), EDouble(e))
        return EInt(result)
    case (let b as EByte, let e as EInt):
        let result = Foundation.pow(EDouble(b), EDouble(e))
        return ELong(result)
    case (let b as EShort, let e as EByte):
        let result = Foundation.pow(EDouble(b), EDouble(e))
        return EInt(result)
    case (let b as EShort, let e as EShort):
        let result = Foundation.pow(EDouble(b), EDouble(e))
        return EInt(result)
    case (let b as EShort, let e as EInt):
        let result = Foundation.pow(EDouble(b), EDouble(e))
        return ELong(result)
    case (let b as ELong, let e as EByte):
        let result = Foundation.pow(EDouble(b), EDouble(e))
        return ELong(result)
    case (let b as ELong, let e as EShort):
        let result = Foundation.pow(EDouble(b), EDouble(e))
        return ELong(result)
    case (let b as ELong, let e as EInt):
        let result = Foundation.pow(EDouble(b), EDouble(e))
        return ELong(result)
    case (let b as ELong, let e as ELong):
        let result = Foundation.pow(EDouble(b), EDouble(e))
        if result <= EDouble(ELong.max) && result >= EDouble(ELong.min) {
            return ELong(result)
        } else {
            return EBigInteger(String(Int64(result))) ?? EBigInteger(0)
        }

    // BigInteger cases - convert to Double for computation
    case (let b as EBigInteger, let e as EInt):
        let baseDouble = Double(b.description) ?? 0
        return Foundation.pow(baseDouble, EDouble(e))
    case (let b as EInt, let e as EBigInteger):
        let expDouble = Double(e.description) ?? 0
        return Foundation.pow(EDouble(b), expDouble)
    case (let b as EBigInteger, let e as EBigInteger):
        let baseDouble = Double(b.description) ?? 0
        let expDouble = Double(e.description) ?? 0
        return Foundation.pow(baseDouble, expDouble)

    default:
        throw OCLError.invalidArguments(
            "power requires numeric arguments, got \(type(of: base)) and \(type(of: exponent))")
    }
}
