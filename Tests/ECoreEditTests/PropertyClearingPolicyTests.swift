import ECore
import EMFBase
import Testing

@testable import ECoreEdit

/// Verifies the editing policy exposed to property pickers.
@Suite("Property clearing policy")
struct PropertyClearingPolicyTests {
    /// Checks that picker capabilities agree with accepted reference edits.
    @Test("Only optional single-valued references offer clearing")
    func optionalReferences() {
        let fixture = Fixture()
        let document = fixture.document
        #expect(!document.allowsClearing(.eType, for: fixture.id("label", in: "Item")))
        #expect(!document.allowsClearing(.eType, for: fixture.id("items", in: "Owner")))
        #expect(document.allowsClearing(.eType, for: fixture.id("check")))
        #expect(document.allowsClearing(.eType, for: fixture.id("level")))
        #expect(document.allowsClearing(.eOpposite, for: fixture.id("items", in: "Owner")))
        #expect(!document.allowsClearing(.eOpposite, for: fixture.id("label", in: "Item")))
        #expect(!document.allowsClearing(.name, for: fixture.id("Item")))
        #expect(!document.allowsClearing(.eSuperTypes, for: fixture.id("Item")))
        #expect(!document.allowsClearing(.eType, for: EUUID()))
    }
}
