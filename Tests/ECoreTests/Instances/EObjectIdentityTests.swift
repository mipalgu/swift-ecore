//
// EObjectIdentityTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// A metamodel that declares a class of its own called `EObject`.
///
/// `Node` extends the declared `EObject`, whereas `Other` does not.
struct OwnEObjectModel {
    /// The namespace URI of the metamodel.
    static let nsURI = "http://example.org/own-eobject"

    let package: EPackage
    let ownEObject: EClass
    let node: EClass
    let other: EClass

    init() {
        let ownEObject = EClass(name: EcoreClassifier.eObject.rawValue)
        let node = EClass(name: "Node", eSuperTypes: [ownEObject])
        let other = EClass(name: "Other")
        package = EPackage(
            name: "own", nsURI: Self.nsURI, nsPrefix: "own", eClassifiers: [ownEObject, node, other])
        self.ownEObject = package.getEClass(ownEObject.name) ?? ownEObject
        self.node = package.getEClass(node.name) ?? node
        self.other = package.getEClass(other.name) ?? other
    }
}

/// Tests that only Ecore's own `EObject` is the supertype of every class.
@Suite("Identity of Ecore's EObject")
struct EObjectIdentityTests {
    /// Ecore's `EObject` class.
    private static var eObject: EClass { EcorePackage.metaClass(.eObject) }

    /// Writes an Ecore document with the given namespace URI and classifiers to a new directory.
    private static func writeDocument(nsURI: String, name: String = "doc", _ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).ecore")
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="\(name)"
                nsURI="\(nsURI)" nsPrefix="\(name)">
            \(body)
            </ecore:EPackage>
            """
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test("Ecore's EObject is the supertype of every class")
    func builtInIsUniversal() {
        let model = OwnEObjectModel()
        #expect(Self.eObject.isEObject)
        #expect(EcorePackage.isEObject(Self.eObject))
        #expect(model.node.conforms(to: Self.eObject))
        #expect(model.other.conforms(to: Self.eObject))
        #expect(model.ownEObject.conforms(to: Self.eObject))
        #expect(EcorePackage.metaClass(.eClass).conforms(to: Self.eObject))
        #expect(!Self.eObject.conforms(to: model.ownEObject))
    }

    @Test("a declared class called EObject is an ordinary class")
    func declaredEObjectIsOrdinary() {
        let model = OwnEObjectModel()
        #expect(!model.ownEObject.isEObject)
        #expect(!EcorePackage.isEObject(model.ownEObject, in: model.package))
        #expect(model.ownEObject.conforms(to: model.ownEObject))
        #expect(model.node.conforms(to: model.ownEObject))
        #expect(!model.other.conforms(to: model.ownEObject))
        #expect(!EcorePackage.metaClass(.eClass).conforms(to: model.ownEObject))
    }

    @Test("a class called EObject outside any package is not Ecore's")
    func adHocClassIsNotEcore() {
        let adHoc = EClass(name: EcoreClassifier.eObject.rawValue)
        #expect(!adHoc.isEObject)
        #expect(!OwnEObjectModel().other.conforms(to: adHoc))
    }

    @Test("a separately loaded copy of Ecore provides Ecore's EObject")
    func loadedEcoreCopy() async throws {
        let url = try Self.writeDocument(
            nsURI: EcorePackage.nsURI, name: EcorePackage.name,
            #"<eClassifiers xsi:type="ecore:EClass" name="EObject"/>"#)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let copy = try await EPackage(url: url)
        let copied = try #require(copy.getEClass(EcoreClassifier.eObject.rawValue))
        #expect(EcorePackage.isEObject(copied, in: copy))
        let model = OwnEObjectModel()
        #expect(!EcorePackage.isEObject(copied, in: model.package))
        #expect(!EcorePackage.isEObject(model.ownEObject, in: copy))
    }

    @Test(
        "a reference into the Ecore metamodel denotes Ecore's EObject",
        arguments: [
            "http://www.eclipse.org/emf/2002/Ecore#//EObject",
            "platform:/plugin/org.eclipse.emf.ecore/model/Ecore.ecore#//EObject",
        ])
    func referenceIntoEcore(href: String) async throws {
        let url = try Self.writeDocument(
            nsURI: "http://example.org/refers",
            """
            <eClassifiers xsi:type="ecore:EClass" name="Holder">
              <eStructuralFeatures xsi:type="ecore:EReference" name="any" eType="ecore:EClass \(href)"/>
            </eClassifiers>
            """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        for options in [EcoreLoadOptions(), EcoreLoadOptions(unresolvedReferences: .keepAsProxies)] {
            let package = try #require(try await EPackage.rootPackages(url: url, options: options).first)
            let holder = try #require(package.getEClass("Holder"))
            let type = try #require(holder.getEReference(name: "any")?.eType as? EClass)
            #expect(type.isEObject)
            #expect(OwnEObjectModel().other.conforms(to: type))
        }
    }

    @Test("a declared EObject class has only its own instances")
    func declaredEObjectInstances() async throws {
        let model = OwnEObjectModel()
        let set = ResourceSet()
        await set.registerMetamodel(model.package, uri: OwnEObjectModel.nsURI)
        let resource = await set.createResource(uri: "memory:/own.xmi")
        let base = DynamicEObject(eClass: model.ownEObject)
        let node = DynamicEObject(eClass: model.node)
        let other = DynamicEObject(eClass: model.other)
        let ecoreObject = DynamicEObject(eClass: Self.eObject)
        await resource.add(contentsOf: [base, node, other, ecoreObject])

        let own = await resource.getAllInstancesOf(model.ownEObject).map(\.id)
        #expect(own == [base.id, node.id])
        #expect(await resource.getAllInstancesOf(Self.eObject).count == 4)

        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(resource, alias: "own")
        #expect(Set(await engine.allInstancesOf(model.ownEObject).map(\.id)) == [base.id, node.id])
        #expect(await engine.allInstancesOf(Self.eObject).count == 4)
    }

    @Test("a subclass of Ecore's EObject is not an instance of a declared EObject class")
    func explicitEcoreSupertype() async throws {
        let model = OwnEObjectModel()
        let explicit = EClass(name: "Explicit", eSuperTypes: [Self.eObject])
        let resource = Resource(uri: "memory:/explicit.xmi")
        let object = DynamicEObject(eClass: explicit)
        await resource.add(object)
        #expect(await resource.getAllInstancesOf(model.ownEObject).isEmpty)
        #expect(await resource.getAllInstancesOf(Self.eObject).map(\.id) == [object.id])
    }

    @Test("a reference of an inferred class accepts any object")
    func inferredReferenceType() {
        let inferred = EClassifierResolver.resolvingReferenceType(DynamicEObject(eClass: Self.eObject))
        #expect((inferred as? EClass)?.isEObject == true)
    }
}
