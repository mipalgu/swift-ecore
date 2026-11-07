import EMFBase
import Foundation
import Testing

@testable import ECore

/// Reads every UML model of a reference directory, if one is given.
///
/// The test runs only if the environment variable `UML_REFERENCE_DIR` names a directory. Every
/// `.uml` file beneath it is read with the bundled UML metamodel, written in the Eclipse UML2
/// layout and read again. The files are only read, never changed or copied.
@Suite("UML reference corpus")
struct UMLReferenceCorpusTests {
    /// The environment variable that names the reference directory.
    static let variable = "UML_REFERENCE_DIR"

    /// The reference directory, if one is given.
    static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment[variable], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The `.uml` files beneath a directory, in sorted order.
    static func models(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == UMLFormat.fileExtension {
            urls.append(url)
        }
        return urls.sorted { $0.path < $1.path }
    }

    /// The number of objects of each class in a resource.
    static func classCounts(in resource: Resource) async -> [String: Int] {
        var counts: [String: Int] = [:]
        for object in await resource.getAllObjects() { counts[object.eClass.name, default: 0] += 1 }
        return counts
    }

    @Test("Every reference model reads and round-trips", .enabled(if: directory != nil))
    func readsReferenceModels() async throws {
        let directory = try #require(Self.directory)
        let models = Self.models(in: directory)
        #expect(!models.isEmpty)
        var failures: [String] = []
        var warnings: [String: Int] = [:]
        var untyped = 0
        var objects = 0
        for url in models {
            let name = url.path.replacingOccurrences(of: directory.path + "/", with: "")
            do {
                let read = try await UMLFormat.read(url: url, resourceSet: ResourceSet())
                for diagnostic in read.diagnostics { warnings[diagnostic.code, default: 0] += 1 }
                let counts = await Self.classCounts(in: read.resource)
                objects += counts.values.reduce(0, +)
                untyped += read.diagnostics.filter { $0.code == ModelDocumentDiagnostic.conversionWarning }.count
                let written = try await UMLFormat.write(read.resource, relativeTo: url)
                let reread = try await UMLFormat.read(
                    data: Data(written.text.utf8), uri: url.absoluteString + ".copy", resourceSet: ResourceSet())
                let rereadCounts = await Self.classCounts(in: reread.resource)
                if rereadCounts != counts {
                    let changed = Set(counts.keys).union(rereadCounts.keys).filter { counts[$0] != rereadCounts[$0] }
                        .sorted().map { "\($0): \(counts[$0] ?? 0) -> \(rereadCounts[$0] ?? 0)" }
                    failures.append("\(name): the round trip changed the objects (\(changed.joined(separator: ", ")))")
                }
            } catch {
                failures.append("\(name): \(error)")
            }
        }
        print("UML corpus: \(models.count) models, \(objects) objects, \(failures.count) failures, "
            + "diagnostics by code: \(warnings.sorted { $0.key < $1.key }), conversion warnings: \(untyped)")
        for failure in failures { print("UML corpus failure: \(failure)") }
        #expect(failures.isEmpty)
    }
}
