//
// MetamodelIndexTests.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Metamodel Index Tests")
struct MetamodelIndexTests {
    private let shop = MetamodelFixtures.shop()
    private var index: MetamodelIndex { MetamodelIndex(roots: [shop.package]) }

    // MARK: Elements

    @Test("an element is found by identifier and reports its kind and name")
    func lookup() throws {
        let element = try #require(index.element(shop.item.id))
        #expect(element.kind == .eClass)
        #expect(element.name == "Item")
        #expect(element.id == shop.item.id)
        #expect(index.element(EUUID()) == nil)
        #expect(index.contains(shop.item.id))
        #expect(!index.contains(EUUID()))
        let label = shop.item.eStructuralFeatures[0]
        #expect(index.element(label.id)?.kind == .eAttribute)
        #expect(index.element(shop.item.eStructuralFeatures[1].id)?.kind == .eReference)
        #expect(index.element(shop.kind.id)?.kind == .eEnum)
        #expect(index.element(shop.kind.literals[0].id)?.kind == .eEnumLiteral)
        #expect(index.element(shop.special.eOperations[0].id)?.kind == .eOperation)
        #expect(index.element(shop.special.eOperations[0].eParameters[0].id)?.kind == .eParameter)
        #expect(index.element(shop.package.id)?.kind == .ePackage)
    }

    @Test("every element kind wraps and unwraps")
    func elementKinds() throws {
        let datatype = EDataType(name: "Money")
        let annotation = EAnnotation(source: "s", orderedDetails: ["k": "v"])
        let entry = try #require(annotation.detailEntries.first)
        let objects: [any EObject] = [
            shop.package, shop.item, datatype, shop.kind, shop.kind.literals[0],
            MetamodelFixtures.object(shop.item.eStructuralFeatures[0]),
            MetamodelFixtures.object(shop.item.eStructuralFeatures[1]),
            shop.special.eOperations[0], shop.special.eOperations[0].eParameters[0], annotation, entry,
        ]
        let kinds: [EcoreClassifier] = [
            .ePackage, .eClass, .eDataType, .eEnum, .eEnumLiteral, .eAttribute, .eReference,
            .eOperation, .eParameter, .eAnnotation, .eStringToStringMapEntry,
        ]
        for (object, kind) in zip(objects, kinds) {
            let element = try #require(EcoreElement(object))
            #expect(element.kind == kind)
            #expect(element.id == object.id)
            #expect(element.object.id == object.id)
        }
        #expect(EcoreElement(EFactory(ePackage: shop.package)) == nil)
        #expect(EcoreElement.classifier(datatype)?.kind == .eDataType)
        #expect(EcoreElement.feature(shop.item.eStructuralFeatures[0])?.kind == .eAttribute)
        #expect(EcoreElement(annotation)?.name == nil)
        #expect(EcoreElement(entry)?.annotations.isEmpty == true)
    }

