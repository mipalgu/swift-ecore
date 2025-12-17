import Foundation
//
// XMIParserTests.swift
// ECoreTests
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing

@testable import ECore

/// Test suite for XMI parsing functionality
///
/// This test suite validates XMI (XML Metadata Interchange) parsing with:
/// - Metamodel (.ecore) file parsing
/// - Model instance (.xmi) file parsing
/// - Cross-resource references
/// - Round-trip serialisation
@Suite("XMI Parser Tests")
struct XMIParserTests {

    // MARK: - Helper Methods

    /// Get the URL for the test resources directory
    ///
    /// This helper locates the Resources directory within the test bundle,
    /// handling different build configurations appropriately.
    ///
    /// - Returns: URL pointing to the Resources directory
    /// - Throws: TestError.resourcesNotFound if the resources directory cannot be located
    private func getResourcesURL() throws -> URL {
        guard let bundleResourcesURL = Bundle.module.resourceURL else {
            throw TestError.resourcesNotFound
        }

        let fm = FileManager.default
        let testResourcesURL = bundleResourcesURL.appendingPathComponent("Resources")
        var isDirectory = ObjCBool(false)

        if fm.fileExists(atPath: testResourcesURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        {
            return testResourcesURL
        } else {
            return bundleResourcesURL
        }
    }

    /// Test-specific errors
    private enum TestError: Error {
        case resourcesNotFound
        case fileNotFound(String)
    }

    // MARK: - Basic Parsing Tests

    /// Test parsing a minimal XMI document
    @Test("Parse minimal XMI structure")
    func testParseMinimalXMI() async throws {
        let xmi = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ecore:EPackage
                xmi:version="2.0"
                xmlns:xmi="http://www.omg.org/XMI"
                xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
                name="test"
                nsURI="http://test"
                nsPrefix="test">
            </ecore:EPackage>
            """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".ecore")
        try xmi.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parser = XMIParser()
        let resource = try await parser.parse(tempURL)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)
    }

    // MARK: - Metamodel Parsing Tests

    /// Test parsing a simple empty package
    ///
    /// This test validates:
    /// - Basic EPackage parsing
    /// - Namespace attributes (name, nsURI, nsPrefix)
    @Test("Parse simple.ecore metamodel")
    func testParseSimpleEcore() async throws {
        let resourcesURL = try getResourcesURL()
        let url = resourcesURL.appendingPathComponent("xmi").appendingPathComponent("simple.ecore")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestError.fileNotFound("simple.ecore")
        }

        let parser = XMIParser()
        let resource = try await parser.parse(url)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        // Verify package attributes
        let pkg = roots[0] as? DynamicEObject
        #expect(pkg != nil)

        let pkgName = await resource.eGet(objectId: pkg!.id, feature: "name") as? String
        #expect(pkgName == "simple")

        let nsURI = await resource.eGet(objectId: pkg!.id, feature: "nsURI") as? String
        #expect(nsURI == "http://swift-modelling.org/test/simple")

        let nsPrefix = await resource.eGet(objectId: pkg!.id, feature: "nsPrefix") as? String
        #expect(nsPrefix == "simple")
    }

    /// Test parsing animals.ecore with enumerations
    ///
    /// This test validates:
    /// - EPackage parsing with namespace attributes
    /// - EEnum parsing with literals
    /// - EClass parsing with attributes
    /// - Default value literals
    /// - Reference to enum types
    @Test("Parse animals.ecore metamodel with enumerations")
    func testParseAnimalsEcore() async throws {
        let resourcesURL = try getResourcesURL()
        let url = resourcesURL.appendingPathComponent("xmi").appendingPathComponent("animals.ecore")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestError.fileNotFound("animals.ecore")
        }

        let parser = XMIParser()
        let resource = try await parser.parse(url)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        // Verify package attributes
        let pkg = roots[0] as? DynamicEObject
        #expect(pkg != nil)

        let pkgName = await resource.eGet(objectId: pkg!.id, feature: "name") as? String
        #expect(pkgName == "animals")

        let nsURI = await resource.eGet(objectId: pkg!.id, feature: "nsURI") as? String
        #expect(nsURI == "http://swift-modelling.org/test/animals")

        // Verify classifiers were parsed
        let classifiers =
            await resource.eGet(objectId: pkg!.id, feature: "eClassifiers") as? [EUUID]
        #expect(classifiers != nil)
        #expect(classifiers?.count == 2)  // Animal class and Species enum
    }

    /// Test parsing organisation.ecore with references
    ///
    /// This test validates:
    /// - EClass with EAttribute and EReference
    /// - Containment references
    /// - Cross-references (non-containment)
    /// - Multiplicity (lowerBound, upperBound)
    @Test("Parse organisation.ecore metamodel with references")
    func testParseOrganisationEcore() async throws {
        let resourcesURL = try getResourcesURL()
        let url = resourcesURL.appendingPathComponent("xmi").appendingPathComponent(
            "organisation.ecore")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestError.fileNotFound("organisation.ecore")
        }

        let parser = XMIParser()
        let resource = try await parser.parse(url)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        let pkg = roots[0] as? DynamicEObject
        #expect(pkg != nil)

        let pkgName = await resource.eGet(objectId: pkg!.id, feature: "name") as? String
        #expect(pkgName == "organisation")

        // Verify classifiers were parsed
        let classifiers =
            await resource.eGet(objectId: pkg!.id, feature: "eClassifiers") as? [EUUID]
        #expect(classifiers != nil)
        #expect(classifiers?.count == 3)  // Person, Team, Organisation
    }

    // MARK: - Instance Parsing Tests

    /// Test parsing a simple instance file
    ///
    /// This test validates:
    /// - Instance XMI parsing
    /// - Attribute values on instances
    /// - Namespace-based type resolution
    @Test("Parse simple animal instance")
    func testParseSimpleInstance() async throws {
        let resourcesURL = try getResourcesURL()
        let url = resourcesURL.appendingPathComponent("xmi").appendingPathComponent("zoo.xmi")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestError.fileNotFound("zoo.xmi")
        }

        let parser = XMIParser()
        let resource = try await parser.parse(url)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        // Verify instance attributes
        let animal = roots[0] as? DynamicEObject
        #expect(animal != nil)

        let name = await resource.eGet(objectId: animal!.id, feature: "name") as? String
        #expect(name == "Fluffy")

        let species = await resource.eGet(objectId: animal!.id, feature: "species") as? String
        #expect(species == "cat")
    }

    /// Test parsing instance with containment references
    ///
    /// This test validates:
    /// - Containment reference parsing
    /// - Multiple contained objects
    /// - Cross-references within same resource
    /// - XPath reference resolution (leader href="#//@members.0")
    @Test("Parse team instance with members and references")
    func testParseTeamInstance() async throws {
        let resourcesURL = try getResourcesURL()
        let url = resourcesURL.appendingPathComponent("xmi").appendingPathComponent("team.xmi")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestError.fileNotFound("team.xmi")
        }

        let parser = XMIParser()
        let resource = try await parser.parse(url)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        // Verify team attributes
        let team = roots[0] as? DynamicEObject
        #expect(team != nil)

        let teamName = await resource.eGet(objectId: team!.id, feature: "name") as? String
        #expect(teamName == "Engineering")

        // Verify contained members
        let members = await resource.eGet(objectId: team!.id, feature: "members") as? [EUUID]
        #expect(members != nil)
        #expect(members?.count == 3)

        // Verify first member's name
        if let firstMemberId = members?.first {
            let memberName =
                await resource.eGet(objectId: firstMemberId, feature: "name") as? String
            #expect(memberName == "Alice")

            // Verify XPath reference resolution - leader should point to first member
            let leaderId = await resource.eGet(objectId: team!.id, feature: "leader") as? EUUID
            #expect(leaderId != nil, "Leader reference should be resolved")
            #expect(leaderId == firstMemberId, "Leader should reference the first member (Alice)")

            // Verify leader's name is Alice
            if let leaderId = leaderId {
                let leaderName = await resource.eGet(objectId: leaderId, feature: "name") as? String
                #expect(leaderName == "Alice", "Leader's name should be Alice")
            }
        }
    }

    /// Test parsing XMI with arbitrary attributes
    ///
    /// This test validates:
    /// - Dynamic attribute iteration using `element.attributeNames`
    /// - Type inference for Int, Double, Bool, and String
    /// - Arbitrary user-defined attribute names
    /// - No data loss for unmapped attributes
    @Test("Parse XMI with arbitrary attributes and type inference")
    func testArbitraryAttributes() async throws {
        let resourcesURL = try getResourcesURL()
        let url = resourcesURL.appendingPathComponent("xmi").appendingPathComponent(
            "arbitrary-attributes.xmi")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TestError.fileNotFound("arbitrary-attributes.xmi")
        }

        let parser = XMIParser()
        let resource = try await parser.parse(url)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        let record = roots[0] as? DynamicEObject
        #expect(record != nil)

        // Verify all attributes were captured with correct types
        let id = await resource.eGet(objectId: record!.id, feature: "id") as? String
        #expect(id == "R001")

        let name = await resource.eGet(objectId: record!.id, feature: "name") as? String
        #expect(name == "Test Record")

        let email = await resource.eGet(objectId: record!.id, feature: "email") as? String
        #expect(email == "test@example.com")

        // Verify Int type inference
        let count = await resource.eGet(objectId: record!.id, feature: "count") as? Int
        #expect(count == 42)

        // Verify Double type inference
        let ratio = await resource.eGet(objectId: record!.id, feature: "ratio") as? Double
        #expect(ratio == 3.14)

        // Verify Bool type inference (true)
        let active = await resource.eGet(objectId: record!.id, feature: "active") as? Bool
        #expect(active == true)

        // Verify Bool type inference (false)
        let inactive = await resource.eGet(objectId: record!.id, feature: "inactive") as? Bool
        #expect(inactive == false)

        // Verify String fallback for non-parseable values
        let status = await resource.eGet(objectId: record!.id, feature: "status") as? String
        #expect(status == "pending")
    }

    // MARK: - ResourceSet Metamodel Lookup Tests (Phase 0.10)

    /// Test that XMI parser uses ResourceSet for metamodel lookup instead of always creating dynamic EClasses
    @Test("ResourceSet metamodel lookup - registered metamodel should be used")
    func testResourceSetMetamodelLookup() async throws {
        // Create a ResourceSet and register a metamodel
        let resourceSet = ResourceSet()

        // Create a simple metamodel with a Person class
        let stringType = EDataType(name: "EString")
        var personClass = EClass(name: "Person")
        let nameAttr = EAttribute(name: "name", eType: stringType)
        personClass.eStructuralFeatures = [nameAttr]

        var metamodelPackage = EPackage(
            name: "family",
            nsURI: "http://family/1.0",
            nsPrefix: "fam"
        )
        metamodelPackage.eClassifiers = [personClass]

        // Register the metamodel in the ResourceSet
        await resourceSet.registerMetamodel(metamodelPackage, uri: "http://family/1.0")

        // Create XMI content that references this metamodel
        let xmiContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <fam:Person xmlns:fam="http://family/1.0"
                        xmlns:xmi="http://www.omg.org/XMI"
                        xmi:version="2.0"
                        name="John Doe"/>
            """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".xmi")
        try xmiContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Parse with ResourceSet - should use registered metamodel
        let parser = XMIParser(resourceSet: resourceSet)
        let resource = try await parser.parse(tempURL)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        let person = roots[0] as? DynamicEObject
        #expect(person != nil)

        // Verify that the object uses the registered EClass, not a dynamic one
        #expect(person!.eClass.name == "Person")

        // Verify that the name attribute was parsed correctly
        let name = await resource.eGet(objectId: person!.id, feature: "name") as? String
        #expect(name == "John Doe")
    }

