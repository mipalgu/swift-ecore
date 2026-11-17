//
// DocumentURIWritingTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for how the writers spell the location of a referenced document: a reference into
/// the written document as a fragment alone, and a reference into another document by its
/// URI, which the default layout can write relative to the written document.
@Suite("Document URI Writing")
struct DocumentURIWritingTests {
    /// The helpers that build the planning metamodel and its documents.
    typealias Planning = MixedReferenceWritingTests

    /// The options of the default layout with the URIs of other documents written relative
    /// to the written document.
    static let legacyRelative: XMISerializationOptions = {
        var options = XMISerializationOptions.legacy
        options.relativeURIs = true
        return options
    }()

    /// A source project and a plan in one resource set, at locations of a test's choosing.
    struct Documents {
        /// The resource set that holds both documents and the metamodel.
        let set: ResourceSet
        /// The source project, whose tasks are titled `source 0` to `source 2`.
        let source: Resource
        /// The plan, whose tasks are titled `plan 0` and `plan 1`.
        let plan: Resource
        /// The identifier of the plan's root project.
        let planRoot: EUUID
        /// The identifiers of the source project's tasks.
        let sourceTasks: [EUUID]
        /// The identifiers of the plan's tasks.
        let planTasks: [EUUID]

        /// A proxy to a task of the source project.
        ///
        /// - Parameter index: The position of the task.
        /// - Returns: The proxy.
        func sourceProxy(_ index: Int) -> ResourceProxy {
            ResourceProxy(uri: source.uri, fragment: "//@tasks.\(index)")
        }

        /// A proxy to a task of the plan itself.
        ///
        /// - Parameter index: The position of the task.
        /// - Returns: The proxy.
        func planProxy(_ index: Int) -> ResourceProxy {
            ResourceProxy(uri: plan.uri, fragment: "//@tasks.\(index)")
        }

        /// Sets a feature of the plan's root project.
        ///
        /// - Parameters:
        ///   - feature: The name of the feature.
        ///   - value: The value.
        func set(_ feature: String, _ value: any EcoreValue) async {
            await plan.eSet(objectId: planRoot, feature: feature, value: value)
        }
    }

    /// Builds a source project with three tasks and a plan with two tasks.
    ///
    /// - Parameters:
    ///   - sourceURI: The URI of the source project.
    ///   - planURI: The URI of the plan.
    /// - Returns: The documents.
    static func makeDocuments(source sourceURI: String, plan planURI: String) async throws -> Documents {
        let set = ResourceSet()
        let package = Planning.makeMetamodel()
        await set.registerMetamodel(package, uri: package.nsURI)
        let source = try await Planning.makeProject(in: set, uri: sourceURI, name: "source", count: 3)
        let plan = try await Planning.makeProject(in: set, uri: planURI, name: "plan", count: 2)
        return Documents(
            set: set, source: source.resource, plan: plan.resource, planRoot: plan.root,
            sourceTasks: source.tasks, planTasks: plan.tasks)
    }

    /// The `href` values of the elements of a feature in an XMI text, in order.
    ///
    /// - Parameters:
    ///   - feature: The name of the feature.
    ///   - text: The XMI document.
    /// - Returns: The values of the `href` attributes.
    static func hrefs(_ feature: String, in text: String) -> [String] {
        let opening = "<\(feature) href=\""
        return text.split(separator: "\n").compactMap { line in
            guard let start = line.range(of: opening) else { return nil }
            let rest = line[start.upperBound...]
            return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
        }
    }

    /// The `$ref` text of a single-valued feature of the root object of a JSON document.
    ///
    /// - Parameters:
    ///   - feature: The name of the feature.
    ///   - text: The JSON document.
    /// - Returns: The reference text.
    static func jsonReference(_ feature: String, in text: String) throws -> String {
        let document = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let entry = try #require(document[feature] as? [String: Any], "\(text)")
        return try #require(entry[JSONSyntax.referenceKey] as? String)
    }

