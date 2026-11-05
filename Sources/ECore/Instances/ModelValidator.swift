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
///   following the multiplicity rules of the Eclipse Modeling Framework (see below),
/// - attribute values that do not conform to the data type, including enumeration literals,
///   where only the values that a model sets are checked, as in the Eclipse Modeling
///   Framework, so the default of an unset attribute is never reported,
/// - references to objects of the wrong class, and references to objects that do not exist,
/// - identifying attributes with duplicate values, and
/// - instances of abstract classes and interfaces.
///
/// Each element of a many-valued feature counts as one value, and a single value that a
/// many-valued feature holds without a list counts as one value. Many-valued features are
/// checked against both bounds; an upper bound applies to many-valued features only. A
/// required single-valued feature is satisfied when it reads as a value, so an unset feature
/// that reads as a default, such as the first literal of an enumeration, `false` or zero for
/// a primitive type, or its default value literal, is satisfied, whereas one without a
/// default, such as a string or a reference, is not. An unsettable feature, which
/// distinguishes being unset from holding its default, must be set. The option
/// ``Options/requiresExplicitValues`` makes every required single-valued feature need a
/// value of its own.
///
/// Derived and transient features are not checked. Classes are looked up in the given
/// metamodels by identifier, so a model is checked against the latest definition of each
/// class even before its objects have been rebound.
public struct ModelValidator: Sendable {
    /// The settings that control validation.
    public struct Options: Sendable, Hashable {
        /// Whether a required single-valued feature must be set, even if it reads as a default.
        ///
        /// When this is `false`, as in the Eclipse Modeling Framework, a required feature that
        /// is unset but reads as a default, such as the first literal of an enumeration, zero
        /// for a primitive number, or its default value literal, is satisfied. When it is
        /// `true`, every required single-valued feature that the model does not set violates
        /// its lower bound, whatever its type. The option adds only this requirement: the
        /// default of an unset attribute is still not checked against the attribute type.
        ///
        /// Turn this on to check models written by hand or migrated from another format,
        /// where an omitted value is more likely a mistake than a deliberate default. Models
        /// that the Eclipse Modeling Framework saves omit values equal to the default of a
        /// feature that is not unsettable, so such models may fail this stricter check
        /// although Eclipse accepts them.
        public var requiresExplicitValues: Bool

        /// Creates options.
        ///
        /// - Parameter requiresExplicitValues: Whether a required single-valued feature must
        ///   be set even if it reads as a default (`false` by default, as in Eclipse).
        public init(requiresExplicitValues: Bool = false) {
            self.requiresExplicitValues = requiresExplicitValues
        }
    }

    /// The settings that control validation.
    public var options: Options

    private let classes: [EUUID: EClass]

    /// Creates a validator.
    ///
    /// - Parameters:
    ///   - metamodels: The metamodels that the instances conform to.
    ///   - options: The settings that control validation (the defaults follow the Eclipse
    ///     Modeling Framework).
    public init(metamodels: [EPackage] = [], options: Options = Options()) {
        self.options = options
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
        let elements = Self.elements(of: object.eGet(attribute), isMany: attribute.isMany)
        let multiplicity = Multiplicity(
            lower: attribute.lowerBound, upper: attribute.upperBound, isMany: attribute.isMany,
            unsettable: attribute.unsettable)
        checkBounds(
            attribute.name, multiplicity, count: count(of: attribute, multiplicity, elements: elements, in: object),
            of: object, into: &diagnostics)
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
        let elements = Self.elements(of: object.eGet(reference), isMany: reference.isMany)
        let multiplicity = Multiplicity(
            lower: reference.lowerBound, upper: reference.upperBound, isMany: reference.isMany,
            unsettable: reference.unsettable)
        checkBounds(
            reference.name, multiplicity, count: count(of: reference, multiplicity, elements: elements, in: object),
            of: object, into: &diagnostics)
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

    /// The values that a feature value holds.
    ///
    /// - Parameters:
    ///   - value: The value that the object sets for the feature.
    ///   - isMany: Whether the feature is many-valued.
    /// - Returns: The elements of a list held by a many-valued feature, a single value on its
    ///   own, or no elements for `nil`.
    private static func elements(of value: (any EcoreValue)?, isMany: Bool) -> [any EcoreValue] {
        guard let value else { return [] }
        guard isMany, ValueList.isList(value) else { return [value] }
        return ValueList.elements(of: value)
    }

    /// The number of values that a feature has for its bounds.
    ///
    /// - Parameters:
    ///   - feature: The feature to count.
    ///   - multiplicity: The bounds of the feature.
    ///   - elements: The values that the object sets for the feature.
    ///   - object: The object that holds the values.
    /// - Returns: The number of elements of a many-valued feature; for a single-valued
    ///   feature, one if it is set or reads as a value that counts, and zero otherwise.
    private func count(
        of feature: some EStructuralFeature, _ multiplicity: Multiplicity, elements: [any EcoreValue],
        in object: DynamicEObject
    ) -> Int {
        guard !multiplicity.isMany else { return elements.count }
        if object.eIsSet(feature) { return 1 }
        guard !options.requiresExplicitValues, !multiplicity.unsettable else { return 0 }
        return EcoreDefaultValue.readsAsValueWhileUnset(feature) ? 1 : 0
    }

    /// Reports the bounds that the values of a feature violate.
    ///
    /// - Parameters:
    ///   - name: The name of the feature.
    ///   - multiplicity: The bounds of the feature.
    ///   - count: The number of values of the feature.
    ///   - object: The object that holds the values.
    ///   - diagnostics: The diagnostics to append to.
    private func checkBounds(
        _ name: String, _ multiplicity: Multiplicity, count: Int, of object: DynamicEObject,
        into diagnostics: inout [ModelDiagnostic]
    ) {
        if count < multiplicity.lower {
            diagnostics.append(
                ModelDiagnostic(
                    code: .lowerBound, objectID: object.id, feature: name,
                    arguments: [name, "\(multiplicity.lower)", "\(count)"]))
        }
        if multiplicity.isMany, multiplicity.upper > 0, count > multiplicity.upper {
            diagnostics.append(
                ModelDiagnostic(
                    code: .upperBound, objectID: object.id, feature: name,
                    arguments: [name, "\(multiplicity.upper)", "\(count)"]))
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

/// The bounds of a structural feature and whether it distinguishes being unset.
private struct Multiplicity {
    /// The least number of values.
    let lower: Int
    /// The greatest number of values, or a negative number if there is no limit.
    let upper: Int
    /// Whether the feature holds a list of values.
    let isMany: Bool
    /// Whether the feature distinguishes being unset from holding its default.
    let unsettable: Bool
}
