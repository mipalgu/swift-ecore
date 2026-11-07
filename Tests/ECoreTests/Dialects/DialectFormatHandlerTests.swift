//
// DialectFormatHandlerTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that EMOF metamodels and UML models are read and written through ``ModelIO`` and
/// the ``ModelFormatRegistry`` as ``EMOFFormat`` and ``UMLFormat`` read and write them.
@Suite("EMOF and UML through the format registry")
struct DialectFormatHandlerTests {
    /// The directory of the dialect fixtures.
    static let directory = OMGXMIDialectTests.directory

    /// The location of a dialect fixture.
    static func fixture(_ name: String) -> URL { directory.appendingPathComponent(name) }

    /// The bytes of a dialect fixture.
    static func data(_ name: String) throws -> Data { try Data(contentsOf: fixture(name)) }

    // MARK: - Formats

    @Test("EMOF and UML are named by their file extensions")
    func formatsAreNamedByExtension() {
        #expect(ModelFormat(fileExtension: "emof") == .emof)
        #expect(ModelFormat(fileExtension: "UML") == .uml)
        #expect(ModelFormat.emof.fileExtension == EMOFFormat.fileExtension)
        #expect(ModelFormat.uml.fileExtension == UMLFormat.fileExtension)
        #expect(ModelFormat.emof.description == "EMOF")
        #expect(ModelFormat.uml.description == "UML")
        #expect(ModelFormat.detect(url: Self.fixture("library.emof")) == .emof)
        #expect(ModelFormat.detect(url: Self.fixture("garden.uml")) == .uml)
    }

    @Test("the contents of EMOF and UML documents are detected", arguments: [
        ("library.emof", ModelFormat.emof), ("garden.uml", .uml), ("garden-profiled.uml", .uml),
        ("garden-stereotyped.uml", .uml), ("class-model-omg.xmi", .uml), ("shop-omg.xmi", .xmi),
        ("shop.ecore", .ecore),
    ])
    func contentsAreDetected(name: String, format: ModelFormat) async throws {
        let data = try Self.data(name)
        #expect(ModelFormat.detect(data: data) == format)
        #expect(await ModelFormatRegistry().handler(recognising: data)?.format == format)
    }

    @Test("an Ecore package in a wrapper that declares a UML namespace stays an Ecore document")
    func ecoreWrapperWithUMLNamespaceIsEcore() {
        let text = """
            <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" xmlns:uml="\(UMLNamespaces.uml)">
              <ecore:EPackage name="p"/>
            </xmi:XMI>
            """
        #expect(ModelFormat.detect(data: Data(text.utf8)) == .ecore)
    }

    @Test("the EMOF and UML handlers recognise documents before the generic formats")
    func handlersArePrioritised() async throws {
        let registry = ModelFormatRegistry()
        let emof = try #require(await registry.handler(for: .emof))
        let uml = try #require(await registry.handler(for: .uml))
        #expect(emof.role == .metamodel)
        #expect(uml.role == .model)
        #expect(emof.priority > .generic)
        #expect(uml.priority > .generic)
        #expect(emof is any WritableModelFormatHandler)
        #expect(uml is any WritableModelFormatHandler)
        #expect(await registry.handler(forFileExtension: "emof")?.identifier == "emof")
        #expect(await registry.handler(forFileExtension: "uml")?.identifier == "uml")
    }

    // MARK: - Refinement of Generic Extensions

    @Test("a generic file extension yields to a handler that recognises the contents", arguments: [
        ("model.xmi", "class-model-omg.xmi", "uml"), ("model.xmi", "shop-omg.xmi", "xmi"),
        ("metamodel.xmi", "library.emof", "emof"), ("shop.ecore", "shop.ecore", "ecore"),
        ("model.uml", "shop-omg.xmi", "uml"), ("model.unknown", "garden.uml", "uml"),
    ])
    func genericExtensionsAreRefined(path: String, fixture: String, identifier: String?) async throws {
        let registry = ModelFormatRegistry()
        let handler = await registry.handler(for: URL(fileURLWithPath: path), contents: try Self.data(fixture))
        #expect(handler?.identifier == identifier)
    }

    @Test("a refined extension is still claimed when nothing more specific recognises the contents")
    func refinementKeepsClaimWithoutRecognition() async {
        let registry = ModelFormatRegistry()
        let handler = await registry.handler(for: URL(fileURLWithPath: "model.xmi"), contents: Data("{}".utf8))
        #expect(handler?.identifier == ModelFormat.xmi.rawValue)
    }

    // MARK: - EMOF

    @Test("an EMOF document loads through ModelIO as EMOFFormat reads it")
    func emofLoadsThroughModelIO() async throws {
        let url = Self.fixture("library.emof")
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(url: url, resourceSet: resourceSet)
        let direct = try await EMOFFormat.read(url: url, resourceSet: ResourceSet())
        #expect(loaded.format == .emof)
        #expect(loaded.formatIdentifier == "emof")
        #expect(loaded.packages.map(\.name) == direct.packages.map(\.name))
        #expect(await loaded.resource.loadDiagnostics == direct.diagnostics)
        #expect(await resourceSet.getMetamodel(uri: "http://example.org/library") != nil)
        let expected = XMISerializer(options: .emf).serialize(direct.packages)
        #expect(XMISerializer(options: .emf).serialize(loaded.packages) == expected)
    }

