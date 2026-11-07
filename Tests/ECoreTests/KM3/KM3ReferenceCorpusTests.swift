//
// KM3ReferenceCorpusTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

/// The location of the reference corpus.
enum KM3Corpus {
    /// The directory of the corpus, if the environment variable `KM3_REFERENCE_DIR` names one.
    static let directory: URL? = ProcessInfo.processInfo.environment["KM3_REFERENCE_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }
}

/// Tests against a corpus of KM3 documents that is not part of the package.
///
/// The tests run only when the environment variable `KM3_REFERENCE_DIR` names a directory;
/// every `.km3` file below it is read. When a `.ecore` file of the same name exists below
/// the directory, the packages read from the KM3 document are compared with it and the
/// differences are printed.
@Suite("Reference corpus", .enabled(if: KM3Corpus.directory != nil))
struct KM3ReferenceCorpusTests {
    /// The files below the corpus directory with an extension.
    ///
    /// - Parameter fileExtension: The extension, without the dot.
    /// - Returns: The files, sorted by path.
    static func files(withExtension fileExtension: String) -> [URL] {
        guard let directory = KM3Corpus.directory,
            let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == fileExtension }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.path < $1.path }
    }

    @Test("Every KM3 document of the corpus reads without errors and round-trips")
    func corpus() throws {
        let files = Self.files(withExtension: KM3Format.fileExtension)
        #expect(!files.isEmpty)
        var report: [String] = []
        for file in files {
            let text = try readText(at: file)
            let result = KM3Reader.parse(text, sourceName: file.lastPathComponent)
            let errors = result.diagnostics.filter { $0.severity == .error }
            let warnings = result.diagnostics.filter { $0.severity == .warning }
            #expect(errors.isEmpty, "\(file.lastPathComponent): \(errors)")
            #expect(KM3Syntax.looksLikeKM3(text), "\(file.lastPathComponent)")
            let written = KM3Writer.write(result.packages)
            let reread = KM3Reader.parse(written.text)
            #expect(!reread.hasErrors, "\(file.lastPathComponent): \(reread.diagnostics)")
            #expect(KM3Structure.describe(reread.packages) == KM3Structure.describe(result.packages))
            #expect(KM3Writer.write(reread.packages).text == written.text)
            let classes = result.packages.reduce(0) { $0 + countClasses($1) }
            report.append(
                "\(file.lastPathComponent): \(result.packages.count) packages, \(classes) classes, "
                    + "\(errors.count) errors, \(warnings.count) warnings \(warnings.map(\.message)), "
                    + "\(written.diagnostics.count) writer warnings")
        }
        print("KM3 corpus (\(files.count) files):\n" + report.joined(separator: "\n"))
    }

    /// The number of classes in a package and its subpackages.
    ///
    /// - Parameter package: The package.
    /// - Returns: The number of classes.
    func countClasses(_ package: EPackage) -> Int {
        package.eClassifiers.filter { $0 is EClass }.count + package.eSubpackages.reduce(0) { $0 + countClasses($1) }
    }

    /// The number of trailing folder names that two files share.
    ///
    /// - Parameters:
    ///   - first: The first file.
    ///   - second: The second file.
    /// - Returns: How many folders, counted from the files upwards, have the same names.
    func sharedFolders(_ first: URL, _ second: URL) -> Int {
        let left = first.deletingLastPathComponent().pathComponents.reversed()
        let right = second.deletingLastPathComponent().pathComponents.reversed()
        return zip(left, right).prefix { $0 == $1 }.count
    }

    /// The number of references of packages for which a property is set.
    ///
    /// - Parameters:
    ///   - property: The optional property of a reference.
    ///   - packages: The packages.
    /// - Returns: How many references have the property.
    func count(_ property: KeyPath<EReference, EUUID?>, in packages: [EPackage]) -> Int {
        packages.reduce(0) { total, package in
            total + package.eClassifiers.compactMap { $0 as? EClass }.flatMap(\.eReferences)
                .filter { $0[keyPath: property] != nil }.count + count(property, in: package.eSubpackages)
        }
    }

    @Test("KM3 documents are compared with Ecore documents of the same name")
    func compareWithEcore() async throws {
        let ecores = Self.files(withExtension: "ecore")
        for file in Self.files(withExtension: KM3Format.fileExtension) {
            let base = file.deletingPathExtension().lastPathComponent
            let candidates = ecores.filter { $0.deletingPathExtension().lastPathComponent == base }
            guard let ecore = candidates.max(by: { sharedFolders(file, $0) < sharedFolders(file, $1) }) else {
                continue
            }
            let options = KM3ReadOptions.declaredDataTypes
            let fromKM3 = KM3Reader.parse(try readText(at: file), sourceName: nil, options: options).packages
            let reference: [EPackage]
            do {
                reference = try await ModelIO.registerMetamodels(
                    at: [ecore], in: ResourceSet(), options: EcoreLoadOptions(tolerant: true))
            } catch {
                print("Skipping \(ecore.lastPathComponent), which swift-ecore cannot load: \(error)")
                continue
            }
            let mine = KM3Structure.describe(fromKM3, includingOpposites: false).split(separator: "\n").map(String.init)
            let theirs = KM3Structure.describe(reference, includingOpposites: false).split(separator: "\n")
                .map(String.init)
            let opposites = (count(\.opposite, in: fromKM3), count(\.opposite, in: reference))
            print("Opposites: \(opposites.0) from KM3, \(opposites.1) loaded from Ecore")
            let missing = theirs.filter { !mine.contains($0) }
            let extra = mine.filter { !theirs.contains($0) }
            let location = ecore.path.replacingOccurrences(of: KM3Corpus.directory?.path ?? "", with: "")
            print(
                "Comparing \(file.lastPathComponent) (declared mapping) with \(location): "
                    + "\(theirs.count) reference lines, \(missing.count) only in Ecore, \(extra.count) only from KM3")
            for line in missing { print("  ecore: \(line)") }
            for line in extra { print("  km3:   \(line)") }
        }
    }
}
