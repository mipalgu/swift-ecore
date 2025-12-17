//
// EClass.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - EClass

/// A class in the Ecore metamodel.
///
/// Represents a class definition in the metamodel, similar to a class declaration
/// in object-oriented programming languages. It defines the structure and behaviour of
/// model objects through structural features, operations, and inheritance relationships.
///
/// ## Overview
///
/// `EClass` serves as the primary metaclass type in Ecore, defining:
/// - **Structural Features**: Attributes and references that define the class's properties
/// - **Operations**: Methods that can be invoked on instances
/// - **Inheritance**: Supertypes that this class extends (supporting multiple inheritance)
/// - **Metadata**: Whether the class is abstract or represents an interface
///
/// ## Creating Classes
///
/// Create an EClass using the designated initialiser:
///
/// ```swift
/// let person = EClass(
///     name: "Person",
///     isAbstract: false,
///     structuralFeatures: [
///         // Features would be added here
///     ]
/// )
/// ```
///
/// ## Inheritance Hierarchy
///
/// Classes can extend multiple supertypes through the ``eSuperTypes`` property.
/// The ``allSuperTypes`` computed property provides the complete inheritance hierarchy
/// including transitive supertypes.
///
/// ## Feature Access
///
/// Structural features can be accessed by name using ``getStructuralFeature(name:)``
/// or filtered by type using ``allAttributes`` and ``allReferences``.
public struct EClass: EClassifier, ENamedElement {
    /// The type of classifier for this class.
    ///
    /// All instances of `EClass` use ``EClassClassifier`` as their metaclass, establishing
    /// the metaclass relationship in the Ecore type system.
    public typealias Classifier = EClassClassifier

    /// Unique identifier for this class.
    ///
    /// Used for identity-based equality and hashing.
    public let id: EUUID

    /// The metaclass describing this class.
    public let eClass: Classifier

    /// The name of this class.
    ///
    /// Must be unique within the containing package. By convention, class names
    /// use UpperCamelCase notation.
    public var name: String

    /// Annotations attached to this class.
    ///
    /// Annotations provide extensible metadata commonly used for code generation hints,
    /// documentation, or custom constraints.
    public var eAnnotations: [EAnnotation]

    /// Whether this class is abstract.
    ///
    /// Abstract classes cannot be instantiated directly and typically define
    /// common behaviour for concrete subclasses.
    public var isAbstract: Bool

    /// Whether this class represents an interface.
    ///
    /// Interfaces define contracts without implementation and can be mixed into
    /// classes through multiple inheritance.
    public var isInterface: Bool

    /// The direct supertypes of this class.
    ///
    /// Classes can extend multiple supertypes, enabling multiple inheritance.
    /// For the complete inheritance hierarchy including transitive supertypes,
    /// use ``allSuperTypes``.
    public var eSuperTypes: [EClass]

    /// The structural features (attributes and references) defined on this class.
    ///
    /// Contains features defined directly on this class, excluding inherited features.
    /// For all features including inherited ones, use ``allStructuralFeatures``.
    public var eStructuralFeatures: [any EStructuralFeature]

    /// The operations (methods) defined on this class.
    ///
    /// Contains operations defined directly on this class, excluding inherited operations.
    public var eOperations: [any EOperation]

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Initialise a new class with the specified attributes.
    ///
    /// Creates a new EClass instance with the given configuration. All parameters except
    /// `name` have sensible defaults for common use cases.
    ///
    /// - Parameters:
    ///   - id: Unique identifier; generates a new UUID if not provided.
    ///   - name: The name of the class.
    ///   - isAbstract: Whether the class is abstract; defaults to `false`.
    ///   - isInterface: Whether the class represents an interface; defaults to `false`.
    ///   - eSuperTypes: The direct supertypes; defaults to an empty array.
    ///   - eStructuralFeatures: The structural features; defaults to an empty array.
    ///   - eOperations: The operations; defaults to an empty array.
    ///   - eAnnotations: Annotations; defaults to an empty array.
    public init(
        id: EUUID = EUUID(),
        name: String,
        isAbstract: Bool = false,
        isInterface: Bool = false,
        eSuperTypes: [EClass] = [],
        eStructuralFeatures: [any EStructuralFeature] = [],
        eOperations: [any EOperation] = [],
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.eClass = EClassClassifier()
        self.name = name
        self.isAbstract = isAbstract
        self.isInterface = isInterface
        self.eSuperTypes = eSuperTypes
        self.eStructuralFeatures = eStructuralFeatures
        self.eOperations = eOperations
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
    }

