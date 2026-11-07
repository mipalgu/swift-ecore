//
// DecodedText.swift
// EMFBase
//
// Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// The text of a document together with the encoding in which it was read.
///
/// Text formats are read in UTF-8. A document whose bytes are not valid UTF-8 is read as
/// ISO-8859-1 instead, which accepts every byte, and ``warning`` then tells the caller so
/// that the substitution can be shown to the user. An explicit encoding overrides both.
///
/// ```swift
/// let decoded = try DecodedText(contentsOf: url)
/// if let warning = decoded.warning { report(warning) }
/// parse(decoded.text)
/// ```
///
/// XML documents follow the rules of XML instead (see ``init(decodingXML:encoding:)``).
public struct DecodedText: Sendable, Hashable {
    /// The decoded text.
    public var text: String

    /// The encoding in which the text was read.
    public var encoding: TextEncoding

    /// A warning that the text was not read in the expected encoding, if it was not.
    ///
    /// The warning has the code ``TextDecodingDiagnostic/decodedAsISOLatin1`` and points at
    /// the first byte that was not valid UTF-8.
    public var warning: SourceDiagnostic?

    /// Creates decoded text from its parts.
    ///
    /// - Parameters:
    ///   - text: The decoded text.
    ///   - encoding: The encoding in which the text was read.
    ///   - warning: A warning about how the text was read, if any.
    public init(text: String, encoding: TextEncoding, warning: SourceDiagnostic? = nil) {
        self.text = text
        self.encoding = encoding
        self.warning = warning
    }

    /// Decodes the bytes of a text document.
    ///
    /// With an explicit encoding, the bytes are decoded in that encoding alone. Otherwise a
    /// UTF-16 byte order mark selects UTF-16, and any other document is read as UTF-8,
    /// with a UTF-8 byte order mark handled as Foundation handles it. Bytes that are not
    /// valid UTF-8 are read as ISO-8859-1 with a warning.
    ///
    /// - Parameters:
    ///   - bytes: The bytes of the document.
    ///   - encoding: The encoding to use, or `nil` (the default) to detect it.
    ///   - document: The identifier (for example the URI) of the document, recorded in a warning.
    /// - Throws: ``TextDecodingError/malformed(_:)`` if the bytes are not valid in an
    ///   explicit encoding. Without an explicit encoding, decoding cannot fail.
    public init<Bytes: Collection>(decoding bytes: Bytes, encoding: TextEncoding? = nil, document: String? = nil) throws
    where Bytes.Element == UInt8 {
        if let encoding {
            self = try Self.strictly(bytes, in: encoding)
            return
        }
        if bytes.starts(with: TextEncoding.bigEndianMark) || bytes.starts(with: TextEncoding.littleEndianMark),
            let text = TextEncoding.utf16.decode(bytes)
        {
            self.init(text: text, encoding: .utf16)
        } else if let text = TextEncoding.utf8.decode(bytes) {
            self.init(text: text, encoding: .utf8)
        } else {
            let text = TextEncoding.isoLatin1.decode(bytes) ?? ""
            self.init(text: text, encoding: .isoLatin1, warning: Self.fallbackWarning(bytes, text: text, document: document))
        }
    }

    /// Reads and decodes a text document.
    ///
    /// The bytes are decoded as ``init(decoding:encoding:document:)`` decodes them, and a
    /// warning names the absolute string of the URL as its document.
    ///
    /// - Parameters:
    ///   - url: The location of the document.
    ///   - encoding: The encoding to use, or `nil` (the default) to detect it.
    /// - Throws: The error of reading the document, or ``TextDecodingError/malformed(_:)``
    ///   if the bytes are not valid in an explicit encoding.
    public init(contentsOf url: URL, encoding: TextEncoding? = nil) throws {
        try self.init(decoding: try Data(contentsOf: url), encoding: encoding, document: url.absoluteString)
    }

