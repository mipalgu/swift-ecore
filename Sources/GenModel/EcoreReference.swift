//
// EcoreReference.swift
// GenModel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// A parsed textual reference from a generator model to an Ecore element.
///
/// Generator model files refer to Ecore elements by attribute values such as
/// `library.ecore#//Book` or, for features, `ecore:EAttribute library.ecore#//Book/title`.
/// The optional type qualifier names the metaclass of the target, the location names
/// the document, and the fragment is a path of names or positions below the document root.
///
/// ## Example
///
/// ```swift
/// let reference = EcoreReference("ecore:EAttribute library.ecore#//Book/title")
/// reference?.location   // "library.ecore"
/// reference?.segments   // ["Book", "title"]
/// ```
public struct EcoreReference: Sendable, Equatable {
    /// The metaclass qualifier written before the location, such as `ecore:EAttribute`, if any.
    public let typeQualifier: String?

    /// The document location, relative to the referring document; empty for the same document.
    public let location: String

    /// The fragment path segments below the document root; empty for the root itself.
    public let segments: [String]

    /// Parses a textual reference.
    ///
    /// - Parameter text: The attribute value of an `ecore*` reference.
    /// - Returns: The parsed reference, or `nil` if the text has no fragment separator.
    public init?(_ text: String) {
        var remaining = Substring(text.trimmingCharacters(in: .whitespaces))
        var qualifier: String?
        if let space = remaining.firstIndex(of: " ") {
            let head = String(remaining[..<space])
            if GenModelConstants.EcoreConvention.referenceTypeQualifiers.contains(head) {
                qualifier = head
                remaining = remaining[remaining.index(after: space)...]
            }
        }
        guard let separator = remaining.firstIndex(of: GenModelConstants.fragmentSeparator) else {
            return nil
        }
        var fragment = remaining[remaining.index(after: separator)...]
        if fragment.hasPrefix(GenModelConstants.fragmentPathPrefix) {
            fragment = fragment.dropFirst(GenModelConstants.fragmentPathPrefix.count)
        } else if fragment.first == GenModelConstants.pathSeparator {
            fragment = fragment.dropFirst()
        }
        self.typeQualifier = qualifier
        self.location = String(remaining[..<separator])
        self.segments =
            fragment
            .split(separator: GenModelConstants.pathSeparator, omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// The name that the last segment denotes, if the segment is name-based.
    ///
    /// A numeric suffix that disambiguates overloaded elements (`borrow.1`) is removed.
    /// Positional segments such as `@eOperations.0` yield `nil`.
    public var lastSegmentName: String? {
        guard let last = segments.last,
            last.first != GenModelConstants.positionalSegmentPrefix
        else { return nil }
        if let dot = last.lastIndex(of: GenModelConstants.positionSeparator),
            Int(last[last.index(after: dot)...]) != nil
        {
            return String(last[..<dot])
        }
        return last
    }
}
