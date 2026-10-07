//
// EcoreRoundTripFidelityTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Describes a native metamodel as lines of text that capture every loaded property.
///
/// Identifiers differ between loads, so elements are described by their names and
/// their paths of names.
struct MetamodelDescription {
    private var paths: [EUUID: String] = [:]

    init(_ package: EPackage) {
        index(package, prefix: "")
    }

    private mutating func index(_ package: EPackage, prefix: String) {
        for classifier in package.eClassifiers {
            paths[classifier.id] = prefix + classifier.name
            guard let eClass = classifier as? EClass else { continue }
            for feature in eClass.eStructuralFeatures {
                paths[feature.id] = prefix + eClass.name + "." + feature.name
            }
        }
        for subpackage in package.eSubpackages {
            index(subpackage, prefix: prefix + subpackage.name + "/")
        }
    }

    private func describeType(_ classifier: (any EClassifier)?) -> String {
        guard let classifier else { return "none" }
        if EcorePackage.isMetaClass(classifier) { return "ecore.\(classifier.name)" }
        if EcorePackage.dataType(EcoreDataType(rawValue: classifier.name) ?? .eString)?.id == classifier.id {
            return "ecore.\(classifier.name)"
        }
        return "\(type(of: classifier)) \(paths[classifier.id] ?? "?\(classifier.name)")"
    }

    func lines(_ package: EPackage, indent: String = "") -> [String] {
        var result = ["\(indent)package \(package.name) \(package.nsURI) \(package.nsPrefix)"]
        let inner = indent + "  "
        for classifier in package.eClassifiers {
            switch classifier {
            case let eClass as EClass: result += lines(eClass, indent: inner)
            case let eEnum as EEnum:
                result.append("\(inner)enum \(eEnum.name)")
                for literal in eEnum.literals {
                    result.append("\(inner)  literal \(literal.name) \(literal.value) \(literal.literal ?? "-")")
                }
            case let dataType as EDataType:
                result.append(
                    "\(inner)datatype \(dataType.name) \(dataType.instanceClassName ?? "-") \(dataType.serialisable)")
            default: break
            }
        }
        for subpackage in package.eSubpackages { result += lines(subpackage, indent: inner) }
        return result
    }

    private func lines(_ eClass: EClass, indent: String) -> [String] {
        var result = [
            "\(indent)class \(eClass.name) abstract=\(eClass.isAbstract) interface=\(eClass.isInterface)"
                + " instance=\(eClass.instanceClassName ?? "-")"
                + " supers=\(eClass.eSuperTypes.map { paths[$0.id] ?? "?" })"
        ]
        let inner = indent + "  "
        for operation in eClass.eOperations {
            result.append(
                "\(inner)operation \(operation.name) type=\(describeType(operation.eType))"
                    + " bounds=\(operation.lowerBound)..\(operation.upperBound)"
                    + " ordered=\(operation.ordered) unique=\(operation.unique)"
                    + " exceptions=\(operation.eExceptions.map { paths[$0.id] ?? "?" })")
            for parameter in operation.eParameters {
                result.append(
                    "\(inner)  parameter \(parameter.name) type=\(describeType(parameter.eType))"
                        + " bounds=\(parameter.lowerBound)..\(parameter.upperBound)"
                        + " ordered=\(parameter.ordered) unique=\(parameter.unique)")
            }
        }
        for feature in eClass.eStructuralFeatures {
            if let attribute = feature as? EAttribute {
                result.append(
                    "\(inner)attribute \(attribute.name) type=\(describeType(attribute.eType))"
                        + " bounds=\(attribute.lowerBound)..\(attribute.upperBound)"
                        + " id=\(attribute.isID) ordered=\(attribute.ordered) unique=\(attribute.unique)"
                        + " changeable=\(attribute.changeable) volatile=\(attribute.volatile)"
                        + " transient=\(attribute.transient) unsettable=\(attribute.unsettable)"
                        + " derived=\(attribute.derived) default=\(attribute.defaultValueLiteral ?? "-")")
            } else if let reference = feature as? EReference {
                result.append(
                    "\(inner)reference \(reference.name) type=\(describeType(reference.eType))"
                        + " bounds=\(reference.lowerBound)..\(reference.upperBound)"
                        + " containment=\(reference.containment) container=\(reference.container)"
                        + " opposite=\(reference.opposite.flatMap { paths[$0] } ?? "-")"
                        + " ordered=\(reference.ordered) unique=\(reference.unique)"
                        + " changeable=\(reference.changeable) volatile=\(reference.volatile)"
                        + " transient=\(reference.transient) unsettable=\(reference.unsettable)"
                        + " derived=\(reference.derived) proxies=\(reference.resolveProxies)")
            }
        }
        return result
    }
}

