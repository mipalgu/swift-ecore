//
// LabelTests.swift
// ECoreEditTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ECoreEdit

@Suite("Labels, Icons, and Multiplicities")
struct LabelTests {
    private let provider = EcoreLabelProvider()

    @Test("labels follow the layout of the Eclipse Sample Ecore Editor")
    func labels() throws {
        let fixture = Fixture()
        let document = fixture.document
        func text(_ identifier: EUUID) -> String { document.label(for: identifier).text }
        #expect(text(fixture.rootID) == "shop")
        #expect(text(fixture.id("sub")) == "sub")
        #expect(text(fixture.id("Owner")) == "Owner")
        #expect(text(fixture.id("Item")) == "Item")
        #expect(text(fixture.id("Special")) == "Special -> Item")
        #expect(text(fixture.id("Inner")) == "Inner -> Special")
        #expect(text(fixture.id("Kind")) == "Kind")
        #expect(text(fixture.id("A")) == "A = 0")
        #expect(text(fixture.id("B")) == "B = 1")
        #expect(text(fixture.id("label", in: "Item")) == "label : EString")
        #expect(text(fixture.id("owner", in: "Item")) == "owner : Owner")
        #expect(text(fixture.id("items", in: "Owner")) == "items : Item")
        #expect(text(fixture.id("check")) == "check(EInt) : EBoolean throws Failure")
        #expect(text(fixture.id("level")) == "level : EInt")
        #expect(text(fixture.annotationID) == "doc")
        let entries = document.index.children(of: fixture.annotationID)
        #expect(text(entries[0].id) == "a -> 1")
        #expect(text(entries[1].id) == "b -> 2")
    }

    @Test("a label has a name and a detail, which together make the text")
    func parts() {
        let fixture = Fixture()
        let label = fixture.document.label(for: fixture.id("Special"))
        #expect(label.name == "Special" && label.detail == " -> Item" && label.text == "Special -> Item")
        #expect(!label.isUnresolved)
        #expect(fixture.document.label(for: fixture.id("Item")).detail.isEmpty)
        let operation = fixture.document.label(for: fixture.id("check"))
        #expect(operation.name == "check" && operation.detail == "(EInt) : EBoolean throws Failure")
    }

    @Test("a class with several supertypes lists them and shows its instance class name")
    func classDetails() throws {
        let fixture = Fixture()
        var document = fixture.document
        let inner = fixture.id("Inner")
        try document.apply(.set(inner, .eSuperTypes, [fixture.id("Special"), fixture.id("Owner")]))
        #expect(document.label(for: inner).text == "Inner -> Special, Owner")
        try document.apply(.set(inner, .instanceClassName, "com.example.Inner"))
        #expect(document.label(for: inner).text == "Inner -> Special, Owner [com.example.Inner]")
        try document.apply(.set(inner, .eSuperTypes, [EUUID]()))
        #expect(document.label(for: inner).text == "Inner [com.example.Inner]")
    }

    @Test("a data type shows its instance class name, or null")
    func dataTypeLabel() throws {
        let fixture = Fixture()
        var document = fixture.document
        let identifier = try document.apply(.create(.eDataType, in: fixture.rootID, feature: .eClassifiers, name: "Money")).createdIDs[0]
        #expect(document.label(for: identifier).text == "Money [null]")
        try document.apply(.set(identifier, .instanceClassName, "java.math.BigDecimal"))
        #expect(document.label(for: identifier).text == "Money [java.math.BigDecimal]")
        let enumeration = try document.apply(.create(.eEnum, in: fixture.rootID, feature: .eClassifiers, name: "Colour")).createdIDs[0]
        #expect(document.label(for: enumeration).text == "Colour")
    }

    @Test("annotation labels show the last source segment, or the whole source inside an annotation")
    func annotationLabels() throws {
        let fixture = Fixture()
        var document = fixture.document
        let outer = fixture.annotationID
        let nested = try document.apply(.create(.eAnnotation, in: outer, feature: .eAnnotations, name: "http://www.eclipse.org/emf/2002/GenModel")).createdIDs[0]
        #expect(document.label(for: nested).text == "http://www.eclipse.org/emf/2002/GenModel")
        let plain = try document.apply(.create(.eAnnotation, in: fixture.id("Kind"), feature: .eAnnotations, name: "http://www.eclipse.org/emf/2002/GenModel")).createdIDs[0]
        #expect(document.label(for: plain).text == "GenModel")
        let bare = try document.apply(.create(.eAnnotation, in: fixture.id("Kind"), feature: .eAnnotations, name: "plain")).createdIDs[0]
        #expect(document.label(for: bare).text == "plain")
        let trailing = try document.apply(.create(.eAnnotation, in: fixture.id("Kind"), feature: .eAnnotations, name: "http://x/")).createdIDs[0]
        #expect(document.label(for: trailing).text == "")
    }

