//
// EnumerationOrderTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// A generated metamodel and instance document with many nested elements.
struct TreeFixture {
    /// The directory that holds the generated documents.
    let directory: URL

    /// The names of the elements in document order.
    let names: [String]

    /// The text of the metamodel document.
    static let metamodel = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="tree"
            nsURI="http://example.org/tree" nsPrefix="tree">
          <eClassifiers xsi:type="ecore:EClass" name="Node">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="name"
                eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="tags" upperBound="-1"
                eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="children" upperBound="-1"
                containment="true" eType="#//Node"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="extras" upperBound="-1"
                containment="true" eType="#//Node"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="peers" upperBound="-1"
                eType="#//Node"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Leaf" eSuperTypes="#//Node"/>
        </ecore:EPackage>
        """

    /// Generates the documents.
    ///
    /// - Parameters:
    ///   - roots: The number of root elements; more than one wraps them in `xmi:XMI`.
    ///   - depth: The depth of the generated tree.
    ///   - branching: The number of children (and extras) per element.
    init(roots: Int = 1, depth: Int = 3, branching: Int = 2) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.metamodel.write(
            to: directory.appendingPathComponent("tree.ecore"), atomically: true, encoding: .utf8)

        var names: [String] = []
        func element(_ tag: String, _ name: String, level: Int, indent: String) -> String {
            names.append(name)
            let typeAttribute = level == depth ? " xsi:type=\"tree:Leaf\"" : ""
            var text = "\(indent)<\(tag)\(typeAttribute) name=\"\(name)\""
            if level == depth {
                return text + "/>\n"
            }
            text += ">\n\(indent)  <tags>\(name)-a</tags>\n\(indent)  <tags>\(name)-b</tags>\n"
            for index in 0..<branching {
                text += element("children", "\(name).c\(index)", level: level + 1, indent: indent + "  ")
            }
            for index in 0..<2 {
                text += element("extras", "\(name).x\(index)", level: level + 1, indent: indent + "  ")
            }
            return text + "\(indent)</\(tag)>\n"
        }
        let namespaces =
            "xmlns:xmi=\"http://www.omg.org/XMI\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\""
            + " xmlns:tree=\"http://example.org/tree\""
        var body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        if roots == 1 {
            var root = element("tree:Node", "root", level: 0, indent: "")
            root.insert(contentsOf: " xmi:version=\"2.0\" \(namespaces)", at: root.index(root.startIndex, offsetBy: "<tree:Node".count))
            body += root
        } else {
            body += "<xmi:XMI xmi:version=\"2.0\" \(namespaces)>\n"
            for index in 0..<roots {
                body += element("tree:Node", "root\(index)", level: 0, indent: "  ")
            }
            body += "</xmi:XMI>\n"
        }
        try body.write(
            to: directory.appendingPathComponent("instance.xmi"), atomically: true, encoding: .utf8)
        self.names = names
    }

    /// Removes the generated documents.
    func remove() { try? FileManager.default.removeItem(at: directory) }

    /// Loads the instance document into a new resource set that knows the metamodel.
    func load() async throws -> (set: ResourceSet, resource: Resource) {
        let set = ResourceSet()
        let metamodel = try await EPackage(url: directory.appendingPathComponent("tree.ecore"))
        await set.registerMetamodel(metamodel, uri: metamodel.nsURI)
        let resource = try await set.loadXMIResource(
            uri: directory.appendingPathComponent("instance.xmi").absoluteString)
        return (set, resource)
    }

    /// The names of objects in a list.
    static func names(_ objects: [any EObject]) -> [String] {
        objects.compactMap { ($0 as? DynamicEObject)?.eGet("name") as? String }
    }
}

@Suite("Deterministic Enumeration Order Tests")
struct EnumerationOrderTests {
    private static let repetitions = 5

    @Test("instances are listed in document order, identically on every load")
    func instancesInDocumentOrder() async throws {
        let fixture = try TreeFixture()
        defer { fixture.remove() }
        #expect(fixture.names.count == 85)
        for _ in 0..<Self.repetitions {
            let (set, resource) = try await fixture.load()
            let node = try #require(
                await set.getMetamodel(uri: "http://example.org/tree")?.getEClass("Node"))
            let instances = await resource.getAllInstancesOf(node)
            #expect(TreeFixture.names(instances) == fixture.names)
        }
    }

    @Test("subclasses are included in document order")
    func subclassInstances() async throws {
        let fixture = try TreeFixture()
        defer { fixture.remove() }
        let (set, resource) = try await fixture.load()
        let leaf = try #require(
            await set.getMetamodel(uri: "http://example.org/tree")?.getEClass("Leaf"))
        let expected = fixture.names.filter { $0.split(separator: ".").count == 4 }
        #expect(TreeFixture.names(await resource.getAllInstancesOf(leaf)) == expected)
    }

    @Test("all objects including contents start with the root in document order")
    func allObjectsInDocumentOrder() async throws {
        let fixture = try TreeFixture()
        defer { fixture.remove() }
        for _ in 0..<Self.repetitions {
            let (_, resource) = try await fixture.load()
            let all = await resource.getAllObjectsIncludingContents()
            #expect(TreeFixture.names(all) == fixture.names)
        }
    }

    @Test("roots keep the order of the document")
    func rootOrder() async throws {
        let fixture = try TreeFixture(roots: 6, depth: 1, branching: 2)
        defer { fixture.remove() }
        for _ in 0..<Self.repetitions {
            let (_, resource) = try await fixture.load()
            let roots = TreeFixture.names(await resource.getRootObjects())
            let expectedRoots: [String] = (0..<6).map { index in "root\(index)" }
            #expect(roots == expectedRoots)
            let all = TreeFixture.names(await resource.getAllObjectsIncludingContents())
            #expect(all == fixture.names)
        }
    }

    @Test("containment navigation lists children in document order")
    func containmentOrder() async throws {
        let fixture = try TreeFixture(depth: 2, branching: 4)
        defer { fixture.remove() }
        let (_, resource) = try await fixture.load()
        let root = try #require(await resource.getRootObjects().first)
        let contents = TreeFixture.names(await resource.eContents(of: root))
        #expect(contents == ["root.c0", "root.c1", "root.c2", "root.c3", "root.x0", "root.x1"])
        let all = TreeFixture.names(await resource.eAllContents(of: root))
        #expect(all == Array(fixture.names.dropFirst()))
    }

    @Test("native metamodel elements are listed in containment order on every load")
    func nativeOrder() async throws {
        for _ in 0..<Self.repetitions {
            let set = ResourceSet()
            let resource = try await set.loadEcoreResource(
                uri: try FidelityFixtures.url("library-full.ecore").absoluteString)
            let all = await resource.getAllObjectsIncludingContents()
            let names = all.compactMap { ($0 as? any ENamedElement)?.name }
            #expect(Array(names.prefix(6)) == ["library", "Named", "name", "Lendable", "borrow", "days"])
            #expect(names.count == all.count)
            let features = await resource.getAllInstancesOf(EcorePackage.metaClass(.eStructuralFeature))
            #expect(features.count == 25)
        }
    }

    @Test("serialisation is identical on every load")
    func serialisationIsStable() async throws {
        let fixture = try TreeFixture(depth: 2, branching: 2)
        defer { fixture.remove() }
        var legacy: Set<String> = []
        var emf: Set<String> = []
        for _ in 0..<Self.repetitions {
            let (_, resource) = try await fixture.load()
            legacy.insert(try await XMISerializer().serialize(resource))
            emf.insert(try await XMISerializer(options: .emf).serialize(resource))
        }
        #expect(legacy.count == 1)
        #expect(emf.count == 1)
    }
}
