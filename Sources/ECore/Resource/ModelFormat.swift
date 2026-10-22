//
// ModelFormat.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// The document formats in which models and metamodels are read and written.
///
/// A model instance is held either as XMI or as JSON, and a metamodel as an Ecore document,
/// which is XMI whose root is an Ecore package. The raw value of each case is the
/// conventional file extension of the format, without the leading dot, so a format can be
/// read from a command-line option with ``init(fileExtension:)`` and the accepted spellings
/// listed through ``allCases``.
///
/// ## Detection
///
/// ``detect(url:)`` recognises a format from the extension of a file name, and
/// ``detect(data:)`` and ``detect(contentsOf:)`` from the start of a document:
///
/// - A document that starts with `{` or `[` is JSON.
/// - An XML document whose root element is an `EPackage` of the Ecore namespace, or an
///   `xmi:XMI` wrapper whose first element is one, is an Ecore document.
/// - Any other XML document is XMI.
///
/// ```swift
/// let format = ModelFormat.detect(url: url) ?? (try ModelFormat.detect(contentsOf: url))
/// ```
public enum ModelFormat: String, CaseIterable, Sendable {
    /// An XMI document that holds model instances.
    case xmi

    /// A JSON document in the format of emfjson and pyecore.
    case json

    /// An Ecore document that holds one or more metamodel packages.
    case ecore

    /// The conventional file extension of the format, without the leading dot.
    public var fileExtension: String { rawValue }

    /// Creates the format that a file extension or format name denotes, ignoring case.
    ///
    /// - Parameter fileExtension: An extension without the leading dot, such as `xmi` or `JSON`.
    /// - Returns: The format, or `nil` if the extension denotes none of the formats.
    public init?(fileExtension: String) {
        self.init(rawValue: fileExtension.lowercased())
    }

    /// Detects the format of a file from the extension of its name, ignoring case.
    ///
    /// The contents of the file are not examined; use ``detect(contentsOf:)`` for that.
    ///
    /// - Parameter url: The location of the file.
    /// - Returns: The format, or `nil` if the file has no extension that names one.
    public static func detect(url: URL) -> ModelFormat? {
        ModelFormat(fileExtension: url.pathExtension)
    }

    /// Detects the format of a document from its first characters.
    ///
    /// A leading byte order mark, white space, XML declarations, processing instructions,
    /// comments and document type declarations are skipped. Only the start of the document
    /// is examined, so the document need not be complete or well formed.
    ///
    /// - Parameter data: The document, or at least its beginning.
    /// - Returns: The format, or `nil` if the document is neither JSON nor XML.
    public static func detect(data: Data) -> ModelFormat? {
        let prefix = data.prefix(ModelFormatSniffing.prefixLength)
        let text = String(decoding: prefix, as: UTF8.self)
        var scanner = ModelFormatSniffing.Scanner(text)
        scanner.skipByteOrderMark()
        scanner.skipWhitespace()
        guard let first = scanner.current else { return nil }
        if ModelFormatSniffing.jsonOpeners.contains(first) { return .json }
        guard first == ModelFormatSniffing.tagOpener else { return nil }
        guard let root = scanner.nextStartTag() else { return .xmi }
        if root.isEcorePackage(within: [:]) { return .ecore }
        if root.isXMIWrapper, let child = scanner.nextStartTag(), child.isEcorePackage(within: root.namespaces) {
            return .ecore
        }
        return .xmi
    }

    /// Detects the format of a file from its first characters.
    ///
    /// Only the beginning of the file is read; see ``detect(data:)`` for the rules.
    ///
    /// - Parameter url: The location of the file.
    /// - Returns: The format, or `nil` if the file is neither JSON nor XML.
    /// - Throws: The error of the file system if the file cannot be read.
    public static func detect(contentsOf url: URL) throws -> ModelFormat? {
        #if os(WASI)
        return detect(data: try Data(contentsOf: url))
        #else
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return detect(data: try handle.read(upToCount: ModelFormatSniffing.prefixLength) ?? Data())
        #endif
    }
}

