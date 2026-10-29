//
// ContainerLookupScope.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The contained objects for which a resource answers a container lookup.
///
/// A resource always looks for the container of an object among its own objects. The scope
/// decides whether the contained object must also belong to the resource. An object of one
/// resource may contain an object of another, for example when a model is split across
/// several documents, and ``anyResource`` finds such a container from either side of the
/// split, while ``thisResource`` answers only for objects that the resource itself can
/// resolve or that their container embeds as an object value.
///
/// Native metamodel contents, such as the classifiers of a package registered with the
/// resource, are answered from their metamodel structure in either scope.
///
/// ``standard`` (also the value of ``init()``) is ``anyResource``, the scope of
/// ``Resource/container(ofIdentifier:)`` and ``ResourceSet/container(ofIdentifier:)``.
/// ``legacy`` is ``thisResource``, the behaviour of ``Resource/eContainer(of:)`` and
/// ``Resource/eContainingFeature(of:)`` as released in version 0.6, which those methods keep.
public enum ContainerLookupScope: Sendable, Hashable, CaseIterable {
    /// The contained object may belong to any resource.
    ///
    /// The container is the first object of the resource, in the order of the resource,
    /// whose containment references hold the contained object, whether by identifier or as
    /// an embedded object value.
    case anyResource

    /// The contained object must be one that this resource resolves, or one that its
    /// container embeds as an object value.
    ///
    /// A containment reference that holds the contained object by identifier counts only
    /// while the resource can resolve that identifier, so an object that belongs to another
    /// resource, or that has been removed from this one, has no container unless an object
    /// of this resource embeds it as a value. This is the behaviour of version 0.6.
    case thisResource

    /// The recommended scope, ``anyResource``.
    public static let standard = ContainerLookupScope.anyResource

    /// The scope of version 0.6, ``thisResource``.
    public static let legacy = ContainerLookupScope.thisResource

    /// Creates the recommended scope, ``standard``.
    public init() {
        self = .standard
    }
}
