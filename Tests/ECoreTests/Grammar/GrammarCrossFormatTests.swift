//
// GrammarCrossFormatTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// One small language, arithmetic expressions with let-bindings, in every notation.
enum ArithmeticFixtures {
    /// The language in ASDL.
    static let asdl = """
        module Arith {
            expr = Num(int value)
                 | Var(identifier name)
                 | BinOp(expr left, op operator, expr right)
                 | Let(identifier name, expr init, expr body)

            op = Add | Sub | Mul | Div
        }
        """

    /// The language as an Xtext grammar.
    static let xtext = """
        grammar org.example.arith.Arith with org.eclipse.xtext.common.Terminals

        generate arith "http://www.example.org/arith"

        Expr: Num | Var | BinOp | Let;
        Num: value=INT;
        Var: name=ID;
        BinOp: '(' left=Expr operator=Op right=Expr ')';
        Let: 'let' name=ID '=' init=Expr 'in' body=Expr;
        enum Op: Add='+' | Sub='-' | Mul='*' | Div='/';
        """

    /// The language as a Langium grammar.
    static let langium = """
        grammar Arith

        entry Expr: Num | Var | BinOp | Let;
        Num: value=INT;
        Var: name=ID;
        BinOp: '(' left=Expr operator=('+' | '-' | '*' | '/') right=Expr ')';
        Let: 'let' name=ID '=' init=Expr 'in' body=Expr;

        hidden terminal WS: /\\s+/;
        terminal ID: /[_a-zA-Z][\\w_]*/;
        terminal INT returns number: /[0-9]+/;
        """

    /// The language as an SDF3 syntax definition, with labelled arguments.
    static let sdf3 = """
        module Arith

        context-free sorts Expr Op
        lexical sorts ID INT

        lexical syntax
          ID  = [a-zA-Z] [a-zA-Z0-9]*
          INT = [0-9]+

        context-free syntax
          Expr.Num   = <<value:INT>>
          Expr.Var   = <<name:ID>>
          Expr.BinOp = <(<left:Expr> <operator:Op> <right:Expr>)>
          Expr.Let   = <let <name:ID> = <init:Expr> in <body:Expr>>
          Op.Add = <+>
          Op.Sub = <->
          Op.Mul = <*>
          Op.Div = </>
        """
}

/// The structure of a language that every notation should agree on.
struct LanguageShape: Equatable, CustomStringConvertible {
    /// For each constructor, its features as `name:kind`, where the kind is
    /// `tree` for a containment of the expression type and `value` otherwise.
    var constructors: [String: [String]]

    /// A readable form for failure messages.
    var description: String {
        constructors.keys.sorted().map { "\($0)(\(constructors[$0]!.joined(separator: ", ")))" }.joined(separator: " ")
    }

    /// Extracts the shape from packages.
    ///
    /// - Parameters:
    ///   - packages: The packages read from one notation.
    ///   - expression: The name of the expression type, compared without regard to case.
    /// - Returns: The shape, or `nil` if there is no expression type.
    static func of(_ packages: [EPackage], expression: String) -> LanguageShape? {
        let classes = packages.flatMap(\.eClassifiers).compactMap { $0 as? EClass }
        guard let root = classes.first(where: { $0.name.lowercased() == expression.lowercased() }) else { return nil }
        var constructors: [String: [String]] = [:]
        for eClass in classes where !eClass.isAbstract && eClass.eSuperTypes.contains(where: { $0.id == root.id }) {
            constructors[eClass.name] = eClass.eAllStructuralFeatures.map { feature in
                if let reference = feature as? EReference, reference.containment, reference.eType.id == root.id {
                    return feature.name + ":tree"
                }
                return feature.name + ":value"
            }
        }
        return LanguageShape(constructors: constructors)
    }
}

@Suite("One language in four notations")
struct GrammarCrossFormatTests {
    /// The shape every notation should produce.
    static let expected = LanguageShape(constructors: [
        "Num": ["value:value"],
        "Var": ["name:value"],
        "BinOp": ["left:tree", "operator:value", "right:tree"],
        "Let": ["name:value", "init:tree", "body:tree"],
    ])

    /// The errors that Ecore validation finds.
    ///
    /// - Parameter packages: The packages.
    /// - Returns: The messages of the errors.
    func validationErrors(_ packages: [EPackage]) -> [String] {
        EcoreValidator().validate(MetamodelIndex(roots: packages)).filter { $0.severity == .error }.map(\.message)
    }

