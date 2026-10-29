//
// EcoreValueArrayCompatibilityTests.swift
// EMFBaseTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation
import Testing

@testable import EMFBase

/// Pins the textual form, reflection, equality and hashing of arrays as released in 0.6.
///
/// The tests use only the API of that release, so that they describe its behaviour exactly.
@Suite("EcoreValueArray compatibility with 0.6")
struct EcoreValueArrayCompatibilityTests {
    private let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Test("the textual forms of an array are unchanged")
    func textualForms() {
        let array = EcoreValueArray([1, "a", identifier, EcoreValueArray([true])])
        let expected =
            "EcoreValueArray(values: [1, \"a\", 00000000-0000-0000-0000-000000000001, "
            + "EMFBase.EcoreValueArray(values: [true])])"
        #expect(String(describing: array) == expected)
        #expect(String(reflecting: array) == "EMFBase." + expected)
        #expect("\(EcoreValueArray([]))" == "EcoreValueArray(values: [])")
    }

    @Test("a dump of an array lists its values only")
    func dumped() {
        var text = ""
        dump(EcoreValueArray([1, "a"]), to: &text)
        let expected = """
            ▿ EMFBase.EcoreValueArray
              ▿ values: 2 elements
                - 1
                - "a"

            """
        #expect(text == expected)
    }

    @Test("an array reflects as a structure with a single values child")
    func reflected() {
        let mirror = Mirror(reflecting: EcoreValueArray([1, 2]))
        #expect(mirror.displayStyle == .struct)
        #expect(mirror.children.map(\.label) == ["values"])
        #expect(mirror.superclassMirror == nil)
    }

    @Test("arrays compare and hash by their values")
    func equalityAndHashing() {
        let first = EcoreValueArray([1, "a", identifier])
        let second = EcoreValueArray([1, "a", identifier])
        let reordered = EcoreValueArray(["a", 1, identifier])
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(first != reordered)
        #expect(Set([first, second, reordered]).count == 2)
        #expect(EcoreValueArray([]) == EcoreValueArray([]))
    }
}
