//
// EOperation.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

// MARK: - EParameter

/// A parameter of an operation in the Ecore metamodel.
///
/// A parameter is a typed element that belongs to an ``EOperation``. It has a name, an
/// optional type, and a multiplicity. Its descriptor is the `EParameter` class of
/// ``EcorePackage``.
///
/// ## Example
///
/// ```swift
/// let days = EParameter(name: "days", eType: EcorePackage.dataType(.eInt))
/// ```
public struct EParameter: ENamedElement, ETypedElement {
    /// The metaclass of every parameter is the `EParameter` class of ``EcorePackage``.
    public typealias Classifier = EClass

    /// Unique identifier for this parameter.
    public let id: EUUID

    /// The metaclass describing this parameter.
    public var eClass: EClass { EcorePackage.metaClass(.eParameter) }

    /// The identifier of the operation that contains this parameter, if any.
    public internal(set) var eContainerID: EUUID?

    /// The name of this parameter.
    public var name: String

    /// Annotations attached to this parameter.
    public var eAnnotations: [EAnnotation] {
        didSet { ContainerStamp.stamp(&eAnnotations, container: id) }
    }

    /// The type of this parameter, or `nil` if the type is not set.
    public var eType: (any EClassifier)?

    /// The lower bound of this parameter's multiplicity.
    public var lowerBound: Int

    /// The upper bound of this parameter's multiplicity (`-1` means unbounded).
    public var upperBound: Int

    /// Whether the values of this parameter are ordered.
    public var ordered: Bool

    /// Whether the values of this parameter are unique.
    public var unique: Bool

    /// The generic type of this element, if its type has type arguments or is a type parameter.
    ///
    /// If this is `nil`, ``eType`` alone describes the type. Otherwise the generic type's
    /// classifier is the raw type that ``eType`` holds.
    public var eGenericType: EGenericType? = nil {
        didSet { ContainerStamp.stamp(&eGenericType, container: id) }
    }

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a new parameter.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (a new one is generated if omitted).
    ///   - name: The name of the parameter.
    ///   - eType: The type of the parameter (default: none).
    ///   - lowerBound: Minimum multiplicity (default: 0).
    ///   - upperBound: Maximum multiplicity (default: 1, use -1 for unbounded).
    ///   - ordered: Whether values are ordered (default: true).
    ///   - unique: Whether values are unique (default: true).
    ///   - eAnnotations: Annotations (empty by default).
    public init(
        id: EUUID = EUUID(),
        name: String,
        eType: (any EClassifier)? = nil,
        lowerBound: Int = 0,
        upperBound: Int = 1,
        ordered: Bool = true,
        unique: Bool = true,
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.name = name
        self.eType = eType
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.ordered = ordered
        self.unique = unique
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
        ContainerStamp.stamp(&self.eAnnotations, container: id)
    }

    /// Whether this parameter is multi-valued.
    public var isMany: Bool { upperBound > 1 || upperBound == -1 }

    /// Whether this parameter is required.
    public var isRequired: Bool { lowerBound >= 1 }

    // MARK: EObject

    /// Reflectively retrieves the value of a feature.
    ///
    /// - Parameter feature: The structural feature whose value to retrieve.
    /// - Returns: The feature's current value, or `nil` if not set.
    public func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        if case .value(let value) = reflectiveEGet(feature) { return value }
        return storage.get(feature: feature.id)
    }

    /// Reflectively sets the value of a feature.
    ///
    /// - Parameters:
    ///   - feature: The structural feature to modify.
    ///   - value: The new value, or `nil` to unset.
    public mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?) {
        if reflectiveESet(feature, value) { return }
        storage.set(feature: feature.id, value: value)
    }

    /// Checks whether a feature has been explicitly set.
    ///
    /// - Parameter feature: The structural feature to check.
    /// - Returns: `true` if the feature differs from its default.
    public func eIsSet(_ feature: some EStructuralFeature) -> Bool {
        if let isSet = reflectiveEIsSet(feature) { return isSet }
        return storage.isSet(feature: feature.id)
    }

    /// Unsets a feature, returning it to its default value.
    ///
    /// - Parameter feature: The structural feature to unset.
    public mutating func eUnset(_ feature: some EStructuralFeature) {
        if reflectiveEUnset(feature) { return }
        storage.unset(feature: feature.id)
    }

    /// Compares two parameters by identifier.
    public static func == (lhs: EParameter, rhs: EParameter) -> Bool { lhs.id == rhs.id }

    /// Hashes the identifier of this parameter.
    ///
    /// - Parameter hasher: The hasher to combine the identifier into.
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - EOperation

/// An operation in the Ecore metamodel.
///
/// Operations represent the behavioural methods that can be invoked on instances of a
/// class. An operation has a name, an optional result type (an operation without a type
/// returns nothing), a multiplicity for its result, an ordered list of ``EParameter``
/// values, and the classifiers of the exceptions it can raise. Its descriptor is the
/// `EOperation` class of ``EcorePackage``.
///
/// ## Example
///
/// ```swift
/// let borrow = EOperation(
///     name: "borrow",
///     eType: EcorePackage.dataType(.eBoolean),
///     eParameters: [EParameter(name: "days", eType: EcorePackage.dataType(.eInt))])
/// ```
public struct EOperation: ENamedElement, ETypedElement {
    /// The metaclass of every operation is the `EOperation` class of ``EcorePackage``.
    public typealias Classifier = EClass

    /// Unique identifier for this operation.
    public let id: EUUID

    /// The metaclass describing this operation.
    public var eClass: EClass { EcorePackage.metaClass(.eOperation) }

    /// The identifier of the class that contains this operation, if any.
    public internal(set) var eContainerID: EUUID?

