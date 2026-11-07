//
// CompleteOCLApplicationTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import OCL
import Testing

@testable import ECore

/// Verifies that the constraints of a Complete OCL document are added to loaded metamodels
/// through ``ModelIO``.
@Suite("Complete OCL applied to loaded metamodels")
struct CompleteOCLApplicationTests {
    /// The namespace URI of the school metamodel of the fixtures.
    static let schoolURI = "http://example.org/school"

    /// Loads the school metamodel without constraints into a resource set.
    static func loadBare(in resourceSet: ResourceSet) async throws -> ModelIO.Loaded {
        try await ModelIO.load(
            data: Data(CompleteOCLFixtures.bare.utf8), uri: "memory:/school.oclinecore", resourceSet: resourceSet)
    }

    @Test("the constraints of a document are added to the packages of a resource and its registration")
    func constraintsAreApplied() async throws {
        let resourceSet = ResourceSet()
        let loaded = try await Self.loadBare(in: resourceSet)
        let application = try await ModelIO.applyCompleteOCL(
            data: Data(CompleteOCLFixtures.constraints.utf8), uri: "memory:/school.ocl", to: [loaded.resource],
            in: resourceSet)
        #expect(application.isComplete, "\(application.diagnostics.map(\.message))")
        let direct = CompleteOCLApplier.apply(
            CompleteOCLReader.parse(CompleteOCLFixtures.constraints, sourceName: "memory:/school.ocl").document,
            to: try CompleteOCLTests.bare(), sourceName: "memory:/school.ocl")
        #expect(application.appliedCount == direct.appliedCount)
        #expect(MetamodelSummary.describe(application.packages) == MetamodelSummary.describe(direct.packages))

        let roots = await loaded.resource.getRootObjects().compactMap { $0 as? EPackage }
        #expect(roots.map(\.name) == ["school"])
        let course = try #require(roots.first?.getEClass("Course"))
        #expect(OCLConstraintAnnotations.invariants(of: course).map(\.name) == ["HasCapacity", "NotOverfull"])
        let registered = try #require(await resourceSet.getMetamodel(uri: Self.schoolURI))
        let registeredCourse = try #require(registered.getEClass("Course"))
        #expect(OCLConstraintAnnotations.invariants(of: registeredCourse).count == 2)
    }

    @Test("the constrained metamodel is written with its constraints")
    func constrainedMetamodelIsWritten() async throws {
        let resourceSet = ResourceSet()
        let loaded = try await Self.loadBare(in: resourceSet)
        _ = try await ModelIO.applyCompleteOCL(
            data: Data(CompleteOCLFixtures.constraints.utf8), uri: "memory:/school.ocl", to: [loaded.resource],
            in: resourceSet)
        var diagnostics = ConversionDiagnostics()
        let text = try await ModelIO.serialise(loaded.resource, format: .oclinecore, diagnostics: &diagnostics)
        #expect(text.contains("invariant HasCapacity: capacity > 0;"))
    }

    @Test("a document is read from a file through the URI handlers of the resource set")
    func documentIsReadFromFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompleteOCLApplicationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("school.ocl")
        try CompleteOCLFixtures.constraints.write(to: url, atomically: true, encoding: .utf8)
        let resourceSet = ResourceSet()
        let loaded = try await Self.loadBare(in: resourceSet)
        let application = try await ModelIO.applyCompleteOCL(at: url, to: [loaded.resource], in: resourceSet)
        #expect(application.isComplete)
        #expect(application.diagnostics.allSatisfy { $0.document == URIReference.canonicalise(url.absoluteString) })
    }

    @Test("contexts that the metamodels lack are reported, and the rest is applied")
    func unresolvedContextsAreReported() async throws {
        let resourceSet = ResourceSet()
        let loaded = try await Self.loadBare(in: resourceSet)
        let text = CompleteOCLFixtures.constraints.replacingOccurrences(of: "context Student", with: "context Teacher")
        let application = try await ModelIO.applyCompleteOCL(
            data: Data(text.utf8), uri: "memory:/school.ocl", to: [loaded.resource], in: resourceSet)
        #expect(!application.isComplete)
        #expect(application.diagnostics.contains { $0.code == OCLDiagnosticCode.unresolvedContext })
        let course = try #require(application.packages.first?.getEClass("Course"))
        #expect(OCLConstraintAnnotations.invariants(of: course).count == 2)
    }

    @Test("a document that is not UTF-8 is read as ISO-8859-1 with a warning")
    func encodingIsApplied() async throws {
        let resourceSet = ResourceSet()
        let loaded = try await Self.loadBare(in: resourceSet)
        let text = CompleteOCLFixtures.constraints.replacingOccurrences(of: "-- Invariants", with: "-- Caf\u{E9} invariants")
        let data = try #require(text.data(using: .isoLatin1))
        let application = try await ModelIO.applyCompleteOCL(
            data: data, uri: "memory:/school.ocl", to: [loaded.resource], in: resourceSet)
        #expect(application.diagnostics.first?.code == TextDecodingDiagnostic.decodedAsISOLatin1)
        let explicit = try await ModelIO.applyCompleteOCL(
            data: data, uri: "memory:/school.ocl", to: [loaded.resource], in: resourceSet,
            options: ModelIO.LoadOptions(textEncoding: .isoLatin1))
        #expect(!explicit.diagnostics.contains { $0.code == TextDecodingDiagnostic.decodedAsISOLatin1 })
    }

    @Test("a resource of model instances is refused")
    func modelInstancesAreRefused() async throws {
        let resourceSet = ResourceSet()
        _ = try await Self.loadBare(in: resourceSet)
        let model = try await ModelIO.load(
            data: Data("<sch:Student xmlns:sch=\"http://example.org/school\" name=\"Ann\"/>".utf8),
            uri: "memory:/ann.xmi", resourceSet: resourceSet)
        await #expect(throws: ModelIOError.unconstrainableResource("memory:/ann.xmi")) {
            try await ModelIO.applyCompleteOCL(
                data: Data(CompleteOCLFixtures.constraints.utf8), uri: "memory:/school.ocl", to: [model.resource],
                in: resourceSet)
        }
    }
}
