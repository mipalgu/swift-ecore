//
// JSONNumberFormattingTests.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that JSON documents write their numbers in the same shortest form on every platform.
@Suite("JSON number formatting")
struct JSONNumberFormattingTests {
    /// The writing options of the model documents, as `JSONSerialization` knows them.
    private static let serialisationOptions: JSONSerialization.WritingOptions = [
        .prettyPrinted, .sortedKeys, .withoutEscapingSlashes,
    ]

    /// Numbers and the text that a JSON document holds for each of them.
    static let expectedTexts: [(Double, String)] = [
        (87.2, "87.2"),
        (0.1, "0.1"),
        (0.30000000000000004, "0.30000000000000004"),
        (3.14159, "3.14159"),
        (-3.25, "-3.25"),
        (12345.678, "12345.678"),
        (5.0, "5"),
        (100.0, "100"),
        (0.0, "0"),
        (-0.0, "-0"),
        (1e15, "1000000000000000"),
        (9007199254740992.0, "9007199254740992"),
        (1e16, "1e+16"),
        (1e20, "1e+20"),
        (1.2345678901234568e20, "1.2345678901234568e+20"),
        (1.5e300, "1.5e+300"),
        (0.0001, "0.0001"),
        (1e-5, "1e-05"),
        (1e-7, "1e-07"),
        (5e-324, "5e-324"),
        (Double.greatestFiniteMagnitude, "1.7976931348623157e+308"),
        (-Double.greatestFiniteMagnitude, "-1.7976931348623157e+308"),
    ]

    /// Values whose shortest text has to read back as exactly the same number.
    static let roundTripValues: [Double] = expectedTexts.map(\.0) + [
        1.0 / 3.0, 2.0 / 3.0, .pi, -.pi, 2.718281828459045, 0.1 + 0.2, 1e-300, 2.2250738585072014e-308,
        Double.leastNormalMagnitude, Double.leastNonzeroMagnitude, Double.ulpOfOne,
        4503599627370497.0, 123456789.123456789, -987654.3210987,
    ] + Self.pseudoRandomValues

