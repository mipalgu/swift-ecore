//
// EClassifier.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - EDataType

/// A data type in the Ecore metamodel.
///
/// `EDataType` represents primitive and serialisable types in the metamodel, including:
/// - Primitive types (EString, EInt, EBoolean, etc.)
/// - Custom serialisable types with string representation
/// - Value objects that can be converted to/from strings
///
/// Data types differ from classes in that they have value semantics and can be
/// serialised as attribute values rather than requiring object identity.
///
/// ## Example
///
/// ```swift
/// let stringType = EDataType(
///     id: EUUID(),
///     name: "EString",
///     instanceClassName: "Swift.String",
///     serialisable: true
/// )
/// ```
public struct EDataType: EClassifier, ENamedElement {
    /// The type of classifier for this data type.
    public typealias Classifier = EDataTypeClassifier

    /// Unique identifier for this data type.
    public let id: EUUID

    /// The metaclass describing this data type.
    public let eClass: Classifier

    /// The name of this data type.
    ///
    /// Should be unique within the containing package. Examples: "EString", "EInt", "URI".
    public var name: String

    /// Annotations attached to this data type.
    ///
    /// Can be used for generation hints, documentation, or validation constraints.
    public var eAnnotations: [EAnnotation]

    /// Whether this data type can be serialised to/from strings.
    ///
    /// Serialisable data types can be converted to string literals in XMI/JSON.
    /// Non-serialisable types require custom serialisation logic.
    public var serialisable: Bool

    /// The fully qualified name of the instance class (optional).
    ///
    /// For Swift, this might be "Swift.String", "Foundation.Date", etc.
    /// Used for code generation and reflection.
    public var instanceClassName: String?

    /// The default value for this data type as a string literal (optional).
    ///
    /// Used when attributes of this type are not explicitly set.
    public var defaultValueLiteral: String?

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a new data type.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - name: The name of the data type.
    ///   - serialisable: Whether the type can be serialised (default: true).
    ///   - instanceClassName: Optional fully qualified class name.
    ///   - defaultValueLiteral: Optional default value as string.
    ///   - eAnnotations: Annotations (empty by default).
    public init(
        id: EUUID = EUUID(),
        name: String,
        serialisable: Bool = true,
        instanceClassName: String? = nil,
        defaultValueLiteral: String? = nil,
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.eClass = EDataTypeClassifier()
        self.name = name
        self.serialisable = serialisable

        // Auto-set instanceClassName for built-in Ecore types
        if instanceClassName == nil {
            self.instanceClassName =
                switch name {
                case EcoreDataType.eString.rawValue: "Swift.String"
                case EcoreDataType.eInt.rawValue: "Swift.Int"
                case EcoreDataType.eBoolean.rawValue: "Swift.Bool"
                case EcoreDataType.eFloat.rawValue: "Swift.Float"
                case EcoreDataType.eDouble.rawValue: "Swift.Double"
                case EcoreDataType.eDate.rawValue: "Foundation.Date"
                case EcoreDataType.eChar.rawValue: "Swift.Character"
                case EcoreDataType.eByte.rawValue: "Swift.Int8"
                case EcoreDataType.eShort.rawValue: "Swift.Int16"
                case EcoreDataType.eLong.rawValue: "Swift.Int64"
                default: nil
                }
        } else {
            self.instanceClassName = instanceClassName
        }

        self.defaultValueLiteral = defaultValueLiteral
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
    }

    // MARK: - EObject Protocol Implementation

