//
// EmfaticCorpusTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore


/// The environment variable that names a directory of Emfatic documents to test against.
private let corpusVariable = "EMFATIC_REFERENCE_DIR"

/// Reads every Emfatic document of an external corpus, when one is configured.
///
/// The corpus is not part of the package. Set `EMFATIC_REFERENCE_DIR` to a directory of
/// `.emf` files to run these tests; each document must read without crashing, and each
/// document that reads without errors must survive writing and reading again with the
/// same structure.
@Suite("Emfatic corpus", .enabled(if: ProcessInfo.processInfo.environment[corpusVariable] != nil))
struct EmfaticCorpusTests {
    /// Reads, writes and reads again every document of the corpus.
    @Test func corpusRoundTrips() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment[corpusVariable]))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == EmfaticLanguage.fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!files.isEmpty)
        var clean = 0
        var withErrors: [String] = []
        var lossy = 0
        var stable = 0
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let result = EmfaticReader.parse(text, sourceName: file.lastPathComponent)
            guard !result.hasErrors else {
                let first = result.diagnostics.first { $0.severity == .error }
                withErrors.append("\(file.lastPathComponent): \(first?.message ?? "") at \(first?.range?.start.line ?? 0)")
                continue
            }
            clean += 1
            let written = EmfaticWriter.write(result.packages)
            if !written.diagnostics.isEmpty { lossy += 1 }
            let again = EmfaticReader.parse(written.text)
            let expected = written.diagnostics.isEmpty ? [] : [EmfaticDiagnosticCode.unresolvedType.rawValue]
            let unexpected = again.diagnostics.filter { $0.severity == .error && !expected.contains($0.code) }
            #expect(unexpected.isEmpty, "\(file.lastPathComponent): \(unexpected.map(\.message))")
            #expect(
                MetamodelSignature.of(again.packages) == MetamodelSignature.of(result.packages),
                "\(file.lastPathComponent) changed in a round trip")
            if EmfaticWriter.write(again.packages).text == written.text { stable += 1 }
        }
        print("Emfatic corpus: \(files.count) files, \(clean) without errors, \(withErrors.count) with errors, "
            + "\(lossy) with lossy writes, \(stable) with stable canonical text")
        for entry in withErrors { print("  error: \(entry)") }
        #expect(stable == clean)
    }
}
