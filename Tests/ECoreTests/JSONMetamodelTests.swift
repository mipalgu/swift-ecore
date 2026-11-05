//
// JSONMetamodelTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Self-authored metamodels that exercise every construct of the JSON metamodel format.
enum JSONMetamodelFixtures {
    /// The namespace URI of the Ecore metamodel, as JSON documents qualify classes with it.
    static let ecore = "http://www.eclipse.org/emf/2002/Ecore"

    /// A metamodel that the workshop metamodel refers to from another document.
    static let parts = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="parts" nsURI="http://example.org/json/parts" nsPrefix="parts">
          <eClassifiers xsi:type="ecore:EClass" name="Part" abstract="true">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="serial" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EEnum" name="Finish">
            <eLiterals name="Matte"/>
            <eLiterals name="Gloss" value="1"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EDataType" name="Millimetres" instanceClassName="double"/>
          <eSubpackages name="spares" nsURI="http://example.org/json/parts/spares" nsPrefix="spares">
            <eClassifiers xsi:type="ecore:EClass" name="Spare"/>
          </eSubpackages>
        </ecore:EPackage>
        """

    /// A metamodel with every construct that native Ecore documents carry.
    static let workshop = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="workshop" nsURI="http://example.org/json/workshop" nsPrefix="ws">
          <eAnnotations source="http://www.eclipse.org/emf/2002/GenModel">
            <details key="zeta" value="last &amp; &quot;quoted&quot;"/>
            <details key="alpha" value="Line one&#xA;Line two&#x9;tabbed"/>
          </eAnnotations>
          <eAnnotations source="urn:example:links" references="#//Machine/tools #//Speed/Fast parts.ecore#//Part"/>
          <eAnnotations source="urn:example:outer">
            <eAnnotations source="urn:example:inner">
              <details key="depth" value="2"/>
            </eAnnotations>
            <details key="depth" value="1"/>
          </eAnnotations>
          <eAnnotations source="urn:example:contents">
            <contents xsi:type="ecore:EClass" name="Embedded"/>
          </eAnnotations>
          <eClassifiers xsi:type="ecore:EClass" name="Named" abstract="true">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="name" lowerBound="1" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"
                iD="true"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Powered" abstract="true" interface="true">
            <eOperations name="start" lowerBound="1" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EBoolean"
                eExceptions="#//Fault">
              <eAnnotations source="http://www.eclipse.org/emf/2002/GenModel">
                <details key="body" value="return true;"/>
              </eAnnotations>
              <eParameters name="speed" lowerBound="1" eType="#//Speed"/>
              <eParameters name="notes" ordered="false" unique="false" upperBound="-1" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            </eOperations>
            <eOperations name="stop"/>
            <eOperations name="owner" eType="#//Workshop"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Machine" eSuperTypes="#//Named #//Powered">
            <eAnnotations source="http://www.eclipse.org/emf/2002/Ecore">
              <details key="constraints" value="HasTools"/>
            </eAnnotations>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="power" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EInt"
                defaultValueLiteral="240"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="speed" eType="#//Speed" defaultValueLiteral="Slow"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="finish" eType="ecore:EEnum parts.ecore#//Finish"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="width" eType="ecore:EDataType parts.ecore#//Millimetres"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="code" eType="#//Code"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="handle" eType="#//Handle"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="labels" ordered="false" unique="false"
                upperBound="-1" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="running" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EBoolean"
                changeable="false" volatile="true" transient="true" derived="true"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="serviced" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EDate"
                unsettable="true"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="tools" upperBound="-1" eType="#//Tool"
                containment="true" eOpposite="#//Tool/machine" eKeys="#//Tool/label"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="neighbours" upperBound="-1" eType="#//Machine"
                resolveProxies="false"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="part" eType="ecore:EClass parts.ecore#//Part"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="spare" eType="ecore:EClass parts.ecore#//spares/Spare"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="kind" eType="ecore:EClass http://www.eclipse.org/emf/2002/Ecore#//EClass"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Tool" eSuperTypes="#//Named parts.ecore#//Part">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="label" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="machine" eType="#//Machine" eOpposite="#//Machine/tools"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Workshop" eSuperTypes="#//Named">
            <eStructuralFeatures xsi:type="ecore:EReference" name="machines" upperBound="-1" containment="true"
                eType="#//Machine"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="benches" upperBound="-1" containment="true"
                eType="#//layout/Bench"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Fault" eSuperTypes="#//Named"/>
          <eClassifiers xsi:type="ecore:EClass" name="Entry" instanceClassName="java.util.Map$Entry">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="key" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="value" eType="#//Machine"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EEnum" name="Speed">
            <eAnnotations source="http://www.eclipse.org/emf/2002/GenModel">
              <details key="documentation" value="How fast a machine runs."/>
            </eAnnotations>
            <eLiterals name="Slow"/>
            <eLiterals name="Fast" value="5" literal="FAST"/>
            <eLiterals name="Idle" value="-1"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EDataType" name="Code" instanceClassName="java.lang.String"/>
          <eClassifiers xsi:type="ecore:EDataType" name="Handle" instanceClassName="java.lang.Object" serializable="false"/>
          <eSubpackages name="layout" nsURI="http://example.org/json/workshop/layout" nsPrefix="layout">
            <eClassifiers xsi:type="ecore:EClass" name="Bench" eSuperTypes="#//Named">
              <eStructuralFeatures xsi:type="ecore:EReference" name="machine" eType="#//Machine"/>
              <eStructuralFeatures xsi:type="ecore:EAttribute" name="speed" eType="#//Speed"/>
            </eClassifiers>
            <eSubpackages name="empty" nsURI="http://example.org/json/workshop/layout/empty" nsPrefix="empty"/>
          </eSubpackages>
        </ecore:EPackage>
        """

