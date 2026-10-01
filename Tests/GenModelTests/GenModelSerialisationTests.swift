//
// GenModelSerialisationTests.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import GenModel

@Suite("GenModel serialisation")
struct GenModelSerialisationTests {
    private static func fixtureURL(_ name: String, _ ext: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources"))
    }

    /// Loads the library generator model; the caller keeps the resource set alive.
    private static func load(in resourceSet: ResourceSet) async throws -> (resource: Resource, genModel: DynamicEObject) {
        let document = try await GenModelResource.loadDocument(
            url: fixtureURL("library", "genmodel"), resourceSet: resourceSet,
            resolution: .nameFragments)
        let root = try #require(await document.resource.getRootObjects().first as? DynamicEObject)
        return (document.resource, root)
    }

    private func count(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    @Test("an unsettable attribute that is set to its default value is written")
    func createChildIsKept() async throws {
        let resourceSet = ResourceSet()
        let (resource, _) = try await Self.load(in: resourceSet)
        let text = try await XMISerializer(options: .emf).serialize(resource)
        let original = try String(
            contentsOf: Self.fixtureURL("library", "genmodel"), encoding: .utf8)
        #expect(count(of: "createChild=\"false\"", in: original) == 9)
        #expect(count(of: "createChild=\"false\"", in: text) == 9)
    }

    @Test("a feature whose createChild was never set does not write it")
    func createChildUnset() async throws {
        let resourceSet = ResourceSet()
        let (resource, _) = try await Self.load(in: resourceSet)
        let objects = await resource.getAllObjects().compactMap { $0 as? DynamicEObject }
        let feature = try #require(
            objects.first { $0.eClass.name == "GenFeature" && $0.eGet("createChild") != nil })
        await resource.eSet(objectId: feature.id, feature: "createChild", value: nil)
        let text = try await XMISerializer(options: .emf).serialize(resource)
        #expect(count(of: "createChild=\"false\"", in: text) == 8)
    }

    @Test("a literal name set in code is written as the literal text")
    func literalNameIsWrittenAsText() async throws {
        let resourceSet = ResourceSet()
        let (resource, genModel) = try await Self.load(in: resourceSet)
        await resource.eSet(objectId: genModel.id, feature: "complianceLevel", value: "JDK210")
        let text = try await XMISerializer(options: .emf).serialize(resource)
        #expect(text.contains("complianceLevel=\"21.0\""))
        #expect(!text.contains("JDK210"))
        let legacy = try await XMISerializer().serialize(resource)
        #expect(legacy.contains("complianceLevel=\"21.0\""))
    }

    @Test("a literal whose text equals its name is unchanged")
    func sameNameAndText() async throws {
        let resourceSet = ResourceSet()
        let (resource, _) = try await Self.load(in: resourceSet)
        let objects = await resource.getAllObjects().compactMap { $0 as? DynamicEObject }
        let feature = try #require(objects.first { $0.eClass.name == "GenFeature" })
        await resource.eSet(objectId: feature.id, feature: "property", value: "Readonly")
        let text = try await XMISerializer(options: .emf).serialize(resource)
        #expect(text.contains("property=\"Readonly\""))
    }

    @Test("loading maps literal text to the literal name, and text and name are both readable")
    func loadedLiteral() async throws {
        let resourceSet = ResourceSet()
        let (resource, genModel) = try await Self.load(in: resourceSet)
        #expect(genModel.eGet("complianceLevel") as? String == "JDK170")
        let element = GenElement(object: genModel, context: await GenModelContext.snapshot(of: resourceSet))
        #expect(element.stringValue("complianceLevel") == "17.0")
        #expect(element.literalName("complianceLevel") == "JDK170")
        #expect(element.stringValue("modelName") == "Library")
        #expect(element.literalName("modelName") == "Library")
        #expect(element.literalName("missing") == nil)
        _ = resource
    }

    @Test("references into a released resource set are reported, not silently dropped")
    func releasedResourceSet() async throws {
        var resourceSet: ResourceSet? = ResourceSet()
        let (resource, _) = try await Self.load(in: try #require(resourceSet))
        #expect(!(await resource.lostResourceSet))
        resourceSet = nil
        #expect(await resource.lostResourceSet)
        await #expect(throws: XMIError.self) {
            _ = try await XMISerializer(options: .emf).serialize(resource)
        }
    }

    @Test("the written document loads again to the same literal")
    func roundTrip() async throws {
        let resourceSet = ResourceSet()
        let (resource, _) = try await Self.load(in: resourceSet)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for ext in ["library.ecore"] {
            try FileManager.default.copyItem(
                at: Self.fixtureURL("library", "ecore"), to: directory.appendingPathComponent(ext))
        }
        let target = directory.appendingPathComponent("library.genmodel")
        try await XMISerializer(options: .emf).serialize(resource, to: target)
        let reloaded = try await GenModelResource.loadDocument(
            url: target, resourceSet: ResourceSet(), resolution: .nameFragments)
        let root = try #require(await reloaded.resource.getRootObjects().first as? DynamicEObject)
        #expect(root.eGet("complianceLevel") as? String == "JDK170")
    }
}
