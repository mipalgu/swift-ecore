//
// EcoreTypesTests.swift
// EMFBaseTests
//
// Created by Rene Hexel on 18/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//

import BigInt
import Foundation
import Testing

@testable import EMFBase

@Suite("Ecore Types Tests")
struct EcoreTypesTests {

    // MARK: - EcoreValue Protocol Tests

    @Test("String can be stored as EcoreValue")
    func testStringAsEcoreValue() throws {
        let value: EString = "test"
        let stored: any EcoreValue = value
        #expect(stored as? EString == "test")
    }

    @Test("Int can be stored as EcoreValue")
    func testIntAsEcoreValue() throws {
        let value: EInt = 42
        let stored: any EcoreValue = value
        #expect(stored as? EInt == 42)
    }

    @Test("Bool can be stored as EcoreValue")
    func testBoolAsEcoreValue() throws {
        let value: EBoolean = true
        let stored: any EcoreValue = value
        #expect(stored as? EBoolean == true)
    }

    @Test("Double can be stored as EcoreValue")
    func testDoubleAsEcoreValue() throws {
        let value: EDouble = 3.14
        let stored: any EcoreValue = value
        #expect(stored as? EDouble == 3.14)
    }

    @Test("Float can be stored as EcoreValue")
    func testFloatAsEcoreValue() throws {
        let value: EFloat = 2.718
        let stored: any EcoreValue = value
        #expect(stored as? EFloat == 2.718)
    }

    @Test("UUID can be stored as EcoreValue")
    func testUUIDAsEcoreValue() throws {
        let value: EUUID = UUID()
        let stored: any EcoreValue = value
        #expect(stored as? EUUID == value)
    }

    @Test("BigInt can be stored as EcoreValue")
    func testBigIntAsEcoreValue() throws {
        let value: EBigInteger = BigInt(123_456_789)
        let stored: any EcoreValue = value
        #expect(stored as? EBigInteger == value)
    }

    @Test("Decimal can be stored as EcoreValue")
    func testDecimalAsEcoreValue() throws {
        let value: EBigDecimal = Decimal(123.456)
        let stored: any EcoreValue = value
        #expect(stored as? EBigDecimal == value)
    }

    // MARK: - areEqual Function Tests

    @Test("areEqual returns true for equal strings")
    func testAreEqualStrings() throws {
        let left: any EcoreValue = "hello" as EString
        let right: any EcoreValue = "hello" as EString
        #expect(areEqual(left, right))
    }

    @Test("areEqual returns false for different strings")
    func testAreEqualDifferentStrings() throws {
        let left: any EcoreValue = "hello" as EString
        let right: any EcoreValue = "world" as EString
        #expect(!areEqual(left, right))
    }

    @Test("areEqual returns true for equal integers")
    func testAreEqualIntegers() throws {
        let left: any EcoreValue = 42 as EInt
        let right: any EcoreValue = 42 as EInt
        #expect(areEqual(left, right))
    }

    @Test("areEqual returns false for different integers")
    func testAreEqualDifferentIntegers() throws {
        let left: any EcoreValue = 42 as EInt
        let right: any EcoreValue = 24 as EInt
        #expect(!areEqual(left, right))
    }

    @Test("areEqual returns true for equal booleans")
    func testAreEqualBooleans() throws {
        let left: any EcoreValue = true as EBoolean
        let right: any EcoreValue = true as EBoolean
        #expect(areEqual(left, right))
    }

    @Test("areEqual returns false for different booleans")
    func testAreEqualDifferentBooleans() throws {
        let left: any EcoreValue = true as EBoolean
        let right: any EcoreValue = false as EBoolean
        #expect(!areEqual(left, right))
    }

    @Test("areEqual returns false for different types")
    func testAreEqualDifferentTypes() throws {
        let left: any EcoreValue = 42 as EInt
        let right: any EcoreValue = "42" as EString
        #expect(!areEqual(left, right))
    }

    @Test("areEqual returns true for equal doubles")
    func testAreEqualDoubles() throws {
        let left: any EcoreValue = 3.14159 as EDouble
        let right: any EcoreValue = 3.14159 as EDouble
        #expect(areEqual(left, right))
    }

    @Test("areEqual returns true for equal BigInt values")
    func testAreEqualBigInts() throws {
        let left: any EcoreValue = BigInt(123_456_789) as EBigInteger
        let right: any EcoreValue = BigInt(123_456_789) as EBigInteger
        #expect(areEqual(left, right))
    }

    @Test("areEqual returns true for equal UUIDs")
    func testAreEqualUUIDs() throws {
        let uuid = UUID()
        let left: any EcoreValue = uuid as EUUID
        let right: any EcoreValue = uuid as EUUID
        #expect(areEqual(left, right))
    }

    // MARK: - areEqualOptional Function Tests

    @Test("areEqualOptional returns true for both nil")
    func testAreEqualOptionalBothNil() throws {
        let left: (any EcoreValue)? = nil
        let right: (any EcoreValue)? = nil
        #expect(areEqualOptional(left, right))
    }

    @Test("areEqualOptional returns false for one nil")
    func testAreEqualOptionalOneNil() throws {
        let left: (any EcoreValue)? = "test" as EString
        let right: (any EcoreValue)? = nil
        #expect(!areEqualOptional(left, right))
    }

    @Test("areEqualOptional returns true for equal non-nil values")
    func testAreEqualOptionalBothValues() throws {
        let left: (any EcoreValue)? = "test" as EString
        let right: (any EcoreValue)? = "test" as EString
        #expect(areEqualOptional(left, right))
    }

    // MARK: - hash Function Tests

