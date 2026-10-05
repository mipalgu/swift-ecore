//
// DescriptorTests.swift
// ECoreEditTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ECoreEdit

@Suite("Descriptors and Choices")
struct DescriptorTests {
    private func pairs(_ descriptors: [ChildDescriptor]) -> [String] {
        descriptors.map { "\($0.feature.rawValue):\($0.kind.rawValue)" }
    }

    @Test("a package accepts annotations, classes, data types, enumerations, and subpackages")
    func packageChildren() {
        let fixture = Fixture()
        #expect(pairs(fixture.document.childDescriptors(for: fixture.rootID)) == [
            "eAnnotations:EAnnotation", "eClassifiers:EClass", "eClassifiers:EDataType",
            "eClassifiers:EEnum", "eSubpackages:EPackage",
        ])
    }

    @Test("a class accepts annotations, operations, attributes, and references")
    func classChildren() {
        let fixture = Fixture()
        #expect(pairs(fixture.document.childDescriptors(for: fixture.id("Item"))) == [
            "eAnnotations:EAnnotation", "eOperations:EOperation", "eStructuralFeatures:EAttribute",
            "eStructuralFeatures:EReference",
        ])
    }

    @Test("the other metaclasses accept exactly what Ecore lets them contain")
    func otherChildren() {
        let fixture = Fixture()
        let annotation = "eAnnotations:EAnnotation"
        let document = fixture.document
        #expect(pairs(document.childDescriptors(for: fixture.id("Kind"))) == [annotation, "eLiterals:EEnumLiteral"])
        #expect(pairs(document.childDescriptors(for: fixture.id("A"))) == [annotation])
        #expect(pairs(document.childDescriptors(for: fixture.id("label", in: "Item"))) == [annotation])
        #expect(pairs(document.childDescriptors(for: fixture.id("owner", in: "Item"))) == [annotation])
        #expect(pairs(document.childDescriptors(for: fixture.id("check"))) == [annotation, "eParameters:EParameter"])
        #expect(pairs(document.childDescriptors(for: fixture.id("level"))) == [annotation])
        #expect(pairs(document.childDescriptors(for: fixture.annotationID)) == [annotation, "details:EStringToStringMapEntry"])
        let detail = document.index.children(of: fixture.annotationID)[0].id
        #expect(document.childDescriptors(for: detail).isEmpty)
        let datatype = MetamodelDocument(roots: [EPackage(name: "p", eClassifiers: [EDataType(name: "D")])])
        #expect(pairs(datatype.childDescriptors(for: datatype.roots[0].eClassifiers[0].id)) == [annotation])
        #expect(document.childDescriptors(for: EUUID()).isEmpty)
    }

    @Test("every element kind has descriptors that the document accepts")
    func descriptorsAreLegal() throws {
        let fixture = Fixture()
        for element in fixture.document.index.allElements {
            for descriptor in fixture.document.childDescriptors(for: element.id) {
                #expect(fixture.document.canApply(descriptor.edit(name: "x")), "\(element.kind) \(descriptor.kind)")
            }
        }
    }

    @Test("sibling descriptors are the container's children, placed after the element in the same feature")
    func siblings() throws {
        let fixture = Fixture()
        let item = fixture.id("Item")
        let siblings = fixture.document.siblingDescriptors(for: item)
        #expect(pairs(siblings) == pairs(fixture.document.childDescriptors(for: fixture.rootID)))
        #expect(siblings.map(\.container).allSatisfy { $0 == fixture.rootID })
        #expect(siblings.filter { $0.feature == .eClassifiers }.map(\.index) == [2, 2, 2])
        #expect(siblings.filter { $0.feature != .eClassifiers }.allSatisfy { $0.index == nil })
        var document = fixture.document
        let created = try document.apply(siblings[1].edit(name: "Next")).createdIDs[0]
        #expect(document.index.container(of: created)?.index == 2)
        #expect(fixture.document.siblingDescriptors(for: fixture.rootID).isEmpty)
        #expect(fixture.document.siblingDescriptors(for: EUUID()).isEmpty)
    }

    @Test("a descriptor makes a create edit")
    func descriptorEdit() {
        let descriptor = ChildDescriptor(container: EUUID(), feature: .eClassifiers, kind: .eEnum, index: 2)
        guard case .create(let kind, _, let feature, let index, let name, _) = descriptor.edit(name: "E") else {
            Issue.record("not a create edit"); return
        }
        #expect(kind == .eEnum && feature == .eClassifiers && index == 2 && name == "E")
    }

    // MARK: Properties

    private func summary(_ identifier: EUUID, in fixture: Fixture) -> [String] {
        fixture.document.propertyDescriptors(for: identifier).map { "\($0.feature.rawValue)" }
    }

    @Test("property descriptors are derived from the features of the metaclass")
    func propertyFeatures() {
        let fixture = Fixture()
        #expect(summary(fixture.rootID, in: fixture) == ["name", "nsURI", "nsPrefix"])
        #expect(summary(fixture.id("Item"), in: fixture) == ["name", "instanceClassName", "abstract", "interface", "eSuperTypes"])
        #expect(summary(fixture.id("Kind"), in: fixture) == ["name", "instanceClassName", "serializable"])
        #expect(summary(fixture.id("A"), in: fixture) == ["name", "value", "literal"])
        #expect(summary(fixture.id("label", in: "Item"), in: fixture) == [
            "name", "ordered", "unique", "lowerBound", "upperBound", "many", "required", "eType", "changeable",
            "volatile", "transient", "defaultValueLiteral", "unsettable", "derived", "iD",
        ])
        #expect(summary(fixture.id("owner", in: "Item"), in: fixture) == [
            "name", "ordered", "unique", "lowerBound", "upperBound", "many", "required", "eType", "changeable",
            "volatile", "transient", "defaultValueLiteral", "unsettable", "derived", "containment", "container",
            "resolveProxies", "eOpposite",
        ])
        #expect(summary(fixture.id("check"), in: fixture) == [
            "name", "ordered", "unique", "lowerBound", "upperBound", "many", "required", "eType", "eExceptions",
        ])
        #expect(summary(fixture.id("level"), in: fixture) == [
            "name", "ordered", "unique", "lowerBound", "upperBound", "many", "required", "eType",
        ])
        #expect(summary(fixture.annotationID, in: fixture) == ["source", "references"])
        let detail = fixture.document.index.children(of: fixture.annotationID)[0].id
        #expect(summary(detail, in: fixture) == ["key", "value"])
        #expect(fixture.document.propertyDescriptors(for: EUUID()).isEmpty)
    }

    @Test("editor kinds follow the type of the feature, and derived features are read-only")
    func editorKinds() throws {
        let fixture = Fixture()
        func editor(_ identifier: EUUID, _ feature: EcoreFeatureName) throws -> PropertyEditor {
            try #require(fixture.document.propertyDescriptors(for: identifier).first { $0.feature == feature }).editor
        }
        let label = fixture.id("label", in: "Item")
        #expect(try editor(fixture.id("Item"), .name) == .text)
        #expect(try editor(fixture.id("Item"), .abstract) == .flag)
        #expect(try editor(fixture.id("Item"), .eSuperTypes) == .multiChoice)
        #expect(try editor(label, .eType) == .choice)
        #expect(try editor(label, .many) == .readOnly)
        #expect(try editor(label, .required) == .readOnly)
        #expect(try editor(fixture.id("owner", in: "Item"), .container) == .readOnly)
        #expect(try editor(fixture.id("owner", in: "Item"), .eOpposite) == .choice)
        #expect(try editor(fixture.id("A"), .value) == .integer(minimum: nil, maximum: nil))
        #expect(try editor(fixture.annotationID, .references) == .multiChoice)
        let detail = fixture.document.index.children(of: fixture.annotationID)[0].id
        #expect(try editor(detail, .value) == .multiLine)
        #expect(try editor(detail, .key) == .text)
        #expect(try editor(fixture.rootID, .nsURI) == .text)
    }

    @Test("integer bounds follow the multiplicity of the element")
    func integerBounds() throws {
        let fixture = Fixture()
        var document = fixture.document
        let label = fixture.id("label", in: "Item")
        func bounds(_ feature: EcoreFeatureName) throws -> PropertyEditor {
            try #require(document.propertyDescriptors(for: label).first { $0.feature == feature }).editor
        }
        #expect(try bounds(.lowerBound) == .integer(minimum: 0, maximum: 1))
        #expect(try bounds(.upperBound) == .integer(minimum: -1, maximum: nil))
        try document.apply(.set(label, .upperBound, -1))
        #expect(try bounds(.lowerBound) == .integer(minimum: 0, maximum: nil))
    }

    @Test("categories and display names")
    func categories() throws {
        let fixture = Fixture()
        let descriptors = fixture.document.propertyDescriptors(for: fixture.id("owner", in: "Item"))
        func descriptor(_ feature: EcoreFeatureName) throws -> PropertyDescriptor {
            try #require(descriptors.first { $0.feature == feature })
        }
        #expect(try descriptor(.name).category == .identity)
        #expect(try descriptor(.eType).category == .typing)
        #expect(try descriptor(.lowerBound).category == .multiplicity)
        #expect(try descriptor(.containment).category == .behaviour)
        #expect(try descriptor(.lowerBound).displayName == "Lower Bound")
        #expect(try descriptor(.eType).displayName == "EType")
        #expect(try descriptor(.resolveProxies).displayName == "Resolve Proxies")
        #expect(PropertyDescriptor.displayName(of: .nsURI) == "Ns URI")
        #expect(PropertyDescriptor.displayName(of: .iD) == "ID")
        #expect(PropertyDescriptor.displayName(of: .eSuperTypes) == "ESuper Types")
        #expect(PropertyDescriptor.displayName(of: .instanceClassName) == "Instance Class Name")
    }

    @Test("property values are read by feature")
    func propertyValues() {
        let fixture = Fixture()
        let item = fixture.id("Item")
        #expect(fixture.document.value(of: .name, for: item) == .string("Item"))
        #expect(fixture.document.value(of: .abstract, for: item) == .bool(false))
        #expect(fixture.document.value(of: .upperBound, for: fixture.id("items", in: "Owner")) == .int(-1))
        #expect(fixture.document.value(of: .eSuperTypes, for: fixture.id("Special")) == .identifiers([item]))
        #expect(fixture.document.value(of: .eType, for: fixture.id("owner", in: "Item")) == .identifier(fixture.id("Owner")))
        #expect(fixture.document.value(of: .instanceClassName, for: item) == nil)
        #expect(fixture.document.value(of: .nsURI, for: item) == nil)
        #expect(fixture.document.value(of: .name, for: EUUID()) == nil)
    }

    // MARK: Choices

    @Test("type choices depend on the kind of element and include the built-in types of Ecore")
    func typeChoices() {
        let fixture = Fixture()
        let attribute = fixture.document.choices(for: fixture.id("label", in: "Item"), feature: .eType)
        #expect(attribute.contains(builtIn(.eString)) && attribute.contains(fixture.id("Kind")))
        #expect(!attribute.contains(fixture.id("Item")))
        let reference = fixture.document.choices(for: fixture.id("owner", in: "Item"), feature: .eType)
        #expect(Array(reference.prefix(5)) == ["Owner", "Item", "Special", "Failure", "Inner"].map { fixture.id($0) })
        #expect(!reference.contains(fixture.id("Kind")) && !reference.contains(builtIn(.eString)))
        #expect(reference.contains(EcorePackage.metaClass(.eClass).id))
        let operation = fixture.document.choices(for: fixture.id("check"), feature: .eType)
        #expect(operation.contains(fixture.id("Item")) && operation.contains(builtIn(.eInt)) && operation.contains(fixture.id("Kind")))
        #expect(fixture.document.choices(for: fixture.id("level"), feature: .eType) == operation)
        #expect(fixture.document.choices(for: fixture.id("Item"), feature: .eType).isEmpty)
    }

    @Test("type choices include the classifiers of external packages")
    func externalChoices() {
        let remote = EClass(name: "Remote")
        let external = EPackage(name: "ext", nsURI: "http://ext", nsPrefix: "ext", eClassifiers: [remote, EDataType(name: "Money")])
        let local = EClass(name: "Local", eStructuralFeatures: [EAttribute(name: "a", eType: EcorePackage.dataType(.eString)!)])
        let document = MetamodelDocument(roots: [EPackage(name: "p", eClassifiers: [local])], externals: [external])
        let attribute = document.roots[0].eClassifiers[0].id
        #expect(document.choices(for: local.eStructuralFeatures[0].id, feature: .eType).contains(external.eClassifiers[1].id))
        #expect(document.choices(for: attribute, feature: .eSuperTypes).contains(remote.id))
    }

    @Test("supertype choices exclude the class itself and its subclasses")
    func supertypeChoices() {
        let fixture = Fixture()
        let choices = fixture.document.choices(for: fixture.id("Item"), feature: .eSuperTypes)
        #expect(choices == [fixture.id("Owner"), fixture.id("Failure")])
        #expect(fixture.document.choices(for: fixture.id("Inner"), feature: .eSuperTypes) == ["Owner", "Item", "Special", "Failure"].map { fixture.id($0) })
        #expect(fixture.document.choices(for: fixture.id("label", in: "Item"), feature: .eSuperTypes).isEmpty)
    }

    @Test("exception choices are classifiers; reference choices are elements; keys have none")
    func otherChoices() {
        let fixture = Fixture()
        let exceptions = fixture.document.choices(for: fixture.id("check"), feature: .eExceptions)
        #expect(exceptions.contains(fixture.id("Failure")) && exceptions.contains(builtIn(.eString)))
        #expect(fixture.document.choices(for: fixture.id("Item"), feature: .eExceptions).isEmpty)
        #expect(fixture.document.choices(for: fixture.annotationID, feature: .references) == fixture.document.index.allElements.map(\.id))
        #expect(fixture.document.choices(for: fixture.id("Item"), feature: .references).isEmpty)
        #expect(fixture.document.choices(for: fixture.id("owner", in: "Item"), feature: .eKeys).isEmpty)
        #expect(fixture.document.choices(for: EUUID(), feature: .eType).isEmpty)
    }

    @Test("opposite choices are the references of the target class that point back at the source class")
    func oppositeChoices() throws {
        let fixture = Fixture()
        var document = fixture.document
        #expect(document.choices(for: fixture.id("owner", in: "Item"), feature: .eOpposite) == [fixture.id("items", in: "Owner")])
        #expect(document.choices(for: fixture.id("items", in: "Owner"), feature: .eOpposite) == [fixture.id("owner", in: "Item")])
        // a reference from Owner to Special sees the inherited Item.owner, which points back at Owner
        let extra = try document.apply(.create(.eReference, in: fixture.id("Owner"), feature: .eStructuralFeatures, name: "extra")).createdIDs[0]
        try document.apply(.set(extra, .eType, fixture.id("Special")))
        #expect(document.choices(for: extra, feature: .eOpposite) == [fixture.id("owner", in: "Item")])
        #expect(document.choices(for: fixture.id("label", in: "Item"), feature: .eOpposite).isEmpty)
        #expect(document.choices(for: fixture.id("Item"), feature: .eOpposite).isEmpty)
    }
}
