//
// LangiumSyntaxTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests of Langium syntax, recovery and corpus.
@Suite("Langium syntax, recovery and corpus")
struct LangiumSyntaxTests {
    /// Checks that malformed declarations are reported at their positions and the rest still imports.
    @Test("Malformed declarations are reported at their positions and the rest still imports")
    func recovery() throws {
        let text = """
            grammar Broken
            entry Model: items+=Item*;
            Item: 'item' name=ID
            Other: 'other' value= ;
            interface Bad { name string }
            terminal ID: /[a-z]+;
            """
        let result = LangiumReader.parse(text, sourceName: "broken.langium")
        let errors = result.diagnostics.filter { $0.severity == .error }
        let positions = errors.map { "\($0.code)@\($0.range!.start.line):\($0.range!.start.column)" }
        #expect(positions == [
            "langium.unexpectedToken@4:1",
            "langium.unexpectedToken@4:23",
            "langium.unexpectedToken@5:22",
            "langium.unterminatedRegex@6:14",
        ])
        let package = try #require(result.packages.first)
        #expect(Set(package.eClassifiers.map(\.name)) == ["Model", "Item", "Other", "Bad"])
        #expect(LangiumInspect.featureNames(package.getEClass("Item")) == ["name"])
    }

    /// Checks that tokens classify keywords, type names, regular expressions and comments.
    @Test("Tokens classify keywords, type names, regular expressions and comments")
    func tokens() throws {
        let text = """
            // Types
            interface Person { friend?: @Person }
            terminal ID: /[a-z]+/i;
            """
        let result = LangiumReader.parse(text)
        let lines = LineTable(text)
        func kind(at line: Int, _ column: Int) -> SourceTokenKind? {
            let offset = lines.utf8Offset(line: line, column: column)
            return result.tokens.first { $0.range.start.utf8Offset == offset }?.kind
        }
        #expect(kind(at: 1, 1) == .comment)
        #expect(kind(at: 2, 1) == .keyword)
        #expect(kind(at: 2, 11) == .typeName)
        #expect(kind(at: 2, 29) == .punctuation)
        #expect(kind(at: 2, 30) == .typeName)
        #expect(kind(at: 3, 14) == .string)
        #expect(result.tokens.first { $0.range.start.line == 3 && $0.range.start.column == 14 }?.range.end.column == 23)
        #expect(LangiumSyntax.tokens(in: text).count == result.tokens.count)
    }

    /// Checks that the outline lists imports, declared types with their properties, and rules.
    @Test("The outline lists imports, declared types with their properties, and rules")
    func outline() throws {
        let result = LangiumReader.parse("""
            grammar Outline
            import './common';
            interface Person { name: string; age?: number }
            type Named = Person;
            entry Model: people+=Person*;
            fragment Tagged: tags+=ID*;
            infix Binary on Primary: '+';
            Primary: value=ID;
            terminal ID: /[a-z]+/;
            """)
        let grammar = try #require(result.outline.first)
        #expect(grammar.kind == LangiumOutlineKind.grammar && grammar.name == "Outline")
        #expect(grammar.children.map(\.kind) == [
            LangiumOutlineKind.import, LangiumOutlineKind.interface, LangiumOutlineKind.type,
            LangiumOutlineKind.parserRule, LangiumOutlineKind.fragment, LangiumOutlineKind.infixRule,
            LangiumOutlineKind.parserRule, LangiumOutlineKind.terminalRule,
        ])
        #expect(grammar.children[1].children.map(\.name) == ["name", "age"])
        #expect(grammar.children[1].children.allSatisfy { $0.kind == LangiumOutlineKind.attribute })
    }

    /// Checks that grammars of a reference corpus import without validation errors.
    @Test(
        "Grammars of a reference corpus import without validation errors",
        .enabled(if: ProcessInfo.processInfo.environment["LANGIUM_REFERENCE_DIR"] != nil))
    func corpus() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["LANGIUM_REFERENCE_DIR"])
        let root = URL(fileURLWithPath: directory)
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if url.pathExtension == "langium" && isFile == true { files.append(url) }
        }
        files.sort { $0.path < $1.path }
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let result = LangiumReader.parse(text, sourceName: file.lastPathComponent)
            let classifiers = result.packages.flatMap(\.eClassifiers)
            let classes = classifiers.compactMap { $0 as? EClass }
            let bySeverity = Dictionary(grouping: result.diagnostics, by: \.severity).mapValues(\.count)
            let codes = Dictionary(grouping: result.diagnostics, by: \.code).mapValues(\.count)
                .sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            print(
                "LANGIUM \(file.lastPathComponent): classes=\(classes.count) abstract=\(classes.filter(\.isAbstract).count)"
                    + " enums=\(classifiers.filter { $0 is EEnum }.count)"
                    + " dataTypes=\(classifiers.filter { $0 is EDataType && !($0 is EEnum) }.count)"
                    + " errors=\(bySeverity[.error] ?? 0) warnings=\(bySeverity[.warning] ?? 0)"
                    + " information=\(bySeverity[.information] ?? 0) [\(codes)]")
            let validation = LangiumInspect.validationErrors(result.packages)
            #expect(validation.isEmpty, "\(file.lastPathComponent): \(validation)")
        }
    }
}
