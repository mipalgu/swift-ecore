import Foundation
import Testing

@testable import ECore

/// Verifies document metadata that belongs alongside a native metamodel.
@Suite("Ecore document metadata")
struct EcoreDocumentMetadataTests {
    /// A self-authored document with comments and explicit identifiers.
    private static let document = """
    <?xml version="1.0" encoding="utf-8"?>
    <!-- before the package -->
    <ecore:EPackage xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
        xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xmi:id="package" name="sample" nsURI="urn:test:metadata" nsPrefix="sample">
      <!-- before the class -->
      <eClassifiers xsi:type="ecore:EClass" xmi:id="owner" name="Owner">
        <!-- before the attribute -->
        <eStructuralFeatures xsi:type="ecore:EAttribute" xmi:id="label" name="label"
            eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
        <!-- inside the class after its features -->
      </eClassifiers>
      <!-- inside the package after its classifiers -->
    </ecore:EPackage>
    <!-- after the package -->
    """

    /// Checks declaration spelling, comment placement and explicit XML identifiers.
    @Test("Comments, encoding declaration and XML identifiers survive editing")
    func preservesMetadata() async throws {
        let resource = try await ResourceSet().loadEcoreResource(text: Self.document, uri: "memory:/metadata.ecore")
        var package = try #require(await resource.getRootObjects().first as? EPackage)
        var owner = try #require(package.getEClass("Owner"))
        owner.name = "Renamed"
        package.eClassifiers = [owner]
        let text = XMISerializer().serialize(package)
        #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<!-- before the package -->"))
        #expect(text.contains("xmi:id=\"package\""))
        #expect(text.contains("xmi:id=\"owner\""))
        #expect(text.contains("xmi:id=\"label\""))
        #expect(text.contains("  <!-- before the class -->\n  <eClassifiers"))
        #expect(text.contains("    <!-- before the attribute -->\n    <eStructuralFeatures"))
        #expect(text.contains("    <!-- inside the class after its features -->\n  </eClassifiers>"))
        #expect(text.contains("  <!-- inside the package after its classifiers -->\n</ecore:EPackage>"))
        #expect(text.hasSuffix("<!-- after the package -->\n"))
        let loaded = try await EPackage(text: text, uri: "memory:/metadata.ecore")
        #expect(loaded.getEClass("Renamed")?.eAttributes.first?.name == "label")
        #expect(XMISerializer().serialize(loaded) == text)
    }

    /// Checks that deleted elements do not donate comments to unrelated siblings.
    @Test("Comments attached to a deleted element are removed with it")
    func removesElementMetadata() async throws {
        var package = try await EPackage(text: Self.document, uri: "memory:/metadata.ecore")
        package.eClassifiers = []
        let text = XMISerializer().serialize(package)
        #expect(!text.contains("before the class"))
        #expect(!text.contains("xmi:id=\"owner\""))
        #expect(text.contains("inside the package after its classifiers"))
    }
    /// Checks trailing comments on otherwise empty named and generic elements.
    @Test("Empty elements retain their own child comments and generic identifiers")
    func emptyElementComments() async throws {
        let text = Self.document
            .replacingOccurrences(of: "EString\"/>", with: "EString\"><!-- attribute end --></eStructuralFeatures>")
            .replacingOccurrences(of: "<!-- inside the class after its features -->", with: """
            <eAnnotations source="urn:test:meta"><!-- entry before --><details xmi:id="entry" key="key" value="value"><!-- entry end --></details><!-- annotation end --></eAnnotations>
            <eOperations name="run"><!-- operation end --></eOperations>
            <eOperations name="typed"><eGenericType xmi:id="generic" eClassifier="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"><!-- generic end --></eGenericType></eOperations>
            <eTypeParameters name="T"><!-- parameter end --></eTypeParameters>
            <!-- inside the class after its features -->
            """)
        let package = try await EPackage(text: text, uri: "memory:/metadata.ecore")
        let written = XMISerializer().serialize(package)
        #expect(written.contains("<!-- attribute end -->"))
        #expect(written.contains("<!-- operation end -->"))
        #expect(written.contains("<!-- parameter end -->"))
        #expect(written.contains("<!-- generic end -->"))
        #expect(written.contains("<!-- entry before -->"))
        #expect(written.contains("<!-- entry end -->"))
        #expect(written.contains("xmi:id=\"entry\""))
        #expect(written.contains("<!-- annotation end -->"))
        #expect(written.contains("xmi:id=\"generic\""))
        let reloaded = try await EPackage(text: written, uri: "memory:/metadata.ecore")
        #expect(XMISerializer().serialize(reloaded) == written)
    }

    /// Checks comments within a multi-root wrapper independently of document comments.
    @Test("Multiple package roots retain wrapper comments and identifiers")
    func multipleRoots() async throws {
        let text = """
        <xmi:XMI xmlns:xmi="http://www.omg.org/XMI" xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore">
          <!-- first package --><ecore:EPackage xmi:id="first" name="first" nsURI="urn:test:first" nsPrefix="first"/>
          <!-- second package --><ecore:EPackage xmi:id="second" name="second" nsURI="urn:test:second" nsPrefix="second"/>
          <!-- wrapper end -->
        </xmi:XMI>
        """
        let resource = try await ResourceSet().loadEcoreResource(text: text, uri: "memory:/multiple.ecore")
        let packages = await resource.getRootObjects().compactMap { $0 as? EPackage }
        let written = XMISerializer().serialize(packages)
        #expect(written.contains("<!-- first package -->"))
        #expect(written.contains("<!-- second package -->"))
        #expect(written.contains("<!-- wrapper end -->\n</xmi:XMI>"))
        #expect(written.contains("xmi:id=\"first\""))
        #expect(written.contains("xmi:id=\"second\""))
        let loaded = try await ResourceSet().loadEcoreResource(text: written, uri: "memory:/multiple.ecore")
        #expect(XMISerializer().serialize(await loaded.getRootObjects().compactMap { $0 as? EPackage }) == written)
    }

    /// Checks source ordering remains stable across legacy and current Eclipse layouts.
    @Test("Reference and data type attribute ordering follows the source", arguments: [false, true])
    func attributeOrdering(legacy: Bool) async throws {
        let flags = legacy ? "resolveProxies=\"false\" containment=\"true\"" : "containment=\"true\" resolveProxies=\"false\""
        let typeFlags = legacy ? "serializable=\"false\" instanceTypeName=\"Sample\"" : "instanceTypeName=\"Sample\" serializable=\"false\""
        let text = """
        <ecore:EPackage xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" name="sample" nsURI="urn:test:sample" nsPrefix="sample">
          <eClassifiers xsi:type="ecore:EClass" name="Owner">
            <eStructuralFeatures xsi:type="ecore:EReference" name="items" eType="#//Owner" \(flags)/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EDataType" name="Value" \(typeFlags)/>
        </ecore:EPackage>
        """
        let package = try await EPackage(text: text, uri: "memory:/ordering.ecore")
        let written = XMISerializer().serialize(package)
        #expect(written.contains(flags))
        #expect(written.contains(typeFlags))
    }

}
