//
// OppositeAndDetailTests.swift
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
@Suite("Opposite and Detail Edits")
struct OppositeAndDetailTests {
    /// The fixture with a second pair of unpaired references between `Special` and `Owner`.
    private func unpaired() throws -> (Fixture, MetamodelDocument, extra: EUUID, back: EUUID) {
        let fixture = Fixture()
        var document = fixture.document
        let extra = try document.apply(.create(.eReference, in: fixture.id("Owner"), feature: .eStructuralFeatures, name: "extra")).createdIDs[0]
        let back = try document.apply(.create(.eReference, in: fixture.id("Special"), feature: .eStructuralFeatures, name: "back")).createdIDs[0]
        try document.apply(.set(extra, .eType, fixture.id("Special")))
        try document.apply(.set(back, .eType, fixture.id("Owner")))
        return (fixture, document, extra, back)
    }

    @Test("pairing two references sets both sides and the container flags")
    func pair() throws {
        let (_, document, extra, back) = try unpaired()
        let domain = MetamodelEditingDomain(document: document)
        let before = domain.document
        try domain.perform(.set(extra, .containment, true))
        let changes = try domain.perform(.setOpposite(back, extra))
        #expect(changes.label == "Set Opposite")
        guard case .reference(let first)? = domain.document.index.element(back), case .reference(let second)? = domain.document.index.element(extra) else {
            Issue.record("references"); return
        }
        #expect(first.opposite == extra && second.opposite == back)
        #expect(first.container && !second.container)
        #expect(changes.modified == [back: [.eOpposite, .container], extra: [.eOpposite]])
        domain.undo()
        domain.undo()
        #expect(domain.document == before)
    }

    @Test("re-pairing clears the previous partners on both sides")
    func repair() throws {
        let (fixture, document, extra, back) = try unpaired()
        var edited = document
        let (items, owner) = (fixture.id("items", in: "Owner"), fixture.id("owner", in: "Item"))
        let changes = try edited.apply(.setOpposite(owner, extra))
        guard case .reference(let oldPartner)? = edited.index.element(items), case .reference(let newPartner)? = edited.index.element(extra),
            case .reference(let source)? = edited.index.element(owner)
        else { Issue.record("references"); return }
        #expect(oldPartner.opposite == nil && !oldPartner.container)
        #expect(source.opposite == extra && newPartner.opposite == owner)
        #expect(changes.modified[items] == [.eOpposite])
        // pairing again with a reference that already has a partner clears that partner too
        try edited.apply(.setOpposite(back, extra))
        guard case .reference(let released)? = edited.index.element(owner) else { Issue.record("reference"); return }
        #expect(released.opposite == nil)
        guard case .reference(let paired)? = edited.index.element(extra) else { Issue.record("reference"); return }
        #expect(paired.opposite == back)
    }

    @Test("clearing an opposite clears both sides")
    func unpair() throws {
        let fixture = Fixture()
        var document = fixture.document
        let (items, owner) = (fixture.id("items", in: "Owner"), fixture.id("owner", in: "Item"))
        let changes = try document.apply(.setOpposite(owner, nil))
        guard case .reference(let first)? = document.index.element(items), case .reference(let second)? = document.index.element(owner) else {
            Issue.record("references"); return
        }
        #expect(first.opposite == nil && second.opposite == nil && !second.container)
        #expect(changes.modified == [owner: [.eOpposite, .container], items: [.eOpposite]])
        #expect(try document.apply(.setOpposite(owner, nil)).isEmpty)
    }

    @Test("setting eOpposite through set behaves like setOpposite")
    func setOppositeFeature() throws {
        let fixture = Fixture()
        var document = fixture.document
        let (items, owner) = (fixture.id("items", in: "Owner"), fixture.id("owner", in: "Item"))
        try document.apply(.set(owner, .eOpposite, nil))
        guard case .reference(let cleared)? = document.index.element(items) else { Issue.record("reference"); return }
        #expect(cleared.opposite == nil)
        try document.apply(.set(owner, .eOpposite, items))
        guard case .reference(let paired)? = document.index.element(items) else { Issue.record("reference"); return }
        #expect(paired.opposite == owner)
        #expect(throws: MetamodelEditError.invalidValue(.eOpposite)) { try document.apply(.set(owner, .eOpposite, "x")) }
        #expect(throws: MetamodelEditError.unknownFeature(fixture.id("Item"), .eOpposite)) { try document.apply(.set(fixture.id("Item"), .eOpposite, items)) }
    }

