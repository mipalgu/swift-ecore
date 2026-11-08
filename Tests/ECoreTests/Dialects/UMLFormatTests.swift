import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that UML models are read with the bundled metamodel, can be queried, and round-trip.
@Suite("UML models")
struct UMLFormatTests {
    /// The directory of the dialect fixtures.
    static let directory = OMGXMIDialectTests.directory

    /// The namespace of the profile that the stereotype fixtures apply but do not contain.
    static let missingProfile = "http:///schemas/Gardening/_g1/0"

    /// The namespace of the profile that the profiled fixture contains.
    static let embeddedProfile = "http:///schemas/Gardening/_g2/0"

    /// Reads a fixture into a new resource set.
    static func read(_ name: String, in resourceSet: ResourceSet = ResourceSet()) async throws
        -> ModelDocumentReadResult
    {
        try await UMLFormat.read(url: directory.appendingPathComponent(name), resourceSet: resourceSet)
    }

    /// The objects of a resource by name, for the objects whose name is unique.
    static func objectsByName(in resource: Resource) async -> [String: any EObject] {
        var objects: [String: any EObject] = [:]
        for object in await resource.getAllObjects() {
            if let name = await resource.eGet(objectId: object.id, feature: "name") as? String {
                objects[name] = object
            }
        }
        return objects
    }

    /// The names of the classes of the objects of a resource, with their counts.
    static func classCounts(in resource: Resource) async -> [String: Int] {
        var counts: [String: Int] = [:]
        for object in await resource.getAllObjects() { counts[object.eClass.name, default: 0] += 1 }
        return counts
    }

    @Test("A class model loads as instances of the UML metamodel")
    func loadsClassModel() async throws {
        let read = try await Self.read("garden.uml")
        #expect(read.diagnostics.isEmpty, "\(read.diagnostics.map(\.message))")
        let resource = read.resource
        let roots = await resource.getRootObjects()
        #expect(roots.count == 1)
        #expect(roots.first?.eClass.name == "Model")
        let (uml, _) = try await UMLMetamodel.packages()
        #expect(roots.first?.eClass.id == uml.getEClass("Model")?.id)

        let objects = await Self.objectsByName(in: resource)
        let plant = try #require(objects["Plant"])
        let rose = try #require(objects["Rose"])
        let bed = try #require(objects["Bed"])
        let season = try #require(objects["Season"])
        #expect(plant.eClass.name == "Class")
        #expect(season.eClass.name == "Enumeration")
        #expect(await resource.eGet(objectId: plant.id, feature: "isAbstract") as? Bool == true)
        #expect(await resource.eGet(objectId: rose.id, feature: "isAbstract") == nil)

        let generalization = try #require(await resource.eGet(objectId: rose.id, feature: "generalization") as? EUUID)
        #expect(await resource.eGet(objectId: generalization, feature: "general") as? EUUID == plant.id)
        let literals = try #require(await resource.eGet(objectId: season.id, feature: "ownedLiteral") as? [EUUID])
        #expect(literals.count == 4)

        let plantsEnd = try #require(objects["plants"].flatMap { $0.eClass.name == "Property" ? $0 : nil })
        #expect(await resource.eGet(objectId: plantsEnd.id, feature: "type") as? EUUID == plant.id)
        #expect(await resource.eGet(objectId: plantsEnd.id, feature: "aggregation") as? String == "composite")
        let holds = try #require(objects["holds"])
        let ends = try #require(await resource.eGet(objectId: holds.id, feature: "memberEnd") as? [EUUID])
        #expect(ends.first == plantsEnd.id)
        #expect(ends.count == 2)

        let name = try #require(await Self.firstProperty(named: "name", in: resource))
        let type = try #require(await resource.eGet(objectId: name.id, feature: "type") as? ResourceProxy)
        #expect(type.uri == "pathmap://UML_LIBRARIES/UMLPrimitiveTypes.library.uml")
        #expect(type.fragment == "String")

        let counts = await Self.classCounts(in: resource)
        #expect(counts["Class"] == 3)
        #expect(counts["Property"] == 6)
        #expect(counts["EnumerationLiteral"] == 4)
    }