    /// A document with two root packages that refer to each other.
    static let twoRoots = """
        <?xml version="1.0" encoding="UTF-8"?>
        <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore">
          <ecore:EPackage name="first" nsURI="http://example.org/json/first" nsPrefix="first">
            <eClassifiers xsi:type="ecore:EClass" name="Alpha">
              <eStructuralFeatures xsi:type="ecore:EReference" name="beta" eType="#/1/Beta" eOpposite="#/1/Beta/alpha"/>
            </eClassifiers>
          </ecore:EPackage>
          <ecore:EPackage name="second" nsURI="http://example.org/json/second" nsPrefix="second">
            <eClassifiers xsi:type="ecore:EClass" name="Beta" eSuperTypes="#/0/Alpha">
              <eStructuralFeatures xsi:type="ecore:EReference" name="alpha" eType="#/0/Alpha" eOpposite="#/0/Alpha/beta"/>
            </eClassifiers>
          </ecore:EPackage>
        </xmi:XMI>
        """

    /// A metamodel in the form that emfjson-jackson documents show, written by hand.
    ///
    /// Classes are given as `eClass` URIs, references as `$ref` objects with or without the
    /// class of their target, and objects whose class a containment implies leave it out.
    static let handWritten = """
        {
          "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EPackage",
          "name": "garden",
          "nsPrefix": "garden",
          "nsURI": "http://example.org/json/garden",
          "eClassifiers": [
            {
              "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EClass",
              "name": "Bed",
              "eStructuralFeatures": [
                {
                  "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EAttribute",
                  "name": "label",
                  "unsettable": true,
                  "eType": { "$ref": "http://www.eclipse.org/emf/2002/Ecore#//EString" }
                },
                {
                  "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EReference",
                  "name": "plants",
                  "containment": true,
                  "upperBound": -1,
                  "eType": { "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EClass", "$ref": "//Plant" }
                },
                {
                  "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EAttribute",
                  "name": "soil",
                  "eType": { "$ref": "//Soil" }
                }
              ]
            },
            {
              "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EClass",
              "name": "Plant",
              "eSuperTypes": [ { "$ref": "//Bed" } ],
              "eStructuralFeatures": [
                {
                  "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EReference",
                  "name": "bed",
                  "eOpposite": { "$ref": "//Bed/plants" },
                  "eType": { "$ref": "//Bed" }
                }
              ]
            },
            {
              "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EEnum",
              "name": "Soil",
              "eLiterals": [ { "name": "Clay" }, { "name": "Loam", "value": 1 } ],
              "eAnnotations": [ { "source": "urn:example:note", "details": { "b": "2", "a": "1" } } ]
            }
          ]
        }
        """

