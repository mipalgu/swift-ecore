//
// TextDiagnostics.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// The kinds of problem that reading or writing a textual metamodel notation reports.
///
/// The raw value is the format-independent part of a diagnostic code; each notation
/// prefixes it with its own namespace, such as `emfatic.` or `xcore.`.
enum TextDiagnosticKind: String, Sendable, Hashable, CaseIterable {
    /// A character cannot start any token.
    case unexpectedCharacter

    /// A string or character literal has no closing delimiter.
    case unterminatedString

    /// A block comment has no closing `*/`.
    case unterminatedComment

    /// A numeric literal cannot be read.
    case invalidNumber

    /// A token appears where the grammar does not allow it.
    case unexpectedToken

    /// The text holds no package declaration.
    case missingPackage

    /// A type name refers to no known classifier.
    case unresolvedType

    /// An opposite names no reference of the target class.
    case unresolvedOpposite

    /// A key names no attribute of the target class.
    case unresolvedKey

    /// An annotation names no known annotation source.
    case unresolvedAnnotation

    /// Two elements of the same container have the same name.
    case duplicateName

    /// A multiplicity is malformed or inconsistent.
    case invalidMultiplicity

    /// A construct is read but has no counterpart in the native metamodel.
    case unsupportedConstruct

    /// A body is kept as text but is never executed.
    case bodyNotExecuted

    /// Writing a metamodel loses information that the notation cannot express.
    case lossyWrite
}

/// Creates diagnostics with a code in the namespace of one textual notation.
struct DiagnosticFactory: Sendable {
    /// The namespace that prefixes every diagnostic code, such as `emfatic`.
    let namespace: String

    /// The name of the source document that diagnostics refer to, if any.
    let document: String?

    /// Creates a diagnostic factory.
    ///
    /// - Parameters:
    ///   - namespace: The namespace that prefixes every diagnostic code.
    ///   - document: The name of the source document, if any.
    init(namespace: String, document: String? = nil) {
        self.namespace = namespace
        self.document = document
    }

    /// The full diagnostic code for a kind of problem.
    ///
    /// - Parameter kind: The kind of problem.
    /// - Returns: The kind prefixed with the namespace and a full stop.
    func code(_ kind: TextDiagnosticKind) -> String {
        Self.code(kind, namespace: namespace)
    }

    /// The full diagnostic code for a kind of problem in a namespace.
    ///
    /// - Parameters:
    ///   - kind: The kind of problem.
    ///   - namespace: The namespace of the notation.
    /// - Returns: The kind prefixed with the namespace and a full stop.
    static func code(_ kind: TextDiagnosticKind, namespace: String) -> String {
        namespace + "." + kind.rawValue
    }

    /// Creates an error diagnostic.
    ///
    /// - Parameters:
    ///   - kind: The kind of problem.
    ///   - message: The message that describes the problem.
    ///   - range: The source range of the problem, if known.
    /// - Returns: The diagnostic.
    func error(_ kind: TextDiagnosticKind, _ message: String, at range: SourceRange?) -> SourceDiagnostic {
        SourceDiagnostic(severity: .error, code: code(kind), message: message, range: range, document: document)
    }

    /// Creates a warning diagnostic.
    ///
    /// - Parameters:
    ///   - kind: The kind of problem.
    ///   - message: The message that describes the problem.
    ///   - range: The source range of the problem, if known.
    /// - Returns: The diagnostic.
    func warning(_ kind: TextDiagnosticKind, _ message: String, at range: SourceRange?) -> SourceDiagnostic {
        SourceDiagnostic(severity: .warning, code: code(kind), message: message, range: range, document: document)
    }

    /// Converts a lexical problem into an error diagnostic.
    ///
    /// - Parameter problem: The problem found by the lexer.
    /// - Returns: The diagnostic.
    func diagnostic(for problem: LexicalProblem) -> SourceDiagnostic {
        error(problem.kind, problem.message, at: problem.range)
    }
}

/// Orders diagnostics by their position in the source.
enum SourceOrder {
    /// Sorts diagnostics by the start of their range, keeping the order of equal positions.
    ///
    /// Diagnostics without a range follow those with one.
    ///
    /// - Parameter diagnostics: The diagnostics to sort.
    /// - Returns: The diagnostics in source order.
    static func sorted(_ diagnostics: [SourceDiagnostic]) -> [SourceDiagnostic] {
        diagnostics.enumerated().sorted { left, right in
            let leftOffset = left.element.range?.start.utf8Offset ?? Int.max
            let rightOffset = right.element.range?.start.utf8Offset ?? Int.max
            return leftOffset == rightOffset ? left.offset < right.offset : leftOffset < rightOffset
        }.map(\.element)
    }
}
