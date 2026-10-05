//
// EcoreCopier.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// The result of copying metamodel elements.
public struct EcoreCopy: Sendable {
    /// The copies, in the order of the elements that were copied.
    public let elements: [EcoreElement]

    /// The identifier of the copy of every element that was copied, by the identifier of the
    /// original. It covers the copied elements and everything they contain.
    public let identifiers: [EUUID: EUUID]
}

/// Makes deep copies of metamodel elements.
///
/// The copy follows the semantics of `EcoreUtil.copyAll`. Every copied element, and every
/// element it contains, receives a fresh identifier. A reference between copied elements (a
/// supertype, a type, an opposite, or an annotation reference) refers to the copy; a
/// reference to an element that was not copied is kept and still refers to the original.
/// Values that have no identity of their own are copied as they are.
///
/// Free-form objects that an annotation contains (``EAnnotation/contents``) and values that
/// are stored reflectively outside the modelled properties are not copied.
public enum EcoreCopier {
    /// Copies elements.
    ///
    /// The copies are not contained by anything: they can be added to any container that
    /// accepts their kind.
    ///
    /// - Parameter elements: The elements to copy, each with everything it contains.
    /// - Returns: The copies and the identifiers they received.
    public static func copy(_ elements: [EcoreElement]) -> EcoreCopy {
        var renames: [EUUID: EUUID] = [:]
        for element in elements { assignIdentifiers(element, &renames) }
        let copies = elements.map { copy($0, renames) }
        return EcoreCopy(elements: refreshed(copies, renames), identifiers: renames)
    }

    // MARK: Identifiers

    /// Gives a fresh identifier to an element and everything it contains.
    private static func assignIdentifiers(_ element: EcoreElement, _ renames: inout [EUUID: EUUID]) {
        let identifier = renames[element.id] ?? EUUID()
        renames[element.id] = identifier
        if case .annotation(let annotation) = element {
            for entry in annotation.detailEntries {
                renames[entry.id] = ReflectiveValues.derivedID(from: identifier, key: entry.key)
            }
        }
        for child in element.children {
            if case .detail = child.element { continue }
            assignIdentifiers(child.element, &renames)
        }
    }

    // MARK: Copying

    private static func copy(_ element: EcoreElement, _ renames: [EUUID: EUUID]) -> EcoreElement {
        switch element {
        case .package(let value): return .package(copy(value, renames))
        case .eClass(let value): return .eClass(copy(value, renames))
        case .dataType(let value): return .dataType(copy(value, renames))
        case .eEnum(let value): return .eEnum(copy(value, renames))
        case .literal(let value): return .literal(copy(value, renames))
        case .attribute(let value): return .attribute(copy(value, renames))
        case .reference(let value): return .reference(copy(value, renames))
        case .operation(let value): return .operation(copy(value, renames))
        case .parameter(let value): return .parameter(copy(value, renames))
        case .annotation(let value): return .annotation(copy(value, renames))
        case .typeParameter(let value): return .typeParameter(copy(value, renames))
        case .detail(let value):
            return .detail(EStringToStringMapEntry(id: renames[value.id] ?? EUUID(), key: value.key, value: value.value))
        }
    }

    private static func copy(_ classifier: any EClassifier, _ renames: [EUUID: EUUID]) -> any EClassifier {
        switch classifier {
        case let value as EClass: return copy(value, renames)
        case let value as EEnum: return copy(value, renames)
        case let value as EDataType: return copy(value, renames)
        default: return classifier
        }
    }

    private static func copy(_ feature: any EStructuralFeature, _ renames: [EUUID: EUUID])
        -> any EStructuralFeature
    {
        switch feature {
        case let value as EAttribute: return copy(value, renames)
        case let value as EReference: return copy(value, renames)
        default: return feature
        }
    }

    private static func copy(_ value: EPackage, _ renames: [EUUID: EUUID]) -> EPackage {
        EPackage(
            id: renames[value.id] ?? EUUID(), name: value.name, nsURI: value.nsURI,
            nsPrefix: value.nsPrefix, eClassifiers: value.eClassifiers.map { copy($0, renames) },
            eSubpackages: value.eSubpackages.map { copy($0, renames) },
            eAnnotations: value.eAnnotations.map { copy($0, renames) })
    }

