//
// Generics.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

// MARK: - EGenericType

/// A generic type in the Ecore metamodel.
///
/// A generic type is a use of a classifier, or of a type parameter, optionally with type
/// arguments, as in `EList<EString>`. A generic type with neither a classifier nor a type
/// parameter is a wildcard, which may have an upper or a lower bound (for example
/// `? extends Car`).
///
/// A generic type refers to its classifier through a snapshot, as the types of attributes do,
/// and to its type parameter by identifier. Type arguments and bounds are generic types in
/// their own right.
///
/// ```swift
/// let listOfStrings = EGenericType(
///     eClassifier: EcorePackage.dataType(.eEList),
///     eTypeArguments: [EGenericType(eClassifier: EcorePackage.dataType(.eString))])
/// ```
public struct EGenericType: EObject, EMetaObject {
    /// The metaclass of generic types is the `EGenericType` class of ``EcorePackage``.
    public typealias Classifier = EClass

    /// Unique identifier for this generic type.
    public let id: EUUID

    /// The metaclass describing this generic type.
    public var eClass: EClass { EcorePackage.metaClass(.eGenericType) }

    /// The identifier of the element that contains this generic type, if any.
    public internal(set) var eContainerID: EUUID?

    /// The classifier that this generic type uses, if it is not a type parameter or a wildcard.
    ///
    /// The classifier is a snapshot, kept up to date by ``MetamodelLinker``.
    public var eClassifier: (any EClassifier)?

    /// The identifier of the type parameter that this generic type uses, if any.
    public var eTypeParameter: EUUID?

    /// The type arguments that parameterise the classifier.
    public var eTypeArguments: [EGenericType] {
        didSet { Self.stamp(&eTypeArguments, container: id) }
    }

    /// The upper bound of a wildcard, held as an array of at most one element.
    private var upperBoundStorage: [EGenericType]

    /// The lower bound of a wildcard, held as an array of at most one element.
    private var lowerBoundStorage: [EGenericType]

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a generic type.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - eClassifier: The classifier that the type uses, if any.
    ///   - eTypeParameter: The identifier of the type parameter that the type uses, if any.
    ///   - eTypeArguments: The type arguments (empty by default).
    ///   - eUpperBound: The upper bound of a wildcard, if any.
    ///   - eLowerBound: The lower bound of a wildcard, if any.
    public init(
        id: EUUID = EUUID(),
        eClassifier: (any EClassifier)? = nil,
        eTypeParameter: EUUID? = nil,
        eTypeArguments: [EGenericType] = [],
        eUpperBound: EGenericType? = nil,
        eLowerBound: EGenericType? = nil
    ) {
        self.id = id
        self.eClassifier = eClassifier
        self.eTypeParameter = eTypeParameter
        self.eTypeArguments = eTypeArguments
        self.upperBoundStorage = eUpperBound.map { [$0] } ?? []
        self.lowerBoundStorage = eLowerBound.map { [$0] } ?? []
        self.storage = EObjectStorage()
        Self.stamp(&self.eTypeArguments, container: id)
        Self.stamp(&self.upperBoundStorage, container: id)
        Self.stamp(&self.lowerBoundStorage, container: id)
    }

    /// The upper bound of a wildcard, if any.
    public var eUpperBound: EGenericType? {
        get { upperBoundStorage.first }
        set {
            upperBoundStorage = newValue.map { [$0] } ?? []
            Self.stamp(&upperBoundStorage, container: id)
        }
    }

    /// The lower bound of a wildcard, if any.
    public var eLowerBound: EGenericType? {
        get { lowerBoundStorage.first }
        set {
            lowerBoundStorage = newValue.map { [$0] } ?? []
            Self.stamp(&lowerBoundStorage, container: id)
        }
    }

    /// The raw classifier of this generic type, if it has one.
    ///
    /// A type parameter has no raw classifier of its own; see ``EClassifier`` bounds for the
    /// classifier that a type parameter erases to.
    public var eRawType: (any EClassifier)? { eClassifier }

    /// Whether this generic type is a wildcard: it has neither a classifier nor a type parameter.
    public var isWildcard: Bool { eClassifier == nil && eTypeParameter == nil }

    /// Whether this generic type is more than a plain use of a classifier.
    ///
    /// A plain use names a classifier only. Anything else (type arguments, a type parameter,
    /// or a wildcard) cannot be written as a simple `eType` reference.
    public var isParameterised: Bool {
        eClassifier == nil || !eTypeArguments.isEmpty || !upperBoundStorage.isEmpty
            || !lowerBoundStorage.isEmpty || eTypeParameter != nil
    }

