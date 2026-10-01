//
// MetamodelSerialisationTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Metamodel Serialisation Tests")
struct MetamodelSerialisationTests {
    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ecore-reflection-\(UUID().uuidString)-\(name)")
    }

    private func typeName(of feature: any EStructuralFeature) -> String? {
        (feature as? EAttribute)?.eType.name ?? (feature as? EReference)?.eType.name
    }

    private func roundTrip(_ package: EPackage) async throws -> EPackage {
        let url = temporaryURL("\(package.name).ecore")
        defer { try? FileManager.default.removeItem(at: url) }
        try XMISerializer().serialize(package, to: url)
        return try await EPackage(url: url)
    }

    // MARK: - The Ecore package itself

    @Test("The reflective Ecore package serialises to an Ecore.ecore file and re-parses")
    func ecoreRoundTrip() async throws {
        let original = EcorePackage.instance
        let reparsed = try await roundTrip(original)
        #expect(reparsed.name == "ecore")
        #expect(reparsed.nsURI == EcorePackage.nsURI)
        #expect(reparsed.nsPrefix == EcorePackage.nsPrefix)
        #expect(reparsed.eClassifiers.count == original.eClassifiers.count)

        let originalClasses = original.eClassifiers.compactMap { $0 as? EClass }
        let reparsedClasses = reparsed.eClassifiers.compactMap { $0 as? EClass }
        #expect(reparsedClasses.map(\.name) == originalClasses.map(\.name))
        for (before, after) in zip(originalClasses, reparsedClasses) {
            #expect(after.isAbstract == before.isAbstract, "abstract flag of \(before.name)")
            #expect(
                after.eStructuralFeatures.map(\.name) == before.eStructuralFeatures.map(\.name),
                "features of \(before.name)")
            #expect(
                after.eSuperTypes.map(\.name) == before.eSuperTypes.map(\.name),
                "supertypes of \(before.name)")
        }
        let totalFeatures = originalClasses.reduce(0) { $0 + $1.eStructuralFeatures.count }
        #expect(reparsedClasses.reduce(0) { $0 + $1.eStructuralFeatures.count } == totalFeatures)
        #expect(totalFeatures > 50)
        let dataTypes = reparsed.eClassifiers.compactMap { $0 as? EDataType }
        #expect(dataTypes.count == EcoreDataType.allCases.count - 1)
    }

    @Test("Reparsed Ecore package keeps feature properties")
    func ecoreFeatureProperties() async throws {
        let reparsed = try await roundTrip(EcorePackage.instance)
        let eClass = try #require(reparsed.getEClass("EClass"))
        let structural = try #require(
            eClass.getStructuralFeature(name: "eStructuralFeatures") as? EReference)
        #expect(structural.containment)
        #expect(structural.upperBound == -1)
        #expect(structural.eType.name == "EStructuralFeature")
        let supertypes = try #require(eClass.getStructuralFeature(name: "eSuperTypes") as? EReference)
        #expect(!supertypes.containment && supertypes.upperBound == -1)
        #expect(eClass.getStructuralFeature(name: "abstract") is EAttribute)
        let package = try #require(reparsed.getEClass("EPackage"))
        #expect(
            (package.getStructuralFeature(name: "eClassifiers") as? EReference)?.containment == true)
        let typed = try #require(reparsed.getEClass("ETypedElement"))
        let upper = try #require(typed.getStructuralFeature(name: "upperBound") as? EAttribute)
        #expect(upper.defaultValueLiteral == "1")
        let many = try #require(typed.getStructuralFeature(name: "many") as? EAttribute)
        #expect(!many.changeable && many.volatile && many.transient)
        #expect(reparsed.getEClass("EAttribute")?.eSuperTypes.map(\.name) == ["EStructuralFeature"])
    }

    @Test("The serialised Ecore package is an ecore:EPackage document")
    func ecoreDocumentShape() {
        let text = XMISerializer().serialize(EcorePackage.instance)
        #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ecore:EPackage"))
        #expect(text.contains("xmlns:ecore=\"http://www.eclipse.org/emf/2002/Ecore\""))
        #expect(text.contains("name=\"ecore\""))
        #expect(text.contains("nsURI=\"http://www.eclipse.org/emf/2002/Ecore\""))
        #expect(text.contains("xsi:type=\"ecore:EClass\" name=\"EClass\""))
        #expect(text.contains("eSuperTypes=\"#//EStructuralFeature\""))
        #expect(text.contains("eOpposite=\"#//EClassifier/ePackage\""))
        #expect(text.hasSuffix("</ecore:EPackage>\n"))
        #expect(!text.contains("Swift."))
    }

    @Test("The serialised Ecore package loads as a metamodel resource")
    func ecoreAsResource() async throws {
        let url = temporaryURL("Ecore.ecore")
        defer { try? FileManager.default.removeItem(at: url) }
        try XMISerializer().serialize(EcorePackage.instance, to: url)
        let resource = try await XMIParser().parse(url)
        let classes = await resource.getAllInstancesOf(EcorePackage.metaClass(.eClass))
        #expect(classes.count == EcoreClassifier.allCases.count)
        let attributes = await resource.getAllInstancesOf(EcorePackage.metaClass(.eAttribute))
        let references = await resource.getAllInstancesOf(EcorePackage.metaClass(.eReference))
        let features = await resource.getAllInstancesOf(EcorePackage.metaClass(.eStructuralFeature))
        #expect(features.count == attributes.count + references.count)
        let nativeFeatureCount = EcoreClassifier.allCases.reduce(0) {
            $0 + EcorePackage.metaClass($1).eStructuralFeatures.count
        }
        #expect(features.count == nativeFeatureCount)
    }

    // MARK: - Hand-built and parsed metamodels

    @Test("Hand-built metamodel round trips")
    func libraryRoundTrip() async throws {
        let original = ReflectionFixtures.makeLibraryPackage()
        let reparsed = try await roundTrip(original)
        #expect(reparsed.name == original.name)
        #expect(reparsed.nsURI == original.nsURI)
        #expect(reparsed.nsPrefix == original.nsPrefix)
        let book = try #require(reparsed.getEClass("Book"))
        #expect(book.eSuperTypes.map(\.name) == ["Item"])
        #expect(book.eAllStructuralFeatures.map(\.name) == ["title", "pages", "genre", "tags"])
        let title = try #require(book.eAllAttributes.first)
        #expect(title.isID)
        #expect(title.lowerBound == 1)
        let tags = try #require(book.getStructuralFeature(name: "tags") as? EAttribute)
        #expect(tags.upperBound == -1)
        let items = try #require(
            reparsed.getEClass("Library")?.getStructuralFeature(name: "items") as? EReference)
        #expect(items.containment && items.upperBound == -1)
        #expect(items.eType.name == "Item")
        #expect(reparsed.getEClass("Library")?.getStructuralFeature(name: "featured") is EReference)
        #expect(reparsed.getEEnum("Genre")?.literals.map(\.name) == ["fiction", "history"])
        #expect(reparsed.getEEnum("Genre")?.getLiteral(name: "history")?.value == 1)
        #expect(reparsed.getEEnum("Genre")?.getLiteral(name: "history")?.literal == "HISTORY")
    }

    @Test("Parsed fixtures round trip", arguments: [
        "xmi/organisation.ecore", "xmi/animals.ecore", "metamodels/Families.ecore",
    ])
    func fixtureRoundTrip(path: String) async throws {
        let original = try await ReflectionFixtures.loadPackage(path)
        let reparsed = try await roundTrip(original)
        #expect(reparsed.name == original.name)
        #expect(reparsed.nsURI == original.nsURI)
        #expect(reparsed.eClassifiers.map(\.name) == original.eClassifiers.map(\.name))
        for case let before as EClass in original.eClassifiers {
            let after = try #require(reparsed.getEClass(before.name))
            #expect(after.eStructuralFeatures.map(\.name) == before.eStructuralFeatures.map(\.name))
            for (a, b) in zip(after.eStructuralFeatures, before.eStructuralFeatures) {
                #expect(typeName(of: a) == typeName(of: b) || typeName(of: b) == "EString")
            }
        }
    }

    @Test("Annotations are written")
    func annotations() {
        var package = EPackage(name: "p", nsURI: "http://p", nsPrefix: "p")
        package.eAnnotations = [EAnnotation(source: "http://doc", details: ["text": "a < b & \"c\""])]
        let text = XMISerializer().serialize(package)
        #expect(text.contains("<eAnnotations source=\"http://doc\">"))
        #expect(text.contains("<details key=\"text\" value=\"a &lt; b &amp; &quot;c&quot;\"/>"))
    }

    @Test("References to Ecore built-ins and unknown classifiers use qualified fragments")
    func externalReferences() {
        let external = EClass(name: "Elsewhere")
        let ecoreClass = EClass(name: "EObject")
        let ecoreEnumLike = EDataType(name: "EInt")
        let holder = EClass(
            name: "Holder",
            eStructuralFeatures: [
                EAttribute(name: "count", eType: ecoreEnumLike),
                EReference(name: "any", eType: ecoreClass),
                EReference(name: "other", eType: external),
            ])
        let text = XMISerializer().serialize(EPackage(name: "p", nsURI: "http://p", nsPrefix: "p", eClassifiers: [holder]))
        #expect(text.contains("eType=\"ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EInt\""))
        #expect(text.contains("eType=\"ecore:EClass http://www.eclipse.org/emf/2002/Ecore#//EObject\""))
        #expect(text.contains("eType=\"#//Elsewhere\""))
    }

    @Test("Nested packages and every feature flag are written")
    func flagsAndNesting() {
        let string = EDataType(name: "EString")
        let sub = EPackage(
            name: "sub", nsURI: "http://p/sub", nsPrefix: "sub",
            eClassifiers: [EClass(name: "Inner", isInterface: true)])
        let attribute = EAttribute(
            name: "a", eType: string, lowerBound: 1, upperBound: -1, changeable: false,
            volatile: true, transient: true, defaultValueLiteral: "x", isID: true,
            eAnnotations: [EAnnotation(source: "s")], ordered: false, unique: false,
            unsettable: true, derived: true)
        let outer = EClass(
            name: "Outer", isAbstract: true, eStructuralFeatures: [attribute],
            eAnnotations: [EAnnotation(source: "c")])
        let custom = EDataType(
            name: "Custom", serialisable: false, instanceClassName: "Foo.Bar",
            eAnnotations: [EAnnotation(source: "d")])
        let enumeration = EEnum(
            name: "Colour",
            literals: [
                EEnumLiteral(name: "red", value: 0, eAnnotations: [EAnnotation(source: "l")])
            ], eAnnotations: [EAnnotation(source: "e")])
        let text = XMISerializer().serialize(
            EPackage(
                name: "p", nsURI: "http://p", nsPrefix: "p",
                eClassifiers: [outer, custom, enumeration, EEnum(name: "Empty"), EClass(name: "Bare")],
                eSubpackages: [sub, EPackage(name: "empty", nsURI: "http://e", nsPrefix: "e")]))
        #expect(text.contains("abstract=\"true\""))
        #expect(text.contains("interface=\"true\""))
        #expect(text.contains("ordered=\"false\" unique=\"false\" lowerBound=\"1\" upperBound=\"-1\""))
        #expect(text.contains("changeable=\"false\" volatile=\"true\" transient=\"true\" defaultValueLiteral=\"x\" unsettable=\"true\" derived=\"true\" iD=\"true\""))
        #expect(text.contains("instanceClassName=\"Foo.Bar\" serializable=\"false\""))
        #expect(text.contains("<eSubpackages name=\"sub\""))
        #expect(text.contains("<eSubpackages name=\"empty\" nsURI=\"http://e\" nsPrefix=\"e\"/>"))
        #expect(text.contains("<eClassifiers xsi:type=\"ecore:EClass\" name=\"Bare\"/>"))
        #expect(text.contains("<eClassifiers xsi:type=\"ecore:EEnum\" name=\"Empty\"/>"))
        #expect(text.contains("<eLiterals name=\"red\">"))
        #expect(text.contains("<eAnnotations source=\"l\"/>"))
        #expect(text.contains("<eAnnotations source=\"e\"/>"))
        #expect(text.contains("<eAnnotations source=\"d\"/>"))
    }

    @Test("Reference opposites and nested fragments are written as paths")
    func oppositesAndPaths() {
        let aID = EUUID()
        let bID = EUUID()
        let toB = EReference(
            name: "toB", eType: EClass(id: bID, name: "B"), opposite: nil, resolveProxies: false)
        let a = EClass(id: aID, name: "A", eStructuralFeatures: [toB])
        let fromB = EReference(
            name: "fromB", eType: EClass(id: aID, name: "A"), opposite: toB.id)
        let b = EClass(id: bID, name: "B", eStructuralFeatures: [fromB])
        let sub = EPackage(name: "sub", nsURI: "http://sub", nsPrefix: "sub", eClassifiers: [b])
        let text = XMISerializer().serialize(
            EPackage(
                name: "p", nsURI: "http://p", nsPrefix: "p", eClassifiers: [a],
                eSubpackages: [sub]))
        #expect(text.contains("eType=\"#//sub/B\""))
        #expect(text.contains("eOpposite=\"#//A/toB\""))
        #expect(text.contains("resolveProxies=\"false\""))
        #expect(text.contains("eType=\"#//A\""))
    }
}