extension ModelFormat: CustomStringConvertible {
    /// The name of the format as it is written in prose, such as `XMI`, `JSON` or `Ecore`.
    public var description: String {
        switch self {
        case .xmi: return "XMI"
        case .json: return "JSON"
        case .ecore: return "Ecore"
        }
    }
}

/// Errors raised when the format of a document is unknown.
public enum ModelFormatError: Error, Sendable, Equatable {
    /// The format of a document could be determined neither from its name nor from its contents.
    ///
    /// The associated value is the location of the document.
    case undetectableFormat(String)

    /// A format was named that is not one of the supported formats.
    ///
    /// The associated value is the name as it was given.
    case unsupportedFormat(String)
}

extension ModelFormatError: CustomStringConvertible, LocalizedError {
    /// A sentence that describes the error and lists the supported formats.
    public var description: String {
        let supported = ModelFormat.allCases.map(\.rawValue).joined(separator: ", ")
        switch self {
        case .undetectableFormat(let location):
            return "Cannot determine the model format of \(location) (supported: \(supported))"
        case .unsupportedFormat(let name):
            return "Unsupported model format '\(name)' (supported: \(supported))"
        }
    }

    /// The ``description`` of the error.
    public var errorDescription: String? { description }
}

// MARK: - Sniffing

/// The vocabulary and the scanner with which the start of a document is examined.
enum ModelFormatSniffing {
    /// The number of bytes at the start of a document that are examined.
    static let prefixLength = 64 * 1024

    /// The byte order mark that may precede a document.
    static let byteOrderMark: Character = "\u{FEFF}"

    /// The characters that start a JSON resource: an object or an array of objects.
    static let jsonOpeners: Set<Character> = ["{", "["]

    /// The character that starts every XML markup construct.
    static let tagOpener: Character = "<"

    /// The character that ends a start tag.
    static let tagCloser: Character = ">"

    /// The character that ends an empty-element tag before ``tagCloser``.
    static let emptyTagMarker: Character = "/"

    /// The character that separates an attribute name from its value.
    static let valueSeparator: Character = "="

    /// The characters that may quote an attribute value.
    static let quotes: Set<Character> = ["\"", "'"]

    /// The constructs before the root element that are skipped, by opening and closing text.
    static let skippedConstructs: [(open: String, close: String)] = [
        ("<?", "?>"), ("<!--", "-->"), ("<!", ">"),
    ]

    /// A start tag read from the beginning of a document.
    struct StartTag {
        /// The qualified name of the element.
        let name: String

        /// The namespace declarations of the element, by prefix (empty for the default namespace).
        let namespaces: [String: String]

        /// The prefix and local part of the qualified name.
        private var parts: (prefix: String, local: String) {
            guard let separator = name.firstIndex(of: CrossReferenceSyntax.qualifierSeparator) else {
                return ("", name)
            }
            return (String(name[..<separator]), String(name[name.index(after: separator)...]))
        }

        /// Whether the element is the `xmi:XMI` wrapper of a document with several roots.
        var isXMIWrapper: Bool {
            let (prefix, local) = parts
            return local == XMIDocumentSyntax.multipleRootElement
                && (namespaces[prefix] == EcoreURI.xmiNamespace.rawValue || prefix == CrossReferenceSyntax.xmiPrefix)
        }

        /// Whether the element is a package of the Ecore namespace.
        ///
        /// - Parameter inherited: The namespace declarations of the enclosing elements.
        /// - Returns: `true` if the element is an `EPackage` whose prefix denotes the Ecore namespace.
        func isEcorePackage(within inherited: [String: String]) -> Bool {
            let (prefix, local) = parts
            guard local == EcoreClassifier.ePackage.rawValue else { return false }
            return (namespaces[prefix] ?? inherited[prefix]) == EcorePackage.nsURI
        }
    }

    /// Reads markup from the start of a document.
    struct Scanner {
        private let characters: [Character]
        private var position = 0

