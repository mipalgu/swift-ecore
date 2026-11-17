//
// WrittenLocationURITests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for the location against which the writers make the URIs of other documents relative.
///
/// Every writer, and every entry point that saves or renders a document, writes the URI of
/// another document relative to the location that the document is written to, and relative
/// to the URI of the resource only when no location is given. A reference into the written
/// document stays a fragment wherever the document is written.
@Suite("Written Location URIs")
struct WrittenLocationURITests {
    /// The helpers that build the planning metamodel and its documents.
    typealias Planning = MixedReferenceWritingTests

    /// The helpers that build a source project and a plan at locations of a test's choosing.
    typealias Documents = DocumentURIWritingTests

    /// The URI of the referenced document.
    static let tasksURI = "file:///work/models/tasks.xmi"

    /// The URI of the referring document, which lies in a sibling directory of the referenced one.
    static let notesURI = "file:///work/output/notes.xmi"

    /// A writer and the layout in which it writes references.
    enum Writer: String, CaseIterable, Sendable {
        /// The default XMI layout with relative URIs.
        case legacyRelative
        /// The EMF-style XMI layout, with references as attributes.
        case emf
        /// The EMF-style XMI layout, with references as `href` elements.
        case emfHrefs
        /// The JSON writer.
        case json

        /// The XMI options of the writer, which the JSON writer ignores.
        var xmiOptions: XMISerializationOptions {
            switch self {
            case .legacyRelative: Documents.legacyRelative
            case .emf, .json: .emf
            case .emfHrefs: Planning.emfHrefs
            }
        }

        /// The format of the documents of the writer.
        var format: ModelFormat { self == .json ? .json : .xmi }

        /// The file extension of the documents of the writer.
        var fileExtension: String { format.rawValue }

        /// The reference to a task of the written document, as the writer spells it.
        ///
        /// - Parameter index: The position of the task.
        /// - Returns: The fragment, preceded by `#` in XMI.
        func local(_ index: Int) -> String {
            (self == .json ? "" : "#") + "//@tasks.\(index)"
        }

        /// Renders a resource for a location, or for the URI of the resource.
        ///
        /// - Parameters:
        ///   - resource: The resource to render.
        ///   - location: The location of the document, or `nil` for none.
        /// - Returns: The text of the document.
        func render(_ resource: Resource, at location: URL?) async throws -> String {
            switch (self, location) {
            case (.json, let location?): try await JSONSerializer().serialize(resource, relativeTo: location)
            case (.json, nil): try await JSONSerializer().serialize(resource)
            case (_, let location?): try await XMISerializer(options: xmiOptions).serialize(resource, relativeTo: location)
            case (_, nil): try await XMISerializer(options: xmiOptions).serialize(resource)
            }
        }

        /// The reference texts of a feature of the root object of a written document, in order.
        ///
        /// - Parameters:
        ///   - feature: The name of the feature.
        ///   - text: The document.
        /// - Returns: The references.
        func references(_ feature: String, in text: String) throws -> [String] {
            switch self {
            case .json:
                let document = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
                let value = try #require(document[feature], "\(text)")
                let entries = try (value as? [[String: Any]]) ?? [#require(value as? [String: Any])]
                return try entries.map { try #require($0[JSONSyntax.referenceKey] as? String) }
            case .emf:
                guard let start = text.range(of: " \(feature)=\"") else { return Documents.hrefs(feature, in: text) }
                let rest = text[start.upperBound...]
                let end = try #require(rest.firstIndex(of: "\""))
                return rest[..<end].split(separator: " ").map(String.init)
            case .legacyRelative, .emfHrefs:
                return Documents.hrefs(feature, in: text)
            }
        }
    }

    /// Builds the referenced and the referring document and sets the references of the latter.
    ///
    /// `lead` refers to task 1 of the referenced document through a proxy. `highlights`
    /// holds, in this order, task 1 of the referring document, a proxy to task 2 of the
    /// referenced document, task 0 of the referenced document, and a proxy to task 0 of the
    /// referring document.
    ///
    /// - Parameters:
    ///   - tasks: The URI of the referenced document.
    ///   - notes: The URI of the referring document.
    /// - Returns: The documents.
    static func makeDocuments(tasks: String = tasksURI, notes: String = notesURI) async throws
        -> DocumentURIWritingTests.Documents
    {
        let documents = try await Documents.makeDocuments(source: tasks, plan: notes)
        await documents.set("lead", documents.sourceProxy(1))
        await documents.set(
            "highlights",
            EcoreValueArray([
                documents.planTasks[1], documents.sourceProxy(2), documents.sourceTasks[0], documents.planProxy(0),
            ]))
        return documents
    }

    /// Checks the references of a document written by a writer.
    ///
    /// - Parameters:
    ///   - text: The document.
    ///   - writer: The writer that wrote it.
    ///   - location: The expected spelling of the URI of the referenced document.
    static func expectReferences(in text: String, of writer: Writer, to location: String) throws {
        #expect(try writer.references("lead", in: text) == [location + "#//@tasks.1"], "\(text)")
        #expect(
            try writer.references("highlights", in: text) == [
                writer.local(1), location + "#//@tasks.2", location + "#//@tasks.0", writer.local(0),
            ], "\(text)")
    }

