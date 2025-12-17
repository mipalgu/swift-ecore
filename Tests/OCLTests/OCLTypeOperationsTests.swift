//
// OCLTypeOperationsTests.swift
// OCL
//
//  Created by Rene Hexel on 18/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//

import EMFBase
import Testing

@testable import OCL

@Suite("OCL Type Operations")
struct OCLTypeOperationsTests {

    // MARK: - oclIsTypeOf() Tests

    @Test("oclIsTypeOf returns true for exact type match")
    func testOclIsTypeOfExactMatch() throws {
        let intValue: any EcoreValue = 42 as EInt
        let stringValue: any EcoreValue = "Hello" as EString
        let doubleValue: any EcoreValue = 3.14 as EDouble
        let boolValue: any EcoreValue = true as EBoolean

        #expect(try oclIsTypeOf(intValue, EInt.self) == true)
        #expect(try oclIsTypeOf(stringValue, EString.self) == true)
        #expect(try oclIsTypeOf(doubleValue, EDouble.self) == true)
        #expect(try oclIsTypeOf(boolValue, EBoolean.self) == true)
    }

    @Test("oclIsTypeOf returns false for different types")
    func testOclIsTypeOfDifferentTypes() throws {
        let intValue: any EcoreValue = 42 as EInt
        let stringValue: any EcoreValue = "Hello" as EString

        #expect(try oclIsTypeOf(intValue, EString.self) == false)
        #expect(try oclIsTypeOf(stringValue, EInt.self) == false)
        #expect(try oclIsTypeOf(intValue, EDouble.self) == false)
        #expect(try oclIsTypeOf(stringValue, EBoolean.self) == false)
    }

    @Test("oclIsTypeOf returns false for supertype")
    func testOclIsTypeOfSupertype() throws {
        let intValue: any EcoreValue = 42 as EInt

        // Even though Int conforms to Any, oclIsTypeOf is strict
        #expect(try oclIsTypeOf(intValue, Any.self) == false)
    }

    @Test("oclIsTypeOf works with array types")
    func testOclIsTypeOfArrays() throws {
        let arrayValue: any EcoreValue = EcoreValueArray([1, 2, 3])
        let wrapperValue: any EcoreValue = EcoreValueArray([1, 2, 3])

        #expect(try oclIsTypeOf(arrayValue, EcoreValueArray.self) == true)
        #expect(try oclIsTypeOf(wrapperValue, EcoreValueArray.self) == true)
        #expect(try oclIsTypeOf(arrayValue, [EInt].self) == false)
        #expect(try oclIsTypeOf(wrapperValue, [EInt].self) == false)
    }

    // MARK: - oclIsKindOf() Tests

    @Test("oclIsKindOf returns true for exact type match")
    func testOclIsKindOfExactMatch() throws {
        let intValue: any EcoreValue = 42 as EInt
        let stringValue: any EcoreValue = "Hello" as EString
        let doubleValue: any EcoreValue = 3.14 as EDouble

        #expect(try oclIsKindOf(intValue, EInt.self) == true)
        #expect(try oclIsKindOf(stringValue, EString.self) == true)
        #expect(try oclIsKindOf(doubleValue, EDouble.self) == true)
    }

    @Test("oclIsKindOf returns true for supertypes")
    func testOclIsKindOfSupertypes() throws {
        let intValue: any EcoreValue = 42 as EInt
        let stringValue: any EcoreValue = "Hello" as EString

        // These should return true because of type hierarchy
        #expect(try oclIsKindOf(intValue, Any.self) == true)
        #expect(try oclIsKindOf(stringValue, Any.self) == true)
    }

    @Test("oclIsKindOf returns false for unrelated types")
    func testOclIsKindOfUnrelatedTypes() throws {
        let intValue: any EcoreValue = 42 as EInt
        let stringValue: any EcoreValue = "Hello" as EString

        #expect(try oclIsKindOf(intValue, EString.self) == false)
        #expect(try oclIsKindOf(stringValue, EInt.self) == false)
    }

    @Test("oclIsKindOf works with protocol conformance")
    func testOclIsKindOfProtocolConformance() throws {
        let intValue: any EcoreValue = 42 as EInt
        let stringValue: any EcoreValue = "Hello" as EString
        let arrayValue: any EcoreValue = EcoreValueArray([1, 2, 3])

        // All EcoreValue types should conform to EcoreValue
        #expect(try oclIsKindOf(intValue, (any EcoreValue).self) == true)
        #expect(try oclIsKindOf(stringValue, (any EcoreValue).self) == true)
        #expect(try oclIsKindOf(arrayValue, (any EcoreValue).self) == true)
    }

