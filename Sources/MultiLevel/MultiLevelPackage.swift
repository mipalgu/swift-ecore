//
// MultiLevelPackage.swift
// MultiLevel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

/// The bundled linguistic metamodel of multi-level models.
///
/// Every element of a deep model is a linguistic instance of one class of this package:
/// `DeepModel`, `LevelModel`, `Clabject`, `EdgeEnd`, `Feature`, `Slot`, `Value` and
/// `Constraint` (see ``LinguisticClass``). Encoded as instances of this package, a deep model
/// is written and read losslessly as XMI or JSON by the existing serialisers (see
/// ``LinguisticEncoding``), and reflective tools can process it generically.
///
/// Potencies are kept as text (a number or `*`), and an absent optional value as an unset
/// attribute, so that defaults remain distinguishable from explicit values.
public enum MultiLevelPackage {
    /// The package.
    public static let package: EPackage = build()

    /// The class of the package with a name.
    ///
    /// - Parameter linguisticClass: The class.
    /// - Returns: The class with its features.
    public static func eClass(_ linguisticClass: LinguisticClass) -> EClass {
        classes[linguisticClass] ?? EClass(name: linguisticClass.rawValue)
    }

    /// The classes of the package, by name.
    static let classes: [LinguisticClass: EClass] = {
        var classes: [LinguisticClass: EClass] = [:]
        for classifier in package.eClassifiers {
            if let eClass = classifier as? EClass, let name = LinguisticClass(rawValue: eClass.name) {
                classes[name] = eClass
            }
        }
        return classes
    }()

    /// Builds the package.
    private static func build() -> EPackage {
        let string = EcorePackage.dataType(.eString) ?? EDataType(name: EcoreDataType.eString.rawValue)
        let integer = EcorePackage.dataType(.eInt) ?? EDataType(name: EcoreDataType.eInt.rawValue)
        let boolean = EcorePackage.dataType(.eBoolean) ?? EDataType(name: EcoreDataType.eBoolean.rawValue)
        func shell(_ linguisticClass: LinguisticClass) -> EClass {
            EClass(id: identifier(of: linguisticClass), name: linguisticClass.rawValue)
        }
        func attribute(_ feature: LinguisticFeature, _ type: EDataType, many: Bool = false) -> EAttribute {
            EAttribute(name: feature.rawValue, eType: type, upperBound: many ? -1 : 1)
        }
        func reference(
            _ feature: LinguisticFeature, _ target: LinguisticClass, many: Bool = false, containment: Bool = false
        ) -> EReference {
            EReference(name: feature.rawValue, eType: shell(target), upperBound: many ? -1 : 1, containment: containment)
        }
        func make(_ linguisticClass: LinguisticClass, _ features: [any EStructuralFeature]) -> EClass {
            EClass(id: identifier(of: linguisticClass), name: linguisticClass.rawValue, eStructuralFeatures: features)
        }
        let classes: [EClass] = [
            make(.deepModel, [
                attribute(.name, string), attribute(.potencyVariant, string), attribute(.levelCrossing, string),
                reference(.levels, .levelModel, many: true, containment: true),
            ]),
            make(.levelModel, [
                attribute(.name, string), attribute(.potency, string), attribute(.typeModel, string),
                attribute(.extensible, boolean),
                reference(.clabjects, .clabject, many: true, containment: true),
                reference(.constraints, .constraint, many: true, containment: true),
            ]),
            make(.clabject, [
                attribute(.name, string), attribute(.identifier, string), attribute(.kind, string),
                attribute(.potency, string), attribute(.leap, boolean), attribute(.isAbstract, boolean),
                reference(.type, .clabject), reference(.supertypes, .clabject, many: true),
                reference(.source, .edgeEnd, containment: true), reference(.target, .edgeEnd, containment: true),
                reference(.features, .feature, many: true, containment: true),
                reference(.slots, .slot, many: true, containment: true),
                reference(.constraints, .constraint, many: true, containment: true),
            ]),
            make(.edgeEnd, [reference(.clabject, .clabject), attribute(.feature, string)]),
            make(.feature, [
                attribute(.name, string), attribute(.potency, string), attribute(.mutability, string),
                attribute(.dataType, string), reference(.targetClabject, .clabject), attribute(.targetPotency, string),
                attribute(.targetLevel, string), attribute(.lowerBound, integer), attribute(.upperBound, integer),
                attribute(.containment, boolean), attribute(.ordered, boolean), attribute(.unique, boolean),
                attribute(.derived, boolean), attribute(.derivation, string),
                reference(.defaults, .value, many: true, containment: true), reference(.type, .feature),
            ]),
            make(.slot, [attribute(.feature, string), reference(.values, .value, many: true, containment: true)]),
            make(.value, [attribute(.valueKind, string), attribute(.literal, string), reference(.object, .clabject)]),
            make(.constraint, [
                attribute(.name, string), attribute(.potency, string), attribute(.body, string),
                attribute(.language, string),
            ]),
        ]
        return EPackage(
            id: MultiLevelIdentifiers.identifier(for: [MultiLevelSyntax.linguisticNamespaceURI]),
            name: MultiLevelSyntax.linguisticPackageName, nsURI: MultiLevelSyntax.linguisticNamespaceURI,
            nsPrefix: MultiLevelSyntax.linguisticNamespacePrefix, eClassifiers: classes)
    }

    /// The stable identifier of a class of the package.
    private static func identifier(of linguisticClass: LinguisticClass) -> EUUID {
        MultiLevelIdentifiers.identifier(for: [MultiLevelSyntax.linguisticNamespaceURI, linguisticClass.rawValue])
    }
}