    @Test("ASDL gives the reference shape")
    func asdl() throws {
        let result = ASDLReader.parse(ArithmeticFixtures.asdl)
        #expect(result.diagnostics.isEmpty)
        #expect(validationErrors(result.packages).isEmpty)
        #expect(LanguageShape.of(result.packages, expression: "expr") == Self.expected)
    }

    @Test("Xtext gives the same shape")
    func xtext() throws {
        let result = XtextReader.parse(ArithmeticFixtures.xtext)
        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty)
        #expect(validationErrors(result.packages).isEmpty)
        #expect(LanguageShape.of(result.packages, expression: "Expr") == Self.expected)
    }

    @Test("Langium gives the same shape")
    func langium() throws {
        let result = LangiumReader.parse(ArithmeticFixtures.langium)
        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty)
        #expect(validationErrors(result.packages).isEmpty)
        #expect(LanguageShape.of(result.packages, expression: "Expr") == Self.expected)
    }

    @Test("SDF3 with labelled arguments gives the same shape")
    func sdf3() throws {
        let result = SDF3Reader.parse(ArithmeticFixtures.sdf3, options: .init(useLabels: true))
        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty)
        #expect(validationErrors(result.packages).isEmpty)
        #expect(LanguageShape.of(result.packages, expression: "Expr") == Self.expected)
    }

    @Test("The notations differ in documented ways")
    func documentedDifferences() throws {
        let asdl = ASDLReader.parse(ArithmeticFixtures.asdl).packages
        let xtext = XtextReader.parse(ArithmeticFixtures.xtext).packages
        let langium = LangiumReader.parse(ArithmeticFixtures.langium).packages
        let sdf3 = SDF3Reader.parse(ArithmeticFixtures.sdf3, options: .init(useLabels: true)).packages
        func eClass(_ name: String, _ packages: [EPackage]) -> EClass? {
            packages.flatMap(\.eClassifiers).first { $0.name == name } as? EClass
        }
        func feature(_ owner: String, _ name: String, _ packages: [EPackage]) -> (any EStructuralFeature)? {
            eClass(owner, packages)?.eAllStructuralFeatures.first { $0.name == name }
        }
        func bounds(_ feature: (any EStructuralFeature)?) -> String {
            if let attribute = feature as? EAttribute { return GrammarMetamodelDescription.bounds(attribute.lowerBound, attribute.upperBound) }
            if let reference = feature as? EReference { return GrammarMetamodelDescription.bounds(reference.lowerBound, reference.upperBound) }
            return "?"
        }
        func typeName(_ feature: (any EStructuralFeature)?) -> String {
            (feature as? EAttribute)?.eType.name ?? (feature as? EReference)?.eType.name ?? "?"
        }
        // The expression type is abstract except in Xtext, which never infers abstract classes.
        #expect(eClass("expr", asdl)?.isAbstract == true)
        #expect(eClass("Expr", xtext)?.isAbstract == false)
        #expect(eClass("Expr", langium)?.isAbstract == true)
        #expect(eClass("Expr", sdf3)?.isAbstract == true)
        // ASDL and SDF3 fields are required; Xtext and Langium infer optional features.
        #expect(bounds(feature("Num", "value", asdl)) == "[1..1]")
        #expect(bounds(feature("Num", "value", sdf3)) == "[1..1]")
        #expect(bounds(feature("Num", "value", xtext)) == "[0..1]")
        #expect(bounds(feature("Num", "value", langium)) == "[0..1]")
        // Numbers: EInt in ASDL and Xtext, EDouble (Langium's number) and a lexical data type in SDF3.
        #expect(typeName(feature("Num", "value", asdl)) == "EInt")
        #expect(typeName(feature("Num", "value", xtext)) == "EInt")
        #expect(typeName(feature("Num", "value", langium)) == "EDouble")
        #expect(typeName(feature("Num", "value", sdf3)) == "INT")
        // Operators: an enumeration in ASDL and Xtext, a string in Langium, a sort of constructors in SDF3.
        #expect(typeName(feature("BinOp", "operator", asdl)) == "op")
        #expect(typeName(feature("BinOp", "operator", xtext)) == "Op")
        #expect(typeName(feature("BinOp", "operator", langium)) == "EString")
        #expect(typeName(feature("BinOp", "operator", sdf3)) == "Op")
        #expect(feature("BinOp", "operator", sdf3) is EReference)
    }
}
