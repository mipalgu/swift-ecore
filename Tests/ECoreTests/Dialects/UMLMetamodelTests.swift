import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that the bundled Eclipse UML2 metamodel loads with its own data types.
@Suite("Bundled UML metamodel")
struct UMLMetamodelTests {
    @Test("The metamodel loads with its classes and primitive types")
    func loads() async throws {
        let (uml, types) = try await UMLMetamodel.packages()
        #expect(uml.nsURI == UMLNamespaces.uml)
        #expect(types.nsURI == UMLNamespaces.types)
        let umlClass = try #require(uml.getEClass("Class"))
        let isAbstract = try #require(umlClass.allAttributes.first { $0.name == "isAbstract" })
        #expect(isAbstract.eType.name == "Boolean")
        let element = try #require(uml.getEClass("Element"))
        #expect(element.allReferences.contains { $0.name == "eAnnotations" })
        #expect(uml.eClassifiers.count > 200)
    }
}
