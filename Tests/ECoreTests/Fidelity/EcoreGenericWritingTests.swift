import EMFBase
import Foundation
import Testing

@testable import ECore

/// Self-authored documents exercising generic metamodel interchange.
enum GenericWritingFixtures {
    /// The URI used to resolve references in the fixture.
    static let uri = "memory:/generic.ecore"

    /// A package with classifier, operation and feature generics and reference keys.
    static let document = """
    <?xml version="1.0" encoding="UTF-8"?>
    <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
        name="generic" nsURI="urn:test:generic" nsPrefix="generic">
      <eClassifiers xsi:type="ecore:EClass" name="Box" instanceTypeName="example.Box">
        <eTypeParameters name="T">
          <eBounds eClassifier="ecore:EClass http://www.eclipse.org/emf/2002/Ecore#//EObject"/>
        </eTypeParameters>
        <eOperations name="convert">
          <eTypeParameters name="R"/>
          <eGenericType eTypeParameter="#//Box/convert/R"/>
          <eParameters name="input">
            <eGenericType eTypeParameter="#//Box/T"/>
          </eParameters>
          <eGenericExceptions eClassifier="#//Failure">
            <eTypeArguments eTypeParameter="#//Box/T"/>
          </eGenericExceptions>
        </eOperations>
        <eStructuralFeatures xsi:type="ecore:EReference" name="value">
          <eGenericType eTypeParameter="#//Box/T"/>
        </eStructuralFeatures>
        <eStructuralFeatures xsi:type="ecore:EReference" name="items" upperBound="-1"
            eType="#//Item" resolveProxies="false" containment="true" eKeys="#//Item/key"/>
      </eClassifiers>
      <eClassifiers xsi:type="ecore:EClass" name="Child">
        <eGenericSuperTypes eClassifier="#//Box">
          <eTypeArguments eClassifier="#//Item"/>
        </eGenericSuperTypes>
      </eClassifiers>
      <eClassifiers xsi:type="ecore:EClass" name="Item">
        <eStructuralFeatures xsi:type="ecore:EAttribute" name="key"
            eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
      </eClassifiers>
      <eClassifiers xsi:type="ecore:EClass" name="Failure">
        <eTypeParameters name="E"/>
      </eClassifiers>
      <eClassifiers xsi:type="ecore:EDataType" name="Sequence" instanceClassName="example.Sequence"
          serializable="false" instanceTypeName="example.Sequence&lt;T&gt;">
        <eTypeParameters name="T"/>
      </eClassifiers>
      <eClassifiers xsi:type="ecore:EEnum" name="Kind" instanceClassName="example.Kind"
          serializable="false" instanceTypeName="example.Kind">
        <eLiterals name="One"/>
      </eClassifiers>
    </ecore:EPackage>
    """
}

/// Verifies that native serialisation retains generic declarations and references.
@Suite("Generic metamodel writing")
struct EcoreGenericWritingTests {
    /// Checks every supported generic containment feature in a load-save-load cycle.
    @Test("Generic declarations and reference keys survive native writing")
    func genericRoundTrip() async throws {
        let package = try await EPackage(text: GenericWritingFixtures.document, uri: GenericWritingFixtures.uri)
        let text = XMISerializer().serialize(package)
        #expect(text.contains("<eTypeParameters name=\"T\">"))
        #expect(text.contains("<eBounds eClassifier="))
        #expect(text.contains("<eGenericType eTypeParameter=\"#//Box/convert/R\"/>"))
        #expect(text.contains("<eGenericType eTypeParameter=\"#//Box/T\"/>"))
        #expect(text.contains("<eGenericExceptions eClassifier=\"#//Failure\">"))
        #expect(text.contains("<eGenericSuperTypes eClassifier=\"#//Box\">"))
        #expect(text.contains("eKeys=\"#//Item/key\""))
        #expect(text.contains("instanceTypeName=\"example.Sequence&lt;T>\""))
        #expect(text.contains("name=\"Kind\" instanceClassName=\"example.Kind\" serializable=\"false\" instanceTypeName=\"example.Kind\""))
        let reloaded = try await EPackage(text: text, uri: GenericWritingFixtures.uri)
        let box = try #require(reloaded.getEClass("Box"))
        #expect(box.eTypeParameters.map(\.name) == ["T"])
        #expect(box.eTypeParameters.first?.eBounds.first?.eClassifier?.name == "EObject")
        #expect(box.eOperations.first?.eTypeParameters.map(\.name) == ["R"])
        #expect(box.eOperations.first?.eGenericExceptions.first?.eTypeArguments.count == 1)
        #expect(box.eReferences.first?.eGenericType?.eTypeParameter == box.eTypeParameters.first?.id)
        #expect(box.eReferences.last?.eKeys.count == 1)
        #expect(reloaded.getEClass("Child")?.eGenericSuperTypes.first?.eTypeArguments.first?.eClassifier?.name == "Item")
        #expect(XMISerializer().serialize(reloaded) == text)
    }

    /// Checks nested wildcard bounds and their reference spelling.
    @Test("Wildcard upper and lower bounds are written recursively")
    func wildcardBounds() async throws {
        let sequence = EDataType(name: "Sequence", instanceClassName: "example.Sequence")
        var item = EClass(name: "Item")
        var feature = EAttribute(name: "values", eType: sequence)
        feature.eGenericType = EGenericType(eClassifier: sequence, eTypeArguments: [
            EGenericType(eUpperBound: EGenericType(eClassifier: EcorePackage.dataType(.eString))),
            EGenericType(eLowerBound: EGenericType(eClassifier: EcorePackage.dataType(.eInt))),
        ])
        item.eStructuralFeatures = [feature]
        let package = EPackage(name: "bounds", nsURI: "urn:test:bounds", nsPrefix: "bounds", eClassifiers: [sequence, item])
        let text = XMISerializer().serialize(package)
        #expect(text.contains("<eUpperBound eClassifier="))
        #expect(text.contains("<eLowerBound eClassifier="))
        let loaded = try await EPackage(text: text, uri: GenericWritingFixtures.uri)
        let arguments = try #require(loaded.getEClass("Item")?.eAttributes.first?.eGenericType?.eTypeArguments)
        #expect(arguments.count == 2)
        #expect(arguments.first?.eUpperBound?.eClassifier?.name == "EString")
        #expect(arguments.last?.eLowerBound?.eClassifier?.name == "EInt")
    }

    /// Checks the order used by older EMF resources for reference attributes.
    @Test("Proxy resolution precedes containment in reference attributes")
    func referenceAttributeOrder() async throws {
        let package = try await EPackage(text: GenericWritingFixtures.document, uri: GenericWritingFixtures.uri)
        let text = XMISerializer().serialize(package)
        #expect(text.contains("resolveProxies=\"false\" containment=\"true\""))
    }
}
