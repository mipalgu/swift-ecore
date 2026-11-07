import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that root packages without a namespace load as in EMF and that every root
/// package of a document can be loaded.
@Suite("Optional package namespaces")
struct OptionalNamespaceTests {
    /// The namespace URI of the package that declares one.
    private static let shelfURI = "http://example.org/shelf"

    /// A document with a package of data types that has no namespace, followed by a package
    /// with a namespace whose features refer to those data types by `xmi:id` and by fragment.
    private static let twoRoots = """
    <?xml version="1.0" encoding="UTF-8"?>
    <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore">
      <ecore:EPackage xmi:id="t1" name="PrimitiveTypes">
        <eClassifiers xsi:type="ecore:EDataType" xmi:id="t2" name="Boolean"/>
        <eClassifiers xsi:type="ecore:EDataType" xmi:id="t3" name="Integer"/>
        <eClassifiers xsi:type="ecore:EDataType" xmi:id="t4" name="String"/>
      </ecore:EPackage>
      <ecore:EPackage xmi:id="s1" name="Shelf" nsURI="http://example.org/shelf" nsPrefix="shelf">
        <eClassifiers xsi:type="ecore:EClass" xmi:id="s2" name="Item" abstract="true">
          <eStructuralFeatures xsi:type="ecore:EAttribute" xmi:id="s3" name="label" lowerBound="1" eType="t4"/>
          <eStructuralFeatures xsi:type="ecore:EAttribute" xmi:id="s8" name="note" eType="#/0/String"/>
        </eClassifiers>
        <eClassifiers xsi:type="ecore:EClass" xmi:id="s4" name="Box" eSuperTypes="s2">
          <eStructuralFeatures xsi:type="ecore:EAttribute" xmi:id="s5" name="capacity" eType="t3"/>
          <eStructuralFeatures xsi:type="ecore:EAttribute" xmi:id="s6" name="sealed" eType="t2"/>
          <eStructuralFeatures xsi:type="ecore:EReference" xmi:id="s7" name="contents" upperBound="-1" \
    eType="s2" containment="true"/>
        </eClassifiers>
      </ecore:EPackage>
    </xmi:XMI>
    """

    /// A single package with a namespace URI but no prefix.
    private static let withoutPrefix = """
    <ecore:EPackage xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" name="labels" nsURI="urn:test:labels">
      <eClassifiers xsi:type="ecore:EClass" name="Label"/>
    </ecore:EPackage>
    """

    /// A package without a name, which a strict load still rejects.
    private static let withoutName = """
    <ecore:EPackage xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" nsURI="urn:test:anonymous" nsPrefix="anonymous"/>
    """

    /// Loads the two-root document into a new resource set.
    private static func loadTwoRoots(
        options: EcoreLoadOptions = EcoreLoadOptions()
    ) async throws -> (set: ResourceSet, resource: Resource, packages: [EPackage]) {
        let set = ResourceSet()
        let resource = try await set.loadEcoreResource(text: twoRoots, uri: "memory:/shelf.ecore", options: options)
        let packages = await resource.getRootObjects().compactMap { $0 as? EPackage }
        return (set, resource, packages)
    }

    /// The attribute with a given name that a class declares.
    private static func attribute(_ name: String, of eClass: EClass) -> EAttribute? {
        eClass.eAttributes.first { $0.name == name }
    }

