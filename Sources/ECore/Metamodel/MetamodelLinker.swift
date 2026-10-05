//
// MetamodelLinker.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Refreshes the class snapshots that native metamodel elements hold.
///
/// Native classes are value types, so a supertype or the type of a feature is a snapshot of
/// the class it names, taken when the metamodel was built. Editing a class (renaming it,
/// adding a feature, changing its supertypes, or removing it) leaves every snapshot of it
/// stale. The linker rebuilds the snapshots from the canonical elements, which are those found
/// by walking the containment tree of the packages, and matches them to snapshots by
/// identifier. Nothing else changes: identifiers, containment, order, and every other
/// property of every element are kept.
public enum MetamodelLinker {
    /// The number of reference hops that a snapshot reproduces accurately.
    ///
    /// A snapshot records the features of its class, whose types are snapshots in turn; each
    /// further level is one hop shallower than the one before, and the deepest level records
    /// classes without features.
    static let snapshotDepth = 4

    /// Rebuilds the supertype and type snapshots of packages from the canonical elements.
    ///
    /// Classifiers are found in the packages and their subpackages. A snapshot of a classifier
    /// that is not found there is looked up by identifier in the built-in classifiers of Ecore
    /// and in the classifiers of the `externals`; if it is found nowhere, the snapshot is kept
    /// as it is.
    ///
    /// - Parameters:
    ///   - roots: The root packages whose snapshots are refreshed.
    ///   - externals: Packages whose classifiers the roots refer to but do not contain.
    /// - Returns: The packages in the same order, with refreshed snapshots.
    public static func relinked(_ roots: [EPackage], externals: [EPackage] = []) -> [EPackage] {
        var classifiers: [EUUID: any EClassifier] = [:]
        for package in externals { collectClassifiers(of: package, into: &classifiers) }
        return relinked(roots, externalClassifiers: classifiers)
    }

    /// Rebuilds snapshots, with external classifiers given by identifier.
    ///
    /// - Parameters:
    ///   - roots: The root packages whose snapshots are refreshed.
    ///   - externalClassifiers: The classifiers that the roots refer to but do not contain.
    /// - Returns: The packages in the same order, with refreshed snapshots.
    static func relinked(
        _ roots: [EPackage], externalClassifiers: [EUUID: any EClassifier]
    ) -> [EPackage] {
        var classes: [EClass] = []
        var dataTypes: [EUUID: any EClassifier] = [:]
        for root in roots { collect(root, classes: &classes, dataTypes: &dataTypes) }
        let linked = SnapshotLinker(
            classes: classes, dataTypes: dataTypes, externals: externalClassifiers
        ).link()
        return roots.map { replacingClasses(in: $0, with: linked) }
    }

    /// Lists the classes of a package tree in document order and collects the other classifiers.
    ///
    /// The classifiers of a package precede those of its subpackages.
    static func collect(
        _ package: EPackage, classes: inout [EClass], dataTypes: inout [EUUID: any EClassifier]
    ) {
        for classifier in package.eClassifiers {
            if let eClass = classifier as? EClass {
                classes.append(eClass)
            } else {
                dataTypes[classifier.id] = classifier
            }
        }
        for subpackage in package.eSubpackages {
            collect(subpackage, classes: &classes, dataTypes: &dataTypes)
        }
    }

    /// Collects every classifier of a package tree by identifier.
    private static func collectClassifiers(of package: EPackage, into result: inout [EUUID: any EClassifier]) {
        for classifier in package.eClassifiers { result[classifier.id] = classifier }
        for subpackage in package.eSubpackages { collectClassifiers(of: subpackage, into: &result) }
    }

    /// Replaces the classes of a package tree by their linked versions.
    static func replacingClasses(in package: EPackage, with linked: [EUUID: EClass]) -> EPackage {
        var result = package
        result.eClassifiers = package.eClassifiers.map { classifier in
            (classifier as? EClass).flatMap { linked[$0.id] } ?? classifier
        }
        result.eSubpackages = package.eSubpackages.map { replacingClasses(in: $0, with: linked) }
        return result
    }
}

/// The snapshot-building algorithm that the converter and the linker share.
struct SnapshotLinker {
    /// The canonical classes, in document order.
    let classes: [EClass]

    /// The canonical enumerations and data types, by identifier.
    let dataTypes: [EUUID: any EClassifier]

    /// The classifiers of other documents, by identifier.
    let externals: [EUUID: any EClassifier]

    /// The identifier that each snapshot refers to when it is not its own, by the identifier
    /// of the snapshot.
    var renames: [EUUID: EUUID] = [:]

