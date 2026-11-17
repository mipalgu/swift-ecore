//
// RootFragmentWritingTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for the fragments that identify the objects of a resource with one or several roots.
///
/// As in EMF, the only root of a resource is `/` and its contents lie below `//`, while root
/// `n` of several is `/n` and its contents lie below `/n/`, whether the contents are named by
/// position (`@tasks.0`) or by name. An object with an identifier is named by it instead.
/// Every writer writes these fragments, and every reader resolves them back to the same
/// objects.
@Suite("Root Fragment Writing")
struct RootFragmentWritingTests {
    /// The writers, with the layouts in which they write references.
    typealias Writer = WrittenLocationURITests.Writer

    /// The namespace URI of the catalogue metamodel.
    static let namespace = "http://www.example.org/catalogue"

    /// The URI of the document with one or several root projects.
    static let projectsURI = "file:///work/models/projects.xmi"

    /// The URI of the document that refers to the projects from outside.
    static let planURI = "file:///work/models/plan.xmi"

    /// The titles of the tasks of every project, in order.
    static let titles = ["alpha", "beta"]

    /// Builds the catalogue metamodel: projects that contain tasks and refer to projects and tasks.
    ///
    /// - Parameter identified: Whether tasks are identified by their `code` attribute.
    /// - Returns: The package.
    static func makeMetamodel(identified: Bool = false) -> EPackage {
        let string = EcorePackage.dataType(.eString) ?? EDataType(name: "EString")
        let task = EClass(
            name: "Task",
            eStructuralFeatures: [
                EAttribute(name: "title", eType: string),
                EAttribute(name: "code", eType: string, isID: identified),
            ])
        var project = EClass(name: "Project")
        project.eStructuralFeatures = [
            EAttribute(name: "name", eType: string),
            EReference(name: "tasks", eType: task, upperBound: -1, containment: true),
            EReference(name: "related", eType: project, upperBound: -1),
            EReference(name: "focus", eType: task),
            EReference(name: "highlights", eType: task, upperBound: -1),
        ]
        return EPackage(name: "catalogue", nsURI: namespace, nsPrefix: "catalogue", eClassifiers: [project, task])
    }

    /// The rules that name projects by their names and tasks by their titles in name-based fragments.
    static let namingRules = [
        FragmentSegmentRule(className: "Project") { object, _ in object.eGet("name") as? String },
        FragmentSegmentRule(className: "Task") { object, _ in object.eGet("title") as? String },
    ]

    /// Creates a resource set with the catalogue metamodel.
    ///
    /// - Parameters:
    ///   - named: Whether projects and tasks take part in name-based fragments.
    ///   - identified: Whether tasks are identified by their `code` attribute.
    /// - Returns: The resource set.
    static func makeSet(named: Bool, identified: Bool = false) async -> ResourceSet {
        let set = ResourceSet()
        let package = makeMetamodel(identified: identified)
        await set.registerMetamodel(package, uri: package.nsURI)
        if named {
            for rule in namingRules { await set.registerFragmentSegmentRule(rule) }
        }
        return set
    }

    /// The projects of a document and a plan that refers to them.
    struct Catalogue {
        /// The resource set that holds both documents.
        let set: ResourceSet
        /// The document with the root projects `p0`, `p1`, and so on.
        let projects: Resource
        /// The document whose only root refers to the projects.
        let plan: Resource
        /// The identifiers of the root projects.
        let roots: [EUUID]
        /// The identifiers of the tasks of each root project.
        let tasks: [[EUUID]]
    }

