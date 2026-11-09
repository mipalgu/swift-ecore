//
// TextEncoding+Encoding.swift
// EMFBase
//
// Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// The kinds of text document that are encoded by different rules.
///
/// Plain text is written character by character, and a character that the encoding cannot
/// hold is an error. An XML document names its encoding in its declaration and writes such a
/// character as a numeric character reference wherever XML allows one. A JSON document is
/// always written in UTF-8, as RFC 8259 requires.
public enum TextDocumentKind: String, Sendable, Hashable, CaseIterable {
    /// Plain text, such as generated code or a textual model notation.
    case text

    /// An XML document, such as XMI, Ecore, EMOF or UML.
    case xml

    /// A JSON document.
    case json

    /// The start of an XML declaration, by which an XML document is recognised.
    public static let xmlDeclarationStart = "<?xml"

    /// Finds the kind of a text document from its contents.
    ///
    /// A document that starts with an XML declaration, after an optional byte order mark, is
    /// XML; any other document is plain text. JSON is never detected, because a JSON document
    /// cannot be told from plain text that happens to look like JSON.
    ///
    /// - Parameter text: The text of the document.
    public init(detecting text: String) {
        let body = text.unicodeScalars.first == TextEncoding.byteOrderMarkScalar
            ? Substring(text.unicodeScalars.dropFirst()) : Substring(text)
        self = body.hasPrefix(Self.xmlDeclarationStart) ? .xml : .text
    }
}

/// Encoded text together with the encoding in which it was encoded.
public struct EncodedText: Sendable, Hashable {
    /// The encoded bytes.
    public var data: Data

    /// The encoding of the bytes, which differs from the one asked for only for JSON.
    public var encoding: TextEncoding

    /// Creates encoded text from its parts.
    ///
    /// - Parameters:
    ///   - data: The encoded bytes.
    ///   - encoding: The encoding of the bytes.
    public init(data: Data, encoding: TextEncoding) {
        self.data = data
        self.encoding = encoding
    }
}

/// An error that prevents text from being encoded.
public enum TextEncodingError: Error, Sendable, Hashable, CustomStringConvertible, LocalizedError {
    /// The encoding cannot hold a character of the text.
    ///
    /// - Parameters:
    ///   - character: The first character that the encoding cannot hold.
    ///   - encoding: The encoding.
    ///   - position: The position of the character in the text.
    case unrepresentable(Unicode.Scalar, encoding: TextEncoding, position: SourcePosition)

    /// A phrase that names the character, its line and column, and the encoding.
    public var description: String {
        switch self {
        case .unrepresentable(let character, let encoding, let position):
            return "the character '\(character)' (U+\(TextEncoding.hexadecimal(character))) at line \(position.line), "
                + "column \(position.column) cannot be written in \(encoding.name)"
        }
    }

    /// The ``description`` of the error.
    public var errorDescription: String? { description }
}

extension TextEncoding {
    /// Whether the encoding can hold a character.
    ///
    /// The Unicode encodings hold every character. ISO-8859-1 holds the code points below 256,
    /// US-ASCII those below 128, and windows-1252 the characters that it decodes from its bytes.
    ///
    /// - Parameter character: The character.
    /// - Returns: `true` if the character can be written in this encoding.
    public func canEncode(_ character: Unicode.Scalar) -> Bool {
        switch self {
        case .utf8, .utf16, .utf16BigEndian, .utf16LittleEndian: return true
        case .isoLatin1, .windows1252, .usASCII: return singleByte(for: character) != nil
        }
    }

    /// Encodes text.
    ///
    /// UTF-8 is encoded exactly as Foundation writes it, without a byte order mark. ``utf16``
    /// starts with a byte order mark and is big-endian, and the UTF-16 encodings that name a
    /// byte order write none. The other encodings write one byte for each character; for them,
    /// the text is first precomposed (Unicode normalisation form C), so that a letter followed
    /// by a combining mark, such as `e` followed by a combining acute accent, is written as the
    /// single character that the encoding holds, such as `é`.
    ///
    /// - Parameter text: The text to encode.
    /// - Returns: The encoded bytes.
    /// - Throws: ``TextEncodingError/unrepresentable(_:encoding:position:)`` for the first
    ///   character that the encoding cannot hold.
    public func encode(_ text: String) throws(TextEncodingError) -> Data {
        if self == .utf8 { return Data(text.utf8) }
        let text = precomposed(text)
        var bytes = byteOrderMarkBytes
        bytes.reserveCapacity(bytes.count + text.utf8.count)
        var offset = 0
        for scalar in text.unicodeScalars {
            guard append(scalar, to: &bytes) else {
                throw .unrepresentable(scalar, encoding: self, position: LineTable(text).position(forUTF8Offset: offset))
            }
            offset += UTF8.width(scalar)
        }
        return Data(bytes)
    }

