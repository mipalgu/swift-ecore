//
// TextDecodingTests.swift
// EMFBaseTests
//
// Copyright © 2026 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import EMFBase

/// Verifies the shared decoding of text documents and the supported encoding names.
@Suite("Text decoding")
struct TextDecodingTests {
    /// The UTF-8 byte order mark.
    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// A text with characters outside ASCII that ISO-8859-1 can represent.
    private static let accented = "caf\u{E9} na\u{EF}ve"

    /// The ISO-8859-1 bytes of ``accented``.
    private static let accentedLatin1: [UInt8] = Array("caf".utf8) + [0xE9] + Array(" na".utf8) + [0xEF] + Array("ve".utf8)

    // MARK: Encoding names

    @Test("Every encoding is named by its IANA name")
    func ianaNames() {
        #expect(TextEncoding.utf8.rawValue == "UTF-8")
        #expect(TextEncoding.utf16.rawValue == "UTF-16")
        #expect(TextEncoding.utf16BigEndian.rawValue == "UTF-16BE")
        #expect(TextEncoding.utf16LittleEndian.rawValue == "UTF-16LE")
        #expect(TextEncoding.isoLatin1.rawValue == "ISO-8859-1")
        #expect(TextEncoding.windows1252.rawValue == "windows-1252")
        #expect(TextEncoding.usASCII.rawValue == "US-ASCII")
        for encoding in TextEncoding.allCases {
            #expect(encoding.name == encoding.rawValue)
            #expect(TextEncoding(name: encoding.name) == encoding)
        }
    }

    @Test("Names are matched ignoring case and separators, including registered aliases", arguments: [
        ("utf-8", TextEncoding.utf8), ("UTF8", .utf8), ("utf_16", .utf16), ("utf-16be", .utf16BigEndian),
        ("UTF-16LE", .utf16LittleEndian), ("iso-8859-1", .isoLatin1), ("ISO_8859-1", .isoLatin1),
        ("ISO_8859-1:1987", .isoLatin1), ("latin1", .isoLatin1), ("l1", .isoLatin1), ("CP819", .isoLatin1),
        ("Windows-1252", .windows1252), ("cp1252", .windows1252), ("ascii", .usASCII), ("US-ASCII", .usASCII),
        ("ANSI_X3.4-1968", .usASCII), (" utf-8 ", .utf8),
    ])
    func aliases(name: String, encoding: TextEncoding) {
        #expect(TextEncoding(name: name) == encoding)
    }

    @Test("Unsupported or empty names are not recognised", arguments: ["", "EBCDIC", "ISO-8859-15", "utf-7", "Shift_JIS"])
    func unsupportedNames(name: String) {
        #expect(TextEncoding(name: name) == nil)
    }

    @Test("Every alias names exactly one encoding")
    func aliasesAreUnambiguous() {
        var owners: [String: TextEncoding] = [:]
        for encoding in TextEncoding.allCases {
            for alias in encoding.aliases {
                #expect(owners[alias] == nil, "\(alias) names both \(owners[alias].map(\.name) ?? "") and \(encoding.name)")
                owners[alias] = encoding
                #expect(TextEncoding(name: alias) == encoding)
            }
        }
    }

    // MARK: Strict decoding with one encoding

    /// Byte sequences that exercise byte order marks, invalid bytes and surrogates.
    private static let utf8Samples: [[UInt8]] = {
        let plain: [UInt8] = Array("plain".utf8)
        let marked: [UInt8] = utf8BOM + Array("marked".utf8)
        let twice: [UInt8] = utf8BOM + utf8BOM + Array("twice".utf8)
        let inside: [UInt8] = Array("in".utf8) + utf8BOM + Array("side".utf8)
        let accented: [UInt8] = Array("caf\u{E9}".utf8)
        return [plain, marked, twice, inside, [0x00, 0x41], [], utf8BOM, accented, [0x63, 0xE9], [0xED, 0xA0, 0x80]]
    }()

