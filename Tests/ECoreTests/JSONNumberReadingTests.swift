//
// JSONNumberReadingTests.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that model documents read their numbers back as exactly the numbers they hold.
@Suite("JSON number reading")
struct JSONNumberReadingTests {
    /// The namespace URI of the measurement metamodel.
    static let measurementsURI = "http://www.example.org/measurements"

    /// The `eClass` value of a sample of the measurement metamodel.
    static let sampleClass = "\(measurementsURI)#//Sample"

    /// A number with seventeen significant digits that a platform reader once read one unit
    /// in the last place too low.
    static let seventeenDigitText = "-0.00021793413373688968"

    /// The values that the number formatting tests write in their shortest form.
    static let values = JSONNumberFormattingTests.roundTripValues

    /// The texts of the values with seventeen significant digits.
    static let seventeenDigitTexts: [String] = values.map { String(format: "%.17g", $0) } + [seventeenDigitText]

    /// A metamodel whose samples hold one number and a list of numbers.
    static func measurementPackage() -> EPackage {
        let double = EcorePackage.dataType(.eDouble) ?? EDataType(name: "EDouble")
        let sample = EClass(
            name: "Sample",
            eStructuralFeatures: [
                EAttribute(name: "value", eType: double),
                EAttribute(name: "values", eType: double, upperBound: -1),
            ])
        return EPackage(
            name: "measurements", nsURI: measurementsURI, nsPrefix: "measurements", eClassifiers: [sample])
    }

    /// A resource set with the measurement metamodel registered.
    static func measurementSet() async -> ResourceSet {
        let set = ResourceSet()
        let package = measurementPackage()
        await set.registerMetamodel(package, uri: package.nsURI)
        return set
    }

    /// Reads the root object of a document.
    ///
    /// - Parameters:
    ///   - text: The JSON text of the document.
    ///   - set: The resource set with the metamodels, or `nil` to synthesise the classes.
    /// - Returns: The first root object.
    static func root(of text: String, in set: ResourceSet?) async throws -> DynamicEObject {
        let resource = try await JSONParser(resourceSet: set).parse(Data(text.utf8), uri: "memory:/numbers.json")
        return try #require(await resource.getRootObjects().first as? DynamicEObject)
    }

    /// Writes a sample that holds a list of numbers through the model serialiser.
    ///
    /// - Parameter values: The numbers of the list.
    /// - Returns: The JSON text of the document.
    static func writtenSample(holding values: [Double]) async throws -> String {
        let sampleClass = try #require(measurementPackage().getEClass("Sample"))
        var sample = DynamicEObject(eClass: sampleClass)
        sample.eSet("values", value: values)
        let resource = Resource(uri: "memory:/written.json")
        _ = await resource.add(sample)
        return try await JSONSerializer().serialize(resource)
    }

    /// Records every element of a list that does not have exactly the bits of the expected number.
    ///
    /// - Parameters:
    ///   - read: The numbers read back.
    ///   - expected: The numbers written.
    static func expectIdentical(_ read: [Double], _ expected: [Double]) {
        #expect(read.count == expected.count)
        for (value, original) in zip(read, expected) {
            #expect(value.bitPattern == original.bitPattern, "\(value) is not \(original)")
        }
    }

    // MARK: Round trips

