//
// SDF3CorpusTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// An opt-in test over a directory of published SDF3 definitions and Stratego signatures.
///
/// Set the environment variable `SDF3_REFERENCE_DIR` to a directory that holds
/// `.sdf3` and `.str` files. Every file is read, its package is validated, and
/// a summary is printed.
@Suite("SDF3 corpus")
struct SDF3CorpusTests {
    /// The environment variable that names the corpus directory.
    static let directoryVariable = "SDF3_REFERENCE_DIR"

    /// The corpus directory, if the environment names one.
    static var directory: URL? {
        ProcessInfo.processInfo.environment[directoryVariable].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Reads every file of the corpus and checks that the packages validate.
    @Test(.enabled(if: directory != nil, "Set SDF3_REFERENCE_DIR to run the corpus test"))
    func corpus() throws {
        let directory = try #require(Self.directory)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["sdf3", "str"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!files.isEmpty)
        var totals = (files: 0, sorts: 0, classes: 0, dataTypes: 0, errors: 0, warnings: 0)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let result = SDF3Reader.parse(text, sourceName: file.lastPathComponent)
            let classes = result.packages.flatMap(\.eClassifiers).compactMap { $0 as? EClass }
            let sorts = classes.filter(\.isAbstract).count
            let dataTypes = result.packages.flatMap(\.eClassifiers).filter { $0 is EDataType }.count
            let errors = result.diagnostics.filter { $0.severity == .error }
            let warnings = result.diagnostics.filter { $0.severity == .warning }
            let validation = EcoreValidator().validate(MetamodelIndex(roots: result.packages))
                .filter { $0.severity == .error }
            #expect(validation.isEmpty, "\(file.lastPathComponent): \(validation.map(\.message))")
            print(
                "\(file.lastPathComponent): \(sorts) sorts, \(classes.count - sorts) constructor classes, "
                    + "\(dataTypes) data types, \(errors.count) errors, \(warnings.count) warnings")
            for diagnostic in errors + warnings {
                let line = diagnostic.range?.start.line ?? 0
                print("  \(line): \(diagnostic.code) \(diagnostic.message)")
            }
            totals.files += 1
            totals.sorts += sorts
            totals.classes += classes.count
            totals.dataTypes += dataTypes
            totals.errors += errors.count
            totals.warnings += warnings.count
        }
        print(
            "SDF3 corpus: \(totals.files) files, \(totals.sorts) sorts, \(totals.classes) classes, "
                + "\(totals.dataTypes) data types, \(totals.errors) errors, \(totals.warnings) warnings")
    }
}
