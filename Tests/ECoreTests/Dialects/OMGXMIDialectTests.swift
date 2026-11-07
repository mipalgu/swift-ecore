import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that documents in the OMG dialect of XMI are read and written.
@Suite("OMG XMI dialect")
struct OMGXMIDialectTests {
    /// The directory of the dialect fixtures.
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/dialects")

    /// Loads the shop metamodel into a new resource set.
    static func shopSet() async throws -> ResourceSet {
        let resourceSet = ResourceSet()
        try await ModelIO.registerMetamodels(at: [directory.appendingPathComponent("shop.ecore")], in: resourceSet)
        return resourceSet
    }

    /// Reads a document with an XMI parser of a resource set.
    static func parse(_ text: String, uri: String, in resourceSet: ResourceSet) async throws -> Resource {
        try await XMIParser(resourceSet: resourceSet).parse(text, uri: uri)
    }

    /// The object of a resource whose `name` has a given value.
    static func object(named name: String, in resource: Resource) async -> (any EObject)? {
        for object in await resource.getAllObjects() {
            if await resource.eGet(objectId: object.id, feature: "name") as? String == name { return object }
        }
        return nil
    }

    @Test("XMI 2.5.1 roots, ids, idrefs, hrefs and xmi:type are read")
    func readsOMGDocument() async throws {
        let resourceSet = try await Self.shopSet()
        let url = Self.directory.appendingPathComponent("shop-omg.xmi")
        let resource = try await XMIParser(resourceSet: resourceSet).parse(url)
        let roots = await resource.getRootObjects()
        #expect(roots.map { $0.eClass.name } == ["Shop", "Shop"])

        let guide = try #require(await Self.object(named: "Field Guide", in: resource))
        let torch = try #require(await Self.object(named: "Torch", in: resource))
        let atlas = try #require(await Self.object(named: "Atlas", in: resource))
        #expect(guide.eClass.name == "Book")
        #expect(torch.eClass.name == "Gadget")
        #expect(await resource.eGet(objectId: guide.id, feature: "price") as? Double == 12.5)
        #expect(await resource.eGet(objectId: torch.id, feature: "wireless") as? Bool == true)
        #expect(await resource.eGet(objectId: guide.id, feature: "related") as? [EUUID] == [torch.id])
        #expect(await resource.eGet(objectId: torch.id, feature: "related") as? [EUUID] == [guide.id, atlas.id])
        #expect(await resource.eGet(objectId: roots[0].id, feature: "featured") as? EUUID == torch.id)

        let proxy = try #require(await resource.eGet(objectId: roots[1].id, feature: "featured") as? ResourceProxy)
        #expect(proxy.uri.hasSuffix("dialects/shop-stock.xmi"))
        #expect(proxy.fragment == "q1")

        let classNames = Set(await resource.getAllObjects().map { $0.eClass.name })
        #expect(!classNames.contains("Documentation"))
        #expect(!classNames.contains("Extension"))
        #expect(!classNames.contains("layout"))
        #expect(try await parserDiagnostics(for: url, in: resourceSet).isEmpty)
    }

    /// The warnings of a fresh parse of a document.
    private func parserDiagnostics(for url: URL, in resourceSet: ResourceSet) async throws -> [ConversionWarning] {
        let parser = XMIParser(resourceSet: resourceSet)
        _ = try await parser.parse(url)
        return await parser.diagnostics.warnings
    }

