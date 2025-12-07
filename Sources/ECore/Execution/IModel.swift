//
// IModel.swift
// ECore
//
// Created by Rene Hexel on 7/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

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
    /// - Returns: A set of all matching element IDs
    func getElementsByType(_ metaElement: EClass) async -> Set<EUUID>

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

    public func getElementsByType(_ metaElement: EClass) async -> Set<EUUID> {
        let allObjects = await resource.getAllObjects()
        return Set(allObjects.compactMap { obj in
            guard let objClass = obj.eClass as? EClass else { return nil }
            return objClass == metaElement || objClass.allSuperTypes.contains(metaElement) ? obj.id : nil
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
public struct EcoreReferenceModel: IReferenceModel, Sendable, Equatable, Hashable {
    public let rootPackage: EPackage
    public let resource: Resource
    public var isTarget: Bool = false

    public var referenceModel: IReferenceModel { self }

    public init(rootPackage: EPackage, resource: Resource) {
        self.rootPackage = rootPackage
        self.resource = resource
    }

    public func createElement(ofType metaElement: EClass) throws -> any EObject {
        throw ECoreExecutionError.readOnlyModel
    }

    public func getElementsByType(_ metaElement: EClass) async -> Set<EUUID> {
        return []  // Metamodels don't contain instance data
    }

    public func isModelOf(_ object: any EObject) async -> Bool {
        return false  // Metamodels don't contain instance data
    }

    public func getClassifier(_ name: String) -> (any EClassifier)? {
        return rootPackage.getClassifier(name)
    }

    public func getClassifiers(matching pattern: String) -> [any EClassifier] {
        return rootPackage.eClassifiers.filter { classifier in
            classifier.name.contains(pattern)
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rootPackage.name)
        hasher.combine(rootPackage.nsURI)
    }

    public static func == (lhs: EcoreReferenceModel, rhs: EcoreReferenceModel) -> Bool {
        return lhs.rootPackage.nsURI == rhs.rootPackage.nsURI
    }
}
