//
// MetamodelLinkerTests.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Describes a class together with every snapshot it holds, at every depth.
private func describe(_ eClass: EClass) -> String {
    var text = "\(eClass.name)#\(eClass.id)"
    text += "<" + eClass.eSuperTypes.map(describe).joined(separator: ",") + ">"
    text += "{" + eClass.eStructuralFeatures.map { describe($0) }.joined(separator: ",") + "}"
    text += "(" + eClass.eOperations.map(describe).joined(separator: ",") + ")"
    return text
}

private func describe(_ classifier: (any EClassifier)?) -> String {
    guard let classifier else { return "nil" }
    if let eClass = classifier as? EClass { return describe(eClass) }
    return "\(classifier.name)#\(classifier.id)"
}

private func describe(_ feature: any EStructuralFeature) -> String {
    switch feature {
    case let attribute as EAttribute: return "\(attribute.name)#\(attribute.id):" + describe(attribute.eType)
    case let reference as EReference: return "\(reference.name)#\(reference.id):" + describe(reference.eType)
    default: return feature.name
    }
}

private func describe(_ operation: EOperation) -> String {
    let parameters = operation.eParameters.map { "\($0.name)#\($0.id):" + describe($0.eType) }
    return "\(operation.name)#\(operation.id):" + describe(operation.eType) + "["
        + parameters.joined(separator: ",") + "]!" + operation.eExceptions.map { describe($0) }.joined(separator: ",")
}

private func describe(_ package: EPackage) -> String {
    let classifiers = package.eClassifiers.map { describe($0) }
    return "\(package.name)#\(package.id)[" + classifiers.joined(separator: ";") + "]"
        + package.eSubpackages.map(describe).joined(separator: ";")
}

@Suite("Metamodel Linker Tests")
struct MetamodelLinkerTests {
    private func identifiers(of package: EPackage) -> [EUUID] {
        MetamodelIndex(roots: [package]).allElements.map(\.id)
    }

    /// Replaces a class of a package tree.
    private func replacing(_ eClass: EClass, in package: EPackage) -> EPackage {
        var result = package
        result.eClassifiers = package.eClassifiers.map { $0.id == eClass.id ? eClass : $0 }
        result.eSubpackages = package.eSubpackages.map { replacing(eClass, in: $0) }
        return result
    }

    private func linkedItem(_ package: EPackage) throws -> EClass {
        try #require(package.getEClass("Item"))
    }

    // MARK: Loaded metamodels

    @Test("relinking an unedited loaded metamodel changes nothing, for every fixture")
    func idempotent() async throws {
        for (name, package) in try await MetamodelFixtures.fixturePackages() {
            let relinked = MetamodelLinker.relinked([package])
            #expect(relinked.count == 1)
            #expect(describe(relinked[0]) == describe(package), "\(name)")
            #expect(relinked[0].origin == package.origin, "\(name)")
            #expect(XMISerializer().serialize(relinked[0]) == XMISerializer().serialize(package), "\(name)")
        }
    }

    @Test("snapshots built by the converter are four levels deep")
    func snapshotDepth() async throws {
        let package = try await FidelityFixtures.package("library-full.ecore")
        let book = try #require(package.getEClass("Book"))
        var current: EClass? = book
        var levelsWithFeatures = 0
        while let eClass = current, !eClass.eStructuralFeatures.isEmpty {
            levelsWithFeatures += 1
            current = (eClass.getStructuralFeature(name: "related") as? EReference)?.eType as? EClass
        }
        #expect(levelsWithFeatures == MetamodelLinker.snapshotDepth)
        #expect(current != nil)
    }

    @Test("renaming a loaded class refreshes every snapshot and serialises consistently")
    func renameLoaded() async throws {
        let package = try await FidelityFixtures.package("library-full.ecore")
        let original = XMISerializer().serialize(package)
        var writer = try #require(package.getEClass("Writer"))
        writer.name = "Author"
        let edited = replacing(writer, in: package)
        let stale = try #require(edited.getEClass("Book")?.getEReference(name: "author")?.eType as? EClass)
        #expect(stale.name == "Writer")
        let relinked = MetamodelLinker.relinked([edited])[0]
        let author = try #require(relinked.getEClass("Book")?.getEReference(name: "author"))
        #expect((author.eType as? EClass)?.name == "Author")
        #expect(author.eType.id == writer.id)
        let holder = try #require(relinked.getEClass("Lendable")?.getOperation(name: "holder"))
        #expect(holder.eType?.name == "Author")
        #expect(identifiers(of: relinked) == identifiers(of: package))
        let text = XMISerializer().serialize(relinked)
        #expect(text == original.replacingOccurrences(of: "Writer", with: "Author"))
    }

    // MARK: Edits of a hand-built metamodel

