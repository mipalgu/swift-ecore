//
// EcoreValidationRun+Features.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

extension EcoreValidationRun {
    /// Checks an attribute.
    func checkAttribute(_ value: EAttribute) {
        checkName(of: value.id, value.name)
        checkBounds(of: value.id, lower: value.lowerBound, upper: value.upperBound)
        let type = canonical(value.eType)
        if type is EClass {
            report(.validType, .attributeTypeIsClass, element: value.id, feature: .eType)
        }
        if let literal = value.defaultValueLiteral, isEnabled(.validDefaultValueLiteral) {
            checkDefaultValue(literal, of: value.id, type: type)
        }
        if !value.transient, isEnabled(.consistentTransient),
            let dataType = type as? EDataType, !dataType.serialisable
        {
            let owner = containingClass(of: value.id)?.name
            let label = owner.map { $0 + EcoreValidationSyntax.qualifiedNameSeparator + value.name } ?? value.name
            report(
                .consistentTransient, .transientRequired, element: value.id, feature: .transient,
                arguments: [label])
        }
    }

    /// Checks that a default value literal denotes a value of the attribute's type.
    private func checkDefaultValue(_ literal: String, of identifier: EUUID, type: any EClassifier) {
        switch type {
        case let enumeration as EEnum:
            let matches = enumeration.literals.contains { ($0.literal ?? $0.name) == literal || $0.name == literal }
            if !matches {
                report(
                    .validDefaultValueLiteral, .defaultValueInvalid, severity: .warning,
                    element: identifier, feature: .defaultValueLiteral, arguments: [literal])
            }
        case let dataType as EDataType:
            if !EcoreDefaultValue.isConvertible(literal, to: dataType) {
                report(
                    .validDefaultValueLiteral, .defaultValueInvalid, element: identifier,
                    feature: .defaultValueLiteral, arguments: [literal])
            }
        default:
            report(
                .validDefaultValueLiteral, .defaultValueInvalid, element: identifier,
                feature: .defaultValueLiteral, arguments: [literal])
        }
    }

    /// Checks an operation.
    func checkOperation(_ value: EOperation) {
        checkName(of: value.id, value.name)
        checkBounds(of: value.id, lower: value.lowerBound, upper: value.upperBound)
        if value.eType == nil && value.upperBound != 1 {
            report(
                .noRepeatingVoid, .voidOperationRepeats, element: value.id, feature: .upperBound,
                arguments: [EcoreValidationMessages.argument(forBound: value.upperBound)])
        }
        guard isEnabled(.uniqueParameterNames), value.eParameters.count > 1 else { return }
        var order: [String] = []
        var groups: [String: [EUUID]] = [:]
        for parameter in value.eParameters {
            if groups[parameter.name] == nil { order.append(parameter.name) }
            groups[parameter.name, default: []].append(parameter.id)
        }
        for name in order {
            guard let group = groups[name], group.count > 1 else { continue }
            report(
                .uniqueParameterNames, .duplicateParameterName, element: value.id,
                feature: .eParameters, arguments: [name], related: group)
        }
    }

    /// Checks an operation parameter.
    func checkParameter(_ value: EParameter) {
        checkName(of: value.id, value.name)
        checkBounds(of: value.id, lower: value.lowerBound, upper: value.upperBound)
        if value.eType == nil {
            report(.validType, .typeMissing, element: value.id, feature: .eType)
        }
    }

    /// Checks a reference.
    func checkReference(_ value: EReference) {
        checkName(of: value.id, value.name)
        checkBounds(of: value.id, lower: value.lowerBound, upper: value.upperBound)
        let type = canonical(value.eType)
        if !(type is EClass) {
            report(.validType, .referenceTypeIsDataType, element: value.id, feature: .eType)
        }
        if let literal = value.defaultValueLiteral, isEnabled(.validDefaultValueLiteral) {
            report(
                .validDefaultValueLiteral, .defaultValueInvalid, element: value.id,
                feature: .defaultValueLiteral, arguments: [literal])
        }
        checkOpposite(of: value, type: type)
        if value.container && value.upperBound != 1 {
            report(
                .singleContainer, .containerNotSingle, element: value.id, feature: .upperBound,
                arguments: [EcoreValidationMessages.argument(forBound: value.upperBound)])
        }
        checkContainer(of: value, type: type)
        if value.isMany && (value.containment || value.opposite != nil) && !value.unique {
            report(.consistentUnique, .containmentNotUnique, element: value.id, feature: .unique)
        }
    }

    /// Checks that the type of a containment does not require another container.
    private func checkContainer(of value: EReference, type: any EClassifier) {
        guard isEnabled(.consistentContainer), value.containment, let target = type as? EClass,
            containingClass(of: value.id) != nil
        else { return }
        let blocker = allFeatures(of: target).lazy.compactMap { $0 as? EReference }.first {
            $0.lowerBound >= 1 && $0.container && $0.opposite != value.id
        }
        if let blocker {
            report(
                .consistentContainer, .containerRequiresContainer, element: value.id,
                feature: .eType, arguments: [blocker.name], related: [blocker.id])
        }
    }

    /// Checks the opposite of a reference.
    private func checkOpposite(of value: EReference, type: any EClassifier) {
        guard isEnabled(.consistentOpposite), let oppositeID = value.opposite,
            case .reference(let opposite)? = index.element(oppositeID)
        else { return }
        let arguments = [value.name, opposite.name]
        let related = [opposite.id]
        var consistent = true
        if containingClass(of: value.id) != nil {
            if opposite.opposite != value.id {
                consistent = false
                report(
                    .consistentOpposite, .oppositeNotMatching, element: value.id,
                    feature: .eOpposite, arguments: arguments, related: related)
            }
            if let oppositeOwner = containingClass(of: opposite.id), oppositeOwner.id != type.id {
                consistent = false
                report(
                    .consistentOpposite, .oppositeNotFromType, element: value.id,
                    feature: .eOpposite, arguments: arguments, related: related)
            }
        }
        guard consistent else { return }
        if value.id == opposite.id {
            report(
                .consistentOpposite, .selfOpposite, element: value.id, feature: .eOpposite,
                arguments: [value.name])
        } else if value.transient && !opposite.transient && opposite.resolveProxies
            && !opposite.containment
        {
            report(
                .consistentOpposite, .oppositeNotTransient, element: value.id,
                feature: .eOpposite, arguments: arguments, related: related)
        } else if value.containment && opposite.containment {
            report(
                .consistentOpposite, .oppositeBothContainment, element: value.id,
                feature: .eOpposite, arguments: arguments, related: related)
        }
    }
}
