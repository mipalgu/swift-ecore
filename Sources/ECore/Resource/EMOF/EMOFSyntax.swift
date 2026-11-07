//
// EMOFSyntax.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// The vocabulary of EMOF documents as the Eclipse Modeling Framework reads and writes them.
///
/// EMOF (Essential MOF) is the subset of the OMG Meta Object Facility that Ecore implements.
/// EMF reads and writes EMOF metamodels (`.emof`) by mapping the names of Ecore onto those of
/// EMOF, and keeps what EMOF cannot express in `xmi:Extension` elements whose `extender` is
/// the Ecore namespace.
///
/// ## Element and attribute names
///
/// | Ecore | EMOF |
/// |---|---|
/// | `EPackage` | `Package` |
/// | `EPackage.nsURI` | `uri` |
/// | `EPackage.eClassifiers` | `ownedType` |
/// | `EPackage.eSubpackages` | `nestedPackage` |
/// | `EClass` | `Class` |
/// | `EClass.abstract` | `isAbstract` |
/// | `EClass.eSuperTypes` | `superClass` |
/// | `EClass.eStructuralFeatures` | `ownedAttribute` |
/// | `EClass.eOperations` | `ownedOperation` |
/// | `EAttribute`, `EReference` | `Property` |
/// | `ETypedElement.eType` | `type` |
/// | `ETypedElement.lowerBound` | `lower` (EMOF default 1) |
/// | `ETypedElement.upperBound` | `upper` (EMOF default 1, `*` for unbounded) |
/// | `ETypedElement.ordered` | `isOrdered` (EMOF default `false`) |
/// | `ETypedElement.unique` | `isUnique` (EMOF default `true`) |
/// | `EStructuralFeature.changeable` | `isReadOnly` (inverted) |
/// | `EStructuralFeature.derived` | `isDerived` |
/// | `EStructuralFeature.defaultValueLiteral` | `default` |
/// | `EAttribute.iD` | `isID` |
/// | `EReference.containment` | `isComposite` |
/// | `EReference.eOpposite` | `opposite` |
/// | `EOperation` | `Operation` |
/// | `EOperation.eParameters` | `ownedParameter` |
/// | `EOperation.eExceptions` | `raisedException` |
/// | `EParameter` | `Parameter` |
/// | `EEnum` | `Enumeration` |
/// | `EEnum.eLiterals` | `ownedLiteral` |
/// | `EEnumLiteral` | `EnumerationLiteral` |
/// | `EDataType` | `PrimitiveType` (and `DataType` when read) |
/// | `EAnnotation` with the source `…/emof.xml#Comment` | `ownedComment` with a `body` |
/// | `EAnnotation` with the EMOF namespace as source | `Tag` with `name`, `value` and `element` |
///
/// The features `nsPrefix`, `instanceClassName`, `instanceTypeName`, `serializable`,
/// `interface`, `volatile`, `transient`, `unsettable`, `resolveProxies` and the `value` of an
/// enumeration literal, all other annotations and the generic types and type parameters are
/// written in an Ecore `xmi:Extension`.
///
/// ## Primitive types
///
/// | Ecore | EMOF |
/// |---|---|
/// | `EString` | `http://schema.omg.org/spec/MOF/2.0/emof.xml#String` |
/// | `EBoolean` | `…/emof.xml#Boolean` |
/// | `EInt` | `…/emof.xml#Integer` |
/// | `EBigInteger` | `…/emof.xml#UnlimitedNatural` |
/// | any other Ecore data type `EX` | `http://www.eclipse.org/emf/2002/Ecore.emof#ecore.EX` |
///
/// When read, `…/emof.xml#Real` is taken as `EDouble`, which EMF does not map.
public enum EMOFSyntax {
    /// The namespace URI of EMOF that EMF writes.
    public static let namespaceURI = "http://schema.omg.org/spec/MOF/2.0/emof.xml"

    /// The older namespace URI of EMOF that EMF also reads.
    public static let legacyNamespaceURI = "http://schema.omg.org/spec/mof/2.0/emof.xmi"

    /// The namespace URIs of EMOF that are read.
    public static let namespaceURIs: Set<String> = [namespaceURI, legacyNamespaceURI]

