//
// EcorePackage.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// The reflective Ecore metamodel: the metamodel that describes metamodels.
///
/// `EcorePackage` provides an ``EPackage`` with the namespace URI
/// `http://www.eclipse.org/emf/2002/Ecore` whose classes describe the native metamodel types
/// (``EPackage``, ``EClass``, ``EAttribute``, ``EReference``, ``EEnum``, ``EEnumLiteral``,
/// ``EDataType``, ``EAnnotation``, and so on). Each native object reports the matching
/// descriptor from ``EObject/eClass``, so reflective tools can navigate a loaded `.ecore`
/// by feature name exactly as they navigate any other model.
///
/// The descriptors carry the correct supertypes, feature types, multiplicities, and
/// containment flags. The built-in data types (`EString`, `EInt`, `EBoolean`, and the other
/// members of ``EcoreDataType``) are included as ``EDataType`` classifiers.
///
/// ## Obtaining the Package
///
/// ```swift
/// let ecore = EcorePackage.instance
/// let classDescriptor = EcorePackage.metaClass(.eClass)
/// let supertypes = classDescriptor.eAllSuperTypes.map(\.name)
/// ```
///
/// A ``ResourceSet`` registers the package under its namespace URI, so lookups by URI find it.
public enum EcorePackage {
    /// The name of the Ecore package.
    public static let name = "ecore"

    /// The namespace URI of the Ecore package.
    public static let nsURI = EcoreURI.ecoreNamespace.rawValue

    /// The namespace prefix of the Ecore package.
    public static let nsPrefix = "ecore"

    /// The Ecore package itself.
    ///
    /// The package contains one ``EClass`` per ``EcoreClassifier`` and one ``EDataType`` per
    /// ``EcoreDataType`` that Ecore defines. The same package instance is returned on every
    /// access.
    public static var instance: EPackage { registry.package }

    /// Retrieves the descriptor for a class of the Ecore metamodel.
    ///
    /// - Parameter classifier: The Ecore class to describe.
    /// - Returns: The ``EClass`` descriptor, complete with supertypes and features.
    public static func metaClass(_ classifier: EcoreClassifier) -> EClass {
        registry.classes[classifier] ?? EClass(name: classifier.rawValue)
    }

    /// Retrieves a built-in data type of the Ecore metamodel.
    ///
    /// - Parameter dataType: The built-in data type.
    /// - Returns: The ``EDataType`` classifier, or `nil` if Ecore does not define the type.
    public static func dataType(_ dataType: EcoreDataType) -> EDataType? {
        registry.dataTypes[dataType.rawValue]
    }

    /// Retrieves a classifier of the Ecore package by name.
    ///
    /// - Parameter name: The classifier name, such as `EClass` or `EString`.
    /// - Returns: The matching class or data type, or `nil` if there is none.
    public static func classifier(named name: String) -> (any EClassifier)? {
        if let classifier = EcoreClassifier(rawValue: name) {
            return metaClass(classifier)
        }
        return registry.dataTypes[name]
    }

    /// Retrieves a structural feature of an Ecore class, including inherited ones.
    ///
    /// - Parameters:
    ///   - name: The feature name.
    ///   - classifier: The Ecore class that defines or inherits the feature.
    /// - Returns: The feature, or `nil` if the class has no feature of that name.
    public static func feature(_ name: EcoreFeatureName, of classifier: EcoreClassifier)
        -> (any EStructuralFeature)?
    {
        metaClass(classifier).getStructuralFeature(name: name.rawValue)
    }

    /// Reports whether a classifier is one of the Ecore metamodel's own classes.
    ///
    /// - Parameter classifier: The classifier to test.
    /// - Returns: `true` if the classifier is a descriptor of this package.
    public static func isMetaClass(_ classifier: any EClassifier) -> Bool {
        registry.classByID[classifier.id] != nil
    }

    // MARK: - Internal Lookups

    /// The name of the Ecore feature that has the given identifier.
    static func featureName(forID id: EUUID) -> EcoreFeatureName? {
        registry.featureNames[id]
    }

    /// Replaces a descriptor stand-in by the complete descriptor with the same identity.
    static func canonical(_ classifier: any EClassifier) -> any EClassifier {
        registry.classByID[classifier.id] ?? classifier
    }

