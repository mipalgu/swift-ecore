//
// EcoreBuiltInIdentityTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Ecore Built-In Identity Tests")
struct EcoreBuiltInIdentityTests {
    private static let ecore = "http://www.eclipse.org/emf/2002/Ecore"
    private static let platformEcore = "platform:/plugin/org.eclipse.emf.ecore/model/Ecore.ecore"

    private static func body(_ base: String) -> String {
        """
          <eClassifiers xsi:type="ecore:EClass" name="Uses"
              eSuperTypes="ecore:EClass \(base)#//EObject">
            <eOperations name="op" eType="ecore:EDataType \(base)#//EDate">
              <eParameters name="p" eType="ecore:EClass \(base)#//EAttribute"/>
            </eOperations>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="s" eType="ecore:EDataType \(base)#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="i" eType="ecore:EDataType \(base)#//EInt"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="b" eType="ecore:EDataType \(base)#//EBoolean"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="j" eType="ecore:EDataType \(base)#//EJavaObject"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="object" eType="ecore:EClass \(base)#//EObject"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="metaclass" eType="ecore:EClass \(base)#//EClass"/>
          </eClassifiers>
        """
    }

    private static let expectations: [(feature: String, name: String)] = [
        ("s", "EString"), ("i", "EInt"), ("b", "EBoolean"), ("j", "EJavaObject"),
        ("object", "EObject"), ("metaclass", "EClass"),
    ]

    /// The identifier of a classifier of the Ecore package, as the package itself lists it.
    private func instanceID(_ name: String) throws -> EUUID {
        try #require(EcorePackage.instance.eClassifiers.first { $0.name == name }).id
    }

    @Test("the reflective package lists the same classifiers that the registry hands out")
    func packageAgreesWithRegistry() throws {
        for name in ["EString", "EInt", "EBoolean", "EObject", "EClass", "EDate"] {
            let fromRegistry = try #require(EcorePackage.classifier(named: name))
            #expect(fromRegistry.id == (try instanceID(name)))
        }
    }

    @Test("built-ins named by namespace or platform URI load as the classifiers of the Ecore package",
        arguments: [ecore, platformEcore])
    func nativeIdentity(base: String) async throws {
        let url = try FidelityFixtures.writeDocument(Self.body(base))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let package = try await EPackage(url: url)
        let uses = try #require(package.getEClass("Uses"))
        for (feature, name) in Self.expectations {
            let expected = try instanceID(name)
            let type: any EClassifier
            if let attribute = uses.attribute(feature) {
                type = attribute.eType
            } else {
                type = try #require(uses.reference(feature)).eType
            }
            #expect(type.id == expected, "\(feature) is \(name)")
            #expect(type.name == name)
        }
        let supertype = try #require(uses.eSuperTypes.first)
        #expect(supertype.id == (try instanceID("EObject")))
        let operation = try #require(uses.eOperations.first)
        #expect(operation.eType?.id == (try instanceID("EDate")))
        #expect(operation.eParameters.first?.eType?.id == (try instanceID("EAttribute")))
        #expect(EcorePackage.isMetaClass(supertype))
    }

    @Test("a built-in can be recognised by identity after loading")
    func recognisedByIdentity() async throws {
        let url = try FidelityFixtures.writeDocument(Self.body(Self.ecore))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let uses = try #require(try await EPackage(url: url).getEClass("Uses"))
        let string = try #require(uses.attribute("s")).eType
        #expect(string.id == EcorePackage.dataType(.eString)?.id)
        #expect(string.id != (try #require(uses.attribute("i")).eType).id)
        #expect(string.id == (try instanceID("EString")))
    }

    @Test("two separate loads agree on the identifiers of built-ins")
    func stableAcrossLoads() async throws {
        let url = try FidelityFixtures.writeDocument(Self.body(Self.ecore))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = try #require(try await EPackage(url: url).getEClass("Uses")?.attribute("s")).eType
        let second = try #require(try await EPackage(url: url).getEClass("Uses")?.attribute("s")).eType
        #expect(first.id == second.id)
    }

