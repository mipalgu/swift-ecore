//
// LangiumInferenceTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// The terminals that most fixtures share.
private let terminals = """

    hidden terminal WS: /\\s+/;
    terminal ID: /[_a-zA-Z][\\w_]*/;
    terminal NUMBER returns number: /[0-9]+(\\.[0-9]+)?/;
    terminal STRING: /"[^"]*"/;
    """

/// Tests of Langium type inference and declared types.
@Suite("Langium type inference and declared types")
struct LangiumInferenceTests {
    /// The arithmetic language with let bindings, with inferred types.
    static let arithmetic = """
        grammar Arith

        entry Expr: Let | Addition;
        Let: 'let' name=ID '=' init=Expr 'in' body=Expr;
        Addition infers Expr: Multiplication ({infer BinOp.left=current} operator=('+' | '-') right=Multiplication)*;
        Multiplication infers Expr: Primary ({infer BinOp.left=current} operator=('*' | '/') right=Primary)*;
        Primary infers Expr: {infer Num} value=NUMBER | {infer Var} name=ID | '(' Expr ')';
        """ + terminals

    /// The arithmetic language with declared types.
    static let declaredArithmetic = """
        grammar Arith

        type Expr = Let | BinOp | Num | Var;
        interface Let { name: string; init: Expr; body: Expr }
        interface BinOp { left: Expr; operator: Op; right: Expr }
        type Op = 'Add' | 'Sub' | 'Mul' | 'Div';
        interface Num { value: number }
        interface Var { name: string }

        entry Expression returns Expr: Let | Addition;
        Let returns Let: 'let' name=ID '=' init=Expression 'in' body=Expression;
        Addition returns Expr: Multiplication ({BinOp.left=current} operator=AddOp right=Multiplication)*;
        Multiplication returns Expr: Primary ({BinOp.left=current} operator=MulOp right=Primary)*;
        Primary returns Expr: {Num} value=NUMBER | {Var} name=ID | '(' Expression ')';
        AddOp returns string: 'Add' | 'Sub';
        MulOp returns string: 'Mul' | 'Div';
        """ + terminals