    /// Whether this generic type has the same structure as another, ignoring identifiers.
    ///
    /// - Parameter other: The generic type to compare with.
    /// - Returns: `true` if classifiers, type parameters, arguments, and bounds all agree.
    public func hasSameStructure(as other: EGenericType) -> Bool {
        eClassifier?.id == other.eClassifier?.id && eTypeParameter == other.eTypeParameter
            && eTypeArguments.count == other.eTypeArguments.count
            && zip(eTypeArguments, other.eTypeArguments).allSatisfy { $0.hasSameStructure(as: $1) }
            && Self.same(eUpperBound, other.eUpperBound) && Self.same(eLowerBound, other.eLowerBound)
    }

    private static func same(_ first: EGenericType?, _ second: EGenericType?) -> Bool {
        switch (first, second) {
        case (nil, nil): return true
        case (let left?, let right?): return left.hasSameStructure(as: right)
        default: return false
        }
    }

    /// This generic type without its references to deleted elements.
    ///
    /// A type argument that refers to a deleted classifier or type parameter becomes an
    /// unbounded wildcard, so that the arity of the type is kept; a bound that does so is
    /// dropped.
    ///
    /// - Parameter doomed: The identifiers of the deleted classifiers and type parameters.
    /// - Returns: The remaining generic type, or `nil` if its own classifier or type parameter
    ///   is deleted.
    public func removingReferences(to doomed: Set<EUUID>) -> EGenericType? {
        if let classifier = eClassifier, doomed.contains(classifier.id) { return nil }
        if let parameter = eTypeParameter, doomed.contains(parameter) { return nil }
        var result = self
        result.eTypeArguments = eTypeArguments.map {
            $0.removingReferences(to: doomed) ?? EGenericType(id: $0.id)
        }
        result.eUpperBound = eUpperBound.flatMap { $0.removingReferences(to: doomed) }
        result.eLowerBound = eLowerBound.flatMap { $0.removingReferences(to: doomed) }
        return result
    }

    /// The generic types of this type's arguments and bounds, in feature order.
    var containedTypes: [(feature: EcoreFeatureName, object: EGenericType)] {
        upperBoundStorage.map { (.eUpperBound, $0) } + eTypeArguments.map { (.eTypeArguments, $0) }
            + lowerBoundStorage.map { (.eLowerBound, $0) }
    }

    /// Records the container of generic types.
    static func stamp(_ types: inout [EGenericType], container: EUUID) {
        for index in types.indices where types[index].eContainerID != container {
            types[index].eContainerID = container
        }
    }

    // MARK: - EObject Protocol Implementation

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
    /// - Returns: `true` if the feature has been set, `false` otherwise.
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

    /// Compares two generic types for equality.
    ///
    /// Generic types are equal if they have the same identifier.
    public static func == (lhs: EGenericType, rhs: EGenericType) -> Bool { lhs.id == rhs.id }

    /// Hashes the identifier of this generic type.
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - ETypeParameter

/// A type parameter of a generic classifier or operation.
///
/// A type parameter has a name and any number of bounds, each a generic type, as in
/// `T extends Car & Comparable<T>`.
///
/// ```swift
/// let parameter = ETypeParameter(name: "T", eBounds: [EGenericType(eClassifier: carClass)])
/// ```
public struct ETypeParameter: ENamedElement {
    /// The metaclass of type parameters is the `ETypeParameter` class of ``EcorePackage``.
    public typealias Classifier = EClass

    /// Unique identifier for this type parameter.
    public let id: EUUID

    /// The metaclass describing this type parameter.
    public var eClass: EClass { EcorePackage.metaClass(.eTypeParameter) }

    /// The identifier of the classifier or operation that declares this type parameter, if any.
    public internal(set) var eContainerID: EUUID?

    /// The name of this type parameter, such as `T`.
    public var name: String

    /// Annotations attached to this type parameter.
    public var eAnnotations: [EAnnotation] {
        didSet { ContainerStamp.stamp(&eAnnotations, container: id) }
    }

    /// The bounds of this type parameter, in declaration order.
    public var eBounds: [EGenericType] {
        didSet { EGenericType.stamp(&eBounds, container: id) }
    }

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a type parameter.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - name: The name of the type parameter.
    ///   - eBounds: The bounds (none by default).
    ///   - eAnnotations: Annotations (empty by default).
    public init(
        id: EUUID = EUUID(), name: String, eBounds: [EGenericType] = [],
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.name = name
        self.eBounds = eBounds
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
        ContainerStamp.stamp(&self.eAnnotations, container: id)
        EGenericType.stamp(&self.eBounds, container: id)
    }

