//
// OCLinEcoreVocabulary.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import OCL

/// The keywords, qualifiers and outline kinds of OCLinEcore.
///
/// OCLinEcore keywords are contextual: most of them may also name elements, so the reader only
/// treats a word as a keyword where the grammar expects one, and the writer escapes only the
/// words that Essential OCL reserves.
public enum OCLinEcoreSyntax {
    /// The usual file extension of OCLinEcore documents.
    public static let fileExtension = "oclinecore"

    /// The keyword that names the module of a document.
    public static let moduleKeyword = "module"

    /// The keyword of an import.
    public static let importKeyword = "import"

    /// The keyword of a library import.
    public static let libraryKeyword = "library"

    /// The keyword of a package.
    public static let packageKeyword = "package"

    /// The keyword of a class.
    public static let classKeyword = "class"

    /// The qualifier of an abstract class.
    public static let abstractKeyword = "abstract"

    /// The keyword that lists the supertypes of a class.
    public static let extendsKeyword = "extends"

    /// The qualifier of an interface.
    public static let interfaceKeyword = "interface"

    /// The keyword of a data type.
    public static let datatypeKeyword = "datatype"

    /// The qualifier of a primitive data type.
    public static let primitiveKeyword = "primitive"

    /// The qualifier of a serialisable data type or enumeration.
    public static let serializableKeyword = "serializable"

    /// The keyword of an enumeration.
    public static let enumKeyword = "enum"

    /// The keyword that introduces an enumeration literal whose name is a keyword.
    public static let literalKeyword = "literal"

    /// The keyword of an attribute.
    public static let attributeKeyword = "attribute"

    /// The keyword of a reference, or of an attribute whose type is a data type.
    public static let propertyKeyword = "property"

    /// The keyword of an operation.
    public static let operationKeyword = "operation"

    /// The keyword that lists the exceptions of an operation.
    public static let throwsKeyword = "throws"

    /// The keyword of an invariant.
    public static let invariantKeyword = "invariant"

    /// The qualifier of an invariant that is also an operation.
    public static let callableKeyword = "callable"

    /// The keyword of a precondition.
    public static let preconditionKeyword = "precondition"

    /// The keyword of a postcondition.
    public static let postconditionKeyword = "postcondition"

    /// The keyword of the body of an operation.
    public static let bodyKeyword = "body"

    /// The keyword of the initial value of a feature.
    public static let initialKeyword = "initial"

    /// The keyword of the derivation of a feature.
    public static let derivationKeyword = "derivation"

    /// The keyword that lists the keys of a reference.
    public static let keyKeyword = "key"

    /// The keyword of an implicit opposite.
    public static let oppositeKeyword = "opposite"

    /// The keyword of an annotation.
    public static let annotationKeyword = "annotation"

    /// The keyword of documentation.
    public static let documentationKeyword = "documentation"

    /// The keyword of a SysML annotation.
    public static let sysmlKeyword = "sysml"

    /// The keyword that refers to a model element from an annotation.
    public static let referenceKeyword = "reference"

    /// The qualifier of a static feature or operation.
    public static let staticKeyword = "static"

    /// The qualifier of an experimental definition.
    public static let definitionKeyword = "definition"

    /// The prefix that negates a qualifier.
    public static let negation = "!"

    /// The qualifier of a containment reference.
    public static let composes = "composes"

    /// The qualifier of a derived feature or operation.
    public static let derived = "derived"

    /// The qualifier of an identifying attribute.
    public static let id = "id"

    /// The qualifier of ordered values.
    public static let ordered = "ordered"

    /// The qualifier of a feature that cannot be changed.
    public static let readonly = "readonly"

    /// The qualifier of a reference whose proxies are resolved.
    public static let resolve = "resolve"

    /// The qualifier of a feature that is not saved.
    public static let transient = "transient"

    /// The qualifier of unique values.
    public static let unique = "unique"

    /// The qualifier of a feature that can be unset.
    public static let unsettable = "unsettable"

    /// The qualifier of a feature that is computed when read.
    public static let volatile = "volatile"

    /// The qualifiers of an attribute, in the order the writer writes them.
    public static let attributeQualifiers = [derived, id, ordered, readonly, transient, unique, unsettable, volatile]

    /// The qualifiers of a reference, in the order the writer writes them.
    public static let referenceQualifiers = [composes, derived, ordered, readonly, resolve, transient, unique, unsettable, volatile]

    /// The qualifiers of an operation.
    public static let operationQualifiers = [derived, ordered, transient, unique]

    /// The qualifiers of a parameter or implicit opposite.
    public static let parameterQualifiers = [ordered, unique]

    /// The value each qualifier has when it is not written.
    ///
    /// The defaults follow UML, as Eclipse OCL documents them, except that proxies are
    /// resolved by default as Eclipse OCL writes references in practice.
    public static let qualifierDefaults: [String: Bool] = [
        composes: false, derived: false, id: false, ordered: false, readonly: false, resolve: true,
        transient: false, unique: true, unsettable: false, volatile: false,
    ]

    /// The words that start a declaration and so end error recovery.
    public static let declarationKeywords: Set<String> = [
        packageKeyword, classKeyword, abstractKeyword, datatypeKeyword, primitiveKeyword, enumKeyword,
        attributeKeyword, propertyKeyword, operationKeyword, invariantKeyword, callableKeyword,
        annotationKeyword, documentationKeyword, sysmlKeyword, staticKeyword, definitionKeyword,
        preconditionKeyword, postconditionKeyword, bodyKeyword, initialKeyword, derivationKeyword,
        keyKeyword, importKeyword, libraryKeyword, literalKeyword,
    ]

    /// The words that tools highlight as OCLinEcore keywords.
    public static let keywords: Set<String> = declarationKeywords.union(OCLSyntax.reservedWords).union([
        moduleKeyword, extendsKeyword, interfaceKeyword, serializableKeyword, throwsKeyword, oppositeKeyword,
        referenceKeyword, composes, derived, id, ordered, readonly, resolve, transient, unique, unsettable, volatile,
    ])

    /// The words that cannot name an element without escaping, as the Eclipse OCL lexer
    /// treats them as keywords of Essential OCL.
    public static let escapedWords: Set<String> = OCLSyntax.reservedWords
        .union(OCLSyntax.collectionTypeNames).union(OCLSyntax.primitiveTypeNames)
        .union([OCLSyntax.tupleTypeName, OCLSyntax.mapTypeName, OCLSyntax.lambdaName])
}

/// The kinds of the outline nodes of an OCLinEcore document.
public enum OCLinEcoreOutlineKind {
    /// A package.
    public static let package = "package"

    /// A class.
    public static let `class` = "class"

    /// A data type.
    public static let dataType = "datatype"

    /// An enumeration.
    public static let enumeration = "enum"

    /// An enumeration literal.
    public static let literal = "literal"

    /// An attribute.
    public static let attribute = "attribute"

    /// A reference.
    public static let reference = "property"

    /// An operation.
    public static let operation = "operation"

    /// An invariant.
    public static let invariant = "invariant"

    /// A precondition.
    public static let precondition = "precondition"

    /// A postcondition.
    public static let postcondition = "postcondition"

    /// The body of an operation.
    public static let body = "body"

    /// The initial value of a feature.
    public static let initial = "initial"

    /// The derivation of a feature.
    public static let derivation = "derivation"

    /// An import.
    public static let `import` = "import"
}
