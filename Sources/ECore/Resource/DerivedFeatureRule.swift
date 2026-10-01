//
// DerivedFeatureRule.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// A rule that computes the value of a derived feature of dynamic objects on demand.
///
/// Objects of dynamic classes do not store derived features, so a plain reflective read of
/// one yields nothing. A package that knows how a derived feature is computed registers a rule
/// with ``ResourceSet/registerDerivedFeatureRule(_:)``. Reads that go through
/// ``Resource/eGetComputed(objectId:feature:)``, which includes navigation by the
/// ``ECoreExecutionEngine``, then return the computed value.
///
/// A rule applies to objects of the named class and of its subclasses. If rules exist for both a
/// class and one of its superclasses, the rule of the most specific class is used.
///
/// ## Example
///
/// ```swift
/// await resourceSet.registerDerivedFeatureRule(
///     DerivedFeatureRule(className: "Shelf", featureName: "allBooks") { shelf, _ in
///         shelf.eGet("books")
///     })
/// ```
public struct DerivedFeatureRule: Sendable {
    /// The name of the class whose objects, and those of its subclasses, the rule computes for.
    public let className: String

    /// The name of the derived feature that the rule computes.
    public let featureName: String

    /// Computes the value of the feature.
    ///
    /// The closure receives the object and the resource that holds it. It returns the value in
    /// the form that the feature stores: an identifier for a single-valued reference, an array of
    /// identifiers for a many-valued one, or the attribute value. It returns `nil` if the feature
    /// has no value for the object.
    public let evaluate: @Sendable (_ object: DynamicEObject, _ resource: Resource) async -> (any EcoreValue)?

    /// Creates a rule.
    ///
    /// - Parameters:
    ///   - className: The name of the class whose objects the rule computes for.
    ///   - featureName: The name of the derived feature.
    ///   - evaluate: The closure that computes the value.
    public init(
        className: String,
        featureName: String,
        evaluate: @escaping @Sendable (_ object: DynamicEObject, _ resource: Resource) async -> (any EcoreValue)?
    ) {
        self.className = className
        self.featureName = featureName
        self.evaluate = evaluate
    }
}

extension ResourceSet {
    /// Registers a rule that computes a derived feature.
    ///
    /// A rule registered for the same class and feature as an earlier rule replaces it.
    ///
    /// - Parameter rule: The rule to register.
    public func registerDerivedFeatureRule(_ rule: DerivedFeatureRule) {
        derivedFeatureRules[DerivedFeatureKey(className: rule.className, featureName: rule.featureName)] = rule
    }

    /// Finds the rule that computes a feature for objects of a class.
    ///
    /// - Parameters:
    ///   - eClass: The class of the object being read.
    ///   - featureName: The name of the feature.
    /// - Returns: The rule of the most specific class that has one, or `nil` if there is none.
    public func derivedFeatureRule(for eClass: EClass, featureName: String) -> DerivedFeatureRule? {
        if let rule = derivedFeatureRules[DerivedFeatureKey(className: eClass.name, featureName: featureName)] {
            return rule
        }
        for superType in eClass.allSuperTypes {
            if let rule = derivedFeatureRules[
                DerivedFeatureKey(className: superType.name, featureName: featureName)]
            {
                return rule
            }
        }
        return nil
    }
}

/// The key under which a derived feature rule is registered.
struct DerivedFeatureKey: Hashable, Sendable {
    let className: String
    let featureName: String
}

extension Resource {
    /// Reads a feature, computing it if it is derived.
    ///
    /// The value is, in order of preference, the value computed by the ``DerivedFeatureRule``
    /// registered in the resource set for the object's class, the stored value, or, for an unset
    /// transient reference whose opposite is a containment reference, the object's container.
    /// Defaults are not applied (see ``DynamicEObject/eGetWithDefault(_:)-(String)``).
    ///
    /// - Parameters:
    ///   - objectId: The identifier of the object to read.
    ///   - featureName: The name of the feature to read.
    /// - Returns: The value, in stored form, or `nil` if the object is unknown or the feature
    ///   has no value.
    public func eGetComputed(objectId: EUUID, feature featureName: String) async -> (any EcoreValue)? {
        guard let object = resolve(objectId) as? DynamicEObject else { return nil }
        if let resourceSet, let eClass = object.eClass as? EClass,
            let rule = await resourceSet.derivedFeatureRule(for: eClass, featureName: featureName)
        {
            return await rule.evaluate(object, self)
        }
        if let stored = object.eGet(featureName) { return stored }
        return containerValue(of: object, feature: featureName)
    }

    private func containerValue(of object: DynamicEObject, feature featureName: String) -> (any EcoreValue)? {
        guard let reference = object.eClass.getStructuralFeature(name: featureName) as? EReference,
            reference.transient, !reference.isMany, !reference.containment,
            let opposite = resolveOpposite(reference), opposite.containment,
            let container = eContainer(of: object),
            let containing = eContainingFeature(of: object), containing.name == opposite.name
        else { return nil }
        return container.id
    }
}
