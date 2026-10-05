//
// InstanceFixtures.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

@testable import ECore

/// A small library metamodel built in code, with opposites, containment, an enumeration,
/// an abstract class, and an identifying attribute.
struct LibraryModel {
    let package: EPackage
    let library: EClass
    let item: EClass
    let book: EClass
    let dvd: EClass
    let member: EClass
    let status: EEnum

    let itemsID = EUUID()
    let libraryID = EUUID()
    let loansID = EUUID()
    let borrowerID = EUUID()

    var items: EReference { library.getEReference(name: "items")! }
    var members: EReference { library.getEReference(name: "members")! }
    var manager: EReference { library.getEReference(name: "manager")! }
    var loans: EReference { member.getEReference(name: "loans")! }
    var borrower: EReference { book.getEReference(name: "borrower")! }
    var title: EAttribute { item.getEAttribute(name: "title")! }
    var pages: EAttribute { book.getEAttribute(name: "pages")! }
    var state: EAttribute { book.getEAttribute(name: "state")! }
    var isbn: EAttribute { book.getEAttribute(name: "isbn")! }
    var libraryName: EAttribute { library.getEAttribute(name: "name")! }
    var memberName: EAttribute { member.getEAttribute(name: "name")! }
    var tags: EAttribute { member.getEAttribute(name: "tags")! }

    init() {
        let string = EDataType(name: "EString", instanceClassName: "String")
        let int = EDataType(name: "EInt", instanceClassName: "Int")
        let status = EEnum(
            name: "Status",
            literals: [EEnumLiteral(name: "available", value: 0), EEnumLiteral(name: "loaned", value: 1)])
        let itemsID = self.itemsID
        let libraryID = self.libraryID
        let loansID = self.loansID
        let borrowerID = self.borrowerID

        let libraryClassID = EUUID()
        let memberID = EUUID()
        let bookID = EUUID()
        let itemID = EUUID()
        let memberStub = EClass(
            id: memberID, name: "Member",
            eStructuralFeatures: [EAttribute(name: "name", eType: string)])
        let itemStub = EClass(
            id: itemID, name: "Item", isAbstract: true,
            eStructuralFeatures: [EAttribute(name: "title", eType: string, lowerBound: 1)])
        let book = EClass(
            id: bookID, name: "Book", eSuperTypes: [itemStub],
            eStructuralFeatures: [
                EAttribute(name: "pages", eType: int),
                EAttribute(name: "state", eType: status),
                EAttribute(name: "isbn", eType: string, isID: true),
                EReference(id: borrowerID, name: "borrower", eType: memberStub, opposite: loansID),
            ])
        let member = EClass(
            id: memberID, name: "Member",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EAttribute(name: "tags", eType: string, upperBound: -1),
                EReference(id: loansID, name: "loans", eType: book, upperBound: -1, opposite: borrowerID),
            ])
        let item = EClass(
            id: itemID, name: "Item", isAbstract: true,
            eStructuralFeatures: [
                EAttribute(name: "title", eType: string, lowerBound: 1),
                EReference(id: libraryID, name: "library", eType: EClass(id: libraryClassID, name: "Library"), opposite: itemsID, container: true),
            ])
        let bookFull = EClass(
            id: bookID, name: "Book", eSuperTypes: [item], eStructuralFeatures: book.eStructuralFeatures)
        let dvd = EClass(
            name: "Dvd", eSuperTypes: [item], eStructuralFeatures: [EAttribute(name: "minutes", eType: int)])
        let library = EClass(
            id: libraryClassID, name: "Library",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EReference(id: itemsID, name: "items", eType: item, upperBound: -1, containment: true, opposite: libraryID),
                EReference(name: "members", eType: member, upperBound: -1, containment: true),
                EReference(name: "manager", eType: member, containment: true),
            ])
        self.package = EPackage(
            name: "lib", nsURI: "http://example.org/lib", nsPrefix: "lib",
            eClassifiers: [library, item, bookFull, dvd, member, status])
        self.library = library
        self.item = item
        self.book = bookFull
        self.dvd = dvd
        self.member = member
        self.status = status
    }
}

/// A resource populated with a library, two books, a member, and a second library.
struct LibraryWorld {
    let model = LibraryModel()
    let resource: Resource
    let resourceSet: ResourceSet
    var lib: DynamicEObject
    var other: DynamicEObject
    var book1: DynamicEObject
    var book2: DynamicEObject
    var dvd: DynamicEObject
    var alice: DynamicEObject

    init() async throws {
        resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(model.package, uri: model.package.nsURI)
        resource = await resourceSet.createResource(uri: "memory:/library.xmi")
        lib = DynamicEObject(eClass: model.library)
        other = DynamicEObject(eClass: model.library)
        book1 = DynamicEObject(eClass: model.book)
        book2 = DynamicEObject(eClass: model.book)
        dvd = DynamicEObject(eClass: model.dvd)
        alice = DynamicEObject(eClass: model.member)
        lib.eSet("name", value: "Main")
        other.eSet("name", value: "Branch")
        book1.eSet("title", value: "Dune")
        book1.eSet("isbn", value: "111")
        book2.eSet("title", value: "Emma")
        book2.eSet("isbn", value: "222")
        dvd.eSet("title", value: "Alien")
        alice.eSet("name", value: "Alice")
        await resource.add(contentsOf: [lib, other, alice])
        try await resource.eAdd(objectId: lib.id, feature: "items", value: book1)
        try await resource.eAdd(objectId: lib.id, feature: "items", value: book2)
        try await resource.eAdd(objectId: lib.id, feature: "items", value: dvd)
        try await resource.eAdd(objectId: lib.id, feature: "members", value: alice.id)
    }

    func value(_ object: DynamicEObject, _ feature: String) async -> (any EcoreValue)? {
        await resource.eGet(objectId: object.id, feature: feature)
    }

    func ids(_ object: DynamicEObject, _ feature: String) async -> [EUUID] {
        ReferenceValues.identifiers(await value(object, feature))
    }
}

/// Describes every object of a snapshot, including each set feature value, for comparisons.
func describe(_ snapshot: ResourceSnapshot) -> [String] {
    var lines = ["roots:" + snapshot.rootIDs.map(\.uuidString).joined(separator: ",")]
    for case let object as DynamicEObject in snapshot.objects {
        let values = object.getFeatureNames().map { "\($0)=\(object.eGet($0).map { "\($0)" } ?? "nil")" }
        lines.append("\(object.id) \(object.eClass.name) " + values.joined(separator: ";"))
    }
    return lines
}
