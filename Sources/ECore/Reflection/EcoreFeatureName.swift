//
// EcoreFeatureName.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The names of all structural features of the Ecore metamodel.
///
/// Every feature that the reflective Ecore metamodel (``EcorePackage``) defines is named
/// here exactly once, so that descriptors, reflective access, and navigation by name all
/// share a single authoritative spelling. Several classes share a feature name (for example
/// `name` or `eType`); the owning class identifies the feature uniquely.
///
/// ## Usage
///
/// ```swift
/// let nameFeature = EcorePackage.feature(.name, of: .eNamedElement)
/// ```
public enum EcoreFeatureName: String, CaseIterable, Sendable {
    // MARK: EModelElement, ENamedElement and EAnnotation

    /// The annotations attached to a model element.
    case eAnnotations
    /// The name of a named element.
    case name
    /// The source URI of an annotation.
    case source
    /// The key and value entries of an annotation.
    case details
    /// The model element an annotation is attached to.
    case eModelElement
    /// The objects contained directly by an annotation.
    case contents
    /// The objects an annotation refers to.
    case references
    /// The key of a string map entry.
    case key
    /// The value of a string map entry or an enumeration literal.
    case value

    // MARK: ETypedElement

    /// Whether the values of a typed element are ordered.
    case ordered
    /// Whether the values of a typed element are unique.
    case unique
    /// The lower multiplicity bound.
    case lowerBound
    /// The upper multiplicity bound.
    case upperBound
    /// Whether a typed element is many-valued (derived).
    case many
    /// Whether a typed element is required (derived).
    case required
    /// The type of a typed element.
    case eType
    /// The generic type of a typed element.
    case eGenericType

    // MARK: EClassifier, EDataType, EEnum and EEnumLiteral

    /// The instance class name of a classifier.
    case instanceClassName
    /// The instance class of a classifier (derived).
    case instanceClass
    /// The default value of a classifier (derived).
    case defaultValue
    /// The instance type name of a classifier.
    case instanceTypeName
    /// The package containing a classifier.
    case ePackage
    /// The type parameters of a classifier or operation.
    case eTypeParameters
    /// Whether a data type is serialisable.
    case serializable
    /// The literals of an enumeration.
    case eLiterals
    /// The literal text of an enumeration literal.
    case literal
    /// The enumeration containing a literal.
    case eEnum
    /// The runtime instance of an enumeration literal (derived).
    case instance

    // MARK: EPackage and EFactory

    /// The namespace URI of a package.
    case nsURI
    /// The namespace prefix of a package.
    case nsPrefix
    /// The factory of a package.
    case eFactoryInstance
    /// The classifiers of a package.
    case eClassifiers
    /// The nested packages of a package.
    case eSubpackages
    /// The package containing a package.
    case eSuperPackage

    // MARK: EClass

    /// Whether a class is abstract.
    case abstract
    /// Whether a class is an interface.
    case interface
    /// The direct supertypes of a class.
    case eSuperTypes
    /// The operations declared by a class.
    case eOperations
    /// All attributes of a class including inherited ones.
    case eAllAttributes
    /// All references of a class including inherited ones.
    case eAllReferences
    /// The references declared by a class.
    case eReferences
    /// The attributes declared by a class.
    case eAttributes
    /// All containment references of a class including inherited ones.
    case eAllContainments
    /// All operations of a class including inherited ones.
    case eAllOperations
    /// All structural features of a class including inherited ones.
    case eAllStructuralFeatures
    /// All supertypes of a class, transitively.
    case eAllSuperTypes
    /// The identifying attribute of a class.
    case eIDAttribute
    /// The structural features declared by a class.
    case eStructuralFeatures
    /// The generic supertypes of a class.
    case eGenericSuperTypes
    /// All generic supertypes of a class (derived).
    case eAllGenericSuperTypes

    // MARK: EStructuralFeature, EAttribute and EReference

    /// Whether a feature can be changed.
    case changeable
    /// Whether a feature is volatile.
    case volatile
    /// Whether a feature is transient.
    case transient
    /// The default value literal of a feature.
    case defaultValueLiteral
    /// Whether a feature is unsettable.
    case unsettable
    /// Whether a feature is derived.
    case derived
    /// The class containing a feature or operation.
    case eContainingClass
    /// Whether an attribute identifies its object.
    case iD
    /// The type of an attribute (derived).
    case eAttributeType
    /// Whether a reference is a containment.
    case containment
    /// Whether a reference is a container reference (derived).
    case container
    /// Whether a reference resolves proxies.
    case resolveProxies
    /// The opposite of a reference.
    case eOpposite
    /// The type of a reference (derived).
    case eReferenceType
    /// The key attributes of a reference.
    case eKeys

    // MARK: EOperation, EParameter, ETypeParameter and EGenericType

    /// The parameters of an operation.
    case eParameters
    /// The exceptions of an operation.
    case eExceptions
    /// The generic exceptions of an operation.
    case eGenericExceptions
    /// The operation containing a parameter.
    case eOperation
    /// The bounds of a type parameter.
    case eBounds
    /// The upper bound of a generic type.
    case eUpperBound
    /// The type arguments of a generic type.
    case eTypeArguments
    /// The raw type of a generic type (derived).
    case eRawType
    /// The lower bound of a generic type.
    case eLowerBound
    /// The type parameter of a generic type.
    case eTypeParameter
    /// The classifier of a generic type.
    case eClassifier
}

/// Names of the container navigation properties available on every object.
///
/// These pseudo-properties are answered by the execution engine from the containment
/// structure of the registered models, rather than from a structural feature.
public enum EObjectNavigationProperty: String, CaseIterable, Sendable {
    /// The object containing this object.
    case eContainer
    /// The feature through which the container holds this object.
    case eContainingFeature
    /// The objects directly contained by this object.
    case eContents
    /// All objects contained by this object, transitively and in depth-first order.
    case eAllContents
}