    @Test("allElements lists each element once, in document order")
    func allElements() {
        let names = index.allElements.compactMap(\.name)
        #expect(
            names == [
                "shop", "Owner", "items", "Item", "label", "owner", "Special", "check", "level", "Kind",
                "A", "B", "sub", "Inner",
            ])
        #expect(Set(index.allElements.map(\.id)).count == index.allElements.count)
    }

    // MARK: Containment

    @Test("container answers the container, feature, and index")
    func container() throws {
        let containment = try #require(index.container(of: shop.special.id))
        #expect(containment.container == shop.package.id)
        #expect(containment.feature == .eClassifiers)
        #expect(containment.index == 2)
        let owner = try #require(index.container(of: shop.item.eStructuralFeatures[1].id))
        #expect(owner.container == shop.item.id)
        #expect(owner.feature == .eStructuralFeatures)
        #expect(owner.index == 1)
        let sub = try #require(index.container(of: shop.subpackage.id))
        #expect(sub.feature == .eSubpackages)
        #expect(index.container(of: shop.package.id) == nil)
        #expect(index.container(of: EUUID()) == nil)
        let parameter = shop.special.eOperations[0].eParameters[0]
        #expect(index.container(of: parameter.id)?.feature == .eParameters)
        #expect(index.container(of: shop.kind.literals[1].id)?.feature == .eLiterals)
    }

    @Test("children are listed in containment order, annotations first")
    func children() throws {
        let annotation = EAnnotation(source: "doc")
        var item = shop.item
        item.eAnnotations = [annotation]
        var package = shop.package
        package.eClassifiers = [item]
        let index = MetamodelIndex(roots: [package])
        let children = index.children(of: item.id)
        #expect(children.map(\.kind) == [.eAnnotation, .eAttribute, .eReference])
        #expect(index.children(of: item.id, feature: .eStructuralFeatures).compactMap(\.name) == ["label", "owner"])
        #expect(index.children(of: item.id, feature: .eAnnotations).count == 1)
        #expect(index.children(of: item.id, feature: .eOperations).isEmpty)
        #expect(index.children(of: EUUID()).isEmpty)
        #expect(index.children(of: package.id).first?.id == item.id)
    }

    @Test("annotations contain their detail entries and nested annotations")
    func annotationChildren() throws {
        let nested = EAnnotation(source: "nested")
        let annotation = EAnnotation(source: "s", orderedDetails: ["a": "1", "b": "2"], eAnnotations: [nested])
        let package = EPackage(name: "p", eAnnotations: [annotation])
        let index = MetamodelIndex(roots: [package])
        let children = index.children(of: annotation.id)
        #expect(children.map(\.kind) == [.eAnnotation, .eStringToStringMapEntry, .eStringToStringMapEntry])
        let entry = try #require(index.children(of: annotation.id, feature: .details).last)
        #expect(index.container(of: entry.id)?.index == 1)
        #expect(index.fragment(of: entry.id) == "//%s%/@details.1")
        guard case .detail(let detail) = entry else {
            Issue.record("not a detail entry")
            return
        }
        #expect(detail.key == "b")
    }

    @Test("root and ancestors lead up to the root package")
    func roots() {
        let parameter = shop.special.eOperations[0].eParameters[0]
        #expect(index.root(of: parameter.id) == shop.package.id)
        #expect(index.root(of: shop.inner.id) == shop.package.id)
        #expect(index.root(of: shop.package.id) == shop.package.id)
        #expect(index.root(of: EUUID()) == nil)
        #expect(index.ancestors(of: parameter.id) == [shop.special.eOperations[0].id, shop.special.id, shop.package.id])
        #expect(index.ancestors(of: shop.package.id).isEmpty)
        #expect(index.ancestors(of: shop.inner.id) == [shop.subpackage.id, shop.package.id])
    }

    // MARK: Fragments

    @Test("fragment and resolve are inverses")
    func fragments() throws {
        #expect(index.fragment(of: shop.inner.id) == "//sub/Inner")
        #expect(index.fragment(of: shop.package.id) == "/")
        #expect(index.fragment(of: EUUID()) == nil)
        #expect(index.resolve(fragment: "#//sub/Inner")?.id == shop.inner.id)
        #expect(index.resolve(fragment: "//Nothing") == nil)
        for element in index.allElements {
            let fragment = try #require(index.fragment(of: element.id))
            #expect(index.resolve(fragment: fragment, in: shop.package.id)?.id == element.id)
        }
        #expect(index.resolve(fragment: "//Item", in: EUUID()) == nil)
    }

    @Test("fragments of several roots are relative to each root")
    func severalRoots() throws {
        let other = EPackage(name: "other", eClassifiers: [EClass(name: "Item")])
        let index = MetamodelIndex(roots: [shop.package, other])
        let otherItem = try #require(other.eClassifiers.first)
        #expect(index.fragment(of: otherItem.id) == "//Item")
        #expect(index.resolve(fragment: "//Item", in: other.id)?.id == otherItem.id)
        #expect(index.resolve(fragment: "//Item")?.id == shop.item.id)
        #expect(index.root(of: otherItem.id) == other.id)
        #expect(index.allElements.count == MetamodelIndex(roots: [shop.package]).allElements.count + 2)
    }

    // MARK: Usages

    @Test("usages cover supertypes, types, opposites, exceptions, and annotation references")
    func usages() throws {
        let owner = shop.owner
        let ownerType = index.usages(of: owner.id)
        #expect(ownerType.count == 1)
        #expect(ownerType[0].referrer == shop.item.eStructuralFeatures[1].id)
        #expect(ownerType[0].feature == .eType)
        #expect(index.usages(of: shop.item.id).contains(EcoreUsage(referrer: shop.special.id, feature: .eSuperTypes, position: 0)))
        let items = shop.owner.eStructuralFeatures[0]
        let opposite = index.usages(of: items.id)
        #expect(opposite == [EcoreUsage(referrer: shop.item.eStructuralFeatures[1].id, feature: .eOpposite)])
        let boolean = try #require(EcorePackage.dataType(.eBoolean))
        #expect(index.usages(of: boolean.id) == [EcoreUsage(referrer: shop.special.eOperations[0].id, feature: .eType)])
        let level = shop.special.eOperations[0].eParameters[0]
        #expect(index.usages(of: try #require(level.eType).id) == [EcoreUsage(referrer: level.id, feature: .eType)])
        #expect(index.usages(of: shop.inner.id).isEmpty)
        #expect(index.usages(of: EUUID()).isEmpty)
    }

    @Test("exceptions and annotation references are usages")
    func exceptionsAndReferences() {
        let failure = EClass(name: "Failure")
        let other = EClass(name: "Other")
        let operation = EOperation(name: "run", eExceptions: [other, failure])
        let annotation = EAnnotation(
            source: "s", references: [.local(failure.id), .external(ResourceProxy(uri: "x.ecore", fragment: "//Y"))])
        let host = EClass(name: "Host", eOperations: [operation], eAnnotations: [annotation])
        let package = EPackage(name: "p", eClassifiers: [failure, other, host])
        let index = MetamodelIndex(roots: [package])
        #expect(
            index.usages(of: failure.id) == [
                EcoreUsage(referrer: annotation.id, feature: .references, position: 0),
                EcoreUsage(referrer: operation.id, feature: .eExceptions, position: 1),
            ])
        #expect(index.usages(of: other.id) == [EcoreUsage(referrer: operation.id, feature: .eExceptions, position: 0)])
    }

    @Test("usages follow identifiers, so a stale snapshot is still found")
    func staleSnapshots() {
        var renamed = shop.owner
        renamed.name = "Renamed"
        var package = shop.package
        package.eClassifiers[0] = renamed
        let index = MetamodelIndex(roots: [package])
        #expect(index.usages(of: renamed.id).count == 1)
        #expect(index.element(renamed.id)?.name == "Renamed")
    }

    // MARK: Subclasses

    @Test("subclasses lists direct and indirect subclasses in document order")
    func subclasses() {
        #expect(index.subclasses(of: shop.item.id).map(\.name) == ["Special", "Inner"])
        #expect(index.subclasses(of: shop.item.id, transitive: false).map(\.name) == ["Special"])
        #expect(index.subclasses(of: shop.special.id).map(\.name) == ["Inner"])
        #expect(index.subclasses(of: shop.inner.id).isEmpty)
        #expect(index.subclasses(of: EUUID()).isEmpty)
    }

    @Test("concreteOnly leaves out abstract classes and interfaces")
    func concreteSubclasses() {
        let base = EClass(name: "Base")
        let abstract = EClass(name: "Abstract", isAbstract: true, eSuperTypes: [base])
        let interface = EClass(name: "Interface", isInterface: true, eSuperTypes: [base])
        let leaf = EClass(name: "Leaf", eSuperTypes: [abstract, interface])
        let package = EPackage(name: "p", eClassifiers: [base, abstract, interface, leaf])
        let index = MetamodelIndex(roots: [package])
        #expect(index.subclasses(of: base.id).map(\.name) == ["Abstract", "Interface", "Leaf"])
        #expect(index.subclasses(of: base.id, concreteOnly: true).map(\.name) == ["Leaf"])
    }

    @Test("a cycle of supertypes does not loop")
    func cyclicSubclasses() {
        let a = EClass(name: "A")
        let b = EClass(name: "B", eSuperTypes: [a])
        var cyclic = a
        cyclic.eSuperTypes = [b]
        let package = EPackage(name: "p", eClassifiers: [cyclic, b])
        let index = MetamodelIndex(roots: [package])
        #expect(index.subclasses(of: a.id).map(\.name) == ["B"])
    }

    // MARK: Externals

    @Test("external packages are indexed for lookup only")
    func externals() throws {
        let remote = EClass(name: "Remote")
        let external = EPackage(name: "ext", eClassifiers: [remote, EClass(name: "Sub", eSuperTypes: [remote])])
        let local = EClass(name: "Local", eSuperTypes: [remote])
        let package = EPackage(name: "p", eClassifiers: [local])
        let index = MetamodelIndex(roots: [package], externals: [external])
        #expect(index.element(remote.id)?.name == "Remote")
        #expect(index.isExternal(remote.id))
        #expect(!index.isExternal(local.id))
        #expect(!index.isExternal(EUUID()))
        #expect(index.fragment(of: remote.id) == "//Remote")
        #expect(index.root(of: remote.id) == external.id)
        #expect(index.allElements.map(\.id) == [package.id, local.id])
        #expect(index.usages(of: remote.id).map(\.referrer) == [local.id])
        #expect(index.subclasses(of: remote.id).map(\.name) == ["Local"])
        #expect(index.resolve(fragment: "//Remote") == nil)
        #expect(index.resolve(fragment: "//Remote", in: external.id)?.id == remote.id)
    }

    // MARK: Loaded models

    @Test("the index of a loaded metamodel is consistent for every element")
    func loadedConsistency() async throws {
        for (name, package) in try await MetamodelFixtures.fixturePackages() {
            let index = MetamodelIndex(roots: [package])
            for element in index.allElements {
                #expect(index.element(element.id)?.id == element.id, "\(name)")
                if let containment = index.container(of: element.id) {
                    let siblings = index.children(of: containment.container, feature: containment.feature)
                    #expect(siblings.indices.contains(containment.index), "\(name)")
                    #expect(siblings[containment.index].id == element.id, "\(name)")
                    #expect(index.root(of: element.id) == package.id, "\(name)")
                } else {
                    #expect(element.id == package.id, "\(name)")
                }
                let all = index.children(of: element.id)
                #expect(all.count == element.children.count, "\(name)")
            }
        }
    }

    @Test("usages and subclasses of the library fixture match its declarations")
    func libraryFixture() async throws {
        let package = try await FidelityFixtures.package("library-full.ecore")
        let index = MetamodelIndex(roots: [package])
        let named = try #require(package.getEClass("Named"))
        #expect(
            index.subclasses(of: named.id).map(\.name)
                == ["Book", "Writer", "Library", "LoanFailure", "Section"])
        #expect(index.subclasses(of: named.id, transitive: false).count == 5)
        #expect(index.subclasses(of: named.id, concreteOnly: true).count == 5)
        let lendable = try #require(package.getEClass("Lendable"))
        #expect(index.subclasses(of: lendable.id).map(\.name) == ["Book"])
        #expect(index.subclasses(of: lendable.id, concreteOnly: true).count == 1)
        let failure = try #require(package.getEClass("LoanFailure"))
        let uses = index.usages(of: failure.id)
        #expect(uses.map(\.feature) == [.eExceptions])
        #expect(index.element(uses[0].referrer)?.name == "borrow")
        let book = try #require(package.getEClass("Book"))
        let bookUses = index.usages(of: book.id)
        #expect(bookUses.allSatisfy { $0.feature == .eType })
        #expect(bookUses.count >= 4)
        let author = try #require(book.getEReference(name: "author"))
        #expect(index.usages(of: author.id).count == 1)
        #expect(index.usages(of: author.id)[0].feature == .eOpposite)
    }

    @Test("annotations of loaded metamodels get fragments that resolve")
    func loadedAnnotations() async throws {
        let packages = try await MetamodelFixtures.fixturePackages()
        let annotated = try #require(packages.first { $0.name == "annotated.ecore" }).package
        let index = MetamodelIndex(roots: [annotated])
        let annotations = index.allElements.filter { $0.kind == .eAnnotation }
        #expect(!annotations.isEmpty)
        for annotation in annotations {
            let fragment = try #require(index.fragment(of: annotation.id))
            #expect(fragment.contains("%"))
            #expect(index.resolve(fragment: fragment)?.id == annotation.id)
        }
    }
}