    /// The namespace URIs of CMOF, whose documents are recognised but not read.
    public static let cmofNamespaceURIs: Set<String> = [
        "http://schema.omg.org/spec/MOF/2.0/cmof.xml", "http://schema.omg.org/spec/mof/2.0/cmof.xmi",
    ]

    /// The prefix of the EMOF namespace in written documents.
    public static let prefix = "emof"

    /// The conventional file extension of EMOF documents, without the leading dot.
    public static let fileExtension = "emof"

    /// The source of the annotations that EMOF writes as comments.
    public static let commentSource = namespaceURI + "#Comment"

    /// The location of the EMOF descriptions of the Ecore data types that EMOF does not define.
    public static let ecoreTypesDocument = "http://www.eclipse.org/emf/2002/Ecore.emof"

    /// The prefix of the fragments of ``ecoreTypesDocument`` before the name of a data type.
    public static let ecoreTypesFragmentPrefix = "ecore."

    /// The Ecore data types that EMOF defines, by Ecore name, with their EMOF names.
    public static let primitiveTypes: [(ecore: String, emof: String)] = [
        ("EString", "String"), ("EBoolean", "Boolean"), ("EInt", "Integer"), ("EBigInteger", "UnlimitedNatural"),
    ]

    /// The EMOF primitive types that are read as an Ecore data type although EMF does not map them.
    static let additionalPrimitiveTypes: [String: String] = ["Real": "EDouble"]

    /// The names of EMOF elements and attributes.
    enum Name {
        static let package = "Package"
        static let `class` = "Class"
        static let property = "Property"
        static let operation = "Operation"
        static let parameter = "Parameter"
        static let enumeration = "Enumeration"
        static let enumerationLiteral = "EnumerationLiteral"
        static let primitiveType = "PrimitiveType"
        static let dataType = "DataType"
        static let tag = "Tag"
        static let uri = "uri"
        static let ownedType = "ownedType"
        static let nestedPackage = "nestedPackage"
        static let isAbstract = "isAbstract"
        static let superClass = "superClass"
        static let ownedAttribute = "ownedAttribute"
        static let ownedOperation = "ownedOperation"
        static let type = "type"
        static let lower = "lower"
        static let upper = "upper"
        static let isOrdered = "isOrdered"
        static let isUnique = "isUnique"
        static let isReadOnly = "isReadOnly"
        static let isDerived = "isDerived"
        static let `default` = "default"
        static let isID = "isID"
        static let isComposite = "isComposite"
        static let opposite = "opposite"
        static let ownedParameter = "ownedParameter"
        static let raisedException = "raisedException"
        static let ownedLiteral = "ownedLiteral"
        static let ownedComment = "ownedComment"
        static let body = "body"
        static let name = "name"
        static let value = "value"
        static let element = "element"
        static let unbounded = "*"
    }

    /// The Ecore features that EMOF keeps in an Ecore extension, as simple values.
    static let extensionFeatures: [EcoreFeatureName] = [
        .nsPrefix, .instanceClassName, .instanceTypeName, .serializable, .interface, .volatile, .transient,
        .unsettable, .resolveProxies, .value,
    ]

    /// The Ecore elements that EMOF keeps in an Ecore extension as they are.
    static let extensionElements: Set<String> = [
        EcoreFeatureName.eAnnotations.rawValue, EcoreFeatureName.eGenericType.rawValue,
        EcoreFeatureName.eGenericSuperTypes.rawValue, EcoreFeatureName.eGenericExceptions.rawValue,
        EcoreFeatureName.eTypeParameters.rawValue,
    ]

    /// The EMOF name of the data type that an Ecore data type is written as.
    ///
    /// - Parameter ecoreName: The name of an Ecore data type, such as `EString`.
    /// - Returns: The EMOF name, such as `String`, or `nil` if EMOF does not define the type.
    static func emofName(ofEcoreType ecoreName: String) -> String? {
        primitiveTypes.first { $0.ecore == ecoreName }?.emof
    }

    /// The Ecore data type that an EMOF primitive type is read as.
    ///
    /// - Parameter emofName: The name of an EMOF primitive type, such as `Integer`.
    /// - Returns: The Ecore name, such as `EInt`, or `nil` if the type is not known.
    static func ecoreName(ofEMOFType emofName: String) -> String? {
        primitiveTypes.first { $0.emof == emofName }?.ecore ?? additionalPrimitiveTypes[emofName]
    }
}
