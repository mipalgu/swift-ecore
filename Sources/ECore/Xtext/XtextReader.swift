//
// XtextReader.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Imports the metamodels that an Xtext grammar generates.
///
/// Xtext infers an Ecore package for every `generate` declaration of a grammar
/// from the grammar's rules. The reader parses the grammar and performs that
/// inference as the Xtext documentation ("Metamodel Inference") describes and
/// as Xtext's own transformer implements it, so the packages match what Xtext
/// would generate. Packages that the grammar only imports are not read: their
/// types are external, and diagnostics name every external type that a
/// generated package would need.
///
/// ## Mapping
///
/// | Xtext | Ecore |
/// | --- | --- |
/// | `generate name "nsURI" (as alias)?` | `EPackage` with that name and URI, prefix = name |
/// | `import "nsURI" (as alias)?` | not imported; its types are external (`EObject`, or `EString` as values) |
/// | `ecore::EInt` and other Ecore data types (Ecore imported) | the built-in data type |
/// | parser rule `R` or `R returns T` | `EClass` `R` (or `T`), concrete |
/// | action `{T}`, `{T.f=current}` | `EClass` `T`, subtype of the rule's type; `f` a containment reference typed with the previous type |
/// | unassigned call of parser rule `S` in rule `R` | `S` becomes a subtype of `R` |
/// | parser fragment `fragment F: ...` | `EClass` `F`, supertype of every caller's type |
/// | wildcard fragment `fragment F*: ...` | inlined into its callers |
/// | `f=TerminalOrDatatypeRule` | `EAttribute` of the rule's value type, `[0..1]` |
/// | `f+=...` | the same feature with upper bound `-1` |
/// | `f?=...` | `EAttribute` of type `EBoolean`, `[0..1]` |
/// | `f='keyword'` | `EAttribute` of type `EString` |
/// | `f=ParserRule` | containment `EReference` |
/// | `f=EnumRule` | `EAttribute` of the `EEnum` |
/// | `f=[T]`, `f=[T\|RULE]` | non-containment `EReference` to `T` |
/// | `f=(A \| B)` | the compatible type of `A` and `B` |
/// | `enum E: a='A' \| b;` | `EEnum` with literals `a` (literal `A`) and `b` |
/// | terminal and datatype rules | their value type: `EString` unless `returns` names an Ecore data type |
///
/// Features always have lower bound 0. Multi-valued attributes and
/// non-containment references are not unique, as in Xtext. A feature
/// assigned in several places keeps one definition: class types widen to
/// their most specific common supertype (or `EObject`), while different
/// cardinalities, containment or data types are errors. After inference,
/// features shared by all direct subtypes of a class move to that class
/// (deepest classes first), as Xtext's type hierarchy helper does.
///
/// Xtext creates no data types in generated packages: a terminal or datatype
/// rule that returns an unknown type is an error, and its values are taken to
/// be `EString`, as Xtext suggests. Grammars that extend
/// `org.eclipse.xtext.common.Terminals` (or any grammar) inherit its terminals
/// `ID`, `INT` (`EInt`), `STRING`, `ML_COMMENT`, `SL_COMMENT`, `WS` and
/// `ANY_OTHER`. Grammars that extend other grammars, such as Xbase, may call
/// their rules: the well-known datatype rules and terminals of Xtype and Xbase
/// (``XtextReader/knownDatatypeRules``) yield `EString`, and any other unknown
/// rule is taken to be an external parser rule whose type `EObject` stands in for.
public enum XtextReader {
    /// The datatype rules and terminals of Xtext's Xtype and Xbase grammars, whose values are strings.
    public static let knownDatatypeRules: Set<String> = [
        "ValidID", "QualifiedName", "QualifiedNameWithWildcard", "QualifiedNameInStaticImport", "Number",
        "FeatureCallID", "IdOrSuper", "ArrayBrackets", "StaticQualifier", "OpSingleAssign", "OpMultiAssign",
        "OpOr", "OpAnd", "OpEquality", "OpCompare", "OpOther", "OpAdd", "OpMulti", "OpUnary", "OpPostfix",
        "HEX", "DECIMAL",
    ]

    /// The alias under which predefined rules name Ecore data types; it cannot be written in a grammar.
    static let builtinAlias = "#ecore"