    // MARK: - EObject Protocol Implementation

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
    /// - Returns: `true` if the feature has been set, `false` otherwise.
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

    /// Compares two type parameters for equality.
    ///
    /// Type parameters are equal if they have the same identifier.
    public static func == (lhs: ETypeParameter, rhs: ETypeParameter) -> Bool { lhs.id == rhs.id }

    /// Hashes the identifier of this type parameter.
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Reflection

extension EGenericType: EcoreReflective {
    func reflectiveGet(_ feature: EcoreFeatureName) -> ReflectiveValue {
        switch feature {
        case .eUpperBound: return .value(eUpperBound)
        case .eLowerBound: return .value(eLowerBound)
        case .eTypeArguments: return ReflectiveValues.collection(eTypeArguments)
        case .eRawType: return .value(eRawType.flatMap { EcorePackage.canonical($0) as? any EcoreValue })
        case .eClassifier:
            return .value(eClassifier.flatMap { EcorePackage.canonical($0) as? any EcoreValue })
        case .eTypeParameter: return .value(eTypeParameter)
        default: return .unsupported
        }
    }

    mutating func reflectiveSet(_ feature: EcoreFeatureName, _ value: (any EcoreValue)?) -> Bool {
        switch feature {
        case .eUpperBound: eUpperBound = value as? EGenericType
        case .eLowerBound: eLowerBound = value as? EGenericType
        case .eTypeArguments:
            eTypeArguments = ReflectiveValues.elements(value, as: EGenericType.self) ?? []
        case .eClassifier: eClassifier = value as? any EClassifier
        case .eTypeParameter:
            if let identifier = value as? EUUID {
                eTypeParameter = identifier
            } else if let parameter = value as? ETypeParameter {
                eTypeParameter = parameter.id
            } else {
                eTypeParameter = nil
            }
        default: return false
        }
        return true
    }

    var containedObjects: [(feature: EcoreFeatureName, object: any EObject)] {
        containedTypes.map { (feature: $0.feature, object: $0.object) }
    }
}

extension ETypeParameter: EcoreReflective {
    func reflectiveGet(_ feature: EcoreFeatureName) -> ReflectiveValue {
        switch feature {
        case .name: return .value(name)
        case .eAnnotations: return ReflectiveValues.collection(eAnnotations)
        case .eBounds: return ReflectiveValues.collection(eBounds)
        default: return .unsupported
        }
    }

    mutating func reflectiveSet(_ feature: EcoreFeatureName, _ value: (any EcoreValue)?) -> Bool {
        switch feature {
        case .name: name = value as? String ?? ""
        case .eAnnotations:
            eAnnotations = ReflectiveValues.elements(value, as: EAnnotation.self) ?? []
        case .eBounds: eBounds = ReflectiveValues.elements(value, as: EGenericType.self) ?? []
        default: return false
        }
        return true
    }

    var containedObjects: [(feature: EcoreFeatureName, object: any EObject)] {
        eAnnotations.map { (feature: EcoreFeatureName.eAnnotations, object: $0) }
            + eBounds.map { (feature: EcoreFeatureName.eBounds, object: $0) }
    }
}

// MARK: - Stamping

extension ContainerStamp {
    /// Records the container of type parameters.
    static func stamp(_ parameters: inout [ETypeParameter], container: EUUID) {
        for index in parameters.indices where parameters[index].eContainerID != container {
            parameters[index].eContainerID = container
        }
    }

    /// Records the container of an optional generic type.
    static func stamp(_ type: inout EGenericType?, container: EUUID) {
        if type?.eContainerID != container { type?.eContainerID = container }
    }
}

// MARK: - Generic Typing

/// Conversions between a typed element's `eType` and its generic type.
enum GenericTyping {
    /// Splits a generic type that is assigned to an element into its stored form.
    ///
    /// A plain use of a classifier is stored as the element's `eType` only.
    ///
    /// - Parameter value: The generic type being assigned, or `nil` to clear it.
    /// - Returns: The explicit generic type to store (if any) and the raw classifier for `eType`.
    static func stored(_ value: EGenericType?) -> (generic: EGenericType?, raw: (any EClassifier)?) {
        guard let value else { return (nil, nil) }
        return (value.isParameterised ? value : nil, value.eClassifier)
    }
}
