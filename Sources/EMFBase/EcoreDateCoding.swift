//
// EcoreDateCoding.swift
// EMFBase
//
// Copyright © 2025 Rene Hexel. All rights reserved.
//

import Foundation

/// Reads and writes `EDate` values as ISO 8601 text.
///
/// The coding is implemented without `DateFormatter`, so it behaves the same
/// on every platform. Dates are written in UTC. Parsing accepts the date and
/// time forms used by EMF and PyEcore tooling:
///
/// - `2025-01-02T03:04:05Z` and `2025-01-02T03:04:05+10:00` (also `+1000`
///   and `+10`)
/// - the same with fractional seconds, such as `2025-01-02T03:04:05.123456Z`
/// - `2025-01-02T03:04:05` without a time zone, which is read as UTC
///
/// Fractional seconds are kept to millisecond precision, both when reading
/// and when writing. Field values may have fewer digits than the canonical
/// form, and a day that exceeds the length of its month carries into the
/// following month. Dates are interpreted in the proleptic Gregorian calendar.
public enum EcoreDateCoding {
    /// Reads a date in any of the supported forms.
    ///
    /// - Parameter text: The text to read.
    /// - Returns: The date, or `nil` if the text is not in a supported form.
    public static func date(from text: String) -> EDate? {
        parse(text, requiresTimeZone: false)
    }

    /// Reads a date in internet date-time form (`yyyy-MM-ddTHH:mm:ssZ`).
    ///
    /// Unlike ``date(from:)``, the time zone designator is required and
    /// fractional seconds are rejected.
    ///
    /// - Parameter text: The text to read.
    /// - Returns: The date, or `nil` if the text is not in this form.
    public static func internetDate(from text: String) -> EDate? {
        parse(text, requiresTimeZone: true, allowsFraction: false)
    }

    /// Writes a date with microsecond-width fractional seconds in UTC.
    ///
    /// The result looks like `2025-01-02T03:04:05.123000Z`; the date is
    /// rounded to the nearest millisecond.
    ///
    /// - Parameter date: The date to write.
    /// - Returns: The text form.
    public static func fractionalString(from date: EDate) -> String {
        let (seconds, milliseconds) = roundedToMilliseconds(date)
        return base(seconds) + "." + pad(milliseconds * 1000, 6) + "Z"
    }

    /// Writes a date in internet date-time form in UTC.
    ///
    /// The result looks like `2025-01-02T03:04:05Z`; fractional seconds are
    /// dropped (rounded towards the past).
    ///
    /// - Parameter date: The date to write.
    /// - Returns: The text form.
    public static func internetString(from date: EDate) -> String {
        base(roundedToMilliseconds(date).seconds) + "Z"
    }

    // MARK: - Writing

    private static func roundedToMilliseconds(_ date: EDate) -> (seconds: Int64, milliseconds: Int) {
        let interval = date.timeIntervalSinceReferenceDate
        var seconds = Int64(interval.rounded(.down))
        var milliseconds = Int(((interval - Double(seconds)) * 1000).rounded())
        if milliseconds >= 1000 {
            seconds += 1
            milliseconds -= 1000
        }
        return (seconds + referenceDateOffset, milliseconds)
    }

    private static let referenceDateOffset = Int64(Date.timeIntervalBetween1970AndReferenceDate)