    @Test("UTF-8 decodes exactly as Foundation does, including its byte order mark handling", arguments: utf8Samples)
    func utf8MatchesFoundation(bytes: [UInt8]) {
        #expect(TextEncoding.utf8.decode(bytes) == String(data: Data(bytes), encoding: .utf8))
    }

    @Test("ISO-8859-1 maps every byte to the code point of the same value")
    func latin1() throws {
        let all = (0...255).map { UInt8($0) }
        let text = try #require(TextEncoding.isoLatin1.decode(all))
        #expect(text.unicodeScalars.map(\.value) == (0...255).map { UInt32($0) })
        #expect(TextEncoding.isoLatin1.decode(Self.accentedLatin1) == Self.accented)
    }

    @Test("windows-1252 maps the printable characters of 0x80 to 0x9F and keeps undefined bytes as controls")
    func windows1252() throws {
        let text = try #require(TextEncoding.windows1252.decode([0x80, 0x93, 0x94, 0x99, 0x81, 0x9D, 0xE9, 0x41]))
        #expect(text.unicodeScalars.map(\.value) == [0x20AC, 0x201C, 0x201D, 0x2122, 0x81, 0x9D, 0xE9, 0x41])
        let printable = try #require(TextEncoding.windows1252.decode((0x80...0x9F).map { UInt8($0) }))
        #expect(printable.unicodeScalars.count == 32)
    }

    @Test("US-ASCII rejects bytes above 0x7F")
    func ascii() {
        #expect(TextEncoding.usASCII.decode(Array("plain text".utf8)) == "plain text")
        #expect(TextEncoding.usASCII.decode([0x41, 0x80]) == nil)
    }

    @Test("UTF-16 follows its byte order mark and defaults to big-endian")
    func utf16() {
        #expect(TextEncoding.utf16.decode([0xFE, 0xFF, 0x00, 0x41, 0x00, 0xE9]) == "A\u{E9}")
        #expect(TextEncoding.utf16.decode([0xFF, 0xFE, 0x41, 0x00, 0xE9, 0x00]) == "A\u{E9}")
        #expect(TextEncoding.utf16.decode([0x00, 0x41, 0x00, 0xE9]) == "A\u{E9}")
        #expect(TextEncoding.utf16BigEndian.decode([0x00, 0x41, 0xD8, 0x3D, 0xDE, 0x00]) == "A\u{1F600}")
        #expect(TextEncoding.utf16LittleEndian.decode([0x41, 0x00, 0x3D, 0xD8, 0x00, 0xDE]) == "A\u{1F600}")
        #expect(TextEncoding.utf16LittleEndian.decode([0xFF, 0xFE, 0x41, 0x00]) == "A")
    }

    @Test("Malformed UTF-16 is rejected")
    func malformedUTF16() {
        #expect(TextEncoding.utf16.decode([0x00, 0x41, 0x00]) == nil)
        #expect(TextEncoding.utf16BigEndian.decode([0xD8, 0x3D, 0x00, 0x41]) == nil)
        #expect(TextEncoding.utf16LittleEndian.decode([0x00, 0xDC]) == nil)
    }

    // MARK: Decoding text documents

    @Test("Valid UTF-8 is decoded without a warning, with the byte order mark handled as before")
    func utf8Document() throws {
        for bytes in [Array("caf\u{E9}\n".utf8), Self.utf8BOM + Array("caf\u{E9}\n".utf8)] {
            let decoded = try DecodedText(decoding: bytes, document: "memory:/a.txt")
            #expect(decoded.text == String(data: Data(bytes), encoding: .utf8))
            #expect(decoded.encoding == .utf8)
            #expect(decoded.warning == nil)
        }
    }

