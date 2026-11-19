//
// SaveAsTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for giving a resource a new URI and for saving a resource as a document that it then
/// stands for.
///
/// Changing the URI of a resource moves it within its resource set: the set finds it under
/// the new URI only, references to it from other resources of the set are written against
/// the new location, and its own references to other documents are written relative to the
/// new location. Saving as a document writes the document and then gives the resource the
/// URI of the document, whereas saving a copy leaves the URI of the resource as it was.
@Suite("Save As")
struct SaveAsTests {
    /// The helpers that build the planning metamodel and its documents.
    typealias Planning = MixedReferenceWritingTests

    /// The writers and the layouts in which they write references.
    typealias Writer = WrittenLocationURITests.Writer

    /// The helpers that build documents at locations of a test's choosing.
    typealias Located = WrittenLocationURITests

    /// The URI of the referenced document, as ``WrittenLocationURITests`` builds it.
    static let tasksURI = Located.tasksURI

    /// The URI of the referring document, as ``WrittenLocationURITests`` builds it.
    static let notesURI = Located.notesURI

    /// The URI that the referring document is moved to, two directories below its own.
    static let archivedNotesURI = "file:///work/archive/2026/notes.xmi"

    /// The URI that the referenced document is moved to.
    static let archivedTasksURI = "file:///work/archive/tasks.xmi"

    /// The identifier of the root object of a resource.
    ///
    /// - Parameter resource: The resource.
    /// - Returns: The identifier of its first root object.
    static func root(of resource: Resource) async throws -> EUUID {
        try #require(await resource.getRootObjects().first).id
    }

    /// Sets a feature of the root object of the referenced document.
    ///
    /// - Parameters:
    ///   - feature: The name of the feature.
    ///   - value: The value.
    ///   - documents: The documents.
    static func setSource(
        _ feature: String, _ value: any EcoreValue, in documents: DocumentURIWritingTests.Documents
    ) async throws {
        let root = try await root(of: documents.source)
        await documents.source.eSet(objectId: root, feature: feature, value: value)
    }

    /// Makes the referenced document refer back to the referring one.
    ///
    /// `lead` holds a proxy to task 1 of the referring document under its URI. `highlights`
    /// holds, in this order, task 0 of the referring document, a proxy to its task 1, and
    /// task 2 of the referenced document itself.
    ///
    /// - Parameter documents: The documents.
    static func referBack(in documents: DocumentURIWritingTests.Documents) async throws {
        try await setSource("lead", documents.planProxy(1), in: documents)
        try await setSource(
            "highlights", EcoreValueArray([documents.planTasks[0], documents.planProxy(1), documents.sourceTasks[2]]),
            in: documents)
    }

