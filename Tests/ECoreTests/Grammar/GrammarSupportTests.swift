//
// GrammarSupportTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

@Suite("Source scanner")
struct SourceScannerTests {
    @Test("Identifiers, escaped identifiers and identifiers with extra characters")
    func identifiers() throws {
        var scanner = SourceScanner("^grammar STRING-CHAR x1")
        let maybeEscaped = scanner.scanIdentifier(escape: UInt8(ascii: "^"))
        let escaped = try #require(maybeEscaped)
        #expect(escaped.text == "^grammar" && escaped.value == "grammar")
        scanner.skipWhitespace()
        let maybeHyphenated = scanner.scanIdentifier(extraParts: [UInt8(ascii: "-")])
        let hyphenated = try #require(maybeHyphenated)
        #expect(hyphenated.value == "STRING-CHAR")
        scanner.skipWhitespace()
        #expect(scanner.scanIdentifier()?.value == "x1")
        #expect(scanner.isAtEnd && scanner.scanIdentifier() == nil)
    }

    @Test("A hyphen not followed by an identifier character ends the identifier")
    func trailingHyphen() {
        var scanner = SourceScanner("Exp-")
        #expect(scanner.scanIdentifier(extraParts: [UInt8(ascii: "-")])?.value == "Exp")
    }

    @Test("Strings decode escapes and report a missing quote")
    func strings() {
        var scanner = SourceScanner(#""a\"b\nA\q" 'open"#)
        let string = scanner.scanString()
        #expect(string.value == "a\"b\nAq" && string.isTerminated)
        scanner.skipWhitespace()
        let open = scanner.scanString()
        #expect(!open.isTerminated && open.value == "open")
    }

    @Test("Numbers with fractions and exponents")
    func numbers() {
        var scanner = SourceScanner("12.5e-3 7.")
        #expect(scanner.scanNumber()?.text == "12.5e-3")
        scanner.skipWhitespace()
        #expect(scanner.scanNumber()?.text == "7")
    }

    @Test("Comments, documentation comments and unterminated comments")
    func comments() {
        var scanner = SourceScanner("/** doc */ /**/ // line\n/* open")
        #expect(scanner.scanBlockComment().kind == .documentation)
        scanner.skipWhitespace()
        #expect(scanner.scanBlockComment().kind == .comment)
        scanner.skipWhitespace()
        #expect(scanner.scanLineComment().text == "// line")
        scanner.skipWhitespace()
        #expect(!scanner.scanBlockComment().isTerminated)
    }

    @Test("Punctuation takes the longest match, and invalid tokens cover a whole character")
    func punctuation() {
        var scanner = SourceScanner("+=+é")
        #expect(scanner.scanPunctuation(["+", "+="])?.text == "+=")
        #expect(scanner.scanPunctuation(["+", "+="])?.text == "+")
        #expect(scanner.scanPunctuation(["+"]) == nil)
        let invalid = scanner.scanInvalid()
        #expect(invalid.kind == .invalid && invalid.range.utf8Length == 2 && invalid.range.start.column == 4)
    }

    @Test("Ranges count lines and columns from one")
    func ranges() {
        var scanner = SourceScanner("a\r\n  b")
        _ = scanner.scanIdentifier()
        scanner.skipWhitespace()
        let token = scanner.scanIdentifier()
        #expect(token?.range.start.line == 2 && token?.range.start.column == 3)
        #expect(scanner.endRange.start.utf8Offset == 6)
    }
}

@Suite("Token cursor and diagnostics")
struct TokenCursorTests {
    /// Tokens of a small text.
    func tokens(_ text: String) -> (tokens: [ScannedToken], end: SourceRange) {
        var scanner = SourceScanner(text)
        var result: [ScannedToken] = []
        while true {
            scanner.skipWhitespace()
            if scanner.isAtEnd { break }
            if scanner.hasPrefix("//") { result.append(scanner.scanLineComment()); continue }
            if let identifier = scanner.scanIdentifier() { result.append(identifier); continue }
            result.append(scanner.scanPunctuation([";", "="]) ?? scanner.scanInvalid())
        }
        return (result, scanner.endRange)
    }

