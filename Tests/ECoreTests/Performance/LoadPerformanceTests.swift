//
// LoadPerformanceTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Generates large synthetic documents for the performance tests.
enum SyntheticDocuments {
    /// The URI of the Ecore built-in string type as EMF writes it.
    private static let ecoreString = "ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"

    /// The URI of the Ecore built-in integer type as EMF writes it.
    private static let ecoreInt = "ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EInt"

    /// The number of model elements that each generated class contributes.
    static let elementsPerClass = 9

    /// The text of an Ecore document with many classes.
    ///
    /// Each class has three attributes, a reference, an operation with a parameter, and two
    /// annotations. Classes are grouped in hierarchies of at most twenty classes so that
    /// no class has an unrealistically deep inheritance chain.
    ///
    /// - Parameter classes: The number of classes to generate.
    /// - Returns: The document text; it has `classes * elementsPerClass` model elements.
    static func ecore(classes: Int) -> String {
        var text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="big"
                nsURI="http://example.org/big" nsPrefix="big">

            """
        for index in 0..<classes {
            text += "  <eClassifiers xsi:type=\"ecore:EClass\" name=\"C\(index)\""
            if index % 20 != 0 { text += " eSuperTypes=\"#//C\(index - index % 20)\"" }
            text += ">\n"
            text += "    <eAnnotations source=\"http://www.eclipse.org/emf/2002/GenModel\">\n"
            text += "      <details key=\"documentation\" value=\"Class \(index)\"/>\n    </eAnnotations>\n"
            for attribute in 0..<3 {
                text += "    <eStructuralFeatures xsi:type=\"ecore:EAttribute\" name=\"a\(attribute)\""
                text += " eType=\"\(ecoreString)\"/>\n"
            }
            text += "    <eStructuralFeatures xsi:type=\"ecore:EReference\" name=\"r\""
            text += " eType=\"#//C\((index + 1) % classes)\"/>\n"
            text += "    <eOperations name=\"op\">\n"
            text += "      <eParameters name=\"p\" eType=\"\(ecoreInt)\"/>\n    </eOperations>\n"
            text += "  </eClassifiers>\n"
        }
        return text + "</ecore:EPackage>\n"
    }

    /// Writes an Ecore document to a new temporary directory.
    ///
    /// - Parameter classes: The number of classes to generate.
    /// - Returns: The URL of the document; the caller removes its directory.
    static func writeEcore(classes: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("big.ecore")
        try ecore(classes: classes).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

@Suite("Load Performance Tests")
struct LoadPerformanceTests {
    /// The classes of the large document; with nine elements each, the document has 5,400.
    private static let classCount = 600

    /// A bound that debug builds meet by a wide margin, even on a slow shared machine.
    private static let loadBound = Duration.seconds(15)

    @Test("a document of 5,400 elements loads natively in bounded time")
    func nativeLoad() async throws {
        let url = try SyntheticDocuments.writeEcore(classes: Self.classCount)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var package: EPackage?
        let elapsed = try await ContinuousClock().measure {
            package = try await EPackage(url: url)
        }
        #expect(package?.eClassifiers.count == Self.classCount)
        #expect(package?.getEClass("C599")?.eReferences.first?.eType.name == "C0")
        #expect(elapsed < Self.loadBound)
    }

    @Test("a document of 5,400 elements loads dynamically in bounded time")
    func dynamicLoad() async throws {
        let url = try SyntheticDocuments.writeEcore(classes: Self.classCount)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let set = ResourceSet()
        var resource: Resource?
        let elapsed = try await ContinuousClock().measure {
            resource = try await set.loadXMIResource(uri: url.absoluteString)
        }
        let loaded = try #require(resource)
        #expect(await loaded.count() >= Self.classCount * SyntheticDocuments.elementsPerClass)
        #expect(elapsed < Self.loadBound)
    }

    @Test("load time grows in proportion to the size of the document")
    func loadScalesLinearly() async throws {
        func seconds(_ classes: Int) async throws -> Double {
            let url = try SyntheticDocuments.writeEcore(classes: classes)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let elapsed = try await ContinuousClock().measure { _ = try await EPackage(url: url) }
            return Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
        }
        let small = try await seconds(150)
        let large = try await seconds(600)
        // A fourfold size may cost up to ten times as much before growth counts as quadratic.
        #expect(large < max(small * 10, 1.0))
    }

    @Test("a package of 5,400 elements serialises in bounded time")
    func serialisation() async throws {
        let url = try SyntheticDocuments.writeEcore(classes: Self.classCount)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let package = try await EPackage(url: url)
        var text = ""
        let elapsed = ContinuousClock().measure { text = XMISerializer().serialize(package) }
        #expect(text.contains("name=\"C599\""))
        #expect(elapsed < Self.loadBound)
    }

    @Test("an instance document of 9,000 elements loads in bounded time")
    func instanceLoad() async throws {
        let fixture = try TreeFixture(depth: 5, branching: 4)
        defer { fixture.remove() }
        #expect(fixture.names.count > 9000)
        var resource: Resource?
        let elapsed = try await ContinuousClock().measure {
            resource = try await fixture.load().resource
        }
        let loaded = try #require(resource)
        #expect(await loaded.count() >= fixture.names.count)
        #expect(elapsed < Self.loadBound)
    }

    @Test("a wrapper document with 2,000 roots loads in bounded time and keeps the root order")
    func manyRoots() async throws {
        let fixture = try TreeFixture(roots: 2_000, depth: 1, branching: 1)
        defer { fixture.remove() }
        var resource: Resource?
        let elapsed = try await ContinuousClock().measure {
            resource = try await fixture.load().resource
        }
        let loaded = try #require(resource)
        let roots = TreeFixture.names(await loaded.getRootObjects())
        #expect(roots == (0..<2_000).map { "root\($0)" })
        #expect(elapsed < Self.loadBound)
    }
}

@Suite("Batch Add Tests")
struct BatchAddTests {
    private func makeTree() -> (parent: DynamicEObject, child: DynamicEObject, loose: DynamicEObject) {
        let node = EClass(name: "Node")
        let children = EReference(name: "children", eType: node, upperBound: -1, containment: true)
        let nodeClass = EClass(name: "Node", eStructuralFeatures: [children])
        var parent = DynamicEObject(eClass: nodeClass)
        let child = DynamicEObject(eClass: nodeClass)
        let loose = DynamicEObject(eClass: nodeClass)
        parent.eSet("children", value: [child.id])
        return (parent, child, loose)
    }

    @Test("contained objects do not become roots and the order of roots is kept")
    func roots() async {
        let (parent, child, loose) = makeTree()
        let resource = Resource(uri: "memory://batch")
        let added = await resource.add(contentsOf: [loose, child, parent])
        #expect(added == 3)
        #expect(await resource.getRootObjects().map(\.id) == [loose.id, parent.id])
        #expect(await resource.resolve(child.id) != nil)
    }

    @Test("adding again counts only new objects and does not duplicate roots")
    func repeated() async {
        let (parent, child, loose) = makeTree()
        let resource = Resource(uri: "memory://batch")
        await resource.add(contentsOf: [parent, child])
        let added = await resource.add(contentsOf: [parent, child, loose])
        #expect(added == 1)
        #expect(await resource.getRootObjects().map(\.id) == [parent.id, loose.id])
    }

    @Test("an empty batch changes nothing")
    func empty() async {
        let resource = Resource(uri: "memory://batch")
        #expect(await resource.add(contentsOf: []) == 0)
        #expect(await resource.getRootObjects().isEmpty)
    }
}

@Suite("Large Enumeration Order Tests")
struct LargeEnumerationOrderTests {
    private static let repetitions = 2

    @Test("thousands of instances are listed in document order, identically on every load")
    func largeDocumentOrder() async throws {
        let fixture = try TreeFixture(depth: 5, branching: 3)
        defer { fixture.remove() }
        #expect(fixture.names.count > 3_000)
        for _ in 0..<Self.repetitions {
            let (set, resource) = try await fixture.load()
            let node = try #require(
                await set.getMetamodel(uri: "http://example.org/tree")?.getEClass("Node"))
            let instances = await resource.getAllInstancesOf(node)
            #expect(TreeFixture.names(instances) == fixture.names)
            let all = await resource.getAllObjectsIncludingContents()
            #expect(TreeFixture.names(all) == fixture.names)
        }
    }
}
