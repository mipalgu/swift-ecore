import BigInt
//
// Ecoretypes.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - Marker Protocol

/// Marker protocol for types that can be stored as Ecore values
///
/// All Ecore primitive types and model elements conform to this protocol,
/// providing type-safe storage and retrieval.
public protocol EcoreValue: Sendable, Equatable, Hashable {}

// MARK: - EMF Primitive Type Mappings

/// Unique identifier type for Ecore model elements.
///
/// Maps to Swift's `UUID` type for universal uniqueness across all model elements.
public typealias EUUID = UUID

/// String type for Ecore models.
///
/// Maps to Swift's native `String` type.
public typealias EString = String

/// Integer type for Ecore models.
///
/// Maps to Swift's native `Int` type, providing platform-specific integer precision.
public typealias EInt = Int

/// Boolean type for Ecore models.
///
/// Maps to Swift's native `Bool` type for true/false values.
public typealias EBoolean = Bool

/// Single-precision floating-point type for Ecore models.
///
/// Maps to Swift's `Float` type (32-bit IEEE 754 floating point).
public typealias EFloat = Float

/// Double-precision floating-point type for Ecore models.
///
/// Maps to Swift's `Double` type (64-bit IEEE 754 floating point).
public typealias EDouble = Double

/// Date and time type for Ecore models.
///
/// Maps to Swift's `Date` type for temporal values.
public typealias EDate = Date

/// Character type for Ecore models.
///
/// Maps to Swift's `Character` type for single Unicode scalar values.
public typealias EChar = Character

/// 8-bit signed integer type for Ecore models.
///
/// Maps to Swift's `Int8` type, equivalent to Java's `byte`.
public typealias EByte = Int8

/// 16-bit signed integer type for Ecore models.
///
/// Maps to Swift's `Int16` type, equivalent to Java's `short`.
public typealias EShort = Int16

/// 64-bit signed integer type for Ecore models.
///
/// Maps to Swift's `Int64` type, equivalent to Java's `long`.
public typealias ELong = Int64

/// Arbitrary-precision decimal type for Ecore models.
///
/// Maps to Swift's `Decimal` type for precise decimal arithmetic.
public typealias EBigDecimal = Decimal

/// Arbitrary-precision integer type for Ecore models.
///
/// Maps to the BigInt library's `BigInt` type for true arbitrary-precision integers.
public typealias EBigInteger = BigInt

// MARK: - EcoreValue Conformances

extension EString: EcoreValue {}
extension EInt: EcoreValue {}
extension EBoolean: EcoreValue {}
extension EFloat: EcoreValue {}
extension EDouble: EcoreValue {}
extension EDate: EcoreValue {}
extension EChar: EcoreValue {}
extension EByte: EcoreValue {}
extension EShort: EcoreValue {}
extension ELong: EcoreValue {}
extension EBigDecimal: EcoreValue {}
extension EBigInteger: EcoreValue {}
extension EUUID: EcoreValue {}
extension Array: EcoreValue where Element: EcoreValue {}

// MARK: - EcoreValue Collection Wrappers

/// Wrapper for arrays of EcoreValue to enable EcoreValue conformance.
///
/// This wrapper allows `[any EcoreValue]` collections to conform to EcoreValue,
/// which isn't possible with conditional extensions due to Swift's type system.
/// It provides proper equality and hashing semantics for heterogeneous collections.
public struct EcoreValueArray: EcoreValue, Sendable, Equatable, Hashable {
    /// The underlying array of EcoreValue instances.
    public let values: [any EcoreValue]

    /// Creates a new EcoreValueArray wrapping the given values.
    ///
    /// - Parameter values: Array of EcoreValue instances to wrap
    public init(_ values: [any EcoreValue]) {
        self.values = values
    }

    /// Compares two EcoreValueArray instances for equality.
    ///
    /// Arrays are considered equal if they have the same count and all
    /// corresponding elements are equal using EcoreValue equality semantics.
    public static func == (lhs: EcoreValueArray, rhs: EcoreValueArray) -> Bool {
        return lhs.values.count == rhs.values.count
            && zip(lhs.values, rhs.values).allSatisfy { areEqual($0, $1) }
    }

    /// Hashes the EcoreValueArray using its elements.
    ///
    /// The hash combines the count with individual element hashes using
    /// the EcoreValue hashing function for consistent results.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(values.count)
        for value in values {
            ECore.hash(value, into: &hasher)
        }
    }
}

// MARK: - EcoreValue Comparison Functions

