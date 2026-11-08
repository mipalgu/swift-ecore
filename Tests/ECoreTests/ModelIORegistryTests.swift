//
// ModelIORegistryTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests that ``ModelIO`` reads and writes registered formats through their handlers.
@Suite("Model loading and saving through registered formats")
struct ModelIORegistryTests {
    private static let shapesURI = "http://example.org/shapes"

    private static let sketch = """
        sketch package shapes http://example.org/shapes shp
        class Shape
        abstract class Figure
        warn mind the gap
        nonsense here
        """

    /// A registry with the built-in handlers and the sketch handler.
    private static func registry() async -> ModelFormatRegistry {
        let registry = ModelFormatRegistry()
        await registry.register(SketchFormatHandler())
        await registry.register(ReadOnlySketchFormatHandler())
        return registry
    }

    /// A fresh temporary directory, removed by the caller.
    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelIORegistryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func write(_ data: Data, named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private static func classNames(_ package: EPackage?) -> [String] {
        package?.eClassifiers.map(\.name) ?? []
    }

    // MARK: - Reading

    @Test("a registered text metamodel is loaded from a file by its extension")
    func loadsRegisteredFormatFromURL() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try Self.write(Data(Self.sketch.utf8), named: "shapes.sketch", in: directory)
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(url: url, resourceSet: resourceSet, registry: await Self.registry())
        #expect(loaded.formatIdentifier == SketchSyntax.identifier)
        #expect(loaded.format == .ecore)
        #expect(loaded.diagnostics.isEmpty)
        #expect(loaded.packages.map(\.name) == ["shapes"])
        #expect(Self.classNames(loaded.packages.first) == ["Shape", "Figure"])
        let roots = await loaded.resource.getRootObjects()
        #expect(roots.compactMap { ($0 as? EPackage)?.name } == ["shapes"])
        #expect(await resourceSet.getMetamodel(uri: Self.shapesURI)?.name == "shapes")
        #expect(await resourceSet.getResource(uri: url.absoluteString) === loaded.resource)
        let diagnostics = await loaded.resource.loadDiagnostics
        #expect(diagnostics.map(\.code) == [SketchSyntax.explicitWarning, SketchSyntax.unknownLine])
        #expect(diagnostics.map(\.severity) == [.warning, .error])
        #expect(diagnostics.first?.message == "mind the gap")
        #expect(diagnostics.first?.range?.start.line == 4)
        #expect(diagnostics.allSatisfy { $0.document == url.absoluteString })
    }

    @Test("a registered text metamodel is loaded from bytes by its content")
    func loadsRegisteredFormatFromData() async throws {
        let resourceSet = ResourceSet()
        let uri = "memory:/documents/shapes"
        let loaded = try await ModelIO.load(
            data: Data(Self.sketch.utf8), uri: uri, resourceSet: resourceSet, registry: await Self.registry())
        #expect(loaded.formatIdentifier == SketchSyntax.identifier)
        #expect(loaded.packages.map(\.name) == ["shapes"])
        #expect(loaded.resource.uri == uri)
        #expect(await resourceSet.getMetamodel(uri: Self.shapesURI) != nil)
    }

