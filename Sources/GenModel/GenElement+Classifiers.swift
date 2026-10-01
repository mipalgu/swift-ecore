//
// GenElement+Classifiers.swift
// GenModel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore

extension GenElement {
    /// All classifiers of a package: classes, then enumerations, then data types.
    ///
    /// Each group keeps its model order. The position of a classifier in this list
    /// is its ``classifierID``.
    public var genClassifiers: [GenElement] { genClasses + genEnums + genDataTypes }

    /// The classes of a package ordered so that each class follows its first base class.
    ///
    /// Classes are visited in model order. For each, the chain of first base classes
    /// that belong to this package and have not yet been listed is added, starting with
    /// the most distant base class.
    public var orderedGenClasses: [GenElement] {
        var ordered: [GenElement] = []
        var listed = Set<GenElement>()
        for start in genClasses {
            var chain: [GenElement] = []
            var visited = Set<GenElement>()
            var current: GenElement? = start
            while let candidate = current, visited.insert(candidate).inserted {
                if candidate.genPackage == self, listed.insert(candidate).inserted {
                    chain.insert(candidate, at: 0)
                }
                current = candidate.baseGenClass
            }
            ordered.append(contentsOf: chain)
        }
        return ordered
    }

    /// The classifiers of a package in dependency order: ordered classes, enumerations, data types.
    public var orderedGenClassifiers: [GenElement] {
        orderedGenClasses + genEnums + genDataTypes
    }

    /// The numeric identifier of a classifier within its package.
    ///
    /// The identifier is the classifier's position among the package's ``genClassifiers``:
    /// classes first, then enumerations, then data types, each in model order.
    ///
    /// - Returns: The identifier, or `nil` if this element is not a classifier of a package.
    public var classifierID: Int? {
        guard isKind(of: GenModelConstants.ClassName.genClassifier),
            let package = container?.enclosing(GenModelConstants.ClassName.genPackage)
        else { return nil }
        return package.genClassifiers.firstIndex(of: self)
    }

    /// The symbolic identifier of a classifier within its package.
    ///
    /// The classifier name is split into words, the package prefix is kept as the first
    /// word, and the words are joined by underscores in upper case, for example
    /// `LIBRARY_BOOK` for the class `Book` of a package with prefix `Library`.
    ///
    /// - Returns: The symbolic identifier, or `nil` if this element is not a classifier.
    public var classifierIDName: String? {
        guard isKind(of: GenModelConstants.ClassName.genClassifier) else { return nil }
        let prefix = container?.enclosing(GenModelConstants.ClassName.genPackage)?
            .stringValue(GenModelConstants.FeatureName.prefix)
        return GenModelNaming.format(
            name, separator: "_", prefix: prefix, includePrefix: true, includeLeadingSeparator: true
        ).uppercased()
    }
}