    /// Builds a document with root projects that refer to each other, and a plan that refers to them.
    ///
    /// Every project holds the tasks `alpha` and `beta`, so a task is identified only together
    /// with its project. The last project and the plan each refer to every project, last
    /// first (`related`), to `beta` of the last project (`focus`), and to `alpha` of the last
    /// and of the first project (`highlights`).
    ///
    /// - Parameters:
    ///   - rootCount: The number of root projects.
    ///   - named: Whether projects and tasks take part in name-based fragments.
    ///   - identified: Whether tasks are identified by their `code` attribute, `T<project>-<task>`.
    ///   - projectsURI: The URI of the document of the projects.
    ///   - planURI: The URI of the plan.
    /// - Returns: The documents.
    static func makeCatalogue(
        rootCount: Int, named: Bool, identified: Bool = false, projectsURI: String = projectsURI,
        planURI: String = planURI
    ) async throws -> Catalogue {
        let set = await makeSet(named: named, identified: identified)
        let package = try #require(await set.getMetamodel(uri: namespace))
        let projectClass = try #require(package.getEClass("Project"))
        let taskClass = try #require(package.getEClass("Task"))
        let projects = await set.createResource(uri: projectsURI)
        var roots: [DynamicEObject] = []
        var tasks: [[EUUID]] = []
        for index in 0..<rootCount {
            var project = DynamicEObject(eClass: projectClass)
            project.eSet("name", value: "p\(index)")
            var ids: [EUUID] = []
            for (position, title) in titles.enumerated() {
                var task = DynamicEObject(eClass: taskClass)
                task.eSet("title", value: title)
                task.eSet("code", value: "T\(index)-\(position)")
                await projects.register(task)
                ids.append(task.id)
            }
            project.eSet("tasks", value: ids)
            roots.append(project)
            tasks.append(ids)
        }
        let last = rootCount - 1
        let related = roots.reversed().map(\.id)
        let highlights = [tasks[last][0], tasks[0][0]]
        roots[last].eSet("related", value: related)
        roots[last].eSet("focus", value: tasks[last][1])
        roots[last].eSet("highlights", value: highlights)
        for root in roots { await projects.add(root) }

        let plan = await set.createResource(uri: planURI)
        var planRoot = DynamicEObject(eClass: projectClass)
        planRoot.eSet("name", value: "plan")
        planRoot.eSet("related", value: related)
        planRoot.eSet("focus", value: tasks[last][1])
        planRoot.eSet("highlights", value: highlights)
        await plan.add(planRoot)
        return Catalogue(set: set, projects: projects, plan: plan, roots: roots.map(\.id), tasks: tasks)
    }

    /// The fragment that a writer writes for a root project.
    ///
    /// - Parameters:
    ///   - position: The position of the root.
    ///   - rootCount: The number of roots of its document.
    ///   - writer: The writer.
    /// - Returns: The fragment, without `#`.
    static func rootFragment(_ position: Int, of rootCount: Int, by writer: Writer) -> String {
        guard rootCount == 1 else { return "/\(position)" }
        return writer == .json ? "//" : "/"
    }

    /// The fragment that a writer writes for a task.
    ///
    /// - Parameters:
    ///   - position: The position of the project that holds the task.
    ///   - task: The position of the task in its project.
    ///   - rootCount: The number of roots of the document.
    ///   - named: Whether the writer names the task by its title.
    /// - Returns: The fragment, without `#`.
    static func taskFragment(_ position: Int, _ task: Int, of rootCount: Int, named: Bool) -> String {
        let root = rootCount == 1 ? "/" : "/\(position)"
        return root + "/" + (named ? titles[task] : "@tasks.\(task)")
    }

    /// The references that a document of a writer holds in the features set by makeCatalogue.
    ///
    /// - Parameters:
    ///   - rootCount: The number of root projects.
    ///   - writer: The writer.
    ///   - named: Whether the writer writes name-based fragments.
    ///   - document: The text before each fragment: `#` for the same document in XMI, the
    ///     relative URI and `#` for the document of the projects.
    /// - Returns: The expected references of `related`, `focus` and `highlights`.
    static func expected(rootCount: Int, writer: Writer, named: Bool, document: String)
        -> (related: [String], focus: [String], highlights: [String])
    {
        let last = rootCount - 1
        let related = (0..<rootCount).reversed().map { document + rootFragment($0, of: rootCount, by: writer) }
        let focus = [document + taskFragment(last, 1, of: rootCount, named: named)]
        let highlights = [last, 0].map { document + taskFragment($0, 0, of: rootCount, named: named) }
        return (related, focus, highlights)
    }

