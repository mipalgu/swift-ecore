//
// URIHandlerTests.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// A log of the URIs that a handler was asked for.
private actor ReadLog {
    private(set) var uris: [String] = []
    func record(_ uri: String) { uris.append(uri) }
}

/// The fixture documents of the test bundle.
private enum HandlerFixtures {
    /// The relative paths of every `.ecore` and `.xmi` fixture.
    static func paths() throws -> [String] {
        let root = try ReflectionFixtures.resourcesURL()
        let enumerator = try #require(FileManager.default.enumerator(atPath: root.path))
        return (enumerator.allObjects as! [String]).filter { $0.hasSuffix(".ecore") || $0.hasSuffix(".xmi") }
            .sorted()
    }

    static func url(_ path: String) throws -> URL {
        try ReflectionFixtures.resourcesURL().appendingPathComponent(path)
    }

    static func text(_ path: String) throws -> String {
        try String(contentsOf: try url(path), encoding: .utf8)
    }

    /// An in-memory handler holding the given fixtures under `memory:/` URIs.
    static func memory(_ paths: [String]) throws -> InMemoryURIHandler {
        var texts: [String: String] = [:]
        for path in paths { texts["memory:/\(path)"] = try text(path) }
        return InMemoryURIHandler(texts: texts, scheme: "memory")
    }

    /// The native serialisation of an Ecore document, or the failure.
    static func nativeOutcome(_ load: () async throws -> Resource) async -> String {
        do {
            let resource = try await load()
            guard let package = await resource.getRootObjects().first as? EPackage else { return "no package" }
            return XMISerializer().serialize(package)
        } catch {
            return "error \(type(of: error))"
        }
    }

    /// The dynamic serialisation of a document, or the failure.
    static func dynamicOutcome(_ load: () async throws -> Resource) async -> String {
        do { return try await XMISerializer().serialize(try await load()) } catch {
            return "error \(type(of: error))"
        }
    }
}

@Suite("URI Handler Tests")
struct URIHandlerTests {
    // MARK: - Fixture equivalence

    @Test("every fixture loads from text exactly as from its file")
    func textMatchesFile() async throws {
        for path in try HandlerFixtures.paths() {
            let url = try HandlerFixtures.url(path)
            let uri = URIReference.canonicalise(url.absoluteString)
            let text = try HandlerFixtures.text(path)

            let fromFile = await HandlerFixtures.dynamicOutcome {
                try await XMIParser(resourceSet: ResourceSet()).parse(url)
            }
            let fromText = await HandlerFixtures.dynamicOutcome {
                try await XMIParser(resourceSet: ResourceSet()).parse(text, uri: uri)
            }
            #expect(fromFile == fromText, Comment(rawValue: path))
            let fromData = await HandlerFixtures.dynamicOutcome {
                try await XMIParser(resourceSet: ResourceSet()).parse(Data(text.utf8), uri: uri)
            }
            #expect(fromFile == fromData, Comment(rawValue: path))
            let viaSet = await HandlerFixtures.dynamicOutcome {
                try await ResourceSet().loadXMIResource(text: text, uri: uri)
            }
            #expect(fromFile == viaSet, Comment(rawValue: path))

            if path.hasSuffix(".ecore") {
                let nativeFile = await HandlerFixtures.nativeOutcome {
                    try await ResourceSet().loadEcoreResource(uri: uri)
                }
                let nativeText = await HandlerFixtures.nativeOutcome {
                    try await ResourceSet().loadEcoreResource(text: text, uri: uri)
                }
                #expect(nativeFile == nativeText, Comment(rawValue: path))
            }
        }
    }

    @Test("a package loads from text")
    func packageFromText() async throws {
        let text = try HandlerFixtures.text("metamodels/Families.ecore")
        let uri = URIReference.canonicalise(try HandlerFixtures.url("metamodels/Families.ecore").absoluteString)
        let fromText = try await EPackage(text: text, uri: uri)
        let fromFile = try await EPackage(url: try HandlerFixtures.url("metamodels/Families.ecore"))
        #expect(XMISerializer().serialize(fromText) == XMISerializer().serialize(fromFile))
    }

    // MARK: - Cross-document resolution without a file system