@Suite("Ecore Round Trip Fidelity Tests")
struct EcoreRoundTripFidelityTests {
    private func describe(_ package: EPackage) -> [String] {
        MetamodelDescription(package).lines(package)
    }

    private func roundTrip(_ package: EPackage) async throws -> (text: String, reloaded: EPackage) {
        let text = XMISerializer().serialize(package)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("round-trip.ecore")
        try text.write(to: url, atomically: testWritesAtomically, encoding: .utf8)
        return (text, try await EPackage(url: url))
    }

    @Test("the description of the loaded fixture covers every property")
    func descriptionIsComplete() async throws {
        let lines = describe(try await FidelityFixtures.package())
        #expect(lines.contains { $0.contains("class Book") && $0.contains("supers=[\"Named\", \"Lendable\"]") })
        #expect(lines.contains { $0.contains("attribute category type=EEnum BookCategory") })
        #expect(lines.contains { $0.contains("reference library") && $0.contains("container=true") })
        #expect(lines.contains { $0.contains("operation borrow") && $0.contains("exceptions=[\"LoanFailure\"]") })
        #expect(lines.contains { $0.contains("instance=java.util.Map$Entry") })
        #expect(lines.contains { $0.contains("package archive") })
    }

    @Test("a serialised and reloaded package is identical to the original")
    func nativeRoundTrip() async throws {
        let original = try await FidelityFixtures.package()
        let (_, reloaded) = try await roundTrip(original)
        let before = describe(original)
        let after = describe(reloaded)
        #expect(before.count == 51)
        #expect(after == before)
    }

    @Test("serialising a reloaded package gives the same text")
    func serialisationIsStable() async throws {
        let original = try await FidelityFixtures.package()
        let (text, reloaded) = try await roundTrip(original)
        #expect(XMISerializer().serialize(reloaded) == text)
    }

    @Test("the serialised document contains operations, parameters, and class instance names")
    func serialisedContent() async throws {
        let text = XMISerializer().serialize(try await FidelityFixtures.package())
        #expect(text.contains("instanceClassName=\"java.util.Map$Entry\""))
        #expect(text.contains("<eOperations name=\"borrow\" lowerBound=\"1\" eType=\"ecore:EDataType"))
        #expect(text.contains("eExceptions=\"#//LoanFailure\""))
        #expect(text.contains("<eParameters name=\"notes\" ordered=\"false\" unique=\"false\" upperBound=\"-1\""))
        #expect(text.contains("<eOperations name=\"giveBack\"/>"))
        #expect(text.contains("eSuperTypes=\"#//Named #//Lendable\""))
        #expect(text.contains("eType=\"#//catalogue/Shelf\""))
        #expect(text.contains("<eSubpackages name=\"archive\""))
    }

    @Test("a serialised package loads dynamically with the same structure")
    func dynamicReload() async throws {
        let original = try await FidelityFixtures.package()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("dynamic.ecore")
        try XMISerializer().serialize(original, to: url)
        let resource = try await XMIParser().parse(url)
        let classes = await resource.getAllInstancesOf(EcorePackage.metaClass(.eClass))
        #expect(classes.count == 9)
        #expect(await resource.getAllInstancesOf(EcorePackage.metaClass(.eOperation)).count == 3)
        let book = try #require(await FragmentNavigator(resource: resource).resolve("//Book") as? DynamicEObject)
        #expect((book.eGet("eSuperTypes") as? [EUUID])?.count == 2)
    }

    @Test("the reflective Ecore package serialises and reloads")
    func ecorePackageRoundTrip() async throws {
        let (_, reloaded) = try await roundTrip(EcorePackage.instance)
        #expect(reloaded.getEClass("EClass")?.eSuperTypes.map(\.name) == ["EClassifier"])
        #expect(reloaded.getEClass("EOperation")?.eSuperTypes.map(\.name) == ["ETypedElement"])
    }
}