    /// Test fallback to dynamic EClass creation when metamodel is not registered
    @Test("ResourceSet metamodel lookup - fallback to dynamic EClass")
    func testResourceSetFallbackToDynamic() async throws {
        // Create a ResourceSet but don't register the needed metamodel
        let resourceSet = ResourceSet()

        // Create XMI content that references an unregistered metamodel
        let xmiContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <unknown:Widget xmlns:unknown="http://unknown/1.0"
                           xmlns:xmi="http://www.omg.org/XMI"
                           xmi:version="2.0"
                           title="Test Widget"/>
            """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".xmi")
        try xmiContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Parse with ResourceSet - should fall back to dynamic creation
        let parser = XMIParser(resourceSet: resourceSet)
        let resource = try await parser.parse(tempURL)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        let widget = roots[0] as? DynamicEObject
        #expect(widget != nil)

        // Verify that a dynamic EClass was created
        #expect(widget!.eClass.name == "Widget")

        // Verify that the title attribute was parsed correctly
        let title = await resource.eGet(objectId: widget!.id, feature: "title") as? String
        #expect(title == "Test Widget")
    }

    /// Test parsing without ResourceSet - should always create dynamic EClasses
    @Test("No ResourceSet - always creates dynamic EClasses")
    func testParsingWithoutResourceSet() async throws {
        // Create XMI content
        let xmiContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <test:Sample xmlns:test="http://test/1.0"
                        xmlns:xmi="http://www.omg.org/XMI"
                        xmi:version="2.0"
                        value="123"/>
            """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".xmi")
        try xmiContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Parse without ResourceSet - should create dynamic EClass
        let parser = XMIParser()  // No ResourceSet
        let resource = try await parser.parse(tempURL)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        let sample = roots[0] as? DynamicEObject
        #expect(sample != nil)

