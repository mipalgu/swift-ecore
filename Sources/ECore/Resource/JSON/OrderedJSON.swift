//
// OrderedJSON.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// A JSON value whose objects keep their members in document order.
///
/// Metamodel documents are read and written with this representation, so that the order of
/// annotation details and the layout of a written document do not depend on how a dictionary
/// happens to order its keys.
enum OrderedJSON: Equatable, Sendable {
    /// A string.
    case string(String)

    /// A number without a fraction or exponent that fits into an `Int`.
    case integer(Int)

    /// Any other number.
    case number(Double)

    /// `true` or `false`.
    case boolean(Bool)

    /// `null`.
    case null

    /// An array of values.
    case array([OrderedJSON])

    /// An object, with its members in document order.
    case object([Member])

    /// A member of an object.
    struct Member: Equatable, Sendable {
        /// The key of the member.
        let key: String

        /// The value of the member.
        let value: OrderedJSON
    }

    /// The value of the last member of an object with a given key.
    ///
    /// - Parameter key: The key to look up.
    /// - Returns: The value, or `nil` if the value is not an object or has no such member.
    subscript(key: String) -> OrderedJSON? {
        guard case .object(let members) = self else { return nil }
        return members.last { $0.key == key }?.value
    }

    /// The members of an object, or `nil` for any other value.
    var members: [Member]? {
        if case .object(let members) = self { return members }
        return nil
    }

    /// The text of a string, or `nil` for any other value.
    var text: String? {
        if case .string(let text) = self { return text }
        return nil
    }
}

// MARK: - Parsing

extension OrderedJSON {
    /// The deepest nesting of arrays and objects that a document may have.
    static let maximumDepth = 128

    /// Parses a JSON document.
    ///
    /// A leading byte order mark and white space around the value are allowed; anything else
    /// after the value is an error.
    ///
    /// - Parameter data: The UTF-8 text of the document.
    /// - Returns: The value of the document.
    /// - Throws: ``JSONError/invalidFormat(_:)`` naming the line and column of the first error.
    static func parse(_ data: Data) throws -> OrderedJSON {
        var parser = OrderedJSONParser(bytes: Array(data))
        return try parser.document()
    }
}

/// Reads the bytes of a JSON document.
private struct OrderedJSONParser {
    /// The bytes that JSON syntax is made of.
    private enum Byte {
        /// The quotation mark that delimits strings.
        static let quote = UInt8(ascii: "\"")
        /// The backslash that starts an escape sequence.
        static let backslash = UInt8(ascii: "\\")
        /// The solidus, which strings may escape.
        static let slash = UInt8(ascii: "/")
        /// The brace that opens an object.
        static let openBrace = UInt8(ascii: "{")
        /// The brace that closes an object.
        static let closeBrace = UInt8(ascii: "}")
        /// The bracket that opens an array.
        static let openBracket = UInt8(ascii: "[")
        /// The bracket that closes an array.
        static let closeBracket = UInt8(ascii: "]")
        /// The colon between the key and the value of a member.
        static let colon = UInt8(ascii: ":")
        /// The comma between members and elements.
        static let comma = UInt8(ascii: ",")
        /// The sign of a negative number or exponent.
        static let minus = UInt8(ascii: "-")
        /// The sign of a positive exponent.
        static let plus = UInt8(ascii: "+")
        /// The decimal point.
        static let point = UInt8(ascii: ".")
        /// The first decimal digit.
        static let zero = UInt8(ascii: "0")
        /// The last decimal digit.
        static let nine = UInt8(ascii: "9")
        /// The exponent marker in lower case.
        static let lowerE = UInt8(ascii: "e")
        /// The exponent marker in upper case.
        static let upperE = UInt8(ascii: "E")
        /// The line feed that ends a line.
        static let newline = UInt8(ascii: "\n")
        /// The white space that may surround values.
        static let whiteSpace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        /// The UTF-8 byte order mark that may start a document.
        static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
        /// The first byte that a string may hold without an escape.
        static let firstPrintable: UInt8 = 0x20
        /// The characters that a single-character escape sequence stands for.
        static let escapes: [UInt8: UInt8] = [
            UInt8(ascii: "\""): UInt8(ascii: "\""), UInt8(ascii: "\\"): UInt8(ascii: "\\"),
            UInt8(ascii: "/"): UInt8(ascii: "/"), UInt8(ascii: "b"): 0x08, UInt8(ascii: "f"): 0x0C,
            UInt8(ascii: "n"): 0x0A, UInt8(ascii: "r"): 0x0D, UInt8(ascii: "t"): 0x09,
        ]
        /// The letter of a `\u` escape sequence.
        static let unicodeEscape = UInt8(ascii: "u")
    }

