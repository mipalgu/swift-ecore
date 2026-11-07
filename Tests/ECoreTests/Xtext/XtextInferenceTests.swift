//
// XtextInferenceTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// The header that most fixtures share.
private let header = """
    grammar org.example.Test with org.eclipse.xtext.common.Terminals
    generate test "http://www.example.org/test"

    """

/// Imports a grammar body under the shared header.
///
/// - Parameter body: The rules.
/// - Returns: The result.
private func importing(_ body: String) -> XtextParseResult {
    XtextReader.parse(header + body, sourceName: "test.xtext")
}

/// Tests of Xtext metamodel inference.
@Suite("Xtext metamodel inference")
struct XtextInferenceTests {
    /// The arithmetic language with let bindings that the cross-format comparison uses.
    static let arithmetic = """
        grammar org.example.Arith with org.eclipse.xtext.common.Terminals
        generate arith "http://www.example.org/arith"

        Expr: Let | Addition;
        Let: 'let' name=ID '=' init=Expr 'in' body=Expr;
        Addition returns Expr: Multiplication ({BinOp.left=current} operator=AddOp right=Multiplication)*;
        Multiplication returns Expr: Primary ({BinOp.left=current} operator=MulOp right=Primary)*;
        Primary returns Expr: {Num} value=INT | {Var} name=ID | '(' Expr ')';
        enum AddOp returns Op: Add='+' | Sub='-';
        enum MulOp returns Op: Mul='*' | Div='/';
        """

    /// Checks that the arithmetic language yields concrete Expr with four subclasses and an Op enumeration.
    @Test("The arithmetic language yields concrete Expr with four subclasses and an Op enumeration")
    func arithmetic() throws {
        let result = XtextReader.parse(Self.arithmetic, sourceName: "arith.xtext")
        #expect(result.diagnostics.filter { $0.severity >= .warning }.isEmpty, "\(result.diagnostics)")
        let package = try #require(result.packages.first)
        #expect(package.name == "arith")
        #expect(package.nsURI == "http://www.example.org/arith")
        #expect(package.nsPrefix == "arith")
        #expect(package.eClassifiers.map(\.name) == ["Expr", "Let", "Op", "BinOp", "Num", "Var"])
        let expr = try #require(XtextInspect.eClass("Expr", in: package))
        #expect(!expr.isAbstract)
        #expect(XtextInspect.featureNames(expr).isEmpty)
        for name in ["Let", "BinOp", "Num", "Var"] {
            #expect(XtextInspect.superTypeNames(XtextInspect.eClass(name, in: package)) == ["Expr"], "\(name)")
        }
        let binOp = XtextInspect.eClass("BinOp", in: package)
        #expect(XtextInspect.featureNames(binOp) == ["left", "operator", "right"])
        #expect(XtextInspect.reference("left", of: binOp)?.containment == true)
        #expect(XtextInspect.reference("left", of: binOp)?.eType.name == "Expr")
        #expect(XtextInspect.attribute("operator", of: binOp)?.eType.name == "Op")
        let op = try #require(package.getEEnum("Op"))
        #expect(op.literals.map(\.name) == ["Add", "Sub", "Mul", "Div"])
        #expect(op.literals.map(\.literal) == ["+", "-", "*", "/"])
        let letClass = XtextInspect.eClass("Let", in: package)
        #expect(XtextInspect.featureNames(letClass) == ["name", "init", "body"])
        #expect(XtextInspect.attribute("name", of: letClass)?.eType.name == "EString")
        #expect(XtextInspect.attribute("value", of: XtextInspect.eClass("Num", in: package))?.eType.name == "EInt")
        #expect(XtextInspect.validationErrors(result.packages).isEmpty)
    }

    /// Checks that features that every direct subtype has move to the supertype.
    @Test("Features that every direct subtype has move to the supertype")
    func lifting() throws {
        let result = importing("""
            Model: elements+=Element*;
            Element: A | B;
            A: 'a' name=ID x=INT;
            B: 'b' name=ID y=STRING;
            """)
        let package = try #require(result.packages.first)
        #expect(XtextInspect.featureNames(XtextInspect.eClass("Element", in: package)) == ["name"])
        #expect(XtextInspect.featureNames(XtextInspect.eClass("A", in: package)) == ["x"])
        #expect(XtextInspect.featureNames(XtextInspect.eClass("B", in: package)) == ["y"])
        #expect(XtextInspect.validationErrors(result.packages).isEmpty)
    }

