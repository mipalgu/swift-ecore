//
// GenModelCrossDocumentTests.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import GenModel

@Suite("GenModel cross-document references")
struct GenModelCrossDocumentTests {
    private static func fixtureURL(_ name: String, _ ext: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources"))
    }

    /// A scratch directory holding copies of the library fixtures, removed by the caller.
    private static func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, ext) in [("library", "genmodel"), ("library", "ecore")] {
            try FileManager.default.copyItem(
                at: fixtureURL(name, ext), to: directory.appendingPathComponent("\(name).\(ext)"))
        }
        return directory
    }

    private func names(_ elements: [GenElement]) -> [String] { elements.map(\.name) }

    // MARK: - Resolution through the resource set

    @Test("resolved loading replaces references by identifiers of native elements")
    func resolvedLoadingUsesIdentifiers() async throws {
        let resourceSet = ResourceSet()
        let document = try await GenModelResource.loadDocument(
            url: Self.fixtureURL("library", "genmodel"), resourceSet: resourceSet,
            resolution: .nameFragments)
        let objects = await document.resource.getAllObjects().compactMap { $0 as? DynamicEObject }
        let genClass = try #require(objects.first { $0.eClass.name == "GenClass" })
        let target = try #require(genClass.eGet("ecoreClass") as? EUUID)
        let package = try #require(document.foreignPackages.values.first)
        #expect(package.getEClass("Named")?.id == target)
        let feature = try #require(objects.first { $0.eClass.name == "GenFeature" })
        #expect(feature.eGet("ecoreFeature") is EUUID)
    }

    @Test("source models are loaded as native resources of the same resource set")
    func sourceModelsAreNative() async throws {
        let resourceSet = ResourceSet()
        _ = try await GenModelResource.load(
            url: Self.fixtureURL("library", "genmodel"), resourceSet: resourceSet,
            resolution: .nameFragments)
        let resources = await resourceSet.getResources()
        let native = await resources.asyncCompactMap { await $0.getRootObjects().first as? EPackage }
        #expect(native.map(\.name) == ["library"])
    }

    @Test("references to missing source models stay unresolved proxies")
    func missingTargetsStayProxies() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("missing.genmodel")
        try """
            <?xml version="1.0" encoding="UTF-8"?>
            <genmodel:GenModel xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
                xmlns:genmodel="http://www.eclipse.org/emf/2002/GenModel" modelName="Missing">
              <genPackages prefix="M" ecorePackage="missing.ecore#/"/>
            </genmodel:GenModel>
            """.write(to: url, atomically: true, encoding: .utf8)
        let resource = try await GenModelResource.load(
            url: url, resolution: .nameFragments)
        let package = try #require(
            await resource.getAllObjects().compactMap { $0 as? DynamicEObject }
                .first { $0.eClass.name == "GenPackage" })
        #expect(package.eGet("ecorePackage") is ResourceProxy)
    }

    // MARK: - Generator package fragments

    @Test("a generator package is identified by the name of its Ecore package")
    func genPackageFragment() async throws {
        let resourceSet = ResourceSet()
        let resource = try await GenModelResource.load(
            url: Self.fixtureURL("library", "genmodel"), resourceSet: resourceSet,
            resolution: .nameFragments)
        let navigator = FragmentNavigator(resource: resource)
        let package = try #require(
            await resource.getAllObjects().compactMap { $0 as? DynamicEObject }
                .first { $0.eClass.name == "GenPackage" })
        #expect(await navigator.resolve("//library")?.id == package.id)
        #expect(await navigator.fragment(for: package.id) == "//library")
        #expect(await navigator.resolve("//other") == nil)
    }

    private static let usedModelText = """
        <?xml version="1.0" encoding="UTF-8"?>
        <genmodel:GenModel xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:genmodel="http://www.eclipse.org/emf/2002/GenModel" modelName="Used">
          <foreignModel>Used.ecore</foreignModel>
          <genPackages prefix="Used" ecorePackage="Used.ecore#/"/>
        </genmodel:GenModel>
        """

    private static let usedEcoreText = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
            name="shared" nsURI="http://example.org/shared" nsPrefix="shared"/>
        """

    private static func usingModelText(used: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <genmodel:GenModel xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:genmodel="http://www.eclipse.org/emf/2002/GenModel" modelName="Using"
            usedGenPackages="\(used)">
          <genPackages prefix="Using" ecorePackage="Used.ecore#/"/>
        </genmodel:GenModel>
        """
    }

    @Test("usedGenPackages references resolve and are written as package fragments")
    func usedGenPackages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.usedEcoreText.write(
            to: directory.appendingPathComponent("Used.ecore"), atomically: true, encoding: .utf8)
        try Self.usedModelText.write(
            to: directory.appendingPathComponent("Used.genmodel"), atomically: true, encoding: .utf8)
        let usingURL = directory.appendingPathComponent("Using.genmodel")
        try Self.usingModelText(used: "Used.genmodel#//shared")
            .write(to: usingURL, atomically: true, encoding: .utf8)

        let resourceSet = ResourceSet()
        let resource = try await GenModelResource.load(
            url: usingURL, resourceSet: resourceSet, resolution: .nameFragments)
        let objects = await resource.getAllObjects().compactMap { $0 as? DynamicEObject }
        let genModel = try #require(objects.first { $0.eClass.name == "GenModel" })
        let used = try #require(genModel.eGet("usedGenPackages") as? [EUUID])
        let target = try #require(await resourceSet.resolve(used[0]))
        #expect(target.object.eClass.name == "GenPackage")
        #expect(target.resource.uri.hasSuffix("Used.genmodel"))

        let savedURL = directory.appendingPathComponent("Saved.genmodel")
        try await GenModelResource.save(resource, to: savedURL)
        let text = try String(contentsOf: savedURL, encoding: .utf8)
        #expect(text.contains("usedGenPackages=\"Used.genmodel#//shared\""))
    }

    // MARK: - Saving

    @Test("a saved generator model reloads to the same structure with EMF reference forms")
    func saveRoundTrip() async throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("library.genmodel")
        let saved = directory.appendingPathComponent("saved.genmodel")

        let resourceSet = ResourceSet()
        let resource = try await GenModelResource.load(
            url: original, resourceSet: resourceSet, resolution: .nameFragments)
        try await GenModelResource.save(resource, to: saved)

        let text = try String(contentsOf: saved, encoding: .utf8)
        #expect(text.contains("ecoreClass=\"library.ecore#//Book\""))
        #expect(text.contains("ecoreFeature=\"ecore:EAttribute library.ecore#//Book/pages\""))
        #expect(text.contains("ecoreFeature=\"ecore:EReference library.ecore#//Book/author\""))
        #expect(text.contains("ecorePackage=\"library.ecore#/\""))
        #expect(text.contains("ecoreEnumLiteral=\"library.ecore#//BookCategory/Mystery\""))

        let reloadedSet = ResourceSet()
        _ = try await GenModelResource.load(
            url: saved, resourceSet: reloadedSet, resolution: .nameFragments)
        let before = await GenModelContext.snapshot(of: resourceSet)
        let after = await GenModelContext.snapshot(of: reloadedSet)
        let packageBefore = try #require(before.genModels.first?.genPackages.first)
        let packageAfter = try #require(after.genModels.first?.genPackages.first)
        #expect(names(packageAfter.genClasses) == names(packageBefore.genClasses))
        #expect(names(packageAfter.genEnums) == names(packageBefore.genEnums))
        #expect(names(packageAfter.genDataTypes) == names(packageBefore.genDataTypes))
        for (lhs, rhs) in zip(packageBefore.genClasses, packageAfter.genClasses) {
            #expect(names(rhs.genFeatures) == names(lhs.genFeatures))
            #expect(rhs.isAbstract == lhs.isAbstract)
        }
        #expect(packageAfter.name == "library")
    }
}

extension Sequence {
    fileprivate func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var result: [T] = []
        for element in self {
            if let value = await transform(element) { result.append(value) }
        }
        return result
    }
}
