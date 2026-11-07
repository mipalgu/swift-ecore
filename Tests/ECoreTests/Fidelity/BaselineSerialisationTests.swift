import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that every existing test document loads and is written exactly as before.
///
/// Each `.ecore`, `.xmi` and `.json` document of the test targets is loaded and written in
/// several ways: as legacy XMI, as EMF-style XMI, as wrapped EMF-style XMI, as JSON, and, for
/// metamodels, as the parsed object graph. The texts, together with the diagnostics of the
/// load and the writes, are compared with a manifest that was recorded before the XMI
/// dialects, EMOF and UML were supported. Setting the environment variable
/// `ECORE_BASELINE_RECORD` to a file path records a new manifest there instead.
@Suite("Baseline serialisation")
struct BaselineSerialisationTests {
    /// The environment variable that names the file to which a manifest is recorded.
    private static let recordVariable = "ECORE_BASELINE_RECORD"

    /// The placeholder that replaces the location of the test directory in recorded texts.
    private static let testsPlaceholder = "$TESTS"

    /// The extensions of the documents that are compared.
    private static let extensions: Set<String> = ["ecore", "xmi", "json"]

    /// The directories of recorded manifests and new fixtures, which are not inputs.
    private static let excludedDirectories = ["compatibility", "dialects"]

    /// The directory that holds the test targets.
    private static let testsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The recorded manifest.
    private static let manifestURL = testsDirectory
        .appendingPathComponent("ECoreTests/Resources/compatibility/baseline-serialisations.json")

    /// The ways in which a document is written.
    private enum Rendering: String, CaseIterable {
        case legacyXMI = "xmi-legacy"
        case emfXMI = "xmi-emf"
        case wrappedXMI = "xmi-emf-wrapped"
        case json = "json"
        case parsedGraph = "parsed-graph"
    }

    /// The documents of the test targets, relative to the test directory, in sorted order.
    private static func documents() throws -> [String] {
        let root = testsDirectory.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        var paths: [String] = []
        for case let path as String in enumerator {
            let url = URL(fileURLWithPath: path)
            guard extensions.contains(url.pathExtension),
                !excludedDirectories.contains(where: { path.contains("/Resources/\($0)/") })
            else { continue }
            paths.append(path)
        }
        return paths.sorted()
    }

    /// The pattern of the textual form of a UUID, which identifies objects of one process.
    private static let uuidPattern = "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"

    /// Replaces the location of the test directory in a text by a placeholder, and every
    /// UUID by a token numbered in the order of its first occurrence.
    private static func normalised(_ text: String) -> String {
        let directories = [testsDirectory.standardizedFileURL, testsDirectory.resolvingSymlinksInPath()]
        var prefixes: [String] = []
        for directory in directories {
            for path in [directory.path, "/private" + directory.path] {
                let url = URL(fileURLWithPath: path, isDirectory: true)
                prefixes += [url.absoluteString, "file://" + path + "/", path + "/"]
            }
        }
        var result = text
        for prefix in Set(prefixes).sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: prefix, with: testsPlaceholder + "/")
        }
        var tokens: [String: String] = [:]
        while let range = result.range(of: uuidPattern, options: .regularExpression) {
            let uuid = String(result[range])
            let token = tokens[uuid] ?? "<uuid-\(tokens.count + 1)>"
            tokens[uuid] = token
            result.replaceSubrange(range, with: token)
        }
        return result
    }

    /// Renders a document in every way, keyed by `path|rendering`.
    private static func renderings(of path: String) async -> [String: String] {
        let url = testsDirectory.appendingPathComponent(path)
        var results: [String: String] = [:]
        let resourceSet = ResourceSet()
        let loaded: ModelIO.Loaded
        do {
            loaded = try await ModelIO.load(url: url, resourceSet: resourceSet)
        } catch {
            results["\(path)|load"] = "error: \(error)"
            return results
        }
        let loadDiagnostics = await loaded.resource.loadDiagnostics
        results["\(path)|load"] = normalised(
            "format: \(loaded.format)\npackages: \(loaded.packages.map(\.name))\n"
                + "diagnostics: \(loaded.diagnostics.warnings.map(\.description))\n"
                + "load: \(loadDiagnostics.map { "\($0.severity) \($0.code) \($0.message)" })")
        let writes: [(Rendering, ModelFormat, XMISerializationOptions)] = [
            (.legacyXMI, .xmi, .legacy), (.emfXMI, .xmi, .emf), (.wrappedXMI, .xmi, .emfWrapped),
            (.json, .json, .legacy),
        ]
        for (rendering, format, options) in writes {
            var diagnostics = ConversionDiagnostics()
            do {
                let text = try await ModelIO.serialise(
                    loaded.resource, format: format, relativeTo: url, xmiOptions: options, diagnostics: &diagnostics)
                results["\(path)|\(rendering.rawValue)"] = normalised(
                    text + "\n--\n" + diagnostics.warnings.map(\.description).joined(separator: "\n"))
            } catch {
                results["\(path)|\(rendering.rawValue)"] = normalised("error: \(error)")
            }
        }
        if url.pathExtension == ModelFormat.ecore.fileExtension {
            do {
                let resource = try await XMIParser().parse(url)
                let text = try await XMISerializer().serialize(resource)
                results["\(path)|\(Rendering.parsedGraph.rawValue)"] = normalised(text)
            } catch {
                results["\(path)|\(Rendering.parsedGraph.rawValue)"] = normalised("error: \(error)")
            }
        }
        return results
    }

    /// Renders every document of the test targets.
    private static func allRenderings(of paths: [String]) async -> [String: String] {
        var results: [String: String] = [:]
        for path in paths {
            results.merge(await renderings(of: path)) { first, _ in first }
        }
        return results
    }

    @Test("Every existing document is written exactly as before")
    func existingDocumentsAreUnchanged() async throws {
        if let target = ProcessInfo.processInfo.environment[Self.recordVariable], !target.isEmpty {
            let recorded = await Self.allRenderings(of: try Self.documents())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(recorded).write(to: URL(fileURLWithPath: target))
            return
        }
        let manifest = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: Self.manifestURL))
        let paths = Set(manifest.keys.compactMap { $0.split(separator: "|").first.map(String.init) })
        #expect(!paths.isEmpty)
        for path in paths.sorted() {
            #expect(FileManager.default.fileExists(atPath: Self.testsDirectory.appendingPathComponent(path).path),
                "\(path) is missing")
        }
        let current = await Self.allRenderings(of: paths.sorted())
        #expect(Set(current.keys) == Set(manifest.keys))
        for key in manifest.keys.sorted() {
            #expect(current[key] == manifest[key], "\(key) differs from the baseline")
        }
    }
}
