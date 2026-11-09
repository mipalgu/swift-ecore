//
// TextEncodingTests.swift
// EMFBaseTests
//
// Copyright © 2026 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import EMFBase

/// Verifies the encoding of text and XML documents in the supported encodings.
@Suite("Text encoding")
struct TextEncodingTests {
    /// A text with characters outside ASCII that ISO-8859-1 can represent.
    private static let accented = "caf\u{E9} na\u{EF}ve"

    /// The ISO-8859-1 bytes of ``accented``.
    private static let accentedLatin1: [UInt8] =
        Array("caf".utf8) + [0xE9] + Array(" na".utf8) + [0xEF] + Array("ve".utf8)

    /// The euro sign, which windows-1252 holds but ISO-8859-1 does not.
    private static let euro: Unicode.Scalar = "\u{20AC}"

    /// A character that none of the single-byte encodings holds.
    private static let snowman: Unicode.Scalar = "\u{2603}"

    // MARK: Plain text

    @Test("UTF-8 encodes exactly as Foundation writes UTF-8", arguments: ["", "plain", accented, "\u{1F600}\r\n\u{FEFF}x"])
    func utf8MatchesFoundation(text: String) throws {
        #expect(try TextEncoding.utf8.encode(text) == text.data(using: .utf8))
    }

    @Test("Every supported encoding decodes what it encodes", arguments: TextEncoding.allCases)
    func roundTrip(encoding: TextEncoding) throws {
        let text = "Plain ASCII text\nwith two lines\r\n"
        #expect(encoding.decode(try encoding.encode(text)) == text)
    }

    @Test("ISO-8859-1 writes every code point below 256 as one byte")
    func latin1() throws {
        #expect(try Array(TextEncoding.isoLatin1.encode(Self.accented)) == Self.accentedLatin1)
        let all = String(String.UnicodeScalarView((0...255).compactMap { Unicode.Scalar(UInt32($0)) }))
        #expect(try Array(TextEncoding.isoLatin1.encode(all)) == (0...255).map { UInt8($0) })
    }

    @Test("windows-1252 writes the printable characters of 0x80 to 0x9F and the bytes it leaves undefined")
    func windows1252() throws {
        let text = String(String.UnicodeScalarView([Self.euro, "\u{201C}", "\u{2122}", "\u{81}", "\u{9D}", "\u{E9}", "A"]))
        #expect(try Array(TextEncoding.windows1252.encode(text)) == [0x80, 0x93, 0x99, 0x81, 0x9D, 0xE9, 0x41])
        let every = (0...255).map { UInt8($0) }
        let decoded = try #require(TextEncoding.windows1252.decode(every))
        #expect(try Array(TextEncoding.windows1252.encode(decoded)) == every)
    }

    @Test("windows-1252 rejects the control characters whose bytes hold printable characters")
    func windows1252Controls() {
        #expect(!TextEncoding.windows1252.canEncode("\u{80}"))
        #expect(!TextEncoding.windows1252.canEncode("\u{93}"))
        #expect(TextEncoding.windows1252.canEncode("\u{8D}"))
    }

    @Test("UTF-16 writes a big-endian byte order mark; the variants with a byte order write none")
    func utf16() throws {
        let text = "A\u{1F600}"
        #expect(try Array(TextEncoding.utf16.encode(text)) == [0xFE, 0xFF, 0x00, 0x41, 0xD8, 0x3D, 0xDE, 0x00])
        #expect(try Array(TextEncoding.utf16BigEndian.encode(text)) == [0x00, 0x41, 0xD8, 0x3D, 0xDE, 0x00])
        #expect(try Array(TextEncoding.utf16LittleEndian.encode(text)) == [0x41, 0x00, 0x3D, 0xD8, 0x00, 0xDE])
    }

