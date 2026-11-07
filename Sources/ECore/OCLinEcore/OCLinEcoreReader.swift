//
// OCLinEcoreReader.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OCL

/// The result of reading an OCLinEcore document.
///
/// Reading recovers from errors, so the packages hold every declaration that could be read,
/// and the diagnostics describe each one that could not.
public struct OCLinEcoreParseResult: Sendable {
    /// The root packages that the document declares, with their constraints as annotations.
    public var packages: [EPackage]

    /// The problems found, in source order.
    public var diagnostics: [SourceDiagnostic]

    /// The lexical tokens of the document, including comments.
    public var tokens: [SourceToken]

    /// The outline of the document: packages, classifiers, features, operations and constraints.
    public var outline: [OutlineNode]

    /// The imports of the document, in order.
    public var imports: [OCLinEcoreImport]

    /// The module name of the document, if it declares one.
    public var module: String?

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - packages: The root packages.
    ///   - diagnostics: The problems found.
    ///   - tokens: The lexical tokens.
    ///   - outline: The outline.
    ///   - imports: The imports.
    ///   - module: The module name.
    public init(
        packages: [EPackage], diagnostics: [SourceDiagnostic], tokens: [SourceToken], outline: [OutlineNode],
        imports: [OCLinEcoreImport] = [], module: String? = nil
    ) {
        self.packages = packages
        self.diagnostics = diagnostics
        self.tokens = tokens
        self.outline = outline
        self.imports = imports
        self.module = module
    }

    /// Whether the document was read without errors.
    public var isValid: Bool { !diagnostics.contains { $0.severity == .error } }
}

/// Reads OCLinEcore documents into Ecore packages.
///
/// OCLinEcore is the textual syntax of Eclipse OCL for Ecore metamodels with embedded OCL.
/// The reader turns packages, classes, data types, enumerations, attributes, references,
/// operations and annotations into their Ecore counterparts, and stores invariants, operation
/// bodies, preconditions, postconditions, initial values and derivations as the annotations
/// that Eclipse OCL writes (see ``OCLAnnotation``). The text of each expression is kept
/// verbatim.
///
/// Unwritten multiplicities and qualifiers take the OCLinEcore defaults: `[1]`, `!ordered` and
/// `unique`. `String`, `Integer`, `Real`, `Boolean` and `UnlimitedNatural` denote the Ecore
/// types that Eclipse OCL maps them to; other Ecore types are written as `ecore::EInt` and so on.
public enum OCLinEcoreReader {
    /// Reads an OCLinEcore document.
    ///
    /// - Parameters:
    ///   - text: The document.
    ///   - sourceName: The name of the document, attached to each diagnostic.
    /// - Returns: The packages, diagnostics, tokens and outline of the document.
    public static func parse(_ text: String, sourceName: String? = nil) -> OCLinEcoreParseResult {
        parse(text, sourceName: sourceName, importing: [])
    }

    /// Reads an OCLinEcore document whose imports refer to other packages.
    ///
    /// - Parameters:
    ///   - text: The document.
    ///   - sourceName: The name of the document, attached to each diagnostic.
    ///   - externals: The packages that imports may name, matched by namespace URI or name.
    /// - Returns: The packages, diagnostics, tokens and outline of the document.
    public static func parse(_ text: String, sourceName: String?, importing externals: [EPackage]) -> OCLinEcoreParseResult {
        let tokenisation = OCLLexer.tokenise(text)
        var parser = OCLinEcoreParser(
            cursor: OCLTokenCursor(tokens: tokenisation.significantTokens, source: text), document: sourceName)
        let declaration = parser.parseDocument()
        var builder = OCLinEcoreBuilder(document: sourceName, externals: externals)
        let packages = builder.build(declaration)
        var diagnostics = tokenisation.diagnostics.map { diagnostic in
            var located = diagnostic
            located.document = sourceName
            return located
        }
        for diagnostic in parser.diagnostics + builder.diagnostics
        where !diagnostics.contains(where: { $0.range == diagnostic.range && $0.code == diagnostic.code }) {
            diagnostics.append(diagnostic)
        }
        diagnostics.sort { ($0.range?.start.utf8Offset ?? 0) < ($1.range?.start.utf8Offset ?? 0) }
        return OCLinEcoreParseResult(
            packages: packages, diagnostics: diagnostics, tokens: OCLinEcoreSyntax.tokens(of: tokenisation),
            outline: OCLinEcoreOutline.nodes(of: declaration), imports: declaration.imports, module: declaration.module)
    }
}

