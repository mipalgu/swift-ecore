//
// NestedPackageRegistrationTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests that the subpackages of a registered metamodel are found by their own namespace URIs.
@Suite("Nested package registration")
struct NestedPackageRegistrationTests {
    private static let metamodelPath = "metamodels/Nested.ecore"
    private static let rootURI = "http://example.org/root"
    private static let kernelURI = "http://example.org/root/kernel"
    private static let viewsURI = "http://example.org/root/views"
    private static let xsiDeclaration = "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\""

    // MARK: - Helpers

    private static func metamodelURL() throws -> URL {
        try ReflectionFixtures.resourcesURL().appendingPathComponent(metamodelPath)
    }

    /// A resource set with the nested metamodel loaded from its document.
    private static func loadedResourceSet() async throws -> ResourceSet {
        let resourceSet = ResourceSet()
        _ = try await resourceSet.loadEcoreResource(uri: try metamodelURL().absoluteString)
        return resourceSet
    }

    private static func subpackage(_ name: String, of package: EPackage) throws -> EPackage {
        try #require(package.getSubpackage(name))
    }

    private static func parse(_ text: String, in resourceSet: ResourceSet) async throws -> Resource {
        let parser = XMIParser(resourceSet: resourceSet)
        return try await parser.parse(text, uri: "memory:/instance-\(UUID().uuidString).xmi")
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

    // MARK: - Loading

    @Test("a document with subpackages loads as its root package with the subpackages attached")
    func packageFromURLHasSubpackages() async throws {
        let package = try await EPackage(url: try Self.metamodelURL())
        #expect(package.name == "root")
        #expect(package.nsURI == Self.rootURI)
        #expect(package.eSubpackages.map(\.name) == ["kernel", "views"])
        let kernel = try Self.subpackage("kernel", of: package)
        let views = try Self.subpackage("views", of: package)
        #expect(kernel.nsURI == Self.kernelURI)
        #expect(views.nsURI == Self.viewsURI)
    }

    @Test("references between subpackages resolve to the classes of the other subpackage")
    func crossSubpackageReferencesResolve() async throws {
        let package = try await EPackage(url: try Self.metamodelURL())
        let kernel = try Self.subpackage("kernel", of: package)
        let views = try Self.subpackage("views", of: package)
        let element = try #require(kernel.getEClass("Element"))
        let node = try #require(kernel.getEClass("Node"))
        let view = try #require(views.getEClass("View"))
        #expect(view.eSuperTypes.map(\.id) == [element.id])
        let shows = try #require(view.getStructuralFeature(name: "shows") as? EReference)
        #expect((shows.eType as? EClass)?.id == node.id)
        let focus = try #require(view.getStructuralFeature(name: "focus") as? EReference)
        #expect((focus.eType as? EClass)?.id == element.id)
        let model = try #require(package.getEClass("Model"))
        let elements = try #require(model.getStructuralFeature(name: "elements") as? EReference)
        #expect((elements.eType as? EClass)?.id == element.id)
    }

    @Test("all packages lists a package and its nested packages depth first")
    func allPackagesIsDepthFirst() async throws {
        let innermost = EPackage(name: "a1", nsURI: "http://example.org/p/a/a1", nsPrefix: "a1")
        let first = EPackage(name: "a", nsURI: "http://example.org/p/a", nsPrefix: "a", eSubpackages: [innermost])
        let second = EPackage(name: "b", nsURI: "http://example.org/p/b", nsPrefix: "b")
        let root = EPackage(name: "p", nsURI: "http://example.org/p", nsPrefix: "p", eSubpackages: [first, second])
        #expect(root.allPackages.map(\.name) == ["p", "a", "a1", "b"])
        #expect(second.allPackages.map(\.name) == ["b"])

        let loaded = try await EPackage(url: try Self.metamodelURL())
        #expect(loaded.allPackages.map(\.nsURI) == [Self.rootURI, Self.kernelURI, Self.viewsURI])
    }

    // MARK: - Registration

    @Test("registering a root package makes its subpackages available by their namespace URIs")
    func registrationIncludesSubpackages() async throws {
        let package = try await EPackage(url: try Self.metamodelURL())
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(package, uri: package.nsURI)
        #expect(await resourceSet.getMetamodel(uri: Self.kernelURI)?.name == "kernel")
        #expect(await resourceSet.getMetamodel(uri: Self.viewsURI)?.name == "views")
        #expect(await resourceSet.getMetamodelURIs() == [Self.rootURI])
        #expect(
            await resourceSet.getMetamodelURIs(includingSubpackages: true)
                == [Self.rootURI, Self.kernelURI, Self.viewsURI])
    }

    @Test("loading an Ecore document registers its subpackages")
    func ecoreLoadingRegistersSubpackages() async throws {
        let resourceSet = try await Self.loadedResourceSet()
        #expect(await resourceSet.getMetamodel(uri: Self.rootURI)?.name == "root")
        #expect(await resourceSet.getMetamodel(uri: Self.kernelURI)?.getEClass("Node") != nil)
        #expect(await resourceSet.getMetamodel(uri: Self.viewsURI)?.getEClass("View") != nil)
    }