    private static func copy(_ value: EClass, _ renames: [EUUID: EUUID]) -> EClass {
        var result = EClass(
            id: renames[value.id] ?? EUUID(), name: value.name, isAbstract: value.isAbstract,
            isInterface: value.isInterface, eSuperTypes: value.eSuperTypes,
            eStructuralFeatures: value.eStructuralFeatures.map { copy($0, renames) },
            eOperations: value.eOperations.map { copy($0, renames) },
            eAnnotations: value.eAnnotations.map { copy($0, renames) },
            instanceClassName: value.instanceClassName)
        result.instanceTypeName = value.instanceTypeName
        result.eTypeParameters = value.eTypeParameters.map { copy($0, renames) }
        result.eGenericSuperTypes = value.eGenericSuperTypes.map { copy($0, renames) }
        return result
    }

    private static func copy(_ value: EDataType, _ renames: [EUUID: EUUID]) -> EDataType {
        var result = EDataType(
            id: renames[value.id] ?? EUUID(), name: value.name, serialisable: value.serialisable,
            instanceClassName: value.instanceClassName, defaultValueLiteral: value.defaultValueLiteral,
            eAnnotations: value.eAnnotations.map { copy($0, renames) })
        result.instanceTypeName = value.instanceTypeName
        result.eTypeParameters = value.eTypeParameters.map { copy($0, renames) }
        return result
    }

    private static func copy(_ value: EEnum, _ renames: [EUUID: EUUID]) -> EEnum {
        var result = EEnum(
            id: renames[value.id] ?? EUUID(), name: value.name,
            literals: value.literals.map { copy($0, renames) },
            eAnnotations: value.eAnnotations.map { copy($0, renames) })
        result.serialisable = value.serialisable
        result.instanceClassName = value.instanceClassName
        result.instanceTypeName = value.instanceTypeName
        result.eTypeParameters = value.eTypeParameters.map { copy($0, renames) }
        return result
    }

    private static func copy(_ value: EEnumLiteral, _ renames: [EUUID: EUUID]) -> EEnumLiteral {
        EEnumLiteral(
            id: renames[value.id] ?? EUUID(), name: value.name, value: value.value,
            literal: value.literal, eAnnotations: value.eAnnotations.map { copy($0, renames) })
    }

    private static func copy(_ value: EAttribute, _ renames: [EUUID: EUUID]) -> EAttribute {
        var result = EAttribute(
            id: renames[value.id] ?? EUUID(), name: value.name, eType: value.eType,
            lowerBound: value.lowerBound, upperBound: value.upperBound, changeable: value.changeable,
            volatile: value.volatile, transient: value.transient,
            defaultValueLiteral: value.defaultValueLiteral, isID: value.isID,
            eAnnotations: value.eAnnotations.map { copy($0, renames) }, ordered: value.ordered,
            unique: value.unique, unsettable: value.unsettable, derived: value.derived)
        result.eGenericType = value.eGenericType.map { copy($0, renames) }
        return result
    }

    private static func copy(_ value: EReference, _ renames: [EUUID: EUUID]) -> EReference {
        var result = EReference(
            id: renames[value.id] ?? EUUID(), name: value.name, eType: value.eType,
            lowerBound: value.lowerBound, upperBound: value.upperBound, changeable: value.changeable,
            volatile: value.volatile, transient: value.transient, containment: value.containment,
            opposite: value.opposite.map { renames[$0] ?? $0 }, resolveProxies: value.resolveProxies,
            eAnnotations: value.eAnnotations.map { copy($0, renames) }, ordered: value.ordered,
            unique: value.unique, unsettable: value.unsettable, derived: value.derived,
            container: value.container)
        result.eGenericType = value.eGenericType.map { copy($0, renames) }
        result.eKeys = value.eKeys.map { renames[$0] ?? $0 }
        return result
    }