extension OCLinEcoreSyntax {
    /// Splits OCLinEcore text into classified tokens for syntax highlighting.
    ///
    /// The tokeniser never fails: text it cannot read becomes a token of kind
    /// ``SourceTokenKind/invalid``. Comments are included and whitespace is not. Words that
    /// OCLinEcore or Essential OCL use as keywords are ``SourceTokenKind/keyword`` tokens,
    /// wherever they appear.
    ///
    /// - Parameter text: The OCLinEcore text.
    /// - Returns: The tokens in source order.
    public static func tokens(in text: String) -> [SourceToken] {
        tokens(of: OCLLexer.tokenise(text))
    }

    /// Classifies the tokens of a tokenisation.
    static func tokens(of tokenisation: OCLTokenisation) -> [SourceToken] {
        OCLTokenClassifier.sourceTokens(of: tokenisation.tokens, keywords: keywords)
    }

    /// The number of characters at the start of a text that ``looksLikeOCLinEcore(_:)`` scans.
    static let recognitionLength = 16 * 1024

    /// Whether a text starts like an OCLinEcore document.
    ///
    /// After comments, any `module` declaration and any `import` or `library` declarations,
    /// the text must declare a package whose name is followed by a namespace prefix
    /// (`package school : sch = 'http://example.org/school'`) or a namespace URI. A package
    /// without either counts only after an import or module declaration, so that KM3
    /// (`package School {`), Emfatic (`package school;`) and Complete OCL documents, whose
    /// packages are followed by contexts, are not taken for OCLinEcore. Only the start of the
    /// text is examined.
    ///
    /// - Parameter text: The text, or at least its beginning.
    /// - Returns: `true` if the text starts like an OCLinEcore document.
    public static func looksLikeOCLinEcore(_ text: String) -> Bool {
        let tokens = OCLLexer.tokenise(String(text.prefix(recognitionLength))).significantTokens
        var index = 0
        var hasHeader = false
        func token(_ offset: Int = 0) -> OCLToken? {
            index + offset < tokens.count ? tokens[index + offset] : nil
        }
        while let current = token() {
            if current.isWord(moduleKeyword), token(1)?.isName == true {
                index += 2
                if token()?.isSymbol(";") == true { index += 1 }
            } else if current.isWord(importKeyword) || current.isWord(libraryKeyword) {
                index += 1
                if token()?.isName == true, token(1)?.isSymbol(":") == true { index += 2 }
                guard let target = token(), target.kind == .string || target.isName else { return false }
                index += 1
                while token()?.isSymbol(OCLSyntax.pathSeparator) == true, token(1)?.isName == true { index += 2 }
                guard token()?.isSymbol(";") == true else { return false }
                index += 1
            } else {
                break
            }
            hasHeader = true
        }
        guard token()?.isWord(packageKeyword) == true, token(1)?.isName == true else { return false }
        index += 2
        if token()?.isSymbol(":") == true {
            guard token(1)?.isName == true else { return false }
            index += 2
            guard token()?.isSymbol("=") == true else { return token()?.isSymbol("{") == true }
        }
        if token()?.isSymbol("=") == true {
            guard token(1)?.kind == .string else { return false }
            index += 2
            return token()?.isSymbol("{") == true || token()?.isSymbol(";") == true
        }
        return hasHeader && (token()?.isSymbol("{") == true || token()?.isSymbol(";") == true)
    }
}

/// Builds the outline of an OCLinEcore document.
enum OCLinEcoreOutline {
    /// The kinds of outline node.
    typealias Kind = OCLinEcoreOutlineKind

