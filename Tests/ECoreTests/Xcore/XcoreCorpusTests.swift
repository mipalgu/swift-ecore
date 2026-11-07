//
// XcoreCorpusTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// The environment variable that names a directory tree of Xcore documents to test against.
private let corpusVariable = "XCORE_REFERENCE_DIR"

/// The file extension of Xcore validation test documents.
private let validationExtension = "xcore_test"

/// Reads every Xcore document below an external directory, when one is configured.
///
/// The corpus is not part of the package. Set `XCORE_REFERENCE_DIR` to a directory that
/// holds `.xcore` or `.xcore_test` files, at any depth, to run these tests; each document
/// must read without crashing, and each document that reads without errors must survive
/// writing and reading again with the same structure.
@Suite("Xcore corpus", .enabled(if: ProcessInfo.processInfo.environment[corpusVariable] != nil))
struct XcoreCorpusTests {
    /// Reads, writes and reads again every document of the corpus.
    @Test func corpusRoundTrips() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment[corpusVariable]))
        let enumerator = try #require(
            FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]))
        var files: [URL] = []
        for case let file as URL in enumerator
        where [XcoreLanguage.fileExtension, validationExtension].contains(file.pathExtension)
            && (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        {
            files.append(file)
        }
        files.sort { $0.path < $1.path }
        #expect(!files.isEmpty)
        let options = MetamodelSignature.Options(ignoresSingleValuedCollectionFlags: true)
        var clean = 0
        var stable = 0
        var report: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let result = XcoreReader.parse(text, sourceName: file.lastPathComponent)
            let errors = result.diagnostics.filter { $0.severity == .error }
            guard errors.isEmpty else {
                report.append("  \(file.lastPathComponent): \(errors.count) error(s), first: \(errors[0].message)")
                continue
            }
            clean += 1
            let written = XcoreWriter.write(result.packages)
            let again = XcoreReader.parse(written.text)
            #expect(!again.hasErrors, "\(file.lastPathComponent): \(again.diagnostics.map(\.message))")
            #expect(
                MetamodelSignature.of(again.packages, options: options)
                    == MetamodelSignature.of(result.packages, options: options),
                "\(file.lastPathComponent) changed in a round trip")
            if XcoreWriter.write(again.packages).text == written.text { stable += 1 }
            report.append("  \(file.lastPathComponent): clean, \(result.diagnostics.count) warning(s)")
        }
        print("Xcore corpus: \(files.count) files, \(clean) without errors, \(stable) with stable canonical text")
        for line in report { print(line) }
        #expect(stable == clean)
    }
}