    @Test("cross-document references resolve through an in-memory handler")
    func crossDocumentInMemory() async throws {
        for pair in [
            ("fidelity/consumer.ecore", "fidelity/shared.ecore"),
            ("annotations/annotated.ecore", "annotations/annotated-other.ecore"),
        ] {
            let memory = try HandlerFixtures.memory([pair.0, pair.1])
            let memorySet = ResourceSet()
            await memorySet.setURIHandlers([memory])
            let fromMemory = await HandlerFixtures.nativeOutcome {
                try await memorySet.loadEcoreResource(uri: "memory:/\(pair.0)")
            }
            let fromDisk = await HandlerFixtures.nativeOutcome {
                try await ResourceSet().loadEcoreResource(
                    uri: URIReference.canonicalise(try HandlerFixtures.url(pair.0).absoluteString))
            }
            let loaded = !fromMemory.hasPrefix("error") && fromMemory != "no package"
            #expect(loaded, Comment(rawValue: pair.0))
            // The documents differ only in where they are, so references are written the same way.
            #expect(fromMemory == fromDisk, Comment(rawValue: pair.0))
            #expect(await memorySet.getResource(uri: "memory:/\(pair.1)") != nil)
        }
    }

    @Test("a referenced document is read through the handler")
    func referencedDocumentRead() async throws {
        let log = ReadLog()
        let memory = try HandlerFixtures.memory(["fidelity/consumer.ecore", "fidelity/shared.ecore"])
        let handler = ClosureURIHandler(
            canHandle: { $0.hasPrefix("memory:") },
            read: { uri in
                await log.record(uri)
                return try await memory.read(uri)
            })
        let set = ResourceSet()
        await set.setURIHandlers([handler])
        let resource = try await set.loadEcoreResource(uri: "memory:/fidelity/consumer.ecore")
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        #expect(package.eClassifiers.count == 1)
        #expect(await log.uris == ["memory:/fidelity/consumer.ecore", "memory:/fidelity/shared.ecore"])
    }

    @Test("an XMI document that refers to another loads it through the handler")
    func xmiReferencedDocument() async throws {
        let paths = ["xmi/company-a.xmi", "xmi/department-b.xmi"]
        let memory = try HandlerFixtures.memory(paths)
        let set = ResourceSet()
        await set.setURIHandlers([memory])
        let loaded = try await set.loadReferencedResource(uri: "memory:/xmi/department-b.xmi")
        #expect(loaded.uri == "memory:/xmi/department-b.xmi")
        #expect(await set.getResource(uri: "memory:/xmi/department-b.xmi") != nil)
    }

    // MARK: - Errors