    /// The reference texts of a feature that only one root object of a document sets.
    ///
    /// - Parameters:
    ///   - feature: The name of the feature.
    ///   - text: The document.
    ///   - writer: The writer of the document.
    /// - Returns: The references, in order.
    static func references(_ feature: String, in text: String, by writer: Writer) throws -> [String] {
        guard writer == .json else { return try writer.references(feature, in: text) }
        let document = try JSONSerialization.jsonObject(with: Data(text.utf8))
        let roots = try (document as? [[String: Any]]) ?? [#require(document as? [String: Any])]
        let root = try #require(roots.first { $0[feature] != nil }, "\(text)")
        let value = try #require(root[feature])
        let entries = try (value as? [[String: Any]]) ?? [#require(value as? [String: Any])]
        return try entries.map { try #require($0[JSONSyntax.referenceKey] as? String) }
    }

    /// Checks the references that a written document holds.
    ///
    /// - Parameters:
    ///   - text: The document.
    ///   - writer: The writer.
    ///   - expected: The expected references.
    static func expectReferences(
        in text: String, by writer: Writer, _ expected: (related: [String], focus: [String], highlights: [String])
    ) throws {
        #expect(try references("related", in: text, by: writer) == expected.related, "\(text)")
        #expect(try references("focus", in: text, by: writer) == expected.focus, "\(text)")
        #expect(try references("highlights", in: text, by: writer) == expected.highlights, "\(text)")
    }

    /// Whether a writer writes name-based fragments for objects that have names.
    ///
    /// - Parameter writer: The writer.
    /// - Returns: `true` for the EMF-style layouts.
    static func writesNames(_ writer: Writer) -> Bool {
        writer != .json && writer.xmiOptions.nameBasedFragments
    }

    // MARK: - Fragment navigation

    @Test("the name-based fragment of a root and of its contents names the position of the root", arguments: [1, 2, 3])
    func navigatorFragments(rootCount: Int) async throws {
        let catalogue = try await Self.makeCatalogue(rootCount: rootCount, named: true)
        let navigator = FragmentNavigator(resource: catalogue.projects)
        for position in 0..<rootCount {
            let root = await navigator.fragment(for: catalogue.roots[position])
            #expect(root == (rootCount == 1 ? "/" : "/\(position)"))
            for task in Self.titles.indices {
                let fragment = await navigator.fragment(for: catalogue.tasks[position][task])
                #expect(fragment == Self.taskFragment(position, task, of: rootCount, named: true))
                let text = try #require(fragment)
                let resolved = try #require(await navigator.resolve(text))
                #expect(resolved.id == catalogue.tasks[position][task])
            }
            let rootText = try #require(root)
            #expect(await navigator.resolve(rootText)?.id == catalogue.roots[position])
        }
    }

    /// Builds native root packages that each hold a class `Item` with an attribute `label`.
    ///
    /// - Parameter count: The number of packages.
    /// - Returns: The packages, named `pkg0`, `pkg1`, and so on.
    static func makePackages(_ count: Int) -> [EPackage] {
        let string = EcorePackage.dataType(.eString) ?? EDataType(name: "EString")
        return (0..<count).map { index in
            let item = EClass(name: "Item", eStructuralFeatures: [EAttribute(name: "label", eType: string)])
            return EPackage(
                name: "pkg\(index)", nsURI: "http://www.example.org/pkg\(index)", nsPrefix: "pkg\(index)",
                eClassifiers: [item])
        }
    }

    @Test(
        "the name-based fragments of native packages agree with those of the metamodel writers",
        arguments: [1, 2, 3])
    func navigatorNativePackages(rootCount: Int) async throws {
        let packages = Self.makePackages(rootCount)
        let resource = Resource(uri: "file:///work/models/packages.ecore")
        for package in packages { await resource.add(package) }
        let navigator = FragmentNavigator(resource: resource)
        for (position, package) in packages.enumerated() {
            let fragments = EcoreFragment.fragments(in: package, rootIndex: rootCount == 1 ? nil : position)
            let item = try #require(package.getEClass("Item"))
            let label = try #require(item.eStructuralFeatures.first)
            for identifier in [package.id, item.id, label.id] {
                let fragment = try #require(await navigator.fragment(for: identifier))
                #expect(fragment == fragments[identifier])
                #expect(await navigator.resolve(fragment)?.id == identifier)
            }
            #expect(await navigator.fragment(for: item.id) == (rootCount == 1 ? "//Item" : "/\(position)/Item"))
        }
    }

    @Test("the EMF fragment rule names roots and contents alike for every kind of segment", arguments: [1, 2, 3])
    func sharedRootSegments(rootCount: Int) async throws {
        let catalogue = try await Self.makeCatalogue(rootCount: rootCount, named: true)
        let positional = await PositionalFragments.index(of: catalogue.projects)
        let navigator = FragmentNavigator(resource: catalogue.projects)
        for position in 0..<rootCount {
            let root = PositionalFragments.rootSegment(position, rootCount: rootCount)
            #expect(positional[catalogue.roots[position]] == root)
            #expect(await navigator.fragment(for: catalogue.roots[position]) == root)
            #expect(positional[catalogue.tasks[position][1]] == PositionalFragments.path(below: root, segments: ["@tasks.1"]))
            #expect(await navigator.fragment(for: catalogue.tasks[position][1]) == PositionalFragments.path(below: root, segments: ["beta"]))
        }
        #expect(PositionalFragments.path(below: "/", segments: []) == "/")
        #expect(PositionalFragments.path(below: "/2", segments: ["a", "b"]) == "/2/a/b")
    }

    // MARK: - Writers

    @Test(
        "every writer refers to roots and their contents by the position of the root",
        arguments: Writer.allCases, [1, 2, 3])
    func writers(writer: Writer, rootCount: Int) async throws {
        for named in [false, true] {
            let catalogue = try await Self.makeCatalogue(rootCount: rootCount, named: named)
            let names = named && Self.writesNames(writer)
            let local = writer == .json ? "" : "#"
            let projects = try await writer.render(catalogue.projects, at: nil)
            try Self.expectReferences(
                in: projects, by: writer,
                Self.expected(rootCount: rootCount, writer: writer, named: names, document: local))
            let plan = try await writer.render(catalogue.plan, at: nil)
            try Self.expectReferences(
                in: plan, by: writer,
                Self.expected(rootCount: rootCount, writer: writer, named: names, document: "projects.xmi#"))
        }
    }

    @Test(
        "every writer refers to objects with identifiers by their identifiers in documents with several roots",
        arguments: Writer.allCases, [1, 3])
    func identifiedTasks(writer: Writer, rootCount: Int) async throws {
        let catalogue = try await Self.makeCatalogue(rootCount: rootCount, named: true, identified: true)
        let last = rootCount - 1
        let plan = try await writer.render(catalogue.plan, at: nil)
        let projects = try await writer.render(catalogue.projects, at: nil)
        if writer == .json {
            #expect(try Self.references("focus", in: plan, by: writer) == ["projects.xmi#" + Self.taskFragment(last, 1, of: rootCount, named: false)])
            return
        }
        #expect(try Self.references("focus", in: plan, by: writer) == ["projects.xmi#T\(last)-1"], "\(plan)")
        #expect(try Self.references("highlights", in: plan, by: writer) == ["projects.xmi#T\(last)-0", "projects.xmi#T0-0"])
        #expect(try Self.references("focus", in: projects, by: writer) == ["#T\(last)-1"], "\(projects)")
        #expect(
            try Self.references("related", in: projects, by: writer)
                == (0..<rootCount).reversed().map { "#" + Self.rootFragment($0, of: rootCount, by: writer) })
    }

    // MARK: - Round trips through files

    /// A description of an object of a loaded catalogue: `p1` for a project, `p1/beta` for a task.
    ///
    /// - Parameters:
    ///   - object: The object.
    ///   - roots: The root projects of the document that holds it.
    /// - Returns: The description.
    static func label(of object: any EObject, roots: [any EObject]) throws -> String {
        let dynamic = try #require(object as? DynamicEObject)
        if let name = dynamic.eGet("name") as? String { return name }
        let title = try #require(dynamic.eGet("title") as? String)
        for case let root as DynamicEObject in roots
        where ReferenceValues.identifiers(root.eGet("tasks")).contains(object.id) {
            return "\(try #require(root.eGet("name") as? String))/\(title)"
        }
        return "?/\(title)"
    }

    /// The descriptions of the objects that a reference value refers to, in order.
    ///
    /// - Parameters:
    ///   - value: The reference value.
    ///   - resource: The resource that holds the value.
    ///   - set: The resource set that holds or loads the referenced documents.
    /// - Returns: The description of each referenced object.
    static func labels(of value: (any EcoreValue)?, in resource: Resource, set: ResourceSet) async throws -> [String] {
        var labels: [String] = []
        for element in ValueList.elements(of: value) {
            let object: (any EObject)?
            let holder: Resource?
            switch element {
            case let identifier as EUUID:
                let found = await set.resolve(identifier)
                object = found?.object
                holder = found?.resource
            case let proxy as ResourceProxy where proxy.uri == resource.uri:
                object = await XPathResolver(resource: resource).resolveObject("#" + proxy.fragment)
                holder = resource
            case let proxy as ResourceProxy:
                object = await proxy.resolveObject(in: set)
                holder = await proxy.targetResource(in: set)
            default:
                object = nil
                holder = nil
            }
            let found = try #require(object, "\(element)")
            let document = try #require(holder)
            labels.append(try label(of: found, roots: await document.getRootObjects()))
        }
        return labels
    }

    @Test(
        "a document with several roots and a document that refers to it load back to the same objects",
        arguments: Writer.allCases, [1, 2, 3])
    func fileRoundTrip(writer: Writer, rootCount: Int) async throws {
        for named in [false, true] {
            let root = try WrittenLocationURITests.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let projectsURL = root.appendingPathComponent("projects." + writer.fileExtension)
            let planURL = root.appendingPathComponent("plan." + writer.fileExtension)
            let catalogue = try await Self.makeCatalogue(
                rootCount: rootCount, named: named, projectsURI: WrittenLocationURITests.uri(of: projectsURL),
                planURI: WrittenLocationURITests.uri(of: planURL))
            var diagnostics = ConversionDiagnostics()
            try await ModelIO.save(catalogue.projects, to: projectsURL, xmiOptions: writer.xmiOptions, diagnostics: &diagnostics)
            try await ModelIO.save(catalogue.plan, to: planURL, xmiOptions: writer.xmiOptions, diagnostics: &diagnostics)

            let last = rootCount - 1
            let related = (0..<rootCount).reversed().map { "p\($0)" }
            let focus = ["p\(last)/beta"]
            let highlights = ["p\(last)/alpha", "p0/alpha"]
            let set = await Self.makeSet(named: named)
            let plan = try await ModelIO.load(url: planURL, resourceSet: set)
            let planRoot = try #require(await plan.resource.getRootObjects().first as? DynamicEObject)
            let planText = try String(contentsOf: planURL, encoding: .utf8)
            #expect(try await Self.labels(of: planRoot.eGet("related"), in: plan.resource, set: set) == related, "\(planText)")
            #expect(try await Self.labels(of: planRoot.eGet("focus"), in: plan.resource, set: set) == focus, "\(planText)")
            #expect(try await Self.labels(of: planRoot.eGet("highlights"), in: plan.resource, set: set) == highlights)

            let reading = await Self.makeSet(named: named)
            let projects = try await ModelIO.load(url: projectsURL, resourceSet: reading)
            let roots = await projects.resource.getRootObjects()
            #expect(roots.count == rootCount)
            let holder = try #require(roots.last as? DynamicEObject)
            let text = try String(contentsOf: projectsURL, encoding: .utf8)
            #expect(try await Self.labels(of: holder.eGet("related"), in: projects.resource, set: reading) == related, "\(text)")
            #expect(try await Self.labels(of: holder.eGet("focus"), in: projects.resource, set: reading) == focus, "\(text)")
            #expect(try await Self.labels(of: holder.eGet("highlights"), in: projects.resource, set: reading) == highlights)
        }
    }

    @Test(
        "objects with identifiers in a document with several roots load back to the same objects",
        arguments: Writer.allCases)
    func identifiedRoundTrip(writer: Writer) async throws {
        let root = try WrittenLocationURITests.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let projectsURL = root.appendingPathComponent("projects." + writer.fileExtension)
        let planURL = root.appendingPathComponent("plan." + writer.fileExtension)
        let catalogue = try await Self.makeCatalogue(
            rootCount: 3, named: true, identified: true, projectsURI: WrittenLocationURITests.uri(of: projectsURL),
            planURI: WrittenLocationURITests.uri(of: planURL))
        var diagnostics = ConversionDiagnostics()
        try await ModelIO.save(catalogue.projects, to: projectsURL, xmiOptions: writer.xmiOptions, diagnostics: &diagnostics)
        try await ModelIO.save(catalogue.plan, to: planURL, xmiOptions: writer.xmiOptions, diagnostics: &diagnostics)
        let set = await Self.makeSet(named: true, identified: true)
        let plan = try await ModelIO.load(url: planURL, resourceSet: set)
        let planRoot = try #require(await plan.resource.getRootObjects().first as? DynamicEObject)
        #expect(try await Self.labels(of: planRoot.eGet("focus"), in: plan.resource, set: set) == ["p2/beta"])
        #expect(try await Self.labels(of: planRoot.eGet("highlights"), in: plan.resource, set: set) == ["p2/alpha", "p0/alpha"])
        #expect(try await Self.labels(of: planRoot.eGet("related"), in: plan.resource, set: set) == ["p2", "p1", "p0"])
    }

    // MARK: - Reading

    /// A document with three root projects, written by hand, that refers to roots and their
    /// contents by position and by name.
    static let handWritten = """
        <?xml version="1.0" encoding="UTF-8"?>
        <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:catalogue="http://www.example.org/catalogue">
          <catalogue:Project name="p0">
            <tasks title="alpha"/>
            <tasks title="beta"/>
          </catalogue:Project>
          <catalogue:Project name="p1">
            <tasks title="alpha"/>
            <tasks title="beta"/>
          </catalogue:Project>
          <catalogue:Project name="p2" related="#/ #/0 #/1 #/2" focus="#/2/@tasks.1" highlights="#//@tasks.0 #/1/@tasks.0">
            <tasks title="alpha"/>
            <tasks title="beta"/>
          </catalogue:Project>
        </xmi:XMI>

        """

    @Test("a reader resolves the fragments of roots and their contents by position")
    func readsPositionalFragments() async throws {
        let set = await Self.makeSet(named: false)
        let resource = try await XMIParser(resourceSet: set).parse(Self.handWritten, uri: Self.projectsURI)
        let holder = try #require(await resource.getRootObjects().last as? DynamicEObject)
        #expect(try await Self.labels(of: holder.eGet("related"), in: resource, set: set) == ["p0", "p0", "p1", "p2"])
        #expect(try await Self.labels(of: holder.eGet("focus"), in: resource, set: set) == ["p2/beta"])
        #expect(try await Self.labels(of: holder.eGet("highlights"), in: resource, set: set) == ["p0/alpha", "p1/alpha"])
        let resolver = XPathResolver(resource: resource)
        let roots = await resource.getRootObjects()
        for (fragment, expected) in [("/", "p0"), ("//@tasks.1", "p0/beta"), ("/1", "p1"), ("/2/@tasks.0", "p2/alpha")] {
            let object = try #require(await resolver.resolveObject("#" + fragment))
            #expect(try Self.label(of: object, roots: roots) == expected)
            let json = try #require(await JSONFragments.resolve(fragment: fragment, in: resource))
            let viaJSON = try #require(await resource.resolve(json))
            #expect(try Self.label(of: viaJSON, roots: roots) == expected)
        }
    }

    @Test("a reader resolves the name-based fragments of roots and their contents")
    func readsNamedFragments() async throws {
        let set = await Self.makeSet(named: true)
        let resource = try await XMIParser(resourceSet: set).parse(Self.handWritten, uri: Self.projectsURI)
        let roots = await resource.getRootObjects()
        let navigator = FragmentNavigator(resource: resource)
        let resolver = XPathResolver(resource: resource)
        for (fragment, expected) in [("/", "p0"), ("//beta", "p0/beta"), ("/1", "p1"), ("/2/alpha", "p2/alpha"), ("/0/beta", "p0/beta")] {
            let object = try #require(await navigator.resolve(fragment), "\(fragment)")
            #expect(try Self.label(of: object, roots: roots) == expected)
            let viaResolver = try #require(await resolver.resolveObject("#" + fragment), "\(fragment)")
            #expect(try Self.label(of: viaResolver, roots: roots) == expected)
        }
    }
}
