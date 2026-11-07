//
// LangiumReader.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// Imports the types of a Langium grammar as an Ecore package.
///
/// Langium derives a semantic model (TypeScript types) from a grammar: types
/// declared with `interface` and `type`, and types inferred from the parser
/// rules, as the Langium documentation on semantic model inference describes.
/// The reader parses the grammar and builds the corresponding Ecore package.
/// Inference follows the same rules as Xtext's, from which Langium's grammar
/// language descends, adapted to Langium in three ways: fragments are inlined
/// into their callers, features stay where they are assigned, and an inferred
/// type that no rule instantiates (such as `Expression: Addition;`) is a union
/// of its subtypes and so an abstract class.
///
/// ## Mapping
///
/// | Langium | Ecore |
/// | --- | --- |
/// | `grammar Name` | `EPackage` `Name`, URI `urn:langium:Name` unless the options give one |
/// | `interface I extends J, K { ... }` | `EClass` `I` with supertypes `J` and `K` |
/// | `p: T` / `p?: T` / `p: T[]` | lower bound 1 / 0 / list `[0..*]` |
/// | `p: string`, `number`, `boolean`, `bigint`, `Date` | `EAttribute` of `EString`, `EDouble`, `EBoolean`, `EBigInteger`, `EDate` |
/// | `p: 'a' \| 'b'` | `EAttribute` of `EString` |
/// | `p: T` (a type) | containment `EReference` |
/// | `p: @T` / `p: @T+` | non-containment `EReference` / the same as a list |
/// | `p: A \| B` | the most specific common supertype, or `EObject` |
/// | `p: T = value` | default value literal |
/// | `type T = A \| B` | abstract `EClass` `T`, supertype of `A` and `B` |
/// | `type T = 'a' \| 'b'` | `EEnum` `T` (if every literal is a name), otherwise an `EString`-like `EDataType` |
/// | `type T = string` | `EDataType` `T` with the primitive's instance class |
/// | parser rule `R`, `R infers T` | inferred `EClass` (abstract if no rule instantiates it) |
/// | `R returns T` | the declared or inferred type `T`; a declared type gets no inferred features |
/// | `{infer T}`, `{infer T.f=current}` | as in Xtext: subtype of the rule's type, `f` a containment reference |
/// | `f=Rule`, `f+=...`, `f?=...`, `f=[T:ID]`, `f=[+T:ID]` | as in Xtext; `[+T]` is a non-containment list |
/// | `fragment F: ...` | inlined into its callers |
/// | `infix E on P: ...` | `EClass` `E` with `left` and `right` (common type of `E` and `P`) and `operator` (`EString`) |
/// | terminal and datatype rules | their primitive (`EString` unless `returns` names another) |
///
/// A rule that returns a type which this grammar neither declares nor infers
/// (it may be declared in an imported grammar file) has that type inferred
/// from its rules, with a warning. Rules of imported grammar files are taken to
/// be terminals (names in capitals) or parser rules of another grammar
/// (`EObject`). In strict mode (``LangiumTypeMode/strict``) every inferred type
/// is an error and only declared types are created.
public enum LangiumReader {
    /// Imports the types of a Langium grammar.
    ///
    /// Reading never fails: problems become diagnostics, and everything that
    /// can be inferred is.
    ///
    /// - Parameters:
    ///   - text: The grammar text.
    ///   - sourceName: The name of the document, used in diagnostics and as fallback package name.
    ///   - options: The namespace and type-mode settings.
    /// - Returns: The package, diagnostics, tokens and outline.
    public static func parse(
        _ text: String, sourceName: String? = nil, options: LangiumImportOptions = .init()
    ) -> LangiumParseResult {
        var collector = DiagnosticCollector(document: sourceName)
        let scanned = RuleGrammarLexer.scan(text, dialect: LangiumSyntax.dialect, collector: &collector)
        var parser = LangiumParser(tokens: scanned.tokens, endRange: scanned.end, collector: collector)
        parser.parse()
        let grammar = parser.grammar
        collector = parser.state.collector
        let name = GrammarNaming.packageName(declared: grammar.name, option: options.packageName, sourceName: sourceName)
        let draft = GrammarDraftPackage(
            name: name, nsURI: options.nsURI ?? GrammarNaming.defaultNsURI(notation: "langium", packageName: name),
            nsPrefix: options.nsPrefix ?? GrammarNaming.defaultNsPrefix(packageName: name), range: grammar.nameRange)
        var configuration = RuleInferenceConfiguration.langium
        configuration.allowsInferredTypes = options.typeMode == .normal
        let imports = grammar.imports
        var inference = RuleInference(
            configuration: configuration, dialect: LangiumSyntax.dialect, packages: [draft], collector: collector,
            resolver: { reference, _ in resolve(reference, package: name) },
            externalRule: { rule in externalRule(rule, imports: imports) })
        declareTypes(of: grammar, package: name, in: &inference)
        if options.typeMode == .normal { noteUndeclaredReturnTypes(of: grammar, inference: &inference) }
        let filled = inference.run(grammar.rules)
        collector = inference.collector
        let assembled = GrammarMetamodelAssembler(codePrefix: LangiumSyntax.dialect.codePrefix, document: sourceName)
            .assemble(filled)
        collector.append(contentsOf: assembled.diagnostics)
        let outline = OutlineNode(
            id: "grammar", kind: LangiumOutlineKind.grammar, name: grammar.name ?? name,
            range: SourceRange(start: .start, end: scanned.end.end),
            selectionRange: grammar.nameRange ?? SourceRange(start: .start, end: .start),
            children: grammar.outlineChildren)
        return LangiumParseResult(
            packages: assembled.packages, diagnostics: collector.sorted,
            tokens: RuleGrammarLexer.sourceTokens(
                scanned.tokens, dialect: LangiumSyntax.dialect, typeNameOffsets: parser.state.typeNameOffsets),
            outline: [outline])
    }

