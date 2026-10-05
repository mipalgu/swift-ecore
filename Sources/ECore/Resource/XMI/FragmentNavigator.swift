//
// FragmentNavigator.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Navigates the name-based containment tree of Ecore model elements.
///
/// EMF identifies the elements of an Ecore document by the names along their
/// containment path: `#/` is the root package, `#//Book` a classifier of that
/// package, `#//Book/title` a feature of the classifier, `#//sub/Library` a
/// classifier of a nested package, `#//BookCategory/Mystery` an enumeration
/// literal, and `#//Book/borrow/days` a parameter of an operation. Elements
/// that share a name with an earlier sibling carry a trailing `.n` index.
///
/// The navigator understands both representations of Ecore models in this
/// package: native values (``EPackage``, ``EClass``, ``EEnum``,
/// ``EAttribute``, ``EReference``, ``EEnumLiteral``) reached through their
/// Swift API, and the ``DynamicEObject`` graphs that the XMI parser builds from
/// `.ecore` documents (which also contain operations and parameters).
public struct FragmentNavigator: Sendable {
    /// The resource whose objects are navigated.
    private let resource: Resource

    /// The dynamic feature names that contain named children, keyed by metaclass name.
    ///
    /// The order follows the containment order EMF uses to number duplicate names.
    private static let dynamicContainments: [String: [XMIElement]] = [
        EcoreClassifier.ePackage.rawValue: [.eClassifiers, .eSubpackages],
        EcoreClassifier.eClass.rawValue: [.eTypeParameters, .eOperations, .eStructuralFeatures],
        EcoreClassifier.eEnum.rawValue: [.eTypeParameters, .eLiterals],
        EcoreClassifier.eDataType.rawValue: [.eTypeParameters],
        EcoreClassifier.eOperation.rawValue: [.eTypeParameters, .eParameters],
    ]

    /// Creates a navigator for the objects of a resource.
    ///
    /// - Parameter resource: The resource that holds the Ecore model elements.
    public init(resource: Resource) {
        self.resource = resource
    }

    /// Resolves a name-based fragment path to an object.
    ///
    /// - Parameter fragment: A fragment such as `/`, `//Book`, or `//Book/title`,
    ///   with or without a leading `#`.
    /// - Returns: The identified object, or `nil` if no element has that path.
    public func resolve(_ fragment: String) async -> (any EObject)? {
        var path = fragment
        if path.first == CrossReferenceSyntax.fragmentSeparator { path.removeFirst() }
        let roots = await resource.getRootObjects()
        if path.isEmpty || path == CrossReferenceSyntax.rootFragment {
            return roots.first
        }
        let candidates: [any EObject]
        let remainder: Substring
        if path.hasPrefix(CrossReferenceSyntax.fragmentPathPrefix) {
            candidates = roots
            remainder = path.dropFirst(CrossReferenceSyntax.fragmentPathPrefix.count)
        } else if path.hasPrefix(String(CrossReferenceSyntax.segmentSeparator)) {
            let parts = path.dropFirst().split(separator: CrossReferenceSyntax.segmentSeparator, maxSplits: 1)
            guard let first = parts.first, let index = Int(first), roots.indices.contains(index) else { return nil }
            candidates = [roots[index]]
            remainder = parts.count > 1 ? parts[1] : ""
        } else { return nil }
        let segments = remainder.split(separator: CrossReferenceSyntax.segmentSeparator, omittingEmptySubsequences: true).map(String.init)
        for root in candidates {
            var current: any EObject = root
            var found = true
            for segment in segments {
                guard let next = await child(of: current, segment: segment) else {
                    found = false
                    break
                }
                current = next
            }
            if found { return current }
        }
        return nil
    }

    /// Computes the name-based fragment of an object.
    ///
    /// The fragment is `/` for a root object and `//` followed by the names along the
    /// containment path otherwise (omitting the root's own name).
    ///
    /// - Parameter target: The identifier of the object within the resource.
    /// - Returns: The fragment without a leading `#`, or `nil` if the object is not
    ///   reachable through named containment from a root of the resource.
    public func fragment(for target: EUUID) async -> String? {
        for root in await resource.getRootObjects() {
            if root.id == target { return CrossReferenceSyntax.rootFragment }
            if let path = await path(to: target, from: root) {
                return CrossReferenceSyntax.fragmentPathPrefix
                    + path.joined(separator: String(CrossReferenceSyntax.segmentSeparator))
            }
        }
        return nil
    }

    /// Returns the name of a named Ecore model element.
    ///
    /// - Parameter object: A native element or a dynamic Ecore element.
    /// - Returns: The element name, or `nil` if the object is not a named Ecore element.
    public static func name(of object: any EObject) -> String? {
        if let named = object as? any ENamedElement { return named.name }
        if let dynamic = object as? DynamicEObject, isEcoreMetaclass(dynamic.eClass.name) {
            return dynamic.eGet(XMIAttribute.name.rawValue) as? String
        }
        return nil
    }