    @Test("an EMOF document in an XMI file loads as EMOF")
    func emofInXMIFileLoadsAsEMOF() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DialectFormatHandlerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.xmi")
        try Self.data("library.emof").write(to: url)
        let loaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        #expect(loaded.format == .emof)
        let registered = try await ModelIO.registerMetamodels(at: [url], in: ResourceSet())
        #expect(registered.map(\.name) == ["library"])
    }

    @Test("an EMOF document registers its packages as a metamodel")
    func emofRegistersMetamodel() async throws {
        let resourceSet = ResourceSet()
        let packages = try await ModelIO.registerMetamodels(at: [Self.fixture("library.emof")], in: resourceSet)
        #expect(packages.map(\.name) == ["library"])
        #expect(await resourceSet.getMetamodel(uri: "http://example.org/library")?.name == "library")
    }

    @Test("an EMOF document loaded from its bytes is recognised")
    func emofLoadsFromBytes() async throws {
        let loaded = try await ModelIO.load(
            data: try Self.data("library.emof"), uri: "memory:/library.emof", resourceSet: ResourceSet())
        #expect(loaded.format == .emof)
        #expect(loaded.packages.map(\.name) == ["library"])
    }

    @Test("a metamodel is saved as EMOF as EMOFFormat writes it")
    func emofSavesThroughModelIO() async throws {
        let url = Self.fixture("library.emof")
        let loaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        var diagnostics = ConversionDiagnostics()
        let text = try await ModelIO.serialise(loaded.resource, format: .emof, relativeTo: url, diagnostics: &diagnostics)
        #expect(text == EMOFFormat.write(loaded.packages, relativeTo: url).text)
        #expect(diagnostics.warnings.isEmpty)
    }

    @Test("model instances are not written as EMOF")
    func modelInstancesAreNotEMOF() async throws {
        let loaded = try await ModelIO.load(url: Self.fixture("shop-omg.xmi"), resourceSet: ResourceSet())
        var diagnostics = ConversionDiagnostics()
        await #expect(throws: ModelIOError.self) {
            try await ModelIO.serialise(loaded.resource, format: .emof, diagnostics: &diagnostics)
        }
    }

    // MARK: - UML

    @Test("a UML model loads through ModelIO as UMLFormat reads it")
    func umlLoadsThroughModelIO() async throws {
        let url = Self.fixture("garden.uml")
        let loaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        let direct = try await UMLFormat.read(url: url, resourceSet: ResourceSet())
        #expect(loaded.format == .uml)
        #expect(loaded.formatIdentifier == "uml")
        #expect(loaded.packages.isEmpty)
        #expect(loaded.diagnostics.warnings.isEmpty)
        let (uml, _) = try await UMLMetamodel.packages()
        let roots = await loaded.resource.getRootObjects()
        #expect(roots.first?.eClass.id == uml.getEClass("Model")?.id)
        let written = try await UMLFormat.write(loaded.resource, relativeTo: url)
        #expect(written == (try await UMLFormat.write(direct.resource, relativeTo: url)))
    }

    @Test("an unresolved profile of a UML model is reported in the load diagnostics")
    func umlProfileWarningsAreLoadDiagnostics() async throws {
        let url = Self.fixture("garden-stereotyped.uml")
        let loaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        let codes = await loaded.resource.loadDiagnostics.map(\.code)
        #expect(codes.contains(ModelDocumentDiagnostic.unresolvedProfile))
        let direct = try await UMLFormat.read(url: url, resourceSet: ResourceSet())
        let directCodes = direct.diagnostics.map(\.code).filter { $0 == ModelDocumentDiagnostic.unresolvedProfile }
        #expect(codes.filter { $0 == ModelDocumentDiagnostic.unresolvedProfile } == directCodes)
    }

    @Test("an OMG UML model in an XMI file loads as UML unless XMI is asked for")
    func omgUMLInXMIFileLoadsAsUML() async throws {
        let url = Self.fixture("class-model-omg.xmi")
        let loaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        #expect(loaded.format == .uml)
        let (uml, _) = try await UMLMetamodel.packages()
        #expect(await loaded.resource.getRootObjects().first?.eClass.id == uml.getEClass("Model")?.id)
        let asXMI = try await ModelIO.load(url: url, format: .xmi, resourceSet: ResourceSet())
        #expect(asXMI.format == .xmi)
        let detected = try await ModelIO.load(data: try Self.data("class-model-omg.xmi"), uri: url.absoluteString,
                                              resourceSet: ResourceSet())
        #expect(detected.format == .uml)
    }

    @Test("an XMI document of another namespace still loads as XMI")
    func otherXMIStaysXMI() async throws {
        let loaded = try await ModelIO.load(url: Self.fixture("shop-omg.xmi"), resourceSet: ResourceSet())
        #expect(loaded.format == .xmi)
        #expect(loaded.formatIdentifier == "xmi")
    }

    @Test("a UML model is saved in the layout of Eclipse UML2")
    func umlSavesThroughModelIO() async throws {
        let url = Self.fixture("garden.uml")
        let loaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        for options in [XMISerializationOptions.legacy, .emf] {
            var diagnostics = ConversionDiagnostics()
            let text = try await ModelIO.serialise(
                loaded.resource, format: .uml, relativeTo: url, xmiOptions: options, diagnostics: &diagnostics)
            #expect(text == (try await UMLFormat.write(loaded.resource, relativeTo: url)).text)
            #expect(diagnostics.warnings.isEmpty)
        }
    }

    @Test("a UML model is written to a file through its extension and read back")
    func umlRoundTripsThroughFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DialectFormatHandlerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = try await ModelIO.load(url: Self.fixture("garden.uml"), resourceSet: ResourceSet())
        let url = directory.appendingPathComponent("copy.uml")
        try await ModelIO.save(loaded.resource, to: url)
        let reloaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        #expect(reloaded.format == .uml)
        #expect(await UMLFormatTests.classCounts(in: reloaded.resource)
            == UMLFormatTests.classCounts(in: loaded.resource))
    }
}
