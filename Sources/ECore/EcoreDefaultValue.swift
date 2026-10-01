//
// EcoreDefaultValue.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Computes the value that a structural feature reads as while it is unset.
///
/// A many-valued feature reads as an empty list. A single-valued attribute reads as its
/// default value literal converted to the type of the attribute or, without a literal, as the
/// intrinsic default of its type: `false` for booleans, zero for numbers, and the name of the
/// first literal for enumerations. Strings, dates, arbitrary-precision numbers and references
/// have no intrinsic default, so they read as `nil`.
///
/// This is the value reflective reads return for an unset feature. It never changes whether a
/// feature counts as set.
public enum EcoreDefaultValue {
    /// The value an unset feature reads as.
    ///
    /// - Parameter feature: The attribute or reference to inspect. Other kinds of feature
    ///   read as `nil`.
    /// - Returns: The empty list, converted default, or intrinsic default; `nil` if the feature
    ///   has none.
    public static func value(for feature: some EStructuralFeature) -> (any EcoreValue)? {
        switch feature {
        case let attribute as EAttribute:
            return attribute.isMany ? emptyList(of: attribute.eType) : singleValue(of: attribute)
        case let reference as EReference:
            return reference.isMany ? [EUUID]() : nil
        default:
            return nil
        }
    }

    private static func singleValue(of attribute: EAttribute) -> (any EcoreValue)? {
        let type = attribute.eType
        if let literal = attribute.defaultValueLiteral {
            return convert(literal, to: type) ?? literal
        }
        if let eEnum = type as? EEnum { return eEnum.literals.first?.name }
        return intrinsicDefault(of: type)
    }

    private static func dataType(_ type: any EClassifier) -> EcoreDataType? {
        EcoreDataType(rawValue: type.name)
    }

    private static func intrinsicDefault(of type: any EClassifier) -> (any EcoreValue)? {
        switch dataType(type) {
        case .eBoolean: return false
        case .eInt: return 0 as EInt
        case .eFloat: return 0 as EFloat
        case .eDouble: return 0 as EDouble
        case .eByte: return 0 as EByte
        case .eShort: return 0 as EShort
        case .eLong: return 0 as ELong
        default: return nil
        }
    }

    private static func convert(_ literal: String, to type: any EClassifier) -> (any EcoreValue)? {
        switch dataType(type) {
        case .eBoolean, .eBooleanObject: return BooleanString.fromString(literal)
        case .eInt, .eIntegerObject: return EInt(literal)
        case .eFloat, .eFloatObject: return EFloat(literal)
        case .eDouble, .eDoubleObject: return EDouble(literal)
        case .eByte, .eByteObject: return EByte(literal)
        case .eShort, .eShortObject: return EShort(literal)
        case .eLong, .eLongObject: return ELong(literal)
        case .eBigDecimal: return EBigDecimal(string: literal)
        case .eBigInteger: return EBigInteger(literal)
        case .eChar, .eCharacterObject: return literal.count == 1 ? literal.first : nil
        default: return nil
        }
    }

    private static func emptyList(of type: any EClassifier) -> any EcoreValue {
        switch dataType(type) {
        case .eInt, .eIntegerObject: return [EInt]()
        case .eBoolean, .eBooleanObject: return [EBoolean]()
        case .eFloat, .eFloatObject: return [EFloat]()
        case .eDouble, .eDoubleObject: return [EDouble]()
        case .eByte, .eByteObject: return [EByte]()
        case .eShort, .eShortObject: return [EShort]()
        case .eLong, .eLongObject: return [ELong]()
        case .eChar, .eCharacterObject: return [EChar]()
        case .eDate: return [EDate]()
        case .eBigDecimal: return [EBigDecimal]()
        case .eBigInteger: return [EBigInteger]()
        default: return [EString]()
        }
    }
}
