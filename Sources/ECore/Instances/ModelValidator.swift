//
// ModelValidator.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import BigInt
import Foundation

/// Checks the instances of a model against their metamodels.
///
/// The validator reads a ``ResourceSnapshot`` and reports, as ``ModelDiagnostic`` values:
/// - features with fewer values than their lower bound or more than their upper bound,
/// - attribute values that do not conform to the data type, including enumeration literals,
/// - references to objects of the wrong class, and references to objects that do not exist,
/// - identifying attributes with duplicate values, and
/// - instances of abstract classes and interfaces.
///
/// Derived and transient features are not checked. Classes are looked up in the given
/// metamodels by identifier, so a model is checked against the latest definition of each
/// class even before its objects have been rebound.
public struct ModelValidator: Sendable {

    private let classes: [EUUID: EClass]

    /// Creates a validator.
    ///
    /// - Parameter metamodels: The metamodels that the instances conform to.
    public init(metamodels: [EPackage] = []) {
        var classes: [EUUID: EClass] = [:]
        func collect(_ package: EPackage) {
            for case let eClass as EClass in package.eClassifiers { classes[eClass.id] = eClass }
            package.eSubpackages.forEach(collect)
        }
        metamodels.forEach(collect)
        self.classes = classes
    }

    /// Validates every dynamic instance of a snapshot.
    ///
    /// - Parameter snapshot: The model to check.
    /// - Returns: The problems found, in object order and then feature order.
    public func validate(_ snapshot: ResourceSnapshot) -> [ModelDiagnostic] {
        var diagnostics: [ModelDiagnostic] = []
        var identifiers: [String: [EUUID: Int]] = [:]
        for case let object as DynamicEObject in snapshot.objects {
            let eClass = classes[object.eClass.id] ?? object.eClass
            if eClass.isAbstract || eClass.isInterface {
                diagnostics.append(
                    ModelDiagnostic(code: .abstractInstance, objectID: object.id, arguments: [eClass.name]))
            }
            for feature in eClass.eAllStructuralFeatures {
                switch feature {
                case let attribute as EAttribute where !attribute.derived && !attribute.transient:
                    check(attribute, of: object, into: &diagnostics)
                    if attribute.isID, let value = object.eGet(attribute) {
                        identifiers["\(attribute.name)\u{0}\(value)", default: [:]][object.id] = 0
                    }
                case let reference as EReference where !reference.derived && !reference.transient:
                    check(reference, of: object, in: snapshot, into: &diagnostics)
                default: break
                }
            }
        }
        diagnostics.append(contentsOf: duplicates(in: identifiers, of: snapshot))
        return diagnostics
    }

    // MARK: - Attributes and references

    private func check(_ attribute: EAttribute, of object: DynamicEObject, into diagnostics: inout [ModelDiagnostic]) {
        let value = object.eGetWithDefault(attribute)
        let elements = attribute.isMany ? ValueList.elements(of: value) : (value.map { [$0] } ?? [])
        checkBounds(attribute.name, lower: attribute.lowerBound, upper: attribute.upperBound, count: elements.count, of: object, into: &diagnostics)
        for element in elements {
            if let eEnum = attribute.eType as? EEnum {
                guard !Self.isLiteral(element, of: eEnum) else { continue }
                diagnostics.append(
                    ModelDiagnostic(
                        code: .invalidEnumLiteral, objectID: object.id, feature: attribute.name,
                        arguments: [attribute.name, "\(element)", eEnum.name]))
            } else if !Self.conforms(element, to: attribute.eType) {
                diagnostics.append(
                    ModelDiagnostic(
                        code: .invalidValue, objectID: object.id, feature: attribute.name,
                        arguments: [attribute.name, "\(element)", attribute.eType.name]))
            }
        }
    }