    /// Reflectively retrieves the value of a feature.
    ///
    /// - Parameter feature: The structural feature whose value to retrieve.
    /// - Returns: The feature's current value, or `nil` if not set.
    public func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        return storage.get(feature: feature.id)
    }

    /// Reflectively sets the value of a feature.
    ///
    /// - Parameters:
    ///   - feature: The structural feature to modify.
    ///   - value: The new value, or `nil` to unset.
    public mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?) {
        storage.set(feature: feature.id, value: value)
    }

    /// Checks whether a feature has been explicitly set.
    ///
    /// - Parameter feature: The structural feature to check.
    /// - Returns: `true` if the feature has been set, `false` otherwise.
    public func eIsSet(_ feature: some EStructuralFeature) -> Bool {
        return storage.isSet(feature: feature.id)
    }

    /// Unsets a feature, returning it to its default value.
    ///
    /// - Parameter feature: The structural feature to unset.
    public mutating func eUnset(_ feature: some EStructuralFeature) {
        storage.unset(feature: feature.id)
    }

    // MARK: - Equatable & Hashable

    /// Compares two data types for equality.
    ///
    /// Data types are equal if they have the same identifier.
    ///
    /// - Parameters:
    ///   - lhs: The first data type to compare.
    ///   - rhs: The second data type to compare.
    /// - Returns: `true` if the data types are equal, `false` otherwise.
    public static func == (lhs: EDataType, rhs: EDataType) -> Bool {
        return lhs.id == rhs.id
    }

    /// Hashes the essential components of this data type.
    ///
    /// Only the identifier is used for hashing to maintain consistency with equality.
    ///
    /// - Parameter hasher: The hasher to use for combining components.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - EEnumLiteral

/// A literal value within an enumeration.
///
/// `EEnumLiteral` represents a single named value in an `EEnum`, similar to
/// enum cases in Swift or constants in Java enums.
///
/// ## Example
///
/// ```swift
/// let blackbird = EEnumLiteral(
///     name: "blackbird",
///     value: 0,
///     literal: "BLACKBIRD"
/// )
/// ```
public struct EEnumLiteral: ENamedElement {
    /// The type of classifier for this enum literal.
    public typealias Classifier = EEnumLiteralClassifier

    /// Unique identifier for this literal.
    public let id: EUUID

    /// The metaclass describing this enum literal.
    public let eClass: Classifier

    /// The name of this literal.
    ///
    /// Used as the identifier in generated code. Example: "blackbird".
    public var name: String

    /// Annotations attached to this literal.
    public var eAnnotations: [EAnnotation]

    /// The integer value of this literal.
    ///
    /// Used for ordinal comparisons and serialisation. Typically starts at 0.
    public var value: Int

    /// The string literal representation (optional).
    ///
    /// If not provided, defaults to the name. Example: "BLACKBIRD" vs "blackbird".
    public var literal: String?

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a new enum literal.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - name: The name of the literal.
    ///   - value: The integer value (typically ordinal position).
    ///   - literal: Optional string representation (defaults to name if not provided).
    ///   - eAnnotations: Annotations (empty by default).
    public init(
        id: EUUID = EUUID(),
        name: String,
        value: Int,
        literal: String? = nil,
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.eClass = EEnumLiteralClassifier()
        self.name = name
        self.value = value
        self.literal = literal
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
    }

    // MARK: - EObject Protocol Implementation

    /// Reflectively retrieves the value of a feature.
    ///
    /// - Parameter feature: The structural feature whose value to retrieve.
    /// - Returns: The feature's current value, or `nil` if not set.
    public func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        return storage.get(feature: feature.id)
    }

    /// Reflectively sets the value of a feature.
    ///
    /// - Parameters:
    ///   - feature: The structural feature to modify.
    ///   - value: The new value, or `nil` to unset.
    public mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?) {
        storage.set(feature: feature.id, value: value)
    }

    /// Checks whether a feature has been explicitly set.
    ///
    /// - Parameter feature: The structural feature to check.
    /// - Returns: `true` if the feature has been set, `false` otherwise.
    public func eIsSet(_ feature: some EStructuralFeature) -> Bool {
        return storage.isSet(feature: feature.id)
    }

    /// Unsets a feature, returning it to its default value.
    ///
    /// - Parameter feature: The structural feature to unset.
    public mutating func eUnset(_ feature: some EStructuralFeature) {
        storage.unset(feature: feature.id)
    }

    // MARK: - Equatable & Hashable

    /// Compares two enum literals for equality.
    ///
    /// Literals are equal if they have the same identifier.
    ///
    /// - Parameters:
    ///   - lhs: The first literal to compare.
    ///   - rhs: The second literal to compare.
    /// - Returns: `true` if the literals are equal, `false` otherwise.
    public static func == (lhs: EEnumLiteral, rhs: EEnumLiteral) -> Bool {
        return lhs.id == rhs.id
    }

    /// Hashes the essential components of this literal.
    ///
    /// Only the identifier is used for hashing to maintain consistency with equality.
    ///
    /// - Parameter hasher: The hasher to use for combining components.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - EEnum