    /// An instance of the hand-written metamodel.
    static let gardenInstance = """
        {"eClass": "http://example.org/json/garden#//Bed", "label": "north",
         "plants": [{"eClass": "http://example.org/json/garden#//Plant"}], "soil": "Loam"}
        """
}

/// Tests that metamodels are written as JSON and read back as native packages.
@Suite("JSON metamodels")
struct JSONMetamodelTests {
    private typealias Fixtures = JSONMetamodelFixtures

    // MARK: - Helpers

    /// A fresh temporary directory holding the given documents; the caller removes it.
    private static func directory(with documents: [String: String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONMetamodelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, text) in documents {
            try text.write(to: directory.appendingPathComponent(name), atomically: testWritesAtomically, encoding: .utf8)
        }
        return directory
    }

    /// The text of a document.
    private static func text(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// The parsed JSON object of a document with a single root.
    private static func object(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    /// The objects held by a key of a JSON object.
    private static func objects(_ key: String, of object: [String: Any]) -> [[String: Any]] {
        object[key] as? [[String: Any]] ?? []
    }

    /// The object of a list whose `name` is the given one.
    private static func named(_ name: String, in objects: [[String: Any]]) throws -> [String: Any] {
        try #require(objects.first { $0["name"] as? String == name })
    }

    /// The qualified class of an Ecore metaclass.
    private static func ecoreClass(_ name: String) -> String {
        Fixtures.ecore + "#//" + name
    }

    /// The description of each package, together with the XMI text that the packages are
    /// written as at a fixed location.
    private static func summary(of packages: [EPackage], at url: URL) -> (lines: [String], xmi: String) {
        let lines = packages.flatMap { MetamodelDescription($0).lines($0) }
        return (lines, XMISerializer().serialize(packages, relativeTo: url))
    }

    /// Loads the workshop and parts metamodels, saves the workshop as JSON and loads that
    /// document into a new resource set.
    ///
    /// - Parameters:
    ///   - directory: The directory that holds the metamodels.
    ///   - resourceSet: The resource set into which the JSON document is loaded.
    private static func workshopRoundTrip(in directory: URL, reloadingInto resourceSet: ResourceSet = ResourceSet())
        async throws -> (original: ModelIO.Loaded, json: String, reloaded: ModelIO.Loaded)
    {
        let original = try await ModelIO.load(
            url: directory.appendingPathComponent("workshop.ecore"), resourceSet: ResourceSet())
        let jsonURL = directory.appendingPathComponent("workshop.json")
        let diagnostics = try await ModelIO.save(original.resource, to: jsonURL)
        #expect(diagnostics.warnings.isEmpty)
        let reloaded = try await ModelIO.load(url: jsonURL, resourceSet: resourceSet)
        return (original, try text(of: jsonURL), reloaded)
    }

    // MARK: - Round trips

    @Test("an Ecore document survives conversion to JSON and back unchanged")
    func ecoreRoundTrip() async throws {
        let directory = try Self.directory(with: ["parts.ecore": Fixtures.parts, "workshop.ecore": Fixtures.workshop])
        defer { try? FileManager.default.removeItem(at: directory) }
        let (original, _, reloaded) = try await Self.workshopRoundTrip(in: directory)
        #expect(reloaded.format == .json)
        #expect(reloaded.packages.map(\.name) == ["workshop"])
        #expect(await reloaded.resource.getRootObjects().allSatisfy { $0 is EPackage })
        let tool = try #require(original.packages.first?.getEClass("Tool"))
        #expect(tool.eSuperTypes.map(\.name) == ["Named", "Part"])
        #expect(tool.eSuperTypes.first?.id == original.packages.first?.getEClass("Named")?.id)
        let ecoreURL = directory.appendingPathComponent("workshop.ecore")
        let before = Self.summary(of: original.packages, at: ecoreURL)
        let after = Self.summary(of: reloaded.packages, at: ecoreURL)
        #expect(before.lines.count > 40)
        #expect(after.lines == before.lines)
        #expect(after.xmi == before.xmi)
    }

    @Test("writing a metamodel read from JSON gives the same JSON again")
    func jsonIsStable() async throws {
        let directory = try Self.directory(with: ["parts.ecore": Fixtures.parts, "workshop.ecore": Fixtures.workshop])
        defer { try? FileManager.default.removeItem(at: directory) }
        let (_, json, reloaded) = try await Self.workshopRoundTrip(in: directory)
        let secondURL = directory.appendingPathComponent("second.json")
        try await ModelIO.save(reloaded.resource, to: secondURL)
        #expect(try Self.text(of: secondURL) == json)
        let third = try await ModelIO.load(url: secondURL, resourceSet: ResourceSet())
        var diagnostics = ConversionDiagnostics()
        let thirdText = try await ModelIO.serialise(
            third.resource, format: .json, relativeTo: secondURL, diagnostics: &diagnostics)
        #expect(thirdText == json)
    }

    @Test("the JSON document follows the emfjson conventions for Ecore models")
    func documentLayout() async throws {
        let directory = try Self.directory(with: ["parts.ecore": Fixtures.parts, "workshop.ecore": Fixtures.workshop])
        defer { try? FileManager.default.removeItem(at: directory) }
        let (_, json, _) = try await Self.workshopRoundTrip(in: directory)
        #expect(json.hasPrefix("{\n  \"eClass\": \"\(Self.ecoreClass("EPackage"))\",\n  \"name\": \"workshop\""))
        #expect(json.hasSuffix("}\n"))
        let root = try Self.object(json)
        #expect(root["nsURI"] as? String == "http://example.org/json/workshop")
        #expect(root["nsPrefix"] as? String == "ws")
        let classifiers = Self.objects("eClassifiers", of: root)
        let machine = try Self.named("Machine", in: classifiers)
        #expect(machine["eClass"] as? String == Self.ecoreClass("EClass"))
        #expect(Self.objects("eSuperTypes", of: machine).compactMap { $0["$ref"] as? String } == ["//Named", "//Powered"])
        let features = Self.objects("eStructuralFeatures", of: machine)
        let power = try Self.named("power", in: features)
        #expect(power["eClass"] as? String == Self.ecoreClass("EAttribute"))
        #expect(power["defaultValueLiteral"] as? String == "240")
        let powerType = try #require(power["eType"] as? [String: Any])
        #expect(powerType["$ref"] as? String == Fixtures.ecore + "#//EInt")
        #expect(powerType["eClass"] as? String == Self.ecoreClass("EDataType"))
        let tools = try Self.named("tools", in: features)
        #expect(tools["containment"] as? Bool == true)
        #expect(tools["upperBound"] as? Int == -1)
        #expect((tools["eOpposite"] as? [String: Any])?["$ref"] as? String == "//Tool/machine")
        #expect(Self.objects("eKeys", of: tools).compactMap { $0["$ref"] as? String } == ["//Tool/label"])
        let finish = try Self.named("finish", in: features)
        let finishType = try #require(finish["eType"] as? [String: Any])
        #expect(finishType["$ref"] as? String == "parts.ecore#//Finish")
        #expect(finishType["eClass"] as? String == Self.ecoreClass("EEnum"))
        let running = try Self.named("running", in: features)
        #expect(running["changeable"] as? Bool == false)
        #expect(running["derived"] as? Bool == true)
        #expect(running["ordered"] == nil)
        let tool = try Self.named("Tool", in: classifiers)
        #expect(Self.objects("eSuperTypes", of: tool).compactMap { $0["$ref"] as? String } == ["//Named", "parts.ecore#//Part"])
        let speed = try Self.named("Speed", in: classifiers)
        let literals = Self.objects("eLiterals", of: speed)
        #expect(literals.compactMap { $0["name"] as? String } == ["Slow", "Fast", "Idle"])
        #expect(literals[1]["value"] as? Int == 5)
        #expect(literals[1]["literal"] as? String == "FAST")
        #expect(literals[0]["value"] == nil)
        let handle = try Self.named("Handle", in: classifiers)
        #expect(handle["serializable"] as? Bool == false)
        #expect(handle["instanceClassName"] as? String == "java.lang.Object")
        let annotations = Self.objects("eAnnotations", of: root)
        #expect(annotations.first?["eClass"] as? String == Self.ecoreClass("EAnnotation"))
        let details = try #require(annotations.first?["details"] as? [String: String])
        #expect(details["alpha"] == "Line one\nLine two\ttabbed")
        let zeta = try #require(json.range(of: "\"zeta\""))
        let alpha = try #require(json.range(of: "\"alpha\""))
        #expect(zeta.lowerBound < alpha.lowerBound)
        let links = Self.objects("references", of: annotations[1]).compactMap { $0["$ref"] as? String }
        #expect(links == ["//Machine/tools", "//Speed/Fast", "parts.ecore#//Part"])
        let layout = try Self.named("layout", in: Self.objects("eSubpackages", of: root))
        #expect(layout["eClass"] as? String == Self.ecoreClass("EPackage"))
        #expect(layout["nsURI"] as? String == "http://example.org/json/workshop/layout")
    }

    @Test("references, opposites and keys of a JSON metamodel resolve to its elements")
    func referencesResolve() async throws {
        let directory = try Self.directory(with: ["parts.ecore": Fixtures.parts, "workshop.ecore": Fixtures.workshop])
        defer { try? FileManager.default.removeItem(at: directory) }
        let resourceSet = ResourceSet()
        let (_, _, reloaded) = try await Self.workshopRoundTrip(in: directory, reloadingInto: resourceSet)
        let package = try #require(reloaded.packages.first)
        let machine = try #require(package.getEClass("Machine"))
        let tool = try #require(package.getEClass("Tool"))
        let tools = try #require(machine.getEReference(name: "tools"))
        let back = try #require(tool.getEReference(name: "machine"))
        #expect(tools.opposite == back.id)
        #expect(back.opposite == tools.id)
        #expect(back.container)
        #expect(tools.eKeys == [try #require(tool.getEAttribute(name: "label")).id])
        #expect(machine.eSuperTypes.map(\.name) == ["Named", "Powered"])
        #expect(tool.eSuperTypes.map(\.name) == ["Named", "Part"])
        let part = try #require(tool.eSuperTypes.last)
        #expect(part.isAbstract)
        let parts = try #require(await resourceSet.getMetamodel(uri: "http://example.org/json/parts"))
        #expect(part.id == parts.getEClass("Part")?.id)
        #expect(tool.allAttributes.map(\.name).contains("serial"))
        let kind = try #require(machine.getEReference(name: "kind"))
        #expect(kind.eType.id == EcorePackage.metaClass(.eClass).id)
        let speed = try #require(machine.getEAttribute(name: "speed"))
        #expect(speed.eType is EEnum)
        #expect(speed.eType.id == package.getClassifier("Speed")?.id)
        let width = try #require(machine.getEAttribute(name: "width"))
        #expect(width.eType.name == "Millimetres")
        #expect((width.eType as? EDataType)?.instanceClassName == "double")
        let annotation = try #require(package.eAnnotations.first { $0.source == "urn:example:links" })
        #expect(annotation.references.first == .local(tools.id))
        let start = try #require((package.getEClass("Powered"))?.eOperations.first)
        #expect(start.eExceptions.map(\.name) == ["Fault"])
        #expect(start.eParameters.map(\.name) == ["speed", "notes"])
        #expect(await resourceSet.getMetamodel(uri: "http://example.org/json/workshop/layout") != nil)
    }

    @Test("a metamodel read from JSON validates like the original")
    func validation() async throws {
        let directory = try Self.directory(with: ["parts.ecore": Fixtures.parts, "workshop.ecore": Fixtures.workshop])
        defer { try? FileManager.default.removeItem(at: directory) }
        let (original, _, reloaded) = try await Self.workshopRoundTrip(in: directory)
        let validator = EcoreValidator()
        let before = validator.validate(MetamodelIndex(roots: original.packages)).map(\.code)
        let after = validator.validate(MetamodelIndex(roots: reloaded.packages)).map(\.code)
        #expect(after == before)
    }

    @Test("a document with several root packages is written as an array and read back")
    func multipleRoots() async throws {
        let directory = try Self.directory(with: ["pair.ecore": Fixtures.twoRoots])
        defer { try? FileManager.default.removeItem(at: directory) }
        let ecoreURL = directory.appendingPathComponent("pair.ecore")
        let original = try await ModelIO.load(url: ecoreURL, resourceSet: ResourceSet())
        #expect(original.packages.count == 2)
        let jsonURL = directory.appendingPathComponent("pair.json")
        try await ModelIO.save(original.resource, to: jsonURL)
        let json = try Self.text(of: jsonURL)
        let roots = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(roots.compactMap { $0["name"] as? String } == ["first", "second"])
        #expect(json.contains("\"$ref\": \"/1/Beta\""))
        #expect(json.contains("\"$ref\": \"/0/Alpha/beta\""))
        let reloaded = try await ModelIO.load(url: jsonURL, resourceSet: ResourceSet())
        #expect(reloaded.packages.map(\.name) == ["first", "second"])
        #expect(Self.summary(of: reloaded.packages, at: ecoreURL) == Self.summary(of: original.packages, at: ecoreURL))
        let alpha = try #require(reloaded.packages[0].getEClass("Alpha"))
        let beta = try #require(reloaded.packages[1].getEClass("Beta"))
        #expect(beta.eSuperTypes.first?.id == alpha.id)
        #expect(alpha.getEReference(name: "beta")?.opposite == beta.getEReference(name: "alpha")?.id)
        var diagnostics = ConversionDiagnostics()
        let again = try await ModelIO.serialise(reloaded.resource, format: .json, relativeTo: jsonURL, diagnostics: &diagnostics)
        #expect(again == json)
    }

    @Test("generic types, type parameters and keys survive conversion to JSON and back")
    func genericRoundTrip() async throws {
        let original = try await EPackage(text: GenericWritingFixtures.document, uri: GenericWritingFixtures.uri)
        let json = JSONSerializer().serialize([original])
        #expect(json.contains("\"eGenericType\""))
        #expect(json.contains("\"eTypeParameter\": {\n"))
        #expect(json.contains("\"eGenericSuperTypes\""))
        #expect(json.contains("\"eBounds\""))
        #expect(json.contains("\"eGenericExceptions\""))
        #expect(json.contains("\"eTypeArguments\""))
        let resourceSet = ResourceSet()
        let resource = try await resourceSet.loadEcoreResource(
            text: json, uri: "memory:/generic.json")
        let reloaded = try #require(await resource.getRootObjects().first as? EPackage)
        #expect(JSONSerializer().serialize([reloaded]) == json)
        let xmi = XMISerializer().serialize(reloaded)
        #expect(xmi.contains("<eGenericType eTypeParameter=\"#//Box/convert/R\"/>"))
        #expect(xmi.contains("<eGenericSuperTypes eClassifier=\"#//Box\">"))
        #expect(xmi.contains("eKeys=\"#//Item/key\""))
        let viaXMI = try await EPackage(text: xmi, uri: GenericWritingFixtures.uri)
        #expect(JSONSerializer().serialize([viaXMI]) == json)
        #expect(XMISerializer().serialize(viaXMI) == xmi)
    }

    @Test("a metamodel refers to another metamodel written as JSON")
    func crossDocumentJSON() async throws {
        let workshopJSON = Fixtures.workshop.replacingOccurrences(of: "parts.ecore#", with: "parts.json#")
        let directory = try Self.directory(with: ["parts.ecore": Fixtures.parts, "workshop.ecore": workshopJSON])
        defer { try? FileManager.default.removeItem(at: directory) }
        let parts = try await ModelIO.load(url: directory.appendingPathComponent("parts.ecore"), resourceSet: ResourceSet())
        try await ModelIO.save(parts.resource, to: directory.appendingPathComponent("parts.json"))
        let resourceSet = ResourceSet()
        let (_, json, reloaded) = try await Self.workshopRoundTrip(in: directory, reloadingInto: resourceSet)
        #expect(json.contains("\"$ref\": \"parts.json#//Part\""))
        #expect(json.contains("\"$ref\": \"parts.json#//spares/Spare\""))
        let package = try #require(reloaded.packages.first)
        let tool = try #require(package.getEClass("Tool"))
        #expect(tool.eSuperTypes.map(\.name) == ["Named", "Part"])
        let spare = try #require(package.getEClass("Machine")?.getEReference(name: "spare"))
        #expect(spare.eType.name == "Spare")
        let loadedParts = try #require(await resourceSet.getMetamodel(uri: "http://example.org/json/parts"))
        #expect(tool.eSuperTypes.last?.id == loadedParts.getEClass("Part")?.id)
        #expect(loadedParts.origin?.documentURI.hasSuffix("parts.json") == true)
    }

    @Test("a hand-written emfjson metamodel loads as native packages")
    func handWrittenDocument() async throws {
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(
            data: Data(Fixtures.handWritten.utf8), uri: "memory:/garden.json", resourceSet: resourceSet)
        #expect(loaded.format == .json)
        let package = try #require(loaded.packages.first)
        #expect(package.nsURI == "http://example.org/json/garden")
        let bed = try #require(package.getEClass("Bed"))
        let plant = try #require(package.getEClass("Plant"))
        #expect(plant.eSuperTypes.map(\.id) == [bed.id])
        #expect(bed.getEAttribute(name: "label")?.unsettable == true)
        #expect(bed.getEAttribute(name: "label")?.eType.id == EcorePackage.dataType(.eString)?.id)
        let plants = try #require(bed.getEReference(name: "plants"))
        #expect(plants.containment)
        #expect(plant.getEReference(name: "bed")?.opposite == plants.id)
        let soil = try #require(package.getClassifier("Soil") as? EEnum)
        #expect(soil.literals.map(\.name) == ["Clay", "Loam"])
        #expect(soil.literals.map(\.value) == [0, 1])
        #expect(soil.eAnnotations.first?.detailEntries.map(\.key) == ["b", "a"])
        #expect(await resourceSet.getMetamodel(uri: package.nsURI) != nil)
    }

    @Test("a metamodel read from JSON types the instance documents that use it")
    func instancesOfJSONMetamodel() async throws {
        let resourceSet = ResourceSet()
        let metamodel = try await ModelIO.load(
            data: Data(Fixtures.handWritten.utf8), uri: "memory:/garden.json", resourceSet: resourceSet)
        let package = try #require(metamodel.packages.first)
        let instance = try await ModelIO.load(
            data: Data(Fixtures.gardenInstance.utf8), uri: "memory:/beds.json", resourceSet: resourceSet)
        #expect(instance.packages.isEmpty)
        let root = try #require(await instance.resource.getRootObjects().first as? DynamicEObject)
        #expect(root.eClass.id == package.getEClass("Bed")?.id)
        #expect(root.eGet("label") as? String == "north")
        #expect(instance.diagnostics.warnings.isEmpty)
    }

    @Test("the JSON parser reads a metamodel document as native packages")
    func parserReadsMetamodels() async throws {
        let data = Data(Fixtures.handWritten.utf8)
        let resourceSet = ResourceSet()
        let resource = try await JSONParser(resourceSet: resourceSet).parse(data, uri: "memory:/garden.json")
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        #expect(package.name == "garden")
        #expect(await resourceSet.getMetamodel(uri: "http://example.org/json/garden")?.id == package.id)
        let standalone = try await JSONParser().parse(data, uri: "memory:/garden.json")
        let roots = await standalone.getRootObjects()
        #expect(roots.count == 1)
        #expect((roots.first as? EPackage)?.getEClass("Plant") != nil)
    }

    @Test("the JSON serialiser writes a resource of native packages")
    func serialiserWritesPackages() async throws {
        let resourceSet = ResourceSet()
        let resource = try await resourceSet.loadEcoreResource(text: Fixtures.handWritten, uri: "memory:/garden.json")
        let text = try await JSONSerializer().serialize(resource)
        #expect(text.contains("\"eClass\": \"\(Self.ecoreClass("EPackage"))\""))
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        #expect(text == JSONSerializer().serialize([package]))
        var diagnostics = ConversionDiagnostics()
        let ecore = try await ModelIO.serialise(resource, format: .ecore, diagnostics: &diagnostics)
        #expect(ecore.contains("name=\"garden\""))
    }

    @Test("an Ecore document is written as JSON by the Ecore API too")
    func ecoreAPI() async throws {
        let directory = try Self.directory(with: ["parts.ecore": Fixtures.parts])
        defer { try? FileManager.default.removeItem(at: directory) }
        let package = try await EPackage(url: directory.appendingPathComponent("parts.ecore"))
        let jsonURL = directory.appendingPathComponent("copy.json")
        try JSONSerializer().serialize(package, to: jsonURL)
        let reloaded = try await EPackage(url: jsonURL)
        #expect(MetamodelDescription(reloaded).lines(reloaded) == MetamodelDescription(package).lines(package))
    }

    // MARK: - Instance documents

    @Test("instance documents are read as dynamic objects as before")
    func instanceDocumentsUnchanged() async throws {
        let instance = #"{"eClass": "EPackage", "name": "notAMetamodel", "size": 2}"#
        let resource = try await JSONParser().parse(Data(instance.utf8), uri: "memory:/plain.json")
        let root = try #require(await resource.getRootObjects().first as? DynamicEObject)
        #expect(root.eClass.name == "EPackage")
        #expect(root.eGet("size") as? Int == 2)
        let loaded = try await ModelIO.load(
            data: Data(#"{"eClass": "http://example.org/other#//Thing", "count": 1}"#.utf8),
            uri: "memory:/thing.json", resourceSet: ResourceSet())
        #expect(loaded.packages.isEmpty)
        #expect(await loaded.resource.getRootObjects().first is DynamicEObject)
    }

    // MARK: - Errors

    /// The error raised by loading a JSON metamodel document.
    private static func loadingError(_ text: String) async -> (any Error)? {
        do {
            _ = try await ResourceSet().loadEcoreResource(text: text, uri: "memory:/broken.json")
            return nil
        } catch {
            return error
        }
    }

    /// A metamodel document whose only class has the given features.
    private static func document(features: String, classifierClass: String = "EClass") -> String {
        """
        {"eClass": "\(ecoreClass("EPackage"))", "name": "broken", "nsURI": "http://example.org/json/broken",
         "nsPrefix": "broken", "eClassifiers": [{"eClass": "\(ecoreClass(classifierClass))", "name": "Thing",
         "eStructuralFeatures": [\(features)]}]}
        """
    }

    @Test("malformed JSON is reported with its position")
    func malformedJSON() async throws {
        let text = "{\"eClass\": \"\(Self.ecoreClass("EPackage"))\",\n  \"name\": \"broken\",\n  \"nsURI\" \"x\"}"
        let error = try #require(await Self.loadingError(text) as? JSONError)
        #expect(error.description.contains("line 3"), "\(error)")
        let unterminated = try #require(await Self.loadingError(#"{"eClass": "#) as? JSONError)
        #expect(unterminated.description.contains("line 1"), "\(unterminated)")
        let nested = String(repeating: "[", count: 10_000) + String(repeating: "]", count: 10_000)
        #expect(await Self.loadingError(nested) is JSONError)
    }

    @Test("an unknown Ecore class is reported by name")
    func unknownClass() async throws {
        let feature = #"{"eClass": "http://www.eclipse.org/emf/2002/Ecore#//EAttribut", "name": "size"}"#
        let error = try #require(await Self.loadingError(Self.document(features: feature)) as? JSONError)
        #expect(error.description.contains("EAttribut"), "\(error)")
        let misplaced = try #require(
            await Self.loadingError(Self.document(features: "", classifierClass: "EAttribute")) as? JSONError)
        #expect(misplaced.description.contains("EAttribute"), "\(misplaced)")
        #expect(misplaced.description.contains("eClassifiers"), "\(misplaced)")
    }

    @Test("a reference to an element that does not exist is reported")
    func danglingReference() async throws {
        let feature = """
            {"eClass": "\(Self.ecoreClass("EReference"))", "name": "next", "eType": {"$ref": "//Missing"}}
            """
        let error = try #require(await Self.loadingError(Self.document(features: feature)) as? JSONError)
        #expect(error.description.contains("//Missing"), "\(error)")
        #expect(error.description.contains("eType"), "\(error)")
        #expect(error.description.contains("//@eClassifiers.0/@eStructuralFeatures.0"), "\(error)")
        let builtIn = """
            {"eClass": "\(Self.ecoreClass("EAttribute"))", "name": "size",
             "eType": {"$ref": "http://www.eclipse.org/emf/2002/Ecore#//EWhole"}}
            """
        let ecoreError = try #require(await Self.loadingError(Self.document(features: builtIn)) as? JSONError)
        #expect(ecoreError.description.contains("EWhole"), "\(ecoreError)")
    }

    @Test("a JSON document that is not a metamodel is not loaded as one")
    func notAMetamodel() async throws {
        let error = try #require(await Self.loadingError(Fixtures.gardenInstance) as? JSONError)
        #expect(error.description.contains("EPackage"), "\(error)")
        let unnamed = #"{"eClass": "http://www.eclipse.org/emf/2002/Ecore#//EPackage", "nsURI": "urn:x", "nsPrefix": "x"}"#
        let missing = try #require(await Self.loadingError(unnamed) as? JSONError)
        #expect(missing.description.contains("name"), "\(missing)")
    }
}
