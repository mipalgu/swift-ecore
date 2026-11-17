//
// MixedReferenceWritingTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// A value of a type that no document format can hold.
private struct OpaqueValue: EcoreValue {
    /// A number that makes values distinguishable.
    let code: Int
}

/// Tests for how the XMI and JSON writers write references whose values mix objects of the
/// written document with objects of other documents, and values that no document can hold.
@Suite("Mixed Reference Writing")
struct MixedReferenceWritingTests {
    /// The namespace URI of the planning metamodel.
    static let namespace = "http://www.example.org/planning"

    /// The URI of the document whose tasks the plan refers to.
    static let sourceURI = "file:///models/project.xmi"

    /// The URI of the document that holds the plan.
    static let planURI = "file:///models/plan.xmi"

    /// The URI at which written plans are read back.
    static let copyURI = "file:///models/plan-copy.xmi"

    /// Builds the planning metamodel: projects that contain tasks and refer to some of them.
    ///
    /// - Returns: The package.
    static func makeMetamodel() -> EPackage {
        let string = EcorePackage.dataType(.eString) ?? EDataType(name: "EString")
        let float = EcorePackage.dataType(.eFloat) ?? EDataType(name: "EFloat")
        let task = EClass(name: "Task", eStructuralFeatures: [EAttribute(name: "title", eType: string)])
        let project = EClass(
            name: "Project",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EAttribute(name: "labels", eType: string, upperBound: -1),
                EAttribute(name: "weights", eType: float, upperBound: -1),
                EReference(name: "tasks", eType: task, upperBound: -1, containment: true),
                EReference(name: "highlights", eType: task, upperBound: -1),
                EReference(name: "lead", eType: task),
            ])
        return EPackage(name: "planning", nsURI: namespace, nsPrefix: "planning", eClassifiers: [project, task])
    }

    /// A source project and a plan in one resource set.
    struct Planning {
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
            ResourceProxy(uri: MixedReferenceWritingTests.sourceURI, fragment: "//@tasks.\(index)")
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

    /// Builds a project with tasks in a resource of a set.
    ///
    /// - Parameters:
    ///   - set: The resource set.
    ///   - uri: The URI of the resource.
    ///   - name: The name of the project, which also prefixes the titles of its tasks.
    ///   - count: The number of tasks.
    /// - Returns: The resource, the identifier of the project, and those of its tasks.
    static func makeProject(in set: ResourceSet, uri: String, name: String, count: Int) async throws
        -> (resource: Resource, root: EUUID, tasks: [EUUID])
    {
        let package = try #require(await set.getMetamodel(uri: namespace))
        let taskClass = try #require(package.getEClass("Task"))
        let tasks = (0..<count).map { index -> DynamicEObject in
            var task = DynamicEObject(eClass: taskClass)
            task.eSet("title", value: "\(name) \(index)")
            return task
        }
        var project = DynamicEObject(eClass: try #require(package.getEClass("Project")))
        project.eSet("name", value: name.capitalized)
        project.eSet("tasks", value: tasks.map(\.id))
        let resource = await set.createResource(uri: uri)
        for task in tasks { await resource.register(task) }
        await resource.add(project)
        return (resource, project.id, tasks.map(\.id))
    }

    /// Builds a source project with three tasks and a plan with two tasks.
    ///
    /// - Returns: The documents.
    static func makePlanning() async throws -> Planning {
        let set = ResourceSet()
        let package = makeMetamodel()
        await set.registerMetamodel(package, uri: package.nsURI)
        let source = try await makeProject(in: set, uri: sourceURI, name: "source", count: 3)
        let plan = try await makeProject(in: set, uri: planURI, name: "plan", count: 2)
        return Planning(
            set: set, source: source.resource, plan: plan.resource, planRoot: plan.root,
            sourceTasks: source.tasks, planTasks: plan.tasks)
    }

    /// The value that mixes tasks of the plan with proxies to tasks of the source project.
    ///
    /// - Parameter planning: The documents.
    /// - Returns: Plan task 1, source task 2, plan task 0, and source task 0, in this order.
    static func mixed(_ planning: Planning) -> EcoreValueArray {
        EcoreValueArray([planning.planTasks[1], planning.sourceProxy(2), planning.planTasks[0], planning.sourceProxy(0)])
    }

    /// The titles of the tasks that mixed(_:) refers to, in order.
    static let mixedTitles = ["plan 1", "source 2", "plan 0", "source 0"]

    /// The titles of the objects that a reference value refers to, in order.
    ///
    /// Identifiers are looked up in the resource set; a proxy into the resource that holds
    /// the value is resolved against that resource, and any other proxy through the set.
    ///
    /// - Parameters:
    ///   - value: The reference value.
    ///   - resource: The resource that holds the value.
    ///   - set: The resource set.
    /// - Returns: The `title` of each referenced object.
    static func titles(of value: (any EcoreValue)?, in resource: Resource, set: ResourceSet) async throws -> [String] {
        var titles: [String] = []
        for element in ValueList.elements(of: value) {
            let object: (any EObject)?
            switch element {
            case let identifier as EUUID:
                object = await set.resolve(identifier)?.object
            case let proxy as ResourceProxy where proxy.uri == resource.uri:
                let identifier = await XPathResolver(resource: resource).resolve("#" + proxy.fragment)
                object = await identifier.asyncMap { await resource.resolve($0) } ?? nil
            case let proxy as ResourceProxy:
                object = await proxy.resolveObject(in: set)
            default:
                object = nil
            }
            let task = try #require(object as? DynamicEObject, "\(element)")
            titles.append(try #require(task.eGet("title") as? String))
        }
        return titles
    }

    /// The `$ref` texts of a feature of the root object of a JSON document.
    ///
    /// - Parameters:
    ///   - feature: The name of the feature.
    ///   - text: The JSON document.
    /// - Returns: The reference texts in order.
    static func jsonReferences(_ feature: String, in text: String) throws -> [String] {
        let document = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let entries = try #require(document[feature] as? [[String: Any]], "\(text)")
        return try entries.map { try #require($0[JSONSyntax.referenceKey] as? String) }
    }

    /// The XMI options of the EMF layout with references written as `href` elements.
    static let emfHrefs: XMISerializationOptions = {
        var options = XMISerializationOptions.emf
        options.attributeStyleReferences = false
        return options
    }()

    // MARK: - Legacy writer

    @Test("the default writer writes a mixed reference as href elements in order")
    func legacyMixed() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("highlights", Self.mixed(planning))
        let text = try await XMISerializer().serialize(planning.plan)
        #expect(
            text == """
                <?xml version="1.0" encoding="UTF-8"?>
                <planning:Project xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:planning="http://www.example.org/planning" name="Plan">
                    <tasks title="plan 0"/>
                    <tasks title="plan 1"/>
                    <highlights href="#//@tasks.1"/>
                    <highlights href="file:///models/project.xmi#//@tasks.2"/>
                    <highlights href="#//@tasks.0"/>
                    <highlights href="file:///models/project.xmi#//@tasks.0"/>
                </planning:Project>

                """, "\(text)")
    }

    @Test("the default writer writes objects of another resource held beside proxies")
    func legacyMixedForeignIdentifier() async throws {
        let planning = try await Self.makePlanning()
        await planning.set(
            "highlights", EcoreValueArray([planning.sourceTasks[1], planning.sourceProxy(2), planning.planTasks[0]]))
        let text = try await XMISerializer().serialize(planning.plan)
        let hrefs = text.split(separator: "\n").filter { $0.contains("<highlights ") }.map(String.init)
        #expect(
            hrefs == [
                "    <highlights href=\"file:///models/project.xmi#//@tasks.1\"/>",
                "    <highlights href=\"file:///models/project.xmi#//@tasks.2\"/>",
                "    <highlights href=\"#//@tasks.0\"/>",
            ], "\(text)")
        #expect(!text.contains("highlights=\""), "\(text)")
    }

    @Test(
        "the default writer writes homogeneous reference arrays as href elements",
        arguments: [true, false])
    func legacyHomogeneousArrays(resolved: Bool) async throws {
        let planning = try await Self.makePlanning()
        let value =
            resolved
            ? EcoreValueArray([planning.planTasks[1], planning.planTasks[0]])
            : EcoreValueArray([planning.sourceProxy(1), planning.sourceProxy(0)])
        await planning.set("highlights", value)
        let text = try await XMISerializer().serialize(planning.plan)
        let expected =
            resolved
            ? ["#//@tasks.1", "#//@tasks.0"]
            : ["file:///models/project.xmi#//@tasks.1", "file:///models/project.xmi#//@tasks.0"]
        let hrefs = text.split(separator: "\n").filter { $0.contains("<highlights ") }.map(String.init)
        #expect(hrefs == expected.map { "    <highlights href=\"\($0)\"/>" }, "\(text)")
        #expect(!text.contains("highlights=\""), "\(text)")
        #expect(!text.contains("EcoreValueArray"), "\(text)")
    }

    @Test("the default writer writes a mixed value of an undeclared feature as href elements")
    func legacyUndeclaredMixed() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("related", Self.mixed(planning))
        let text = try await XMISerializer().serialize(planning.plan)
        let hrefs = text.split(separator: "\n").filter { $0.contains("<related ") }.map(String.init)
        #expect(hrefs.count == 4, "\(text)")
        #expect(hrefs.first == "    <related href=\"#//@tasks.1\"/>", "\(text)")
        #expect(!text.contains("related=\""), "\(text)")
    }

    @Test("the default writer writes lists of any primitive type as elements")
    func legacyPrimitiveLists() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("weights", [Float(1.5), Float(2.25)])
        await planning.set("labels", EcoreValueArray(["urgent", "later"]))
        let text = try await XMISerializer().serialize(planning.plan)
        #expect(text.contains("<weights>1.5</weights>"), "\(text)")
        #expect(text.contains("<weights>2.25</weights>"), "\(text)")
        #expect(text.contains("<labels>urgent</labels>"), "\(text)")
        #expect(!text.contains("weights=\""), "\(text)")
        #expect(!text.contains("labels=\""), "\(text)")
    }

    // MARK: - EMF-style writer

    @Test("the EMF writer writes a mixed reference as one attribute in order")
    func emfMixed() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("highlights", Self.mixed(planning))
        let text = try await XMISerializer(options: .emf).serialize(planning.plan)
        #expect(
            text == """
                <?xml version="1.0" encoding="UTF-8"?>
                <planning:Project xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:planning="http://www.example.org/planning" name="Plan" highlights="#//@tasks.1 project.xmi#//@tasks.2 #//@tasks.0 project.xmi#//@tasks.0">
                  <tasks title="plan 0"/>
                  <tasks title="plan 1"/>
                </planning:Project>

                """, "\(text)")
    }

    @Test("the EMF writer writes a mixed reference as href elements in order")
    func emfMixedHrefs() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("highlights", Self.mixed(planning))
        let text = try await XMISerializer(options: Self.emfHrefs).serialize(planning.plan)
        #expect(
            text == """
                <?xml version="1.0" encoding="UTF-8"?>
                <planning:Project xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:planning="http://www.example.org/planning" name="Plan">
                  <tasks title="plan 0"/>
                  <tasks title="plan 1"/>
                  <highlights href="#//@tasks.1"/>
                  <highlights href="project.xmi#//@tasks.2"/>
                  <highlights href="#//@tasks.0"/>
                  <highlights href="project.xmi#//@tasks.0"/>
                </planning:Project>

                """, "\(text)")
    }

    @Test("the EMF writer writes objects of another resource held beside proxies")
    func emfMixedForeignIdentifier() async throws {
        let planning = try await Self.makePlanning()
        await planning.set(
            "highlights", EcoreValueArray([planning.sourceTasks[1], planning.sourceProxy(2), planning.planTasks[0]]))
        let text = try await XMISerializer(options: .emf).serialize(planning.plan)
        #expect(text.contains("highlights=\"project.xmi#//@tasks.1 project.xmi#//@tasks.2 #//@tasks.0\""), "\(text)")
    }

    @Test("the EMF writer spells same-document entries of a mixed reference in the plain style")
    func emfMixedPlain() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("highlights", Self.mixed(planning))
        var options = XMISerializationOptions.emf
        options.referenceStyle = .plain
        let text = try await XMISerializer(options: options).serialize(planning.plan)
        #expect(
            text.contains("highlights=\"//@tasks.1 project.xmi#//@tasks.2 //@tasks.0 project.xmi#//@tasks.0\""),
            "\(text)")
    }

    @Test("the EMF writer writes absolute URIs in a mixed reference without relative URIs")
    func emfMixedAbsolute() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("highlights", Self.mixed(planning))
        var options = XMISerializationOptions.emf
        options.relativeURIs = false
        let text = try await XMISerializer(options: options).serialize(planning.plan)
        #expect(
            text.contains(
                "highlights=\"#//@tasks.1 file:///models/project.xmi#//@tasks.2 #//@tasks.0 file:///models/project.xmi#//@tasks.0\""),
            "\(text)")
    }

    @Test(
        "the EMF writer writes homogeneous reference arrays as one attribute",
        arguments: [true, false])
    func emfHomogeneousArrays(resolved: Bool) async throws {
        let planning = try await Self.makePlanning()
        let value =
            resolved
            ? EcoreValueArray([planning.planTasks[1], planning.planTasks[0]])
            : EcoreValueArray([planning.sourceProxy(1), planning.sourceProxy(0)])
        await planning.set("highlights", value)
        let text = try await XMISerializer(options: .emf).serialize(planning.plan)
        let expected = resolved ? "#//@tasks.1 #//@tasks.0" : "project.xmi#//@tasks.1 project.xmi#//@tasks.0"
        #expect(text.contains("highlights=\"\(expected)\""), "\(text)")
    }

    @Test("the EMF writer writes single-valued references beside a mixed reference")
    func emfSingleValued() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("highlights", Self.mixed(planning))
        await planning.set("lead", planning.sourceProxy(1))
        let text = try await XMISerializer(options: .emf).serialize(planning.plan)
        #expect(text.contains(" lead=\"project.xmi#//@tasks.1\""), "\(text)")
        await planning.set("lead", planning.planTasks[1])
        let local = try await XMISerializer(options: .emf).serialize(planning.plan)
        #expect(local.contains(" lead=\"#//@tasks.1\""), "\(local)")
    }

    @Test("the EMF writer writes a mixed value of an undeclared feature")
    func emfUndeclaredMixed() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("related", Self.mixed(planning))
        var diagnostics = ConversionDiagnostics()
        let text = try await XMISerializer(options: .emf).serialize(planning.plan, diagnostics: &diagnostics)
        #expect(
            text.contains("related=\"#//@tasks.1 project.xmi#//@tasks.2 #//@tasks.0 project.xmi#//@tasks.0\""),
            "\(text)")
        #expect(diagnostics.isEmpty, "\(diagnostics.warnings)")
    }

    @Test("the EMF writer writes lists of any primitive type")
    func emfPrimitiveLists() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("weights", [Float(1.5), Float(2.25)])
        await planning.set("labels", EcoreValueArray(["urgent", "later"]))
        let text = try await XMISerializer(options: .emf).serialize(planning.plan)
        #expect(text.contains("<weights>1.5</weights>"), "\(text)")
        #expect(text.contains("<labels>later</labels>"), "\(text)")
        #expect(!text.contains("EcoreValueArray"), "\(text)")
        #expect(!text.contains("["), "\(text)")
        var joined = XMISerializationOptions.emf
        joined.manyValuedAttributesAsElements = false
        let attributes = try await XMISerializer(options: joined).serialize(planning.plan)
        #expect(attributes.contains("labels=\"urgent later\""), "\(attributes)")
        #expect(attributes.contains("weights=\"1.5 2.25\""), "\(attributes)")
    }

    // MARK: - JSON writer

    @Test("the JSON writer writes a mixed reference as references in order")
    func jsonMixed() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("highlights", Self.mixed(planning))
        await planning.set("related", Self.mixed(planning))
        let text = try await JSONSerializer().serialize(planning.plan)
        let expected = ["//@tasks.1", "project.xmi#//@tasks.2", "//@tasks.0", "project.xmi#//@tasks.0"]
        #expect(try Self.jsonReferences("highlights", in: text) == expected, "\(text)")
        #expect(try Self.jsonReferences("related", in: text) == expected, "\(text)")
        #expect(!text.contains("ResourceProxy"), "\(text)")
    }

    // MARK: - Round trips

    @Test(
        "a mixed reference written as XMI loads back to the same objects in order",
        arguments: [XMISerializationOptions.legacy, .emf, emfHrefs])
    func xmiRoundTrip(options: XMISerializationOptions) async throws {
        let planning = try await Self.makePlanning()
        await planning.set("highlights", Self.mixed(planning))
        await planning.set("lead", planning.sourceProxy(1))
        let text = try await XMISerializer(options: options).serialize(planning.plan)
        let copy = try await XMIParser(resourceSet: planning.set).parse(text, uri: Self.copyURI)
        let root = try #require(await copy.getRootObjects().first as? DynamicEObject)
        #expect(
            try await Self.titles(of: root.eGet("highlights"), in: copy, set: planning.set) == Self.mixedTitles,
            "\(text)")
        #expect(try await Self.titles(of: root.eGet("lead"), in: copy, set: planning.set) == ["source 1"], "\(text)")

        // The EMF layout writes a proxy into the written document as a fragment, so the text is stable
        if options != .legacy {
            let again = try await XMISerializer(options: options).serialize(copy)
            #expect(again == text)
        }

        let report = await copy.resolveProxies()
        #expect(report.unresolved.isEmpty, "\(report.unresolved)")
        let resolved = try #require(await copy.getRootObjects().first as? DynamicEObject)
        #expect(resolved.eGet("highlights") is [EUUID])
        #expect(
            try await Self.titles(of: resolved.eGet("highlights"), in: copy, set: planning.set) == Self.mixedTitles)
    }

    @Test("a mixed reference written as JSON loads back to the same objects in order")
    func jsonRoundTrip() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("highlights", Self.mixed(planning))
        await planning.set("lead", planning.sourceProxy(1))
        let text = try await JSONSerializer().serialize(planning.plan)
        let copy = try await JSONParser(resourceSet: planning.set).parse(
            Data(text.utf8), uri: "file:///models/plan-copy.json")
        let root = try #require(await copy.getRootObjects().first as? DynamicEObject)
        #expect(
            try await Self.titles(of: root.eGet("highlights"), in: copy, set: planning.set) == Self.mixedTitles,
            "\(text)")
        #expect(try await Self.titles(of: root.eGet("lead"), in: copy, set: planning.set) == ["source 1"], "\(text)")
    }

    // MARK: - Objects and primitive values

    @Test("objects held by a list of a reference are left out of XMI and nested in JSON")
    func objectListsInReferences() async throws {
        let planning = try await Self.makePlanning()
        let taskClass = try #require(await planning.set.getMetamodel(uri: Self.namespace)?.getEClass("Task"))
        var loose = DynamicEObject(eClass: taskClass)
        loose.eSet("title", value: "loose")
        await planning.set("highlights", EcoreValueArray([loose]))
        for options in [XMISerializationOptions.legacy, .emf] {
            var diagnostics = ConversionDiagnostics()
            let text = try await XMISerializer(options: options).serialize(planning.plan, diagnostics: &diagnostics)
            #expect(!text.contains("highlights"), "\(text)")
            #expect(
                diagnostics.warnings.map(\.kind) == [.droppedFeature(name: "highlights", className: "Project")],
                "\(diagnostics.warnings)")
        }
        let json = try await JSONSerializer().serialize(planning.plan)
        let document = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let nested = try #require(document["highlights"] as? [[String: Any]], "\(json)")
        #expect(nested.map { $0["title"] as? String } == ["loose"], "\(json)")
    }

    @Test("the XMI writers leave out an object held by an attribute")
    func objectsInAttributes() async throws {
        let planning = try await Self.makePlanning()
        let taskClass = try #require(await planning.set.getMetamodel(uri: Self.namespace)?.getEClass("Task"))
        await planning.set("name", DynamicEObject(eClass: taskClass))
        for options in [XMISerializationOptions.legacy, .emf] {
            var diagnostics = ConversionDiagnostics()
            let text = try await XMISerializer(options: options).serialize(planning.plan, diagnostics: &diagnostics)
            #expect(!text.contains("name="), "\(text)")
            #expect(
                diagnostics.warnings.map(\.kind) == [.droppedFeature(name: "name", className: "Project")],
                "\(diagnostics.warnings)")
        }
    }

    @Test("the EMF writer leaves out a list of texts held by a reference")
    func emfTextsInReferences() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("highlights", EcoreValueArray(["first", "second"]))
        var diagnostics = ConversionDiagnostics()
        let text = try await XMISerializer(options: .emf).serialize(planning.plan, diagnostics: &diagnostics)
        #expect(!text.contains("highlights"), "\(text)")
        #expect(
            diagnostics.warnings.map(\.kind) == [.droppedFeature(name: "highlights", className: "Project")],
            "\(diagnostics.warnings)")
    }

    @Test("single values of every primitive type are written as their text")
    func primitiveSingles() async throws {
        let planning = try await Self.makePlanning()
        let values: [(String, any EcoreValue, String)] = [
            ("count", Int64(42), "42"), ("small", Int8(-3), "-3"), ("ratio", Float(0.5), "0.5"),
            ("price", try #require(Decimal(string: "12.75")), "12.75"), ("initial", Character("Q"), "Q"),
            ("flag", true, "true"),
        ]
        for (feature, value, _) in values { await planning.set(feature, value) }
        let xmi = try await XMISerializer().serialize(planning.plan)
        for (feature, _, text) in values {
            #expect(xmi.contains(" \(feature)=\"\(text)\""), "\(xmi)")
        }
        let json = try await JSONSerializer().serialize(planning.plan)
        let document = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        for (feature, _, text) in values {
            #expect(document[feature].map { "\($0)" } == text || (document[feature] as? Bool).map { "\($0)" } == text, "\(json)")
        }
    }

    // MARK: - Values that no document can hold

    /// Checks that a writer fails with an error that names a feature of the plan's project.
    ///
    /// - Parameters:
    ///   - feature: The name of the feature.
    ///   - write: Writes the document.
    static func expectUnwritable(_ feature: String, _ write: () async throws -> String) async {
        do {
            let text = try await write()
            Issue.record("Expected an error for '\(feature)', but wrote:\n\(text)")
        } catch XMIError.unsupportedFeature(let message) {
            #expect(message.contains("'\(feature)'"), "\(message)")
            #expect(message.contains("'Project'"), "\(message)")
        } catch JSONError.parseError(let message) {
            #expect(message.contains("'\(feature)'"), "\(message)")
            #expect(message.contains("'Project'"), "\(message)")
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test(
        "every writer rejects a reference that mixes objects with other values",
        arguments: [XMISerializationOptions.legacy, .emf, emfHrefs])
    func rejectsCorruptReferences(options: XMISerializationOptions) async throws {
        let planning = try await Self.makePlanning()
        await planning.set("highlights", EcoreValueArray([planning.planTasks[0], "loose text"]))
        await Self.expectUnwritable("highlights") { try await XMISerializer(options: options).serialize(planning.plan) }
    }

    @Test("the JSON writer rejects a reference that mixes objects with other values")
    func jsonRejectsCorruptReferences() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("highlights", EcoreValueArray([planning.planTasks[0], "loose text"]))
        await Self.expectUnwritable("highlights") { try await JSONSerializer().serialize(planning.plan) }
    }

    @Test(
        "every XMI writer rejects an attribute value that has no textual form",
        arguments: [XMISerializationOptions.legacy, .emf])
    func rejectsOpaqueAttributes(options: XMISerializationOptions) async throws {
        let planning = try await Self.makePlanning()
        await planning.set("name", OpaqueValue(code: 7))
        await Self.expectUnwritable("name") { try await XMISerializer(options: options).serialize(planning.plan) }

        let lists = try await Self.makePlanning()
        await lists.set("labels", EcoreValueArray(["urgent", OpaqueValue(code: 8)]))
        await Self.expectUnwritable("labels") { try await XMISerializer(options: options).serialize(lists.plan) }
    }

    @Test("the default writer rejects an undeclared value that has no textual form")
    func legacyRejectsOpaqueUndeclared() async throws {
        let planning = try await Self.makePlanning()
        await planning.set("extra", OpaqueValue(code: 9))
        await Self.expectUnwritable("extra") { try await XMISerializer().serialize(planning.plan) }
    }

    @Test("the JSON writer rejects values that have no JSON form", arguments: ["name", "extra"])
    func jsonRejectsOpaqueValues(feature: String) async throws {
        let planning = try await Self.makePlanning()
        await planning.set(feature, OpaqueValue(code: 10))
        await Self.expectUnwritable(feature) { try await JSONSerializer().serialize(planning.plan) }
    }
}

extension Optional {
    /// Transforms the wrapped value with an asynchronous closure.
    ///
    /// - Parameter transform: The transformation.
    /// - Returns: The transformed value, or `nil` if there is no wrapped value.
    fileprivate func asyncMap<Result>(_ transform: (Wrapped) async throws -> Result) async rethrows -> Result? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}
