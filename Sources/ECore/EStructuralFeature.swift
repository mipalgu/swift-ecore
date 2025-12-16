//
// EStructuralFeature.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - EAttribute

/// An attribute in the Ecore metamodel.
///
/// Attributes represent data-valued properties of a class, holding primitive or
/// data type values such as strings, numbers, dates, or enumerations. Unlike
/// references, attributes do not point to other objects.
///
/// ## Example
///
/// ```swift
/// let nameAttribute = EAttribute(
///     name: "name",
///     eType: EDataType(name: "EString"),
///     lowerBound: 1  // Required attribute
/// )
/// ```
///
/// ## Multiplicity
///
/// Attributes support multiplicity through ``lowerBound`` and ``upperBound``:
/// - Single-valued: `lowerBound: 0, upperBound: 1`
/// - Required: `lowerBound: 1, upperBound: 1`
/// - Multi-valued: `upperBound: -1` (unbounded)
///
/// ## ID Attributes
///
/// An attribute marked with ``isID`` set to `true` uniquely identifies instances
/// within their container, similar to primary keys in databases.
public struct EAttribute: EStructuralFeature, ENamedElement {
    /// The type of classifier for this attribute.
    ///
    /// All instances of `EAttribute` use ``EAttributeClassifier`` as their metaclass.
    public typealias Classifier = EAttributeClassifier

    /// Unique identifier for this attribute.
    ///
    /// Used for identity-based equality and hashing.
    public let id: EUUID

    /// The metaclass describing this attribute.
    public let eClass: Classifier

    /// The name of this attribute.
    ///
    /// Should be unique within the containing class. By convention, attribute names
    /// use lowerCamelCase.
    public var name: String

    /// Annotations attached to this attribute.
    public var eAnnotations: [EAnnotation]

    /// The data type of this attribute.
    ///
    /// Specifies what kind of values this attribute can hold (e.g., EString, EInt).
    public var eType: any EClassifier

    /// The lower bound of this attribute's multiplicity.
    ///
    /// - `0`: Optional attribute (can be unset)
    /// - `1`: Required attribute (must have a value)
    /// - `n`: Must have at least n values (for multi-valued attributes)
    public var lowerBound: Int

    /// The upper bound of this attribute's multiplicity.
    ///
    /// - `1`: Single-valued attribute
    /// - `-1`: Unbounded (can have any number of values)
    /// - `n`: Can have at most n values
    public var upperBound: Int

    /// Whether this attribute can be modified.
    ///
    /// If `false`, the attribute is read-only after initialisation.
    public var changeable: Bool

    /// Whether this attribute has a volatile value.
    ///
    /// Volatile attributes are not stored but computed on demand.
    public var volatile: Bool

    /// Whether this attribute is transient.
    ///
    /// Transient attributes are not persisted during serialisation.
    public var transient: Bool

    /// The default value for this attribute as a string literal.
    ///
    /// Used when the attribute is not explicitly set. The literal is converted
    /// to the attribute's type using the data type's conversion logic.
    public var defaultValueLiteral: String?

    /// Whether this attribute serves as an identifier.
    ///
    /// ID attributes uniquely identify instances within their container.
    /// Only one attribute per class should be marked as an ID.
    public var isID: Bool

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a new attribute.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - name: The name of the attribute.
    ///   - eType: The data type of the attribute.
    ///   - lowerBound: Minimum multiplicity (default: 0).
    ///   - upperBound: Maximum multiplicity (default: 1, use -1 for unbounded).
    ///   - changeable: Whether the attribute can be modified (default: true).
    ///   - volatile: Whether the attribute is computed (default: false).
    ///   - transient: Whether the attribute is persisted (default: false).
    ///   - defaultValueLiteral: Default value as string (optional).
    ///   - isID: Whether this is an ID attribute (default: false).
    ///   - eAnnotations: Annotations (empty by default).
    public init(
        id: EUUID = EUUID(),
        name: String,
        eType: any EClassifier,
        lowerBound: Int = 0,
        upperBound: Int = 1,
        changeable: Bool = true,
        volatile: Bool = false,
        transient: Bool = false,
        defaultValueLiteral: String? = nil,
        isID: Bool = false,
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.eClass = EAttributeClassifier()
        self.name = name
        self.eType = eType
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.changeable = changeable
        self.volatile = volatile
        self.transient = transient
        self.defaultValueLiteral = defaultValueLiteral
        self.isID = isID
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
    }

