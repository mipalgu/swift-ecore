//
// SDF3ArithmeticTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// Tests of the arithmetic language with let bindings that every importer reads.
///
/// The ASDL version of the language is:
///
/// ```
/// module Arith {
///     expr = Num(int value)
///          | Var(identifier name)
///          | BinOp(expr left, op operator, expr right)
///          | Let(identifier name, expr init, expr body)
///     op = Add | Sub | Mul | Div
/// }
/// ```
@Suite("SDF3 arithmetic language")
struct SDF3ArithmeticTests {
    /// The language as an SDF3 definition.
    static let definition = """
        module Arith

        context-free sorts Expr Op

        context-free syntax

          Expr.Num   = <<value:INT>>
          Expr.Var   = <<name:ID>>
          Expr.BinOp = <<left:Expr> <operator:Op> <right:Expr>>
          Expr.Let   = <let <name:ID> = <init:Expr> in <body:Expr>>
          Expr       = <(<Expr>)> {bracket}

          Op.Add = <+>
          Op.Sub = <->
          Op.Mul = <*>
          Op.Div = </>

        lexical sorts ID INT

        lexical syntax

          ID  = [a-zA-Z] [a-zA-Z0-9]*
          INT = [0-9]+
        """

    /// The language as a Stratego signature.
    static let signature = """
        module signatures/Arith-sig

        signature
          sorts Expr Op ID INT
          constructors
            Num   : INT -> Expr
            Var   : ID -> Expr
            BinOp : Expr * Op * Expr -> Expr
            Let   : ID * Expr * Expr -> Expr
            Add   : Op
            Sub   : Op
            Mul   : Op
            Div   : Op
                  : string -> ID
                  : string -> INT
        """

    /// Checks the shape that both versions share.
    ///
    /// - Parameters:
    ///   - result: The parse result.
    ///   - binOp: The expected feature names of `BinOp`.
    ///   - letNames: The expected feature names of `Let`.
    private func checkStructure(_ result: SDF3ParseResult, binOp: [String], letFeatures letNames: [String]) throws {
        #expect(result.errors.isEmpty)
        #expect(result.validationErrors.isEmpty)
        let expr = try #require(result.eClass("Expr"))
        #expect(expr.isAbstract)
        #expect(result.eClass("Op")?.isAbstract == true)
        for name in ["Num", "Var", "BinOp", "Let"] {
            let eClass = try #require(result.eClass(name))
            #expect(!eClass.isAbstract)
            #expect(eClass.superTypeNames == ["Expr"])
        }
        for name in ["Add", "Sub", "Mul", "Div"] {
            #expect(result.eClass(name)?.superTypeNames == ["Op"])
        }
        let binOpClass = try #require(result.eClass("BinOp"))
        #expect(binOpClass.featureNames == binOp)
        #expect(binOpClass.anyReference(binOp[0])?.containment == true)
        #expect(binOpClass.anyReference(binOp[1])?.eType.name == "Op")
        #expect(result.eClass("Let")?.featureNames == letNames)
        #expect(result.package.getEDataType("ID") != nil)
        #expect(result.package.getEDataType("INT") != nil)
        #expect(result.eClass("Num")?.featureTypeNames.first == "INT")
    }

    /// The SDF3 version with labels gives the ASDL field names.
    @Test func definitionWithLabels() throws {
        let result = read(Self.definition, options: SDF3ImportOptions(useLabels: true))
        try checkStructure(result, binOp: ["left", "operator", "right"], letFeatures: ["name", "init", "body"])
        #expect(result.eClass("Num")?.featureNames == ["value"])
    }

    /// The SDF3 version without labels gives positional names.
    @Test func definitionPositional() throws {
        let result = read(Self.definition)
        try checkStructure(result, binOp: ["expr1", "op1", "expr2"], letFeatures: ["id1", "expr1", "expr2"])
    }

    /// The Stratego signature gives the same structure as the positional SDF3 version.
    @Test func signature() throws {
        let result = read(Self.signature)
        try checkStructure(result, binOp: ["expr1", "op1", "expr2"], letFeatures: ["id1", "expr1", "expr2"])
        #expect(Set(result.package.eClassifiers.map(\.name)) == Set(read(Self.definition).package.eClassifiers.map(\.name)))
    }
}
