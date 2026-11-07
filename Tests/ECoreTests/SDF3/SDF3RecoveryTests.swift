//
// SDF3RecoveryTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// Tests that malformed input is reported at the right place and that reading recovers.
@Suite("SDF3 recovery")
struct SDF3RecoveryTests {
    /// The line and column at which a diagnostic starts.
    ///
    /// - Parameter diagnostic: The diagnostic.
    /// - Returns: The one-based line and column, or `nil` without a range.
    private func position(_ diagnostic: SourceDiagnostic?) -> [Int]? {
        diagnostic?.range.map { [$0.start.line, $0.start.column] }
    }

    /// A production without `=` is reported, and the next production is read.
    @Test func missingEquals() throws {
        let result = read("""
            module Broken
            context-free syntax
              Exp.Add <<Exp> + <Exp>>
              Exp.Zero = "0"
            """)
        let error = try #require(result.diagnostics(.expectedToken).first)
        #expect(error.severity == .error)
        #expect(position(error) == [3, 11])
        #expect(error.document == "test.sdf3")
        #expect(result.eClass("Zero") != nil)
        #expect(result.eClass("Add") == nil)
    }

    /// A missing constructor name after `.` is reported.
    @Test func missingConstructorName() throws {
        let result = read("module Broken\ncontext-free syntax\n  Exp. = <x>\n  Exp.Zero = \"0\"")
        #expect(position(result.diagnostics(.expectedToken).first) == [3, 8])
        #expect(result.eClass("Zero") != nil)
    }

    /// A template without its closing delimiter is reported at its opening one.
    @Test func unterminatedTemplate() throws {
        let result = read("module Broken\ncontext-free syntax\n  Exp.Zero = \"0\"\n  Exp.Neg = <-<Exp>")
        #expect(position(result.diagnostics(.unterminatedTemplate).first) == [4, 13])
        #expect(result.eClass("Neg")?.featureNames == ["exp1"])
        #expect(result.eClass("Zero") != nil)
    }

    /// A placeholder without its closing delimiter is reported at its opening one.
    @Test func unterminatedPlaceholder() throws {
        let result = read("module Broken\ncontext-free syntax\n  Exp.Neg = <-<Exp")
        #expect(position(result.diagnostics(.unterminatedPlaceholder).first) == [3, 15])
        #expect(position(result.diagnostics(.unterminatedTemplate).first) == [3, 13])
    }

    /// Unexpected tokens inside a placeholder are reported once.
    @Test func unexpectedInPlaceholder() throws {
        let result = read("module Broken\ncontext-free syntax\n  Exp.Paren = <(<Exp)>)>")
        #expect(result.diagnostics(.unexpectedToken).count == 1)
        #expect(position(result.diagnostics(.unexpectedToken).first) == [3, 21])
        #expect(result.eClass("Paren")?.featureNames == ["exp1"])
    }

    /// Lexical problems are reported with their positions.
    @Test func lexicalProblems() throws {
        let result = read("""
            module Broken
            context-free syntax
              Exp.Str = "abc
              Exp.Mod = Exp % Exp
            lexical syntax
              ID = [a-z
            /* not closed
            """)
        #expect(position(result.diagnostics(.unterminatedString).first) == [3, 13])
        #expect(position(result.diagnostics(.invalidCharacter).first) == [4, 17])
        #expect(position(result.diagnostics(.unterminatedCharacterClass).first) == [6, 8])
        #expect(position(result.diagnostics(.unterminatedComment).first) == [7, 1])
        #expect(result.eClass("Mod")?.featureNames == ["exp1", "exp2"])
    }

    /// Text before any section is reported, and the following sections are read.
    @Test func statementOutsideSection() throws {
        let result = read("Exp.Add = Exp \"+\" Exp\ncontext-free syntax\n  Exp.Zero = \"0\"")
        #expect(position(result.diagnostics(.unexpectedToken).first) == [1, 1])
        #expect(result.eClass("Zero") != nil)
        #expect(result.eClass("Add") == nil)
    }

    /// A malformed signature entry is reported, and the next entry is read.
    @Test func malformedSignatureEntry() throws {
        let result = read("""
            module broken
            signature constructors
              Add : -> Exp
              Mul : Exp * Exp Exp
              Zero : Exp
            """)
        let errors = result.diagnostics(.expectedToken)
        #expect(errors.map(position) == [[3, 9], [4, 19]])
        #expect(result.eClass("Zero") != nil)
        #expect(result.eClass("Add") == nil)
    }

    /// Diagnostics are ordered by their position.
    @Test func diagnosticsAreSorted() throws {
        let result = read("module Broken\ncontext-free syntax\n  Exp.Neg = <-<Exp>\n  Exp.Add <<Exp>>\n  Stat.Do = <<Undefined>>")
        let offsets = result.diagnostics.compactMap { $0.range?.start.utf8Offset }
        #expect(offsets == offsets.sorted())
        #expect(!result.diagnostics.isEmpty)
    }

    /// Empty input yields an empty package without diagnostics.
    @Test func emptyInput() throws {
        let result = SDF3Reader.parse("")
        #expect(result.packages.count == 1)
        #expect(result.package.eClassifiers.isEmpty)
        #expect(result.diagnostics.isEmpty)
        #expect(result.tokens.isEmpty)
        #expect(result.outline.isEmpty)
    }
}
