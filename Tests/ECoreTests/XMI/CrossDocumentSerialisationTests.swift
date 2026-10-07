//
// CrossDocumentSerialisationTests.swift
// ECoreTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for the EMF-style serialisation of cross-document references.
@Suite("Cross-Document Reference Serialisation")
struct CrossDocumentSerialisationTests {

    /// Reads a fixture file as text.
    private func text(of name: String, in fixtures: CrossDocumentFixtures) throws -> String {
        try String(contentsOf: fixtures.directory.appendingPathComponent(name), encoding: .utf8)
    }

    /// Creates a `Mapping` resource at a URI inside the fixtures' resource set.
    ///
    /// - Parameters:
    ///   - uri: The URI of the new resource.
    ///   - configure: Sets features on the root `Mapping` object before it is added.
    /// - Returns: The resource and the identifier of the root object.
    private func makeMapping(
        _ fixtures: CrossDocumentFixtures, uri: String, configure: (inout DynamicEObject) -> Void
    ) async throws -> (resource: Resource, root: EUUID) {
        let package = try #require(await fixtures.resourceSet.getMetamodel(uri: "http://swift-modelling.org/test/mapping"))
        var root = DynamicEObject(eClass: try #require(package.getEClass("Mapping")))
        configure(&root)
        let resource = await fixtures.resourceSet.createResource(uri: uri)
        await resource.add(root)
        return (resource, root.id)
    }

    // MARK: - Round trips

    @Test("A normalised instance document round trips byte for byte")
    func roundTripsByteForByte() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadMapping()
        let written = try await XMISerializer(options: .emf).serialize(resource)
        #expect(written == (try text(of: "library.mapping", in: fixtures)))
    }