    @Test("Text that is not UTF-8 is read as ISO-8859-1 with a warning")
    func latin1Fallback() throws {
        let bytes = Array("first line\n".utf8) + Self.accentedLatin1
        let decoded = try DecodedText(decoding: bytes, document: "memory:/latin.txt")
        #expect(decoded.text == "first line\n" + Self.accented)
        #expect(decoded.encoding == .isoLatin1)
        let warning = try #require(decoded.warning)
        #expect(warning.severity == .warning)
        #expect(warning.code == TextDecodingDiagnostic.decodedAsISOLatin1)
        #expect(warning.document == "memory:/latin.txt")
        #expect(warning.message.contains(TextEncoding.utf8.name))
        #expect(warning.message.contains(TextEncoding.isoLatin1.name))
        let range = try #require(warning.range)
        #expect(range.start.line == 2)
        #expect(range.start.column == 4)
        #expect(range.start.utf8Offset == "first line\ncaf".utf8.count)
        #expect(range.utf8Length == "\u{E9}".utf8.count)
    }

    @Test("A byte after valid multi-byte UTF-8 is located in the decoded text")
    func fallbackPosition() throws {
        let bytes = Array("\u{E9}x".utf8) + [0xFF]
        let decoded = try DecodedText(decoding: bytes)
        #expect(decoded.text == "\u{C3}\u{A9}x\u{FF}")
        let range = try #require(decoded.warning?.range)
        #expect(range.start.utf8Offset == "\u{C3}\u{A9}x".utf8.count)
        #expect(range.start.column == 4)
        #expect(decoded.warning?.document == nil)
    }

    @Test("A UTF-16 byte order mark selects UTF-16 without a warning")
    func utf16Document() throws {
        let little = try DecodedText(decoding: [0xFF, 0xFE, 0x41, 0x00, 0xE9, 0x00])
        #expect(little.text == "A\u{E9}")
        #expect(little.encoding == .utf16)
        #expect(little.warning == nil)
        let big = try DecodedText(decoding: [0xFE, 0xFF, 0x00, 0x41])
        #expect(big.text == "A")
        #expect(big.encoding == .utf16)
    }