    // MARK: - Computed Properties

    /// Whether this attribute is multi-valued.
    ///
    /// Returns `true` if the upper bound is greater than 1 or unbounded (-1).
    public var isMany: Bool {
        return upperBound > 1 || upperBound == -1
    }

    /// Whether this attribute is required.
    ///
    /// Returns `true` if the lower bound is at least 1.
    public var isRequired: Bool {
        return lowerBound >= 1
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

    /// Compares two attributes for equality.
    ///
    /// Attributes are equal if they have the same identifier.
    ///
    /// - Parameters:
    ///   - lhs: The first attribute to compare.
    ///   - rhs: The second attribute to compare.
    /// - Returns: `true` if the attributes are equal, `false` otherwise.
    public static func == (lhs: EAttribute, rhs: EAttribute) -> Bool {
        return lhs.id == rhs.id
    }

    /// Hashes the essential components of this attribute.
    ///
    /// Only the identifier is used for hashing to maintain consistency with equality.
    ///
    /// - Parameter hasher: The hasher to use for combining components.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - EReference

/// A reference in the Ecore metamodel.
///
/// References represent relationships between classes, pointing to other model objects.
/// They enable navigation between instances and can define both simple associations
/// and complex containment hierarchies.
///
/// ## Example
///
/// ```swift
/// let managerRef = EReference(
///     name: "manager",
///     eType: personClass,
///     containment: false,
///     lowerBound: 1  // Required reference
/// )
/// ```
///
/// ## Containment
///
/// References can be either:
/// - **Containment** (`containment: true`): Defines parent-child ownership
/// - **Non-containment** (`containment: false`): Defines associations
///
/// Containment references create a tree structure where children are owned by
/// their parent and deleted when the parent is deleted.
///
/// ## Bidirectional References
///
/// References can have an ``opposite`` reference creating bidirectional navigation.
/// The opposite is stored as a UUID (ID-based reference) and resolved through
/// the Resource pattern when needed.
///
/// ## Example: Bidirectional Reference
///
/// ```swift
/// let booksRef = EReference(
///     name: "books",
///     eType: bookClass,
///     upperBound: -1
/// )
///
/// let authorsRef = EReference(
///     name: "authors",
///     eType: writerClass,
///     upperBound: -1,
///     opposite: booksRef.id  // ID-based opposite
/// )
/// ```
public struct EReference: EStructuralFeature, ENamedElement {
    /// The type of classifier for this reference.
    ///
    /// All instances of `EReference` use ``EReferenceClassifier`` as their metaclass.
    public typealias Classifier = EReferenceClassifier

    /// Unique identifier for this reference.
    ///
    /// Used for identity-based equality, hashing, and opposite reference resolution.
    public let id: EUUID

    /// The metaclass describing this reference.
    public let eClass: Classifier

    /// The name of this reference.
    ///
    /// Should be unique within the containing class. By convention, reference names
    /// use lowerCamelCase.
    public var name: String

    /// Annotations attached to this reference.
    public var eAnnotations: [EAnnotation]

    /// The type of objects this reference points to.
    ///
    /// Must be an `EClass` that defines the structure of referenced objects.
    public var eType: any EClassifier

    /// The lower bound of this reference's multiplicity.
    ///
    /// - `0`: Optional reference (can be unset)
    /// - `1`: Required reference (must point to an object)
    /// - `n`: Must reference at least n objects (for multi-valued references)
    public var lowerBound: Int

    /// The upper bound of this reference's multiplicity.
    ///
    /// - `1`: Single-valued reference
    /// - `-1`: Unbounded (can reference any number of objects)
    /// - `n`: Can reference at most n objects
    public var upperBound: Int

    /// Whether this reference can be modified.
    ///
    /// If `false`, the reference is read-only after initialisation.
    public var changeable: Bool

    /// Whether this reference has a volatile value.
    ///
    /// Volatile references are not stored but computed on demand.
    public var volatile: Bool

    /// Whether this reference is transient.
    ///
    /// Transient references are not persisted during serialisation.
    public var transient: Bool

    /// Whether this is a containment reference.
    ///
    /// Containment references define parent-child ownership relationships.
    /// The referenced objects are considered children of the container and
    /// are typically deleted when the container is deleted.
    public var containment: Bool

    /// The identifier of the opposite reference in a bidirectional relationship.
    ///
    /// For bidirectional references, this stores the UUID of the opposite reference
    /// rather than a direct reference. The opposite reference is resolved through
    /// the Resource pattern when needed.
    ///
    /// Example: In a Writer.books ↔ Book.authors bidirectional relationship,
    /// each reference stores the ID of its opposite.
    public var opposite: EUUID?

    /// Whether to resolve proxies for this reference.
    ///
    /// When `true`, proxy objects are resolved to their actual instances when
    /// accessed. This enables lazy loading across resource boundaries.
    public var resolveProxies: Bool

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a new reference.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - name: The name of the reference.
    ///   - eType: The class of objects this reference points to.
    ///   - lowerBound: Minimum multiplicity (default: 0).
    ///   - upperBound: Maximum multiplicity (default: 1, use -1 for unbounded).
    ///   - changeable: Whether the reference can be modified (default: true).
    ///   - volatile: Whether the reference is computed (default: false).
    ///   - transient: Whether the reference is persisted (default: false).
    ///   - containment: Whether this is a containment reference (default: false).
    ///   - opposite: ID of the opposite reference for bidirectional relationships (optional).
    ///   - resolveProxies: Whether to resolve proxy objects (default: true).
    ///   - eAnnotations: Annotations (empty by default).
    public init(
        id: EUUID = EUUID(),
        name: String,
        eType: any EClassifier,
        lowerBound: Int = 0,
        upperBound: Int = 1,
        changeable: Bool = true,
        volatile: Bool = false,
        transient: Bool = false,
        containment: Bool = false,
        opposite: EUUID? = nil,
        resolveProxies: Bool = true,
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.eClass = EReferenceClassifier()
        self.name = name
        self.eType = eType
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.changeable = changeable
        self.volatile = volatile
        self.transient = transient
        self.containment = containment
        self.opposite = opposite
        self.resolveProxies = resolveProxies
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
    }

    // MARK: - Computed Properties

    /// Whether this reference is multi-valued.
    ///
    /// Returns `true` if the upper bound is greater than 1 or unbounded (-1).
    public var isMany: Bool {
        return upperBound > 1 || upperBound == -1
    }

    /// Whether this reference is required.
    ///
    /// Returns `true` if the lower bound is at least 1.
    public var isRequired: Bool {
        return lowerBound >= 1
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

    /// Compares two references for equality.
    ///
    /// References are equal if they have the same identifier.
    ///
    /// - Parameters:
    ///   - lhs: The first reference to compare.
    ///   - rhs: The second reference to compare.
    /// - Returns: `true` if the references are equal, `false` otherwise.
    public static func == (lhs: EReference, rhs: EReference) -> Bool {
        return lhs.id == rhs.id
    }

    /// Hashes the essential components of this reference.
    ///
    /// Only the identifier is used for hashing to maintain consistency with equality.
    ///
    /// - Parameter hasher: The hasher to use for combining components.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Classifier Types

/// Metaclass for `EAttribute`.
///
/// Describes the structure of `EAttribute` itself within the metamodel hierarchy.
public struct EAttributeClassifier: EClassifier {
    /// Unique identifier for this metaclass.
    ///
    /// Each instance creates its own unique identifier.
    public let id: EUUID = EUUID()

    /// The name of this classifier.
    ///
    /// Always returns `"EAttribute"` to identify this as the metaclass for attributes.
    public var name: String { "EAttribute" }
}

/// Metaclass for `EReference`.
///
/// Describes the structure of `EReference` itself within the metamodel hierarchy.
public struct EReferenceClassifier: EClassifier {
    /// Unique identifier for this metaclass.
    ///
    /// Each instance creates its own unique identifier.
    public let id: EUUID = EUUID()

    /// The name of this classifier.
    ///
    /// Always returns `"EReference"` to identify this as the metaclass for references.
    public var name: String { "EReference" }
}

// MARK: - EStructuralFeature Type Resolution

/// Helper type for resolving EStructuralFeature types from DynamicEObject instances.
///
/// This type provides static methods for dispatching to the appropriate concrete
/// type initializer based on runtime type information.
public enum EStructuralFeatureResolver {
    /// Resolves the concrete EStructuralFeature type from a DynamicEObject.
    ///
    /// Dispatches to the appropriate concrete type initializer based on eClass.name.
    ///
    /// - Parameter object: The DynamicEObject to convert.
    /// - Returns: EAttribute or EReference instance.
    /// - Throws: XMIError if the object type is unsupported or initialization fails.
    public static func resolvingFeature(_ object: any EObject) throws -> any EStructuralFeature {
        guard let dynamicObj = object as? DynamicEObject else {
            throw XMIError.invalidObjectType("\(type(of: object))")
        }

        let eClass = dynamicObj.eClass
        let typeName = eClass.name

        switch typeName {
        case "EAttribute":
            guard let result = EAttribute(object: object) else {
                throw XMIError.missingRequiredAttribute(
                    "Failed to initialize EAttribute from object")
            }
            return result
        case "EReference":
            guard let result = EReference(object: object) else {
                throw XMIError.missingRequiredAttribute(
                    "Failed to initialize EReference from object")
            }
            return result
        default:
            throw XMIError.unsupportedFeature("Unsupported feature type: \(typeName)")
        }
    }
}

// MARK: - EAttribute Initializer

extension EAttribute {
    /// Initialise an EAttribute from a DynamicEObject.
    ///
    /// Extracts attribute metadata including type, multiplicity, and flags from a dynamic object.
    /// Uses a fallback EDataType when type information cannot be resolved.
    ///
    /// - Parameter object: The DynamicEObject representing an EAttribute.
    /// - Returns: A new EAttribute instance, or `nil` if the object is invalid or missing required attributes.
    public init?(object: any EObject) {
        guard let dynamicObj = object as? DynamicEObject,
            let name: String = dynamicObj.eGet("name") as? String
        else {
            return nil
        }

        let lowerBound: Int = dynamicObj.eGet("lowerBound") as? Int ?? 0
        let upperBound: Int = dynamicObj.eGet("upperBound") as? Int ?? 1
        let changeable: Bool = dynamicObj.eGet("changeable") as? Bool ?? true
        let volatile: Bool = dynamicObj.eGet("volatile") as? Bool ?? false
        let transient: Bool = dynamicObj.eGet("transient") as? Bool ?? false
        let isID: Bool = dynamicObj.eGet("iD") as? Bool ?? false
        let defaultValueLiteral: String? = dynamicObj.eGet("defaultValueLiteral") as? String

        // Resolve eType
        let eType: any EClassifier
        if dynamicObj.eGet("eType") as? any EObject != nil {
            eType = EDataType(name: "EString")  // Fallback for non-resource context
        } else {
            eType = EDataType(name: "EString")
        }

        // Call existing designated initializer
        self.init(
            name: name,
            eType: eType,
            lowerBound: lowerBound,
            upperBound: upperBound,
            changeable: changeable,
            volatile: volatile,
            transient: transient,
            defaultValueLiteral: defaultValueLiteral,
            isID: isID
        )
    }
}

// MARK: - EReference Initializer

extension EReference {
    /// Initialise an EReference from a DynamicEObject.
    ///
    /// Extracts reference metadata including type, multiplicity, containment, and flags from a dynamic object.
    /// Uses a fallback EClass when type information cannot be resolved.
    ///
    /// - Parameter object: The DynamicEObject representing an EReference.
    /// - Returns: A new EReference instance, or `nil` if the object is invalid or missing required attributes.
    public init?(object: any EObject) {
        guard let dynamicObj = object as? DynamicEObject,
            let name: String = dynamicObj.eGet("name") as? String
        else {
            return nil
        }

        let lowerBound: Int = dynamicObj.eGet("lowerBound") as? Int ?? 0
        let upperBound: Int = dynamicObj.eGet("upperBound") as? Int ?? 1
        let containment: Bool = dynamicObj.eGet("containment") as? Bool ?? false
        let changeable: Bool = dynamicObj.eGet("changeable") as? Bool ?? true
        let volatile: Bool = dynamicObj.eGet("volatile") as? Bool ?? false
        let transient: Bool = dynamicObj.eGet("transient") as? Bool ?? false
        let resolveProxies: Bool = dynamicObj.eGet("resolveProxies") as? Bool ?? true

        // Resolve eType
        let eType: any EClassifier
        if dynamicObj.eGet("eType") as? any EObject != nil {
            eType = EClass(name: "EObject")  // Fallback for non-resource context
        } else {
            eType = EClass(name: "EObject")
        }

        // eOpposite resolution deferred (TODO: two-pass conversion)
        let opposite: EUUID? = nil

        // Call existing designated initializer
        self.init(
            name: name,
            eType: eType,
            lowerBound: lowerBound,
            upperBound: upperBound,
            changeable: changeable,
            volatile: volatile,
            transient: transient,
            containment: containment,
            opposite: opposite,
            resolveProxies: resolveProxies
        )
    }
}
