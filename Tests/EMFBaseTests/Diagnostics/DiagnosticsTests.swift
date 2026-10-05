//
// DiagnosticsTests.swift
// EMFBaseTests
//
// Copyright © 2025 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import EMFBase

// Disambiguates from the Testing module's own source location type.
private typealias SourceLocation = EMFBase.SourceLocation

@Suite("Source Diagnostics Tests")
struct DiagnosticsTests {
    private func loc(_ offset: Int, _ line: Int = 1, _ column: Int? = nil) -> SourceLocation {
        SourceLocation(utf8Offset: offset, line: line, column: column ?? offset + 1)
    }

    private func range(_ a: Int, _ b: Int) -> SourceRange {
        SourceRange(start: loc(a), end: loc(b))
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    @Test("Locations order by offset")
    func locationOrdering() {
        #expect(loc(1) < loc(2))
        #expect(!(loc(2) < loc(2)))
        #expect([loc(5), loc(1), loc(3)].sorted() == [loc(1), loc(3), loc(5)])
        #expect(SourceLocation.start == SourceLocation(utf8Offset: 0, line: 1, column: 1))
    }

    @Test("Range containment is half open")
    func rangeContains() {
        let r = range(2, 5)
        #expect(r.contains(loc(2)))
        #expect(r.contains(loc(4)))
        #expect(!r.contains(loc(5)))
        #expect(!r.contains(loc(1)))
        #expect(r.contains(range(3, 5)))
        #expect(r.contains(range(2, 5)))
        #expect(!r.contains(range(1, 3)))
        #expect(!r.contains(range(4, 6)))
    }

    @Test("Empty ranges and length")
    func rangeEmpty() {
        #expect(range(3, 3).isEmpty)
        #expect(!range(3, 4).isEmpty)
        #expect(range(3, 3).utf8Length == 0)
        #expect(range(3, 9).utf8Length == 6)
        #expect(!range(3, 3).contains(loc(3)))
    }

    @Test("Overlap")
    func rangeOverlaps() {
        #expect(range(0, 4).overlaps(range(3, 6)))
        #expect(!range(0, 3).overlaps(range(3, 6)))
        #expect(!range(2, 2).overlaps(range(0, 6)))
    }

    @Test("Union of ranges")
    func rangeUnion() {
        #expect(range(2, 4).union(range(6, 8)) == range(2, 8))
        #expect(range(6, 8).union(range(2, 4)) == range(2, 8))
        #expect(range(0, 9).union(range(2, 4)) == range(0, 9))
        #expect(SourceRange.union(of: [range(5, 6), range(1, 2), range(3, 9)]) == range(1, 9))
        #expect(SourceRange.union(of: [SourceRange]()) == nil)
        #expect(SourceRange.union(of: [range(1, 2)]) == range(1, 2))
    }

    @Test("Origins never affect equality or hashing")
    func originNeutrality() {
        struct Node: Hashable { var name: String; var origin = SourceOrigin() }
        let a = Node(name: "x", origin: SourceOrigin(range(0, 4)))
        let b = Node(name: "x", origin: SourceOrigin(range(9, 12)))
        let c = Node(name: "x", origin: SourceOrigin())
        #expect(a == b)
        #expect(a == c)
        #expect(a.hashValue == c.hashValue)
        #expect(Set([a, b, c]).count == 1)
        #expect(Node(name: "y", origin: a.origin) != a)
        #expect(SourceOrigin(range(1, 2)).range == range(1, 2))
    }

    @Test("Severity ordering and raw values")
    func severity() {
        #expect(DiagnosticSeverity.information < .warning)
        #expect(DiagnosticSeverity.warning < .error)
        #expect(DiagnosticSeverity.allCases == [.information, .warning, .error])
        #expect(DiagnosticSeverity.allCases.map(\.rawValue) == [0, 1, 2])
        #expect(DiagnosticSeverity.allCases.max() == .error)
    }

    @Test("Token kinds are complete")
    func tokenKinds() {
        #expect(SourceTokenKind.allCases.count == 14)
        #expect(SourceTokenKind.operator.rawValue == "operator")
    }

    @Test("Codable round trips")
    func codable() throws {
        let inner = SourceDiagnostic(severity: .information, code: "dup", message: "first", range: range(1, 2))
        let diagnostic = SourceDiagnostic(
            severity: .error, code: "E1", message: "bad", range: range(3, 7),
            document: "mem:a", related: [inner])
        #expect(try roundTrip(diagnostic) == diagnostic)
        #expect(try roundTrip(loc(4, 2, 3)) == loc(4, 2, 3))
        #expect(try roundTrip(range(1, 8)) == range(1, 8))
        let token = SourceToken(kind: .keyword, range: range(0, 3))
        #expect(try roundTrip(token) == token)
        let origin = try roundTrip(SourceOrigin(range(1, 2)))
        #expect(origin.range == range(1, 2))
        #expect(try roundTrip(DiagnosticSeverity.warning) == .warning)
    }

    @Test("Diagnostics are errors with defaults")
    func diagnosticDefaults() {
        let d = SourceDiagnostic(severity: .warning, code: "W", message: "m")
        #expect(d.range == nil && d.document == nil && d.related.isEmpty)
        let error: Error = d
        #expect(error is SourceDiagnostic)
        #expect(d != SourceDiagnostic(severity: .error, code: "W", message: "m"))
    }

    @Test("Outline nodes")
    func outline() {
        let child = OutlineNode(id: "a/b", kind: "attr", name: "b", range: range(2, 4), selectionRange: range(2, 3))
        let parent = OutlineNode(
            id: "a", kind: "class", name: "a", detail: "Class", range: range(0, 9),
            selectionRange: range(0, 1), children: [child])
        #expect(parent.id == "a")
        #expect(parent.children == [child])
        #expect(child.detail == nil && child.children.isEmpty)
        #expect(Set([parent, child]).count == 2)
    }
}

@Suite("LineTable Tests")
struct LineTableTests {
    @Test("Empty text")
    func empty() {
        let t = LineTable("")
        #expect(t.lineCount == 1)
        #expect(t.utf8Count == 0 && t.utf16Count == 0)
        #expect(t.location(forUTF8Offset: 0) == .start)
        #expect(t.location(forUTF8Offset: 10) == .start)
        #expect(t.location(forUTF8Offset: -3) == .start)
        #expect(t.utf8Offset(line: 1, column: 1) == 0)
        #expect(t.utf8Offset(line: 1, column: 2) == nil)
        #expect(t.utf8Offset(line: 2, column: 1) == nil)
        #expect(t.utf8Offset(line: 0, column: 1) == nil)
        #expect(t.contentRange(ofLine: 1) == 0..<0)
        #expect(t.contentRange(ofLine: 2) == nil)
        #expect(t.utf8Offset(forUTF16Offset: 5) == 0)
    }

