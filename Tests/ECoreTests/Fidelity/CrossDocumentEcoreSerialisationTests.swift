//
// CrossDocumentEcoreSerialisationTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

private let wrapped = XMISerializationOptions(lineWidth: XMISerializationOptions.emfLineWidth)

@Suite("Cross-Document Ecore Serialisation Tests")
struct CrossDocumentEcoreSerialisationTests {
    private func fixtureText(_ name: String) throws -> String {
        try String(contentsOf: try FidelityFixtures.url(name), encoding: .utf8)
    }

    @Test("the shared document round-trips byte for byte")
    func sharedRoundTrip() async throws {
        let package = try await FidelityFixtures.package("shared.ecore")
        #expect(XMISerializer(options: wrapped).serialize(package) == (try fixtureText("shared.ecore")))
    }

    @Test("the consumer document round-trips byte for byte, with references into the shared document")
    func consumerRoundTrip() async throws {
        let package = try await FidelityFixtures.package("consumer.ecore")
        #expect(XMISerializer(options: wrapped).serialize(package) == (try fixtureText("consumer.ecore")))
    }

    @Test("references into another document are written as relative URIs with kind qualifiers")
    func qualifiedReferences() async throws {
        let package = try await FidelityFixtures.package("consumer.ecore")
        let text = XMISerializer().serialize(package)
        #expect(text.contains("eSuperTypes=\"shared.ecore#//Audited\""))
        #expect(text.contains("eType=\"ecore:EEnum shared.ecore#//Colour\""))
        #expect(text.contains("eType=\"ecore:EDataType shared.ecore#//Identifier\""))
        #expect(text.contains("eType=\"ecore:EClass shared.ecore#//inner/Stamp\""))
        #expect(text.contains("eType=\"#//Widget\""))
    }

    @Test("without a line width every attribute stays on one line")
    func unwrappedByDefault() async throws {
        let text = XMISerializer().serialize(try await FidelityFixtures.package("shared.ecore"))
        let root = try #require(text.split(separator: "\n").dropFirst().first)
        #expect(root.hasSuffix("nsPrefix=\"shared\">"))
        #expect(root.count > 200)
    }

    @Test("references are written relative to the location of the target document")
    func relativeToTarget() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let models = directory.appendingPathComponent("models")
        let output = directory.appendingPathComponent("out/deeper")
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["shared.ecore", "consumer.ecore"] {
            try FileManager.default.copyItem(
                at: try FidelityFixtures.url(name), to: models.appendingPathComponent(name))
        }
        let consumer = try await EPackage(url: models.appendingPathComponent("consumer.ecore"))
        let target = output.appendingPathComponent("moved.ecore")
        try XMISerializer().serialize(consumer, to: target)
        let written = try String(contentsOf: target, encoding: .utf8)
        #expect(written.contains("eSuperTypes=\"../../models/shared.ecore#//Audited\""))
        #expect(written.contains("eType=\"ecore:EEnum ../../models/shared.ecore#//Colour\""))
        let reloaded = try await EPackage(url: target)
        let widget = try #require(reloaded.getEClass("Widget"))
        #expect(widget.eSuperTypes.first?.name == "Audited")
        #expect(widget.eAttributes.first { $0.name == "colour" }?.eType is EEnum)
        #expect(widget.eAttributes.first { $0.name == "colour" }?.eType.name == "Colour")
        let text = XMISerializer().serialize(consumer, relativeTo: target)
        #expect(text == written)
    }

    @Test("a package that was built in code names foreign classifiers locally")
    func builtInCode() {
        let foreign = EClass(name: "Foreign")
        let holder = EClass(
            name: "Holder", eSuperTypes: [foreign],
            eStructuralFeatures: [EReference(name: "r", eType: foreign)])
        let package = EPackage(name: "p", nsURI: "http://p", nsPrefix: "p", eClassifiers: [holder])
        let text = XMISerializer().serialize(package)
        #expect(package.origin == nil)
        #expect(text.contains("eSuperTypes=\"#//Foreign\""))
        #expect(text.contains("eType=\"#//Foreign\""))
    }

    @Test("long attribute lists continue on indented lines")
    func attributeWrapping() {
        let longName = String(repeating: "n", count: 60)
        let attribute = EAttribute(
            name: longName, eType: EcorePackage.dataType(.eString)!, lowerBound: 1, upperBound: -1)
        let package = EPackage(
            name: "p", nsURI: "http://p", nsPrefix: "p",
            eClassifiers: [EClass(name: "Holder", eStructuralFeatures: [attribute])])
        let text = XMISerializer(options: wrapped).serialize(package)
        let expected = [
            "    <eStructuralFeatures xsi:type=\"ecore:EAttribute\" name=\"\(longName)\"",
            "        lowerBound=\"1\" upperBound=\"-1\""
                + " eType=\"ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString\"/>",
        ].joined(separator: "\n")
        #expect(text.contains(expected))
    }

    @Test("origin records the document and the external classifiers by identifier")
    func origin() async throws {
        let package = try await FidelityFixtures.package("consumer.ecore")
        let origin = try #require(package.origin)
        #expect(origin.documentURI.hasSuffix("consumer.ecore"))
        let widget = try #require(package.getEClass("Widget"))
        let audited = try #require(widget.eSuperTypes.first)
        let proxy = try #require(origin.externalReferences[audited.id])
        #expect(proxy.uri.hasSuffix("shared.ecore"))
        #expect(proxy.fragment == "//Audited")
        #expect(origin == EPackageOrigin(documentURI: origin.documentURI, externalReferences: origin.externalReferences))
    }
}