    @Test("opposites must be other references")
    func invalidOpposites() {
        let fixture = Fixture()
        var document = fixture.document
        let owner = fixture.id("owner", in: "Item")
        #expect(throws: MetamodelEditError.invalidOpposite(owner)) { try document.apply(.setOpposite(owner, owner)) }
        #expect(throws: MetamodelEditError.invalidOpposite(fixture.id("label", in: "Item"))) {
            try document.apply(.setOpposite(owner, fixture.id("label", in: "Item")))
        }
        #expect(throws: MetamodelEditError.invalidOpposite(fixture.id("Item"))) { try document.apply(.setOpposite(fixture.id("Item"), owner)) }
    }

    @Test("setting a detail updates an existing key in place and appends or inserts a new one")
    func setDetail() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let before = domain.document
        let first = domain.document.index.children(of: fixture.annotationID)[0].id
        let updated = try domain.perform(.setDetail(annotation: fixture.annotationID, key: "a", value: "one"))
        #expect(updated.changes == [MetamodelChange(kind: .set, element: first, feature: .value, oldValue: .string("1"), newValue: .string("one"))])
        #expect(updated.modified == [first: [.value]])
        #expect(domain.document.label(for: first).text == "a -> one")
        let inserted = try domain.perform(.setDetail(annotation: fixture.annotationID, key: "c", value: "3", at: 1))
        let identifier = try #require(inserted.createdIDs.first)
        #expect(inserted.added == [identifier])
        #expect(inserted.structureChanged == [fixture.annotationID])
        #expect(domain.document.index.children(of: fixture.annotationID).map(\.id).count == 3)
        #expect(domain.document.index.container(of: identifier)?.index == 1)
        try domain.perform(.setDetail(annotation: fixture.annotationID, key: "d", value: "4"))
        #expect(domain.document.index.children(of: fixture.annotationID).compactMap { EcoreLabelProvider().label(for: $0.id, in: domain.document.index).name } == ["a", "c", "b", "d"])
        domain.undo(); domain.undo(); domain.undo()
        #expect(domain.document == before)
        #expect(throws: MetamodelEditError.self) { try domain.perform(.setDetail(annotation: fixture.id("Item"), key: "a", value: "b")) }
        #expect(try domain.perform(.setDetail(annotation: fixture.annotationID, key: "b", value: "2")).isEmpty)
    }

    @Test("setting the value or key of a detail entry through set uses the detail operations")
    func setDetailEntry() throws {
        let fixture = Fixture()
        var document = fixture.document
        let entry = document.index.children(of: fixture.annotationID)[0].id
        try document.apply(.set(entry, .value, "x"))
        #expect(document.label(for: entry).text == "a -> x")
        let renamed = try document.apply(.set(entry, .key, "z"))
        #expect(renamed.removed == [entry])
        #expect(renamed.added.count == 1)
        #expect(document.label(for: renamed.createdIDs[0]).text == "z -> x")
        #expect(throws: MetamodelEditError.invalidValue(.key)) { try document.apply(.set(renamed.createdIDs[0], .key, 3)) }
        #expect(throws: MetamodelEditError.unknownFeature(renamed.createdIDs[0], .name)) { try document.apply(.set(renamed.createdIDs[0], .name, "x")) }
    }

    @Test("renaming a detail key keeps its position and value, and undoes exactly")
    func renameDetailKey() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let before = domain.document
        let old = domain.document.index.children(of: fixture.annotationID)[0].id
        let changes = try domain.perform(.renameDetailKey(annotation: fixture.annotationID, from: "a", to: "alpha"))
        #expect(changes.label == "Rename Detail Key")
        let new = try #require(changes.createdIDs.first)
        #expect(changes.removed == [old] && changes.added == [new])
        #expect(changes.changes.map(\.kind) == [.remove, .add])
        #expect(changes.structureChanged == [fixture.annotationID])
        #expect(domain.document.index.children(of: fixture.annotationID).map(\.id)[0] == new)
        #expect(domain.document.label(for: new).text == "alpha -> 1")
        domain.undo()
        #expect(domain.document == before)
        #expect(try domain.perform(.renameDetailKey(annotation: fixture.annotationID, from: "a", to: "a")).isEmpty)
        #expect(throws: MetamodelEditError.duplicateDetailKey("b")) { try domain.perform(.renameDetailKey(annotation: fixture.annotationID, from: "a", to: "b")) }
        #expect(throws: MetamodelEditError.missingDetailKey("q")) { try domain.perform(.renameDetailKey(annotation: fixture.annotationID, from: "q", to: "r")) }
        #expect(throws: MetamodelEditError.self) { try domain.perform(.renameDetailKey(annotation: fixture.id("Item"), from: "a", to: "r")) }
    }
}