    /// Checks that the inferred arithmetic language yields an abstract Expr with four concrete subclasses.
    @Test("The inferred arithmetic language yields an abstract Expr with four concrete subclasses")
    func arithmetic() throws {
        let result = LangiumReader.parse(Self.arithmetic, sourceName: "arith.langium")
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics)")
        let package = try #require(result.packages.first)
        #expect(package.name == "Arith" && package.nsURI == "urn:langium:Arith" && package.nsPrefix == "arith")
        #expect(package.eClassifiers.map(\.name) == ["Expr", "Let", "BinOp", "Num", "Var"])
        let expr = try #require(package.getEClass("Expr"))
        #expect(expr.isAbstract)
        for name in ["Let", "BinOp", "Num", "Var"] {
            let eClass = package.getEClass(name)
            #expect(eClass?.isAbstract == false, "\(name)")
            #expect(LangiumInspect.superTypeNames(eClass) == ["Expr"], "\(name)")
        }
        let binOp = package.getEClass("BinOp")
        #expect(LangiumInspect.featureNames(binOp) == ["left", "operator", "right"])
        #expect(LangiumInspect.attribute("operator", of: binOp)?.eType.name == "EString")
        #expect(LangiumInspect.reference("right", of: binOp)?.eType.name == "Expr")
        #expect(LangiumInspect.attribute("value", of: package.getEClass("Num"))?.eType.name == "EDouble")
        #expect(LangiumInspect.featureNames(package.getEClass("Let")) == ["name", "init", "body"])
        #expect(LangiumInspect.validationErrors(result.packages).isEmpty)
    }

    /// Checks that the declared arithmetic language keeps its declared structure, also in strict mode.
    @Test("The declared arithmetic language keeps its declared structure, also in strict mode")
    func declaredArithmetic() throws {
        for mode in LangiumTypeMode.allCases {
            let result = LangiumReader.parse(Self.declaredArithmetic, options: LangiumImportOptions(typeMode: mode))
            #expect(result.diagnostics.isEmpty, "\(mode): \(result.diagnostics)")
            let package = try #require(result.packages.first)
            #expect(package.eClassifiers.map(\.name) == ["Expr", "Let", "BinOp", "Op", "Num", "Var"])
            #expect(package.getEClass("Expr")?.isAbstract == true)
            #expect(LangiumInspect.superTypeNames(package.getEClass("Num")) == ["Expr"])
            let binOp = package.getEClass("BinOp")
            #expect(LangiumInspect.attribute("operator", of: binOp)?.eType.name == "Op")
            #expect(LangiumInspect.reference("left", of: binOp)?.lowerBound == 1)
            #expect(package.getEEnum("Op")?.literals.map(\.name) == ["Add", "Sub", "Mul", "Div"])
            #expect(LangiumInspect.validationErrors(result.packages).isEmpty)
        }
    }

    /// Checks that strict mode rejects inferred types.
    @Test("Strict mode rejects inferred types")
    func strictMode() throws {
        let result = LangiumReader.parse(Self.arithmetic, options: LangiumImportOptions(typeMode: .strict))
        let errors = result.diagnostics.filter { $0.code == LangiumDiagnosticCode.inferredTypeNotAllowed.rawValue }
        #expect(errors.count >= 5)
        #expect(errors.first?.range?.start.line == 3 && errors.first?.range?.start.column == 7)
        #expect(result.packages.first?.eClassifiers.isEmpty == true)
    }

    /// Checks that interface properties map to bounds, containment, references and defaults.
    @Test("Interface properties map to bounds, containment, references and defaults")
    func interfaces() throws {
        let result = LangiumReader.parse("""
            grammar Shapes
            interface Named { name: string }
            interface Shape extends Named, Tagged {
                label?: string;
                sides: number = 3
                visible: boolean = true;
                parts: Shape[];
                parent?: @Shape;
                peers: @Shape+;
                friends: @Shape[];
                kind: 'circle' | 'square';
                size: bigint; created?: Date
                owner: Circle | Square
                misc: Circle | Named
            }
            interface Tagged { tags: string[] }
            interface Circle extends Shape {}
            interface Square extends Shape {}
            """)
        let package = try #require(result.packages.first)
        let shape = try #require(package.getEClass("Shape"))
        #expect(LangiumInspect.superTypeNames(shape) == ["Named", "Tagged"])
        #expect(LangiumInspect.attribute("label", of: shape)?.lowerBound == 0)
        let sides = try #require(LangiumInspect.attribute("sides", of: shape))
        #expect(sides.lowerBound == 1 && sides.eType.name == "EDouble" && sides.defaultValueLiteral == "3")
        #expect(LangiumInspect.attribute("visible", of: shape)?.defaultValueLiteral == "true")
        let parts = try #require(LangiumInspect.reference("parts", of: shape))
        #expect(parts.containment && parts.upperBound == -1 && parts.lowerBound == 0)
        let parent = try #require(LangiumInspect.reference("parent", of: shape))
        #expect(!parent.containment && parent.upperBound == 1)
        #expect(LangiumInspect.reference("peers", of: shape)?.upperBound == -1)
        #expect(LangiumInspect.reference("peers", of: shape)?.containment == false)
        #expect(LangiumInspect.reference("friends", of: shape)?.upperBound == -1)
        #expect(LangiumInspect.attribute("kind", of: shape)?.eType.name == "EString")
        #expect(LangiumInspect.attribute("size", of: shape)?.eType.name == "EBigInteger")
        #expect(LangiumInspect.attribute("created", of: shape)?.eType.name == "EDate")
        #expect(LangiumInspect.reference("owner", of: shape)?.eType.name == "Shape")
        #expect(LangiumInspect.reference("misc", of: shape)?.eType.name == "Named")
        #expect(LangiumInspect.attribute("tags", of: package.getEClass("Tagged"))?.upperBound == -1)
        #expect(result.diagnostics.map(\.code) == [LangiumDiagnosticCode.approximation.rawValue])
        #expect(LangiumInspect.validationErrors(result.packages).isEmpty)
    }

    /// Checks that declared types become abstract unions, enumerations or data types.
    @Test("Declared types become abstract unions, enumerations or data types")
    func typeDeclarations() throws {
        let result = LangiumReader.parse("""
            grammar Kinds
            interface A {}
            interface B {}
            type AB = A | B;
            type Colour = 'red' | 'green';
            type Operator = '+' | '-';
            type Name = string;
            type Count = number;
            type Mixed = A | string;
            """)
        let package = try #require(result.packages.first)
        #expect(package.getEClass("AB")?.isAbstract == true)
        #expect(LangiumInspect.superTypeNames(package.getEClass("A")) == ["AB"])
        #expect(package.getEEnum("Colour")?.literals.map(\.name) == ["red", "green"])
        #expect(package.getEDataType("Operator")?.instanceClassName == "java.lang.String")
        #expect(package.getEDataType("Name")?.instanceClassName == "java.lang.String")
        #expect(package.getEDataType("Count")?.instanceClassName == "java.lang.Double")
        #expect(package.getEDataType("Mixed")?.instanceClassName == "java.lang.Object")
        #expect(result.diagnostics.map(\.code) == [LangiumDiagnosticCode.approximation.rawValue])
        #expect(LangiumInspect.validationErrors(result.packages).isEmpty)
    }

    /// Checks that rules returning declared types add no features and warn about undeclared properties.
    @Test("Rules returning declared types add no features and warn about undeclared properties")
    func declaredReturnTypes() throws {
        let result = LangiumReader.parse("""
            grammar People
            interface Person { name: string }
            entry Model: people+=Person*;
            Person returns Person: 'person' name=ID age=NUMBER;
            """ + terminals)
        let package = try #require(result.packages.first)
        #expect(LangiumInspect.featureNames(package.getEClass("Person")) == ["name"])
        let warnings = result.diagnostics.filter { $0.code == LangiumDiagnosticCode.undeclaredProperty.rawValue }
        #expect(warnings.count == 1)
        #expect(warnings.first?.range?.start.line == 4 && warnings.first?.range?.start.column == 41)
        #expect(LangiumInspect.reference("people", of: package.getEClass("Model"))?.eType.name == "Person")
    }

    /// Checks that fragments are inlined into the rules that call them.
    @Test("Fragments are inlined into the rules that call them")
    func fragments() throws {
        let result = LangiumReader.parse("""
            grammar Frag
            entry Model: items+=Item*;
            Item: 'item' Named Typed?;
            fragment Named: name=ID;
            fragment Typed: ':' type=ID;
            """ + terminals)
        let package = try #require(result.packages.first)
        #expect(package.eClassifiers.map(\.name) == ["Model", "Item"])
        #expect(LangiumInspect.featureNames(package.getEClass("Item")) == ["name", "type"])
    }

    /// Checks that cross-references of all three spellings are non-containment references.
    @Test("Cross-references of all three spellings are non-containment references")
    func crossReferences() throws {
        let result = LangiumReader.parse("""
            grammar Refs
            entry Model: (people+=Person | greetings+=Greeting)*;
            Person: 'person' name=ID;
            Greeting: 'hello' person=[Person:ID] others+=[Person] many=[+Person:ID] old=[Person|ID];
            """ + terminals)
        let greeting = result.packages.first?.getEClass("Greeting")
        for name in ["person", "others", "many", "old"] {
            #expect(LangiumInspect.reference(name, of: greeting)?.containment == false, "\(name)")
            #expect(LangiumInspect.reference(name, of: greeting)?.eType.name == "Person", "\(name)")
        }
        #expect(LangiumInspect.reference("others", of: greeting)?.upperBound == -1)
        #expect(LangiumInspect.reference("many", of: greeting)?.upperBound == -1)
        #expect(result.diagnostics.map(\.code) == [LangiumDiagnosticCode.approximation.rawValue])
    }

    /// Checks that infix rules yield a class with left, operator and right.
    @Test("Infix rules yield a class with left, operator and right")
    func infixRules() throws {
        let result = LangiumReader.parse("""
            grammar Calc
            entry Expression: BinaryExpr;
            infix BinaryExpr on Primary: '*' | '/' > '+' | '-';
            Primary: value=NUMBER;
            """ + terminals)
        let package = try #require(result.packages.first)
        let binary = package.getEClass("BinaryExpr")
        #expect(LangiumInspect.featureNames(binary) == ["left", "operator", "right"])
        #expect(LangiumInspect.reference("left", of: binary)?.eType.name == "Expression")
        #expect(package.getEClass("Expression")?.isAbstract == true)
        #expect(LangiumInspect.superTypeNames(package.getEClass("Primary")) == ["Expression"])
        #expect(LangiumInspect.validationErrors(result.packages).isEmpty)
    }

    /// Checks that types and rules of imported grammars are approximated with warnings.
    @Test("Types and rules of imported grammars are approximated with warnings")
    func imports() throws {
        let result = LangiumReader.parse("""
            grammar Uses
            import './common';
            interface Holder { target: Missing }
            entry Model: holders+=Holder* items+=Item*;
            Holder returns Holder: 'holder';
            Item returns Thing: name=ID ref=QualifiedName other=Other;
            """)
        let package = try #require(result.packages.first)
        #expect(LangiumInspect.reference("target", of: package.getEClass("Holder"))?.eType.name == "EObject")
        let thing = package.getEClass("Thing")
        #expect(LangiumInspect.attribute("name", of: thing)?.eType.name == "EString")
        #expect(LangiumInspect.reference("other", of: thing)?.eType.name == "EObject")
        let codes = result.diagnostics.map(\.code)
        #expect(codes.contains(LangiumDiagnosticCode.externalType.rawValue))
        #expect(codes.contains(LangiumDiagnosticCode.unknownRule.rawValue))
        #expect(result.diagnostics.allSatisfy { $0.severity < .error }, "\(result.diagnostics)")
        #expect(LangiumInspect.validationErrors(result.packages).isEmpty)
    }

    /// Checks that options name the package when the grammar has no name.
    @Test("Options name the package when the grammar has no name")
    func options() throws {
        let unnamed = LangiumReader.parse("entry Model: name=ID;" + terminals, sourceName: "dir/my-lang.langium")
        #expect(unnamed.packages.first?.name == "my_lang")
        let named = LangiumReader.parse(
            "entry Model: name=ID;" + terminals,
            options: LangiumImportOptions(packageName: "lang", nsURI: "http://example.org/lang", nsPrefix: "l"))
        let package = try #require(named.packages.first)
        #expect(package.name == "lang" && package.nsURI == "http://example.org/lang" && package.nsPrefix == "l")
    }

    /// Checks that every rule-grammar and assembly problem has a Langium diagnostic code.
    @Test("Every rule-grammar and assembly problem has a Langium diagnostic code")
    func diagnosticCodes() {
        let codes = Set(LangiumDiagnosticCode.allCases.map(\.rawValue))
        for problem in RuleGrammarProblem.allCases { #expect(codes.contains("langium." + problem.rawValue)) }
        for problem in AssemblyProblem.allCases { #expect(codes.contains("langium." + problem.rawValue)) }
    }
}
