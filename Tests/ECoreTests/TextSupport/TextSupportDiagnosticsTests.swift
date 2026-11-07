//
// TextSupportDiagnosticsTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore




/// Creates a range that starts at the given byte offset on the first line.
private func range(at offset: Int) -> SourceRange {
    let position = SourcePosition(utf8Offset: offset, line: 1, column: offset + 1)
    return SourceRange(start: position, end: position)
}

/// Tests for diagnostic creation and ordering.
@Suite("Text diagnostics")
struct DiagnosticsTests {
    /// Codes join the namespace and the kind's raw value.
    @Test func codesCombineNamespaceAndKind() {
        let factory = DiagnosticFactory(namespace: "shop")
        for kind in TextDiagnosticKind.allCases {
            #expect(factory.code(kind) == "shop." + kind.rawValue)
            #expect(DiagnosticFactory.code(kind, namespace: "till") == "till." + kind.rawValue)
        }
    }

    /// Errors and warnings carry the severity, code, message, range and document.
    @Test func createsErrorsAndWarnings() {
        let factory = DiagnosticFactory(namespace: "shop", document: "stock.txt")
        let error = factory.error(.duplicateName, "Duplicate", at: range(at: 4))
        #expect(error.severity == .error)
        #expect(error.code == "shop.duplicateName")
        #expect(error.message == "Duplicate")
        #expect(error.range == range(at: 4))
        #expect(error.document == "stock.txt")
        let warning = factory.warning(.lossyWrite, "Lossy", at: nil)
        #expect(warning.severity == .warning)
        #expect(warning.range == nil)
    }

    /// A document is optional.
    @Test func documentDefaultsToNil() {
        #expect(DiagnosticFactory(namespace: "x").error(.missingPackage, "m", at: nil).document == nil)
    }

    /// Lexical problems become errors with the problem's kind and range.
    @Test func convertsLexicalProblems() {
        let factory = DiagnosticFactory(namespace: "shop")
        let problem = LexicalProblem(kind: .invalidNumber, message: "Bad", range: range(at: 2))
        let diagnostic = factory.diagnostic(for: problem)
        #expect(diagnostic.code == "shop.invalidNumber")
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.range == range(at: 2))
    }

    /// Sorting orders by offset, keeps the original order for ties and puts missing ranges last.
    @Test func sortsInSourceOrderStably() {
        let factory = DiagnosticFactory(namespace: "shop")
        let diagnostics = [
            factory.error(.unexpectedToken, "none", at: nil),
            factory.error(.unexpectedToken, "late", at: range(at: 9)),
            factory.error(.unexpectedToken, "tie one", at: range(at: 3)),
            factory.error(.unexpectedToken, "early", at: range(at: 1)),
            factory.error(.unexpectedToken, "tie two", at: range(at: 3)),
            factory.error(.unexpectedToken, "second none", at: nil),
        ]
        #expect(
            SourceOrder.sorted(diagnostics).map(\.message)
                == ["early", "tie one", "tie two", "late", "none", "second none"])
        #expect(SourceOrder.sorted([]).isEmpty)
    }
}
