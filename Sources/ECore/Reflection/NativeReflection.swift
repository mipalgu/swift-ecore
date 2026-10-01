//
// NativeReflection.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import OrderedCollections

// MARK: - Conversion Helpers

/// Helpers that convert between reflective values and the typed properties of native objects.
private enum Reflect {
    /// Wraps objects as a collection value.
    static func objects(_ elements: [any EcoreValue]) -> ReflectiveValue {
        .value(EcoreValueArray(elements))
    }

    /// Wraps classifiers as a collection value.
    static func classifiers(_ classifiers: [any EClassifier]) -> ReflectiveValue {
        objects(classifiers.compactMap { $0 as? any EcoreValue })
    }

    /// Wraps structural features as a collection value.
    static func features(_ features: [any EStructuralFeature]) -> ReflectiveValue {
        objects(features.compactMap { $0 as? any EcoreValue })
    }

    /// Pairs a containment feature with the objects it holds, for containment traversal.
    static func contained(
        _ feature: EcoreFeatureName, _ elements: [any EcoreValue]
    ) -> [(feature: EcoreFeatureName, object: any EObject)] {
        elements.compactMap { element in
            (element as? any EObject).map { (feature: feature, object: $0) }
        }
    }

    /// The empty collection value.
    static var empty: ReflectiveValue { .value(EcoreValueArray([])) }
}

// MARK: - Shared Feature Behaviour

/// Reflective behaviour shared by attributes and references.
private protocol ReflectiveStructuralFeature: EcoreReflective {
    var name: String { get set }
    var eAnnotations: [EAnnotation] { get set }
    var eType: any EClassifier { get set }
    var lowerBound: Int { get set }
    var upperBound: Int { get set }
    var changeable: Bool { get set }
    var volatile: Bool { get set }
    var transient: Bool { get set }
    var defaultValueLiteral: String? { get set }
    var ordered: Bool { get set }
    var unique: Bool { get set }
    var unsettable: Bool { get set }
    var derived: Bool { get set }
    var isMany: Bool { get }
    var isRequired: Bool { get }
}

extension ReflectiveStructuralFeature {
    fileprivate func commonGet(_ feature: EcoreFeatureName) -> ReflectiveValue {
        switch feature {
        case .name: return .value(name)
        case .eAnnotations: return Reflect.objects(eAnnotations)
        case .ordered: return .value(ordered)
        case .unique: return .value(unique)
        case .lowerBound: return .value(lowerBound)
        case .upperBound: return .value(upperBound)
        case .many: return .value(isMany)
        case .required: return .value(isRequired)
        case .eType: return .value(EcorePackage.canonical(eType) as? any EcoreValue)
        case .eGenericType: return .value(nil)
        case .changeable: return .value(changeable)
        case .volatile: return .value(volatile)
        case .transient: return .value(transient)
        case .defaultValueLiteral: return .value(defaultValueLiteral)
        case .defaultValue: return .value(nil)
        case .unsettable: return .value(unsettable)
        case .derived: return .value(derived)
        case .eContainingClass: return .value(eContainerID)
        default: return .unsupported
        }
    }

    fileprivate mutating func commonSet(_ feature: EcoreFeatureName, _ value: (any EcoreValue)?)
        -> Bool
    {
        switch feature {
        case .name: name = value as? String ?? ""
        case .eAnnotations:
            eAnnotations = ReflectiveValues.elements(value, as: EAnnotation.self) ?? []
        case .ordered: ordered = value as? Bool ?? true
        case .unique: unique = value as? Bool ?? true
        case .lowerBound: lowerBound = value as? Int ?? 0
        case .upperBound: upperBound = value as? Int ?? 1
        case .eType:
            guard let type = value as? any EClassifier else { return true }
            eType = type
        case .changeable: changeable = value as? Bool ?? true
        case .volatile: volatile = value as? Bool ?? false
        case .transient: transient = value as? Bool ?? false
        case .defaultValueLiteral: defaultValueLiteral = value as? String
        case .unsettable: unsettable = value as? Bool ?? false
        case .derived: derived = value as? Bool ?? false
        default: return false
        }
        return true
    }
}

