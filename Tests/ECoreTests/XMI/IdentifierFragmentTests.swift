//
// IdentifierFragmentTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for fragments that name an object by its identifier.
///
/// EMF reads a fragment that starts with `/` as a path and any other fragment as an
/// identifier: the `xmi:id` of an element, or else the value of the attribute that the
/// class of an object declares as its ID. A trailing `?query?` is not part of the
/// identifier. Writers name an object that has an identifier by that identifier, both
/// within its own document and from other documents.
@Suite("Identifier fragments")
struct IdentifierFragmentTests {
    /// The namespace URI of the test metamodel.
    static let namespace = "http://example.org/departments"

    /// The base URI of the in-memory documents.
    static let base = "memory:/identifiers/"

    /// The URI of the shared document.
    static let sharedURI = base + "SharedDeps.xmi"

    /// The URI of the referring document.
    static let projectURI = base + "Project.xmi"

    /// A shared document whose departments carry an `xmi:id` and a code.
    static let sharedDocument = """
        <?xml version="1.0" encoding="UTF-8"?>
        <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:dep="http://example.org/departments">
          <dep:Department xmi:id="it" name="IT" code="D-IT"/>
          <dep:Department xmi:id="hr" name="HR" code="D-HR"/>
          <dep:Department name="Finance" code="D-FIN"/>
        </xmi:XMI>

        """

