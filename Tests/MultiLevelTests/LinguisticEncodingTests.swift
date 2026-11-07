//
// LinguisticEncodingTests.swift
// MultiLevelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import MultiLevel

/// Tests the lossless XMI and JSON interchange of deep models.
@Suite("Linguistic encoding")
struct LinguisticEncodingTests {
    @Test("the linguistic metamodel has a class for every linguistic concept")
    func package() {
        let package = MultiLevelPackage.package
        #expect(package.nsURI == MultiLevelSyntax.linguisticNamespaceURI)
        #expect(Set(package.eClassifiers.map(\.name)) == Set(LinguisticClass.allCases.map(\.rawValue)))
        let clabject = MultiLevelPackage.eClass(.clabject)
        #expect(clabject.getStructuralFeature(name: LinguisticFeature.potency.rawValue) != nil)
        #expect(clabject.getEReference(name: LinguisticFeature.features.rawValue)?.containment == true)
        #expect(clabject.getEReference(name: LinguisticFeature.type.rawValue)?.containment == false)
    }

    @Test("XMI interchange is lossless and byte-stable", arguments: MetaDepthTextTests.fixtures)
    func xmiRoundTrip(text: String) async throws {
        let model = try MultiLevelFixtures.model(text)
        let xmi = try await LinguisticEncoding.xmi(of: model)
        #expect(xmi.contains(MultiLevelSyntax.linguisticNamespaceURI))
        let decoded = try await LinguisticEncoding.model(from: Data(xmi.utf8), uri: "memory:model.xmi")
        #expect(decoded == model)
        #expect(try await LinguisticEncoding.xmi(of: decoded) == xmi)
        #expect(MetaDepthWriter.write(decoded).text == MetaDepthWriter.write(model).text)
    }

    @Test("JSON interchange is lossless and byte-stable", arguments: MetaDepthTextTests.fixtures)
    func jsonRoundTrip(text: String) async throws {
        let model = try MultiLevelFixtures.model(text)
        let json = try await LinguisticEncoding.json(of: model)
        let decoded = try await LinguisticEncoding.model(from: Data(json.utf8), uri: "memory:model.json")
        #expect(decoded == model)
        #expect(try await LinguisticEncoding.json(of: decoded) == json)
    }

    @Test("both XMI layouts and JSON write the encoding without warnings", arguments: MetaDepthTextTests.fixtures)
    func interchangeWithoutWarnings(text: String) async throws {
        let model = try MultiLevelFixtures.model(text)
        let resourceSet = ResourceSet()
        let resource = await LinguisticEncoding.resource(for: model, in: resourceSet)
        for options in [XMISerializationOptions.legacy, .emf] {
            var diagnostics = ConversionDiagnostics()
            let xmi = try await XMISerializer(options: options).serialize(resource, diagnostics: &diagnostics)
            #expect(diagnostics.warnings.isEmpty, "\(diagnostics.warnings)")
            let decoded = try await LinguisticEncoding.model(from: Data(xmi.utf8), uri: "memory:model.xmi")
            #expect(decoded == model)
        }
        var diagnostics = ConversionDiagnostics()
        _ = try await JSONSerializer().serialize(resource, diagnostics: &diagnostics)
        #expect(diagnostics.warnings.isEmpty, "\(diagnostics.warnings)")
        withExtendedLifetime(resourceSet) {}
    }

    @Test("the policy, the potency variant, identifiers and edges survive the interchange")
    func detailsSurvive() async throws {
        var model = try MultiLevelFixtures.model(MetaDepthTextTests.edgeText)
        model.levelCrossing = .nonStrict
        let decoded = try await LinguisticEncoding.model(
            from: Data(try await LinguisticEncoding.xmi(of: model).utf8), uri: "memory:edges.xmi")
        #expect(decoded.levelCrossing == .nonStrict)
        #expect(decoded.clabject(named: "credit")?.ends == model.clabject(named: "credit")?.ends)
        #expect(decoded.allClabjects.map(\.id) == model.allClabjects.map(\.id))
        let retail = try MultiLevelFixtures.model(MultiLevelFixtures.retail)
        let json = try await LinguisticEncoding.json(of: retail)
        #expect(try await LinguisticEncoding.model(from: Data(json.utf8), uri: "memory:retail.json").potencyVariant == .melanee)
    }

    @Test("decoding reports resources that hold no deep model and unknown potency variants")
    func decodingErrors() async throws {
        await #expect(throws: MultiLevelError.notALinguisticModel("memory:empty")) {
            try await LinguisticEncoding.model(from: Resource(uri: "memory:empty"))
        }
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.retail)
        let resourceSet = ResourceSet()
        let resource = await LinguisticEncoding.resource(for: model, in: resourceSet, uri: "memory:retail")
        await #expect(throws: MultiLevelError.unknownPotencyVariant("melanee")) {
            try await LinguisticEncoding.model(from: resource, schemes: [MetaDepthPotencyScheme()])
        }
        #expect(MultiLevelError.unreadableText(["a", "b"]).description == "Cannot read MetaDepth text: a; b")
    }
}