    /// Encodes an XML document.
    ///
    /// The `encoding` of the XML declaration is set to the ``name`` of this encoding, a
    /// declaration without one gains one, and a document without a declaration gains a
    /// declaration unless it is written in UTF-8. A character that the encoding cannot hold is
    /// written as a hexadecimal numeric character reference, such as `&#x20AC;`, in character
    /// data and in attribute values, as EMF writes it. In the single-byte encodings, the text
    /// is first precomposed, as ``encode(_:)`` describes. A UTF-8 document whose declaration
    /// names UTF-8 is written unchanged.
    ///
    /// - Parameter text: The text of the document.
    /// - Returns: The encoded bytes.
    /// - Throws: ``TextEncodingError/unrepresentable(_:encoding:position:)`` for the first
    ///   character that the encoding cannot hold in a place where XML allows no character
    ///   reference: a name, a comment, a CDATA section, a processing instruction or a
    ///   document type declaration.
    public func encode(xmlDocument text: String) throws(TextEncodingError) -> Data {
        let scanner = XMLEncodingScanner(text: precomposed(text), encoding: self)
        return try scanner.encode()
    }

    /// Encodes a document by the rules of its kind.
    ///
    /// Plain text is encoded by ``encode(_:)`` and XML by ``encode(xmlDocument:)``. JSON is
    /// written in UTF-8 whatever encoding is asked for, so the result names the encoding that
    /// was actually used.
    ///
    /// - Parameters:
    ///   - text: The text of the document.
    ///   - kind: The kind of the document.
    /// - Returns: The encoded bytes and their encoding.
    /// - Throws: ``TextEncodingError/unrepresentable(_:encoding:position:)`` for a character
    ///   that the encoding cannot hold where no character reference can stand for it.
    public func encode(document text: String, as kind: TextDocumentKind) throws(TextEncodingError) -> EncodedText {
        switch kind {
        case .json: return EncodedText(data: Data(text.utf8), encoding: .utf8)
        case .xml: return EncodedText(data: try encode(xmlDocument: text), encoding: self)
        case .text: return EncodedText(data: try encode(text), encoding: self)
        }
    }

    // MARK: Implementation

    /// The byte order mark as a character.
    static let byteOrderMarkScalar: Unicode.Scalar = "\u{FEFF}"

    /// The first code point outside ISO-8859-1.
    static let latin1Limit: UInt32 = 0x100

    /// The first code point that windows-1252 replaces with a printable character.
    static let windows1252ControlStart: UInt32 = 0x80

    /// The first code point after the range that windows-1252 replaces.
    static let windows1252ControlEnd: UInt32 = 0xA0

    /// The bytes of windows-1252 from 0x80 to 0x9F, keyed by the code points they stand for.
    static let windows1252Bytes: [UInt32: UInt8] = {
        var bytes: [UInt32: UInt8] = [:]
        for (index, value) in windows1252Upper.enumerated() {
            bytes[value] = windows1252UpperStart + UInt8(index)
        }
        return bytes
    }()

    /// Precomposes text for an encoding that holds only some characters.
    ///
    /// - Parameter text: The text.
    /// - Returns: The text in Unicode normalisation form C for the single-byte encodings if it
    ///   holds a character outside ASCII, and the text unchanged otherwise.
    func precomposed(_ text: String) -> String {
        switch self {
        case .utf8, .utf16, .utf16BigEndian, .utf16LittleEndian:
            return text
        case .isoLatin1, .windows1252, .usASCII:
            guard text.utf8.contains(where: { $0 >= Self.asciiLimit }) else { return text }
            return text.precomposedStringWithCanonicalMapping
        }
    }

    /// The bytes written before the content, the byte order mark of ``utf16``.
    var byteOrderMarkBytes: [UInt8] { self == .utf16 ? Self.bigEndianMark : [] }

