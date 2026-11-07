//
// KM3DiagnosticsTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@Suite("Diagnostics and recovery")
struct KM3DiagnosticsTests {
    /// The diagnostics of a text with a given code.
    ///
    /// - Parameters:
    ///   - code: The code.
    ///   - result: The parse result.
    /// - Returns: The matching diagnostics.
    func diagnostics(_ code: KM3DiagnosticCode, in result: KM3ParseResult) -> [SourceDiagnostic] {
        result.diagnostics.filter { $0.code == code.rawValue }
    }

    @Test("An unresolved type is an error at the type name, and the feature is kept")
    func unresolvedType() throws {
        let text = "package P {\n\tclass C {\n\t\tattribute a : Missing;\n\t}\n}"
        let result = KM3Reader.parse(text, sourceName: "test.km3")
        let found = diagnostics(.unresolvedType, in: result)
        #expect(found.count == 1)
        let diagnostic = try #require(found.first)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.document == "test.km3")
        #expect(diagnostic.range?.start.line == 3)
        #expect(diagnostic.range?.start.column == 17)
        #expect(diagnostic.range?.end.column == 24)
        #expect(result.packages.eClass(named: "C")?.getEAttribute(name: "a")?.eType.name == "Missing")
        #expect(result.hasErrors)
    }

    @Test("An unresolved reference type keeps a class stand-in")
    func unresolvedReferenceType() throws {
        let result = KM3Reader.parse("package P { class C { reference r : Missing; } }")
        #expect(diagnostics(.unresolvedType, in: result).count == 1)
        let reference = try #require(result.packages.eClass(named: "C")?.getEReference(name: "r"))
        #expect(reference.eType is EClass)
    }

    @Test("A missing semicolon is reported at the end of the declaration and the declaration is kept")
    func missingSemicolon() throws {
        let text = "package P {\n\tclass C {\n\t\tattribute a : String\n\t\tattribute b : String;\n\t}\n\tdatatype String;\n}"
        let result = KM3Reader.parse(text)
        let found = diagnostics(.missingToken, in: result)
        #expect(found.count == 1)
        #expect(found.first?.range?.start.line == 3)
        #expect(found.first?.range?.start.column == 23)
        #expect(result.packages.eClass(named: "C")?.eStructuralFeatures.map(\.name) == ["a", "b"])
    }

    @Test("A malformed member is skipped up to the next member")
    func malformedMember() throws {
        let text = "package P {\n\tclass C {\n\t\tattribute : String;\n\t\tattribute b : String;\n\t}\n\tdatatype String;\n}"
        let result = KM3Reader.parse(text)
        let found = diagnostics(.unexpectedToken, in: result)
        #expect(found.count == 1)
        #expect(found.first?.range?.start.line == 3)
        #expect(found.first?.range?.start.column == 13)
        #expect(result.packages.eClass(named: "C")?.eStructuralFeatures.map(\.name) == ["b"])
    }

    @Test("Stray tokens in a class are reported once and skipped")
    func strayTokens() throws {
        let text = "package P { class C { foo bar baz; attribute b : String; } datatype String; }"
        let result = KM3Reader.parse(text)
        let found = diagnostics(.unexpectedToken, in: result)
        #expect(found.count == 1)
        #expect(found.first?.range?.start.column == 23)
        #expect(found.first?.range?.end.column == 35)
        #expect(result.packages.eClass(named: "C")?.eStructuralFeatures.map(\.name) == ["b"])
    }

    @Test("Text outside packages is reported and the following package is read")
    func textOutsidePackages() throws {
        let result = KM3Reader.parse("class Stray { attribute x : X; }\npackage P { class C {} }")
        #expect(diagnostics(.unexpectedToken, in: result).count == 1)
        #expect(result.packages.map(\.name) == ["P"])
        #expect(result.diagnostics.first?.range?.start.line == 1)
    }

    @Test("A missing closing brace of a class does not swallow the next class")
    func missingClassBrace() throws {
        let text = "package P {\n\tclass A {\n\t\tattribute a : String;\n\tclass B {}\n\tdatatype String;\n}"
        let result = KM3Reader.parse(text)
        let found = diagnostics(.missingToken, in: result)
        #expect(found.count == 1)
        #expect(found.first?.range?.start.line == 3)
        #expect(result.packages.first?.eClassifiers.map(\.name) == ["A", "B"])
        #expect(result.packages.eClass(named: "A")?.eStructuralFeatures.count == 1)
    }