        /// Creates a scanner that starts at the beginning of a text.
        ///
        /// - Parameter text: The text to scan.
        init(_ text: String) {
            characters = Array(text)
        }

        /// The character at the current position, or `nil` at the end of the text.
        var current: Character? { position < characters.count ? characters[position] : nil }

        /// Skips a byte order mark at the current position.
        mutating func skipByteOrderMark() {
            if current == ModelFormatSniffing.byteOrderMark { position += 1 }
        }

        /// Skips white space at the current position.
        mutating func skipWhitespace() {
            while let character = current, character.isWhitespace { position += 1 }
        }

        /// Reads the next start tag, skipping text, end tags and constructs that are not elements.
        ///
        /// - Returns: The start tag, or `nil` if the text ends before a complete start tag.
        mutating func nextStartTag() -> StartTag? {
            while true {
                while let character = current, character != ModelFormatSniffing.tagOpener { position += 1 }
                guard current != nil else { return nil }
                if let skipped = ModelFormatSniffing.skippedConstructs.first(where: { hasPrefix($0.open) }) {
                    guard skip(past: skipped.close) else { return nil }
                    continue
                }
                position += 1
                if current == ModelFormatSniffing.emptyTagMarker {
                    guard skip(past: String(ModelFormatSniffing.tagCloser)) else { return nil }
                    continue
                }
                return startTag()
            }
        }

        /// Reads the name and the namespace declarations of a start tag after its opening `<`.
        private mutating func startTag() -> StartTag? {
            let name = readName()
            guard !name.isEmpty else { return nil }
            var namespaces: [String: String] = [:]
            while true {
                skipWhitespace()
                guard let character = current else { return nil }
                if character == ModelFormatSniffing.tagCloser || character == ModelFormatSniffing.emptyTagMarker {
                    position += 1
                    return StartTag(name: name, namespaces: namespaces)
                }
                let attribute = readName()
                guard !attribute.isEmpty else { return nil }
                skipWhitespace()
                guard current == ModelFormatSniffing.valueSeparator else { continue }
                position += 1
                skipWhitespace()
                guard let value = readQuotedValue() else { return nil }
                if attribute == XMLNamespace.xmlns {
                    namespaces[""] = value
                } else if attribute.hasPrefix(XMLNamespace.prefixed("")) {
                    namespaces[String(attribute.dropFirst(XMLNamespace.prefixed("").count))] = value
                }
            }
        }

        /// Reads a name up to white space, `=`, `/` or `>`.
        private mutating func readName() -> String {
            let start = position
            while let character = current, !character.isWhitespace,
                character != ModelFormatSniffing.valueSeparator, character != ModelFormatSniffing.tagCloser,
                character != ModelFormatSniffing.emptyTagMarker
            {
                position += 1
            }
            return String(characters[start..<position])
        }

        /// Reads a quoted attribute value.
        private mutating func readQuotedValue() -> String? {
            guard let quote = current, ModelFormatSniffing.quotes.contains(quote) else { return nil }
            position += 1
            let start = position
            while let character = current, character != quote { position += 1 }
            guard current != nil else { return nil }
            let value = String(characters[start..<position])
            position += 1
            return value
        }

        /// Whether the text at the current position starts with a string.
        private func hasPrefix(_ string: String) -> Bool {
            matches(Array(string), at: position)
        }

        /// Whether a sequence of characters occurs at an offset of the text.
        private func matches(_ expected: [Character], at offset: Int) -> Bool {
            guard offset + expected.count <= characters.count else { return false }
            for (index, character) in expected.enumerated() where characters[offset + index] != character {
                return false
            }
            return true
        }

        /// Moves past the next occurrence of a string.
        ///
        /// - Returns: `false` if the string does not occur before the end of the text.
        private mutating func skip(past string: String) -> Bool {
            let expected = Array(string)
            while position + expected.count <= characters.count {
                if matches(expected, at: position) {
                    position += expected.count
                    return true
                }
                position += 1
            }
            position = characters.count
            return false
        }
    }
}
