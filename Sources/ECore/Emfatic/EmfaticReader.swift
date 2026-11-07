//
// EmfaticReader.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// The diagnostic codes that reading and writing Emfatic report.
public enum EmfaticDiagnosticCode: String, CaseIterable, Sendable {
    /// A character cannot start any token.
    case unexpectedCharacter = "emfatic.unexpectedCharacter"
    /// A string or character literal has no closing delimiter.
    case unterminatedString = "emfatic.unterminatedString"
    /// A block comment has no closing `*/`.
    case unterminatedComment = "emfatic.unterminatedComment"
    /// A numeric literal cannot be read.
    case invalidNumber = "emfatic.invalidNumber"
    /// A token appears where the grammar does not allow it.
    case unexpectedToken = "emfatic.unexpectedToken"
    /// The text holds no package declaration.
    case missingPackage = "emfatic.missingPackage"
    /// A type name refers to no known classifier.
    case unresolvedType = "emfatic.unresolvedType"
    /// An opposite names no reference of the target class.
    case unresolvedOpposite = "emfatic.unresolvedOpposite"
    /// A key names no attribute of the target class.
    case unresolvedKey = "emfatic.unresolvedKey"
    /// An annotation names no known annotation source.
    case unresolvedAnnotation = "emfatic.unresolvedAnnotation"
    /// Two elements of the same container have the same name.
    case duplicateName = "emfatic.duplicateName"
    /// A multiplicity is malformed or inconsistent.
    case invalidMultiplicity = "emfatic.invalidMultiplicity"
    /// A construct is read but has no counterpart in the native metamodel, or is ignored.
    case unsupportedConstruct = "emfatic.unsupportedConstruct"
    /// A body is kept as text but is never executed.
    case bodyNotExecuted = "emfatic.bodyNotExecuted"
    /// Writing a metamodel loses information that Emfatic cannot express.
    case lossyWrite = "emfatic.lossyWrite"
}

/// The result of reading an Emfatic document.
///
/// Reading never fails: whatever could be read is returned together with the diagnostics
/// that describe the rest.
public struct EmfaticParseResult: Sendable {
    /// The packages declared by the document; a document declares at most one root package.
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

/// Reads Emfatic documents into native Ecore packages.
///
/// The reader covers the Emfatic language: the package declaration with `@namespace`,
/// subpackages, imports, annotations (with the predefined labels `Ecore`, `GenModel`,
/// `ExtendedMetaData` and `EmfaticAnnotationMap`, and labels defined through
/// `EmfaticAnnotationMap`), classes and interfaces with type parameters, supertypes and
/// instance class names, data types, enumerations, map entries, attributes, references
/// with opposites, operations with parameters and exceptions, modifiers, multiplicities,
/// default values and generic types.
///
/// Imported metamodels are not loaded: a type that only an import could provide becomes
/// a placeholder classifier that keeps its name, and is reported as a warning.
public enum EmfaticReader {
    /// Reads an Emfatic document.
    ///
    /// - Parameters:
    ///   - text: The text of the document.
    ///   - sourceName: The name of the document that diagnostics refer to, if any.
    /// - Returns: The packages, diagnostics, tokens and outline of the document.
    public static func parse(_ text: String, sourceName: String? = nil) -> EmfaticParseResult {
        let factory = DiagnosticFactory(namespace: EmfaticLanguage.diagnosticNamespace, document: sourceName)
        let scan = TextLexer.scan(text, configuration: EmfaticLanguage.lexicalConfiguration)
        var parser = EmfaticParser(scan: scan, factory: factory)
        let document = parser.parseDocument()
        let external = ExternalTypeNames { EmfaticLanguage.builtinClassifier($0) }
        let assembled = MetamodelAssembler.assemble(
            document.packages, factory: factory, external: external,
            unresolvedSeverity: document.imports.isEmpty ? .error : .warning)
        var diagnostics = scan.problems.map(factory.diagnostic(for:)) + parser.diagnostics + assembled.diagnostics
        if !document.imports.isEmpty {
            diagnostics.append(factory.warning(
                .unsupportedConstruct, "Imported metamodels are not loaded; their types are kept as placeholders",
                at: document.imports[0]))
        }
        return EmfaticParseResult(
            packages: assembled.packages, diagnostics: SourceOrder.sorted(diagnostics),
            tokens: EmfaticSyntax.classifier.sourceTokens(of: scan, overrides: parser.tokenKinds),
            outline: OutlineBuilder.outline(of: document.packages))
    }
}

/// Lexical analysis of Emfatic text for tools such as editors.
public enum EmfaticSyntax {
    /// The token classifier of Emfatic.
    static let classifier = TokenClassifier(
        keywords: EmfaticLanguage.keywords, operators: EmfaticLanguage.operators,
        typeNames: Set(EmfaticLanguage.basicTypes.map(\.name)).union(EmfaticLanguage.unprefixedEcoreNames))

    /// Splits Emfatic text into classified tokens.
    ///
    /// The tokeniser never fails: text that cannot be read becomes a token of kind
    /// ``SourceTokenKind/invalid``. Comments are included and whitespace is not. The text
    /// is parsed as well, so that type names, annotation labels and enumeration literals
    /// are classified by their role. Positions count UTF-8 offsets, lines from one and
    /// columns in Unicode scalars from one.
    ///
    /// - Parameter text: The Emfatic text.
    /// - Returns: The tokens in source order.
    public static func tokens(in text: String) -> [SourceToken] {
        let scan = TextLexer.scan(text, configuration: EmfaticLanguage.lexicalConfiguration)
        var parser = EmfaticParser(scan: scan, factory: DiagnosticFactory(namespace: EmfaticLanguage.diagnosticNamespace))
        _ = parser.parseDocument()
        return classifier.sourceTokens(of: scan, overrides: parser.tokenKinds)
    }

    /// The symbol that ends the package declaration of an Emfatic document.
    static let packageTerminator = ";"

    /// Whether a text starts like an Emfatic document.
    ///
    /// The text starts like Emfatic if, after comments and annotations such as
    /// `@namespace(...)`, it declares a package with a qualified name followed by a
    /// semicolon (`package library;`), and the declaration is followed by an annotation or
    /// a keyword of Emfatic, such as `import` or `class`. KM3 (`package Library {`) and
    /// Xcore (`package org.example.library` without a semicolon) are not taken for Emfatic,
    /// nor is a lone package declaration. Only the start of the text is examined.
    ///
    /// - Parameter text: The text, or at least its beginning.
    /// - Returns: `true` if the text starts like an Emfatic document.
    public static func looksLikeEmfatic(_ text: String) -> Bool {
        guard
            let rest = PackageHeader.tokensAfterName(in: text, configuration: EmfaticLanguage.lexicalConfiguration),
            let terminator = rest.first, terminator.kind == .punctuation, terminator.text == packageTerminator
        else { return false }
        return PackageHeader.startsDeclaration(rest.dropFirst().first, keywords: EmfaticLanguage.keywords)
    }
}
