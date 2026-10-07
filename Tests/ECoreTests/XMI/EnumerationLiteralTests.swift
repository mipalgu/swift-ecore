//
// EnumerationLiteralTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// A metamodel with an enumeration whose literal texts differ from the literal names.
private enum LevelFixture {
    static let metamodel = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="levels"
            nsURI="http://example.org/levels" nsPrefix="levels">
          <eClassifiers xsi:type="ecore:EEnum" name="Level">
            <eLiterals name="JDK50" literal="5.0"/>
            <eLiterals name="JDK170" value="1" literal="17.0"/>
            <eLiterals name="Editable" value="2"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Holder">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="level" eType="#//Level"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="levels" upperBound="-1" eType="#//Level"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="peer" eType="#//Holder"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="plain" unsettable="true"
                eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EBoolean"/>
          </eClassifiers>
        </ecore:EPackage>
        """

    static func instance(_ attributes: String, children: String = "") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <levels:Holder xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:levels="http://example.org/levels" \(attributes)>\(children)</levels:Holder>
        """
    }

    /// Writes the metamodel and an instance document and loads the instance.
    static func load(_ instance: String) async throws -> (set: ResourceSet, resource: Resource, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let metamodelURL = directory.appendingPathComponent("levels.ecore")
        try metamodel.write(to: metamodelURL, atomically: testWritesAtomically, encoding: .utf8)
        let instanceURL = directory.appendingPathComponent("holder.xmi")
        try instance.write(to: instanceURL, atomically: testWritesAtomically, encoding: .utf8)
        let set = ResourceSet()
        let package = try await EPackage(url: metamodelURL)
        await set.registerMetamodel(package, uri: package.nsURI)
        let resource = try await set.loadXMIResource(uri: instanceURL.absoluteString)
        return (set, resource, directory)
    }
}

@Suite("Enumeration Literal Text Tests")
struct EnumerationLiteralTests {
    private let level = EEnum(
        name: "Level",
        literals: [
            EEnumLiteral(name: "JDK50", value: 0, literal: "5.0"),
            EEnumLiteral(name: "JDK170", value: 1, literal: "17.0"),
            EEnumLiteral(name: "Editable", value: 2, literal: "Editable"),
            EEnumLiteral(name: "Tricky", value: 3, literal: "JDK50"),
        ])

    @Test("literal text is preferred over the name when reading")
    func storedValues() {
        #expect(level.storedValue(forText: "17.0") == "JDK170")
        #expect(level.storedValue(forText: "JDK170") == "JDK170")
        #expect(level.storedValue(forText: "Editable") == "Editable")
        #expect(level.storedValue(forText: "JDK50") == "Tricky")
        #expect(level.storedValue(forText: "unknown") == "unknown")
    }

    @Test("the literal text is written for a stored name")
    func writtenText() {
        #expect(level.text(forStoredValue: "JDK170") == "17.0")
        #expect(level.text(forStoredValue: "Editable") == "Editable")
        #expect(level.text(forStoredValue: "Tricky") == "JDK50")
        #expect(level.text(forStoredValue: "17.0") == "17.0")
        #expect(level.text(forStoredValue: "unknown") == "unknown")
    }

    @Test("literals are found by their text")
    func literalLookup() {
        #expect(level.getLiteral(text: "5.0")?.name == "JDK50")
        #expect(level.getLiteral(text: "nope") == nil)
    }

    @Test("an enumeration-typed attribute read as literal text is stored as the literal name")
    func parsesLiteralText() async throws {
        let (_, resource, directory) = try await LevelFixture.load(
            LevelFixture.instance("level=\"17.0\""))
        defer { try? FileManager.default.removeItem(at: directory) }
        let holder = try #require(await resource.getRootObjects().first as? DynamicEObject)
        #expect(holder.eGet("level") as? String == "JDK170")
    }

    @Test("a literal name is accepted when no literal has that text")
    func parsesLiteralName() async throws {
        let (_, resource, directory) = try await LevelFixture.load(
            LevelFixture.instance("level=\"JDK50\""))
        defer { try? FileManager.default.removeItem(at: directory) }
        let holder = try #require(await resource.getRootObjects().first as? DynamicEObject)
        #expect(holder.eGet("level") as? String == "JDK50")
    }

    @Test("many-valued enumeration attributes are mapped value by value")
    func parsesLists() async throws {
        let (_, resource, directory) = try await LevelFixture.load(
            LevelFixture.instance("", children: "<levels>5.0</levels><levels>Editable</levels>"))
        defer { try? FileManager.default.removeItem(at: directory) }
        let holder = try #require(await resource.getRootObjects().first as? DynamicEObject)
        #expect(holder.eGet("levels") as? [String] == ["JDK50", "Editable"])
    }

    @Test("serialisation writes the literal text in both layouts")
    func serialisesLiteralText() async throws {
        let (_, resource, directory) = try await LevelFixture.load(
            LevelFixture.instance("level=\"17.0\"", children: "<levels>5.0</levels><levels>17.0</levels>"))
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = try await XMISerializer().serialize(resource)
        #expect(legacy.contains("level=\"17.0\""))
        #expect(!legacy.contains("JDK170"))
        let emf = try await XMISerializer(options: .emf).serialize(resource)
        #expect(emf.contains("level=\"17.0\""))
        #expect(emf.contains("<levels>5.0</levels>"))
        #expect(emf.contains("<levels>17.0</levels>"))
        #expect(!emf.contains("JDK"))
    }