    @Test("Which characters each encoding holds")
    func canEncode() {
        for encoding in TextEncoding.allCases { #expect(encoding.canEncode("A")) }
        #expect(TextEncoding.utf8.canEncode(Self.snowman))
        #expect(TextEncoding.utf16LittleEndian.canEncode(Self.snowman))
        #expect(TextEncoding.isoLatin1.canEncode("\u{FF}"))
        #expect(!TextEncoding.isoLatin1.canEncode(Self.euro))
        #expect(TextEncoding.windows1252.canEncode(Self.euro))
        #expect(!TextEncoding.windows1252.canEncode(Self.snowman))
        #expect(!TextEncoding.usASCII.canEncode("\u{E9}"))
    }

    @Test("A character that the encoding cannot hold is an error with its line and column")
    func unrepresentable() throws {
        let text = "first line\r\nsecond \u{E9}\nthird \u{2603} line"
        let error = try #require(throws: TextEncodingError.self) { try TextEncoding.isoLatin1.encode(text) }
        guard case .unrepresentable(let character, let encoding, let position) = error else {
            Issue.record("unexpected error \(error)")
            return
        }
        #expect(character == Self.snowman)
        #expect(encoding == .isoLatin1)
        #expect(position.line == 3)
        #expect(position.column == 7)
        #expect(position.utf8Offset == "first line\r\nsecond \u{E9}\nthird ".utf8.count)
        #expect(error.description == "the character '\u{2603}' (U+2603) at line 3, column 7 cannot be written in ISO-8859-1")
    }

    @Test("Columns count Unicode scalars, as in source positions")
    func columnsCountScalars() throws {
        let error = try #require(throws: TextEncodingError.self) { try TextEncoding.usASCII.encode("\u{1F600}x\u{E9}") }
        #expect(error == .unrepresentable("\u{1F600}", encoding: .usASCII, position: .start))
    }

    // MARK: Precomposition

    /// An e followed by a combining acute accent, as file systems often store it.
    private static let decomposed = "caf" + "e\u{301}"

    @Test("Decomposed characters are written precomposed in the single-byte encodings",
        arguments: [TextEncoding.isoLatin1, .windows1252])
    func precomposes(encoding: TextEncoding) throws {
        #expect(try Array(encoding.encode(Self.decomposed)) == [0x63, 0x61, 0x66, 0xE9])
        let xml = try encoding.encode(xmlDocument: "<a b=\"\(Self.decomposed)\">\(Self.decomposed)</a>")
        #expect(encoding.decode(xml)?.hasSuffix("<a b=\"caf\u{E9}\">caf\u{E9}</a>") == true)
    }

    @Test("UTF-8 keeps decomposed characters as they are")
    func utf8KeepsDecomposition() throws {
        #expect(try TextEncoding.utf8.encode(Self.decomposed) == Data(Self.decomposed.utf8))
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><a>\(Self.decomposed)</a>"
        #expect(try TextEncoding.utf8.encode(xmlDocument: xml) == Data(xml.utf8))
        #expect(try TextEncoding.utf8.encode(document: xml, as: .json).data == Data(xml.utf8))
    }

    @Test("A character without a precomposed form in the encoding is still an error or a reference")
    func precompositionFallback() throws {
        let text = "q\u{301}"
        #expect(throws: TextEncodingError.self) { try TextEncoding.isoLatin1.encode(text) }
        let xml = try TextEncoding.isoLatin1.encode(xmlDocument: "<a>\(text)</a>")
        #expect(TextEncoding.isoLatin1.decode(xml)?.hasSuffix("<a>q&#x301;</a>") == true)
        #expect(throws: TextEncodingError.self) { try TextEncoding.usASCII.encode(Self.decomposed) }
    }

    // MARK: XML documents

    /// A document as the XML writers produce it.
    private static let document = """
        <?xml version="1.0" encoding="UTF-8"?>
        <xmi:XMI xmi:version="2.0" name="caf\u{E9} \u{2603}">
          <child value="\u{20AC}&amp;"/>text \u{2603}
        </xmi:XMI>

        """

    @Test("UTF-8 XML is written unchanged")
    func utf8XML() throws {
        #expect(try TextEncoding.utf8.encode(xmlDocument: Self.document) == Data(Self.document.utf8))
    }

    @Test("The XML declaration names the encoding in which the document is written")
    func xmlDeclaration() throws {
        let data = try TextEncoding.isoLatin1.encode(xmlDocument: Self.document)
        let text = try #require(TextEncoding.isoLatin1.decode(data))
        #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n<xmi:XMI"))
        #expect(data.contains(0xE9))
    }

    @Test("Characters that the encoding cannot hold become numeric character references")
    func characterReferences() throws {
        let data = try TextEncoding.isoLatin1.encode(xmlDocument: Self.document)
        let text = try #require(TextEncoding.isoLatin1.decode(data))
        #expect(text == """
            <?xml version="1.0" encoding="ISO-8859-1"?>
            <xmi:XMI xmi:version="2.0" name="caf\u{E9} &#x2603;">
              <child value="&#x20AC;&amp;"/>text &#x2603;
            </xmi:XMI>

            """)
        let windows = try #require(TextEncoding.windows1252.decode(try TextEncoding.windows1252.encode(xmlDocument: Self.document)))
        #expect(windows.contains("value=\"\u{20AC}&amp;\""))
        #expect(windows.contains("encoding=\"windows-1252\""))
        let ascii = try #require(TextEncoding.usASCII.decode(try TextEncoding.usASCII.encode(xmlDocument: Self.document)))
        #expect(ascii.contains("name=\"caf&#xE9; &#x2603;\""))
    }

    @Test("UTF-16 XML names its encoding and holds every character")
    func utf16XML() throws {
        let data = try TextEncoding.utf16.encode(xmlDocument: Self.document)
        #expect(data.starts(with: [0xFE, 0xFF]))
        let text = try #require(TextEncoding.utf16.decode(data))
        #expect(text == Self.document.replacingOccurrences(of: "encoding=\"UTF-8\"", with: "encoding=\"UTF-16\""))
    }

    @Test("A declaration without an encoding gains one, and a document without a declaration gains a declaration")
    func missingDeclaration() throws {
        let bare = try TextEncoding.isoLatin1.encode(xmlDocument: "<?xml version=\"1.0\" standalone='yes'?><a/>")
        #expect(TextEncoding.isoLatin1.decode(bare) == "<?xml version=\"1.0\" encoding=\"ISO-8859-1\" standalone='yes'?><a/>")
        let none = try TextEncoding.isoLatin1.encode(xmlDocument: "<a>\u{E9}</a>")
        #expect(TextEncoding.isoLatin1.decode(none) == "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n<a>\u{E9}</a>")
        #expect(try TextEncoding.utf8.encode(xmlDocument: "<a/>") == Data("<a/>".utf8))
    }

    @Test("Single-quoted encodings and other declarations are rewritten in place")
    func singleQuotedDeclaration() throws {
        let data = try TextEncoding.usASCII.encode(xmlDocument: "<?xml version='1.0' encoding='utf-8'?>\n<a b='\u{E9}'/>")
        #expect(TextEncoding.usASCII.decode(data) == "<?xml version='1.0' encoding='US-ASCII'?>\n<a b='&#xE9;'/>")
    }

    @Test("Characters in markup that cannot hold references are an error", arguments: [
        ("<?xml version=\"1.0\"?>\n<!-- \u{2603} -->", 2, 6),
        ("<?xml version=\"1.0\"?>\n<a><![CDATA[\u{2603}]]></a>", 2, 13),
        ("<?xml version=\"1.0\"?>\n<\u{2603}/>", 2, 2),
        ("<?xml version=\"1.0\"?>\n<a \u{2603}=\"x\"/>", 2, 4),
        ("<?xml version=\"1.0\"?>\n<?pi \u{2603}?><a/>", 2, 6),
    ])
    func unrepresentableMarkup(text: String, line: Int, column: Int) throws {
        let error = try #require(throws: TextEncodingError.self) { try TextEncoding.isoLatin1.encode(xmlDocument: text) }
        guard case .unrepresentable(let character, _, let position) = error else {
            Issue.record("unexpected error \(error)")
            return
        }
        #expect(character == Self.snowman)
        #expect(position.line == line)
        #expect(position.column == column)
    }

    @Test("Text after comments, CDATA sections and processing instructions is escaped again")
    func escapingResumes() throws {
        let text = "<?xml version=\"1.0\"?>\n<a><!-- x --><![CDATA[y]]><?p z?>\u{2603}<b c=\"\u{2603}\">\u{2603}</b></a>"
        let data = try TextEncoding.isoLatin1.encode(xmlDocument: text)
        #expect(TextEncoding.isoLatin1.decode(data) == "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n"
            + "<a><!-- x --><![CDATA[y]]><?p z?>&#x2603;<b c=\"&#x2603;\">&#x2603;</b></a>")
    }

    // MARK: Documents by kind

    @Test("Documents are encoded by kind, and JSON is always UTF-8")
    func documentKinds() throws {
        let json = try TextEncoding.isoLatin1.encode(document: "{\"a\":\"\u{2603}\"}", as: .json)
        #expect(json.encoding == .utf8)
        #expect(json.data == Data("{\"a\":\"\u{2603}\"}".utf8))
        let xml = try TextEncoding.isoLatin1.encode(document: "<a>\u{2603}</a>", as: .xml)
        #expect(xml.encoding == .isoLatin1)
        #expect(TextEncoding.isoLatin1.decode(xml.data)?.hasSuffix("<a>&#x2603;</a>") == true)
        let text = try TextEncoding.isoLatin1.encode(document: Self.accented, as: .text)
        #expect(text.encoding == .isoLatin1)
        #expect(Array(text.data) == Self.accentedLatin1)
        #expect(throws: TextEncodingError.self) { try TextEncoding.isoLatin1.encode(document: "\u{2603}", as: .text) }
        let utf8JSON = try TextEncoding.utf8.encode(document: "{}", as: .json)
        #expect(utf8JSON.encoding == .utf8)
    }

    @Test("The kind of a document follows its contents when it is not known")
    func detectedKinds() {
        #expect(TextDocumentKind(detecting: "<?xml version=\"1.0\"?><a/>") == .xml)
        #expect(TextDocumentKind(detecting: "\u{FEFF}<?xml version=\"1.0\"?><a/>") == .xml)
        #expect(TextDocumentKind(detecting: "package a;") == .text)
        #expect(TextDocumentKind(detecting: "") == .text)
    }
}