    /// Checks that features differing in type are not lifted, and a single subtype lifts nothing.
    @Test("Features differing in type are not lifted, and a single subtype lifts nothing")
    func noLifting() throws {
        let result = importing("""
            Model: a=Element b=Single;
            Element: A | B;
            A: 'a' name=ID;
            B: 'b' name=INT;
            Single: Only;
            Only: 'o' name=ID;
            """)
        let package = try #require(result.packages.first)
        #expect(XtextInspect.featureNames(XtextInspect.eClass("Element", in: package)).isEmpty)
        #expect(XtextInspect.featureNames(XtextInspect.eClass("A", in: package)) == ["name"])
        #expect(XtextInspect.featureNames(XtextInspect.eClass("Single", in: package)).isEmpty)
        #expect(XtextInspect.featureNames(XtextInspect.eClass("Only", in: package)) == ["name"])
    }

    /// Checks that values of unrelated classes give EObject; related ones their common supertype.
    @Test("Values of unrelated classes give EObject; related ones their common supertype")
    func compatibleTypes() throws {
        let result = importing("""
            Model: (things+=A | things+=B)* (shapes+=Circle | shapes+=Square)* choice=(Circle | Square);
            A: 'a' name=ID;
            B: 'b' name=ID;
            Shape: Circle | Square;
            Circle: 'circle' r=INT;
            Square: 'square' s=INT;
            """)
        let package = try #require(result.packages.first)
        let model = XtextInspect.eClass("Model", in: package)
        #expect(XtextInspect.reference("things", of: model)?.eType.name == "EObject")
        #expect(XtextInspect.reference("things", of: model)?.upperBound == -1)
        #expect(XtextInspect.reference("shapes", of: model)?.eType.name == "Shape")
        #expect(XtextInspect.reference("choice", of: model)?.eType.name == "Shape")
        #expect(XtextInspect.validationErrors(result.packages).isEmpty)
    }

    /// Checks that assigning a feature with a different cardinality or data type is an error.
    @Test("Assigning a feature with a different cardinality or data type is an error")
    func conflicts() throws {
        let result = importing("""
            Model: 'm' x=ID x+=ID ';' y=ID y=INT;
            """)
        #expect(XtextInspect.diagnostics(result.diagnostics, code: XtextDiagnosticCode.featureConflict.rawValue).count == 1)
        #expect(XtextInspect.diagnostics(result.diagnostics, code: XtextDiagnosticCode.incompatibleTypes.rawValue).count == 1)
        let model = XtextInspect.eClass("Model", in: result.packages.first)
        #expect(XtextInspect.attribute("x", of: model)?.upperBound == 1)
        #expect(XtextInspect.attribute("y", of: model)?.eType.name == "EString")
    }

    /// Checks that cross-references, flags, keywords and lists map to their Ecore features.
    @Test("Cross-references, flags, keywords and lists map to their Ecore features")
    func assignments() throws {
        let result = importing("""
            Model: entities+=Entity* refs+=Ref*;
            Entity: (abstract?='abstract')? 'entity' name=ID kind=('class' | 'record') tags+=STRING*;
            Ref: 'ref' target=[Entity] others+=[Entity|STRING]*;
            """)
        let package = try #require(result.packages.first)
        let entity = XtextInspect.eClass("Entity", in: package)
        #expect(XtextInspect.attribute("abstract", of: entity)?.eType.name == "EBoolean")
        #expect(XtextInspect.attribute("kind", of: entity)?.eType.name == "EString")
        let tags = try #require(XtextInspect.attribute("tags", of: entity))
        #expect(tags.upperBound == -1 && tags.lowerBound == 0 && !tags.unique)
        let ref = XtextInspect.eClass("Ref", in: package)
        let target = try #require(XtextInspect.reference("target", of: ref))
        #expect(!target.containment && target.eType.name == "Entity" && target.upperBound == 1)
        let others = try #require(XtextInspect.reference("others", of: ref))
        #expect(!others.containment && others.upperBound == -1 && !others.unique)
        let entities = try #require(XtextInspect.reference("entities", of: XtextInspect.eClass("Model", in: package)))
        #expect(entities.containment && entities.unique)
        #expect(XtextInspect.validationErrors(result.packages).isEmpty)
    }

