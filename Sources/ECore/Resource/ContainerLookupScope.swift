//
// ContainerLookupScope.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Synchronization

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
/// ``Resource/container(ofIdentifier:scope:)`` and
/// ``ResourceSet/container(ofIdentifier:scope:)`` when no scope is configured.
/// ``legacy`` is ``thisResource``, the behaviour of ``Resource/eContainer(of:scope:)`` and
/// ``Resource/eContainingFeature(of:scope:)`` as released in version 0.6.
///
/// Those two methods use the scope configured for the resource when they are not given one:
/// the scope set with ``Resource/setContainerLookupScope(_:)``, else the default of the
/// resource's ``ResourceSet`` (see ``ResourceSet/setDefaultContainerLookupScope(_:)``), else
/// ``builtInDefault``, which is ``legacy`` so that they behave as in version 0.6.
///
/// The raw value of each case is its lower-case, hyphenated command-line spelling, so that a
/// tool can parse a scope with ``init(rawValue:)`` and list the accepted spellings through
/// `allCases`.
public enum ContainerLookupScope: String, Sendable, Hashable, CaseIterable {
    /// The contained object may belong to any resource.
    ///
    /// The container is the first object of the resource, in the order of the resource,
    /// whose containment references hold the contained object, whether by identifier or as
    /// an embedded object value.
    case anyResource = "any-resource"

    /// The contained object must be one that this resource resolves, or one that its
    /// container embeds as an object value.
    ///
    /// A containment reference that holds the contained object by identifier counts only
    /// while the resource can resolve that identifier, so an object that belongs to another
    /// resource, or that has been removed from this one, has no container unless an object
    /// of this resource embeds it as a value. This is the behaviour of version 0.6.
    case thisResource = "this-resource"

    /// The recommended scope, ``anyResource``.
    public static let standard = ContainerLookupScope.anyResource

    /// The scope of version 0.6, ``thisResource``.
    public static let legacy = ContainerLookupScope.thisResource

    /// The scope of a resource for which no scope has been configured, ``legacy``.
    ///
    /// A resource uses this scope when neither the resource nor its resource set configures
    /// one, so that ``Resource/eContainer(of:scope:)`` and
    /// ``Resource/eContainingFeature(of:scope:)`` behave as in version 0.6 unless asked
    /// otherwise.
    public static let builtInDefault = ContainerLookupScope.legacy

    /// Creates the recommended scope, ``standard``.
    public init() {
        self = .standard
    }

    /// Creates the scope that a choice of semantics selects.
    ///
    /// ``ModellingSemantics/standard`` selects ``standard`` (``anyResource``) and
    /// ``ModellingSemantics/legacy`` selects ``legacy`` (``thisResource``).
    ///
    /// - Parameter semantics: The semantics to follow.
    public init(semantics: ModellingSemantics) {
        switch semantics {
        case .standard: self = .standard
        case .legacy: self = .legacy
        }
    }
}

/// A container lookup scope that a resource set shares with its resources.
///
/// A resource reads the default of its set synchronously, while the set is a separate actor,
/// so the set keeps its default in this lock-protected value and hands it to its resources.
final class ContainerLookupDefault: Sendable {
    /// The configured scope, or `nil` if none is configured.
    private let storage: Mutex<ContainerLookupScope?>

    /// Creates a shared default.
    ///
    /// - Parameter scope: The configured scope, or `nil` for none.
    init(_ scope: ContainerLookupScope?) {
        storage = Mutex(scope)
    }

    /// The configured scope, or `nil` if none is configured.
    var scope: ContainerLookupScope? {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}
