//
// ModelIOMetamodelDetectionTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests that a metamodel is recognised by its contents whatever the extension of its file.
@Suite("Metamodel detection by contents")
struct ModelIOMetamodelDetectionTests {
    /// A metamodel with one class that has one attribute.
    private static func library() -> EPackage {
        let title = EAttribute(name: "title", eType: EDataType(name: "EString"))
        var book = EClass(name: "Book")
        book.eStructuralFeatures = [title]
        return EPackage(
            name: "library", nsURI: "http://example.org/library", nsPrefix: "lib", eClassifiers: [book])
    }

    /// A fresh temporary directory, removed by the caller.
    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelIOMetamodelDetectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("a package saved as .xmi loads back as an equal package", arguments: ["xmi", "ecore"])
    func packageRoundTrip(fileExtension: String) async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let package = Self.library()
        let resource = await ResourceSet().createResource(uri: "memory:/library.ecore")
        await resource.registerNativePackage(package)
        let url = directory.appendingPathComponent("library").appendingPathExtension(fileExtension)
        var diagnostics = ConversionDiagnostics()
        try await ModelIO.save(resource, to: url, diagnostics: &diagnostics)

        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(url: url, resourceSet: resourceSet)
        #expect(loaded.format == .ecore)
        #expect(loaded.packages.map(\.name) == [package.name])
        let roots = await loaded.resource.getRootObjects()
        let reloaded = try #require(roots.first as? EPackage)
        #expect(roots.count == 1)
        #expect(await resourceSet.getMetamodel(uri: package.nsURI)?.name == package.name)
        let serialiser = XMISerializer()
        #expect(serialiser.serialize([reloaded], relativeTo: nil) == serialiser.serialize([package], relativeTo: nil))
    }

    @Test("a package document read from bytes is detected as Ecore")
    func packageFromBytes() async throws {
        let text = XMISerializer().serialize([Self.library()], relativeTo: nil)
        let loaded = try await ModelIO.load(
            data: Data(text.utf8), uri: "memory:/library.xmi", resourceSet: ResourceSet())
        #expect(loaded.format == .ecore)
        #expect(loaded.packages.map(\.name) == ["library"])
    }

    @Test("the registry chooses the Ecore handler for a package in an .xmi file")
    func registryRefinesXMI() async throws {
        let registry = ModelFormatRegistry()
        let package = Data(XMISerializer().serialize([Self.library()], relativeTo: nil).utf8)
        let instance = Data(#"<p:Thing xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:p="urn:p"/>"#.utf8)
        let xmi = URL(fileURLWithPath: "model.xmi")
        let ecore = URL(fileURLWithPath: "model.ecore")
        #expect(await registry.handler(for: xmi, contents: package)?.format == .ecore)
        #expect(await registry.handler(for: xmi, contents: instance)?.format == .xmi)
        #expect(await registry.handler(for: ecore, contents: instance)?.format == .ecore)
    }

    @Test("an explicit XMI format still reads a package document as model objects")
    func explicitFormatIsKept() async throws {
        let text = XMISerializer().serialize([Self.library()], relativeTo: nil)
        let loaded = try await ModelIO.load(
            data: Data(text.utf8), uri: "memory:/library.xmi", format: .xmi, resourceSet: ResourceSet())
        #expect(loaded.format == .xmi)
        #expect(loaded.packages.isEmpty)
    }
}