    @Test("a throwing handler surfaces as a load error carrying the URI")
    func throwingHandler() async {
        struct Failure: Error {}
        let set = ResourceSet()
        await set.setURIHandlers([ClosureURIHandler(read: { _ in throw Failure() })])
        await #expect(throws: URIHandlerError.self) {
            _ = try await set.loadEcoreResource(uri: "memory:/broken.ecore")
        }
        do {
            _ = try await set.loadXMIResource(uri: "memory:/broken.xmi")
            Issue.record("expected a failure")
        } catch let error as URIHandlerError {
            guard case .readFailed(let uri, _) = error else { Issue.record("\(error)"); return }
            #expect(uri == "memory:/broken.xmi")
        } catch {
            Issue.record("\(error)")
        }
    }

    @Test("a missing in-memory document is reported as not found")
    func missingInMemory() async {
        let set = ResourceSet()
        await set.setURIHandlers([InMemoryURIHandler(scheme: "memory")])
        await #expect(throws: URIHandlerError.notFound("memory:/none.ecore")) {
            _ = try await set.loadEcoreResource(uri: "memory:/none.ecore")
        }
    }

    @Test("a missing file still fails as it always has")
    func missingFile() async {
        let uri = URL(fileURLWithPath: "/nonexistent-directory/none.ecore").absoluteString
        await #expect(throws: (any Error).self) { _ = try await ResourceSet().loadEcoreResource(uri: uri) }
        await #expect(throws: (any Error).self) { _ = try await ResourceSet().loadXMIResource(uri: uri) }
        await #expect(throws: (any Error).self) { _ = try await ResourceSet().loadJSONResource(uri: uri) }
    }

    @Test("a malformed document and a bad encoding give the usual errors")
    func malformedText() async {
        await #expect(throws: (any Error).self) {
            _ = try await ResourceSet().loadXMIResource(text: "<not-closed", uri: "memory:/bad.xmi")
        }
        await #expect(throws: XMIError.self) {
            _ = try await XMIParser().parse(Data([0xFF, 0xFE, 0xFD]), uri: "memory:/bad.xmi")
        }
    }

    // MARK: - Handler chain

    @Test("the first handler that can handle a URI wins and files are the fallback")
    func chainOrder() async throws {
        let first = InMemoryURIHandler(texts: ["a:/x": "first"], scheme: "a")
        let second = InMemoryURIHandler(texts: ["a:/x": "second", "b:/y": "other"])
        let set = ResourceSet()
        await set.setURIHandlers([first, second])
        #expect(await set.uriHandlers.count == 2)
        #expect(try await set.readDocument(uri: "a:/x") == Data("first".utf8))
        #expect(try await set.readDocument(uri: "b:/y") == Data("other".utf8))
        let file = try HandlerFixtures.url("xmi/minimal.ecore")
        let none = ResourceSet()
        #expect(await none.uriHandlers.isEmpty)
        #expect(try await none.readDocument(uri: file.absoluteString) == Data(contentsOf: file))
        #expect(await none.documentExists(uri: file.absoluteString))
        #expect(await none.documentExists(uri: file.absoluteString + ".missing") == false)
    }

    @Test("URI mappings apply before handler lookup")
    func mappingApplies() async throws {
        let memory = try HandlerFixtures.memory(["metamodels/Families.ecore"])
        let set = ResourceSet()
        await set.setURIHandlers([memory])
        await set.mapURI(from: "http://logical.example/Families.ecore", to: "memory:/metamodels/Families.ecore")
        let resource = try await set.loadEcoreResource(uri: "http://logical.example/Families.ecore")
        #expect(resource.uri == "http://logical.example/Families.ecore")
        #expect(await resource.getRootObjects().first is EPackage)
    }

    // MARK: - Handlers

    @Test("the file handler reads, writes, and checks files")
    func fileHandler() async throws {
        let handler = FileURIHandler()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.txt")
        #expect(handler.canHandle(file.absoluteString))
        #expect(handler.canHandle("relative/path.ecore"))
        #expect(!handler.canHandle("memory:/a"))
        #expect(await handler.exists(file.absoluteString) == false)
        try await handler.write(Data("hello".utf8), to: file.absoluteString)
        #expect(try await handler.read(file.absoluteString) == Data("hello".utf8))
        #expect(await handler.exists(file.absoluteString))
        await #expect(throws: URIHandlerError.invalidURI("")) { _ = try await handler.read("") }
        #expect(await handler.exists("memory:/a") == false)
    }

    @Test("the in-memory handler stores, reads, lists, and removes documents")
    func inMemoryHandler() async throws {
        let handler = InMemoryURIHandler(documents: ["m:/a": Data("1".utf8)])
        #expect(handler.canHandle("anything:/x"))
        #expect(InMemoryURIHandler(scheme: "M").canHandle("m:/x"))
        #expect(!InMemoryURIHandler(scheme: "m").canHandle("n:/x"))
        #expect(!InMemoryURIHandler(scheme: "m").canHandle(""))
        try await handler.write(Data("2".utf8), to: "m:/b")
        await handler.set("3", for: "m:/c")
        #expect(await handler.uris == ["m:/a", "m:/b", "m:/c"])
        #expect(await handler.text(for: "m:/c") == "3")
        #expect(await handler.text(for: "m:/none") == nil)
        #expect(await handler.exists("m:/b"))
        await handler.remove("m:/b")
        #expect(await handler.exists("m:/b") == false)
    }

    @Test("the closure handler delegates and has sensible defaults")
    func closureHandler() async throws {
        let log = ReadLog()
        let handler = ClosureURIHandler(
            canHandle: { $0.hasPrefix("x:") },
            read: { uri in
                await log.record(uri)
                return Data(uri.utf8)
            })
        #expect(handler.canHandle("x:/a") && !handler.canHandle("y:/a"))
        #expect(try await handler.read("x:/a") == Data("x:/a".utf8))
        #expect(await handler.exists("x:/a"))
        #expect(await log.uris.count == 2)
        await #expect(throws: URIHandlerError.writeFailed("x:/a", "Writing is not supported")) {
            try await handler.write(Data(), to: "x:/a")
        }
        let explicit = ClosureURIHandler(read: { _ in Data() }, write: { _, _ in }, exists: { _ in false })
        try await explicit.write(Data(), to: "z:/a")
        #expect(await explicit.exists("z:/a") == false)
        #expect(explicit.canHandle("anything"))
    }

    // MARK: - Saving

    @Test("saving through a handler writes the bytes that the serialiser writes")
    func saveMatchesSerialiser() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try HandlerFixtures.url("xmi/zoo.xmi")
        let animals = try HandlerFixtures.url("xmi/animals.ecore")
        let memory = InMemoryURIHandler(scheme: "memory")
        let set = ResourceSet()
        await set.setURIHandlers([memory])
        _ = try await set.loadEcoreResource(uri: URIReference.canonicalise(animals.absoluteString))
        let resource = try await set.loadXMIResource(uri: URIReference.canonicalise(source.absoluteString))

        for options in [XMISerializationOptions.legacy, XMISerializationOptions.emf] {
            let file = directory.appendingPathComponent("out.xmi")
            try await XMISerializer(options: options).serialize(resource, to: file)
            try await set.save(resource, to: "memory:/out.xmi", options: options)
            #expect(try await memory.read("memory:/out.xmi") == Data(contentsOf: file))
        }

        let package = try await EPackage(url: try HandlerFixtures.url("fidelity/consumer.ecore"))
        let packageFile = directory.appendingPathComponent("consumer.ecore")
        try XMISerializer().serialize(package, to: packageFile)
        try await set.save(package, to: packageFile.absoluteString)
        #expect(try Data(contentsOf: packageFile) == Data(XMISerializer().serialize(package, relativeTo: packageFile).utf8))
    }

    @Test("a package saved to memory loads back from memory")
    func saveAndReload() async throws {
        let package = try await EPackage(url: try HandlerFixtures.url("fidelity/shared.ecore"))
        let memory = InMemoryURIHandler(scheme: "memory")
        let set = ResourceSet()
        await set.setURIHandlers([memory])
        try await set.save(package, to: "memory:/shared.ecore")
        let reloaded = try await set.loadEcoreResource(uri: "memory:/shared.ecore")
        let root = try #require(await reloaded.getRootObjects().first as? EPackage)
        #expect(XMISerializer().serialize(root) == XMISerializer().serialize(package, relativeTo: URL(string: "memory:/shared.ecore")!))
    }

    @Test("a throwing writer surfaces as a write error")
    func throwingWriter() async throws {
        struct Failure: Error {}
        let set = ResourceSet()
        await set.setURIHandlers([ClosureURIHandler(read: { _ in Data() }, write: { _, _ in throw Failure() })])
        let package = try await EPackage(url: try HandlerFixtures.url("xmi/minimal.ecore"))
        do {
            try await set.save(package, to: "memory:/x.ecore")
            Issue.record("expected a failure")
        } catch URIHandlerError.writeFailed(let uri, _) {
            #expect(uri == "memory:/x.ecore")
        }
    }

    @Test("JSON loads from text and saves through a handler")
    func jsonText() async throws {
        let path = "json/" + (try FileManager.default.contentsOfDirectory(atPath: try HandlerFixtures.url("json").path)
            .sorted().first { $0.hasSuffix(".json") } ?? "")
        let text = try HandlerFixtures.text(path)
        let set = ResourceSet()
        let memory = InMemoryURIHandler(scheme: "memory")
        await set.setURIHandlers([memory])
        let resource = try await set.loadJSONResource(text: text, uri: "memory:/a.json")
        #expect(try await set.loadJSONResource(text: text, uri: "memory:/a.json") === resource)
        try await set.saveJSON(resource, to: "memory:/b.json")
        #expect(try await memory.read("memory:/b.json") == Data(try await JSONSerializer().serialize(resource).utf8))
        try await memory.write(Data(text.utf8), to: "memory:/c.json")
        let viaHandler = try await set.loadJSONResource(uri: "memory:/c.json")
        #expect(viaHandler.uri == "memory:/c.json")
    }
}
