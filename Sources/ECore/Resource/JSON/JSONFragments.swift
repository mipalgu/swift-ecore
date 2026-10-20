//
// JSONFragments.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// The target that a JSON reference denotes.
public enum JSONReferenceTarget: Sendable, Equatable {
    /// An object of the resource that holds the reference.
    case object(EUUID)

    /// An object that cannot be found yet, or that lives in another document.
    case proxy(ResourceProxy)
}

/// Computes and resolves the fragments that JSON documents use to refer to objects.
///
/// A fragment names an object by its containment path from a root of the resource.
/// Three notations are understood when resolving:
///
/// - EMF fragments, `//@authors.0/@books.1`, where `@feature` selects a feature and
///   `.n` the element of a many-valued feature. A single-root document starts
///   with `//`; the object at index `r` of a multi-root document starts with `/r`.
/// - JSON pointers, `/authors/0/books/1`, where each segment is a feature name or an index.
/// - Name-based Ecore fragments such as `//Book/title`.
///
/// References are written as EMF fragments. A reference may be preceded by a document
/// URI (`other.json#//@authors.0`), which makes it refer to another resource.
public enum JSONFragments {
    // MARK: - Computing

    /// Computes the fragment of every object that is reachable through containment.
    ///
    /// The fragments are those that ``JSONSerializer`` writes: `//` for the only root,
    /// `/r` for root `r` of several, and `@feature` or `@feature.n` segments below it.
    /// They are the ``PositionalFragments`` of the resource, except that the only root
    /// of a resource is spelt `//` (where EMF's XMI writer uses `/`), which is the
    /// spelling JSON documents use.
    ///
    /// - Parameter resource: The resource whose objects to index.
    /// - Returns: The fragment of each contained object, without a leading `#`.
    public static func index(of resource: Resource) async -> [EUUID: String] {
        await PositionalFragments.index(of: resource, singleRootFragment: CrossReferenceSyntax.fragmentPathPrefix)
    }

    /// Computes the fragment of one object.
    ///
    /// - Parameters:
    ///   - target: The identifier of the object.
    ///   - resource: The resource that contains the object.
    /// - Returns: The fragment without a leading `#`, or `nil` if the object is not reachable
    ///   through containment from a root of the resource.
    public static func fragment(for target: EUUID, in resource: Resource) async -> String? {
        await index(of: resource)[target]
    }

    /// Computes the text of a reference from a resource to an object.
    ///
    /// An object of the same resource is denoted by its fragment alone. An object of another
    /// resource in the same resource set is denoted by the URI of that resource (relative to
    /// the referring one) and its fragment.
    ///
    /// - Parameters:
    ///   - target: The identifier of the referenced object.
    ///   - resource: The resource that holds the reference.
    /// - Returns: The reference text, or `nil` if the object cannot be located.
    public static func reference(to target: EUUID, from resource: Resource) async -> String? {
        if let local = await fragment(for: target, in: resource) { return local }
        guard let resourceSet = await resource.resourceSet,
            let located = await resourceSet.resolve(target), located.resource !== resource,
            let remote = await fragment(for: target, in: located.resource)
        else { return nil }
        return reference(uri: located.resource.uri, fragment: remote, from: resource.uri)
    }

    /// Composes the text of a reference to a fragment of a document.
    ///
    /// - Parameters:
    ///   - uri: The URI of the referenced document.
    ///   - fragment: The fragment, with or without a leading `#`.
    ///   - base: The URI of the referring document.
    /// - Returns: The document URI relative to `base`, a `#`, and the fragment.
    public static func reference(uri: String, fragment: String, from base: String) -> String {
        let bare = fragment.first == CrossReferenceSyntax.fragmentSeparator ? String(fragment.dropFirst()) : fragment
        let location = URIReference.relativise(uri, against: base)
        return location + String(CrossReferenceSyntax.fragmentSeparator) + bare
    }

    // MARK: - Resolving

    /// Resolves the text of a reference.
    ///
    /// - Parameters:
    ///   - reference: A fragment (`//@authors.0`, `#//@authors.0`, `#/authors/0`) or a
    ///     document URI and fragment (`other.json#//@authors.0`).
    ///   - resource: The resource that holds the reference.
    /// - Returns: The object of the resource, or a proxy if the reference names another
    ///   document or the fragment cannot be resolved (yet).
    public static func resolve(_ reference: String, from resource: Resource) async -> JSONReferenceTarget {
        let parts = URIReference.split(reference)
        let ownURI = resource.uri
        var documentURI = parts.uri
        var fragment = parts.fragment ?? ""
        if parts.fragment == nil, reference.first == CrossReferenceSyntax.segmentSeparator {
            documentURI = ""
            fragment = reference
        }
        if !documentURI.isEmpty {
            let absolute = URIReference.canonicalise(URIReference.resolve(documentURI, against: ownURI))
            if absolute != URIReference.canonicalise(ownURI) {
                return .proxy(ResourceProxy(uri: absolute, fragment: fragment))
            }
        }
        if let identifier = await resolve(fragment: fragment, in: resource) { return .object(identifier) }
        return .proxy(ResourceProxy(uri: ownURI, fragment: fragment))
    }