    /// Decodes the bytes of an XML document.
    ///
    /// With an explicit encoding, the bytes are decoded in that encoding alone. Otherwise
    /// the encoding is found as an XML parser finds it: a UTF-16 byte order mark, or a
    /// document that starts with `<?` in UTF-16, selects UTF-16; bytes that are valid UTF-8
    /// are read as UTF-8, exactly as Foundation reads them; any other document is read in
    /// the encoding that its XML declaration names. A document that is not valid UTF-8 and
    /// names no other encoding is rejected rather than guessed, so the result never has a
    /// warning.
    ///
    /// - Parameters:
    ///   - bytes: The bytes of the document.
    ///   - encoding: The encoding to use, or `nil` (the default) to detect it.
    /// - Throws: ``TextDecodingError/unsupportedEncoding(_:)`` if the declaration names an
    ///   encoding that ``TextEncoding`` does not support, or
    ///   ``TextDecodingError/malformed(_:)`` if the bytes are not valid in the encoding used.
    public init<Bytes: Collection>(decodingXML bytes: Bytes, encoding: TextEncoding? = nil) throws
    where Bytes.Element == UInt8 {
        if let encoding {
            self = try Self.strictly(bytes, in: encoding)
            return
        }
        if let signature = XMLSignature.encoding(of: bytes) {
            self = try Self.strictly(bytes, in: signature)
        } else if let text = TextEncoding.utf8.decode(bytes) {
            self.init(text: text, encoding: .utf8)
        } else if let name = XMLSignature.declaredEncoding(in: bytes) {
            guard let declared = TextEncoding(name: name) else { throw TextDecodingError.unsupportedEncoding(name) }
            self = try Self.strictly(bytes, in: declared)
        } else {
            throw TextDecodingError.malformed(.utf8)
        }
    }

    // MARK: Implementation

    /// Decodes bytes in one encoding.
    ///
    /// - Parameters:
    ///   - bytes: The bytes.
    ///   - encoding: The encoding.
    /// - Returns: The text without a warning.
    /// - Throws: ``TextDecodingError/malformed(_:)`` if the bytes are not valid.
    private static func strictly<Bytes: Collection>(_ bytes: Bytes, in encoding: TextEncoding) throws -> DecodedText
    where Bytes.Element == UInt8 {
        guard let text = encoding.decode(bytes) else { throw TextDecodingError.malformed(encoding) }
        return DecodedText(text: text, encoding: encoding)
    }

    /// The warning that bytes that are not UTF-8 were read as ISO-8859-1.
    ///
    /// - Parameters:
    ///   - bytes: The bytes of the document.
    ///   - text: The text read as ISO-8859-1.
    ///   - document: The identifier of the document.
    /// - Returns: A warning whose range covers the character of the first invalid byte.
    private static func fallbackWarning<Bytes: Collection>(_ bytes: Bytes, text: String, document: String?)
        -> SourceDiagnostic where Bytes.Element == UInt8
    {
        let invalid = firstInvalidUTF8Offset(Array(bytes))
        let offset = bytes.prefix(invalid).reduce(0) { $0 + String(Unicode.Scalar($1)).utf8.count }
        let table = LineTable(text)
        let start = table.position(forUTF8Offset: offset)
        let end = table.position(forUTF8Offset: offset + String(Unicode.Scalar(Array(bytes)[invalid])).utf8.count)
        return SourceDiagnostic(
            severity: .warning, code: TextDecodingDiagnostic.decodedAsISOLatin1,
            message: "The text is not valid \(TextEncoding.utf8.name) and was read as \(TextEncoding.isoLatin1.name)",
            range: SourceRange(start: start, end: end), document: document)
    }

    /// The offset of the first byte at which bytes stop being valid UTF-8.
    ///
    /// - Parameter bytes: Bytes that are not valid UTF-8 as a whole.
    /// - Returns: The offset of the first byte of the first invalid sequence.
    private static func firstInvalidUTF8Offset(_ bytes: [UInt8]) -> Int {
        var parser = Unicode.UTF8.ForwardParser()
        var iterator = bytes.makeIterator()
        var offset = 0
        while true {
            switch parser.parseScalar(from: &iterator) {
            case .valid(let scalar): offset += scalar.count
            case .error: return min(offset, bytes.count - 1)
            case .emptyInput: return max(0, bytes.count - 1)
            }
        }
    }
}