    @Test("LF line ends")
    func lf() {
        let t = LineTable("ab\ncd\n")
        #expect(t.lineCount == 3)
        #expect(t.location(forUTF8Offset: 2) == SourceLocation(utf8Offset: 2, line: 1, column: 3))
        #expect(t.location(forUTF8Offset: 3) == SourceLocation(utf8Offset: 3, line: 2, column: 1))
        #expect(t.location(forUTF8Offset: 6) == SourceLocation(utf8Offset: 6, line: 3, column: 1))
        #expect(t.utf8Offset(line: 2, column: 2) == 4)
        #expect(t.utf8Offset(line: 2, column: 3) == 5)
        #expect(t.utf8Offset(line: 2, column: 4) == nil)
        #expect(t.utf8Offset(line: 3, column: 1) == 6)
        #expect(t.contentRange(ofLine: 1) == 0..<2)
        #expect(t.contentRange(ofLine: 3) == 6..<6)
    }

    @Test("CRLF is a single line end")
    func crlf() {
        let t = LineTable("ab\r\ncd")
        #expect(t.lineCount == 2)
        #expect(t.location(forUTF8Offset: 4) == SourceLocation(utf8Offset: 4, line: 2, column: 1))
        #expect(t.contentRange(ofLine: 1) == 0..<2)
        #expect(t.utf8Offset(line: 2, column: 3) == 6)
        #expect(t.utf16Offset(forUTF8Offset: 4) == 4)
        #expect(t.utf8Offset(forUTF16Offset: 4) == 4)
        #expect(t.utf16Count == 6)
    }