    /// Creates an empty temporary directory.
    ///
    /// - Returns: The directory.
    static func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("written-location-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// The canonical URI of a file.
    ///
    /// - Parameter url: The location of the file.
    /// - Returns: The URI.
    static func uri(of url: URL) -> String {
        URIReference.canonicalise(url.absoluteString)
    }

    // MARK: - Serialisers

    /// Locations to write the referring document to, with the expected spelling of the
    /// referenced document from there; `nil` writes it for the URI of the resource.
    static let locations: [(location: String?, relative: String)] = [
        (nil, "../models/tasks.xmi"),
        ("file:///work/output/notes", "../models/tasks.xmi"),
        ("file:///work/notes", "models/tasks.xmi"),
        ("file:///work/archive/2026/notes", "../../models/tasks.xmi"),
        ("file:///work/models/notes", "tasks.xmi"),
    ]

    @Test(
        "every writer makes the URIs of other documents relative to the location it writes",
        arguments: Writer.allCases, locations)
    func serialiserLocations(writer: Writer, location: (location: String?, relative: String)) async throws {
        let documents = try await Self.makeDocuments()
        let url = try location.location.map { try #require(URL(string: $0 + "." + writer.fileExtension)) }
        let text = try await writer.render(documents.plan, at: url)
        try Self.expectReferences(in: text, of: writer, to: location.relative)
        #expect(!text.contains("file:"), "\(text)")
    }

    @Test("every writer writes for the location of the resource as it writes without a location", arguments: Writer.allCases)
    func ownLocation(writer: Writer) async throws {
        let documents = try await Self.makeDocuments()
        let own = try #require(URL(string: Self.notesURI))
        #expect(try await writer.render(documents.plan, at: own) == writer.render(documents.plan, at: nil))
    }

    /// URIs of referenced documents that cannot be written relative to the written locations.
    static let absoluteTasks = ["http://www.example.org/models/tasks.xmi", "urn:example:tasks"]

    @Test(
        "every writer keeps a URI that cannot be made relative to the location it writes",
        arguments: Writer.allCases, absoluteTasks)
    func absoluteURIs(writer: Writer, tasks: String) async throws {
        let documents = try await Self.makeDocuments(tasks: tasks)
        for location in [nil, "file:///work/notes." + writer.fileExtension] {
            let url = try location.map { try #require(URL(string: $0)) }
            let text = try await writer.render(documents.plan, at: url)
            try Self.expectReferences(in: text, of: writer, to: tasks)
        }
    }

    @Test(
        "every writer keeps the URI of a document on another drive or host than the written location",
        arguments: Writer.allCases)
    func otherDrive(writer: Writer) async throws {
        let tasks = "file:///C:/work/models/tasks.xmi"
        let documents = try await Self.makeDocuments(tasks: tasks, notes: "file:///C:/work/output/notes.xmi")
        let unrendered = try await writer.render(documents.plan, at: nil)
        try Self.expectReferences(in: unrendered, of: writer, to: "../models/tasks.xmi")
        for location in ["file:///D:/notes.", "file://server/work/notes."] {
            let url = try #require(URL(string: location + writer.fileExtension))
            try Self.expectReferences(in: try await writer.render(documents.plan, at: url), of: writer, to: tasks)
        }
        let sameDrive = try #require(URL(string: "file:///c:/work/notes." + writer.fileExtension))
        try Self.expectReferences(in: try await writer.render(documents.plan, at: sameDrive), of: writer, to: "models/tasks.xmi")
    }

    @Test(
        "every writer keeps a reference into the written document a fragment wherever it is written",
        arguments: Writer.allCases)
    func sameDocumentElsewhere(writer: Writer) async throws {
        let documents = try await Self.makeDocuments()
        await documents.set("lead", documents.planProxy(1))
        let url = try #require(URL(string: "file:///work/archive/notes." + writer.fileExtension))
        let text = try await writer.render(documents.plan, at: url)
        #expect(try writer.references("lead", in: text) == [writer.local(1)], "\(text)")
        #expect(!text.contains("notes.xmi"), "\(text)")
    }

    @Test("the JSON writer writes a single object of another document relative to the location it writes")
    func jsonSingleObject() async throws {
        let documents = try await Self.makeDocuments()
        await documents.set("lead", documents.sourceTasks[2])
        let url = try #require(URL(string: "file:///work/notes.json"))
        let text = try await JSONSerializer().serialize(documents.plan, relativeTo: url)
        #expect(try Writer.json.references("lead", in: text) == ["models/tasks.xmi#//@tasks.2"], "\(text)")
    }

    @Test("the JSON writer records what it cannot keep for a location as it does without one")
    func jsonDiagnosticsAtLocation() async throws {
        let documents = try await Self.makeDocuments()
        await documents.set("lead", ResourceProxy(uri: documents.plan.uri, fragment: "//@tasks.7"))
        let url = try #require(URL(string: "file:///work/notes.json"))
        var located = ConversionDiagnostics()
        var unlocated = ConversionDiagnostics()
        _ = try await JSONSerializer().serialize(documents.plan, relativeTo: url, diagnostics: &located)
        _ = try await JSONSerializer().serialize(documents.plan, diagnostics: &unlocated)
        #expect(!located.warnings.isEmpty)
        #expect(located.warnings == unlocated.warnings)
    }

    // MARK: - Entry points

    /// The entry points that render or save a document at a location.
    enum EntryPoint: String, CaseIterable, Sendable {
        /// ``ModelIO/save(_:to:format:xmiOptions:registry:diagnostics:)``.
        case modelIOSave
        /// ``ModelIO/save(_:to:format:xmiOptions:registry:)``.
        case modelIOSaveReturningDiagnostics
        /// ``ModelIO/save(_:to:format:xmiOptions:registry:encoding:diagnostics:)``.
        case modelIOSaveEncoded
        /// ``ModelIO/serialise(_:format:relativeTo:xmiOptions:registry:diagnostics:)``.
        case modelIOSerialise
        /// The `serialize(_:to:)` method of the serialiser.
        case serialiserFile
        /// The save methods of a ``ResourceSet``.
        case resourceSetSave

        /// Writes a resource to a location and returns the text of the document.
        ///
        /// - Parameters:
        ///   - resource: The resource to write.
        ///   - url: The location of the document.
        ///   - writer: The writer of the document.
        /// - Returns: The text of the document.
        func write(_ resource: Resource, to url: URL, with writer: Writer) async throws -> String {
            var diagnostics = ConversionDiagnostics()
            let options = writer.xmiOptions
            switch self {
            case .modelIOSave:
                try await ModelIO.save(resource, to: url, xmiOptions: options, diagnostics: &diagnostics)
            case .modelIOSaveReturningDiagnostics:
                try await ModelIO.save(resource, to: url, xmiOptions: options)
            case .modelIOSaveEncoded:
                let used = try await ModelIO.save(
                    resource, to: url, xmiOptions: options, encoding: .isoLatin1, diagnostics: &diagnostics)
                if used != .utf8 { return try String(contentsOf: url, encoding: .isoLatin1) }
            case .modelIOSerialise:
                return try await ModelIO.serialise(
                    resource, format: writer.format, relativeTo: url, xmiOptions: options, diagnostics: &diagnostics)
            case .serialiserFile:
                if writer == .json {
                    try await JSONSerializer().serialize(resource, to: url)
                } else {
                    try await XMISerializer(options: options).serialize(resource, to: url)
                }
            case .resourceSetSave:
                let set = try #require(await resource.resourceSet)
                if writer == .json {
                    try await set.saveJSON(resource, to: WrittenLocationURITests.uri(of: url))
                } else {
                    try await set.save(resource, to: WrittenLocationURITests.uri(of: url), options: options)
                }
            }
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    @Test(
        "every entry point writes the URIs of other documents relative to the file it writes",
        arguments: EntryPoint.allCases, Writer.allCases)
    func entryPoints(entryPoint: EntryPoint, writer: Writer) async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = try await Self.makeDocuments(
            tasks: Self.uri(of: root.appendingPathComponent("models/tasks.xmi")),
            notes: Self.uri(of: root.appendingPathComponent("output/notes.xmi")))
        let url = root.appendingPathComponent("notes." + writer.fileExtension)
        let text = try await entryPoint.write(documents.plan, to: url, with: writer)
        try Self.expectReferences(in: text, of: writer, to: "models/tasks.xmi")
        #expect(!text.contains(root.path), "\(text)")
    }

    @Test(
        "rendering without a location writes the URIs of other documents relative to the resource",
        arguments: Writer.allCases)
    func renderingWithoutLocation(writer: Writer) async throws {
        let documents = try await Self.makeDocuments()
        var diagnostics = ConversionDiagnostics()
        let text = try await ModelIO.serialise(
            documents.plan, format: writer.format, xmiOptions: writer.xmiOptions, diagnostics: &diagnostics)
        try Self.expectReferences(in: text, of: writer, to: "../models/tasks.xmi")
    }

    // MARK: - Round trips through files

    @Test(
        "a model saved to another directory loads back to the objects it refers to",
        arguments: Writer.allCases)
    func fileRoundTrip(writer: Writer) async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tasksURL = root.appendingPathComponent("models/tasks.xmi")
        let notesURL = root.appendingPathComponent("output/notes.xmi")
        for url in [tasksURL, notesURL] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let documents = try await Self.makeDocuments(tasks: Self.uri(of: tasksURL), notes: Self.uri(of: notesURL))
        var diagnostics = ConversionDiagnostics()
        try await ModelIO.save(documents.source, to: tasksURL, diagnostics: &diagnostics)
        try await ModelIO.save(documents.plan, to: notesURL, xmiOptions: writer.xmiOptions, diagnostics: &diagnostics)

        // Convert the saved model, as a conversion tool does, into a file one directory up.
        let converting = ResourceSet()
        let metamodel = Planning.makeMetamodel()
        await converting.registerMetamodel(metamodel, uri: metamodel.nsURI)
        let loaded = try await ModelIO.load(url: notesURL, resourceSet: converting)
        let convertedURL = root.appendingPathComponent("notes." + writer.fileExtension)
        try await ModelIO.save(loaded.resource, to: convertedURL, xmiOptions: writer.xmiOptions, diagnostics: &diagnostics)
        let text = try String(contentsOf: convertedURL, encoding: .utf8)
        #expect(try writer.references("lead", in: text) == ["models/tasks.xmi#//@tasks.1"], "\(text)")
        #expect(!text.contains("file:"), "\(text)")

        let reading = ResourceSet()
        await reading.registerMetamodel(Planning.makeMetamodel(), uri: metamodel.nsURI)
        let converted = try await ModelIO.load(url: convertedURL, resourceSet: reading)
        let project = try #require(await converted.resource.getRootObjects().first as? DynamicEObject)
        #expect(try await Planning.titles(of: project.eGet("lead"), in: converted.resource, set: reading) == ["source 1"])
        #expect(
            try await Planning.titles(of: project.eGet("highlights"), in: converted.resource, set: reading)
                == ["plan 1", "source 2", "source 0", "plan 0"], "\(text)")
    }

    @Test(
        "a model read from a copy of its directory tree resolves its relative URIs against the copy",
        arguments: Writer.allCases)
    func readingFromCopy(writer: Writer) async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original", isDirectory: true)
        let tasksURL = original.appendingPathComponent("models/tasks.xmi")
        let notesURL = original.appendingPathComponent("output/notes." + writer.fileExtension)
        for url in [tasksURL, notesURL] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let documents = try await Self.makeDocuments(tasks: Self.uri(of: tasksURL), notes: Self.uri(of: notesURL))
        var diagnostics = ConversionDiagnostics()
        try await ModelIO.save(documents.source, to: tasksURL, diagnostics: &diagnostics)
        try await ModelIO.save(documents.plan, to: notesURL, xmiOptions: writer.xmiOptions, diagnostics: &diagnostics)
        let copy = root.appendingPathComponent("copy", isDirectory: true)
        try FileManager.default.copyItem(at: original, to: copy)
        try FileManager.default.removeItem(at: original)

        let reading = ResourceSet()
        let metamodel = Planning.makeMetamodel()
        await reading.registerMetamodel(metamodel, uri: metamodel.nsURI)
        let loaded = try await ModelIO.load(
            url: copy.appendingPathComponent("output/notes." + writer.fileExtension), resourceSet: reading)
        let project = try #require(await loaded.resource.getRootObjects().first as? DynamicEObject)
        let lead = try #require(project.eGet("lead") as? ResourceProxy)
        #expect(lead.uri == Self.uri(of: copy.appendingPathComponent("models/tasks.xmi")))
        #expect(try await Planning.titles(of: project.eGet("lead"), in: loaded.resource, set: reading) == ["source 1"])
        #expect(
            try await Planning.titles(of: project.eGet("highlights"), in: loaded.resource, set: reading)
                == ["plan 1", "source 2", "source 0", "plan 0"])
    }

