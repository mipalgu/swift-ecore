//
// OCLReferenceCorpusTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import OCL
import Testing

@testable import ECore

/// The environment that selects the OCL reference corpus.
enum OCLCorpusEnvironment {
    /// The environment variable that names the corpus directory.
    static let variable = "OCL_REFERENCE_DIR"

    /// The corpus directory, if the variable is set.
    static var directory: String? { ProcessInfo.processInfo.environment[variable] }
}

/// Reads every OCLinEcore and Complete OCL document below the directory named by the
/// `OCL_REFERENCE_DIR` environment variable and reports how far each one is read,
/// round-tripped and applied. The suite is skipped when the variable is not set.
@Suite("OCL reference corpus", .enabled(if: OCLCorpusEnvironment.directory != nil))
struct OCLReferenceCorpusTests {
    /// The directory of the corpus.
    static var directory: URL { URL(fileURLWithPath: OCLCorpusEnvironment.directory ?? "") }

    /// The files below a directory with an extension, sorted.
    static func files(below directory: URL, extension pathExtension: String) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        var result: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isFile, url.pathExtension == pathExtension { result.append(url) }
        }
        return result.sorted { $0.path < $1.path }
    }

    /// Shortens a path to its location within the corpus.
    static func relative(_ url: URL) -> String {
        String(url.path.dropFirst(directory.path.count))
    }

    @Test("OCLinEcore documents are read and round-tripped")
    func oclinecore() async throws {
        var valid = 0
        var roundTrips = 0
        let files = Self.files(below: Self.directory, extension: OCLinEcoreSyntax.fileExtension)
        for url in files {
            let loaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
            let errors = await loaded.resource.loadDiagnostics.filter { $0.severity == .error }
            if errors.isEmpty { valid += 1 }
            var diagnostics = ConversionDiagnostics()
            let written = try? await ModelIO.serialise(loaded.resource, format: .oclinecore, diagnostics: &diagnostics)
            let reread = OCLinEcoreReader.parse(written ?? "")
            let same = MetamodelSummary.describe(reread.packages) == MetamodelSummary.describe(loaded.packages)
            if same && reread.isValid { roundTrips += 1 }
            print("CORPUS oclinecore \(Self.relative(url)): errors \(errors.count), round trip \(same && reread.isValid ? "same" : "differs")")
        }
        print("CORPUS oclinecore total: \(files.count) files, \(valid) without errors, \(roundTrips) round-tripped")
        #expect(files.count > 0)
    }

    @Test("Complete OCL documents are read and applied to their metamodels")
    func completeOCL() async throws {
        var valid = 0
        var applied = 0
        let files = Self.files(below: Self.directory, extension: CompleteOCLSyntax.fileExtension)
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = CompleteOCLReader.parse(text, sourceName: url.lastPathComponent)
            if parsed.isValid { valid += 1 }
            let folder = url.deletingLastPathComponent()
            var candidates = [url.deletingPathExtension().appendingPathExtension(ModelFormat.ecore.fileExtension)]
            for anImport in parsed.document.imports {
                let name = URL(fileURLWithPath: anImport.target).lastPathComponent
                if name.hasSuffix("." + ModelFormat.ecore.fileExtension) { candidates.append(folder.appendingPathComponent(name)) }
            }
            let resourceSet = ResourceSet()
            var resources: [Resource] = []
            for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
                if let loaded = try? await ModelIO.load(url: candidate, resourceSet: resourceSet),
                    !resources.contains(where: { $0.uri == loaded.resource.uri })
                {
                    resources.append(loaded.resource)
                }
            }
            var summary = ""
            if !resources.isEmpty {
                let application = try await ModelIO.applyCompleteOCL(at: url, to: resources, in: resourceSet)
                let unresolved = application.diagnostics.filter { $0.code == OCLDiagnosticCode.unresolvedContext }
                if unresolved.isEmpty { applied += 1 }
                summary = ", \(application.appliedCount) specifications applied, \(unresolved.count) unresolved"
            }
            print("CORPUS ocl \(Self.relative(url)): errors \(parsed.diagnostics.filter { $0.severity == .error }.count)\(summary)")
        }
        print("CORPUS ocl total: \(files.count) files, \(valid) without errors, \(applied) applied without unresolved contexts")
        #expect(files.count > 0)
    }
}
