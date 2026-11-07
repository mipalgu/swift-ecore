//
// XcoreReader.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// The diagnostic codes that reading and writing Xcore report.
public enum XcoreDiagnosticCode: String, CaseIterable, Sendable {
    /// A character cannot start any token.
    case unexpectedCharacter = "xcore.unexpectedCharacter"
    /// A string literal has no closing delimiter.
    case unterminatedString = "xcore.unterminatedString"
    /// A block comment has no closing `*/`.
    case unterminatedComment = "xcore.unterminatedComment"
    /// A numeric literal cannot be read.
    case invalidNumber = "xcore.invalidNumber"
    /// A token appears where the grammar does not allow it.
    case unexpectedToken = "xcore.unexpectedToken"
    /// The text holds no package declaration.
    case missingPackage = "xcore.missingPackage"
    /// A type name refers to no known classifier.
    case unresolvedType = "xcore.unresolvedType"
    /// An opposite names no reference of the target class.
    case unresolvedOpposite = "xcore.unresolvedOpposite"
    /// A key names no attribute of the target class.
    case unresolvedKey = "xcore.unresolvedKey"
    /// An annotation names no declared alias.
    case unresolvedAnnotation = "xcore.unresolvedAnnotation"
    /// Two elements of the same container have the same name.
    case duplicateName = "xcore.duplicateName"
    /// A multiplicity is malformed or inconsistent.
    case invalidMultiplicity = "xcore.invalidMultiplicity"
    /// A construct is read but has no counterpart in the native metamodel, or is ignored.
    case unsupportedConstruct = "xcore.unsupportedConstruct"
    /// A body is kept as text but is never executed.
    case bodyNotExecuted = "xcore.bodyNotExecuted"
    /// Writing a metamodel loses information that Xcore cannot express.
    case lossyWrite = "xcore.lossyWrite"
}

/// The result of reading an Xcore document.
///
/// Reading never fails: whatever could be read is returned together with the diagnostics
/// that describe the rest.
public struct XcoreParseResult: Sendable {
    /// The packages declared by the document; an Xcore document declares one package.
    public var packages: [EPackage]

    /// The errors, warnings and information found while reading, in source order.
    public var diagnostics: [SourceDiagnostic]

    /// The classified tokens of the document, including comments, in source order.
    public var tokens: [SourceToken]

    /// The outline of the declarations of the document.
    public var outline: [OutlineNode]

    /// Creates a parse result.
    ///
    /// - Parameters:
    ///   - packages: The packages declared by the document.
    ///   - diagnostics: The diagnostics found while reading.
    ///   - tokens: The classified tokens of the document.
    ///   - outline: The outline of the document.
    public init(packages: [EPackage], diagnostics: [SourceDiagnostic], tokens: [SourceToken], outline: [OutlineNode]) {
        self.packages = packages
        self.diagnostics = diagnostics
        self.tokens = tokens
        self.outline = outline
    }

    /// Whether any diagnostic is an error.
    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}

