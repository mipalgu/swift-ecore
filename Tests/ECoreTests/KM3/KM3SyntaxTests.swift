//
// KM3SyntaxTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@Suite("Tokens and outline")
struct KM3SyntaxTests {
    /// The text and kind of each token.
    ///
    /// - Parameter text: The KM3 text.
    /// - Returns: The pairs, in source order.
    func classified(_ text: String) -> [(String, SourceTokenKind)] {
        let bytes = Array(text.utf8)
        return KM3Syntax.tokens(in: text).map {
            (String(decoding: bytes[$0.range.start.utf8Offset..<$0.range.end.utf8Offset], as: UTF8.self), $0.kind)
        }
    }

    @Test("Tokens are classified for colouring")
    func classification() {
        let text = """
            -- @nsURI http://example.org/x
            -- a comment
            package P {
            \tabstract class C extends A, B {
            \t\tattribute "class"[0-*] ordered : String;
            \t\toperation f(a : T, b : U) : R;
            \t}
            \tenumeration E { literal one; }
            \tdatatype D;
            }
            """
        let tokens = classified(text)
        let expected: [(String, SourceTokenKind)] = [
            ("-- @nsURI http://example.org/x", .directive), ("-- a comment", .comment),
            ("package", .keyword), ("P", .identifier), ("{", .punctuation),
            ("abstract", .keyword), ("class", .keyword), ("C", .typeName), ("extends", .keyword),
            ("A", .typeName), (",", .punctuation), ("B", .typeName), ("{", .punctuation),
            ("attribute", .keyword), ("\"class\"", .identifier), ("[", .punctuation), ("0", .number),
            ("-", .operator), ("*", .operator), ("]", .punctuation), ("ordered", .keyword), (":", .punctuation),
            ("String", .typeName), (";", .punctuation),
            ("operation", .keyword), ("f", .identifier), ("(", .punctuation), ("a", .identifier),
            (":", .punctuation), ("T", .typeName), (",", .punctuation), ("b", .identifier), (":", .punctuation),
            ("U", .typeName), (")", .punctuation), (":", .punctuation), ("R", .typeName), (";", .punctuation),
            ("}", .punctuation),
            ("enumeration", .keyword), ("E", .typeName), ("{", .punctuation), ("literal", .keyword),
            ("one", .enumLiteral), (";", .punctuation), ("}", .punctuation),
            ("datatype", .keyword), ("D", .typeName), (";", .punctuation), ("}", .punctuation),
        ]
        #expect(tokens.count == expected.count)
        for (actual, wanted) in zip(tokens, expected) {
            #expect(actual.0 == wanted.0)
            #expect(actual.1 == wanted.1, "\(actual.0)")
        }
    }

    @Test("Unreadable text, strings and trailing comments are classified")
    func otherTokens() {
        let tokens = classified("package P { 'text' 1.5 $ } -- end")
        #expect(tokens.map(\.1) == [.keyword, .identifier, .punctuation, .string, .number, .invalid, .punctuation, .comment])
    }

    @Test("Escapes, compound symbols and unknown escapes are read")
    func lexicalDetails() {
        let tokens = classified(#"package P { 'it\'s' "a\qb" :: -> <- <= >= <> ! | # ? . / + = < > }"#)
        #expect(tokens.map(\.0) == [
            "package", "P", "{", #"'it\'s'"#, #""a\qb""#, "::", "->", "<-", "<=", ">=", "<>", "!", "|", "#", "?", ".",
            "/", "+", "=", "<", ">", "}",
        ])
        let parsed = KM3Reader.parse(#"package P { class "a\qb" {} }"#)
        #expect(parsed.packages.first?.eClassifiers.first?.name == "aqb")
        let trailing = KM3Reader.parse("package P { class \"x\\")
        #expect(trailing.diagnostics.contains { $0.code == KM3DiagnosticCode.unterminatedString.rawValue })
    }

