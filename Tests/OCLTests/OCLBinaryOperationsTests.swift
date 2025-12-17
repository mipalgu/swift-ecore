//
// OCLBinaryOperationsTests.swift
// OCLTests
//
// Created by Rene Hexel on 18/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import OCL

@Suite("OCL Binary Operations")
struct OCLBinaryOperationsTests {

    // MARK: - Arithmetic Operations Tests

    @Test("Add integers")
    func testAddIntegers() throws {
        let result = try add(5 as EInt, 3 as EInt)
        #expect(result as? EInt == 8)
    }

    @Test("Add doubles")
    func testAddDoubles() throws {
        let result = try add(5.5 as EDouble, 2.3 as EDouble)
        #expect(result as? EDouble == 7.8)
    }

    @Test("Add floats")
    func testAddFloats() throws {
        let result = try add(5.5 as EFloat, 2.3 as EFloat)
        let expected: EFloat = 7.8
        #expect(abs((result as? EFloat ?? 0) - expected) < 0.001)
    }

    @Test("Add strings (concatenation)")
    func testAddStrings() throws {
        let result = try add("Hello" as EString, " World" as EString)
        #expect(result as? EString == "Hello World")
    }

    @Test("Add int and double (type coercion)")
    func testAddIntAndDouble() throws {
        let result = try add(5 as EInt, 3.5 as EDouble)
        #expect(result as? EDouble == 8.5)
    }

    @Test("Add double and int (type coercion)")
    func testAddDoubleAndInt() throws {
        let result = try add(5.5 as EDouble, 3 as EInt)
        #expect(result as? EDouble == 8.5)
    }

    @Test("Add int and float (type coercion)")
    func testAddIntAndFloat() throws {
        let result = try add(5 as EInt, 3.5 as EFloat)
        let expected: EFloat = 8.5
        #expect(abs((result as? EFloat ?? 0) - expected) < 0.001)
    }

    @Test("Add float and double (type coercion)")
    func testAddFloatAndDouble() throws {
        let result = try add(5.5 as EFloat, 2.3 as EDouble)
        #expect(result as? EDouble == 7.8)
    }

