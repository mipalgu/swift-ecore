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
}