    /// Checks that datatype rules yield strings or the Ecore type they return.
    @Test("Datatype rules yield strings or the Ecore type they return")
    func datatypeRules() throws {
        let result = XtextReader.parse("""
            grammar org.example.Data with org.eclipse.xtext.common.Terminals
            import "http://www.eclipse.org/emf/2002/Ecore" as ecore
            generate data "http://www.example.org/data"
            Model: name=QualifiedName size=Size when=Date flag=Flag;
            QualifiedName: ID ('.' ID)*;
            Size returns ecore::EInt: '-'? INT;
            Date returns ecore::EDate: STRING;
            Flag returns ecore::EBoolean: 'yes' | 'no';
            """)
        #expect(result.diagnostics.filter { $0.severity >= .warning }.isEmpty, "\(result.diagnostics)")
        let package = try #require(result.packages.first)
        #expect(package.eClassifiers.map(\.name) == ["Model"])
        let model = XtextInspect.eClass("Model", in: package)
        #expect(XtextInspect.attribute("name", of: model)?.eType.name == "EString")
        #expect(XtextInspect.attribute("size", of: model)?.eType.name == "EInt")
        #expect(XtextInspect.attribute("when", of: model)?.eType.name == "EDate")
        #expect(XtextInspect.attribute("flag", of: model)?.eType.name == "EBoolean")
    }

    /// Checks that a data type that Ecore lacks cannot be created, as in Xtext.
    @Test("A data type that Ecore lacks cannot be created, as in Xtext")
    func uncreatableDataType() throws {
        let result = importing("""
            Model: name=Name;
            Name returns Identifier: ID;
            """)
        let errors = XtextInspect.diagnostics(result.diagnostics, code: XtextDiagnosticCode.unresolvedTypeReference.rawValue)
        #expect(errors.count == 1)
        #expect(errors.first?.range?.start.line == 4)
        #expect(XtextInspect.attribute("name", of: XtextInspect.eClass("Model", in: result.packages.first))?.eType.name == "EString")
    }

    /// Checks that an unaliased Ecore import makes Ecore's data types available by simple name.
    @Test("An unaliased Ecore import makes Ecore's data types available by simple name")
    func unaliasedEcore() throws {
        let result = XtextReader.parse("""
            grammar org.example.Plain with org.eclipse.xtext.common.Terminals
            import "http://www.eclipse.org/emf/2002/Ecore"
            generate plain "http://www.example.org/plain"
            Model: value=SignedInt any=Anything;
            SignedInt returns EInt: '-'? INT;
            Anything returns EObject: Model;
            """)
        let model = XtextInspect.eClass("Model", in: result.packages.first)
        #expect(XtextInspect.attribute("value", of: model)?.eType.name == "EInt")
        #expect(XtextInspect.reference("any", of: model)?.eType.name == "EObject")
    }

    /// Checks that types of imported packages are external: EObject stands in and their features are not inferred.
    @Test("Types of imported packages are external: EObject stands in and their features are not inferred")
    func externalTypes() throws {
        let result = XtextReader.parse("""
            grammar org.example.Ext with org.eclipse.xtext.common.Terminals
            import "http://www.example.org/other" as other
            generate ext "http://www.example.org/ext"
            Model: thing=Other;
            Other returns other::Thing: name=ID;
            """)
        let model = XtextInspect.eClass("Model", in: result.packages.first)
        let thing = try #require(XtextInspect.reference("thing", of: model))
        #expect(thing.eType.name == "EObject" && thing.containment)
        let external = XtextInspect.diagnostics(result.diagnostics, code: XtextDiagnosticCode.externalType.rawValue)
        #expect(external.count == 1)
        #expect(external.first?.message.contains("Thing") == true)
        #expect(external.first?.message.contains("http://www.example.org/other") == true)
        #expect(XtextInspect.diagnostics(result.diagnostics, code: XtextDiagnosticCode.sealedType.rawValue).count == 1)
        #expect(XtextInspect.validationErrors(result.packages).isEmpty)
    }