    // MARK: - oclAsType() Tests

    @Test("oclAsType succeeds for valid cast")
    func testOclAsTypeValidCast() throws {
        let intValue: any EcoreValue = 42 as EInt
        let stringValue: any EcoreValue = "Hello" as EString
        let doubleValue: any EcoreValue = 3.14 as EDouble

        let castInt = try oclAsType(intValue, EInt.self)
        #expect(castInt == 42)

        let castString = try oclAsType(stringValue, EString.self)
        #expect(castString == "Hello")

        let castDouble = try oclAsType(doubleValue, EDouble.self)
        #expect(castDouble == 3.14)
    }

    @Test("oclAsType throws error for invalid cast")
    func testOclAsTypeInvalidCast() throws {
        let intValue: any EcoreValue = 42 as EInt
        let stringValue: any EcoreValue = "Hello" as EString

        #expect(throws: OCLError.typeError("Cannot cast Int to String")) {
            try oclAsType(intValue, EString.self)
        }

        #expect(throws: OCLError.typeError("Cannot cast String to Int")) {
            try oclAsType(stringValue, EInt.self)
        }
    }

    @Test("oclAsType works with supertype cast")
    func testOclAsTypeSupertypeCast() throws {
        let intValue: any EcoreValue = 42 as EInt

        // This should work since Int is-a Any
        let castAny = try oclAsType(intValue, Any.self)
        #expect(castAny as? EInt == 42)
    }

    @Test("oclAsType preserves value during cast")
    func testOclAsTypePreservesValue() throws {
        let originalValue = 123.456 as EDouble
        let ecoreValue: any EcoreValue = originalValue

        let castValue = try oclAsType(ecoreValue, EDouble.self)
        #expect(castValue == originalValue)
    }

    // MARK: - oclIsTypeOfName() Tests

    @Test("oclIsTypeOfName recognises basic types")
    func testOclIsTypeOfNameBasicTypes() throws {
        let intValue: any EcoreValue = 42 as EInt
        let stringValue: any EcoreValue = "Hello" as EString
        let doubleValue: any EcoreValue = 3.14 as EDouble
        let floatValue: any EcoreValue = 2.5 as EFloat
        let boolValue: any EcoreValue = true as EBoolean

        #expect(try oclIsTypeOfName(intValue, "EInt") == true)
        #expect(try oclIsTypeOfName(stringValue, "EString") == true)
        #expect(try oclIsTypeOfName(doubleValue, "EDouble") == true)
        #expect(try oclIsTypeOfName(floatValue, "EFloat") == true)
        #expect(try oclIsTypeOfName(boolValue, "EBoolean") == true)
    }

    @Test("oclIsTypeOfName returns false for wrong type names")
    func testOclIsTypeOfNameWrongTypes() throws {
        let intValue: any EcoreValue = 42 as EInt

        #expect(try oclIsTypeOfName(intValue, "EString") == false)
        #expect(try oclIsTypeOfName(intValue, "EDouble") == false)
        #expect(try oclIsTypeOfName(intValue, "EBoolean") == false)
    }

    @Test("oclIsTypeOfName recognises array wrapper")
    func testOclIsTypeOfNameArrayWrapper() throws {
        let wrapperValue: any EcoreValue = EcoreValueArray([1, 2, 3])
        let regularArray: any EcoreValue = EcoreValueArray([1, 2, 3])

        #expect(try oclIsTypeOfName(wrapperValue, "EcoreValueArray") == true)
        #expect(try oclIsTypeOfName(regularArray, "EcoreValueArray") == true)
    }

    @Test("oclIsTypeOfName throws error for unknown type name")
    func testOclIsTypeOfNameUnknownType() throws {
        let intValue: any EcoreValue = 42 as EInt

        #expect(throws: OCLError.invalidArguments("Unknown type name: UnknownType")) {
            try oclIsTypeOfName(intValue, "UnknownType")
        }
    }

    // MARK: - oclTypeName() Tests

    @Test("oclTypeName returns correct names for basic types")
    func testOclTypeNameBasicTypes() throws {
        let intValue: any EcoreValue = 42 as EInt
        let stringValue: any EcoreValue = "Hello" as EString
        let doubleValue: any EcoreValue = 3.14 as EDouble
        let floatValue: any EcoreValue = 2.5 as EFloat
        let boolValue: any EcoreValue = true as EBoolean

        #expect(try oclTypeName(intValue) == "EInt")
        #expect(try oclTypeName(stringValue) == "EString")
        #expect(try oclTypeName(doubleValue) == "EDouble")
        #expect(try oclTypeName(floatValue) == "EFloat")
        #expect(try oclTypeName(boolValue) == "EBoolean")
    }

    @Test("oclTypeName returns correct names for collection types")
    func testOclTypeNameCollectionTypes() throws {
        let arrayValue: any EcoreValue = EcoreValueArray([1, 2, 3])
        let wrapperValue: any EcoreValue = EcoreValueArray([1, 2, 3])

        #expect(try oclTypeName(arrayValue) == "EcoreValueArray")
        #expect(try oclTypeName(wrapperValue) == "EcoreValueArray")
    }

    // MARK: - Integration and Edge Case Tests

    @Test("type operations work with complex nested structures")
    func testComplexNestedStructures() throws {
        let nestedArray: any EcoreValue = EcoreValueArray([
            EcoreValueArray([1, 2]),
            EcoreValueArray([3, 4]),
        ])

        #expect(try oclIsTypeOf(nestedArray, EcoreValueArray.self) == true)
        #expect(try oclIsKindOf(nestedArray, EcoreValueArray.self) == true)
        #expect(try oclTypeName(nestedArray) == "EcoreValueArray")
    }

    @Test("type operations handle edge cases")
    func testEdgeCases() throws {
        // Empty array
        let emptyArray: any EcoreValue = EcoreValueArray([])
        #expect(try oclTypeName(emptyArray) == "EcoreValueArray")
        #expect(try oclIsTypeOf(emptyArray, EcoreValueArray.self) == true)

        // Zero values
        let zeroInt: any EcoreValue = 0 as EInt
        let zeroDouble: any EcoreValue = 0.0 as EDouble
        #expect(try oclTypeName(zeroInt) == "EInt")
        #expect(try oclTypeName(zeroDouble) == "EDouble")

        // Empty string
        let emptyString: any EcoreValue = "" as EString
        #expect(try oclTypeName(emptyString) == "EString")
        #expect(try oclIsTypeOf(emptyString, EString.self) == true)
    }

    @Test("type operations are consistent with each other")
    func testTypeOperationConsistency() throws {
        let testValues: [any EcoreValue] = [
            42 as EInt,
            "Hello" as EString,
            3.14 as EDouble,
            2.5 as EFloat,
            true as EBoolean,
            EcoreValueArray([1, 2, 3]),
            EcoreValueArray([1, 2, 3]),
        ]

        for value in testValues {
            let typeName = try oclTypeName(value)

            // If we can get a type name, we should be able to check it
            switch typeName {
            case "EInt":
                #expect(try oclIsTypeOf(value, EInt.self) == true)
                #expect(try oclIsKindOf(value, EInt.self) == true)
                #expect(try oclIsTypeOfName(value, "EInt") == true)
            case "EString":
                #expect(try oclIsTypeOf(value, EString.self) == true)
                #expect(try oclIsKindOf(value, EString.self) == true)
                #expect(try oclIsTypeOfName(value, "EString") == true)
            case "EDouble":
                #expect(try oclIsTypeOf(value, EDouble.self) == true)
                #expect(try oclIsKindOf(value, EDouble.self) == true)
                #expect(try oclIsTypeOfName(value, "EDouble") == true)
            case "EFloat":
                #expect(try oclIsTypeOf(value, EFloat.self) == true)
                #expect(try oclIsKindOf(value, EFloat.self) == true)
                #expect(try oclIsTypeOfName(value, "EFloat") == true)
            case "EBoolean":
                #expect(try oclIsTypeOf(value, EBoolean.self) == true)
                #expect(try oclIsKindOf(value, EBoolean.self) == true)
                #expect(try oclIsTypeOfName(value, "EBoolean") == true)
            case "Array":
                // Skip this case as we don't use raw arrays in tests
                break
            case "EcoreValueArray":
                #expect(try oclIsTypeOf(value, EcoreValueArray.self) == true)
                #expect(try oclIsKindOf(value, EcoreValueArray.self) == true)
                #expect(try oclIsTypeOfName(value, "EcoreValueArray") == true)
            default:
                break
            }
        }
    }

    @Test("chained type operations work correctly")
    func testChainedTypeOperations() throws {
        let value: any EcoreValue = 42 as EInt

        // First check if it's an integer
        if try oclIsKindOf(value, EInt.self) {
            // Then safely cast it
            let intValue = try oclAsType(value, EInt.self)
            #expect(intValue == 42)

            // Verify type name matches
            let typeName = try oclTypeName(value)
            #expect(typeName == "EInt")
        }
    }
}