/// An error that prevents bytes from being decoded as text.
public enum TextDecodingError: Error, Sendable, Hashable {
    /// The bytes are not valid in the encoding.
    case malformed(TextEncoding)

    /// An XML declaration names an encoding that is not supported; the associated value
    /// is the name as declared.
    case unsupportedEncoding(String)
}

/// The diagnostic codes that decoding text can report.
public enum TextDecodingDiagnostic {
    /// Text that is not valid UTF-8 was read as ISO-8859-1.
    public static let decodedAsISOLatin1 = "text.decoding.decodedAsISOLatin1"
}

/// The parts of an XML document that identify its encoding before it is decoded.
enum XMLSignature {
    /// The start of an XML declaration.
    private static let declarationStart = Array("<?xml".utf8)

    /// The end of an XML declaration.
    private static let declarationEnd = Array("?>".utf8)

    /// The name of the pseudo-attribute that declares the encoding.
    private static let encodingAttribute = Array("encoding".utf8)

    /// The first two characters of an XML declaration in UTF-16 big-endian order.
    private static let bigEndianStart: [UInt8] = [0x00, 0x3C, 0x00, 0x3F]

    /// The first two characters of an XML declaration in UTF-16 little-endian order.
    private static let littleEndianStart: [UInt8] = [0x3C, 0x00, 0x3F, 0x00]

    /// The longest declaration that is searched for an encoding.
    private static let declarationLimit = 1024

    /// The encoding that the first bytes of an XML document imply, if they imply one other than UTF-8.
    ///
    /// - Parameter bytes: The bytes of the document.
    /// - Returns: ``TextEncoding/utf16`` for a UTF-16 byte order mark, the UTF-16 encoding
    ///   of the byte order of a declaration that starts in UTF-16, or `nil`.
    static func encoding<Bytes: Collection>(of bytes: Bytes) -> TextEncoding? where Bytes.Element == UInt8 {
        if bytes.starts(with: TextEncoding.bigEndianMark) || bytes.starts(with: TextEncoding.littleEndianMark) {
            return .utf16
        }
        if bytes.starts(with: bigEndianStart) { return .utf16BigEndian }
        if bytes.starts(with: littleEndianStart) { return .utf16LittleEndian }
        return nil
    }

    /// The encoding name that the XML declaration of an ASCII-compatible document declares.
    ///
    /// - Parameter bytes: The bytes of the document.
    /// - Returns: The declared name, or `nil` if there is no declaration or it names no encoding.
    static func declaredEncoding<Bytes: Collection>(in bytes: Bytes) -> String? where Bytes.Element == UInt8 {
        let head = Array(bytes.prefix(declarationLimit))
        guard head.starts(with: declarationStart),
            let end = range(of: declarationEnd, in: head)?.lowerBound,
            let attribute = range(of: encodingAttribute, in: Array(head[..<end]))
        else { return nil }
        var position = attribute.upperBound
        func skipSpace() { while position < end, isSpace(head[position]) { position += 1 } }
        skipSpace()
        guard position < end, head[position] == UInt8(ascii: "=") else { return nil }
        position += 1
        skipSpace()
        guard position < end, head[position] == UInt8(ascii: "\"") || head[position] == UInt8(ascii: "'") else {
            return nil
        }
        let quote = head[position]
        let start = position + 1
        guard let close = head[start..<end].firstIndex(of: quote) else { return nil }
        return String(decoding: head[start..<close], as: UTF8.self)
    }

    /// Whether a byte is XML white space.
    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    /// The first range at which a pattern occurs in bytes.
    private static func range(of pattern: [UInt8], in bytes: [UInt8]) -> Range<Int>? {
        guard !pattern.isEmpty, bytes.count >= pattern.count else { return nil }
        for start in 0...(bytes.count - pattern.count) where bytes[start..<start + pattern.count].elementsEqual(pattern) {
            return start..<start + pattern.count
        }
        return nil
    }
}
