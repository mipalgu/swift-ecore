//
// Diagnostics.swift
// EMFBase
//
// Copyright © 2025 Rene Hexel. All rights reserved.
//

/// How serious a diagnostic is.
///
/// Severities are ordered from least to most serious.
public enum DiagnosticSeverity: Int, Sendable, Hashable, Comparable, CaseIterable, Codable {
    /// Purely informational.
    case information = 0
    /// A likely problem that does not prevent use of the document.
    case warning = 1
    /// A definite problem.
    case error = 2

    /// Orders severities by seriousness.
    ///
    /// - Parameters:
    ///   - lhs: The first severity.
    ///   - rhs: The second severity.
    /// - Returns: `true` if `lhs` is less serious than `rhs`.
    public static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A message about a place in a document.
///
/// Diagnostics are produced by parsers and validators. The optional
/// `related` list carries secondary locations, such as the other declaration
/// in a duplicate-name error.
public struct SourceDiagnostic: Sendable, Hashable, Error, Codable {
    /// How serious the problem is.
    public var severity: DiagnosticSeverity

    /// A stable machine-readable identifier for the kind of problem.
    public var code: String

    /// A human-readable description.
    public var message: String

    /// The affected text, or `nil` if the diagnostic concerns the whole document.
    public var range: SourceRange?

    /// The identifier (for example a URI) of the document the range refers to.
    public var document: String?

    /// Secondary diagnostics that give context for this one.
    public var related: [SourceDiagnostic]

    /// Creates a diagnostic.
    ///
    /// - Parameters:
    ///   - severity: How serious the problem is.
    ///   - code: A stable identifier for the kind of problem.
    ///   - message: A human-readable description.
    ///   - range: The affected text, if any.
    ///   - document: The document the range refers to, if known.
    ///   - related: Secondary diagnostics giving context.
    public init(
        severity: DiagnosticSeverity,
        code: String,
        message: String,
        range: SourceRange? = nil,
        document: String? = nil,
        related: [SourceDiagnostic] = []
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.range = range
        self.document = document
        self.related = related
    }
}

/// The lexical category of a span of text, used for syntax highlighting.
public enum SourceTokenKind: String, Sendable, Hashable, CaseIterable, Codable {
    /// A reserved word.
    case keyword
    /// A name.
    case identifier
    /// A reference to a type.
    case typeName
    /// A string literal.
    case string
    /// A numeric literal.
    case number
    /// A boolean literal.
    case boolean
    /// An enumeration literal.
    case enumLiteral
    /// An ordinary comment.
    case comment
    /// A documentation comment.
    case documentation
    /// An operator.
    case `operator`
    /// Punctuation such as brackets and separators.
    case punctuation
    /// Free text, for example in a template body.
    case text
    /// A directive or annotation.
    case directive
    /// Text that could not be tokenised.
    case invalid
}

/// A classified span of text.
public struct SourceToken: Sendable, Hashable, Codable {
    /// The lexical category.
    public var kind: SourceTokenKind

    /// The text the token covers.
    public var range: SourceRange

    /// Creates a token.
    ///
    /// - Parameters:
    ///   - kind: The lexical category.
    ///   - range: The text the token covers.
    public init(kind: SourceTokenKind, range: SourceRange) {
        self.kind = kind
        self.range = range
    }
}

/// An entry in a document outline.
///
/// Outline nodes form a tree that editors present as a table of contents.
/// The `kind` is a language-specific label (for example a class or a rule)
/// that front ends map to icons.
public struct OutlineNode: Identifiable, Sendable, Hashable {
    /// A stable identifier, unique within the outline.
    public var id: String

    /// A language-specific category label.
    public var kind: String

    /// The display name.
    public var name: String

    /// Optional secondary text, such as a type or signature.
    public var detail: String?

    /// The full extent of the construct.
    public var range: SourceRange

    /// The part of the construct to select when navigating to it, typically its name.
    public var selectionRange: SourceRange

    /// Nested entries.
    public var children: [OutlineNode]

    /// Creates an outline node.
    ///
    /// - Parameters:
    ///   - id: A stable identifier, unique within the outline.
    ///   - kind: A language-specific category label.
    ///   - name: The display name.
    ///   - detail: Optional secondary text.
    ///   - range: The full extent of the construct.
    ///   - selectionRange: The part to select when navigating to it.
    ///   - children: Nested entries.
    public init(
        id: String,
        kind: String,
        name: String,
        detail: String? = nil,
        range: SourceRange,
        selectionRange: SourceRange,
        children: [OutlineNode] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.detail = detail
        self.range = range
        self.selectionRange = selectionRange
        self.children = children
    }
}
