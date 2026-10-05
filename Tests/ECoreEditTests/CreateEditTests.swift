//
// CreateEditTests.swift
// ECoreEditTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ECoreEdit

@MainActor
@Suite("Create Edits")
struct CreateEditTests {
    @Test("creating a class gives the exact change set and undoes exactly")
    func createClass() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let before = domain.document
        let identifier = EUUID()
        let changes = try domain.perform(
            .create(.eClass, in: fixture.rootID, feature: .eClassifiers, at: 1, name: "Book", identifier: identifier))
        #expect(changes.label == "Create EClass")
        #expect(changes.changes == [
            MetamodelChange(kind: .add, element: identifier, feature: .eClassifiers, newValue: .identifier(fixture.rootID), index: 1)
        ])
        #expect(changes.added == [identifier])
        #expect(changes.removed.isEmpty)
        #expect(changes.createdIDs == [identifier])
        #expect(changes.structureChanged == [fixture.rootID])
        #expect(changes.modified.isEmpty)
        #expect(changes.labelsAffected.isEmpty)
        let created = try #require(domain.document.index.element(identifier))
        #expect(created.name == "Book")
        #expect(domain.document.index.container(of: identifier) == EcoreContainment(container: fixture.rootID, feature: .eClassifiers, index: 1))
        #expect(domain.document.index.children(of: fixture.rootID, feature: .eClassifiers).map(\.name) == ["Owner", "Book", "Item", "Special", "Failure", "Kind"])
        let after = domain.document
        let undone = try #require(domain.undo())
        #expect(domain.document == before)
        #expect(undone.removed == [identifier])
        #expect(domain.document.index.element(identifier) == nil)
        domain.redo()
        #expect(domain.document == after)
    }

    @Test("every kind of element can be created in a container that accepts it")
    func createEveryKind() throws {
        let fixture = Fixture()
        let cases: [(EcoreClassifier, String, EcoreFeatureName, String)] = [
            (.ePackage, "shop", .eSubpackages, "Pkg"),
            (.eClass, "shop", .eClassifiers, "C"),
            (.eDataType, "shop", .eClassifiers, "D"),
            (.eEnum, "shop", .eClassifiers, "E"),
            (.eEnumLiteral, "Kind", .eLiterals, "L"),
            (.eAttribute, "Item", .eStructuralFeatures, "attr"),
            (.eReference, "Item", .eStructuralFeatures, "ref"),
            (.eOperation, "Item", .eOperations, "op"),
            (.eParameter, "check", .eParameters, "p"),
            (.eAnnotation, "Item", .eAnnotations, "http://x/y"),
            (.eStringToStringMapEntry, "", .details, "k"),
        ]
        for (kind, containerName, feature, name) in cases {
            var document = fixture.document
            let container = containerName.isEmpty ? fixture.annotationID : fixture.id(containerName)
            let changes = try document.apply(.create(kind, in: container, feature: feature, name: name))
            let identifier = try #require(changes.createdIDs.first)
            let element = try #require(document.index.element(identifier))
            #expect(element.kind == kind)
            #expect(changes.structureChanged == [container])
            #expect(document.index.container(of: identifier)?.feature == feature)
        }
    }

    @Test("a new attribute is a string and a new reference points at EObject")
    func defaultTypes() throws {
        let fixture = Fixture()
        var document = fixture.document
        let attribute = try document.apply(.create(.eAttribute, in: fixture.id("Item"), feature: .eStructuralFeatures, name: "a")).createdIDs[0]
        let reference = try document.apply(.create(.eReference, in: fixture.id("Item"), feature: .eStructuralFeatures, name: "r")).createdIDs[0]
        guard case .attribute(let created) = try #require(document.index.element(attribute)),
            case .reference(let createdReference) = try #require(document.index.element(reference))
        else { Issue.record("wrong kinds"); return }
        #expect(created.eType.name == "EString")
        #expect(createdReference.eType.name == "EObject")
        #expect(document.label(for: reference).text == "r : EObject")
    }

    @Test("new literals take the next free value")
    func literalValues() throws {
        let fixture = Fixture()
        var document = fixture.document
        let identifier = try document.apply(.create(.eEnumLiteral, in: fixture.id("Kind"), feature: .eLiterals, name: "C")).createdIDs[0]
        #expect(document.label(for: identifier).text == "C = 2")
    }

    @Test("new detail entries get unique keys")
    func detailKeys() throws {
        let fixture = Fixture()
        var document = fixture.document
        let first = try document.apply(.create(.eStringToStringMapEntry, in: fixture.annotationID, feature: .details)).createdIDs[0]
        let second = try document.apply(.create(.eStringToStringMapEntry, in: fixture.annotationID, feature: .details)).createdIDs[0]
        #expect(document.label(for: first).name == "key")
        #expect(document.label(for: second).name == "key1")
        #expect(throws: MetamodelEditError.duplicateDetailKey("a")) {
            try document.apply(.create(.eStringToStringMapEntry, in: fixture.annotationID, feature: .details, name: "a"))
        }
    }

    @Test("illegal creations are refused and leave the document unchanged")
    func illegalCreations() throws {
        let fixture = Fixture()
        var document = fixture.document
        let before = document
        #expect(throws: MetamodelEditError.illegalChild(container: fixture.id("Item"), feature: .eClassifiers, kind: .eClass)) {
            try document.apply(.create(.eClass, in: fixture.id("Item"), feature: .eClassifiers))
        }
        #expect(throws: MetamodelEditError.illegalChild(container: fixture.rootID, feature: .eClassifiers, kind: .eAttribute)) {
            try document.apply(.create(.eAttribute, in: fixture.rootID, feature: .eClassifiers))
        }
        #expect(throws: MetamodelEditError.illegalChild(container: fixture.rootID, feature: .eClassifiers, kind: .eObject)) {
            try document.apply(.create(.eObject, in: fixture.rootID, feature: .eClassifiers))
        }
        #expect(throws: MetamodelEditError.unknownElement(EUUID(uuidString: "00000000-0000-0000-0000-000000000001")!)) {
            try document.apply(.create(.eClass, in: EUUID(uuidString: "00000000-0000-0000-0000-000000000001")!, feature: .eClassifiers))
        }
        #expect(throws: MetamodelEditError.indexOutOfRange(99, count: 5)) {
            try document.apply(.create(.eClass, in: fixture.rootID, feature: .eClassifiers, at: 99))
        }
        #expect(document == before)
        #expect(!document.canApply(.create(.eClass, in: fixture.id("Item"), feature: .eClassifiers)))
        #expect(document.canApply(.create(.eClass, in: fixture.rootID, feature: .eClassifiers)))
    }

    @Test("a detail entry cannot be created in a class")
    func detailInClass() {
        let fixture = Fixture()
        var document = fixture.document
        #expect(throws: MetamodelEditError.illegalChild(container: fixture.id("Item"), feature: .eAnnotations, kind: .eStringToStringMapEntry)) {
            try document.apply(.create(.eStringToStringMapEntry, in: fixture.id("Item"), feature: .eAnnotations))
        }
    }

    @Test("elements of external packages cannot be edited")
    func externalElements() throws {
        let external = EPackage(name: "ext", nsURI: "http://ext", nsPrefix: "ext", eClassifiers: [EClass(name: "Remote")])
        var document = MetamodelDocument(roots: Fixture().document.roots, externals: [external])
        let remote = external.eClassifiers[0].id
        #expect(throws: MetamodelEditError.externalElement(remote)) {
            try document.apply(.set(remote, .name, "Local"))
        }
        #expect(document.childDescriptors(for: remote).isEmpty)
    }

    @Test("creating into a compound is atomic and later edits can use created identifiers")
    func compoundCreate() throws {
        let fixture = Fixture()
        var document = fixture.document
        let identifier = EUUID()
        let changes = try document.apply(
            .compound(label: "New Class", [
                .create(.eClass, in: fixture.rootID, feature: .eClassifiers, name: "Book", identifier: identifier),
                .create(.eAttribute, in: identifier, feature: .eStructuralFeatures, name: "title"),
                .set(identifier, .abstract, true),
            ]))
        #expect(changes.label == "New Class")
        #expect(changes.createdIDs.count == 2)
        #expect(changes.added.count == 2)
        #expect(changes.modified.isEmpty)
        #expect(document.label(for: identifier).text == "Book")
        let before = document
        #expect(throws: MetamodelEditError.self) {
            try document.apply(.compound(label: "Bad", [
                .create(.eClass, in: fixture.rootID, feature: .eClassifiers, name: "Ok"),
                .create(.eClass, in: fixture.id("Item"), feature: .eClassifiers),
            ]))
        }
        #expect(document == before)
    }
}