    /// The single byte that stands for a character in a single-byte encoding.
    ///
    /// - Parameter character: The character.
    /// - Returns: The byte, or `nil` if the encoding cannot hold the character or is not a
    ///   single-byte encoding.
    func singleByte(for character: Unicode.Scalar) -> UInt8? {
        let value = character.value
        switch self {
        case .usASCII:
            return value < UInt32(Self.asciiLimit) ? UInt8(value) : nil
        case .isoLatin1:
            return value < Self.latin1Limit ? UInt8(value) : nil
        case .windows1252:
            if value < Self.windows1252ControlStart || (value >= Self.windows1252ControlEnd && value < Self.latin1Limit) {
                return UInt8(value)
            }
            return Self.windows1252Bytes[value]
        case .utf8, .utf16, .utf16BigEndian, .utf16LittleEndian:
            return nil
        }
    }

    /// Appends the bytes of a character.
    ///
    /// - Parameters:
    ///   - character: The character.
    ///   - bytes: The bytes to append to.
    /// - Returns: `false`, appending nothing, if the encoding cannot hold the character.
    func append(_ character: Unicode.Scalar, to bytes: inout [UInt8]) -> Bool {
        switch self {
        case .utf8:
            UTF8.encode(character) { bytes.append($0) }
        case .utf16, .utf16BigEndian:
            UTF16.encode(character) { bytes.append(UInt8($0 >> 8)); bytes.append(UInt8($0 & 0xFF)) }
        case .utf16LittleEndian:
            UTF16.encode(character) { bytes.append(UInt8($0 & 0xFF)); bytes.append(UInt8($0 >> 8)) }
        case .isoLatin1, .windows1252, .usASCII:
            guard let byte = singleByte(for: character) else { return false }
            bytes.append(byte)
        }
        return true
    }

    /// Formats a code point as upper-case hexadecimal with at least four digits.
    ///
    /// - Parameter character: The character.
    /// - Returns: The digits, such as `00E9`.
    static func hexadecimal(_ character: Unicode.Scalar) -> String {
        let digits = String(character.value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }
}

/// Encodes an XML document, rewriting its declaration and escaping what the encoding cannot hold.
struct XMLEncodingScanner {
    /// The places in a document that decide whether a character reference may stand for a character.
    private enum Context: Equatable {
        /// Character data between tags, where references are allowed.
        case content

        /// The inside of a tag outside attribute values: names, where references are not allowed.
        case tag

        /// An attribute value delimited by a quote, where references are allowed.
        case attributeValue(Unicode.Scalar)

        /// A comment, where references are not recognised.
        case comment

        /// A CDATA section, where references are not recognised.
        case cdata

        /// A processing instruction, where references are not recognised.
        case processingInstruction

        /// A document type or other markup declaration, with the depth of its internal subset.
        case markupDeclaration(depth: Int)
    }

    /// The markup that opens a comment.
    private static let commentOpen = Array("<!--".unicodeScalars)

    /// The markup that closes a comment.
    private static let commentClose = Array("-->".unicodeScalars)

    /// The markup that opens a CDATA section.
    private static let cdataOpen = Array("<![CDATA[".unicodeScalars)

    /// The markup that closes a CDATA section.
    private static let cdataClose = Array("]]>".unicodeScalars)

    /// The markup that opens a processing instruction.
    private static let instructionOpen = Array("<?".unicodeScalars)

    /// The markup that closes a processing instruction.
    private static let instructionClose = Array("?>".unicodeScalars)

    /// The markup that opens a markup declaration.
    private static let declarationOpen = Array("<!".unicodeScalars)

    /// The name of the pseudo-attribute that declares the encoding.
    private static let encodingAttribute = "encoding"

    /// The name of the pseudo-attribute that declares the version.
    private static let versionAttribute = "version"

    /// The XML version written into a declaration that a document lacks.
    private static let defaultVersion = "1.0"

    /// The text that starts a hexadecimal character reference.
    private static let referenceStart = "&#x"

    /// The text that ends a character reference.
    private static let referenceEnd = ";"

    /// The text of the document.
    private let text: String

    /// The encoding to write.
    private let encoding: TextEncoding

    /// The characters of the document.
    private let scalars: [Unicode.Scalar]

    /// Creates a scanner for a document.
    ///
    /// - Parameters:
    ///   - text: The text of the document.
    ///   - encoding: The encoding to write.
    init(text: String, encoding: TextEncoding) {
        self.text = text
        self.encoding = encoding
        self.scalars = Array(text.unicodeScalars)
    }

