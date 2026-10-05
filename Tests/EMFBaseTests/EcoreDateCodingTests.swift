//
// EcoreDateCodingTests.swift
// EMFBaseTests
//
// Copyright © 2025 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import EMFBase

@Suite("Ecore Date Coding Tests")
struct EcoreDateCodingTests {
    /// 2025-01-02T03:04:05Z
    private let reference = 1_735_787_045.0

    private func seconds(_ text: String) -> Double? {
        EcoreDateCoding.date(from: text)?.timeIntervalSince1970
    }

    @Test("Internet date-time with Z", arguments: ["2025-01-02T03:04:05Z", "2025-01-02T03:04:05z"])
    func zulu(_ text: String) {
        #expect(seconds(text) == reference)
        #expect(EcoreDateCoding.internetDate(from: text)?.timeIntervalSince1970 == reference)
    }

    @Test("Time zone offsets", arguments: [
        ("2025-01-02T03:04:05+10:00", 36_000.0), ("2025-01-02T03:04:05+1000", 36_000.0),
        ("2025-01-02T03:04:05+10", 36_000.0), ("2025-01-02T03:04:05-0530", -19_800.0),
        ("2025-01-02T03:04:05-05:30", -19_800.0), ("2025-01-02T03:04:05UTC", 0.0),
        ("2025-01-02T03:04:05GMT+10", 36_000.0), ("2025-01-02T03:04:05-00:00", 0.0),
        ("2025-01-02T03:04:05+10:30:15", 37_815.0),
    ])
    func offsets(_ text: String, _ offset: Double) {
        #expect(seconds(text) == reference - offset)
    }

    @Test("Fractional seconds are kept to milliseconds")
    func fractions() {
        #expect(seconds("2025-01-02T03:04:05.123456Z") == reference + 0.123)
        #expect(seconds("2025-01-02T03:04:05.123Z") == reference + 0.123)
        #expect(seconds("2025-01-02T03:04:05.5Z") == reference + 0.5)
        #expect(seconds("2025-01-02T03:04:05.9996Z") == reference + 0.999)
        #expect(seconds("2025-01-02T03:04:05.0000001Z") == reference)
        #expect(seconds("2025-01-02T03:04:05.123456+10:00") == reference - 36_000 + 0.123)
        #expect(seconds("2025-01-02T03:04:05.123456+1000") == reference - 36_000 + 0.123)
        #expect(seconds("2025-01-02T03:04:05.5 +10:00") == reference - 36_000 + 0.5)
    }

    @Test("A fraction needs a time zone and digits")
    func fractionRequirements() {
        #expect(seconds("2025-01-02T03:04:05.123456") == nil)
        #expect(seconds("2025-01-02T03:04:05.5") == nil)
        #expect(seconds("2025-01-02T03:04:05.Z") == nil)
        #expect(EcoreDateCoding.internetDate(from: "2025-01-02T03:04:05.5Z") == nil)
    }

    @Test("Time zone is optional and means UTC")
    func noZone() {
        #expect(seconds("2025-01-02T03:04:05") == reference)
        #expect(EcoreDateCoding.internetDate(from: "2025-01-02T03:04:05") == nil)
    }

    @Test("Lenient field widths and surrounding space")
    func leniency() {
        #expect(seconds("2025-1-2T3:4:5Z") == reference)
        #expect(seconds(" 2025-01-02T03:04:05Z") == reference)
        #expect(seconds("2025-01-02T03:04:05 ") == reference)
        #expect(seconds("2025-01-02T03:04:05Zjunk") == reference)
        #expect(seconds("2025-01-02T03:04:05 +10:00") == reference - 36_000)
    }

    @Test("Day overflow carries on the internet form only")
    func overflow() {
        #expect(seconds("2025-02-30T03:04:05Z") == 1_740_884_645)
        #expect(seconds("2025-02-30T03:04:05") == nil)
        #expect(seconds("2025-02-30T03:04:05.5Z") == nil)
        #expect(seconds("2024-02-29T00:00:00Z") == 1_709_164_800)
        #expect(seconds("2024-02-29T00:00:00.5Z") == 1_709_164_800.5)
        #expect(seconds("2025-01-02T24:00:00Z") == 1_735_862_400)
        #expect(seconds("2025-01-02T24:00:00") == nil)
    }

    @Test("Malformed text is rejected", arguments: [
        "", "2025-01-02", "2025-01-02T03:04Z", "2025-13-02T03:04:05Z", "2025-01-32T03:04:05Z",
        "2025-01-00T03:04:05Z", "2025-01-02T25:04:05Z", "2025-01-02T03:60:05Z",
        "2025-01-02T03:04:60Z", "2025-01-02 03:04:05Z", "2025-01-02t03:04:05Z",
        "20250102T030405Z", "2025-01-02T03:04:05abc", "2025-01-02T03:04:05.123456+10:00junk",
        "not a date",
    ])
    func malformed(_ text: String) {
        #expect(seconds(text) == nil)
    }

    @Test("Writing with fractional seconds")
    func writeFractional() {
        #expect(EcoreDateCoding.fractionalString(from: Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00.000000Z")
        #expect(EcoreDateCoding.fractionalString(from: Date(timeIntervalSince1970: reference + 0.5)) == "2025-01-02T03:04:05.500000Z")
        #expect(EcoreDateCoding.fractionalString(from: Date(timeIntervalSince1970: reference + 0.1234)) == "2025-01-02T03:04:05.123000Z")
        #expect(EcoreDateCoding.fractionalString(from: Date(timeIntervalSince1970: reference + 0.9996)) == "2025-01-02T03:04:06.000000Z")
        #expect(EcoreDateCoding.fractionalString(from: Date(timeIntervalSince1970: -1.5)) == "1969-12-31T23:59:58.500000Z")
        #expect(EcoreDateCoding.fractionalString(from: Date(timeIntervalSince1970: 253_402_300_799.5)) == "9999-12-31T23:59:59.500000Z")
        #expect(EcoreDateCoding.fractionalString(from: Date(timeIntervalSince1970: 1_709_164_800)) == "2024-02-29T00:00:00.000000Z")
    }

    @Test("Writing internet date-time")
    func writeInternet() {
        #expect(EcoreDateCoding.internetString(from: Date(timeIntervalSince1970: reference)) == "2025-01-02T03:04:05Z")
        #expect(EcoreDateCoding.internetString(from: Date(timeIntervalSince1970: reference + 0.9)) == "2025-01-02T03:04:05Z")
        #expect(EcoreDateCoding.internetString(from: Date(timeIntervalSince1970: -1.5)) == "1969-12-31T23:59:58Z")
        #expect(EcoreDateCoding.internetString(from: Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00Z")
    }

    @Test("Written text reads back")
    func roundTrip() {
        for interval in [0.0, reference, reference + 0.25, -86_400.75, 951_782_400.5, 4_102_444_800.125] {
            let date = Date(timeIntervalSince1970: interval)
            #expect(EcoreDateCoding.date(from: EcoreDateCoding.fractionalString(from: date)) == date)
            let whole = Date(timeIntervalSince1970: interval.rounded(.down))
            #expect(EcoreDateCoding.internetDate(from: EcoreDateCoding.internetString(from: date)) == whole)
        }
    }
}