    /// Imports the generated packages of an Xtext grammar.
    ///
    /// Reading never fails: problems become diagnostics, and everything that
    /// can be inferred is.
    ///
    /// - Parameters:
    ///   - text: The grammar text.
    ///   - sourceName: The name of the document, used in diagnostics.
    ///   - options: Overrides for the default generated package.
    /// - Returns: The generated packages, diagnostics, tokens and outline.
    public static func parse(
        _ text: String, sourceName: String? = nil, options: XtextImportOptions = .init()
    ) -> XtextParseResult {
        var collector = DiagnosticCollector(document: sourceName)
        let scanned = RuleGrammarLexer.scan(text, dialect: XtextSyntax.dialect, collector: &collector)
        var parser = XtextParser(tokens: scanned.tokens, endRange: scanned.end, collector: collector)
        parser.parse()
        var grammar = parser.grammar
        collector = parser.state.collector
        applyOptions(options, to: &grammar.generated)
        if grammar.generated.isEmpty {
            collector.information(
                XtextDiagnosticCode.noGeneratedPackage.rawValue,
                "The grammar generates no package; only generated packages are imported", at: grammar.nameRange)
        }
        let overridden = defaultPackage(grammar.generated)
        let drafts = grammar.generated.map { generated in
            GrammarDraftPackage(
                name: generated.name, nsURI: generated.nsURI,
                nsPrefix: (generated == overridden ? options.nsPrefix : nil) ?? generated.name,
                range: generated.range)
        }
        let resolver = XtextTypeResolver(generated: grammar.generated, imported: grammar.imported)
        let usedGrammars = grammar.usedGrammars
        var inference = RuleInference(
            configuration: .xtext, dialect: XtextSyntax.dialect, packages: drafts, collector: collector,
            resolver: { reference, role in resolver.resolve(reference, role: role) },
            externalRule: { name in externalRule(name, usedGrammars: usedGrammars) })
        let filled = inference.run(grammar.rules, inheritedRules: usedGrammars.isEmpty ? [] : commonTerminals)
        collector = inference.collector
        let assembled = GrammarMetamodelAssembler(codePrefix: XtextSyntax.dialect.codePrefix, document: sourceName)
            .assemble(filled)
        collector.append(contentsOf: assembled.diagnostics)
        let outline = OutlineNode(
            id: "grammar", kind: XtextOutlineKind.grammar, name: grammar.name ?? "",
            range: SourceRange(start: .start, end: scanned.end.end),
            selectionRange: grammar.nameRange ?? SourceRange(start: .start, end: .start),
            children: grammar.outlineChildren)
        return XtextParseResult(
            packages: assembled.packages, diagnostics: collector.sorted,
            tokens: RuleGrammarLexer.sourceTokens(
                scanned.tokens, dialect: XtextSyntax.dialect, typeNameOffsets: parser.state.typeNameOffsets),
            outline: [outline])
    }

    /// The generated package that the options override: the one without an alias, or else the first.
    ///
    /// - Parameter generated: The generated packages.
    /// - Returns: The default package, if there is any.
    static func defaultPackage(_ generated: [XtextGeneratedPackage]) -> XtextGeneratedPackage? {
        generated.first { $0.alias == nil } ?? generated.first
    }

    /// Applies the namespace overrides of the options to the default generated package.
    ///
    /// - Parameters:
    ///   - options: The options.
    ///   - generated: The generated packages, modified in place.
    static func applyOptions(_ options: XtextImportOptions, to generated: inout [XtextGeneratedPackage]) {
        guard let target = defaultPackage(generated), let position = generated.firstIndex(of: target) else { return }
        if let name = options.packageName { generated[position].name = name }
        if let uri = options.nsURI { generated[position].nsURI = uri }
    }

    /// The terminals of `org.eclipse.xtext.common.Terminals`.
    static let commonTerminals: [GrammarRule] = [
        ("ID", nil), ("INT", "EInt"), ("STRING", nil), ("ML_COMMENT", nil), ("SL_COMMENT", nil), ("WS", nil),
        ("ANY_OTHER", nil),
    ].map { name, type in
        GrammarRule(
            kind: .terminal, name: name, returnType: type.map { RuleTypeReference(alias: builtinAlias, name: $0) },
            isInherited: true)
    }