    /// Encodes the document.
    ///
    /// - Returns: The encoded bytes.
    /// - Throws: ``TextEncodingError`` for a character that cannot be written.
    func encode() throws(TextEncodingError) -> Data {
        var bytes = encoding.byteOrderMarkBytes
        var start = 0
        if scalars.first == TextEncoding.byteOrderMarkScalar {
            start = 1
            if encoding == .utf8 { _ = encoding.append(TextEncoding.byteOrderMarkScalar, to: &bytes) }
        }
        let declaration = declarationRange(from: start)
        let head: String
        let bodyStart: Int
        if let declaration {
            let written = String(String.UnicodeScalarView(scalars[declaration]))
            head = rewrittenDeclaration(written)
            if encoding == .utf8 && head == written { return Data(text.utf8) }
            bodyStart = declaration.upperBound
        } else if encoding == .utf8 {
            return Data(text.utf8)
        } else {
            head = "<?xml \(Self.versionAttribute)=\"\(Self.defaultVersion)\" \(Self.encodingAttribute)=\"\(encoding.name)\"?>\n"
            bodyStart = start
        }
        bytes.reserveCapacity(bytes.count + text.utf8.count)
        for scalar in head.unicodeScalars { _ = encoding.append(scalar, to: &bytes) }
        try scan(from: bodyStart, into: &bytes)
        return Data(bytes)
    }

    /// The range of the XML declaration that starts at an index, if there is one.
    ///
    /// - Parameter start: The index after an optional byte order mark.
    /// - Returns: The range, including the closing `?>`.
    private func declarationRange(from start: Int) -> Range<Int>? {
        let opening = Array(TextDocumentKind.xmlDeclarationStart.unicodeScalars)
        guard Self.matches(opening, in: scalars, at: start) else { return nil }
        let afterName = start + opening.count
        guard afterName < scalars.count, Self.isSpace(scalars[afterName]) || Self.matches(Self.instructionClose, in: scalars, at: afterName)
        else { return nil }
        var index = afterName
        while index < scalars.count {
            if Self.matches(Self.instructionClose, in: scalars, at: index) { return start..<index + Self.instructionClose.count }
            index += 1
        }
        return nil
    }

    /// Sets the encoding of an XML declaration to the name of the encoding.
    ///
    /// - Parameter declaration: The declaration, from `<?xml` to `?>`.
    /// - Returns: The declaration with its encoding replaced, or with one inserted after the
    ///   version if it named none.
    private func rewrittenDeclaration(_ declaration: String) -> String {
        if let value = Self.pseudoAttributeValue(Self.encodingAttribute, in: declaration) {
            return declaration.replacingCharacters(in: value, with: encoding.name)
        }
        let inserted = " \(Self.encodingAttribute)=\"\(encoding.name)\""
        if let version = Self.pseudoAttributeValue(Self.versionAttribute, in: declaration) {
            let afterQuote = declaration.index(after: version.upperBound)
            return declaration.replacingCharacters(in: afterQuote..<afterQuote, with: inserted)
        }
        let afterName = declaration.index(declaration.startIndex, offsetBy: TextDocumentKind.xmlDeclarationStart.count)
        return declaration.replacingCharacters(in: afterName..<afterName, with: inserted)
    }

    /// Finds the value of a pseudo-attribute of an XML declaration.
    ///
    /// - Parameters:
    ///   - name: The name of the pseudo-attribute.
    ///   - declaration: The declaration.
    /// - Returns: The range of the value between its quotes, or `nil` if the declaration does
    ///   not have the pseudo-attribute.
    private static func pseudoAttributeValue(_ name: String, in declaration: String) -> Range<String.Index>? {
        var searchStart = declaration.startIndex
        while let found = declaration.range(of: name, range: searchStart..<declaration.endIndex) {
            searchStart = found.upperBound
            var index = found.upperBound
            while index < declaration.endIndex, declaration[index].isWhitespace { index = declaration.index(after: index) }
            guard index < declaration.endIndex, declaration[index] == "=" else { continue }
            index = declaration.index(after: index)
            while index < declaration.endIndex, declaration[index].isWhitespace { index = declaration.index(after: index) }
            guard index < declaration.endIndex, declaration[index] == "\"" || declaration[index] == "'" else { continue }
            let quote = declaration[index]
            let valueStart = declaration.index(after: index)
            guard let close = declaration[valueStart...].firstIndex(of: quote) else { return nil }
            return valueStart..<close
        }
        return nil
    }

