//
// IModel.swift
// ECore
//
//  Created by Rene Hexel on 7/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation
import OrderedCollections

/// Protocol abstracting model access for transformation engines.
///
/// The `IModel` interface provides a framework-agnostic way to access and manipulate models,
/// similar to Eclipse ATL's IModel. This abstraction allows transformation engines to work
/// with different modelling frameworks whilst maintaining consistent semantics.
///
/// ## Design Principles
///
/// - **Framework Independence**: Abstract from specific ECore implementation details
/// - **Read/Write Control**: Clear separation between source (read-only) and target (writable) models
/// - **Type Safety**: Maintain Swift's type system whilst providing dynamic model access
/// - **Thread Safety**: All operations must be safe for concurrent access
///
/// ## Usage Example
///
/// ```swift
/// let sourceModel: IModel = EcoreModel(resource: sourceResource, isTarget: false)
/// let targetModel: IModel = EcoreModel(resource: targetResource, isTarget: true)
///
/// let elements = sourceModel.getElementsByType(personClass)
/// let newPerson = try targetModel.createElement(ofType: personClass)
/// ```
public protocol IModel: Sendable {
    /// The reference model (metamodel) for this model.
    var referenceModel: IReferenceModel { get }

    /// Creates a new element of the specified metatype.
    ///
    /// - Parameter metaElement: The EClass defining the type of element to create
    /// - Returns: A newly created EObject instance
    /// - Throws: `ECoreExecutionError` if creation fails or model is read-only
    func createElement(ofType metaElement: EClass) throws -> any EObject

    /// Returns all elements matching the given type.
    ///
    /// This method performs type-based querying across the entire model,
    /// returning both direct instances and instances of subtypes.
    ///
    /// - Parameter metaElement: The EClass to match against
    /// - Returns: An ordered set of all matching element IDs
    func getElementsByType(_ metaElement: EClass) async -> OrderedSet<EUUID>

    /// Indicates if this model allows modifications.
    ///
    /// Source models are typically read-only (`false`), whilst target models
    /// allow creation and modification (`true`).
    var isTarget: Bool { get set }

    /// The underlying resource containing the model elements.
    var resource: Resource { get }

    /// Checks if an object belongs to this model.
    ///
    /// - Parameter object: The EObject to test for membership
    /// - Returns: `true` if the object is contained in this model's resource
    func isModelOf(_ object: any EObject) async -> Bool
}

/// Protocol for reference models (metamodels).
///
/// Reference models represent metamodels and provide access to type definitions
/// and structural information required for model manipulation.
public protocol IReferenceModel: IModel {
    /// The root package of this metamodel.
    var rootPackage: EPackage { get }

    /// Find a classifier by name.
    ///
    /// - Parameter name: The name of the classifier to find
    /// - Returns: The matching EClassifier, or `nil` if not found
    func getClassifier(_ name: String) -> (any EClassifier)?

    /// Find all classifiers matching a name pattern.
    ///
    /// - Parameter pattern: A pattern to match against classifier names
    /// - Returns: Array of matching classifiers
    func getClassifiers(matching pattern: String) -> [any EClassifier]
}

/// Default implementation wrapping Resource.
///
/// This implementation provides the standard ECore model abstraction,
/// delegating operations to the underlying Resource whilst maintaining
/// the IModel contract.
public struct EcoreModel: IModel, Sendable, Equatable, Hashable {
    public let resource: Resource
    public let referenceModel: IReferenceModel
    public var isTarget: Bool

    /// Creates a new EcoreModel wrapping the given resource.
    ///
    /// - Parameters:
    ///   - resource: The Resource to wrap
    ///   - referenceModel: The metamodel for this model
    ///   - isTarget: Whether this model allows modifications
    public init(resource: Resource, referenceModel: IReferenceModel, isTarget: Bool = false) {
        self.resource = resource
        self.referenceModel = referenceModel
        self.isTarget = isTarget
    }

    public func createElement(ofType metaElement: EClass) throws -> any EObject {
        guard isTarget else {
            throw ECoreExecutionError.readOnlyModel
        }
        return DynamicEObject(eClass: metaElement)
    }