extension EAttribute: ReflectiveStructuralFeature {}
extension EReference: ReflectiveStructuralFeature {}

// MARK: - EPackage

extension EPackage: EcoreReflective {
    func reflectiveGet(_ feature: EcoreFeatureName) -> ReflectiveValue {
        switch feature {
        case .name: return .value(name)
        case .eAnnotations: return Reflect.objects(eAnnotations)
        case .nsURI: return .value(nsURI)
        case .nsPrefix: return .value(nsPrefix)
        case .eClassifiers: return Reflect.classifiers(eClassifiers)
        case .eSubpackages: return Reflect.objects(eSubpackages)
        case .eSuperPackage: return .value(eContainerID)
        case .eFactoryInstance: return .value(eFactoryInstance)
        default: return .unsupported
        }
    }

    mutating func reflectiveSet(_ feature: EcoreFeatureName, _ value: (any EcoreValue)?) -> Bool {
        switch feature {
        case .name: name = value as? String ?? ""
        case .nsURI: nsURI = value as? String ?? ""
        case .nsPrefix: nsPrefix = value as? String ?? ""
        case .eAnnotations:
            eAnnotations = ReflectiveValues.elements(value, as: EAnnotation.self) ?? []
        case .eClassifiers:
            eClassifiers = ReflectiveValues.elements(value, as: (any EClassifier).self) ?? []
        case .eSubpackages:
            eSubpackages = ReflectiveValues.elements(value, as: EPackage.self) ?? []
        default: return false
        }
        return true
    }

    var containedObjects: [(feature: EcoreFeatureName, object: any EObject)] {
        Reflect.contained(.eAnnotations, eAnnotations)
            + Reflect.contained(
                .eClassifiers, eClassifiers.compactMap { $0 as? any EcoreValue })
            + Reflect.contained(.eSubpackages, eSubpackages)
    }
}

// MARK: - EClass

extension EClass: EcoreReflective {
    func reflectiveGet(_ feature: EcoreFeatureName) -> ReflectiveValue {
        switch feature {
        case .name: return .value(name)
        case .eAnnotations: return Reflect.objects(eAnnotations)
        case .abstract: return .value(isAbstract)
        case .interface: return .value(isInterface)
        case .eSuperTypes: return Reflect.objects(eSuperTypes)
        case .eAllSuperTypes: return Reflect.objects(eAllSuperTypes)
        case .eStructuralFeatures: return Reflect.features(eStructuralFeatures)
        case .eAllStructuralFeatures: return Reflect.features(eAllStructuralFeatures)
        case .eAttributes: return Reflect.objects(eAttributes)
        case .eReferences: return Reflect.objects(eReferences)
        case .eAllAttributes: return Reflect.objects(eAllAttributes)
        case .eAllReferences: return Reflect.objects(eAllReferences)
        case .eAllContainments: return Reflect.objects(eAllContainments)
        case .eIDAttribute: return .value(eIDAttribute)
        case .eOperations: return Reflect.objects(eOperations)
        case .eAllOperations: return Reflect.objects(eAllOperations)
        case .eTypeParameters, .eGenericSuperTypes, .eAllGenericSuperTypes:
            return Reflect.empty
        case .ePackage: return .value(eContainerID)
        case .instanceClassName: return .value(instanceClassName)
        case .instanceClass, .defaultValue: return .value(nil)
        default: return .unsupported
        }
    }

