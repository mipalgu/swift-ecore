//
// Resource.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

/// A resource manages model objects and provides EMF-compliant reference resolution.
///
/// Resources serve as containers for model objects, providing identity-based storage
/// and resolution capabilities. They enable cross-reference resolution, URI-based
/// addressing, and proper object lifecycle management following EMF patterns.
///
/// ## Thread Safety
///
/// Resources are thread-safe actors that manage concurrent access to model objects
/// and provide atomic reference resolution operations.
///
/// ## Example
///
/// ```swift
/// let resource = Resource(uri: "http://example.com/mymodel")
/// 
/// // Add objects to resource
/// let person = DynamicEObject(eClass: personClass)
/// resource.add(person)
/// 
/// // Resolve references by ID
/// if let resolved = resource.resolve(person.id) {
///     print("Found object: \(resolved)")
/// }
/// ```
@globalActor
public actor Resource {
    /// Global resource actor for thread-safe operations.
    public static let shared = Resource()
    
    /// The URI identifying this resource.
    ///
    /// Resources are identified by URIs following EMF conventions. The URI
    /// typically indicates the location or logical name of the resource.
    nonisolated public let uri: String
    
    /// Objects contained in this resource, indexed by their unique identifier.
    ///
    /// All objects within a resource must have unique identifiers. The resource
    /// maintains ownership and provides resolution services.
    private var objects: [EUUID: any EObject]
    
    /// Root objects that are not contained by other objects in this resource.
    ///
    /// Root objects serve as entry points for model traversal and are typically
    /// the top-level objects that contain the entire model hierarchy.
    private var rootObjects: Set<EUUID>
    
    /// The resource set that owns this resource, if any.
    ///
    /// Resources can be managed independently or as part of a resource set
    /// for cross-resource reference resolution.
    public weak var resourceSet: ResourceSet?
    
    /// Initialises a new resource with the specified URI.
    ///
    /// - Parameter uri: The URI identifying this resource. Defaults to a generated URI.
    public init(uri: String = "resource://\(UUID().uuidString)") {
        self.uri = uri
        self.objects = [:]
        self.rootObjects = Set()
    }
    
    // MARK: - Object Management
    
    /// Adds an object to this resource.
    ///
    /// The object becomes owned by this resource and can be resolved by its identifier.
    /// If the object is not contained by another object, it becomes a root object.
    ///
    /// - Parameter object: The object to add to this resource.
    /// - Returns: `true` if the object was added, `false` if it already exists.
    @discardableResult
    public func add(_ object: any EObject) -> Bool {
        guard objects[object.id] == nil else { return false }
        
        objects[object.id] = object
        
        // Check if this is a root object (not contained by another)
        let isContained = objects.values.contains { container in
            // Check if any object contains this one through containment references
            if let eClass = container.eClass as? EClass {
                return eClass.allReferences.contains { reference in
                    reference.containment && doesObjectContain(container, objectId: object.id, through: reference)
                }
            }
            return false
        }
        
        if !isContained {
            rootObjects.insert(object.id)
        }
        
        return true
    }
    
    /// Removes an object from this resource.
    ///
    /// - Parameter object: The object to remove from this resource.
    /// - Returns: `true` if the object was removed, `false` if it wasn't found.
    @discardableResult
    public func remove(_ object: any EObject) -> Bool {
        return remove(id: object.id)
    }
    
    /// Removes an object from this resource by its identifier.
    ///
    /// - Parameter id: The identifier of the object to remove.
    /// - Returns: `true` if the object was removed, `false` if it wasn't found.
    @discardableResult
    public func remove(id: EUUID) -> Bool {
        guard objects.removeValue(forKey: id) != nil else { return false }
        rootObjects.remove(id)
        return true
    }
    
    /// Removes all objects from this resource.
    public func clear() {
        objects.removeAll()
        rootObjects.removeAll()
    }
    
    // MARK: - Object Resolution
    
    /// Resolves an object by its identifier.
    ///
    /// - Parameter id: The unique identifier of the object to resolve.
    /// - Returns: The resolved object, or `nil` if not found in this resource.
    public func resolve(_ id: EUUID) -> (any EObject)? {
        return objects[id]
    }
    
    /// Resolves an object by its identifier with a specific type.
    ///
    /// - Parameters:
    ///   - id: The unique identifier of the object to resolve.
    ///   - type: The expected type of the resolved object.
    /// - Returns: The resolved object cast to the specified type, or `nil` if not found or wrong type.
    public func resolve<T: EObject>(_ id: EUUID, as type: T.Type) -> T? {
        return objects[id] as? T
    }
    
    /// Gets all objects contained in this resource.
    ///
    /// - Returns: An array of all objects in this resource.
    public func getAllObjects() -> [any EObject] {
        return Array(objects.values)
    }
    
    /// Gets all root objects in this resource.
    ///
    /// Root objects are those that are not contained by other objects
    /// within the same resource.
    ///
    /// - Returns: An array of root objects.
    public func getRootObjects() -> [any EObject] {
        return rootObjects.compactMap { objects[$0] }
    }
    
    /// Gets the number of objects in this resource.
    ///
    /// - Returns: The count of objects contained in this resource.
    public func count() -> Int {
        return objects.count
    }
    
    /// Checks if this resource contains an object with the specified identifier.
    ///
    /// - Parameter id: The identifier to check for.
    /// - Returns: `true` if an object with the identifier exists, `false` otherwise.
    public func contains(id: EUUID) -> Bool {
        return objects[id] != nil
    }
    
    // MARK: - Reference Resolution
    
    /// Resolves the opposite reference for a bidirectional reference.
    ///
    /// In EMF, bidirectional references maintain opposites automatically.
    /// This method resolves the opposite reference through ID-based lookup.
    ///
    /// - Parameter reference: The reference whose opposite should be resolved.
    /// - Returns: The opposite reference, or `nil` if not found.
    public func resolveOpposite(_ reference: EReference) -> EReference? {
        guard let oppositeId = reference.opposite else { return nil }
        
        // Search through all objects to find the reference with the matching ID
        for object in objects.values {
            if let eClass = object.eClass as? EClass {
                for feature in eClass.allReferences {
                    if feature.id == oppositeId {
                        return feature
                    }
                }
            }
        }
        
        // Check in resource set if this resource is part of one
        // Note: Cross-resource resolution requires async context in ResourceSet
        // Cross-resource resolution would need async context
        return nil
    }
    
    /// Resolves a reference to its target objects.
    ///
    /// For single-valued references, returns an array with one element.
    /// For multi-valued references, returns all referenced objects.
    ///
    /// - Parameters:
    ///   - reference: The reference to resolve.
    ///   - from: The object containing the reference.
    /// - Returns: An array of resolved target objects.
    public func resolveReference(_ reference: EReference, from object: any EObject) -> [any EObject] {
        guard let value = object.eGet(reference) else { return [] }
        
        if reference.isMany {
            // Multi-valued reference - extract IDs from array
            // Try casting to array of EUUIDs directly, or convert from Any array
            if let ids = value as? [EUUID] {
                return ids.compactMap { resolve($0) }
            } else if let anyArray = value as? [Any] {
                let ids = anyArray.compactMap { $0 as? EUUID }
                return ids.compactMap { resolve($0) }
            }
        } else {
            // Single-valued reference - direct ID
            if let id = value as? EUUID {
                return resolve(id).map { [$0] } ?? []
            }
        }
        
        return []
    }
    
    // MARK: - URI Resolution
    
    /// Resolves an object by its URI path within this resource.
    ///
    /// EMF uses URI paths to identify objects within resources, typically
    /// following XPath-like syntax for model navigation.
    ///
    /// - Parameter path: The URI path to resolve (e.g., "/@contents.0/@departments.1").
    /// - Returns: The resolved object, or `nil` if the path is invalid.
    public func resolveByPath(_ path: String) -> (any EObject)? {
        // Simple path resolution - starts with root objects
        guard path.hasPrefix("/") else { return nil }
        
        let components = path.dropFirst().split(separator: "/")
        
        // If path is just "/", return the first root object
        if components.isEmpty {
            let roots = getRootObjects()
            return roots.first
        }
        
        // For now, implement basic @contents.index resolution
        // More sophisticated path resolution would parse XPath expressions
        if components[0].hasPrefix("@contents.") {
            let indexStr = String(components[0].dropFirst("@contents.".count))
            guard let index = Int(indexStr) else { return nil }
            
            let roots = getRootObjects()
            guard index < roots.count else { return nil }
            
            return roots[index]
        }
        
        return nil
    }
    
    // MARK: - Private Helpers
    
    /// Checks if a container object contains a target object through a specific reference.
    ///
    /// - Parameters:
    ///   - container: The potential container object.
    ///   - objectId: The ID of the object to check for containment.
    ///   - reference: The containment reference to check.
    /// - Returns: `true` if the container contains the target object.
    private func doesObjectContain(_ container: any EObject, objectId: EUUID, through reference: EReference) -> Bool {
        guard reference.containment else { return false }
        
        if let value = container.eGet(reference) {
            if reference.isMany {
                if let ids = value as? [EUUID] {
                    return ids.contains(objectId)
                } else if let anyArray = value as? [Any] {
                    let ids = anyArray.compactMap { $0 as? EUUID }
                    return ids.contains(objectId)
                }
            } else {
                if let id = value as? EUUID {
                    return id == objectId
                }
            }
        }
        
        return false
    }
}

// MARK: - CustomStringConvertible

extension Resource: CustomStringConvertible {
    /// A textual representation of this resource.
    nonisolated public var description: String {
        return "Resource(uri: \"\(uri)\")"
    }
}

// MARK: - Equatable

extension Resource: Equatable {
    /// Compares two resources for equality based on their URI.
    ///
    /// - Parameters:
    ///   - lhs: The first resource to compare.
    ///   - rhs: The second resource to compare.
    /// - Returns: `true` if the resources have the same URI, `false` otherwise.
    nonisolated public static func == (lhs: Resource, rhs: Resource) -> Bool {
        return lhs.uri == rhs.uri
    }
}

// MARK: - Hashable

extension Resource: Hashable {
    /// Hashes the resource based on its URI.
    ///
    /// - Parameter hasher: The hasher to use for combining hash values.
    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(uri)
    }
}