//
// BundledMetamodelTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation
import Testing

@testable import ECore

/// Tests that metamodels shipped as package resources are found, loaded once and registered.
@Suite("Bundled metamodels")
struct BundledMetamodelTests {
    private static let name = "Nested"
    private static let subdirectory = "Resources/metamodels"
    private static let rootURI = "http://example.org/root"
    private static let kernelURI = "http://example.org/root/kernel"

    /// A fresh temporary directory, removed by the caller.
    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundledMetamodelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func fixtureText() throws -> String {
        try String(
            contentsOf: try ReflectionFixtures.resourcesURL().appendingPathComponent("metamodels/Nested.ecore"),
            encoding: .utf8)
    }

    // MARK: - Locating

    @Test("the resource directory of a target is named after its package and target")
    func resourceBundleDirectoryName() {
        let bundleName = ResourceBundleName(package: "swift-example", target: "Metamodels")
        #expect(bundleName.directoryName == "swift-example_Metamodels.resources")
        #expect(bundleName.package == "swift-example")
        #expect(bundleName.target == "Metamodels")
    }

    @Test("a resource is found in a bundle")
    func findsResourceInBundle() throws {
        let url = try #require(
            BundledResources.url(
                forResource: Self.name, withExtension: ModelFormat.ecore.fileExtension,
                subdirectory: Self.subdirectory, in: .module))
        #expect(url.lastPathComponent == "Nested.ecore")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("a resource that a bundle lacks is not found")
    func missingResourceIsNotFound() {
        #expect(
            BundledResources.url(
                forResource: "Absent", withExtension: ModelFormat.ecore.fileExtension,
                subdirectory: Self.subdirectory, in: .module) == nil)
    }

    @Test("without a bundle a resource is found in the resource directory under a search root")
    func findsResourceBesideExecutable() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundleName = ResourceBundleName(package: "swift-example", target: "Metamodels")
        let directory = root.appendingPathComponent(bundleName.directoryName, isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.fixtureText().write(
            to: directory.appendingPathComponent("Nested.ecore"), atomically: testWritesAtomically, encoding: .utf8)

        let empty = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: empty) }
        let found = BundledResources.url(
            forResource: Self.name, withExtension: ModelFormat.ecore.fileExtension, subdirectory: "models",
            bundleName: bundleName, searching: [empty, root])
        #expect(found?.standardizedFileURL.path == directory.appendingPathComponent("Nested.ecore").standardizedFileURL.path)
        #expect(
            BundledResources.url(
                forResource: Self.name, withExtension: ModelFormat.ecore.fileExtension, subdirectory: "models",
                bundleName: bundleName, searching: [empty]) == nil)
    }

    @Test("the resource directory is derived from the name of the bundle")
    func derivesDirectoryNameFromBundle() {
        let name = BundledResources.directoryName(of: .module)
        #expect(name == Bundle.module.bundleURL.lastPathComponent)
        #expect(name.hasPrefix("swift-ecore_ECoreTests."))
    }

    @Test("without a bundle name a resource is found in the directory named like the bundle")
    func findsResourceInDirectoryDerivedFromBundle() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent(BundledResources.directoryName(of: .module), isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.fixtureText().write(
            to: directory.appendingPathComponent("Derived.ecore"), atomically: testWritesAtomically, encoding: .utf8)

        let found = BundledResources.url(
            forResource: "Derived", withExtension: ModelFormat.ecore.fileExtension, subdirectory: "models",
            in: .module, bundleName: nil, searching: [root])
        #expect(found?.standardizedFileURL.path == directory.appendingPathComponent("Derived.ecore").standardizedFileURL.path)
        #expect(
            BundledResources.url(
                forResource: "Derived", withExtension: ModelFormat.ecore.fileExtension, subdirectory: "models",
                in: .module, bundleName: nil, searching: [try Self.temporaryDirectory()]) == nil)
    }

    // MARK: - Loading

    @Test("a bundled metamodel is loaded with its subpackages")
    func loadsBundledMetamodel() async throws {
        let package = try await EPackage.bundled(
            named: Self.name, subdirectory: Self.subdirectory, in: .module, cache: BundledMetamodelCache())
        #expect(package.nsURI == Self.rootURI)
        #expect(package.allPackages.map(\.name) == ["root", "kernel", "views"])
    }

    @Test("a bundled metamodel is loaded once per location and cache")
    func cachesPerLocation() async throws {
        let cache = BundledMetamodelCache()
        let first = try await EPackage.bundled(named: Self.name, subdirectory: Self.subdirectory, in: .module, cache: cache)
        let second = try await EPackage.bundled(named: Self.name, subdirectory: Self.subdirectory, in: .module, cache: cache)
        #expect(first.id == second.id)
        #expect(first.getEClass("Model")?.id == second.getEClass("Model")?.id)
        let other = try await EPackage.bundled(
            named: Self.name, subdirectory: Self.subdirectory, in: .module, cache: BundledMetamodelCache())
        #expect(other.id != first.id)
    }

    @Test("concurrent first loads share one package")
    func concurrentLoadsShareOnePackage() async throws {
        let cache = BundledMetamodelCache()
        let url = try #require(
            BundledResources.url(
                forResource: Self.name, withExtension: ModelFormat.ecore.fileExtension,
                subdirectory: Self.subdirectory, in: .module))
        let identifiers = try await withThrowingTaskGroup(of: UUID.self) { group in
            for _ in 0..<8 { group.addTask { try await cache.package(at: url).id } }
            var result = Set<UUID>()
            for try await identifier in group { result.insert(identifier) }
            return result
        }
        #expect(identifiers.count == 1)
    }

    @Test("a bundled metamodel can be registered with a resource set as it is loaded")
    func registersBundledMetamodel() async throws {
        let resourceSet = ResourceSet()
        let package = try await EPackage.bundled(
            named: Self.name, subdirectory: Self.subdirectory, in: .module, registeringIn: resourceSet,
            cache: BundledMetamodelCache())
        #expect(await resourceSet.getMetamodel(uri: Self.rootURI)?.id == package.id)
        #expect(await resourceSet.getMetamodel(uri: Self.kernelURI)?.name == "kernel")
    }

    @Test("a missing bundled metamodel is an error that names it")
    func missingMetamodelThrows() async throws {
        await #expect(throws: BundledMetamodelError.resourceMissing("Absent.ecore")) {
            _ = try await EPackage.bundled(named: "Absent", subdirectory: Self.subdirectory, in: .module)
        }
        let error = BundledMetamodelError.resourceMissing("Absent.ecore")
        #expect(error.description.contains("Absent.ecore"))
        #expect(error.errorDescription == error.description)
    }

    @Test("a load that fails is not cached")
    func failuresAreNotCached() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Later.ecore")
        let cache = BundledMetamodelCache()
        await #expect(throws: (any Error).self) { _ = try await cache.package(at: url) }
        try Self.fixtureText().write(to: url, atomically: testWritesAtomically, encoding: .utf8)
        #expect(try await cache.package(at: url).nsURI == Self.rootURI)
    }
}