    /// Determines whether a reflective value differs from the default of its feature.
    static func isSet(_ value: (any EcoreValue)?, for feature: some EStructuralFeature) -> Bool {
        guard let value else { return false }
        if let array = value as? EcoreValueArray { return !array.values.isEmpty }
        let literal = (feature as? EAttribute)?.defaultValueLiteral
        switch value {
        case let flag as Bool:
            return flag != (literal.flatMap(BooleanString.fromString) ?? false)
        case let number as Int:
            return number != (literal.flatMap { Int($0) } ?? 0)
        case let text as String:
            return !text.isEmpty
        default:
            return true
        }
    }

    // MARK: - Registry

    private static let registry = Registry()

    /// The immutable lookup tables for the reflective package.
    private struct Registry: Sendable {
        let package: EPackage
        let classes: [EcoreClassifier: EClass]
        let classByID: [EUUID: EClass]
        let dataTypes: [String: EDataType]
        let featureNames: [EUUID: EcoreFeatureName]

        init() {
            var builder = EcorePackageBuilder()
            let package = builder.build()
            var classes: [EcoreClassifier: EClass] = [:]
            var classByID: [EUUID: EClass] = [:]
            var dataTypes: [String: EDataType] = [:]
            var featureNames: [EUUID: EcoreFeatureName] = [:]
            for classifier in package.eClassifiers {
                if let eClass = classifier as? EClass {
                    classByID[eClass.id] = eClass
                    if let known = EcoreClassifier(rawValue: eClass.name) {
                        classes[known] = eClass
                    }
                    for feature in eClass.eStructuralFeatures {
                        if let name = EcoreFeatureName(rawValue: feature.name) {
                            featureNames[feature.id] = name
                        }
                    }
                } else if let dataType = classifier as? EDataType {
                    dataTypes[dataType.name] = dataType
                }
            }
            self.package = package
            self.classes = classes
            self.classByID = classByID
            self.dataTypes = dataTypes
            self.featureNames = featureNames
        }
    }
}

// MARK: - Builder

/// Constructs the descriptors of the reflective Ecore package from a declarative table.
private struct EcorePackageBuilder {
    /// Identifies a feature by its owning class and name.
    struct FeatureKey: Hashable {
        let owner: EcoreClassifier
        let name: EcoreFeatureName
    }

    /// Describes a feature of an Ecore class.
    struct FeatureSpec {
        enum Kind {
            case attribute(EcoreDataType)
            case reference(EcoreClassifier, containment: Bool, opposite: FeatureKey?)
        }

        var name: EcoreFeatureName
        var kind: Kind
        var lowerBound = 0
        var upperBound = 1
        var defaultValueLiteral: String?
        var changeable = true
        var volatile = false
        var transient = false
        var derived = false
        var unsettable = false
        var resolveProxies = true
    }

    /// Describes a class of the Ecore metamodel.
    struct ClassSpec {
        var classifier: EcoreClassifier
        var isAbstract = false
        var superTypes: [EcoreClassifier] = []
        var features: [FeatureSpec] = []
    }

    // MARK: Specification helpers

    static func attribute(
        _ name: EcoreFeatureName, _ type: EcoreDataType, lower: Int = 0, upper: Int = 1,
        defaultLiteral: String? = nil, derived: Bool = false, unsettable: Bool = false
    ) -> FeatureSpec {
        FeatureSpec(
            name: name, kind: .attribute(type), lowerBound: lower, upperBound: upper,
            defaultValueLiteral: defaultLiteral, changeable: !derived, volatile: derived,
            transient: derived, derived: derived, unsettable: unsettable)
    }

    static func reference(
        _ name: EcoreFeatureName, _ target: EcoreClassifier, lower: Int = 0, upper: Int = 1,
        containment: Bool = false, opposite: (EcoreClassifier, EcoreFeatureName)? = nil,
        derived: Bool = false, unsettable: Bool = false, resolveProxies: Bool = true,
        transient: Bool = false
    ) -> FeatureSpec {
        FeatureSpec(
            name: name,
            kind: .reference(
                target, containment: containment,
                opposite: opposite.map { FeatureKey(owner: $0.0, name: $0.1) }),
            lowerBound: lower, upperBound: upper, changeable: !derived, volatile: derived,
            transient: derived || transient, derived: derived, unsettable: unsettable,
            resolveProxies: resolveProxies)
    }

