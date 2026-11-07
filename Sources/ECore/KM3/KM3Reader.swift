//
// KM3Reader.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// The options that control how KM3 text is read.
public struct KM3ReadOptions: Sendable, Hashable {
    /// How declared data types are treated.
    public var primitiveTypes: KM3PrimitiveTypeMapping

    /// Creates options.
    ///
    /// - Parameter primitiveTypes: How declared data types are treated; by default, the
    ///   primitive types stand for the built-in Ecore data types.
    public init(primitiveTypes: KM3PrimitiveTypeMapping = .ecore) {
        self.primitiveTypes = primitiveTypes
    }

    /// The default options, which map primitive types to the built-in Ecore data types.
    public static let standard = KM3ReadOptions()

    /// The options that reproduce the KM32EMF transformation of the ATL tool chain, which
    /// keeps every declared data type.
    public static let declaredDataTypes = KM3ReadOptions(primitiveTypes: .declared)
}

/// The result of reading KM3 text while collecting diagnostics.
///
/// Reading recovers from errors, so the packages hold every declaration that was read
/// correctly, and the diagnostics describe each problem.
public struct KM3ParseResult: Sendable {
    /// The root packages of the document, in source order.
    public var packages: [EPackage]

    /// The problems found, in source order.
    public var diagnostics: [SourceDiagnostic]

    /// The lexical tokens of the text, including comments.
    public var tokens: [SourceToken]

    /// The outline of the text: one node per root package.
    public var outline: [OutlineNode]

    /// Creates a parse result.
    ///
    /// - Parameters:
    ///   - packages: The root packages.
    ///   - diagnostics: The problems found.
    ///   - tokens: The lexical tokens of the text.
    ///   - outline: The outline of the text.
    public init(
        packages: [EPackage], diagnostics: [SourceDiagnostic], tokens: [SourceToken], outline: [OutlineNode]
    ) {
        self.packages = packages
        self.diagnostics = diagnostics
        self.tokens = tokens
        self.outline = outline
    }

    /// Whether any diagnostic is an error.
    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}

/// Reads KM3 (Kernel MetaMetaModel) text into native Ecore packages.
///
/// KM3 is the textual metamodel language of the ATL tool chain. Each `package` of a
/// document becomes a root ``EPackage``; `-- @nsURI` and `-- @nsPrefix` directives in the
/// comments before a package give its namespace URI and prefix, which are otherwise empty.
/// Other directives, such as `-- @name` or `-- @begin`, are ignored.
///
/// | KM3 | Ecore |
/// | :-- | :-- |
/// | `package` | ``EPackage``; a nested package is a subpackage |
/// | `class`, `abstract`, `extends` | ``EClass`` with ``EClass/isAbstract`` and ``EClass/eSuperTypes`` |
/// | `attribute` of a data type or enumeration | ``EAttribute`` |
/// | `attribute` of a class | containment ``EReference`` |
/// | `reference`, `container`, `oppositeOf` | ``EReference`` with ``EReference/containment`` and ``EReference/opposite`` |
/// | no multiplicity, `[n-m]`, `[n-*]`, `[*]` | bounds `1..1`, `n..m`, `n..-1`, `0..-1` |
/// | `ordered`, `unique` | ``EAttribute/ordered``, ``EAttribute/unique``; both are `false` unless written |
/// | `datatype` | ``EDataType``, or a built-in Ecore data type (see ``KM3PrimitiveTypeMapping``) |
/// | `enumeration`, `literal` | ``EEnum`` whose literals are numbered from one, as KM32EMF numbers them |
/// | `operation` with parameters | ``EOperation`` with ``EParameter`` values |
///
/// References are unique, as Ecore makes them by default, because KM3 cannot say otherwise.
/// Operations and parameters keep the Ecore defaults for their bounds and flags. `subsets`
/// has no counterpart in Ecore and is reported and ignored.
public enum KM3Reader {
    /// Reads KM3 text with the default options.
    ///
    /// Reading never throws: every problem becomes a diagnostic with a source range, and
    /// reading carries on after it.
    ///
    /// - Parameters:
    ///   - text: The KM3 text.
    ///   - sourceName: The name of the document, such as its URI, which diagnostics carry.
    /// - Returns: The packages, diagnostics, tokens and outline of the text.
    public static func parse(_ text: String, sourceName: String? = nil) -> KM3ParseResult {
        parse(text, sourceName: sourceName, options: .standard)
    }

    /// Reads KM3 text with the given options.
    ///
    /// Reading never throws: every problem becomes a diagnostic with a source range, and
    /// reading carries on after it.
    ///
    /// - Parameters:
    ///   - text: The KM3 text.
    ///   - sourceName: The name of the document, such as its URI, which diagnostics carry.
    ///   - options: How the text is read.
    /// - Returns: The packages, diagnostics, tokens and outline of the text.
    public static func parse(_ text: String, sourceName: String?, options: KM3ReadOptions) -> KM3ParseResult {
        var lexer = KM3Lexer(text, document: sourceName)
        let scan = lexer.scanAll()
        var parser = KM3Parser(scan: scan, document: sourceName)
        let syntax = parser.parseDocument()
        var builder = KM3Builder(mapping: options.primitiveTypes, document: sourceName)
        let packages = builder.build(syntax)
        let diagnostics = (scan.diagnostics + parser.diagnostics + builder.diagnostics).enumerated().sorted {
            let first = $0.element.range?.start.utf8Offset ?? 0
            let second = $1.element.range?.start.utf8Offset ?? 0
            return first == second ? $0.offset < $1.offset : first < second
        }.map(\.element)
        return KM3ParseResult(
            packages: packages, diagnostics: diagnostics, tokens: KM3Syntax.sourceTokens(of: scan),
            outline: KM3Outline.nodes(for: syntax))
    }
}
