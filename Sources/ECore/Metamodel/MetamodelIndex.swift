//
// MetamodelIndex.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// A place where one element refers to another.
public struct EcoreUsage: Sendable, Hashable {
    /// The identifier of the element that holds the reference.
    public let referrer: EUUID

    /// The feature of the referrer that holds the reference: `eSuperTypes`, `eType`,
    /// `eOpposite`, `eExceptions`, or `references`.
    public let feature: EcoreFeatureName

    /// The zero-based position within a many-valued feature, and zero for a single-valued one.
    public let position: Int

    /// Creates a usage.
    ///
    /// - Parameters:
    ///   - referrer: The identifier of the element that holds the reference.
    ///   - feature: The feature of the referrer that holds the reference.
    ///   - position: The position within the feature.
    public init(referrer: EUUID, feature: EcoreFeatureName, position: Int = 0) {
        self.referrer = referrer
        self.feature = feature
        self.position = position
    }
}

/// An index over the elements of native metamodels.
///
/// Native metamodel types are values, and a reference to a class (a supertype or the type of a
/// feature) is a snapshot that becomes stale when the class is edited. The index therefore
/// identifies every element by its identifier and answers questions about the canonical
/// elements, which are those found by walking the containment tree of the root packages:
/// what an identifier denotes, what contains it, what it contains, how it is addressed in a
/// document, what refers to it, and what inherits from it.
///
/// An index is immutable. After editing the roots, build a new index from the edited roots.
/// Building takes time proportional to the number of elements.
public struct MetamodelIndex: Sendable {
    /// Everything recorded about one element.
    private struct Entry: Sendable {
        /// The element.
        let element: EcoreElement

        /// The position of the element in its container, or `nil` for a root.
        let containment: EcoreContainment?

        /// The fragment of the element within its document.
        let fragment: String

        /// The identifier of the root package that contains the element.
        let root: EUUID

        /// The position of the element in document order.
        let order: Int

        /// Whether the element belongs to an external package.
        let isExternal: Bool

        /// The identifiers of the contained elements, in containment order.
        var children: [EUUID]
    }

    /// The root packages that the index describes.
    public let roots: [EPackage]

    /// The packages that the roots refer to, which are indexed for lookup only.
    public let externals: [EPackage]

    /// Every element of the roots (but not of the externals) in document order.
    ///
    /// Each package is followed by its annotations, classifiers, and subpackages, and each
    /// element by everything it contains.
    public private(set) var allElements: [EcoreElement] = []

    private var entries: [EUUID: Entry] = [:]
    private var usageMap: [EUUID: [EcoreUsage]] = [:]

    /// Builds an index.
    ///
    /// - Parameters:
    ///   - roots: The root packages whose elements the index describes.
    ///   - externals: Packages that the roots refer to. Their elements can be looked up,
    ///     located, and addressed, but they are not part of ``allElements`` and their
    ///     references are not recorded as usages.
    public init(roots: [EPackage], externals: [EPackage] = []) {
        self.roots = roots
        self.externals = externals
        entries.reserveCapacity(1024)
        for root in roots { add(root, isExternal: false) }
        for root in externals { add(root, isExternal: true) }
    }

    // MARK: Building

    /// Records a root package and everything below it.
    private mutating func add(_ root: EPackage, isExternal: Bool) {
        guard entries[root.id] == nil else { return }
        record(
            .package(root), containment: nil, root: root.id,
            fragment: CrossReferenceSyntax.rootFragment, isExternal: isExternal)
    }

    /// Records an element, then everything it contains.
    private mutating func record(
        _ element: EcoreElement, containment: EcoreContainment?, root: EUUID,
        fragment: String, isExternal: Bool
    ) {
        let identifier = element.id
        guard entries[identifier] == nil else { return }
        let order = allElements.count
        if !isExternal {
            allElements.append(element)
            recordUsages(of: element)
        }
        entries[identifier] = Entry(
            element: element, containment: containment, fragment: fragment,
            root: root, order: order, isExternal: isExternal, children: [])
        let contents = element.children
        let segments = EcoreFragment.segments(of: contents)
        var children: [EUUID] = []
        children.reserveCapacity(contents.count)
        for (child, segment) in zip(contents, segments) {
            guard entries[child.element.id] == nil else { continue }
            children.append(child.element.id)
            record(
                child.element,
                containment: EcoreContainment(container: identifier, feature: child.feature, index: child.index),
                root: root, fragment: fragment + String(CrossReferenceSyntax.segmentSeparator) + segment,
                isExternal: isExternal)
        }
        entries[identifier]?.children = children
    }