    /// Writes a document to a new temporary directory.
    private static func temporaryFile(_ text: String, name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OptionalNamespaceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: testWritesAtomically, encoding: .utf8)
        return url
    }

    @Test("A strict load accepts a root package without a namespace and reports warnings")
    func strictLoad() async throws {
        let (_, resource, packages) = try await Self.loadTwoRoots()
        #expect(packages.map(\.name) == ["PrimitiveTypes", "Shelf"])
        let primitives = try #require(packages.first)
        #expect(primitives.nsURI.isEmpty)
        #expect(primitives.nsPrefix.isEmpty)
        #expect(primitives.eClassifiers.map(\.name) == ["Boolean", "Integer", "String"])
        #expect(packages.last?.nsURI == Self.shelfURI)
        let diagnostics = await resource.loadDiagnostics
        #expect(diagnostics.map(\.code) == [EcoreLoadDiagnostic.missingNamespaceURI, EcoreLoadDiagnostic.missingNamespacePrefix])
        #expect(diagnostics.allSatisfy { $0.severity == .warning && $0.document == resource.uri })
        #expect(diagnostics.allSatisfy { $0.message.contains("PrimitiveTypes") })
    }

    @Test("References by xmi:id and by fragment reach the package without a namespace")
    func crossRootReferences() async throws {
        let (_, _, packages) = try await Self.loadTwoRoots()
        let primitives = try #require(packages.first)
        let shelf = try #require(packages.last)
        let item = try #require(shelf.getEClass("Item"))
        let box = try #require(shelf.getEClass("Box"))
        let string = try #require(primitives.getEDataType("String"))
        #expect(Self.attribute("label", of: item)?.eType.id == string.id)
        #expect(Self.attribute("note", of: item)?.eType.id == string.id)
        #expect(Self.attribute("capacity", of: box)?.eType.id == primitives.getEDataType("Integer")?.id)
        #expect(Self.attribute("sealed", of: box)?.eType.id == primitives.getEDataType("Boolean")?.id)
        #expect(box.eSuperTypes.map(\.id) == [item.id])
        #expect(box.eReferences.first { $0.name == "contents" }?.eType.id == item.id)
    }

    @Test("Only packages with a namespace are registered")
    func registration() async throws {
        let (set, _, packages) = try await Self.loadTwoRoots()
        #expect(await set.getMetamodelURIs() == [Self.shelfURI])
        #expect(await set.getMetamodel(uri: "") == nil)
        let url = try Self.temporaryFile(Self.twoRoots, name: "shelf.ecore")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let registering = ResourceSet()
        let registered = try await ModelIO.registerMetamodels(at: [url], in: registering)
        #expect(registered.map(\.name) == packages.map(\.name))
        #expect(await registering.getMetamodelURIs() == [Self.shelfURI])
    }

    @Test("Validation still reports the missing namespace URI")
    func validation() async throws {
        let (_, _, packages) = try await Self.loadTwoRoots()
        let primitives = try #require(packages.first)
        let diagnostics = EcoreValidator().validate(MetamodelIndex(roots: packages))
        let namespaces = diagnostics.filter { $0.code == .wellFormedNsURI }
        #expect(namespaces.map(\.element) == [primitives.id])
        #expect(namespaces.first?.severity == .error)
    }

    @Test("Tolerant loading reports the omissions as before")
    func tolerantLoad() async throws {
        let (_, resource, packages) = try await Self.loadTwoRoots(options: EcoreLoadOptions(tolerant: true))
        #expect(packages.first?.nsURI.isEmpty == true)
        let diagnostics = await resource.loadDiagnostics
        #expect(diagnostics.map(\.code) == [EcoreLoadDiagnostic.missingNamespaceURI, EcoreLoadDiagnostic.missingNamespacePrefix])
        #expect(diagnostics.allSatisfy { $0.severity == .error && $0.message == "Missing required attribute '\($0.code == EcoreLoadDiagnostic.missingNamespaceURI ? "nsURI" : "nsPrefix")'" })
    }

    @Test("A missing prefix alone is reported alone")
    func missingPrefix() async throws {
        let resource = try await ResourceSet().loadEcoreResource(text: Self.withoutPrefix, uri: "memory:/labels.ecore")
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        #expect(package.nsURI == "urn:test:labels")
        #expect(package.nsPrefix.isEmpty)
        #expect(await resource.loadDiagnostics.map(\.code) == [EcoreLoadDiagnostic.missingNamespacePrefix])
    }

    @Test("A strict load still rejects a package without a name")
    func missingName() async {
        await #expect(throws: XMIError.self) {
            _ = try await ResourceSet().loadEcoreResource(text: Self.withoutName, uri: "memory:/anonymous.ecore")
        }
    }

    @Test("The XMI parser reads the document as dynamic objects")
    func dynamicParse() async throws {
        let parser = XMIParser()
        let resource = try await parser.parse(Self.twoRoots, uri: "memory:/shelf.ecore")
        let roots = await resource.getRootObjects()
        #expect(roots.count == 2)
        #expect((roots.first as? DynamicEObject)?.eGet("nsURI") as? String == "")
        #expect(await resource.loadDiagnostics.count == 2)
    }

    @Test("Writing and reading the packages again reaches a fixed point")
    func rewrite() async throws {
        let (_, _, packages) = try await Self.loadTwoRoots()
        let written = XMISerializer(options: .emf).serialize(packages)
        let reloaded = try await ResourceSet().loadEcoreResource(text: written, uri: "memory:/shelf.ecore")
        let again = await reloaded.getRootObjects().compactMap { $0 as? EPackage }
        #expect(again.map(\.name) == ["PrimitiveTypes", "Shelf"])
        #expect(XMISerializer(options: .emf).serialize(again) == written)
    }

    @Test("A JSON metamodel whose root package has no namespace loads with warnings")
    func jsonRoot() async throws {
        let json = """
        {
          "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EPackage",
          "name": "PrimitiveTypes",
          "eClassifiers": [
            {"eClass": "http://www.eclipse.org/emf/2002/Ecore#//EDataType", "name": "Text"}
          ]
        }
        """
        let set = ResourceSet()
        let resource = try await set.loadEcoreResource(text: json, uri: "memory:/primitives.json")
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        #expect(package.name == "PrimitiveTypes")
        #expect(package.nsURI.isEmpty)
        #expect(package.nsPrefix.isEmpty)
        #expect(package.getEDataType("Text") != nil)
        let diagnostics = await resource.loadDiagnostics
        #expect(diagnostics.map(\.code) == [EcoreLoadDiagnostic.missingNamespaceURI, EcoreLoadDiagnostic.missingNamespacePrefix])
        #expect(diagnostics.allSatisfy { $0.severity == .warning && $0.document == resource.uri })
        #expect(await set.getMetamodelURIs().isEmpty)
    }

    @Test("Model loading returns every root package")
    func modelIOLoad() async throws {
        let url = try Self.temporaryFile(Self.twoRoots, name: "shelf.ecore")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let set = ResourceSet()
        let loaded = try await ModelIO.load(url: url, resourceSet: set)
        #expect(loaded.format == .ecore)
        #expect(loaded.packages.map(\.name) == ["PrimitiveTypes", "Shelf"])
        #expect(await loaded.resource.loadDiagnostics.count == 2)
        #expect(await set.getMetamodelURIs() == [Self.shelfURI])
    }

    @Test("All root packages of a file load in document order")
    func rootPackages() async throws {
        let url = try Self.temporaryFile(Self.twoRoots, name: "shelf.ecore")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let packages = try await EPackage.rootPackages(url: url)
        #expect(packages.map(\.name) == ["PrimitiveTypes", "Shelf"])
        let shelf = try #require(packages.last)
        let box = try #require(shelf.getEClass("Box"))
        #expect(Self.attribute("capacity", of: box)?.eType.id == packages.first?.getEDataType("Integer")?.id)
        let first = try await EPackage(url: url)
        #expect(first.name == "PrimitiveTypes")
        #expect(first.eClassifiers.map(\.name) == packages.first?.eClassifiers.map(\.name))
    }

    @Test("All root packages honour the load options")
    func rootPackagesOptions() async throws {
        let text = """
        <ecore:EPackage xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" nsURI="urn:test:unnamed" nsPrefix="unnamed">
          <eClassifiers xsi:type="ecore:EClass" name="Thing"/>
        </ecore:EPackage>
        """
        let url = try Self.temporaryFile(text, name: "unnamed.ecore")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await #expect(throws: XMIError.self) { _ = try await EPackage.rootPackages(url: url) }
        let packages = try await EPackage.rootPackages(url: url, options: EcoreLoadOptions(tolerant: true))
        #expect(packages.map(\.name) == [""])
        #expect(packages.first?.getEClass("Thing") != nil)
    }

    @Test("A single root package is returned alone")
    func singleRoot() async throws {
        let url = try Self.temporaryFile(Self.withoutPrefix, name: "labels.ecore")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let packages = try await EPackage.rootPackages(url: url)
        #expect(packages.map(\.name) == ["labels"])
        await #expect(throws: (any Error).self) {
            _ = try await EPackage.rootPackages(url: url.deletingLastPathComponent().appendingPathComponent("absent.ecore"))
        }
    }
}