    /// The name of this operation.
    public var name: String

    /// Annotations attached to this operation.
    public var eAnnotations: [EAnnotation] {
        didSet { ContainerStamp.stamp(&eAnnotations, container: id) }
    }

    /// The result type of this operation, or `nil` if the operation returns nothing.
    public var eType: (any EClassifier)?

    /// The lower bound of the result's multiplicity.
    public var lowerBound: Int

    /// The upper bound of the result's multiplicity (`-1` means unbounded).
    public var upperBound: Int

    /// Whether the values of the result are ordered.
    public var ordered: Bool

    /// Whether the values of the result are unique.
    public var unique: Bool

    /// The parameters of this operation, in declaration order.
    public var eParameters: [EParameter] {
        didSet { ContainerStamp.stamp(&eParameters, container: id) }
    }

    /// The classifiers of the exceptions this operation can raise.
    public var eExceptions: [any EClassifier]

    /// The generic type of this element, if its type has type arguments or is a type parameter.
    ///
    /// If this is `nil`, ``eType`` alone describes the type. Otherwise the generic type's
    /// classifier is the raw type that ``eType`` holds.
    public var eGenericType: EGenericType? = nil {
        didSet { ContainerStamp.stamp(&eGenericType, container: id) }
    }

    /// The type parameters of this element, in declaration order.
    public var eTypeParameters: [ETypeParameter] = [] {
        didSet { ContainerStamp.stamp(&eTypeParameters, container: id) }
    }

    /// The generic exceptions of this operation, in declaration order.
    ///
    /// If the list is empty, ``eExceptions`` alone describes the exceptions.
    public var eGenericExceptions: [EGenericType] = [] {
        didSet { EGenericType.stamp(&eGenericExceptions, container: id) }
    }

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a new operation.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (a new one is generated if omitted).
    ///   - name: The name of the operation.
    ///   - eType: The result type (default: none).
    ///   - lowerBound: Minimum multiplicity of the result (default: 0).
    ///   - upperBound: Maximum multiplicity of the result (default: 1, use -1 for unbounded).
    ///   - ordered: Whether result values are ordered (default: true).
    ///   - unique: Whether result values are unique (default: true).
    ///   - eParameters: The parameters (empty by default).
    ///   - eExceptions: The exception classifiers (empty by default).
    ///   - eAnnotations: Annotations (empty by default).
    public init(
        id: EUUID = EUUID(),
        name: String,
        eType: (any EClassifier)? = nil,
        lowerBound: Int = 0,
        upperBound: Int = 1,
        ordered: Bool = true,
        unique: Bool = true,
        eParameters: [EParameter] = [],
        eExceptions: [any EClassifier] = [],
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.name = name
        self.eType = eType
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.ordered = ordered
        self.unique = unique
        self.eParameters = eParameters
        self.eExceptions = eExceptions
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
        ContainerStamp.stamp(&self.eAnnotations, container: id)
        ContainerStamp.stamp(&self.eParameters, container: id)
    }

    /// Whether the result of this operation is multi-valued.
    public var isMany: Bool { upperBound > 1 || upperBound == -1 }

    /// Whether the result of this operation is required.
    public var isRequired: Bool { lowerBound >= 1 }

    /// Retrieves a parameter by name.
    ///
    /// - Parameter name: The name of the parameter.
    /// - Returns: The first parameter with that name, or `nil` if there is none.
    public func getParameter(name: String) -> EParameter? {
        eParameters.first { $0.name == name }
    }

    // MARK: EObject

    /// Reflectively retrieves the value of a feature.
    ///
    /// - Parameter feature: The structural feature whose value to retrieve.
    /// - Returns: The feature's current value, or `nil` if not set.
    public func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        if case .value(let value) = reflectiveEGet(feature) { return value }
        return storage.get(feature: feature.id)
    }

    /// Reflectively sets the value of a feature.
    ///
    /// - Parameters:
    ///   - feature: The structural feature to modify.
    ///   - value: The new value, or `nil` to unset.
    public mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?) {
        if reflectiveESet(feature, value) { return }
        storage.set(feature: feature.id, value: value)
    }

    /// Checks whether a feature has been explicitly set.
    ///
    /// - Parameter feature: The structural feature to check.
    /// - Returns: `true` if the feature differs from its default.
    public func eIsSet(_ feature: some EStructuralFeature) -> Bool {
        if let isSet = reflectiveEIsSet(feature) { return isSet }
        return storage.isSet(feature: feature.id)
    }

    /// Unsets a feature, returning it to its default value.
    ///
    /// - Parameter feature: The structural feature to unset.
    public mutating func eUnset(_ feature: some EStructuralFeature) {
        if reflectiveEUnset(feature) { return }
        storage.unset(feature: feature.id)
    }

    /// Compares two operations by identifier.
    public static func == (lhs: EOperation, rhs: EOperation) -> Bool { lhs.id == rhs.id }

    /// Hashes the identifier of this operation.
    ///
    /// - Parameter hasher: The hasher to combine the identifier into.
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The properties shared by the typed elements of an operation.
///
/// Both ``EOperation`` and ``EParameter`` carry an optional type and a multiplicity.
public protocol ETypedElement: EObject {
    /// The type of the element, or `nil` if it has none.
    var eType: (any EClassifier)? { get set }

    /// The lower bound of the multiplicity.
    var lowerBound: Int { get set }

    /// The upper bound of the multiplicity (`-1` means unbounded).
    var upperBound: Int { get set }

    /// Whether the values are ordered.
    var ordered: Bool { get set }

    /// Whether the values are unique.
    var unique: Bool { get set }
}