    /// Builds a metamodel whose departments have an ID attribute `code`.
    ///
    /// - Returns: The package.
    static func makeMetamodel() -> EPackage {
        let string = EcorePackage.dataType(.eString) ?? EDataType(name: "EString")
        var department = EClass(
            name: "Department",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EAttribute(name: "code", eType: string, isID: true),
            ])
        department.eStructuralFeatures.append(
            EReference(name: "relatedDepartments", eType: department, upperBound: -1))
        department.eStructuralFeatures.append(EReference(name: "partner", eType: department))
        return EPackage(name: "dep", nsURI: namespace, nsPrefix: "dep", eClassifiers: [department])
    }

    /// Creates a resource set that knows the test metamodel.
    ///
    /// - Returns: The resource set.
    static func makeResourceSet() async -> ResourceSet {
        let set = ResourceSet()
        let package = makeMetamodel()
        await set.registerMetamodel(package, uri: package.nsURI)
        return set
    }

    /// A project document that refers to departments through the given reference elements.
    ///
    /// - Parameter references: The reference elements of the project.
    /// - Returns: The document text.
    static func projectDocument(_ references: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <dep:Department xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:dep="http://example.org/departments" name="Project">
          \(references)
        </dep:Department>

        """
    }

    /// Loads the shared document and a project into a fresh resource set.
    ///
    /// - Parameter references: The reference elements of the project.
    /// - Returns: The set, the shared resource and its departments, and the project resource.
    static func loadProject(_ references: String) async throws -> (
        set: ResourceSet, shared: Resource, departments: [DynamicEObject], project: Resource
    ) {
        let set = await makeResourceSet()
        let shared = try await XMIParser(resourceSet: set).parse(sharedDocument, uri: sharedURI)
        let departments = await shared.getRootObjects().compactMap { $0 as? DynamicEObject }
        try #require(departments.count == 3)
        let project = try await XMIParser(resourceSet: set).parse(projectDocument(references), uri: projectURI)
        return (set, shared, departments, project)
    }

    /// The identifiers that a feature of the root object of a resource refers to, after resolving proxies.
    ///
    /// - Parameters:
    ///   - feature: The feature name.
    ///   - resource: The resource.
    ///   - set: The resource set that holds the resource and the referenced documents.
    /// - Returns: The referenced identifiers.
    static func targets(of feature: String, in resource: Resource, of set: ResourceSet) async throws -> [EUUID] {
        let root = try #require(await resource.getRootObjects().first)
        let value = await resource.eGetResolving(objectId: root.id, feature: feature)
        withExtendedLifetime(set) {}
        return ReferenceValues.identifiers(value)
    }

    // MARK: - Resolving

    @Test("a fragment that does not start with a slash names an xmi:id")
    func resolverFindsXMLIdentifier() async throws {
        let (_, shared, departments, _) = try await Self.loadProject("")
        let resolver = XPathResolver(resource: shared)
        #expect(await resolver.resolve("it") == departments[0].id)
        #expect(await resolver.resolve("#hr") == departments[1].id)
        #expect(await resolver.resolve("#/0") == departments[0].id)
        #expect(await resolver.resolve("#missing") == nil)
    }

    @Test("a fragment that does not start with a slash names the value of an ID attribute")
    func resolverFindsIDAttribute() async throws {
        let (_, shared, departments, _) = try await Self.loadProject("")
        let resolver = XPathResolver(resource: shared)
        #expect(await resolver.resolve("D-FIN") == departments[2].id)
        #expect(await resolver.resolve("#D-HR") == departments[1].id)
    }

    @Test("an xmi:id takes precedence over an equal ID attribute value")
    func xmlIdentifierFirst() async throws {
        let document = """
            <?xml version="1.0" encoding="UTF-8"?>
            <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:dep="http://example.org/departments">
              <dep:Department name="first" code="shared"/>
              <dep:Department xmi:id="shared" name="second"/>
            </xmi:XMI>

            """
        let set = await Self.makeResourceSet()
        let resource = try await XMIParser(resourceSet: set).parse(document, uri: Self.sharedURI)
        let roots = await resource.getRootObjects()
        #expect(await XPathResolver(resource: resource).resolve("shared") == roots[1].id)
    }

    @Test("a trailing query is not part of the identifier")
    func queryIsIgnored() async throws {
        let (_, shared, departments, _) = try await Self.loadProject("")
        let resolver = XPathResolver(resource: shared)
        #expect(await resolver.resolve("it?Department?") == departments[0].id)
        #expect(await resolver.resolve("D-FIN?code?") == departments[2].id)
    }

    @Test("the identifier lookup follows changes to the ID attribute")
    func lookupFollowsChanges() async throws {
        let (_, shared, departments, _) = try await Self.loadProject("")
        await shared.eSet(objectId: departments[2].id, feature: "code", value: "D-ACC")
        #expect(await shared.object(identifiedBy: "D-FIN") == nil)
        #expect(await shared.object(identifiedBy: "D-ACC") == departments[2].id)
        _ = await shared.remove(id: departments[2].id)
        #expect(await shared.object(identifiedBy: "D-ACC") == nil)
        _ = await shared.remove(id: departments[0].id)
        #expect(await shared.object(identifiedBy: "it") == nil)
    }

    @Test("an object is identified by its xmi:id, else by its ID attribute")
    func identifierOfObject() async throws {
        let (_, shared, departments, project) = try await Self.loadProject("")
        #expect(await shared.identifier(of: departments[0].id) == "it")
        #expect(await shared.identifier(of: departments[2].id) == "D-FIN")
        let root = try #require(await project.getRootObjects().first)
        #expect(await project.identifier(of: root.id) == nil)
        #expect(await shared.identifier(of: EUUID()) == nil)
    }

    @Test("an ID attribute value that starts with a slash does not identify an object")
    func pathLikeValueIsNoIdentifier() async throws {
        let set = await Self.makeResourceSet()
        let resource = try await XMIParser(resourceSet: set).parse(
            Self.projectDocument(""), uri: Self.projectURI)
        let root = try #require(await resource.getRootObjects().first)
        await resource.eSet(objectId: root.id, feature: "code", value: "/0")
        #expect(await resource.identifier(of: root.id) == nil)
        await resource.eSet(objectId: root.id, feature: "code", value: "")
        #expect(await resource.identifier(of: root.id) == nil)
    }

    // MARK: - Loading

    @Test(
        "a reference into another document by xmi:id resolves",
        arguments: [
            #"<relatedDepartments href="SharedDeps.xmi#it"/>"#,
            #"<relatedDepartments href="SharedDeps.xmi#hr?query?"/>"#,
        ])
    func crossDocumentXMLIdentifier(reference: String) async throws {
        let (set, _, departments, project) = try await Self.loadProject(reference)
        let expected = reference.contains("#it") ? departments[0].id : departments[1].id
        #expect(try await Self.targets(of: "relatedDepartments", in: project, of: set) == [expected])
    }

    @Test("a reference into another document by ID attribute value resolves")
    func crossDocumentIDAttribute() async throws {
        let (set, _, departments, project) = try await Self.loadProject(
            #"<relatedDepartments href="SharedDeps.xmi#D-FIN"/>"#)
        #expect(try await Self.targets(of: "relatedDepartments", in: project, of: set) == [departments[2].id])
    }

    @Test("identifier and positional references into another document resolve side by side")
    func crossDocumentMixed() async throws {
        let (set, _, departments, project) = try await Self.loadProject(
            """
            <relatedDepartments href="SharedDeps.xmi#/1"/>
              <relatedDepartments href="SharedDeps.xmi#it"/>
              <relatedDepartments href="SharedDeps.xmi#D-FIN"/>
            """)
        #expect(
            try await Self.targets(of: "relatedDepartments", in: project, of: set)
                == [departments[1].id, departments[0].id, departments[2].id])
        let report = await set.resolveAllProxies()
        #expect(report.unresolved.isEmpty)
    }

    @Test("a reference into the same document by ID attribute value resolves", arguments: ["D-SALES", "#D-SALES"])
    func sameDocumentIDAttribute(reference: String) async throws {
        let document = """
            <?xml version="1.0" encoding="UTF-8"?>
            <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:dep="http://example.org/departments">
              <dep:Department name="Marketing" partner="\(reference)"/>
              <dep:Department name="Sales" code="D-SALES"/>
            </xmi:XMI>

            """
        let set = await Self.makeResourceSet()
        let resource = try await XMIParser(resourceSet: set).parse(document, uri: Self.sharedURI)
        let roots = await resource.getRootObjects()
        try #require(roots.count == 2)
        let partner = await resource.eGet(objectId: roots[0].id, feature: "partner")
        #expect(ReferenceValues.identifiers(partner) == [roots[1].id])
    }

    @Test("a reference into the same document by xmi:id resolves", arguments: ["it", "#it"])
    func sameDocumentXMLIdentifier(reference: String) async throws {
        let document = """
            <?xml version="1.0" encoding="UTF-8"?>
            <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:dep="http://example.org/departments">
              <dep:Department name="Marketing" partner="\(reference)"/>
              <dep:Department xmi:id="it" name="IT"/>
            </xmi:XMI>

            """
        let set = await Self.makeResourceSet()
        let resource = try await XMIParser(resourceSet: set).parse(document, uri: Self.sharedURI)
        let roots = await resource.getRootObjects()
        try #require(roots.count == 2)
        let partner = await resource.eGet(objectId: roots[0].id, feature: "partner")
        #expect(ReferenceValues.identifiers(partner) == [roots[1].id])
    }

    // MARK: - Writing

    @Test(
        "a reference into another document keeps the identifier of its target",
        arguments: [XMISerializationOptions.legacy, .emf])
    func writesCrossDocumentIdentifiers(options: XMISerializationOptions) async throws {
        let (set, _, _, project) = try await Self.loadProject(
            """
            <relatedDepartments href="SharedDeps.xmi#/0"/>
              <relatedDepartments href="SharedDeps.xmi#/2"/>
            """)
        _ = try await Self.targets(of: "relatedDepartments", in: project, of: set)
        let text = try await XMISerializer(options: options).serialize(project)
        withExtendedLifetime(set) {}
        #expect(text.contains("SharedDeps.xmi#it\"") || text.contains("SharedDeps.xmi#it "), "\(text)")
        #expect(text.contains("SharedDeps.xmi#D-FIN\""), "\(text)")
        #expect(!text.contains("SharedDeps.xmi#/"), "\(text)")
    }

    @Test(
        "an unresolved identifier reference is written back unchanged",
        arguments: [XMISerializationOptions.legacy, .emf])
    func writesUnresolvedIdentifier(options: XMISerializationOptions) async throws {
        let (_, _, _, project) = try await Self.loadProject(#"<relatedDepartments href="SharedDeps.xmi#it"/>"#)
        let text = try await XMISerializer(options: options).serialize(project)
        #expect(text.contains("SharedDeps.xmi#it\""), "\(text)")
    }

    @Test(
        "a document keeps the xmi:id of its objects and refers to them by it",
        arguments: [XMISerializationOptions.legacy, .emf])
    func writesSameDocumentIdentifiers(options: XMISerializationOptions) async throws {
        let document = """
            <?xml version="1.0" encoding="UTF-8"?>
            <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:dep="http://example.org/departments">
              <dep:Department name="Marketing" partner="/1"/>
              <dep:Department xmi:id="it" name="IT"/>
              <dep:Department name="Sales" code="D-SALES" partner="/0"/>
              <dep:Department name="Legal" partner="/2"/>
            </xmi:XMI>

            """
        let set = await Self.makeResourceSet()
        let resource = try await XMIParser(resourceSet: set).parse(document, uri: Self.sharedURI)
        let text = try await XMISerializer(options: options).serialize(resource)
        #expect(text.contains(#"xmi:id="it""#), "\(text)")
        #expect(text.contains(#"#it""#), "\(text)")
        #expect(text.contains(#"#D-SALES""#), "\(text)")
        #expect(text.contains(#"#/0""#), "\(text)")

        let reloaded = try await XMIParser(resourceSet: set).parse(text, uri: Self.base + "Reloaded.xmi")
        let roots = await reloaded.getRootObjects()
        try #require(roots.count == 4)
        var partners: [[EUUID]] = []
        for root in roots {
            partners.append(ReferenceValues.identifiers(await reloaded.eGet(objectId: root.id, feature: "partner")))
        }
        #expect(partners == [[roots[1].id], [], [roots[0].id], [roots[2].id]])
        #expect(await reloaded.identifier(of: roots[1].id) == "it")
    }
}