    @Test("An explicit encoding overrides detection and the fallback")
    func explicitEncoding() throws {
        let utf8Bytes = Array("caf\u{E9}".utf8)
        let latin = try DecodedText(decoding: utf8Bytes, encoding: .isoLatin1)
        #expect(latin.text == "caf\u{C3}\u{A9}")
        #expect(latin.encoding == .isoLatin1)
        #expect(latin.warning == nil)
        let windows = try DecodedText(decoding: [0x93, 0x41, 0x94], encoding: .windows1252)
        #expect(windows.text == "\u{201C}A\u{201D}")
        #expect(windows.warning == nil)
        #expect(throws: TextDecodingError.malformed(.utf8)) {
            _ = try DecodedText(decoding: Self.accentedLatin1, encoding: .utf8)
        }
        #expect(throws: TextDecodingError.malformed(.usASCII)) {
            _ = try DecodedText(decoding: utf8Bytes, encoding: .usASCII)
        }
    }

    @Test("Files are read with the same rules")
    func contentsOfFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextDecodingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("latin.txt")
        try Data(Self.accentedLatin1).write(to: url)
        let detected = try DecodedText(contentsOf: url)
        #expect(detected.text == Self.accented)
        #expect(detected.warning?.document == url.absoluteString)
        let explicit = try DecodedText(contentsOf: url, encoding: .isoLatin1)
        #expect(explicit.text == Self.accented)
        #expect(explicit.warning == nil)
        #expect(throws: (any Error).self) {
            _ = try DecodedText(contentsOf: directory.appendingPathComponent("absent.txt"))
        }
    }

    // MARK: Decoding XML documents

    /// The bytes of a small XML document with a declaration naming an encoding.
    private static func xml(declaring encoding: String?, body: [UInt8]) -> [UInt8] {
        let declaration = encoding.map { "<?xml version=\"1.0\" encoding=\"\($0)\"?>\n" } ?? ""
        return Array(declaration.utf8) + Array("<a>".utf8) + body + Array("</a>".utf8)
    }

    @Test("XML in UTF-8 decodes as before, whatever its declaration says")
    func xmlUTF8() throws {
        for declared in [nil, "UTF-8", "ISO-8859-1"] {
            let bytes = Self.xml(declaring: declared, body: Array("caf\u{E9}".utf8))
            let decoded = try DecodedText(decodingXML: bytes)
            #expect(decoded.text == String(data: Data(bytes), encoding: .utf8))
            #expect(decoded.encoding == .utf8)
            #expect(decoded.warning == nil)
        }
        let marked = Self.utf8BOM + Self.xml(declaring: "UTF-8", body: [])
        #expect(try DecodedText(decodingXML: marked).text == String(data: Data(marked), encoding: .utf8))
    }

    @Test("XML that is not UTF-8 is decoded in its declared encoding", arguments: [
        ("ISO-8859-1", TextEncoding.isoLatin1), ("iso-8859-1", .isoLatin1), ("latin1", .isoLatin1),
        ("windows-1252", .windows1252), ("Cp1252", .windows1252),
    ])
    func xmlDeclared(name: String, encoding: TextEncoding) throws {
        let decoded = try DecodedText(decodingXML: Self.xml(declaring: name, body: Self.accentedLatin1))
        #expect(decoded.text.hasSuffix("<a>" + Self.accented + "</a>"))
        #expect(decoded.encoding == encoding)
        #expect(decoded.warning == nil)
    }

    @Test("The declaration may use single quotes and extra spacing")
    func xmlDeclarationSyntax() throws {
        let bytes = Array("<?xml version='1.0'  encoding = 'ISO-8859-1' standalone='yes'?><a>".utf8) + [0xE9]
            + Array("</a>".utf8)
        #expect(try DecodedText(decodingXML: bytes).text == "<?xml version='1.0'  encoding = 'ISO-8859-1' standalone='yes'?><a>\u{E9}</a>")
    }

    @Test("XML in UTF-16 is recognised by its byte order mark or its first characters")
    func xmlUTF16() throws {
        let text = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><a>caf\u{E9}</a>"
        let bigEndian = text.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        let littleEndian = text.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        let marked = try DecodedText(decodingXML: [0xFE, 0xFF] + bigEndian)
        #expect(marked.text == text)
        #expect(marked.encoding == .utf16)
        let markedLittle = try DecodedText(decodingXML: [0xFF, 0xFE] + littleEndian)
        #expect(markedLittle.text == text)
        let unmarkedBig = try DecodedText(decodingXML: bigEndian)
        #expect(unmarkedBig.text == text)
        #expect(unmarkedBig.encoding == .utf16BigEndian)
        let unmarkedLittle = try DecodedText(decodingXML: littleEndian)
        #expect(unmarkedLittle.text == text)
        #expect(unmarkedLittle.encoding == .utf16LittleEndian)
    }

    @Test("XML that is not UTF-8 and declares no other encoding is rejected without a fallback")
    func xmlUndeclared() {
        #expect(throws: TextDecodingError.malformed(.utf8)) {
            _ = try DecodedText(decodingXML: Self.xml(declaring: nil, body: Self.accentedLatin1))
        }
        #expect(throws: TextDecodingError.malformed(.utf8)) {
            _ = try DecodedText(decodingXML: Self.xml(declaring: "UTF-8", body: Self.accentedLatin1))
        }
    }

    @Test("XML declaring an unsupported encoding or bytes invalid in it is rejected")
    func xmlUnsupported() {
        #expect(throws: TextDecodingError.unsupportedEncoding("ISO-8859-15")) {
            _ = try DecodedText(decodingXML: Self.xml(declaring: "ISO-8859-15", body: Self.accentedLatin1))
        }
        #expect(throws: TextDecodingError.malformed(.usASCII)) {
            _ = try DecodedText(decodingXML: Self.xml(declaring: "US-ASCII", body: Self.accentedLatin1))
        }
    }

    @Test("An explicit encoding overrides the declaration of an XML document")
    func xmlExplicit() throws {
        let bytes = Self.xml(declaring: "ISO-8859-1", body: Array("caf\u{E9}".utf8))
        let decoded = try DecodedText(decodingXML: bytes, encoding: .isoLatin1)
        #expect(decoded.text.hasSuffix("<a>caf\u{C3}\u{A9}</a>"))
        #expect(decoded.encoding == .isoLatin1)
    }
}
