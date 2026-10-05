//
// MoveAndPasteTests.swift
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
@Suite("Move and Paste Edits")
struct MoveAndPasteTests {
    @Test("moving a class to another package gives the exact change set and undoes exactly")
    func moveClass() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let before = domain.document
        let (failure, sub) = (fixture.id("Failure"), fixture.id("sub"))
        let changes = try domain.perform(.move([failure], to: sub))
        #expect(changes.label == "Move")
        #expect(changes.changes == [
            MetamodelChange(
                kind: .move, element: failure, feature: .eClassifiers, oldValue: .identifier(fixture.rootID),
                newValue: .identifier(sub), index: 1, oldIndex: 3, oldFeature: .eClassifiers)
        ])
        #expect(changes.structureChanged == [fixture.rootID, sub])
        #expect(changes.added.isEmpty && changes.removed.isEmpty)
        #expect(domain.document.index.container(of: failure)?.container == sub)
        #expect(domain.document.index.fragment(of: failure) == "//sub/Failure")
        #expect(domain.document.label(for: fixture.id("check")).text == "check(EInt) : EBoolean throws Failure")
        domain.undo()
        #expect(domain.document == before)
        #expect(changes.inverted().changes == [changes.changes[0].inverted])
    }

    @Test("the position is relative to the feature after the moved elements were taken out")
    func movePositions() throws {
        let fixture = Fixture()
        var document = fixture.document
        let (owner, item) = (fixture.id("Owner"), fixture.id("Item"))
        try document.apply(.move([owner, item], to: fixture.rootID, at: 3))
        #expect(document.index.children(of: fixture.rootID, feature: .eClassifiers).map(\.name) == ["Special", "Failure", "Kind", "Owner", "Item"])
        let again = try document.apply(.move([fixture.id("Special")], to: fixture.rootID, feature: .eClassifiers, at: 0))
        #expect(again.isEmpty)
        #expect(throws: MetamodelEditError.indexOutOfRange(9, count: 4)) { try document.apply(.move([owner], to: fixture.rootID, at: 9)) }
    }

    @Test("moving within a container reorders it and reports the container")
    func reorder() throws {
        let fixture = Fixture()
        var document = fixture.document
        let (kind, owner) = (fixture.id("Kind"), fixture.id("Owner"))
        let changes = try document.apply(.move([kind], to: fixture.rootID, at: 0))
        #expect(changes.structureChanged == [fixture.rootID])
        #expect(changes.changes.map(\.kind) == [.move])
        #expect(document.index.container(of: owner)?.index == 1)
    }

    @Test("features can move between classes and keep their identifiers")
    func moveFeature() throws {
        let fixture = Fixture()
        var document = fixture.document
        let label = fixture.id("label", in: "Item")
        try document.apply(.move([label], to: fixture.id("Failure")))
        #expect(document.index.container(of: label)?.container == fixture.id("Failure"))
        #expect(document.index.container(of: label)?.feature == .eStructuralFeatures)
    }

    @Test("moves into an element that does not accept them, or into themselves, are refused")
    func illegalMoves() throws {
        let fixture = Fixture()
        var document = fixture.document
        let before = document
        let (item, sub) = (fixture.id("Item"), fixture.id("sub"))
        #expect(throws: MetamodelEditError.illegalChild(container: item, feature: .eClassifiers, kind: .eClass)) {
            try document.apply(.move([fixture.id("Failure")], to: item, feature: .eClassifiers))
        }
        #expect(throws: MetamodelEditError.illegalChild(container: item, feature: .eClassifiers, kind: .eClass)) {
            try document.apply(.move([fixture.id("Failure")], to: item))
        }
        #expect(throws: MetamodelEditError.cannotMoveRoot(fixture.rootID)) { try document.apply(.move([fixture.rootID], to: sub)) }
        #expect(throws: MetamodelEditError.moveIntoDescendant(fixture.id("Item"))) { try document.apply(.move([fixture.id("Item")], to: fixture.id("label", in: "Item"))) }
        #expect(throws: MetamodelEditError.moveIntoDescendant(sub)) { try document.apply(.move([sub], to: sub)) }
        #expect(throws: MetamodelEditError.cannotMoveRoot(fixture.rootID)) { try document.apply(.move([fixture.rootID], to: fixture.rootID)) }
        #expect(throws: MetamodelEditError.illegalChild(container: sub, feature: .eStructuralFeatures, kind: .eClass)) {
            try document.apply(.move([fixture.id("Failure")], to: sub, feature: .eStructuralFeatures))
        }
        #expect(throws: MetamodelEditError.unknownElement(EUUID(uuidString: "00000000-0000-0000-0000-000000000003")!)) {
            try document.apply(.move([EUUID(uuidString: "00000000-0000-0000-0000-000000000003")!], to: sub))
        }
        #expect(document == before)
        #expect(!document.canApply(.move([fixture.id("Failure")], to: item)))
        #expect(try document.apply(.move([], to: sub)).isEmpty)
    }

    @Test("annotation details can be reordered but not moved to another annotation")
    func moveDetails() throws {
        let fixture = Fixture()
        var document = fixture.document
        let entries = document.index.children(of: fixture.annotationID).map(\.id)
        try document.apply(.move([entries[1]], to: fixture.annotationID, at: 0))
        #expect(document.index.children(of: fixture.annotationID).map(\.id) == entries.reversed())
        let other = try document.apply(.create(.eAnnotation, in: fixture.id("Failure"), feature: .eAnnotations, name: "x")).createdIDs[0]
        #expect(throws: MetamodelEditError.cannotMoveDetail(entries[0])) { try document.apply(.move([entries[0]], to: other)) }
    }

    @Test("annotations can move to other elements")
    func moveAnnotation() throws {
        let fixture = Fixture()
        var document = fixture.document
        try document.apply(.move([fixture.annotationID], to: fixture.id("Failure")))
        #expect(document.index.container(of: fixture.annotationID)?.container == fixture.id("Failure"))
        #expect(document.index.children(of: fixture.id("Item"), feature: .eAnnotations).isEmpty)
    }

    // MARK: Paste

    @Test("copying and pasting a class remaps identifiers and keeps references to outside elements")
    func pasteClass() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let before = domain.document
        let special = fixture.id("Special")
        let clipboard = domain.document.copy([special])
        #expect(clipboard.kinds == [.eClass])
        #expect(clipboard.identifiers[special] != nil)
        let changes = try domain.perform(.paste(clipboard, into: fixture.id("sub")))
        #expect(changes.label == "Paste")
        let copy = try #require(changes.createdIDs.first)
        #expect(copy != special && copy != clipboard.identifiers[special])
        #expect(domain.document.index.container(of: copy)?.container == fixture.id("sub"))
        #expect(domain.document.label(for: copy).text == "Special -> Item")
        #expect(changes.added.count == 1 + 1 + 1)
        #expect(changes.structureChanged == [fixture.id("sub")])
        guard case .eClass(let pasted)? = domain.document.index.element(copy) else { Issue.record("class"); return }
        #expect(pasted.eSuperTypes.map(\.id) == [fixture.id("Item")])
        let operation = try #require(domain.document.index.children(of: copy, feature: .eOperations).first)
        #expect(operation.id != fixture.id("check"))
        #expect(domain.document.label(for: operation.id).text == "check(EInt) : EBoolean throws Failure")
        domain.undo()
        #expect(domain.document == before)
    }

    @Test("pasting twice gives distinct copies")
    func pasteTwice() throws {
        let fixture = Fixture()
        var document = fixture.document
        let clipboard = document.copy([fixture.id("Failure")])
        let first = try document.apply(.paste(clipboard, into: fixture.rootID)).createdIDs[0]
        let second = try document.apply(.paste(clipboard, into: fixture.rootID, feature: .eClassifiers, at: 0)).createdIDs[0]
        #expect(first != second)
        #expect(document.index.container(of: second)?.index == 0)
    }

    @Test("references between pasted elements refer to the copies and opposites of outside elements are cleared")
    func pasteReferences() throws {
        let fixture = Fixture()
        var document = fixture.document
        let (owner, item) = (fixture.id("Owner"), fixture.id("Item"))
        let both = document.copy([owner, item])
        let created = try document.apply(.paste(both, into: fixture.id("sub"))).createdIDs
        #expect(created.count == 2)
        let (ownerCopy, itemCopy) = (created[0], created[1])
        let itemsCopy = try #require(document.index.children(of: ownerCopy, feature: .eStructuralFeatures).first)
        let ownerReferenceCopy = try #require(document.index.children(of: itemCopy, feature: .eStructuralFeatures).last)
        guard case .reference(let items) = itemsCopy, case .reference(let back) = ownerReferenceCopy else { Issue.record("references"); return }
        #expect(items.eType.id == itemCopy && back.eType.id == ownerCopy)
        #expect(items.opposite == back.id && back.opposite == items.id)
        #expect(back.container)
        guard case .reference(let original)? = document.index.element(fixture.id("items", in: "Owner")) else { Issue.record("original"); return }
        #expect(original.opposite == fixture.id("owner", in: "Item"))
        // copying a single end leaves the opposite behind
        let single = document.copy([fixture.id("owner", in: "Item")])
        let pasted = try document.apply(.paste(single, into: fixture.id("Failure"))).createdIDs[0]
        guard case .reference(let alone)? = document.index.element(pasted) else { Issue.record("pasted"); return }
        #expect(alone.opposite == nil && !alone.container)
        #expect(alone.eType.id == owner)
    }

    @Test("copying skips unknown elements and elements inside other copied elements")
    func copySelection() {
        let fixture = Fixture()
        let item = fixture.id("Item")
        let clipboard = fixture.document.copy([item, fixture.id("label", in: "Item"), item, EUUID()])
        #expect(clipboard.elements.count == 1)
        #expect(!clipboard.isEmpty)
        #expect(fixture.document.copy([]).isEmpty)
    }

    @Test("pasting into another package of another document keeps outside references unresolved")
    func pasteIntoOtherDocument() throws {
        let fixture = Fixture()
        let clipboard = fixture.document.copy([fixture.id("Special")])
        let target = EPackage(name: "other", nsURI: "http://other", nsPrefix: "o")
        var other = MetamodelDocument(roots: [target], uri: "memory:other.ecore")
        let copy = try other.apply(.paste(clipboard, into: target.id)).createdIDs[0]
        let label = other.label(for: copy)
        #expect(label.text == "Special -> Item")
        #expect(label.isUnresolved)
        #expect(EcoreLabelProvider().icon(for: copy, in: other.index) == .eClass)
        let check = try #require(other.index.children(of: copy, feature: .eOperations).first)
        #expect(other.label(for: check.id).text == "check(EInt) : EBoolean throws Failure")
        #expect(other.label(for: check.id).isUnresolved)
        #expect(other.index.usages(of: fixture.id("Item")).map(\.referrer) == [copy])
    }

    @Test("pasting into a container that does not accept the elements is refused")
    func pasteIncompatible() throws {
        let fixture = Fixture()
        var document = fixture.document
        let before = document
        let clipboard = document.copy([fixture.id("Special")])
        #expect(clipboard.canPaste(into: fixture.rootID, in: document))
        #expect(clipboard.canPaste(into: fixture.rootID, feature: .eClassifiers, in: document))
        #expect(!clipboard.canPaste(into: fixture.rootID, feature: .eSubpackages, in: document))
        #expect(!clipboard.canPaste(into: fixture.id("Item"), in: document))
        #expect(!clipboard.canPaste(into: EUUID(), in: document))
        #expect(!EcoreClipboard(elements: [], identifiers: [:]).canPaste(into: fixture.rootID, in: document))
        #expect(throws: MetamodelEditError.incompatibleClipboard) { try document.apply(.paste(clipboard, into: fixture.id("Item"))) }
        #expect(throws: MetamodelEditError.incompatibleClipboard) { try document.apply(.paste(clipboard, into: fixture.rootID, feature: .eSubpackages)) }
        #expect(throws: MetamodelEditError.incompatibleClipboard) { try document.apply(.paste(EcoreClipboard(elements: [], identifiers: [:]), into: fixture.rootID)) }
        #expect(throws: MetamodelEditError.unknownElement(EUUID(uuidString: "00000000-0000-0000-0000-000000000004")!)) {
            try document.apply(.paste(clipboard, into: EUUID(uuidString: "00000000-0000-0000-0000-000000000004")!))
        }
        #expect(document == before)
    }

    @Test("a package, an annotation, and a detail entry can be pasted into their containers")
    func pasteOtherKinds() throws {
        let fixture = Fixture()
        var document = fixture.document
        let package = try document.apply(.paste(document.copy([fixture.id("sub")]), into: fixture.rootID)).createdIDs[0]
        #expect(document.index.container(of: package)?.feature == .eSubpackages)
        let annotation = try document.apply(.paste(document.copy([fixture.annotationID]), into: fixture.id("Failure"))).createdIDs[0]
        #expect(document.index.children(of: annotation).count == 2)
        let entry = document.index.children(of: fixture.annotationID)[0].id
        #expect(throws: MetamodelEditError.duplicateDetailKey("a")) {
            try document.apply(.paste(document.copy([entry]), into: fixture.annotationID))
        }
        let created = try document.apply(.create(.eAnnotation, in: fixture.id("Kind"), feature: .eAnnotations, name: "empty")).createdIDs[0]
        let pasted = try document.apply(.paste(document.copy([entry]), into: created)).createdIDs[0]
        #expect(document.label(for: pasted).text == "a -> 1")
    }
}
