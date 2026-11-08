//
// KM3FormatHandlerTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that KM3 is a built-in format of ``ModelFormat``, ``ModelFormatRegistry`` and ``ModelIO``.
@Suite("KM3 format handler")
struct KM3FormatHandlerTests {
    /// A metamodel whose package has no namespace URI, as many KM3 documents have.
    static let garden = """
        -- A garden metamodel without a namespace URI.
        package Garden {
        \tclass Bed {
        \t\tattribute label : String;
        \t\treference plants[*] ordered container : Plant;
        \t}
        \tclass Plant {
        \t\tattribute species : String;
        \t}
        }

        package PrimitiveTypes {
        \tdatatype String;
        }

        """

    /// A model of the garden metamodel whose namespace is the name of the package.
    static let gardenModel = """
        <?xml version="1.0" encoding="UTF-8"?>
        <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:garden="Garden">
          <garden:Bed label="North">
            <plants species="Fern"/>
            <plants species="Moss"/>
          </garden:Bed>
        </xmi:XMI>

        """

    /// Creates a new temporary directory.
    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KM3FormatHandlerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes bytes to a file in a directory.
    static func write(_ data: Data, named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    /// Writes text as UTF-8 to a file in a directory.
    static func write(_ text: String, named name: String, in directory: URL) throws -> URL {
        try write(Data(text.utf8), named: name, in: directory)
    }

    // MARK: - ModelFormat

    @Test("KM3 is a format named by its file extension, regardless of case")
    func formatName() {
        #expect(ModelFormat.km3.rawValue == KM3Format.fileExtension)
        #expect(ModelFormat.km3.fileExtension == "km3")
        #expect(ModelFormat.km3.description == "KM3")
        #expect(ModelFormat(fileExtension: "KM3") == .km3)
        #expect(ModelFormat.detect(url: URL(fileURLWithPath: "models/Garden.Km3")) == .km3)
        #expect(ModelFormat.allCases.contains(.km3))
    }

    @Test("KM3 text is detected by its content", arguments: [
        garden, KM3Fixtures.library, "package P {}", "\u{FEFF}-- comment\n\npackage P { class C {} }",
    ])
    func detectsKM3(text: String) {
        #expect(ModelFormat.detect(data: Data(text.utf8)) == .km3)
    }

    @Test("text that does not start like KM3 is not detected as KM3", arguments: [
        "package P;", "class C {}", "plain text", "-- only a comment", "package {",
    ])
    func rejectsOtherText(text: String) {
        #expect(ModelFormat.detect(data: Data(text.utf8)) == nil)
    }

    @Test("XML and JSON are detected before KM3")
    func xmlAndJSONFirst() {
        #expect(ModelFormat.detect(data: Data("<package name=\"P\">{</package>".utf8)) == .xmi)
        #expect(ModelFormat.detect(data: Data("{\"package\": \"P\"}".utf8)) == .json)
    }

    // MARK: - Registry

    @Test("the built-in KM3 handler reads and writes metamodels with specific priority")
    func builtInHandler() async throws {
        let handler = try #require(await ModelFormatRegistry.shared.handler(for: .km3))
        #expect(handler.identifier == "km3")
        #expect(handler.name == "KM3")
        #expect(handler.fileExtensions == ["km3"])
        #expect(handler.role == .metamodel)
        #expect(handler.priority == .specific)
        #expect(handler.format == .km3)
        #expect(handler is any WritableModelFormatHandler)
        #expect(ModelFormatRegistry.builtInHandlers.contains { $0.identifier == "km3" })
    }

    @Test("the registry recognises KM3 text, and XML and JSON as before")
    func registryRecognisesKM3() async {
        let registry = ModelFormatRegistry()
        #expect(await registry.handler(recognising: Data(Self.garden.utf8))?.format == .km3)
        #expect(await registry.handler(recognising: Data(Self.gardenModel.utf8))?.format == .xmi)
        #expect(await registry.handler(recognising: Data("[]".utf8))?.format == .json)
        #expect(await registry.handler(forFileExtension: "KM3")?.format == .km3)
    }

    // MARK: - Loading

    @Test("a KM3 document loads as metamodel packages that are registered")
    func loadsKM3Document() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try Self.write(KM3Fixtures.library, named: "Library.km3", in: directory)
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(url: url, resourceSet: resourceSet)
        #expect(loaded.format == .km3)
        #expect(loaded.formatIdentifier == "km3")
        #expect(loaded.packages.map(\.name) == ["Library", "People"])
        #expect(await resourceSet.getMetamodel(uri: "http://example.org/library")?.name == "Library")
        #expect(await resourceSet.getMetamodel(uri: "http://example.org/people")?.name == "People")
        #expect(await loaded.resource.loadDiagnostics.isEmpty)
        let roots = await loaded.resource.getRootObjects().compactMap { ($0 as? EPackage)?.name }
        #expect(roots == ["Library", "People"])
    }

