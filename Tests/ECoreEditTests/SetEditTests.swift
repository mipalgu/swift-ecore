//
// SetEditTests.swift
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
@Suite("Set Edits")
struct SetEditTests {
    @Test("renaming a class gives the exact change set and undoes exactly")
    func rename() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let before = domain.document
        let item = fixture.id("Item")
        let changes = try domain.perform(.set(item, .name, "Thing"))
        #expect(changes.label == "Rename")
        #expect(changes.changes == [
            MetamodelChange(kind: .set, element: item, feature: .name, oldValue: .string("Item"), newValue: .string("Thing"))
        ])
        #expect(changes.modified == [item: [.name]])
        #expect(changes.added.isEmpty && changes.removed.isEmpty && changes.structureChanged.isEmpty)
        let special = fixture.id("Special")
        let owner = fixture.id("owner", in: "Item")
        let itemsReference = fixture.id("items", in: "Owner")
        #expect(changes.labelsAffected == [item, special, itemsReference])
        #expect(!changes.labelsAffected.contains(owner))
        #expect(domain.document.label(for: special).text == "Special -> Thing")
        #expect(domain.document.label(for: itemsReference).text == "items : Thing")
        let after = domain.document
        domain.undo()
        #expect(domain.document == before)
        #expect(domain.document.label(for: special).text == "Special -> Item")
        domain.redo()
        #expect(domain.document == after)
    }

    @Test("renaming a class refreshes the class snapshots that other elements hold")
    func renameRelinks() throws {
        let fixture = Fixture()
        var document = fixture.document
        try document.apply(.set(fixture.id("Item"), .name, "Thing"))
        guard case .eClass(let special)? = document.index.element(fixture.id("Special")) else { Issue.record("class"); return }
        #expect(special.eSuperTypes.map(\.name) == ["Thing"])
        guard case .reference(let items)? = document.index.element(fixture.id("items", in: "Owner")) else { Issue.record("reference"); return }
        #expect(items.eType.name == "Thing")
    }

    @Test("renaming a parameter's type renames the label of the operation")
    func operationLabelAffected() throws {
        let fixture = Fixture()
        var document = fixture.document
        let check = fixture.id("check")
        let failure = fixture.id("Failure")
        let changes = try document.apply(.set(failure, .name, "Problem"))
        #expect(changes.labelsAffected.contains(check))
        #expect(document.label(for: check).text == "check(EInt) : EBoolean throws Problem")
    }

    @Test("every kind of property can be set: text, flag, integer, and references")
    func propertyKinds() throws {
        let fixture = Fixture()
        var document = fixture.document
        let item = fixture.id("Item")
        let label = fixture.id("label", in: "Item")
        try document.apply(.set(fixture.rootID, .nsURI, "http://shop/2"))
        try document.apply(.set(item, .abstract, true))
        try document.apply(.set(item, .interface, true))
        try document.apply(.set(item, .instanceClassName, "com.example.Item"))
        try document.apply(.set(label, .upperBound, -1))
        try document.apply(.set(label, .lowerBound, 1))
        try document.apply(.set(label, .eType, builtIn(.eInt)))
        try document.apply(.set(label, .defaultValueLiteral, "7"))
        try document.apply(.set(fixture.id("A"), .value, 5))
        try document.apply(.set(fixture.id("A"), .literal, "alpha"))
        guard case .package(let package)? = document.index.element(fixture.rootID) else { Issue.record("package"); return }
        #expect(package.nsURI == "http://shop/2")
        let updated = document.index
        guard case .eClass(let itemClass)? = updated.element(item), case .attribute(let attribute)? = updated.element(label),
            case .literal(let literal)? = updated.element(fixture.id("A"))
        else { Issue.record("elements"); return }
        #expect(itemClass.isAbstract && itemClass.isInterface && itemClass.instanceClassName == "com.example.Item")
        #expect(attribute.upperBound == -1 && attribute.lowerBound == 1 && attribute.eType.name == "EInt")
        #expect(attribute.defaultValueLiteral == "7")
        #expect(literal.value == 5 && literal.literal == "alpha")
        #expect(document.label(for: label).text == "label : EInt")
        #expect(document.label(for: fixture.id("A")).text == "A = 5")
    }

    @Test("setting a property to its current value changes nothing and is not recorded")
    func noOp() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let changes = try domain.perform(.set(fixture.id("Item"), .name, "Item"))
        #expect(changes.isEmpty)
        #expect(!domain.canUndo)
        #expect(!domain.isDirty)
    }

    @Test("set refuses wrong value types, derived and containment features, and unknown features")
    func refusals() throws {
        let fixture = Fixture()
        var document = fixture.document
        let item = fixture.id("Item")
        let label = fixture.id("label", in: "Item")
        let before = document
        #expect(throws: MetamodelEditError.invalidValue(.name)) { try document.apply(.set(item, .name, 3)) }
        #expect(throws: MetamodelEditError.invalidValue(.abstract)) { try document.apply(.set(item, .abstract, "yes")) }
        #expect(throws: MetamodelEditError.invalidValue(.lowerBound)) { try document.apply(.set(label, .lowerBound, true)) }
        #expect(throws: MetamodelEditError.notSettable(.many)) { try document.apply(.set(label, .many, true)) }
        #expect(throws: MetamodelEditError.notSettable(.eClassifiers)) { try document.apply(.set(fixture.rootID, .eClassifiers, [EUUID]())) }
        #expect(throws: MetamodelEditError.notSettable(.eAllSuperTypes)) { try document.apply(.set(item, .eAllSuperTypes, [EUUID]())) }
        #expect(throws: MetamodelEditError.unknownFeature(item, .nsURI)) { try document.apply(.set(item, .nsURI, "x")) }
        #expect(throws: MetamodelEditError.invalidValue(.eType)) { try document.apply(.set(label, .eType, nil)) }
        #expect(throws: MetamodelEditError.invalidValue(.eType)) { try document.apply(.set(label, .eType, item)) }
        #expect(throws: MetamodelEditError.invalidValue(.eType)) {
            try document.apply(.set(fixture.id("owner", in: "Item"), .eType, builtIn(.eString)))
        }
        #expect(throws: MetamodelEditError.invalidValue(.eType)) { try document.apply(.set(label, .eType, "x")) }
        #expect(throws: MetamodelEditError.unresolvedReference(fixture.id("A"))) { try document.apply(.set(label, .eType, fixture.id("A"))) }
        #expect(throws: MetamodelEditError.invalidValue(.eSuperTypes)) { try document.apply(.set(item, .eSuperTypes, "x")) }
        #expect(throws: MetamodelEditError.invalidValue(.eSuperTypes)) { try document.apply(.set(item, .eSuperTypes, [builtIn(.eString)])) }
        #expect(throws: MetamodelEditError.invalidValue(.references)) { try document.apply(.set(fixture.annotationID, .references, "x")) }
        #expect(document == before)
    }

    @Test("operation and parameter types can be cleared; exceptions and annotation references can be set")
    func referenceLists() throws {
        let fixture = Fixture()
        var document = fixture.document
        let check = fixture.id("check")
        let level = fixture.id("level")
        try document.apply(.set(check, .eType, nil))
        try document.apply(.set(level, .eType, nil))
        #expect(document.label(for: check).text == "check() throws Failure")
        #expect(document.label(for: level).text == "level")
        let item = fixture.id("Item")
        try document.apply(.set(check, .eExceptions, [fixture.id("Failure"), item]))
        #expect(document.label(for: check).text == "check() throws Failure, Item")
        try document.apply(.set(check, .eExceptions, nil))
        #expect(document.label(for: check).text == "check()")
        try document.apply(.set(fixture.annotationID, .references, [item, fixture.id("Special")]))
        #expect(document.index.usages(of: item).contains { $0.feature == .references })
        #expect(throws: MetamodelEditError.unresolvedReference(EUUID(uuidString: "00000000-0000-0000-0000-000000000002")!)) {
            try document.apply(.set(fixture.annotationID, .references, [EUUID(uuidString: "00000000-0000-0000-0000-000000000002")!]))
        }
    }

    @Test("setting supertypes updates the subclasses in the index")
    func supertypes() throws {
        let fixture = Fixture()
        var document = fixture.document
        let changes = try document.apply(.set(fixture.id("Special"), .eSuperTypes, [fixture.id("Owner")]))
        #expect(changes.changes.first?.oldValue == .identifiers([fixture.id("Item")]))
        #expect(changes.changes.first?.newValue == .identifiers([fixture.id("Owner")]))
        #expect(document.index.subclasses(of: fixture.id("Item")).isEmpty)
        #expect(document.index.subclasses(of: fixture.id("Owner")).map(\.name) == ["Special", "Inner"])
    }

    @Test("a supertype cycle is rejected by default, directly and through the hierarchy")
    func cycleRejected() throws {
        let fixture = Fixture()
        var document = fixture.document
        let (item, special, inner) = (fixture.id("Item"), fixture.id("Special"), fixture.id("Inner"))
        let before = document
        #expect(throws: MetamodelEditError.supertypeCycle([item, item])) { try document.apply(.set(item, .eSuperTypes, [item])) }
        #expect(throws: MetamodelEditError.supertypeCycle([item, inner, special, item])) {
            try document.apply(.set(item, .eSuperTypes, [inner]))
        }
        #expect(document == before)
    }

    @Test("the permissive policy applies a cycle and reports a diagnostic")
    func cycleAllowed() throws {
        let fixture = Fixture()
        var document = fixture.document
        let item = fixture.id("Item")
        let changes = try document.apply(.set(item, .eSuperTypes, [fixture.id("Inner")]), policy: .permissive)
        #expect(changes.diagnostics.map(\.code) == [EcoreEditDefaults.supertypeCycleCode])
        #expect(changes.diagnostics.first?.severity == .warning)
        #expect(document.label(for: item).text == "Item -> Inner")
        #expect(document.canApply(.set(item, .eSuperTypes, [item])) == false)
        #expect(document.canApply(.set(item, .eSuperTypes, [item]), policy: .permissive))
    }

    @Test("setting containment keeps the container flag of the opposite in step")
    func containmentFlag() throws {
        let fixture = Fixture()
        var document = fixture.document
        let items = fixture.id("items", in: "Owner")
        let owner = fixture.id("owner", in: "Item")
        let changes = try document.apply(.set(items, .containment, false))
        #expect(fixture.reference("owner", in: "Item").container)
        guard case .reference(let updated)? = document.index.element(owner) else { Issue.record("reference"); return }
        #expect(!updated.container)
        #expect(changes.modified == [items: [.containment], owner: [.container]])
        try document.apply(.set(items, .containment, true))
        guard case .reference(let restored)? = document.index.element(owner) else { Issue.record("reference"); return }
        #expect(restored.container)
    }
}
