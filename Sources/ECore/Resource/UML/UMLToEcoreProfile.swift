//
// UMLToEcoreProfile.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

extension UMLToEcore {
    /// The namespace URIs under which documents apply the Ecore profile of Eclipse UML2.
    public static let ecoreProfileNamespaces = [
        UMLNamespaces.ecoreProfile, "http://www.eclipse.org/uml2/schemas/Ecore/4",
        "http://www.eclipse.org/uml2/schemas/Ecore/3",
    ]

    /// Registers a description of the stereotypes of the Ecore profile with a resource set.
    ///
    /// The applications of the Ecore profile in a UML model can be read without the profile,
    /// but then a tagged value with several values, such as `annotations`, that is written as
    /// child elements loses its text. With this description registered before the model is
    /// read, every tagged value is read with its type and ``UMLFormat`` does not warn about the
    /// profile. The description lists the stereotypes and tagged values that the conversion
    /// applies; it is registered under every namespace of ``ecoreProfileNamespaces`` under
    /// which no package is registered yet.
    ///
    /// ```swift
    /// let resourceSet = ResourceSet()
    /// await UMLToEcore.registerEcoreProfile(in: resourceSet)
    /// let model = try await UMLFormat.read(url: modelURL, resourceSet: resourceSet)
    /// let metamodel = try await UMLToEcore.convert(model.resource)
    /// ```
    ///
    /// - Parameter resourceSet: The resource set with which the description is registered.
    public static func registerEcoreProfile(in resourceSet: ResourceSet) async {
        let package = ecoreProfilePackage
        for namespace in ecoreProfileNamespaces where await resourceSet.getMetamodel(uri: namespace) == nil {
            await resourceSet.registerMetamodel(package, uri: namespace)
        }
    }

    /// The description of the stereotypes of the Ecore profile and their tagged values.
    ///
    /// Each stereotype is a class with a reference for each metaclass it extends (`base_Class`
    /// and so on) and an attribute or reference for each of its tagged values, including those
    /// it inherits within the profile.
    static let ecoreProfilePackage: EPackage = {
        typealias Stereotype = Syntax.Stereotype
        typealias Tag = Syntax.Tag
        let string = EcorePackage.classifier(named: EcoreDataType.eString.rawValue) ?? EDataType(name: EcoreDataType.eString.rawValue)
        let boolean = EcorePackage.classifier(named: EcoreDataType.eBoolean.rawValue)
            ?? EDataType(name: EcoreDataType.eBoolean.rawValue)
        let object = EcorePackage.metaClass(.eObject)
        func base(_ metaclasses: [String]) -> [any EStructuralFeature] {
            metaclasses.map { EReference(name: Syntax.metaclassRolePrefix + $0, eType: object) }
        }
        func text(_ names: [String]) -> [any EStructuralFeature] { names.map { EAttribute(name: $0, eType: string) } }
        func flags(_ names: [String]) -> [any EStructuralFeature] { names.map { EAttribute(name: $0, eType: boolean) } }
        let annotations: [any EStructuralFeature] = [EAttribute(name: Tag.annotations, eType: string, upperBound: -1)]
        let namedElement = text([Tag.xmlName]) + annotations
        let classifier = namedElement + text([Tag.instanceClassName])
        let feature = flags([Tag.isTransient, Tag.isUnsettable, Tag.isVolatile])
            + text([Tag.xmlNamespace, Tag.xmlFeatureKind, Tag.visibility]) + namedElement
        typealias Metaclass = Syntax.Metaclass
        let stereotypes: [(String, [any EStructuralFeature])] = [
            (Stereotype.ePackage, base([Metaclass.package])
                + text([Tag.packageName, Tag.nsPrefix, Tag.nsURI, Tag.basePackage, Tag.prefix]) + annotations),
            (Stereotype.eClass, base([Metaclass.class, Metaclass.interface, Metaclass.dataType, Metaclass.association])
                + text([Tag.className, Tag.xmlContentKind]) + classifier),
            (Stereotype.eDataType, base([Metaclass.primitiveType, Metaclass.dataType]) + text([Tag.dataTypeName])
                + classifier),
            (Stereotype.eEnum, base([Metaclass.enumeration]) + text([Tag.enumName]) + classifier),
            (Stereotype.eEnumLiteral, base([Metaclass.enumerationLiteral]) + text([Tag.enumLiteralName, Tag.literal])
                + namedElement),
            (Stereotype.eOperation, base([Metaclass.operation]) + text([Tag.operationName, Tag.visibility])
                + annotations),
            (Stereotype.eParameter, base([Metaclass.parameter]) + text([Tag.parameterName]) + annotations),
            (Stereotype.eAttribute, base([Metaclass.property]) + text([Tag.attributeName]) + flags([Tag.isID])
                + feature),
            (Stereotype.eReference, base([Metaclass.property]) + text([Tag.referenceName])
                + flags([Tag.isResolveProxies]) + [EReference(name: Tag.keys, eType: object, upperBound: -1)] + feature),
            (Stereotype.eTypeParameter, base([Metaclass.templateParameter])
                + [EReference(name: Tag.bounds, eType: object, upperBound: -1)]),
            (Stereotype.eGenericType, base([Metaclass.class, Metaclass.interface, Metaclass.dataType])
                + [EReference(name: Tag.upperBound, eType: object), EReference(name: Tag.lowerBound, eType: object)]),
        ]
        return EPackage(
            name: Syntax.ecoreProfileName, nsURI: UMLNamespaces.ecoreProfile, nsPrefix: Syntax.ecoreProfileName,
            eClassifiers: stereotypes.map { EClass(name: $0.0, eStructuralFeatures: $0.1) })
    }()
}
