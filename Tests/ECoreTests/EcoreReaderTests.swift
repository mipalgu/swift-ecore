//
// EcoreReaderTests.swift
// ECore
//
//  Created by Rene Hexel on 16/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing
@testable import ECore
import Foundation

/// Test suite for EPackage initialization from .ecore files.
///
/// Verifies that EPackage can properly initialize itself from XMI-parsed .ecore files,
/// converting DynamicEObject representations into fully-formed EPackage structs with
/// all their classifiers and features.
@Suite("EPackage Initialization Tests")
struct EcoreReaderTests {

    // MARK: - Simple Package Reading

    @Test("Read simple EPackage from .ecore file")
    func testReadSimplePackage() async throws {
        // Given - create a test .ecore file
        let tempDir = FileManager.default.temporaryDirectory
        let ecoreFile = tempDir.appendingPathComponent("TestPackage-\(UUID().uuidString).ecore")

        let ecoreContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
            name="TestPackage" nsURI="http://test.example.org/package" nsPrefix="test">
        </ecore:EPackage>
        """

        try ecoreContent.write(to: ecoreFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: ecoreFile) }

        // When - read the package
        let package = try await EPackage(url: ecoreFile)

        // Then - verify package attributes
        #expect(package.name == "TestPackage")
        #expect(package.nsURI == "http://test.example.org/package")
        #expect(package.nsPrefix == "test")
        #expect(package.eClassifiers.isEmpty)
        #expect(package.eSubpackages.isEmpty)
    }

    // MARK: - EClass Extraction

    @Test("Read EPackage with EClass")
    func testReadPackageWithEClass() async throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory
        let ecoreFile = tempDir.appendingPathComponent("ClassPackage-\(UUID().uuidString).ecore")

        let ecoreContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
            name="TestPackage" nsURI="http://test" nsPrefix="test">
          <eClassifiers xsi:type="ecore:EClass" name="Person"/>
          <eClassifiers xsi:type="ecore:EClass" name="Company" abstract="true"/>
        </ecore:EPackage>
        """

        try ecoreContent.write(to: ecoreFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: ecoreFile) }

        // When
        let package = try await EPackage(url: ecoreFile)

        // Then
        #expect(package.eClassifiers.count == 2)

        let personClass = package.getEClass("Person")
        #expect(personClass != nil)
        #expect(personClass?.name == "Person")
        #expect(personClass?.isAbstract == false)
        #expect(personClass?.isInterface == false)