/// An enumeration type in the Ecore metamodel.
///
/// `EEnum` represents enumerated types with a fixed set of named values,
/// similar to Swift enums or Java enums.
///
/// Each enum contains a collection of ``EEnumLiteral`` values that define
/// the valid values for attributes of this type.
///
/// ## Example
///
/// ```swift
/// let birdType = EEnum(
///     name: "BirdType",
///     literals: [
///         EEnumLiteral(name: "blackbird", value: 0),
///         EEnumLiteral(name: "thrush", value: 1),
///         EEnumLiteral(name: "bluebird", value: 2)
///     ]
/// )
///
/// // Look up literal by name
/// let literal = birdType.getLiteral(name: "thrush")
/// print(literal?.value)  // 1
/// ```
public struct EEnum: EClassifier, ENamedElement {
    /// The type of classifier for this enum.
    public typealias Classifier = EEnumClassifier

    /// Unique identifier for this enum.
    public let id: EUUID

    /// The metaclass describing this enum.
    public let eClass: Classifier

    /// The name of this enum.
    ///
    /// Should be unique within the containing package. Example: "BirdType".
    public var name: String

    /// Annotations attached to this enum.
    public var eAnnotations: [EAnnotation]

    /// The literals (named values) in this enum.
    ///
    /// Each literal has a unique name and integer value within the enum.
    public var literals: [EEnumLiteral]

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a new enumeration.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - name: The name of the enum.
    ///   - literals: The literal values in this enum.
    ///   - eAnnotations: Annotations (empty by default).
    public init(
        id: EUUID = EUUID(),
        name: String,
        literals: [EEnumLiteral] = [],
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.eClass = EEnumClassifier()
        self.name = name
        self.literals = literals
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
    }

    /// Retrieves a literal by its name.
    ///
    /// - Parameter name: The name of the literal to find.
    /// - Returns: The matching literal, or `nil` if not found.
    public func getLiteral(name: String) -> EEnumLiteral? {
        return literals.first { $0.name == name }
    }

    /// Retrieves a literal by its integer value.
    ///
    /// - Parameter value: The integer value of the literal to find.
    /// - Returns: The matching literal, or `nil` if not found.
    public func getLiteral(value: Int) -> EEnumLiteral? {
        return literals.first { $0.value == value }
    }

    // MARK: - EObject Protocol Implementation

    /// Reflectively retrieves the value of a feature.
    ///
    /// - Parameter feature: The structural feature whose value to retrieve.
    /// - Returns: The feature's current value, or `nil` if not set.
    public func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        return storage.get(feature: feature.id)
    }

    /// Reflectively sets the value of a feature.
    ///
    /// - Parameters:
    ///   - feature: The structural feature to modify.
    ///   - value: The new value, or `nil` to unset.
    public mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?) {
        storage.set(feature: feature.id, value: value)
    }

    /// Checks whether a feature has been explicitly set.
    ///
    /// - Parameter feature: The structural feature to check.
    /// - Returns: `true` if the feature has been set, `false` otherwise.
    public func eIsSet(_ feature: some EStructuralFeature) -> Bool {
        return storage.isSet(feature: feature.id)
    }

    /// Unsets a feature, returning it to its default value.
    ///
    /// - Parameter feature: The structural feature to unset.
    public mutating func eUnset(_ feature: some EStructuralFeature) {
        storage.unset(feature: feature.id)
    }

    // MARK: - Equatable & Hashable

    /// Compares two enumerations for equality.
    ///
    /// Enumerations are equal if they have the same identifier.
    ///
    /// - Parameters:
    ///   - lhs: The first enumeration to compare.
    ///   - rhs: The second enumeration to compare.
    /// - Returns: `true` if the enumerations are equal, `false` otherwise.
    public static func == (lhs: EEnum, rhs: EEnum) -> Bool {
        return lhs.id == rhs.id
    }

    /// Hashes the essential components of this enumeration.
    ///
    /// Only the identifier is used for hashing to maintain consistency with equality.
    ///
    /// - Parameter hasher: The hasher to use for combining components.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Classifier Types