    /// Initialise an EClass from a DynamicEObject.
    ///
    /// Extracts class metadata and structural features from a dynamic object.
    /// When structural features cannot be resolved, behaviour depends on the
    /// `shouldIgnoreUnresolvedFeatures` parameter.
    ///
    /// - Parameters:
    ///   - object: The DynamicEObject representing an EClass.
    ///   - shouldIgnoreUnresolvedFeatures: If `true`, continues processing when feature resolution fails; if `false`, returns `nil` on resolution failure (default: `false`).
    /// - Returns: A new EClass instance, or `nil` if the object is invalid or missing required attributes.
    public init?(object: any EObject, shouldIgnoreUnresolvedFeatures: Bool = false) {
        guard let dynamicObj = object as? DynamicEObject,
            let name: String = dynamicObj.eGet(.name)
        else {
            return nil
        }

        let isAbstract: Bool = dynamicObj.getBoolProperty(.abstract, defaultValue: false)
        let isInterface: Bool = dynamicObj.getBoolProperty(.interface, defaultValue: false)

        // Extract structural features
        var eStructuralFeatures: [any EStructuralFeature] = []
        if let featuresList: [any EObject] = dynamicObj.eGet(.eStructuralFeatures)
        {
            for featureObj in featuresList {
                if let feature = try? EStructuralFeatureResolver.resolvingFeature(featureObj) {
                    eStructuralFeatures.append(feature)
                } else if !shouldIgnoreUnresolvedFeatures {
                    return nil
                }
            }
        }

        // Call existing designated initializer
        // Note: eSuperTypes left empty (TODO: two-pass conversion for type resolution)
        self.init(
            name: name,
            isAbstract: isAbstract,
            isInterface: isInterface,
            eSuperTypes: [],
            eStructuralFeatures: eStructuralFeatures
        )
    }

    // MARK: - Computed Properties

    /// Retrieve all structural features including inherited ones.
    ///
    /// Combines features from this class and all supertypes. This class's features
    /// take precedence in case of name conflicts.
    public var allStructuralFeatures: [any EStructuralFeature] {
        var features = eStructuralFeatures
        for superType in eSuperTypes {
            features.append(contentsOf: superType.allStructuralFeatures)
        }
        return features
    }

    /// Retrieve all attributes including inherited ones.
    ///
    /// Filters ``allStructuralFeatures`` to return only attribute features.
    public var allAttributes: [EAttribute] {
        return allStructuralFeatures.compactMap { $0 as? EAttribute }
    }

    /// Retrieve all references including inherited ones.
    ///
    /// Filters ``allStructuralFeatures`` to return only reference features.
    public var allReferences: [EReference] {
        return allStructuralFeatures.compactMap { $0 as? EReference }
    }

    /// Retrieve all containment references including inherited ones.
    ///
    /// Filters ``allReferences`` to return only containment references, which
    /// define parent-child relationships in the model.
    public var allContainments: [EReference] {
        return allReferences.filter { $0.containment }
    }

    /// Retrieve all supertypes including transitive ones.
    ///
    /// Provides the complete inheritance hierarchy by recursively collecting
    /// all direct and indirect supertypes. The result includes:
    /// - Direct supertypes from ``eSuperTypes``
    /// - Supertypes of supertypes (transitively)
    ///
    /// Duplicates are included if a class appears multiple times in the hierarchy.
    public var allSuperTypes: [EClass] {
        var result = eSuperTypes
        for superType in eSuperTypes {
            result.append(contentsOf: superType.allSuperTypes)
        }
        return result
    }

    // MARK: - Methods

    /// Retrieve a structural feature by name.
    ///
    /// Searches this class's features first, then searches inherited features
    /// from supertypes.
    ///
    /// - Parameter name: The name of the feature to find.
    /// - Returns: The matching feature, or `nil` if not found.
    public func getStructuralFeature(name: String) -> (any EStructuralFeature)? {
        return allStructuralFeatures.first { $0.name == name }
    }