    /// The first property of a resource with a given name.
    static func firstProperty(named name: String, in resource: Resource) async -> (any EObject)? {
        for object in await resource.getAllObjects() where object.eClass.name == "Property" {
            if await resource.eGet(objectId: object.id, feature: "name") as? String == name { return object }
        }
        return nil
    }

    @Test("A loaded class model can be queried")
    func queriesClassModel() async throws {
        let read = try await Self.read("garden.uml")
        let (uml, _) = try await UMLMetamodel.packages()
        let reference = EcoreReferenceModel(rootPackage: uml, resource: Resource(uri: "memory:/uml"))
        let model = EcoreModel(resource: read.resource, referenceModel: reference)
        let evaluator = ECoreQueryEvaluator(executionEngine: ECoreExecutionEngine(models: ["garden": model]))
        let objects = await Self.objectsByName(in: read.resource)
        let plant = try #require(objects["Plant"])
        let classContext = try #require(uml.getEClass("Class"))
        #expect(try await evaluator.evaluate(ECoreQuery("self.name", context: classContext), on: plant) as? String
            == "Plant")
        #expect(try await evaluator.evaluate(ECoreQuery("self.isAbstract", context: classContext), on: plant) as? Bool
            == true)
    }

    @Test("A class model round-trips through the Eclipse UML2 layout")
    func roundTrips() async throws {
        let url = Self.directory.appendingPathComponent("garden.uml")
        let first = try await Self.read("garden.uml")
        let written = try await UMLFormat.write(first.resource, relativeTo: url)
        #expect(written.diagnostics.isEmpty, "\(written.diagnostics.map(\.message))")
        let text = written.text
        #expect(text.contains("xmlns:xmi=\"http://www.omg.org/spec/XMI/20131001\""))
        #expect(text.contains("xmlns:uml=\"http://www.eclipse.org/uml2/5.0.0/UML\""))
        #expect(text.contains("<packagedElement xmi:type=\"uml:Class\" xmi:id=\"Rose\" name=\"Rose\">"))
        #expect(text.contains("general=\"Plant\""))
        #expect(text.contains("memberEnd=\"Bed-plants Bed-holds-bed\""))
        #expect(text.contains("pathmap://UML_LIBRARIES/UMLPrimitiveTypes.library.uml#String"))
        #expect(UMLFormat.sniff(data: Data(text.utf8)))

        let copyURL = Self.directory.appendingPathComponent("garden-copy.uml")
        let second = try await UMLFormat.read(
            data: Data(text.utf8), uri: copyURL.absoluteString, resourceSet: ResourceSet())
        #expect(second.diagnostics.isEmpty)
        #expect(await Self.classCounts(in: second.resource) == Self.classCounts(in: first.resource))
        let objects = await Self.objectsByName(in: second.resource)
        let rose = try #require(objects["Rose"])
        let plant = try #require(objects["Plant"])
        let generalization = try #require(
            await second.resource.eGet(objectId: rose.id, feature: "generalization") as? EUUID)
        #expect(await second.resource.eGet(objectId: generalization, feature: "general") as? EUUID == plant.id)
        let rewritten = try await UMLFormat.write(second.resource, relativeTo: url)
        #expect(rewritten.text == text)
    }

    @Test("A class model round-trips through JSON with the classes of the UML metamodel")
    func roundTripsThroughJSON() async throws {
        let first = try await Self.read("garden.uml")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uml-json-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = directory.appendingPathComponent("garden.json")
        _ = try await ModelIO.save(first.resource, to: json, format: .json)

        let loaded = try await ModelIO.load(url: json, format: .json, resourceSet: ResourceSet())

        #expect(loaded.diagnostics.warnings.isEmpty, "\(loaded.diagnostics.warnings.map(\.message))")
        let (uml, _) = try await UMLMetamodel.packages()
        let roots = await loaded.resource.getRootObjects()
        #expect(roots.first?.eClass.id == uml.getEClass("Model")?.id)
        #expect(await Self.classCounts(in: loaded.resource) == Self.classCounts(in: first.resource))
        let copy = directory.appendingPathComponent("garden-copy.uml")
        let written = try await UMLFormat.write(loaded.resource, relativeTo: copy)
        #expect(written.text.contains("xmlns:uml=\"http://www.eclipse.org/uml2/5.0.0/UML\""), "\(written.text)")
        #expect(written.text.contains("<packagedElement xmi:type=\"uml:Class\""), "\(written.text)")
        let second = try await UMLFormat.read(data: Data(written.text.utf8), uri: copy.absoluteString, resourceSet: ResourceSet())
        #expect(second.diagnostics.isEmpty, "\(second.diagnostics.map(\.message))")
        #expect(await Self.classCounts(in: second.resource) == Self.classCounts(in: first.resource))
    }

    @Test("A stereotype application without its profile loads with a warning")
    func stereotypeWithoutProfile() async throws {
        let read = try await Self.read("garden-stereotyped.uml")
        let unresolved = read.diagnostics.filter { $0.code == ModelDocumentDiagnostic.unresolvedProfile }
        #expect(unresolved.count == 1)
        #expect(unresolved.first?.severity == .warning)
        #expect(unresolved.first?.message.contains(Self.missingProfile) == true)
        #expect(!read.diagnostics.contains { $0.severity == .error })
        let roots = await read.resource.getRootObjects()
        #expect(roots.map { $0.eClass.name } == ["Model", "Perennial"])
        #expect(await read.resource.eGet(objectId: roots[1].id, feature: "base_Class") as? String == "Shrub")
    }

    @Test("A stereotype application is typed by a profile in the same document")
    func stereotypeWithEmbeddedProfile() async throws {
        let resourceSet = ResourceSet()
        let read = try await Self.read("garden-profiled.uml", in: resourceSet)
        #expect(!read.diagnostics.contains { $0.code == ModelDocumentDiagnostic.unresolvedProfile })
        let profile = try #require(await resourceSet.getMetamodel(uri: Self.embeddedProfile))
        let perennial = try #require(profile.getEClass("Perennial"))
        #expect(perennial.getStructuralFeature(name: "base_Class") is EReference)
        let roots = await read.resource.getRootObjects()
        #expect(roots.map { $0.eClass.name } == ["Profile", "Model", "Perennial"])
        let application = roots[2]
        #expect(application.eClass.id == perennial.id)
        let apple = try #require(await Self.objectsByName(in: read.resource)["Apple"])
        #expect(await read.resource.eGet(objectId: application.id, feature: "base_Class") as? EUUID == apple.id)
        #expect(await read.resource.eGet(objectId: application.id, feature: "lifespan") as? Int == 40)
    }

    @Test("A profile with its Ecore definition and its applications round-trips")
    func profileRoundTrips() async throws {
        let url = Self.directory.appendingPathComponent("garden-profiled.uml")
        let first = try await Self.read("garden-profiled.uml")
        let written = try await UMLFormat.write(first.resource, relativeTo: url)
        #expect(written.diagnostics.isEmpty, "\(written.diagnostics.map(\.message))")
        #expect(written.text.contains("xmlns:ecore=\"http://www.eclipse.org/emf/2002/Ecore\""))
        #expect(written.text.contains("<contents xmi:type=\"ecore:EPackage\""))
        let second = try await UMLFormat.read(
            data: Data(written.text.utf8), uri: Self.directory.appendingPathComponent("garden-copy.uml").absoluteString,
            resourceSet: ResourceSet())
        #expect(!second.diagnostics.contains { $0.code == ModelDocumentDiagnostic.unresolvedProfile })
        #expect(await Self.classCounts(in: second.resource) == Self.classCounts(in: first.resource))
        let rewritten = try await UMLFormat.write(second.resource, relativeTo: url)
        #expect(rewritten.text == written.text)
    }

    @Test("An activity keeps its nodes, which Eclipse UML2 writes under the name of a derived feature")
    func activityNodesRoundTrip() async throws {
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <uml:Model xmi:version="20131001" xmlns:xmi="http://www.omg.org/spec/XMI/20131001" \
            xmlns:uml="http://www.eclipse.org/uml2/5.0.0/UML" xmi:id="m" name="Watering">
              <packagedElement xmi:type="uml:Activity" xmi:id="a" name="water" node="start end">
                <edge xmi:type="uml:ControlFlow" xmi:id="flow" target="end" source="start"/>
                <node xmi:type="uml:InitialNode" xmi:id="start" name="start" outgoing="flow"/>
                <node xmi:type="uml:ActivityFinalNode" xmi:id="end" name="end" incoming="flow"/>
              </packagedElement>
            </uml:Model>
            """
        let read = try await UMLFormat.read(
            data: Data(text.utf8), uri: "memory:/watering.uml", resourceSet: ResourceSet())
        let objects = await Self.objectsByName(in: read.resource)
        let activity = try #require(objects["water"])
        let start = try #require(objects["start"])
        let end = try #require(objects["end"])
        #expect(await read.resource.eGet(objectId: activity.id, feature: "ownedNode") as? [EUUID] == [start.id, end.id])
        let written = try await UMLFormat.write(read.resource)
        #expect(written.text.contains("<node xmi:type=\"uml:InitialNode\" xmi:id=\"start\""))
        #expect(!written.text.contains("ownedNode"))
        let reread = try await UMLFormat.read(
            data: Data(written.text.utf8), uri: "memory:/watering-copy.uml", resourceSet: ResourceSet())
        #expect(await Self.classCounts(in: reread.resource) == Self.classCounts(in: read.resource))
    }

    @Test("A stereotype application is typed by a registered profile")
    func stereotypeWithRegisteredProfile() async throws {
        let (uml, _) = try await UMLMetamodel.packages()
        let umlClass = try #require(uml.getEClass("Class"))
        let base = EReference(name: "base_Class", eType: umlClass, lowerBound: 1)
        let lifespan = EAttribute(name: "lifespan", eType: EDataType(name: "EInt"))
        let perennial = EClass(name: "Perennial", eStructuralFeatures: [base, lifespan])
        let profile = EPackage(
            name: "Gardening", nsURI: Self.missingProfile, nsPrefix: "Gardening", eClassifiers: [perennial])
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(profile)
        let read = try await Self.read("garden-stereotyped.uml", in: resourceSet)
        #expect(!read.diagnostics.contains { $0.code == ModelDocumentDiagnostic.unresolvedProfile })
        let roots = await read.resource.getRootObjects()
        let shrub = try #require(await Self.objectsByName(in: read.resource)["Shrub"])
        #expect(roots.last?.eClass.id == perennial.id)
        #expect(await read.resource.eGet(objectId: roots[1].id, feature: "base_Class") as? EUUID == shrub.id)
        #expect(await read.resource.eGet(objectId: roots[1].id, feature: "lifespan") as? Int == 12)
    }

    @Test("UML documents are recognised by their namespaces")
    func sniffsUML() throws {
        for name in ["garden.uml", "garden-stereotyped.uml", "garden-profiled.uml", "class-model-omg.xmi"] {
            let data = try Data(contentsOf: Self.directory.appendingPathComponent(name))
            #expect(UMLFormat.sniff(data: data), "\(name)")
        }
        for name in ["shop.ecore", "shop-omg.xmi"] {
            let data = try Data(contentsOf: Self.directory.appendingPathComponent(name))
            #expect(!UMLFormat.sniff(data: data), "\(name)")
        }
        #expect(!UMLFormat.sniff(data: Data("{}".utf8)))
        #expect(UMLFormat.fileExtension == "uml")
    }
}
