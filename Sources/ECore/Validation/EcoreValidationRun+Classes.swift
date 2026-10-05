//
// EcoreValidationRun+Classes.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

extension EcoreValidationRun {
    /// The part of a signature that decides whether two signatures clash.
    private struct Signature {
        /// One parameter of a signature.
        struct Parameter {
            let type: EUUID?
            let instanceClassName: String?
            let isMany: Bool
        }

        let name: String
        let parameters: [Parameter]
        let label: String

        /// Whether another signature clashes with this one.
        ///
        /// Two signatures clash if they have the same name and parameters of the same number
        /// and multiplicity, whose types are the same or are different classifiers that
        /// share an instance class name.
        func clashes(with other: Signature) -> Bool {
            guard name == other.name, parameters.count == other.parameters.count else { return false }
            for (left, right) in zip(parameters, other.parameters) {
                guard left.isMany == right.isMany else { return false }
                if left.type != right.type {
                    guard left.type != nil, right.type != nil,
                        let name = left.instanceClassName, name == right.instanceClassName
                    else { return false }
                }
            }
            return true
        }
    }

    /// The instance class name of a classifier, if it has one.
    private func instanceClassName(of type: any EClassifier) -> String? {
        switch type {
        case let value as EClass: value.instanceClassName
        case let value as EDataType: value.instanceClassName
        default: nil
        }
    }

    private func parameter(_ type: (any EClassifier)?, isMany: Bool) -> Signature.Parameter {
        guard let type else { return .init(type: nil, instanceClassName: nil, isMany: isMany) }
        let resolved = canonical(type)
        return .init(type: resolved.id, instanceClassName: instanceClassName(of: resolved), isMany: isMany)
    }

    private func signature(of operation: EOperation) -> Signature {
        let parameters = operation.eParameters
        return Signature(
            name: operation.name,
            parameters: parameters.map { parameter($0.eType, isMany: $0.isMany) },
            label: EcoreValidationMessages.signatureLabel(
                name: operation.name, parameterTypes: parameters.map { typeName($0.eType) }))
    }

    /// Checks a class.
    func checkClass(_ value: EClass) {
        checkName(of: value.id, value.name)
        checkInstanceClassName(of: value.id, value.instanceClassName)
        if value.isInterface && !value.isAbstract {
            report(
                .interfaceIsAbstract, .interfaceNotAbstract, element: value.id, feature: .abstract)
        }
        checkIdentifiers(of: value)
        checkFeatureNames(of: value)
        checkOperationSignatures(of: value)
        checkAccessorSignatures(of: value)
        checkSuperTypes(of: value)
        checkMapEntry(value)
    }

    /// Checks that a class has at most one identifier attribute.
    private func checkIdentifiers(of value: EClass) {
        guard isEnabled(.atMostOneID) else { return }
        let identifiers = allFeatures(of: value).compactMap { $0 as? EAttribute }.filter(\.isID)
        guard identifiers.count > 1,
            identifiers.contains(where: { identifier in
                value.eStructuralFeatures.contains { $0.id == identifier.id }
            })
        else { return }
        report(
            .atMostOneID, .multipleIDs, element: value.id, feature: .eStructuralFeatures,
            arguments: [identifiers[0].name, identifiers[1].name],
            related: identifiers.map(\.id))
    }

    /// Checks that the features of a class, with the inherited ones, have different names.
    private func checkFeatureNames(of value: EClass) {
        guard isEnabled(.uniqueFeatureNames) else { return }
        let features = allFeatures(of: value)
        guard features.count > 1 else { return }
        let supertypeFeatures = value.eSuperTypes.map { Set(allFeatures(of: canonical($0)).map { $0.id }) }
        reportNameClashes(
            in: value.id, feature: .eStructuralFeatures,
            items: features.map { (id: $0.id, name: $0.name) },
            code: .uniqueFeatureNames, duplicate: .duplicateFeatureName,
            similar: .similarFeatureNames,
            isExcused: { ids in supertypeFeatures.contains { $0.isSuperset(of: ids) } })
    }

    /// Checks that the operations of a class have different signatures.
    private func checkOperationSignatures(of value: EClass) {
        guard isEnabled(.uniqueOperationSignatures), value.eOperations.count > 1 else { return }
        let operations = value.eOperations
        let signatures = operations.map { signature(of: $0) }
        for later in operations.indices {
            for earlier in 0..<later where signatures[later].clashes(with: signatures[earlier]) {
                report(
                    .uniqueOperationSignatures, .duplicateOperationSignature, element: value.id,
                    feature: .eOperations,
                    arguments: [signatures[earlier].label, signatures[later].label],
                    related: [operations[earlier].id, operations[later].id])
            }
        }
    }