    // MARK: - Metamodels

    /// A metamodel whose class and an annotation of it refer to a class of another document.
    static let shopEcore = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="shop" nsURI="http://www.example.org/shop" nsPrefix="shop">
          <eClassifiers xsi:type="ecore:EClass" name="Order">
            <eAnnotations source="http://www.example.org/notes" references="../base/base.ecore#//Item"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="item" eType="ecore:EClass ../base/base.ecore#//Item"/>
          </eClassifiers>
        </ecore:EPackage>

        """

    /// The metamodel that the shop metamodel refers to.
    static let baseEcore = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="base" nsURI="http://www.example.org/base" nsPrefix="base">
          <eClassifiers xsi:type="ecore:EClass" name="Item"/>
        </ecore:EPackage>

        """

    @Test(
        "a metamodel saved to another directory refers to other documents relative to the file it writes",
        arguments: [ModelFormat.ecore, .json])
    func metamodelElsewhere(format: ModelFormat) async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let baseURL = root.appendingPathComponent("base/base.ecore")
        let shopURL = root.appendingPathComponent("models/shop.ecore")
        for (url, text) in [(baseURL, Self.baseEcore), (shopURL, Self.shopEcore)] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: testWritesAtomically, encoding: .utf8)
        }
        let set = ResourceSet()
        let shop = try await ModelIO.load(url: shopURL, resourceSet: set)
        let outputURL = root.appendingPathComponent("shop." + format.rawValue)
        var diagnostics = ConversionDiagnostics()
        try await ModelIO.save(shop.resource, to: outputURL, diagnostics: &diagnostics)
        let text = try String(contentsOf: outputURL, encoding: .utf8)
        let spelt = text.components(separatedBy: "base/base.ecore#//Item").count - 1
        #expect(spelt == 2, "\(text)")
        #expect(!text.contains("../base/base.ecore"), "\(text)")
        guard format == .json else { return }
        #expect(try await JSONSerializer().serialize(shop.resource, relativeTo: outputURL) == text)
        #expect(try await JSONSerializer().serialize(shop.resource) == JSONSerializer().serialize(shop.packages))
        let savedURL = root.appendingPathComponent("saved/shop.json")
        try FileManager.default.createDirectory(at: savedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await set.saveJSON(shop.resource, to: Self.uri(of: savedURL))
        #expect(try String(contentsOf: savedURL, encoding: .utf8).contains("\"../base/base.ecore#//Item\""))
        #expect(!text.contains("file:"), "\(text)")
    }
}