    private static func base(_ epochSeconds: Int64) -> String {
        let days = floorDiv(epochSeconds, 86_400)
        let secondOfDay = Int(epochSeconds - days * 86_400)
        let (year, month, day) = civil(fromDays: days)
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))T"
            + "\(pad(secondOfDay / 3600, 2)):\(pad(secondOfDay / 60 % 60, 2)):\(pad(secondOfDay % 60, 2))"
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    private static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    // MARK: - Calendar arithmetic

    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int64 {
        let y = Int64(month <= 2 ? year - 1 : year)
        let era = floorDiv(y, 400)
        let yearOfEra = y - era * 400
        let shifted = Int64(month > 2 ? month - 3 : month + 9)
        let dayOfYear = (153 * shifted + 2) / 5 + Int64(day) - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        let next = month == 12 ? daysFromCivil(year: year + 1, month: 1, day: 1) : daysFromCivil(year: year, month: month + 1, day: 1)
        return Int(next - daysFromCivil(year: year, month: month, day: 1))
    }

    private static func civil(fromDays days: Int64) -> (Int, Int, Int) {
        let z = days + 719_468
        let era = floorDiv(z, 146_097)
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shifted = (5 * dayOfYear + 2) / 153
        let day = Int(dayOfYear - (153 * shifted + 2) / 5 + 1)
        let month = Int(shifted < 10 ? shifted + 3 : shifted - 9)
        let year = Int(yearOfEra + era * 400) + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }

    // MARK: - Reading

    private static func parse(_ text: String, requiresTimeZone: Bool, allowsFraction: Bool = true) -> EDate? {
        var scanner = Scanner8(Array(text.utf8))
        scanner.skipSpaces()
        guard let year = scanner.number(maxDigits: 9), scanner.skipSpacesThen("-"),
            let month = scanner.number(maxDigits: 2), (1...12).contains(month), scanner.skipSpacesThen("-"),
            let day = scanner.number(maxDigits: 2), (1...31).contains(day),
            scanner.expect("T")
        else { return nil }
        scanner.skipSpaces()
        guard let hour = scanner.number(maxDigits: 2), hour <= 24, scanner.skipSpacesThen(":"),
            let minute = scanner.number(maxDigits: 2), minute <= 59, scanner.skipSpacesThen(":"),
            let second = scanner.number(maxDigits: 2), second <= 59
        else { return nil }

        var milliseconds = 0
        var hasFraction = false
        if scanner.peek == UInt8(ascii: ".") {
            guard allowsFraction else { return nil }
            scanner.advance()
            guard let digits = scanner.digits(), !digits.isEmpty else { return nil }
            hasFraction = true
            for (index, digit) in digits.prefix(3).enumerated() {
                milliseconds += digit * [100, 10, 1][index]
            }
        }
        scanner.skipSpaces()

        var offsetSeconds = 0
        var hasZone = false
        if let zone = scanner.timeZone() {
            offsetSeconds = zone
            hasZone = true
        }
        if (requiresTimeZone || hasFraction) && !hasZone { return nil }
        if hasFraction || !hasZone {
            guard hour < 24, day <= daysInMonth(year: year, month: month) else { return nil }
        }
        if !(hasZone && !hasFraction) {
            scanner.skipSpaces()
            guard scanner.atEnd else { return nil }
        }

        let days = daysFromCivil(year: year, month: month, day: 1) + Int64(day - 1)
        let epoch = days * 86_400 + Int64(hour * 3600 + minute * 60 + second - offsetSeconds)
        return Date(timeIntervalSince1970: Double(epoch) + Double(milliseconds) / 1000)
    }

    private struct Scanner8 {
        let bytes: [UInt8]
        var index = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        var atEnd: Bool { index >= bytes.count }
        var peek: UInt8? { index < bytes.count ? bytes[index] : nil }
        mutating func advance() { index += 1 }

        mutating func skipSpaces() {
            while let b = peek, b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { index += 1 }
        }

        mutating func expect(_ character: Character) -> Bool {
            guard peek == character.asciiValue else { return false }
            index += 1
            return true
        }

        mutating func skipSpacesThen(_ character: Character) -> Bool {
            skipSpaces()
            guard expect(character) else { return false }
            skipSpaces()
            return true
        }

        mutating func number(maxDigits: Int) -> Int? {
            var value = 0
            var count = 0
            while count < maxDigits, let b = peek, (0x30...0x39).contains(b) {
                value = value * 10 + Int(b - 0x30)
                index += 1
                count += 1
            }
            return count == 0 ? nil : value
        }

        mutating func digits() -> [Int]? {
            var result: [Int] = []
            while let b = peek, (0x30...0x39).contains(b) {
                result.append(Int(b - 0x30))
                index += 1
            }
            return result
        }

        mutating func timeZone() -> Int? {
            guard let b = peek else { return nil }
            if b == UInt8(ascii: "Z") || b == UInt8(ascii: "z") {
                index += 1
                return 0
            }
            for name in ["UTC", "GMT"] where bytes[index...].starts(with: Array(name.utf8)) {
                index += name.utf8.count
                return offset() ?? 0
            }
            return offset()
        }

        private mutating func offset() -> Int? {
            guard let b = peek, b == UInt8(ascii: "+") || b == UInt8(ascii: "-") else { return nil }
            let sign = b == UInt8(ascii: "-") ? -1 : 1
            let start = index
            index += 1
            guard let hours = number(maxDigits: 2) else {
                index = start
                return nil
            }
            if hours > 23 {
                index -= 1
                return sign * (hours / 10) * 3600
            }
            var seconds = hours * 3600
            for unit in [60, 1] {
                let mark = index
                if peek == UInt8(ascii: ":") { index += 1 }
                if let part = number(maxDigits: 2), part <= 59 {
                    seconds += part * unit
                } else {
                    index = mark
                    break
                }
            }
            return sign * seconds
        }
    }
}
