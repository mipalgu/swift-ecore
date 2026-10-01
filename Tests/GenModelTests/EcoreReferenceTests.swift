//
// EcoreReferenceTests.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import Testing

@testable import GenModel

@Suite("Ecore references")
struct EcoreReferenceTests {
    @Test(
        "references parse into qualifier, location and segments",
        arguments: [
            ("library.ecore#//Book", nil, "library.ecore", ["Book"]),
            (
                "ecore:EAttribute library.ecore#//Book/title", "ecore:EAttribute", "library.ecore",
                ["Book", "title"]
            ),
            ("library.ecore#/", nil, "library.ecore", []),
            ("#//Book", nil, "", ["Book"]),
            ("../m/lib.ecore#//@eClassifiers.0/@eStructuralFeatures.1", nil, "../m/lib.ecore",
                ["@eClassifiers.0", "@eStructuralFeatures.1"]),
            ("  library.ecore#//Book  ", nil, "library.ecore", ["Book"]),
        ] as [(String, String?, String, [String])])
    func parsing(text: String, qualifier: String?, location: String, segments: [String]) throws {
        let reference = try #require(EcoreReference(text))
        #expect(reference.typeQualifier == qualifier)
        #expect(reference.location == location)
        #expect(reference.segments == segments)
    }

    @Test("text without a fragment separator is not a reference", arguments: ["", "Book", "ecore:EClass Book"])
    func notAReference(text: String) {
        #expect(EcoreReference(text) == nil)
    }

    @Test(
        "last segment names ignore positions and overload suffixes",
        arguments: [
            ("m.ecore#//A/b", "b"), ("m.ecore#//A/b.1", "b"), ("m.ecore#//A/@eOperations.0", nil),
            ("m.ecore#/", nil), ("m.ecore#//A/v1.2.3", "v1.2"), ("m.ecore#//A/x.y", "x.y"),
        ] as [(String, String?)])
    func lastSegment(text: String, expected: String?) throws {
        #expect(try #require(EcoreReference(text)).lastSegmentName == expected)
    }

    private func fixture() -> (EPackage, URL) {
        let name = EAttribute(name: "name", eType: EDataType(name: "EString"))
        let year = EAttribute(name: "year", eType: EDataType(name: "EInt"))
        let book = EClass(name: "Book", eStructuralFeatures: [name, year])
        let kind = EEnum(
            name: "Kind", literals: [EEnumLiteral(name: "A", value: 0), EEnumLiteral(name: "B", value: 1)])
        let inner = EClass(name: "Inner")
        let sub = EPackage(name: "sub", nsURI: "http://example.org/sub", nsPrefix: "s", eClassifiers: [inner])
        let package = EPackage(
            name: "lib", nsURI: "http://example.org/lib", nsPrefix: "l", eClassifiers: [book, kind, EDataType(name: "Code")],
            eSubpackages: [sub])
        return (package, URL(fileURLWithPath: "/models/lib.ecore"))
    }

    @Test("name and position paths resolve to native elements")
    func resolution() throws {
        let (package, url) = fixture()
        let base = URL(fileURLWithPath: "/models/shelf.genmodel")
        let resolver = EcoreFragmentResolver(packages: [url: package])
        let book = try #require(package.getEClass("Book"))
        let kind = try #require(package.getClassifier("Kind") as? EEnum)
        let sub = try #require(package.eSubpackages.first)

        #expect(resolver.resolve("lib.ecore#/", relativeTo: base) == package.id)
        #expect(resolver.resolve("lib.ecore#//Book", relativeTo: base) == book.id)
        #expect(
            resolver.resolve("ecore:EAttribute lib.ecore#//Book/year", relativeTo: base)
                == book.eStructuralFeatures[1].id)
        #expect(resolver.resolve("lib.ecore#//Kind/B", relativeTo: base) == kind.literals[1].id)
        #expect(resolver.resolve("lib.ecore#//Code", relativeTo: base) == package.eClassifiers[2].id)
        #expect(resolver.resolve("lib.ecore#//sub", relativeTo: base) == sub.id)
        #expect(resolver.resolve("lib.ecore#//sub/Inner", relativeTo: base) == sub.eClassifiers[0].id)
        #expect(resolver.resolve("lib.ecore#//@eClassifiers.0", relativeTo: base) == book.id)
        #expect(
            resolver.resolve("lib.ecore#//@eClassifiers.0/@eStructuralFeatures.0", relativeTo: base)
                == book.eStructuralFeatures[0].id)
        #expect(resolver.resolve("lib.ecore#//@eClassifiers.1/@eLiterals.0", relativeTo: base) == kind.literals[0].id)
        #expect(resolver.resolve("lib.ecore#//@eSubpackages.0", relativeTo: base) == sub.id)
        #expect(resolver.resolve("../models/lib.ecore#//Book", relativeTo: base) == book.id)
        #expect(resolver.resolve("#//Book", relativeTo: url) == book.id)
    }

    @Test(
        "unresolvable references yield nil",
        arguments: [
            "lib.ecore#//Missing", "lib.ecore#//Book/missing", "other.ecore#//Book", "lib.ecore#//Code/x",
            "lib.ecore#//@eClassifiers.9", "lib.ecore#//@eClassifiers.x", "lib.ecore#//@eClassifiers.-1",
            "lib.ecore#//@eStructuralFeatures.0", "lib.ecore#//Book/@eStructuralFeatures.5",
            "lib.ecore#//Kind/@eLiterals.5", "lib.ecore#//@eSubpackages.3", "lib.ecore#//@bogus",
            "plain text", "lib.ecore#//Book/year/deeper",
        ])
    func unresolvable(text: String) {
        let (package, url) = fixture()
        let resolver = EcoreFragmentResolver(packages: [url: package])
        #expect(resolver.resolve(text, relativeTo: URL(fileURLWithPath: "/models/shelf.genmodel")) == nil)
    }
}
