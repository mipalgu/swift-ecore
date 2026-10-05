import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies opt-in tolerant loading and multi-package resources.
@Suite("Ecore load options")
struct EcoreLoadOptionsTests {
    /// An incomplete package containing unnamed model elements.
    private static let incomplete = """
    <ecore:EPackage xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <eClassifiers xsi:type="ecore:EClass">
        <eStructuralFeatures xsi:type="ecore:EAttribute"/>
      </eClassifiers>
    </ecore:EPackage>
    """

    /// Checks that tolerant mode retains editable objects and reports omissions.
    @Test("Tolerant loading retains incomplete model elements with diagnostics")
    func tolerantLoading() async throws {
        let resource = try await ResourceSet().loadEcoreResource(
            text: Self.incomplete, uri: "memory:/incomplete.ecore", options: EcoreLoadOptions(tolerant: true))
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        #expect(package.name.isEmpty)
        #expect(package.nsURI.isEmpty)
        #expect(package.nsPrefix.isEmpty)
        #expect(package.eClassifiers.count == 1)
        #expect(package.getEClass("")?.eAttributes.count == 1)
        let diagnostics = await resource.loadDiagnostics
        #expect(diagnostics.count == 5)
        #expect(diagnostics.filter { $0.code == EcoreLoadDiagnostic.missingElementName }.count == 2)
        #expect(Set(diagnostics.map(\.code)) == Set([
            EcoreLoadDiagnostic.missingPackageName, EcoreLoadDiagnostic.missingNamespaceURI,
            EcoreLoadDiagnostic.missingNamespacePrefix, EcoreLoadDiagnostic.missingElementName,
        ]))
        #expect(diagnostics.allSatisfy { $0.document == resource.uri && $0.severity == .error })
    }

    /// Checks that the established strict default remains unchanged.
    @Test("Strict loading continues to reject an incomplete package")
    func strictLoading() async {
        await #expect(throws: XMIError.self) {
            _ = try await ResourceSet().loadEcoreResource(text: Self.incomplete, uri: "memory:/strict.ecore")
        }
    }

    /// Checks the URI overload and preservation of unresolved types.
    @Test("URI loading accepts proxy-preserving options")
    func proxyOptions() async throws {
        let text = """
        <ecore:EPackage xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            name="sample" nsURI="urn:test:sample" nsPrefix="sample">
          <eClassifiers xsi:type="ecore:EClass" name="Owner">
            <eStructuralFeatures xsi:type="ecore:EReference" name="target"
                eType="ecore:EClass absent.ecore#//Missing"/>
          </eClassifiers>
        </ecore:EPackage>
        """
        let uri = "memory:/proxy.ecore"
        let set = ResourceSet()
        await set.setURIHandlers([InMemoryURIHandler(texts: [uri: text])])
        let resource = try await set.loadEcoreResource(uri: uri, options: EcoreLoadOptions(unresolvedReferences: .keepAsProxies))
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        #expect(package.getEClass("Owner")?.eReferences.first?.eType.name == "Missing")
        #expect(XMISerializer().serialize(package).contains("absent.ecore#//Missing"))
    }

    /// Checks the root order, cross-root references and native resource writer.
    @Test("All root packages and their references survive native resource writing")
    func multipleRoots() async throws {
        let text = """
        <xmi:XMI xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore">
          <ecore:EPackage name="first" nsURI="urn:test:first" nsPrefix="first">
            <eClassifiers xsi:type="ecore:EClass" name="Owner">
              <eStructuralFeatures xsi:type="ecore:EReference" name="target" eType="#/1/Target"/>
            </eClassifiers>
          </ecore:EPackage>
          <ecore:EPackage name="second" nsURI="urn:test:second" nsPrefix="second">
            <eClassifiers xsi:type="ecore:EClass" name="Target"/>
          </ecore:EPackage>
        </xmi:XMI>
        """
        let resource = try await ResourceSet().loadEcoreResource(text: text, uri: "memory:/roots.ecore")
        let packages = await resource.getRootObjects().compactMap { $0 as? EPackage }
        #expect(packages.map(\.name) == ["first", "second"])
        #expect(packages.first?.getEClass("Owner")?.eReferences.first?.eType.id == packages.last?.getEClass("Target")?.id)
        let written = XMISerializer(options: .emf).serialize(packages)
        #expect(written.contains("<xmi:XMI"))
        let loaded = try await ResourceSet().loadEcoreResource(text: written, uri: "memory:/roots.ecore")
        #expect(await loaded.getRootObjects().compactMap { ($0 as? EPackage)?.name } == ["first", "second"])
        let loadedPackages = await loaded.getRootObjects().compactMap { $0 as? EPackage }
        #expect(XMISerializer(options: .emf).serialize(loadedPackages) == written)
    }
}
