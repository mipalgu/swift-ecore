//
// PositionalFragments.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Computes the positional fragments that identify the objects of a resource.
///
/// A positional fragment names an object by the containment features and indices
/// along its path from a root of the resource, following the rule of EMF's
/// `ResourceImpl.getURIFragment`:
///
/// - The only root of a resource is `/`, and its contents are `//@feature.index/...`.
/// - Root `n` of a resource with several roots is `/n`, and its contents are
///   `/n/@feature.index/...`, including for the first root (`/0`).
///
/// A segment `@feature.index` selects an element of a many-valued containment
/// feature, and a segment `@feature` the value of a single-valued one. Only
/// containment references are followed; the container side of a containment (see
/// ``EReference/isContainerSide``) never contributes a segment.
///
/// Fragments are returned without a leading `#`. Writers add `#` where the document
/// syntax needs it, for example in an `href`.
public enum PositionalFragments {
    /// Computes the fragment of every object that is reachable through containment.
    ///
    /// The fragments follow the EMF rule described for ``PositionalFragments``. If an
    /// object is reachable along several paths, the first path found is used.
    ///
    /// - Parameters:
    ///   - resource: The resource whose objects to index.
    ///   - singleRootFragment: The fragment of the root of a resource with only one root.
    ///     EMF writes ``CrossReferenceSyntax/rootFragment``; the contents of that root are
    ///     always written below ``CrossReferenceSyntax/fragmentPathPrefix``.
    /// - Returns: The fragment of each contained object, without a leading `#`.
    public static func index(
        of resource: Resource, singleRootFragment: String = CrossReferenceSyntax.rootFragment
    ) async -> [EUUID: String] {
        let roots = await resource.getRootObjects()
        var result: [EUUID: String] = [:]
        for (position, root) in roots.enumerated() {
            let base = rootSegment(position, rootCount: roots.count)
            await collect(root, path: base, in: resource, into: &result)
            if roots.count == 1 { result[root.id] = singleRootFragment }
        }
        return result
    }

    /// Computes the fragment of one object.
    ///
    /// To compute the fragments of many objects of the same resource, compute the
    /// ``index(of:singleRootFragment:)`` once and look the objects up in it.
    ///
    /// - Parameters:
    ///   - target: The identifier of the object.
    ///   - resource: The resource that contains the object.
    /// - Returns: The fragment without a leading `#`, or `nil` if the object is not reachable
    ///   through containment from a root of the resource.
    public static func fragment(for target: EUUID, in resource: Resource) async -> String? {
        await index(of: resource)[target]
    }

    /// The fragment of a root of a resource.
    ///
    /// - Parameters:
    ///   - position: The position of the root among the roots of the resource.
    ///   - rootCount: The number of roots of the resource.
    /// - Returns: ``CrossReferenceSyntax/rootFragment`` for the only root of a resource,
    ///   otherwise `/` followed by the position of the root.
    public static func rootSegment(_ position: Int, rootCount: Int) -> String {
        guard rootCount != 1 else { return CrossReferenceSyntax.rootFragment }
        return String(CrossReferenceSyntax.segmentSeparator) + String(position)
    }

    /// Records the fragments of an object and of everything it contains.
    ///
    /// - Parameters:
    ///   - object: The object to record.
    ///   - path: The fragment of the object.
    ///   - resource: The resource that holds the object and its contents.
    ///   - result: The fragments recorded so far.
    private static func collect(
        _ object: any EObject, path: String, in resource: Resource,
        into result: inout [EUUID: String]
    ) async {
        guard result[object.id] == nil else { return }
        result[object.id] = path
        guard let dynamic = object as? DynamicEObject else { return }
        let separator = String(CrossReferenceSyntax.segmentSeparator)
        let marker = String(CrossReferenceSyntax.positionalMarker)
        for reference in dynamic.eClass.allReferences where reference.containment && !reference.isContainerSide {
            let children = ReferenceValues.identifiers(dynamic.eGet(reference))
            for (position, identifier) in children.enumerated() {
                guard let child = await resource.resolve(identifier) else { continue }
                var segment = marker + reference.name
                if reference.isMany { segment += String(CrossReferenceSyntax.indexSeparator) + String(position) }
                await collect(child, path: path + separator + segment, in: resource, into: &result)
            }
        }
    }
}

extension EReference {
    /// Whether this reference is the container side of a containment.
    ///
    /// The container side of a bidirectional containment refers from a contained
    /// object back to its container. Its value follows from the containment, so
    /// EMF never writes it to a document. A reference is the container side if
    /// loading has flagged it as ``container``, or if its opposite, looked up in
    /// the class that the reference refers to, is a containment reference.
    public var isContainerSide: Bool {
        if container { return true }
        guard let opposite, let target = eType as? EClass else { return false }
        return target.allReferences.first { $0.id == opposite }?.containment ?? false
    }
}