    @Test("a KM3 document with an unknown extension is recognised by its content")
    func recognisesKM3ByContent() async throws {
        let loaded = try await ModelIO.load(
            data: Data(KM3Fixtures.nested.utf8), uri: "memory:/outer.txt", resourceSet: ResourceSet())
        #expect(loaded.format == .km3)
        #expect(loaded.packages.map(\.name) == ["Outer"])
    }

    @Test("the KM3 options of the Ecore load options choose how primitive types are read")
    func declaredDataTypes() async throws {
        let standard = try await ModelIO.load(
            data: Data(KM3Fixtures.library.utf8), uri: "memory:/standard.km3", resourceSet: ResourceSet())
        #expect(!standard.packages.map(\.name).contains(KM3Format.primitiveTypesPackageName))
        #expect(EcoreLoadOptions().km3Options == .standard)
        let options = ModelIO.LoadOptions(ecoreLoadOptions: EcoreLoadOptions(km3Options: .declaredDataTypes))
        let declared = try await ModelIO.load(
            data: Data(KM3Fixtures.library.utf8), uri: "memory:/declared.km3", resourceSet: ResourceSet(),
            options: options)
        #expect(declared.packages.map(\.name) == ["Library", "People", KM3Format.primitiveTypesPackageName])
    }

    @Test("syntax errors of a KM3 document are recorded as load diagnostics")
    func syntaxErrorsAreRecorded() async throws {
        let loaded = try await ModelIO.load(
            data: Data("package P { class C { attribute ; } }".utf8), uri: "memory:/broken.km3",
            format: .km3, resourceSet: ResourceSet())
        let diagnostics = await loaded.resource.loadDiagnostics
        #expect(diagnostics.contains { $0.severity == .error })
        #expect(diagnostics.allSatisfy { $0.document == "memory:/broken.km3" })
    }

    @Test("a KM3 document that is not UTF-8 is read as ISO-8859-1 with a warning")
    func latin1Fallback() async throws {
        let text = "-- @nsURI http://example.org/cafe\npackage Caf\u{E9} { class Fa\u{E7}ade {} }\n"
        let bytes = try #require(text.data(using: .isoLatin1))
        let loaded = try await ModelIO.load(data: bytes, uri: "memory:/cafe.km3", resourceSet: ResourceSet())
        #expect(loaded.packages.map(\.name) == ["Caf\u{E9}"])
        #expect(loaded.packages.first?.eClassifiers.map(\.name) == ["Fa\u{E7}ade"])
        let diagnostics = await loaded.resource.loadDiagnostics
        #expect(diagnostics.map(\.code) == [TextDecodingDiagnostic.decodedAsISOLatin1])
        #expect(diagnostics.first?.severity == .warning)
    }

    // MARK: - Metamodels Without a Namespace

    @Test("a package without a namespace URI is registered under its name with a warning")
    func packageWithoutNamespace() async throws {
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(
            data: Data(Self.garden.utf8), uri: "memory:/Garden.km3", resourceSet: resourceSet)
        let package = try #require(loaded.packages.first)
        #expect(package.name == "Garden")
        #expect(package.nsURI.isEmpty)
        #expect(await resourceSet.getMetamodel(uri: "Garden")?.id == package.id)
        #expect(await !resourceSet.getMetamodelURIs().contains(""))
        let diagnostics = await loaded.resource.loadDiagnostics
        #expect(diagnostics.map(\.code) == [EcoreLoadDiagnostic.registeredUnderName])
        #expect(diagnostics.first?.severity == .warning)
        #expect(diagnostics.first?.message.contains("Garden") == true)
        #expect(diagnostics.first?.document == "memory:/Garden.km3")
        let message = diagnostics.first?.message ?? ""
        #expect(message.contains("in this resource set only"), "\(message)")
        #expect(message.contains("validation reports"), "\(message)")
    }

