//
// XtextSyntaxTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests of Xtext syntax, recovery and corpus.
@Suite("Xtext syntax, recovery and corpus")
struct XtextSyntaxTests {
    /// Checks that malformed rules are reported at their positions and later rules still import.
    @Test("Malformed rules are reported at their positions and later rules still import")
    func recovery() throws {
        let text = """
            grammar org.example.Broken with org.eclipse.xtext.common.Terminals
            generate broken "http://www.example.org/broken"
            A: 'a' name= ;
            B: 'b' value=INT
            C: 'c' text=STRING;
            D: 'd' 'unterminated;
            """
        let result = XtextReader.parse(text, sourceName: "broken.xtext")
        let errors = result.diagnostics.filter { $0.severity == .error }
        let positions = errors.map { "\($0.code)@\($0.range!.start.line):\($0.range!.start.column)" }
        #expect(positions == [
            "xtext.unexpectedToken@3:14",
            "xtext.unexpectedToken@5:1",
            "xtext.unterminatedString@6:8",
            "xtext.unexpectedToken@6:22",
        ])
        #expect(errors.allSatisfy { $0.document == "broken.xtext" })
        let package = try #require(result.packages.first)
        #expect(package.eClassifiers.map(\.name) == ["A", "B", "C"])
        #expect(XtextInspect.featureNames(package.getEClass("B")) == ["value"])
        #expect(XtextInspect.featureNames(package.getEClass("C")) == ["text"])
    }

    /// Checks that a missing grammar header is reported and the rules still import nothing.
    @Test("A missing grammar header is reported and the rules still import nothing")
    func missingHeader() {
        let result = XtextReader.parse("Model: name=ID;")
        #expect(result.diagnostics.first?.code == XtextDiagnosticCode.unexpectedToken.rawValue)
        #expect(result.diagnostics.first?.range?.start.column == 1)
        #expect(result.packages.isEmpty)
    }

    /// Checks that characters that start no token are reported.
    @Test("Characters that start no token are reported")
    func invalidCharacter() {
        let result = XtextReader.parse("""
            grammar g.G with org.eclipse.xtext.common.Terminals
            generate g "http://g"
            Model: name=ID $;
            """)
        let invalid = result.diagnostics.filter { $0.code == XtextDiagnosticCode.unexpectedCharacter.rawValue }
        #expect(invalid.map { $0.range?.start.column } == [16])
        #expect(result.tokens.contains { $0.kind == .invalid })
    }

    /// Checks that tokens classify keywords, type names, strings, operators and comments.
    @Test("Tokens classify keywords, type names, strings, operators and comments")
    func tokens() throws {
        let text = """
            // A comment
            grammar g.G with org.eclipse.xtext.common.Terminals
            generate g "http://g"
            /** Documented. */
            Model returns Root: name=ID;
            """
        let result = XtextReader.parse(text)
        let lines = LineTable(text)
        func kind(at line: Int, _ column: Int) -> SourceTokenKind? {
            let offset = lines.utf8Offset(line: line, column: column)
            return result.tokens.first { $0.range.start.utf8Offset == offset }?.kind
        }
        #expect(kind(at: 1, 1) == .comment)
        #expect(kind(at: 2, 1) == .keyword)
        #expect(kind(at: 3, 12) == .string)
        #expect(kind(at: 4, 1) == .documentation)
        #expect(kind(at: 5, 1) == .identifier)
        #expect(kind(at: 5, 15) == .typeName)
        #expect(kind(at: 5, 25) == .operator)
        let plain = XtextSyntax.tokens(in: text)
        #expect(plain.count == result.tokens.count)
        #expect(plain.first { $0.range.start.line == 5 && $0.range.start.column == 15 }?.kind == .identifier)
    }

    /// Checks that the outline lists the metamodel declarations and rules of the grammar.
    @Test("The outline lists the metamodel declarations and rules of the grammar")
    func outline() throws {
        let result = XtextReader.parse(XtextInferenceTests.arithmetic)
        let grammar = try #require(result.outline.first)
        #expect(grammar.kind == XtextOutlineKind.grammar && grammar.name == "org.example.Arith")
        #expect(grammar.children.map(\.kind) == [
            XtextOutlineKind.generate, XtextOutlineKind.parserRule, XtextOutlineKind.parserRule,
            XtextOutlineKind.parserRule, XtextOutlineKind.parserRule, XtextOutlineKind.parserRule,
            XtextOutlineKind.enumRule, XtextOutlineKind.enumRule,
        ])
        let addition = grammar.children[3]
        #expect(addition.name == "Addition" && addition.detail == "Expr")
        #expect(addition.selectionRange.start.line == 6 && addition.selectionRange.start.column == 1)
    }

    /// Checks that grammars of a reference corpus import without errors in the generated packages.
    @Test(
        "Grammars of a reference corpus import without errors in the generated packages",
        .enabled(if: ProcessInfo.processInfo.environment["XTEXT_REFERENCE_DIR"] != nil))
    func corpus() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["XTEXT_REFERENCE_DIR"])
        let root = URL(fileURLWithPath: directory)
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if url.pathExtension == "xtext" && isFile == true { files.append(url) }
        }
        files.sort { $0.path < $1.path }
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let result = XtextReader.parse(text, sourceName: file.lastPathComponent)
            let classes = result.packages.flatMap(\.eClassifiers).filter { $0 is EClass }.count
            let enums = result.packages.flatMap(\.eClassifiers).filter { $0 is EEnum }.count
            let bySeverity = Dictionary(grouping: result.diagnostics, by: \.severity).mapValues(\.count)
            let codes = Dictionary(grouping: result.diagnostics, by: \.code).mapValues(\.count)
                .sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            print(
                "XTEXT \(file.lastPathComponent): packages=\(result.packages.count) classes=\(classes) enums=\(enums)"
                    + " errors=\(bySeverity[.error] ?? 0) warnings=\(bySeverity[.warning] ?? 0)"
                    + " information=\(bySeverity[.information] ?? 0) [\(codes)]")
            let validation = XtextInspect.validationErrors(result.packages)
            #expect(validation.isEmpty, "\(file.lastPathComponent): \(validation)")
        }
    }
}