    /// Checks the references of a referenced document that refers back to the referring one.
    ///
    /// - Parameters:
    ///   - text: The referenced document as written.
    ///   - writer: The writer that wrote it.
    ///   - location: The expected spelling of the URI of the referring document.
    static func expectBackReferences(in text: String, of writer: Writer, to location: String) throws {
        #expect(try writer.references("lead", in: text) == [location + "#//@tasks.1"], "\(text)")
        #expect(
            try writer.references("highlights", in: text) == [
                location + "#//@tasks.0", location + "#//@tasks.1", writer.local(2),
            ], "\(text)")
    }

    // MARK: - Changing the URI

    @Test("a resource with a new URI is found in its resource set under that URI only")
    func lookUpUnderNewURI() async throws {
        let documents = try await Located.makeDocuments()
        let before = await documents.set.getResources()
        try await documents.plan.setURI(Self.archivedNotesURI)

        #expect(documents.plan.uri == Self.archivedNotesURI)
        #expect(await documents.set.getResource(uri: Self.archivedNotesURI) === documents.plan)
        let after = await documents.set.getResources()
        #expect(after.map(ObjectIdentifier.init) == before.map(ObjectIdentifier.init))
        #expect(after.map(\.uri) == [Self.tasksURI, Self.archivedNotesURI])
        #expect(await documents.set.count() == 2)
        #expect(await documents.set.removeResource(uri: Self.notesURI) == false)
    }

    @Test("a new URI is canonicalised as the resource set canonicalises the URIs of its resources")
    func canonicalNewURI() async throws {
        let documents = try await Located.makeDocuments()
        let spelt = "file:///work/archive/./2026/../2026/notes.xmi"
        try await documents.plan.setURI(spelt)
        #expect(documents.plan.uri == URIReference.canonicalise(spelt))
        #expect(await documents.set.getResource(uri: spelt) === documents.plan)
    }

    @Test("giving a resource the URI of another resource of its set is an error that changes nothing")
    func uriInUse() async throws {
        let documents = try await Located.makeDocuments()
        await #expect(throws: ResourceSetError.uriInUse(Self.tasksURI)) {
            try await documents.plan.setURI(Self.tasksURI)
        }
        #expect(documents.plan.uri == Self.notesURI)
        #expect(documents.source.uri == Self.tasksURI)
        #expect(await documents.set.getResource(uri: Self.notesURI) === documents.plan)
        #expect(await documents.set.getResource(uri: Self.tasksURI) === documents.source)
    }

    @Test("the error for a URI in use names the URI")
    func uriInUseDescription() {
        let error = ResourceSetError.uriInUse(Self.tasksURI)
        #expect(error.description.contains(Self.tasksURI))
        #expect(error.errorDescription == error.description)
    }

    @Test("giving a resource its own URI changes nothing")
    func ownURI() async throws {
        let documents = try await Located.makeDocuments()
        try await documents.plan.setURI(Self.notesURI)
        try await documents.plan.setURI("file:///work/output/./notes.xmi")
        #expect(documents.plan.uri == Self.notesURI)
        #expect(await documents.set.getResource(uri: Self.notesURI) === documents.plan)
        #expect(await documents.set.count() == 2)
    }

    @Test("a resource can be given its previous URI again")
    func renameBack() async throws {
        let documents = try await Located.makeDocuments()
        try await documents.plan.setURI(Self.archivedNotesURI)
        try await documents.plan.setURI(Self.notesURI)
        #expect(documents.plan.uri == Self.notesURI)
        #expect(await documents.set.getResources().map(\.uri) == [Self.tasksURI, Self.notesURI])
        let text = try await Writer.legacyRelative.render(documents.plan, at: nil)
        try Located.expectReferences(in: text, of: .legacyRelative, to: "../models/tasks.xmi")
    }

    @Test("the old URI of a resource is free for another resource")
    func oldURIFree() async throws {
        let documents = try await Located.makeDocuments()
        try await documents.plan.setURI(Self.archivedNotesURI)
        let newcomer = await documents.set.createResource(uri: Self.notesURI)
        #expect(newcomer !== documents.plan)
        #expect(await documents.set.count() == 3)
    }

    @Test("a resource outside a resource set takes any URI")
    func withoutResourceSet() async throws {
        let resource = Resource(uri: Self.notesURI)
        let package = Planning.makeMetamodel()
        let taskClass = try #require(package.getEClass("Task"))
        let projectClass = try #require(package.getEClass("Project"))
        let task = DynamicEObject(eClass: taskClass)
        var project = DynamicEObject(eClass: projectClass)
        project.eSet("tasks", value: [task.id])
        project.eSet("lead", value: ResourceProxy(uri: Self.notesURI, fragment: "//@tasks.0"))
        await resource.register(task)
        await resource.add(project)

        try await resource.setURI(Self.archivedNotesURI)
        #expect(resource.uri == Self.archivedNotesURI)
        let lead = try #require(await resource.eGet(objectId: project.id, feature: "lead") as? ResourceProxy)
        #expect(lead == ResourceProxy(uri: Self.archivedNotesURI, fragment: "//@tasks.0"))
    }

    @Test("objects keep their identity and fragments under a new URI")
    func identityAndFragments() async throws {
        let documents = try await Located.makeDocuments()
        let objects = await documents.plan.getAllObjects().map(\.id)
        try await documents.plan.setURI(Self.archivedNotesURI)

        #expect(await documents.plan.getAllObjects().map(\.id) == objects)
        for (index, task) in documents.planTasks.enumerated() {
            #expect(await XPathResolver(resource: documents.plan).resolve("#//@tasks.\(index)") == task)
            let proxy = ResourceProxy(uri: Self.archivedNotesURI, fragment: "//@tasks.\(index)")
            #expect(await proxy.resolve(in: documents.set) == task)
            #expect(await documents.set.resolve(task)?.resource === documents.plan)
        }
    }

    @Test("proxies of the resource set to the old URI refer to the resource under its new URI")
    func proxiesFollow() async throws {
        let documents = try await Located.makeDocuments()
        try await Self.referBack(in: documents)
        try await documents.plan.setURI(Self.archivedNotesURI)

        let sourceRoot = try await Self.root(of: documents.source)
        let lead = try #require(await documents.source.eGet(objectId: sourceRoot, feature: "lead") as? ResourceProxy)
        #expect(lead == ResourceProxy(uri: Self.archivedNotesURI, fragment: "//@tasks.1"))
        #expect(await lead.resolve(in: documents.set) == documents.planTasks[1])
        let highlights = ValueList.elements(of: await documents.source.eGet(objectId: sourceRoot, feature: "highlights"))
        #expect(highlights.count == 3)
        #expect(highlights[0] as? EUUID == documents.planTasks[0])
        #expect(highlights[1] as? ResourceProxy == ResourceProxy(uri: Self.archivedNotesURI, fragment: "//@tasks.1"))
        #expect(highlights[2] as? EUUID == documents.sourceTasks[2])
        #expect(await documents.set.count() == 2)
    }

    @Test("a list of proxies to the old URI keeps its form under the new URI")
    func proxyListsFollow() async throws {
        let documents = try await Located.makeDocuments()
        try await Self.setSource("highlights", [documents.planProxy(0), documents.sourceProxy(1)], in: documents)
        try await documents.plan.setURI(Self.archivedNotesURI)

        let sourceRoot = try await Self.root(of: documents.source)
        let highlights = try #require(
            await documents.source.eGet(objectId: sourceRoot, feature: "highlights") as? [ResourceProxy])
        #expect(highlights == [ResourceProxy(uri: Self.archivedNotesURI, fragment: "//@tasks.0"), documents.sourceProxy(1)])
    }

    @Test(
        "other resources of the set refer to a resource at its new location when they are written",
        arguments: Writer.allCases)
    func otherResourcesFollow(writer: Writer) async throws {
        let documents = try await Located.makeDocuments()
        try await Self.referBack(in: documents)
        let before = try await writer.render(documents.source, at: nil)
        try Self.expectBackReferences(in: before, of: writer, to: "../output/notes.xmi")

        try await documents.plan.setURI(Self.archivedNotesURI)
        let text = try await writer.render(documents.source, at: nil)
        try Self.expectBackReferences(in: text, of: writer, to: "../archive/2026/notes.xmi")
    }

    @Test("the default layout without relative URIs refers to a resource by its new absolute URI")
    func otherResourcesFollowAbsolute() async throws {
        let documents = try await Located.makeDocuments()
        try await Self.referBack(in: documents)
        try await documents.plan.setURI(Self.archivedNotesURI)
        let text = try await XMISerializer().serialize(documents.source)
        #expect(
            DocumentURIWritingTests.hrefs("highlights", in: text) == [
                Self.archivedNotesURI + "#//@tasks.0", Self.archivedNotesURI + "#//@tasks.1", "#//@tasks.2",
            ], "\(text)")
        #expect(!text.contains(Self.notesURI), "\(text)")
    }

    @Test(
        "a resource with a new URI refers to other documents relative to its new location",
        arguments: Writer.allCases)
    func outgoingReferencesFollow(writer: Writer) async throws {
        let documents = try await Located.makeDocuments()
        try await documents.plan.setURI(Self.archivedNotesURI)
        let text = try await writer.render(documents.plan, at: nil)
        try Located.expectReferences(in: text, of: writer, to: "../../models/tasks.xmi")
    }

    // MARK: - Saving as a document

    /// The ways of saving a resource as a document that it then stands for.
    enum SaveAs: String, CaseIterable, Sendable {
        /// ``ModelIO/saveAs(_:to:format:xmiOptions:registry:diagnostics:)``.
        case modelIO
        /// ``ModelIO/saveAs(_:to:format:xmiOptions:registry:encoding:diagnostics:)``.
        case modelIOEncoded
        /// ``ResourceSet/saveAs(_:to:options:)`` and ``ResourceSet/saveJSONAs(_:to:)``.
        case resourceSet

        /// Saves a resource as a document.
        ///
        /// - Parameters:
        ///   - resource: The resource to save.
        ///   - url: The location of the document.
        ///   - writer: The writer of the document.
        func save(_ resource: Resource, to url: URL, with writer: Writer) async throws {
            var diagnostics = ConversionDiagnostics()
            switch self {
            case .modelIO:
                try await ModelIO.saveAs(resource, to: url, xmiOptions: writer.xmiOptions, diagnostics: &diagnostics)
            case .modelIOEncoded:
                try await ModelIO.saveAs(
                    resource, to: url, xmiOptions: writer.xmiOptions, encoding: .utf8, diagnostics: &diagnostics)
            case .resourceSet:
                let set = try #require(await resource.resourceSet)
                if writer == .json {
                    try await set.saveJSONAs(resource, to: Located.uri(of: url))
                } else {
                    try await set.saveAs(resource, to: Located.uri(of: url), options: writer.xmiOptions)
                }
            }
        }
    }

    /// Documents in a temporary directory, with the referenced one saved at its URI.
    struct SavedDocuments {
        /// The temporary directory.
        let root: URL
        /// The documents.
        let documents: DocumentURIWritingTests.Documents
    }

    /// Builds the documents in a temporary directory and saves the referenced one.
    ///
    /// - Returns: The documents and their directory.
    static func makeSavedDocuments() async throws -> SavedDocuments {
        let root = try Located.temporaryDirectory()
        let tasksURL = root.appendingPathComponent("models/tasks.xmi")
        let notesURL = root.appendingPathComponent("output/notes.xmi")
        for url in [tasksURL, notesURL] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let documents = try await Located.makeDocuments(tasks: Located.uri(of: tasksURL), notes: Located.uri(of: notesURL))
        var diagnostics = ConversionDiagnostics()
        try await ModelIO.save(documents.source, to: tasksURL, diagnostics: &diagnostics)
        return SavedDocuments(root: root, documents: documents)
    }

    @Test(
        "saving as a document writes it relative to its location and gives the resource its URI",
        arguments: SaveAs.allCases, Writer.allCases)
    func saveAs(saving: SaveAs, writer: Writer) async throws {
        let saved = try await Self.makeSavedDocuments()
        defer { try? FileManager.default.removeItem(at: saved.root) }
        let documents = saved.documents
        let url = saved.root.appendingPathComponent("archive/2026/notes." + writer.fileExtension)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        try await saving.save(documents.plan, to: url, with: writer)
        let uri = Located.uri(of: url)
        #expect(documents.plan.uri == uri)
        #expect(await documents.set.getResource(uri: uri) === documents.plan)
        #expect(await documents.set.getResources().map(\.uri) == [documents.source.uri, uri])

        let text = try String(contentsOf: url, encoding: .utf8)
        try Located.expectReferences(in: text, of: writer, to: "../../models/tasks.xmi")
        #expect(!text.contains(saved.root.path), "\(text)")
        #expect(try await writer.render(documents.plan, at: nil) == writer.render(documents.plan, at: url))
    }

    @Test(
        "a document saved as a new document loads into a fresh resource set as an equal model",
        arguments: SaveAs.allCases, Writer.allCases)
    func saveAsRoundTrip(saving: SaveAs, writer: Writer) async throws {
        let saved = try await Self.makeSavedDocuments()
        defer { try? FileManager.default.removeItem(at: saved.root) }
        let documents = saved.documents
        let url = saved.root.appendingPathComponent("notes." + writer.fileExtension)
        try await saving.save(documents.plan, to: url, with: writer)

        let reading = ResourceSet()
        let metamodel = Planning.makeMetamodel()
        await reading.registerMetamodel(metamodel, uri: metamodel.nsURI)
        let loaded = try await ModelIO.load(url: url, resourceSet: reading)
        #expect(loaded.resource.uri == documents.plan.uri)
        let project = try #require(await loaded.resource.getRootObjects().first as? DynamicEObject)
        #expect(project.eGet("name") as? String == "Plan")
        #expect(try await Planning.titles(of: project.eGet("tasks"), in: loaded.resource, set: reading) == ["plan 0", "plan 1"])
        #expect(try await Planning.titles(of: project.eGet("lead"), in: loaded.resource, set: reading) == ["source 1"])
        #expect(
            try await Planning.titles(of: project.eGet("highlights"), in: loaded.resource, set: reading)
                == ["plan 1", "source 2", "source 0", "plan 0"])
    }

    @Test(
        "documents of the set saved after a save as refer to the new document",
        arguments: SaveAs.allCases, Writer.allCases)
    func othersSavedAfterSaveAs(saving: SaveAs, writer: Writer) async throws {
        let saved = try await Self.makeSavedDocuments()
        defer { try? FileManager.default.removeItem(at: saved.root) }
        let documents = saved.documents
        try await Self.referBack(in: documents)
        let url = saved.root.appendingPathComponent("archive/notes.xmi")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await saving.save(documents.plan, to: url, with: writer == .json ? .emf : writer)

        let tasksURL = try #require(URL(string: documents.source.uri))
        var diagnostics = ConversionDiagnostics()
        try await ModelIO.save(documents.source, to: tasksURL, xmiOptions: writer.xmiOptions, diagnostics: &diagnostics)
        let text = try String(contentsOf: tasksURL, encoding: .utf8)
        let xmiWriter = writer == .json ? Writer.emf : writer
        try Self.expectBackReferences(in: text, of: xmiWriter, to: "../archive/notes.xmi")

        let reading = ResourceSet()
        let metamodel = Planning.makeMetamodel()
        await reading.registerMetamodel(metamodel, uri: metamodel.nsURI)
        let loaded = try await ModelIO.load(url: tasksURL, resourceSet: reading)
        let project = try #require(await loaded.resource.getRootObjects().first as? DynamicEObject)
        #expect(try await Planning.titles(of: project.eGet("lead"), in: loaded.resource, set: reading) == ["plan 1"])
        #expect(
            try await Planning.titles(of: project.eGet("highlights"), in: loaded.resource, set: reading)
                == ["plan 0", "plan 1", "source 2"])
    }

    @Test("saving a copy leaves the URI of the resource as it was", arguments: Writer.allCases)
    func saveCopy(writer: Writer) async throws {
        let saved = try await Self.makeSavedDocuments()
        defer { try? FileManager.default.removeItem(at: saved.root) }
        let documents = saved.documents
        let uri = documents.plan.uri
        let url = saved.root.appendingPathComponent("copy." + writer.fileExtension)
        for entryPoint in WrittenLocationURITests.EntryPoint.allCases {
            _ = try await entryPoint.write(documents.plan, to: url, with: writer)
            #expect(documents.plan.uri == uri, "\(entryPoint)")
        }
        #expect(await documents.set.getResource(uri: uri) === documents.plan)
    }

    @Test("saving as a document of another resource of the set writes nothing and changes nothing", arguments: SaveAs.allCases)
    func saveAsOverOther(saving: SaveAs) async throws {
        let saved = try await Self.makeSavedDocuments()
        defer { try? FileManager.default.removeItem(at: saved.root) }
        let documents = saved.documents
        let tasksURL = try #require(URL(string: documents.source.uri))
        let original = try Data(contentsOf: tasksURL)
        let notesURI = documents.plan.uri

        await #expect(throws: ResourceSetError.uriInUse(documents.source.uri)) {
            try await saving.save(documents.plan, to: tasksURL, with: .emf)
        }
        #expect(try Data(contentsOf: tasksURL) == original)
        #expect(documents.plan.uri == notesURI)
        #expect(await documents.set.getResource(uri: notesURI) === documents.plan)
    }

    @Test("a save as whose document cannot be written leaves the URI unchanged", arguments: SaveAs.allCases)
    func failedWrite(saving: SaveAs) async throws {
        let saved = try await Self.makeSavedDocuments()
        defer { try? FileManager.default.removeItem(at: saved.root) }
        let documents = saved.documents
        let notesURI = documents.plan.uri
        let url = saved.root.appendingPathComponent("missing/directory/notes.xmi")

        await #expect(throws: (any Error).self) {
            try await saving.save(documents.plan, to: url, with: .emf)
        }
        #expect(documents.plan.uri == notesURI)
        #expect(await documents.set.getResource(uri: notesURI) === documents.plan)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("a save as whose document cannot be rendered leaves the URI unchanged")
    func failedRendering() async throws {
        let saved = try await Self.makeSavedDocuments()
        defer { try? FileManager.default.removeItem(at: saved.root) }
        let documents = saved.documents
        let notesURI = documents.plan.uri
        let url = saved.root.appendingPathComponent("notes.ecore")
        var diagnostics = ConversionDiagnostics()

        await #expect(throws: ModelIOError.self) {
            try await ModelIO.saveAs(documents.plan, to: url, diagnostics: &diagnostics)
        }
        #expect(documents.plan.uri == notesURI)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// A URI handler that refuses to write.
    struct RefusingHandler: URIHandler {
        /// The failure that the handler reports.
        struct Refusal: Error {}

        func canHandle(_ uri: String) -> Bool { true }
        func read(_ uri: String) async throws -> Data { throw Refusal() }
        func write(_ data: Data, to uri: String) async throws { throw Refusal() }
        func exists(_ uri: String) async -> Bool { false }
    }

    @Test("a save as through a URI handler that fails leaves the URI unchanged", arguments: [Writer.emf, .json])
    func failedHandler(writer: Writer) async throws {
        let documents = try await Located.makeDocuments()
        await documents.set.setURIHandlers([RefusingHandler()])
        let uri = "memory:/notes." + writer.fileExtension

        await #expect(throws: URIHandlerError.self) {
            if writer == .json {
                try await documents.set.saveJSONAs(documents.plan, to: uri)
            } else {
                try await documents.set.saveAs(documents.plan, to: uri, options: writer.xmiOptions)
            }
        }
        #expect(documents.plan.uri == Self.notesURI)
    }

    @Test("a save as of a resource of another resource set is an error")
    func foreignResource() async throws {
        let documents = try await Located.makeDocuments()
        let other = try await Located.makeDocuments()
        await #expect(throws: ResourceSetError.notInResourceSet(Self.notesURI)) {
            try await other.set.saveAs(documents.plan, to: Self.archivedNotesURI)
        }
        await #expect(throws: ResourceSetError.notInResourceSet(Self.notesURI)) {
            try await other.set.saveJSONAs(documents.plan, to: Self.archivedNotesURI)
        }
        #expect(documents.plan.uri == Self.notesURI)
        #expect(ResourceSetError.notInResourceSet(Self.notesURI).description.contains(Self.notesURI))
    }

    @Test("a resource outside a resource set can be saved as a document")
    func saveAsWithoutResourceSet() async throws {
        let root = try Located.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Planning.makeMetamodel()
        let resource = Resource(uri: "file:///work/unsaved.xmi")
        let projectClass = try #require(package.getEClass("Project"))
        var project = DynamicEObject(eClass: projectClass)
        project.eSet("name", value: "Standalone")
        await resource.add(project)

        let url = root.appendingPathComponent("standalone.xmi")
        var diagnostics = ConversionDiagnostics()
        try await ModelIO.saveAs(resource, to: url, diagnostics: &diagnostics)
        #expect(resource.uri == Located.uri(of: url))
        #expect(try String(contentsOf: url, encoding: .utf8).contains("Standalone"))
    }

    // MARK: - Metamodels and other formats

    /// A metamodel that holds its classes and refers to nothing outside.
    static let shelfEcore = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="shelf" nsURI="http://www.example.org/shelf" nsPrefix="shelf">
          <eClassifiers xsi:type="ecore:EClass" name="Shelf">
            <eStructuralFeatures xsi:type="ecore:EReference" name="items" upperBound="-1" eType="#//Item" containment="true"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Item">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="label" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
          </eClassifiers>
        </ecore:EPackage>

        """

    /// The metamodel formats that are saved as and read back.
    static let writtenMetamodelFormats: [ModelFormat] = [.ecore, .json, .km3, .emof, .emfatic, .xcore, .oclinecore]

    @Test("a metamodel saved as a document in any format takes the URI of the document", arguments: writtenMetamodelFormats)
    func metamodelFormats(format: ModelFormat) async throws {
        let root = try Located.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let shelfURL = root.appendingPathComponent("shelf.ecore")
        try Self.shelfEcore.write(to: shelfURL, atomically: testWritesAtomically, encoding: .utf8)
        let set = ResourceSet()
        let shelf = try await ModelIO.load(url: shelfURL, resourceSet: set)

        let url = root.appendingPathComponent("converted/shelf." + format.fileExtension)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var diagnostics = ConversionDiagnostics()
        try await ModelIO.saveAs(shelf.resource, to: url, format: format, diagnostics: &diagnostics)
        #expect(shelf.resource.uri == Located.uri(of: url))
        #expect(await set.getResource(uri: Located.uri(of: url)) === shelf.resource)

        let loaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        let package = try #require(await loaded.resource.getRootObjects().first as? EPackage)
        #expect(package.name == "shelf")
        #expect(Set(package.eClassifiers.map(\.name)) == ["Shelf", "Item"])
    }

    /// Writes the shop and base metamodels of ``WrittenLocationURITests`` and loads the shop.
    ///
    /// - Parameter root: The directory to write them to.
    /// - Returns: The resource set and the resources of the shop and the base metamodel.
    static func loadShop(in root: URL) async throws -> (set: ResourceSet, shop: Resource, base: Resource) {
        let baseURL = root.appendingPathComponent("base/base.ecore")
        let shopURL = root.appendingPathComponent("models/shop.ecore")
        for (url, text) in [(baseURL, Located.baseEcore), (shopURL, Located.shopEcore)] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: testWritesAtomically, encoding: .utf8)
        }
        let set = ResourceSet()
        let shop = try await ModelIO.load(url: shopURL, resourceSet: set)
        let base = try #require(await set.getResource(uri: Located.uri(of: baseURL)))
        return (set, shop.resource, base)
    }

    @Test(
        "a metamodel saved as a document refers to other documents relative to its new location",
        arguments: [ModelFormat.ecore, .json])
    func metamodelOutgoing(format: ModelFormat) async throws {
        let root = try Located.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let loaded = try await Self.loadShop(in: root)
        let url = root.appendingPathComponent("shop." + format.rawValue)
        var diagnostics = ConversionDiagnostics()
        try await ModelIO.saveAs(loaded.shop, to: url, diagnostics: &diagnostics)

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.components(separatedBy: "base/base.ecore#//Item").count - 1 == 2, "\(text)")
        #expect(!text.contains("../base/base.ecore"), "\(text)")
        let rendered = try await ModelIO.serialise(loaded.shop, format: format, diagnostics: &diagnostics)
        #expect(rendered == text)
    }

    @Test(
        "a metamodel refers to another metamodel at the location that the other was saved as",
        arguments: [ModelFormat.ecore, .json])
    func metamodelIncoming(format: ModelFormat) async throws {
        let root = try Located.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let loaded = try await Self.loadShop(in: root)
        let baseURL = root.appendingPathComponent("shared/base.ecore")
        try FileManager.default.createDirectory(at: baseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var diagnostics = ConversionDiagnostics()
        try await ModelIO.saveAs(loaded.base, to: baseURL, diagnostics: &diagnostics)
        #expect(loaded.base.uri == Located.uri(of: baseURL))

        let text = try await ModelIO.serialise(loaded.shop, format: format, diagnostics: &diagnostics)
        #expect(text.components(separatedBy: "../shared/base.ecore#//Item").count - 1 == 2, "\(text)")
        #expect(!text.contains("base/base.ecore"), "\(text)")

        let shopURL = try #require(URL(string: loaded.shop.uri))
        try await ModelIO.save(loaded.shop, to: shopURL, format: .ecore, diagnostics: &diagnostics)
        let reading = ResourceSet()
        let reloaded = try await ModelIO.load(url: shopURL, resourceSet: reading)
        let package = try #require(await reloaded.resource.getRootObjects().first as? EPackage)
        let order = try #require(package.getEClass("Order"))
        let item = try #require(order.getStructuralFeature(name: "item") as? EReference)
        #expect(item.eType.name == "Item")
        #expect(await reading.getResource(uri: Located.uri(of: baseURL)) != nil)
    }

    /// A model format of this test that writes the titles of the tasks of a plan, one per line.
    struct TitleListHandler: WritableModelFormatHandler {
        /// The file extension and identifier of the format.
        static let fileExtension = "titles"

        var identifier: String { Self.fileExtension }
        var name: String { "Title list" }
        var fileExtensions: [String] { [Self.fileExtension] }
        var role: ModelFormatRole { .model }

        func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
            throw ModelFormatError.unsupportedFormat(identifier)
        }

        func write(
            _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
            diagnostics: inout ConversionDiagnostics
        ) async throws -> String {
            var lines: [String] = []
            for case let object as DynamicEObject in await resource.getAllObjects() {
                if let title = object.eGet("title") as? String { lines.append(title) }
            }
            return lines.joined(separator: "\n")
        }
    }

    @Test("a model saved as a document of a registered format takes the URI of the document")
    func registeredFormat() async throws {
        let root = try Located.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = try await Located.makeDocuments()
        let registry = ModelFormatRegistry()
        await registry.register(TitleListHandler())
        let url = root.appendingPathComponent("notes." + TitleListHandler.fileExtension)

        var diagnostics = ConversionDiagnostics()
        try await ModelIO.saveAs(documents.plan, to: url, registry: registry, diagnostics: &diagnostics)
        #expect(documents.plan.uri == Located.uri(of: url))
        #expect(try String(contentsOf: url, encoding: .utf8).split(separator: "\n") == ["plan 0", "plan 1"])
    }

    @Test("a save as in an encoding returns the encoding of the document and takes its URI")
    func encodedSaveAs() async throws {
        let saved = try await Self.makeSavedDocuments()
        defer { try? FileManager.default.removeItem(at: saved.root) }
        let documents = saved.documents
        let url = saved.root.appendingPathComponent("notes-latin.xmi")
        var diagnostics = ConversionDiagnostics()
        let used = try await ModelIO.saveAs(documents.plan, to: url, encoding: .isoLatin1, diagnostics: &diagnostics)
        #expect(used == .isoLatin1)
        #expect(documents.plan.uri == Located.uri(of: url))
        #expect(try String(contentsOf: url, encoding: .isoLatin1).contains("encoding=\"ISO-8859-1\""))
    }
}
