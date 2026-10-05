//
// EditTestSupport.swift
// ECoreEditTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ECoreEdit

/// A small metamodel for the editing tests.
///
/// The package `shop` holds `Owner` (abstract, with the containment `items` whose opposite is
/// `Item.owner`), `Item` (with the attribute `label`), `Special` (extends `Item`, with the
/// operation `check(level)` that throws `Failure`), `Failure`, and the enumeration `Kind` with the
/// literals `A` and `B`. The subpackage `sub` holds `Inner`, which extends `Special`. `Item` carries
/// an annotation with the details `a` and `b` that refers to `Special`.
struct Fixture {
    var document: MetamodelDocument

    static let sourceURI = "http://example.org/doc"

    init() {
        let string = EcorePackage.dataType(.eString)!
        let owner = EClass(name: "Owner", isAbstract: true)
        let item = EClass(name: "Item")
        let failure = EClass(name: "Failure")
        var items = EReference(name: "items", eType: item, upperBound: -1, containment: true)
        var itemOwner = EReference(name: "owner", eType: owner, container: true)
        items.opposite = itemOwner.id
        itemOwner.opposite = items.id
        var ownerWithFeatures = owner
        ownerWithFeatures.eStructuralFeatures = [items]
        let special = EClass(name: "Special", eSuperTypes: [item])
        var itemWithFeatures = item
        itemWithFeatures.eStructuralFeatures = [EAttribute(name: "label", eType: string), itemOwner]
        itemWithFeatures.eAnnotations = [
            EAnnotation(
                source: Self.sourceURI, orderedDetails: ["a": "1", "b": "2"],
                references: [.local(special.id)])
        ]
        let check = EOperation(
            name: "check", eType: EcorePackage.dataType(.eBoolean),
            eParameters: [EParameter(name: "level", eType: EcorePackage.dataType(.eInt))],
            eExceptions: [failure])
        var specialWithOperation = special
        specialWithOperation.eSuperTypes = [itemWithFeatures]
        specialWithOperation.eOperations = [check]
        let inner = EClass(name: "Inner", eSuperTypes: [specialWithOperation])
        let kind = EEnum(
            name: "Kind", literals: [EEnumLiteral(name: "A", value: 0), EEnumLiteral(name: "B", value: 1)])
        let sub = EPackage(name: "sub", nsURI: "http://shop/sub", nsPrefix: "sub", eClassifiers: [inner])
        let package = EPackage(
            name: "shop", nsURI: "http://shop", nsPrefix: "shop",
            eClassifiers: [ownerWithFeatures, itemWithFeatures, specialWithOperation, failure, kind],
            eSubpackages: [sub])
        document = MetamodelDocument(roots: MetamodelLinker.relinked([package]), uri: "memory:shop.ecore")
    }

    var index: MetamodelIndex { document.index }

    /// The identifier of the first element with a name.
    func id(_ name: String) -> EUUID {
        document.index.allElements.first { $0.name == name }!.id
    }

    /// The identifier of the first child with a name.
    func id(_ name: String, in container: String) -> EUUID {
        document.index.children(of: id(container)).first { $0.name == name }!.id
    }

    var rootID: EUUID { document.roots[0].id }

    /// The annotation of `Item`.
    var annotationID: EUUID { document.index.children(of: id("Item"), feature: .eAnnotations)[0].id }

    func element(_ identifier: EUUID) -> EcoreElement { document.index.element(identifier)! }

    func eClass(_ name: String) -> EClass {
        guard case .eClass(let value) = element(id(name)) else { fatalError("not a class") }
        return value
    }

    func reference(_ name: String, in container: String) -> EReference {
        guard case .reference(let value) = element(id(name, in: container)) else { fatalError("not a reference") }
        return value
    }

    func attribute(_ name: String, in container: String) -> EAttribute {
        guard case .attribute(let value) = element(id(name, in: container)) else { fatalError("not an attribute") }
        return value
    }

    func annotation() -> EAnnotation {
        guard case .annotation(let value) = element(annotationID) else { fatalError("not an annotation") }
        return value
    }
}

/// The built-in Ecore data type with a name.
func builtIn(_ type: EcoreDataType) -> EUUID { EcorePackage.dataType(type)!.id }
