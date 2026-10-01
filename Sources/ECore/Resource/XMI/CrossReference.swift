//
// CrossReference.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// A parsed XMI reference to an object in the same or another document.
///
/// EMF writes the value of a non-containment reference attribute as one or more
/// space-separated references. Each reference is an optional type qualifier
/// (`ecore:EAttribute`) followed by `<uri>#<fragment>`, where the URI may be empty
/// for a reference into the same document:
///
/// ```
/// ecoreFeature="ecore:EAttribute library.ecore#//Book/title"
/// usedGenPackages="../../ecore/model/Ecore.genmodel#//ecore other.genmodel#//x"
/// ```
///
/// `CrossReference` splits such text into its parts.
public struct CrossReference: Sendable, Equatable {
    /// The type qualifier (for example `ecore:EAttribute`), or `nil` if none was written.
    public let qualifier: String?

    /// The URI of the referenced resource as written; empty for the same document.
    public let uri: String

    /// The fragment that identifies the object within the resource, without `#`.
    public let fragment: String

    /// Creates a cross-reference.
    ///
    /// - Parameters:
    ///   - qualifier: The optional type qualifier.
    ///   - uri: The resource URI as written; empty for the same document.
    ///   - fragment: The fragment without a leading `#`.
    public init(qualifier: String? = nil, uri: String, fragment: String) {
        self.qualifier = qualifier
        self.uri = uri
        self.fragment = fragment
    }

    /// The reference as `uri#fragment` text, without the qualifier.
    public var href: String {
        uri + String(CrossReferenceSyntax.fragmentSeparator) + fragment
    }

    /// Parses the value of a reference attribute.
    ///
    /// Tokens are separated by white space. A token that contains `#` (or starts with
    /// the positional prefix `//@`) is a reference; a preceding token without `#` that
    /// contains a `:` is its type qualifier. Any other token is taken to be an `xmi:id`
    /// reference into the same document.
    ///
    /// - Parameter value: The attribute value.
    /// - Returns: The references in document order; empty if the value is blank.
    public static func parseList(_ value: String) -> [CrossReference] {
        let tokens = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var references: [CrossReference] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if isReference(token) {
                references.append(reference(from: token, qualifier: nil))
            } else if token.contains(CrossReferenceSyntax.qualifierSeparator),
                index + 1 < tokens.count, isReference(tokens[index + 1])
            {
                references.append(reference(from: tokens[index + 1], qualifier: token))
                index += 1
            } else {
                references.append(CrossReference(uri: "", fragment: token))
            }
            index += 1
        }
        return references
    }

    /// Whether a token has the form of a reference (as opposed to a type qualifier).
    ///
    /// - Parameter token: The token to test.
    /// - Returns: `true` if the token contains `#` or is a positional path.
    private static func isReference(_ token: String) -> Bool {
        token.contains(CrossReferenceSyntax.fragmentSeparator)
            || token.hasPrefix(CrossReferenceSyntax.fragmentPathPrefix)
    }

    /// Builds a reference from a token.
    ///
    /// - Parameters:
    ///   - token: A token that satisfies ``isReference(_:)``.
    ///   - qualifier: The qualifier that preceded the token, if any.
    /// - Returns: The parsed reference.
    private static func reference(from token: String, qualifier: String?) -> CrossReference {
        if token.contains(CrossReferenceSyntax.fragmentSeparator) {
            let parts = URIReference.split(token)
            return CrossReference(qualifier: qualifier, uri: parts.uri, fragment: parts.fragment ?? "")
        }
        return CrossReference(qualifier: qualifier, uri: "", fragment: token)
    }
}
