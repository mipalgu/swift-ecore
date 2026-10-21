//
// LegacyNamespaceTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for the namespaces that the legacy XMI writer declares.
///
/// The legacy writer takes the namespace of a class from the registered package that
/// holds it, from the Ecore namespace for Ecore's own metaclasses, and only for a class
/// of no known package from a namespace derived from the class name.
@Suite("Legacy writer namespaces")
struct LegacyNamespaceTests {
    /// The namespace URI of the reports package.
    static let reportsURI = "http://www.example.org/reports"

    /// A package whose only class is named like an Ecore metaclass would begin.
    static func reportsPackage() -> EPackage {
        let string = EcorePackage.dataType(.eString) ?? EDataType(name: "EString")
        let entry = EClass(name: "Entry", eStructuralFeatures: [EAttribute(name: "title", eType: string)])
        return EPackage(name: "reports", nsURI: reportsURI, nsPrefix: "reports", eClassifiers: [entry])
    }

    /// Creates entries of the reports package in a resource of a resource set.
    ///
    /// - Parameter count: The number of root entries.
    /// - Returns: The resource set and the resource.
    static func entries(_ count: Int) async throws -> (set: ResourceSet, resource: Resource) {
        let set = ResourceSet()
        let package = reportsPackage()
        await set.registerMetamodel(package, uri: package.nsURI)
        let entryClass = try #require(package.getEClass("Entry"))
        let resource = await set.createResource(uri: "file:///reports.xmi")
        for index in 0..<count {
            var entry = DynamicEObject(eClass: entryClass)
            entry.eSet("title", value: "entry\(index)")
            await resource.add(entry)
        }
        return (set, resource)
    }

    @Test("a class of a registered package takes the namespace of its package")
    func registeredPackage() async throws {
        let (_, resource) = try await Self.entries(1)
        let text = try await XMISerializer().serialize(resource)
        #expect(
            text.contains(
                "<reports:Entry xmi:version=\"2.0\" xmlns:xmi=\"http://www.omg.org/XMI\" xmlns:reports=\"\(Self.reportsURI)\""),
            "\(text)")
        #expect(!text.contains("ecore"), "\(text)")
    }

    @Test("several roots of a registered package declare its namespace on the wrapper")
    func registeredPackageSeveralRoots() async throws {
        let (_, resource) = try await Self.entries(2)
        let text = try await XMISerializer().serialize(resource)
        #expect(text.contains("xmlns:reports=\"\(Self.reportsURI)\""), "\(text)")
        #expect(text.components(separatedBy: "<reports:Entry ").count == 3, "\(text)")
        #expect(!text.contains("ecore"), "\(text)")
        #expect(!text.contains("swift-modelling.org"), "\(text)")
    }

    @Test("the namespace comes from the metamodel snapshot once the resource set is gone")
    func metamodelSnapshot() async throws {
        var set: ResourceSet? = ResourceSet()
        let package = Self.reportsPackage()
        await set?.registerMetamodel(package, uri: package.nsURI)
        let resource = try #require(await set?.createResource(uri: "file:///snapshot.xmi"))
        await resource.add(DynamicEObject(eClass: try #require(package.getEClass("Entry"))))
        set = nil
        #expect(await resource.lostResourceSet)
        let text = try await XMISerializer().serialize(resource)
        #expect(text.contains("<reports:Entry "), "\(text)")
        #expect(text.contains("xmlns:reports=\"\(Self.reportsURI)\""), "\(text)")
    }

    @Test("an Ecore metaclass takes the Ecore namespace")
    func ecoreMetaclass() async throws {
        let resource = Resource(uri: "file:///metaclass.xmi")
        var object = DynamicEObject(eClass: EClass(name: "EClass"))
        object.eSet("name", value: "Book")
        await resource.add(object)
        let text = try await XMISerializer().serialize(resource)
        #expect(text.contains("<ecore:EClass "), "\(text)")
        #expect(text.contains("xmlns:ecore=\"\(EcoreURI.ecoreNamespace.rawValue)\""), "\(text)")
    }

    @Test("a class of no known package takes the derived namespace", arguments: ["Entry", "Gadget"])
    func unknownPackage(className: String) async throws {
        let resource = Resource(uri: "file:///loose.xmi")
        await resource.add(DynamicEObject(eClass: EClass(name: className)))
        let text = try await XMISerializer().serialize(resource)
        let prefix = className.lowercased()
        #expect(text.contains("<\(prefix):\(className) "), "\(text)")
        #expect(text.contains("xmlns:\(prefix)=\"\(XMIDocumentSyntax.fallbackNamespaceBase)\(prefix)\""), "\(text)")
        #expect(!text.contains("ecore"), "\(text)")
    }
}
