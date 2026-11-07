//
// JSONText.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// Writes JSON values as text that is the same on every platform.
///
/// Model documents are written in the layout of `JSONSerialization` with the options
/// `prettyPrinted`, `sortedKeys` and `withoutEscapingSlashes`: members and elements one per
/// line, indented by two spaces per level, with `" : "` between a key and its value, and keys
/// in the order of that layout. Numbers with a fraction or an exponent are written in their
/// shortest form that reads back as the same number (see ``number(_:)``), so the same model
/// gives the same text whichever platform or toolchain writes it.
enum JSONText {
    /// The number of spaces by which each level of nesting is indented.
    static let indentWidth = 2

    /// The text between the key and the value of a member.
    static let memberSeparator = " : "

    /// The text between the members of an object or the elements of an array.
    static let elementSeparator = ",\n"

    /// The comparison options that put the keys of an object in order.
    ///
    /// Keys are compared numerically and without regard to case, as `JSONSerialization`
    /// compares them for sorted keys, so that `item2` comes before `item10`.
    static let keyOrder: String.CompareOptions = [.numeric, .caseInsensitive, .forcedOrdering]

    /// The suffix that the description of a whole number ends in.
    private static let wholeNumberSuffix = ".0"

    /// The text of the JSON literal `true`.
    private static let trueLiteral = "true"

    /// The text of the JSON literal `false`.
    private static let falseLiteral = "false"

    /// The text of the JSON literal `null`.
    private static let nullLiteral = "null"

    /// The escapes of the characters that a JSON string cannot hold as they are.
    private static let escapes: [Unicode.Scalar: String] = [
        "\"": "\\\"", "\\": "\\\\", "\n": "\\n", "\r": "\\r", "\t": "\\t", "\u{08}": "\\b", "\u{0C}": "\\f",
    ]

    /// The first code point that a JSON string holds without an escape.
    private static let firstPrintable: UInt32 = 0x20

    /// The number of hexadecimal digits of a `\u` escape.
    private static let unicodeEscapeDigits = 4

    // MARK: Numbers

    /// The shortest JSON text of a floating point number that reads back as the same number.
    ///
    /// The text is the description of the number, which has as few significant digits as
    /// identify the number among those of its type: `87.2` rather than `87.200000000000003`.
    /// A whole number is written without a fraction (`92`, `-0`), and a very large or very
    /// small number with an exponent (`1e+16`, `1e-07`), as the description writes it.
    ///
    /// - Parameter value: The number.
    /// - Returns: The text, or `nil` if the number is infinite or not a number, which JSON
    ///   cannot hold.
    static func number<Value: BinaryFloatingPoint & LosslessStringConvertible>(_ value: Value) -> String? {
        guard value.isFinite else { return nil }
        let text = value.description
        return text.hasSuffix(wholeNumberSuffix) ? String(text.dropLast(wholeNumberSuffix.count)) : text
    }

    // MARK: Documents

    /// The text of a document.
    ///
    /// The document is made of dictionaries with string keys, arrays, strings, Booleans,
    /// integers, floating point numbers and `NSNull`. The text has no trailing newline.
    ///
    /// - Parameter value: The root value.
    /// - Returns: The text.
    /// - Throws: ``JSONError`` if a number is infinite or not a number, or a value has no
    ///   JSON form.
    static func document(_ value: Any) throws -> String {
        var output = ""
        try write(value, to: &output, depth: 0)
        return output
    }

    /// Appends the text of a value.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - output: The text written so far.
    ///   - depth: The nesting depth of the value.
    /// - Throws: ``JSONError`` if the value or a value that it holds cannot be written.
    private static func write(_ value: Any, to output: inout String, depth: Int) throws {
        switch value {
        case let text as String: writeString(text, to: &output)
        case let flag as Bool: output += flag ? trueLiteral : falseLiteral
        case let integer as any BinaryInteger: output += String(describing: integer)
        case let number as Double: output += try text(of: number)
        case let number as Float: output += try text(of: number)
        case let object as [String: Any]: try writeObject(object, to: &output, depth: depth)
        case let elements as [Any]: try writeArray(elements, to: &output, depth: depth)
        case is NSNull: output += nullLiteral
        default: throw JSONError.unwritableValue(value)
        }
    }

    /// The text of a number that a document holds.
    ///
    /// - Parameter value: The number.
    /// - Returns: The text.
    /// - Throws: ``JSONError`` if the number is infinite or not a number.
    private static func text<Value: BinaryFloatingPoint & LosslessStringConvertible>(of value: Value) throws
        -> String
    {
        guard let text = number(value) else { throw JSONError.invalidNumber(value.description) }
        return text
    }

    /// Appends an array, one element per line.
    ///
    /// - Parameters:
    ///   - elements: The elements.
    ///   - output: The text written so far.
    ///   - depth: The nesting depth of the array.
    /// - Throws: ``JSONError`` if an element cannot be written.
    private static func writeArray(_ elements: [Any], to output: inout String, depth: Int) throws {
        output += "[\n"
        for (index, element) in elements.enumerated() {
            if index > 0 { output += elementSeparator }
            output += indentation(depth + 1)
            try write(element, to: &output, depth: depth + 1)
        }
        output += "\n" + indentation(depth) + "]"
    }

    /// Appends an object, one member per line, with its keys in order.
    ///
    /// - Parameters:
    ///   - object: The members.
    ///   - output: The text written so far.
    ///   - depth: The nesting depth of the object.
    /// - Throws: ``JSONError`` if a value cannot be written.
    private static func writeObject(_ object: [String: Any], to output: inout String, depth: Int) throws {
        output += "{\n"
        let locale: Locale = NSLocale.system
        let members = object.sorted { first, second in
            first.key.compare(second.key, options: keyOrder, range: nil, locale: locale) == .orderedAscending
        }
        for (index, member) in members.enumerated() {
            if index > 0 { output += elementSeparator }
            output += indentation(depth + 1)
            writeString(member.key, to: &output)
            output += memberSeparator
            try write(member.value, to: &output, depth: depth + 1)
        }
        output += "\n" + indentation(depth) + "}"
    }

    /// The indentation of a nesting depth.
    ///
    /// - Parameter depth: The depth.
    /// - Returns: The spaces that indent it.
    private static func indentation(_ depth: Int) -> String {
        String(repeating: " ", count: depth * indentWidth)
    }

    /// Appends a quoted string, escaping quotes, backslashes and control characters only.
    ///
    /// - Parameters:
    ///   - text: The text of the string.
    ///   - output: The text written so far.
    static func writeString(_ text: String, to output: inout String) {
        output += "\""
        for scalar in text.unicodeScalars {
            if let escape = escapes[scalar] {
                output += escape
            } else if scalar.value < firstPrintable {
                let hex = String(scalar.value, radix: 16, uppercase: false)
                output += "\\u" + String(repeating: "0", count: unicodeEscapeDigits - hex.count) + hex
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }
}

extension JSONError {
    /// The error for a number that JSON cannot hold.
    ///
    /// - Parameter description: The description of the number, such as `nan` or `inf`.
    /// - Returns: The error.
    static func invalidNumber(_ description: String) -> JSONError {
        .parseError("Cannot write the number \(description) in JSON")
    }

    /// The error for a value that has no JSON form.
    ///
    /// - Parameter value: The value.
    /// - Returns: The error.
    static func unwritableValue(_ value: Any) -> JSONError {
        .parseError("Cannot write a value of type \(type(of: value)) in JSON")
    }
}
