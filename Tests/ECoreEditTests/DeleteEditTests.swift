//
// DeleteEditTests.swift
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
@Suite("Delete Edits")
struct DeleteEditTests {
    @Test("deleting an attribute gives the exact change set and undoes exactly")
    func deleteAttribute() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let before = domain.document
        let label = fixture.id("label", in: "Item")
        let changes = try domain.perform(.delete([label]))
        #expect(changes.label == "Delete")
        #expect(changes.changes == [
            MetamodelChange(kind: .remove, element: label, feature: .eStructuralFeatures, oldValue: .identifier(fixture.id("Item")), index: 0)
        ])
        #expect(changes.removed == [label])
        #expect(changes.structureChanged == [fixture.id("Item")])
        #expect(changes.added.isEmpty && changes.modified.isEmpty)
        #expect(domain.document.index.element(label) == nil)
        domain.undo()
        #expect(domain.document == before)
        domain.redo()
        #expect(domain.document.index.element(label) == nil)
    }

    @Test("deleting a package element removes everything it contains")
    func deleteSubtree() throws {
        let fixture = Fixture()
        var document = fixture.document
        let item = fixture.id("Item")
        let contained = document.index.children(of: item).map(\.id)
        let annotationDetails = document.index.children(of: fixture.annotationID).map(\.id)
        let changes = try document.apply(.delete([item]))
        #expect(changes.removed == Set([item] + contained + annotationDetails))
        #expect(changes.removed.count == 1 + 3 + 2)
        #expect(changes.changes.filter { $0.kind == .remove }.map(\.element) == [item])
        for identifier in changes.removed { #expect(document.index.element(identifier) == nil) }
    }

    @Test("deleting a class removes it from supertypes, exceptions, and annotation references")
    func deleteClassCleanUp() throws {
        let fixture = Fixture()
        var document = fixture.document
        let special = fixture.id("Special")
        let failure = fixture.id("Failure")
        let check = fixture.id("check")
        let inner = fixture.id("Inner")
        let changes = try document.apply(.delete([special, failure]))
        #expect(document.index.usages(of: special).isEmpty)
        #expect(document.index.usages(of: failure).isEmpty)
        #expect(document.label(for: inner).text == "Inner")
        #expect(changes.modified[inner] == [.eSuperTypes])
        #expect(changes.modified[fixture.annotationID] == [.references])
        #expect(changes.removed.contains(check))
        guard case .annotation(let annotation)? = document.index.element(fixture.annotationID) else { Issue.record("annotation"); return }
        #expect(annotation.references.isEmpty)
        #expect(changes.changes.contains(MetamodelChange(kind: .set, element: inner, feature: .eSuperTypes, oldValue: .identifiers([special]), newValue: .identifiers([]))))
    }

    @Test("an operation exception that is deleted is removed from the operation")
    func deleteException() throws {
        let fixture = Fixture()
        var document = fixture.document
        let changes = try document.apply(.delete([fixture.id("Failure")]))
        #expect(changes.modified[fixture.id("check")] == [.eExceptions])
        #expect(document.label(for: fixture.id("check")).text == "check(EInt) : EBoolean")
    }

    @Test("a reference whose class was deleted gets EObject and its opposite is cleared on both sides")
    func deleteReferenceTarget() throws {
        let fixture = Fixture()
        var document = fixture.document
        let (item, owner) = (fixture.id("Item"), fixture.id("Owner"))
        let items = fixture.id("items", in: "Owner")
        let changes = try document.apply(.delete([item]))
        #expect(changes.modified[items] == [.eType, .eOpposite])
        #expect(document.label(for: items).text == "items : EObject")
        guard case .reference(let updated)? = document.index.element(items) else { Issue.record("reference"); return }
        #expect(updated.opposite == nil)
        #expect(document.index.element(owner) != nil)
        #expect(document.index.usages(of: item).isEmpty)
    }

    @Test("an attribute whose enumeration was deleted gets EJavaObject")
    func deleteAttributeType() throws {
        let fixture = Fixture()
        var document = fixture.document
        let kind = fixture.id("Kind")
        try document.apply(.set(fixture.id("label", in: "Item"), .eType, kind))
        #expect(document.label(for: fixture.id("label", in: "Item")).text == "label : Kind")
        let changes = try document.apply(.delete([kind]))
        #expect(document.label(for: fixture.id("label", in: "Item")).text == "label : EJavaObject")
        #expect(changes.modified[fixture.id("label", in: "Item")] == [.eType])
        #expect(changes.changes.contains(MetamodelChange(kind: .set, element: fixture.id("label", in: "Item"), feature: .eType, oldValue: .identifier(kind), newValue: .identifier(builtIn(.eJavaObject)))))
    }

    @Test("operation and parameter types are cleaned up according to the kind of the deleted type")
    func deleteOperationTypes() throws {
        let fixture = Fixture()
        var document = fixture.document
        let (check, level) = (fixture.id("check"), fixture.id("level"))
        let item = fixture.id("Item")
        try document.apply(.set(check, .eType, item))
        try document.apply(.set(level, .eType, item))
        try document.apply(.delete([item]))
        #expect(document.label(for: check).text == "check(EObject) throws Failure")
        try document.apply(.set(level, .eType, fixture.id("Kind")))
        try document.apply(.delete([fixture.id("Kind")]))
        #expect(document.label(for: check).text == "check(EJavaObject) throws Failure")
    }

    @Test("deleting a reference clears the opposite on the other side and its container flag")
    func deleteOpposite() throws {
        let fixture = Fixture()
        var document = fixture.document
        let items = fixture.id("items", in: "Owner")
        let owner = fixture.id("owner", in: "Item")
        let changes = try document.apply(.delete([items]))
        guard case .reference(let updated)? = document.index.element(owner) else { Issue.record("reference"); return }
        #expect(updated.opposite == nil && !updated.container)
        #expect(changes.modified[owner] == [.eOpposite, .container])
    }

    @Test("deleting both ends of an opposite pair leaves nothing to clean up")
    func deleteBothOpposites() throws {
        let fixture = Fixture()
        var document = fixture.document
        let changes = try document.apply(.delete([fixture.id("items", in: "Owner"), fixture.id("owner", in: "Item")]))
        #expect(changes.modified.isEmpty)
        #expect(changes.removed.count == 2)
    }

    @Test("deleting an annotation detail removes its key; deleting an annotation removes its references")
    func deleteDetail() throws {
        let fixture = Fixture()
        var document = fixture.document
        let detail = document.index.children(of: fixture.annotationID)[0].id
        let changes = try document.apply(.delete([detail]))
        #expect(changes.removed == [detail])
        #expect(fixture.annotation().details.count == 2)
        #expect(document.index.children(of: fixture.annotationID).map { document.label(for: $0.id).text } == ["b -> 2"])
        #expect(Set(document.index.usages(of: fixture.id("Special")).map(\.feature)).contains(.references))
        try document.apply(.delete([fixture.annotationID]))
        #expect(document.index.usages(of: fixture.id("Special")).allSatisfy { $0.feature != .references })
    }

    @Test("deleting a root package removes it from the document")
    func deleteRoot() throws {
        let fixture = Fixture()
        var document = fixture.document
        let changes = try document.apply(.delete([fixture.rootID]))
        #expect(document.roots.isEmpty)
        #expect(changes.changes == [MetamodelChange(kind: .remove, element: fixture.rootID)])
        #expect(changes.removed.contains(fixture.id("Item")))
    }

    @Test("elements inside other deleted elements and duplicates are removed once")
    func deleteNested() throws {
        let fixture = Fixture()
        var document = fixture.document
        let (item, label) = (fixture.id("Item"), fixture.id("label", in: "Item"))
        let changes = try document.apply(.delete([label, item, item]))
        #expect(changes.changes.filter { $0.kind == .remove }.map(\.element) == [item])
        #expect(try document.apply(.delete([])).isEmpty)
    }

    @Test("deleting unknown elements is refused")
    func deleteUnknown() {
        var document = Fixture().document
        let unknown = EUUID()
        #expect(throws: MetamodelEditError.unknownElement(unknown)) { try document.apply(.delete([unknown])) }
    }

    @Test("deleting several containers at different depths in one edit keeps every container valid")
    func deleteDifferentDepths() throws {
        let fixture = Fixture()
        var document = fixture.document
        let ids = [fixture.id("Inner"), fixture.id("level"), fixture.id("A"), fixture.id("Owner"), fixture.id("label", in: "Item")]
        let changes = try document.apply(.delete(ids))
        #expect(changes.structureChanged == [fixture.id("sub"), fixture.id("check"), fixture.id("Kind"), fixture.rootID, fixture.id("Item")])
        #expect(document.index.children(of: fixture.rootID, feature: .eClassifiers).map(\.name) == ["Item", "Special", "Failure", "Kind"])
    }
}