    @Test("detail values are cut at the first control character")
    func detailCropping() throws {
        let fixture = Fixture()
        var document = fixture.document
        let entry = document.index.children(of: fixture.annotationID)[0].id
        try document.apply(.set(entry, .value, "first\nsecond"))
        #expect(document.label(for: entry).text == "a -> first...")
        try document.apply(.set(document.index.children(of: fixture.annotationID)[0].id, .value, "plain"))
        #expect(document.label(for: entry).text == "a -> plain")
    }

    @Test("operations list parameter types only, as the Eclipse editor does")
    func operationLabels() throws {
        let fixture = Fixture()
        var document = fixture.document
        let check = fixture.id("check")
        let second = try document.apply(.create(.eParameter, in: check, feature: .eParameters, name: "text")).createdIDs[0]
        // as in the Eclipse editor, an untyped parameter is skipped but the separator after its predecessor stays
        #expect(document.label(for: check).text == "check(EInt, ) : EBoolean throws Failure")
        try document.apply(.set(second, .eType, builtIn(.eString)))
        #expect(document.label(for: check).text == "check(EInt, EString) : EBoolean throws Failure")
        try document.apply(.set(fixture.id("level"), .eType, nil))
        #expect(document.label(for: check).text == "check(EString) : EBoolean throws Failure")
        let plain = try document.apply(.create(.eOperation, in: fixture.id("Item"), feature: .eOperations, name: "run")).createdIDs[0]
        #expect(document.label(for: plain).text == "run()")
    }

    @Test("types are resolved by identifier through the index")
    func resolvedTypes() throws {
        let fixture = Fixture()
        var document = fixture.document
        try document.apply(.set(fixture.id("Owner"), .name, "Boss"))
        #expect(document.label(for: fixture.id("owner", in: "Item")).text == "owner : Boss")
        let stale = fixture.reference("owner", in: "Item")
        #expect(stale.eType.name == "Owner")
        #expect(!document.label(for: fixture.id("owner", in: "Item")).isUnresolved)
    }

    @Test("a type that the document does not hold is unresolved and keeps the snapshot name")
    func unresolved() {
        let missing = EClass(name: "Missing")
        let holder = EClass(name: "Holder", eStructuralFeatures: [EReference(name: "r", eType: missing)])
        let document = MetamodelDocument(roots: [EPackage(name: "p", eClassifiers: [holder])])
        let label = document.label(for: document.roots[0].eClassifiers[0].id)
        #expect(!label.isUnresolved)
        let feature = document.index.children(of: holder.id)[0].id
        let featureLabel = document.label(for: feature)
        #expect(featureLabel.text == "r : Missing" && featureLabel.isUnresolved)
        #expect(provider.icon(for: feature, in: document.index) == .eReference)
        let unknown = provider.label(for: EUUID(), in: document.index)
        #expect(unknown.isUnresolved && unknown.text.isEmpty)
    }

    @Test("the Ecore metamodel itself is labelled as the Eclipse editor labels it")
    func ecoreLabels() throws {
        let document = MetamodelDocument(roots: [EcorePackage.instance])
        func label(_ name: String) throws -> String {
            let element = try #require(document.index.allElements.first { $0.name == name })
            return document.label(for: element.id).text
        }
        #expect(try label("EClass") == "EClass -> EClassifier")
        #expect(try label("EAttribute") == "EAttribute -> EStructuralFeature")
        #expect(try label("EObject") == "EObject")
        #expect(try label("ENamedElement") == "ENamedElement -> EModelElement")
        #expect(try label("EString") == "EString [null]")
        #expect(try label("eSuperTypes") == "eSuperTypes : EClass")
        #expect(try label("lowerBound") == "lowerBound : EInt")
        let unresolved = document.index.allElements.filter { document.label(for: $0.id).isUnresolved }
        #expect(unresolved.isEmpty)
    }

    // MARK: Icons

