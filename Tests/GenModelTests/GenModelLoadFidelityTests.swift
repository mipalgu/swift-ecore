//
// GenModelLoadFidelityTests.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import Testing

@testable import GenModel

@Suite("GenModel metamodel loading")
struct GenModelLoadFidelityTests {
    private static let ecoreReferences: [(owner: String, feature: String, target: EcoreClassifier)] = [
        ("GenPackage", "ecorePackage", .ePackage),
        ("GenClass", "ecoreClass", .eClass),
        ("GenFeature", "ecoreFeature", .eStructuralFeature),
        ("GenEnum", "ecoreEnum", .eEnum),
        ("GenEnumLiteral", "ecoreEnumLiteral", .eEnumLiteral),
        ("GenDataType", "ecoreDataType", .eDataType),
        ("GenOperation", "ecoreOperation", .eOperation),
        ("GenParameter", "ecoreParameter", .eParameter),
        ("GenTypeParameter", "ecoreTypeParameter", .eTypeParameter),
    ]

    @Test(
        "references to Ecore metaclasses resolve to the real Ecore descriptors",
        arguments: ecoreReferences)
    func ecoreMetaclassReferences(
        reference: (owner: String, feature: String, target: EcoreClassifier)
    ) async throws {
        let package = try await GenModelPackage.load()
        let owner = try #require(package.getEClass(reference.owner))
        let feature = try #require(owner.eAllReferences.first { $0.name == reference.feature })
        let descriptor = EcorePackage.metaClass(reference.target)
        #expect(feature.eType.id == descriptor.id)
        #expect(EcorePackage.isMetaClass(feature.eType))
        #expect(feature.eType.name == descriptor.name)
    }

    @Test("metaclass references are complete descriptors")
    func completeDescriptors() async throws {
        let package = try await GenModelPackage.load()
        let genClass = try #require(package.getEClass("GenClass"))
        let ecoreClass = try #require(genClass.eAllReferences.first { $0.name == "ecoreClass" })
        let target = try #require(ecoreClass.eType as? EClass)
        #expect(target.eAllStructuralFeatures.map(\.name).contains("eSuperTypes"))
    }

    @Test("no stand-in classes for Ecore metaclasses are created")
    func noStandIns() async throws {
        let package = try await GenModelPackage.load()
        #expect(package.getClassifier("EClass") == nil)
        #expect(package.getClassifier("EOperation") == nil)
    }
}
