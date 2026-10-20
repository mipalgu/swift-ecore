//
// XPathResolver.swift
// ECore
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Resolves XPath-style fragment identifiers to object IDs
///
/// XPath resolution handles XMI fragment identifiers like:
/// - `#//@members.0` - Navigate to the first member of the first (or only) root
/// - `#//Person.0/@children.2` - Navigate through multiple containment levels
/// - `#/1` - The second root of a resource with several roots
/// - `#/1/@children.0` - Navigate from the second root of a resource with several roots
/// - `#//Book/title` - Name-based navigation of Ecore elements (see ``FragmentNavigator``)
///
/// ## XPath Fragment Format
///
/// XMI uses a simplified XPath syntax for same-resource references
/// (see ``PositionalFragments`` for the fragments that writers produce):
/// - `#` - Same resource reference indicator
/// - `//` - Navigate from the first (or only) root object
/// - `/n` - Navigate from root `n` of a resource with several roots
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
    /// to locate the target object. A path that starts with `//` navigates from
    /// the first root; a path that starts with `/n` navigates from root `n`.
    ///
    /// - Parameter path: XPath expression (e.g., "#//@members.0" or "#/1/@members.0")
    /// - Returns: The EUUID of the target object, or nil if not found
    public func resolve(_ path: String) async -> EUUID? {
        // Remove leading # if present (same-resource indicator)
        let cleanPath = path.first == CrossReferenceSyntax.fragmentSeparator ? String(path.dropFirst()) : path

        // Empty path, "/" or "//" means the first root object
        if cleanPath.isEmpty || cleanPath == CrossReferenceSyntax.rootFragment
            || cleanPath == CrossReferenceSyntax.fragmentPathPrefix
        {
            return await resource.getRootObjects().first?.id
        }

        // Paths without positional segments (//Book/title, /1, /1/Book) identify elements by name or root
        guard cleanPath.contains(CrossReferenceSyntax.positionalMarker) else {
            return await FragmentNavigator(resource: resource).resolve(cleanPath)?.id
        }

        // Find the root to start from and the positional steps below it
        let roots = await resource.getRootObjects()
        let start: (any EObject)?
        let steps: Substring
        if cleanPath.hasPrefix(CrossReferenceSyntax.fragmentPathPrefix) {
            start = roots.first
            steps = cleanPath.dropFirst(CrossReferenceSyntax.fragmentPathPrefix.count)
        } else if let (position, remainder) = rootPosition(in: cleanPath) {
            guard roots.indices.contains(position) else { return nil }
            start = roots[position]
            steps = remainder
        } else {
            start = roots.first
            steps = Substring(cleanPath)
        }
        guard let rootObject = start else {
            return nil
        }

        // Navigate through the path
        return await navigate(from: rootObject.id, components: parsePathComponents(steps))
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
    /// Converts "@members.0/@children.1" into structured components:
    /// - ["@members", "0", "@children", "1"]
    ///
    /// - Parameter path: The positional steps below the root (without a leading `#` or root segment)
    /// - Returns: Array of path components
    private func parsePathComponents(_ path: Substring) -> [String] {
        var components: [String] = []

        // Split by / and process each segment
        let segments = path.split(separator: CrossReferenceSyntax.segmentSeparator)

        for segment in segments {
            // Split by . to separate feature names from indices
            // e.g., "@members.0" → ["@members", "0"]
            let parts = segment.split(separator: CrossReferenceSyntax.indexSeparator)
            for part in parts {
                components.append(String(part))
            }
        }

        return components
    }

    /// Splits a leading root segment (`/n`) off a path.
    ///
    /// - Parameter path: The cleaned path (without a leading `#`).
    /// - Returns: The position of the root and the rest of the path, or `nil` if the path
    ///   does not start with `/` followed by a root position.
    private func rootPosition(in path: String) -> (Int, Substring)? {
        guard path.first == CrossReferenceSyntax.segmentSeparator else { return nil }
        let body = path.dropFirst()
        let end = body.firstIndex(of: CrossReferenceSyntax.segmentSeparator) ?? body.endIndex
        guard let position = Int(body[..<end]) else { return nil }
        return (position, body[end...])
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
            if component.first == CrossReferenceSyntax.positionalMarker {
                // It's a feature name - navigate through it
                let featureName = String(component.dropFirst())  // Remove @

                // Get the next component to check if it's an index
                if index + 1 < components.count,
                    let arrayIndex = Int(components[index + 1])
                {
                    // Multi-valued feature with index
                    guard
                        let nextId = await navigateFeature(
                            from: currentId, feature: featureName, index: arrayIndex)
                    else {
                        return nil
                    }
                    currentId = nextId
                    index += 2  // Skip both feature name and index
                } else {
                    // Single-valued feature
                    guard
                        let nextId = await navigateFeature(
                            from: currentId, feature: featureName, index: nil)
                    else {
                        return nil
                    }
                    currentId = nextId
                    index += 1
                }
            } else {
                // Unknown component format (root positions are only valid at the start)
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
            // Single-valued reference: also accept index 0 for XPath
            // compatibility (e.g., //@feature.0 when only one element)
            return (index == nil || index == 0) ? id : nil
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
}