    /// The literal names and their values.
    private static let literals: [(text: [UInt8], value: OrderedJSON)] = [
        (Array("true".utf8), .boolean(true)), (Array("false".utf8), .boolean(false)), (Array("null".utf8), .null),
    ]

    /// The UTF-16 code units that start a surrogate pair.
    private static let highSurrogates: ClosedRange<UInt32> = 0xD800...0xDBFF
    /// The UTF-16 code units that end a surrogate pair.
    private static let lowSurrogates: ClosedRange<UInt32> = 0xDC00...0xDFFF

    /// The first code point beyond the basic multilingual plane, which a surrogate pair encodes.
    private static let supplementaryPlanes: UInt32 = 0x10000

    /// The number of bits of a code point that each code unit of a surrogate pair carries.
    private static let surrogateBits: UInt32 = 10

    /// The bytes of the document.
    private let bytes: [UInt8]
    /// The position of the next byte to read.
    private var position = 0
    /// The number of arrays and objects that enclose the current position.
    private var depth = 0

    /// Prepares to read a document.
    ///
    /// - Parameter bytes: The UTF-8 bytes of the document.
    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Reads the whole document.
    ///
    /// - Returns: The value of the document.
    /// - Throws: ``JSONError/invalidFormat(_:)`` at the first error.
    mutating func document() throws -> OrderedJSON {
        if bytes.starts(with: Byte.byteOrderMark) { position = Byte.byteOrderMark.count }
        skipWhiteSpace()
        let value = try self.value()
        skipWhiteSpace()
        guard position == bytes.count else { throw failure("unexpected text after the document") }
        return value
    }

    // MARK: Values

    /// Reads a value.
    ///
    /// - Returns: The value.
    /// - Throws: ``JSONError/invalidFormat(_:)`` if no value starts at the current position.
    private mutating func value() throws -> OrderedJSON {
        guard let byte = current else { throw failure("unexpected end of the document") }
        switch byte {
        case Byte.openBrace: return try nested { try $0.object() }
        case Byte.openBracket: return try nested { try $0.array() }
        case Byte.quote: return .string(try string())
        case Byte.minus, Byte.zero...Byte.nine: return try number()
        default:
            for literal in Self.literals where bytes[position...].starts(with: literal.text) {
                position += literal.text.count
                return literal.value
            }
            throw failure("unexpected character")
        }
    }

    /// Reads an array or object one level deeper, refusing documents that nest too deeply.
    ///
    /// - Parameter read: Reads the array or object.
    /// - Returns: The value read.
    /// - Throws: ``JSONError/invalidFormat(_:)`` if the nesting is too deep or the value is malformed.
    private mutating func nested(_ read: (inout OrderedJSONParser) throws -> OrderedJSON) throws -> OrderedJSON {
        depth += 1
        defer { depth -= 1 }
        guard depth <= OrderedJSON.maximumDepth else {
            throw failure("arrays and objects are nested more than \(OrderedJSON.maximumDepth) levels deep")
        }
        return try read(&self)
    }

    /// Reads an object, keeping its members in order.
    ///
    /// - Returns: The object.
    /// - Throws: ``JSONError/invalidFormat(_:)`` if the object is malformed.
    private mutating func object() throws -> OrderedJSON {
        position += 1
        var members: [OrderedJSON.Member] = []
        skipWhiteSpace()
        if current == Byte.closeBrace {
            position += 1
            return .object(members)
        }
        while true {
            skipWhiteSpace()
            guard current == Byte.quote else { throw failure("expected the quoted key of a member") }
            let key = try string()
            skipWhiteSpace()
            try expect(Byte.colon, "expected ':' after the key \"\(key)\"")
            skipWhiteSpace()
            members.append(OrderedJSON.Member(key: key, value: try value()))
            skipWhiteSpace()
            if current == Byte.comma {
                position += 1
                continue
            }
            try expect(Byte.closeBrace, "expected ',' or '}' in an object")
            return .object(members)
        }
    }