    @Test("an explicit registration takes precedence over a subpackage with the same namespace URI")
    func explicitRegistrationWins() async throws {
        let replacement = EPackage(name: "replacement", nsURI: Self.kernelURI, nsPrefix: "kernel")
        let package = try await EPackage(url: try Self.metamodelURL())
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(replacement, uri: Self.kernelURI)
        await resourceSet.registerMetamodel(package, uri: package.nsURI)
        #expect(await resourceSet.getMetamodel(uri: Self.kernelURI)?.name == "replacement")
        #expect(await resourceSet.getMetamodel(uri: Self.viewsURI)?.name == "views")
    }

    @Test("unregistering a root package also forgets its subpackages")
    func unregisteringForgetsSubpackages() async throws {
        let package = try await EPackage(url: try Self.metamodelURL())
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(package, uri: package.nsURI)
        await resourceSet.unregisterMetamodel(uri: package.nsURI)
        #expect(await resourceSet.getMetamodel(uri: Self.kernelURI) == nil)
        #expect(await resourceSet.getMetamodel(uri: Self.viewsURI) == nil)
        #expect(await resourceSet.getMetamodelURIs(includingSubpackages: true).isEmpty)
    }

    @Test("the metamodels kept by a resource include the subpackages")
    func snapshotKeepsSubpackages() async throws {
        let package = try await EPackage(url: try Self.metamodelURL())
        let resource: Resource
        do {
            let resourceSet = ResourceSet()
            await resourceSet.registerMetamodel(package, uri: package.nsURI)
            resource = await resourceSet.createResource(uri: "memory:/kept.xmi")
        }
        let snapshot = try #require(await resource.metamodelSnapshot)
        #expect(snapshot.package(uri: Self.kernelURI)?.name == "kernel")
        #expect(snapshot.package(uri: Self.viewsURI)?.name == "views")
        #expect(snapshot.package(uri: Self.rootURI)?.name == "root")
        #expect(snapshot.all.map(\.name) == ["root"])
    }

    // MARK: - XMI Class Lookup

    @Test("an object whose class is qualified by a subpackage namespace gets the subpackage class")
    func subpackageNamespaceResolves() async throws {
        let resourceSet = try await Self.loadedResourceSet()
        let kernel = try #require(await resourceSet.getMetamodel(uri: Self.kernelURI))
        let resource = try await Self.parse(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <kernel:Node xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
            xmlns:kernel="\(Self.kernelURI)" name="solo" weight="3"/>
            """, in: resourceSet)
        let root = try await Self.root(of: resource)
        #expect(root.eClass.id == kernel.getEClass("Node")?.id)
        #expect(root.eGet("weight") as? Int == 3)
        #expect(await resource.metamodelSnapshot != nil)
    }

    @Test("contained objects typed by subpackage namespaces get the subpackage classes")
    func containedSubpackageTypesResolve() async throws {
        let resourceSet = try await Self.loadedResourceSet()
        let rootPackage = try #require(await resourceSet.getMetamodel(uri: Self.rootURI))
        let kernel = try #require(await resourceSet.getMetamodel(uri: Self.kernelURI))
        let views = try #require(await resourceSet.getMetamodel(uri: Self.viewsURI))
        let resource = try await Self.parse(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <root:Model xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \(Self.xsiDeclaration) \
            xmlns:root="\(Self.rootURI)" xmlns:kernel="\(Self.kernelURI)" xmlns:views="\(Self.viewsURI)" name="m">
              <elements xsi:type="kernel:Node" name="a" weight="1"/>
              <views xsi:type="views:View" name="v" shows="//@elements.0" focus="//@elements.0"/>
            </root:Model>
            """, in: resourceSet)
        let model = try await Self.root(of: resource)
        #expect(model.eClass.id == rootPackage.getEClass("Model")?.id)
        let elements = await Self.children("elements", of: model, in: resource)
        let viewObjects = await Self.children("views", of: model, in: resource)
        #expect(elements.map(\.eClass.id) == [kernel.getEClass("Node")?.id])
        #expect(viewObjects.map(\.eClass.id) == [views.getEClass("View")?.id])
        let view = try #require(viewObjects.first)
        #expect((view.eGet("shows") as? [EUUID]) == elements.map(\.id))
        #expect((view.eGet("focus") as? EUUID) == elements.first?.id)
    }