    @Test("a KM3 metamodel without a namespace URI is usable by the models of a load")
    func modelOfKM3Metamodel() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let metamodel = try Self.write(Self.garden, named: "Garden.km3", in: directory)
        let model = try Self.write(Self.gardenModel, named: "garden.xmi", in: directory)
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(url: model, resourceSet: resourceSet, metamodels: [metamodel])
        let bed = try #require(await loaded.resource.getRootObjects().first as? DynamicEObject)
        let package = try #require(await resourceSet.getMetamodel(uri: "Garden"))
        #expect(bed.eClass.id == package.getEClass("Bed")?.id)
        #expect(bed.eGet("label") as? String == "North")
        let metamodelResource = try #require(await resourceSet.getResource(uri: metamodel.absoluteString))
        #expect((await metamodelResource.getRootObjects().first as? EPackage)?.id == package.id)
    }

    // MARK: - Registering Metamodels

    @Test("metamodels in KM3 are registered through the registry")
    func registerKM3Metamodels() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try Self.write(KM3Fixtures.library, named: "Library.km3", in: directory)
        let garden = try Self.write(Self.garden, named: "garden.mm", in: directory)
        let resourceSet = ResourceSet()
        let packages = try await ModelIO.registerMetamodels(at: [library, garden], in: resourceSet)
        #expect(packages.map(\.name) == ["Library", "People", "Garden"])
        #expect(await resourceSet.getMetamodel(uri: "http://example.org/library")?.id == packages.first?.id)
        #expect(await resourceSet.getMetamodel(uri: "Garden")?.id == packages.last?.id)
        let again = try await ModelIO.registerMetamodels(at: [library], in: resourceSet)
        #expect(again.map(\.id) == packages.prefix(2).map(\.id))
        let resource = try #require(await resourceSet.getResource(uri: library.absoluteString))
        let roots = await resource.getRootObjects()
        #expect(roots.count == 2)
    }

    @Test("the KM3 options apply to registered metamodels")
    func registerWithDeclaredDataTypes() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try Self.write(KM3Fixtures.library, named: "Library.km3", in: directory)
        let packages = try await ModelIO.registerMetamodels(
            at: [library], in: ResourceSet(), options: EcoreLoadOptions(km3Options: .declaredDataTypes))
        #expect(packages.map(\.name) == ["Library", "People", KM3Format.primitiveTypesPackageName])
    }

    @Test("a registry without a KM3 handler loads metamodels as Ecore documents")
    func registryWithoutKM3() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try Self.write(KM3Fixtures.library, named: "Library.km3", in: directory)
        let registry = ModelFormatRegistry(handlers: ModelFormatRegistry.builtInHandlers.filter { $0.format != .km3 })
        await #expect(throws: (any Error).self) {
            try await ModelIO.registerMetamodels(at: [library], in: ResourceSet(), registry: registry)
        }
    }

    // MARK: - Saving

    @Test("metamodel packages are written as KM3 and read back alike")
    func savesKM3() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = try await ModelIO.load(
            data: Data(KM3Fixtures.library.utf8), uri: "memory:/library.km3", resourceSet: ResourceSet())
        let url = directory.appendingPathComponent("Copy.km3")
        let diagnostics = try await ModelIO.save(loaded.resource, to: url)
        #expect(diagnostics.isEmpty)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text == KM3Writer.write(loaded.packages).text)
        let reloaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        #expect(KM3Structure.describe(reloaded.packages) == KM3Structure.describe(loaded.packages))
    }

    @Test("an Ecore metamodel is written as KM3")
    func ecoreAsKM3() async throws {
        let ecore = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" \
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="pond" nsURI="http://example.org/pond" nsPrefix="pond">
              <eClassifiers xsi:type="ecore:EClass" name="Fish"/>
            </ecore:EPackage>
            """
        let loaded = try await ModelIO.load(data: Data(ecore.utf8), uri: "memory:/pond.ecore", resourceSet: ResourceSet())
        var diagnostics = ConversionDiagnostics()
        let text = try await ModelIO.serialise(loaded.resource, format: .km3, diagnostics: &diagnostics)
        #expect(text.contains("-- @nsURI http://example.org/pond"), "\(text)")
        #expect(text.contains("package pond {"), "\(text)")
        #expect(text.contains("class Fish"), "\(text)")
    }

    @Test("model instances cannot be written as KM3")
    func instancesAreNotKM3() async throws {
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(
            data: Data(Self.gardenModel.utf8), uri: "memory:/garden.xmi", resourceSet: resourceSet,
            options: ModelIO.LoadOptions(requiresMetamodel: false))
        var diagnostics = ConversionDiagnostics()
        await #expect(throws: ModelIOError.notAMetamodel("memory:/garden.xmi")) {
            try await ModelIO.serialise(loaded.resource, format: .km3, diagnostics: &diagnostics)
        }
    }
}