    @Test("the dynamic loader stores the identifiers of the Ecore package's classifiers",
        arguments: [ecore, platformEcore])
    func dynamicIdentity(base: String) async throws {
        let url = try FidelityFixtures.writeDocument(Self.body(base))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let resource = try await XMIParser().parse(url)
        let navigator = FragmentNavigator(resource: resource)
        for (feature, name) in Self.expectations {
            let object = try #require(await navigator.resolve("//Uses/\(feature)") as? DynamicEObject)
            let identifier = try #require(object.eGet("eType") as? EUUID)
            #expect(identifier == (try instanceID(name)), "\(feature) is \(name)")
            let resolved = try #require(await resource.resolve(identifier) as? any EClassifier)
            #expect(resolved.name == name)
            #expect(resolved.id == identifier)
        }
        let uses = try #require(await navigator.resolve("//Uses") as? DynamicEObject)
        #expect(uses.eGet("eSuperTypes") as? [EUUID] == [try instanceID("EObject")])
    }

    @Test("a name that Ecore does not define is a data type of the document, not a built-in")
    func unknownName() async throws {
        let url = try FidelityFixtures.writeDocument(
            """
              <eClassifiers xsi:type="ecore:EClass" name="Uses">
                <eStructuralFeatures xsi:type="ecore:EAttribute" name="x"
                    eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EUnheardOf"/>
              </eClassifiers>
            """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let resource = try await XMIParser().parse(url)
        let attribute = try #require(
            await FragmentNavigator(resource: resource).resolve("//Uses/x") as? DynamicEObject)
        let identifier = try #require(attribute.eGet("eType") as? EUUID)
        #expect(EcorePackage.classifier(id: identifier) == nil)
        let stand = try #require(await resource.resolve(identifier) as? DynamicEObject)
        #expect(stand.eGet("name") as? String == "EUnheardOf")
    }

    @Test("references name the Ecore package by namespace or platform location only")
    func referenceRecognition() {
        #expect(EcoreURI.isEcoreMetamodelReference("http://www.eclipse.org/emf/2002/Ecore#//EString"))
        #expect(EcoreURI.isEcoreMetamodelReference("ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EInt"))
        #expect(EcoreURI.isEcoreMetamodelReference(
            "platform:/plugin/org.eclipse.emf.ecore/model/Ecore.ecore#//EString"))
        #expect(!EcoreURI.isEcoreMetamodelReference("#//EString"))
        #expect(!EcoreURI.isEcoreMetamodelReference("http://www.eclipse.org/emf/2002/Ecore"))
        #expect(!EcoreURI.isEcoreMetamodelReference("other/Ecore.ecore#//EString"))
        #expect(!EcoreURI.isEcoreMetamodelReference("file:/x/org.eclipse.emf.ecore/model/Ecore.ecore#//EString"))
        #expect(!EcoreURI.isEcoreMetamodelReference("http://www.eclipse.org/emf/2002/Ecore#EString"))
        #expect(!EcoreURI.isEcoreMetamodelReference("ecore:EClass "))
    }

    @Test("a reference that merely ends in Ecore.ecore is not taken for the Ecore package")
    func lookalike() async throws {
        let url = try FidelityFixtures.writeDocument(
            """
              <eClassifiers xsi:type="ecore:EClass" name="Uses">
                <eStructuralFeatures xsi:type="ecore:EAttribute" name="x"
                    eType="ecore:EDataType other/MyEcore.ecore#//EString"/>
              </eClassifiers>
            """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let resource = try await XMIParser().parse(url)
        let attribute = try #require(
            await FragmentNavigator(resource: resource).resolve("//Uses/x") as? DynamicEObject)
        #expect(attribute.eGet("eType") is ResourceProxy)
    }
}
