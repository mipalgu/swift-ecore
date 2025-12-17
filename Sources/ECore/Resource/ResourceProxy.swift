//
// ResourceProxy.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// A proxy representing an unresolved cross-resource reference
///
/// ResourceProxy stores information about a reference to an object in another resource
/// that hasn't been loaded yet. When the target resource is loaded, the proxy can be
/// resolved to the actual object.
///
/// ## Usage Example
///
/// ```swift
/// // Create a proxy for a cross-resource reference
/// let proxy = ResourceProxy(uri: "department-b.xmi", fragment: "/")
///
/// // Later, resolve the proxy when the resource is loaded
/// if let object = await proxy.resolve(in: resourceSet) {
///     // Use the resolved object
/// }
/// ```
public struct ResourceProxy: EcoreValue, Sendable, Equatable, Hashable {
    /// The URI of the external resource (relative or absolute)
    public let uri: String

    /// The fragment identifier within the external resource (e.g., "/" or "//@members.0")
    public let fragment: String

    /// Creates a new resource proxy
    ///
    /// - Parameters:
    ///   - uri: The URI of the external resource
    ///   - fragment: The fragment identifier within the resource
    public init(uri: String, fragment: String) {
        self.uri = uri
        self.fragment = fragment
    }

    /// Resolve the proxy to an actual object
    ///
    /// This method attempts to load the target resource and resolve the fragment
    /// to an actual object ID. If the resource is not loaded, it will attempt to
    /// load it using loadXMIResource.
    ///
    /// - Parameter resourceSet: The ResourceSet to use for resolution
    /// - Returns: The resolved object ID, or nil if resolution fails
    public func resolve(in resourceSet: ResourceSet) async -> EUUID? {
        // Get the target resource URI
        let targetURI = uri

        // Try to get the resource, loading it if necessary
        var targetResource = await resourceSet.getResource(uri: targetURI)

        // If not found, try to load it as an XMI resource
        if targetResource == nil {
            do {
                targetResource = try await resourceSet.loadXMIResource(uri: targetURI)
            } catch {
                return nil
            }
        }

        guard let resource = targetResource else {
            return nil
        }

        // If fragment is empty or just "/", return root object
        if fragment.isEmpty || fragment == "/" {
            let roots = await resource.getRootObjects()
            return roots.first?.id
        }

        // Use XPath resolver to find the object
        let xpath = fragment.hasPrefix("#") ? fragment : "#\(fragment)"
        let resolver = XPathResolver(resource: resource)
        return await resolver.resolve(xpath)
    }

    /// Resolve the proxy to an actual object (convenience method)
    ///
    /// - Parameter resourceSet: The ResourceSet to use for resolution
    /// - Returns: The resolved object, or nil if resolution fails
    public func resolveObject(in resourceSet: ResourceSet) async -> (any EObject)? {
        guard let id = await resolve(in: resourceSet) else { return nil }
        guard let targetResource = await resourceSet.getResource(uri: uri) else { return nil }
        return await targetResource.resolve(id)
    }

    // MARK: - Equatable

    public static func == (lhs: ResourceProxy, rhs: ResourceProxy) -> Bool {
        return lhs.uri == rhs.uri && lhs.fragment == rhs.fragment
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uri)
        hasher.combine(fragment)
    }
}
