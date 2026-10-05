//
// URIReference.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// Helpers for splitting, resolving, and relativising resource URI references.
///
/// XMI documents refer to other documents with URI references that are usually
/// relative to the referring document (`../model/Library.ecore#//Book`). This
/// type converts between such relative references and absolute URIs, so that
/// the parser can locate target resources and the serialiser can write the
/// same relative form that EMF writes.
///
/// All operations work on the textual form of the URI and do not touch the
/// file system, so they behave identically on every platform.
public enum URIReference {
    /// The scheme (with its separator) of file URIs.
    private static let fileScheme = "file:"

    /// The components of a hierarchical URI.
    private struct Components {
        /// The scheme including its separator (for example `file:`), or an empty string.
        var scheme: String
        /// The authority including its leading slashes (for example `//host`), or an empty string.
        var authority: String
        /// The path component.
        var path: String
    }

    /// Splits a reference into its resource URI and fragment.
    ///
    /// The fragment is everything after the first `#`. A reference without `#`
    /// has no fragment.
    ///
    /// - Parameter reference: A reference such as `library.ecore#//Book`.
    /// - Returns: The resource URI (possibly empty for a same-document reference)
    ///   and the fragment without its leading `#`, or `nil` if there was none.
    public static func split(_ reference: String) -> (uri: String, fragment: String?) {
        guard let separator = reference.firstIndex(of: CrossReferenceSyntax.fragmentSeparator) else {
            return (reference, nil)
        }
        return (
            String(reference[..<separator]),
            String(reference[reference.index(after: separator)...])
        )
    }

    /// Resolves a possibly relative reference against a base URI.
    ///
    /// Absolute references (those with a scheme) are returned unchanged. Other
    /// references are interpreted relative to the directory of `base`, with `.` and
    /// `..` path segments removed.
    ///
    /// - Parameters:
    ///   - reference: The relative or absolute resource URI (without fragment).
    ///   - base: The URI of the referring resource.
    /// - Returns: The absolute URI of the referenced resource.
    public static func resolve(_ reference: String, against base: String) -> String {
        if reference.isEmpty { return base }
        if hasScheme(reference) || driveLength(of: reference) > 0 { return reference }

        var baseComponents = components(of: base)
        let referencePath: String
        if reference.hasPrefix("/") {
            referencePath = reference
        } else {
            let directory = baseComponents.path.lastIndex(of: "/").map {
                String(baseComponents.path[...$0])
            } ?? "/"
            referencePath = directory + reference
        }
        baseComponents.path = normalise(path: referencePath)
        return baseComponents.scheme + baseComponents.authority + baseComponents.path
    }

    /// Reduces a file URI to its canonical textual form.
    ///
    /// Empty path segments (`//`) and `.` and `..` segments are removed and a Windows drive
    /// letter is upper-cased, so that different spellings of the same file produce the same
    /// text. URIs with any other scheme, and text that is not a URI, are returned unchanged.
    ///
    /// - Parameter uri: The URI text.
    /// - Returns: The canonical form of a file URI, or `uri` itself.
    public static func canonicalise(_ uri: String) -> String {
        var parts = components(of: uri)
        guard parts.scheme.lowercased() == fileScheme, parts.path.hasPrefix("/") else { return uri }
        parts.path = normalise(path: parts.path)
        return fileScheme + parts.authority + parts.path
    }

    /// Expresses a target URI relative to a base URI where possible.
    ///
    /// The result is the shortest relative path from the directory of `base` to
    /// `target` (for example `Library.ecore` or `../../ecore/Ecore.genmodel`), as EMF
    /// writes it. If the URIs differ in scheme or authority, or either has no
    /// hierarchical path, the target is returned unchanged.
    ///
    /// - Parameters:
    ///   - target: The absolute URI of the referenced resource.
    ///   - base: The absolute URI of the referring resource.
    /// - Returns: The relative reference, or `target` if it cannot be relativised.
    public static func relativise(_ target: String, against base: String) -> String {
        let targetComponents = components(of: target)
        let baseComponents = components(of: base)
        guard targetComponents.scheme == baseComponents.scheme,
            targetComponents.authority == baseComponents.authority,
            targetComponents.path.hasPrefix("/"), baseComponents.path.hasPrefix("/")
        else {
            return target
        }

        guard driveDesignator(of: targetComponents.path) == driveDesignator(of: baseComponents.path)
        else { return target }

        let targetSegments = targetComponents.path.split(
            separator: "/", omittingEmptySubsequences: true
        ).map(String.init)
        var baseDirectory = baseComponents.path.split(
            separator: "/", omittingEmptySubsequences: true
        ).map(String.init)
        if !baseComponents.path.hasSuffix("/") { baseDirectory.removeLast(min(1, baseDirectory.count)) }
        guard let targetName = targetSegments.last else { return target }
        let targetDirectory = Array(targetSegments.dropLast())

        var common = 0
        while common < baseDirectory.count, common < targetDirectory.count,
            baseDirectory[common] == targetDirectory[common]
        {
            common += 1
        }
        let ascents = Array(repeating: CrossReferenceSyntax.parentDirectory, count: baseDirectory.count - common)
        let descents = Array(targetDirectory.dropFirst(common))
        return (ascents + descents + [targetName]).joined(separator: "/")
    }