    mutating func reflectiveSet(_ feature: EcoreFeatureName, _ value: (any EcoreValue)?) -> Bool {
        switch feature {
        case .name: name = value as? String ?? ""
        case .abstract: isAbstract = value as? Bool ?? false
        case .interface: isInterface = value as? Bool ?? false
        case .eAnnotations:
            eAnnotations = ReflectiveValues.elements(value, as: EAnnotation.self) ?? []
        case .eSuperTypes:
            eSuperTypes = ReflectiveValues.elements(value, as: EClass.self) ?? []
        case .eOperations:
            eOperations = ReflectiveValues.elements(value, as: EOperation.self) ?? []
        case .instanceClassName: instanceClassName = value as? String
        case .eStructuralFeatures:
            eStructuralFeatures =
                ReflectiveValues.elements(value, as: (any EStructuralFeature).self) ?? []
        default: return false
        }
        return true
    }

    var containedObjects: [(feature: EcoreFeatureName, object: any EObject)] {
        Reflect.contained(.eAnnotations, eAnnotations)
            + Reflect.contained(.eOperations, eOperations)
            + Reflect.contained(
                .eStructuralFeatures, eStructuralFeatures.compactMap { $0 as? any EcoreValue })
    }
}

// MARK: - EAttribute and EReference

extension EAttribute {
    func reflectiveGet(_ feature: EcoreFeatureName) -> ReflectiveValue {
        switch feature {
        case .iD: return .value(isID)
        case .eAttributeType:
            let canonical = EcorePackage.canonical(eType)
            return .value((canonical is EDataType || canonical is EEnum) ? canonical as? any EcoreValue : nil)
        default: return commonGet(feature)
        }
    }

    mutating func reflectiveSet(_ feature: EcoreFeatureName, _ value: (any EcoreValue)?) -> Bool {
        switch feature {
        case .iD:
            isID = value as? Bool ?? false
            return true
        default: return commonSet(feature, value)
        }
    }

    var containedObjects: [(feature: EcoreFeatureName, object: any EObject)] {
        Reflect.contained(.eAnnotations, eAnnotations)
    }
}

extension EReference {
    func reflectiveGet(_ feature: EcoreFeatureName) -> ReflectiveValue {
        switch feature {
        case .containment: return .value(containment)
        case .container: return .value(container)
        case .resolveProxies: return .value(resolveProxies)
        case .eOpposite: return .value(opposite)
        case .eReferenceType:
            let canonical = EcorePackage.canonical(eType)
            return .value(canonical is EClass ? canonical as? any EcoreValue : nil)
        case .eKeys: return Reflect.empty
        default: return commonGet(feature)
        }
    }

    mutating func reflectiveSet(_ feature: EcoreFeatureName, _ value: (any EcoreValue)?) -> Bool {
        switch feature {
        case .containment: containment = value as? Bool ?? false
        case .resolveProxies: resolveProxies = value as? Bool ?? true
        case .eOpposite:
            if let identifier = value as? EUUID {
                opposite = identifier
            } else if let reference = value as? EReference {
                opposite = reference.id
            } else {
                opposite = nil
            }
        default: return commonSet(feature, value)
        }
        return true
    }

    var containedObjects: [(feature: EcoreFeatureName, object: any EObject)] {
        Reflect.contained(.eAnnotations, eAnnotations)
    }
}

// MARK: - EOperation and EParameter

/// Reflective behaviour shared by operations and parameters.
private protocol ReflectiveTypedElement: EcoreReflective, ETypedElement {
    var name: String { get set }
    var eAnnotations: [EAnnotation] { get set }
    var isMany: Bool { get }
    var isRequired: Bool { get }
}

extension ReflectiveTypedElement {
    fileprivate func typedGet(_ feature: EcoreFeatureName) -> ReflectiveValue {
        switch feature {
        case .name: return .value(name)
        case .eAnnotations: return Reflect.objects(eAnnotations)
        case .ordered: return .value(ordered)
        case .unique: return .value(unique)
        case .lowerBound: return .value(lowerBound)
        case .upperBound: return .value(upperBound)
        case .many: return .value(isMany)
        case .required: return .value(isRequired)
        case .eType: return .value(eType.flatMap { EcorePackage.canonical($0) as? any EcoreValue })
        case .eGenericType: return .value(nil)
        default: return .unsupported
        }
    }

