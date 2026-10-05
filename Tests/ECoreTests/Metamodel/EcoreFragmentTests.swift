//
// EcoreFragmentTests.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Ecore Fragment Tests")
struct EcoreFragmentTests {
    private let shop = MetamodelFixtures.shop()

    // MARK: Encoding

    @Test("names without reserved characters are not encoded")
    func plainNames() {
        #expect(EcoreFragment.encode(name: "Book_2.x@y[z]") == "Book_2.x@y[z]")
    }

    @Test("reserved characters of names are percent-encoded as EMF does")
    func reservedNames() {
        #expect(EcoreFragment.encode(name: "a b/c:d") == "a%20b%2Fc%3Ad")
        #expect(EcoreFragment.encode(name: "\"#%&',<>") == "%22%23%25%26%27%2C%3C%3E")
        #expect(EcoreFragment.encode(name: "tab\there") == "tab%09here")
    }

    @Test("annotation sources keep URI punctuation and escape slashes and percent signs")
    func sources() {
        #expect(
            EcoreFragment.encode(source: "http://www.eclipse.org/emf/2002/GenModel")
                == "http:%2F%2Fwww.eclipse.org%2Femf%2F2002%2FGenModel")
        #expect(EcoreFragment.encode(source: "a b%c") == "a%20b%25c")
        #expect(EcoreFragment.encode(source: "x-_.!~*'();:@&=+$,y") == "x-_.!~*'();:@&=+$,y")
        #expect(EcoreFragment.encode(source: "é") == "é")
    }

    @Test("decoding reverses encoding, including non-ASCII text")
    func decoding() {
        for text in ["a b/c:d", "100%", "naïve é", "\"quoted\""] {
            #expect(EcoreFragment.decode(EcoreFragment.encode(name: text)) == text)
            #expect(EcoreFragment.decode(EcoreFragment.encode(source: text)) == text)
        }
        #expect(EcoreFragment.decode("%C3%A9") == "é")
        #expect(EcoreFragment.decode("50%") == "50%")
        #expect(EcoreFragment.decode("%zz") == "%zz")
    }

    // MARK: Fragments

    @Test("fragments follow the containment path")
    func hierarchy() throws {
        let fragments = EcoreFragment.fragments(in: shop.package)
        #expect(fragments[shop.package.id] == "/")
        #expect(fragments[shop.item.id] == "//Item")
        #expect(fragments[shop.item.eStructuralFeatures[0].id] == "//Item/label")
        #expect(fragments[shop.special.eOperations[0].id] == "//Special/check")
        #expect(fragments[shop.special.eOperations[0].eParameters[0].id] == "//Special/check/level")
        #expect(fragments[shop.kind.literals[1].id] == "//Kind/B")
        #expect(fragments[shop.subpackage.id] == "//sub")
        #expect(fragments[shop.inner.id] == "//sub/Inner")
    }

    @Test("a duplicate name takes the number of earlier siblings as a suffix")
    func duplicates() {
        let first = EClass(name: "Twin")
        let second = EClass(name: "Twin")
        let third = EClass(name: "Twin")
        let other = EClass(name: "Other")
        let package = EPackage(name: "p", eClassifiers: [first, other, second, third])
        let fragments = EcoreFragment.fragments(in: package)
        #expect(fragments[first.id] == "//Twin")
        #expect(fragments[second.id] == "//Twin.1")
        #expect(fragments[third.id] == "//Twin.2")
        #expect(fragments[other.id] == "//Other")
    }

    @Test("duplicates are counted across the containments of a parent, operations first")
    func duplicatesAcrossContainments() {
        let feature = EAttribute(name: "size", eType: MetamodelFixtures.string)
        let operation = EOperation(name: "size")
        let eClass = EClass(name: "C", eStructuralFeatures: [feature], eOperations: [operation])
        let package = EPackage(name: "p", eClassifiers: [eClass])
        let fragments = EcoreFragment.fragments(in: package)
        #expect(fragments[operation.id] == "//C/size")
        #expect(fragments[feature.id] == "//C/size.1")
        let subpackage = EPackage(name: "Same")
        let sameName = EPackage(name: "p2", eClassifiers: [EClass(name: "Same")], eSubpackages: [subpackage])
        let again = EcoreFragment.fragments(in: sameName)
        #expect(again[subpackage.id] == "//Same.1")
    }

    @Test("names with reserved characters are encoded in fragments")
    func encodedFragments() {
        let odd = EClass(name: "a/b c")
        let package = EPackage(name: "p", eClassifiers: [odd])
        #expect(EcoreFragment.fragments(in: package)[odd.id] == "//a%2Fb%20c")
        #expect(EcoreFragment.resolve("//a%2Fb%20c", in: [package])?.id == odd.id)
    }

    @Test("annotations are named by their encoded source, with a suffix for duplicates")
    func annotations() {
        let source = "http://www.eclipse.org/emf/2002/GenModel"
        let nested = EAnnotation(source: "inner", orderedDetails: ["k": "v"])
        let first = EAnnotation(
            source: source, orderedDetails: ["documentation": "d", "other": "o"], eAnnotations: [nested])
        let second = EAnnotation(source: source)
        let third = EAnnotation(source: "plain")
        let eClass = EClass(name: "C", eAnnotations: [first, second, third])
        let package = EPackage(name: "p", eClassifiers: [eClass])
        let fragments = EcoreFragment.fragments(in: package)
        let prefix = "//C/%http:%2F%2Fwww.eclipse.org%2Femf%2F2002%2FGenModel%"
        #expect(fragments[first.id] == prefix)
        #expect(fragments[second.id] == prefix + ".1")
        #expect(fragments[third.id] == "//C/%plain%")
        #expect(fragments[nested.id] == prefix + "/%inner%")
        let entries = first.detailEntries
        #expect(fragments[entries[0].id] == prefix + "/@details.0")
        #expect(fragments[entries[1].id] == prefix + "/@details.1")
        #expect(fragments[nested.detailEntries[0].id] == prefix + "/%inner%/@details.0")
    }

    @Test("a document with several roots numbers its roots")
    func multipleRoots() throws {
        let one = EPackage(name: "one", eClassifiers: [EClass(name: "A")])
        let two = EPackage(name: "two", eClassifiers: [EClass(name: "B")])
        let a = try #require(one.eClassifiers.first)
        let b = try #require(two.eClassifiers.first)
        #expect(EcoreFragment.fragment(of: two.id, in: two, rootIndex: 1) == "/1")
        #expect(EcoreFragment.fragment(of: b.id, in: two, rootIndex: 1) == "/1/B")
        #expect(EcoreFragment.resolve("/1/B", in: [one, two])?.id == b.id)
        #expect(EcoreFragment.resolve("/0/A", in: [one, two])?.id == a.id)
        #expect(EcoreFragment.resolve("/0", in: [one, two])?.id == one.id)
        #expect(EcoreFragment.resolve("//A", in: [one, two])?.id == a.id)
        #expect(EcoreFragment.resolve("/2/A", in: [one, two]) == nil)
        #expect(EcoreFragment.resolve("/x/A", in: [one, two]) == nil)
    }

    @Test("fragment(of:in:) answers nil for an element outside the root")
    func outside() {
        #expect(EcoreFragment.fragment(of: EUUID(), in: shop.package) == nil)
        #expect(EcoreFragment.fragment(of: shop.item.id, in: shop.package) == "//Item")
    }

    // MARK: Resolution

    @Test("resolve answers the element of a fragment, with or without a leading hash")
    func resolving() {
        let roots = [shop.package]
        #expect(EcoreFragment.resolve("/", in: roots)?.id == shop.package.id)
        #expect(EcoreFragment.resolve("#/", in: roots)?.id == shop.package.id)
        #expect(EcoreFragment.resolve("", in: roots)?.id == shop.package.id)
        #expect(EcoreFragment.resolve("#//sub/Inner", in: roots)?.id == shop.inner.id)
        #expect(EcoreFragment.resolve("//Special/check/level", in: roots)?.kind == .eParameter)
    }

    @Test("resolve answers nil for fragments that name nothing")
    func unresolvable() {
        let roots = [shop.package]
        #expect(EcoreFragment.resolve("//Nothing", in: roots) == nil)
        #expect(EcoreFragment.resolve("//Item/label/deeper", in: roots) == nil)
        #expect(EcoreFragment.resolve("//Item.5", in: roots) == nil)
        #expect(EcoreFragment.resolve("Item", in: roots) == nil)
        #expect(EcoreFragment.resolve("/", in: []) == nil)
        #expect(EcoreFragment.resolve("//Item/@details.0", in: roots) == nil)
        #expect(EcoreFragment.resolve("//Item/@bogus.0", in: roots) == nil)
        #expect(EcoreFragment.resolve("//Item/@details", in: roots) == nil)
        #expect(EcoreFragment.resolve("//Item/%none%", in: roots) == nil)
        #expect(EcoreFragment.resolve("//Item/%none%.x", in: roots) == nil)
        #expect(EcoreFragment.resolve("//Item/%", in: roots) == nil)
        #expect(EcoreFragment.child(of: .eEnum(shop.kind), segment: "") == nil)
    }

    @Test("a suffix that is not a number is part of the name")
    func nonNumericSuffix() {
        let dotted = EClass(name: "a.b")
        let package = EPackage(name: "p", eClassifiers: [dotted])
        #expect(EcoreFragment.resolve("//a.b", in: [package])?.id == dotted.id)
    }

    @Test("every element of the hand-built metamodel resolves from its own fragment")
    func roundTrip() throws {
        let package = shop.package
        let fragments = EcoreFragment.fragments(in: package)
        let elements = MetamodelFixtures.elements(of: package)
        #expect(elements.count == fragments.count)
        for element in elements {
            let fragment = try #require(fragments[element.id])
            #expect(EcoreFragment.resolve(fragment, in: [package])?.id == element.id)
        }
    }

    // MARK: Fixtures

    @Test("every element of every fixture round-trips through its fragment")
    func fixtureRoundTrip() async throws {
        let packages = try await MetamodelFixtures.fixturePackages()
        #expect(packages.count >= 10)
        #expect(packages.contains { $0.name == "library-full.ecore" })
        #expect(packages.contains { $0.name == "annotated.ecore" })
        for (name, package) in packages {
            let fragments = EcoreFragment.fragments(in: package)
            let elements = MetamodelFixtures.elements(of: package)
            #expect(elements.count == fragments.count, "\(name)")
            #expect(Set(fragments.values).count == fragments.count, "\(name): fragments are unique")
            for element in elements {
                let fragment = try #require(fragments[element.id], "\(name)")
                let resolved = EcoreFragment.resolve(fragment, in: [package])
                #expect(resolved?.id == element.id, "\(name) \(fragment)")
            }
        }
    }

    @Test("fragments agree with the paths of the metamodel writer for every fixture")
    func agreesWithWriter() async throws {
        var compared = 0
        for (name, package) in try await MetamodelFixtures.fixturePackages() {
            let fragments = EcoreFragment.fragments(in: package)
            for (identifier, path) in Self.writerPaths(of: package, prefix: "//") {
                #expect(fragments[identifier] == path, "\(name) \(path)")
                compared += 1
            }
        }
        #expect(compared > 100)
    }

    @Test("the references that the writer produces resolve to the referenced elements")
    func writtenReferencesResolve() async throws {
        let package = try await FidelityFixtures.package("library-full.ecore")
        let text = XMISerializer().serialize(package)
        var checked = 0
        for match in text.matches(of: /(?:eType|eSuperTypes|eOpposite|eExceptions)="([^"]*)"/) {
            for reference in match.1.split(separator: " ") where reference.hasPrefix("#//") {
                #expect(EcoreFragment.resolve(String(reference), in: [package]) != nil, "\(reference)")
                checked += 1
            }
        }
        #expect(checked > 20)
    }

    /// The paths that the metamodel writer assigns to the elements of a package.
    ///
    /// Mirrors the rules of the writer for metamodels whose sibling names are unique.
    private static func writerPaths(of package: EPackage, prefix: String) -> [EUUID: String] {
        var paths: [EUUID: String] = [:]
        for classifier in package.eClassifiers {
            let path = prefix + classifier.name
            paths[classifier.id] = path
            if let eClass = classifier as? EClass {
                for feature in eClass.eStructuralFeatures { paths[feature.id] = path + "/" + feature.name }
                for operation in eClass.eOperations {
                    let operationPath = path + "/" + operation.name
                    paths[operation.id] = operationPath
                    for parameter in operation.eParameters {
                        paths[parameter.id] = operationPath + "/" + parameter.name
                    }
                }
            } else if let eEnum = classifier as? EEnum {
                for literal in eEnum.literals { paths[literal.id] = path + "/" + literal.name }
            }
        }
        for subpackage in package.eSubpackages {
            paths[subpackage.id] = prefix + subpackage.name
            paths.merge(writerPaths(of: subpackage, prefix: prefix + subpackage.name + "/")) { first, _ in first }
        }
        return paths
    }
}
