//
// JSONSyntax.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// The keys and separators of the JSON resource format.
///
/// The JSON parser, the JSON serialiser, and the fragment helpers all take their
/// vocabulary from this enumeration, so that the format is defined in one place.
/// Fragment punctuation that JSON shares with XMI (`#`, `//`, `@`, and `.`) is
/// defined by ``CrossReferenceSyntax``.
public enum JSONSyntax {
    /// The key that names the class of an object, as in `"eClass": "http://ns#//Book"`.
    public static let eClassKey = "eClass"

    /// The key of a reference object, as in `{"$ref": "//@authors.0"}`.
    public static let referenceKey = "$ref"

    /// The text that follows a namespace URI in a qualified class name (`#//`).
    public static let classFragmentPrefix =
        String(CrossReferenceSyntax.fragmentSeparator) + CrossReferenceSyntax.fragmentPathPrefix

    /// Separates the segments of a JSON pointer.
    public static let pointerSeparator = CrossReferenceSyntax.segmentSeparator

    /// The JSON pointer escape of a slash inside a segment.
    public static let pointerSlashEscape = "~1"

    /// The JSON pointer escape of a tilde inside a segment.
    public static let pointerTildeEscape = "~0"

    /// The document written for a resource without root objects.
    ///
    /// A JSON resource holds one root object or an array of roots, so a resource without
    /// roots is an empty array, which reads back as an empty resource.
    public static let emptyDocument = "[]"
}