    /// Resolves a type reference of a Langium grammar.
    ///
    /// - Parameters:
    ///   - reference: The written reference.
    ///   - package: The name of the grammar's package.
    /// - Returns: A built-in data type for a primitive, otherwise a type of the package.
    static func resolve(_ reference: RuleTypeReference, package: String) -> TypeResolution {
        if let primitive = LangiumSyntax.primitiveTypes[reference.name] { return .ecore(primitive) }
        return .generated(package: package, name: reference.name)
    }

    /// What a rule that the grammar does not define stands for.
    ///
    /// - Parameters:
    ///   - name: The rule name.
    ///   - imports: The imported grammar files.
    /// - Returns: For a grammar with imports, a terminal for names in capitals and
    ///   a parser rule of another grammar otherwise; `nil` without imports.
    static func externalRule(_ name: String, imports: [String]) -> ExternalRule? {
        guard !imports.isEmpty else { return nil }
        if name == name.uppercased() { return .dataType(.ecore(.eString)) }
        return .parserRule(.external(name: name, origin: imports.joined(separator: ", ")))
    }

    // MARK: Declared types

    /// Declares the interfaces and types of a grammar, in source order.
    ///
    /// - Parameters:
    ///   - grammar: The parsed grammar.
    ///   - package: The package name.
    ///   - inference: The inference that receives the declarations.
    static func declareTypes(of grammar: LangiumGrammar, package: String, in inference: inout RuleInference) {
        /// A declaration in the order it was written.
        enum Declaration {
            /// An interface declaration.
            case interface(LangiumInterface)
            /// A type declaration.
            case type(LangiumTypeDeclaration)
        }
        let declarations = (grammar.interfaces.map { (Declaration.interface($0), $0.nameRange) }
            + grammar.types.map { (Declaration.type($0), $0.nameRange) })
            .sorted { $0.1.start.utf8Offset < $1.1.start.utf8Offset }.map(\.0)
        for declaration in declarations {
            switch declaration {
            case .interface(let value):
                inference.declareClass(package: package, name: value.name, isAbstract: false, range: value.nameRange)
            case .type(let value):
                declareType(value, package: package, in: &inference)
            }
        }
        for interface in grammar.interfaces {
            let key = TypeKey.generated(package: package, name: interface.name)
            for superType in interface.superTypes {
                let superKey = TypeKey.generated(package: package, name: superType.name)
                if !inference.exists(superKey) {
                    inference.declareClass(package: package, name: superType.name, isAbstract: false, range: superType.range)
                    noteUndeclared(superType.name, range: superType.range, in: &inference)
                }
                inference.declareSuperType(superKey, of: key)
            }
            inference.declareFeatures(interface.attributes.map { feature($0, package: package, inference: &inference) }, of: key)
        }
    }

    /// Declares a type `type T = ...` as a class, enumeration or data type.
    ///
    /// - Parameters:
    ///   - declaration: The type declaration.
    ///   - package: The package name.
    ///   - inference: The inference that receives the declaration.
    private static func declareType(
        _ declaration: LangiumTypeDeclaration, package: String, in inference: inout RuleInference
    ) {
        let alternatives = declaration.type.alternatives
        let literals = alternatives.compactMap { alternative -> String? in
            if case .literal(let value) = alternative { return value }
            return nil
        }
        let names = alternatives.compactMap { alternative -> (String, SourceRange)? in
            if case .named(let name, let range) = alternative { return (name, range) }
            return nil
        }
        if literals.count == alternatives.count {
            if literals.allSatisfy(isName) {
                inference.declareEnum(
                    package: package, name: declaration.name, literals: literals.map { GrammarDraftLiteral(name: $0, literal: $0) },
                    range: declaration.nameRange)
            } else {
                inference.declareDataType(
                    package: package, name: declaration.name, instanceClassName: "java.lang.String",
                    range: declaration.nameRange)
            }
        } else if names.count == alternatives.count {
            inference.declareClass(package: package, name: declaration.name, isAbstract: true, range: declaration.nameRange)
            let union = TypeKey.generated(package: package, name: declaration.name)
            for (member, range) in names {
                inference.declareUnionMember(.generated(package: package, name: member), of: union, range: range)
            }
        } else if alternatives.count == 1, case .primitive(let primitive) = alternatives[0] {
            inference.declareDataType(
                package: package, name: declaration.name,
                instanceClassName: LangiumSyntax.primitiveInstanceClasses[primitive], range: declaration.nameRange)
        } else {
            inference.declareDataType(
                package: package, name: declaration.name, instanceClassName: "java.lang.Object",
                range: declaration.nameRange)
            inference.report(
                .information, .approximation,
                "The type '\(declaration.name)' mixes kinds of type; it becomes a data type of arbitrary objects",
                at: declaration.nameRange)
        }
    }

