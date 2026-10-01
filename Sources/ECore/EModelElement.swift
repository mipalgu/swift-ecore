//
// EModelElement.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation
public import OrderedCollections

// MARK: - EAnnotation

/// A reference held by an annotation to a model element.
///
/// An annotation's `references` are the model elements that the annotation concerns. An
/// element of the same document is identified by its identifier; an element of another
/// document is identified by a ``ResourceProxy`` that names the document and the fragment.
public enum EAnnotationReference: Sendable, Hashable {
    /// An element of the document that holds the annotation.
    case local(EUUID)

    /// An element of another document.
    case external(ResourceProxy)

    /// The reference as a reflective value: an identifier or a proxy.
    public var value: any EcoreValue {
        switch self {
        case .local(let identifier): return identifier
        case .external(let proxy): return proxy
        }
    }

    /// Creates a reference from a reflective value.
    ///
    /// - Parameter value: An identifier or a ``ResourceProxy``.
    /// - Returns: The reference, or `nil` for any other kind of value.
    public init?(value: any EcoreValue) {
        switch value {
        case let identifier as EUUID: self = .local(identifier)
        case let proxy as ResourceProxy: self = .external(proxy)
        default: return nil
        }
    }
}

/// An annotation on a model element.
///
/// Annotations provide a mechanism to attach arbitrary metadata to model elements
/// without modifying the core metamodel. They are commonly used for:
///
/// - Documentation and comments
/// - Tool-specific metadata
/// - Generation hints
/// - Validation constraints
///
/// Each annotation has a source URI that identifies its purpose and key and value
/// details that hold the actual metadata. The details keep the order in which they were added
/// (the order of the document for a loaded annotation).
/// An annotation can also refer to other model elements (``references``), contain
/// arbitrary objects (``contents``), and carry annotations of its own (``eAnnotations``).
///
/// ## Example
///
/// ```swift
/// let docAnnotation = EAnnotation(
///     source: "http://www.eclipse.org/emf/2002/GenModel",
///     details: ["documentation": "This class represents a person"]
/// )
/// ```
public struct EAnnotation: EObject, EMetaObject, EModelElement {
    /// The metaclass of annotations is the `EAnnotation` class of ``EcorePackage``.
    public typealias Classifier = EClass

    /// Unique identifier for this annotation.
    ///
    /// Used for identity-based equality comparison.
    public let id: EUUID

    /// The metaclass describing this annotation.
    public var eClass: EClass { EcorePackage.metaClass(.eAnnotation) }

    /// The identifier of the model element that holds this annotation, if any.
    public internal(set) var eContainerID: EUUID?

    /// Internal storage for feature values that are not answered reflectively.
    private var storage = EObjectStorage()

    /// The source URI identifying the annotation's purpose.
    ///
    /// This URI typically identifies the tool or framework that created the annotation
    /// and interprets its details. Common examples are listed in ``AnnotationSource``.
    ///
    /// The source should be unique within the containing model element's annotations.
    public var source: String

    /// Key-value pairs of annotation details, in the order in which they were added.
    ///
    /// The details contain the actual metadata associated with this annotation.
    /// Keys and values are both strings, allowing flexible representation of various
    /// metadata types. Assigning to an existing key keeps its position.
    public var details: OrderedDictionary<String, String>

    /// The annotations that this annotation carries.
    public var eAnnotations: [EAnnotation] {
        didSet { ContainerStamp.stamp(&eAnnotations, container: id) }
    }

    /// The model elements that this annotation refers to, in order.
    public var references: [EAnnotationReference]

    /// The objects that this annotation contains, in order.
    public var contents: [any EObject]

    /// Creates a new annotation whose details keep the given order.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - source: The source URI identifying the annotation's purpose.
    ///   - orderedDetails: Key-value pairs of annotation metadata in the order in which they
    ///     are kept and written (empty by default).
    ///   - eAnnotations: Annotations carried by this annotation (none by default).
    ///   - references: Model elements that this annotation refers to (none by default).
    ///   - contents: Objects that this annotation contains (none by default).
    public init(
        id: EUUID = EUUID(),
        source: String,
        orderedDetails: OrderedDictionary<String, String> = [:],
        eAnnotations: [EAnnotation] = [],
        references: [EAnnotationReference] = [],
        contents: [any EObject] = []
    ) {
        self.id = id
        self.source = source
        self.details = orderedDetails
        self.eAnnotations = eAnnotations
        self.references = references
        self.contents = contents
        ContainerStamp.stamp(&self.eAnnotations, container: id)
    }