    @Test("hash function produces consistent results for same value")
    func testHashConsistency() throws {
        let value: any EcoreValue = "test" as EString

        var hasher1 = Hasher()
        hash(value, into: &hasher1)
        let hash1 = hasher1.finalize()

        var hasher2 = Hasher()
        hash(value, into: &hasher2)
        let hash2 = hasher2.finalize()

        #expect(hash1 == hash2)
    }

    @Test("hash function produces different results for different values")
    func testHashDifferentValues() throws {
        let value1: any EcoreValue = "test1" as EString
        let value2: any EcoreValue = "test2" as EString

        var hasher1 = Hasher()
        hash(value1, into: &hasher1)
        let hash1 = hasher1.finalize()

        var hasher2 = Hasher()
        hash(value2, into: &hasher2)
        let hash2 = hasher2.finalize()

        #expect(hash1 != hash2)
    }

    @Test("hash function handles all basic types")
    func testHashAllTypes() throws {
        let values: [any EcoreValue] = [
            "string" as EString,
            42 as EInt,
            true as EBoolean,
            3.14 as EDouble,
            2.718 as EFloat,
            UUID() as EUUID,
            BigInt(999) as EBigInteger,
            Decimal(123.45) as EBigDecimal,
            Date() as EDate,
            "c" as Character as EChar,
            Int8(8) as EByte,
            Int16(16) as EShort,
            Int64(64) as ELong,
        ]

        // Ensure all types can be hashed without crashing
        for value in values {
            var hasher = Hasher()
            hash(value, into: &hasher)
            let _ = hasher.finalize()
        }
    }

    // MARK: - EcoreValueArray Tests

    @Test("EcoreValueArray equality with same elements")
    func testEcoreValueArrayEquality() throws {
        let array1 = EcoreValueArray([
            "hello" as EString,
            42 as EInt,
            true as EBoolean,
        ])

        let array2 = EcoreValueArray([
            "hello" as EString,
            42 as EInt,
            true as EBoolean,
        ])

        #expect(array1 == array2)
    }

    @Test("EcoreValueArray inequality with different elements")
    func testEcoreValueArrayInequality() throws {
        let array1 = EcoreValueArray([
            "hello" as EString,
            42 as EInt,
        ])

        let array2 = EcoreValueArray([
            "world" as EString,
            42 as EInt,
        ])

        #expect(array1 != array2)
    }

    @Test("EcoreValueArray inequality with different lengths")
    func testEcoreValueArrayDifferentLengths() throws {
        let array1 = EcoreValueArray([
            "hello" as EString
        ])

        let array2 = EcoreValueArray([
            "hello" as EString,
            42 as EInt,
        ])

        #expect(array1 != array2)
    }

    @Test("EcoreValueArray empty arrays are equal")
    func testEcoreValueArrayEmptyEquality() throws {
        let array1 = EcoreValueArray([])
        let array2 = EcoreValueArray([])
        #expect(array1 == array2)
    }

    @Test("EcoreValueArray hashing consistency")
    func testEcoreValueArrayHashConsistency() throws {
        let array = EcoreValueArray([
            "test" as EString,
            42 as EInt,
        ])

        let hash1 = array.hashValue
        let hash2 = array.hashValue

        #expect(hash1 == hash2)
    }

    @Test("EcoreValueArray different arrays have different hashes")
    func testEcoreValueArrayDifferentHashes() throws {
        let array1 = EcoreValueArray(["test1" as EString])
        let array2 = EcoreValueArray(["test2" as EString])

        // Note: Hash values can collide, but they should be different most of the time
        #expect(array1.hashValue != array2.hashValue)
    }

    // MARK: - EcoreTypeConverter Tests

    @Test("EcoreTypeConverter fromString converts string")
    func testFromStringString() throws {
        let result = EcoreTypeConverter.fromString("hello", as: String.self)
        #expect(result == "hello")
    }

    @Test("EcoreTypeConverter fromString converts int")
    func testFromStringInt() throws {
        let result = EcoreTypeConverter.fromString("42", as: Int.self)
        #expect(result == 42)
    }

    @Test("EcoreTypeConverter fromString converts bool true")
    func testFromStringBoolTrue() throws {
        let result = EcoreTypeConverter.fromString("true", as: Bool.self)
        #expect(result == true)
    }

    @Test("EcoreTypeConverter fromString converts bool false")
    func testFromStringBoolFalse() throws {
        let result = EcoreTypeConverter.fromString("false", as: Bool.self)
        #expect(result == false)
    }

    @Test("EcoreTypeConverter fromString converts double")
    func testFromStringDouble() throws {
        let result = EcoreTypeConverter.fromString("3.14", as: Double.self)
        #expect(result == 3.14)
    }

    @Test("EcoreTypeConverter fromString converts BigInt")
    func testFromStringBigInt() throws {
        let result = EcoreTypeConverter.fromString("123456789", as: BigInt.self)
        #expect(result == BigInt(123_456_789))
    }

    @Test("EcoreTypeConverter fromString returns nil for invalid int")
    func testFromStringInvalidInt() throws {
        let result = EcoreTypeConverter.fromString("not-a-number", as: Int.self)
        #expect(result == nil)
    }

    @Test("EcoreTypeConverter fromString returns nil for unsupported type")
    func testFromStringUnsupportedType() throws {
        let result = EcoreTypeConverter.fromString("test", as: Date.self)
        #expect(result == nil)
    }

    @Test("EcoreTypeConverter toString converts various types")
    func testToString() throws {
        #expect(EcoreTypeConverter.toString("hello") == "hello")
        #expect(EcoreTypeConverter.toString(42) == "42")
        #expect(EcoreTypeConverter.toString(true) == "true")
        #expect(EcoreTypeConverter.toString(3.14) == "3.14")
        #expect(EcoreTypeConverter.toString(BigInt(999)) == "999")
    }
}
