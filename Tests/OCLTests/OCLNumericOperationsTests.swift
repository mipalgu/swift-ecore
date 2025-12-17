//
// OCLNumericOperationsTests.swift
// OCL
//
//  Created by Rene Hexel on 18/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//

import EMFBase
import Testing

@testable import OCL

@Suite("OCL Numeric Operations")
struct OCLNumericOperationsTests {

    // MARK: - abs() Tests

    @Test("abs returns absolute value for positive integer")
    func testAbsPositiveInt() throws {
        let result = try abs(5 as EInt)
        #expect(result as? EInt == 5)
    }

    @Test("abs returns absolute value for negative integer")
    func testAbsNegativeInt() throws {
        let result = try abs(-7 as EInt)
        #expect(result as? EInt == 7)
    }

    @Test("abs returns absolute value for zero")
    func testAbsZero() throws {
        let result = try abs(0 as EInt)
        #expect(result as? EInt == 0)
    }

    @Test("abs returns absolute value for positive double")
    func testAbsPositiveDouble() throws {
        let result = try abs(3.14 as EDouble)
        #expect(result as? EDouble == 3.14)
    }

    @Test("abs returns absolute value for negative double")
    func testAbsNegativeDouble() throws {
        let result = try abs(-2.71 as EDouble)
        #expect(result as? EDouble == 2.71)
    }

    @Test("abs returns absolute value for float")
    func testAbsFloat() throws {
        let result1 = try abs(-1.5 as EFloat)
        #expect(result1 as? EFloat == 1.5)

        let result2 = try abs(2.5 as EFloat)
        #expect(result2 as? EFloat == 2.5)
    }