    /// Reads an array.
    ///
    /// - Returns: The array.
    /// - Throws: ``JSONError/invalidFormat(_:)`` if the array is malformed.
    private mutating func array() throws -> OrderedJSON {
        position += 1
        var elements: [OrderedJSON] = []
        skipWhiteSpace()
        if current == Byte.closeBracket {
            position += 1
            return .array(elements)
        }
        while true {
            skipWhiteSpace()
            elements.append(try value())
            skipWhiteSpace()
            if current == Byte.comma {
                position += 1
                continue
            }
            try expect(Byte.closeBracket, "expected ',' or ']' in an array")
            return .array(elements)
        }
    }

    /// Reads a string, decoding its escape sequences.
    ///
    /// - Returns: The text of the string.
    /// - Throws: ``JSONError/invalidFormat(_:)`` if the string is malformed or unterminated.
    private mutating func string() throws -> String {
        position += 1
        var text: [UInt8] = []
        while let byte = current {
            position += 1
            switch byte {
            case Byte.quote:
                return String(decoding: text, as: UTF8.self)
            case Byte.backslash:
                guard let escape = current else { break }
                position += 1
                if let replacement = Byte.escapes[escape] {
                    text.append(replacement)
                } else if escape == Byte.unicodeEscape {
                    text.append(contentsOf: Array(String(try unicodeScalar()).utf8))
                } else {
                    position -= 1
                    throw failure("invalid escape sequence in a string")
                }
            case ..<Byte.firstPrintable:
                position -= 1
                throw failure("control character in a string")
            default:
                text.append(byte)
            }
        }
        throw failure("unterminated string")
    }

    /// Reads the hexadecimal digits of a `\u` escape, and a second escape for a surrogate pair.
    ///
    /// - Returns: The character that the escape stands for.
    /// - Throws: ``JSONError/invalidFormat(_:)`` if the escape is malformed or a surrogate is unpaired.
    private mutating func unicodeScalar() throws -> Unicode.Scalar {
        let first = try hexadecimalCodeUnit()
        if Self.highSurrogates.contains(first) {
            guard current == Byte.backslash, position + 1 < bytes.count, bytes[position + 1] == Byte.unicodeEscape
            else { throw failure("unpaired surrogate in a string") }
            position += 2
            let second = try hexadecimalCodeUnit()
            guard Self.lowSurrogates.contains(second) else { throw failure("unpaired surrogate in a string") }
            let high = first - Self.highSurrogates.lowerBound
            let low = second - Self.lowSurrogates.lowerBound
            let value = Self.supplementaryPlanes + (high << Self.surrogateBits) + low
            if let scalar = Unicode.Scalar(value) { return scalar }
        } else if let scalar = Unicode.Scalar(first) {
            return scalar
        }
        throw failure("invalid character escape in a string")
    }

    /// Reads the four hexadecimal digits of a UTF-16 code unit.
    ///
    /// - Returns: The code unit.
    /// - Throws: ``JSONError/invalidFormat(_:)`` if there are not four hexadecimal digits.
    private mutating func hexadecimalCodeUnit() throws -> UInt32 {
        let digits = 4
        guard position + digits <= bytes.count,
            let value = UInt32(String(decoding: bytes[position..<position + digits], as: UTF8.self), radix: 16)
        else { throw failure("expected four hexadecimal digits after \\u") }
        position += digits
        return value
    }

    /// Reads a number.
    ///
    /// - Returns: An integer if the number has no fraction or exponent and fits into an `Int`,
    ///   otherwise a floating point number.
    /// - Throws: ``JSONError/invalidFormat(_:)`` if the number is malformed.
    private mutating func number() throws -> OrderedJSON {
        let start = position
        var isInteger = true
        if current == Byte.minus { position += 1 }
        let integerStart = position
        let integerDigits = digits()
        guard integerDigits > 0 else { throw failure("expected a digit") }
        if integerDigits > 1, bytes[integerStart] == Byte.zero {
            throw failure("a number must not start with a zero")
        }
        if current == Byte.point {
            isInteger = false
            position += 1
            guard digits() > 0 else { throw failure("expected a digit after the decimal point") }
        }
        if current == Byte.lowerE || current == Byte.upperE {
            isInteger = false
            position += 1
            if current == Byte.plus || current == Byte.minus { position += 1 }
            guard digits() > 0 else { throw failure("expected a digit in the exponent") }
        }
        let text = String(decoding: bytes[start..<position], as: UTF8.self)
        if isInteger, let value = Int(text) { return .integer(value) }
        guard let value = Double(text) else { throw failure("invalid number") }
        return .number(value)
    }

