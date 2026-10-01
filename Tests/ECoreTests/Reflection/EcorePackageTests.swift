//
// EcorePackageTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Reflective Ecore Package Tests")
struct EcorePackageTests {
    private func feature(_ name: EcoreFeatureName, of classifier: EcoreClassifier) throws
        -> any EStructuralFeature
    {
        try #require(EcorePackage.feature(name, of: classifier))
    }

    @Test("Package identity")
    func packageIdentity() {
        let package = EcorePackage.instance
        #expect(package.name == "ecore")
        #expect(package.nsURI == "http://www.eclipse.org/emf/2002/Ecore")
        #expect(package.nsPrefix == "ecore")
        #expect(EcorePackage.instance.id == package.id)
    }

    @Test("Package holds every Ecore class and data type", arguments: EcoreClassifier.allCases)
    func packageHoldsClass(classifier: EcoreClassifier) throws {
        let found = try #require(EcorePackage.instance.getEClass(classifier.rawValue))
        #expect(found.id == EcorePackage.metaClass(classifier).id)
        #expect(EcorePackage.classifier(named: classifier.rawValue)?.id == found.id)
    }

    @Test("Built-in data types are classifiers of the package")
    func dataTypes() throws {
        for type in EcoreDataType.allCases where type != .eStringObject {
            let dataType = try #require(EcorePackage.dataType(type))
            #expect(dataType.name == type.rawValue)
            #expect(EcorePackage.instance.getEDataType(type.rawValue)?.id == dataType.id)
        }
        #expect(EcorePackage.dataType(.eStringObject) == nil)
        #expect(EcorePackage.classifier(named: "NoSuchClassifier") == nil)
    }

    @Test("Classifier count covers classes and data types")
    func classifierCount() {
        let classCount = EcoreClassifier.allCases.count
        let dataTypeCount = EcoreDataType.allCases.count - 1
        #expect(EcorePackage.instance.eClassifiers.count == classCount + dataTypeCount)
    }

    @Test("Abstract classes")
    func abstractClasses() {
        let abstract: [EcoreClassifier] = [
            .eModelElement, .eNamedElement, .eTypedElement, .eClassifier, .eStructuralFeature,
        ]
        for classifier in EcoreClassifier.allCases {
            #expect(EcorePackage.metaClass(classifier).isAbstract == abstract.contains(classifier))
        }
    }

    @Test(
        "Supertype chains follow the Ecore hierarchy",
        arguments: [
            (EcoreClassifier.eAttribute,
             ["EModelElement", "ENamedElement", "ETypedElement", "EStructuralFeature"]),
            (.eReference, ["EModelElement", "ENamedElement", "ETypedElement", "EStructuralFeature"]),
            (.eOperation, ["EModelElement", "ENamedElement", "ETypedElement"]),
            (.eParameter, ["EModelElement", "ENamedElement", "ETypedElement"]),
            (.eClass, ["EModelElement", "ENamedElement", "EClassifier"]),
            (.eDataType, ["EModelElement", "ENamedElement", "EClassifier"]),
            (.eEnum, ["EModelElement", "ENamedElement", "EClassifier", "EDataType"]),
            (.eEnumLiteral, ["EModelElement", "ENamedElement"]),
            (.ePackage, ["EModelElement", "ENamedElement"]),
            (.eFactory, ["EModelElement"]),
            (.eAnnotation, ["EModelElement"]),
            (.eTypeParameter, ["EModelElement", "ENamedElement"]),
            (.eModelElement, []),
            (.eStringToStringMapEntry, []),
            (.eGenericType, []),
        ])
    func supertypes(classifier: EcoreClassifier, expected: [String]) {
        let descriptor = EcorePackage.metaClass(classifier)
        #expect(descriptor.eAllSuperTypes.map(\.name) == expected)
    }

    @Test("Direct supertypes are declared in order")
    func directSupertypes() {
        #expect(EcorePackage.metaClass(.eEnum).eSuperTypes.map(\.name) == ["EDataType"])
        #expect(EcorePackage.metaClass(.eReference).eSuperTypes.map(\.name) == ["EStructuralFeature"])
    }

