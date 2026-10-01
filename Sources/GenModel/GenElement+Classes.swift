//
// GenElement+Classes.swift
// GenModel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore

extension GenElement {
    /// Whether the Ecore class of a generator class is an interface.
    public var isInterface: Bool { ecoreClass?.isInterface ?? false }

    /// Whether the Ecore class of a generator class is abstract or an interface.
    public var isAbstract: Bool {
        guard let eClass = ecoreClass else { return false }
        return eClass.isAbstract || eClass.isInterface
    }

    /// The generator classes of the direct supertypes, in declaration order.
    ///
    /// Supertypes without a generator class in the context are omitted.
    public var baseGenClasses: [GenElement] {
        guard let eClass = ecoreClass else { return [] }
        return eClass.eSuperTypes.compactMap { context.genClass(forEcoreClass: $0.id) }
    }

    /// The generator classes of all transitive supertypes, ancestors first.
    ///
    /// For each direct supertype in declaration order, its own supertypes precede it.
    /// Each class appears once. Supertypes without a generator class are omitted.
    public var allBaseGenClasses: [GenElement] {
        guard let eClass = ecoreClass else { return [] }
        return context.allSuperTypes(of: eClass).compactMap { context.genClass(forEcoreClass: $0.id) }
    }

    /// The generator class of the first supertype.
    public var baseGenClass: GenElement? {
        guard let first = ecoreClass?.eSuperTypes.first else { return nil }
        return context.genClass(forEcoreClass: first.id)
    }

    /// The first base class, searching upwards, that is not an interface.
    ///
    /// This is the class that a class extends in single-inheritance languages; the
    /// remaining supertypes are implemented.
    public var classExtendsGenClass: GenElement? {
        var visited = Set<GenElement>([self])
        var base = baseGenClass
        while let candidate = base, visited.insert(candidate).inserted {
            if !candidate.isInterface { return candidate }
            base = candidate.baseGenClass
        }
        return nil
    }

    /// The classes whose features this class implements itself, ancestors first, ending with this class.
    ///
    /// These are all base classes that follow the class this class extends, plus this class.
    public var implementedGenClasses: [GenElement] {
        let allBases = allBaseGenClasses
        var result: [GenElement]
        if let extended = classExtendsGenClass, let index = allBases.firstIndex(of: extended) {
            result = Array(allBases[(index + 1)...])
        } else {
            result = allBases
        }
        result.append(self)
        return result
    }

    /// All features of a class, inherited features first.
    ///
    /// Features of base classes come first, in the order of ``allBaseGenClasses``, followed
    /// by the features declared by the class itself. The position of a feature in this
    /// list is its ``featureID(of:)``.
    public var allGenFeatures: [GenElement] {
        allBaseGenClasses.flatMap(\.genFeatures) + genFeatures
    }

    /// The features inherited from base classes, in order.
    public var inheritedGenFeatures: [GenElement] {
        allBaseGenClasses.flatMap(\.genFeatures)
    }

    /// The features that this class must implement itself.
    ///
    /// These are the features of ``implementedGenClasses``: those declared by this class and
    /// by interface supertypes that the class extended by this class does not already provide.
    public var implementedGenFeatures: [GenElement] {
        implementedGenClasses.flatMap(\.genFeatures)
    }

    /// The total number of features of a class, including inherited features.
    public var featureCount: Int { allGenFeatures.count }

    /// The numeric identifier of a feature within this class.
    ///
    /// The identifier is the position of the feature among the class's ``allGenFeatures``,
    /// so inherited features keep the identifiers they have in their base classes.
    ///
    /// - Parameter feature: A generator feature of this class or one of its base classes.
    /// - Returns: The identifier, or `nil` if the feature does not belong to this class.
    public func featureID(of feature: GenElement) -> Int? {
        allGenFeatures.firstIndex(of: feature)
    }