    fileprivate mutating func typedSet(_ feature: EcoreFeatureName, _ value: (any EcoreValue)?)
        -> Bool
    {
        switch feature {
        case .name: name = value as? String ?? ""
        case .eAnnotations:
            eAnnotations = ReflectiveValues.elements(value, as: EAnnotation.self) ?? []
        case .ordered: ordered = value as? Bool ?? true
        case .unique: unique = value as? Bool ?? true
        case .lowerBound: lowerBound = value as? Int ?? 0
        case .upperBound: upperBound = value as? Int ?? 1
        case .eType: eType = value as? any EClassifier
        default: return false
        }
        return true
    }
}

extension EOperation: ReflectiveTypedElement {
    func reflectiveGet(_ feature: EcoreFeatureName) -> ReflectiveValue {
        switch feature {
        case .eContainingClass: return .value(eContainerID)
        case .eParameters: return Reflect.objects(eParameters)
        case .eExceptions:
            return Reflect.classifiers(eExceptions.map { EcorePackage.canonical($0) })
        case .eTypeParameters, .eGenericExceptions: return Reflect.empty
        default: return typedGet(feature)
        }
    }

    mutating func reflectiveSet(_ feature: EcoreFeatureName, _ value: (any EcoreValue)?) -> Bool {
        switch feature {
        case .eParameters:
            eParameters = ReflectiveValues.elements(value, as: EParameter.self) ?? []
            return true
        case .eExceptions:
            eExceptions = ReflectiveValues.elements(value, as: (any EClassifier).self) ?? []
            return true
        default: return typedSet(feature, value)
        }
    }

    var containedObjects: [(feature: EcoreFeatureName, object: any EObject)] {
        Reflect.contained(.eAnnotations, eAnnotations)
            + Reflect.contained(.eParameters, eParameters)
    }
}

extension EParameter: ReflectiveTypedElement {
    func reflectiveGet(_ feature: EcoreFeatureName) -> ReflectiveValue {
        switch feature {
        case .eOperation: return .value(eContainerID)
        default: return typedGet(feature)
        }
    }

    mutating func reflectiveSet(_ feature: EcoreFeatureName, _ value: (any EcoreValue)?) -> Bool {
        typedSet(feature, value)
    }

    var containedObjects: [(feature: EcoreFeatureName, object: any EObject)] {
        Reflect.contained(.eAnnotations, eAnnotations)
    }
}

// MARK: - EDataType, EEnum and EEnumLiteral

extension EDataType: EcoreReflective {
    func reflectiveGet(_ feature: EcoreFeatureName) -> ReflectiveValue {
        switch feature {
        case .name: return .value(name)
        case .eAnnotations: return Reflect.objects(eAnnotations)
        case .serializable: return .value(serialisable)
        case .instanceClassName: return .value(instanceClassName)
        case .ePackage: return .value(eContainerID)
        case .eTypeParameters: return Reflect.empty
        case .instanceClass, .defaultValue: return .value(nil)
        default: return .unsupported
        }
    }

    mutating func reflectiveSet(_ feature: EcoreFeatureName, _ value: (any EcoreValue)?) -> Bool {
        switch feature {
        case .name: name = value as? String ?? ""
        case .serializable: serialisable = value as? Bool ?? true
        case .instanceClassName: instanceClassName = value as? String
        case .eAnnotations:
            eAnnotations = ReflectiveValues.elements(value, as: EAnnotation.self) ?? []
        default: return false
        }
        return true
    }

    var containedObjects: [(feature: EcoreFeatureName, object: any EObject)] {
        Reflect.contained(.eAnnotations, eAnnotations)
    }
}