    /// Creates a new annotation from an unordered dictionary of details.
    ///
    /// A dictionary has no order of its own, so the details are kept in the order of their
    /// keys. Use ``init(id:source:orderedDetails:eAnnotations:references:contents:)`` to
    /// keep a particular order.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - source: The source URI identifying the annotation's purpose.
    ///   - details: Key-value pairs of annotation metadata.
    ///   - eAnnotations: Annotations carried by this annotation (none by default).
    ///   - references: Model elements that this annotation refers to (none by default).
    ///   - contents: Objects that this annotation contains (none by default).
    public init(
        id: EUUID = EUUID(),
        source: String,
        details: [String: String],
        eAnnotations: [EAnnotation] = [],
        references: [EAnnotationReference] = [],
        contents: [any EObject] = []
    ) {
        var ordered: OrderedDictionary<String, String> = [:]
        for key in details.keys.sorted() { ordered[key] = details[key] }
        self.init(
            id: id, source: source, orderedDetails: ordered, eAnnotations: eAnnotations,
            references: references, contents: contents)
    }

    /// The details of this annotation as metamodel objects.
    ///
    /// Each entry is an ``EStringToStringMapEntry`` whose identifier is derived from the
    /// annotation and the entry key, so repeated reads answer entries with the same identity.
    /// Entries are in the order of ``details``.
    public var detailEntries: [EStringToStringMapEntry] {
        details.map { key, value in
            EStringToStringMapEntry(
                id: ReflectiveValues.derivedID(from: id, key: key),
                key: key,
                value: value,
                eContainerID: id)
        }
    }

    // MARK: - EObject Protocol Implementation

    /// Reflectively retrieves the value of a feature.
    ///
    /// The features `source`, `details`, `eModelElement`, `contents`, and `references` of
    /// the `EAnnotation` metaclass are answered from the annotation itself.
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
    /// - Returns: `true` if the feature has been set; otherwise, `false`.
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

    /// Compares two annotations for equality.
    ///
    /// Annotations are equal if they have the same identifier, source, details (including
    /// their order), nested annotations, references, and contents.
    ///
    /// - Parameters:
    ///   - lhs: The first annotation to compare.
    ///   - rhs: The second annotation to compare.
    /// - Returns: `true` if the annotations are equal, `false` otherwise.
    public static func == (lhs: EAnnotation, rhs: EAnnotation) -> Bool {
        lhs.id == rhs.id && lhs.source == rhs.source && lhs.details == rhs.details
            && lhs.eAnnotations == rhs.eAnnotations && lhs.references == rhs.references
            && lhs.contents.map(\.id) == rhs.contents.map(\.id)
    }

    /// Hashes the essential components of this annotation.
    ///
    /// - Parameter hasher: The hasher to use for combining components.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(source)
        hasher.combine(details)
        hasher.combine(eAnnotations)
        hasher.combine(references)
        for object in contents { hasher.combine(object.id) }
    }
}

// MARK: - EModelElement

/// Base protocol for model elements that can have annotations.
///
/// `EModelElement` extends ``EObject`` to add support for attaching annotations,
/// making it the base for most metamodel elements including classes, attributes,
/// references, packages, and more.
///
/// Annotations allow metadata to be attached to model elements without modifying
/// the core metamodel structure, supporting use cases such as:
///
/// - Code generation directives
/// - Documentation strings
/// - Validation rules
/// - Tool-specific settings
///
/// ## Usage
///
/// ```swift
/// struct MyClass: EModelElement {
///     let id: EUUID
///     let eClass: MyClassifier
///     var eAnnotations: [EAnnotation] = []
///
///     mutating func addDocumentation(_ text: String) {
///         let annotation = EAnnotation(
///             source: "http://www.eclipse.org/emf/2002/GenModel",
///             details: ["documentation": text]
///         )
///         eAnnotations.append(annotation)
///     }
/// }
/// ```
public protocol EModelElement: EObject {
    /// Annotations attached to this model element.
    ///
    /// The array can contain multiple annotations, each identified by a unique source URI.
    /// Annotations are typically added during model construction or by tools processing the model.
    var eAnnotations: [EAnnotation] { get set }

    /// Retrieves an annotation by its source URI.
    ///
    /// This convenience method searches the ``eAnnotations`` array for an annotation
    /// with the specified source URI.
    ///
    /// - Parameter source: The source URI to search for.
    /// - Returns: The first annotation matching the source, or `nil` if not found.
    func getEAnnotation(source: String) -> EAnnotation?

    /// Retrieves the value of a detail of the annotation with the given source.
    ///
    /// - Parameters:
    ///   - source: The source URI of the annotation.
    ///   - key: The key of the detail.
    /// - Returns: The value of the detail, or `nil` if there is no such annotation or detail.
    func getEAnnotationDetail(source: String, key: String) -> String?
}