    @Test("Resolved references serialise to the same document")
    func resolvedReferencesRoundTrip() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadMapping()
        _ = await fixtures.resourceSet.resolveAllProxies()
        let written = try await XMISerializer(options: .emf).serialize(resource)
        #expect(written == (try text(of: "library.mapping", in: fixtures)))
    }

    @Test("Native Ecore targets serialise with qualifiers and name-based fragments")
    func nativeTargetsSerialise() async throws {
        let fixtures = try await CrossDocumentFixtures()
        _ = try await fixtures.resourceSet.loadEcoreResource(uri: fixtures.uri("library.ecore"))
        let resource = try await fixtures.loadMapping()
        _ = await fixtures.resourceSet.resolveAllProxies()
        let written = try await XMISerializer(options: .emf).serialize(resource)
        #expect(written.contains("ecoreFeature=\"ecore:EAttribute library.ecore#//Book/title\""))
        #expect(written.contains("ecoreLiteral=\"library.ecore#//BookCategory/Mystery\""))
        #expect(written.contains("ecorePackage=\"library.ecore#/\""))
    }

    // MARK: - Direct objects of another resource

    @Test("Objects of another resource serialise as relative cross-document references")
    func serialisesForeignObjects() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let withAttribute = EAttribute(name: "attr", eType: EDataType(name: "EString"))
        let eClass = EClass(name: "Thing", eStructuralFeatures: [withAttribute])
        let package = EPackage(name: "things", nsURI: "http://x/things", nsPrefix: "th", eClassifiers: [eClass])
        let target = await fixtures.resourceSet.createResource(uri: "file:///models/b/things.ecore")
        await target.registerNativePackage(package)

        let source = try await makeMapping(fixtures, uri: "file:///models/a/c/doc.mapping") { root in
            root.eSet("ecorePackage", value: package.id)
        }
        let entry = try #require(await fixtures.resourceSet.getMetamodel(uri: "http://swift-modelling.org/test/mapping")?.getEClass("Entry"))
        var item = DynamicEObject(eClass: entry)
        item.eSet("ecoreClass", value: eClass.id)
        item.eSet("ecoreFeature", value: withAttribute.id)
        await source.resource.register(item)
        await source.resource.eSet(objectId: source.root, feature: "entries", value: item.id)

        let written = try await XMISerializer(options: .emf).serialize(source.resource)
        #expect(written.contains("ecorePackage=\"../../b/things.ecore#/\""))
        #expect(written.contains("ecoreClass=\"../../b/things.ecore#//Thing\""))
        #expect(written.contains("ecoreFeature=\"ecore:EAttribute ../../b/things.ecore#//Thing/attr\""))

        var absolute = XMISerializationOptions.emf
        absolute.relativeURIs = false
        let absoluteText = try await XMISerializer(options: absolute).serialize(source.resource)
        #expect(absoluteText.contains("ecorePackage=\"file:///models/b/things.ecore#/\""))

        var positional = XMISerializationOptions.emf
        positional.nameBasedFragments = false
        let positionalText = try await XMISerializer(options: positional).serialize(source.resource)
        #expect(positionalText.contains("ecoreClass=\"../../b/things.ecore#\(eClass.id.uuidString)\""))
    }

    @Test("Dangling references are reported")
    func danglingReferencesThrow() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let source = try await makeMapping(fixtures, uri: "file:///models/dangling.mapping") { root in
            root.eSet("ecorePackage", value: EUUID())
        }
        await #expect(throws: XMIError.self) {
            _ = try await XMISerializer(options: .emf).serialize(source.resource)
        }
    }

    @Test("The default serialiser writes objects of other resources as href elements")
    func legacySerialiserWritesForeignObjects() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let package = EPackage(name: "things", nsURI: "http://x/things", nsPrefix: "th")
        let target = await fixtures.resourceSet.createResource(uri: "file:///models/things.ecore")
        await target.registerNativePackage(package)
        let source = try await makeMapping(fixtures, uri: "file:///models/legacy.mapping") { root in
            root.eSet("ecorePackage", value: package.id)
            root.eSet("name", value: "Legacy")
        }
        let written = try await XMISerializer().serialize(source.resource)
        #expect(written.contains("<ecorePackage href=\"file:///models/things.ecore#"))
    }

    // MARK: - Options

    @Test("Without attribute-style references, href child elements are written")
    func writesHrefChildren() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadMapping()
        var options = XMISerializationOptions.emf
        options.attributeStyleReferences = false
        let written = try await XMISerializer(options: options).serialize(resource)
        #expect(written.contains("<ecorePackage href=\"library.ecore#/\"/>"))
        #expect(written.contains("<ecoreFeature xsi:type=\"ecore:EAttribute\" href=\"library.ecore#//Book/title\"/>"))
        #expect(written.contains("xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\""))
        #expect(!written.contains(" ecoreClass="))
    }

    @Test("Type qualifiers and many-valued attribute layout can be switched off")
    func switchesCanBeDisabled() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let resource = try await fixtures.loadMapping()
        var options = XMISerializationOptions.emf
        options.typeQualifiers = false
        options.manyValuedAttributesAsElements = false
        let written = try await XMISerializer(options: options).serialize(resource)
        #expect(!written.contains("ecore:EAttribute"))
        #expect(!written.contains("xmlns:ecore"))
        #expect(written.contains("notes=\"first note second &amp; last note\""))
        #expect(!written.contains("<notes>"))
    }

    @Test("Default values and unset features are omitted")
    func omitsDefaults() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let defaults = try await makeMapping(fixtures, uri: "file:///models/defaults.mapping") { root in
            root.eSet("name", value: "")
            root.eSet("enabled", value: true)
            root.eSet("priority", value: 0)
        }
        let omitted = try await XMISerializer(options: .emf).serialize(defaults.resource)
        #expect(omitted.contains("<map:Mapping xmi:version=\"2.0\" xmlns:xmi=\"http://www.omg.org/XMI\" xmlns:map=\"http://swift-modelling.org/test/mapping\" name=\"\"/>"))

        var keep = XMISerializationOptions.emf
        keep.omitDefaultValues = false
        let kept = try await XMISerializer(options: keep).serialize(defaults.resource)
        #expect(kept.contains("enabled=\"true\""))
        #expect(kept.contains("priority=\"0\""))

        let changed = try await makeMapping(fixtures, uri: "file:///models/changed.mapping") { root in
            root.eSet("enabled", value: false)
            root.eSet("priority", value: 2)
        }
        let written = try await XMISerializer(options: .emf).serialize(changed.resource)
        #expect(written.contains("priority=\"2\" enabled=\"false\"") || written.contains("enabled=\"false\" priority=\"2\""))
    }

    @Test("Attributes are written in feature order regardless of the order they were set")
    func writesInFeatureOrder() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let ordered = try await makeMapping(fixtures, uri: "file:///models/ordered.mapping") { root in
            root.eSet("priority", value: 9)
            root.eSet("name", value: "n")
        }
        let written = try await XMISerializer(options: .emf).serialize(ordered.resource)
        #expect(written.contains(" name=\"n\" priority=\"9\"/>"))
    }

    @Test("Default values of primitive types and enumerations are recognised")
    func recognisesTypeDefaults() async throws {
        let literals = [EEnumLiteral(name: "First", value: 0), EEnumLiteral(name: "Second", value: 1)]
        let kind = EEnum(name: "Kind", literals: literals)
        let attributes: [any EStructuralFeature] = [
            EAttribute(name: "flag", eType: EDataType(name: "EBoolean")),
            EAttribute(name: "ratio", eType: EDataType(name: "EDouble")),
            EAttribute(name: "count", eType: EDataType(name: "EInt")),
            EAttribute(name: "kind", eType: kind),
            EAttribute(name: "text", eType: EDataType(name: "EString")),
            EAttribute(name: "boxed", eType: EDataType(name: "EIntegerObject")),
        ]
        let thing = EClass(name: "Thing", eStructuralFeatures: attributes)
        let package = EPackage(name: "defs", nsURI: "http://x/defs", nsPrefix: "defs", eClassifiers: [thing, kind])
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(package, uri: package.nsURI)
        let resource = await resourceSet.createResource(uri: "file:///models/defs.xmi")
        var object = DynamicEObject(eClass: thing)
        object.eSet("flag", value: false)
        object.eSet("ratio", value: 0.0)
        object.eSet("count", value: 0)
        object.eSet("kind", value: "First")
        object.eSet("text", value: "")
        object.eSet("boxed", value: 0)
        await resource.add(object)

        let written = try await XMISerializer(options: .emf).serialize(resource)
        #expect(written == """
            <?xml version="1.0" encoding="UTF-8"?>
            <defs:Thing xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:defs="http://x/defs" text="" boxed="0"/>

            """)

        object = DynamicEObject(eClass: thing)
        object.eSet("kind", value: "Second")
        object.eSet("ratio", value: 1.5)
        let other = await resourceSet.createResource(uri: "file:///models/defs2.xmi")
        await other.add(object)
        let second = try await XMISerializer(options: .emf).serialize(other)
        #expect(second.contains("ratio=\"1.5\" kind=\"Second\""))
    }

    // MARK: - Namespaces and structure

    @Test("Namespaces are declared in a fixed order with xsi only when a type is written")
    func declaresNamespacesInOrder() async throws {
        let base = EClass(name: "Base", eStructuralFeatures: [EAttribute(name: "id", eType: EDataType(name: "EString"))])
        let derived = EClass(
            name: "Derived", eSuperTypes: [base],
            eStructuralFeatures: [EAttribute(name: "extra", eType: EDataType(name: "EString"))])
        var containment = EReference(name: "nodes", eType: base)
        containment.containment = true
        containment.upperBound = -1
        let holder = EClass(name: "Holder", eStructuralFeatures: [containment])
        let package = EPackage(name: "tree", nsURI: "http://x/tree", nsPrefix: "tr", eClassifiers: [base, derived, holder])
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(package, uri: package.nsURI)
        let resource = await resourceSet.createResource(uri: "file:///models/tree.xmi")

        var plain = DynamicEObject(eClass: base)
        plain.eSet("id", value: "a")
        var special = DynamicEObject(eClass: derived)
        special.eSet("id", value: "b")
        special.eSet("extra", value: "x")
        await resource.register(plain)
        await resource.register(special)
        var root = DynamicEObject(eClass: holder)
        root.eSet("nodes", value: [plain.id, special.id])
        await resource.add(root)

        let written = try await XMISerializer(options: .emf).serialize(resource)
        #expect(written == """
            <?xml version="1.0" encoding="UTF-8"?>
            <tr:Holder xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:tr="http://x/tree">
              <nodes id="a"/>
              <nodes xsi:type="tr:Derived" id="b" extra="x"/>
            </tr:Holder>

            """)
    }

    @Test("Several root objects are wrapped in an xmi:XMI element")
    func wrapsMultipleRoots() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let first = try await makeMapping(fixtures, uri: "file:///models/multi.mapping") { $0.eSet("name", value: "one") }
        let package = try #require(await fixtures.resourceSet.getMetamodel(uri: "http://swift-modelling.org/test/mapping"))
        var second = DynamicEObject(eClass: try #require(package.getEClass("Mapping")))
        second.eSet("name", value: "two")
        await first.resource.add(second)

        let written = try await XMISerializer(options: .emf).serialize(first.resource)
        #expect(written == """
            <?xml version="1.0" encoding="UTF-8"?>
            <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:map="http://swift-modelling.org/test/mapping">
              <map:Mapping name="one"/>
              <map:Mapping name="two"/>
            </xmi:XMI>

            """)
    }

    @Test("Classes outside registered metamodels use a derived namespace")
    func usesFallbackNamespace() async throws {
        let resource = Resource(uri: "file:///models/loose.xmi")
        var object = DynamicEObject(eClass: EClass(name: "Gadget"))
        object.eSet("size", value: 3)
        await resource.add(object)
        let written = try await XMISerializer(options: .emf).serialize(resource)
        #expect(written == """
            <?xml version="1.0" encoding="UTF-8"?>
            <gadget:Gadget xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:gadget="http://swift-modelling.org/test/gadget" size="3"/>

            """)
    }

    @Test("Empty resources and non-dynamic roots are rejected")
    func rejectsUnsupportedRoots() async throws {
        let empty = Resource(uri: "file:///models/empty.xmi")
        await #expect(throws: XMIError.self) { _ = try await XMISerializer(options: .emf).serialize(empty) }

        let native = Resource(uri: "file:///models/native.ecore")
        await native.registerNativePackage(EPackage(name: "p", nsURI: "http://x/p", nsPrefix: "p"))
        await #expect(throws: XMIError.self) { _ = try await XMISerializer(options: .emf).serialize(native) }
    }

    @Test("Local proxies and mixed reference lists keep their order")
    func mixedReferenceListsRoundTrip() async throws {
        let fixtures = try await CrossDocumentFixtures()
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <map:Mapping xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:map="http://swift-modelling.org/test/mapping">
              <entries label="a" related="#//@entries.1 other.mapping#/"/>
              <entries label="b"/>
            </map:Mapping>

            """
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mixed-\(UUID().uuidString).mapping")
        try xml.write(to: file, atomically: testWritesAtomically, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let resource = try await fixtures.resourceSet.loadXMIResource(uri: file.absoluteString)
        let written = try await XMISerializer(options: .emf).serialize(resource)
        #expect(written == xml)
    }

    @Test("The default options keep the original layout")
    func defaultOptionsAreLegacy() {
        #expect(XMISerializer().options == .legacy)
        #expect(XMISerializationOptions.legacy != .emf)
        #expect(XMISerializationOptions().attributeStyleReferences == false)
    }
}