    @Test("a class of a subpackage qualified by the root namespace is found in the subpackage")
    func rootNamespaceFindsSubpackageClass() async throws {
        let resourceSet = try await Self.loadedResourceSet()
        let kernel = try #require(await resourceSet.getMetamodel(uri: Self.kernelURI))
        let resource = try await Self.parse(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <root:Model xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \(Self.xsiDeclaration) \
            xmlns:root="\(Self.rootURI)" name="m">
              <elements xsi:type="root:Node" name="a"/>
            </root:Model>
            """, in: resourceSet)
        let model = try await Self.root(of: resource)
        let elements = await Self.children("elements", of: model, in: resource)
        #expect(elements.map(\.eClass.id) == [kernel.getEClass("Node")?.id])

        let single = try await Self.parse(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <root:Node xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:root="\(Self.rootURI)" name="n"/>
            """, in: resourceSet)
        #expect(try await Self.root(of: single).eClass.id == kernel.getEClass("Node")?.id)
    }

    // MARK: - Round Trip

    /// Builds a model typed by the given metamodel.
    ///
    /// The elements of the model are a node and a view, both subclasses of the declared
    /// element type, and its views hold a view that shows the node.
    private static func buildInstance(of package: EPackage, in resource: Resource) async throws {
        let kernel = try subpackage("kernel", of: package)
        let views = try subpackage("views", of: package)
        let viewClass = try #require(views.getEClass("View"))
        var node = DynamicEObject(eClass: try #require(kernel.getEClass("Node")))
        node.eSet("name", value: "a")
        node.eSet("weight", value: 2)
        var overview = DynamicEObject(eClass: viewClass)
        overview.eSet("name", value: "o")
        var view = DynamicEObject(eClass: viewClass)
        view.eSet("name", value: "v")
        view.eSet("shows", value: [node.id])
        view.eSet("focus", value: overview.id)
        var model = DynamicEObject(eClass: try #require(package.getEClass("Model")))
        model.eSet("name", value: "m")
        model.eSet("elements", value: [node.id, overview.id])
        model.eSet("views", value: [view.id])
        await resource.register(node)
        await resource.register(overview)
        await resource.register(view)
        await resource.add(model)
    }

    @Test(
        "an instance is written with one namespace per subpackage and reads back with the same classes",
        arguments: [XMISerializationOptions.legacy, XMISerializationOptions.emf])
    func roundTripWithSubpackageNamespaces(options: XMISerializationOptions) async throws {
        let writingSet = try await Self.loadedResourceSet()
        let package = try #require(await writingSet.getMetamodel(uri: Self.rootURI))
        let resource = await writingSet.createResource(uri: "memory:/written.xmi")
        try await Self.buildInstance(of: package, in: resource)

        var diagnostics = ConversionDiagnostics()
        let text = try await XMISerializer(options: options).serialize(resource, diagnostics: &diagnostics)
        #expect(diagnostics.isEmpty)
        #expect(text.contains("xmlns:root=\"\(Self.rootURI)\""))
        #expect(text.contains("xmlns:kernel=\"\(Self.kernelURI)\""))
        #expect(text.contains("xmlns:views=\"\(Self.viewsURI)\""))
        #expect(text.contains("xsi:type=\"kernel:Node\""))
        #expect(text.contains("xsi:type=\"views:View\""))

        let readingSet = try await Self.loadedResourceSet()
        let readPackage = try #require(await readingSet.getMetamodel(uri: Self.rootURI))
        let kernel = try Self.subpackage("kernel", of: readPackage)
        let views = try Self.subpackage("views", of: readPackage)
        let parser = XMIParser(resourceSet: readingSet)
        let read = try await parser.parse(text, uri: "memory:/read.xmi")
        #expect(await parser.diagnostics.isEmpty)
        let model = try await Self.root(of: read)
        #expect(model.eClass.id == readPackage.getEClass("Model")?.id)
        let elements = await Self.children("elements", of: model, in: read)
        let viewObjects = await Self.children("views", of: model, in: read)
        #expect(elements.map(\.eClass.id) == [kernel.getEClass("Node")?.id, views.getEClass("View")?.id])
        #expect(viewObjects.map(\.eClass.id) == [views.getEClass("View")?.id])
        #expect(elements.first?.eGet("weight") as? Int == 2)
        #expect((viewObjects.first?.eGet("shows") as? [EUUID]) == elements.first.map { [$0.id] })
        #expect((viewObjects.first?.eGet("focus") as? EUUID) == elements.last?.id)
    }

    // MARK: - JSON

    @Test("a JSON class qualified by a subpackage namespace gets the subpackage class")
    func jsonSubpackageNamespaceResolves() async throws {
        let resourceSet = try await Self.loadedResourceSet()
        let kernel = try #require(await resourceSet.getMetamodel(uri: Self.kernelURI))
        let parser = JSONParser(resourceSet: resourceSet, options: JSONParseOptions(requiresMetamodel: true))
        let resource = try await parser.parse(
            Data(#"{"eClass": "\#(Self.kernelURI)#//Node", "name": "n", "weight": 4}"#.utf8),
            uri: "memory:/node.json")
        let root = try await Self.root(of: resource)
        #expect(root.eClass.id == kernel.getEClass("Node")?.id)
        #expect(root.eGet("weight") as? Int == 4)
    }
}
