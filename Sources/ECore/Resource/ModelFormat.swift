//
// ModelFormat.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// The document formats in which models and metamodels are read and written.
///
/// A model instance is held either as XMI or as JSON, and a metamodel as an Ecore document,
/// which is XMI whose root is an Ecore package, or as KM3 text (see ``KM3Reader``). EMOF
/// metamodels (see ``EMOFFormat``) and UML models (see ``UMLFormat``) are dialects of XMI,
/// and Emfatic (see ``EmfaticReader``), Xcore (see ``XcoreReader``) and OCLinEcore (see
/// ``OCLinEcoreReader``) further textual metamodel notations. Metamodels are also imported
/// from ASDL descriptions (see ``ASDLReader``), Langium and Xtext grammars (see
/// ``LangiumReader`` and ``XtextReader``) and SDF3 syntax definitions (see ``SDF3Reader``). The raw value of each case is the conventional file extension of the
/// format, without the leading dot, so a format can be read from a command-line option with
/// ``init(fileExtension:)``, which also accepts the prose name of a format such as `emfatic`,
/// and the accepted spellings listed through `allCases`.
///
/// ## Detection
///
/// ``detect(url:)`` recognises a format from the extension of a file name, and
/// ``detect(data:)`` and ``detect(contentsOf:)`` from the start of a document:
///
/// - A document that starts with `{` or `[` is JSON.
/// - An XML document whose root element is an `EPackage` of the Ecore namespace, or an
///   `xmi:XMI` wrapper whose first element is one, is an Ecore document.
/// - Any other XML document whose root element is in an EMOF namespace, or is an `xmi:XMI`
///   wrapper that declares one, is EMOF (see ``EMOFFormat/sniff(data:)``).
/// - Any other XML document whose root element is in a UML namespace, or is an `xmi:XMI`
///   wrapper that declares one, is UML (see ``UMLFormat/sniff(data:)``).
/// - Any other XML document is XMI.
/// - A document that is neither JSON nor XML and starts like KM3 (see
///   ``KM3Syntax/looksLikeKM3(_:)``) is KM3.
/// - A text document that is neither JSON, XML nor KM3 and starts like Emfatic (see
///   ``EmfaticSyntax/looksLikeEmfatic(_:)``) is Emfatic, and one that starts like Xcore (see
///   ``XcoreSyntax/looksLikeXcore(_:)``) is Xcore, and one that starts like OCLinEcore (see
///   ``OCLinEcoreSyntax/looksLikeOCLinEcore(_:)``) is OCLinEcore. A text that starts with
///   `module` is ASDL if the name is followed by its body in braces (see
///   ``ASDLSyntax/looksLikeASDL(_:)``) and SDF3 if it is followed by a section (see
///   ``SDF3Syntax/looksLikeSDF3(_:)``); one that starts with `grammar` is Xtext or Langium
///   (see ``XtextSyntax/looksLikeXtext(_:)`` and ``LangiumSyntax/looksLikeLangium(_:)``). A document whose start holds a NUL or
///   another control character than white space is binary and is neither, so that a
///   Windows metafile, which shares the `.emf` extension with Emfatic, is not taken for one.
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

    /// A KM3 document that holds one or more metamodel packages as text.
    ///
    /// KM3 (Kernel MetaMetaModel) is the textual metamodel language of the ATL tool chain.
    case km3

    /// An EMOF document that holds one or more metamodel packages in the vocabulary of the
    /// OMG Meta Object Facility.
    ///
    /// See ``EMOFFormat``.
    case emof

    /// A UML model, read as instances of the bundled Eclipse UML2 metamodel.
    ///
    /// See ``UMLFormat``.
    case uml

    /// An Emfatic document that holds a metamodel package as text.
    ///
    /// Emfatic is the textual notation of the Eclipse Emfatic tools; its documents have
    /// the extension `emf`. See ``EmfaticReader`` and ``EmfaticWriter``.
    case emfatic = "emf"

    /// An Xcore document that holds a metamodel package as text.
    ///
    /// See ``XcoreReader`` and ``XcoreWriter``.
    case xcore

    /// An OCLinEcore document that holds metamodel packages with OCL constraints as text.
    ///
    /// The constraints are kept as the annotations that Eclipse OCL writes (see
    /// ``OCLConstraintAnnotations``). See ``OCLinEcoreReader`` and ``OCLinEcoreWriter``.
    case oclinecore

    /// A Zephyr ASDL description, from which a metamodel is imported.
    ///
    /// See ``ASDLReader`` and ``ASDLWriter``.
    case asdl

    /// A Langium grammar, from which a metamodel is inferred; it is read but not written.
    ///
    /// See ``LangiumReader``.
    case langium

    /// An Xtext grammar, whose generated packages are imported; it is read but not written.
    ///
    /// See ``XtextReader``.
    case xtext

    /// An SDF3 syntax definition or Stratego signature, from which a metamodel is imported;
    /// it is read but not written.
    ///
    /// See ``SDF3Reader``.
    case sdf3

    /// The conventional file extension of the format, without the leading dot.
    public var fileExtension: String { rawValue }

    /// Creates the format that a file extension or format name denotes, ignoring case.
    ///
    /// The prose name of a format (its ``description``) is accepted where it differs from
    /// the extension, such as `emfatic` for ``emfatic``.
    ///
    /// - Parameter fileExtension: An extension without the leading dot, such as `xmi` or
    ///   `JSON`, or the name of a format.
    /// - Returns: The format, or `nil` if the extension denotes none of the formats.
    public init?(fileExtension: String) {
        let key = fileExtension.lowercased()
        guard let format = ModelFormat(rawValue: key) ?? ModelFormat.allCases.first(where: {
            $0.description.lowercased() == key
        }) else { return nil }
        self = format
    }

    /// Detects the format of a file from the extension of its name, ignoring case.
    ///
    /// Only the conventional file extensions are recognised, not the names of formats. The
    /// contents of the file are not examined; use ``detect(contentsOf:)`` for that.
    ///
    /// - Parameter url: The location of the file.
    /// - Returns: The format, or `nil` if the file has no extension that names one.
    public static func detect(url: URL) -> ModelFormat? {
        ModelFormat(rawValue: url.pathExtension.lowercased())
    }

    /// Detects the format of a document from its first characters.
    ///
    /// A leading byte order mark, white space, XML declarations, processing instructions,
    /// comments and document type declarations are skipped. Only the start of the document
    /// is examined, so the document need not be complete or well formed.
    ///
    /// - Parameter data: The document, or at least its beginning.
    /// - Returns: The format, or `nil` if the document is in none of the formats.
    public static func detect(data: Data) -> ModelFormat? {
        let prefix = data.prefix(ModelFormatSniffing.prefixLength)
        let text = String(decoding: prefix, as: UTF8.self)
        var scanner = ModelFormatSniffing.Scanner(text)
        scanner.skipByteOrderMark()
        scanner.skipWhitespace()
        guard let first = scanner.current else { return nil }
        if ModelFormatSniffing.jsonOpeners.contains(first) { return .json }
        guard first == ModelFormatSniffing.tagOpener else { return ModelFormatSniffing.textFormat(of: prefix) }
        guard let root = scanner.nextStartTag() else { return .xmi }
        if root.isEcorePackage(within: [:]) { return .ecore }
        if root.isXMIWrapper, let child = scanner.nextStartTag(), child.isEcorePackage(within: root.namespaces) {
            return .ecore
        }
        if EMOFFormat.isEMOF(root: root) { return .emof }
        if UMLFormat.isUML(root: root) { return .uml }
        return .xmi
    }

    /// Detects the format of a file from its first characters.
    ///
    /// Only the beginning of the file is read; see ``detect(data:)`` for the rules.
    ///
    /// - Parameter url: The location of the file.
    /// - Returns: The format, or `nil` if the file is in none of the formats.
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
    /// The name of the format as it is written in prose, such as `XMI`, `JSON`, `Ecore`, `KM3`,
    /// `EMOF`, `UML`, `Emfatic`, `Xcore`, `OCLinEcore`, `ASDL`, `Langium`, `Xtext` or `SDF3`.
    public var description: String {
        switch self {
        case .xmi: return "XMI"
        case .json: return "JSON"
        case .ecore: return "Ecore"
        case .km3: return "KM3"
        case .emof: return "EMOF"
        case .uml: return "UML"
        case .emfatic: return "Emfatic"
        case .xcore: return "Xcore"
        case .oclinecore: return "OCLinEcore"
        case .asdl: return "ASDL"
        case .langium: return "Langium"
        case .xtext: return "Xtext"
        case .sdf3: return "SDF3"
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

    /// A document was to be written in a format whose handler can only read.
    ///
    /// The associated value is the name of the format.
    case unwritableFormat(String)
}

extension ModelFormatError: CustomStringConvertible, LocalizedError {
    /// A sentence that describes the error and, where a format is unknown, lists the supported formats.
    public var description: String {
        let supported = ModelFormat.allCases.map(\.rawValue).joined(separator: ", ")
        switch self {
        case .undetectableFormat(let location):
            return "Cannot determine the model format of \(location) (supported: \(supported))"
        case .unsupportedFormat(let name):
            return "Unsupported model format '\(name)' (supported: \(supported))"
        case .unwritableFormat(let name):
            return "Cannot write documents in the \(name) format"
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

    /// The text of the start of a document, without a leading byte order mark.
    ///
    /// The bytes are read as UTF-8 or, if they are not valid UTF-8, as ISO-8859-1, in which
    /// many KM3 documents are written.
    ///
    /// - Parameter prefix: The start of the document.
    /// - Returns: The text read as UTF-8 or, if it is not valid UTF-8, as ISO-8859-1.
    static func text(of prefix: Data) -> String? {
        guard let decoded = try? DecodedText(decoding: prefix) else { return nil }
        return decoded.text.first == byteOrderMark ? String(decoded.text.dropFirst()) : decoded.text
    }

    /// The control characters that may occur in a text document: tab, line feed, vertical
    /// tab, form feed and carriage return.
    static let textControlBytes: Set<UInt8> = [0x09, 0x0A, 0x0B, 0x0C, 0x0D]

    /// The bytes below which every byte is a control character.
    static let firstPrintableByte: UInt8 = 0x20

    /// Whether the start of a document is text rather than binary data.
    ///
    /// A document is binary if its start holds a NUL or any other control character than
    /// the white space in ``textControlBytes``.
    ///
    /// - Parameter prefix: The start of the document.
    /// - Returns: `true` if the start of the document is text.
    static func isText(_ prefix: Data) -> Bool {
        !prefix.contains { $0 < firstPrintableByte && !textControlBytes.contains($0) }
    }

    /// The textual format of a document that is neither JSON nor XML.
    ///
    /// KM3 is recognised as before. The other textual formats are recognised only in text,
    /// never in binary data (see ``isText(_:)``).
    ///
    /// - Parameter prefix: The start of the document.
    /// - Returns: The format, or `nil` if the document starts like none of the textual formats.
    static func textFormat(of prefix: Data) -> ModelFormat? {
        guard let text = text(of: prefix) else { return nil }
        if KM3Syntax.looksLikeKM3(text) { return .km3 }
        guard isText(prefix) else { return nil }
        if EmfaticSyntax.looksLikeEmfatic(text) { return .emfatic }
        if XcoreSyntax.looksLikeXcore(text) { return .xcore }
        if OCLinEcoreSyntax.looksLikeOCLinEcore(text) { return .oclinecore }
        if ASDLSyntax.looksLikeASDL(text) { return .asdl }
        if SDF3Syntax.looksLikeSDF3(text) { return .sdf3 }
        if XtextSyntax.looksLikeXtext(text) { return .xtext }
        if LangiumSyntax.looksLikeLangium(text) { return .langium }
        return nil
    }

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