    /// Encodes the characters of the document from an index, tracking where references are allowed.
    ///
    /// - Parameters:
    ///   - start: The index of the first character after the declaration.
    ///   - bytes: The bytes to append to.
    /// - Throws: ``TextEncodingError`` for a character that cannot be written where it stands.
    private func scan(from start: Int, into bytes: inout [UInt8]) throws(TextEncodingError) {
        var context = Context.content
        var index = start
        while index < scalars.count {
            let opened = opening(at: index, in: context)
            if let (next, length) = opened {
                for offset in 0..<length { _ = encoding.append(scalars[index + offset], to: &bytes) }
                index += length
                context = next
                continue
            }
            let scalar = scalars[index]
            if !encoding.append(scalar, to: &bytes) {
                guard context == .content || isAttributeValue(context) else { throw error(at: index) }
                let reference = Self.referenceStart + String(scalar.value, radix: 16, uppercase: true) + Self.referenceEnd
                for character in reference.unicodeScalars { _ = encoding.append(character, to: &bytes) }
            }
            context = following(context, after: index)
            index += 1
        }
    }

    /// The context that markup starting at an index opens, if any.
    ///
    /// - Parameters:
    ///   - index: The index.
    ///   - context: The current context.
    /// - Returns: The context that the markup opens and the length of the markup, or `nil`.
    private func opening(at index: Int, in context: Context) -> (Context, Int)? {
        switch context {
        case .content:
            if Self.matches(Self.commentOpen, in: scalars, at: index) { return (.comment, Self.commentOpen.count) }
            if Self.matches(Self.cdataOpen, in: scalars, at: index) { return (.cdata, Self.cdataOpen.count) }
            if Self.matches(Self.instructionOpen, in: scalars, at: index) {
                return (.processingInstruction, Self.instructionOpen.count)
            }
            if Self.matches(Self.declarationOpen, in: scalars, at: index) {
                return (.markupDeclaration(depth: 0), Self.declarationOpen.count)
            }
            return nil
        case .comment:
            return Self.matches(Self.commentClose, in: scalars, at: index) ? (.content, Self.commentClose.count) : nil
        case .cdata:
            return Self.matches(Self.cdataClose, in: scalars, at: index) ? (.content, Self.cdataClose.count) : nil
        case .processingInstruction:
            return Self.matches(Self.instructionClose, in: scalars, at: index)
                ? (.content, Self.instructionClose.count) : nil
        case .tag, .attributeValue, .markupDeclaration:
            return nil
        }
    }

    /// The context after a character that opens no markup.
    ///
    /// - Parameters:
    ///   - context: The context of the character.
    ///   - index: The index of the character.
    /// - Returns: The context of the next character.
    private func following(_ context: Context, after index: Int) -> Context {
        let scalar = scalars[index]
        switch context {
        case .content:
            return scalar == "<" ? .tag : .content
        case .tag:
            if scalar == ">" { return .content }
            if scalar == "\"" || scalar == "'" { return .attributeValue(scalar) }
            return .tag
        case .attributeValue(let quote):
            return scalar == quote ? .tag : context
        case .markupDeclaration(let depth):
            if scalar == "[" { return .markupDeclaration(depth: depth + 1) }
            if scalar == "]" { return .markupDeclaration(depth: max(0, depth - 1)) }
            return scalar == ">" && depth == 0 ? .content : context
        case .comment, .cdata, .processingInstruction:
            return context
        }
    }

    /// Whether a context is an attribute value.
    ///
    /// - Parameter context: The context.
    /// - Returns: `true` inside the quotes of an attribute value.
    private func isAttributeValue(_ context: Context) -> Bool {
        if case .attributeValue = context { return true }
        return false
    }

    /// The error for a character that cannot be written.
    ///
    /// - Parameter index: The index of the character.
    /// - Returns: The error, with the position of the character in the document.
    private func error(at index: Int) -> TextEncodingError {
        let offset = scalars[..<index].reduce(0) { $0 + UTF8.width($1) }
        return .unrepresentable(scalars[index], encoding: encoding, position: LineTable(text).position(forUTF8Offset: offset))
    }

    /// Whether a pattern occurs at an index.
    ///
    /// - Parameters:
    ///   - pattern: The characters of the pattern.
    ///   - scalars: The characters to search.
    ///   - index: The index.
    /// - Returns: `true` if the characters at the index are the pattern.
    private static func matches(_ pattern: [Unicode.Scalar], in scalars: [Unicode.Scalar], at index: Int) -> Bool {
        guard index >= 0, index + pattern.count <= scalars.count else { return false }
        for offset in pattern.indices where scalars[index + offset] != pattern[offset] { return false }
        return true
    }

    /// Whether a character is XML white space.
    ///
    /// - Parameter scalar: The character.
    /// - Returns: `true` for a space, tab, line feed or carriage return.
    private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
    }
}