    /// Creates the outline nodes of the imports of a document.
    ///
    /// - Parameter document: The parsed document.
    /// - Returns: The outline nodes.
    static func nodes(of document: OCLinEcoreDocumentDeclaration) -> [OutlineNode] {
        document.imports.compactMap { anImport in
            anImport.range.map {
                OutlineNode(id: Kind.import + ":" + anImport.target, kind: Kind.import, name: anImport.alias ?? anImport.target,
                    detail: anImport.target, range: $0, selectionRange: $0)
            }
        } + document.packages.map { node(of: $0, path: []) }
    }

    /// Creates an outline node from a declaration header.
    ///
    /// - Parameters:
    ///   - kind: The kind of outline node.
    ///   - header: The name and ranges of the declaration.
    ///   - path: The names of the enclosing declarations.
    ///   - detail: The description shown beside the name.
    ///   - children: The nested outline nodes.
    /// - Returns: The outline node.
    static func node(_ kind: String, _ header: DeclarationHeader, path: [String], detail: String? = nil, children: [OutlineNode] = []) -> OutlineNode {
        OutlineNode(
            id: kind + ":" + (path + [header.name]).joined(separator: "."), kind: kind, name: header.name, detail: detail,
            range: header.range, selectionRange: header.nameRange, children: children)
    }

    /// Creates the outline node of a package and everything inside it.
    ///
    /// - Parameters:
    ///   - package: The package declaration.
    ///   - path: The names of the enclosing packages.
    /// - Returns: The outline node.
    static func node(of package: PackageDeclaration, path: [String]) -> OutlineNode {
        let inner = path + [package.header.name]
        let children = package.packages.map { node(of: $0, path: inner) } + package.classifiers.map { node(of: $0, path: inner) }
        return node(Kind.package, package.header, path: path, detail: package.nsURI, children: children)
    }

    /// Creates the outline node of a classifier and its members.
    ///
    /// - Parameters:
    ///   - classifier: The classifier declaration.
    ///   - path: The names of the enclosing declarations.
    /// - Returns: The outline node.
    static func node(of classifier: ClassifierDeclaration, path: [String]) -> OutlineNode {
        let inner = path + [classifier.header.name]
        var children = classifier.invariants.map { constraint(Kind.invariant, $0, path: inner) }
        children += classifier.literals.map { node(Kind.literal, $0.header, path: inner) }
        children += classifier.features.map { feature in
            let constraints = [feature.initial.map { constraint(Kind.initial, $0, path: inner + [feature.header.name]) },
                feature.derivation.map { constraint(Kind.derivation, $0, path: inner + [feature.header.name]) }].compactMap { $0 }
            return node(feature.isAttribute ? Kind.attribute : Kind.reference, feature.header, path: inner,
                detail: feature.type?.textWithMultiplicity, children: constraints)
        }
        children += classifier.operations.map { operation in
            let operationPath = inner + [operation.header.name]
            let constraints = operation.preconditions.map { constraint(Kind.precondition, $0, path: operationPath) }
                + (operation.body.map { [constraint(Kind.body, $0, path: operationPath)] } ?? [])
                + operation.postconditions.map { constraint(Kind.postcondition, $0, path: operationPath) }
            let signature = "(" + operation.parameters.map { $0.type?.textWithMultiplicity ?? "" }.joined(separator: ", ") + ")"
                + (operation.type.map { " : " + $0.textWithMultiplicity } ?? "")
            return node(Kind.operation, operation.header, path: inner, detail: signature, children: constraints)
        }
        let kind: String
        switch classifier.kind {
        case .class: kind = Kind.class
        case .dataType: kind = Kind.dataType
        case .enumeration: kind = Kind.enumeration
        }
        return node(kind, classifier.header, path: path, children: children)
    }

    /// Creates the outline node of a constraint.
    ///
    /// - Parameters:
    ///   - kind: The kind of outline node.
    ///   - specification: The constraint.
    ///   - path: The names of the enclosing declarations.
    /// - Returns: The outline node.
    static func constraint(_ kind: String, _ specification: SpecificationDeclaration, path: [String]) -> OutlineNode {
        let name = specification.name ?? kind
        return OutlineNode(
            id: kind + ":" + (path + [name]).joined(separator: "."), kind: kind, name: name, detail: specification.text,
            range: specification.range, selectionRange: specification.range)
    }
}
