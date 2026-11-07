//
// ASDLSyntaxTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

@Suite("ASDL recovery and diagnostics")
struct ASDLRecoveryTests {
    /// A module with several independent mistakes.
    static let broken = """
        module Broken {
            good = (int x)
            bad = (int x
            later = A | B(undefined y)
            good = (string again)
            @
        }
        """

    @Test("Reading continues after errors and reports each at its position")
    func recovery() throws {
        let result = ASDLReader.parse(Self.broken, sourceName: "broken.asdl")
        let package = try #require(result.packages.first)
        #expect(package.eClassifiers.map(\.name) == ["good", "later", "A", "B"])
        let summary = result.diagnostics.map { "\($0.code)@\($0.range?.start.line ?? 0):\($0.range?.start.column ?? 0)" }
        #expect(summary == [
            "asdl.unexpectedToken@4:5",
            "asdl.undefinedType@4:19",
            "asdl.duplicateType@5:5",
            "asdl.unexpectedCharacter@6:5",
        ])
        #expect(result.diagnostics.allSatisfy { $0.document == "broken.asdl" })
        #expect(validationErrors(result.packages).isEmpty)
    }

    @Test("Undefined types fall back to EJavaObject")
    func undefinedFallback() throws {
        let result = ASDLReader.parse(Self.broken)
        let package = try #require(result.packages.first)
        let y = try #require(attribute("y", of: eClass("B", in: package)))
        #expect(y.eType.name == "EJavaObject")
    }

    @Test("A text without a module is reported at its end")
    func missingModule() {
        let result = ASDLReader.parse("-- nothing here\n")
        #expect(result.packages.isEmpty)
        let missing = diagnostics(.missingModule, in: result)
        #expect(missing.count == 1)
        #expect(missing.first?.range?.start.line == 2)
    }

    @Test("A missing closing brace is reported at the end of the text")
    func missingBrace() throws {
        let result = ASDLReader.parse("module M {\n  t = (int x)\n")
        #expect(result.packages.first?.eClassifiers.map(\.name) == ["t"])
        let error = try #require(result.diagnostics.first)
        #expect(error.code == ASDLDiagnosticCode.unexpectedToken.rawValue)
        #expect(error.range?.start.line == 3 && error.range?.start.column == 1)
    }

    @Test("Text before a module is skipped with one error")
    func textBeforeModule() {
        let result = ASDLReader.parse("garbage here\nmodule M { t = (int x) }")
        #expect(diagnostics(.unexpectedToken, in: result).count == 1)
        #expect(result.packages.count == 1)
    }

    @Test("An unterminated version string is reported once")
    func unterminatedString() {
        let result = ASDLReader.parse("module M version \"1.0\n{ t = (int x) }")
        #expect(diagnostics(.unterminatedString, in: result).count == 1)
        #expect(result.packages.first?.eClassifiers.map(\.name) == ["t"])
    }

    @Test("Repeated constructors are reported and the repetition dropped")
    func duplicateConstructor() throws {
        let result = ASDLReader.parse("module M { a = X(int i) | Y\n b = X | Z\n c = (int c) | W }")
        let duplicates = diagnostics(.duplicateConstructor, in: result)
        #expect(duplicates.count == 1)
        #expect(duplicates.first?.range?.start.line == 2)
        let package = try #require(result.packages.first)
        #expect(package.eClassifiers.map(\.name).filter { $0 == "X" }.count == 1)
    }

    @Test("Empty field lists are accepted with a warning")
    func emptyFields() {
        let result = ASDLReader.parse("module M { t = C() }")
        #expect(diagnostics(.emptyFields, in: result).first?.severity == .warning)
    }

    @Test("Every diagnostic code has the notation prefix, and assembly problems have codes")
    func codes() {
        #expect(ASDLDiagnosticCode.allCases.allSatisfy { $0.rawValue.hasPrefix("asdl.") })
        for problem in AssemblyProblem.allCases {
            #expect(ASDLDiagnosticCode(rawValue: "asdl." + problem.rawValue) != nil)
        }
    }
}

@Suite("ASDL tokens and outline")
struct ASDLTokenTests {
    @Test("Tokens classify keywords, types, constructors, comments and punctuation")
    func tokens() {
        let text = "-- c\nmodule M version \"2\" { t = C(int x, t* ys) attributes (int line) }"
        let tokens = ASDLSyntax.tokens(in: text)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        func spelling(_ token: SourceToken) -> String {
            let line = Array(lines[token.range.start.line - 1].unicodeScalars)
            let start = token.range.start.column - 1
            return String(String.UnicodeScalarView(line[start..<(start + token.range.utf8Length)]))
        }
        let classified = tokens.map { "\(spelling($0)):\($0.kind.rawValue)" }
        #expect(classified == [
            "-- c:comment", "module:keyword", "M:typeName", "version:keyword", "\"2\":string", "{:punctuation",
            "t:typeName", "=:punctuation", "C:identifier", "(:punctuation", "int:typeName", "x:identifier",
            ",:punctuation", "t:typeName", "*:punctuation", "ys:identifier", "):punctuation", "attributes:keyword",
            "(:punctuation", "int:typeName", "line:identifier", "):punctuation", "}:punctuation",
        ])
    }

    @Test("Characters that start no token are invalid tokens")
    func invalidTokens() {
        let tokens = ASDLSyntax.tokens(in: "module M { é }")
        #expect(tokens.contains { $0.kind == .invalid && $0.range.utf8Length == 2 })
    }

    @Test("The outline nests definitions, constructors, fields and attributes")
    func outline() throws {
        let result = ASDLReader.parse(ASDLFixtures.shapes)
        let module = try #require(result.outline.first)
        #expect(module.kind == ASDLOutlineKind.module && module.name == "Shapes" && module.detail == "1.0")
        #expect(module.children.map(\.name) == ["shape", "point", "colour", "tag", "note"])
        #expect(module.children.map(\.kind) == ["sum", "product", "sum", "product", "sum"])
        let shape = module.children[0]
        #expect(shape.children.map(\.name) == ["Circle", "Polygon", "Empty", "line", "column"])
        #expect(shape.children.map(\.kind) == ["constructor", "constructor", "constructor", "attribute", "attribute"])
        #expect(shape.children[1].detail == "(point* vertices, string? label)")
        #expect(shape.children[0].children.map(\.name) == ["centre", "radius"])
        #expect(shape.selectionRange.start.line == 3 && shape.selectionRange.start.column == 5)
        let identifiers = collectIDs(result.outline)
        #expect(Set(identifiers).count == identifiers.count)
    }

    /// The identifiers of every node of an outline.
    ///
    /// - Parameter nodes: The nodes.
    /// - Returns: The identifiers in depth-first order.
    func collectIDs(_ nodes: [OutlineNode]) -> [String] {
        nodes.flatMap { [$0.id] + collectIDs($0.children) }
    }
}
