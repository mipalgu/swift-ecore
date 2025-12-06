//
// XPathResolver.swift
// ECore
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

/// Resolves XPath-style fragment identifiers to object IDs
///
/// XPath resolution handles XMI fragment identifiers like:
/// - `#//@members.0` - Navigate to first member from root
/// - `#//Person.0/@children.2` - Navigate through multiple containment levels
/// - `#/0/@children.1` - Index-based navigation
///
/// ## XPath Fragment Format
///
/// XMI uses a simplified XPath syntax for same-resource references:
/// - `#` - Same resource reference indicator
/// - `//` - Navigate from root object
/// - `@feature` - Navigate through containment feature named "feature"
/// - `.index` - Array index for multi-valued features
/// - `/` - Path separator for nested navigation
///
/// ## Example
///
/// ```swift
/// let resolver = XPathResolver(resource: resource)
/// if let memberId = await resolver.resolve("#//@members.0") {
///     let member = await resource.resolve(memberId)
/// }
/// ```
public struct XPathResolver: Sendable {
    private let resource: Resource

    /// Initialise an XPath resolver for a specific resource
    ///
    /// - Parameter resource: The Resource containing the objects to navigate
    public init(resource: Resource) {
        self.resource = resource
    }

    /// Resolve an XPath expression to an object ID
    ///
    /// Parses the XPath expression and navigates the containment hierarchy
    /// to locate the target object.
    ///
    /// - Parameter path: XPath expression (e.g., "#//@members.0")
    /// - Returns: The EUUID of the target object, or nil if not found
    public func resolve(_ path: String) async -> EUUID? {
        // Remove leading # if present (same-resource indicator)
        let cleanPath = path.hasPrefix("#") ? String(path.dropFirst()) : path

        // Empty path or just "/" means root object
        if cleanPath.isEmpty || cleanPath == "/" || cleanPath == "//" {
            let roots = await resource.getRootObjects()
            return roots.first?.id
        }

        // Parse the path components
        let components = parsePathComponents(cleanPath)

        // Start navigation from root
        let roots = await resource.getRootObjects()
        guard let rootObject = roots.first else {
            return nil
        }

        // Navigate through the path
        return await navigate(from: rootObject.id, components: components)
    }

    /// Resolve XPath to object directly (convenience method)
    ///
    /// - Parameter path: XPath expression
    /// - Returns: The resolved EObject, or nil if not found
    public func resolveObject(_ path: String) async -> (any EObject)? {
        guard let id = await resolve(path) else { return nil }
        return await resource.resolve(id)
    }

    // MARK: - Private Helper Methods

    /// Parse XPath components from a path string
    ///
    /// Converts "#//@members.0/@children.1" into structured components:
    /// - ["@members", "0", "@children", "1"]
    ///
    /// - Parameter path: The cleaned XPath string (without leading #)
    /// - Returns: Array of path components
    private func parsePathComponents(_ path: String) -> [String] {
        var components: [String] = []

        // Remove leading // if present
        let workingPath = path.hasPrefix("//") ? String(path.dropFirst(2)) : path

        // Split by / and process each segment
        let segments = workingPath.split(separator: "/")

        for segment in segments {
            // Split by . to separate feature names from indices
            // e.g., "@members.0" → ["@members", "0"]
            let parts = segment.split(separator: ".")
            for part in parts {
                components.append(String(part))
            }
        }

        return components
    }

    /// Navigate from a starting object through path components
    ///
    /// - Parameters:
    ///   - objectId: Starting object ID
    ///   - components: Path components to navigate
    /// - Returns: The ID of the target object, or nil if navigation fails
    private func navigate(from objectId: EUUID, components: [String]) async -> EUUID? {
        var currentId = objectId
        var index = 0

        while index < components.count {
            let component = components[index]

            // Check if it's a feature name or an index
            if component.hasPrefix("@") {
                // It's a feature name - navigate through it
                let featureName = String(component.dropFirst()) // Remove @

                // Get the next component to check if it's an index
                if index + 1 < components.count,
                   let arrayIndex = Int(components[index + 1]) {
                    // Multi-valued feature with index
                    guard let nextId = await navigateFeature(from: currentId, feature: featureName, index: arrayIndex) else {
                        return nil
                    }
                    currentId = nextId
                    index += 2 // Skip both feature name and index
                } else {
                    // Single-valued feature
                    guard let nextId = await navigateFeature(from: currentId, feature: featureName, index: nil) else {
                        return nil
                    }
                    currentId = nextId
                    index += 1
                }
            } else if let arrayIndex = Int(component) {
                // It's a bare index without @ prefix (less common)
                // Treat as index into the current object's children
                guard let nextId = await navigateIndex(from: currentId, index: arrayIndex) else {
                    return nil
                }
                currentId = nextId
                index += 1
            } else {
                // Unknown component format
                return nil
            }
        }

        return currentId
    }

    /// Navigate through a named feature
    ///
    /// - Parameters:
    ///   - objectId: Current object ID
    ///   - feature: Feature name to navigate
    ///   - index: Optional array index for multi-valued features
    /// - Returns: The ID of the target object, or nil if not found
    private func navigateFeature(from objectId: EUUID, feature: String, index: Int?) async -> EUUID? {
        // Get the value of the feature from the resource
        guard let value = await resource.eGet(objectId: objectId, feature: feature) else {
            return nil
        }

        // Handle different value types
        if let id = value as? EUUID {
            // Single-valued reference
            return index == nil ? id : nil
        } else if let ids = value as? [EUUID] {
            // Multi-valued reference
            guard let index = index, index >= 0, index < ids.count else {
                return nil
            }
            return ids[index]
        } else {
            // Not a reference type
            return nil
        }
    }

    /// Navigate to a child by index
    ///
    /// - Parameters:
    ///   - objectId: Current object ID
    ///   - index: Index of child to navigate to
    /// - Returns: The ID of the child object, or nil if not found
    private func navigateIndex(from objectId: EUUID, index: Int) async -> EUUID? {
        // This is a simplified implementation
        // In a full EMF implementation, we'd need to know which containment
        // feature to use. For now, we'll try to get all contained children
        // and index into them.

        // TODO: Implement proper child enumeration if needed
        return nil
    }
}