    @Test("renaming a class refreshes the snapshots at every depth")
    func rename() throws {
        let shop = MetamodelFixtures.shop()
        var owner = shop.owner
        owner.name = "Boss"
        let edited = replacing(owner, in: shop.package)
        let relinked = MetamodelLinker.relinked([edited])[0]
        let item = try linkedItem(relinked)
        #expect(item.getEReference(name: "owner")?.eType.name == "Boss")
        let special = try #require(relinked.getEClass("Special"))
        #expect(special.eSuperTypes[0].getEReference(name: "owner")?.eType.name == "Boss")
        let inner = try #require(relinked.getSubpackage("sub")?.getEClass("Inner"))
        let grandparent = inner.eSuperTypes[0].eSuperTypes[0]
        #expect(grandparent.getEReference(name: "owner")?.eType.name == "Boss")
        #expect(grandparent.getEReference(name: "owner")?.eType.id == owner.id)
        #expect(identifiers(of: relinked) == identifiers(of: edited))
    }

    @Test("adding a feature shows in the snapshots of subclasses and referrers")
    func addFeature() throws {
        let shop = MetamodelFixtures.shop()
        var item = shop.item
        let extra = EAttribute(name: "extra", eType: MetamodelFixtures.string)
        item.eStructuralFeatures.append(extra)
        let relinked = MetamodelLinker.relinked([replacing(item, in: shop.package)])[0]
        let special = try #require(relinked.getEClass("Special"))
        #expect(special.eSuperTypes[0].eStructuralFeatures.map(\.name) == ["label", "owner", "extra"])
        let inner = try #require(relinked.getSubpackage("sub")?.getEClass("Inner"))
        #expect(inner.eSuperTypes[0].eSuperTypes[0].eStructuralFeatures.last?.id == extra.id)
        #expect(inner.eAllAttributes.map(\.name) == ["label", "extra"])
        let owner = try #require(relinked.getEClass("Owner"))
        let items = try #require(owner.getEReference(name: "items"))
        #expect((items.eType as? EClass)?.eStructuralFeatures.count == 3)
    }

    @Test("changing the supertypes refreshes the supertype snapshots")
    func changeSupertypes() throws {
        let shop = MetamodelFixtures.shop()
        var inner = shop.inner
        inner.eSuperTypes = [shop.owner]
        let relinked = MetamodelLinker.relinked([replacing(inner, in: shop.package)])[0]
        let linkedInner = try #require(relinked.getSubpackage("sub")?.getEClass("Inner"))
        #expect(linkedInner.eSuperTypes.map(\.name) == ["Owner"])
        #expect(linkedInner.eSuperTypes[0].getEReference(name: "items") != nil)
        let index = MetamodelIndex(roots: [relinked])
        #expect(index.subclasses(of: shop.special.id).isEmpty)
        #expect(index.subclasses(of: shop.owner.id).map(\.name) == ["Inner"])
    }

    @Test("a supertype that is renamed and a subtype that is added are linked in one pass")
    func newSubclass() throws {
        let shop = MetamodelFixtures.shop()
        var item = shop.item
        item.name = "Thing"
        let fresh = EClass(name: "Fresh", eSuperTypes: [shop.item])
        var package = replacing(item, in: shop.package)
        package.eClassifiers.append(fresh)
        let relinked = MetamodelLinker.relinked([package])[0]
        let linkedFresh = try #require(relinked.getEClass("Fresh"))
        #expect(linkedFresh.eSuperTypes.map(\.name) == ["Thing"])
        #expect(linkedFresh.eSuperTypes[0].eStructuralFeatures.count == 2)
        #expect(linkedFresh.eAllAttributes.map(\.name) == ["label"])
    }

    @Test("deleting a class leaves the snapshots of the deleted class alone and refreshes the rest")
    func deleteClass() throws {
        let shop = MetamodelFixtures.shop()
        var package = shop.package
        var owner = shop.owner
        owner.name = "Boss"
        package.eClassifiers = package.eClassifiers.compactMap { classifier in
            if classifier.id == shop.special.id { return nil }
            return classifier.id == owner.id ? owner : classifier
        }
        let relinked = MetamodelLinker.relinked([package])[0]
        #expect(relinked.getEClass("Special") == nil)
        #expect(try linkedItem(relinked).getEReference(name: "owner")?.eType.name == "Boss")
        let inner = try #require(relinked.getSubpackage("sub")?.getEClass("Inner"))
        #expect(inner.eSuperTypes.map(\.name) == ["Special"])
        #expect(MetamodelIndex(roots: [relinked]).element(shop.special.id) == nil)
    }

    @Test("operation results, parameters, and exceptions are refreshed")
    func operations() throws {
        let failure = EClass(name: "Failure")
        let value = EClass(name: "Value")
        let operation = EOperation(
            name: "run", eType: value, eParameters: [EParameter(name: "input", eType: value)], eExceptions: [failure])
        let host = EClass(name: "Host", eOperations: [operation])
        let package = EPackage(name: "p", eClassifiers: [host, failure, value])
        var renamedValue = value
        renamedValue.name = "Amount"
        var renamedFailure = failure
        renamedFailure.eStructuralFeatures = [EAttribute(name: "why", eType: MetamodelFixtures.string)]
        var edited = replacing(renamedValue, in: package)
        edited = replacing(renamedFailure, in: edited)
        let relinked = MetamodelLinker.relinked([edited])[0]
        let linked = try #require(relinked.getEClass("Host")?.getOperation(name: "run"))
        #expect(linked.eType?.name == "Amount")
        #expect(linked.eParameters[0].eType?.name == "Amount")
        #expect((linked.eExceptions[0] as? EClass)?.eStructuralFeatures.count == 1)
        #expect(linked.eParameters[0].id == operation.eParameters[0].id)
    }

