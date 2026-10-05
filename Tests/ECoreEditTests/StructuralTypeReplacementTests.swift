import ECore
import EMFBase
import Testing

@testable import ECoreEdit

/// Verifies replacing mandatory structural types through the editing domain.
@MainActor
@Suite("Structural type replacement")
struct StructuralTypeReplacementTests {
    /// Checks attribute and reference replacements with shared undo and redo.
    @Test("Existing classifier references can be replaced and undone")
    func replacesTypes() throws {
        let fixture = Fixture()
        let domain = MetamodelEditingDomain(document: fixture.document)
        let attributeID = fixture.id("label", in: "Item")
        let referenceID = fixture.id("items", in: "Owner")
        let newClassID = fixture.id("Special")
        let before = domain.document
        let integer = try #require(EcorePackage.dataType(.eInt))
        let attributeChange = try domain.perform(.set(attributeID, .eType, integer.id))
        #expect(attributeChange.modified[attributeID]?.contains(.eType) == true)
        guard case .attribute(let attribute)? = domain.document.index.element(attributeID) else {
            Issue.record("Attribute is missing after its type changed")
            return
        }
        #expect(attribute.eType.id == integer.id)
        let referenceChange = try domain.perform(.set(referenceID, .eType, newClassID))
        #expect(referenceChange.modified[referenceID]?.contains(.eType) == true)
        guard case .reference(let reference)? = domain.document.index.element(referenceID) else {
            Issue.record("Reference is missing after its type changed")
            return
        }
        #expect(reference.eType.id == newClassID)
        #expect(reference.eType.name == "Special")
        let after = domain.document
        domain.undo()
        domain.undo()
        #expect(domain.document == before)
        domain.redo()
        domain.redo()
        #expect(domain.document == after)
    }
    /// Checks retained proxies are replaced with explicit editor choices and restored by undo.
    @Test("Changing retained references replaces their saved proxy spelling")
    func replacesRetainedReferences() async throws {
        let text = """
        <ecore:EPackage xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" name="sample" nsURI="urn:test:sample" nsPrefix="sample">
          <eClassifiers xsi:type="ecore:EClass" name="Owner" eSuperTypes="absent.ecore#//Base">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="label" eType="absent.ecore#//Type"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="items" eType="#//Owner"
              eOpposite="absent.ecore#//Other/owner"/>
          </eClassifiers>
        </ecore:EPackage>
        """
        let resource = try await ResourceSet().loadEcoreResource(text: text, uri: "memory:/sample.ecore",
            options: EcoreLoadOptions(unresolvedReferences: .keepAsProxies))
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        let owner = try #require(package.getEClass("Owner"))
        let attribute = try #require(owner.eAttributes.first)
        let reference = try #require(owner.eReferences.first)
        let domain = MetamodelEditingDomain(document: MetamodelDocument(roots: [package]))
        let before = XMISerializer().serialize(package)
        let integer = try #require(EcorePackage.dataType(.eInt))
        try domain.perform(.compound(label: "Replace retained references", [
            .set(attribute.id, .eType, integer.id), .set(owner.id, .eSuperTypes, [EUUID]()),
            .set(reference.id, .eOpposite, nil),
        ]))
        let after = XMISerializer().serialize(domain.document.roots[0])
        #expect(!after.contains("absent.ecore"))
        #expect(after.contains("#//EInt"))
        domain.undo()
        #expect(XMISerializer().serialize(domain.document.roots[0]) == before)
        domain.redo()
        #expect(XMISerializer().serialize(domain.document.roots[0]) == after)
    }

}