    private func check(
        _ reference: EReference, of object: DynamicEObject, in snapshot: ResourceSnapshot,
        into diagnostics: inout [ModelDiagnostic]
    ) {
        let raw = object.eGet(reference)
        let elements = reference.isMany ? ValueList.elements(of: raw) : (raw.map { [$0] } ?? [])
        checkBounds(reference.name, lower: reference.lowerBound, upper: reference.upperBound, count: elements.count, of: object, into: &diagnostics)
        let expected = (reference.eType as? EClass).map { classes[$0.id] ?? $0 }
        for case let id as EUUID in elements {
            guard let target = snapshot.object(id: id) else {
                diagnostics.append(
                    ModelDiagnostic(
                        code: .danglingReference, objectID: object.id, feature: reference.name,
                        arguments: [reference.name, id.uuidString]))
                continue
            }
            guard let expected, let targetClass = target.eClass as? EClass else { continue }
            let actual = classes[targetClass.id] ?? targetClass
            if !Self.isInstance(actual, of: expected) {
                diagnostics.append(
                    ModelDiagnostic(
                        code: .referenceTypeMismatch, objectID: object.id, feature: reference.name,
                        arguments: [reference.name, actual.name, expected.name]))
            }
        }
    }

    private func checkBounds(
        _ name: String, lower: Int, upper: Int, count: Int, of object: DynamicEObject,
        into diagnostics: inout [ModelDiagnostic]
    ) {
        if count < lower {
            diagnostics.append(
                ModelDiagnostic(
                    code: .lowerBound, objectID: object.id, feature: name,
                    arguments: [name, "\(lower)", "\(count)"]))
        }
        if upper >= 0, count > upper {
            diagnostics.append(
                ModelDiagnostic(
                    code: .upperBound, objectID: object.id, feature: name,
                    arguments: [name, "\(upper)", "\(count)"]))
        }
    }

    private func duplicates(in identifiers: [String: [EUUID: Int]], of snapshot: ResourceSnapshot) -> [ModelDiagnostic] {
        var result: [ModelDiagnostic] = []
        let order = Dictionary(uniqueKeysWithValues: snapshot.objects.enumerated().map { ($1.id, $0) })
        for (key, holders) in identifiers where holders.count > 1 {
            let parts = key.split(separator: "\u{0}", maxSplits: 1).map(String.init)
            for id in holders.keys.sorted(by: { order[$0, default: 0] < order[$1, default: 0] }) {
                result.append(
                    ModelDiagnostic(
                        code: .duplicateID, objectID: id, feature: parts[0],
                        arguments: [parts[0], parts.count > 1 ? parts[1] : ""]))
            }
        }
        return result.sorted { (order[$0.objectID] ?? 0, $0.feature ?? "") < (order[$1.objectID] ?? 0, $1.feature ?? "") }
    }

    // MARK: - Conformance

    private static func isInstance(_ candidate: EClass, of expected: EClass) -> Bool {
        candidate.id == expected.id || expected.name == EcoreClassifier.eObject.rawValue
            || candidate.eAllSuperTypes.contains { $0.id == expected.id }
    }

    private static func isLiteral(_ value: any EcoreValue, of eEnum: EEnum) -> Bool {
        switch value {
        case let name as String: return eEnum.getLiteral(name: name) != nil || eEnum.getLiteral(text: name) != nil
        case let number as Int: return eEnum.getLiteral(value: number) != nil
        default: return false
        }
    }

    private static func conforms(_ value: any EcoreValue, to type: any EClassifier) -> Bool {
        guard let dataType = EcoreDataType(rawValue: type.name) else { return true }
        switch dataType {
        case .eString, .eStringObject: return value is String
        case .eBoolean, .eBooleanObject: return value is Bool
        case .eChar, .eCharacterObject: return value is Character
        case .eDate: return value is Date
        case .eInt, .eIntegerObject, .eByte, .eByteObject, .eShort, .eShortObject, .eLong, .eLongObject, .eBigInteger:
            return isInteger(value)
        case .eFloat, .eFloatObject, .eDouble, .eDoubleObject, .eBigDecimal:
            return isInteger(value) || value is Float || value is Double || value is Decimal
        default: return true
        }
    }

    private static func isInteger(_ value: any EcoreValue) -> Bool {
        value is Int || value is Int8 || value is Int16 || value is Int32 || value is Int64 || value is BigInt
    }
}