/// Compare two EcoreValue instances for equality
///
/// This function provides type-safe comparison for any two EcoreValue instances
/// by attempting to cast to known types and falling back to string comparison.
public func areEqual(_ lhs: any EcoreValue, _ rhs: any EcoreValue) -> Bool {
    // If types are different, they cannot be equal
    guard type(of: lhs) == type(of: rhs) else {
        return false
    }

    // Use switch pattern matching for type-safe comparison
    switch (lhs, rhs) {
    case (let lString as String, let rString as String):
        return lString == rString
    case (let lInt as Int, let rInt as Int):
        return lInt == rInt
    case (let lBool as Bool, let rBool as Bool):
        return lBool == rBool
    case (let lFloat as Float, let rFloat as Float):
        return lFloat == rFloat
    case (let lDouble as Double, let rDouble as Double):
        return lDouble == rDouble
    case (let lDate as Date, let rDate as Date):
        return lDate == rDate
    case (let lChar as Character, let rChar as Character):
        return lChar == rChar
    case (let lByte as Int8, let rByte as Int8):
        return lByte == rByte
    case (let lShort as Int16, let rShort as Int16):
        return lShort == rShort
    case (let lLong as Int64, let rLong as Int64):
        return lLong == rLong
    case (let lDecimal as Decimal, let rDecimal as Decimal):
        return lDecimal == rDecimal
    case (let lBigInt as BigInt, let rBigInt as BigInt):
        return lBigInt == rBigInt
    case (let lUUID as UUID, let rUUID as UUID):
        return lUUID == rUUID
    case (let lObject as any EObject, let rObject as any EObject):
        return lObject.id == rObject.id
    case (let lArray as [String], let rArray as [String]):
        return lArray == rArray
    case (let lArray as [Int], let rArray as [Int]):
        return lArray == rArray
    case (let lArray as [any EObject], let rArray as [any EObject]):
        return lArray.count == rArray.count && zip(lArray, rArray).allSatisfy { $0.id == $1.id }

    default:
        // Fall back to string comparison for unknown EcoreValue types
        return "\(lhs)" == "\(rhs)"
    }
}

/// Hash two EcoreValue instances consistently
///
/// This function provides consistent hashing for EcoreValue instances
/// by attempting to cast to known types and falling back to string hashing.
public func hash(_ value: any EcoreValue, into hasher: inout Hasher) {
    // Use switch pattern matching for type-safe hashing
    switch value {
    case let stringValue as String:
        hasher.combine(0)
        hasher.combine(stringValue)
    case let intValue as Int:
        hasher.combine(1)
        hasher.combine(intValue)
    case let boolValue as Bool:
        hasher.combine(2)
        hasher.combine(boolValue)
    case let floatValue as Float:
        hasher.combine(3)
        hasher.combine(floatValue)
    case let doubleValue as Double:
        hasher.combine(4)
        hasher.combine(doubleValue)
    case let dateValue as Date:
        hasher.combine(5)
        hasher.combine(dateValue)
    case let charValue as Character:
        hasher.combine(6)
        hasher.combine(charValue)
    case let byteValue as Int8:
        hasher.combine(7)
        hasher.combine(byteValue)
    case let shortValue as Int16:
        hasher.combine(8)
        hasher.combine(shortValue)
    case let longValue as Int64:
        hasher.combine(9)
        hasher.combine(longValue)
    case let decimalValue as Decimal:
        hasher.combine(10)
        hasher.combine(decimalValue)
    case let bigIntValue as BigInt:
        hasher.combine(11)
        hasher.combine(bigIntValue)
    case let uuidValue as UUID:
        hasher.combine(12)
        hasher.combine(uuidValue)
    case let objectValue as any EObject:
        hasher.combine(13)
        hasher.combine(objectValue.id)
    case let arrayValue as [String]:
        hasher.combine(14)
        hasher.combine(arrayValue)
    case let arrayValue as [Int]:
        hasher.combine(15)
        hasher.combine(arrayValue)
    case let arrayValue as [any EObject]:
        hasher.combine(16)
        for obj in arrayValue {
            hasher.combine(obj.id)
        }

    default:
        // Fall back to string hash for unknown EcoreValue types
        hasher.combine(17)
        hasher.combine("\(value)")
    }
}

/// Compare two optional EcoreValue instances for equality
///
/// This function provides type-safe comparison for optional EcoreValue instances.
public func areEqualOptional(_ lhs: (any EcoreValue)?, _ rhs: (any EcoreValue)?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        return true
    case (let lValue?, let rValue?):
        return areEqual(lValue, rValue)
    default:
        return false
    }
}

/// Type conversion utilities for Ecore primitive types.
///
/// Provides bidirectional conversion between string representations and typed values,
/// supporting serialisation and deserialisation of Ecore models.
public enum EcoreTypeConverter: Sendable {
    /// Converts a string representation to a typed value.
    ///
    /// This method parses the string according to the target type's format requirements.
    /// If the string cannot be parsed into the requested type, `nil` is returned.
    ///
    /// - Parameters:
    ///   - value: The string representation to convert.
    ///   - type: The target type to convert to.
    /// - Returns: The parsed value of type `T`, or `nil` if parsing fails.
    public static func fromString<T>(_ value: String, as type: T.Type) -> T? {
        switch type {
        case is EString.Type:
            return value as? T
        case is EInt.Type:
            return Int(value) as? T
        case is EBoolean.Type:
            return Bool(value) as? T
        case is EFloat.Type:
            return Float(value) as? T
        case is EDouble.Type:
            return Double(value) as? T
        case is EBigInteger.Type:
            return BigInt(value, radix: 10) as? T
        default:
            return nil
        }
    }

    /// Converts a typed value to its string representation.
    ///
    /// This method produces a string representation suitable for serialisation
    /// and can be parsed back using ``fromString(_:as:)``.
    ///
    /// - Parameter value: The value to convert to a string.
    /// - Returns: A string representation of the value.
    public static func toString<T>(_ value: T) -> String {
        return "\(value)"
    }
}