    // MARK: - Same-document proxies

    @Test(
        "the default writer writes a proxy into the written document as a fragment",
        arguments: [XMISerializationOptions.legacy, legacyRelative])
    func legacySameDocumentProxy(options: XMISerializationOptions) async throws {
        let documents = try await Self.makeDocuments(source: Planning.sourceURI, plan: Planning.planURI)
        await documents.set("highlights", [documents.planProxy(1), documents.planProxy(0)])
        await documents.set("lead", documents.planProxy(1))
        let text = try await XMISerializer(options: options).serialize(documents.plan)
        #expect(Self.hrefs("highlights", in: text) == ["#//@tasks.1", "#//@tasks.0"], "\(text)")
        #expect(Self.hrefs("lead", in: text) == ["#//@tasks.1"], "\(text)")
        #expect(!text.contains(Planning.planURI), "\(text)")
    }

    @Test(
        "a proxy into the written document stays a fragment wherever the document is written",
        arguments: [XMISerializationOptions.legacy, legacyRelative, .emf])
    func sameDocumentProxyElsewhere(options: XMISerializationOptions) async throws {
        let documents = try await Self.makeDocuments(source: Planning.sourceURI, plan: Planning.planURI)
        await documents.set("lead", documents.planProxy(1))
        let location = try #require(URL(string: "file:///archive/2026/plan.xmi"))
        let text = try await XMISerializer(options: options).serialize(documents.plan, relativeTo: location)
        #expect(text.contains("\"#//@tasks.1\""), "\(text)")
        #expect(!text.contains("plan.xmi"), "\(text)")
    }

    @Test(
        "the EMF writer writes a proxy into the written document as a fragment",
        arguments: [XMISerializationOptions.emf, Planning.emfHrefs])
    func emfSameDocumentProxy(options: XMISerializationOptions) async throws {
        let documents = try await Self.makeDocuments(source: Planning.sourceURI, plan: Planning.planURI)
        await documents.set("highlights", [documents.planProxy(1), documents.planProxy(0)])
        let text = try await XMISerializer(options: options).serialize(documents.plan)
        if options.attributeStyleReferences {
            #expect(text.contains("highlights=\"#//@tasks.1 #//@tasks.0\""), "\(text)")
        } else {
            #expect(Self.hrefs("highlights", in: text) == ["#//@tasks.1", "#//@tasks.0"], "\(text)")
        }
        #expect(!text.contains(Planning.planURI), "\(text)")
    }

    @Test("the JSON writer writes a proxy into the written document as a fragment")
    func jsonSameDocumentProxy() async throws {
        let documents = try await Self.makeDocuments(source: Planning.sourceURI, plan: Planning.planURI)
        await documents.set("highlights", [documents.planProxy(1), documents.sourceProxy(0)])
        await documents.set("lead", ResourceProxy(uri: documents.plan.uri, fragment: "T-1"))
        let text = try await JSONSerializer().serialize(documents.plan)
        #expect(try Planning.jsonReferences("highlights", in: text) == ["//@tasks.1", "project.xmi#//@tasks.0"])
        #expect(try Self.jsonReference("lead", in: text) == "#T-1")
        #expect(!text.contains("plan.xmi"), "\(text)")
    }

    @Test("a proxy into the written document written as JSON reads back as a reference into the same document")
    func jsonSameDocumentRoundTrip() async throws {
        let documents = try await Self.makeDocuments(source: Planning.sourceURI, plan: Planning.planURI)
        await documents.set("highlights", [documents.planProxy(1), documents.sourceProxy(2)])
        await documents.set("lead", ResourceProxy(uri: documents.plan.uri, fragment: "T-1"))
        let text = try await JSONSerializer().serialize(documents.plan)
        let copyURI = "file:///models/plan-copy.json"
        let copy = try await JSONParser(resourceSet: documents.set).parse(Data(text.utf8), uri: copyURI)
        let root = try #require(await copy.getRootObjects().first as? DynamicEObject)
        let highlights = ValueList.elements(of: root.eGet("highlights"))
        let local = try #require(highlights.first as? ResourceProxy)
        #expect(local.uri == copyURI)
        #expect(try await Planning.titles(of: root.eGet("highlights"), in: copy, set: documents.set) == ["plan 1", "source 2"])
        let lead = try #require(root.eGet("lead") as? ResourceProxy)
        #expect(lead.uri == copyURI)
        #expect(lead.fragment == "T-1")
    }