    /// Checks that a grammar without generate declarations imports no package.
    @Test("A grammar without generate declarations imports no package")
    func nothingGenerated() throws {
        let result = XtextReader.parse("""
            grammar org.example.Only with org.eclipse.xtext.common.Terminals
            import "http://www.example.org/existing"
            Model returns Model: name=ID;
            """)
        #expect(result.packages.isEmpty)
        #expect(XtextInspect.diagnostics(result.diagnostics, code: XtextDiagnosticCode.noGeneratedPackage.rawValue).count == 1)
        #expect(XtextInspect.diagnostics(result.diagnostics, code: XtextDiagnosticCode.externalType.rawValue).count == 1)
    }

    /// Checks that several generated packages hold the types their aliases name.
    @Test("Several generated packages hold the types their aliases name")
    func aliasedPackages() throws {
        let result = XtextReader.parse("""
            grammar org.example.Two with org.eclipse.xtext.common.Terminals
            generate main "http://www.example.org/main"
            generate extra "http://www.example.org/extra" as extra
            Model: items+=Item*;
            Item returns extra::Item: 'item' name=ID;
            """)
        #expect(result.packages.map(\.name) == ["main", "extra"])
        #expect(result.packages[1].getEClass("Item") != nil)
        let items = XtextInspect.reference("items", of: XtextInspect.eClass("Model", in: result.packages[0]))
        #expect(items?.eType.name == "Item")
        #expect(XtextInspect.validationErrors(result.packages).isEmpty)
    }

    /// Checks that fragments become supertypes; wildcard fragments are inlined.
    @Test("Fragments become supertypes; wildcard fragments are inlined")
    func fragments() throws {
        let result = importing("""
            Model: entities+=Entity* values+=Value*;
            Entity: 'entity' Named;
            Value: 'value' Typed;
            fragment Named: name=ID;
            fragment Typed*: type=ID;
            """)
        let package = try #require(result.packages.first)
        #expect(XtextInspect.superTypeNames(XtextInspect.eClass("Entity", in: package)) == ["Named"])
        #expect(XtextInspect.featureNames(XtextInspect.eClass("Named", in: package)) == ["name"])
        #expect(XtextInspect.featureNames(XtextInspect.eClass("Entity", in: package)).isEmpty)
        #expect(XtextInspect.featureNames(XtextInspect.eClass("Value", in: package)) == ["type"])
        #expect(package.getEClass("Typed") == nil)
    }

    /// Checks that unordered groups and optional groups contribute all their features.
    @Test("Unordered groups and optional groups contribute all their features")
    func unorderedGroups() throws {
        let result = importing("""
            Model: (public?='public' & static?='static')? ('as' alias=ID)? name=ID;
            """)
        #expect(XtextInspect.featureNames(XtextInspect.eClass("Model", in: result.packages.first)) == ["public", "static", "alias", "name"])
    }

    /// Checks that assigned actions that add to a list create many-valued containment features.
    @Test("Assigned actions that add to a list create many-valued containment features")
    func addingActions() throws {
        let result = importing("""
            Seq returns Expr: Atom ({Seq.items+=current} ',' items+=Atom)*;
            Atom returns Expr: {Atom} value=INT;
            """)
        let seq = XtextInspect.eClass("Seq", in: result.packages.first)
        let items = try #require(XtextInspect.reference("items", of: seq))
        #expect(items.upperBound == -1 && items.containment && items.eType.name == "Expr")
    }

    /// Checks that changing the type twice in a rule is an error.
    @Test("Changing the type twice in a rule is an error")
    func typeChangedTwice() throws {
        let result = importing("""
            Model: A B;
            A: 'a' name=ID;
            B: 'b' name=ID;
            """)
        let errors = XtextInspect.diagnostics(result.diagnostics, code: XtextDiagnosticCode.typeChangedTwice.rawValue)
        #expect(errors.count == 1)
        #expect(errors.first?.range?.start.line == 3 && errors.first?.range?.start.column == 10)
    }