    public func getElementsByType(_ metaElement: EClass) async -> OrderedSet<EUUID> {
        let allObjects = await resource.getAllObjects()
        return OrderedSet(
            allObjects.compactMap { obj in
                guard let objClass = obj.eClass as? EClass else { return nil }
                return objClass == metaElement || objClass.allSuperTypes.contains(metaElement)
                    ? obj.id : nil
            })
    }

    public func isModelOf(_ object: any EObject) async -> Bool {
        return await resource.contains(id: object.id)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(resource.uri)
        hasher.combine(isTarget)
    }

    public static func == (lhs: EcoreModel, rhs: EcoreModel) -> Bool {
        return lhs.resource.uri == rhs.resource.uri && lhs.isTarget == rhs.isTarget
    }
}

/// Reference model implementation for EPackages.
///
/// Represents a metamodel as a reference model within the execution framework.
/// Reference models define the structure and types available for instance models
/// but do not themselves contain instance data. They serve as the schema or
/// metamodel definition that instance models conform to.
///
/// ## Usage
///
/// ```swift
/// let package = EPackage(name: "company", nsURI: "http://company/1.0", nsPrefix: "comp")
/// let resource = Resource()
/// let referenceModel = EcoreReferenceModel(rootPackage: package, resource: resource)
///
/// // Use in execution engine
/// let instanceModel = EcoreModel(resource: instanceResource, referenceModel: referenceModel)
/// ```
///
/// ## Thread Safety
///
/// This struct is `Sendable` and safe to use across concurrent contexts.
public struct EcoreReferenceModel: IReferenceModel, Sendable, Equatable, Hashable {
    /// The root package defining the metamodel structure.
    ///
    /// Contains all the classifiers (EClass, EEnum, EDataType) and their relationships
    /// that define the metamodel. This package serves as the authoritative source
    /// for type definitions within this reference model.
    public let rootPackage: EPackage

    /// The resource containing the metamodel definition.
    ///
    /// Provides storage and management for the metamodel objects. While the resource
    /// contains the metamodel objects, this reference model provides the execution
    /// framework interface to access and query those definitions.
    public let resource: Resource

    /// Indicates whether this model allows modifications.
    ///
    /// Reference models are typically read-only as they define the schema structure.
    /// Instance creation attempts on reference models will throw `ECoreExecutionError.readOnlyModel`.
    public var isTarget: Bool = false

    /// Initialises a new reference model with the specified root package and resource.
    ///
    /// - Parameters:
    ///   - rootPackage: The root package defining the metamodel structure
    ///   - resource: The resource containing the metamodel definition
    public init(rootPackage: EPackage, resource: Resource) {
        self.rootPackage = rootPackage
        self.resource = resource
    }
}

extension EcoreReferenceModel {
    /// Returns this reference model as an IReferenceModel.
    ///
    /// - Returns: Self-reference conforming to IReferenceModel protocol
    public var referenceModel: IReferenceModel { self }

    /// Attempts to create an element of the specified type.
    ///
    /// Reference models are read-only and do not support element creation.
    /// This method will always throw an error to maintain metamodel integrity.
    ///
    /// - Parameter metaElement: The EClass defining the type of element to create
    /// - Throws: `ECoreExecutionError.readOnlyModel` always, as reference models are immutable
    /// - Returns: Never returns successfully
    public func createElement(ofType metaElement: EClass) throws -> any EObject {
        throw ECoreExecutionError.readOnlyModel
    }

    /// Retrieves all elements of the specified type.
    ///
    /// Reference models contain metamodel definitions, not instance data.
    /// This method returns an empty set as metamodels do not contain instances.
    ///
    /// - Parameter metaElement: The EClass to search for instances of
    /// - Returns: Empty ordered set, as metamodels contain no instance data
    public func getElementsByType(_ metaElement: EClass) async -> OrderedSet<EUUID> {
        return []  // Metamodels don't contain instance data
    }

    /// Determines if the specified object belongs to this model.
    ///
    /// Reference models contain metamodel definitions, not instance data.
    /// This method returns false as no instances belong to a reference model.
    ///
    /// - Parameter object: The object to check ownership of
    /// - Returns: Always false, as reference models contain no instance data
    public func isModelOf(_ object: any EObject) async -> Bool {
        return false  // Metamodels don't contain instance data
    }