/// Metaclass for `EDataType`.
///
/// Describes the structure of `EDataType` itself within the metamodel hierarchy.
/// This is the classifier that describes all `EDataType` instances.
public struct EDataTypeClassifier: EClassifier {
    /// Unique identifier for this metaclass.
    ///
    /// Each instance creates its own unique identifier.
    public let id: EUUID = EUUID()

    /// The name of this classifier.
    ///
    /// Always returns `"EDataType"` to identify this as the metaclass for data types.
    public var name: String { EcoreClassifier.eDataType.rawValue }
}

/// Metaclass for `EEnumLiteral`.
///
/// Describes the structure of `EEnumLiteral` itself within the metamodel hierarchy.
/// This is the classifier that describes all `EEnumLiteral` instances.
public struct EEnumLiteralClassifier: EClassifier {
    /// Unique identifier for this metaclass.
    ///
    /// Each instance creates its own unique identifier.
    public let id: EUUID = EUUID()

    /// The name of this classifier.
    ///
    /// Always returns `"EEnumLiteral"` to identify this as the metaclass for enum literals.
    public var name: String { EcoreClassifier.eEnumLiteral.rawValue }
}

/// Metaclass for `EEnum`.
///
/// Describes the structure of `EEnum` itself within the metamodel hierarchy.
/// This is the classifier that describes all `EEnum` instances.
public struct EEnumClassifier: EClassifier {
    /// Unique identifier for this metaclass.
    ///
    /// Each instance creates its own unique identifier.
    public let id: EUUID = EUUID()

    /// The name of this classifier.
    ///
    /// Always returns `"EEnum"` to identify this as the metaclass for enumerations.
    public var name: String { EcoreClassifier.eEnum.rawValue }
}

// MARK: - EClassifier Type Resolution

/// Helper type for resolving EClassifier types from DynamicEObject instances.
///
/// This type provides static methods for dispatching to the appropriate concrete
/// type initializer based on runtime type information.
public enum EClassifierResolver {
    /// Resolves the concrete EClassifier type from a DynamicEObject.
    ///
    /// Dispatches to the appropriate concrete type initializer based on eClass.name.
    ///
    /// - Parameter object: The DynamicEObject to convert.
    /// - Returns: EClass, EEnum, or EDataType instance.
    /// - Throws: XMIError if the object type is unsupported or initialization fails.
    public static func resolvingType(_ object: any EObject) throws -> any EClassifier {
        guard let dynamicObj = object as? DynamicEObject else {
            throw XMIError.invalidObjectType("\(type(of: object))")
        }

        let eClass = dynamicObj.eClass
        let typeName = eClass.name

        switch typeName {
        case EcoreClassifier.eClass.rawValue:
            guard let result = EClass(object: object) else {
                throw XMIError.missingRequiredAttribute(ErrorMessage.missingNameAttribute.rawValue)
            }
            return result
        case EcoreClassifier.eEnum.rawValue:
            guard let result = EEnum(object: object) else {
                throw XMIError.missingRequiredAttribute(ErrorMessage.missingNameAttribute.rawValue)
            }
            return result
        case EcoreClassifier.eDataType.rawValue:
            guard let result = EDataType(object: object) else {
                throw XMIError.missingRequiredAttribute(
                    "Failed to initialize EDataType from object")
            }
            return result
        default:
            throw XMIError.unsupportedFeature("Unsupported classifier type: \(typeName)")
        }
    }

