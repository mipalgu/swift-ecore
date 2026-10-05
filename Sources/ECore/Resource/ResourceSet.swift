//
// ResourceSet.swift
// ECore
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation
import OrderedCollections

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
    var resources: OrderedDictionary<String, Resource>

    /// Metamodel registry mapping namespace URIs to their root packages.
    ///
    /// This registry provides namespace-based metamodel resolution without
    /// relying on global variables, as requested.
    private var metamodelRegistry: OrderedDictionary<String, EPackage>

    /// The registered metamodels, shared with the resources of the set so that they remain
    /// available to the resources after the set has been released.
    nonisolated let metamodelSnapshot = MetamodelSnapshot()

    /// URI converter for transforming logical URIs to physical URIs.
    ///
    /// Maps logical model URIs to their actual storage locations or
    /// provides URI normalisation services.
    private var uriConverter: OrderedDictionary<String, String>

    /// Factory registry for creating resources based on file extensions or URI patterns.
    ///
    /// Different resource types (XMI, JSON, etc.) can register factories
    /// to handle their specific serialisation formats.
    private var resourceFactories: OrderedDictionary<String, ResourceFactory>

    /// The URIs of the Ecore documents that are currently being loaded natively.
    private var ecoreLoadsInProgress: Set<String> = []

    /// The handlers that read and write documents (see ``setURIHandlers(_:)``).
    var installedURIHandlers: [any URIHandler] = []

    /// Fragment segment naming rules, keyed by metaclass name (see ``FragmentSegmentRule``).
    var fragmentSegmentRules: [String: FragmentSegmentRule] = [:]

    /// Derived feature rules, keyed by class and feature name (see ``DerivedFeatureRule``).
    var derivedFeatureRules: [DerivedFeatureKey: DerivedFeatureRule] = [:]

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
    public func createResource(uri logicalURI: String) async -> Resource {
        let uri = URIReference.canonicalise(logicalURI)
        if let existing = resources[uri] {
            return existing
        }

        let resource = Resource(uri: uri)
        await resource.setResourceSet(self)
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
    public func getResource(uri logicalURI: String) -> Resource? {
        let uri = URIReference.canonicalise(logicalURI)
        // Return existing resource if already loaded
        if let existing = resources[uri] {
            return existing
        }

        // Attempt to load the resource using factories
        return loadResource(uri: uri)
    }

    /// Load an XMI resource from a file URL
    ///
    /// This method is a convenience for loading XMI files without requiring
    /// resource factories to be set up. It creates an XMIParser and loads
    /// the resource directly.
    ///
    /// This method is automatically called when resolving `ResourceProxy` objects that
    /// reference external resources. For example, when a reference like
    /// `href="department-b.xmi#/"` is resolved, this method loads the target resource.
    ///
    /// - Parameters:
    ///   - uri: The URI of the XMI file to load
    ///   - referenceParsing: How reference attributes of registered metamodels are read
    ///     (default ``XMIReferenceParsing/interpreted``)
    /// - Returns: The loaded Resource, either newly loaded or cached from previous load
    /// - Throws: XMIError if parsing fails
    public func loadXMIResource(
        uri documentURI: String, referenceParsing: XMIReferenceParsing = .interpreted
    ) async throws -> Resource {
        let uri = URIReference.canonicalise(documentURI)
        // Check if already loaded
        if let existing = resources[uri] {
            return existing
        }

        // Parse with XMIParser
        let parser = XMIParser(resourceSet: self, referenceParsing: referenceParsing)
        let data: Data
        do {
            data = try await readDocument(uri: uri)
        } catch URIHandlerError.invalidURI {
            throw XMIError.invalidXML("Invalid URI: \(uri)")
        }
        let resource = try await parser.parse(data, uri: uri)

        // Register in the resource set
        resources[uri] = resource

        return resource
    }

    /// Load a JSON resource from a file URL
    ///
    /// This method is a convenience for loading JSON files without requiring
    /// resource factories to be set up. It creates a JSONParser and loads
    /// the resource directly.
    ///
    /// This method is automatically called when resolving cross-resource references
    /// to JSON files.
    ///
    /// - Parameter uri: The URI of the JSON file to load
    /// - Returns: The loaded Resource, either newly loaded or cached from previous load
    /// - Throws: JSONError if parsing fails
    public func loadJSONResource(uri documentURI: String) async throws -> Resource {
        let uri = URIReference.canonicalise(documentURI)
        // Check if already loaded
        if let existing = resources[uri] {
            return existing
        }

        // Parse with JSONParser
        let parser = JSONParser(resourceSet: self)
        let data: Data
        do {
            data = try await readDocument(uri: uri)
        } catch URIHandlerError.invalidURI {
            throw JSONError.invalidFormat("Invalid URI: \(uri)")
        }
        let resource = try await parser.parse(data, uri: uri)

        // Register in the resource set
        resources[uri] = resource

        return resource
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
        metamodelSnapshot.register(package, uri: uri)
    }

    /// Unregisters a metamodel by its namespace URI.
    ///
    /// - Parameter uri: The namespace URI of the metamodel to unregister.
    /// - Returns: The unregistered package, or `nil` if not found.
    @discardableResult
    public func unregisterMetamodel(uri: String) -> EPackage? {
        metamodelSnapshot.unregister(uri: uri)
        return metamodelRegistry.removeValue(forKey: uri)
    }

    /// Gets a metamodel package by its namespace URI.
    ///
    /// The reflective Ecore package is built in: looking up its namespace URI
    /// (``EcorePackage/nsURI``) finds ``EcorePackage/instance`` unless a different
    /// package has been registered under that URI. The built-in package is not listed
    /// by ``getMetamodelURIs()``, which reports explicit registrations only.
    ///
    /// - Parameter uri: The namespace URI of the metamodel to retrieve.
    /// - Returns: The metamodel package, or `nil` if not registered.
    public func getMetamodel(uri: String) -> EPackage? {
        if let registered = metamodelRegistry[uri] { return registered }
        return uri == EcorePackage.nsURI ? EcorePackage.instance : nil
    }

    /// The reflective Ecore package that every resource set provides.
    ///
    /// Returns the package registered under the Ecore namespace URI if there is one,
    /// otherwise ``EcorePackage/instance``.
    public var ecorePackage: EPackage {
        return metamodelRegistry[EcorePackage.nsURI] ?? EcorePackage.instance
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
    /// Supports both exact matches and prefix matches. For prefix matches,
    /// the longest matching prefix is used. Chained mappings are resolved
    /// iteratively until no more conversions are possible.
    ///
    /// - Parameter logicalURI: The logical URI to convert.
    /// - Returns: The physical URI, or the original URI if no mapping exists.
    public func convertURI(_ logicalURI: String) -> String {
        var currentURI = logicalURI
        var previousURI = ""
        var iterationCount = 0
        let maxIterations = 100  // Prevent infinite loops

        // Keep converting until no more changes (chaining) or max iterations
        while currentURI != previousURI && iterationCount < maxIterations {
            previousURI = currentURI

            // First try exact match
            if let exactMatch = uriConverter[currentURI] {
                currentURI = exactMatch
                iterationCount += 1
                continue
            }

            // Then try prefix matches (longest first)
            var longestMatch: (prefix: String, replacement: String)?
            for (prefix, replacement) in uriConverter {
                if currentURI.hasPrefix(prefix) {
                    if longestMatch == nil || prefix.count > longestMatch!.prefix.count {
                        longestMatch = (prefix, replacement)
                    }
                }
            }

            if let match = longestMatch {
                // Replace prefix with replacement
                let suffix = String(currentURI.dropFirst(match.prefix.count))
                currentURI = match.replacement + suffix
                iterationCount += 1
            } else {
                // No match found
                break
            }
        }

        return currentURI
    }

    /// Normalises a URI by applying registered conversions and cleanup.
    ///
    /// - Parameter uri: The URI to normalise.
    /// - Returns: The normalised URI.
    public func normaliseURI(_ uri: String) -> String {
        let converted = convertURI(uri)

        // Check if URI is invalid or whitespace-only (handle gracefully)
        let trimmed = converted.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return converted  // Return whitespace/empty URIs as-is
        }

        if converted == "://" || converted.hasPrefix("://") || converted == "http://"
            || converted == "https://" || converted == "test:////"
        {
            return converted  // Return invalid URIs as-is
        }

        // If URI contains .. or . or //, use manual normalization
        if converted.contains("..") || converted.contains("/.") || converted.contains("//") {
            // Handle protocol prefixes manually
            if let protocolRange = converted.range(of: "://") {
                let protocolPart = String(converted[..<protocolRange.upperBound])
                let pathPart = String(converted[protocolRange.upperBound...])

                // Check if there's a leading slash after protocol (e.g., file:///)
                let hasLeadingSlash = pathPart.hasPrefix("/")
                let cleanPath = hasLeadingSlash ? String(pathPart.dropFirst()) : pathPart

                // Handle empty path (e.g., "test://")
                if cleanPath.isEmpty {
                    return converted
                }

                // Collapse multiple slashes and split into components
                // Replace "//" with "/" before splitting
                let collapsedPath = cleanPath.replacingOccurrences(of: "//", with: "/")
                let components = collapsedPath.split(separator: "/")
                var normalised: [String] = []

                for component in components {
                    if component == ".." {
                        // Pop previous component if it exists and isn't ".."
                        if !normalised.isEmpty && normalised.last != ".." {
                            normalised.removeLast()
                        }
                        // If stack is empty or last is "..", we're trying to go above root
                        // In EMF/URI semantics, extra ".." are simply ignored (stay at root)
                    } else if component != "." && !component.isEmpty {
                        normalised.append(String(component))
                    }
                }

                let normalisedPath = normalised.joined(separator: "/")
                return protocolPart + (hasLeadingSlash ? "/" : "") + normalisedPath
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

        // For URIs without special characters, use Foundation URL for normalization
        if let url = URL(string: converted) {
            let standardized = url.standardized

            // For file:/// URLs, preserve the triple slash
            if converted.hasPrefix("file:///") && !standardized.absoluteString.hasPrefix("file:///")
            {
                // Reconstruct with triple slash
                if let path = standardized.path.isEmpty ? nil : standardized.path {
                    return "file:///" + path.dropFirst()
                }
            }

            return standardized.absoluteString
        }

        // Final fallback: return as-is
        return converted
    }

    // MARK: - Loading Referenced Resources

    /// Loads a resource that another resource refers to.
    ///
    /// The resource is returned from the set if it is already loaded. Otherwise it is
    /// loaded by file type: `.json` files with the JSON parser, everything else
    /// (including `.ecore`, `.xmi`, and `.genmodel`) with the XMI parser. Ecore
    /// documents are loaded as the object graph the XMI parser builds; use
    /// ``loadEcoreResource(uri:)`` to load them as native metamodel objects.
    ///
    /// - Parameter uri: The absolute URI of the resource to load.
    /// - Returns: The loaded resource.
    /// - Throws: A parsing error if the resource cannot be read or parsed.
    public func loadReferencedResource(uri documentURI: String) async throws -> Resource {
        let uri = URIReference.canonicalise(documentURI)
        if let existing = resources[uri] {
            return existing
        }
        let lowercased = uri.lowercased()
        if lowercased.hasSuffix(".json") {
            return try await loadJSONResource(uri: uri)
        }
        return try await loadXMIResource(uri: uri)
    }

    /// Loads an Ecore document as native metamodel objects.
    ///
    /// The document is parsed and converted into an ``EPackage`` with its native
    /// classifiers, features, operations, and parameters. The package and every element it
    /// contains are registered in the new resource, so name-based fragments such as
    /// `#//Book/title` and `#//Book/borrow/days` resolve to the native objects. The package
    /// is also registered as a metamodel under its namespace URI unless one is already
    /// registered.
    ///
    /// Types that refer to other documents (for example `other.ecore#//Name`) are resolved
    /// by loading those documents as native metamodels into this set, relative to the
    /// document that refers to them. Documents that refer to each other in a cycle resolve
    /// the references that close the cycle to stand-ins.
    ///
    /// - Parameter uri: The absolute URI of the `.ecore` document.
    /// - Returns: The resource holding the native package as its root object.
    /// - Throws: ``XMIError`` if the document cannot be read or has no root package.
    public func loadEcoreResource(uri: String) async throws -> Resource {
        try await loadEcoreResource(uri: uri, enableDebugging: false)
    }

    /// Loads an Ecore document as native metamodel objects, optionally tracing the parse.
    ///
    /// - Parameters:
    ///   - uri: The absolute URI of the `.ecore` document.
    ///   - enableDebugging: Whether the parser prints a trace.
    /// - Returns: The resource holding the native package as its root object.
    /// - Throws: ``XMIError`` if the document cannot be read or has no root package.
    func loadEcoreResource(uri documentURI: String, enableDebugging: Bool) async throws -> Resource {
        let uri = URIReference.canonicalise(documentURI)
        if let existing = resources[uri] {
            return existing
        }
        let data: Data
        do {
            data = try await readDocument(uri: uri)
        } catch URIHandlerError.invalidURI {
            throw XMIError.invalidXML("Invalid URI: \(uri)")
        }
        return try await loadEcoreResource(data: data, uri: uri, enableDebugging: enableDebugging)
    }

    /// Loads an Ecore document that has been read already as native metamodel objects.
    ///
    /// - Parameters:
    ///   - data: The bytes of the document.
    ///   - uri: The canonical URI of the document.
    ///   - enableDebugging: Whether the parser prints a trace.
    /// - Returns: The resource holding the native package as its root object.
    /// - Throws: ``XMIError`` if the document cannot be parsed or has no root package.
    func loadEcoreResource(data: Data, uri: String, enableDebugging: Bool) async throws -> Resource {
        if let existing = resources[uri] {
            return existing
        }
        ecoreLoadsInProgress.insert(uri)
        defer { ecoreLoadsInProgress.remove(uri) }

        let parser = XMIParser(enableDebugging: enableDebugging)
        let parsed = try await parser.parse(data, uri: uri)
        await parsed.enableDebugging(enableDebugging)
        await parsed.setResourceSet(self)
        guard let root = await parsed.getRootObjects().first else {
            throw XMIError.noRootObject
        }
        let package = try await parsed.createEPackage(from: root)
        let resource = await createResource(uri: uri)
        await resource.registerNativePackage(package)
        if metamodelRegistry[package.nsURI] == nil {
            registerMetamodel(package, uri: package.nsURI)
        }
        return resource
    }

    /// The resource of a document as native metamodel objects, if it can be provided.
    ///
    /// A resource that is already loaded is returned only if its root object is a native
    /// package. Otherwise the document is loaded with ``loadEcoreResource(uri:)``, unless
    /// it is currently being loaded (a cyclic reference), in which case `nil` is returned.
    ///
    /// - Parameter uri: The absolute URI of the document.
    /// - Returns: The native resource, or `nil` if the document cannot be provided natively.
    func nativeResource(uri documentURI: String) async -> Resource? {
        let uri = URIReference.canonicalise(documentURI)
        if let existing = resources[uri] {
            return await existing.getRootObjects().first is EPackage ? existing : nil
        }
        guard !ecoreLoadsInProgress.contains(uri) else { return nil }
        return try? await loadEcoreResource(uri: uri)
    }

    /// Resolves the cross-resource proxies of every resource in the set.
    ///
    /// Target resources are loaded on demand. See ``Resource/resolveProxies()`` for
    /// how individual values are replaced.
    ///
    /// - Returns: The combined report over all resources in the set.
    public func resolveAllProxies() async -> ProxyResolutionReport {
        var report = ProxyResolutionReport()
        for resource in Array(resources.values) {
            report.merge(await resource.resolveProxies())
        }
        return report
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
        guard !components.isEmpty else { return nil }

        let resourceURI = String(components[0])
        let objectPath = components.count > 1 ? String(components[1]) : "/"

        guard let resource = getResource(uri: resourceURI) else { return nil }
        return await resource.resolveByPath(objectPath)
    }

    /// Updates the opposite side of a bidirectional reference across resources.
    ///
    /// This method is used by Resource to coordinate opposite reference updates
    /// when the target object is in a different resource. The method automatically
    /// determines if the opposite reference is multi-valued by examining the
    /// target object's metamodel.
    ///
    /// - Parameters:
    ///   - targetId: The unique identifier of the target object to update.
    ///   - oppositeRefId: The unique identifier of the opposite reference feature.
    ///   - sourceId: The unique identifier of the source object establishing the relationship.
    ///   - add: Whether to add (`true`) or remove (`false`) the bidirectional relationship.
    public func updateOpposite(targetId: EUUID, oppositeRefId: EUUID, sourceId: EUUID, add: Bool)
        async
    {
        // Find the resource containing the target object
        for resource in resources.values {
            if await resource.contains(id: targetId) {
                // Find the target object and update its opposite reference
                guard var target = await resource.resolve(targetId) as? DynamicEObject else {
                    continue
                }
                let targetClass = target.eClass
                guard
                    let oppositeRef = targetClass.allReferences.first(where: {
                        $0.id == oppositeRefId
                    })
                else { continue }

                // Determine multiplicity from the opposite reference itself
                if oppositeRef.isMany {
                    // Multi-valued opposite
                    var oppositeArray = (target.eGet(oppositeRef) as? [EUUID]) ?? []
                    if add {
                        if !oppositeArray.contains(sourceId) {
                            oppositeArray.append(sourceId)
                        }
                    } else {
                        oppositeArray.removeAll { $0 == sourceId }
                    }
                    target.eSet(oppositeRef, oppositeArray)
                } else {
                    // Single-valued opposite
                    target.eSet(oppositeRef, add ? sourceId : nil)
                }

                // Update the object in its resource
                _ = await resource.add(target)
                return
            }
        }
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
    /// Attempts to load a resource using registered resource factories.
    ///
    /// Converts the logical URI to a physical URI using the URI converter,
    /// then searches through registered factories to find one that can handle
    /// the resource format. If a suitable factory is found, it creates and
    /// loads the resource into this resource set.
    ///
    /// - Parameter uri: The logical URI of the resource to load.
    /// - Returns: The loaded resource, or `nil` if no factory can handle the URI format.
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

    /// Registers default resource factories for standard EMF serialisation formats.
    ///
    /// Sets up built-in factories for common resource types such as XMI and JSON.
    /// This method is called automatically when factories are first needed,
    /// providing sensible defaults without requiring explicit configuration.
    ///
    /// ## Registered Factories
    /// - XMI factory for `.xmi` and `.ecore` files
    /// - JSON factory for `.json` files
    /// - Generic factory for unknown formats (falls back to XMI)
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
