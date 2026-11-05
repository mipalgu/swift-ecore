//
// JSONMetamodelSyntax.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// The vocabulary of metamodel documents in JSON.
///
/// A metamodel is written as an instance of the Ecore metamodel: every object names its
/// metaclass as `"http://www.eclipse.org/emf/2002/Ecore#//<Metaclass>"`, contained elements
/// are nested under the name of their containment feature, and references are `$ref`
/// objects. This enumeration lists which features of each metaclass contain elements and
/// which refer to them, so that the reader and the writer share one definition.
enum JSONMetamodelSyntax {
    /// The text that precedes the name of a metaclass in an `eClass` value.
    static let classPrefix = EcorePackage.nsURI + JSONSyntax.classFragmentPrefix

    /// The `eClass` value of a metaclass, as in `http://www.eclipse.org/emf/2002/Ecore#//EClass`.
    ///
    /// - Parameter metaclass: The metaclass.
    /// - Returns: The qualified name of the metaclass.
    static func className(_ metaclass: EcoreClassifier) -> String {
        classPrefix + metaclass.rawValue
    }

    /// The metaclass that an `eClass` value names.
    ///
    /// - Parameter value: A qualified name such as `http://www.eclipse.org/emf/2002/Ecore#//EClass`,
    ///   or the bare name of a metaclass.
    /// - Returns: The metaclass, or `nil` if the value names no metaclass of Ecore.
    static func metaclass(named value: String) -> EcoreClassifier? {
        let name = value.hasPrefix(classPrefix) ? String(value.dropFirst(classPrefix.count)) : value
        return EcoreClassifier(rawValue: name)
    }

    /// The type qualifier that a reference to an element of another document records, as in
    /// `ecore:EClass`.
    ///
    /// - Parameter metaclass: The metaclass of the referenced element.
    /// - Returns: The qualifier.
    static func qualifier(_ metaclass: EcoreClassifier) -> String {
        EcorePackage.nsPrefix + String(CrossReferenceSyntax.qualifierSeparator) + metaclass.rawValue
    }

    /// The metaclass that a type qualifier such as `ecore:EClass` names.
    ///
    /// - Parameter qualifier: The qualifier.
    /// - Returns: The metaclass, or `nil` if the qualifier names none.
    static func metaclass(qualifier: String) -> EcoreClassifier? {
        let prefix = EcorePackage.nsPrefix + String(CrossReferenceSyntax.qualifierSeparator)
        guard qualifier.hasPrefix(prefix) else { return nil }
        return EcoreClassifier(rawValue: String(qualifier.dropFirst(prefix.count)))
    }

    /// A feature that contains elements.
    struct Containment {
        /// The feature.
        let feature: EcoreFeatureName

        /// The metaclasses that the contained elements may have; the first is the one an
        /// element without an `eClass` takes.
        let metaclasses: [EcoreClassifier]

        /// Whether the feature holds a list rather than a single element.
        let isMany: Bool

        /// Whether the contained elements have name-based fragment segments.
        ///
        /// The elements that EMF lists among the contents of a model element have them;
        /// generic types are reached by position only.
        let isNamed: Bool
    }

    /// A feature that refers to elements without containing them.
    struct Reference {
        /// The feature.
        let feature: EcoreFeatureName

        /// The declared type of the feature.
        ///
        /// A reference to an element of a different metaclass names that metaclass in its
        /// `eClass`, as emfjson does.
        let type: EcoreClassifier?

        /// Whether the feature holds a list rather than a single reference.
        let isMany: Bool
    }

    /// The annotations that every model element contains.
    static let annotations = Containment(
        feature: .eAnnotations, metaclasses: [.eAnnotation], isMany: true, isNamed: true)

    /// The generic type of a typed element.
    private static let genericType = Containment(
        feature: .eGenericType, metaclasses: [.eGenericType], isMany: false, isNamed: false)

    /// The type parameters of a classifier or operation.
    private static let typeParameters = Containment(
        feature: .eTypeParameters, metaclasses: [.eTypeParameter], isMany: true, isNamed: true)

    /// The type of a typed element.
    private static let type = Reference(feature: .eType, type: .eClassifier, isMany: false)

    /// The features that contain elements, by metaclass, in the order in which EMF lists the
    /// contents of an element (annotations first).
    ///
    /// Annotation details are a map from keys to values and are not listed here.
    ///
    /// - Parameter metaclass: The metaclass of the containing element.
    /// - Returns: The containment features of the metaclass.
    static func containments(of metaclass: EcoreClassifier) -> [Containment] {
        switch metaclass {
        case .ePackage:
            return [
                annotations,
                Containment(
                    feature: .eClassifiers, metaclasses: [.eClass, .eEnum, .eDataType], isMany: true, isNamed: true),
                Containment(feature: .eSubpackages, metaclasses: [.ePackage], isMany: true, isNamed: true),
            ]
        case .eClass:
            return [
                annotations, typeParameters,
                Containment(feature: .eOperations, metaclasses: [.eOperation], isMany: true, isNamed: true),
                Containment(
                    feature: .eStructuralFeatures, metaclasses: [.eAttribute, .eReference], isMany: true,
                    isNamed: true),
                Containment(feature: .eGenericSuperTypes, metaclasses: [.eGenericType], isMany: true, isNamed: false),
            ]
        case .eEnum:
            return [
                annotations, typeParameters,
                Containment(feature: .eLiterals, metaclasses: [.eEnumLiteral], isMany: true, isNamed: true),
            ]
        case .eDataType:
            return [annotations, typeParameters]
        case .eOperation:
            return [
                annotations, typeParameters,
                Containment(feature: .eParameters, metaclasses: [.eParameter], isMany: true, isNamed: true),
                genericType,
                Containment(feature: .eGenericExceptions, metaclasses: [.eGenericType], isMany: true, isNamed: false),
            ]
        case .eAttribute, .eReference, .eParameter:
            return [annotations, genericType]
        case .eTypeParameter:
            return [
                annotations,
                Containment(feature: .eBounds, metaclasses: [.eGenericType], isMany: true, isNamed: false),
            ]
        case .eGenericType:
            return [
                Containment(feature: .eUpperBound, metaclasses: [.eGenericType], isMany: false, isNamed: false),
                Containment(feature: .eTypeArguments, metaclasses: [.eGenericType], isMany: true, isNamed: false),
                Containment(feature: .eLowerBound, metaclasses: [.eGenericType], isMany: false, isNamed: false),
            ]
        default:
            return [annotations]
        }
    }

    /// The features that refer to elements without containing them, by metaclass.
    ///
    /// - Parameter metaclass: The metaclass of the referring element.
    /// - Returns: The reference features of the metaclass.
    static func references(of metaclass: EcoreClassifier) -> [Reference] {
        switch metaclass {
        case .eClass:
            return [Reference(feature: .eSuperTypes, type: .eClass, isMany: true)]
        case .eAttribute, .eParameter:
            return [type]
        case .eReference:
            return [
                type, Reference(feature: .eOpposite, type: .eReference, isMany: false),
                Reference(feature: .eKeys, type: .eAttribute, isMany: true),
            ]
        case .eOperation:
            return [type, Reference(feature: .eExceptions, type: .eClassifier, isMany: true)]
        case .eGenericType:
            return [
                Reference(feature: .eClassifier, type: .eClassifier, isMany: false),
                Reference(feature: .eTypeParameter, type: .eTypeParameter, isMany: false),
            ]
        case .eAnnotation:
            return [Reference(feature: .references, type: nil, isMany: true)]
        default:
            return []
        }
    }
}
