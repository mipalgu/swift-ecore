//
// TextEncoding.swift
// EMFBase
//
// Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// A character encoding in which text documents can be read.
///
/// This is the authoritative list of the encodings that the modelling readers support.
/// Each case is identified by its preferred name in the IANA character set registry, so
/// the raw value can be shown to users, written into an XML declaration, or accepted as
/// the argument of a command line option. ``init(name:)`` also recognises the registered
/// aliases of each encoding.
///
/// ```swift
/// let encoding = TextEncoding(name: "latin1")        // .isoLatin1
/// let text = encoding?.decode(bytes)                 // nil if the bytes are not valid
/// ```
public enum TextEncoding: String, Sendable, Hashable, CaseIterable, Codable {
    /// UTF-8, the default encoding of XML and of every text format.
    case utf8 = "UTF-8"

    /// UTF-16 whose byte order follows a leading byte order mark, big-endian without one.
    case utf16 = "UTF-16"

    /// UTF-16 in big-endian byte order.
    case utf16BigEndian = "UTF-16BE"

    /// UTF-16 in little-endian byte order.
    case utf16LittleEndian = "UTF-16LE"

    /// ISO-8859-1 (Latin-1), in which every byte is the code point of the same value.
    case isoLatin1 = "ISO-8859-1"

    /// The Windows code page 1252, a superset of the printable characters of ISO-8859-1.
    case windows1252 = "windows-1252"

    /// US-ASCII, which has only the code points below 128.
    case usASCII = "US-ASCII"

    /// The preferred IANA name of the encoding.
    public var name: String { rawValue }

    /// The names under which the encoding is recognised, in normalised form.
    ///
    /// The list holds the preferred IANA name and the registered aliases, together with
    /// common spellings such as `latin1` or `cp1252`. Every name is lower case and has no
    /// hyphens, underscores, colons or spaces (see ``init(name:)``).
    public var aliases: [String] {
        switch self {
        case .utf8: return ["utf8", "csutf8"]
        case .utf16: return ["utf16", "csutf16"]
        case .utf16BigEndian: return ["utf16be", "csutf16be"]
        case .utf16LittleEndian: return ["utf16le", "csutf16le"]
        case .isoLatin1:
            return ["iso88591", "iso885911987", "isoir100", "latin1", "l1", "ibm819", "cp819", "csisolatin1"]
        case .windows1252: return ["windows1252", "cswindows1252", "cp1252"]
        case .usASCII:
            return ["usascii", "ascii", "ansix3.41968", "ansix3.41986", "isoir6", "iso646.irv1991", "iso646us",
                "us", "ibm367", "cp367", "csascii"]
        }
    }

    /// Finds the encoding with a given name.
    ///
    /// Names are compared without regard to case, and hyphens, underscores, colons and
    /// spaces are ignored, so `UTF-8`, `utf8` and `ISO_8859-1:1987` are all recognised.
    ///
    /// - Parameter name: The preferred IANA name or an alias of the encoding.
    /// - Returns: The encoding, or `nil` if the name names no supported encoding.
    public init?(name: String) {
        let normalised = Self.normalise(name)
        guard !normalised.isEmpty,
            let match = Self.allCases.first(where: { $0.aliases.contains(normalised) })
        else { return nil }
        self = match
    }

    /// Decodes bytes in this encoding.
    ///
    /// UTF-8 is decoded exactly as Foundation decodes it, which removes a leading byte
    /// order mark. For the UTF-16 encodings, a leading byte order mark is removed as well;
    /// ``utf16`` uses it to choose the byte order. ISO-8859-1 and windows-1252 accept every
    /// byte; the five bytes that windows-1252 leaves undefined are read as the control
    /// characters of the same value.
    ///
    /// - Parameter bytes: The encoded bytes.
    /// - Returns: The text, or `nil` if the bytes are not valid in this encoding.
    public func decode<Bytes: Collection>(_ bytes: Bytes) -> String? where Bytes.Element == UInt8 {
        switch self {
        case .utf8:
            return String(data: bytes as? Data ?? Data(bytes), encoding: .utf8)
        case .isoLatin1:
            return String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
        case .windows1252:
            return String(String.UnicodeScalarView(bytes.map(Self.windows1252Scalar)))
        case .usASCII:
            guard bytes.allSatisfy({ $0 < Self.asciiLimit }) else { return nil }
            return String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
        case .utf16:
            let units = Array(bytes)
            if units.starts(with: Self.littleEndianMark) { return Self.decodeUTF16(units, bigEndian: false) }
            return Self.decodeUTF16(units, bigEndian: true)
        case .utf16BigEndian:
            return Self.decodeUTF16(Array(bytes), bigEndian: true)
        case .utf16LittleEndian:
            return Self.decodeUTF16(Array(bytes), bigEndian: false)
        }
    }

    // MARK: Implementation

    /// The first byte value outside US-ASCII.
    private static let asciiLimit: UInt8 = 0x80

    /// The byte order mark of UTF-16 in big-endian order.
    static let bigEndianMark: [UInt8] = [0xFE, 0xFF]

    /// The byte order mark of UTF-16 in little-endian order.
    static let littleEndianMark: [UInt8] = [0xFF, 0xFE]

    /// The byte order mark as a code point.
    private static let byteOrderMark: UInt16 = 0xFEFF

    /// The characters that names may contain but that do not distinguish them.
    private static let ignoredNameCharacters: Set<Character> = ["-", "_", ":", " "]

    /// The code points of the bytes 0x80 to 0x9F in windows-1252.
    ///
    /// The bytes that the code page leaves undefined map to the control characters of the
    /// same value, as in the WHATWG encoding standard.
    private static let windows1252Upper: [UInt32] = [
        0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
        0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
    ]

    /// The first byte that ``windows1252Upper`` maps.
    private static let windows1252UpperStart: UInt8 = 0x80

    /// Normalises a name for comparison with ``aliases``.
    ///
    /// - Parameter name: The name as written.
    /// - Returns: The name in lower case without ignored characters or surrounding spaces.
    private static func normalise(_ name: String) -> String {
        String(name.lowercased().filter { !ignoredNameCharacters.contains($0) })
    }

    /// The code point of a byte in windows-1252.
    ///
    /// - Parameter byte: The byte.
    /// - Returns: The code point.
    private static func windows1252Scalar(_ byte: UInt8) -> Unicode.Scalar {
        let index = Int(byte) - Int(windows1252UpperStart)
        guard windows1252Upper.indices.contains(index), let scalar = Unicode.Scalar(windows1252Upper[index]) else {
            return Unicode.Scalar(byte)
        }
        return scalar
    }

    /// Decodes UTF-16 bytes in a given byte order.
    ///
    /// - Parameters:
    ///   - bytes: The bytes, possibly starting with a byte order mark.
    ///   - bigEndian: Whether the most significant byte of each code unit comes first.
    /// - Returns: The text without a leading byte order mark, or `nil` if the byte count is
    ///   odd or a surrogate is unpaired.
    private static func decodeUTF16(_ bytes: [UInt8], bigEndian: Bool) -> String? {
        guard bytes.count.isMultiple(of: 2) else { return nil }
        var units = stride(from: 0, to: bytes.count, by: 2).map { index -> UInt16 in
            let first = UInt16(bytes[index]), second = UInt16(bytes[index + 1])
            return bigEndian ? first << 8 | second : second << 8 | first
        }
        if units.first == byteOrderMark { units.removeFirst() }
        return String(validating: units, as: UTF16.self)
    }
}