    /// Returns the fragment segment name of an object.
    ///
    /// Ecore elements are named by their own names. Objects of a metaclass for which the
    /// resource set holds a ``FragmentSegmentRule`` are named by that rule.
    ///
    /// - Parameter object: The object to name.
    /// - Returns: The segment name, or `nil` if the object takes no part in name-based fragments.
    public func segmentName(of object: any EObject) async -> String? {
        if let name = Self.name(of: object) { return name }
        guard let dynamic = object as? DynamicEObject,
            let rule = await resource.resourceSet?.fragmentSegmentRule(forClass: dynamic.eClass.name)
        else { return nil }
        return await rule.segmentName(dynamic, resource)
    }

    /// Whether the name is that of an Ecore metaclass such as `EClass` or `EPackage`.
    ///
    /// - Parameter className: The metaclass name to test.
    /// - Returns: `true` for the metaclasses of the Ecore metamodel.
    public static func isEcoreMetaclass(_ className: String) -> Bool {
        EcoreClassifier(rawValue: className) != nil
    }

    // MARK: - Private Helpers

    /// Finds the child of an object that a path segment denotes.
    ///
    /// - Parameters:
    ///   - object: The containing object.
    ///   - segment: A segment: a name, or a name followed by `.n` to select the nth duplicate.
    /// - Returns: The child, or `nil` if none matches.
    private func child(of object: any EObject, segment: String) async -> (any EObject)? {
        var names: [(object: any EObject, name: String)] = []
        for candidate in await namedChildren(of: object) {
            if let name = await segmentName(of: candidate) { names.append((candidate, name)) }
        }
        if let exact = names.first(where: { $0.name == segment }) {
            return exact.object
        }
        guard let separator = segment.lastIndex(of: CrossReferenceSyntax.indexSeparator),
            let index = Int(segment[segment.index(after: separator)...]), index >= 0
        else { return nil }
        let name = String(segment[..<separator])
        let matches = names.filter { $0.name == name }
        return index < matches.count ? matches[index].object : nil
    }

    /// Searches the named containment tree below an object for a target.
    ///
    /// - Parameters:
    ///   - target: The identifier to find.
    ///   - object: The object whose descendants are searched.
    /// - Returns: The path segments from `object` to the target, or `nil` if not found.
    private func path(to target: EUUID, from object: any EObject) async -> [String]? {
        let children = await namedChildren(of: object)
        var seen: [String: Int] = [:]
        for child in children {
            guard let name = await segmentName(of: child) else { continue }
            let occurrence = seen[name, default: 0]
            seen[name] = occurrence + 1
            let segment = occurrence == 0 ? name : name + String(CrossReferenceSyntax.indexSeparator) + String(occurrence)
            if child.id == target { return [segment] }
            if let rest = await path(to: target, from: child) { return [segment] + rest }
        }
        return nil
    }

    /// Lists the named children of an Ecore element in containment order.
    ///
    /// - Parameter object: The containing element.
    /// - Returns: The children that take part in name-based fragments.
    private func namedChildren(of object: any EObject) async -> [any EObject] {
        switch object {
        case let package as EPackage:
            let classifiers = package.eClassifiers.compactMap { $0 as? any EObject }
            return classifiers + package.eSubpackages.map { $0 as any EObject }
        case let eClass as EClass:
            let parameters = eClass.eTypeParameters.map { $0 as any EObject }
            let operations = eClass.eOperations.map { $0 as any EObject }
            let features = eClass.eStructuralFeatures.compactMap { $0 as? any EObject }
            return parameters + operations + features
        case let operation as EOperation:
            return operation.eTypeParameters.map { $0 as any EObject }
                + operation.eParameters.map { $0 as any EObject }
        case let eEnum as EEnum:
            return eEnum.eTypeParameters.map { $0 as any EObject } + eEnum.literals.map { $0 as any EObject }
        case let dataType as EDataType:
            return dataType.eTypeParameters.map { $0 as any EObject }
        case let dynamic as DynamicEObject:
            guard let containments = Self.dynamicContainments[dynamic.eClass.name] else {
                return await containedChildren(of: dynamic)
            }
            var children: [any EObject] = []
            for containment in containments {
                switch dynamic.eGet(containment.rawValue) {
                case let id as EUUID:
                    if let child = await resource.resolve(id) { children.append(child) }
                case let ids as [EUUID]:
                    for id in ids {
                        if let child = await resource.resolve(id) { children.append(child) }
                    }
                default:
                    break
                }
            }
            return children
        default:
            return []
        }
    }

    /// Lists the objects contained in a dynamic object that is not an Ecore element.
    ///
    /// - Parameter object: The containing object.
    /// - Returns: The contained objects, in the order of the containment references.
    private func containedChildren(of object: DynamicEObject) async -> [any EObject] {
        var children: [any EObject] = []
        for reference in (object.eClass as? EClass)?.allReferences ?? [] where reference.containment {
            switch object.eGet(reference.name) {
            case let id as EUUID:
                if let child = await resource.resolve(id) { children.append(child) }
            case let ids as [EUUID]:
                for id in ids {
                    if let child = await resource.resolve(id) { children.append(child) }
                }
            default:
                break
            }
        }
        return children
    }
}
