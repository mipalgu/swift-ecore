//
// OppositeReferenceTests.swift
// ECore
//
//  Created by Rene Hexel on 19/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing
@testable import ECore

@Suite("Opposite Reference Tests")
struct OppositeReferenceTests {

    private enum TestError: Error {
        case resourcesNotFound
        case fileNotFound(String)
    }

    private func getResourcesURL() throws -> URL {
        guard let bundleResourcesURL = Bundle.module.resourceURL else {
            throw TestError.resourcesNotFound
        }

        let fm = FileManager.default
        let testResourcesURL = bundleResourcesURL.appendingPathComponent("Resources")
        var isDirectory = ObjCBool(false)

        if fm.fileExists(atPath: testResourcesURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return testResourcesURL
        } else {
            return bundleResourcesURL
        }
    }

    @Test func testLoadFamiliesMetamodel() async throws {
        // Load the Families metamodel which has opposite references
        let resourcesURL = try getResourcesURL()
        let metamodelURL = resourcesURL.appendingPathComponent("metamodels/Families.ecore")

        // Use the EPackage initializer which properly converts DynamicEObjects to EPackage
        let package = try await EPackage(url: metamodelURL)

        #expect(package.name == "Families", "Package name should be 'Families'")
        #expect(package.nsURI == "http://www.example.org/families", "Package nsURI should match the metamodel")

        // Verify we have classifiers
        #expect(package.eClassifiers.count > 0, "Should have classifiers")

        // Find the Member class
        guard let memberClass = package.getClassifier("Member") as? EClass else {
            throw ECoreExecutionError.typeError("Member class not found")
        }

        // Verify Member has structural features
        #expect(memberClass.eStructuralFeatures.count > 0, "Member should have structural features")

        // Find the familyMother reference
        guard let familyMotherRef = memberClass.getStructuralFeature(name: "familyMother") as? EReference else {
            throw ECoreExecutionError.typeError("familyMother reference not found on Member class")
        }

        // Verify it's the opposite reference
        #expect(familyMotherRef.name == "familyMother", "Reference name should be 'familyMother'")
        #expect(familyMotherRef.lowerBound == 0, "familyMother should be optional")
    }

    @Test func testNavigateOppositeReferencesWithDebug() async throws {
        // Load the Families metamodel using proper EPackage initializer
        let resourcesURL = try getResourcesURL()
        let metamodelURL = resourcesURL.appendingPathComponent("metamodels/Families.ecore")
        let package = try await EPackage(url: metamodelURL)

        guard let memberClass = package.getClassifier("Member") as? EClass else {
            throw ECoreExecutionError.typeError("Member class not found")
        }

        // Create execution engine with debug enabled
        let modelResource = Resource(uri: "test://test-model")

        // Create a reference model using the package
        // We need to parse the metamodel resource for the SharedTestReferenceModel
        let parser = XMIParser()
        let metamodelResource = try await parser.parse(metamodelURL)
        let referenceModel = SharedTestReferenceModel(rootPackage: package, resource: metamodelResource)
        let model = EcoreModel(resource: modelResource, referenceModel: referenceModel, isTarget: false)
        let executionEngine = ECoreExecutionEngine(models: ["test": model])
        //await executionEngine.enableDebugging(true)

        // Create a member instance using the factory
        let factory = package.eFactoryInstance
        let member = factory.create(memberClass)
        await modelResource.add(member)

        // Try to navigate to familyMother property - should return nil (not set)
        let result = try await executionEngine.navigate(from: member, property: "familyMother")

        // The navigation should succeed and return nil (since we haven't set familyMother)
        #expect(result == nil, "familyMother should be nil (not set)")
    }

    @Test func testXMIParserUsesRegisteredMetamodel() async throws {
        // This test verifies that when a metamodel is registered in a ResourceSet,
        // the XMI parser uses the proper EClass instances from that metamodel
        // instead of creating dynamic EClass instances without structural features.

        // Step 1: Load the Families metamodel properly as EPackage
        let resourcesURL = try getResourcesURL()
        let metamodelURL = resourcesURL.appendingPathComponent("metamodels/Families.ecore")
        let package = try await EPackage(url: metamodelURL)

        // Verify the metamodel has the expected structure
        guard let memberClass = package.getClassifier("Member") as? EClass else {
            throw ECoreExecutionError.typeError("Member class not found in metamodel")
        }
        #expect(memberClass.eStructuralFeatures.count > 0, "Member should have structural features")

        // Find the familyMother reference to verify it exists in the metamodel
        guard let familyMotherRef = memberClass.getStructuralFeature(name: "familyMother") as? EReference else {
            throw ECoreExecutionError.typeError("familyMother reference not found in Member class")
        }
        #expect(familyMotherRef.name == "familyMother", "Reference should be named 'familyMother'")

        // Step 2: Create a ResourceSet and register the metamodel
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(package, uri: package.nsURI)

        // Step 3: Create a simple XMI model file to test parsing
        let tempDir = FileManager.default.temporaryDirectory
        let modelURL = tempDir.appendingPathComponent("test-families-\(UUID().uuidString).xmi")

        let xmiContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns="http://www.example.org/families">
          <Family lastName="TestFamily">
            <father firstName="John"/>
            <mother firstName="Jane"/>
          </Family>
        </xmi:XMI>
        """

        try xmiContent.write(to: modelURL, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: modelURL)
        }

        // Step 4: Parse the model using XMIParser with the ResourceSet
        let parser = XMIParser(resourceSet: resourceSet, enableDebugging: true)
        let resource = try await parser.parse(modelURL)

        let rootObjects = await resource.getRootObjects()
        #expect(rootObjects.count > 0, "Should have parsed root objects")

        // Step 5: Verify that parsed objects use the registered metamodel's EClass
        guard let family = rootObjects.first else {
            throw ECoreExecutionError.typeError("No root object found")
        }

        // The crucial test: verify the eClass is the proper EClass with structural features
        #expect(family.eClass.name == "Family", "Root object should be a Family")

        // Cast to EClass to check structural features
        guard let familyEClass = family.eClass as? EClass else {
            throw ECoreExecutionError.typeError("eClass should be an EClass instance, not dynamic")
        }

        // This is the key assertion: the EClass should have structural features from the metamodel
        #expect(familyEClass.eStructuralFeatures.count > 0,
                "Family EClass should have structural features from registered metamodel")

        // Verify we can find the 'lastName' attribute
        let lastNameFeature = familyEClass.getStructuralFeature(name: "lastName")
        #expect(lastNameFeature != nil, "Family should have 'lastName' feature from metamodel")

        // Verify we can navigate to contained members
        if let motherFeature = familyEClass.getStructuralFeature(name: "mother") {
            if let mother = family.eGet(motherFeature) as? (any EObject) {
                // Verify mother uses the registered Member EClass
                guard let motherEClass = mother.eClass as? EClass else {
                    throw ECoreExecutionError.typeError("Mother's eClass should be EClass instance")
                }

                // This is the ultimate test: Member instances should have familyMother reference
                let motherFamilyMotherRef = motherEClass.getStructuralFeature(name: "familyMother")
                #expect(motherFamilyMotherRef != nil,
                        "Member instances should have 'familyMother' reference from registered metamodel")
            }
        }
    }
}