    @Test("The cursor skips comments and stops safely at the end")
    func cursor() {
        let (all, end) = tokens("a // c\n= b;")
        var cursor = GrammarTokenCursor(all, endRange: end)
        #expect(cursor.tokens.count == 4)
        #expect(cursor.accept(.identifier)?.text == "a")
        #expect(cursor.accept("=") != nil)
        #expect(cursor.accept("=") == nil && cursor.check("b"))
        let start = cursor.currentRange
        cursor.advance()
        cursor.advance()
        #expect(cursor.range(from: start).utf8Length == 2)
        #expect(cursor.isAtEnd && cursor.advance() == nil && cursor.currentRange == end)
    }

    @Test("Skipping stops at a synchronisation symbol")
    func skip() {
        let (all, end) = tokens("x y ; z")
        var cursor = GrammarTokenCursor(all, endRange: end)
        cursor.skip(until: [";"])
        #expect(cursor.check(";"))
    }

    @Test("Diagnostics are sorted by position with document-wide ones last")
    func sorting() {
        var collector = DiagnosticCollector(document: "doc")
        let range = { (offset: Int) in
            SourceRange(
                start: SourcePosition(utf8Offset: offset, line: 1, column: offset + 1),
                end: SourcePosition(utf8Offset: offset, line: 1, column: offset + 1))
        }
        collector.warning("w", "late", at: range(5))
        collector.error("e", "whole", at: nil)
        collector.information("i", "early", at: range(1))
        collector.error("e2", "same", at: range(5))
        #expect(collector.sorted.map(\.message) == ["early", "late", "same", "whole"])
        #expect(collector.sorted.allSatisfy { $0.document == "doc" })
    }
}

@Suite("Grammar naming")
struct GrammarNamingTests {
    @Test("Identifiers, case conversion and generated field names")
    func names() {
        #expect(GrammarNaming.identifier("STRING-CHAR") == "STRING_CHAR")
        #expect(GrammarNaming.identifier("1st") == "_1st")
        #expect(GrammarNaming.identifier("") == "_")
        #expect(GrammarNaming.lowerFirst("ID") == "id")
        #expect(GrammarNaming.lowerFirst("URLPath") == "urlPath")
        #expect(GrammarNaming.lowerFirst("Exp") == "exp")
        #expect(GrammarNaming.lowerFirst("exp") == "exp")
        #expect(GrammarNaming.lowerFirst("STRING_CHAR") == "string_char")
        #expect(GrammarNaming.upperFirst("exp") == "Exp")
        #expect(GrammarNaming.fieldNames([("stm", nil), ("stm", nil), ("identifier", "stm1"), ("Exp", nil)])
            == ["stm2", "stm3", "stm1", "exp1"])
    }

    @Test("Package names and namespace defaults")
    func packageNames() {
        #expect(GrammarNaming.packageName(declared: "Decl", option: "Opt", sourceName: "a/b.x") == "Decl")
        #expect(GrammarNaming.packageName(declared: nil, option: "Opt", sourceName: "a/b.x") == "Opt")
        #expect(GrammarNaming.packageName(declared: "", option: nil, sourceName: "dir\\my-lang.asdl") == "my_lang")
        #expect(GrammarNaming.packageName(declared: nil, option: nil, sourceName: nil) == "model")
        #expect(GrammarNaming.defaultNsURI(notation: "sdf3", packageName: "Calc") == "urn:sdf3:Calc")
        #expect(GrammarNaming.defaultNsPrefix(packageName: "XmlTools") == "_xmltools")
        #expect(GrammarNaming.defaultNsPrefix(packageName: "Calc") == "calc")
    }
}

