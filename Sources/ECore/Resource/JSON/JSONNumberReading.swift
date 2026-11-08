//
// JSONNumberReading.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// A number of a model document together with the text that gives its exact value.
///
/// `JSONSerialization` reads the integer `-0` as zero, which has no sign. The reader keeps
/// such a number as it was read, so that it is still an integer, and pairs it with the text
/// that a floating point attribute reads as negative zero.
struct JSONNumberText: CustomStringConvertible {
    /// The number as `JSONSerialization` read it.
    let number: NSNumber

    /// The text from which the number's exact value reads back.
    let text: String

    /// The text of the number.
    var description: String { text }
}

/// Reads the numbers of model documents exactly as they are written.
///
/// `JSONSerialization` holds a number with many significant digits as an `NSDecimalNumber`,
/// whose `doubleValue` may differ from the nearest floating point number by a unit in the
/// last place, and some platforms describe a floating point `NSNumber` with fewer digits
/// than it needs to read back as the same number. These functions take the exact value of
/// each number instead, so that a document reads back as the numbers that were written.
enum JSONNumbers {
    /// The number that a JSON value holds.
    ///
    /// - Parameter json: A value that `JSONSerialization` produced, or a ``JSONNumberText``.
    /// - Returns: The number, or `nil` if the value is not a number or Boolean.
    static func number(_ json: Any) -> NSNumber? {
        if let written = json as? JSONNumberText { return written.number }
        return json as? NSNumber
    }

    /// The exact floating point value of a number.
    ///
    /// A decimal number is converted from its decimal text, which reads as the nearest
    /// floating point number; any other number is converted directly.
    ///
    /// - Parameter number: The number.
    /// - Returns: The floating point number nearest to the value of `number`.
    static func double(_ number: NSNumber) -> Double {
        if number is NSDecimalNumber, let exact = Double(number.stringValue) { return exact }
        return number.doubleValue
    }

    /// The text from which a number reads back as exactly the same value.
    ///
    /// The text is the number's own description where that reads back exactly, so that
    /// integers and decimal numbers keep their text; a floating point number whose
    /// description is too short takes its shortest exact form (see ``JSONText/number(_:)``).
    ///
    /// - Parameter json: A value that `JSONSerialization` produced, or a ``JSONNumberText``.
    /// - Returns: The text, or `nil` if the value is not a number or Boolean.
    static func literal(_ json: Any) -> String? {
        if let written = json as? JSONNumberText { return written.text }
        guard let number = json as? NSNumber else { return nil }
        let text = number.stringValue
        guard JSONScalarKind.of(number) == .double, !(number is NSDecimalNumber) else { return text }
        let value = number.doubleValue
        if let read = Double(text), read.bitPattern == value.bitPattern { return text }
        return JSONText.number(value) ?? text
    }

    // MARK: Negative Zero

    /// Restores the sign of the integers written as `-0` that `JSONSerialization` read as zero.
    ///
    /// A document is only parsed a second time if a scan of its text finds `-0` outside
    /// strings (see ``OrderedJSON/mayContainNegativeZero(_:)``). Each such integer then
    /// becomes a ``JSONNumberText`` that remains the integer zero but reads as `-0.0` into a
    /// floating point attribute; every other value is left exactly as it was read. A key
    /// that occurs more than once in an object is left as it was read.
    ///
    /// - Parameters:
    ///   - json: The document as `JSONSerialization` read it.
    ///   - data: The UTF-8 text of the document.
    /// - Returns: The document with the sign of each negative zero integer restored.
    static func restoringNegativeZeros(in json: Any, of data: Data) -> Any {
        guard OrderedJSON.mayContainNegativeZero(data),
            let ordered = try? OrderedJSON.parse(data, keepingNegativeZero: true)
        else { return json }
        return restored(json, from: ordered) ?? json
    }

    /// The value with the sign of its negative zero integers restored.
    ///
    /// - Parameters:
    ///   - json: A value as `JSONSerialization` read it.
    ///   - ordered: The same value as an ordered parse that keeps negative zero read it.
    /// - Returns: The changed value, or `nil` if the value holds no negative zero integer.
    private static func restored(_ json: Any, from ordered: OrderedJSON) -> Any? {
        switch ordered {
        case .number(let value) where value == 0 && value.sign == .minus:
            guard let number = json as? NSNumber, JSONScalarKind.of(number) == .integer else { return nil }
            return JSONNumberText(number: number, text: JSONText.number(value) ?? number.stringValue)
        case .array(let elements):
            guard var array = json as? [Any], array.count == elements.count else { return nil }
            var isChanged = false
            for (index, element) in elements.enumerated() {
                guard let replacement = restored(array[index], from: element) else { continue }
                array[index] = replacement
                isChanged = true
            }
            return isChanged ? array : nil
        case .object(let members):
            guard var object = json as? [String: Any] else { return nil }
            var occurrences: [String: Int] = [:]
            for member in members { occurrences[member.key, default: 0] += 1 }
            var isChanged = false
            for member in members where occurrences[member.key] == 1 {
                guard let value = object[member.key], let replacement = restored(value, from: member.value)
                else { continue }
                object[member.key] = replacement
                isChanged = true
            }
            return isChanged ? object : nil
        default:
            return nil
        }
    }
}