    private static func copy(_ value: EOperation, _ renames: [EUUID: EUUID]) -> EOperation {
        var result = EOperation(
            id: renames[value.id] ?? EUUID(), name: value.name, eType: value.eType,
            lowerBound: value.lowerBound, upperBound: value.upperBound, ordered: value.ordered,
            unique: value.unique, eParameters: value.eParameters.map { copy($0, renames) },
            eExceptions: value.eExceptions, eAnnotations: value.eAnnotations.map { copy($0, renames) })
        result.eGenericType = value.eGenericType.map { copy($0, renames) }
        result.eTypeParameters = value.eTypeParameters.map { copy($0, renames) }
        result.eGenericExceptions = value.eGenericExceptions.map { copy($0, renames) }
        return result
    }

    private static func copy(_ value: EParameter, _ renames: [EUUID: EUUID]) -> EParameter {
        var result = EParameter(
            id: renames[value.id] ?? EUUID(), name: value.name, eType: value.eType,
            lowerBound: value.lowerBound, upperBound: value.upperBound, ordered: value.ordered,
            unique: value.unique, eAnnotations: value.eAnnotations.map { copy($0, renames) })
        result.eGenericType = value.eGenericType.map { copy($0, renames) }
        return result
    }

    private static func copy(_ value: ETypeParameter, _ renames: [EUUID: EUUID]) -> ETypeParameter {
        ETypeParameter(
            id: renames[value.id] ?? EUUID(), name: value.name,
            eBounds: value.eBounds.map { copy($0, renames) },
            eAnnotations: value.eAnnotations.map { copy($0, renames) })
    }

    private static func copy(_ value: EGenericType, _ renames: [EUUID: EUUID]) -> EGenericType {
        EGenericType(
            eClassifier: value.eClassifier, eTypeParameter: value.eTypeParameter.map { renames[$0] ?? $0 },
            eTypeArguments: value.eTypeArguments.map { copy($0, renames) },
            eUpperBound: value.eUpperBound.map { copy($0, renames) },
            eLowerBound: value.eLowerBound.map { copy($0, renames) })
    }

    private static func copy(_ value: EAnnotation, _ renames: [EUUID: EUUID]) -> EAnnotation {
        EAnnotation(
            id: renames[value.id] ?? EUUID(), source: value.source, orderedDetails: value.details,
            eAnnotations: value.eAnnotations.map { copy($0, renames) },
            references: value.references.map { reference in
                if case .local(let target) = reference { return .local(renames[target] ?? target) }
                return reference
            },
            contents: value.contents)
    }

    // MARK: Snapshots

    /// Replaces the class snapshots of copies that name copied elements by snapshots of the copies.
    private static func refreshed(_ copies: [EcoreElement], _ renames: [EUUID: EUUID]) -> [EcoreElement] {
        var classes: [EClass] = []
        var dataTypes: [EUUID: any EClassifier] = [:]
        for element in copies { collect(element, &classes, &dataTypes) }
        let linker = SnapshotLinker(classes: classes, dataTypes: dataTypes, externals: [:], renames: renames)
        let linked = linker.link()
        return copies.map { element in
            switch element {
            case .package(let value):
                return .package(MetamodelLinker.replacingClasses(in: value, with: linked))
            case .eClass(let value):
                return .eClass(linked[value.id] ?? value)
            case .attribute(let value):
                return EcoreElement.feature(linker.feature(value, previous: linked)) ?? element
            case .reference(let value):
                return EcoreElement.feature(linker.feature(value, previous: linked)) ?? element
            case .operation(let value):
                return .operation(linker.operation(value, previous: linked))
            case .parameter(let value):
                return .parameter(linker.parameter(value, previous: linked))
            case .typeParameter(let value):
                return .typeParameter(linker.typeParameter(value, previous: linked))
            default:
                return element
            }
        }
    }

    /// Lists the classes of an element in document order and collects its other classifiers.
    private static func collect(
        _ element: EcoreElement, _ classes: inout [EClass], _ dataTypes: inout [EUUID: any EClassifier]
    ) {
        switch element {
        case .eClass(let value): classes.append(value)
        case .dataType(let value): dataTypes[value.id] = value
        case .eEnum(let value): dataTypes[value.id] = value
        case .package(let value): MetamodelLinker.collect(value, classes: &classes, dataTypes: &dataTypes)
        default: break
        }
    }
}