    @Test("a document with an unknown extension is recognised by its content")
    func unknownExtensionFallsBackToContent() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try Self.write(Data(Self.sketch.utf8), named: "shapes.txt", in: directory)
        let loaded = try await ModelIO.load(url: url, resourceSet: ResourceSet(), registry: await Self.registry())
        #expect(loaded.formatIdentifier == SketchSyntax.identifier)
    }

    @Test("a format registered with the shared registry is used by default")
    func sharedRegistryIsDefault() async throws {
        struct SharedSketchFormatHandler: ModelFormatHandler {
            var identifier: String { "sharedsketch" }
            var name: String { "Shared sketch" }
            var fileExtensions: [String] { ["sharedsketch"] }
            var role: ModelFormatRole { .metamodel }
            func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
                try await SketchFormatHandler().read(request)
            }
        }
        await ModelFormatRegistry.shared.register(SharedSketchFormatHandler())
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try Self.write(Data(Self.sketch.utf8), named: "shapes.sharedsketch", in: directory)
        let loaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        #expect(loaded.formatIdentifier == "sharedsketch")
        #expect(loaded.packages.map(\.name) == ["shapes"])
    }

    @Test("a document that is not UTF-8 is read as ISO-8859-1 with a warning")
    func latin1FallbackIsReported() async throws {
        let text = "sketch package shapes http://example.org/shapes shp\nclass Fa\u{E7}ade\n"
        let bytes = try #require(text.data(using: .isoLatin1))
        let loaded = try await ModelIO.load(
            data: bytes, uri: "memory:/latin1.sketch", resourceSet: ResourceSet(), registry: await Self.registry())
        #expect(Self.classNames(loaded.packages.first) == ["Fa\u{E7}ade"])
        let diagnostics = await loaded.resource.loadDiagnostics
        #expect(diagnostics.map(\.code) == [TextDecodingDiagnostic.decodedAsISOLatin1])
        #expect(diagnostics.first?.severity == .warning)
        #expect(diagnostics.first?.document == "memory:/latin1.sketch")
    }

    @Test("an explicit text encoding is used without a warning")
    func explicitEncodingIsUsed() async throws {
        let text = "sketch package shapes http://example.org/shapes shp\nclass Fa\u{E7}ade\n"
        let bytes = try #require(text.data(using: .isoLatin1))
        let loaded = try await ModelIO.load(
            data: bytes, uri: "memory:/latin1.sketch", resourceSet: ResourceSet(),
            options: ModelIO.LoadOptions(textEncoding: .isoLatin1), registry: await Self.registry())
        #expect(Self.classNames(loaded.packages.first) == ["Fa\u{E7}ade"])
        #expect(await loaded.resource.loadDiagnostics.isEmpty)
    }

    @Test("the text encoding of the Ecore load options applies to documents and to registered metamodels")
    func ecoreLoadOptionsEncoding() async throws {
        let text = "-- Fa\u{E7}ade\npackage Shapes {\n  class Square {}\n}\n"
        let bytes = try #require(text.data(using: .isoLatin1))
        let options = EcoreLoadOptions(textEncoding: .isoLatin1)
        #expect(EcoreLoadOptions().textEncoding == nil)
        let loaded = try await ModelIO.load(
            data: bytes, uri: "memory:/shapes.km3", format: .km3, resourceSet: ResourceSet(),
            options: ModelIO.LoadOptions(ecoreLoadOptions: options))
        #expect(await loaded.resource.loadDiagnostics.allSatisfy { $0.code != TextDecodingDiagnostic.decodedAsISOLatin1 })
        let detected = try await ModelIO.load(
            data: bytes, uri: "memory:/detected.km3", format: .km3, resourceSet: ResourceSet())
        #expect(await detected.resource.loadDiagnostics.contains { $0.code == TextDecodingDiagnostic.decodedAsISOLatin1 })

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("encoding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Shapes.km3")
        try bytes.write(to: url)
        let resourceSet = ResourceSet()
        let packages = try await ModelIO.registerMetamodels(at: [url], in: resourceSet, options: options)
        #expect(packages.map(\.name) == ["Shapes"])
        let resource = await resourceSet.getResource(uri: URIReference.canonicalise(url.absoluteString))
        #expect(await resource?.loadDiagnostics.allSatisfy { $0.code != TextDecodingDiagnostic.decodedAsISOLatin1 } == true)
        await #expect(throws: TextDecodingError.malformed(.utf8)) {
            try await ModelIO.registerMetamodels(
                at: [url], in: ResourceSet(), options: EcoreLoadOptions(textEncoding: .utf8))
        }
    }

    @Test("bytes that are not valid in an explicit text encoding are rejected")
    func malformedExplicitEncodingThrows() async throws {
        let bytes = Data("sketch package broken http://example.org/broken b\nclass ".utf8) + Data([0xFF, 0x0A])
        await #expect(throws: TextDecodingError.malformed(.utf8)) {
            try await ModelIO.load(
                data: bytes, uri: "memory:/broken.sketch", format: nil, resourceSet: ResourceSet(),
                options: ModelIO.LoadOptions(textEncoding: .utf8), registry: await Self.registry())
        }
    }

    @Test("a document that no handler recognises is reported as undetectable")
    func unrecognisedDocumentThrows() async throws {
        await #expect(throws: ModelFormatError.undetectableFormat("memory:/notes")) {
            try await ModelIO.load(
                data: Data("just some notes".utf8), uri: "memory:/notes", resourceSet: ResourceSet(),
                registry: await Self.registry())
        }
    }

    @Test("a format without a registered handler is reported as unsupported")
    func unregisteredFormatThrows() async throws {
        let registry = ModelFormatRegistry(handlers: [SketchFormatHandler()])
        await #expect(throws: ModelFormatError.unsupportedFormat("xmi")) {
            try await ModelIO.load(
                data: Data("<a/>".utf8), uri: "memory:/a", format: .xmi, resourceSet: ResourceSet(),
                registry: registry)
        }
        var diagnostics = ConversionDiagnostics()
        await #expect(throws: ModelFormatError.unsupportedFormat("json")) {
            try await ModelIO.serialise(Resource(), format: .json, registry: registry, diagnostics: &diagnostics)
        }
    }

    @Test("a built-in format reports its raw value as the identifier")
    func builtInIdentifier() async throws {
        let loaded = try await ModelIO.load(
            data: Data(#"{"eClass": "http://example.org/p#//Thing"}"#.utf8), uri: "memory:/thing.json",
            resourceSet: ResourceSet())
        #expect(loaded.format == .json)
        #expect(loaded.formatIdentifier == "json")
    }

    @Test("a loaded document records the identifier of its format")
    func loadedIdentifierDefaultsToFormat() {
        let resource = Resource()
        #expect(ModelIO.Loaded(resource: resource, format: .ecore).formatIdentifier == "ecore")
        #expect(ModelIO.Loaded(resource: resource, format: .ecore, formatIdentifier: "sketch").formatIdentifier == "sketch")
    }

    @Test("a model reader's resource is returned with its diagnostics")
    func modelReaderResource() async throws {
        let registry = ModelFormatRegistry()
        await registry.register(GreedyXMLFormatHandler(priority: .specific))
        let loaded = try await ModelIO.load(
            data: Data("<a/>".utf8), uri: "memory:/a", resourceSet: ResourceSet(), registry: registry)
        #expect(loaded.formatIdentifier == "greedy")
        #expect(loaded.format == .xmi)
        #expect(loaded.packages.isEmpty)
    }

    // MARK: - Writing

    @Test("a metamodel is saved in a registered format by the extension of the file")
    func savesRegisteredFormat() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = await Self.registry()
        let source = try Self.write(Data(Self.sketch.utf8), named: "shapes.sketch", in: directory)
        let loaded = try await ModelIO.load(url: source, resourceSet: ResourceSet(), registry: registry)
        let target = directory.appendingPathComponent("copy.sketch")
        let diagnostics = try await ModelIO.save(loaded.resource, to: target, registry: registry)
        #expect(diagnostics.isEmpty)
        #expect(try String(contentsOf: target, encoding: .utf8) == """
            sketch package shapes http://example.org/shapes shp
            class Shape
            abstract class Figure

            """)
    }

    @Test("a registered format converts to and from the built-in formats")
    func convertsBetweenFormats() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = await Self.registry()
        let source = try Self.write(Data(Self.sketch.utf8), named: "shapes.sketch", in: directory)
        let loaded = try await ModelIO.load(url: source, resourceSet: ResourceSet(), registry: registry)
        let ecoreURL = directory.appendingPathComponent("shapes.ecore")
        try await ModelIO.save(loaded.resource, to: ecoreURL, registry: registry)
        let ecore = try await ModelIO.load(url: ecoreURL, resourceSet: ResourceSet(), registry: registry)
        #expect(ecore.format == .ecore)
        var diagnostics = ConversionDiagnostics()
        let handler = try #require(await registry.handler(identifier: SketchSyntax.identifier) as? any WritableModelFormatHandler)
        let text = try await handler.write(
            ecore.resource, relativeTo: nil, xmiOptions: .legacy, diagnostics: &diagnostics)
        #expect(text.hasPrefix("sketch package shapes http://example.org/shapes shp\nclass Shape\n"))
    }

    @Test("the warnings of a writer are recorded and its errors are thrown")
    func writerDiagnostics() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "memory:/colours.ecore")
        let colour = EEnum(name: "Colour")
        await resource.registerNativePackage(EPackage(
            name: "colours", nsURI: "http://example.org/colours", nsPrefix: "c",
            eClassifiers: [EClass(name: "Palette"), colour]))
        var diagnostics = ConversionDiagnostics()
        let handler = SketchFormatHandler()
        let text = try await handler.write(resource, relativeTo: nil, xmiOptions: .legacy, diagnostics: &diagnostics)
        #expect(text == "sketch package colours http://example.org/colours c\nclass Palette\n")
        let recorded = diagnostics.warnings.compactMap { warning -> SourceDiagnostic? in
            if case .sourceDiagnostic(let diagnostic) = warning.kind { return diagnostic }
            return nil
        }
        #expect(recorded.map(\.code) == [SketchSyntax.skippedClassifier])
        #expect(diagnostics.warnings.first?.message == "The classifier 'Colour' is not a class and was left out")

        let unnamed = await resourceSet.createResource(uri: "memory:/unnamed.ecore")
        await unnamed.registerNativePackage(EPackage(name: ""))
        await #expect {
            try await handler.write(unnamed, relativeTo: nil, xmiOptions: .legacy, diagnostics: &diagnostics)
        } throws: { error in
            (error as? SourceDiagnostic)?.code == SketchSyntax.unnamedPackage
        }
    }

    @Test("a resource of model instances cannot be written as a text metamodel")
    func modelInstancesAreNotAMetamodel() async throws {
        let loaded = try await ModelIO.load(
            data: Data(#"{"eClass": "http://example.org/p#//Thing"}"#.utf8), uri: "memory:/thing.json",
            resourceSet: ResourceSet())
        var diagnostics = ConversionDiagnostics()
        await #expect(throws: ModelIOError.notAMetamodel("memory:/thing.json")) {
            try await SketchFormatHandler().write(
                loaded.resource, relativeTo: nil, xmiOptions: .legacy, diagnostics: &diagnostics)
        }
        let target = URL(fileURLWithPath: "/nonexistent/thing.sketch")
        await #expect(throws: ModelIOError.notAMetamodel(target.absoluteString)) {
            try await SketchFormatHandler().write(
                loaded.resource, relativeTo: target, xmiOptions: .legacy, diagnostics: &diagnostics)
        }
    }

    @Test("a format whose handler cannot write is reported as unwritable")
    func unwritableFormatThrows() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = await Self.registry()
        let source = try Self.write(Data(Self.sketch.utf8), named: "shapes.rosketch", in: directory)
        let loaded = try await ModelIO.load(url: source, resourceSet: ResourceSet(), registry: registry)
        #expect(loaded.formatIdentifier == "readonlysketch")
        let target = directory.appendingPathComponent("copy.rosketch")
        await #expect(throws: ModelFormatError.unwritableFormat("Read-only sketch")) {
            try await ModelIO.save(loaded.resource, to: target, registry: registry)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test("a file with an extension that no handler claims cannot be saved")
    func undetectableSaveFormatThrows() async throws {
        let target = URL(fileURLWithPath: "/nonexistent/model.txt")
        await #expect(throws: ModelFormatError.undetectableFormat(target.absoluteString)) {
            try await ModelIO.save(Resource(), to: target, registry: await Self.registry())
        }
    }

    @Test("the new error and warning descriptions name the format and the diagnostic")
    func descriptions() {
        #expect(ModelFormatError.unwritableFormat("Sketch").description == "Cannot write documents in the Sketch format")
        let diagnostic = SourceDiagnostic(severity: .warning, code: "c", message: "m")
        #expect(ConversionWarning(.sourceDiagnostic(diagnostic)).message == "m")
    }
}
