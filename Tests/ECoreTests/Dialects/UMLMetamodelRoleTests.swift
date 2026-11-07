//
// UMLMetamodelRoleTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that a UML class model given as a metamodel to ``ModelIO`` is converted into an
/// Ecore metamodel through the handler of its format.
@Suite("UML class models in the role of a metamodel")
struct UMLMetamodelRoleTests {
    /// The directory of the dialect fixtures.
    static let directory = OMGXMIDialectTests.directory

    /// The namespace URI of the converted library class model.
    static let libraryURI = UMLToEcoreTests.libraryURI

    /// The location of a dialect fixture.
    static func fixture(_ name: String) -> URL { directory.appendingPathComponent(name) }

    @Test("The UML handler converts documents into metamodels")
    func handlerConvertsMetamodels() async throws {
        let registry = ModelFormatRegistry.shared
        let handler = try #require(await registry.handler(for: .uml))
        #expect(handler.role == .model)
        let converting = try #require(handler as? any MetamodelConvertingModelFormatHandler)
        let resourceSet = ResourceSet()
        let request = ModelFormatReadRequest(
            data: try Data(contentsOf: Self.fixture("library-classes.uml")),
            uri: Self.fixture("library-classes.uml").absoluteString, resourceSet: resourceSet)
        guard case .resource(let resource, let packages, _) = try await converting.readMetamodel(request) else {
            Issue.record("the metamodel is not returned as a resource")
            return
        }
        #expect(packages.map(\.name) == ["library"])
        #expect(await resource.getRootObjects().count == 1)
        #expect(await resourceSet.getMetamodel(uri: Self.libraryURI)?.id == packages.first?.id)
    }

    @Test("A UML class model is registered as a metamodel")
    func registersUMLMetamodel() async throws {
        let resourceSet = ResourceSet()
        let packages = try await ModelIO.registerMetamodels(
            at: [Self.fixture("library-classes.uml")], in: resourceSet)
        let package = try #require(packages.first)
        #expect(packages.count == 1)
        #expect(package.nsURI == Self.libraryURI)
        #expect(package.getEClass("Library") != nil)
        #expect(package.getEClass("Book") != nil)
        #expect(await resourceSet.getMetamodel(uri: Self.libraryURI)?.id == package.id)
        let again = try await ModelIO.registerMetamodels(at: [Self.fixture("library-classes.uml")], in: resourceSet)
        #expect(again.map(\.id) == packages.map(\.id))
    }

    @Test("A model is read with a UML class model as its metamodel")
    func loadsInstancesOfUMLMetamodel() async throws {
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(
            url: Self.fixture("library-instance.xmi"), resourceSet: resourceSet,
            metamodels: [Self.fixture("library-classes.uml")])
        #expect(loaded.format == .xmi)
        #expect(loaded.diagnostics.warnings.isEmpty)
        let roots = await loaded.resource.getRootObjects()
        let root = try #require(roots.first)
        #expect(root.eClass.name == "Library")
        let package = try #require(await resourceSet.getMetamodel(uri: Self.libraryURI))
        #expect(root.eClass.id == package.getEClass("Library")?.id)
        let items = try #require(await loaded.resource.eGet(objectId: root.id, feature: "items") as? [EUUID])
        #expect(items.count == 2)
    }

    @Test("A UML class model in an XMI file is recognised and converted as a metamodel")
    func convertsRecognisedUMLMetamodel() async throws {
        let text = try String(contentsOf: Self.fixture("library-classes.uml"), encoding: .utf8)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UMLMetamodelRoleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library-classes.xmi")
        try Data(text.utf8).write(to: url)
        let packages = try await ModelIO.registerMetamodels(at: [url], in: ResourceSet())
        #expect(packages.map(\.nsURI) == [Self.libraryURI])
    }
}
