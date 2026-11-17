//
// FeatureValueForms.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

extension ReferenceValues {
    /// The objects that a stored value refers to, in the order of the value.
    ///
    /// A reference value holds the identifier of an object, a ``ResourceProxy`` for an object
    /// that is not loaded, or a list of them. An ``EcoreValueArray`` may hold identifiers and
    /// proxies side by side, as a many-valued reference does that refers to objects of the
    /// same document and of other documents.
    ///
    /// - Parameter value: The stored value.
    /// - Returns: The identifiers and proxies of the value, in order, which is empty for an
    ///   empty list; or `nil` if the value holds anything other than identifiers and proxies.
    static func targets(of value: any EcoreValue) -> [any EcoreValue]? {
        switch value {
        case let identifier as EUUID: return [identifier]
        case let proxy as ResourceProxy: return [proxy]
        case let identifiers as [EUUID]: return identifiers
        case let proxies as [ResourceProxy]: return proxies
        case let array as EcoreValueArray: return array.values.allSatisfy(isTarget) ? array.values : nil
        default: return nil
        }
    }

    /// Whether a value is a single target of a reference.
    ///
    /// - Parameter value: A value, such as an element of a list.
    /// - Returns: `true` for an identifier or a ``ResourceProxy``.
    static func isTarget(_ value: any EcoreValue) -> Bool {
        value is EUUID || value is ResourceProxy
    }

    /// Whether a list holds targets of a reference among values of other kinds.
    ///
    /// Such a list is neither a reference nor a list of values, so no document can hold it.
    ///
    /// - Parameter value: The stored value.
    /// - Returns: `true` for an ``EcoreValueArray`` that holds an identifier or a proxy
    ///   together with a value that is neither.
    static func mixesTargetsWithOtherValues(_ value: any EcoreValue) -> Bool {
        guard let array = value as? EcoreValueArray else { return false }
        return array.values.contains(where: isTarget) && !array.values.allSatisfy(isTarget)
    }
}

/// Helpers for the values that documents hold as text.
enum PrimitiveValues {
    /// Whether a stored value is a single value that a document holds as text.
    ///
    /// Texts, Boolean values, numbers, characters and dates have a textual form.
    /// Identifiers and proxies refer to objects, and lists and objects have no textual
    /// form of their own.
    ///
    /// - Parameter value: The stored value.
    /// - Returns: `true` if the value has a textual form.
    static func isPrimitive(_ value: any EcoreValue) -> Bool {
        switch value {
        case is String, is Bool, is Date, is Character, is Decimal: return true
        case is any BinaryInteger, is any BinaryFloatingPoint: return true
        default: return false
        }
    }

    /// The elements of a stored list of primitive values.
    ///
    /// - Parameter value: The stored value.
    /// - Returns: The elements, in order, if the value is a list (an array or an
    ///   ``EcoreValueArray``) whose elements all have a textual form (see
    ///   ``isPrimitive(_:)``); otherwise `nil`.
    static func elements(of value: any EcoreValue) -> [any EcoreValue]? {
        let elements: [any EcoreValue]
        if let array = value as? EcoreValueArray {
            elements = array.values
        } else if let array = value as? [any EcoreValue] {
            elements = array
        } else {
            return nil
        }
        return elements.allSatisfy(isPrimitive) ? elements : nil
    }
}

/// Helpers for values that hold objects themselves rather than their identifiers.
enum ObjectValues {
    /// The objects that a stored value holds.
    ///
    /// An empty list holds no objects, whatever its element type, so an empty list of
    /// identifiers, such as an unused many-valued reference, is not mistaken for one.
    ///
    /// - Parameter value: The stored value.
    /// - Returns: The objects, in order, for an object or a non-empty list (an array or an
    ///   ``EcoreValueArray``) of objects; otherwise `nil`.
    static func objects(of value: any EcoreValue) -> [any EObject]? {
        if let object = value as? any EObject { return [object] }
        if let objects = value as? [any EObject] { return objects.isEmpty ? nil : objects }
        guard let array = value as? EcoreValueArray, !array.values.isEmpty else { return nil }
        let objects = array.values.compactMap { $0 as? any EObject }
        return objects.count == array.values.count ? objects : nil
    }
}

/// The description of a feature value that a document cannot hold.
enum UnwritableValue {
    /// Describes a value that is neither a primitive value nor a reference to objects.
    ///
    /// - Parameters:
    ///   - value: The stored value.
    ///   - feature: The name of the feature that holds the value.
    ///   - className: The name of the class of the object that holds the value.
    /// - Returns: A sentence that names the feature, the class, and the type of the value.
    static func message(_ value: any EcoreValue, feature: String, className: String) -> String {
        "Cannot write the value of feature '\(feature)' of class '\(className)': a value of type "
            + "\(type(of: value)) is neither a primitive value nor a reference to objects"
    }
}

extension XMIError {
    /// The error for a feature value that an XMI document cannot hold.
    ///
    /// - Parameters:
    ///   - value: The stored value.
    ///   - feature: The name of the feature that holds the value.
    ///   - className: The name of the class of the object that holds the value.
    /// - Returns: An ``XMIError/unsupportedFeature(_:)`` error that names the feature and the class.
    static func unwritableValue(_ value: any EcoreValue, feature: String, className: String) -> XMIError {
        .unsupportedFeature(UnwritableValue.message(value, feature: feature, className: className))
    }
}

extension JSONError {
    /// The error for a feature value that a JSON document cannot hold.
    ///
    /// - Parameters:
    ///   - value: The stored value, or the element of a list that has no JSON form.
    ///   - feature: The name of the feature that holds the value.
    ///   - className: The name of the class of the object that holds the value.
    /// - Returns: A ``JSONError/parseError(_:)`` error that names the feature and the class.
    static func unwritableValue(_ value: any EcoreValue, feature: String, className: String) -> JSONError {
        .parseError(UnwritableValue.message(value, feature: feature, className: className))
    }
}