extension EEnum: EcoreReflective {
    func reflectiveGet(_ feature: EcoreFeatureName) -> ReflectiveValue {
        switch feature {
        case .name: return .value(name)
        case .eAnnotations: return Reflect.objects(eAnnotations)
        case .eLiterals: return Reflect.objects(literals)
        case .serializable: return .value(true)
        case .ePackage: return .value(eContainerID)
        case .eTypeParameters: return Reflect.empty
        case .instanceClass, .defaultValue: return .value(nil)
        default: return .unsupported
        }
    }

    mutating func reflectiveSet(_ feature: EcoreFeatureName, _ value: (any EcoreValue)?) -> Bool {
        switch feature {
        case .name: name = value as? String ?? ""
        case .eAnnotations:
            eAnnotations = ReflectiveValues.elements(value, as: EAnnotation.self) ?? []
        case .eLiterals:
            literals = ReflectiveValues.elements(value, as: EEnumLiteral.self) ?? []
        default: return false
        }
        return true
    }

    var containedObjects: [(feature: EcoreFeatureName, object: any EObject)] {
        Reflect.contained(.eAnnotations, eAnnotations) + Reflect.contained(.eLiterals, literals)
    }
}

extension EEnumLiteral: EcoreReflective {
    func reflectiveGet(_ feature: EcoreFeatureName) -> ReflectiveValue {
        switch feature {
        case .name: return .value(name)
        case .eAnnotations: return Reflect.objects(eAnnotations)
        case .value: return .value(value)
        case .literal: return .value(literal ?? name)
        case .eEnum: return .value(eContainerID)
        case .instance: return .value(nil)
        default: return .unsupported
        }
    }

    mutating func reflectiveSet(_ feature: EcoreFeatureName, _ newValue: (any EcoreValue)?) -> Bool {
        switch feature {
        case .name: name = newValue as? String ?? ""
        case .value: value = newValue as? Int ?? 0
        case .literal: literal = newValue as? String
        case .eAnnotations:
            eAnnotations = ReflectiveValues.elements(newValue, as: EAnnotation.self) ?? []
        default: return false
        }
        return true
    }

    var containedObjects: [(feature: EcoreFeatureName, object: any EObject)] {
        Reflect.contained(.eAnnotations, eAnnotations)
    }
}

// MARK: - EAnnotation

extension EAnnotation: EcoreReflective {
    func reflectiveGet(_ feature: EcoreFeatureName) -> ReflectiveValue {
        switch feature {
        case .source: return .value(source)
        case .details: return Reflect.objects(detailEntries)
        case .eModelElement: return .value(eContainerID)
        case .eAnnotations: return Reflect.objects(eAnnotations)
        case .contents: return Reflect.objects(contents.compactMap { $0 as? any EcoreValue })
        case .references: return Reflect.objects(references.map(\.value))
        default: return .unsupported
        }
    }

    mutating func reflectiveSet(_ feature: EcoreFeatureName, _ value: (any EcoreValue)?) -> Bool {
        switch feature {
        case .source: source = value as? String ?? ""
        case .details:
            var updated: OrderedDictionary<String, String> = [:]
            for entry in ReflectiveValues.elements(value, as: EStringToStringMapEntry.self) ?? [] {
                updated[entry.key] = entry.value
            }
            details = updated
        case .eAnnotations:
            eAnnotations = ReflectiveValues.elements(value, as: EAnnotation.self) ?? []
        case .contents:
            contents = ReflectiveValues.elements(value, as: (any EObject).self) ?? []
        case .references:
            let values = ReflectiveValues.elements(value, as: (any EcoreValue).self) ?? []
            references = values.compactMap { EAnnotationReference(value: $0) }
        default: return false
        }
        return true
    }

    var containedObjects: [(feature: EcoreFeatureName, object: any EObject)] {
        Reflect.contained(.eAnnotations, eAnnotations) + Reflect.contained(.details, detailEntries)
            + contents.map { (feature: .contents, object: $0) }
    }
}
