//
// OCLinEcoreFormatHandlerTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import OCL
import Testing

@testable import ECore

/// Verifies that OCLinEcore metamodels are recognised, read and written through ``ModelIO``
/// and the ``ModelFormatRegistry``.
@Suite("OCLinEcore through the format registry")
struct OCLinEcoreFormatHandlerTests {
    /// A new temporary directory, which the caller removes.
    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OCLinEcoreFormatHandlerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("OCLinEcore is named by its file extension and name")
    func formatIsNamed() {
        #expect(ModelFormat.oclinecore.fileExtension == OCLinEcoreSyntax.fileExtension)
        #expect(ModelFormat.oclinecore.description == "OCLinEcore")
        #expect(ModelFormat(fileExtension: "OCLinEcore") == .oclinecore)
        #expect(ModelFormat.detect(url: URL(fileURLWithPath: "school.oclinecore")) == .oclinecore)
    }

    @Test("OCLinEcore documents are recognised by their package declaration", arguments: [
        OCLinEcoreFixtures.school,
        CompleteOCLFixtures.inline,
        "-- A school\npackage school : sch = 'http://example.org/school' { class Course; }",
        "package school = 'http://example.org/school' { }",
        "import ecore : 'http://www.eclipse.org/emf/2002/Ecore#/';\npackage school { }",
        "module school;\nlibrary 'lib.oclstdlib';\nimport other::types;\npackage school;",
    ])
    func oclinecoreIsRecognised(text: String) async {
        let data = Data(text.utf8)
        #expect(OCLinEcoreSyntax.looksLikeOCLinEcore(text))
        #expect(ModelFormat.detect(data: data) == .oclinecore)
        #expect(await ModelFormatRegistry().handler(recognising: data)?.format == .oclinecore)
    }

    @Test("other text is not taken for OCLinEcore", arguments: [
        CompleteOCLFixtures.constraints, "package School { class Course {} }", "package school;\nclass Course {}",
        "package org.example.school\nclass Course {}", "import 'school.ecore'\npackage school\ncontext Course inv: true",
        "package school : sch = 'uri'", "plain text", "", "package school : = 'x' {",
    ])
    func otherTextIsNotRecognised(text: String) {
        #expect(!OCLinEcoreSyntax.looksLikeOCLinEcore(text))
        #expect(ModelFormat.detect(data: Data(text.utf8)) != .oclinecore)
    }

    @Test("KM3, Emfatic and Xcore documents keep their formats")
    func otherTextFormatsKeepTheirFormats() {
        #expect(ModelFormat.detect(data: Data("package School {\n class Course {}\n}".utf8)) == .km3)
        #expect(ModelFormat.detect(data: Data("package school;\nclass Course {}".utf8)) == .emfatic)
        #expect(ModelFormat.detect(data: Data("package school\nclass Course {}".utf8)) == .xcore)
    }

    @Test("the OCLinEcore handler is a writable metamodel handler of specific priority")
    func handlerIsDescribed() async throws {
        let handler = try #require(await ModelFormatRegistry().handler(for: .oclinecore))
        #expect(handler.role == .metamodel)
        #expect(handler.priority == .specific)
        #expect(handler is any WritableModelFormatHandler)
    }

    @Test("an OCLinEcore document loads through ModelIO with its constraints")
    func oclinecoreLoads() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("school.oclinecore")
        try OCLinEcoreFixtures.school.write(to: url, atomically: testWritesAtomically, encoding: .utf8)
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(url: url, resourceSet: resourceSet)
        let direct = OCLinEcoreReader.parse(
            OCLinEcoreFixtures.school, sourceName: URIReference.canonicalise(url.absoluteString))
        #expect(loaded.format == .oclinecore)
        #expect(loaded.formatIdentifier == "oclinecore")
        #expect(MetamodelSummary.describe(loaded.packages) == MetamodelSummary.describe(direct.packages))
        #expect(await loaded.resource.loadDiagnostics == direct.diagnostics)
        let course = try #require(loaded.packages.first?.getEClass("Course"))
        #expect(OCLConstraintAnnotations.invariants(of: course).map(\.name) == ["HasCapacity", "NotOverfull"])
        #expect(await resourceSet.getMetamodel(uri: "http://example.org/school")?.name == "school")
    }

    @Test("an OCLinEcore document is written as OCLinEcoreWriter writes it and read back")
    func oclinecoreRoundTrips() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = try await ModelIO.load(
            data: Data(OCLinEcoreFixtures.school.utf8), uri: "memory:/school", resourceSet: ResourceSet())
        var diagnostics = ConversionDiagnostics()
        let text = try await ModelIO.serialise(loaded.resource, format: .oclinecore, diagnostics: &diagnostics)
        #expect(text == OCLinEcoreWriter.write(loaded.packages).text)
        let url = directory.appendingPathComponent("copy.oclinecore")
        try await ModelIO.save(loaded.resource, to: url)
        let reloaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        #expect(MetamodelSummary.describe(reloaded.packages) == MetamodelSummary.describe(loaded.packages))
        let ecore = directory.appendingPathComponent("copy.ecore")
        try await ModelIO.save(reloaded.resource, to: ecore)
        let fromEcore = try await ModelIO.load(url: ecore, resourceSet: ResourceSet())
        let course = try #require(fromEcore.packages.first?.getEClass("Course"))
        #expect(OCLConstraintAnnotations.invariants(of: course).map(\.name) == ["HasCapacity", "NotOverfull"])
    }

    @Test("an import of a registered metamodel resolves to its classifiers")
    func importsResolveRegisteredMetamodels() async throws {
        let resourceSet = ResourceSet()
        _ = try await ModelIO.load(
            data: Data("package shared : sh = 'http://example.org/shared' { class Person; }".utf8),
            uri: "memory:/shared.oclinecore", resourceSet: resourceSet)
        let text = """
            import sh : 'http://example.org/shared';
            package school : sch = 'http://example.org/school'
            {
            \tclass Teacher extends sh::Person;
            }
            """
        let loaded = try await ModelIO.load(data: Data(text.utf8), uri: "memory:/school.oclinecore", resourceSet: resourceSet)
        let errors = await loaded.resource.loadDiagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map(\.message))")
        let teacher = try #require(loaded.packages.first?.getEClass("Teacher"))
        #expect(teacher.eSuperTypes.map(\.name) == ["Person"])
    }

    @Test("a binary document is refused")
    func binaryIsRefused() async {
        await #expect(throws: ModelFormatError.undetectableFormat("memory:/school.oclinecore")) {
            try await ModelIO.load(
                data: Data([0x00, 0x01]) + Data(OCLinEcoreFixtures.school.utf8), uri: "memory:/school.oclinecore",
                format: .oclinecore, resourceSet: ResourceSet())
        }
    }
}