        let companyClass = package.getEClass("Company")
        #expect(companyClass != nil)
        #expect(companyClass?.name == "Company")
        #expect(companyClass?.isAbstract == true)
    }

    // MARK: - EAttribute Extraction

    @Test("Read EClass with EAttributes")
    func testReadClassWithAttributes() async throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory
        let ecoreFile = tempDir.appendingPathComponent("AttributePackage-\(UUID().uuidString).ecore")

        let ecoreContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
            name="TestPackage" nsURI="http://test" nsPrefix="test">
          <eClassifiers xsi:type="ecore:EClass" name="Person">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="name"
                eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="age"
                eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EInt"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="id"
                eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"
                iD="true" lowerBound="1"/>
          </eClassifiers>
        </ecore:EPackage>
        """

        try ecoreContent.write(to: ecoreFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: ecoreFile) }

        // When
        let package = try await EPackage(url: ecoreFile)

        // Then
        let personClass = package.getEClass("Person")
        #expect(personClass != nil)
        #expect(personClass?.eStructuralFeatures.count == 3)

        // Check name attribute
        let nameAttr = personClass?.getStructuralFeature(name: "name") as? EAttribute
        #expect(nameAttr != nil)
        #expect(nameAttr?.name == "name")
        #expect(nameAttr?.eType.name == "EString")
        #expect(nameAttr?.lowerBound == 0)
        #expect(nameAttr?.upperBound == 1)
        #expect(nameAttr?.isID == false)

        // Check age attribute
        let ageAttr = personClass?.getStructuralFeature(name: "age") as? EAttribute
        #expect(ageAttr != nil)
        #expect(ageAttr?.eType.name == "EInt")

        // Check id attribute
        let idAttr = personClass?.getStructuralFeature(name: "id") as? EAttribute
        #expect(idAttr != nil)
        #expect(idAttr?.isID == true)
        #expect(idAttr?.lowerBound == 1)
    }

    // MARK: - EReference Extraction

    @Test("Read EClass with EReferences")
    func testReadClassWithReferences() async throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory
        let ecoreFile = tempDir.appendingPathComponent("ReferencePackage-\(UUID().uuidString).ecore")

        let ecoreContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
            name="TestPackage" nsURI="http://test" nsPrefix="test">
          <eClassifiers xsi:type="ecore:EClass" name="Company">
            <eStructuralFeatures xsi:type="ecore:EReference" name="employees"
                eType="#//Person" upperBound="-1" containment="true"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="ceo"
                eType="#//Person" lowerBound="1"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Person"/>
        </ecore:EPackage>
        """

        try ecoreContent.write(to: ecoreFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: ecoreFile) }

        // When
        let package = try await EPackage(url: ecoreFile)

        // Then
        let companyClass = package.getEClass("Company")
        #expect(companyClass != nil)
        #expect(companyClass?.eStructuralFeatures.count == 2)

        // Check employees reference
        let employeesRef = companyClass?.getStructuralFeature(name: "employees") as? EReference
        #expect(employeesRef != nil)
        #expect(employeesRef?.name == "employees")
        #expect(employeesRef?.eType.name == "Person")
        #expect(employeesRef?.upperBound == -1)
        #expect(employeesRef?.containment == true)
        #expect(employeesRef?.lowerBound == 0)

        // Check ceo reference
        let ceoRef = companyClass?.getStructuralFeature(name: "ceo") as? EReference
        #expect(ceoRef != nil)
        #expect(ceoRef?.eType.name == "Person")
        #expect(ceoRef?.lowerBound == 1)
        #expect(ceoRef?.containment == false)
    }

    // MARK: - EEnum Extraction

    @Test("Read EPackage with EEnum")
    func testReadPackageWithEnum() async throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory
        let ecoreFile = tempDir.appendingPathComponent("EnumPackage-\(UUID().uuidString).ecore")

        let ecoreContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
            name="TestPackage" nsURI="http://test" nsPrefix="test">
          <eClassifiers xsi:type="ecore:EEnum" name="Color">
            <eLiterals name="red" value="0"/>
            <eLiterals name="green" value="1"/>
            <eLiterals name="blue" value="2"/>
          </eClassifiers>
        </ecore:EPackage>
        """

        try ecoreContent.write(to: ecoreFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: ecoreFile) }

        // When
        let package = try await EPackage(url: ecoreFile)

        // Then
        let colorEnum = package.getEEnum("Color")
        #expect(colorEnum != nil)
        #expect(colorEnum?.name == "Color")
        #expect(colorEnum?.literals.count == 3)

        let redLiteral = colorEnum?.getLiteral(name: "red")
        #expect(redLiteral != nil)
        #expect(redLiteral?.value == 0)

        let greenLiteral = colorEnum?.getLiteral(name: "green")
        #expect(greenLiteral != nil)
        #expect(greenLiteral?.value == 1)

        let blueLiteral = colorEnum?.getLiteral(name: "blue")
        #expect(blueLiteral != nil)
        #expect(blueLiteral?.value == 2)
    }

    // MARK: - EDataType Extraction

    @Test("Read EPackage with custom EDataType")
    func testReadPackageWithDataType() async throws {
        // Given
        let tempDir = FileManager.default.temporaryDirectory
        let ecoreFile = tempDir.appendingPathComponent("DataTypePackage-\(UUID().uuidString).ecore")

        let ecoreContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
            name="TestPackage" nsURI="http://test" nsPrefix="test">
          <eClassifiers xsi:type="ecore:EDataType" name="URI"
              instanceClassName="java.net.URI" serializable="true"/>
        </ecore:EPackage>
        """

        try ecoreContent.write(to: ecoreFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: ecoreFile) }

        // When
        let package = try await EPackage(url: ecoreFile)

        // Then
        let uriDataType = package.getEDataType("URI")
        #expect(uriDataType != nil)
        #expect(uriDataType?.name == "URI")
        #expect(uriDataType?.instanceClassName == "java.net.URI")
        #expect(uriDataType?.serialisable == true)
    }

    // MARK: - Complex Package

    @Test("Read complex EPackage with mixed classifiers")
    func testReadComplexPackage() async throws {
        // Given - a package with classes, enums, and datatypes
        let tempDir = FileManager.default.temporaryDirectory
        let ecoreFile = tempDir.appendingPathComponent("ComplexPackage-\(UUID().uuidString).ecore")

        let ecoreContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
            name="ComplexPackage" nsURI="http://complex.example.org" nsPrefix="complex">
          <eClassifiers xsi:type="ecore:EClass" name="Person">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="name"
                eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="status"
                eType="#//Status"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EEnum" name="Status">
            <eLiterals name="active" value="0"/>
            <eLiterals name="inactive" value="1"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EDataType" name="Email"
              instanceClassName="Swift.String"/>
        </ecore:EPackage>
        """

        try ecoreContent.write(to: ecoreFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: ecoreFile) }

        // When
        let package = try await EPackage(url: ecoreFile)

        // Then
        #expect(package.name == "ComplexPackage")
        #expect(package.eClassifiers.count == 3)

        // Verify EClass
        let personClass = package.getEClass("Person")
        #expect(personClass != nil)
        #expect(personClass?.eStructuralFeatures.count == 2)

        // Verify EEnum
        let statusEnum = package.getEEnum("Status")
        #expect(statusEnum != nil)
        #expect(statusEnum?.literals.count == 2)

        // Verify EDataType
        let emailType = package.getEDataType("Email")
        #expect(emailType != nil)
        #expect(emailType?.instanceClassName == "Swift.String")
    }

    // MARK: - Error Handling

    @Test("Handle non-existent file")
    func testReadNonExistentFile() async {
        // Given
        let nonExistentFile = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).ecore")

        // When/Then
        await #expect(throws: Error.self) {
            _ = try await EPackage(url: nonExistentFile)
        }
    }

    @Test("Handle empty package name")
    func testHandleMissingPackageName() async throws {
        // Given - .ecore file without name attribute
        let tempDir = FileManager.default.temporaryDirectory
        let ecoreFile = tempDir.appendingPathComponent("Invalid-\(UUID().uuidString).ecore")

        let ecoreContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
            nsURI="http://test" nsPrefix="test">
        </ecore:EPackage>
        """

        try ecoreContent.write(to: ecoreFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: ecoreFile) }

        // When/Then
        await #expect(throws: XMIError.self) {
            _ = try await EPackage(url: ecoreFile)
        }
    }
}
