//
// EcoreCopierTests.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Ecore Copier Tests")
struct EcoreCopierTests {
    private let shop = MetamodelFixtures.shop()

    private func ids(of element: EcoreElement) -> Set<EUUID> {
        func collect(_ element: EcoreElement, _ result: inout Set<EUUID>) {
            result.insert(element.id)
            for child in element.children { collect(child.element, &result) }
        }
        var result: Set<EUUID> = []
        collect(element, &result)
        return result
    }

    @Test("a copied package has fresh identifiers throughout and the same structure")
    func copiesPackage() throws {
        let copy = EcoreCopier.copy([.package(shop.package)])
        let original = ids(of: .package(shop.package))
        let copied = try #require(copy.elements.first)
        let fresh = ids(of: copied)
        #expect(fresh.count == original.count)
        #expect(fresh.isDisjoint(with: original))
        #expect(Set(copy.identifiers.keys) == original)
        #expect(Set(copy.identifiers.values) == fresh)
        let index = MetamodelIndex(roots: [try #require(copied.object as? EPackage)])
        #expect(index.allElements.compactMap(\.name) == MetamodelFixtures.elements(of: shop.package).compactMap(\.name))
        #expect(index.allElements.map(\.kind) == MetamodelFixtures.elements(of: shop.package).map(\.kind))
    }

    @Test("references between copied elements are remapped at every depth")
    func remapsInternalReferences() throws {
        let copy = EcoreCopier.copy([.package(shop.package)])
        let package = try #require(copy.elements.first?.object as? EPackage)
        let newItem = try #require(package.getEClass("Item"))
        let newOwner = try #require(package.getEClass("Owner"))
        let map = copy.identifiers
        #expect(newItem.id == map[shop.item.id])
        let owner = try #require(newItem.getEReference(name: "owner"))
        #expect(owner.eType.id == newOwner.id)
        #expect(owner.opposite == newOwner.getEReference(name: "items")?.id)
        #expect(newOwner.getEReference(name: "items")?.opposite == owner.id)
        let special = try #require(package.getEClass("Special"))
        #expect(special.eSuperTypes.map(\.id) == [newItem.id])
        let inner = try #require(package.getSubpackage("sub")?.getEClass("Inner"))
        #expect(inner.eSuperTypes[0].id == special.id)
        #expect(inner.eSuperTypes[0].eSuperTypes[0].id == newItem.id)
        #expect(inner.eSuperTypes[0].eSuperTypes[0].getEReference(name: "owner")?.eType.id == newOwner.id)
        let index = MetamodelIndex(roots: [package])
        #expect(index.subclasses(of: newItem.id).map(\.name) == ["Special", "Inner"])
        #expect(index.usages(of: shop.item.id).isEmpty)
    }

    @Test("references to elements that were not copied are kept")
    func keepsExternalReferences() throws {
        let copy = EcoreCopier.copy([.eClass(shop.special)])
        let special = try #require(copy.elements.first?.object as? EClass)
        #expect(special.id != shop.special.id)
        #expect(special.eSuperTypes.map(\.id) == [shop.item.id])
        let check = special.eOperations[0]
        #expect(check.id != shop.special.eOperations[0].id)
        #expect(check.eType?.id == EcorePackage.dataType(.eBoolean)?.id)
        #expect(check.eParameters[0].id != shop.special.eOperations[0].eParameters[0].id)
        let item = try #require(copy.elements.first.flatMap { _ in shop.item.eStructuralFeatures[1] as? EReference })
        let copiedReference = EcoreCopier.copy([.reference(item)])
        let reference = try #require(copiedReference.elements.first?.object as? EReference)
        #expect(reference.eType.id == shop.owner.id)
        #expect(reference.opposite == item.opposite)
        #expect(reference.name == "owner")
    }

    @Test("copying several classes remaps references among them only")
    func copiesClasses() throws {
        let copy = EcoreCopier.copy([.eClass(shop.item), .eClass(shop.special)])
        let item = try #require(copy.elements[0].object as? EClass)
        let special = try #require(copy.elements[1].object as? EClass)
        #expect(special.eSuperTypes.map(\.id) == [item.id])
        #expect(item.getEReference(name: "owner")?.eType.id == shop.owner.id)
        #expect(item.getEReference(name: "owner")?.opposite == shop.item.getEReference(name: "owner")?.opposite)
        #expect(copy.identifiers[shop.item.id] == item.id)
        #expect(copy.identifiers[shop.owner.id] == nil)
    }

    /// A package that sets every property of the copied kinds to a non-default value.
    private func propertyModel() -> (package: EPackage, annotation: EAnnotation) {
        let doc = EAnnotation(
            source: "doc", orderedDetails: ["z": "1", "a": "2"],
            eAnnotations: [EAnnotation(source: "inner", orderedDetails: ["k": "v"])])
        let attribute = EAttribute(
            name: "attr", eType: MetamodelFixtures.string, lowerBound: 1, upperBound: -1, changeable: false,
            volatile: true, transient: true, defaultValueLiteral: "x", isID: true, eAnnotations: [doc],
            ordered: false, unique: false, unsettable: true, derived: true)
        let target = EClass(name: "T")
        let reference = EReference(
            name: "ref", eType: target, lowerBound: 1, upperBound: 3, changeable: false, volatile: true,
            transient: true, containment: true, resolveProxies: false, ordered: false, unique: false,
            unsettable: true, derived: true, container: true)
        let operation = EOperation(
            name: "op", eType: target, lowerBound: 1, upperBound: 2, ordered: false, unique: false,
            eParameters: [
                EParameter(name: "p", eType: target, lowerBound: 1, upperBound: 4, ordered: false, unique: false)
            ], eExceptions: [target])
        let eClass = EClass(
            name: "C", isAbstract: true, isInterface: true, eStructuralFeatures: [attribute, reference],
            eOperations: [operation], instanceClassName: "a.B")
        let enumeration = EEnum(name: "E", literals: [EEnumLiteral(name: "L", value: 7, literal: "ell")])
        let datatype = EDataType(
            name: "D", serialisable: false, instanceClassName: "java.lang.Foo", defaultValueLiteral: "d")
        let package = EPackage(
            name: "p", nsURI: "http://p", nsPrefix: "pp", eClassifiers: [eClass, target, enumeration, datatype])
        return (package, doc)
    }

    @Test("all properties of the copied kinds are kept")
    func properties() throws {
        let (package, doc) = propertyModel()
        let copy = EcoreCopier.copy([.package(package)])
        let copied = try #require(copy.elements[0].object as? EPackage)
        #expect(copied.nsURI == "http://p")
        #expect(copied.nsPrefix == "pp")
        let c = try #require(copied.getEClass("C"))
        #expect(c.isAbstract)
        #expect(c.isInterface)
        #expect(c.instanceClassName == "a.B")
        let a = try #require(c.getEAttribute(name: "attr"))
        #expect(a.lowerBound == 1)
        #expect(a.upperBound == -1)
        #expect(a.changeable == false)
        #expect(a.volatile)
        #expect(a.transient)
        #expect(a.defaultValueLiteral == "x")
        #expect(a.isID)
        #expect(a.ordered == false)
        #expect(a.unique == false)
        #expect(a.unsettable)
        #expect(a.derived)
        #expect(a.eAnnotations[0].details.keys.elements == ["z", "a"])
        #expect(a.eAnnotations[0].eAnnotations[0].source == "inner")
        #expect(a.eAnnotations[0].id != doc.id)
        #expect(a.eAnnotations[0].detailEntries.map(\.id) != doc.detailEntries.map(\.id))
        let r = try #require(c.getEReference(name: "ref"))
        #expect(r.lowerBound == 1)
        #expect(r.upperBound == 3)
        #expect(r.changeable == false)
        #expect(r.volatile)
        #expect(r.transient)
        #expect(r.containment)
        #expect(r.resolveProxies == false)
        #expect(r.ordered == false)
        #expect(r.unique == false)
        #expect(r.unsettable)
        #expect(r.derived)
        #expect(r.container)
        let copiedTarget = try #require(copied.getEClass("T"))
        #expect(r.eType.id == copiedTarget.id)
        let o = try #require(c.getOperation(name: "op"))
        #expect(o.lowerBound == 1)
        #expect(o.upperBound == 2)
        #expect(o.ordered == false)
        #expect(o.unique == false)
        #expect(o.eExceptions.map { $0.id } == [copiedTarget.id])
        #expect(o.eParameters[0].eType?.id == copiedTarget.id)
        #expect(o.eParameters[0].upperBound == 4)
        #expect(o.eParameters[0].ordered == false)
        let e = try #require(copied.getEEnum("E"))
        #expect(e.literals[0].value == 7)
        #expect(e.literals[0].literal == "ell")
        let d = try #require(copied.getEDataType("D"))
        #expect(d.serialisable == false)
        #expect(d.instanceClassName == "java.lang.Foo")
        #expect(d.defaultValueLiteral == "d")
    }

    @Test("annotation references to copied elements are remapped and others are kept")
    func annotationReferences() throws {
        let inside = EClass(name: "Inside")
        let outside = EClass(name: "Outside")
        let proxy = ResourceProxy(uri: "x.ecore", fragment: "//Y")
        let annotation = EAnnotation(
            source: "s", references: [.local(inside.id), .local(outside.id), .external(proxy)])
        let host = EClass(name: "Host", eAnnotations: [annotation])
        let package = EPackage(name: "p", eClassifiers: [host, inside])
        let copy = EcoreCopier.copy([.package(package)])
        let copied = try #require(copy.elements[0].object as? EPackage)
        let references = try #require(copied.getEClass("Host")?.eAnnotations.first?.references)
        #expect(references == [.local(try #require(copied.getEClass("Inside")).id), .local(outside.id), .external(proxy)])
    }

    @Test("every kind of element can be copied alone")
    func everyKind() throws {
        let annotation = EAnnotation(source: "s", orderedDetails: ["k": "v"])
        let entry = try #require(annotation.detailEntries.first)
        let elements: [EcoreElement] = [
            .package(shop.package), .eClass(shop.item), .dataType(EDataType(name: "D")), .eEnum(shop.kind),
            .literal(shop.kind.literals[0]), .attribute(EAttribute(name: "a", eType: shop.item)),
            .reference(try #require(shop.item.eStructuralFeatures[1] as? EReference)),
            .operation(shop.special.eOperations[0]), .parameter(shop.special.eOperations[0].eParameters[0]),
            .annotation(annotation), .detail(entry),
        ]
        let copy = EcoreCopier.copy(elements)
        #expect(copy.elements.map(\.kind) == elements.map(\.kind))
        #expect(copy.elements.map(\.name) == elements.map(\.name))
        for (original, copied) in zip(elements, copy.elements) {
            #expect(original.id != copied.id)
            #expect(copy.identifiers[original.id] == copied.id)
        }
        guard case .detail(let copiedEntry) = copy.elements[10] else {
            Issue.record("not a detail entry")
            return
        }
        #expect(copiedEntry.key == "k" && copiedEntry.value == "v")
        #expect(EcoreCopier.copy([]).elements.isEmpty)
    }

    @Test("standalone typed elements that name copied classes are retargeted")
    func standaloneTypes() throws {
        let target = EClass(name: "T")
        let feature = EReference(name: "r", eType: target)
        let parameter = EParameter(name: "p", eType: target)
        let operation = EOperation(name: "o", eType: target, eParameters: [parameter])
        let attribute = EAttribute(name: "a", eType: target)
        let copy = EcoreCopier.copy([
            .eClass(target), .reference(feature), .parameter(parameter), .operation(operation),
            .attribute(attribute),
        ])
        let newTarget = copy.elements[0].id
        #expect((copy.elements[1].object as? EReference)?.eType.id == newTarget)
        #expect((copy.elements[2].object as? EParameter)?.eType?.id == newTarget)
        #expect((copy.elements[3].object as? EOperation)?.eType?.id == newTarget)
        #expect((copy.elements[3].object as? EOperation)?.eParameters[0].eType?.id == newTarget)
        #expect((copy.elements[4].object as? EAttribute)?.eType.id == newTarget)
    }

    @Test("a copy of a loaded metamodel serialises like the original apart from identity")
    func loadedCopy() async throws {
        let package = try await FidelityFixtures.package("library-full.ecore")
        let copy = EcoreCopier.copy([.package(package)])
        let copied = try #require(copy.elements[0].object as? EPackage)
        let original = MetamodelFixtures.elements(of: package)
        let copies = MetamodelFixtures.elements(of: copied)
        #expect(original.count == copies.count)
        #expect(Set(copies.map(\.id)).isDisjoint(with: original.map(\.id)))
        let expected = XMISerializer().serialize(package)
        #expect(XMISerializer().serialize(copied) == expected)
    }
}
