//
// ModelFormatHandlerTestSupport.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

@testable import ECore

/// The vocabulary of the sketch format, a tiny text metamodel format used to test format handlers.
///
/// A sketch document starts with a package line and lists one class per line:
///
/// ```
/// sketch package shapes http://example.org/shapes shp
/// class Shape
/// abstract class Circle
/// ```
///
/// A line `warn <text>` produces a warning, and any other line an error.
enum SketchSyntax {
    /// The identifier and file extension of the format.
    static let identifier = "sketch"

    /// The name of the format as written in prose.
    static let name = "Sketch"

    /// The keyword that starts every sketch document.
    static let documentKeyword = "sketch package"

    /// The keyword of a class line.
    static let classKeyword = "class"

    /// The keyword of an abstract class line.
    static let abstractKeyword = "abstract"

    /// The keyword of a line that produces a warning.
    static let warningKeyword = "warn"

    /// The code of the diagnostic for a line that is not understood.
    static let unknownLine = "sketch.unknownLine"

    /// The code of the diagnostic produced by a `warn` line.
    static let explicitWarning = "sketch.warning"

    /// The code of the warning that a classifier other than a class was not written.
    static let skippedClassifier = "sketch.skippedClassifier"

    /// The code of the error that a package without a name cannot be written.
    static let unnamedPackage = "sketch.unnamedPackage"
}

/// The result of parsing a sketch document, shaped like the result of a text format reader.
struct SketchParseResult {
    /// The packages of the document.
    var packages: [EPackage]

    /// The problems found while parsing.
    var diagnostics: [SourceDiagnostic]
}

/// Parses sketch documents.
enum SketchReader {
    /// Parses the text of a sketch document.
    ///
    /// - Parameters:
    ///   - text: The text of the document.
    ///   - sourceName: The name of the document, recorded in diagnostics.
    /// - Returns: The packages and diagnostics of the document.
    static func parse(_ text: String, sourceName: String?) -> SketchParseResult {
        var package: EPackage?
        var classes: [any EClassifier] = []
        var diagnostics: [SourceDiagnostic] = []
        let table = LineTable(text)
        var offset = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            defer { offset += line.utf8.count + 1 }
            let words = line.split(separator: " ").map(String.init)
            let range = SourceRange(
                start: table.position(forUTF8Offset: offset),
                end: table.position(forUTF8Offset: offset + line.utf8.count))
            if words.isEmpty { continue }
            if line.hasPrefix(SketchSyntax.documentKeyword), words.count == 5 {
                package = EPackage(name: words[2], nsURI: words[3], nsPrefix: words[4])
            } else if words.count == 2, words[0] == SketchSyntax.classKeyword {
                classes.append(EClass(name: words[1]))
            } else if words.count == 3, words[0] == SketchSyntax.abstractKeyword, words[1] == SketchSyntax.classKeyword {
                classes.append(EClass(name: words[2], isAbstract: true))
            } else if words[0] == SketchSyntax.warningKeyword {
                diagnostics.append(SourceDiagnostic(
                    severity: .warning, code: SketchSyntax.explicitWarning,
                    message: words.dropFirst().joined(separator: " "), range: range, document: sourceName))
            } else {
                diagnostics.append(SourceDiagnostic(
                    severity: .error, code: SketchSyntax.unknownLine, message: "Unknown line '\(line)'",
                    range: range, document: sourceName))
            }
        }
        guard var package else { return SketchParseResult(packages: [], diagnostics: diagnostics) }
        package.eClassifiers = classes
        return SketchParseResult(packages: [package], diagnostics: diagnostics)
    }
}

/// Writes sketch documents.
enum SketchWriter {
    /// Writes packages as a sketch document.
    ///
    /// - Parameter packages: The packages to write.
    /// - Returns: The text of the document and the problems found while writing it.
    static func write(_ packages: [EPackage]) -> (text: String, diagnostics: [SourceDiagnostic]) {
        var lines: [String] = []
        var diagnostics: [SourceDiagnostic] = []
        for package in packages {
            guard !package.name.isEmpty else {
                diagnostics.append(SourceDiagnostic(
                    severity: .error, code: SketchSyntax.unnamedPackage, message: "A package has no name"))
                continue
            }
            lines.append("\(SketchSyntax.documentKeyword) \(package.name) \(package.nsURI) \(package.nsPrefix)")
            for classifier in package.eClassifiers {
                guard let eClass = classifier as? EClass else {
                    diagnostics.append(SourceDiagnostic(
                        severity: .warning, code: SketchSyntax.skippedClassifier,
                        message: "The classifier '\(classifier.name)' is not a class and was left out"))
                    continue
                }
                let prefix = eClass.isAbstract ? "\(SketchSyntax.abstractKeyword) " : ""
                lines.append("\(prefix)\(SketchSyntax.classKeyword) \(eClass.name)")
            }
        }
        return (lines.joined(separator: "\n") + "\n", diagnostics)
    }
}

/// The handler with which sketch documents are read and written through ``ModelIO``.
struct SketchFormatHandler: WritableModelFormatHandler {
    var identifier: String { SketchSyntax.identifier }
    var name: String { SketchSyntax.name }
    var fileExtensions: [String] { [SketchSyntax.identifier] }
    var role: ModelFormatRole { .metamodel }

    func recognises(_ prefix: Data) -> Bool {
        guard let decoded = try? DecodedText(decoding: prefix) else { return false }
        let text = decoded.text.drop { $0 == "\u{FEFF}" || $0.isWhitespace }
        return text.hasPrefix(SketchSyntax.documentKeyword)
    }

    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        try readPackages(from: request) { text, sourceName in
            let result = SketchReader.parse(text, sourceName: sourceName)
            return (result.packages, result.diagnostics)
        }
    }

    func write(
        _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        try await writePackages(of: resource, relativeTo: documentURL, diagnostics: &diagnostics) {
            SketchWriter.write($0)
        }
    }
}

/// A sketch handler under another identifier and extension that can read but not write.
struct ReadOnlySketchFormatHandler: ModelFormatHandler {
    var identifier: String { "readonlysketch" }
    var name: String { "Read-only sketch" }
    var fileExtensions: [String] { ["rosketch"] }
    var role: ModelFormatRole { .metamodel }

    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        try await SketchFormatHandler().read(request)
    }
}

/// A handler that claims every XML document, with a configurable priority.
struct GreedyXMLFormatHandler: ModelFormatHandler {
    var identifier: String
    var name: String { "Greedy XML" }
    var fileExtensions: [String] { [] }
    var role: ModelFormatRole { .model }
    var priority: ModelFormatPriority

    /// Creates a greedy handler.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the handler.
    ///   - priority: The priority with which the handler examines documents.
    init(identifier: String = "greedy", priority: ModelFormatPriority) {
        self.identifier = identifier
        self.priority = priority
    }

    func recognises(_ prefix: Data) -> Bool {
        String(decoding: prefix, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
    }

    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        .resource(await request.resourceSet.createResource(uri: request.uri))
    }
}

/// A handler that recognises nothing and claims a file extension of a built-in format.
struct ExtensionOverrideFormatHandler: ModelFormatHandler {
    var identifier: String { "override" }
    var name: String { "Override" }
    var fileExtensions: [String] { ["XMI"] }
    var role: ModelFormatRole { .model }

    func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        .resource(await request.resourceSet.createResource(uri: request.uri))
    }
}
