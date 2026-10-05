//
// ModelValidatorTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Model validator")
struct ModelValidatorTests {

    func codes(_ w: LibraryWorld) async -> [ModelDiagnosticCode] {
        let diagnostics = ModelValidator(metamodels: [w.model.package]).validate(await w.resource.snapshot())
        return diagnostics.map(\.code)
    }

    func diagnostics(_ w: LibraryWorld) async -> [ModelDiagnostic] {
        ModelValidator(metamodels: [w.model.package]).validate(await w.resource.snapshot())
    }

    @Test("a well-formed model has no diagnostics")
    func clean() async throws {
        let w = try await LibraryWorld()
        #expect(await diagnostics(w).isEmpty)
    }

    @Test("a missing required value violates the lower bound")
    func lowerBound() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: nil)
        let found = await diagnostics(w)
        #expect(found.count == 1)
        let diagnostic = try #require(found.first)
        #expect(diagnostic.code == .lowerBound)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.objectID == w.book1.id)
        #expect(diagnostic.feature == "title")
        #expect(diagnostic.message == "Feature 'title' needs at least 1 value(s) but has 0")
    }

    @Test("too many values violate the upper bound")
    func upperBound() async throws {
        let w = try await LibraryWorld()
        var tags = w.model.tags
        tags.upperBound = 2
        let limited = EClass(
            id: w.model.member.id, name: "Member",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: EDataType(name: "EString")),
                tags,
            ])
        let package = EPackage(name: "lib", nsURI: w.model.package.nsURI, eClassifiers: [limited])
        try await w.resource.eAdd(objectId: w.alice.id, feature: "tags", value: "a")
        try await w.resource.eAdd(objectId: w.alice.id, feature: "tags", value: "b")
        try await w.resource.eAdd(objectId: w.alice.id, feature: "tags", value: "c")
        let found = ModelValidator(metamodels: [package]).validate(await w.resource.snapshot())
        #expect(found.map(\.code).contains(.upperBound))
        let message = try #require(found.first { $0.code == .upperBound }?.message)
        #expect(message == "Feature 'tags' allows at most 2 value(s) but has 3")
        #expect(await codes(w).contains(.upperBound) == false)
    }

    @Test("data values must conform to the attribute type")
    func invalidValue() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "pages", value: "many")
        let found = await diagnostics(w)
        #expect(found.map(\.code) == [.invalidValue])
        #expect(found.first?.message == "Value 'many' is not a valid EInt for feature 'pages'")
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "pages", value: 300)
        #expect(await diagnostics(w).isEmpty)
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "title", value: 5)
        #expect(await codes(w) == [.invalidValue])
    }

    @Test("enumeration values must be literals")
    func enumLiteral() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "state", value: "loaned")
        try await w.resource.eSetWithChanges(objectId: w.book2.id, feature: "state", value: 1)
        #expect(await diagnostics(w).isEmpty)
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "state", value: "lost")
        try await w.resource.eSetWithChanges(objectId: w.book2.id, feature: "state", value: true)
        let found = await diagnostics(w)
        #expect(found.map(\.code) == [.invalidEnumLiteral, .invalidEnumLiteral])
        #expect(found.first?.message == "Value 'lost' is not a literal of enumeration Status (feature 'state')")
    }

    @Test("references to missing objects dangle")
    func dangling() async throws {
        let w = try await LibraryWorld()
        await w.resource.delete([w.book1.id], cleaningReferences: false)
        #expect(await diagnostics(w).isEmpty)
        try await w.resource.eAdd(objectId: w.alice.id, feature: "loans", value: w.book2)
        await w.resource.delete([w.book2.id], cleaningReferences: false)
        let found = await diagnostics(w)
        #expect(found.map(\.code) == [.danglingReference])
        #expect(found.first?.objectID == w.alice.id)
        #expect(found.first?.message == "Feature 'loans' refers to missing object \(w.book2.id.uuidString)")
    }

    @Test("references must point at instances of the referenced type")
    func typeMismatch() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eSetWithChanges(objectId: w.lib.id, feature: "manager", value: w.book1.id)
        let found = await diagnostics(w)
        #expect(found.map(\.code) == [.referenceTypeMismatch])
        #expect(found.first?.message == "Feature 'manager' refers to an instance of Book, which is not a Member")
        try await w.resource.eSetWithChanges(objectId: w.lib.id, feature: "manager", value: w.alice.id)
        #expect(await diagnostics(w).isEmpty)
    }

    @Test("subclass instances conform to the referenced type")
    func subclassConforms() async throws {
        let w = try await LibraryWorld()
        #expect(await w.ids(w.lib, "items").count == 3)
        #expect(await diagnostics(w).isEmpty)
    }

    @Test("identifying attributes must be unique")
    func duplicateID() async throws {
        let w = try await LibraryWorld()
        try await w.resource.eSetWithChanges(objectId: w.book2.id, feature: "isbn", value: "111")
        let found = await diagnostics(w)
        #expect(found.map(\.code) == [.duplicateID, .duplicateID])
        #expect(found.map(\.objectID) == [w.book1.id, w.book2.id])
        #expect(found.first?.message == "Identifier '111' of feature 'isbn' is used by more than one object")
        try await w.resource.eSetWithChanges(objectId: w.book2.id, feature: "isbn", value: "222")
        #expect(await diagnostics(w).isEmpty)
    }

    @Test("instances of abstract classes are reported")
    func abstractInstance() async throws {
        let w = try await LibraryWorld()
        let item = DynamicEObject(eClass: w.model.item)
        try await w.resource.eAdd(objectId: w.lib.id, feature: "items", value: item)
        try await w.resource.eSetWithChanges(objectId: item.id, feature: "title", value: "Abstract")
        let found = await diagnostics(w)
        #expect(found.map(\.code) == [.abstractInstance])
        #expect(found.first?.message == "Class Item is abstract and cannot be instantiated")
    }

    @Test("classes are checked against the latest metamodel definition")
    func latestDefinition() async throws {
        let w = try await LibraryWorld()
        var stricter = w.model.dvd
        stricter.eStructuralFeatures.append(EAttribute(name: "region", eType: EDataType(name: "EString"), lowerBound: 1))
        let package = EPackage(
            name: "lib", nsURI: w.model.package.nsURI,
            eClassifiers: [w.model.library, w.model.item, w.model.book, stricter, w.model.member])
        let found = ModelValidator(metamodels: [package]).validate(await w.resource.snapshot())
        #expect(found.map(\.code) == [.lowerBound])
        #expect(found.first?.objectID == w.dvd.id)
    }

    @Test("every code has a message template and a distinct identifier")
    func catalogue() {
        for code in ModelDiagnosticCode.allCases {
            #expect(ModelDiagnosticMessages.templates[code] != nil)
        }
        #expect(Set(ModelDiagnosticCode.allCases.map(\.rawValue)).count == ModelDiagnosticCode.allCases.count)
        #expect(ModelDiagnosticMessages.message(for: .danglingReference, arguments: []).contains("{0}"))
        #expect(ModelDiagnosticSeverity.error > ModelDiagnosticSeverity.warning)
        #expect(ModelDiagnosticSeverity.warning > ModelDiagnosticSeverity.info)
        #expect(ModelDiagnosticSeverity.allCases.count == 3)
    }

    @Test("numeric attributes accept every numeric width")
    func numericWidths() async throws {
        let w = try await LibraryWorld()
        for value in [Int8(1), Int16(2), Int64(4)] as [any EcoreValue] {
            try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "pages", value: value)
            #expect(await diagnostics(w).isEmpty)
        }
        try await w.resource.eSetWithChanges(objectId: w.book1.id, feature: "pages", value: 2.5)
        #expect(await codes(w) == [.invalidValue])
    }
}