    /// Resolves a data type reference for an EAttribute.
    ///
    /// Falls back to EString if type cannot be determined.
    ///
    /// - Parameter object: The DynamicEObject containing eType reference.
    /// - Returns: The resolved EDataType.
    public static func resolvingDataType(_ object: any EObject) -> any EClassifier {
        guard let dynamicObj = object as? DynamicEObject,
            let typeName: String = dynamicObj.eGet(.name)
        else {
            return EDataType(name: EcoreDataType.eString.rawValue)
        }

        return EDataType(name: typeName)
    }

    /// Resolves a reference type for an EReference.
    ///
    /// Creates a placeholder EClass with just the name.
    ///
    /// - Note: In a full implementation, this would use two-pass conversion to
    ///         resolve to the actual EClass from the package.
    ///
    /// - Parameter object: The DynamicEObject containing eType reference.
    /// - Returns: The resolved EClass.
    public static func resolvingReferenceType(_ object: any EObject) -> any EClassifier {
        guard let dynamicObj = object as? DynamicEObject,
            let className: String = dynamicObj.eGet(.name)
        else {
            return EClass(name: EcoreClassifier.eObject.rawValue)
        }

        return EClass(name: className)
    }
}

// MARK: - EEnum Initializer

extension EEnum {
    /// Initialise an EEnum from a DynamicEObject.
    ///
    /// Extracts enum metadata and literals from a dynamic object.
    /// When enum literals cannot be resolved, behaviour depends on the
    /// `shouldIgnoreUnresolvedLiterals` parameter.
    ///
    /// - Parameters:
    ///   - object: The DynamicEObject representing an EEnum.
    ///   - shouldIgnoreUnresolvedLiterals: If `true`, continues processing when literal resolution fails; if `false`, returns `nil` on resolution failure (default: `false`).
    /// - Returns: A new EEnum instance, or `nil` if the object is invalid or missing required attributes.
    public init?(object: any EObject, shouldIgnoreUnresolvedLiterals: Bool = false) {
        guard let dynamicObj = object as? DynamicEObject,
            let name: String = dynamicObj.eGet(.name)
        else {
            return nil
        }

        // Extract enum literals
        var literals: [EEnumLiteral] = []
        if let literalsList: [any EObject] = dynamicObj.eGet(.eLiterals) {
            for literalObj in literalsList {
                if let literal = EEnumLiteral(object: literalObj) {
                    literals.append(literal)
                } else if !shouldIgnoreUnresolvedLiterals {
                    return nil
                }
            }
        }

        // Call existing designated initializer
        self.init(
            name: name,
            literals: literals
        )
    }
}

// MARK: - EEnumLiteral Initializer

extension EEnumLiteral {
    /// Initialise an EEnumLiteral from a DynamicEObject.
    ///
    /// Extracts literal name, value, and string representation from a dynamic object.
    ///
    /// - Parameter object: The DynamicEObject representing an EEnumLiteral.
    /// - Returns: A new EEnumLiteral instance, or `nil` if the object is invalid or missing required attributes.
    public init?(object: any EObject) {
        guard let dynamicObj = object as? DynamicEObject,
            let name: String = dynamicObj.eGet("name") as? String
        else {
            return nil
        }

        let value: Int = dynamicObj.eGet("value") as? Int ?? 0
        let literal: String = dynamicObj.eGet("literal") as? String ?? name

        // Call existing designated initializer
        self.init(
            name: name,
            value: value,
            literal: literal
        )
    }
}

// MARK: - EDataType Initializer

extension EDataType {
    /// Converts a DynamicEObject to an EDataType.
    ///
    /// Extracts data type metadata. Built-in types are automatically recognized.
    ///
    /// - Parameter object: The DynamicEObject representing an EDataType.
    /// - Returns: nil if the object is invalid or missing required attributes.
    public init?(object: any EObject) {
        guard let dynamicObj = object as? DynamicEObject,
            let name: String = dynamicObj.eGet("name") as? String
        else {
            return nil
        }

        let instanceClassName: String? = dynamicObj.eGet("instanceClassName") as? String
        let serialisable: Bool = dynamicObj.eGet("serializable") as? Bool ?? true

        // Call existing designated initializer (auto-sets instanceClassName for built-ins)
        self.init(
            name: name,
            serialisable: serialisable,
            instanceClassName: instanceClassName
        )
    }
}