    /// Whether a feature's accessors use the Boolean getter prefix.
    private func hasBooleanGetter(_ feature: any EStructuralFeature, type: any EClassifier) -> Bool {
        guard !isMany(feature) else { return false }
        if type.name == EcoreDataType.eBoolean.rawValue { return true }
        return instanceClassName(of: type).map(EcoreValidationSyntax.booleanInstanceClassNames.contains)
            ?? false
    }

    /// Whether a feature is many-valued.
    private func isMany(_ feature: any EStructuralFeature) -> Bool {
        switch feature {
        case let value as EAttribute: value.isMany
        case let value as EReference: value.isMany
        default: false
        }
    }

    /// Checks that no operation has the signature of an accessor of a feature of its class.
    private func checkAccessorSignatures(of value: EClass) {
        guard isEnabled(.disjointFeatureAndOperationSignatures), !value.eOperations.isEmpty else { return }
        var accessors: [(signature: Signature, feature: any EStructuralFeature)] = []
        for feature in value.eStructuralFeatures {
            let type: any EClassifier
            var changeable = true
            var unsettable = false
            switch feature {
            case let attribute as EAttribute:
                type = canonical(attribute.eType)
                changeable = attribute.changeable
                unsettable = attribute.unsettable
            case let reference as EReference:
                type = canonical(reference.eType)
                changeable = reference.changeable
                unsettable = reference.unsettable
            default: continue
            }
            guard let first = feature.name.first else { continue }
            let suffix = first.uppercased() + feature.name.dropFirst()
            func accessor(_ prefix: String, _ parameters: [Signature.Parameter] = []) {
                accessors.append((
                    Signature(name: prefix + suffix, parameters: parameters, label: prefix + suffix), feature
                ))
            }
            accessor(hasBooleanGetter(feature, type: type)
                ? EcoreValidationSyntax.booleanGetPrefix : EcoreValidationSyntax.getPrefix)
            if !isMany(feature) && changeable {
                accessor(EcoreValidationSyntax.setPrefix, [parameter(type, isMany: false)])
            }
            if unsettable {
                accessor(EcoreValidationSyntax.isSetPrefix)
                accessor(EcoreValidationSyntax.unsetPrefix)
            }
        }
        for operation in value.eOperations {
            let operationSignature = signature(of: operation)
            for accessor in accessors where operationSignature.clashes(with: accessor.signature) {
                report(
                    .disjointFeatureAndOperationSignatures, .operationClashesWithAccessor,
                    element: value.id, feature: .eOperations,
                    arguments: [operationSignature.label, accessor.feature.name],
                    related: [operation.id, accessor.feature.id])
            }
        }
    }

    /// Checks that a class is not a supertype of itself.
    private func checkSuperTypes(of value: EClass) {
        guard isEnabled(.noCircularSuperTypes), !value.eSuperTypes.isEmpty else { return }
        var seen: Set<EUUID> = []
        var pending = value.eSuperTypes.map { canonical($0) }
        while let next = pending.popLast() {
            if next.id == value.id {
                report(
                    .noCircularSuperTypes, .circularSuperTypes, element: value.id,
                    feature: .eSuperTypes)
                return
            }
            if seen.insert(next.id).inserted { pending.append(contentsOf: next.eSuperTypes.map { canonical($0) }) }
        }
    }

    /// Checks the rules for map entry classes.
    private func checkMapEntry(_ value: EClass) {
        guard isEnabled(.wellFormedMapEntryClass) else { return }
        let entryName = EcoreValidationSyntax.mapEntryInstanceClassName
        if value.instanceClassName == entryName {
            let names = Set(allFeatures(of: value).map { $0.name })
            for required in [EcoreValidationSyntax.mapEntryKey, EcoreValidationSyntax.mapEntryValue]
            where !names.contains(required) {
                report(
                    .wellFormedMapEntryClass, .mapEntryMissingFeature, element: value.id,
                    feature: .eStructuralFeatures, arguments: [required])
            }
        } else if allSuperTypes(of: value).contains(where: { $0.instanceClassName == entryName }) {
            report(
                .wellFormedMapEntryClass, .mapEntryInstanceClassName, element: value.id,
                feature: .instanceClassName)
        }
    }
}
