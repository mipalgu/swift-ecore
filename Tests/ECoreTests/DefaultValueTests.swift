//
// DefaultValueTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Default values of unset features")
struct DefaultValueTests {
    private static let colour = EEnum(
        name: "Colour",
        literals: [EEnumLiteral(name: "Red", value: 0), EEnumLiteral(name: "Green", value: 1)])

    private struct Fixture {
        let flag = EAttribute(name: "flag", eType: EDataType(name: "EBoolean"))
        let count = EAttribute(name: "count", eType: EDataType(name: "EInt"))
        let ratio = EAttribute(name: "ratio", eType: EDataType(name: "EDouble"))
        let single = EAttribute(name: "single", eType: EDataType(name: "EFloat"))
        let long = EAttribute(name: "long", eType: EDataType(name: "ELong"))
        let title = EAttribute(name: "title", eType: EDataType(name: "EString"))
        let titled = EAttribute(
            name: "titled", eType: EDataType(name: "EString"), defaultValueLiteral: "untitled")
        let limit = EAttribute(
            name: "limit", eType: EDataType(name: "EInt"), defaultValueLiteral: "42")
        let enabled = EAttribute(
            name: "enabled", eType: EDataType(name: "EBoolean"), defaultValueLiteral: "true")
        let scale = EAttribute(
            name: "scale", eType: EDataType(name: "EDouble"), defaultValueLiteral: "2.5")
        let tint = EAttribute(name: "tint", eType: DefaultValueTests.colour)
        let accent = EAttribute(
            name: "accent", eType: DefaultValueTests.colour, defaultValueLiteral: "Green")
        let tags = EAttribute(name: "tags", eType: EDataType(name: "EString"), upperBound: -1)
        let marks = EAttribute(name: "marks", eType: EDataType(name: "EInt"), upperBound: -1)
        let other = EReference(name: "other", eType: EClass(name: "Item"))
        let others = EReference(name: "others", eType: EClass(name: "Item"), upperBound: -1)
        let eClass: EClass

        init() {
            eClass = EClass(
                name: "Item",
                eStructuralFeatures: [
                    flag, count, ratio, single, long, title, titled, limit, enabled, scale, tint,
                    accent, tags, marks, other, others,
                ])
        }

        func make() -> DynamicEObject { DynamicEObject(eClass: eClass) }
    }

    @Test("primitive attributes read as their intrinsic defaults")
    func intrinsicDefaults() {
        let fixture = Fixture()
        let object = fixture.make()
        #expect(object.eGetWithDefault("flag") as? Bool == false)
        #expect(object.eGetWithDefault("count") as? Int == 0)
        #expect(object.eGetWithDefault("ratio") as? Double == 0)
        #expect(object.eGetWithDefault("single") as? Float == 0)
        #expect(object.eGetWithDefault("long") as? Int64 == 0)
        #expect(object.eGetWithDefault(fixture.flag) as? Bool == false)
    }

    @Test("default value literals are converted to the attribute type")
    func literalDefaults() {
        let fixture = Fixture()
        let object = fixture.make()
        #expect(object.eGetWithDefault("titled") as? String == "untitled")
        #expect(object.eGetWithDefault("limit") as? Int == 42)
        #expect(object.eGetWithDefault("enabled") as? Bool == true)
        #expect(object.eGetWithDefault("scale") as? Double == 2.5)
        #expect(object.eGetWithDefault("accent") as? String == "Green")
    }

    @Test("strings, single references and enumerations without literal")
    func absentOrFirstLiteral() {
        let fixture = Fixture()
        let object = fixture.make()
        #expect(object.eGetWithDefault("title") == nil)
        #expect(object.eGetWithDefault("other") == nil)
        #expect(object.eGetWithDefault("tint") as? String == "Red")
    }

    @Test("many-valued features read as empty lists")
    func emptyLists() {
        let fixture = Fixture()
        let object = fixture.make()
        #expect(object.eGetWithDefault("tags") as? [String] == [])
        #expect(object.eGetWithDefault("marks") as? [Int] == [])
        #expect(object.eGetWithDefault("others") as? [EUUID] == [])
    }

    @Test("reading a default does not set the feature")
    func eIsSetUnchanged() {
        let fixture = Fixture()
        let object = fixture.make()
        _ = object.eGetWithDefault("flag")
        #expect(!object.eIsSet("flag"))
        #expect(!object.eIsSet(fixture.tags))
        #expect(object.getFeatureNames().isEmpty)
    }