    /// Records the references that an element holds.
    private mutating func recordUsages(of element: EcoreElement) {
        let referrer = element.id
        func note(_ target: EUUID, _ feature: EcoreFeatureName, _ position: Int = 0) {
            usageMap[target, default: []].append(
                EcoreUsage(referrer: referrer, feature: feature, position: position))
        }
        func noteGeneric(_ type: EGenericType, classifier: Bool = false) {
            if classifier, let target = type.eClassifier { note(target.id, .eClassifier) }
            if let parameter = type.eTypeParameter { note(parameter, .eTypeParameter) }
            for argument in type.eTypeArguments { noteGeneric(argument, classifier: true) }
            if let bound = type.eUpperBound { noteGeneric(bound, classifier: true) }
            if let bound = type.eLowerBound { noteGeneric(bound, classifier: true) }
        }
        switch element {
        case .eClass(let value):
            for (position, supertype) in value.eSuperTypes.enumerated() {
                note(supertype.id, .eSuperTypes, position)
            }
            for type in value.eGenericSuperTypes { noteGeneric(type) }
        case .attribute(let value):
            note(value.eType.id, .eType)
            if let type = value.eGenericType { noteGeneric(type) }
        case .reference(let value):
            note(value.eType.id, .eType)
            if let opposite = value.opposite { note(opposite, .eOpposite) }
            for (position, key) in value.eKeys.enumerated() { note(key, .eKeys, position) }
            if let type = value.eGenericType { noteGeneric(type) }
        case .operation(let value):
            if let type = value.eType { note(type.id, .eType) }
            for (position, exception) in value.eExceptions.enumerated() {
                note(exception.id, .eExceptions, position)
            }
            if let type = value.eGenericType { noteGeneric(type) }
            for type in value.eGenericExceptions { noteGeneric(type) }
        case .parameter(let value):
            if let type = value.eType { note(type.id, .eType) }
            if let type = value.eGenericType { noteGeneric(type) }
        case .typeParameter(let value):
            for bound in value.eBounds { noteGeneric(bound, classifier: true) }
        case .annotation(let value):
            for (position, reference) in value.references.enumerated() {
                if case .local(let target) = reference { note(target, .references, position) }
            }
        case .package, .dataType, .eEnum, .literal, .detail:
            break
        }

    }

    // MARK: Elements

    /// Whether the index knows an identifier.
    ///
    /// - Parameter identifier: The identifier to look up.
    /// - Returns: `true` for an element of the roots or externals.
    public func contains(_ identifier: EUUID) -> Bool { entries[identifier] != nil }

    /// The element with an identifier.
    ///
    /// - Parameter identifier: The identifier to look up.
    /// - Returns: The canonical element, or `nil` if the roots and externals hold no such element.
    public func element(_ identifier: EUUID) -> EcoreElement? { entries[identifier]?.element }

    /// Whether an element belongs to one of the external packages.
    ///
    /// - Parameter identifier: The identifier of the element.
    /// - Returns: `true` for an external element; `false` for any other, or unknown, identifier.
    public func isExternal(_ identifier: EUUID) -> Bool { entries[identifier]?.isExternal ?? false }

    /// The position of an element within its container.
    ///
    /// - Parameter identifier: The identifier of the element.
    /// - Returns: The container, feature, and index; `nil` for a root package and for an
    ///   unknown identifier.
    public func container(of identifier: EUUID) -> EcoreContainment? { entries[identifier]?.containment }

