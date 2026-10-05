//
// EcoreFragment.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Computes and resolves the name-based URI fragments of native metamodel elements.
///
/// The fragments follow the rules of EMF. The root package is `/` and every other element is
/// `//` followed by the segments along its containment path: `//Book`, `//Book/title`,
/// `//sub/Library`, `//Colour/RED`, and `//Book/borrow/days`. An element that has the same
/// name as an earlier named sibling carries the number of those earlier siblings as a `.n`
/// suffix (siblings are counted across all containments of the parent, in the order
/// operations before features). Annotations are named by their source between percent signs
/// (`%http:%2F%2Fexample.org%`), with a `.n` suffix for an earlier annotation of the same
/// source, and the detail entries of an annotation by position (`@details.0`). Reserved
/// characters in names and sources are percent-encoded as EMF does.
///
/// A document with several root packages writes the position of the root as the first
/// segment, so that the root is `/0` and its class `/0/Book`; a document with one root
/// writes an empty root segment. The functions that take a `rootIndex` produce and accept the
/// positional form when the index is not `nil`.
public enum EcoreFragment {
    /// The characters and markers of fragment segments.
    private enum Syntax {
        /// Delimits the source of an annotation segment.
        static let annotationMarker: Character = "%"

        /// Introduces the escape sequence of a reserved character.
        static let escape: Character = "%"

        /// The marker of a placeholder for a missing name.
        static let missingName = "%"

        /// The uppercase hexadecimal digits of escape sequences.
        static let hexDigits = Array("0123456789ABCDEF")

        /// The printable characters that name segments escape.
        static let reservedNames: Set<Character> = ["\"", "#", "%", "&", "'", ",", "/", ":", "<", ">"]

        /// The characters that annotation sources keep unescaped, besides letters and digits.
        static let sourceKeptCharacters: Set<Character> = Set("-_.!~*'();:@&=+$,")

        /// The first code point that source escaping always leaves unchanged.
        static let escapeLimit: UInt32 = 160

        /// The first code point above the control characters and the space.
        static let firstPrintable: UInt32 = 0x21
    }

    // MARK: Encoding

    /// Percent-encodes a name for use as a fragment segment.
    ///
    /// Control characters, the space, and the characters `"`, `#`, `%`, `&`, `'`, `,`, `/`,
    /// `:`, `<`, and `>` become `%` followed by two hexadecimal digits.
    ///
    /// - Parameter name: The name to encode.
    /// - Returns: The encoded name; the name itself if nothing needs encoding.
    public static func encode(name: String) -> String {
        var result = ""
        for character in name.unicodeScalars {
            if character.value < Syntax.firstPrintable
                || Syntax.reservedNames.contains(Character(character))
            {
                result += escaped(UInt8(truncatingIfNeeded: character.value))
            } else {
                result.unicodeScalars.append(character)
            }
        }
        return result
    }

    /// Percent-encodes an annotation source for use in a fragment segment.
    ///
    /// Letters, digits, and `-_.!~*'();:@&=+$,` stay as they are; every other character below
    /// code point 160 is written as `%` followed by two hexadecimal digits.
    ///
    /// - Parameter source: The source to encode.
    /// - Returns: The encoded source.
    public static func encode(source: String) -> String {
        var result = ""
        for character in source.unicodeScalars {
            let value = character.value
            let plain = Character(character)
            if value < Syntax.escapeLimit
                && !(plain.isASCII && (plain.isLetter || plain.isNumber))
                && !Syntax.sourceKeptCharacters.contains(plain)
            {
                result += escaped(UInt8(truncatingIfNeeded: value))
            } else {
                result.unicodeScalars.append(character)
            }
        }
        return result
    }

