//
// GenModelDerivedFeatures.swift
// GenModel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// The rules that compute the derived features of generator model objects.
///
/// The generator metamodel declares features that are not stored, such as the package that owns
/// a classifier, the classifiers of a package, and the platform flags of a model. Objects of a
/// loaded generator model do not hold values for them, so a template that navigates to one would
/// find nothing. Registering these rules in a resource set makes the features readable through
/// ``Resource/eGetComputed(objectId:feature:)``, and therefore through navigation by the
/// ``ECoreExecutionEngine``.
///
/// Loading a generator model with ``GenModelResource`` registers the rules automatically.
///
/// ## Example
///
/// ```swift
/// await GenModelDerivedFeatures.register(in: resourceSet)
/// let package = try await engine.navigate(from: genClass, property: "genPackage")
/// ```
public enum GenModelDerivedFeatures {
    /// The rules of the generator metamodel, in no particular order.
    public static let rules: [DerivedFeatureRule] = [
        DerivedFeatureRule(
            className: GenModelConstants.ClassName.genPackage,
            featureName: GenModelConstants.FeatureName.genClassifiers
        ) { object, _ in
            let features = [
                GenModelConstants.FeatureName.genClasses,
                GenModelConstants.FeatureName.genEnums,
                GenModelConstants.FeatureName.genDataTypes,
            ]
            return features.flatMap { GenModelContext.identifiers(of: object, feature: $0) }
        },
        DerivedFeatureRule(
            className: GenModelConstants.ClassName.genClassifier,
            featureName: GenModelConstants.FeatureName.genPackage
        ) { object, resource in
            await owner(of: object, kind: GenModelConstants.ClassName.genPackage, in: resource)
        },
        DerivedFeatureRule(
            className: GenModelConstants.ClassName.genPackage,
            featureName: GenModelConstants.FeatureName.genModel
        ) { object, resource in
            await owner(of: object, kind: GenModelConstants.ClassName.genModel, in: resource)
        },
        flag(
            GenModelConstants.FeatureName.richClientPlatform,
            of: GenModelConstants.FeatureName.runtimePlatform,
            holding: [
                GenModelConstants.LiteralName.richClientPlatform,
                GenModelConstants.LiteralName.richAjaxPlatform,
            ]),
        flag(
            GenModelConstants.FeatureName.richAjaxPlatform,
            of: GenModelConstants.FeatureName.runtimePlatform,
            holding: [GenModelConstants.LiteralName.richAjaxPlatform]),
        flag(
            GenModelConstants.FeatureName.reflectiveDelegation,
            of: GenModelConstants.FeatureName.featureDelegation,
            holding: [GenModelConstants.LiteralName.reflectiveDelegation]),
    ]

    /// Registers the rules of the generator metamodel.
    ///
    /// - Parameter resourceSet: The resource set whose resources hold generator model objects.
    public static func register(in resourceSet: ResourceSet) async {
        for rule in rules { await resourceSet.registerDerivedFeatureRule(rule) }
    }

    /// The identifier of the nearest container of a kind, or `nil` if there is none.
    private static func owner(of object: DynamicEObject, kind: String, in resource: Resource) async
        -> (any EcoreValue)?
    {
        var current: any EObject = object
        while let container = await resource.eContainer(of: current) {
            if let candidate = container.eClass as? EClass,
                candidate.name == kind || candidate.allSuperTypes.contains(where: { $0.name == kind })
            {
                return container.id
            }
            current = container
        }
        return nil
    }

    /// A rule for a boolean feature that is true when an enumeration attribute holds one of some literals.
    private static func flag(_ name: String, of attribute: String, holding literals: Set<String>)
        -> DerivedFeatureRule
    {
        DerivedFeatureRule(className: GenModelConstants.ClassName.genModel, featureName: name) { object, _ in
            guard let text = object.eGet(attribute) as? String else { return false }
            let eEnum = (object.eClass.getStructuralFeature(name: attribute) as? EAttribute)?.eType as? EEnum
            return literals.contains(eEnum?.storedValue(forText: text) ?? text)
        }
    }
}