    @Test("Lone CR is a line end")
    func loneCR() {
        let t = LineTable("a\rb\r\rc")
        #expect(t.lineCount == 4)
        #expect(t.location(forUTF8Offset: 2) == SourceLocation(utf8Offset: 2, line: 2, column: 1))
        #expect(t.location(forUTF8Offset: 4) == SourceLocation(utf8Offset: 4, line: 3, column: 1))
        #expect(t.location(forUTF8Offset: 5) == SourceLocation(utf8Offset: 5, line: 4, column: 1))
        #expect(t.contentRange(ofLine: 3) == 4..<4)
        #expect(t.utf16Offset(forUTF8Offset: 5) == 5)
    }

    @Test("Mixed line ends")
    func mixed() {
        let t = LineTable("a\nb\r\nc\rd")
        #expect(t.lineCount == 4)
        #expect(t.utf8Offset(line: 4, column: 1) == 7)
        #expect(t.location(forUTF8Offset: 8).line == 4)
    }

    @Test("Non-ASCII columns count scalars")
    func nonASCII() {
        let t = LineTable("é€x\nz")
        // é = 2 bytes, € = 3 bytes
        #expect(t.location(forUTF8Offset: 2) == SourceLocation(utf8Offset: 2, line: 1, column: 2))
        #expect(t.location(forUTF8Offset: 5) == SourceLocation(utf8Offset: 5, line: 1, column: 3))
        #expect(t.location(forUTF8Offset: 3) == SourceLocation(utf8Offset: 2, line: 1, column: 2))
        #expect(t.utf8Offset(line: 1, column: 3) == 5)
        #expect(t.utf8Offset(line: 1, column: 4) == 6)
        #expect(t.utf16Offset(forUTF8Offset: 5) == 2)
        #expect(t.utf8Offset(forUTF16Offset: 2) == 5)
    }

    @Test("Emoji occupy one column and two UTF-16 units")
    func emoji() {
        let text = "a😀b\n😀"
        let t = LineTable(text)
        #expect(t.location(forUTF8Offset: 5) == SourceLocation(utf8Offset: 5, line: 1, column: 3))
        #expect(t.location(forUTF8Offset: 3) == SourceLocation(utf8Offset: 1, line: 1, column: 2))
        #expect(t.utf8Offset(line: 1, column: 3) == 5)
        #expect(t.utf16Offset(forUTF8Offset: 5) == 3)
        #expect(t.utf16Offset(forUTF8Offset: 7) == 5)
        #expect(t.utf16Offset(forUTF8Offset: 11) == 7)
        #expect(t.utf16Count == text.utf16.count)
        #expect(t.utf8Offset(forUTF16Offset: 3) == 5)
        #expect(t.utf8Offset(forUTF16Offset: 2) == 1)
        #expect(t.utf8Offset(forUTF16Offset: 5) == 7)
        #expect(t.utf8Offset(forUTF16Offset: 7) == 11)
        #expect(t.utf8Offset(forUTF16Offset: 99) == 11)
        #expect(t.utf8Offset(forUTF16Offset: -1) == 0)
    }

    @Test("End of file positions")
    func endOfFile() {
        let t = LineTable("ab")
        #expect(t.location(forUTF8Offset: 2) == SourceLocation(utf8Offset: 2, line: 1, column: 3))
        #expect(t.location(forUTF8Offset: 100) == SourceLocation(utf8Offset: 2, line: 1, column: 3))
        #expect(t.utf8Offset(line: 1, column: 3) == 2)
        let n = LineTable("ab\r\n")
        #expect(n.location(forUTF8Offset: 4) == SourceLocation(utf8Offset: 4, line: 2, column: 1))
        #expect(n.contentRange(ofLine: 2) == 4..<4)
        #expect(n.range(fromUTF8Offset: 1, to: 4).end.line == 2)
    }

    @Test("Round trips over every offset")
    func roundTrips() {
        let text = "x😀\r\né\n\r€z"
        let t = LineTable(text)
        var offset = 0
        for scalar in text.unicodeScalars {
            let l = t.location(forUTF8Offset: offset)
            if !"\r\n".unicodeScalars.contains(scalar) {
                #expect(t.utf8Offset(line: l.line, column: l.column) == offset)
            }
            let u = t.utf16Offset(forUTF8Offset: offset)
            #expect(t.utf8Offset(forUTF16Offset: u) == offset)
            offset += String(scalar).utf8.count
        }
    }
}
