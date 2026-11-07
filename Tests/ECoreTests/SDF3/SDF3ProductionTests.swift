//
// SDF3ProductionTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// Tests of the mapping of SDF3 sorts and productions to classifiers.
@Suite("SDF3 productions")
struct SDF3ProductionTests {
    /// A module with angle-bracket templates.
    static let angleTemplates = """
        module lang/Shapes

        context-free sorts Shape Point

        context-free syntax

          Shape.Circle = <circle <Point> radius <NAT>>
          Shape.Polygon = <
            polygon {
              <{Point ","}+>
            }
          >
          Shape.Group = <group <Shape*> label <LABEL?>>
          Point.Point = <(<NAT>, <NAT>)>

        lexical sorts NAT LABEL
        lexical syntax
          NAT = [0-9]+
          LABEL = [a-z]+
        """

    /// The module name, sorts and constructors become a package, abstract and concrete classes.
    @Test func packageAndClasses() throws {
        let result = read(Self.angleTemplates)
        #expect(result.errors.isEmpty)
        #expect(result.packages.count == 1)
        #expect(result.package.name == "Shapes")
        #expect(result.package.nsURI == "urn:sdf3:Shapes")
        #expect(result.package.nsPrefix == "shapes")
        let shape = try #require(result.eClass("Shape"))
        #expect(shape.isAbstract)
        let circle = try #require(result.eClass("Circle"))
        #expect(!circle.isAbstract)
        #expect(circle.superTypeNames == ["Shape"])
        #expect(result.package.eClassifiers.map(\.name) == [
            "Shape", "Circle", "Polygon", "Group", "Point", "PointPoint", "NAT", "LABEL",
        ])
        #expect(result.validationErrors.isEmpty)
    }

    /// Placeholders become features with positional names and SDF3 multiplicities.
    @Test func placeholdersAndMultiplicities() throws {
        let result = read(Self.angleTemplates)
        let circle = try #require(result.eClass("Circle"))
        #expect(circle.featureNames == ["point1", "nat1"])
        let point = try #require(circle.anyReference("point1"))
        #expect(point.containment)
        #expect(point.lowerBound == 1 && point.upperBound == 1)
        let radius = try #require(circle.anyAttribute("nat1"))
        #expect(radius.eType.name == "NAT")
        let polygon = try #require(result.eClass("Polygon")?.anyReference("point1"))
        #expect(polygon.lowerBound == 1 && polygon.upperBound == -1)
        let group = try #require(result.eClass("Group"))
        #expect(group.anyReference("shape1")?.lowerBound == 0)
        #expect(group.anyReference("shape1")?.upperBound == -1)
        #expect(group.anyAttribute("label1")?.lowerBound == 0)
        #expect(group.anyAttribute("label1")?.upperBound == 1)
        let pointPoint = try #require(result.eClass("PointPoint"))
        #expect(pointPoint.featureNames == ["nat1", "nat2"])
    }

    /// Lexical sorts become string data types, or EString when the option is off.
    @Test func lexicalSorts() throws {
        let result = read(Self.angleTemplates)
        let nat = try #require(result.package.getEDataType("NAT"))
        #expect(nat.instanceClassName == "java.lang.String")
        let plain = read(Self.angleTemplates, options: SDF3ImportOptions(lexicalSortsAsDataTypes: false))
        #expect(plain.package.getEDataType("NAT") == nil)
        #expect(plain.eClass("Circle")?.anyAttribute("nat1")?.eType.name == EcoreDataType.eString.rawValue)
        #expect(plain.validationErrors.isEmpty)
    }

    /// Square-bracket templates read placeholders in square brackets.
    @Test func squareTemplates() throws {
        let result = read("""
            module Compare
            context-free syntax
              Exp.Lt = [[Exp] < [Exp]]
              Exp.Tag = [<[ID]>]
              Exp.Escaped = [a \\[ [Exp] \\] b]
            lexical syntax
              ID = [a-z]+
            """)
        #expect(result.errors.isEmpty)
        #expect(result.eClass("Lt")?.featureNames == ["exp1", "exp2"])
        #expect(result.eClass("Tag")?.featureNames == ["id1"])
        #expect(result.eClass("Escaped")?.featureNames == ["exp1"])
    }

    /// Plain productions drop literals and keep sorts in order.
    @Test func plainProductions() throws {
        let result = read("""
            module Plain
            context-free syntax
              Exp.Add = Exp "+" Exp {left}
              Exp.Call = ID "(" {Exp ","}* ")"
              Exp.True = "true"
              Exp.Var = ID
            lexical syntax
              ID = [a-z]+
            """)
        #expect(result.errors.isEmpty)
        #expect(result.eClass("Add")?.featureNames == ["exp1", "exp2"])
        #expect(result.eClass("Call")?.featureNames == ["id1", "exp1"])
        #expect(result.eClass("Call")?.anyReference("exp1")?.upperBound == -1)
        #expect(result.eClass("True")?.featureNames == [])
        #expect(result.eClass("Var")?.anyAttribute("id1")?.lowerBound == 1)
        #expect(result.validationErrors.isEmpty)
    }

    /// Labels name features only when the option asks for it.
    @Test func labels() throws {
        let source = """
            module Labelled
            context-free syntax
              Exp.Sub = <<lhs:Exp> - <rhs:Exp>>
              Exp.Neg = "-" operand:Exp
              Exp.Pair = <(<first:Exp>, <Exp>)>
            """
        let positional = read(source)
        #expect(positional.eClass("Sub")?.featureNames == ["exp1", "exp2"])
        let labelled = read(source, options: SDF3ImportOptions(useLabels: true))
        #expect(labelled.eClass("Sub")?.featureNames == ["lhs", "rhs"])
        #expect(labelled.eClass("Neg")?.featureNames == ["operand"])
        #expect(labelled.eClass("Pair")?.featureNames == ["first", "exp1"])
    }

    /// Context-free injections make subclasses; lexical injections are wrapped.
    @Test func injections() throws {
        let result = read("""
            module Inject
            context-free sorts Exp Literal
            context-free syntax
              Exp = Literal
              Exp = INT
              Exp = <(<Exp>)> {bracket}
              Literal.Bool = "true"
            lexical syntax
              INT = [0-9]+
            """)
        #expect(result.errors.isEmpty)
        #expect(result.eClass("Literal")?.superTypeNames == ["Exp"])
        let wrapper = try #require(result.eClass("ExpINT"))
        #expect(wrapper.superTypeNames == ["Exp"])
        #expect(wrapper.anyAttribute("value")?.eType.name == "INT")
        #expect(wrapper.anyAttribute("value")?.lowerBound == 1)
        #expect(result.diagnostics(.lexicalInjection).count == 1)
        #expect(result.diagnostics(.lexicalInjection).first?.severity == .information)
        #expect(result.validationErrors.isEmpty)
    }

    /// Bracket and reject productions define nothing; `cons` attributes name constructors.
    @Test func attributes() throws {
        let result = read("""
            module Attributes
            context-free syntax
              Exp = "(" Exp ")" {bracket}
              Exp = "if" {reject}
              Exp = Exp "*" Exp {left, cons("Mul")}
            """)
        #expect(result.errors.isEmpty)
        #expect(result.eClass("Mul")?.featureNames == ["exp1", "exp2"])
        #expect(result.package.eClassifiers.map(\.name) == ["Exp", "Mul"])
    }

    /// Kernel suffixes, hyphenated names and layout are normalised.
    @Test func sortNames() throws {
        let result = read("""
            module Kernel
            syntax
              Stat-CF.Print = "print" STRING-CHAR-LEX LAYOUT-CF Exp-CF
              LAYOUT-CF = LAYOUT-LEX
            lexical syntax
              STRING-CHAR = [a-z]
            context-free sorts Exp
            """)
        #expect(result.errors.isEmpty)
        #expect(result.eClass("Stat")?.isAbstract == true)
        #expect(result.package.getEDataType("STRING_CHAR") != nil)
        let print = try #require(result.eClass("Print"))
        #expect(print.featureNames.count == 2)
        #expect(print.featureTypeNames.first == "STRING_CHAR")
        #expect(print.anyReference("exp1") != nil)
        #expect(result.package.getClassifier("LAYOUT") == nil)
        #expect(result.validationErrors.isEmpty)
    }

    /// Undefined sorts are reported and guessed from their spelling.
    @Test func undefinedSorts() throws {
        let result = read("""
            module Uses
            imports Common
            context-free syntax
              Stat.Assign = <<ID> := <Expr>>
            """)
        let undefined = result.diagnostics(.undefinedSort)
        #expect(undefined.map(\.severity) == [.warning, .warning])
        #expect(undefined.first?.range?.start.line == 4)
        #expect(result.package.getEDataType("ID") != nil)
        #expect(result.eClass("Expr")?.isAbstract == true)
        #expect(result.validationErrors.isEmpty)
    }

    /// Plain `sorts` declarations give way to lexical definitions.
    @Test func plainSortsDeclaration() throws {
        let result = read("""
            module Strings
            sorts StrConst Exp
            lexical syntax
              StrConst = "\\"" StrChar* "\\""
              StrChar = ~[\\"\\n]
            context-free syntax
              Exp.String = StrConst
            """)
        #expect(result.errors.isEmpty)
        #expect(result.package.getEDataType("StrConst") != nil)
        #expect(result.package.getEDataType("StrChar") != nil)
        #expect(result.eClass("String")?.anyAttribute("strConst1") != nil)
        #expect(result.diagnostics(.sortKindConflict).isEmpty)
    }

    /// A sort with lexical and context-free definitions is context-free, with a warning.
    @Test func sortKindConflict() throws {
        let result = read("""
            module Conflict
            lexical sorts Name
            context-free syntax
              Name.Simple = ID
            """)
        #expect(result.diagnostics(.sortKindConflict).count == 1)
        #expect(result.eClass("Name")?.isAbstract == true)
    }

    /// Constructors that clash with sorts or with other constructors are renamed.
    @Test func constructorClashes() throws {
        let result = read("""
            module Clash
            context-free syntax
              Decls.Decls = <decls <Decl*>>
              Decl.Var = <var <ID>>
              Type.Var = <tvar <ID>>
              Decl.Var = <variable <ID>>
              Exp.Add = <<Exp> + <Exp>>
              Exp.Add = <add(<Exp>, <Exp>, <Exp>)>
            lexical syntax
              ID = [a-z]+
            """)
        let renamed = result.diagnostics(.constructorRenamed)
        #expect(renamed.count == 3)
        #expect(result.eClass("DeclsDecls")?.superTypeNames == ["Decls"])
        #expect(result.eClass("Var")?.superTypeNames == ["Decl"])
        #expect(result.eClass("VarType")?.superTypeNames == ["Type"])
        #expect(result.eClass("AddExp")?.featureNames == ["exp1", "exp2", "exp3"])
        #expect(result.package.eClassifiers.filter { $0.name.hasPrefix("Var") }.count == 2)
        #expect(result.validationErrors.isEmpty)
    }

    /// Priorities, restrictions, template options and start symbols are skipped.
    @Test func skippedSections() throws {
        let result = read("""
            module Skips
            context-free start-symbols Exp
            context-free syntax
              Exp.Add = <<Exp> + <Exp>> {left}
              Exp.Mul = <<Exp> * <Exp>> {left}
            context-free priorities
              Exp.Mul > Exp.Add,
              {left: Exp.Add Exp.Mul}
            lexical restrictions
              ID -/- [a-zA-Z0-9\\_]
            context-free restrictions
              LAYOUT? -/- [\\/].[\\/]
            template options
              ID = keyword {reject}
              keyword -/- [a-zA-Z0-9]
            lexical syntax
              ID = [a-z]+
            """)
        #expect(result.errors.isEmpty)
        #expect(result.package.eClassifiers.map(\.name) == ["Exp", "Add", "Mul", "ID"])
    }

    /// Options give the package name and namespace when the source has none.
    @Test func namespaceOptions() throws {
        let unnamed = SDF3Reader.parse("context-free syntax\n  Exp.Zero = \"0\"", sourceName: "dir/numbers.sdf3")
        #expect(unnamed.package.name == "numbers")
        let options = SDF3ImportOptions(packageName: "custom", nsURI: "http://example.org/custom", nsPrefix: "cu")
        let named = SDF3Reader.parse("context-free syntax\n  Exp.Zero = \"0\"", options: options)
        #expect(named.package.name == "custom")
        #expect(named.package.nsURI == "http://example.org/custom")
        #expect(named.package.nsPrefix == "cu")
        let declared = SDF3Reader.parse("module a/b/declared\ncontext-free syntax\n  Exp.Zero = \"0\"", options: options)
        #expect(declared.package.name == "declared")
    }

    /// Repeated productions of a constructor with the same arity define it once.
    @Test func repeatedConstructor() throws {
        let result = read("""
            module Repeat
            context-free syntax
              Exp.Seq = <(<{Exp ";"}*>)>
              Exp.Seq = <begin <{Exp ";"}*> end>
            """)
        #expect(result.diagnostics.isEmpty)
        #expect(result.package.eClassifiers.map(\.name) == ["Exp", "Seq"])
    }

    /// Every assembly problem has a diagnostic code of its own.
    @Test func diagnosticCodesCoverAssemblyProblems() {
        for problem in AssemblyProblem.allCases {
            #expect(SDF3DiagnosticCode(rawValue: "sdf3." + problem.rawValue) != nil)
        }
        for code in SDF3DiagnosticCode.allCases { #expect(code.rawValue.hasPrefix("sdf3.")) }
    }
}
