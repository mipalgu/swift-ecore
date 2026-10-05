//
// InstanceChildDescriptor.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// A kind of child that can be created inside an object.
///
/// A descriptor pairs a containment reference with a concrete class whose instances the
/// reference accepts. Descriptors drive "New Child" menus of instance editors.
public struct InstanceChildDescriptor: Sendable, Hashable {
    /// The containment reference that would hold the new child.
    public let reference: EReference

    /// The concrete class to instantiate.
    public let eClass: EClass

    /// Creates a descriptor.
    ///
    /// - Parameters:
    ///   - reference: The containment reference that would hold the child.
    ///   - eClass: The concrete class to instantiate.
    public init(reference: EReference, eClass: EClass) {
        self.reference = reference
        self.eClass = eClass
    }

    /// Lists the children that can be created inside an object.
    ///
    /// Every changeable containment reference of the object's class (inherited ones included)
    /// is combined with each concrete class of the metamodels that conforms to the
    /// reference's type. References whose upper bound is already reached are left out.
    ///
    /// - Parameters:
    ///   - object: The prospective container.
    ///   - metamodels: The metamodels whose classes may be instantiated.
    /// - Returns: The descriptors, in the order of the references and then of the classes.
    public static func legalChildren(of object: any EObject, in metamodels: [EPackage]) -> [InstanceChildDescriptor] {
        guard let eClass = object.eClass as? EClass else { return [] }
        let candidates = concreteClasses(of: metamodels)
        var result: [InstanceChildDescriptor] = []
        for reference in eClass.eAllContainments where !reference.derived && reference.changeable {
            guard let type = reference.eType as? EClass, hasCapacity(reference, in: object) else { continue }
            var matches = candidates.filter { conforms($0, to: type) }
            if matches.isEmpty, !type.isAbstract, !type.isInterface { matches = [type] }
            result.append(contentsOf: matches.map { InstanceChildDescriptor(reference: reference, eClass: $0) })
        }
        return result
    }

    private static func hasCapacity(_ reference: EReference, in object: any EObject) -> Bool {
        guard reference.upperBound >= 0 else { return true }
        return ReferenceValues.identifiers(object.eGet(reference)).count < reference.upperBound
    }

    private static func conforms(_ candidate: EClass, to type: EClass) -> Bool {
        candidate.id == type.id || candidate.eAllSuperTypes.contains { $0.id == type.id }
            || type.name == EcoreClassifier.eObject.rawValue
    }

    private static func concreteClasses(of packages: [EPackage]) -> [EClass] {
        var seen = Set<EUUID>()
        var result: [EClass] = []
        func collect(_ package: EPackage) {
            for case let eClass as EClass in package.eClassifiers
            where !eClass.isAbstract && !eClass.isInterface && seen.insert(eClass.id).inserted {
                result.append(eClass)
            }
            package.eSubpackages.forEach(collect)
        }
        packages.forEach(collect)
        return result
    }
}