    /// Finds a classifier by name within the root package.
    ///
    /// Searches the root package's classifiers for one with the specified name.
    /// This provides access to EClass, EEnum, and EDataType definitions within
    /// the metamodel.
    ///
    /// - Parameter name: The name of the classifier to find
    /// - Returns: The matching classifier, or `nil` if not found
    public func getClassifier(_ name: String) -> (any EClassifier)? {
        return rootPackage.getClassifier(name)
    }

    /// Finds all classifiers matching a name pattern.
    ///
    /// Searches through all classifiers in the root package and returns those
    /// whose names contain the specified pattern. Useful for discovering
    /// related types or performing pattern-based queries.
    ///
    /// - Parameter pattern: A pattern to match against classifier names
    /// - Returns: Array of classifiers with names containing the pattern
    public func getClassifiers(matching pattern: String) -> [any EClassifier] {
        return rootPackage.eClassifiers.filter { classifier in
            classifier.name.contains(pattern)
        }
    }

    /// Combines the reference model's identifying properties into a hash value.
    ///
    /// Uses the root package's name and namespace URI to create a unique hash
    /// value for this reference model.
    ///
    /// - Parameter hasher: The hasher to combine values into
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rootPackage.name)
        hasher.combine(rootPackage.nsURI)
    }

    /// Compares two reference models for equality.
    ///
    /// Reference models are considered equal if their root packages have the
    /// same namespace URI, as this uniquely identifies the metamodel.
    ///
    /// - Parameters:
    ///   - lhs: The first reference model to compare
    ///   - rhs: The second reference model to compare
    /// - Returns: `true` if the reference models represent the same metamodel
    public static func == (lhs: EcoreReferenceModel, rhs: EcoreReferenceModel) -> Bool {
        return lhs.rootPackage.nsURI == rhs.rootPackage.nsURI
    }
}

/// Lightweight wrapper providing `IModel` conformance for a `Resource`.
///
/// This wrapper enables `Resource` instances to be registered directly with
/// the execution engine for UUID resolution and model navigation without
/// requiring a separate metamodel reference model. It is primarily used
/// for model-to-text transformations where read-only access suffices.
public struct ResourceModelWrapper: IModel, Sendable {
    /// The underlying resource containing the model objects.
    public let resource: Resource

    /// Indicates whether this model allows modifications (always `false`).
    public var isTarget: Bool = false

    /// The reference model for this wrapper.
    ///
    /// Returns a minimal reference model with an empty package, as the
    /// wrapper is intended for navigation and querying only.
    public var referenceModel: IReferenceModel {
        EcoreReferenceModel(
            rootPackage: EPackage(name: "dynamic", nsURI: "dynamic", nsPrefix: "dyn"),
            resource: resource
        )
    }

    /// Creates a new resource model wrapper.
    ///
    /// - Parameter resource: The resource to wrap.
    public init(resource: Resource) {
        self.resource = resource
    }

    /// Attempting to create elements throws a read-only error.
    ///
    /// - Parameter metaElement: The EClass defining the type of element to create.
    /// - Throws: `ECoreExecutionError.readOnlyModel` always.
    public func createElement(ofType metaElement: EClass) throws -> any EObject {
        throw ECoreExecutionError.readOnlyModel
    }

    /// Returns all elements matching the given type.
    ///
    /// - Parameter metaElement: The EClass to match against.
    /// - Returns: An ordered set of matching element IDs.
    public func getElementsByType(_ metaElement: EClass) async -> OrderedSet<EUUID> {
        let allObjects = await resource.getAllObjects()
        return OrderedSet(
            allObjects.compactMap { obj in
                guard let objClass = obj.eClass as? EClass else { return nil }
                return objClass == metaElement || objClass.allSuperTypes.contains(metaElement)
                    ? obj.id : nil
            })
    }

    /// Checks if an object belongs to this model.
    ///
    /// - Parameter object: The EObject to test for membership.
    /// - Returns: `true` if the object is contained in this model's resource.
    public func isModelOf(_ object: any EObject) async -> Bool {
        return await resource.contains(id: object.id)
    }
}