@Suite("Metamodel assembler")
struct MetamodelAssemblerTests {
    @Test("Drafts become linked packages whose classes refer to each other")
    func assemble() throws {
        let draft = GrammarDraftPackage(name: "p", nsURI: "urn:p", nsPrefix: "p", classifiers: [
            .eClass(GrammarDraftClass(name: "Node", isAbstract: true, features: [
                GrammarDraftFeature(name: "parent", type: .named("Node"), isContainment: false),
            ])),
            .eClass(GrammarDraftClass(name: "Leaf", superTypes: [.named("Node")], features: [
                GrammarDraftFeature(name: "kind", type: .named("Kind")),
                GrammarDraftFeature(name: "text", type: .ecore(.eString), lowerBound: 1, defaultValueLiteral: "x",
                    annotations: [GrammarDraftAnnotation(source: "urn:a", details: [GrammarDraftDetail("k", "v")])]),
                GrammarDraftFeature(name: "any", type: .eObject, upperBound: -1),
            ])),
            .eEnum(GrammarDraftEnum(name: "Kind", literals: [GrammarDraftLiteral(name: "A"), GrammarDraftLiteral(name: "B", literal: "b")])),
            .dataType(GrammarDraftDataType(name: "Name", instanceClassName: "java.lang.String")),
        ])
        let (packages, diagnostics) = GrammarMetamodelAssembler(codePrefix: "t", document: nil).assemble([draft])
        #expect(diagnostics.isEmpty)
        let package = try #require(packages.first)
        let leaf = try #require(package.getEClass("Leaf"))
        #expect(leaf.eSuperTypes.first?.eStructuralFeatures.map(\.name) == ["parent"])
        #expect(leaf.eAllStructuralFeatures.map(\.name) == ["parent", "kind", "text", "any"])
        #expect((leaf.getStructuralFeature(name: "kind") as? EAttribute)?.eType is EEnum)
        #expect((leaf.getStructuralFeature(name: "any") as? EReference)?.containment == true)
        #expect((leaf.getStructuralFeature(name: "text") as? EAttribute)?.defaultValueLiteral == "x")
        #expect(EcoreValidator().validate(MetamodelIndex(roots: packages)).filter { $0.severity == .error }.isEmpty)
        #expect(GrammarMetamodelDescription.describe(packages) == """
            package p urn:p p
              abstract class Node
                refers parent : Node[0..1]
              class Leaf extends Node
                attribute kind : Kind[0..1]
                attribute text : EString[1..1] = x
                  @urn:a k=v
                contains any : EObject[0..*]
              enum Kind { A, B='b' }
              datatype Name : java.lang.String
            """)
    }

    @Test("Duplicates, unresolved types, invalid supertypes and cycles are reported")
    func problems() throws {
        let draft = GrammarDraftPackage(name: "p", nsURI: "urn:p", nsPrefix: "p", classifiers: [
            .eClass(GrammarDraftClass(name: "A", superTypes: [.named("B"), .named("D"), .named("Missing")], features: [
                GrammarDraftFeature(name: "x", type: .named("Nowhere")),
                GrammarDraftFeature(name: "x", type: .ecore(.eInt)),
            ])),
            .eClass(GrammarDraftClass(name: "B", superTypes: [.named("A")])),
            .eClass(GrammarDraftClass(name: "A")),
            .dataType(GrammarDraftDataType(name: "D")),
        ])
        let (packages, diagnostics) = GrammarMetamodelAssembler(codePrefix: "t", document: "d").assemble([draft])
        let codes = diagnostics.map(\.code).sorted()
        #expect(codes == [
            "t.duplicateClassifier", "t.duplicateFeature", "t.invalidSupertype", "t.invalidSupertype",
            "t.unresolvedType", "t.unresolvedType",
        ])
        let package = try #require(packages.first)
        #expect(package.eClassifiers.map(\.name) == ["A", "B", "D"])
        #expect(EcoreValidator().validate(MetamodelIndex(roots: packages)).filter { $0.severity == .error }.isEmpty)
    }

    @Test("Packages refer to each other's classifiers by package name")
    func crossPackage() throws {
        let base = GrammarDraftPackage(name: "base", nsURI: "urn:b", nsPrefix: "b", classifiers: [.eClass(GrammarDraftClass(name: "Thing"))])
        let user = GrammarDraftPackage(name: "user", nsURI: "urn:u", nsPrefix: "u", classifiers: [
            .eClass(GrammarDraftClass(name: "Special", superTypes: [.named("Thing", package: "base")], features: [
                GrammarDraftFeature(name: "other", type: .named("Thing")),
            ])),
        ])
        let (packages, diagnostics) = GrammarMetamodelAssembler(codePrefix: "t", document: nil).assemble([base, user])
        #expect(diagnostics.isEmpty)
        let special = try #require(packages[1].getEClass("Special"))
        #expect(special.eSuperTypes.map(\.name) == ["Thing"])
        #expect(special.eSuperTypes.first?.id == packages[0].getEClass("Thing")?.id)
    }
}
