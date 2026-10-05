//
// GenModelFragments.swift
// GenModel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// The name-based fragment rules of the generator metamodel.
///
/// A generator element is identified in a fragment by the name of the Ecore element it
/// describes, so that `Ecore.genmodel#//ecore` refers to the generator package whose
/// Ecore package is named `ecore`, and `#//library/Book/title` to the generator feature
/// of the `title` feature of the class `Book` in the package `library`. This is what
/// `usedGenPackages` and `labelFeature` references rely on.
///
/// ## Example
///
/// ```swift
/// await GenModelFragments.register(in: resourceSet)
/// ```
public enum GenModelFragments {
    /// The rule that names a generator package after its Ecore package.
    public static let genPackageRule = rule(
        className: GenModelConstants.ClassName.genPackage,
        feature: GenModelConstants.FeatureName.ecorePackage)

    /// The rules that name each kind of generator element after its Ecore element.
    public static let rules: [FragmentSegmentRule] =
        GenModelConstants.FeatureName.ecoreReferenceByClass.map {
            rule(className: $0.className, feature: $0.feature)
        }

    private static func rule(className: String, feature: String) -> FragmentSegmentRule {
        FragmentSegmentRule(className: className) { object, resource in
            await ecoreElementName(of: object, feature: feature, in: resource)
        }
    }

    /// Registers the generator metamodel's fragment rules in a resource set.
    ///
    /// Call this before loading or saving generator model documents in the set, so that
    /// fragments such as `#//library` resolve and are written correctly.
    ///
    /// - Parameter resourceSet: The resource set to register the rules in.
    public static func register(in resourceSet: ResourceSet) async {
        for rule in rules { await resourceSet.registerFragmentSegmentRule(rule) }
    }

    /// Finds the name of the Ecore element that a generator element describes.
    ///
    /// - Parameters:
    ///   - object: The generator element.
    ///   - feature: The name of the reference that holds the Ecore element.
    ///   - resource: The resource that holds the generator element.
    /// - Returns: The name of the Ecore element, or `nil` if the reference is unset, textual
    ///   or cannot be resolved.
    private static func ecoreElementName(
        of object: DynamicEObject, feature: String, in resource: Resource
    ) async
        -> String?
    {
        let resourceSet = await resource.resourceSet
        let target: (any EObject)?
        switch object.eGet(feature) {
        case let id as EUUID:
            if let local = await resource.resolve(id) {
                target = local
            } else if let resourceSet {
                target = await resourceSet.resolve(id)?.object
            } else {
                target = nil
            }
        case let proxy as ResourceProxy:
            if let resourceSet {
                target = await proxy.resolveObject(in: resourceSet)
            } else {
                target = nil
            }
        default:
            target = nil
        }
        return target.flatMap { FragmentNavigator.name(of: $0) }
    }
}