    static let many = -1

    /// The Ecore classes in dependency order: supertypes precede their subtypes.
    static var specifications: [ClassSpec] {
        [
            ClassSpec(
                classifier: .eModelElement, isAbstract: true,
                features: [
                    reference(
                        .eAnnotations, .eAnnotation, upper: many, containment: true,
                        opposite: (.eAnnotation, .eModelElement))
                ]),
            ClassSpec(
                classifier: .eNamedElement, isAbstract: true, superTypes: [.eModelElement],
                features: [attribute(.name, .eString)]),
            ClassSpec(
                classifier: .eTypedElement, isAbstract: true, superTypes: [.eNamedElement],
                features: [
                    attribute(.ordered, .eBoolean, defaultLiteral: "true"),
                    attribute(.unique, .eBoolean, defaultLiteral: "true"),
                    attribute(.lowerBound, .eInt),
                    attribute(.upperBound, .eInt, defaultLiteral: "1"),
                    attribute(.many, .eBoolean, derived: true),
                    attribute(.required, .eBoolean, derived: true),
                    reference(.eType, .eClassifier, unsettable: true),
                    reference(
                        .eGenericType, .eGenericType, containment: true, unsettable: true,
                        resolveProxies: false),
                ]),
            ClassSpec(
                classifier: .eClassifier, isAbstract: true, superTypes: [.eNamedElement],
                features: [
                    attribute(.instanceClassName, .eString, unsettable: true),
                    attribute(.instanceClass, .eJavaClass, derived: true),
                    attribute(.defaultValue, .eJavaObject, derived: true),
                    attribute(.instanceTypeName, .eString, unsettable: true),
                    reference(
                        .ePackage, .ePackage, opposite: (.ePackage, .eClassifiers),
                        resolveProxies: false, transient: true),
                    reference(
                        .eTypeParameters, .eTypeParameter, upper: many, containment: true,
                        unsettable: true),
                ]),
            ClassSpec(
                classifier: .eDataType, superTypes: [.eClassifier],
                features: [attribute(.serializable, .eBoolean, defaultLiteral: "true")]),
            ClassSpec(
                classifier: .eEnum, superTypes: [.eDataType],
                features: [
                    reference(
                        .eLiterals, .eEnumLiteral, upper: many, containment: true,
                        opposite: (.eEnumLiteral, .eEnum))
                ]),
            ClassSpec(
                classifier: .eEnumLiteral, superTypes: [.eNamedElement],
                features: [
                    attribute(.value, .eInt),
                    attribute(.instance, .eEnumerator, derived: true),
                    attribute(.literal, .eString),
                    reference(
                        .eEnum, .eEnum, opposite: (.eEnum, .eLiterals), resolveProxies: false,
                        transient: true),
                ]),
            ClassSpec(
                classifier: .ePackage, superTypes: [.eNamedElement],
                features: [
                    attribute(.nsURI, .eString),
                    attribute(.nsPrefix, .eString),
                    reference(
                        .eFactoryInstance, .eFactory, lower: 1,
                        opposite: (.eFactory, .ePackage), unsettable: true,
                        resolveProxies: false),
                    reference(
                        .eClassifiers, .eClassifier, upper: many, containment: true,
                        opposite: (.eClassifier, .ePackage)),
                    reference(
                        .eSubpackages, .ePackage, upper: many, containment: true,
                        opposite: (.ePackage, .eSuperPackage)),
                    reference(
                        .eSuperPackage, .ePackage, opposite: (.ePackage, .eSubpackages),
                        resolveProxies: false, transient: true),
                ]),
            ClassSpec(
                classifier: .eFactory, superTypes: [.eModelElement],
                features: [
                    reference(
                        .ePackage, .ePackage, lower: 1, opposite: (.ePackage, .eFactoryInstance),
                        resolveProxies: false, transient: true)
                ]),
            ClassSpec(
                classifier: .eClass, superTypes: [.eClassifier],
                features: [
                    attribute(.abstract, .eBoolean),
                    attribute(.interface, .eBoolean),
                    reference(.eSuperTypes, .eClass, upper: many, unsettable: true),
                    reference(
                        .eOperations, .eOperation, upper: many, containment: true,
                        opposite: (.eOperation, .eContainingClass)),
                    reference(.eAllAttributes, .eAttribute, upper: many, derived: true),
                    reference(.eAllReferences, .eReference, upper: many, derived: true),
                    reference(.eReferences, .eReference, upper: many, derived: true),
                    reference(.eAttributes, .eAttribute, upper: many, derived: true),
                    reference(.eAllContainments, .eReference, upper: many, derived: true),
                    reference(.eAllOperations, .eOperation, upper: many, derived: true),
                    reference(
                        .eAllStructuralFeatures, .eStructuralFeature, upper: many, derived: true),
                    reference(.eAllSuperTypes, .eClass, upper: many, derived: true),
                    reference(.eIDAttribute, .eAttribute, derived: true),
                    reference(
                        .eStructuralFeatures, .eStructuralFeature, upper: many,
                        containment: true, opposite: (.eStructuralFeature, .eContainingClass)),
                    reference(
                        .eGenericSuperTypes, .eGenericType, upper: many, containment: true,
                        unsettable: true, resolveProxies: false),
                    reference(
                        .eAllGenericSuperTypes, .eGenericType, upper: many, derived: true),
                ]),
            ClassSpec(
                classifier: .eStructuralFeature, isAbstract: true, superTypes: [.eTypedElement],
                features: [
                    attribute(.changeable, .eBoolean, defaultLiteral: "true"),
                    attribute(.volatile, .eBoolean),
                    attribute(.transient, .eBoolean),
                    attribute(.defaultValueLiteral, .eString),
                    attribute(.defaultValue, .eJavaObject, derived: true),
                    attribute(.unsettable, .eBoolean),
                    attribute(.derived, .eBoolean),
                    reference(
                        .eContainingClass, .eClass, opposite: (.eClass, .eStructuralFeatures),
                        resolveProxies: false, transient: true),
                ]),
            ClassSpec(
                classifier: .eAttribute, superTypes: [.eStructuralFeature],
                features: [
                    attribute(.iD, .eBoolean),
                    reference(.eAttributeType, .eDataType, lower: 1, derived: true),
                ]),
            ClassSpec(
                classifier: .eReference, superTypes: [.eStructuralFeature],
                features: [
                    attribute(.containment, .eBoolean),
                    attribute(.container, .eBoolean, derived: true),
                    attribute(.resolveProxies, .eBoolean, defaultLiteral: "true"),
                    reference(.eOpposite, .eReference),
                    reference(.eReferenceType, .eClass, lower: 1, derived: true),
                    reference(.eKeys, .eAttribute, upper: many),
                ]),
            ClassSpec(
                classifier: .eOperation, superTypes: [.eTypedElement],
                features: [
                    reference(
                        .eContainingClass, .eClass, opposite: (.eClass, .eOperations),
                        resolveProxies: false, transient: true),
                    reference(
                        .eTypeParameters, .eTypeParameter, upper: many, containment: true,
                        unsettable: true),
                    reference(
                        .eParameters, .eParameter, upper: many, containment: true,
                        opposite: (.eParameter, .eOperation)),
                    reference(.eExceptions, .eClassifier, upper: many, unsettable: true),
                    reference(
                        .eGenericExceptions, .eGenericType, upper: many, containment: true,
                        unsettable: true, resolveProxies: false),
                ]),
            ClassSpec(
                classifier: .eParameter, superTypes: [.eTypedElement],
                features: [
                    reference(
                        .eOperation, .eOperation, opposite: (.eOperation, .eParameters),
                        resolveProxies: false, transient: true)
                ]),
            ClassSpec(
                classifier: .eTypeParameter, superTypes: [.eNamedElement],
                features: [
                    reference(
                        .eBounds, .eGenericType, upper: many, containment: true,
                        unsettable: true, resolveProxies: false)
                ]),
            ClassSpec(
                classifier: .eGenericType,
                features: [
                    reference(
                        .eUpperBound, .eGenericType, containment: true, unsettable: true,
                        resolveProxies: false),
                    reference(
                        .eTypeArguments, .eGenericType, upper: many, containment: true,
                        unsettable: true, resolveProxies: false),
                    reference(.eRawType, .eClassifier, lower: 1, derived: true),
                    reference(
                        .eLowerBound, .eGenericType, containment: true, unsettable: true,
                        resolveProxies: false),
                    reference(.eTypeParameter, .eTypeParameter, unsettable: true),
                    reference(.eClassifier, .eClassifier, unsettable: true),
                ]),
            ClassSpec(
                classifier: .eAnnotation, superTypes: [.eModelElement],
                features: [
                    attribute(.source, .eString),
                    reference(
                        .details, .eStringToStringMapEntry, upper: many, containment: true,
                        resolveProxies: false),
                    reference(
                        .eModelElement, .eModelElement,
                        opposite: (.eModelElement, .eAnnotations), resolveProxies: false,
                        transient: true),
                    reference(.contents, .eObject, upper: many, containment: true),
                    reference(.references, .eObject, upper: many),
                ]),
            ClassSpec(
                classifier: .eStringToStringMapEntry,
                features: [
                    attribute(.key, .eString),
                    attribute(.value, .eString),
                ]),
            ClassSpec(classifier: .eObject),
        ]
    }