    /// Retrieve an attribute by name.
    ///
    /// Provides a convenient method that searches only attribute features,
    /// including inherited attributes.
    ///
    /// - Parameter name: The name of the attribute to find.
    /// - Returns: The matching attribute, or `nil` if not found.
    public func getEAttribute(name: String) -> EAttribute? {
        return allAttributes.first { $0.name == name }
    }

    /// Retrieve a reference by name.
    ///
    /// Provides a convenient method that searches only reference features,
    /// including inherited references.
    ///
    /// - Parameter name: The name of the reference to find.
    /// - Returns: The matching reference, or `nil` if not found.
    public func getEReference(name: String) -> EReference? {
        return allReferences.first { $0.name == name }
    }

    /// Check if this class is a supertype of another class.
    ///
    /// Determines whether the specified class directly or indirectly extends this class
    /// through the inheritance hierarchy.
    ///
    /// - Parameter other: The class to check.
    /// - Returns: `true` if this class is a supertype of `other`; otherwise, `false`.
    public func isSuperTypeOf(_ other: EClass) -> Bool {
        // Check if other directly extends this class
        if other.eSuperTypes.contains(where: { $0.id == self.id }) {
            return true
        }
        // Check transitively
        for superType in other.eSuperTypes {
            if self.isSuperTypeOf(superType) {
                return true
            }
        }
        return false
    }

    // MARK: - EObject Protocol Implementation

    /// Reflectively retrieve the value of a feature.
    ///
    /// Provides dynamic access to feature values using internal storage, allowing
    /// feature access without compile-time knowledge of the feature.
    ///
    /// - Parameter feature: The structural feature whose value to retrieve.
    /// - Returns: The feature's current value, or `nil` if not set.
    public func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        return storage.get(feature: feature.id)
    }

    /// Reflectively set the value of a feature.
    ///
    /// Provides dynamic modification of feature values using internal storage.
    /// Setting a value to `nil` has the same effect as calling ``eUnset(_:)``.
    ///
    /// - Parameters:
    ///   - feature: The structural feature to modify.
    ///   - value: The new value, or `nil` to unset.
    public mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?) {
        storage.set(feature: feature.id, value: value)
    }

    /// Check whether a feature has been explicitly set.
    ///
    /// Determines if a feature has been assigned a value, even if that value
    /// equals the feature's default.
    ///
    /// - Parameter feature: The structural feature to check.
    /// - Returns: `true` if the feature has been set; otherwise, `false`.
    public func eIsSet(_ feature: some EStructuralFeature) -> Bool {
        return storage.isSet(feature: feature.id)
    }

    /// Unset a feature, returning it to its default value.
    ///
    /// Removes the explicit value for the specified feature. After unsetting,
    /// ``eIsSet(_:)`` will return `false` for this feature, and ``eGet(_:)``
    /// will return `nil`.
    ///
    /// - Parameter feature: The structural feature to unset.
    public mutating func eUnset(_ feature: some EStructuralFeature) {
        storage.unset(feature: feature.id)
    }

    // MARK: - Equatable & Hashable

    /// Compare two classes for equality.
    ///
    /// Classes are considered equal if they have the same unique identifier.
    ///
    /// - Parameters:
    ///   - lhs: The first class to compare.
    ///   - rhs: The second class to compare.
    /// - Returns: `true` if the classes are equal; otherwise, `false`.
    public static func == (lhs: EClass, rhs: EClass) -> Bool {
        return lhs.id == rhs.id
    }

    /// Hash the essential components of this class.
    ///
    /// Uses only the unique identifier for hashing to maintain consistency with equality.
    ///
    /// - Parameter hasher: The hasher to use for combining components.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Classifier Type

/// The metaclass for `EClass`.
///
/// Describes the structure of `EClass` itself within the metamodel hierarchy,
/// establishing the metaclass relationship. This classifier describes all
/// `EClass` instances.
public struct EClassClassifier: EClassifier {
    /// Unique identifier for this metaclass.
    ///
    /// Each instance creates its own unique identifier.
    public let id: EUUID = EUUID()

    /// The name of this classifier.
    ///
    /// Always returns `"EClass"`, identifying this as the metaclass for class definitions.
    public var name: String { EcoreClassifier.eClass.rawValue }
}