    /// Builds the snapshots of every class.
    ///
    /// Classes are built in several passes. Supertypes are built before their subtypes within
    /// a pass, so that inherited features are always available; the type of each feature is
    /// the snapshot of the previous pass.
    ///
    /// - Returns: The linked class for each class identifier.
    func link() -> [EUUID: EClass] {
        var canonical: [EUUID: EClass] = [:]
        var current: [EUUID: EClass] = [:]
        for eClass in classes where canonical[eClass.id] == nil {
            canonical[eClass.id] = eClass
            var bare = eClass
            bare.eSuperTypes = []
            bare.eGenericSuperTypes = []
            bare.eTypeParameters = []
            bare.eStructuralFeatures = []
            bare.eOperations = []
            current[eClass.id] = bare
        }
        let order = supertypesFirst(canonical)
        for _ in 0..<MetamodelLinker.snapshotDepth {
            var built: [EUUID: EClass] = [:]
            for identifier in order {
                guard let source = canonical[identifier], var result = current[identifier] else { continue }
                result.eSuperTypes = source.eSuperTypes.map {
                    supertype($0, previous: current, built: built)
                }
                result.eGenericSuperTypes = source.eGenericSuperTypes.map {
                    generic($0, previous: current)
                }
                result.eTypeParameters = source.eTypeParameters.map {
                    typeParameter($0, previous: current)
                }
                result.eStructuralFeatures = source.eStructuralFeatures.map {
                    feature($0, previous: current)
                }
                result.eOperations = source.eOperations.map { operation($0, previous: current) }
                built[identifier] = result
            }
            for (identifier, result) in built { current[identifier] = result }
        }
        return current
    }

    /// Orders the classes so that every class follows its supertypes.
    private func supertypesFirst(_ canonical: [EUUID: EClass]) -> [EUUID] {
        var ordered: [EUUID] = []
        var state: [EUUID: Bool] = [:]  // false while being visited, true once placed
        func place(_ eClass: EClass) {
            if state[eClass.id] != nil { return }
            state[eClass.id] = false
            for parent in eClass.eSuperTypes {
                if let source = canonical[target(parent.id)] { place(source) }
            }
            state[eClass.id] = true
            ordered.append(eClass.id)
        }
        for eClass in classes { place(eClass) }
        return ordered
    }

    /// The identifier of the element that a snapshot stands for.
    private func target(_ identifier: EUUID) -> EUUID { renames[identifier] ?? identifier }

    /// The refreshed snapshot of a supertype.
    private func supertype(_ stale: EClass, previous: [EUUID: EClass], built: [EUUID: EClass]) -> EClass {
        let identifier = target(stale.id)
        return built[identifier] ?? previous[identifier]
            ?? (EcorePackage.classifier(id: identifier) as? EClass)
            ?? (externals[identifier] as? EClass) ?? stale
    }

    /// The refreshed snapshot of a classifier that a feature, operation, or parameter names.
    func classifier(_ stale: any EClassifier, previous: [EUUID: EClass]) -> any EClassifier {
        let identifier = target(stale.id)
        return dataTypes[identifier] ?? previous[identifier] ?? EcorePackage.classifier(id: identifier)
            ?? externals[identifier] ?? stale
    }

    /// The feature with its type refreshed.
    func feature(_ feature: any EStructuralFeature, previous: [EUUID: EClass])
        -> any EStructuralFeature
    {
        switch feature {
        case var attribute as EAttribute:
            attribute.eType = classifier(attribute.eType, previous: previous)
            attribute.eGenericType = attribute.eGenericType.map { generic($0, previous: previous) }
            return attribute
        case var reference as EReference:
            reference.eType = classifier(reference.eType, previous: previous)
            reference.eGenericType = reference.eGenericType.map { generic($0, previous: previous) }
            reference.eKeys = reference.eKeys.map(target)
            return reference
        default:
            return feature
        }
    }

    /// The operation with its types and exceptions refreshed.
    func operation(_ operation: EOperation, previous: [EUUID: EClass]) -> EOperation {
        var result = operation
        result.eType = operation.eType.map { classifier($0, previous: previous) }
        result.eGenericType = operation.eGenericType.map { generic($0, previous: previous) }
        result.eTypeParameters = operation.eTypeParameters.map { typeParameter($0, previous: previous) }
        result.eParameters = operation.eParameters.map { parameter($0, previous: previous) }
        result.eExceptions = operation.eExceptions.map { classifier($0, previous: previous) }
        result.eGenericExceptions = operation.eGenericExceptions.map { generic($0, previous: previous) }
        return result
    }

    /// Refreshes the type and generic type of a parameter.
    func parameter(_ parameter: EParameter, previous: [EUUID: EClass]) -> EParameter {
        var refreshed = parameter
        refreshed.eType = parameter.eType.map { classifier($0, previous: previous) }
        refreshed.eGenericType = parameter.eGenericType.map { generic($0, previous: previous) }
        return refreshed
    }

    /// Refreshes the classifier snapshots in a generic type, including its arguments and bounds.
    func generic(_ type: EGenericType, previous: [EUUID: EClass]) -> EGenericType {
        var result = type
        result.eClassifier = type.eClassifier.map { classifier($0, previous: previous) }
        result.eTypeParameter = type.eTypeParameter.map(target)
        result.eTypeArguments = type.eTypeArguments.map { generic($0, previous: previous) }
        result.eUpperBound = type.eUpperBound.map { generic($0, previous: previous) }
        result.eLowerBound = type.eLowerBound.map { generic($0, previous: previous) }
        return result
    }

    /// Refreshes the classifier snapshots in the bounds of a type parameter.
    func typeParameter(_ parameter: ETypeParameter, previous: [EUUID: EClass]) -> ETypeParameter {
        var result = parameter
        result.eBounds = parameter.eBounds.map { generic($0, previous: previous) }
        return result
    }
}
