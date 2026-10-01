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
        if hasScheme(reference) { return reference }

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
    /// - Returns: `true` if the text begins with `scheme:`.
    private static func hasScheme(_ reference: String) -> Bool {
        guard let colon = reference.firstIndex(of: ":") else { return false }
        let scheme = reference[..<colon]
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
        var output: [Substring] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            if segment == "." { continue }
            if segment == Substring(CrossReferenceSyntax.parentDirectory) {
                if !output.isEmpty { output.removeLast() }
            } else {
                output.append(segment)
            }
        }
        return "/" + output.joined(separator: "/") + (path.hasSuffix("/") && !output.isEmpty ? "/" : "")
    }
}