    /// Checks that undefined rules are errors unless a super grammar such as Xbase may define them.
    @Test("Undefined rules are errors unless a super grammar such as Xbase may define them")
    func unknownRules() throws {
        let missing = importing("Model: name=Missing;")
        #expect(XtextInspect.diagnostics(missing.diagnostics, code: XtextDiagnosticCode.unknownRule.rawValue)
            .map(\.severity) == [.error])
        let xbase = XtextReader.parse("""
            grammar org.example.Script with org.eclipse.xtext.xbase.Xbase
            generate script "http://www.example.org/script"
            Script: 'script' name=QualifiedName body=XBlockExpression;
            """)
        let script = XtextInspect.eClass("Script", in: xbase.packages.first)
        #expect(XtextInspect.attribute("name", of: script)?.eType.name == "EString")
        #expect(XtextInspect.reference("body", of: script)?.eType.name == "EObject")
        #expect(XtextInspect.diagnostics(xbase.diagnostics, code: XtextDiagnosticCode.unknownRule.rawValue)
            .allSatisfy { $0.severity == .warning })
        #expect(XtextInspect.validationErrors(xbase.packages).isEmpty)
    }

    /// Checks that a grammar without super grammar does not know the common terminals.
    @Test("A grammar without super grammar does not know the common terminals")
    func noTerminals() throws {
        let result = XtextReader.parse("""
            grammar org.example.Bare
            generate bare "http://www.example.org/bare"
            Model: name=ID;
            terminal ID: ('a'..'z')+;
            """)
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics)")
        #expect(XtextInspect.attribute("name", of: XtextInspect.eClass("Model", in: result.packages.first))?.eType.name == "EString")
    }

    /// Checks that enum literals keep their keyword as literal and repeat only once.
    @Test("Enum literals keep their keyword as literal and repeat only once")
    func enumRules() throws {
        let result = importing("""
            Model: kind=Kind;
            enum Kind: ADD='add' | ADD='+' | REMOVE='remove' | KEEP;
            """)
        let kind = try #require(result.packages.first?.getEEnum("Kind"))
        #expect(kind.literals.map(\.name) == ["ADD", "REMOVE", "KEEP"])
        #expect(kind.literals.map(\.literal) == ["add", "remove", "KEEP"])
        #expect(kind.literals.map(\.value) == [0, 1, 2])
        #expect(XtextInspect.attribute("kind", of: XtextInspect.eClass("Model", in: result.packages.first))?.eType.name == "Kind")
    }

    /// Checks that calling an enum rule without assignment is an error.
    @Test("Calling an enum rule without assignment is an error")
    func unassignedEnumCall() throws {
        let result = importing("""
            Model: Kind name=ID;
            enum Kind: A | B;
            """)
        #expect(XtextInspect.diagnostics(result.diagnostics, code: XtextDiagnosticCode.invalidRuleCall.rawValue).count == 1)
    }

    /// Checks that options override the default generated package.
    @Test("Options override the default generated package")
    func options() throws {
        let result = XtextReader.parse(
            Self.arithmetic, options: XtextImportOptions(packageName: "calc", nsURI: "urn:calc", nsPrefix: "c"))
        let package = try #require(result.packages.first)
        #expect(package.name == "calc" && package.nsURI == "urn:calc" && package.nsPrefix == "c")
        #expect(XtextInspect.reference("left", of: XtextInspect.eClass("BinOp", in: package))?.eType.name == "Expr")
    }

    /// Checks that every rule-grammar and assembly problem has an Xtext diagnostic code.
    @Test("Every rule-grammar and assembly problem has an Xtext diagnostic code")
    func diagnosticCodes() {
        let codes = Set(XtextDiagnosticCode.allCases.map(\.rawValue))
        for problem in RuleGrammarProblem.allCases { #expect(codes.contains("xtext." + problem.rawValue)) }
        for problem in AssemblyProblem.allCases { #expect(codes.contains("xtext." + problem.rawValue)) }
    }
}