        // Verify that a dynamic EClass was created
        #expect(sample!.eClass.name == "Sample")

        // Verify that the value attribute was parsed correctly (type inference converts "123" to Int)
        let value = await resource.eGet(objectId: sample!.id, feature: "value") as? Int
        #expect(value == 123)
    }

    /// Test that ResourceSet metamodel lookup creates proper instances
    @Test("ResourceSet metamodel lookup creates instances with registered types")
    func testResourceSetCreatesProperInstances() async throws {
        // Create a ResourceSet and register a metamodel
        let resourceSet = ResourceSet()

        // Create metamodel with Employee class
        let stringType = EDataType(name: "EString")
        var employeeClass = EClass(name: "Employee")
        let nameAttr = EAttribute(name: "name", eType: stringType)
        employeeClass.eStructuralFeatures = [nameAttr]

        var companyPackage = EPackage(
            name: "company",
            nsURI: "http://company/1.0",
            nsPrefix: "comp"
        )
        companyPackage.eClassifiers = [employeeClass]

        // Register the metamodel
        await resourceSet.registerMetamodel(companyPackage, uri: "http://company/1.0")

        // Create XMI content with single Employee instance
        let xmiContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <comp:Employee xmlns:comp="http://company/1.0"
                          xmlns:xmi="http://www.omg.org/XMI"
                          xmi:version="2.0"
                          name="Alice"/>
            """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".xmi")
        try xmiContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Parse with ResourceSet
        let parser = XMIParser(resourceSet: resourceSet)
        let resource = try await parser.parse(tempURL)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        // Verify instance uses registered EClass (not dynamic)
        let employee = roots[0] as? DynamicEObject
        #expect(employee != nil)
        #expect(employee!.eClass.name == "Employee")

        // Verify the instance can access registered metamodel structure
        let name = await resource.eGet(objectId: employee!.id, feature: "name") as? String
        #expect(name == "Alice")

        // Verify this is the registered EClass (not a dynamic one)
        let registeredEmployeeClass = companyPackage.getClassifier("Employee") as? EClass
        #expect(registeredEmployeeClass != nil)
        #expect(employee!.eClass.id == registeredEmployeeClass!.id)
    }

    /// Test complex metamodel lookup with inheritance
    @Test("ResourceSet metamodel lookup with inheritance")
    func testMetamodelLookupWithInheritance() async throws {
        // Create ResourceSet
        let resourceSet = ResourceSet()

        // Create metamodel with inheritance: Person -> Employee
        let stringType = EDataType(name: "EString")
        let intType = EDataType(name: "EInt")
        var personClass = EClass(name: "Person")
        let nameAttr = EAttribute(name: "name", eType: stringType)
        personClass.eStructuralFeatures = [nameAttr]

        var employeeClass = EClass(name: "Employee")
        let salaryAttr = EAttribute(name: "salary", eType: intType)
        employeeClass.eStructuralFeatures = [salaryAttr]
        employeeClass.eSuperTypes = [personClass]  // Employee extends Person

        var hrPackage = EPackage(
            name: "hr",
            nsURI: "http://hr/1.0",
            nsPrefix: "hr"
        )
        hrPackage.eClassifiers = [personClass, employeeClass]

        // Register the metamodel
        await resourceSet.registerMetamodel(hrPackage, uri: "http://hr/1.0")

        // Create XMI content with inheritance
        let xmiContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <hr:Employee xmlns:hr="http://hr/1.0"
                        xmlns:xmi="http://www.omg.org/XMI"
                        xmi:version="2.0"
                        name="Jane Smith"
                        salary="90000"/>
            """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".xmi")
        try xmiContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Parse with ResourceSet
        let parser = XMIParser(resourceSet: resourceSet)
        let resource = try await parser.parse(tempURL)
        let roots = await resource.getRootObjects()

        #expect(roots.count == 1)

        let employee = roots[0] as? DynamicEObject
        #expect(employee != nil)

        // Verify correct EClass was used
        #expect(employee!.eClass.name == "Employee")

        // Verify inherited attribute works
        let name = await resource.eGet(objectId: employee!.id, feature: "name") as? String
        #expect(name == "Jane Smith")

        // Verify own attribute works
        let salary = await resource.eGet(objectId: employee!.id, feature: "salary") as? Int
        #expect(salary == 90000)
    }

    // MARK: - Reference Type Resolution Tests

    /// Test that child elements are typed by their parent's reference eType, not element name
    ///
    /// This test validates the critical behavior where XML element names represent
    /// reference names (like `<father>`, `<mother>`), but the actual EClass of the
    /// child object should come from the reference's eType (e.g., `Member`).
    ///
    /// Without this, `getAllInstancesOf(Member)` would return 0 because instances
    /// would be created with EClass names matching the XML element names instead.
    @Test("Parse instances with reference-based type resolution")
    func testReferenceTypeResolution() async throws {
        // Create a simple metamodel with proper type references
        // Note: We need to create the Person class first, then reference it
        let personClass = EClass(
            name: "Person",
            eStructuralFeatures: [
                EAttribute(name: "firstName", eType: EDataType(name: "EString"))
            ]
        )

        let familyClass = EClass(
            name: "Family",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: EDataType(name: "EString")),
                EReference(
                    name: "father",
                    eType: personClass,
                    containment: true
                ),
                EReference(
                    name: "mother",
                    eType: personClass,
                    containment: true
                )
            ]
        )

        let metamodel = EPackage(
            name: "TestFamily",
            nsURI: "http://test.family",
            nsPrefix: "fam",
            eClassifiers: [familyClass, personClass]
        )

        // Create XMI content with <father> and <mother> elements
        // These should be typed as "Person", not "father"/"mother"
        let xmiContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns="http://test.family">
          <Family name="Smith">
            <father firstName="John"/>
            <mother firstName="Jane"/>
          </Family>
        </xmi:XMI>
        """

        // Write to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-reference-types.xmi")
        try xmiContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Register metamodel in ResourceSet
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(metamodel, uri: "http://test.family")

        // Parse with ResourceSet
        let parser = XMIParser(resourceSet: resourceSet)
        let resource = try await parser.parse(tempURL)

        // Get all objects
        let allObjects = await resource.getAllObjects()
        #expect(allObjects.count == 3)  // 1 Family + 2 Persons

        // Get the Person EClass from metamodel
        guard let personClass = metamodel.getClassifier("Person") as? EClass else {
            Issue.record("Person class not found in metamodel")
            return
        }

        // Critical test: getAllInstancesOf(Person) should find both father and mother
        let persons = await resource.getAllInstancesOf(personClass)
        #expect(persons.count == 2, "Should find 2 Person instances (father and mother)")

        // Verify the instances have correct EClass
        for person in persons {
            #expect(person.eClass.name == "Person",
                   "Child element should be typed as 'Person' (reference eType), not element name")
            #expect(person.eClass.id == personClass.id,
                   "EClass ID should match the metamodel's Person class")
        }

        // Verify we can access their attributes
        let firstNames = persons.compactMap { obj -> String? in
            guard let dynObj = obj as? DynamicEObject else { return nil }
            return dynObj.eGet("firstName") as? String
        }
        #expect(firstNames.contains("John"))
        #expect(firstNames.contains("Jane"))
    }
}