    @Test("Token positions count lines, columns and UTF-8 offsets")
    func positions() throws {
        let tokens = KM3Syntax.tokens(in: "package É {\r\n\tclass Ü {}\r}")
        let name = try #require(tokens.first { $0.range.start.line == 2 && $0.kind == .typeName })
        #expect(name.range.start.column == 8)
        #expect(name.range.start.utf8Offset == 21)
        #expect(name.range.end.utf8Offset == 23)
        #expect(tokens.last?.range.start.line == 3)
    }

    @Test("The parse result carries the same tokens as the tokeniser")
    func resultTokens() {
        #expect(KM3Reader.parse(KM3Fixtures.library).tokens == KM3Syntax.tokens(in: KM3Fixtures.library))
    }

    @Test("KM3 documents are recognised")
    func sniffing() {
        #expect(KM3Syntax.looksLikeKM3(KM3Fixtures.library))
        #expect(KM3Syntax.looksLikeKM3("package \"x y\" {"))
        #expect(!KM3Syntax.looksLikeKM3("<?xml version=\"1.0\"?><ecore:EPackage/>"))
        #expect(!KM3Syntax.looksLikeKM3("{ \"eClass\": \"x\" }"))
        #expect(!KM3Syntax.looksLikeKM3("module M; create OUT : A from IN : B;"))
        #expect(!KM3Syntax.looksLikeKM3("package"))
        #expect(!KM3Syntax.looksLikeKM3(""))
    }

    @Test("The outline mirrors packages, classifiers and members")
    func outline() throws {
        let outline = KM3Reader.parse(KM3Fixtures.library).outline
        #expect(outline.map(\.id) == ["package:Library", "package:People", "package:PrimitiveTypes"])
        let library = try #require(outline.first)
        #expect(library.kind == KM3OutlineKind.package)
        #expect(library.detail == "http://example.org/library")
        #expect(library.children.map(\.kind) == [
            KM3OutlineKind.class, KM3OutlineKind.class, KM3OutlineKind.class, KM3OutlineKind.class,
            KM3OutlineKind.class, KM3OutlineKind.class, KM3OutlineKind.enumeration, KM3OutlineKind.dataType,
        ])
        let book = try #require(library.children.first { $0.name == "Book" })
        #expect(book.id == "package:Library/class:Book")
        #expect(book.detail == "extends NamedElement, Lendable")
        #expect(book.children.map(\.name) == [
            "isbn", "pages", "keywords", "genre", "price", "library", "authors", "class", "lend", "reset",
        ])
        let isbn = try #require(book.children.first)
        #expect(isbn.kind == KM3OutlineKind.attribute)
        #expect(isbn.id == "package:Library/class:Book/attribute:isbn")
        #expect(isbn.detail == "String[0-1]")
        #expect(isbn.selectionRange.start.column == 13)
        #expect(isbn.range.start.column == 3)
        let lend = try #require(book.children.first { $0.name == "lend" })
        #expect(lend.kind == KM3OutlineKind.operation)
        #expect(lend.detail == "(borrower : Member, days : Integer) : Boolean")
        #expect(book.children.first { $0.name == "library" }?.kind == KM3OutlineKind.reference)
        #expect(book.children.first { $0.name == "pages" }?.detail == "Integer")
        let genre = try #require(library.children.first { $0.name == "Genre" })
        #expect(genre.children.map(\.kind) == [KM3OutlineKind.literal, KM3OutlineKind.literal, KM3OutlineKind.literal])
        #expect(genre.children.last?.id == "package:Library/enumeration:Genre/literal:package")
        #expect(library.range.start.line == 5)
        #expect(library.selectionRange.start.column == 9)
    }

    @Test("Outline identifiers of same-named siblings are numbered")
    func duplicateIdentifiers() {
        let outline = KM3Reader.parse("package P { class A {} class A {} package Q { datatype D; } } package P {}").outline
        #expect(outline.map(\.id) == ["package:P", "package:P#2"])
        #expect(outline.first?.children.map(\.id) == ["package:P/class:A", "package:P/class:A#2", "package:P/package:Q"])
        #expect(outline.first?.children.last?.children.first?.id == "package:P/package:Q/datatype:D")
    }
}