    @Test("A missing closing brace at the end of the text is reported")
    func missingPackageBrace() throws {
        let result = KM3Reader.parse("package P {\n\tclass A {}\n")
        let found = diagnostics(.missingToken, in: result)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("package 'P'") == true)
        #expect(result.packages.first?.eClassifiers.map(\.name) == ["A"])
    }

    @Test("A missing opening brace is reported, and text up to the next brace is skipped")
    func missingOpeningBrace() throws {
        let result = KM3Reader.parse("package P extra { class A {} }")
        let found = diagnostics(.missingToken, in: result)
        #expect(found.count == 1)
        #expect(found.first?.range?.start.column == 11)
        #expect(result.packages.first?.eClassifiers.map(\.name) == ["A"])
    }

    @Test("A package without a body or a name is reported and kept")
    func packageWithoutBody() throws {
        let result = KM3Reader.parse("package ;")
        #expect(result.hasErrors)
        #expect(result.packages.count == 1)
        #expect(result.packages.first?.name == "")
    }

    @Test("An unterminated quoted name and an invalid character are lexical errors")
    func lexicalErrors() throws {
        let result = KM3Reader.parse("package P { class \"Open {} }\npackage Q { class $ {} }")
        let unterminated = diagnostics(.unterminatedString, in: result)
        #expect(unterminated.count == 1)
        #expect(unterminated.first?.range?.start.column == 19)
        let invalid = diagnostics(.unexpectedCharacter, in: result)
        #expect(invalid.count == 1)
        #expect(invalid.first?.range?.start.line == 2)
        #expect(invalid.first?.range?.start.column == 19)
        #expect(result.packages.package(named: "Q") != nil)
    }

    @Test("An unterminated single-quoted string and an overlong number are lexical errors")
    func moreLexicalErrors() {
        let result = KM3Reader.parse("package P { 'open\n 99999999999999999999999 1.5 'closed' }")
        #expect(diagnostics(.unterminatedString, in: result).count == 1)
        #expect(diagnostics(.invalidNumber, in: result).count == 1)
        #expect(result.packages.map(\.name) == ["P"])
    }

    @Test("Malformed multiplicities are reported")
    func multiplicities() throws {
        let text = """
            package P {
            \tclass C {
            \t\tattribute a[3-1] : String;
            \t\tattribute b[2] : String;
            \t\tattribute c[x] : String;
            \t\tattribute d[1-] : String;
            \t\tattribute e[0-0] : String;
            \t\tattribute f[1-2 : String;
            \t}
            \tdatatype String;
            }
            """
        let result = KM3Reader.parse(text)
        let found = diagnostics(.invalidMultiplicity, in: result)
        #expect(found.map { $0.range?.start.line ?? 0 } == [3, 4, 5, 6, 7, 8])
        #expect(found.map(\.severity) == [.error, .warning, .error, .error, .error, .error])
        let eClass = try #require(result.packages.eClass(named: "C"))
        #expect(eClass.getEAttribute(name: "b")?.lowerBound == 2)
        #expect(eClass.getEAttribute(name: "b")?.upperBound == 2)
        #expect(eClass.eStructuralFeatures.map(\.name) == ["a", "b", "e"])
    }

    @Test("Modifiers that do not apply are reported")
    func inapplicableModifiers() throws {
        let text = """
            package P {
            \tclass C {
            \t\tattribute a container : String;
            \t\treference r unique : C;
            \t\tattribute b ordered ordered : String;
            \t\tattribute s subsets a : String;
            \t\tattribute o : String oppositeOf r;
            \t}
            \tdatatype String;
            }
            """
        let result = KM3Reader.parse(text)
        let found = diagnostics(.inapplicableModifier, in: result)
        #expect(found.map { $0.range?.start.line ?? 0 } == [3, 4, 5, 6, 7])
        #expect(found.map(\.severity) == [.error, .warning, .warning, .error, .error])
        let eClass = try #require(result.packages.eClass(named: "C"))
        #expect(eClass.getEReference(name: "r")?.unique == true)
        #expect(eClass.getEAttribute(name: "b")?.ordered == true)
    }

    @Test("A reserved word used as a name asks for quotes and is accepted")
    func reservedWordAsName() throws {
        let result = KM3Reader.parse("package P { class C { attribute unique : String; } datatype String; }")
        let found = diagnostics(.unexpectedToken, in: result)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("\"unique\"") == true)
        #expect(result.packages.eClass(named: "C")?.getEAttribute(name: "unique") != nil)
    }

    @Test("Duplicate classifiers in a package are errors, across packages warnings")
    func duplicates() throws {
        let text = """
            package P {
            \tclass A {}
            \tclass A {}
            }
            package Q {
            \tclass A {}
            \tclass B { reference r : A; }
            }
            """
        let result = KM3Reader.parse(text)
        let duplicate = diagnostics(.duplicateClassifier, in: result)
        #expect(duplicate.count == 1)
        #expect(duplicate.first?.range?.start.line == 3)
        #expect(duplicate.first?.related.first?.range?.start.line == 2)
        let ambiguous = diagnostics(.ambiguousClassifier, in: result)
        #expect(ambiguous.count == 1)
        #expect(ambiguous.first?.severity == .warning)
        #expect(ambiguous.first?.range?.start.line == 6)
        let first = try #require(result.packages.first?.eClassifiers.first)
        #expect(result.packages.eClass(named: "B")?.getEReference(name: "r")?.eType.id == first.id)
    }

    @Test("Duplicate features, literals and packages are reported")
    func duplicateMembers() throws {
        let text = """
            package P {
            \tclass C { attribute a : String; attribute a : String; }
            \tenumeration E { literal x; literal x; }
            \tdatatype String;
            }
            package P {}
            """
        let result = KM3Reader.parse(text)
        let found = diagnostics(.duplicateMember, in: result)
        #expect(found.map { $0.range?.start.line ?? 0 } == [2, 3, 6])
    }

    @Test("Supertypes must name classes, and repeated supertypes are reported")
    func supertypes() throws {
        let text = "package P { class A extends Nope, D, B, B {} class B {} datatype D; }"
        let result = KM3Reader.parse(text)
        #expect(diagnostics(.unresolvedSupertype, in: result).count == 1)
        #expect(diagnostics(.invalidTypeKind, in: result).count == 1)
        #expect(diagnostics(.duplicateMember, in: result).count == 1)
        #expect(result.packages.eClass(named: "A")?.eSuperTypes.map(\.name) == ["B"])
    }

    @Test("Cyclic inheritance is reported and broken")
    func cycles() throws {
        let result = KM3Reader.parse("package P { class A extends B {} class B extends C {} class C extends A {} class D extends D {} }")
        let found = diagnostics(.cyclicInheritance, in: result)
        #expect(found.count == 2)
        let a = try #require(result.packages.eClass(named: "A"))
        #expect(a.eAllSuperTypes.count == 2)
        #expect(result.packages.eClass(named: "D")?.eSuperTypes.isEmpty == true)
    }

    @Test("Opposites must name references of the referenced class or its supertypes")
    func opposites() throws {
        let text = """
            package P {
            \tclass Base { reference owner : A oppositeOf items; }
            \tclass B extends Base { attribute name : String; }
            \tclass A {
            \t\treference items[*] : B oppositeOf owner;
            \t\treference broken : B oppositeOf nothing;
            \t\treference attr : B oppositeOf name;
            \t\treference lonely : B oppositeOf owner;
            \t}
            \tdatatype String;
            }
            """
        let result = KM3Reader.parse(text)
        let unresolved = diagnostics(.unresolvedOpposite, in: result)
        #expect(unresolved.map { $0.range?.start.line ?? 0 } == [6])
        let kind = diagnostics(.invalidTypeKind, in: result)
        #expect(kind.map { $0.range?.start.line ?? 0 } == [7])
        let inconsistent = diagnostics(.inconsistentOpposite, in: result)
        #expect(inconsistent.map { $0.range?.start.line ?? 0 } == [8])
        #expect(inconsistent.first?.severity == .warning)
        let a = try #require(result.packages.eClass(named: "A"))
        let base = try #require(result.packages.eClass(named: "Base"))
        #expect(a.getEReference(name: "items")?.opposite == base.getEReference(name: "owner")?.id)
    }

    @Test("A one-sided opposite is a warning")
    func oneSidedOpposite() throws {
        let result = KM3Reader.parse("package P { class A { reference b : B oppositeOf a; } class B { reference a : A; } }")
        let found = diagnostics(.inconsistentOpposite, in: result)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("does not name it in return") == true)
    }

    @Test("A reference to a data type is an error and becomes an attribute")
    func referenceToDataType() throws {
        let result = KM3Reader.parse("package P { class C { reference r : String; } datatype String; }")
        #expect(diagnostics(.invalidTypeKind, in: result).count == 1)
        #expect(result.packages.eClass(named: "C")?.getEAttribute(name: "r") != nil)
    }

    @Test("Subsets has no Ecore counterpart and is reported")
    func subsets() throws {
        let result = KM3Reader.parse(
            "package P { class C { reference all[*] : C; reference some[*] subsets all, all : C; } }")
        let found = diagnostics(.unsupportedConstruct, in: result)
        #expect(found.count == 1)
        #expect(found.first?.severity == .warning)
        #expect(result.packages.eClass(named: "C")?.getEReference(name: "some") != nil)
    }

    @Test("Empty and repeated directives are reported")
    func directives() throws {
        let result = KM3Reader.parse("-- @nsURI\n-- @nsPrefix a\n-- @nsPrefix b\npackage P {}")
        let found = diagnostics(.invalidDirective, in: result)
        #expect(found.map { $0.range?.start.line ?? 0 } == [1, 3])
        #expect(result.packages.first?.nsPrefix == "a")
    }

    @Test("A malformed operation is skipped and the next member is kept")
    func malformedOperation() throws {
        let text = "package P { class C { operation f(a String) : String; operation g(a : String, b : String); } datatype String; }"
        let result = KM3Reader.parse(text)
        #expect(diagnostics(.missingToken, in: result).count == 1)
        let eClass = try #require(result.packages.eClass(named: "C"))
        #expect(eClass.eOperations.map(\.name) == ["g"])
        #expect(eClass.getOperation(name: "g")?.eParameters.count == 2)
    }

    @Test("A malformed classifier is skipped up to the next declaration")
    func malformedClassifier() throws {
        let text = "package P { abstract datatype X; enumeration E { literal a; oops; literal b } datatype ; class C {} }"
        let result = KM3Reader.parse(text)
        #expect(result.hasErrors)
        #expect(result.packages.first?.eClassifiers.map(\.name) == ["X", "E", "C"])
        #expect(result.packages.first?.getEEnum("E")?.literals.map(\.name) == ["a", "b"])
    }

    @Test("A malformed literal is skipped up to the next literal")
    func malformedLiteral() throws {
        let result = KM3Reader.parse("package P { enumeration E { literal ; literal b; literal c d; literal e; } }")
        #expect(result.packages.first?.getEEnum("E")?.literals.map(\.name) == ["b", "e"])
        #expect(diagnostics(.unexpectedToken, in: result).count == 1)
        #expect(diagnostics(.missingToken, in: result).count == 1)
    }

    @Test("A data type without a semicolon is kept when a declaration follows")
    func dataTypeWithoutSemicolon() throws {
        let result = KM3Reader.parse("package P { datatype A datatype B class C {} datatype D }")
        #expect(result.packages.first?.eClassifiers.map(\.name) == ["A", "B", "C", "D"])
        #expect(diagnostics(.missingToken, in: result).count == 3)
        let broken = KM3Reader.parse("package P { datatype A extra; class C {} }")
        #expect(broken.packages.first?.eClassifiers.map(\.name) == ["C"])
    }

    @Test("A class with a malformed header is skipped with its body")
    func malformedClassHeader() throws {
        let result = KM3Reader.parse(
            "package P { class A extends { attribute a : String; } class B {} abstract class C extends D, { } }")
        #expect(result.packages.first?.eClassifiers.map(\.name) == ["B"])
        #expect(diagnostics(.unexpectedToken, in: result).count == 2)
    }

    @Test("A member that runs into the end of the body is cut off there")
    func memberAtEndOfBody() throws {
        let result = KM3Reader.parse("package P { class A { attribute a : } class B {} }")
        #expect(result.packages.first?.eClassifiers.map(\.name) == ["A", "B"])
        #expect(result.packages.eClass(named: "A")?.eStructuralFeatures.isEmpty == true)
    }

    @Test("Diagnostics are sorted by position")
    func ordering() {
        let result = KM3Reader.parse("package P { class C { attribute a : X; attribute b : Y } } $")
        let offsets = result.diagnostics.compactMap { $0.range?.start.utf8Offset }
        #expect(offsets == offsets.sorted())
        #expect(result.diagnostics.count == 4)
    }

    @Test("Positions count Unicode scalars in columns and UTF-8 bytes in offsets")
    func positions() throws {
        let result = KM3Reader.parse("package Pé { class Ça { attribute ü : Missing; } }")
        let diagnostic = try #require(diagnostics(.unresolvedType, in: result).first)
        #expect(diagnostic.range?.start.column == 39)
        #expect(diagnostic.range?.start.utf8Offset == 41)
        #expect(result.packages.eClass(named: "Ça") != nil)
    }
}
