//
// AnnotationDetailOrderTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import OrderedCollections
import Testing

@testable import ECore

@Suite("Annotation detail order, end to end")
struct AnnotationDetailOrderTests {
    private static let keys = ["zeta", "alpha", "mid", "beta", "omega", "gamma"]

    private static func annotation() -> EAnnotation {
        var details: OrderedDictionary<String, String> = [:]
        for (index, key) in keys.enumerated() { details[key] = "v\(index)" }
        return EAnnotation(source: "urn:order", orderedDetails: details)
    }

    private func entryKeys(_ value: (any EcoreValue)?) -> [String] {
        let entries = (value as? EcoreValueArray)?.values ?? []
        return entries.compactMap { ($0 as? EStringToStringMapEntry)?.key }
    }

    @Test("reflective reads list the entries in detail order")
    func reflectiveRead() throws {
        let annotation = Self.annotation()
        let feature = try #require(annotation.eClass.getStructuralFeature(name: "details"))
        #expect(entryKeys(annotation.eGet(feature)) == Self.keys)
        #expect(annotation.detailEntries.map(\.key) == Self.keys)
        #expect(annotation.details.keys.elements == Self.keys)
    }

    @Test("reflective writes keep the order of the entries given")
    func reflectiveWrite() throws {
        var annotation = EAnnotation(source: "urn:order", orderedDetails: [:])
        let feature = try #require(annotation.eClass.getStructuralFeature(name: "details"))
        let entries = Self.keys.map { EStringToStringMapEntry(key: $0, value: "x") }
        annotation.eSet(feature, EcoreValueArray(entries))
        #expect(annotation.details.keys.elements == Self.keys)
    }

    @Test("setting details one at a time appends in call order")
    func incremental() {
        var annotation = EAnnotation(source: "urn:order", orderedDetails: [:])
        for key in Self.keys { annotation.details[key] = "x" }
        #expect(annotation.details.keys.elements == Self.keys)
        annotation.details["zeta"] = "changed"
        #expect(annotation.details.keys.elements == Self.keys)
    }

    @Test("native serialisation writes details in order and a reload keeps it")
    func nativeRoundTrip() async throws {
        let eClass = EClass(name: "Ordered", eAnnotations: [Self.annotation()])
        let package = EPackage(
            name: "ord", nsURI: "http://example.org/ord", nsPrefix: "ord", eClassifiers: [eClass])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ordered-\(UUID().uuidString).ecore")
        defer { try? FileManager.default.removeItem(at: url) }
        try XMISerializer().serialize(package, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        let positions = Self.keys.compactMap { text.range(of: "key=\"\($0)\"")?.lowerBound }
        #expect(positions.count == Self.keys.count)
        #expect(positions == positions.sorted())
        let reloaded = try await EPackage(url: url)
        let found = try #require(reloaded.getEClass("Ordered")?.eAnnotations.first)
        #expect(found.details.keys.elements == Self.keys)
    }

    @Test("dynamic loading keeps the order of details of a parsed document")
    func dynamicLoad() async throws {
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
                xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="o" nsURI="urn:o" nsPrefix="o">
              <eAnnotations source="urn:order">
            \(Self.keys.map { "    <details key=\"\($0)\" value=\"1\"/>" }.joined(separator: "\n"))
              </eAnnotations>
            </ecore:EPackage>
            """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dynamic-\(UUID().uuidString).ecore")
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let native = try await EPackage(url: url)
        #expect(native.eAnnotations.first?.details.keys.elements == Self.keys)
        let resource = try await ResourceSet().loadXMIResource(uri: url.absoluteString)
        let root = try #require(await resource.getRootObjects().first as? DynamicEObject)
        let annotationID = try #require((root.eGet("eAnnotations") as? [EUUID])?.first)
        let annotation = try #require(await resource.resolve(annotationID) as? DynamicEObject)
        let entryIDs = try #require(annotation.eGet("details") as? [EUUID])
        var found: [String] = []
        for id in entryIDs {
            if let entry = await resource.resolve(id) as? DynamicEObject, let key = entry.eGet("key") as? String {
                found.append(key)
            }
        }
        #expect(found == Self.keys)
    }
}
