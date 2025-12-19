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

    @Test func testLoadFamiliesMetamodel() async throws {
        // Load the Families metamodel which has opposite references
        let metamodelURL = URL(fileURLWithPath: "Tests/ECoreTests/Resources/metamodels/Families.ecore")

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
        let metamodelURL = URL(fileURLWithPath: "Tests/ECoreTests/Resources/metamodels/Families.ecore")
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
        await executionEngine.enableDebugging(true)

        // Create a member instance using the factory
        let factory = package.eFactoryInstance
        let member = factory.create(memberClass)
        await modelResource.add(member)

        // Try to navigate to familyMother property - should return nil (not set)
        let result = try await executionEngine.navigate(from: member, property: "familyMother")

        // The navigation should succeed and return nil (since we haven't set familyMother)
        #expect(result == nil, "familyMother should be nil (not set)")
    }
}