    /// All operations of a class, inherited operations first.
    ///
    /// - Parameter excludeOverrides: If `true`, an operation is left out when an operation
    ///   with the same name and parameter count has already been collected.
    /// - Returns: The operations of the base classes followed by the class's own operations.
    public func allGenOperations(excludeOverrides: Bool = true) -> [GenElement] {
        var result: [GenElement] = []
        for candidate in allBaseGenClasses.flatMap(\.genOperations) + genOperations {
            if excludeOverrides, result.contains(where: { $0.isOverride(of: candidate) }) {
                continue
            }
            result.append(candidate)
        }
        return result
    }

    /// All operations of a class with overrides excluded, inherited operations first.
    public var allGenOperations: [GenElement] { allGenOperations(excludeOverrides: true) }

    /// The total number of operations of a class, including inherited ones and overrides.
    public var operationCount: Int { allGenOperations(excludeOverrides: false).count }

    /// The numeric identifier of an operation within this class.
    ///
    /// The identifier is the position of the operation among all operations including
    /// overrides, so inherited operations keep the identifiers they have in their base classes.
    ///
    /// - Parameter operation: A generator operation of this class or one of its base classes.
    /// - Returns: The identifier, or `nil` if the operation does not belong to this class.
    public func operationID(of operation: GenElement) -> Int? {
        allGenOperations(excludeOverrides: false).firstIndex(of: operation)
    }

    /// Whether this operation has the same signature as another operation.
    ///
    /// Operations match when their names and parameter counts agree. Parameter types
    /// cannot be compared because native Ecore operations are not available.
    ///
    /// - Parameter other: The operation to compare with.
    /// - Returns: `true` if both operations have the same name and parameter count.
    public func isOverride(of other: GenElement) -> Bool {
        let otherName = other.name
        return !otherName.isEmpty && name == otherName
            && genParameters.count == other.genParameters.count
    }

    /// Whether a class is a map entry class.
    ///
    /// A class is a map entry if its Ecore class has features `key` and `value` and its
    /// instance type name, as recorded in the context, is a map entry type.
    public var isMapEntry: Bool {
        guard let eClass = ecoreClass,
            let typeName = context.instanceTypeName(ofClass: eClass.id),
            GenModelConstants.EcoreConvention.mapEntryInstanceTypeNames.contains(typeName)
        else { return false }
        return GenModelConstants.EcoreConvention.mapEntryFeatureNames.allSatisfy {
            eClass.getStructuralFeature(name: $0) != nil
        }
    }

    /// The feature whose value labels instances of a class.
    ///
    /// An explicitly set label feature wins. Otherwise the best candidate among the
    /// single-valued attributes of the class and its base classes is chosen: a feature
    /// named `name`, else `id`, else one whose name ends with `name`, else one containing `name`,
    /// else the first candidate.
    public var labelFeature: GenElement? {
        if let explicit = elements(GenModelConstants.FeatureName.labelFeature).first {
            return explicit
        }
        let word = GenModelConstants.EcoreConvention.nameWord
        let identifier = GenModelConstants.EcoreConvention.identifierName
        var best: GenElement?
        for candidate in labelFeatureCandidates {
            let candidateName = candidate.name
            let lowered = candidateName.lowercased()
            let bestLowered = best?.name.lowercased()
            if lowered == word {
                best = candidate
            } else if lowered == identifier {
                if best == nil || !(bestLowered?.hasSuffix(word) ?? false) { best = candidate }
            } else if lowered.hasSuffix(word) {
                if best == nil || !(bestLowered?.hasSuffix(word) ?? false) && bestLowered != identifier {
                    best = candidate
                }
            } else if lowered.contains(word) {
                if best == nil || !(bestLowered?.contains(word) ?? false) && bestLowered != identifier {
                    best = candidate
                }
            } else if best == nil {
                best = candidate
            }
        }
        return best
    }

    /// The single-valued attributes that may label instances of a class.
    public var labelFeatureCandidates: [GenElement] {
        allGenFeatures.filter { !$0.isReferenceType && !$0.isListType }
    }
}