/// Reads the structural subset of Xcore documents into native Ecore packages.
///
/// The reader covers the package declaration with `@Ecore(nsURI=..., nsPrefix=...)`,
/// imports, annotation directives (`annotation "uri" as Alias`), annotations with the
/// predefined aliases `Ecore`, `GenModel` and `ExtendedMetaData`, documentation comments,
/// classes and interfaces with type parameters, supertypes and wrapped instance types,
/// data types (`type X wraps T`), enumerations, attributes, references (`contains`,
/// `container`, `refers`) with opposites and keys, operations, modifiers, multiplicities
/// and generic types. It maps names as Xcore does: Java names such as `String` or `int`
/// stand for the Ecore data types, a qualified package name `a.b.c` gives a package `c`
/// with the GenModel base package `a.b`, and the details of `@Ecore` that name an
/// attribute of the element set that attribute.
///
/// Xbase bodies (operation bodies, feature accessors and the `create` and `convert`
/// bodies of data types) are not executed. Each is kept verbatim, braces included, in an
/// annotation with the source ``XcoreLanguage/namespaceURI`` and a key of
/// ``XcoreLanguage/BodyKey``, and reported with a warning.
public enum XcoreReader {
    /// Reads an Xcore document.
    ///
    /// - Parameters:
    ///   - text: The text of the document.
    ///   - sourceName: The name of the document that diagnostics refer to, if any.
    /// - Returns: The packages, diagnostics, tokens and outline of the document.
    public static func parse(_ text: String, sourceName: String? = nil) -> XcoreParseResult {
        let factory = DiagnosticFactory(namespace: XcoreLanguage.diagnosticNamespace, document: sourceName)
        let scan = TextLexer.scan(text, configuration: XcoreLanguage.lexicalConfiguration)
        var parser = XcoreParser(text: text, scan: scan, factory: factory)
        let document = parser.parseDocument()
        let wildcards = document.wildcards
        let external = ExternalTypeNames(aliases: document.imports) {
            XcoreLanguage.builtinClassifier($0, wildcards: wildcards)
        }
        let assembled = MetamodelAssembler.assemble(
            document.packages, factory: factory, external: external,
            unresolvedSeverity: document.externalImports.isEmpty ? .error : .warning)
        let lexical = scan.problems.filter { problem in
            !document.bodies.contains { $0.contains(problem.range) }
        }.map(factory.diagnostic(for:))
        return XcoreParseResult(
            packages: assembled.packages,
            diagnostics: SourceOrder.sorted(lexical + parser.diagnostics + assembled.diagnostics),
            tokens: XcoreSyntax.classifier.sourceTokens(of: scan, overrides: parser.tokenKinds),
            outline: OutlineBuilder.outline(of: document.packages))
    }
}

/// Lexical analysis of Xcore text for tools such as editors.
public enum XcoreSyntax {
    /// The token classifier of Xcore.
    static let classifier = TokenClassifier(
        keywords: XcoreLanguage.keywords, operators: XcoreLanguage.operators,
        typeNames: Set(XcoreLanguage.javaTypes.map(\.simple)))

    /// Splits Xcore text into classified tokens.
    ///
    /// The tokeniser never fails: text that cannot be read becomes a token of kind
    /// ``SourceTokenKind/invalid``. Comments are included and whitespace is not. The text
    /// is parsed as well, so that type names, annotation names and enumeration literals
    /// are classified by their role; the tokens of bodies are classified lexically.
    /// Positions count UTF-8 offsets, lines from one and columns in Unicode scalars from one.
    ///
    /// - Parameter text: The Xcore text.
    /// - Returns: The tokens in source order.
    public static func tokens(in text: String) -> [SourceToken] {
        let scan = TextLexer.scan(text, configuration: XcoreLanguage.lexicalConfiguration)
        var parser = XcoreParser(
            text: text, scan: scan, factory: DiagnosticFactory(namespace: XcoreLanguage.diagnosticNamespace))
        _ = parser.parseDocument()
        return classifier.sourceTokens(of: scan, overrides: parser.tokenKinds)
    }

    /// Whether a text starts like an Xcore document.
    ///
    /// The text starts like Xcore if, after comments and annotations such as
    /// `@Ecore(...)`, it declares a package with a qualified name that is followed by an
    /// annotation or a keyword of Xcore, such as `import` or `class`. Emfatic
    /// (`package library;`) and KM3 (`package Library {`) are not taken for Xcore, nor is a
    /// lone package declaration. Only the start of the text is examined.
    ///
    /// - Parameter text: The text, or at least its beginning.
    /// - Returns: `true` if the text starts like an Xcore document.
    public static func looksLikeXcore(_ text: String) -> Bool {
        guard let rest = PackageHeader.tokensAfterName(in: text, configuration: XcoreLanguage.lexicalConfiguration)
        else { return false }
        return PackageHeader.startsDeclaration(rest.first, keywords: XcoreLanguage.keywords)
    }
}
