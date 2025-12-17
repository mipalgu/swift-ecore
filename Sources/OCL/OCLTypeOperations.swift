//
// OCLTypeOperations.swift
// OCL
//
//  Created by Rene Hexel on 18/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

// MARK: - Type Operations

/// Checks if an object is exactly of the specified type.
///
/// Performs exact type checking - returns true only if the object is exactly
/// the specified type, not a subtype. This is stricter than `oclIsKindOf`.
///
/// ## Examples
/// ```swift
/// let value: any EcoreValue = 42 as EInt
/// let result1 = try oclIsTypeOf(value, EInt.self)    // Result: true
/// let result2 = try oclIsTypeOf(value, EDouble.self) // Result: false
/// let result3 = try oclIsTypeOf(value, Any.self)     // Result: false (not exact)
/// ```
///
/// - Parameters:
///   - object: The object to check the type of
///   - type: The type to check against
/// - Returns: True if the object is exactly of the specified type
/// - Throws: Never throws - type checking is always safe
@inlinable
public func oclIsTypeOf<T>(_ object: any EcoreValue, _ type: T.Type) throws -> EBoolean {
    return Swift.type(of: object) == type
}

/// Checks if an object is of the specified type or a subtype.
///
/// Performs type hierarchy checking - returns true if the object is
/// the specified type or any of its subtypes. This is more permissive than `oclIsTypeOf`.
///
/// ## Examples
/// ```swift
/// let value: any EcoreValue = 42 as EInt
/// let result1 = try oclIsKindOf(value, EInt.self)    // Result: true
/// let result2 = try oclIsKindOf(value, Any.self)     // Result: true (subtype)
/// let result3 = try oclIsKindOf(value, EDouble.self) // Result: false
/// ```
///
/// - Parameters:
///   - object: The object to check the type of
///   - type: The type to check against (including subtypes)
/// - Returns: True if the object is of the specified type or a subtype
/// - Throws: Never throws - type checking is always safe
@inlinable
public func oclIsKindOf<T>(_ object: any EcoreValue, _ type: T.Type) throws -> EBoolean {
    return object is T
}

/// Casts an object to the specified type.
///
/// Performs a safe type cast - returns the object cast to the specified type
/// if the cast is valid, otherwise throws an error.
///
/// ## Examples
/// ```swift
/// let value: any EcoreValue = 42 as EInt
/// let result1 = try oclAsType(value, EInt.self)    // Result: 42 as EInt
/// let result2 = try oclAsType(value, EDouble.self) // Throws: OCLError.typeError
/// ```
///
/// ## Type Safety
/// This operation performs runtime type checking and will throw an error
/// if the cast cannot be performed safely.
///
/// - Parameters:
///   - object: The object to cast
///   - type: The target type to cast to
/// - Returns: The object cast to the specified type
/// - Throws: `OCLError.typeError` if the cast is not valid
@inlinable
public func oclAsType<T>(_ object: any EcoreValue, _ type: T.Type) throws -> T {
    guard let castObject = object as? T else {
        throw OCLError.typeError(
            "Cannot cast \(Swift.type(of: object)) to \(type)")
    }
    return castObject
}

// MARK: - Helper Type Operations

/// Checks if an object is of a specific ECore type by name.
///
/// Convenience method for checking ECore types using string names.
/// Useful when working with dynamic type checking in model transformations.
///
/// ## Supported Type Names
/// - "EString" - String values
/// - "EInt" - Integer values
/// - "EDouble" - Double precision floating point values
/// - "EFloat" - Single precision floating point values
/// - "EBoolean" - Boolean values
/// - "EcoreValueArray" - Array wrapper values
///
/// ## Examples
/// ```swift
/// let value: any EcoreValue = "Hello" as EString
/// let result1 = try oclIsTypeOfName(value, "EString")  // Result: true
/// let result2 = try oclIsTypeOfName(value, "EInt")     // Result: false
/// ```
///
/// - Parameters:
///   - object: The object to check the type of
///   - typeName: The name of the type to check against
/// - Returns: True if the object is exactly of the named type
/// - Throws: `OCLError.invalidArguments` if the type name is not recognised
@inlinable
public func oclIsTypeOfName(_ object: any EcoreValue, _ typeName: EString) throws -> EBoolean {
    switch typeName {
    case "EString":
        return object is EString
    case "EInt":
        return Swift.type(of: object) == EInt.self
    case "EDouble":
        return Swift.type(of: object) == EDouble.self
    case "EFloat":
        return Swift.type(of: object) == EFloat.self
    case "EBoolean":
        return Swift.type(of: object) == EBoolean.self
    case "EcoreValueArray":
        return object is EcoreValueArray
    default:
        throw OCLError.invalidArguments("Unknown type name: \(typeName)")
    }
}

/// Gets the type name of an ECore value as a string.
///
/// Returns a human-readable string representation of the object's type,
/// using ECore naming conventions.
///
/// ## Examples
/// ```swift
/// let value1: any EcoreValue = 42 as EInt
/// let name1 = try oclTypeName(value1)  // Result: "EInt"
///
/// let value2: any EcoreValue = "Hello" as EString
/// let name2 = try oclTypeName(value2)  // Result: "EString"
/// ```
///
/// - Parameter object: The object to get the type name for
/// - Returns: The type name as a string
/// - Throws: Never throws - all ECore values have representable type names
@inlinable
public func oclTypeName(_ object: any EcoreValue) throws -> EString {
    switch object {
    case is EString:
        return "EString"
    case is EInt:
        return "EInt"
    case is EDouble:
        return "EDouble"
    case is EFloat:
        return "EFloat"
    case is EBoolean:
        return "EBoolean"
    case is EcoreValueArray:
        return "EcoreValueArray"
    case is [any EcoreValue]:
        return "Array"
    default:
        return String(describing: Swift.type(of: object))
    }
}