    /// Skips decimal digits.
    ///
    /// - Returns: The number of digits skipped.
    private mutating func digits() -> Int {
        let start = position
        while let byte = current, (Byte.zero...Byte.nine).contains(byte) { position += 1 }
        return position - start
    }

    // MARK: Positions

    /// The byte at the current position, or `nil` at the end of the document.
    private var current: UInt8? {
        position < bytes.count ? bytes[position] : nil
    }

    /// Skips white space.
    private mutating func skipWhiteSpace() {
        while let byte = current, Byte.whiteSpace.contains(byte) { position += 1 }
    }

    /// Reads a byte that must come next.
    ///
    /// - Parameters:
    ///   - byte: The expected byte.
    ///   - message: The description of the error if the byte does not come next.
    /// - Throws: ``JSONError/invalidFormat(_:)`` if the byte does not come next.
    private mutating func expect(_ byte: UInt8, _ message: String) throws {
        guard current == byte else { throw failure(message) }
        position += 1
    }

    /// An error at the current position, naming its line and column.
    ///
    /// - Parameter message: What is wrong.
    /// - Returns: The error.
    private func failure(_ message: String) -> JSONError {
        let end = min(position, bytes.count)
        let preceding = bytes[..<end]
        let line = preceding.reduce(1) { $1 == Byte.newline ? $0 + 1 : $0 }
        let lineStart = preceding.lastIndex(of: Byte.newline).map { $0 + 1 } ?? 0
        let column = String(decoding: bytes[lineStart..<end], as: UTF8.self).count + 1
        return .invalidFormat("malformed JSON at line \(line), column \(column): \(message)")
    }
}

// MARK: - Writing

extension OrderedJSON {
    /// The number of spaces by which each level of nesting is indented.
    static let indentWidth = 2

    /// The text of the value as a document, ending in a newline.
    ///
    /// Members and elements are written one per line, indented by two spaces per level, with
    /// a space after each colon. Empty arrays and objects are written as `[]` and `{}`.
    /// Strings escape quotes, backslashes and control characters only.
    var document: String {
        var output = ""
        write(to: &output, depth: 0)
        return output + "\n"
    }

    /// Appends the text of the value.
    ///
    /// - Parameters:
    ///   - output: The text written so far.
    ///   - depth: The nesting depth of the value.
    private func write(to output: inout String, depth: Int) {
        switch self {
        case .string(let text): Self.writeString(text, to: &output)
        case .integer(let value): output += String(value)
        case .number(let value): output += String(value)
        case .boolean(let value): output += value ? "true" : "false"
        case .null: output += "null"
        case .array(let elements):
            guard !elements.isEmpty else {
                output += "[]"
                return
            }
            output += "["
            for (index, element) in elements.enumerated() {
                output += (index == 0 ? "\n" : ",\n") + Self.indentation(depth + 1)
                element.write(to: &output, depth: depth + 1)
            }
            output += "\n" + Self.indentation(depth) + "]"
        case .object(let members):
            guard !members.isEmpty else {
                output += "{}"
                return
            }
            output += "{"
            for (index, member) in members.enumerated() {
                output += (index == 0 ? "\n" : ",\n") + Self.indentation(depth + 1)
                Self.writeString(member.key, to: &output)
                output += ": "
                member.value.write(to: &output, depth: depth + 1)
            }
            output += "\n" + Self.indentation(depth) + "}"
        }
    }

    /// The indentation of a nesting depth.
    ///
    /// - Parameter depth: The depth.
    /// - Returns: The spaces that indent it.
    private static func indentation(_ depth: Int) -> String {
        String(repeating: " ", count: depth * indentWidth)
    }

    /// The escapes of the characters that a JSON string cannot hold as they are.
    private static let escapes: [Unicode.Scalar: String] = [
        "\"": "\\\"", "\\": "\\\\", "\n": "\\n", "\r": "\\r", "\t": "\\t", "\u{08}": "\\b", "\u{0C}": "\\f",
    ]

    /// The first code point that a JSON string holds without an escape.
    private static let firstPrintable: UInt32 = 0x20

    /// Appends a quoted, escaped string.
    ///
    /// - Parameters:
    ///   - text: The text of the string.
    ///   - output: The text written so far.
    private static func writeString(_ text: String, to output: inout String) {
        output += "\""
        for scalar in text.unicodeScalars {
            if let escape = escapes[scalar] {
                output += escape
            } else if scalar.value < firstPrintable {
                let hex = String(scalar.value, radix: 16, uppercase: false)
                output += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }
}
