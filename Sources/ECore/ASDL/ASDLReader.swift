//
// ASDLReader.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Reads Zephyr ASDL descriptions as Ecore metamodels.
///
/// The Abstract Syntax Description Language (Wang, Appel, Korn and Serra,
/// [USENIX DSL 1997](https://www.usenix.org/conference/dsl-97/zephyr-abstract-syntax-description-language))
/// describes tree-shaped data such as abstract syntax trees.
/// The reader accepts the grammar of the paper together with CPython's
/// dialect, whose `Parser/asdl.py` adds attributes on product types and
/// combined quantifiers, a module's `version` string from older CPython
/// releases, several modules in one text, and the asdlGen import list
/// `module M (imports N) { ... }` with qualified type names `N.t`.
///
/// Each module becomes a package:
///
/// | ASDL | Ecore |
/// |---|---|
/// | `module M { ... }` | `EPackage` named `M` |
/// | `module M version "v"` | package annotation detail `version` |
/// | `t = A(...) \| B(...)` (sum) | abstract `EClass t`, concrete subclasses `A` and `B` |
/// | `attributes (...)` of a sum | features of the abstract class `t` |
/// | constructor without fields | concrete subclass without features |
/// | sum whose constructors all lack fields, without attributes | `EEnum t` with one literal per constructor (see ``ASDLEnumerationStyle``) |
/// | `p = (fields)` (product) | concrete `EClass p`; its `attributes` follow the fields |
/// | field of a sum or product type `T x` | containment `EReference x` |
/// | field of an enumeration type | `EAttribute` typed by the `EEnum` |
/// | field of a built-in type | `EAttribute` (see ``ASDLImportOptions/defaultBuiltinTypes``) |
/// | `T x` | `[1..1]` |
/// | `T? x` | `[0..1]` |
/// | `T* x` | `[0..*]`, ordered; attributes not unique |
/// | `T?* x` (CPython) | `[0..*]`, quantifiers kept in an annotation |
/// | unnamed field | generated name, such as `exp1` (see below) |
/// | `N.t` of another module in the text | reference to `t` of package `N` |
/// | `N.t` of a module outside the text | containment of any `EObject`, with a warning |
///
/// The ASDL paper shows enumerations for sums of constructors without fields
/// ("tools should recognize this idiom") and abstract base classes with one
/// subclass per constructor for other sums in Java and C++; the mapping
/// follows both. Fields that hold trees are containments because ASDL
/// describes trees, and the paper's convention for unnamed fields, the field
/// type followed by its occurrence (`stm1`, `stm2`), names generated features.
///
/// Details that Ecore cannot express are kept in annotations with source
/// ``ASDLSyntax/annotationSource``, which ``ASDLWriter`` reads to write the
/// description back.
public enum ASDLReader {
    /// The prefix of the codes of diagnostics reported while building packages.
    static let codePrefix = "asdl"

    /// Reads an ASDL description.
    ///
    /// Reading never fails. Problems are reported as diagnostics, and every
    /// definition that could be read becomes part of a package.
    ///
    /// - Parameters:
    ///   - text: The ASDL text.
    ///   - sourceName: The name of the document, used in diagnostics and to name
    ///     a package when nothing else does.
    ///   - options: The settings that control the mapping.
    /// - Returns: The packages, diagnostics, tokens and outline.
    public static func parse(
        _ text: String, sourceName: String? = nil, options: ASDLImportOptions = .init()
    ) -> ASDLParseResult {
        let (scanned, endRange) = ASDLSyntax.scan(text)
        var collector = DiagnosticCollector(document: sourceName)
        for token in scanned {
            if token.kind == .invalid {
                collector.error(
                    ASDLDiagnosticCode.unexpectedCharacter.rawValue,
                    "The character '\(token.text)' cannot start an ASDL token", at: token.range)
            } else if token.kind == .string && !token.isTerminated {
                collector.error(
                    ASDLDiagnosticCode.unterminatedString.rawValue, "The string has no closing quote",
                    at: token.range)
            }
        }
        var parser = ASDLParser(tokens: scanned, endRange: endRange, document: sourceName)
        let modules = parser.parseModules()
        collector.append(contentsOf: parser.collector.diagnostics)
        var mapper = ASDLMapper(options: options, sourceName: sourceName)
        let drafts = mapper.map(modules)
        collector.append(contentsOf: mapper.collector.diagnostics)
        let (packages, problems) = GrammarMetamodelAssembler(codePrefix: codePrefix, document: sourceName).assemble(drafts)
        collector.append(contentsOf: problems)
        let tokens = scanned.map { token in
            SourceToken(
                kind: parser.roles[token.range.start.utf8Offset] ?? ASDLSyntax.defaultKind(of: token),
                range: token.range)
        }
        return ASDLParseResult(
            packages: packages, diagnostics: collector.sorted, tokens: tokens, outline: modules.map(outline))
    }