    @Test("every element kind has its icon")
    func icons() throws {
        let fixture = Fixture()
        var document = fixture.document
        let index = { document.index }
        #expect(provider.icon(for: fixture.rootID, in: index()) == .ePackage)
        #expect(provider.icon(for: fixture.id("Item"), in: index()) == .eClass)
        #expect(provider.icon(for: fixture.id("Owner"), in: index()) == .eAbstractClass)
        try document.apply(.set(fixture.id("Failure"), .interface, true))
        #expect(provider.icon(for: fixture.id("Failure"), in: index()) == .eInterface)
        let datatype = try document.apply(.create(.eDataType, in: fixture.rootID, feature: .eClassifiers, name: "D")).createdIDs[0]
        #expect(provider.icon(for: datatype, in: index()) == .eDataType)
        #expect(provider.icon(for: fixture.id("Kind"), in: index()) == .eEnum)
        #expect(provider.icon(for: fixture.id("A"), in: index()) == .eEnumLiteral)
        #expect(provider.icon(for: fixture.id("label", in: "Item"), in: index()) == .eAttribute)
        #expect(provider.icon(for: fixture.id("owner", in: "Item"), in: index()) == .eReference)
        #expect(provider.icon(for: fixture.id("items", in: "Owner"), in: index()) == .eContainmentReference)
        #expect(provider.icon(for: fixture.id("check"), in: index()) == .eOperation)
        #expect(provider.icon(for: fixture.id("level"), in: index()) == .eParameter)
        #expect(provider.icon(for: fixture.annotationID, in: index()) == .eAnnotation)
        #expect(provider.icon(for: index().children(of: fixture.annotationID)[0].id, in: index()) == .detailsEntry)
        #expect(provider.icon(for: EUUID(), in: index()) == .unresolved)
        #expect(EcoreIcon.allCases.count == 15)
    }

    // MARK: Multiplicities

    @Test("multiplicity decorations")
    func multiplicities() {
        #expect(EcoreMultiplicityDecoration(lower: 0, upper: 1) == .zeroToOne)
        #expect(EcoreMultiplicityDecoration(lower: 1, upper: 1) == .one)
        #expect(EcoreMultiplicityDecoration(lower: 0, upper: -1) == .zeroToMany)
        #expect(EcoreMultiplicityDecoration(lower: 0, upper: -2) == .zeroToMany)
        #expect(EcoreMultiplicityDecoration(lower: 1, upper: -1) == .oneToMany)
        #expect(EcoreMultiplicityDecoration(lower: 3, upper: 3) == .exact(3))
        #expect(EcoreMultiplicityDecoration(lower: 0, upper: 0) == .exact(0))
        #expect(EcoreMultiplicityDecoration(lower: 2, upper: 5) == .range(2, 5))
        #expect(EcoreMultiplicityDecoration(lower: 2, upper: -1) == .range(2, -1))
        #expect(EcoreMultiplicityDecoration.zeroToOne.text == "0..1")
        #expect(EcoreMultiplicityDecoration.one.text == "1")
        #expect(EcoreMultiplicityDecoration.zeroToMany.text == "0..*")
        #expect(EcoreMultiplicityDecoration.oneToMany.text == "1..*")
        #expect(EcoreMultiplicityDecoration.exact(3).text == "3")
        #expect(EcoreMultiplicityDecoration.range(2, 5).text == "2..5")
        #expect(EcoreMultiplicityDecoration.range(2, -1).text == "2..*")
    }

    @Test("typed elements have a multiplicity decoration and others do not")
    func elementMultiplicities() throws {
        let fixture = Fixture()
        var document = fixture.document
        let index = { document.index }
        #expect(provider.multiplicity(for: fixture.id("label", in: "Item"), in: index()) == .zeroToOne)
        #expect(provider.multiplicity(for: fixture.id("items", in: "Owner"), in: index()) == .zeroToMany)
        #expect(provider.multiplicity(for: fixture.id("check"), in: index()) == .zeroToOne)
        #expect(provider.multiplicity(for: fixture.id("level"), in: index()) == .zeroToOne)
        try document.apply(.set(fixture.id("level"), .lowerBound, 1))
        #expect(provider.multiplicity(for: fixture.id("level"), in: index()) == .one)
        #expect(provider.multiplicity(for: fixture.id("Item"), in: index()) == nil)
        #expect(provider.multiplicity(for: EUUID(), in: index()) == nil)
    }
}
