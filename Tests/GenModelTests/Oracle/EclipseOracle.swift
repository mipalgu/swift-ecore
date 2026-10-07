//
// EclipseOracle.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// Locates reference documents written by the Eclipse Modeling Framework.
///
/// The reference documents are never part of this package. The tests that use them run only
/// when the environment variable named by ``variable`` points at a checkout of the
/// framework's sources.
enum EclipseOracle {
    /// The environment variable that names the root of the reference checkout.
    static let variable = "EMF_REFERENCE_ROOT"

    /// The environment variable that names a directory to receive the output of failed comparisons.
    static let outputVariable = "EMF_ORACLE_OUTPUT"

    /// The root of the reference checkout, if configured and present.
    static var root: URL? {
        guard let path = ProcessInfo.processInfo.environment[variable], !path.isEmpty else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The explanation shown when the reference checkout is not configured.
    static let skipNotice =
        "Eclipse oracle tests skipped: set \(variable) to a checkout of the reference sources"

    /// Whether the reference checkout is available.
    static var isAvailable: Bool {
        if root == nil { print(skipNotice) }
        return root != nil
    }

    /// Lists the regular files with a given extension under the reference root.
    ///
    /// - Parameter fileExtension: The path extension, without the dot.
    /// - Returns: The relative paths, sorted.
    static func files(withExtension fileExtension: String) -> [String] {
        guard let root else { return [] }
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        var result: [String] = []
        for case let url as URL in enumerator where url.pathExtension == fileExtension {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            result.append(relative)
        }
        return result.sorted()
    }

    /// Normalises line endings to line feeds.
    static func normalised(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
    }

    /// Records the output of a failed comparison, if an output directory is configured.
    static func recordFailure(_ text: String, for relativePath: String) {
        guard let path = ProcessInfo.processInfo.environment[outputVariable], !path.isEmpty else {
            return
        }
        let name = relativePath.replacingOccurrences(of: "/", with: "__")
        try? FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true)
        try? text.write(toFile: path + "/" + name, atomically: testWritesAtomically, encoding: .utf8)
    }
}
