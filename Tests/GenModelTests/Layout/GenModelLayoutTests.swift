//
// GenModelLayoutTests.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import Testing

@testable import GenModel

@Suite("GenModel document layout")
struct GenModelLayoutTests {
    /// The source model of the authored fixtures, laid out as EMF lays out Ecore documents.
    private static let shopEcore = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="shop" nsURI="http://example.org/shop" nsPrefix="shop">
          <eClassifiers xsi:type="ecore:EClass" name="Item">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="title" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
          </eClassifiers>
        </ecore:EPackage>

        """

    /// The body of the authored generator model that follows the root start tag.
    private static let shopBody = """
          <foreignModel>shop.ecore</foreignModel>
          <genPackages prefix="Shop" basePackage="org.example" disposableProviderFactory="true"
              ecorePackage="shop.ecore#/">
            <genClasses ecoreClass="shop.ecore#//Item" labelFeature="#//shop/Item/title">
              <genFeatures createChild="false" ecoreFeature="ecore:EAttribute shop.ecore#//Item/title"/>
            </genClasses>
          </genPackages>
        </genmodel:GenModel>

        """

    /// The generator model in the current root layout.
    private static let standardGenModel =
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <genmodel:GenModel xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
            xmlns:genmodel="http://www.eclipse.org/emf/2002/GenModel" modelDirectory="/shop/src" modelPluginID="shop" modelName="Shop"
            importerID="org.example.importer" complianceLevel="17.0">

        """ + shopBody

    /// The generator model in the layout where the declarations start after `xmi:version`.
    private static let versionFirstGenModel =
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <genmodel:GenModel xmi:version="2.0"
            xmlns:xmi="http://www.omg.org/XMI" xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
            xmlns:genmodel="http://www.eclipse.org/emf/2002/GenModel" modelDirectory="/shop/src"
            modelPluginID="shop" modelName="Shop" importerID="org.example.importer" complianceLevel="17.0">

        """ + shopBody

    /// Writes the fixtures to a scratch directory and returns the generator model location.
    private static func write(_ genModel: String, ecore: String = shopEcore) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ecore.write(
            to: directory.appendingPathComponent("shop.ecore"), atomically: true, encoding: .utf8)
        let url = directory.appendingPathComponent("shop.genmodel")
        try genModel.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func roundTrip(_ text: String) async throws -> (written: String, layout: XMIRootLayout) {
        let url = try write(text)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let resourceSet = ResourceSet()
        let document = try await GenModelResource.loadDocument(
            url: url, resourceSet: resourceSet, resolution: .nameFragments)
        let written = try await GenModelResource.serialised(
            document.resource, for: url, rootLayout: document.rootLayout)
        return (written, document.rootLayout)
    }

    @Test("a document in the current root layout is written back unchanged")
    func standardRoundTrip() async throws {
        let (written, layout) = try await Self.roundTrip(Self.standardGenModel)
        #expect(layout == .standard)
        #expect(written == Self.standardGenModel)
    }

    @Test("a document in the version-first root layout is written back unchanged")
    func versionFirstRoundTrip() async throws {
        let (written, layout) = try await Self.roundTrip(Self.versionFirstGenModel)
        #expect(layout == .versionFirst)
        #expect(written == Self.versionFirstGenModel)
    }

    @Test("saving writes the wrapped layout by default")
    func saveWrapsByDefault() async throws {
        let url = try Self.write(Self.standardGenModel)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let resourceSet = ResourceSet()
        let resource = try await GenModelResource.load(
            url: url, resourceSet: resourceSet, resolution: .nameFragments)
        let target = url.deletingLastPathComponent().appendingPathComponent("saved.genmodel")
        try await GenModelResource.save(resource, to: target)
        let text = try String(contentsOf: target, encoding: .utf8)
        #expect(text == Self.standardGenModel)
    }

    @Test("a label feature is identified by the names of its Ecore elements")
    func labelFeatureFragment() async throws {
        let (written, _) = try await Self.roundTrip(Self.standardGenModel)
        #expect(written.contains("labelFeature=\"#//shop/Item/title\""))
    }

    @Test("a label feature that names nothing is written back unchanged")
    func danglingLabelFeature() async throws {
        let text = Self.standardGenModel.replacingOccurrences(
            of: "#//shop/Item/title", with: "#//shop/Item/missing")
        let (written, _) = try await Self.roundTrip(text)
        #expect(written == text)
    }

    @Test("source models that are not Ecore documents are not loaded and are kept")
    func foreignModelOfAnotherKind() async throws {
        let text = Self.standardGenModel.replacingOccurrences(
            of: "<foreignModel>shop.ecore</foreignModel>",
            with: "<foreignModel>shop.mdl</foreignModel>")
        let (written, _) = try await Self.roundTrip(text)
        #expect(written == text)
    }

    @Test("used generator packages in other locations are written back verbatim")
    func usedGenPackagesVerbatim() async throws {
        let location = "platform:/plugin/org.example.base/model/Base.genmodel#//base"
        let text = Self.standardGenModel.replacingOccurrences(
            of: "complianceLevel=\"17.0\">",
            with: "complianceLevel=\"17.0\" usedGenPackages=\"\(location)\">")
        let (written, _) = try await Self.roundTrip(text)
        #expect(written.contains("usedGenPackages=\"\(location)\""))
        #expect(written.hasSuffix(Self.shopBody))
    }

    @Test("an unsettable attribute set to its default value is written back")
    func explicitDefaultIsKept() async throws {
        let (written, _) = try await Self.roundTrip(Self.standardGenModel)
        #expect(written.contains("createChild=\"false\""))
    }

    @Test("the layout of an unwrapped document is detected as the current one")
    func detectsStandard() {
        #expect(XMIRootLayout.detect(in: Self.standardGenModel) == .standard)
        #expect(XMIRootLayout.detect(in: Self.versionFirstGenModel) == .versionFirst)
        #expect(XMIRootLayout.detect(in: "") == .standard)
    }

    @Test("every kind of generator element is named by its Ecore element in fragments")
    func fragmentRules() {
        let named = GenModelFragments.rules.map(\.className)
        #expect(named == GenModelConstants.FeatureName.ecoreReferenceByClass.map(\.className))
        #expect(named.contains(GenModelConstants.ClassName.genFeature))
        #expect(Set(named).count == named.count)
    }

    @Test("a string and a file written for the same location agree")
    func stringAndFileAgree() async throws {
        let url = try Self.write(Self.standardGenModel)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let resourceSet = ResourceSet()
        let resource = try await GenModelResource.load(
            url: url, resourceSet: resourceSet, resolution: .nameFragments)
        let text = try await XMISerializer(options: .emfWrapped).serialize(resource, relativeTo: url)
        let target = url.deletingLastPathComponent().appendingPathComponent("same.genmodel")
        try await XMISerializer(options: .emfWrapped).serialize(resource, to: target)
        #expect(try String(contentsOf: target, encoding: .utf8) == text)
    }
}