    @Test("Every later XMI version is read in the OMG dialect", arguments: XMIVersion.allCases.filter(\.isOMG))
    func readsEveryOMGVersion(version: XMIVersion) async throws {
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <xmi:XMI xmi:version="\(version.versionText)" xmlns:xmi="\(version.namespaceURI)" xmlns:shop="http://example.org/shop">
              <xmi:Documentation exporter="Hand written" exporterVersion="1.0"/>
              <shop:Shop xmi:id="s1" name="Kiosk">
                <products xmi:type="shop:Gadget" xmi:id="p1" name="Radio"/>
                <featured xmi:idref="p1"/>
              </shop:Shop>
            </xmi:XMI>
            """
        let resourceSet = try await Self.shopSet()
        let resource = try await Self.parse(text, uri: "memory:/kiosk.xmi", in: resourceSet)
        let roots = await resource.getRootObjects()
        #expect(roots.map { $0.eClass.name } == ["Shop"])
        let radio = try #require(await Self.object(named: "Radio", in: resource))
        #expect(radio.eClass.name == "Gadget")
        #expect(await resource.eGet(objectId: roots[0].id, feature: "featured") as? EUUID == radio.id)
    }

    @Test("An EMF document keeps its XMI elements as before")
    func emfDocumentIsUnchanged() async throws {
        #expect(XMIVersion(namespaceURI: EcoreURI.xmiNamespace.rawValue) == .v2_0)
        #expect(XMIVersion.v2_0.isOMG == false)
        #expect(XMIDialectSyntax.isDocumentationOrExtension("xmi:Extension"))
        #expect(XMIDialectSyntax.isDocumentationOrExtension("xmi:documentation"))
        #expect(!XMIDialectSyntax.isDocumentationOrExtension("Extension"))
    }

    @Test("Models are written with xmi:type in the namespace of a later XMI version")
    func writesOMGDialect() async throws {
        let resourceSet = try await Self.shopSet()
        let url = Self.directory.appendingPathComponent("shop-omg.xmi")
        let resource = try await XMIParser(resourceSet: resourceSet).parse(url)
        let options = XMISerializationOptions(
            attributeStyleReferences: true, typeQualifiers: false, nameBasedFragments: true, relativeURIs: true,
            omitDefaultValues: true, manyValuedAttributesAsElements: true, referenceStyle: .plain,
            xmiVersion: .v2_5, typeAttribute: .xmi)
        let text = try await XMISerializer(options: options).serialize(resource, relativeTo: url)
        #expect(text.contains("xmi:version=\"20131001\""))
        #expect(text.contains("xmlns:xmi=\"http://www.omg.org/spec/XMI/20131001\""))
        #expect(text.contains("xmi:type=\"shop:Book\""))
        #expect(!text.contains("xsi:"))
        #expect(text.contains("featured=\"p2\""))
        #expect(text.contains("related=\"p1 p3\""))
        #expect(text.contains("featured=\"shop-stock.xmi#q1\""))

        let reread = try await Self.parse(
            text, uri: url.deletingLastPathComponent().appendingPathComponent("shop-copy.xmi").absoluteString,
            in: resourceSet)
        let torch = try #require(await Self.object(named: "Torch", in: reread))
        let guide = try #require(await Self.object(named: "Field Guide", in: reread))
        #expect(torch.eClass.name == "Gadget")
        #expect(await reread.eGet(objectId: guide.id, feature: "related") as? [EUUID] == [torch.id])
        #expect(await reread.getRootObjects().count == 2)
        let annex = try #require(await Self.object(named: "Annex", in: reread))
        let proxy = try #require(await reread.eGet(objectId: annex.id, feature: "featured") as? ResourceProxy)
        #expect(proxy.uri.hasSuffix("dialects/shop-stock.xmi"))
    }

    @Test("The default options still write xsi:type in the EMF namespace")
    func defaultOptionsAreUnchanged() {
        #expect(XMISerializationOptions.emf.xmiVersion == .v2_0)
        #expect(XMISerializationOptions.emf.typeAttribute == .xsi)
        #expect(XMISerializationOptions.legacy == XMISerializationOptions())
        #expect(XMISerializationOptions.uml.typeAttribute == .xmi)
        #expect(XMISerializationOptions.uml.xmiVersion == .v2_5)
    }

    @Test("OMG UML namespaces and primitive types are read as Eclipse UML2")
    func readsOMGUML() async throws {
        let resourceSet = ResourceSet()
        let (uml, _) = try await UMLMetamodel.packages()
        await resourceSet.registerMetamodel(uml, uri: UMLNamespaces.uml)
        let url = Self.directory.appendingPathComponent("class-model-omg.xmi")
        let resource = try await XMIParser(resourceSet: resourceSet).parse(url)
        let model = try #require(await resource.getRootObjects().first)
        #expect(model.eClass.name == "Model")
        let plant = try #require(await Self.object(named: "Plant", in: resource))
        let bed = try #require(await Self.object(named: "Bed", in: resource))
        let name = try #require(await Self.object(named: "name", in: resource))
        let link = try #require(await Self.object(named: "bed", in: resource))
        #expect(plant.eClass.name == "Class")
        #expect(name.eClass.name == "Property")
        #expect(await resource.eGet(objectId: bed.id, feature: "isAbstract") as? Bool == true)
        #expect(await resource.eGet(objectId: link.id, feature: "type") as? EUUID == bed.id)
        let type = try #require(await resource.eGet(objectId: name.id, feature: "type") as? ResourceProxy)
        #expect(type.uri == "pathmap://UML_LIBRARIES/UMLPrimitiveTypes.library.uml")
        #expect(type.fragment == "String")
        let comments = try #require(await resource.eGet(objectId: bed.id, feature: "ownedComment") as? EUUID)
        #expect(await resource.eGet(objectId: comments, feature: "body") as? String == "A bed holds plants.")
        #expect(await resource.eGet(objectId: comments, feature: "annotatedElement") as? [EUUID] == [bed.id])
    }

    @Test("Namespace aliases map onto Eclipse UML2")
    func namespaceTable() {
        #expect(UMLNamespaces.eclipseNamespace(for: "http://www.omg.org/spec/UML/20131001") == UMLNamespaces.uml)
        #expect(UMLNamespaces.eclipseNamespace(for: "http://schema.omg.org/spec/UML/2.1") == UMLNamespaces.uml)
        #expect(UMLNamespaces.eclipseNamespace(for: "http://www.eclipse.org/uml2/3.0.0/UML") == UMLNamespaces.uml)
        #expect(UMLNamespaces.eclipseNamespace(for: UMLNamespaces.uml) == nil)
        #expect(UMLNamespaces.eclipseNamespace(for: "http://www.omg.org/spec/UML/20131001/StandardProfile")
            == UMLNamespaces.standardProfile)
        #expect(UMLNamespaces.eclipseNamespace(for: "http://www.omg.org/spec/UML/20110701/StandardProfileL2")
            == UMLNamespaces.standardProfile)
        #expect(UMLNamespaces.eclipseNamespace(for: "http://example.org/shop") == nil)
        #expect(UMLNamespaces.eclipseDocument(for: "http://www.omg.org/spec/UML/20110701/PrimitiveTypes.xmi")
            == "pathmap://UML_LIBRARIES/UMLPrimitiveTypes.library.uml")
        #expect(UMLNamespaces.eclipseDocument(for: "http://example.org/other.xmi") == nil)
    }
}