    @Test(
        "a proxy into the written document reads back as a reference into the copy",
        arguments: [XMISerializationOptions.legacy, legacyRelative])
    func legacySameDocumentRoundTrip(options: XMISerializationOptions) async throws {
        let documents = try await Self.makeDocuments(source: Planning.sourceURI, plan: Planning.planURI)
        await documents.set("highlights", EcoreValueArray([documents.planProxy(1), documents.sourceProxy(2)]))
        await documents.set("lead", documents.planProxy(0))
        let text = try await XMISerializer(options: options).serialize(documents.plan)
        let copy = try await XMIParser(resourceSet: documents.set).parse(text, uri: Planning.copyURI)
        let root = try #require(await copy.getRootObjects().first as? DynamicEObject)
        let local = try #require(ValueList.elements(of: root.eGet("highlights")).first as? ResourceProxy)
        #expect(local.uri == Planning.copyURI, "\(text)")
        #expect(
            try await Planning.titles(of: root.eGet("highlights"), in: copy, set: documents.set)
                == ["plan 1", "source 2"], "\(text)")
        #expect(try await Planning.titles(of: root.eGet("lead"), in: copy, set: documents.set) == ["plan 0"])
        #expect(try await XMISerializer(options: options).serialize(copy) == text)
    }

    // MARK: - Relative URIs in the default layout

    /// Locations of a plan and its source, with the relative URI from the plan to the source.
    static let relativeLocations: [(plan: String, source: String, relative: String)] = [
        ("file:///models/plan.xmi", "file:///models/project.xmi", "project.xmi"),
        ("file:///models/plans/plan.xmi", "file:///models/project.xmi", "../project.xmi"),
        ("file:///models/plan.xmi", "file:///models/sources/project.xmi", "sources/project.xmi"),
        ("file:///work/output/plan.xmi", "file:///work/models/project.xmi", "../models/project.xmi"),
        ("file:///C:/work/output/plan.xmi", "file:///C:/work/models/project.xmi", "../models/project.xmi"),
    ]

    @Test("the default layout writes other documents relative to the written document", arguments: relativeLocations)
    func legacyRelativeLocations(location: (plan: String, source: String, relative: String)) async throws {
        let documents = try await Self.makeDocuments(source: location.source, plan: location.plan)
        await documents.set("highlights", [documents.sourceProxy(2), documents.sourceProxy(0)])
        await documents.set("lead", documents.sourceProxy(1))
        let text = try await XMISerializer(options: Self.legacyRelative).serialize(documents.plan)
        #expect(
            Self.hrefs("highlights", in: text) == [location.relative + "#//@tasks.2", location.relative + "#//@tasks.0"],
            "\(text)")
        #expect(Self.hrefs("lead", in: text) == [location.relative + "#//@tasks.1"], "\(text)")
        #expect(!text.contains("file:"), "\(text)")
    }

    @Test("the default layout writes objects of another resource relative to the written document")
    func legacyRelativeForeignObjects() async throws {
        let documents = try await Self.makeDocuments(
            source: "file:///work/models/project.xmi", plan: "file:///work/output/plan.xmi")
        await documents.set("highlights", [documents.sourceTasks[2], documents.sourceTasks[0]])
        await documents.set("lead", documents.sourceTasks[1])
        let text = try await XMISerializer(options: Self.legacyRelative).serialize(documents.plan)
        #expect(
            Self.hrefs("highlights", in: text) == ["../models/project.xmi#//@tasks.2", "../models/project.xmi#//@tasks.0"],
            "\(text)")
        #expect(Self.hrefs("lead", in: text) == ["../models/project.xmi#//@tasks.1"], "\(text)")
    }

    @Test("the default layout computes relative URIs against the location that is written")
    func legacyRelativeToWrittenLocation() async throws {
        let documents = try await Self.makeDocuments(source: "file:///work/models/project.xmi", plan: Planning.planURI)
        await documents.set("lead", documents.sourceProxy(1))
        await documents.set("highlights", [documents.sourceTasks[0]])
        let location = try #require(URL(string: "file:///work/output/plan.xmi"))
        let text = try await XMISerializer(options: Self.legacyRelative).serialize(documents.plan, relativeTo: location)
        #expect(Self.hrefs("lead", in: text) == ["../models/project.xmi#//@tasks.1"], "\(text)")
        #expect(Self.hrefs("highlights", in: text) == ["../models/project.xmi#//@tasks.0"], "\(text)")
    }

    @Test("relative URIs keep the layout of the default writer")
    func legacyRelativeKeepsLayout() async throws {
        let documents = try await Self.makeDocuments(source: Planning.sourceURI, plan: Planning.planURI)
        await documents.set(
            "highlights",
            EcoreValueArray([
                documents.planTasks[1], documents.sourceProxy(2), documents.planTasks[0], documents.sourceProxy(0),
            ]))
        await documents.set("lead", documents.sourceTasks[1])
        let legacy = try await XMISerializer().serialize(documents.plan)
        let relative = try await XMISerializer(options: Self.legacyRelative).serialize(documents.plan)
        #expect(relative == legacy.replacingOccurrences(of: Planning.sourceURI, with: "project.xmi"), "\(relative)")
        #expect(XMISerializationOptions(relativeURIs: true) == Self.legacyRelative)
        #expect(XMISerializationOptions.legacy.relativeURIs == false)
    }

    @Test("the default layout writes a mixed reference with fragments and relative URIs in order")
    func legacyRelativeMixed() async throws {
        let documents = try await Self.makeDocuments(source: Planning.sourceURI, plan: Planning.planURI)
        await documents.set(
            "highlights",
            EcoreValueArray([
                documents.planTasks[1], documents.sourceProxy(2), documents.planProxy(0), documents.sourceTasks[0],
            ]))
        let text = try await XMISerializer(options: Self.legacyRelative).serialize(documents.plan)
        #expect(
            Self.hrefs("highlights", in: text) == [
                "#//@tasks.1", "project.xmi#//@tasks.2", "#//@tasks.0", "project.xmi#//@tasks.0",
            ], "\(text)")
    }

    /// Locations of other documents that cannot be written relative to `file:///C:/work/plan.xmi`.
    static let absoluteLocations = [
        "http://www.example.org/models/project.xmi",
        "file://server/models/project.xmi",
        "urn:example:project",
        "file:///D:/models/project.xmi",
    ]

    @Test("the default layout keeps a URI that cannot be made relative", arguments: absoluteLocations)
    func legacyRelativeKeepsAbsolute(uri: String) async throws {
        let documents = try await Self.makeDocuments(source: Planning.sourceURI, plan: "file:///C:/work/plan.xmi")
        await documents.set("lead", ResourceProxy(uri: uri, fragment: "//@tasks.1"))
        await documents.set("highlights", [ResourceProxy(uri: uri, fragment: "//@tasks.0")])
        let text = try await XMISerializer(options: Self.legacyRelative).serialize(documents.plan)
        #expect(Self.hrefs("lead", in: text) == [uri + "#//@tasks.1"], "\(text)")
        #expect(Self.hrefs("highlights", in: text) == [uri + "#//@tasks.0"], "\(text)")
    }

    @Test("the default layout keeps the URIs of other documents when the written location is unknown")
    func legacyRelativeWithoutLocation() async throws {
        let set = ResourceSet()
        let package = Planning.makeMetamodel()
        await set.registerMetamodel(package, uri: package.nsURI)
        let source = try await Planning.makeProject(in: set, uri: Planning.sourceURI, name: "source", count: 2)
        let plan = try await Planning.makeProject(in: set, uri: Resource().uri, name: "plan", count: 1)
        await plan.resource.eSet(
            objectId: plan.root, feature: "lead", value: ResourceProxy(uri: Planning.sourceURI, fragment: "//@tasks.1"))
        await plan.resource.eSet(objectId: plan.root, feature: "highlights", value: [source.tasks[0]])
        let text = try await XMISerializer(options: Self.legacyRelative).serialize(plan.resource)
        #expect(Self.hrefs("lead", in: text) == [Planning.sourceURI + "#//@tasks.1"], "\(text)")
        #expect(Self.hrefs("highlights", in: text) == [Planning.sourceURI + "#//@tasks.0"], "\(text)")
    }

    // MARK: - Round trips through files

    /// The layouts of the files of a round trip, relative to a temporary directory.
    static let fileLayouts: [(plan: String, source: String)] = [
        ("models/plan.xmi", "models/project.xmi"),
        ("models/plans/plan.xmi", "models/project.xmi"),
        ("models/plan.xmi", "models/sources/project.xmi"),
        ("output/plan.xmi", "models/project.xmi"),
    ]

    @Test(
        "a plan saved with relative URIs holds no absolute path and loads back to the source tasks",
        arguments: fileLayouts)
    func fileRoundTrip(layout: (plan: String, source: String)) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("document-uris-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent(layout.source)
        let planURL = root.appendingPathComponent(layout.plan)
        for url in [sourceURL, planURL] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        let documents = try await Self.makeDocuments(
            source: URIReference.canonicalise(sourceURL.absoluteString),
            plan: URIReference.canonicalise(planURL.absoluteString))
        await documents.set(
            "highlights", EcoreValueArray([documents.sourceProxy(2), documents.planTasks[1], documents.sourceTasks[0]]))
        await documents.set("lead", documents.sourceProxy(1))
        var diagnostics = ConversionDiagnostics()
        try await ModelIO.save(documents.source, to: sourceURL, diagnostics: &diagnostics)
        try await ModelIO.save(documents.plan, to: planURL, xmiOptions: Self.legacyRelative, diagnostics: &diagnostics)

        let text = try String(contentsOf: planURL, encoding: .utf8)
        #expect(!text.contains("file:"), "\(text)")
        #expect(!text.contains(root.path), "\(text)")
        #expect(!text.contains(root.resolvingSymlinksInPath().path), "\(text)")

        let set = ResourceSet()
        let package = Planning.makeMetamodel()
        await set.registerMetamodel(package, uri: package.nsURI)
        let loaded = try await ModelIO.load(url: planURL, resourceSet: set)
        let project = try #require(await loaded.resource.getRootObjects().first as? DynamicEObject)
        #expect(
            try await Planning.titles(of: project.eGet("highlights"), in: loaded.resource, set: set)
                == ["source 2", "plan 1", "source 0"], "\(text)")
        #expect(try await Planning.titles(of: project.eGet("lead"), in: loaded.resource, set: set) == ["source 1"])
    }

    @Test("a resource set saves a resource with relative URIs in the default layout")
    func resourceSetSave() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("document-uris-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sourceURI = URIReference.canonicalise(root.appendingPathComponent("models/project.xmi").absoluteString)
        let planURL = output.appendingPathComponent("plan.xmi")
        let documents = try await Self.makeDocuments(source: sourceURI, plan: Planning.planURI)
        await documents.set("lead", documents.sourceProxy(1))
        try await documents.set.save(
            documents.plan, to: URIReference.canonicalise(planURL.absoluteString), options: Self.legacyRelative)
        let text = try String(contentsOf: planURL, encoding: .utf8)
        #expect(Self.hrefs("lead", in: text) == ["../models/project.xmi#//@tasks.1"], "\(text)")
    }
}