    /// The outline node of a module.
    ///
    /// - Parameter module: The module.
    /// - Returns: A node whose children are the type definitions.
    static func outline(_ module: ASDLModule) -> OutlineNode {
        OutlineNode(
            id: module.name, kind: ASDLOutlineKind.module, name: module.name, detail: module.version,
            range: module.range, selectionRange: module.nameRange,
            children: module.definitions.enumerated().map { index, definition in
                outline(definition, parent: module.name, index: index)
            })
    }

    /// The outline node of a definition.
    ///
    /// - Parameters:
    ///   - definition: The definition.
    ///   - parent: The identifier of the module node.
    ///   - index: The position of the definition, which keeps repeated names distinct.
    /// - Returns: A node whose children are constructors, fields and attributes.
    static func outline(_ definition: ASDLDefinition, parent: String, index: Int) -> OutlineNode {
        let id = parent + "/" + definition.name + (index > 0 ? "#\(index)" : "")
        var children: [OutlineNode] = []
        let kind: String
        switch definition.body {
        case .sum(let constructors):
            kind = ASDLOutlineKind.sum
            children = constructors.map { constructor in
                let constructorID = id + "/" + constructor.name
                return OutlineNode(
                    id: constructorID, kind: ASDLOutlineKind.constructor, name: constructor.name,
                    detail: constructor.fields.isEmpty ? nil : "(" + constructor.fields.map(describe).joined(separator: ", ") + ")",
                    range: constructor.range, selectionRange: constructor.nameRange,
                    children: fieldNodes(constructor.fields, parent: constructorID, kind: ASDLOutlineKind.field))
            }
        case .product(let fields):
            kind = ASDLOutlineKind.product
            children = fieldNodes(fields, parent: id, kind: ASDLOutlineKind.field)
        }
        children += fieldNodes(definition.attributes, parent: id + "/attributes", kind: ASDLOutlineKind.attribute)
        return OutlineNode(
            id: id, kind: kind, name: definition.name, range: definition.range,
            selectionRange: definition.nameRange, children: children)
    }

    /// The outline nodes of fields.
    ///
    /// - Parameters:
    ///   - fields: The fields.
    ///   - parent: The identifier of the containing node.
    ///   - kind: The kind of the nodes.
    /// - Returns: One node per field, named by the field or, without a name, by its type.
    static func fieldNodes(_ fields: [ASDLField], parent: String, kind: String) -> [OutlineNode] {
        fields.enumerated().map { index, field in
            OutlineNode(
                id: parent + "/" + String(index), kind: kind, name: field.name ?? field.typeName,
                detail: describeType(field), range: field.range, selectionRange: field.nameRange)
        }
    }

    /// The type of a field as written, such as `expr*`.
    ///
    /// - Parameter field: The field.
    /// - Returns: The qualified type name followed by the quantifiers.
    static func describeType(_ field: ASDLField) -> String {
        (field.module.map { $0 + ASDLSyntax.Symbol.dot } ?? "") + field.typeName + field.quantifiers
    }

    /// A field as written, such as `expr* args`.
    ///
    /// - Parameter field: The field.
    /// - Returns: The type, followed by the name if there is one.
    static func describe(_ field: ASDLField) -> String {
        describeType(field) + (field.name.map { " " + $0 } ?? "")
    }
}