    // MARK: Construction

    /// Builds the package with all of its classes and data types.
    mutating func build() -> EPackage {
        let specs = Self.specifications
        var classIDs: [EcoreClassifier: EUUID] = [:]
        var featureIDs: [FeatureKey: EUUID] = [:]
        for spec in specs {
            classIDs[spec.classifier] = EUUID()
            for feature in spec.features {
                featureIDs[FeatureKey(owner: spec.classifier, name: feature.name)] = EUUID()
            }
        }

        var dataTypes: [EcoreDataType: EDataType] = [:]
        for type in EcoreDataType.allCases where type != .eStringObject {
            dataTypes[type] = EDataType(name: type.rawValue)
        }

        func stand(in classifier: EcoreClassifier) -> EClass {
            EClass(id: classIDs[classifier] ?? EUUID(), name: classifier.rawValue)
        }

        var built: [EcoreClassifier: EClass] = [:]
        for spec in specs {
            var features: [any EStructuralFeature] = []
            for feature in spec.features {
                let key = FeatureKey(owner: spec.classifier, name: feature.name)
                let id = featureIDs[key] ?? EUUID()
                switch feature.kind {
                case .attribute(let type):
                    features.append(
                        EAttribute(
                            id: id, name: feature.name.rawValue,
                            eType: dataTypes[type] ?? EDataType(name: type.rawValue),
                            lowerBound: feature.lowerBound, upperBound: feature.upperBound,
                            changeable: feature.changeable, volatile: feature.volatile,
                            transient: feature.transient,
                            defaultValueLiteral: feature.defaultValueLiteral,
                            unsettable: feature.unsettable, derived: feature.derived))
                case .reference(let target, let containment, let opposite):
                    features.append(
                        EReference(
                            id: id, name: feature.name.rawValue, eType: stand(in: target),
                            lowerBound: feature.lowerBound, upperBound: feature.upperBound,
                            changeable: feature.changeable, volatile: feature.volatile,
                            transient: feature.transient, containment: containment,
                            opposite: opposite.flatMap { featureIDs[$0] },
                            resolveProxies: feature.resolveProxies,
                            unsettable: feature.unsettable, derived: feature.derived))
                }
            }
            built[spec.classifier] = EClass(
                id: classIDs[spec.classifier] ?? EUUID(), name: spec.classifier.rawValue,
                isAbstract: spec.isAbstract,
                eSuperTypes: spec.superTypes.compactMap { built[$0] },
                eStructuralFeatures: features)
        }

        var classifiers: [any EClassifier] = []
        for classifier in EcoreClassifier.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            if let eClass = built[classifier] { classifiers.append(eClass) }
        }
        for type in EcoreDataType.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            if let dataType = dataTypes[type] { classifiers.append(dataType) }
        }
        return EPackage(
            name: EcorePackage.name, nsURI: EcorePackage.nsURI, nsPrefix: EcorePackage.nsPrefix,
            eClassifiers: classifiers)
    }
}