    @Test("abs throws error for non-numeric value")
    func testAbsNonNumeric() throws {
        #expect(throws: OCLError.invalidArguments("abs requires a numeric value, got String")) {
            try abs("not a number" as EString)
        }
    }

    // MARK: - floor() Tests

    @Test("floor returns floor for positive double")
    func testFloorPositiveDouble() throws {
        let result = try floor(3.7 as EDouble)
        #expect(result == 3)
    }

    @Test("floor returns floor for negative double")
    func testFloorNegativeDouble() throws {
        let result = try floor(-2.3 as EDouble)
        #expect(result == -3)
    }

    @Test("floor handles exact integer values")
    func testFloorExactInteger() throws {
        let result = try floor(4.0 as EDouble)
        #expect(result == 4)
    }

    @Test("floor works with float input")
    func testFloorFloat() throws {
        let result = try floor(2.9 as EFloat)
        #expect(result == 2)

        let result2 = try floor(-1.3 as EFloat)
        #expect(result2 == -2)
    }

    @Test("floor throws error for non-Real value")
    func testFloorNonReal() throws {
        #expect(throws: OCLError.invalidArguments("floor requires a Real value, got Int")) {
            try floor(5 as EInt)
        }
    }

    // MARK: - round() Tests

    @Test("round handles positive rounding")
    func testRoundPositive() throws {
        let result1 = try round(3.6 as EDouble)
        #expect(result1 == 4)

        let result2 = try round(3.4 as EDouble)
        #expect(result2 == 3)
    }

    @Test("round handles negative rounding")
    func testRoundNegative() throws {
        let result1 = try round(-2.3 as EDouble)
        #expect(result1 == -2)

        let result2 = try round(-2.7 as EDouble)
        #expect(result2 == -3)
    }

    @Test("round handles exact half values")
    func testRoundHalfValues() throws {
        // OCL round: ties go to larger integer
        let result1 = try round(2.5 as EDouble)
        #expect(result1 == 3)

        let result2 = try round(3.5 as EDouble)
        #expect(result2 == 4)
    }

    @Test("round works with float input")
    func testRoundFloat() throws {
        let result = try round(2.7 as EFloat)
        #expect(result == 3)

        let result2 = try round(2.5 as EFloat)
        #expect(result2 == 3)  // OCL rounds ties up

        let result3 = try round(-2.3 as EFloat)
        #expect(result3 == -2)
    }

    @Test("round throws error for non-Real value")
    func testRoundNonReal() throws {
        #expect(throws: OCLError.invalidArguments("round requires a Real value, got Int")) {
            try round(5 as EInt)
        }
    }

    // MARK: - ceiling() Tests

    @Test("ceiling returns ceiling of positive double")
    func testCeilingPositiveDouble() throws {
        let result = try ceiling(3.2 as EDouble)
        #expect(result == 4)
    }

    @Test("ceiling returns ceiling of negative double")
    func testCeilingNegativeDouble() throws {
        let result = try ceiling(-2.7 as EDouble)
        #expect(result == -2)
    }

    @Test("ceiling returns exact integer for whole numbers")
    func testCeilingExactInteger() throws {
        let result = try ceiling(5.0 as EDouble)
        #expect(result == 5)
    }

    @Test("ceiling works with Float values")
    func testCeilingFloat() throws {
        let result = try ceiling(3.1 as EFloat)
        #expect(result == 4)

        let result2 = try ceiling(-1.9 as EFloat)
        #expect(result2 == -1)
    }

    @Test("ceiling throws error for non-Real value")
    func testCeilingNonReal() throws {
        #expect(throws: OCLError.invalidArguments("ceiling requires a Real value, got Int")) {
            try ceiling(5 as EInt)
        }
    }

    // MARK: - power() Tests

    @Test("power computes integer to integer power")
    func testPowerIntegers() throws {
        let result = try power(2 as EInt, 3 as EInt)
        #expect(result as? ELong == 8)
    }

    @Test("power computes real to integer power")
    func testPowerRealToInteger() throws {
        let result = try power(2.5 as EDouble, 2 as EInt)
        #expect(result as? EDouble == 6.25)
    }

    @Test("power computes integer to real power")
    func testPowerIntegerToReal() throws {
        let result = try power(4 as EInt, 0.5 as EDouble)
        #expect(result as? EDouble == 2.0)
    }

    @Test("power computes real to real power")
    func testPowerReals() throws {
        let result = try power(2.0 as EDouble, 3.0 as EDouble)
        #expect(result as? EDouble == 8.0)
    }

    @Test("power handles zero exponent")
    func testPowerZeroExponent() throws {
        let result = try power(5 as EInt, 0 as EInt)
        #expect(result as? ELong == 1)
    }

    @Test("power handles negative integer exponent")
    func testPowerNegativeExponent() throws {
        let result = try power(2 as EInt, -1 as EInt)
        #expect(result as? EDouble == 0.5)
    }

    @Test("power handles small integer types")
    func testPowerSmallTypes() throws {
        let result = try power(2 as EByte, 3 as EByte)
        #expect(result as? EInt == 8)

        let result2 = try power(3 as EShort, 2 as EShort)
        #expect(result2 as? EInt == 9)
    }

    @Test("power throws error for non-numeric values")
    func testPowerNonNumeric() throws {
        #expect(
            throws: OCLError.invalidArguments(
                "power requires numeric arguments, got String and Int")
        ) {
            try power("hello" as EString, 2 as EInt)
        }
    }

    // MARK: - max() Tests

    @Test("max returns maximum of two integers")
    func testMaxIntegers() throws {
        let result = try max(5 as EInt, 3 as EInt)
        #expect(result as? EInt == 5)
    }

    @Test("max returns maximum of two doubles")
    func testMaxDoubles() throws {
        let result = try max(2.5 as EDouble, 3.1 as EDouble)
        #expect(result as? EDouble == 3.1)
    }

    @Test("max handles all type combinations")
    func testMaxTypeCoercion() throws {
        // Int + Double → Double
        let result1 = try max(7 as EInt, 6.5 as EDouble)
        #expect(result1 as? EDouble == 7.0)

        let result2 = try max(6.5 as EDouble, 7 as EInt)
        #expect(result2 as? EDouble == 7.0)

        // Int + Float → Float
        let result3 = try max(5 as EInt, 4.5 as EFloat)
        #expect(result3 as? EFloat == 5.0)

        let result4 = try max(4.5 as EFloat, 5 as EInt)
        #expect(result4 as? EFloat == 5.0)

        // Float + Double → Double
        let result5 = try max(3.5 as EFloat, 4.0 as EDouble)
        #expect(result5 as? EDouble == 4.0)

        let result6 = try max(4.0 as EDouble, 3.5 as EFloat)
        #expect(result6 as? EDouble == 4.0)

        // Float + Float → Float
        let result7 = try max(2.5 as EFloat, 3.0 as EFloat)
        #expect(result7 as? EFloat == 3.0)
    }

    @Test("max handles equal values")
    func testMaxEqualValues() throws {
        let result = try max(4 as EInt, 4 as EInt)
        #expect(result as? EInt == 4)
    }

    @Test("max handles negative values")
    func testMaxNegativeValues() throws {
        let result = try max(-5 as EInt, -3 as EInt)
        #expect(result as? EInt == -3)
    }

    @Test("max throws error for non-numeric values")
    func testMaxNonNumeric() throws {
        #expect(
            throws: OCLError.invalidArguments("max requires numeric values, got String and Int")
        ) {
            try max("not a number" as EString, 5 as EInt)
        }
    }

    // MARK: - min() Tests

    @Test("min returns minimum of two integers")
    func testMinIntegers() throws {
        let result = try min(5 as EInt, 3 as EInt)
        #expect(result as? EInt == 3)
    }

    @Test("min returns minimum of two doubles")
    func testMinDoubles() throws {
        let result = try min(2.5 as EDouble, 3.1 as EDouble)
        #expect(result as? EDouble == 2.5)
    }

    @Test("min handles all type combinations")
    func testMinTypeCoercion() throws {
        // Int + Double → Double
        let result1 = try min(7 as EInt, 6.5 as EDouble)
        #expect(result1 as? EDouble == 6.5)

        let result2 = try min(6.5 as EDouble, 7 as EInt)
        #expect(result2 as? EDouble == 6.5)

        // Int + Float → Float
        let result3 = try min(5 as EInt, 4.5 as EFloat)
        #expect(result3 as? EFloat == 4.5)

        let result4 = try min(4.5 as EFloat, 5 as EInt)
        #expect(result4 as? EFloat == 4.5)

        // Float + Double → Double
        let result5 = try min(3.5 as EFloat, 4.0 as EDouble)
        #expect(result5 as? EDouble == 3.5)

        let result6 = try min(4.0 as EDouble, 3.5 as EFloat)
        #expect(result6 as? EDouble == 3.5)

        // Float + Float → Float
        let result7 = try min(2.5 as EFloat, 3.0 as EFloat)
        #expect(result7 as? EFloat == 2.5)
    }

    @Test("min handles equal values")
    func testMinEqualValues() throws {
        let result = try min(4 as EInt, 4 as EInt)
        #expect(result as? EInt == 4)
    }

    @Test("min handles negative values")
    func testMinNegativeValues() throws {
        let result = try min(-5 as EInt, -3 as EInt)
        #expect(result as? EInt == -5)
    }

    @Test("min throws error for non-numeric values")
    func testMinNonNumeric() throws {
        #expect(
            throws: OCLError.invalidArguments("min requires numeric arguments, got String and Int")
        ) {
            try min("not a number" as EString, 5 as EInt)
        }
    }

    // MARK: - Comprehensive Binary Operation Tests

    @Test("all numeric operations work with all type combinations")
    func testAllTypeCombinations() throws {
        // Test that all operations handle the 9 type combinations correctly
        let intVal = 5 as EInt
        let shortVal = 4 as EShort
        let byteVal = 3 as EByte
        let longVal = 2 as ELong
        let bigInt = 1 as EBigInteger
        let bigDecimal = 1.5 as EBigDecimal
        let floatVal = 2.5 as EFloat
        let doubleVal = 3.5 as EDouble

        // abs with all types
        #expect(try abs(intVal) as? EInt == 5)
        #expect(try abs(doubleVal) as? EDouble == 3.5)
        #expect(try abs(floatVal) as? EFloat == 2.5)
        #expect(try abs(shortVal) as? EShort == 4)
        #expect(try abs(byteVal) as? EByte == 3)
        #expect(try abs(longVal) as? ELong == 2)
        #expect(try abs(bigInt) as? EBigInteger == 1)
        #expect(try abs(bigDecimal) as? EBigDecimal == 1.5)

        // max/min with same types
        #expect(try max(intVal, 3 as EInt) as? EInt == 5)
        #expect(try max(doubleVal, 4.0 as EDouble) as? EDouble == 4.0)
        #expect(try max(floatVal, 1.5 as EFloat) as? EFloat == 2.5)
        #expect(try max(shortVal, 3 as EShort) as? EShort == 4)
        #expect(try max(byteVal, 4 as EByte) as? EByte == 4)
        #expect(try max(longVal, 1 as ELong) as? ELong == 2)
        #expect(try max(bigInt, 0 as EBigInteger) as? EBigInteger == 1)
        #expect(try max(bigDecimal, 1.0 as EBigDecimal) as? EBigDecimal == 1.5)

        #expect(try min(intVal, 3 as EInt) as? EInt == 3)
        #expect(try min(doubleVal, 4.0 as EDouble) as? EDouble == 3.5)
        #expect(try min(floatVal, 1.5 as EFloat) as? EFloat == 1.5)
        #expect(try min(shortVal, 3 as EShort) as? EShort == 3)
        #expect(try min(byteVal, 4 as EByte) as? EByte == 3)
        #expect(try min(longVal, 1 as ELong) as? ELong == 1)
        #expect(try min(bigInt, 2 as EBigInteger) as? EBigInteger == 1)
        #expect(try min(bigDecimal, 2.0 as EBigDecimal) as? EBigDecimal == 1.5)

        // max/min with mixed types - all 6 combinations
        #expect(try max(intVal, doubleVal) as? EDouble == 5.0)
        #expect(try max(doubleVal, intVal) as? EDouble == 5.0)
        #expect(try max(intVal, floatVal) as? EFloat == 5.0)
        #expect(try max(floatVal, intVal) as? EFloat == 5.0)
        #expect(try max(floatVal, doubleVal) as? EDouble == 3.5)
        #expect(try max(doubleVal, floatVal) as? EDouble == 3.5)

        #expect(try min(intVal, doubleVal) as? EDouble == 3.5)
        #expect(try min(doubleVal, intVal) as? EDouble == 3.5)
        #expect(try min(intVal, floatVal) as? EFloat == 2.5)
        #expect(try min(floatVal, intVal) as? EFloat == 2.5)
        #expect(try min(floatVal, doubleVal) as? EDouble == 2.5)
        #expect(try min(doubleVal, floatVal) as? EDouble == 2.5)

        // Additional mixed combinations including Short, Byte, Long, BigInteger, BigDecimal
        // Short with Int/Float/Double
        #expect(try max(shortVal, intVal) as? EInt == 5)
        #expect(try min(shortVal, intVal) as? EInt == 4)
        #expect(try max(shortVal, floatVal) as? EFloat == 4.0)
        #expect(try min(shortVal, floatVal) as? EFloat == 2.5)
        #expect(try max(shortVal, doubleVal) as? EDouble == 4.0)
        #expect(try min(shortVal, doubleVal) as? EDouble == 3.5)

        // Byte with Int/Float/Double
        #expect(try max(byteVal, intVal) as? EInt == 5)
        #expect(try min(byteVal, intVal) as? EInt == 3)
        #expect(try max(byteVal, floatVal) as? EFloat == 3.0)
        #expect(try min(byteVal, floatVal) as? EFloat == 2.5)
        #expect(try max(byteVal, doubleVal) as? EDouble == 3.5)
        #expect(try min(byteVal, doubleVal) as? EDouble == 3.0)

        // Long with Int/Float/Double
        #expect(try max(longVal, intVal) as? EInt == 5)
        #expect(try min(longVal, intVal) as? EInt == 2)
        #expect(try max(longVal, floatVal) as? EFloat == 2.5)
        #expect(try min(longVal, floatVal) as? EFloat == 2.0)
        #expect(try max(longVal, doubleVal) as? EDouble == 3.5)
        #expect(try min(longVal, doubleVal) as? EDouble == 2.0)

        // BigInteger with Int/Float/Double
        #expect(try max(bigInt, intVal) as? EInt == 5)
        #expect(try min(bigInt, intVal) as? EInt == 1)
        #expect(try max(bigInt, floatVal) as? EFloat == 2.5)
        #expect(try min(bigInt, floatVal) as? EFloat == 1.0)
        #expect(try max(bigInt, doubleVal) as? EDouble == 3.5)
        #expect(try min(bigInt, doubleVal) as? EDouble == 1.0)

        // BigDecimal with Float/Double
        #expect(try max(bigDecimal, floatVal) as? EBigDecimal == 2.5)
        #expect(try min(bigDecimal, floatVal) as? EBigDecimal == 1.5)
        #expect(try max(bigDecimal, doubleVal) as? EBigDecimal == 3.5)
        #expect(try min(bigDecimal, doubleVal) as? EBigDecimal == 1.5)

        // Exhaustive pairwise combinations for max/min across all declared numeric types
        // Define an array of labeled values for clarity
        // Pairs: (Int, Short, Byte, Long, BigInteger, BigDecimal, Float, Double)

        // Int with others
        #expect(try max(intVal, shortVal) as? EInt == 5)
        #expect(try min(intVal, shortVal) as? EInt == 4)
        #expect(try max(intVal, byteVal) as? EInt == 5)
        #expect(try min(intVal, byteVal) as? EInt == 3)
        #expect(try max(intVal, longVal) as? EInt == 5)
        #expect(try min(intVal, longVal) as? EInt == 2)
        #expect(try max(intVal, bigInt) as? EInt == 5)
        #expect(try min(intVal, bigInt) as? EInt == 1)
        #expect(try max(intVal, bigDecimal) as? EBigDecimal == 5.0)
        #expect(try min(intVal, bigDecimal) as? EBigDecimal == 1.5)

        // Short with others (excluding those covered above with Int)
        #expect(try max(shortVal, byteVal) as? EShort == 4)
        #expect(try min(shortVal, byteVal) as? EShort == 3)
        #expect(try max(shortVal, longVal) as? ELong == 4)
        #expect(try min(shortVal, longVal) as? ELong == 2)
        #expect(try max(shortVal, bigInt) as? EBigInteger == 4)
        #expect(try min(shortVal, bigInt) as? EBigInteger == 1)
        #expect(try max(shortVal, bigDecimal) as? EBigDecimal == 4.0)
        #expect(try min(shortVal, bigDecimal) as? EBigDecimal == 1.5)

        // Byte with others
        #expect(try max(byteVal, longVal) as? ELong == 3)
        #expect(try min(byteVal, longVal) as? ELong == 2)
        #expect(try max(byteVal, bigInt) as? EBigInteger == 3)
        #expect(try min(byteVal, bigInt) as? EBigInteger == 1)
        #expect(try max(byteVal, bigDecimal) as? EBigDecimal == 3.0)
        #expect(try min(byteVal, bigDecimal) as? EBigDecimal == 1.5)

        // Long with others
        #expect(try max(longVal, bigInt) as? EBigInteger == 2)
        #expect(try min(longVal, bigInt) as? EBigInteger == 1)
        #expect(try max(longVal, bigDecimal) as? EBigDecimal == 2.0)
        #expect(try min(longVal, bigDecimal) as? EBigDecimal == 1.5)

        // BigInteger with BigDecimal
        #expect(try max(bigInt, bigDecimal) as? EBigDecimal == 1.5)
        #expect(try min(bigInt, bigDecimal) as? EBigDecimal == 1.0)

        // Float/Double with BigDecimal to ensure coverage of both orders
        #expect(try max(floatVal, bigDecimal) as? EBigDecimal == 2.5)
        #expect(try min(floatVal, bigDecimal) as? EBigDecimal == 1.5)
        #expect(try max(doubleVal, bigDecimal) as? EBigDecimal == 3.5)
        #expect(try min(doubleVal, bigDecimal) as? EBigDecimal == 1.5)

        // Float/Double with integer family (completed for both orders)
        #expect(try max(floatVal, shortVal) as? EFloat == 4.0)
        #expect(try min(floatVal, shortVal) as? EFloat == 2.5)
        #expect(try max(floatVal, byteVal) as? EFloat == 3.0)
        #expect(try min(floatVal, byteVal) as? EFloat == 2.5)
        #expect(try max(floatVal, longVal) as? EFloat == 2.5)
        #expect(try min(floatVal, longVal) as? EFloat == 2.0)
        #expect(try max(floatVal, bigInt) as? EFloat == 2.5)
        #expect(try min(floatVal, bigInt) as? EFloat == 1.0)

        #expect(try max(doubleVal, shortVal) as? EDouble == 4.0)
        #expect(try min(doubleVal, shortVal) as? EDouble == 3.5)
        #expect(try max(doubleVal, byteVal) as? EDouble == 3.5)
        #expect(try min(doubleVal, byteVal) as? EDouble == 3.0)
        #expect(try max(doubleVal, longVal) as? EDouble == 3.5)
        #expect(try min(doubleVal, longVal) as? EDouble == 2.0)
        #expect(try max(doubleVal, bigInt) as? EDouble == 3.5)
        #expect(try min(doubleVal, bigInt) as? EDouble == 1.0)
    }

    // MARK: - Edge Cases and Integration Tests

    @Test("numeric operations handle very large numbers")
    func testLargeNumbers() throws {
        let largeInt = Int.max
        let result1 = try abs(largeInt as EInt)
        #expect(result1 as? EInt == largeInt)

        let largeDouble = Double.greatestFiniteMagnitude / 2
        let result2 = try max(largeDouble as EDouble, 100.0 as EDouble)
        #expect(result2 as? EDouble == largeDouble)

        // Test with Float
        let largeFloat = Float.greatestFiniteMagnitude / 2
        let result3 = try max(largeFloat as EFloat, 100.0 as EFloat)
        #expect(result3 as? EFloat == largeFloat)
    }

    @Test("numeric operations handle very small numbers")
    func testSmallNumbers() throws {
        let smallDouble = Double.leastNormalMagnitude
        let result1 = try abs(smallDouble as EDouble)
        #expect(result1 as? EDouble == smallDouble)

        let result2 = try min(smallDouble as EDouble, 1.0 as EDouble)
        #expect(result2 as? EDouble == smallDouble)

        // Test with Float
        let smallFloat = Float.leastNormalMagnitude
        let result3 = try abs(smallFloat as EFloat)
        #expect(result3 as? EFloat == smallFloat)

        let result4 = try min(smallFloat as EFloat, 1.0 as EFloat)
        #expect(result4 as? EFloat == smallFloat)
    }

    @Test("numeric operations preserve precision")
    func testPrecisionPreservation() throws {
        let preciseValue = 1.2345678901234567 as EDouble
        let result1 = try abs(preciseValue)
        #expect(result1 as? EDouble == preciseValue)

        let result2 = try max(preciseValue, 0.0 as EDouble)
        #expect(result2 as? EDouble == preciseValue)

        // Test with Float precision
        let preciseFloat = 1.234567 as EFloat  // Float has less precision
        let result3 = try abs(preciseFloat)
        #expect(result3 as? EFloat == preciseFloat)

        let result4 = try max(preciseFloat, 0.0 as EFloat)
        #expect(result4 as? EFloat == preciseFloat)
    }

    @Test("chained numeric operations work correctly")
    func testChainedOperations() throws {
        // abs(min(-5, -3)) should equal 5 (min(-5, -3) = -5, abs(-5) = 5)
        let minResult = try min(-5 as EInt, -3 as EInt)
        let absResult = try abs(minResult)
        #expect(absResult as? EInt == 5)

        // max(floor(3.7), round(2.3)) should equal 3
        let floorResult = try floor(3.7 as EDouble)
        let roundResult = try round(2.3 as EDouble)
        let maxResult = try max(floorResult, roundResult)
        #expect(maxResult as? EInt == 3)
    }
}