    @Test("a document with literal texts reloads to the same stored names")
    func roundTrip() async throws {
        let (set, resource, directory) = try await LevelFixture.load(
            LevelFixture.instance("level=\"17.0\"", children: "<levels>5.0</levels>"))
        defer { try? FileManager.default.removeItem(at: directory) }
        let written = directory.appendingPathComponent("again.xmi")
        try await XMISerializer(options: .emf).serialize(resource, to: written)
        let reloaded = try await set.loadXMIResource(uri: written.absoluteString)
        let holder = try #require(await reloaded.getRootObjects().first as? DynamicEObject)
        #expect(holder.eGet("level") as? String == "JDK170")
        #expect(holder.eGet("levels") as? [String] == ["JDK50"])
    }

    @Test("an unsettable attribute that is set to its default value is written")
    func unsettableDefaultIsWritten() async throws {
        let (_, resource, directory) = try await LevelFixture.load(
            LevelFixture.instance("plain=\"false\""))
        defer { try? FileManager.default.removeItem(at: directory) }
        let emf = try await XMISerializer(options: .emf).serialize(resource)
        #expect(emf.contains("plain=\"false\""))
    }

    @Test("an unsettable attribute that was never set is not written")
    func unsettableUnsetIsOmitted() async throws {
        let (_, resource, directory) = try await LevelFixture.load(LevelFixture.instance(""))
        defer { try? FileManager.default.removeItem(at: directory) }
        let emf = try await XMISerializer(options: .emf).serialize(resource)
        #expect(!emf.contains("plain="))
    }

    @Test("unsetting an unsettable attribute removes it from the output")
    func unsetAfterSet() async throws {
        let (_, resource, directory) = try await LevelFixture.load(
            LevelFixture.instance("plain=\"false\""))
        defer { try? FileManager.default.removeItem(at: directory) }
        let holder = try #require(await resource.getRootObjects().first as? DynamicEObject)
        await resource.eSet(objectId: holder.id, feature: "plain", value: nil)
        let emf = try await XMISerializer(options: .emf).serialize(resource)
        #expect(!emf.contains("plain="))
    }

    @Test("a settable attribute equal to its default is still omitted")
    func settableDefaultIsOmitted() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let metamodel = LevelFixture.metamodel.replacingOccurrences(
            of: "name=\"plain\" unsettable=\"true\"", with: "name=\"plain\"")
        let metamodelURL = directory.appendingPathComponent("levels.ecore")
        try metamodel.write(to: metamodelURL, atomically: testWritesAtomically, encoding: .utf8)
        let instanceURL = directory.appendingPathComponent("holder.xmi")
        try LevelFixture.instance("plain=\"false\"").write(to: instanceURL, atomically: testWritesAtomically, encoding: .utf8)
        let set = ResourceSet()
        let package = try await EPackage(url: metamodelURL)
        await set.registerMetamodel(package, uri: package.nsURI)
        let resource = try await set.loadXMIResource(uri: instanceURL.absoluteString)
        let emf = try await XMISerializer(options: .emf).serialize(resource)
        #expect(!emf.contains("plain="))
    }

    @Test("a resource keeps the namespaces of its metamodels after its resource set is released")
    func namespacesSurviveRelease() async throws {
        let (_, resource, directory) = try await LevelFixture.load(
            LevelFixture.instance("level=\"17.0\""))
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(await resource.lostResourceSet)
        let emf = try await XMISerializer(options: .emf).serialize(resource)
        #expect(emf.contains("xmlns:levels=\"http://example.org/levels\""))
        #expect(emf.contains("<levels:Holder"))
        #expect(!emf.contains("swift-modelling.org"))
    }

    /// Builds a resource that refers to an object of another resource and releases their set.
    private func resourceWithReleasedSet() async throws -> (resource: Resource, directory: URL) {
        let (set, resource, directory) = try await LevelFixture.load(LevelFixture.instance(""))
        let otherURL = directory.appendingPathComponent("other.xmi")
        try LevelFixture.instance("").write(to: otherURL, atomically: testWritesAtomically, encoding: .utf8)
        let other = try await set.loadXMIResource(uri: otherURL.absoluteString)
        let target = try #require(await other.getRootObjects().first)
        let holder = try #require(await resource.getRootObjects().first as? DynamicEObject)
        await resource.eSet(objectId: holder.id, feature: "peer", value: target.id)
        let withSet = try await XMISerializer(options: .emf).serialize(resource)
        #expect(withSet.contains("peer=\"other.xmi#/\""))
        return (resource, directory)
    }

    @Test("a reference into another resource of a released set is reported")
    func releasedSetReference() async throws {
        let (resource, directory) = try await resourceWithReleasedSet()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(await resource.lostResourceSet)
        await #expect(throws: XMIError.self) {
            _ = try await XMISerializer(options: .emf).serialize(resource)
        }
    }
}
