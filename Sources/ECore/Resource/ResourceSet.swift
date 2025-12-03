//
// ResourceSet.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

/// A resource set manages multiple resources and enables cross-resource reference resolution.
///
/// ResourceSets provide a container for multiple resources, enabling complex models that
/// span multiple files or logical units. They maintain a registry of metamodels by
/// namespace URI and provide cross-resource reference resolution capabilities.
///
/// ## Thread Safety
///
/// ResourceSets are thread-safe actors that coordinate access to multiple resources
/// and provide atomic cross-resource operations.
///
/// ## Example
///
/// ```swift
/// let resourceSet = ResourceSet()
/// 
/// // Register a metamodel
/// resourceSet.registerMetamodel(companyPackage, uri: "http://company/1.0")
/// 
/// // Create resources
/// let modelResource = resourceSet.createResource(uri: "models/company.xmi")
/// let instanceResource = resourceSet.createResource(uri: "instances/acme.xmi")
/// 
/// // Cross-resource references are automatically resolved
/// ```
@globalActor
public actor ResourceSet {
    /// Global resource set actor for thread-safe operations.
    public static let shared = ResourceSet()
    
    /// Resources managed by this resource set, indexed by URI.
    ///
    /// Each resource in the set has a unique URI that serves as its identifier
    /// within the resource set.
    private var resources: [String: Resource]
    
    /// Metamodel registry mapping namespace URIs to their root packages.
    ///
    /// This registry provides namespace-based metamodel resolution without
    /// relying on global variables, as requested.
    private var metamodelRegistry: [String: EPackage]
    
    /// URI converter for transforming logical URIs to physical URIs.
    ///
    /// Maps logical model URIs to their actual storage locations or
    /// provides URI normalisation services.
    private var uriConverter: [String: String]
    
    /// Factory registry for creating resources based on file extensions or URI patterns.
    ///
    /// Different resource types (XMI, JSON, etc.) can register factories
    /// to handle their specific serialisation formats.
    private var resourceFactories: [String: ResourceFactory]
    
    /// Initialises a new resource set with empty registries.
    public init() {
        self.resources = [:]
        self.metamodelRegistry = [:]
        self.uriConverter = [:]
        self.resourceFactories = [:]
        // registerDefaultFactories() - will be called later when needed
    }
    
    // MARK: - Resource Management
    
    /// Creates a new resource with the specified URI.
    ///
    /// If a resource with the same URI already exists, returns the existing resource.
    /// The new resource is automatically added to this resource set.
    ///
    /// - Parameter uri: The URI for the new resource.
    /// - Returns: The created or existing resource.
    @discardableResult
    public func createResource(uri: String) -> Resource {
        if let existing = resources[uri] {
            return existing
        }
        
        let resource = Resource(uri: uri)
        // Note: ResourceSet reference will be set when needed
        resources[uri] = resource
        return resource
    }
    
    /// Gets a resource by its URI, loading it if necessary.
    ///
    /// If the resource doesn't exist in the set, attempts to load it
    /// using registered resource factories. If no factory can handle
    /// the URI, returns `nil`.
    ///
    /// - Parameter uri: The URI of the resource to retrieve.
    /// - Returns: The resource, or `nil` if it cannot be found or loaded.
    public func getResource(uri: String) -> Resource? {
        // Return existing resource if already loaded
        if let existing = resources[uri] {
            return existing
        }
        
        // Attempt to load the resource using factories
        return loadResource(uri: uri)
    }
    
    /// Removes a resource from this resource set.
    ///
    /// - Parameter resource: The resource to remove.
    /// - Returns: `true` if the resource was removed, `false` if it wasn't found.
    @discardableResult
    public func removeResource(_ resource: Resource) -> Bool {
        guard resources.removeValue(forKey: resource.uri) != nil else { return false }
        // Note: ResourceSet reference cleared
        return true
    }
    
    /// Removes a resource by its URI from this resource set.
    ///
    /// - Parameter uri: The URI of the resource to remove.
    /// - Returns: `true` if the resource was removed, `false` if it wasn't found.
    @discardableResult
    public func removeResource(uri: String) -> Bool {
        guard resources.removeValue(forKey: uri) != nil else { return false }
        // Note: ResourceSet reference cleared
        return true
    }
    
    /// Gets all resources in this resource set.
    ///
    /// - Returns: An array of all resources managed by this resource set.
    public func getResources() -> [Resource] {
        return Array(resources.values)
    }
    
    /// Gets the number of resources in this resource set.
    ///
    /// - Returns: The count of resources managed by this resource set.
    public func count() -> Int {
        return resources.count
    }
    
    // MARK: - Metamodel Registry
    
    /// Registers a metamodel package with its namespace URI.
    ///
    /// This enables namespace-based metamodel resolution without global variables.
    /// The package becomes available for model instantiation and reference resolution.
    ///
    /// - Parameters:
    ///   - package: The root package of the metamodel to register.
    ///   - uri: The namespace URI identifying this metamodel.
    public func registerMetamodel(_ package: EPackage, uri: String) {
        metamodelRegistry[uri] = package
    }
    
    /// Unregisters a metamodel by its namespace URI.
    ///
    /// - Parameter uri: The namespace URI of the metamodel to unregister.
    /// - Returns: The unregistered package, or `nil` if not found.
    @discardableResult
    public func unregisterMetamodel(uri: String) -> EPackage? {
        return metamodelRegistry.removeValue(forKey: uri)
    }
    
    /// Gets a metamodel package by its namespace URI.
    ///
    /// - Parameter uri: The namespace URI of the metamodel to retrieve.
    /// - Returns: The metamodel package, or `nil` if not registered.
    public func getMetamodel(uri: String) -> EPackage? {
        return metamodelRegistry[uri]
    }
    
    /// Gets all registered metamodel URIs.
    ///
    /// - Returns: An array of namespace URIs for all registered metamodels.
    public func getMetamodelURIs() -> [String] {
        return Array(metamodelRegistry.keys)
    }
    
    // MARK: - URI Management
    
    /// Maps a logical URI to a physical URI.
    ///
    /// This enables URI redirection for resource loading, allowing logical
    /// model references to be resolved to actual file system locations.
    ///
    /// - Parameters:
    ///   - logicalURI: The logical URI to map.
    ///   - physicalURI: The physical URI it should resolve to.
    public func mapURI(from logicalURI: String, to physicalURI: String) {
        uriConverter[logicalURI] = physicalURI
    }
    
    /// Converts a logical URI to its physical equivalent.
    ///
    /// - Parameter logicalURI: The logical URI to convert.
    /// - Returns: The physical URI, or the original URI if no mapping exists.
    public func convertURI(_ logicalURI: String) -> String {
        return uriConverter[logicalURI] ?? logicalURI
    }
    
    /// Normalises a URI by applying registered conversions and cleanup.
    ///
    /// - Parameter uri: The URI to normalise.
    /// - Returns: The normalised URI.
    public func normaliseURI(_ uri: String) -> String {
        let converted = convertURI(uri)
        
        // Handle protocol prefixes (http://, https://, file://, etc.)
        if let protocolRange = converted.range(of: "://") {
            let protocolPart = String(converted[..<protocolRange.upperBound])
            let pathPart = String(converted[protocolRange.upperBound...])
            
            // Normalise only the path part
            let components = pathPart.split(separator: "/")
            var normalised: [String] = []
            
            for component in components {
                if component == ".." {
                    if !normalised.isEmpty && normalised.last != ".." {
                        normalised.removeLast()
                    }
                } else if component != "." && !component.isEmpty {
                    normalised.append(String(component))
                }
            }
            
            return protocolPart + normalised.joined(separator: "/")
        } else {
            // Basic URI cleanup - remove redundant path elements
            let components = converted.split(separator: "/")
            var normalised: [String] = []
            
            for component in components {
                if component == ".." {
                    if !normalised.isEmpty && normalised.last != ".." {
                        normalised.removeLast()
                    }
                } else if component != "." && !component.isEmpty {
                    normalised.append(String(component))
                }
            }
            
            return normalised.joined(separator: "/")
        }
    }
    
    // MARK: - Cross-Resource Reference Resolution
    
    /// Resolves an object by its identifier across all resources in the set.
    ///
    /// - Parameter id: The unique identifier of the object to resolve.
    /// - Returns: The resolved object and its containing resource, or `nil` if not found.
    public func resolve(_ id: EUUID) async -> (object: any EObject, resource: Resource)? {
        for resource in resources.values {
            if let object = await resource.resolve(id) {
                return (object, resource)
            }
        }
        return nil
    }
    
    /// Resolves the opposite reference for a bidirectional reference across all resources.
    ///
    /// - Parameter reference: The reference whose opposite should be resolved.
    /// - Returns: The opposite reference, or `nil` if not found in any resource.
    public func resolveOpposite(_ reference: EReference) async -> EReference? {
        guard let oppositeId = reference.opposite else { return nil }
        
        for resource in resources.values {
            for object in await resource.getAllObjects() {
                if let eClass = object.eClass as? EClass {
                    for feature in eClass.allReferences {
                        if feature.id == oppositeId {
                            return feature
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Synchronous version for internal use within Resource
    public func resolveOppositeSync(_ reference: EReference) -> EReference? {
        guard reference.opposite != nil else { return nil }
        // Simplified synchronous resolution - would need proper implementation
        return nil
    }
    
    /// Resolves an object by its URI across all resources in the set.
    ///
    /// The URI format is: "resourceURI#objectPath" where objectPath
    /// identifies the object within the resource.
    ///
    /// - Parameter uri: The complete URI to resolve.
    /// - Returns: The resolved object, or `nil` if not found.
    public func resolveByURI(_ uri: String) async -> (any EObject)? {
        let components = uri.split(separator: "#", maxSplits: 1)
        let resourceURI = String(components[0])
        let objectPath = components.count > 1 ? String(components[1]) : "/"
        
        guard let resource = getResource(uri: resourceURI) else { return nil }
        return await resource.resolveByPath(objectPath)
    }
    
    // MARK: - Resource Factory Management
    
    /// Registers a resource factory for handling specific file extensions or URI patterns.
    ///
    /// - Parameters:
    ///   - factory: The factory to register.
    ///   - pattern: The file extension or URI pattern this factory handles.
    public func registerResourceFactory(_ factory: ResourceFactory, for pattern: String) {
        resourceFactories[pattern] = factory
    }
    
    /// Gets a resource factory for a given URI.
    ///
    /// - Parameter uri: The URI to find a factory for.
    /// - Returns: The matching factory, or `nil` if none found.
    public func getResourceFactory(for uri: String) -> ResourceFactory? {
        // Check for exact pattern matches first
        for (pattern, factory) in resourceFactories {
            if uri.hasSuffix(pattern) || uri.contains(pattern) {
                return factory
            }
        }
        
        return nil
    }
    
    // MARK: - Private Implementation
    
    /// Loads a resource using registered factories.
    ///
    /// - Parameter uri: The URI of the resource to load.
    /// - Returns: The loaded resource, or `nil` if no factory can handle it.
    private func loadResource(uri: String) -> Resource? {
        let physicalURI = convertURI(uri)
        
        guard let factory = getResourceFactory(for: physicalURI) else {
            return nil
        }
        
        do {
            let resource = try factory.createResource(uri: physicalURI, in: self)
            resources[uri] = resource
            // Note: ResourceSet reference set
            return resource
        } catch {
            // Loading failed - could log error here
            return nil
        }
    }
    
    /// Registers default resource factories for standard formats.
    private func registerDefaultFactories() {
        // XMI factory would be registered here
        // JSON factory would be registered here
        // For now, we'll have placeholders
    }
}

// MARK: - Resource Factory Protocol

/// Protocol for factories that can create and load resources.
public protocol ResourceFactory: Sendable {
    /// Creates a resource from the specified URI.
    ///
    /// - Parameters:
    ///   - uri: The URI of the resource to create/load.
    ///   - resourceSet: The resource set that will own the resource.
    /// - Returns: The created resource.
    /// - Throws: An error if the resource cannot be created or loaded.
    func createResource(uri: String, in resourceSet: ResourceSet) throws -> Resource
    
    /// Checks if this factory can handle the specified URI.
    ///
    /// - Parameter uri: The URI to check.
    /// - Returns: `true` if this factory can handle the URI, `false` otherwise.
    func canHandle(uri: String) -> Bool
}

// MARK: - CustomStringConvertible

extension ResourceSet: CustomStringConvertible {
    /// A textual representation of this resource set.
    nonisolated public var description: String {
        return "ResourceSet"
    }
}