    @Test("Add incompatible types throws error")
    func testAddIncompatibleTypes() throws {
        #expect(throws: OCLError.invalidArguments("Cannot add values of types Int and Bool")) {
            try add(5 as EInt, true as EBoolean)
        }
    }

    @Test("Subtract integers")
    func testSubtractIntegers() throws {
        let result = try subtract(10 as EInt, 3 as EInt)
        #expect(result as? EInt == 7)
    }

    @Test("Subtract doubles")
    func testSubtractDoubles() throws {
        let result = try subtract(10.5 as EDouble, 2.3 as EDouble)
        #expect(abs((result as? EDouble ?? 0) - 8.2) < 0.001)
    }

    @Test("Subtract with type coercion")
    func testSubtractWithTypeCoercion() throws {
        let result = try subtract(10 as EInt, 3.5 as EDouble)
        #expect(result as? EDouble == 6.5)
    }

    @Test("Multiply integers")
    func testMultiplyIntegers() throws {
        let result = try multiply(6 as EInt, 7 as EInt)
        #expect(result as? EInt == 42)
    }

    @Test("Multiply doubles")
    func testMultiplyDoubles() throws {
        let result = try multiply(2.5 as EDouble, 4.0 as EDouble)
        #expect(result as? EDouble == 10.0)
    }

    @Test("Multiply with type coercion")
    func testMultiplyWithTypeCoercion() throws {
        let result = try multiply(5 as EInt, 2.5 as EDouble)
        #expect(result as? EDouble == 12.5)
    }

    @Test("Divide integers")
    func testDivideIntegers() throws {
        let result = try divide(12 as EInt, 4 as EInt)
        #expect(result as? EInt == 3)
    }

    @Test("Divide doubles")
    func testDivideDoubles() throws {
        let result = try divide(15.0 as EDouble, 3.0 as EDouble)
        #expect(result as? EDouble == 5.0)
    }

    @Test("Divide with type coercion")
    func testDivideWithTypeCoercion() throws {
        let result = try divide(15 as EInt, 2.5 as EDouble)
        #expect(result as? EDouble == 6.0)
    }

    @Test("Division by zero integer throws error")
    func testDivisionByZeroInteger() throws {
        #expect(throws: OCLError.divisionByZero) {
            try divide(10 as EInt, 0 as EInt)
        }
    }

    @Test("Division by zero double throws error")
    func testDivisionByZeroDouble() throws {
        #expect(throws: OCLError.divisionByZero) {
            try divide(10.5 as EDouble, 0.0 as EDouble)
        }
    }

    @Test("Modulo integers")
    func testModuloIntegers() throws {
        let result = try modulo(17 as EInt, 5 as EInt)
        #expect(result as? EInt == 2)
    }

    @Test("Modulo by zero throws error")
    func testModuloByZero() throws {
        #expect(throws: OCLError.divisionByZero) {
            try modulo(10 as EInt, 0 as EInt)
        }
    }

    @Test("Modulo non-integer types throws error")
    func testModuloNonInteger() throws {
        #expect(
            throws: OCLError.invalidArguments(
                "Modulo operation requires integer operands, got Double and Int")
        ) {
            try modulo(5.5 as EDouble, 3 as EInt)
        }
    }

    // MARK: - Comparison Operations Tests

    @Test("Less than integers")
    func testLessThanIntegers() throws {
        #expect(try lessThan(3 as EInt, 5 as EInt) == true)
        #expect(try lessThan(5 as EInt, 3 as EInt) == false)
        #expect(try lessThan(5 as EInt, 5 as EInt) == false)
    }

    @Test("Less than doubles")
    func testLessThanDoubles() throws {
        #expect(try lessThan(3.5 as EDouble, 5.2 as EDouble) == true)
        #expect(try lessThan(5.2 as EDouble, 3.5 as EDouble) == false)
    }

    @Test("Less than strings")
    func testLessThanStrings() throws {
        #expect(try lessThan("apple" as EString, "banana" as EString) == true)
        #expect(try lessThan("zebra" as EString, "apple" as EString) == false)
    }

    @Test("Less than with type coercion")
    func testLessThanWithTypeCoercion() throws {
        #expect(try lessThan(3 as EInt, 5.5 as EDouble) == true)
        #expect(try lessThan(5.5 as EDouble, 3 as EInt) == false)
    }

    @Test("Less than or equal integers")
    func testLessThanOrEqualIntegers() throws {
        #expect(try lessThanOrEqual(3 as EInt, 5 as EInt) == true)
        #expect(try lessThanOrEqual(5 as EInt, 5 as EInt) == true)
        #expect(try lessThanOrEqual(7 as EInt, 5 as EInt) == false)
    }

    @Test("Greater than integers")
    func testGreaterThanIntegers() throws {
        #expect(try greaterThan(5 as EInt, 3 as EInt) == true)
        #expect(try greaterThan(3 as EInt, 5 as EInt) == false)
        #expect(try greaterThan(5 as EInt, 5 as EInt) == false)
    }

    @Test("Greater than or equal integers")
    func testGreaterThanOrEqualIntegers() throws {
        #expect(try greaterThanOrEqual(5 as EInt, 3 as EInt) == true)
        #expect(try greaterThanOrEqual(5 as EInt, 5 as EInt) == true)
        #expect(try greaterThanOrEqual(3 as EInt, 5 as EInt) == false)
    }

    @Test("Equals same values")
    func testEqualsSameValues() throws {
        #expect(equals(42 as EInt, 42 as EInt) == true)
        #expect(equals("hello" as EString, "hello" as EString) == true)
        #expect(equals(3.14 as EDouble, 3.14 as EDouble) == true)
        #expect(equals(true as EBoolean, true as EBoolean) == true)
    }

    @Test("Equals different values")
    func testEqualsDifferentValues() throws {
        #expect(equals(42 as EInt, 43 as EInt) == false)
        #expect(equals("hello" as EString, "world" as EString) == false)
        #expect(equals(3.14 as EDouble, 2.71 as EDouble) == false)
        #expect(equals(true as EBoolean, false as EBoolean) == false)
    }

    @Test("Equals different types")
    func testEqualsDifferentTypes() throws {
        #expect(equals(42 as EInt, "42" as EString) == false)
        #expect(equals(1 as EInt, true as EBoolean) == false)
    }

    @Test("Not equals same values")
    func testNotEqualsSameValues() throws {
        #expect(notEquals(42 as EInt, 42 as EInt) == false)
        #expect(notEquals("hello" as EString, "hello" as EString) == false)
    }

    @Test("Not equals different values")
    func testNotEqualsDifferentValues() throws {
        #expect(notEquals(42 as EInt, 43 as EInt) == true)
        #expect(notEquals("hello" as EString, "world" as EString) == true)
    }

    // MARK: - Logical Operations Tests

    @Test("Logical AND both true")
    func testLogicalAndBothTrue() throws {
        let result = try and(true as EBoolean, true as EBoolean)
        #expect(result == true)
    }

    @Test("Logical AND one false")
    func testLogicalAndOneFalse() throws {
        #expect(try and(true as EBoolean, false as EBoolean) == false)
        #expect(try and(false as EBoolean, true as EBoolean) == false)
    }

    @Test("Logical AND both false")
    func testLogicalAndBothFalse() throws {
        let result = try and(false as EBoolean, false as EBoolean)
        #expect(result == false)
    }

    @Test("Logical AND non-boolean throws error")
    func testLogicalAndNonBoolean() throws {
        #expect(throws: OCLError.typeError("Left operand of 'and' must be boolean, got Int")) {
            try and(42 as EInt, true as EBoolean)
        }

        #expect(throws: OCLError.typeError("Right operand of 'and' must be boolean, got String")) {
            try and(true as EBoolean, "hello" as EString)
        }
    }

    @Test("Logical OR both false")
    func testLogicalOrBothFalse() throws {
        let result = try or(false as EBoolean, false as EBoolean)
        #expect(result == false)
    }

    @Test("Logical OR one true")
    func testLogicalOrOneTrue() throws {
        #expect(try or(true as EBoolean, false as EBoolean) == true)
        #expect(try or(false as EBoolean, true as EBoolean) == true)
    }

    @Test("Logical OR both true")
    func testLogicalOrBothTrue() throws {
        let result = try or(true as EBoolean, true as EBoolean)
        #expect(result == true)
    }

    @Test("Logical OR non-boolean throws error")
    func testLogicalOrNonBoolean() throws {
        #expect(throws: OCLError.typeError("Left operand of 'or' must be boolean, got Int")) {
            try or(42 as EInt, true as EBoolean)
        }
    }

    @Test("Logical implies truth table")
    func testLogicalImplies() throws {
        // Truth table for implication: T->T=T, T->F=F, F->T=T, F->F=T
        #expect(try implies(true as EBoolean, true as EBoolean) == true)
        #expect(try implies(true as EBoolean, false as EBoolean) == false)
        #expect(try implies(false as EBoolean, true as EBoolean) == true)
        #expect(try implies(false as EBoolean, false as EBoolean) == true)
    }

    @Test("Logical implies non-boolean throws error")
    func testLogicalImpliesNonBoolean() throws {
        #expect(throws: OCLError.typeError("Left operand of 'implies' must be boolean, got Int")) {
            try implies(42 as EInt, true as EBoolean)
        }
    }

    // MARK: - Edge Cases and Error Handling

    @Test("Type coercion preserves precision")
    func testTypeCoercionPrecision() throws {
        // Test that float->double coercion maintains reasonable precision
        let result = try add(3.14159 as EFloat, 2.71828 as EDouble)
        let expected = 5.85987
        #expect(abs((result as? EDouble ?? 0) - expected) < 0.001)
    }

    @Test("Large number arithmetic")
    func testLargeNumberArithmetic() throws {
        let large1 = Int.max - 1000
        let large2 = 500
        let result = try add(large1 as EInt, large2 as EInt)
        #expect(result as? EInt == large1 + large2)
    }

    @Test("Negative number operations")
    func testNegativeNumbers() throws {
        #expect(try add(-5 as EInt, -3 as EInt) as? EInt == -8)
        #expect(try subtract(-5 as EInt, -3 as EInt) as? EInt == -2)
        #expect(try multiply(-5 as EInt, 3 as EInt) as? EInt == -15)
        #expect(try divide(-12 as EInt, 3 as EInt) as? EInt == -4)
    }

    @Test("Zero handling")
    func testZeroHandling() throws {
        #expect(try add(0 as EInt, 42 as EInt) as? EInt == 42)
        #expect(try multiply(0 as EInt, 42 as EInt) as? EInt == 0)
        #expect(try subtract(42 as EInt, 0 as EInt) as? EInt == 42)

        // Zero division should throw
        #expect(throws: OCLError.divisionByZero) {
            try divide(42 as EInt, 0 as EInt)
        }
    }

    @Test("String comparison edge cases")
    func testStringComparisonEdgeCases() throws {
        #expect(equals("" as EString, "" as EString) == true)
        #expect(try lessThan("" as EString, "a" as EString) == true)
        #expect(try lessThan("A" as EString, "a" as EString) == true)  // ASCII ordering
    }

    // MARK: - Extended EMF Numeric Type Tests

    @Test("Add with EByte types")
    func testAddEByteTypes() throws {
        let result = try add(5 as EByte, 3 as EByte)
        #expect(result as? EByte == 8)
    }

    @Test("Add EByte with EShort promotes to EShort")
    func testAddEByteEShort() throws {
        let result = try add(5 as EByte, 300 as EShort)
        #expect(result as? EShort == 305)
    }

    @Test("Add EInt with ELong promotes to ELong")
    func testAddEIntELong() throws {
        let result = try add(1000 as EInt, 2_000_000_000 as ELong)
        #expect(result as? ELong == 2_000_001_000)
    }

    @Test("Add EBigInteger types")
    func testAddEBigInteger() throws {
        let bigInt1 = EBigInteger("123", radix: 10)!
        let bigInt2 = EBigInteger("456", radix: 10)!
        let result = try add(bigInt1, bigInt2)
        let expected = EBigInteger("579", radix: 10)!
        #expect(result as? EBigInteger == expected)
    }

    @Test("Add EFloat with EBigDecimal promotes to EBigDecimal")
    func testAddEFloatEBigDecimal() throws {
        let result = try add(2.5 as EFloat, EBigDecimal(1.25))
        #expect(result as? EBigDecimal == EBigDecimal(3.75))
    }

    @Test("Subtract with extended types")
    func testSubtractExtendedTypes() throws {
        let result = try subtract(1000 as ELong, 50 as EShort)
        #expect(result as? ELong == 950)
    }

    @Test("Add with basic extended types")
    func testAddBasicExtendedTypes() throws {
        // Test combinations that should work with current implementation
        let result1 = try add(100 as EInt, 200 as EInt)
        #expect(result1 as? EInt == 300)

        let result2 = try add(2.5 as EDouble, 1.5 as EDouble)
        #expect(result2 as? EDouble == 4.0)

        let result3 = try add(1.5 as EFloat, 2.5 as EFloat)
        #expect(result3 as? EFloat == 4.0)
    }

    @Test("Comparison with same types")
    func testComparisonSameTypes() throws {
        // Test comparisons that work with current type support
        #expect(try lessThan(5 as EInt, 10 as EInt) == true)
        #expect(try greaterThan(10.5 as EDouble, 5.2 as EDouble) == true)
        #expect(equals(3.14 as EFloat, 3.14 as EFloat) == true)
    }
}