    @Test("a list of numbers written by the model serialiser reads back exactly with a metamodel")
    func typedListRoundTrip() async throws {
        let written = try await Self.writtenSample(holding: Self.values)
        let root = try await Self.root(of: written, in: await Self.measurementSet())
        Self.expectIdentical(try #require(root.eGet("values") as? [Double]), Self.values)
    }

    @Test("a list of numbers written by the model serialiser reads back exactly without a metamodel")
    func synthesisedListRoundTrip() async throws {
        let written = try await Self.writtenSample(holding: Self.values)
        let root = try await Self.root(of: written, in: nil)
        Self.expectIdentical(try #require(root.eGet("values") as? [Double]), Self.values)
    }

    @Test("a number written by the model serialiser reads back exactly", arguments: Self.values)
    func typedValueRoundTrip(value: Double) async throws {
        let sampleClass = try #require(Self.measurementPackage().getEClass("Sample"))
        var sample = DynamicEObject(eClass: sampleClass)
        sample.eSet("value", value: value)
        let resource = Resource(uri: "memory:/written.json")
        _ = await resource.add(sample)
        let written = try await JSONSerializer().serialize(resource)
        let root = try await Self.root(of: written, in: await Self.measurementSet())
        let read = try #require(root.eGet("value") as? Double)
        #expect(read.bitPattern == value.bitPattern, "\(written)")
    }

    // MARK: Seventeen digits

    @Test("a number with seventeen digits reads as the nearest number", arguments: Self.seventeenDigitTexts)
    func seventeenDigits(text: String) async throws {
        let expected = try #require(Double(text))
        let document = #"{"eClass": "\#(Self.sampleClass)", "value": \#(text), "values": [\#(text)]}"#
        let typed = try await Self.root(of: document, in: await Self.measurementSet())
        #expect((typed.eGet("value") as? Double)?.bitPattern == expected.bitPattern)
        Self.expectIdentical(try #require(typed.eGet("values") as? [Double]), [expected])
    }

    @Test("a fractional number with seventeen digits of an undeclared key reads as the nearest number",
        arguments: Self.seventeenDigitTexts.filter { $0.contains(".") || $0.contains("e") })
    func undeclaredSeventeenDigits(text: String) async throws {
        let expected = try #require(Double(text))
        let document = #"{"eClass": "\#(Self.sampleClass)", "reading": \#(text)}"#
        let root = try await Self.root(of: document, in: await Self.measurementSet())
        let read = try #require(root.eGet("reading") as? Double)
        #expect(read.bitPattern == expected.bitPattern)
    }

    @Test("the known seventeen digit number reads as Swift reads its text")
    func knownSeventeenDigitNumber() async throws {
        let expected = try #require(Double(Self.seventeenDigitText))
        let text = Self.seventeenDigitText
        let document = #"{"eClass": "\#(Self.sampleClass)", "value": \#(text), "reading": \#(text)}"#
        let typed = try await Self.root(of: document, in: await Self.measurementSet())
        #expect((typed.eGet("value") as? Double)?.bitPattern == expected.bitPattern)
        #expect((typed.eGet("reading") as? Double)?.bitPattern == expected.bitPattern)
        let synthesised = try await Self.root(of: document, in: nil)
        #expect((synthesised.eGet("value") as? Double)?.bitPattern == expected.bitPattern)
    }

    // MARK: Kinds

    @Test("whole numbers, negative zero and Booleans keep their kinds")
    func kindsArePreserved() async throws {
        let document = #"{"eClass": "Counter", "count": -0, "total": 42, "flag": true, "ratio": -0.0, "list": [-0, 3]}"#
        let synthesised = try await Self.root(of: document, in: nil)
        #expect(synthesised.eGet("count") as? Int == 0)
        #expect(synthesised.eGet("total") as? Int == 42)
        #expect(synthesised.eGet("flag") as? Bool == true)
        #expect((synthesised.eGet("ratio") as? Double)?.bitPattern == (-0.0 as Double).bitPattern)
        #expect(synthesised.eGet("list") as? [Int] == [0, 3])
        let undeclared = #"{"eClass": "\#(Self.sampleClass)", "count": -0, "total": 42, "flag": false}"#
        let typed = try await Self.root(of: undeclared, in: await Self.measurementSet())
        #expect(typed.eGet("count") as? Int == 0)
        #expect(typed.eGet("total") as? Int == 42)
        #expect(typed.eGet("flag") as? Bool == false)
    }

    @Test("negative zero inside strings and nested objects is told apart from negative zero numbers")
    func negativeZeroInContext() async throws {
        let document = #"""
            [{"eClass": "\#(Self.sampleClass)", "value": -0, "values": [0, -0, 1]},
             {"eClass": "\#(Self.sampleClass)", "value": 0, "note": "a -0, b \"-0\"", "values": [-0.0]}]
            """#
        let resource = try await JSONParser(resourceSet: await Self.measurementSet())
            .parse(Data(document.utf8), uri: "memory:/zeros.json")
        let roots = await resource.getRootObjects().compactMap { $0 as? DynamicEObject }
        try #require(roots.count == 2)
        let negativeZero = (-0.0 as Double).bitPattern
        #expect((roots[0].eGet("value") as? Double)?.bitPattern == negativeZero)
        let expected = [0, negativeZero, (1.0 as Double).bitPattern]
        #expect((roots[0].eGet("values") as? [Double])?.map(\.bitPattern) == expected)
        #expect((roots[1].eGet("value") as? Double)?.bitPattern == 0)
        #expect(roots[1].eGet("note") as? String == #"a -0, b "-0""#)
        #expect((roots[1].eGet("values") as? [Double])?.map(\.bitPattern) == [negativeZero])
    }

    @Test("a key that an object holds twice keeps the number that was read")
    func duplicateKeys() async throws {
        let document = #"{"eClass": "\#(Self.sampleClass)", "value": -0, "value": -0, "values": [-0]}"#
        let root = try await Self.root(of: document, in: await Self.measurementSet())
        #expect((root.eGet("value") as? Double)?.bitPattern == 0)
        #expect((root.eGet("values") as? [Double])?.map(\.bitPattern) == [(-0.0 as Double).bitPattern])
    }

    // MARK: Scanning

    /// Documents and whether their text holds the integer `-0` outside strings.
    static let negativeZeroTexts: [(String, Bool)] = [
        ("-0", true), ("[-0]", true), (#"{"a": -0}"#, true), ("[1,-0 ]", true), (#"["a\\", -0]"#, true),
        ("[-0.5]", false), ("[-0e1]", false), ("[-0E1]", false), ("[0, -1, 10, -10]", false), ("[-", false),
        (#"["-0"]"#, false), (#"["a\"-0"]"#, false), (#"{"x-0": 1}"#, false), ("", false),
    ]

    @Test("a scan finds the integer -0 outside strings only", arguments: Self.negativeZeroTexts)
    func negativeZeroScan(text: String, expected: Bool) {
        #expect(OrderedJSON.mayContainNegativeZero(Data(text.utf8)) == expected)
    }

    @Test("an ordered parse reads -0 as negative zero only when asked to")
    func orderedNegativeZero() throws {
        #expect(try OrderedJSON.parse(Data("[-0, 0]".utf8)) == .array([.integer(0), .integer(0)]))
        let kept = try OrderedJSON.parse(Data("[-0, 0, -0.0]".utf8), keepingNegativeZero: true)
        guard case .array(let elements) = kept, elements.count == 3,
            case .number(let negative) = elements[0], case .integer(0) = elements[1],
            case .number(let fraction) = elements[2]
        else {
            Issue.record("\(kept)")
            return
        }
        #expect(negative.bitPattern == (-0.0 as Double).bitPattern)
        #expect(fraction.bitPattern == (-0.0 as Double).bitPattern)
    }

    @Test("a number kept with its text is an integer that reads as its text")
    func numberTextDescription() {
        let written = JSONNumberText(number: NSNumber(value: 0), text: "-0")
        #expect(written.description == "-0")
        #expect(JSONScalarKind.of(written) == .integer)
        #expect(JSONNumbers.literal(written) == "-0")
        #expect(JSONNumbers.number(written) == NSNumber(value: 0))
        #expect(JSONNumbers.number("text") == nil)
        #expect(JSONNumbers.literal("text") == nil)
    }
}
