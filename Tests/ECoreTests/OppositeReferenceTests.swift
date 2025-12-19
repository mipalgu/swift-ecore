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
        let parser = XMIParser(resourceSet: resourceSet)
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

    @Test func testBidirectionalReferenceEClassInstanceMismatch() async throws {
        // This test specifically reproduces the bidirectional reference regression issue:
        // During metamodel loading, Member EClass has correct structural features (5 features)
        // But during model instance parsing, Member EClass from reference.eType has 0 features

        let resourcesURL = try getResourcesURL()
        let metamodelURL = resourcesURL.appendingPathComponent("metamodels/Families.ecore")

        // Step 1: Load metamodel and verify Member class has bidirectional references
        let package = try await EPackage(url: metamodelURL) // enableDebugging: true for debugging
        guard let memberClass = package.getClassifier("Member") as? EClass else {
            throw ECoreExecutionError.typeError("Member class not found in metamodel")
        }

        // Verify Member has the expected 5 structural features including bidirectional references
        #expect(memberClass.eStructuralFeatures.count == 5,
                "Member should have 5 features: firstName, lastName, familyFather, familyMother, familySon, familyDaughter")

        // Verify familyMother exists in the metamodel
        guard let familyMotherRef = memberClass.getStructuralFeature(name: "familyMother") as? EReference else {
            throw ECoreExecutionError.typeError("familyMother reference not found in Member class")
        }
        #expect(familyMotherRef.name == "familyMother")

        // Step 2: Get the Family class and check its mother reference's eType
        guard let familyClass = package.getClassifier("Family") as? EClass else {
            throw ECoreExecutionError.typeError("Family class not found in metamodel")
        }

        guard let motherRef = familyClass.getStructuralFeature(name: "mother") as? EReference else {
            throw ECoreExecutionError.typeError("mother reference not found in Family class")
        }

        // Step 3: This is the key test - check if motherRef.eType has the same features as memberClass
        guard let motherRefEType = motherRef.eType as? EClass else {
            throw ECoreExecutionError.typeError("mother reference eType should be EClass")
        }

        // This assertion should fail with the current implementation because
        // motherRef.eType is a placeholder EClass with only the name, not the full resolved EClass
        #expect(motherRefEType.eStructuralFeatures.count == memberClass.eStructuralFeatures.count,
                "Member EClass from reference.eType should have same features as metamodel Member EClass")

        // Specifically check that motherRef.eType has the familyMother reference
        let eTypeFamilyMother = motherRefEType.getStructuralFeature(name: "familyMother")
        #expect(eTypeFamilyMother != nil,
                "Member EClass from reference.eType should have familyMother reference")

        // Compare the EClass instances directly - they should be the same object
        #expect(motherRefEType.id == memberClass.id,
                "Member EClass from reference.eType should be the same instance as metamodel Member EClass")
    }

    @Test func testEOppositeAttributeParsing() async throws {
        // Test that eOpposite attributes are correctly parsed from XMI
        let resourcesURL = try getResourcesURL()
        let metamodelURL = resourcesURL.appendingPathComponent("metamodels/Families.ecore")

        // Parse the metamodel using XMIParser directly to test eOpposite parsing
        let parser = XMIParser()
        let resource = try await parser.parse(metamodelURL)

        let rootObjects = await resource.getRootObjects()
        #expect(rootObjects.count == 1, "Should have one root EPackage")

        guard let packageObj = rootObjects.first as? DynamicEObject else {
            throw ECoreExecutionError.typeError("Root object should be DynamicEObject")
        }

        // Get the classifiers
        guard let classifiers = packageObj.eGet("eClassifiers") as? [EUUID] else {
            throw ECoreExecutionError.typeError("Package should have eClassifiers")
        }

        #expect(classifiers.count == 2, "Should have Family and Member classes")

        // Find the Family class
        var familyClass: DynamicEObject?
        var memberClass: DynamicEObject?

        for classifierId in classifiers {
            if let classifier = await resource.resolve(classifierId) as? DynamicEObject,
               let name = classifier.eGet("name") as? String {
                if name == "Family" {
                    familyClass = classifier
                } else if name == "Member" {
                    memberClass = classifier
                }
            }
        }

        guard let family = familyClass, let member = memberClass else {
            throw ECoreExecutionError.typeError("Should find both Family and Member classes")
        }

        // Test Family.mother reference has eOpposite
        guard let familyFeatures = family.eGet("eStructuralFeatures") as? [EUUID] else {
            throw ECoreExecutionError.typeError("Family should have structural features")
        }

        var motherRef: DynamicEObject?
        for featureId in familyFeatures {
            if let feature = await resource.resolve(featureId) as? DynamicEObject,
               let name = feature.eGet("name") as? String,
               name == "mother" {
                motherRef = feature
                break
            }
        }

        guard let motherReference = motherRef else {
            throw ECoreExecutionError.typeError("Should find mother reference in Family")
        }

        // Check that eOpposite was parsed and resolved
        let oppositeId = motherReference.eGet(XMIAttribute.eOpposite.rawValue) as? EUUID
        #expect(oppositeId != nil, "mother reference should have eOpposite parsed")

        if let oppId = oppositeId {
            let opposite = await resource.resolve(oppId) as? DynamicEObject
            #expect(opposite != nil, "eOpposite should resolve to an object")
            if let opp = opposite {
                let oppName = opp.eGet("name") as? String
                #expect(oppName == "familyMother", "eOpposite should resolve to familyMother reference")
            }
        }

        // Test Member.familyMother reference has eOpposite
        guard let memberFeatures = member.eGet("eStructuralFeatures") as? [EUUID] else {
            throw ECoreExecutionError.typeError("Member should have structural features")
        }

        var familyMotherRef: DynamicEObject?
        for featureId in memberFeatures {
            if let feature = await resource.resolve(featureId) as? DynamicEObject,
               let name = feature.eGet("name") as? String,
               name == "familyMother" {
                familyMotherRef = feature
                break
            }
        }

        guard let familyMotherReference = familyMotherRef else {
            throw ECoreExecutionError.typeError("Should find familyMother reference in Member")
        }

        // Check that eOpposite was parsed and resolved
        let familyMotherOppositeId = familyMotherReference.eGet(XMIAttribute.eOpposite.rawValue) as? EUUID
        #expect(familyMotherOppositeId != nil, "familyMother reference should have eOpposite parsed")

        if let oppId = familyMotherOppositeId {
            let opposite = await resource.resolve(oppId) as? DynamicEObject
            #expect(opposite != nil, "familyMother eOpposite should resolve to an object")
            if let opp = opposite {
                let oppName = opp.eGet("name") as? String
                #expect(oppName == "mother", "familyMother eOpposite should resolve to mother reference")
            }
        }
    }

    @Test func testEOppositeVsOppositeAttributeFallback() async throws {
        // Create a test XMI with 'opposite' attribute instead of 'eOpposite'
        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("test-opposite-\(UUID().uuidString).ecore")

        let xmiContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="TestPackage" nsURI="http://test.example.org/testpackage" nsPrefix="test">
          <eClassifiers xsi:type="ecore:EClass" name="ClassA">
            <eStructuralFeatures xsi:type="ecore:EReference" name="refToB" eType="#//ClassB" opposite="#//ClassB/refToA"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="ClassB">
            <eStructuralFeatures xsi:type="ecore:EReference" name="refToA" eType="#//ClassA" opposite="#//ClassA/refToB"/>
          </eClassifiers>
        </ecore:EPackage>
        """

        try xmiContent.write(to: testURL, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testURL)
        }

        // Parse the metamodel
        let parser = XMIParser()
        let resource = try await parser.parse(testURL)

        let rootObjects = await resource.getRootObjects()
        #expect(rootObjects.count == 1, "Should have one root EPackage")

        guard let packageObj = rootObjects.first as? DynamicEObject else {
            throw ECoreExecutionError.typeError("Root object should be DynamicEObject")
        }

        // Get classifiers and find ClassA
        guard let classifiers = packageObj.eGet("eClassifiers") as? [EUUID] else {
            throw ECoreExecutionError.typeError("Package should have eClassifiers")
        }

        var classA: DynamicEObject?
        for classifierId in classifiers {
            if let classifier = await resource.resolve(classifierId) as? DynamicEObject,
               let name = classifier.eGet("name") as? String,
               name == "ClassA" {
                classA = classifier
                break
            }
        }

        guard let classAObj = classA else {
            throw ECoreExecutionError.typeError("Should find ClassA")
        }

        // Find refToB reference
        guard let features = classAObj.eGet("eStructuralFeatures") as? [EUUID] else {
            throw ECoreExecutionError.typeError("ClassA should have structural features")
        }

        var refToBRef: DynamicEObject?
        for featureId in features {
            if let feature = await resource.resolve(featureId) as? DynamicEObject,
               let name = feature.eGet("name") as? String,
               name == "refToB" {
                refToBRef = feature
                break
            }
        }

        guard let refToBReference = refToBRef else {
            throw ECoreExecutionError.typeError("Should find refToB reference")
        }

        // Check that opposite attribute was parsed (fallback from eOpposite to opposite)
        let oppositeId = refToBReference.eGet(XMIAttribute.opposite.rawValue) as? EUUID
        #expect(oppositeId != nil, "refToB should have opposite parsed (fallback from eOpposite)")

        if let oppId = oppositeId {
            let opposite = await resource.resolve(oppId) as? DynamicEObject
            #expect(opposite != nil, "opposite should resolve to an object")
            if let opp = opposite {
                let oppName = opp.eGet("name") as? String
                #expect(oppName == "refToA", "opposite should resolve to refToA reference")
            }
        }
    }

    @Test func testEReferenceBidirectionalityAfterParsing() async throws {
        // Test that after parsing a metamodel with eOpposite attributes,
        // we can create EReference objects that have proper opposite references
        let resourcesURL = try getResourcesURL()
        let metamodelURL = resourcesURL.appendingPathComponent("metamodels/Families.ecore")

        // Parse and create EPackage
        let package = try await EPackage(url: metamodelURL)

        // Get the Family and Member classes
        guard let familyClass = package.getClassifier("Family") as? EClass else {
            throw ECoreExecutionError.typeError("Family class not found")
        }

        guard let memberClass = package.getClassifier("Member") as? EClass else {
            throw ECoreExecutionError.typeError("Member class not found")
        }

        // Get the mother reference from Family
        guard let motherRef = familyClass.getStructuralFeature(name: "mother") as? EReference else {
            throw ECoreExecutionError.typeError("mother reference not found in Family")
        }

        // Get the familyMother reference from Member
        guard let familyMotherRef = memberClass.getStructuralFeature(name: "familyMother") as? EReference else {
            throw ECoreExecutionError.typeError("familyMother reference not found in Member")
        }

        // Test that the opposite references are properly set
        #expect(motherRef.opposite != nil, "mother reference should have opposite set")
        #expect(familyMotherRef.opposite != nil, "familyMother reference should have opposite set")

        // The opposite references should point to each other (by ID)
        if let motherOppositeId = motherRef.opposite,
           let familyMotherOppositeId = familyMotherRef.opposite {
            #expect(motherOppositeId == familyMotherRef.id, "mother's opposite should be familyMother")
            #expect(familyMotherOppositeId == motherRef.id, "familyMother's opposite should be mother")
        }
    }
}