// Default implementation
extension EModelElement {
    /// Default implementation of annotation lookup.
    ///
    /// Searches linearly through ``eAnnotations`` for the first annotation
    /// matching the given source URI.
    ///
    /// - Parameter source: The source URI to search for.
    /// - Returns: The first matching annotation, or `nil` if not found.
    public func getEAnnotation(source: String) -> EAnnotation? {
        return eAnnotations.first { $0.source == source }
    }

    /// Default implementation of detail lookup.
    ///
    /// Looks the detail up in the first annotation matching the given source URI.
    ///
    /// - Parameters:
    ///   - source: The source URI of the annotation.
    ///   - key: The key of the detail.
    /// - Returns: The value of the detail, or `nil` if there is no such annotation or detail.
    public func getEAnnotationDetail(source: String, key: String) -> String? {
        getEAnnotation(source: source)?.details[key]
    }
}

// MARK: - ENamedElement

/// Base protocol for model elements that have a name.
///
/// `ENamedElement` extends ``EModelElement`` to add a name attribute,
/// making it the base for most metamodel constructs including:
///
/// - Classes and data types
/// - Attributes and references
/// - Packages and factories
/// - Operations and parameters
///
/// The name is used for identification within the model and typically must be
/// unique within its containing element (e.g., attribute names must be unique
/// within a class).
///
/// ## Usage
///
/// ```swift
/// struct MyAttribute: ENamedElement {
///     let id: EUUID
///     let eClass: MyClassifier
///     var name: String
///     var eAnnotations: [EAnnotation] = []
///
///     init(name: String) {
///         self.id = EUUID()
///         self.eClass = MyClassifier(name: "EAttribute")
///         self.name = name
///     }
/// }
/// ```
public protocol ENamedElement: EModelElement {
    /// The name of this element.
    ///
    /// The name should be a valid identifier and is typically unique within
    /// the containing element. For example:
    ///
    /// - Class names must be unique within their package
    /// - Attribute names must be unique within their class
    /// - Package names must be unique within their parent package
    var name: String { get set }
}

// MARK: - EStringToStringMapEntry

/// A key and value pair of an annotation's details.
///
/// Entries are the objects behind the `details` feature of an ``EAnnotation``. Each entry
/// is contained by its annotation and carries a string key and a string value.
public struct EStringToStringMapEntry: EObject, EMetaObject {
    /// The metaclass of map entries is the `EStringToStringMapEntry` class of ``EcorePackage``.
    public typealias Classifier = EClass

    /// Unique identifier for this entry.
    public let id: EUUID

    /// The metaclass describing this entry.
    public var eClass: EClass { EcorePackage.metaClass(.eStringToStringMapEntry) }

    /// The identifier of the annotation that holds this entry, if any.
    public internal(set) var eContainerID: EUUID?

    /// The key of this entry.
    public var key: String

    /// The value of this entry.
    public var value: String

    /// Creates a new entry.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - key: The key of the entry.
    ///   - value: The value of the entry.
    ///   - eContainerID: The identifier of the containing annotation, if any.
    public init(id: EUUID = EUUID(), key: String, value: String, eContainerID: EUUID? = nil) {
        self.id = id
        self.key = key
        self.value = value
        self.eContainerID = eContainerID
    }

    /// Entries contain no objects.
    public var eContents: [any EObject] { [] }

    /// Reflectively retrieves the value of the `key` or `value` feature.
    ///
    /// - Parameter feature: The structural feature whose value to retrieve.
    /// - Returns: The feature's current value, or `nil` for any other feature.
    public func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        switch EcorePackage.featureName(forID: feature.id) {
        case .key: return key
        case .value: return value
        default: return nil
        }
    }

    /// Reflectively sets the value of the `key` or `value` feature.
    ///
    /// - Parameters:
    ///   - feature: The structural feature to modify.
    ///   - value: The new string value; `nil` resets the feature to the empty string.
    public mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?) {
        let text = value as? String ?? ""
        switch EcorePackage.featureName(forID: feature.id) {
        case .key: key = text
        case .value: self.value = text
        default: break
        }
    }

    /// Checks whether the `key` or `value` feature holds a non-empty string.
    ///
    /// - Parameter feature: The structural feature to check.
    /// - Returns: `true` if the feature is set; otherwise, `false`.
    public func eIsSet(_ feature: some EStructuralFeature) -> Bool {
        switch EcorePackage.featureName(forID: feature.id) {
        case .key: return !key.isEmpty
        case .value: return !value.isEmpty
        default: return false
        }
    }

    /// Resets the `key` or `value` feature to the empty string.
    ///
    /// - Parameter feature: The structural feature to unset.
    public mutating func eUnset(_ feature: some EStructuralFeature) {
        eSet(feature, nil)
    }
}