    /// What a rule that the grammar does not define stands for.
    ///
    /// - Parameters:
    ///   - name: The rule name.
    ///   - usedGrammars: The grammars the grammar extends.
    /// - Returns: A datatype rule for the well-known Xtype and Xbase datatype
    ///   rules, an external parser rule for other rules of a super grammar
    ///   other than the common terminals, and `nil` otherwise.
    static func externalRule(_ name: String, usedGrammars: [String]) -> ExternalRule? {
        guard let library = usedGrammars.first(where: { $0 != XtextSyntax.commonTerminalsGrammar }) else {
            return nil
        }
        if knownDatatypeRules.contains(name) { return .dataType(.ecore(.eString)) }
        return .parserRule(.external(name: name, origin: library))
    }
}

/// Resolves the type references of an Xtext grammar against its metamodel declarations.
struct XtextTypeResolver: Sendable {
    /// The generated packages.
    let generated: [XtextGeneratedPackage]

    /// The imported packages.
    let imported: [XtextImportedPackage]

    /// Resolves a type reference.
    ///
    /// An alias selects the generated or imported package declared with it.
    /// Without an alias, the data types and `EObject` of an Ecore import without
    /// alias come first, then the generated package without alias, then the
    /// first other import without alias, as Xtext looks for the first
    /// unaliased declaration that can hold the type.
    ///
    /// - Parameters:
    ///   - reference: The written reference.
    ///   - role: Where the reference occurs.
    /// - Returns: What the reference denotes.
    func resolve(_ reference: RuleTypeReference, role: TypeRole) -> TypeResolution {
        let name = reference.name
        if reference.alias == XtextReader.builtinAlias {
            return EcoreDataType(rawValue: name).map { .ecore($0) } ?? .eObject
        }
        if let alias = reference.alias {
            if let package = generated.first(where: { $0.alias == alias }) {
                return inGenerated(package, name: name, role: role)
            }
            if let package = imported.first(where: { $0.alias == alias }) {
                return inImported(package, name: name)
            }
            return .unresolved("The alias '\(alias)' of '\(reference.displayName)' is not declared")
        }
        if imported.contains(where: { $0.alias == nil && $0.nsURI == XtextSyntax.ecoreNamespaceURI }),
            let type = ecoreType(name)
        {
            return type
        }
        if let package = generated.first(where: { $0.alias == nil }) {
            return inGenerated(package, name: name, role: role)
        }
        if let package = imported.first(where: { $0.alias == nil && $0.nsURI != XtextSyntax.ecoreNamespaceURI }) {
            return .external(name: name, origin: package.nsURI)
        }
        return .unresolved("No generated or imported package without an alias can hold the type '\(name)'")
    }

    /// A type of a generated package.
    ///
    /// - Parameters:
    ///   - package: The package.
    ///   - name: The type name.
    ///   - role: Where the reference occurs.
    /// - Returns: The generated type, or an explanation for a data type, which Xtext does not create.
    private func inGenerated(_ package: XtextGeneratedPackage, name: String, role: TypeRole) -> TypeResolution {
        if role == .dataRule {
            return .unresolved(
                "Cannot create the data type '\(name)'; to return an Ecore data type, import '\(XtextSyntax.ecoreNamespaceURI)'")
        }
        return .generated(package: package.name, name: name)
    }

    /// A type of an imported package.
    ///
    /// - Parameters:
    ///   - package: The package.
    ///   - name: The type name.
    /// - Returns: A built-in type for Ecore's data types and `EObject`, otherwise an external type.
    private func inImported(_ package: XtextImportedPackage, name: String) -> TypeResolution {
        if package.nsURI == XtextSyntax.ecoreNamespaceURI, let type = ecoreType(name) { return type }
        return .external(name: name, origin: package.nsURI)
    }

    /// An Ecore type by name.
    ///
    /// - Parameter name: The name, such as `EInt` or `EObject`.
    /// - Returns: The built-in type, or `nil` if Ecore has no data type or `EObject` of that name.
    private func ecoreType(_ name: String) -> TypeResolution? {
        if name == EcoreClassifier.eObject.rawValue { return .eObject }
        return EcoreDataType(rawValue: name).map { .ecore($0) }
    }
}
