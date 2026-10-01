//
// GenModelDerivedFeatureTests.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import GenModel

@Suite("Derived features of generator model objects")
struct GenModelDerivedFeatureTests {
    private struct Loaded {
        let resourceSet = ResourceSet()
        let resource: Resource
        let engine: ECoreExecutionEngine
        let context: GenModelContext
        let genModel: GenElement

        init(_ name: String = "ops") async throws {
            let url = try #require(
                Bundle.module.url(forResource: name, withExtension: "genmodel", subdirectory: "Resources"))
            resource = try await GenModelResource.load(
                url: url, resourceSet: resourceSet, resolution: .nameFragments)
            engine = ECoreExecutionEngine(models: [:])
            await engine.registerResource(resource, alias: "gen")
            context = await GenModelContext.snapshot(of: resourceSet)
            genModel = try #require(context.genModels.first)
        }

        func navigate(_ element: GenElement, _ property: String) async throws -> (any EcoreValue)? {
            try await engine.navigate(from: element.object, property: property)
        }

        func ids(_ element: GenElement, _ property: String) async throws -> [EUUID] {
            let value = try await navigate(element, property)
            return (value as? EcoreValueArray)?.values.compactMap { ($0 as? DynamicEObject)?.id } ?? []
        }

        func id(_ element: GenElement, _ property: String) async throws -> EUUID? {
            (try await navigate(element, property) as? DynamicEObject)?.id
        }
    }

    @Test("platform and delegation flags are computed from the chosen enumeration literals")
    func modelFlags() async throws {
        let ops = try await Loaded()
        #expect(try await ops.navigate(ops.genModel, "richClientPlatform") as? Bool == true)
        #expect(try await ops.navigate(ops.genModel, "richAjaxPlatform") as? Bool == false)
        #expect(try await ops.navigate(ops.genModel, "reflectiveDelegation") as? Bool == true)
        let library = try await Loaded("library")
        #expect(try await library.navigate(library.genModel, "richClientPlatform") as? Bool == false)
        #expect(try await library.navigate(library.genModel, "richAjaxPlatform") as? Bool == false)
        #expect(try await library.navigate(library.genModel, "reflectiveDelegation") as? Bool == false)
    }

    @Test("the rich Ajax platform also counts as a rich client")
    func ajaxPlatform() async throws {
        let loaded = try await Loaded()
        await loaded.resource.eSet(
            objectId: loaded.genModel.object.id, feature: "runtimePlatform", value: "RAP")
        #expect(try await loaded.navigate(loaded.genModel, "richAjaxPlatform") as? Bool == true)
        #expect(try await loaded.navigate(loaded.genModel, "richClientPlatform") as? Bool == true)
    }

    @Test("a package lists its classes, enumerations and data types as classifiers")
    func genClassifiers() async throws {
        let library = try await Loaded("library")
        let package = try #require(library.genModel.genPackages.first)
        let expected = package.genClassifiers.map(\.object.id)
        #expect(expected.count == 7)
        #expect(try await library.ids(package, "genClassifiers") == expected)
    }

    @Test("a classifier reads its owning package")
    func classifierPackage() async throws {
        let library = try await Loaded("library")
        let package = try #require(library.genModel.genPackages.first)
        for classifier in package.genClassifiers {
            #expect(try await library.id(classifier, "genPackage") == package.object.id)
        }
    }

    @Test("a package reads its generator model, also when nested")
    func packageModel() async throws {
        let ops = try await Loaded()
        let package = try #require(ops.genModel.genPackages.first)
        let nested = try #require(package.nestedGenPackages.first)
        #expect(try await ops.id(package, "genModel") == ops.genModel.object.id)
        #expect(try await ops.id(nested, "genModel") == ops.genModel.object.id)
    }

    @Test("container references of features, operations and parameters read their owners")
    func containers() async throws {
        let ops = try await Loaded()
        let genClass = try #require(ops.genModel.genPackages.first?.genClasses.first)
        let feature = try #require(genClass.genFeatures.first)
        let operation = try #require(genClass.genOperations.first)
        let parameter = try #require(operation.genParameters.first)
        #expect(try await ops.id(feature, "genClass") == genClass.object.id)
        #expect(try await ops.id(operation, "genClass") == genClass.object.id)
        #expect(try await ops.id(parameter, "genOperation") == operation.object.id)
    }

    @Test("stored values are still read as stored")
    func storedValues() async throws {
        let ops = try await Loaded()
        #expect(try await ops.navigate(ops.genModel, "modelName") as? String == "Ops")
    }
}