    /// Whether a literal can be the name of an enumeration literal.
    ///
    /// - Parameter text: The literal.
    /// - Returns: `true` for a letter or underscore followed by letters, digits and underscores.
    private static func isName(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, first.isASCII,
            first.properties.isAlphabetic || first == "_"
        else { return false }
        return text.unicodeScalars.allSatisfy {
            $0.isASCII && ($0.properties.isAlphabetic || $0 == "_" || ("0"..."9").contains($0))
        }
    }

    /// The declared feature of an interface property.
    ///
    /// - Parameters:
    ///   - attribute: The property.
    ///   - package: The package name.
    ///   - inference: The inference, which receives approximation notes.
    /// - Returns: The feature.
    private static func feature(
        _ attribute: LangiumAttribute, package: String, inference: inout RuleInference
    ) -> DeclaredFeature {
        var isMany = false
        var isContainment = true
        var types: [TypeKey] = []
        /// Records the types, multiplicity and containment that a type expression contributes.
        ///
        /// - Parameter expression: The type expression.
        func add(_ expression: LangiumTypeExpression) {
            switch expression {
            case .array(let element):
                isMany = true
                add(element)
            case .reference(let target, let isMulti):
                isContainment = false
                if isMulti {
                    isMany = true
                    inference.report(
                        .information, .approximation,
                        "The multi-reference '\(attribute.name)' becomes a list of references", at: attribute.range)
                }
                add(target)
            case .union(let members):
                for member in members { add(member) }
            case .named(let name, _):
                append(.generated(package: package, name: name))
            case .primitive(let name):
                append(.ecore(LangiumSyntax.primitiveTypes[name] ?? .eString))
            case .literal:
                append(.ecore(.eString))
            }
        }
        /// Records a type once.
        ///
        /// - Parameter key: The type.
        func append(_ key: TypeKey) { if !types.contains(key) { types.append(key) } }
        add(attribute.type)
        return DeclaredFeature(
            name: attribute.name, types: types, isMany: isMany, isRequired: !attribute.isOptional && !isMany,
            isContainment: isContainment, defaultValueLiteral: attribute.defaultValue, range: attribute.range)
    }

    /// Warns about rules that return a type that is neither declared nor inferred in this grammar.
    ///
    /// Langium requires `returns` to name an existing type; such a type may be
    /// declared in an imported grammar file, which is not read, so the type is
    /// inferred from the rules instead.
    ///
    /// - Parameters:
    ///   - grammar: The parsed grammar.
    ///   - inference: The inference, which receives the warnings.
    private static func noteUndeclaredReturnTypes(of grammar: LangiumGrammar, inference: inout RuleInference) {
        let declared = Set(grammar.interfaces.map(\.name) + grammar.types.map(\.name))
        var inferred: Set<String> = []
        for rule in grammar.rules where rule.kind == .parser || rule.kind == .infix {
            if let returnType = rule.returnType, returnType.isInferred { inferred.insert(returnType.name) }
            if rule.returnType == nil { inferred.insert(rule.name) }
            for type in rule.body.map(actionTypes) ?? [] where type.isInferred { inferred.insert(type.name) }
        }
        var noted: Set<String> = []
        for rule in grammar.rules where rule.kind == .parser || rule.kind == .infix {
            guard let returnType = rule.returnType, !returnType.isInferred,
                LangiumSyntax.primitiveTypes[returnType.name] == nil, !declared.contains(returnType.name),
                !inferred.contains(returnType.name), noted.insert(returnType.name).inserted
            else { continue }
            noteUndeclared(returnType.name, range: returnType.range, in: &inference)
        }
    }

    /// The types of the actions in an element and everything it contains.
    ///
    /// - Parameter element: The element.
    /// - Returns: The action types in source order.
    private static func actionTypes(_ element: RuleElement) -> [RuleTypeReference] {
        if case .action(let type, _, _) = element.kind { return [type] }
        return element.children.flatMap(actionTypes)
    }

    /// Warns that a type is not declared in this grammar and is taken from its uses instead.
    ///
    /// - Parameters:
    ///   - name: The type name.
    ///   - range: Where the type is named.
    ///   - inference: The inference, which receives the warning.
    private static func noteUndeclared(_ name: String, range: SourceRange?, in inference: inout RuleInference) {
        inference.report(
            .warning, .externalType,
            "The type '\(name)' is not declared in this grammar (an imported grammar may declare it); it is inferred from its uses",
            at: range)
    }
}