    /// Resolves a fragment to an object of a resource.
    ///
    /// - Parameters:
    ///   - fragment: An EMF fragment, a JSON pointer, or a name-based fragment, with or
    ///     without a leading `#`.
    ///   - resource: The resource that contains the object.
    /// - Returns: The identifier of the object, or `nil` if the fragment names no object.
    public static func resolve(fragment text: String, in resource: Resource) async -> EUUID? {
        var fragment = text
        if fragment.first == CrossReferenceSyntax.fragmentSeparator { fragment.removeFirst() }
        let roots = await resource.getRootObjects()
        let separator = CrossReferenceSyntax.segmentSeparator
        if fragment.isEmpty || fragment == CrossReferenceSyntax.rootFragment
            || fragment == CrossReferenceSyntax.fragmentPathPrefix
        {
            return roots.first?.id
        }
        var segments = fragment.split(separator: separator, omittingEmptySubsequences: true).map(String.init)
        var start: (any EObject)?
        if fragment.hasPrefix(CrossReferenceSyntax.fragmentPathPrefix) {
            start = roots.first
        } else if let first = segments.first, let position = Int(first), roots.indices.contains(position) {
            start = roots[position]
            segments.removeFirst()
        } else {
            start = roots.first
        }
        guard var current = start as? DynamicEObject else {
            return fragment.hasPrefix(CrossReferenceSyntax.fragmentPathPrefix)
                ? await XPathResolver(resource: resource).resolve(fragment) : nil
        }
        let positional = segments.contains { $0.first == CrossReferenceSyntax.positionalMarker }
        if !positional, fragment.hasPrefix(CrossReferenceSyntax.fragmentPathPrefix) {
            return await XPathResolver(resource: resource).resolve(fragment)
        }
        var index = 0
        while index < segments.count {
            let step = positional ? positionalStep(segments[index]) : pointerStep(segments, at: &index)
            guard let step, let next = await child(of: current, feature: step.feature, index: step.index, in: resource)
            else { return nil }
            index += 1
            if index == segments.count { return next.id }
            guard let object = next as? DynamicEObject else { return nil }
            current = object
        }
        return current.id
    }

    // MARK: - Private Helpers

    /// The object identifiers that a stored reference value holds.
    private static func identifiers(of value: (any EcoreValue)?) -> [EUUID] {
        switch value {
        case let identifier as EUUID: return [identifier]
        case let identifiers as [EUUID]: return identifiers
        case let array as EcoreValueArray: return array.values.compactMap { $0 as? EUUID }
        default: return []
        }
    }

    /// Splits an EMF segment such as `@authors.0` into feature and index.
    private static func positionalStep(_ segment: String) -> (feature: String, index: Int?)? {
        guard segment.first == CrossReferenceSyntax.positionalMarker else { return nil }
        let body = segment.dropFirst()
        guard let dot = body.lastIndex(of: CrossReferenceSyntax.indexSeparator),
            let position = Int(body[body.index(after: dot)...])
        else { return (String(body), nil) }
        return (String(body[..<dot]), position)
    }

    /// Reads a JSON pointer step, which is a feature name optionally followed by an index segment.
    ///
    /// - Parameters:
    ///   - segments: The segments of the pointer.
    ///   - index: The position of the feature segment; advanced past an index segment.
    private static func pointerStep(_ segments: [String], at index: inout Int) -> (feature: String, index: Int?)? {
        let feature = unescape(segments[index])
        if index + 1 < segments.count, let position = Int(segments[index + 1]) {
            index += 1
            return (feature, position)
        }
        return (feature, nil)
    }

    /// Undoes the escapes of a JSON pointer segment.
    private static func unescape(_ segment: String) -> String {
        let decoded = segment.removingPercentEncoding ?? segment
        return decoded.replacingOccurrences(of: JSONSyntax.pointerSlashEscape, with: String(JSONSyntax.pointerSeparator))
            .replacingOccurrences(of: JSONSyntax.pointerTildeEscape, with: "~")
    }

    /// Finds the object that a feature of an object holds at an index.
    private static func child(
        of object: DynamicEObject, feature: String, index: Int?, in resource: Resource
    ) async -> (any EObject)? {
        let current = await resource.resolve(object.id) as? DynamicEObject ?? object
        let candidates = identifiers(of: current.eGet(feature))
        let position = index ?? 0
        guard candidates.indices.contains(position), index != nil || candidates.count == 1 else { return nil }
        return await resource.resolve(candidates[position])
    }
}