    @Test("stored values win over defaults and plain reads ignore defaults")
    func storedValues() {
        let fixture = Fixture()
        var object = fixture.make()
        #expect(object.eGet("flag") == nil)
        #expect(object.eGet(fixture.tags) == nil)
        object.eSet("flag", value: true)
        object.eSet("limit", value: 7)
        #expect(object.eGetWithDefault("flag") as? Bool == true)
        #expect(object.eGetWithDefault("limit") as? Int == 7)
        #expect(object.eGet("limit") as? Int == 7)
        object.eUnset("limit")
        #expect(object.eGetWithDefault("limit") as? Int == 42)
    }

    @Test("features unknown to the class keep reading as nil")
    func unknownFeature() {
        let object = Fixture().make()
        #expect(object.eGetWithDefault("nothing") == nil)
        #expect(object.eGet("nothing") == nil)
    }

    @Test("unconvertible literals read as the literal text")
    func unconvertibleLiteral() {
        let broken = EAttribute(
            name: "broken", eType: EDataType(name: "EInt"), defaultValueLiteral: "many")
        let object = DynamicEObject(eClass: EClass(name: "B", eStructuralFeatures: [broken]))
        #expect(object.eGetWithDefault("broken") as? String == "many")
    }

    @Test("every primitive type has a default and a typed empty list")
    func primitiveTypes() {
        let names = [
            "EBoolean", "EInt", "EFloat", "EDouble", "EByte", "EShort", "ELong", "EChar", "EDate",
            "EBigDecimal", "EBigInteger", "EIntegerObject", "EBooleanObject", "EFloatObject",
            "EDoubleObject", "EByteObject", "EShortObject", "ELongObject", "ECharacterObject",
        ]
        for name in names {
            let single = EAttribute(name: "s", eType: EDataType(name: name))
            let many = EAttribute(name: "m", eType: EDataType(name: name), upperBound: -1)
            let object = DynamicEObject(
                eClass: EClass(name: "T", eStructuralFeatures: [single, many]))
            #expect(object.eGetWithDefault("m") != nil, "list of \(name)")
            let primitive = ["EBoolean", "EInt", "EFloat", "EDouble", "EByte", "EShort", "ELong"]
            #expect((object.eGetWithDefault("s") != nil) == primitive.contains(name), "default of \(name)")
        }
    }

    @Test("literals convert for every numeric and character type")
    func literalConversions() {
        let cases: [(String, String)] = [
            ("EBoolean", "true"), ("EInt", "3"), ("EFloat", "1.5"), ("EDouble", "1.5"),
            ("EByte", "3"), ("EShort", "3"), ("ELong", "3"), ("EBigDecimal", "1.25"),
            ("EBigInteger", "12"), ("EChar", "x"), ("EIntegerObject", "3"),
            ("EBooleanObject", "true"), ("EFloatObject", "1.5"), ("EDoubleObject", "1.5"),
            ("EByteObject", "3"), ("EShortObject", "3"), ("ELongObject", "3"),
            ("ECharacterObject", "x"),
        ]
        for (name, literal) in cases {
            let attribute = EAttribute(
                name: "a", eType: EDataType(name: name), defaultValueLiteral: literal)
            let object = DynamicEObject(eClass: EClass(name: "T", eStructuralFeatures: [attribute]))
            let value = object.eGetWithDefault("a")
            #expect(value != nil && !(value is String), "literal of \(name)")
        }
    }

    @Test("serialisation still omits unset attributes")
    func serialiserOmitsDefaults() async throws {
        let fixture = Fixture()
        let package = EPackage(
            name: "p", nsURI: "http://example.org/p", nsPrefix: "p",
            eClassifiers: [fixture.eClass])
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(package, uri: package.nsURI)
        let resource = await resourceSet.createResource(uri: "memory:/defaults.xmi")
        var object = fixture.make()
        object.eSet("title", value: "t")
        _ = await resource.add(object)
        let text = try await XMISerializer(options: .emf).serialize(resource)
        #expect(text.contains("title=\"t\""))
        #expect(!text.contains("flag="))
        #expect(!text.contains("count="))
        #expect(!text.contains("limit="))
    }
}