    /// A reproducible spread of bit patterns over the finite numbers.
    private static var pseudoRandomValues: [Double] {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        var values: [Double] = []
        while values.count < 256 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let value = Double(bitPattern: state)
            if value.isFinite { values.append(value) }
        }
        return values
    }

    // MARK: Numbers

    @Test("a number is written as its shortest text that reads back as the same number",
        arguments: Self.expectedTexts)
    func shortestText(value: Double, expected: String) throws {
        #expect(JSONText.number(value) == expected)
    }

    @Test("the text of a number reads back as exactly that number", arguments: Self.roundTripValues)
    func roundTrip(value: Double) throws {
        let text = try #require(JSONText.number(value))
        let read = try #require(Double(text))
        #expect(read.bitPattern == value.bitPattern, "\(text)")
        #expect(text == value.description.removingWholeSuffix())
    }

    @Test("the text of a number is a JSON number", arguments: Self.roundTripValues)
    func textIsJSON(value: Double) throws {
        let text = try #require(JSONText.number(value))
        let parsed = try OrderedJSON.parse(Data(text.utf8))
        switch parsed {
        case .number(let read): #expect(read == value)
        case .integer(let read): #expect(Double(read) == value)
        default: Issue.record("\(text) is not a JSON number")
        }
        let object = try JSONSerialization.jsonObject(with: Data("[\(text)]".utf8)) as? [NSNumber]
        #expect(object?.count == 1, "\(text) is not read as a JSON number")
    }

    @Test("a number without a finite value has no JSON text",
        arguments: [Double.nan, -Double.nan, .infinity, -.infinity, .signalingNaN])
    func nonFiniteNumbers(value: Double) {
        #expect(JSONText.number(value) == nil)
        #expect(JSONText.number(Float(value)) == nil)
    }

    @Test("a single precision number is written as its own shortest text")
    func singlePrecision() {
        #expect(JSONText.number(Float(87.2)) == "87.2")
        #expect(JSONText.number(Float(2.718)) == "2.718")
        #expect(JSONText.number(Float(16777216)) == "16777216")
        #expect(JSONText.number(Float(-0.0)) == "-0")
        #expect(JSONText.number(Float(1e-10)) == "1e-10")
        #expect(JSONText.number(Float.greatestFiniteMagnitude) == "3.4028235e+38")
    }

    // MARK: Documents

    /// A document without fractional numbers that exercises keys, strings and nesting.
    private static var structuralDocument: [String: Any] {
        let keys = [
            "b", "B", "a", "A", "item10", "item2", "é", "e", "$ref", "_x", "eClass", "Zeta", "zeta", "a_b",
            "aB", "ab", "ä", "ÄB", "1", "10", "9", "x-y", "x_y", "x.y", "ｆ", "", " ", "a b", "日本",
        ]
        var document: [String: Any] = [:]
        for (index, key) in keys.enumerated() { document[key] = index }
        document["empty array"] = [Any]()
        document["empty object"] = [String: Any]()
        document["nested"] = [
            "text": "a/b\"c\\d\n\r\t\u{08}\u{0C}\u{00}\u{01}\u{0F}\u{10}\u{1F} é😀\u{7F}\u{2028}",
            "true": true, "false": false, "null": NSNull(), "negative": -42, "largest": Int.max,
            "smallest": Int.min, "whole": 92.0, "zero": 0.0, "negative zero": -0.0, "large": 1e15,
            "objects": [["k": 1], ["k": [String]()]], "strings": ["x", "y/z"],
        ] as [String: Any]
        document["mixed"] = [1, "x", [Any](), [String: Any](), [1, 2], true, NSNull()] as [Any]
        return document
    }

    @Test("a document without fractional numbers is written as JSONSerialization writes it")
    func structureMatchesJSONSerialization() throws {
        let documents: [Any] = [
            Self.structuralDocument, [Self.structuralDocument, ["a": 1]], [Any](), [String: Any](),
            [["eClass": "Root", "$ref": "//@a.0"]],
        ]
        for document in documents {
            let expected = try JSONSerialization.data(withJSONObject: document, options: Self.serialisationOptions)
            #expect(try JSONText.document(document) == String(decoding: expected, as: UTF8.self))
        }
    }

    @Test("a document writes its fractional numbers in their shortest form")
    func fractionalNumbersInDocuments() throws {
        let document: [String: Any] = [
            "scores": [95.5, 87.2, 92.0, 100.0], "ratio": 3.14, "tiny": 1e-7, "float": Float(87.2), "count": 42,
        ]
        let expected = """
            {
              "count" : 42,
              "float" : 87.2,
              "ratio" : 3.14,
              "scores" : [
                95.5,
                87.2,
                92,
                100
              ],
              "tiny" : 1e-07
            }
            """
        #expect(try JSONText.document(document) == expected)
    }

    @Test("a document with a number that has no finite value is not written",
        arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteNumbersInDocuments(value: Double) {
        #expect(throws: JSONError.self) { try JSONText.document(["value": value]) }
        #expect(throws: JSONError.self) { try JSONText.document([[value]]) }
        #expect(throws: JSONError.self) { try JSONText.document(["value": Float(value)]) }
    }

    @Test("a document with a value that JSON cannot hold is not written")
    func unsupportedValues() {
        #expect(throws: JSONError.self) { try JSONText.document(["date": Date(timeIntervalSince1970: 0)]) }
        #expect(throws: JSONError.self) { try JSONText.document([1: "one"] as [Int: String]) }
    }

    @Test("integers of every width are written as JSONSerialization writes them")
    func integerWidths() throws {
        let document: [Any] = [
            Int8.min, Int16.max, Int32.min, Int64.max, UInt.max, UInt8.max, UInt16.max, UInt32.max, UInt64.max,
        ]
        let expected = try JSONSerialization.data(withJSONObject: document, options: Self.serialisationOptions)
        #expect(try JSONText.document(document) == String(decoding: expected, as: UTF8.self))
    }

    // MARK: Serialisers

    @Test("the model serialiser writes fractional attribute values in their shortest form")
    func modelSerialiser() async throws {
        let text = """
            {"eClass": "Record", "ratio": 3.14, "scores": [95.5, 87.2, 92.0], "tiny": 1e-7, "count": 42}
            """
        let resource = try await JSONParser().parse(Data(text.utf8), uri: "memory:/numbers.json")
        let written = try await JSONSerializer().serialize(resource)
        let expected = """
            {
              "count" : 42,
              "eClass" : "Record",
              "ratio" : 3.14,
              "scores" : [
                95.5,
                87.2,
                92
              ],
              "tiny" : 1e-07
            }
            """
        #expect(written == expected)
        let reread = try await JSONParser().parse(Data(written.utf8), uri: "memory:/numbers.json")
        #expect(try await JSONSerializer().serialize(reread) == written)
        let root = try #require(await reread.getRootObjects().first as? DynamicEObject)
        #expect(root.eGet("ratio") as? Double == 3.14)
        #expect(root.eGet("tiny") as? Double == 1e-7)
    }

    @Test("the model serialiser writes single and double precision attributes in their shortest form")
    func typedAttributes() async throws {
        let single = EAttribute(name: "single", eType: EDataType(name: "EFloat"))
        let double = EAttribute(name: "double", eType: EDataType(name: "EDouble"))
        var object = DynamicEObject(eClass: EClass(name: "Record", eStructuralFeatures: [single, double]))
        object.eSet(single, Float(87.2))
        object.eSet(double, 0.1)
        let resource = Resource(uri: "memory:/typed.json")
        _ = await resource.add(object)
        let written = try await JSONSerializer().serialize(resource)
        #expect(written.contains(#""single" : 87.2\#n"#), "\(written)")
        #expect(written.contains(#""double" : 0.1,\#n"#), "\(written)")
    }

    @Test("the model serialiser refuses a number that has no finite value", arguments: [Double.nan, .infinity])
    func nonFiniteAttributes(value: Double) async throws {
        let attribute = EAttribute(name: "value", eType: EDataType(name: "EDouble"))
        var object = DynamicEObject(eClass: EClass(name: "Record", eStructuralFeatures: [attribute]))
        object.eSet(attribute, value)
        let resource = Resource(uri: "memory:/invalid.json")
        _ = await resource.add(object)
        await #expect(throws: JSONError.self) { try await JSONSerializer().serialize(resource) }
    }

    @Test("an ordered JSON number is written in the same shortest form", arguments: Self.expectedTexts)
    func orderedJSONNumbers(value: Double, expected: String) {
        #expect(OrderedJSON.number(value).document == expected + "\n")
        #expect(OrderedJSON.array([.number(value)]).document == "[\n  \(expected)\n]\n")
    }
}

private extension String {
    /// The text without a trailing `.0`, which a whole number's description ends in.
    func removingWholeSuffix() -> String {
        hasSuffix(".0") ? String(dropLast(2)) : self
    }
}
