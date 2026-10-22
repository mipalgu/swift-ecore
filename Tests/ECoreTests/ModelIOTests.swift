//
// ModelIOTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests that models of every format are loaded and saved through one interface.
@Suite("Model loading and saving")
struct ModelIOTests {
    private static let rootURI = "http://example.org/root"
    private static let kernelURI = "http://example.org/root/kernel"
    private static let viewsURI = "http://example.org/root/views"

    private static let instanceXMI = """
        <?xml version="1.0" encoding="UTF-8"?>
        <root:Model xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" \
        xmlns:root="http://example.org/root" xmlns:kernel="http://example.org/root/kernel" name="m">
          <elements xsi:type="kernel:Node" name="a" weight="1"/>
          <views name="v" shows="//@elements.0"/>
        </root:Model>
        """

    private static let instanceJSON = """
        {"eClass": "http://example.org/root#//Model", "name": "m",
         "elements": [{"eClass": "http://example.org/root/kernel#//Node", "name": "a", "weight": 1}]}
        """

    private static let unknownClassJSON = #"{"eClass": "http://example.org/unknown#//Thing", "size": 3}"#

    // MARK: - Helpers

    /// A fresh temporary directory, removed by the caller.
    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelIOTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func write(_ text: String, named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: testWritesAtomically, encoding: .utf8)
        return url
    }

    private static func metamodelURL() throws -> URL {
        try ReflectionFixtures.resourcesURL().appendingPathComponent("metamodels/Nested.ecore")
    }

    private static func root(of resource: Resource) async throws -> DynamicEObject {
        try #require(await resource.getRootObjects().first as? DynamicEObject)
    }

    private static func children(
        _ feature: String, of object: DynamicEObject, in resource: Resource
    ) async -> [DynamicEObject] {
        let value = object.eGet(feature)
        let identifiers = (value as? [EUUID]) ?? (value as? EUUID).map { [$0] } ?? []
        var result: [DynamicEObject] = []
        for identifier in identifiers {
            if let child = await resource.resolve(identifier) as? DynamicEObject { result.append(child) }
        }
        return result
    }

    private static func untypedClassNames(_ diagnostics: ConversionDiagnostics) -> [String] {
        diagnostics.warnings.compactMap {
            if case .untypedClass(let name) = $0.kind { return name }
            return nil
        }
    }

    // MARK: - Metamodels

    @Test("an Ecore document is loaded as native packages and registered with its subpackages")
    func loadsEcoreDocument() async throws {
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(url: try Self.metamodelURL(), resourceSet: resourceSet)
        #expect(loaded.format == .ecore)
        #expect(loaded.diagnostics.isEmpty)
        #expect(loaded.packages.map(\.name) == ["root"])
        let roots = await loaded.resource.getRootObjects()
        #expect(roots.compactMap { ($0 as? EPackage)?.name } == ["root"])
        #expect(await resourceSet.getMetamodel(uri: Self.rootURI)?.name == "root")
        #expect(await resourceSet.getMetamodel(uri: Self.kernelURI)?.name == "kernel")
        #expect(await resourceSet.getMetamodel(uri: Self.viewsURI)?.name == "views")
    }

    @Test("metamodels are registered with their subpackages before a model is loaded")
    func registersMetamodels() async throws {
        let resourceSet = ResourceSet()
        let packages = try await ModelIO.registerMetamodels(at: [try Self.metamodelURL()], in: resourceSet)
        #expect(packages.map(\.name) == ["root"])
        #expect(await resourceSet.getMetamodel(uri: Self.kernelURI)?.getEClass("Node") != nil)
    }

    @Test("a registered metamodel replaces an earlier package registered under the same URI")
    func laterMetamodelReplacesEarlier() async throws {
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(EPackage(name: "earlier", nsURI: Self.rootURI, nsPrefix: "root"))
        _ = try await ModelIO.registerMetamodels(at: [try Self.metamodelURL()], in: resourceSet)
        #expect(await resourceSet.getMetamodel(uri: Self.rootURI)?.name == "root")
    }

    // MARK: - XMI

    @Test("an XMI model is read with the classes of the given metamodels")
    func loadsXMIWithMetamodels() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try Self.write(Self.instanceXMI, named: "model.xmi", in: directory)
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(
            url: url, resourceSet: resourceSet, metamodels: [try Self.metamodelURL()])
        #expect(loaded.format == .xmi)
        #expect(loaded.diagnostics.isEmpty)
        #expect(loaded.packages.isEmpty)
        let kernel = try #require(await resourceSet.getMetamodel(uri: Self.kernelURI))
        let model = try await Self.root(of: loaded.resource)
        let elements = await Self.children("elements", of: model, in: loaded.resource)
        #expect(elements.map(\.eClass.id) == [kernel.getEClass("Node")?.id])
        let views = await Self.children("views", of: model, in: loaded.resource)
        #expect((views.first?.eGet("shows") as? [EUUID]) == elements.map(\.id))
        #expect(await resourceSet.getResource(uri: url.absoluteString) != nil)
    }

    @Test("an XMI model without a metamodel reports the classes that it had to make up")
    func loadsXMIWithoutMetamodels() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try Self.write(Self.instanceXMI, named: "model.xmi", in: directory)
        let loaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        #expect(Self.untypedClassNames(loaded.diagnostics).contains("Model"))
    }

    @Test("reference attributes can be kept as the text that was written")
    func keepsReferenceText() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = Self.instanceXMI.replacingOccurrences(
            of: "shows=\"//@elements.0\"", with: "focus=\"other.xmi#//Thing\"")
        let url = try Self.write(text, named: "model.xmi", in: directory)
        let raw = try await ModelIO.load(
            url: url, resourceSet: ResourceSet(), metamodels: [try Self.metamodelURL()],
            options: ModelIO.LoadOptions(referenceParsing: .rawText))
        let rawModel = try await Self.root(of: raw.resource)
        let rawViews = await Self.children("views", of: rawModel, in: raw.resource)
        #expect(rawViews.first?.eGet("focus") as? String == "other.xmi#//Thing")

        let interpreted = try await ModelIO.load(
            url: url, resourceSet: ResourceSet(), metamodels: [try Self.metamodelURL()])
        let model = try await Self.root(of: interpreted.resource)
        let views = await Self.children("views", of: model, in: interpreted.resource)
        let view = try #require(views.first)
        #expect(await interpreted.resource.eGet(objectId: view.id, feature: "focus") is ResourceProxy)
    }

    // MARK: - JSON

    @Test("a JSON model is read with the classes of the given metamodels")
    func loadsJSONWithMetamodels() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try Self.write(Self.instanceJSON, named: "model.json", in: directory)
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(
            url: url, resourceSet: resourceSet, metamodels: [try Self.metamodelURL()])
        #expect(loaded.format == .json)
        #expect(loaded.diagnostics.isEmpty)
        let root = try #require(await resourceSet.getMetamodel(uri: Self.rootURI))
        let model = try await Self.root(of: loaded.resource)
        #expect(model.eClass.id == root.getEClass("Model")?.id)
    }

    @Test("with registered metamodels a JSON class that none defines is an error")
    func jsonRequiresMetamodelWhenRegistered() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try Self.write(Self.unknownClassJSON, named: "thing.json", in: directory)
        await #expect(throws: JSONError.self) {
            _ = try await ModelIO.load(url: url, resourceSet: ResourceSet(), metamodels: [try Self.metamodelURL()])
        }
    }

    @Test("a JSON class that no metamodel defines is made up when a metamodel is not required")
    func jsonSynthesisesWhenNotRequired() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try Self.write(Self.unknownClassJSON, named: "thing.json", in: directory)
        let withMetamodel = try await ModelIO.load(
            url: url, resourceSet: ResourceSet(), metamodels: [try Self.metamodelURL()],
            options: ModelIO.LoadOptions(requiresMetamodel: false))
        #expect(Self.untypedClassNames(withMetamodel.diagnostics) == ["Thing"])
        let withoutMetamodel = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        #expect(Self.untypedClassNames(withoutMetamodel.diagnostics) == ["Thing"])
        #expect(try await Self.root(of: withoutMetamodel.resource).eGet("size") as? Int == 3)
    }

    @Test("a JSON class that no metamodel defines is an error when a metamodel is required")
    func jsonRequiredWithoutMetamodel() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try Self.write(Self.unknownClassJSON, named: "thing.json", in: directory)
        await #expect(throws: JSONError.self) {
            _ = try await ModelIO.load(
                url: url, resourceSet: ResourceSet(), options: ModelIO.LoadOptions(requiresMetamodel: true))
        }
    }

    // MARK: - Formats

    @Test("an explicit format takes precedence over the file extension")
    func explicitFormatWins() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try Self.write(Self.instanceJSON, named: "model.xmi", in: directory)
        let loaded = try await ModelIO.load(
            url: url, format: .json, resourceSet: ResourceSet(), metamodels: [try Self.metamodelURL()])
        #expect(loaded.format == .json)
    }

    @Test("the format of a file without a known extension is detected from its contents")
    func formatDetectedFromContents() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let xmi = try Self.write(Self.instanceXMI, named: "model.data", in: directory)
        let ecore = try Self.write(
            try String(contentsOf: try Self.metamodelURL(), encoding: .utf8), named: "metamodel.data",
            in: directory)
        let resourceSet = ResourceSet()
        #expect(try await ModelIO.load(url: ecore, resourceSet: resourceSet).format == .ecore)
        #expect(try await ModelIO.load(url: xmi, resourceSet: resourceSet).format == .xmi)
    }

    @Test("a document in no known format is an error")
    func undetectableFormatThrows() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try Self.write("name: value", named: "model.txt", in: directory)
        await #expect(throws: ModelFormatError.self) {
            _ = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        }
    }

    @Test("a model is loaded from bytes with a format detected from its contents")
    func loadsFromData() async throws {
        let resourceSet = ResourceSet()
        _ = try await ModelIO.registerMetamodels(at: [try Self.metamodelURL()], in: resourceSet)
        let loaded = try await ModelIO.load(
            data: Data(Self.instanceJSON.utf8), uri: "memory:/model", resourceSet: resourceSet)
        #expect(loaded.format == .json)
        #expect(await loaded.resource.uri == "memory:/model")
    }

    // MARK: - Saving

    @Test("a model converts from XMI to JSON and back with the same classes")
    func convertsBetweenFormats() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try Self.write(Self.instanceXMI, named: "model.xmi", in: directory)
        let metamodels = [try Self.metamodelURL()]
        let loaded = try await ModelIO.load(url: input, resourceSet: ResourceSet(), metamodels: metamodels)

        var diagnostics = loaded.diagnostics
        let json = directory.appendingPathComponent("model.json")
        try await ModelIO.save(loaded.resource, to: json, diagnostics: &diagnostics)
        #expect(diagnostics.isEmpty)
        let text = try String(contentsOf: json, encoding: .utf8)
        #expect(text.contains("\(Self.kernelURI)#//Node"))

        let readingSet = ResourceSet()
        let reloaded = try await ModelIO.load(url: json, resourceSet: readingSet, metamodels: metamodels)
        let kernel = try #require(await readingSet.getMetamodel(uri: Self.kernelURI))
        let model = try await Self.root(of: reloaded.resource)
        let elements = await Self.children("elements", of: model, in: reloaded.resource)
        #expect(elements.map(\.eClass.id) == [kernel.getEClass("Node")?.id])
        let views = await Self.children("views", of: model, in: reloaded.resource)
        #expect((views.first?.eGet("shows") as? [EUUID]) == elements.map(\.id))

        let xmi = directory.appendingPathComponent("again.xmi")
        let written = try await ModelIO.save(reloaded.resource, to: xmi)
        #expect(written.isEmpty)
        #expect(try String(contentsOf: xmi, encoding: .utf8).contains("xsi:type=\"kernel:Node\""))
    }

    @Test("an XMI model is written with the given serialisation options")
    func savesWithXMIOptions() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try Self.write(Self.instanceXMI, named: "model.xmi", in: directory)
        let loaded = try await ModelIO.load(
            url: input, resourceSet: ResourceSet(), metamodels: [try Self.metamodelURL()])
        let output = directory.appendingPathComponent("emf.xmi")
        var diagnostics = ConversionDiagnostics()
        try await ModelIO.save(loaded.resource, to: output, xmiOptions: .emf, diagnostics: &diagnostics)
        let expected = try await XMISerializer(options: .emf).serialize(loaded.resource, relativeTo: output)
        #expect(try String(contentsOf: output, encoding: .utf8) == expected)
    }

    @Test("native packages are written as an Ecore document")
    func savesEcoreDocument() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = try await ModelIO.load(url: try Self.metamodelURL(), resourceSet: ResourceSet())
        let output = directory.appendingPathComponent("copy.ecore")
        let package = try #require(loaded.packages.first)
        try await ModelIO.save(loaded.resource, to: output)
        #expect(
            try String(contentsOf: output, encoding: .utf8)
                == XMISerializer().serialize([package], relativeTo: output))
        let reloaded = try await ModelIO.load(url: output, resourceSet: ResourceSet())
        #expect(reloaded.packages.first?.allPackages.map(\.nsURI) == [Self.rootURI, Self.kernelURI, Self.viewsURI])
    }

    @Test("a model whose roots are not packages cannot be written as an Ecore document")
    func savingInstancesAsEcoreThrows() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try Self.write(Self.instanceXMI, named: "model.xmi", in: directory)
        let loaded = try await ModelIO.load(
            url: input, resourceSet: ResourceSet(), metamodels: [try Self.metamodelURL()])
        let output = directory.appendingPathComponent("model.ecore")
        await #expect(throws: ModelIOError.self) { _ = try await ModelIO.save(loaded.resource, to: output) }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test("saving to a file without a known extension needs an explicit format")
    func savingNeedsAFormat() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try Self.write(Self.instanceXMI, named: "model.xmi", in: directory)
        let loaded = try await ModelIO.load(
            url: input, resourceSet: ResourceSet(), metamodels: [try Self.metamodelURL()])
        let output = directory.appendingPathComponent("model.out")
        await #expect(throws: ModelFormatError.self) { _ = try await ModelIO.save(loaded.resource, to: output) }
        _ = try await ModelIO.save(loaded.resource, to: output, format: .json)
        #expect(try ModelFormat.detect(contentsOf: output) == .json)
    }

    @Test("a model is rendered as text in a given format")
    func rendersText() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try Self.write(Self.instanceXMI, named: "model.xmi", in: directory)
        let loaded = try await ModelIO.load(
            url: input, resourceSet: ResourceSet(), metamodels: [try Self.metamodelURL()])
        var diagnostics = ConversionDiagnostics()
        let json = try await ModelIO.serialise(loaded.resource, format: .json, diagnostics: &diagnostics)
        #expect(json == (try await JSONSerializer().serialize(loaded.resource)))
        let xmi = try await ModelIO.serialise(loaded.resource, format: .xmi, diagnostics: &diagnostics)
        #expect(xmi == (try await XMISerializer().serialize(loaded.resource)))
        #expect(diagnostics.isEmpty)
    }

    @Test("a model error describes the document involved")
    func errorDescription() {
        let error = ModelIOError.notAMetamodel("model.ecore")
        #expect(error.description.contains("model.ecore"))
        #expect(error.errorDescription == error.description)
    }
}