    /// Whether the reference starts with a URI scheme.
    ///
    /// - Parameter reference: The text to check.
    /// - Returns: `true` if the text begins with `scheme:`. A single letter followed by a colon
    ///   is a Windows drive designator rather than a scheme.
    private static func hasScheme(_ reference: String) -> Bool {
        guard let colon = reference.firstIndex(of: ":") else { return false }
        let scheme = reference[..<colon]
        guard scheme.count > 1 else { return false }
        guard let first = scheme.first, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isLetter || $0.isNumber || "+-.".contains($0) }
    }

    /// Splits a URI into scheme, authority, and path.
    ///
    /// - Parameter uri: The URI text.
    /// - Returns: The components; a URI without scheme is treated as a bare path.
    private static func components(of uri: String) -> Components {
        var remainder = Substring(uri)
        var scheme = ""
        if hasScheme(uri), let colon = remainder.firstIndex(of: ":") {
            scheme = String(remainder[...colon])
            remainder = remainder[remainder.index(after: colon)...]
        }
        var authority = ""
        if remainder.hasPrefix("//") {
            let afterSlashes = remainder.dropFirst(2)
            let end = afterSlashes.firstIndex(of: "/") ?? afterSlashes.endIndex
            authority = "//" + afterSlashes[..<end]
            remainder = afterSlashes[end...]
        }
        return Components(scheme: scheme, authority: authority, path: String(remainder))
    }

    /// Removes `.` and `..` segments from an absolute path.
    ///
    /// - Parameter path: The absolute path.
    /// - Returns: The normalised path, preserving a trailing slash.
    private static func normalise(path: String) -> String {
        let driveCount = driveLength(of: path)
        let drive = driveCount > 0 ? String(path.prefix(driveCount)).uppercased() : ""
        let rest = path.dropFirst(driveCount)
        var output: [Substring] = []
        for segment in rest.split(separator: "/", omittingEmptySubsequences: true) {
            if segment == "." { continue }
            if segment == Substring(CrossReferenceSyntax.parentDirectory) {
                if !output.isEmpty { output.removeLast() }
            } else {
                output.append(segment)
            }
        }
        let root = drive.isEmpty ? "/" : drive + "/"
        return root + output.joined(separator: "/") + (path.hasSuffix("/") && !output.isEmpty ? "/" : "")
    }

    /// The length of a leading Windows drive designator in a path.
    ///
    /// Recognises `C:` and `/C:` when followed by a slash or the end of the path.
    ///
    /// - Parameter path: The path or reference text.
    /// - Returns: The number of characters of the designator, or zero if there is none.
    private static func driveLength(of path: String) -> Int {
        let characters = Array(path.prefix(4))
        let offset = characters.first == "/" ? 1 : 0
        guard characters.count >= offset + 2, characters[offset].isASCII, characters[offset].isLetter,
            characters[offset + 1] == ":"
        else { return 0 }
        if characters.count > offset + 2, characters[offset + 2] != "/" { return 0 }
        return offset + 2
    }

    /// The upper-cased drive designator of a path, or an empty string.
    ///
    /// - Parameter path: The path text.
    /// - Returns: The designator without any leading slash, such as `C:`.
    private static func driveDesignator(of path: String) -> String {
        let count = driveLength(of: path)
        guard count > 0 else { return "" }
        return String(path.prefix(count).drop { $0 == "/" }).uppercased()
    }
}