    /// The elements contained by an element, in containment order.
    ///
    /// - Parameter identifier: The identifier of the containing element.
    /// - Returns: The children; empty for an unknown identifier.
    public func children(of identifier: EUUID) -> [EcoreElement] {
        (entries[identifier]?.children ?? []).compactMap { entries[$0]?.element }
    }

    /// The elements that an element holds in one containment feature.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the containing element.
    ///   - feature: The containment feature, such as `eStructuralFeatures`.
    /// - Returns: The children of that feature, in order.
    public func children(of identifier: EUUID, feature: EcoreFeatureName) -> [EcoreElement] {
        (entries[identifier]?.children ?? []).compactMap { child in
            guard let entry = entries[child], entry.containment?.feature == feature else { return nil }
            return entry.element
        }
    }

    /// The root package that contains an element.
    ///
    /// - Parameter identifier: The identifier of the element.
    /// - Returns: The identifier of the root package, which is the element itself for a root.
    public func root(of identifier: EUUID) -> EUUID? { entries[identifier]?.root }

    /// The containing elements of an element, nearest first.
    ///
    /// - Parameter identifier: The identifier of the element.
    /// - Returns: The identifiers from the container up to the root.
    public func ancestors(of identifier: EUUID) -> [EUUID] {
        var result: [EUUID] = []
        var current = entries[identifier]?.containment?.container
        while let next = current, result.count <= entries.count {
            result.append(next)
            current = entries[next]?.containment?.container
        }
        return result
    }

    // MARK: Fragments

    /// The fragment that addresses an element within its document.
    ///
    /// The fragment is relative to the root package that contains the element, as for a
    /// document with a single root (see ``EcoreFragment``).
    ///
    /// - Parameter identifier: The identifier of the element.
    /// - Returns: The fragment without a leading `#`, or `nil` for an unknown identifier.
    public func fragment(of identifier: EUUID) -> String? { entries[identifier]?.fragment }

    /// Finds the element that a fragment addresses.
    ///
    /// - Parameters:
    ///   - fragment: A fragment such as `//Book/title`, with or without a leading `#`.
    ///   - root: The identifier of the root package whose document the fragment belongs to,
    ///     or `nil` to try each root in turn.
    /// - Returns: The element, or `nil` if no element has that fragment.
    public func resolve(fragment: String, in root: EUUID? = nil) -> EcoreElement? {
        let candidates = root.map { identifier in roots.filter { $0.id == identifier } + externals.filter { $0.id == identifier } }
            ?? roots
        for candidate in candidates {
            if let found = EcoreFragment.resolve(fragment, in: [candidate]) { return found }
        }
        return nil
    }

    // MARK: References

    /// The places that refer to an element.
    ///
    /// Supertypes, types of features, operations, and parameters, opposite references,
    /// exceptions, and annotation references are covered, as held by the elements of the roots.
    /// A reference counts by the identifier of its target, so stale snapshots are still found.
    ///
    /// - Parameter identifier: The identifier of the referenced element.
    /// - Returns: The usages in document order of the referrers.
    public func usages(of identifier: EUUID) -> [EcoreUsage] { usageMap[identifier] ?? [] }

    /// The classes that inherit from a class.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the class.
    ///   - concreteOnly: Whether abstract classes and interfaces are left out (default `false`).
    ///   - transitive: Whether subclasses of subclasses are included (default `true`).
    /// - Returns: The canonical subclasses, in document order, without the class itself.
    public func subclasses(
        of identifier: EUUID, concreteOnly: Bool = false, transitive: Bool = true
    ) -> [EClass] {
        var found: Set<EUUID> = []
        var pending = [identifier]
        while let current = pending.popLast() {
            for usage in usageMap[current] ?? [] where usage.feature == .eSuperTypes {
                if usage.referrer != identifier, found.insert(usage.referrer).inserted, transitive {
                    pending.append(usage.referrer)
                }
            }
        }
        return found.compactMap { entries[$0] }
            .sorted { $0.order < $1.order }
            .compactMap { entry -> EClass? in
                guard case .eClass(let value) = entry.element else { return nil }
                return concreteOnly && (value.isAbstract || value.isInterface) ? nil : value
            }
    }
}
