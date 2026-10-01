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
/// A generator package is identified in a fragment by the name of the Ecore package it
/// describes, so that `Ecore.genmodel#//ecore` refers to the generator package whose
/// Ecore package is named `ecore`. This is what `usedGenPackages` references rely on.
///
/// ## Example
///
/// ```swift
/// await GenModelFragments.register(in: resourceSet)
/// ```
public enum GenModelFragments {
    /// The rule that names a generator package after its Ecore package.
    public static let genPackageRule = FragmentSegmentRule(
        className: GenModelConstants.ClassName.genPackage
    ) { object, resource in
        await ecorePackageName(of: object, in: resource)
    }

    /// Registers the generator metamodel's fragment rules in a resource set.
    ///
    /// Call this before loading or saving generator model documents in the set, so that
    /// fragments such as `#//library` resolve and are written correctly.
    ///
    /// - Parameter resourceSet: The resource set to register the rules in.
    public static func register(in resourceSet: ResourceSet) async {
        await resourceSet.registerFragmentSegmentRule(genPackageRule)
    }

    /// Finds the name of the Ecore package that a generator package describes.
    ///
    /// - Parameters:
    ///   - object: The generator package.
    ///   - resource: The resource that holds the generator package.
    /// - Returns: The name of the Ecore package, or `nil` if the reference is unset, textual
    ///   or cannot be resolved.
    private static func ecorePackageName(of object: DynamicEObject, in resource: Resource) async
        -> String?
    {
        let resourceSet = await resource.resourceSet
        let target: (any EObject)?
        switch object.eGet(GenModelConstants.FeatureName.ecorePackage) {
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
