//
// GenElementOperationTests.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import GenModel

@Suite("Operations, parameters and feature flags of a loaded model")
struct GenElementOperationTests {
    private struct Loaded {
        let context: GenModelContext
        let genClass: GenElement

        init() async throws {
            let url = try #require(
                Bundle.module.url(forResource: "ops", withExtension: "genmodel", subdirectory: "Resources"))
            let resourceSet = ResourceSet()
            _ = try await GenModelResource.load(
                url: url, resourceSet: resourceSet, resolution: .nameFragments)
            context = await GenModelContext.snapshot(of: resourceSet)
            let genModel = try #require(context.genModels.first)
            genClass = try #require(genModel.genPackages.first?.genClasses.first)
        }
    }

    @Test("operations and parameters take their names from the native elements")
    func names() async throws {
        let loaded = try await Loaded()
        let operations = loaded.genClass.genOperations
        #expect(operations.map(\.name) == ["scale", "ping", "ping"])
        let scale = try #require(operations.first)
        #expect(scale.genParameters.map(\.name) == ["factor", "steps"])
        #expect(scale.capName == "Scale")
        #expect(scale.genParameters[0].upperName == "FACTOR")
    }

    @Test("operations and parameters expose their native elements")
    func nativeElements() async throws {
        let loaded = try await Loaded()
        let scale = try #require(loaded.genClass.genOperations.first)
        #expect(scale.ecoreOperation?.name == "scale")
        #expect(scale.ecoreParameter == nil)
        let factor = try #require(scale.genParameters.first)
        #expect(factor.ecoreParameter?.name == "factor")
        #expect(factor.ecoreOperation == nil)
        #expect(loaded.genClass.ecoreOperation == nil)
        #expect(loaded.genClass.ecoreParameter == nil)
    }

    @Test("types and bounds follow the native elements")
    func typesAndBounds() async throws {
        let loaded = try await Loaded()
        let scale = try #require(loaded.genClass.genOperations.first)
        #expect(scale.ecoreType?.name == "EBoolean")
        #expect(scale.upperBound == 1)
        #expect(!scale.isListType)
        let factor = scale.genParameters[0]
        let steps = scale.genParameters[1]
        #expect(factor.ecoreType?.name == "EDouble")
        #expect(factor.lowerBound == 1)
        #expect(factor.isRequired)
        #expect(steps.ecoreType?.name == "EInt")
        #expect(steps.upperBound == -1)
        #expect(steps.isListType)
        #expect(loaded.genClass.genOperations[1].ecoreType == nil)
        #expect(loaded.genClass.genOperations[2].isListType)
        let size = try #require(loaded.genClass.genFeatures.last)
        #expect(size.ecoreType?.name == "EInt")
        #expect(loaded.genClass.ecoreType == nil)
    }

    @Test("overloaded operations resolve to distinct native operations")
    func overloads() async throws {
        let loaded = try await Loaded()
        let pings = Array(loaded.genClass.genOperations.dropFirst())
        #expect(pings[0].ecoreOperation?.id != pings[1].ecoreOperation?.id)
        #expect(pings[0].ecoreOperation?.eType == nil)
    }

    @Test("owning elements are navigable from operations and parameters")
    func owners() async throws {
        let loaded = try await Loaded()
        let scale = try #require(loaded.genClass.genOperations.first)
        let factor = try #require(scale.genParameters.first)
        #expect(scale.genClass == loaded.genClass)
        #expect(factor.genOperation == scale)
        #expect(factor.genClass == loaded.genClass)
        #expect(factor.genPackage == loaded.genClass.genPackage)
        #expect(factor.genModel == loaded.genClass.genModel)
        #expect(loaded.genClass.genOperation == nil)
    }

    @Test("derived and unsettable flags are read from the native feature")
    func flags() async throws {
        let loaded = try await Loaded()
        let label = loaded.genClass.genFeatures[0]
        let size = loaded.genClass.genFeatures[1]
        #expect(label.isDerived)
        #expect(label.isVolatile)
        #expect(!label.isUnsettable)
        #expect(size.isUnsettable)
        #expect(!size.isDerived)
        #expect(!loaded.genClass.isDerived)
        #expect(!loaded.genClass.isUnsettable)
    }

    @Test("reference-based reading falls back to textual references")
    func textualFallback() async throws {
        var sample = try await SampleModel()
        let operation = try sample.genOperation("m.ecore#//Shape/scale", parameters: 1)
        let element = try #require(sample.context.element(id: operation.id))
        #expect(element.name == "scale")
        #expect(element.ecoreOperation == nil)
        #expect(element.upperBound == 1)
        #expect(element.ecoreType == nil)
        #expect(element.genParameters.map(\.name) == ["p0"])
    }
}