    @Test("Inherited features come first in declaration order")
    func allStructuralFeaturesOrder() {
        let names = EcorePackage.metaClass(.eReference).eAllStructuralFeatures.map(\.name)
        #expect(
            names == [
                "eAnnotations", "name", "ordered", "unique", "lowerBound", "upperBound", "many",
                "required", "eType", "eGenericType", "changeable", "volatile", "transient",
                "defaultValueLiteral", "defaultValue", "unsettable", "derived", "eContainingClass",
                "containment", "container", "resolveProxies", "eOpposite", "eReferenceType", "eKeys",
            ])
    }

    @Test("Package features")
    func packageFeatures() throws {
        let classifiers = try #require(
            try feature(.eClassifiers, of: .ePackage) as? EReference)
        #expect(classifiers.containment)
        #expect(classifiers.isMany)
        #expect(classifiers.eType.name == "EClassifier")
        let opposite = try #require(
            try feature(.ePackage, of: .eClassifier) as? EReference)
        #expect(classifiers.opposite == opposite.id)
        #expect(opposite.opposite == classifiers.id)
        #expect(!opposite.containment)

        let subpackages = try #require(try feature(.eSubpackages, of: .ePackage) as? EReference)
        let superPackage = try #require(try feature(.eSuperPackage, of: .ePackage) as? EReference)
        #expect(subpackages.containment && subpackages.isMany)
        #expect(subpackages.opposite == superPackage.id)

        let nsURI = try #require(try feature(.nsURI, of: .ePackage) as? EAttribute)
        #expect(nsURI.eType.name == "EString")
    }

    @Test("Typed element features")
    func typedElementFeatures() throws {
        let upperBound = try #require(try feature(.upperBound, of: .eAttribute) as? EAttribute)
        #expect(upperBound.eType.name == "EInt")
        #expect(upperBound.defaultValueLiteral == "1")
        let many = try #require(try feature(.many, of: .eReference) as? EAttribute)
        #expect(many.derived && many.volatile && many.transient && !many.changeable)
        let ordered = try #require(try feature(.ordered, of: .eAttribute) as? EAttribute)
        #expect(ordered.defaultValueLiteral == "true")
        let eType = try #require(try feature(.eType, of: .eStructuralFeature) as? EReference)
        #expect(eType.eType.name == "EClassifier")
        #expect(!eType.containment)
        let changeable = try #require(try feature(.changeable, of: .eReference) as? EAttribute)
        #expect(changeable.defaultValueLiteral == "true")
    }

    @Test("Class features and derived references")
    func classFeatures() throws {
        let structural = try #require(
            try feature(.eStructuralFeatures, of: .eClass) as? EReference)
        #expect(structural.containment && structural.isMany)
        #expect(structural.eType.name == "EStructuralFeature")
        let containing = try #require(
            try feature(.eContainingClass, of: .eStructuralFeature) as? EReference)
        #expect(structural.opposite == containing.id)

        let supertypes = try #require(try feature(.eSuperTypes, of: .eClass) as? EReference)
        #expect(!supertypes.containment && supertypes.isMany)
        #expect(supertypes.eType.name == "EClass")

        for name in [EcoreFeatureName.eAllSuperTypes, .eAllAttributes, .eAllReferences] {
            let derived = try #require(try feature(name, of: .eClass) as? EReference)
            #expect(derived.derived && derived.isMany && !derived.containment)
        }
        let abstract = try #require(try feature(.abstract, of: .eClass) as? EAttribute)
        #expect(abstract.eType.name == "EBoolean")
    }

    @Test("Enumeration and annotation features")
    func enumAndAnnotationFeatures() throws {
        let literals = try #require(try feature(.eLiterals, of: .eEnum) as? EReference)
        #expect(literals.containment && literals.isMany)
        let owner = try #require(try feature(.eEnum, of: .eEnumLiteral) as? EReference)
        #expect(literals.opposite == owner.id)
        let details = try #require(try feature(.details, of: .eAnnotation) as? EReference)
        #expect(details.containment && details.eType.name == "EStringToStringMapEntry")
        let annotations = try #require(
            try feature(.eAnnotations, of: .eNamedElement) as? EReference)
        #expect(annotations.containment && annotations.isMany)
        #expect(annotations.eType.name == "EAnnotation")
        let value = try #require(try feature(.value, of: .eEnumLiteral) as? EAttribute)
        #expect(value.eType.name == "EInt")
        let entryValue = try #require(
            try feature(.value, of: .eStringToStringMapEntry) as? EAttribute)
        #expect(entryValue.eType.name == "EString")
    }

    @Test("Reference features")
    func referenceFeatures() throws {
        let containment = try #require(try feature(.containment, of: .eReference) as? EAttribute)
        #expect(containment.eType.name == "EBoolean")
        let opposite = try #require(try feature(.eOpposite, of: .eReference) as? EReference)
        #expect(opposite.eType.name == "EReference" && !opposite.containment)
        let resolve = try #require(try feature(.resolveProxies, of: .eReference) as? EAttribute)
        #expect(resolve.defaultValueLiteral == "true")
        let isID = try #require(try feature(.iD, of: .eAttribute) as? EAttribute)
        #expect(isID.eType.name == "EBoolean")
    }

    @Test("Operation, parameter, type parameter, and generic type descriptors")
    func remainingDescriptors() throws {
        let parameters = try #require(try feature(.eParameters, of: .eOperation) as? EReference)
        #expect(parameters.containment && parameters.eType.name == "EParameter")
        let operation = try #require(try feature(.eOperation, of: .eParameter) as? EReference)
        #expect(parameters.opposite == operation.id)
        let bounds = try #require(try feature(.eBounds, of: .eTypeParameter) as? EReference)
        #expect(bounds.containment && bounds.eType.name == "EGenericType")
        #expect(EcorePackage.metaClass(.eGenericType).eStructuralFeatures.count == 6)
        #expect(EcorePackage.metaClass(.eObject).eStructuralFeatures.isEmpty)
    }

    @Test("Feature identifiers are unique across the package")
    func featureIdentifiersUnique() {
        var seen = Set<EUUID>()
        for classifier in EcoreClassifier.allCases {
            for feature in EcorePackage.metaClass(classifier).eStructuralFeatures {
                #expect(seen.insert(feature.id).inserted)
                #expect(EcorePackage.featureName(forID: feature.id)?.rawValue == feature.name)
            }
        }
    }

    @Test("Descriptors resolve stand-ins to complete classes")
    func canonicalDescriptors() throws {
        let classifiers = try #require(try feature(.eClassifiers, of: .ePackage) as? EReference)
        let standIn = try #require(classifiers.eType as? EClass)
        #expect(standIn.eStructuralFeatures.isEmpty)
        let canonical = try #require(EcorePackage.canonical(standIn) as? EClass)
        #expect(!canonical.eStructuralFeatures.isEmpty)
        #expect(EcorePackage.isMetaClass(standIn))
        #expect(!EcorePackage.isMetaClass(EClass(name: "Other")))
    }

    @Test("EMF ordering with diamond inheritance")
    func diamondOrdering() {
        let a = EClass(
            name: "A",
            eStructuralFeatures: [EAttribute(name: "a", eType: EDataType(name: "EString"))])
        let b = EClass(
            name: "B", eSuperTypes: [a],
            eStructuralFeatures: [EAttribute(name: "b", eType: EDataType(name: "EString"))])
        let c = EClass(
            name: "C", eSuperTypes: [a],
            eStructuralFeatures: [EAttribute(name: "c", eType: EDataType(name: "EString"))])
        let d = EClass(
            name: "D", eSuperTypes: [b, c],
            eStructuralFeatures: [EAttribute(name: "d", eType: EDataType(name: "EString"))])
        #expect(d.eAllSuperTypes.map(\.name) == ["A", "B", "C"])
        #expect(d.eAllStructuralFeatures.map(\.name) == ["a", "b", "c", "d"])
        #expect(d.eAllAttributes.map(\.name) == ["a", "b", "c", "d"])
        #expect(d.eAttributes.map(\.name) == ["d"])
        #expect(d.eReferences.isEmpty)
        #expect(a.eAllSuperTypes.isEmpty)
    }

    @Test("Supertype declaration order determines inherited feature order")
    func supertypeDeclarationOrder() {
        let string = EDataType(name: "EString")
        let x = EClass(name: "X", eStructuralFeatures: [EAttribute(name: "x", eType: string)])
        let y = EClass(name: "Y", eStructuralFeatures: [EAttribute(name: "y", eType: string)])
        let xy = EClass(name: "XY", eSuperTypes: [x, y])
        let yx = EClass(name: "YX", eSuperTypes: [y, x])
        #expect(xy.eAllStructuralFeatures.map(\.name) == ["x", "y"])
        #expect(yx.eAllStructuralFeatures.map(\.name) == ["y", "x"])
        #expect(xy.eAllSuperTypes.map(\.name) == ["X", "Y"])
        #expect(yx.eAllSuperTypes.map(\.name) == ["Y", "X"])
    }

    @Test("Identifier attribute and containments are derived")
    func identifierAndContainments() {
        let library = ReflectionFixtures.makeLibraryPackage()
        let book = library.getEClass("Book")
        #expect(book?.eIDAttribute?.name == "title")
        #expect(library.getEClass("Library")?.eAllContainments.map(\.name) == ["items"])
        #expect(library.getEClass("Item")?.eIDAttribute?.name == "title")
    }
}
