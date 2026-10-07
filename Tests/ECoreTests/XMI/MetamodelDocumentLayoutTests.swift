//
// MetamodelDocumentLayoutTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Metamodel document layout")
struct MetamodelDocumentLayoutTests {
    private static let body = """
          <eClassifiers xsi:type="ecore:EClass" name="Node">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="size" eType="ecore:EDataType http://www.eclipse.org/emf/2003/XMLType#//Int"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="peer" eType="ecore:EClass peer.ecore#//Peer"
                eOpposite="peer.ecore#//Peer/node"/>
          </eClassifiers>
        </ecore:EPackage>

        """

    private static let standard =
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="demo" nsURI="http://example.org/demo" nsPrefix="demo">

        """ + body

    private static let versionFirst =
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0"
            xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="demo"
            nsURI="http://example.org/demo" nsPrefix="demo">

        """ + body

    private static func roundTrip(_ text: String, layout: XMIRootLayout) async throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("demo.ecore")
        try text.write(to: url, atomically: testWritesAtomically, encoding: .utf8)
        let resourceSet = ResourceSet()
        let resource = try await resourceSet.loadEcoreResource(
            uri: URIReference.canonicalise(url.absoluteString))
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        let options = XMISerializationOptions(
            lineWidth: XMISerializationOptions.emfLineWidth, rootLayout: layout)
        return XMISerializer(options: options).serialize(package, relativeTo: url)
    }

    @Test("a metamodel in the current root layout is written back unchanged")
    func standardRoundTrip() async throws {
        #expect(try await Self.roundTrip(Self.standard, layout: .standard) == Self.standard)
    }

    @Test("a metamodel in the version-first root layout is written back unchanged")
    func versionFirstRoundTrip() async throws {
        #expect(try await Self.roundTrip(Self.versionFirst, layout: .versionFirst) == Self.versionFirst)
    }

    @Test("a type in a document that is not available is written back as it was read")
    func unresolvedTypeIsKept() async throws {
        let written = try await Self.roundTrip(Self.standard, layout: .standard)
        #expect(written.contains("eType=\"ecore:EDataType http://www.eclipse.org/emf/2003/XMLType#//Int\""))
    }

    @Test("an opposite in another document is written back")
    func externalOppositeIsKept() async throws {
        let written = try await Self.roundTrip(Self.standard, layout: .standard)
        #expect(written.contains("eOpposite=\"peer.ecore#//Peer/node\""))
    }

    @Test("the unwrapped layout keeps every attribute on one line")
    func unwrapped() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("demo.ecore")
        try Self.standard.write(to: url, atomically: testWritesAtomically, encoding: .utf8)
        let resourceSet = ResourceSet()
        let resource = try await resourceSet.loadEcoreResource(
            uri: URIReference.canonicalise(url.absoluteString))
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        let text = XMISerializer().serialize(package, relativeTo: url)
        #expect(text.components(separatedBy: "\n").filter { $0.contains("<ecore:EPackage") }.count == 1)
        #expect(!text.contains("\n    xmlns:ecore"))
    }

    @Test("the wrapped preset equals the EMF preset with the EMF line width")
    func presets() {
        var expected = XMISerializationOptions.emf
        expected.lineWidth = XMISerializationOptions.emfLineWidth
        #expect(XMISerializationOptions.emfWrapped == expected)
        #expect(XMISerializationOptions.emf.lineWidth == nil)
        #expect(XMISerializationOptions.emfWrapped.rootLayout == .standard)
    }
}
