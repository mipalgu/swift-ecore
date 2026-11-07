//
// EmfaticXcoreFormatHandlerTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that Emfatic and Xcore metamodels are recognised, read and written through
/// ``ModelIO`` and the ``ModelFormatRegistry``.
@Suite("Emfatic and Xcore through the format registry")
struct EmfaticXcoreFormatHandlerTests {
    /// The start of a Windows enhanced metafile, which shares the `.emf` extension with Emfatic.
    ///
    /// The header record has type 1 and a size of 108 bytes, and carries the signature
    /// ` EMF` at offset 40. The text that follows must not make the document look like Emfatic.
    static let metafile: Data = {
        var bytes: [UInt8] = [0x01, 0x00, 0x00, 0x00, 0x6C, 0x00, 0x00, 0x00]
        bytes += [UInt8](repeating: 0, count: 32)
        bytes += Array(" EMF".utf8)
        bytes += [0x00, 0x00, 0x01, 0x00]
        bytes += Array("package shop;\n".utf8)
        return Data(bytes)
    }()

    /// A model instance of the library metamodel of the fixtures.
    static let libraryModel = """
        <?xml version="1.0" encoding="UTF-8"?>
        <lib:Book xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
        xmlns:lib="http://example.org/library" title="Emma" isbn="978-0"/>
        """

    /// A new temporary directory, which the caller removes.
    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmfaticXcoreFormatHandlerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Formats

    @Test("Emfatic and Xcore are named by their file extensions and names")
    func formatsAreNamed() {
        #expect(ModelFormat.emfatic.fileExtension == "emf")
        #expect(ModelFormat.emfatic.fileExtension == EmfaticLanguage.fileExtension)
        #expect(ModelFormat.xcore.fileExtension == XcoreLanguage.fileExtension)
        #expect(ModelFormat.emfatic.description == "Emfatic")
        #expect(ModelFormat.xcore.description == "Xcore")
        #expect(ModelFormat(fileExtension: "EMF") == .emfatic)
        #expect(ModelFormat(fileExtension: "emfatic") == .emfatic)
        #expect(ModelFormat(fileExtension: "Xcore") == .xcore)
        #expect(ModelFormat.detect(url: URL(fileURLWithPath: "shop.emf")) == .emfatic)
        #expect(ModelFormat.detect(url: URL(fileURLWithPath: "shop.emfatic")) == nil)
        #expect(ModelFormat.detect(url: URL(fileURLWithPath: "shop.xcore")) == .xcore)
    }

    @Test("Emfatic documents are recognised by their package declaration", arguments: [
        EmfaticFixtures.library,
        "package shop;\nclass Item {}",
        "// A shop\n/* of things */\npackage org.example.shop;\nclass Item {}",
        "@namespace(uri=\"http://example.org/shop\", prefix=\"shop\")\npackage shop;\n@Ecore(x=\"y\") class Item {}",
        "\u{FEFF}@Ecore(name=\"x\") @GenModel(documentation=\"(nested) text\")\npackage shop;\nimport \"other.ecore\";",
    ])
    func emfaticIsRecognised(text: String) async {
        let data = Data(text.utf8)
        #expect(ModelFormat.detect(data: data) == .emfatic)
        #expect(EmfaticSyntax.looksLikeEmfatic(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text))
        #expect(await ModelFormatRegistry().handler(recognising: data)?.format == .emfatic)
    }

    @Test("Xcore documents are recognised by their package declaration", arguments: [
        XcoreFixtures.library,
        "package shop\nclass Item {}",
        "package org.example.shop\n\nclass Item {}",
        "// A shop\n@Ecore(nsURI=\"http://example.org/shop\")\npackage shop\nimport org.example.Other",
        "package shop @GenModel(documentation=\"x\") class Item {}",
    ])
    func xcoreIsRecognised(text: String) async {
        let data = Data(text.utf8)
        #expect(ModelFormat.detect(data: data) == .xcore)
        #expect(XcoreSyntax.looksLikeXcore(text))
        #expect(await ModelFormatRegistry().handler(recognising: data)?.format == .xcore)
    }

    @Test("other text is neither Emfatic nor Xcore", arguments: [
        "package Shop { class Item {} }", "package shop {", "package;", "package shop =", "class Item {}",
        "plain text", "", "package shop.;", "@namespace(uri=\"x\"", "package shop;", "package shop",
        "package shop;\nnotAKeyword", "package shop ~class", "package shop;\n~class Item {}",
    ])
    func otherTextIsNotRecognised(text: String) {
        #expect(!EmfaticSyntax.looksLikeEmfatic(text))
        #expect(!XcoreSyntax.looksLikeXcore(text))
        #expect(![ModelFormat.emfatic, .xcore].contains(ModelFormat.detect(data: Data(text.utf8))))
    }

