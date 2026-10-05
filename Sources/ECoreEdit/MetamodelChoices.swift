//
// MetamodelChoices.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

extension MetamodelDocument {
    /// Lists the elements that a reference-valued property can refer to.
    ///
    /// - `eType`: the data types and enumerations (for an attribute), the classes (for a
    ///   reference), or both (for an operation or parameter), of the document and of its
    ///   external packages, followed by the built-in classifiers of Ecore (for example `EString`).
    /// - `eSuperTypes`: the classes of the document and its externals, except the class itself
    ///   and its subclasses.
    /// - `eExceptions`: every classifier.
    /// - `eOpposite`: the references of the reference's target class (inherited ones included)
    ///   whose type is the class that holds the reference, except the reference itself.
    /// - `references`: every element of the document.
    /// - `eKeys`: none, since native references have no key attributes.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the element that holds the property.
    ///   - feature: The feature of the property.
    /// - Returns: The identifiers of the candidates; empty for other features and unknown elements.
    public func choices(for identifier: EUUID, feature: EcoreFeatureName) -> [EUUID] {
        guard let element = index.element(identifier) else { return [] }
        switch feature {
        case .eType:
            switch element {
            case .attribute: return dataTypeIDs()
            case .reference: return classIDs()
            case .operation, .parameter: return classIDs() + dataTypeIDs()
            default: return []
            }
        case .eSuperTypes:
            guard case .eClass = element else { return [] }
            let excluded = Set(index.subclasses(of: identifier).map(\.id)).union([identifier])
            return classIDs(includeBuiltIns: false).filter { !excluded.contains($0) }
        case .eExceptions:
            guard case .operation = element else { return [] }
            return classIDs() + dataTypeIDs()
        case .eOpposite:
            return oppositeCandidates(for: identifier, element: element)
        case .eKeys:
            guard case .reference(let reference) = element else { return [] }
            return index.keyCandidates(of: reference)
        case .references:
            guard case .annotation = element else { return [] }
            return index.allElements.map(\.id)
        default:
            return []
        }
    }

    /// The classifiers of the document and of its external packages.
    private func classifiers() -> [EcoreElement] {
        var result = index.allElements.filter(Self.isClassifier)
        func collect(_ package: EPackage) {
            for classifier in package.eClassifiers {
                if let element = EcoreElement.classifier(classifier) { result.append(element) }
            }
            package.eSubpackages.forEach(collect)
        }
        index.externals.forEach(collect)
        return result
    }

    private static func isClassifier(_ element: EcoreElement) -> Bool {
        switch element {
        case .eClass, .dataType, .eEnum: return true
        default: return false
        }
    }

    private func classIDs(includeBuiltIns: Bool = true) -> [EUUID] {
        var result = classifiers().compactMap { element -> EUUID? in
            if case .eClass = element { return element.id }
            return nil
        }
        if includeBuiltIns { result += EcoreBuiltIns.metaClasses.map(\.id) }
        return result
    }

    private func dataTypeIDs() -> [EUUID] {
        classifiers().compactMap { element -> EUUID? in
            switch element {
            case .dataType, .eEnum: return element.id
            default: return nil
            }
        } + EcoreBuiltIns.dataTypes.map(\.id)
    }

    private func oppositeCandidates(for identifier: EUUID, element: EcoreElement) -> [EUUID] {
        guard case .reference(let reference) = element, let source = index.container(of: identifier)?.container,
            case .eClass? = index.element(source)
        else { return [] }
        var result: [EUUID] = []
        for classIdentifier in [reference.eType.id] + superTypeIdentifiers(of: reference.eType.id) {
            for case .reference(let candidate) in index.children(of: classIdentifier, feature: .eStructuralFeatures)
            where candidate.eType.id == source && candidate.id != identifier {
                result.append(candidate.id)
            }
        }
        return result
    }

    /// The identifiers of every supertype of a class, nearest first.
    private func superTypeIdentifiers(of identifier: EUUID) -> [EUUID] {
        var result: [EUUID] = []
        var seen: Set<EUUID> = [identifier]
        var pending = [identifier]
        while !pending.isEmpty {
            let current = pending.removeFirst()
            guard case .eClass(let value)? = index.element(current) else { continue }
            for parent in value.eSuperTypes where seen.insert(parent.id).inserted {
                result.append(parent.id)
                pending.append(parent.id)
            }
        }
        return result
    }
}

extension MetamodelIndex {
    /// The attributes of a reference's type and its supertypes, which can serve as keys.
    ///
    /// - Parameter reference: The reference whose keys are chosen.
    /// - Returns: The identifiers of the candidate attributes, the type's own attributes first.
    func keyCandidates(of reference: EReference) -> [EUUID] {
        var result: [EUUID] = []
        var seen: Set<EUUID> = [reference.eType.id]
        var pending = [reference.eType.id]
        var owners: [EUUID] = []
        while !pending.isEmpty {
            let current = pending.removeFirst()
            owners.append(current)
            let parents: [EClass]
            if case .eClass(let value)? = element(current) {
                parents = value.eSuperTypes
            } else {
                parents = (EcoreBuiltIns.classifiers[current] as? EClass)?.eSuperTypes ?? []
            }
            for parent in parents where seen.insert(parent.id).inserted { pending.append(parent.id) }
        }
        for owner in owners {
            if case .eClass? = element(owner) {
                for case .attribute(let attribute) in children(of: owner, feature: .eStructuralFeatures) {
                    result.append(attribute.id)
                }
            } else if let eClass = EcoreBuiltIns.classifiers[owner] as? EClass {
                result.append(contentsOf: eClass.eAttributes.map(\.id))
            }
        }
        return result
    }
}
