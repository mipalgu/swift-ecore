//
// MetamodelTestSupport.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Builds metamodels and loads fixtures for the index, fragment, linker, and copier tests.
enum MetamodelFixtures {
    /// The string data type of Ecore.
    static var string: any EClassifier { EcorePackage.dataType(.eString)! }

    /// A hand-built metamodel: a package `shop` with a subpackage `sub`.
    ///
    /// `Item` has the attribute `label` and a reference `owner` to `Owner` (opposite `items`);
    /// `Special` extends `Item` and has an operation `check` with the parameter `level`;
    /// `Kind` is an enumeration with the literals `A` and `B`; `Owner` is abstract and has the
    /// reference `items`; `sub` holds `Inner`, which extends `Special`.
    struct Shop {
        var item: EClass
        var special: EClass
        var owner: EClass
        var inner: EClass
        var kind: EEnum
        var package: EPackage
        var subpackage: EPackage
    }

    static func shop() -> Shop {
        let owner = EClass(name: "Owner", isAbstract: true)
        let item = EClass(name: "Item")
        var items = EReference(name: "items", eType: item, upperBound: -1, containment: true)
        var itemOwner = EReference(name: "owner", eType: owner)
        items.opposite = itemOwner.id
        itemOwner.opposite = items.id
        var ownerWithFeatures = owner
        ownerWithFeatures.eStructuralFeatures = [items]
        var itemWithFeatures = item
        itemWithFeatures.eStructuralFeatures = [EAttribute(name: "label", eType: string), itemOwner]
        let check = EOperation(
            name: "check", eType: EcorePackage.dataType(.eBoolean),
            eParameters: [EParameter(name: "level", eType: EcorePackage.dataType(.eInt))])
        let special = EClass(
            name: "Special", eSuperTypes: [itemWithFeatures], eOperations: [check])
        let inner = EClass(name: "Inner", eSuperTypes: [special])
        let kind = EEnum(
            name: "Kind", literals: [EEnumLiteral(name: "A", value: 0), EEnumLiteral(name: "B", value: 1)])
        let sub = EPackage(name: "sub", nsURI: "http://shop/sub", nsPrefix: "sub", eClassifiers: [inner])
        let package = EPackage(
            name: "shop", nsURI: "http://shop", nsPrefix: "shop",
            eClassifiers: [ownerWithFeatures, itemWithFeatures, special, kind], eSubpackages: [sub])
        return Shop(
            item: itemWithFeatures, special: special, owner: ownerWithFeatures, inner: inner, kind: kind,
            package: package, subpackage: sub)
    }

    /// A feature as a metamodel object.
    static func object(_ feature: any EStructuralFeature) -> any EObject {
        EcoreElement.feature(feature)!.object
    }

    /// The URLs of every `.ecore` fixture.
    static func fixtureURLs() throws -> [URL] {
        let root = try ReflectionFixtures.resourcesURL()
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var urls: [URL] = []
        while let url = walker?.nextObject() as? URL {
            if url.pathExtension == "ecore" { urls.append(url) }
        }
        return urls.sorted { $0.path < $1.path }
    }

    /// Every fixture that loads as a native package, by file name.
    static func fixturePackages() async throws -> [(name: String, package: EPackage)] {
        var result: [(String, EPackage)] = []
        for url in try fixtureURLs() {
            if let package = try? await EPackage(url: url) { result.append((url.lastPathComponent, package)) }
        }
        return result
    }

    /// Every element below a package, and the package itself, in document order.
    static func elements(of root: EPackage) -> [EcoreElement] {
        MetamodelIndex(roots: [root]).allElements
    }
}