    @Test("KM3 documents are still recognised as KM3")
    func km3StaysKM3() {
        #expect(ModelFormat.detect(data: Data("package Shop {\n class Item {}\n}".utf8)) == .km3)
    }

    @Test("a Windows metafile is not claimed as Emfatic")
    func metafileIsNotClaimed() async throws {
        #expect(ModelFormat.detect(data: Self.metafile) == nil)
        #expect(await ModelFormatRegistry().handler(recognising: Self.metafile) == nil)
        let control = Data([0x07]) + Data("package shop;".utf8)
        #expect(ModelFormat.detect(data: control) == nil)
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("picture.emf")
        try Self.metafile.write(to: url)
        await #expect(throws: ModelFormatError.undetectableFormat(URIReference.canonicalise(url.absoluteString))) {
            try await ModelIO.load(url: url, resourceSet: ResourceSet())
        }
        await #expect(throws: ModelFormatError.self) {
            try await ModelIO.registerMetamodels(at: [url], in: ResourceSet())
        }
    }

    @Test("the Emfatic and Xcore handlers are writable metamodel handlers of specific priority")
    func handlersAreDescribed() async throws {
        let registry = ModelFormatRegistry()
        for format in [ModelFormat.emfatic, .xcore] {
            let handler = try #require(await registry.handler(for: format))
            #expect(handler.role == .metamodel)
            #expect(handler.priority == .specific)
            #expect(handler is any WritableModelFormatHandler)
            #expect(await registry.handler(forFileExtension: format.fileExtension)?.format == format)
        }
    }

    // MARK: - Reading and Writing

    @Test("an Emfatic document loads through ModelIO as EmfaticReader reads it")
    func emfaticLoads() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.emf")
        try EmfaticFixtures.library.write(to: url, atomically: true, encoding: .utf8)
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(url: url, resourceSet: resourceSet)
        let direct = EmfaticReader.parse(EmfaticFixtures.library, sourceName: URIReference.canonicalise(url.absoluteString))
        #expect(loaded.format == .emfatic)
        #expect(loaded.formatIdentifier == "emf")
        #expect(loaded.packages.map(\.name) == direct.packages.map(\.name))
        #expect(await loaded.resource.loadDiagnostics == direct.diagnostics)
        #expect(await resourceSet.getMetamodel(uri: "http://example.org/library")?.name == "library")
        #expect(XMISerializer(options: .emf).serialize(loaded.packages)
            == XMISerializer(options: .emf).serialize(direct.packages))
    }

    @Test("an Xcore document loads through ModelIO as XcoreReader reads it")
    func xcoreLoads() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.xcore")
        try XcoreFixtures.library.write(to: url, atomically: true, encoding: .utf8)
        let loaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        let direct = XcoreReader.parse(XcoreFixtures.library, sourceName: URIReference.canonicalise(url.absoluteString))
        #expect(loaded.format == .xcore)
        #expect(loaded.packages.map(\.name) == direct.packages.map(\.name))
        #expect(await loaded.resource.loadDiagnostics == direct.diagnostics)
        #expect(XMISerializer(options: .emf).serialize(loaded.packages)
            == XMISerializer(options: .emf).serialize(direct.packages))
    }

    @Test("documents without a known extension are recognised by their contents")
    func documentsAreRecognisedFromBytes() async throws {
        let emfatic = try await ModelIO.load(
            data: Data(EmfaticFixtures.library.utf8), uri: "memory:/library", resourceSet: ResourceSet())
        #expect(emfatic.format == .emfatic)
        let xcore = try await ModelIO.load(
            data: Data(XcoreFixtures.library.utf8), uri: "memory:/library", resourceSet: ResourceSet())
        #expect(xcore.format == .xcore)
    }

    @Test("a model is read with the classes of an Emfatic or Xcore metamodel", arguments: [
        ("library.emf", EmfaticFixtures.library), ("library.xcore", XcoreFixtures.library),
    ])
    func modelsUseTextMetamodels(name: String, text: String) async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let metamodel = directory.appendingPathComponent(name)
        try text.write(to: metamodel, atomically: true, encoding: .utf8)
        let model = directory.appendingPathComponent("book.xmi")
        try Self.libraryModel.write(to: model, atomically: true, encoding: .utf8)
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(url: model, resourceSet: resourceSet, metamodels: [metamodel])
        let book = try #require(await loaded.resource.getRootObjects().first)
        let registered = try #require(await resourceSet.getMetamodel(uri: "http://example.org/library"))
        #expect(book.eClass.name == "Book")
        #expect(book.eClass.id == registered.getEClass("Book")?.id)
        #expect(loaded.diagnostics.warnings.isEmpty)
    }

    @Test("a metamodel is written as Emfatic and Xcore as their writers write it")
    func metamodelsAreWritten() async throws {
        let loaded = try await ModelIO.load(
            data: Data(EmfaticFixtures.library.utf8), uri: "memory:/library.emf", resourceSet: ResourceSet())
        var diagnostics = ConversionDiagnostics()
        let emfatic = try await ModelIO.serialise(loaded.resource, format: .emfatic, diagnostics: &diagnostics)
        #expect(emfatic == EmfaticWriter.write(loaded.packages).text)
        let xcore = try await ModelIO.serialise(loaded.resource, format: .xcore, diagnostics: &diagnostics)
        #expect(xcore == XcoreWriter.write(loaded.packages).text)
        let expected = (EmfaticWriter.write(loaded.packages).diagnostics + XcoreWriter.write(loaded.packages).diagnostics)
        #expect(diagnostics.warnings.count == expected.count)
    }

    @Test("a metamodel saved as Emfatic or Xcore is read back with the same classifiers", arguments: ["emf", "xcore"])
    func metamodelsRoundTrip(fileExtension: String) async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = try await ModelIO.load(
            data: Data(EmfaticFixtures.library.utf8), uri: "memory:/library.emf", resourceSet: ResourceSet())
        let url = directory.appendingPathComponent("copy.\(fileExtension)")
        try await ModelIO.save(loaded.resource, to: url)
        let reloaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        let names = { (packages: [EPackage]) in packages.flatMap { $0.eClassifiers.map(\.name) }.sorted() }
        #expect(names(reloaded.packages) == names(loaded.packages))
    }

    @Test("model instances are not written as Emfatic or Xcore", arguments: [ModelFormat.emfatic, .xcore])
    func modelInstancesAreRefused(format: ModelFormat) async throws {
        let resourceSet = ResourceSet()
        _ = try await ModelIO.load(
            data: Data(EmfaticFixtures.library.utf8), uri: "memory:/library.emf", resourceSet: resourceSet)
        let model = try await ModelIO.load(
            data: Data(Self.libraryModel.utf8), uri: "memory:/book.xmi", resourceSet: resourceSet)
        var diagnostics = ConversionDiagnostics()
        await #expect(throws: ModelIOError.self) {
            try await ModelIO.serialise(model.resource, format: format, diagnostics: &diagnostics)
        }
    }

    // MARK: - Text Encodings

    @Test("a document that is not UTF-8 is read as ISO-8859-1 with a warning, unless an encoding is given")
    func encodingsAreApplied() async throws {
        let text = "@GenModel(documentation=\"Caf\u{E9}\")\n@namespace(uri=\"http://example.org/cafe\", prefix=\"cafe\")\npackage cafe;\nclass Table {}\n"
        let latin1 = try #require(text.data(using: .isoLatin1))
        let detected = try await ModelIO.load(data: latin1, uri: "memory:/cafe.emf", resourceSet: ResourceSet())
        let detectedDiagnostics = await detected.resource.loadDiagnostics
        #expect(detectedDiagnostics.first?.severity == .warning)
        #expect(detected.packages.first?.eAnnotations.first?.details["documentation"] == "Caf\u{E9}")
        let explicit = try await ModelIO.load(
            data: latin1, uri: "memory:/cafe.emf", format: .emfatic, resourceSet: ResourceSet(),
            options: ModelIO.LoadOptions(textEncoding: .isoLatin1))
        #expect(await explicit.resource.loadDiagnostics.isEmpty)
        #expect(explicit.packages.first?.eAnnotations.first?.details["documentation"] == "Caf\u{E9}")
        await #expect(throws: TextDecodingError.self) {
            try await ModelIO.load(
                data: latin1, uri: "memory:/cafe.xcore", format: .xcore, resourceSet: ResourceSet(),
                options: ModelIO.LoadOptions(textEncoding: .utf8))
        }
    }
}