    /// Decodes the percent escapes of a fragment segment.
    ///
    /// Escapes are read as the bytes of UTF-8 characters. An incomplete escape stays as it is.
    ///
    /// - Parameter text: The encoded text.
    /// - Returns: The decoded text.
    public static func decode(_ text: String) -> String {
        var bytes: [UInt8] = []
        let source = Array(text.utf8)
        var index = 0
        let escapeByte = Syntax.escape.asciiValue ?? 0
        while index < source.count {
            if source[index] == escapeByte, index + 2 < source.count,
                let high = hexValue(source[index + 1]), let low = hexValue(source[index + 2])
            {
                bytes.append(high << 4 | low)
                index += 3
            } else {
                bytes.append(source[index])
                index += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The escape sequence for a byte.
    private static func escaped(_ byte: UInt8) -> String {
        String(Syntax.escape) + String(Syntax.hexDigits[Int(byte >> 4)])
            + String(Syntax.hexDigits[Int(byte & 0x0F)])
    }

    /// The value of a hexadecimal digit.
    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30
        case 0x41...0x46: return byte - 0x41 + 10
        case 0x61...0x66: return byte - 0x61 + 10
        default: return nil
        }
    }

    // MARK: Segments

    /// Computes the fragment segments of the children of an element.
    ///
    /// - Parameter children: The children of one element, in containment order.
    /// - Returns: One segment for each child, in the same order.
    public static func segments(of children: [EcoreChild]) -> [String] {
        var names: [String: Int] = [:]
        var sources: [String: Int] = [:]
        var result: [String] = []
        result.reserveCapacity(children.count)
        for child in children {
            switch child.element {
            case .annotation(let annotation):
                let count = sources[annotation.source, default: 0]
                sources[annotation.source] = count + 1
                var segment = String(Syntax.annotationMarker) + encode(source: annotation.source)
                    + String(Syntax.annotationMarker)
                if count > 0 { segment += String(CrossReferenceSyntax.indexSeparator) + String(count) }
                result.append(segment)
            case .detail:
                result.append(
                    String(CrossReferenceSyntax.positionalMarker) + EcoreFeatureName.details.rawValue
                        + String(CrossReferenceSyntax.indexSeparator) + String(child.index))
            default:
                let name = child.element.name ?? ""
                let count = names[name, default: 0]
                names[name] = count + 1
                var segment = name.isEmpty ? Syntax.missingName : encode(name: name)
                if count > 0 { segment += String(CrossReferenceSyntax.indexSeparator) + String(count) }
                result.append(segment)
            }
        }
        return result
    }

    /// Finds the child that a fragment segment denotes.
    ///
    /// - Parameters:
    ///   - element: The containing element.
    ///   - segment: A segment as written by ``segments(of:)``.
    /// - Returns: The child, or `nil` if the element has no such child.
    public static func child(of element: EcoreElement, segment: String) -> EcoreChild? {
        child(in: element.children, segment: segment)
    }

    /// Finds the child among a list of children that a fragment segment denotes.
    private static func child(in children: [EcoreChild], segment: String) -> EcoreChild? {
        guard let first = segment.first else { return nil }
        if first == CrossReferenceSyntax.positionalMarker {
            return positionalChild(in: children, segment: segment)
        }
        if first == Syntax.annotationMarker, let match = annotationChild(in: children, segment: segment) {
            return match
        }
        var name = segment
        var count = 0
        if let separator = segment.lastIndex(of: CrossReferenceSyntax.indexSeparator) {
            if let number = Int(segment[segment.index(after: separator)...]) {
                name = String(segment[..<separator])
                count = number
            }
        }
        let wanted = name == Syntax.missingName ? "" : decode(name)
        var remaining = count
        for child in children where child.element.annotationSource == nil && child.element.isNamed {
            if (child.element.name ?? "") == wanted {
                if remaining == 0 { return child }
                remaining -= 1
            }
        }
        return nil
    }

    /// Resolves a segment of the form `@feature.index`.
    private static func positionalChild(in children: [EcoreChild], segment: String) -> EcoreChild? {
        let body = segment.dropFirst()
        guard let separator = body.lastIndex(of: CrossReferenceSyntax.indexSeparator),
            let position = Int(body[body.index(after: separator)...]), position >= 0,
            let feature = EcoreFeatureName(rawValue: String(body[..<separator]))
        else { return nil }
        return children.first { $0.feature == feature && $0.index == position }
    }

    /// Resolves a segment of the form `%source%` or `%source%.n`.
    private static func annotationChild(in children: [EcoreChild], segment: String) -> EcoreChild? {
        guard let closing = segment.lastIndex(of: Syntax.annotationMarker), closing != segment.startIndex
        else { return nil }
        let afterClosing = segment.index(after: closing)
        var count = 0
        if afterClosing != segment.endIndex {
            guard segment[afterClosing] == CrossReferenceSyntax.indexSeparator,
                let number = Int(segment[segment.index(after: afterClosing)...])
            else { return nil }
            count = number
        }
        let encoded = String(segment[segment.index(after: segment.startIndex)..<closing])
        let source = encoded == Syntax.missingName ? "" : decode(encoded)
        var remaining = count
        for child in children where child.element.annotationSource == source {
            if remaining == 0 { return child }
            remaining -= 1
        }
        return nil
    }

    // MARK: Fragments of elements

    /// Computes the fragment of every element below a root package, and of the root.
    ///
    /// - Parameters:
    ///   - root: The root package of a document.
    ///   - rootIndex: The position of the root among the roots of its document, or `nil` if
    ///     the document has one root.
    /// - Returns: The fragment of each element, by identifier, without a leading `#`.
    public static func fragments(in root: EPackage, rootIndex: Int? = nil) -> [EUUID: String] {
        var result: [EUUID: String] = [:]
        let top = CrossReferenceSyntax.rootFragment + (rootIndex.map(String.init) ?? "")
        result[root.id] = top
        func visit(_ element: EcoreElement, _ fragment: String) {
            let children = element.children
            let segments = segments(of: children)
            for (child, segment) in zip(children, segments) {
                let path = fragment + String(CrossReferenceSyntax.segmentSeparator) + segment
                result[child.element.id] = path
                visit(child.element, path)
            }
        }
        visit(.package(root), top)
        return result
    }

    /// Computes the fragment of one element below a root package.
    ///
    /// - Parameters:
    ///   - target: The identifier of the element.
    ///   - root: The root package of a document.
    ///   - rootIndex: The position of the root among the roots of its document, or `nil` if
    ///     the document has one root.
    /// - Returns: The fragment without a leading `#`, or `nil` if the root does not contain
    ///   the element.
    public static func fragment(of target: EUUID, in root: EPackage, rootIndex: Int? = nil) -> String? {
        fragments(in: root, rootIndex: rootIndex)[target]
    }

    /// Resolves a fragment to an element of a document.
    ///
    /// - Parameters:
    ///   - fragment: A fragment such as `/`, `//Book`, or `//Book/title`, with or without a
    ///     leading `#`.
    ///   - roots: The root packages of the document, in order.
    /// - Returns: The identified element, or `nil` if no element has that fragment.
    public static func resolve(_ fragment: String, in roots: [EPackage]) -> EcoreElement? {
        var path = Substring(fragment)
        if path.first == CrossReferenceSyntax.fragmentSeparator { path = path.dropFirst() }
        guard path.first == CrossReferenceSyntax.segmentSeparator else {
            return path.isEmpty ? roots.first.map { .package($0) } : nil
        }
        let segments = path.dropFirst().split(
            separator: CrossReferenceSyntax.segmentSeparator, omittingEmptySubsequences: false
        ).map(String.init)
        guard let rootSegment = segments.first else { return nil }
        let root: EPackage
        if rootSegment.isEmpty {
            guard let first = roots.first else { return nil }
            root = first
        } else {
            guard let position = Int(rootSegment), roots.indices.contains(position) else { return nil }
            root = roots[position]
        }
        var current = EcoreElement.package(root)
        for segment in segments.dropFirst() {
            guard let next = child(of: current, segment: segment) else { return nil }
            current = next.element
        }
        return current
    }
}

extension EcoreElement {
    /// The source of an annotation, or `nil` for any other element.
    fileprivate var annotationSource: String? {
        if case .annotation(let annotation) = self { return annotation.source }
        return nil
    }

    /// Whether the element has a name.
    fileprivate var isNamed: Bool {
        switch self {
        case .annotation, .detail: return false
        default: return true
        }
    }
}