    @Test("other properties, order, containment, and identifiers are preserved")
    func preservation() throws {
        let shop = MetamodelFixtures.shop()
        var item = shop.item
        item.name = "Renamed"
        item.instanceClassName = "x.Y"
        item.eAnnotations = [EAnnotation(source: "doc", orderedDetails: ["b": "2", "a": "1"])]
        let relinked = MetamodelLinker.relinked([replacing(item, in: shop.package)])[0]
        let linked = try #require(relinked.getEClass("Renamed"))
        #expect(linked.instanceClassName == "x.Y")
        #expect(linked.eAnnotations[0].details.keys.elements == ["b", "a"])
        #expect(linked.eAnnotations[0].eContainerID == item.id)
        #expect(linked.eContainerID == relinked.id)
        #expect(relinked.eClassifiers.map(\.name) == ["Owner", "Renamed", "Special", "Kind"])
        #expect(relinked.eClassifiers[3] is EEnum)
        #expect(relinked.nsURI == shop.package.nsURI)
        #expect(relinked.eSubpackages.map(\.name) == ["sub"])
        let reference = try #require(linked.getEReference(name: "owner"))
        #expect(reference.opposite == shop.item.getEReference(name: "owner")?.opposite)
        #expect(reference.id == shop.item.getEReference(name: "owner")?.id)
        #expect(linked.eStructuralFeatures.map(\.name) == ["label", "owner"])
    }

    @Test("a package without classes relinks to itself")
    func empty() {
        let package = EPackage(name: "empty")
        #expect(MetamodelLinker.relinked([package]).map(\.id) == [package.id])
        #expect(MetamodelLinker.relinked([]).isEmpty)
    }

    @Test("a cycle of supertypes terminates")
    func cycle() throws {
        let a = EClass(name: "A")
        let b = EClass(name: "B", eSuperTypes: [a])
        var cyclic = a
        cyclic.eSuperTypes = [b]
        let package = EPackage(name: "p", eClassifiers: [cyclic, b])
        let relinked = MetamodelLinker.relinked([package])[0]
        #expect(relinked.getEClass("A")?.eSuperTypes.map(\.name) == ["B"])
    }

    // MARK: Several packages

    @Test("snapshots that name classes of another root are refreshed")
    func severalRoots() throws {
        let target = EClass(name: "Target")
        let user = EClass(name: "User", eStructuralFeatures: [EReference(name: "to", eType: target)])
        let first = EPackage(name: "first", eClassifiers: [target])
        let second = EPackage(name: "second", eClassifiers: [user])
        var renamed = target
        renamed.name = "Goal"
        let relinked = MetamodelLinker.relinked([replacing(renamed, in: first), second])
        #expect(relinked.map(\.name) == ["first", "second"])
        let reference = try #require(relinked[1].getEClass("User")?.getEReference(name: "to"))
        #expect(reference.eType.name == "Goal")
    }

    @Test("snapshots of external classifiers follow the external packages when given")
    func externals() throws {
        let remote = EClass(name: "Remote")
        let user = EClass(
            name: "User", eSuperTypes: [remote], eStructuralFeatures: [EReference(name: "to", eType: remote)])
        let package = EPackage(name: "p", eClassifiers: [user])
        var renamed = remote
        renamed.name = "Distant"
        renamed.eStructuralFeatures = [EAttribute(name: "x", eType: MetamodelFixtures.string)]
        let external = EPackage(name: "ext", eClassifiers: [renamed])
        let without = MetamodelLinker.relinked([package])[0]
        #expect(without.getEClass("User")?.getEReference(name: "to")?.eType.name == "Remote")
        let with = MetamodelLinker.relinked([package], externals: [external])[0]
        let linked = try #require(with.getEClass("User"))
        #expect(linked.getEReference(name: "to")?.eType.name == "Distant")
        #expect(linked.eSuperTypes.map(\.name) == ["Distant"])
        #expect(linked.eSuperTypes[0].eStructuralFeatures.count == 1)
    }

    @Test("snapshots of built-in Ecore classifiers are kept")
    func builtIns() throws {
        let user = EClass(
            name: "User",
            eSuperTypes: [EcorePackage.metaClass(.eNamedElement)],
            eStructuralFeatures: [EAttribute(name: "n", eType: MetamodelFixtures.string)])
        let relinked = MetamodelLinker.relinked([EPackage(name: "p", eClassifiers: [user])])[0]
        let linked = try #require(relinked.getEClass("User"))
        #expect(linked.eSuperTypes.map(\.name) == ["ENamedElement"])
        #expect(linked.getEAttribute(name: "n")?.eType.id == MetamodelFixtures.string.id)
    }
}
