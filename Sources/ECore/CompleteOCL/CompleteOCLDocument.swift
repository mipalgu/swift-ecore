//
// CompleteOCLDocument.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OCL

/// The keywords and outline kinds of Complete OCL.
public enum CompleteOCLSyntax {
    /// The usual file extension of Complete OCL documents.
    public static let fileExtension = "ocl"

    /// The keyword of an import.
    public static let importKeyword = "import"

    /// The keyword of an include.
    public static let includeKeyword = "include"

    /// The keyword of a library import.
    public static let libraryKeyword = "library"

    /// The keyword that opens a package declaration.
    public static let packageKeyword = "package"

    /// The keyword that closes a package declaration.
    public static let endpackageKeyword = "endpackage"

    /// The keyword of a context declaration.
    public static let contextKeyword = "context"

    /// The keyword of an invariant.
    public static let invKeyword = "inv"

    /// The keyword of a definition.
    public static let defKeyword = "def"

    /// The qualifier of a static definition.
    public static let staticKeyword = "static"

    /// The keyword of a precondition.
    public static let preKeyword = "pre"

    /// The keyword of a postcondition.
    public static let postKeyword = "post"

    /// The keyword of an operation body.
    public static let bodyKeyword = "body"

    /// The keyword of an initial value.
    public static let initKeyword = "init"

    /// The keyword of a derivation.
    public static let deriveKeyword = "derive"

    /// The words that start a constraint or declaration, which end an expression and error recovery.
    public static let declarationKeywords: Set<String> = [
        importKeyword, includeKeyword, libraryKeyword, packageKeyword, endpackageKeyword, contextKeyword,
        invKeyword, defKeyword, staticKeyword, preKeyword, postKeyword, bodyKeyword, initKeyword, deriveKeyword,
    ]

    /// The words that tools highlight as Complete OCL keywords.
    public static let keywords: Set<String> = declarationKeywords.union(OCLSyntax.reservedWords)
}

/// The kinds of the outline nodes of a Complete OCL document.
public enum CompleteOCLOutlineKind {
    /// An import.
    public static let `import` = "import"

    /// A package declaration.
    public static let package = "package"

    /// A classifier context.
    public static let classifier = "classifier"

    /// An operation context.
    public static let operation = "operation"

    /// A property context.
    public static let property = "property"

    /// An invariant.
    public static let invariant = "inv"

    /// A definition.
    public static let definition = "def"

    /// A precondition.
    public static let precondition = "pre"

    /// A postcondition.
    public static let postcondition = "post"

    /// An operation body.
    public static let body = "body"

    /// An initial value.
    public static let initial = "init"

    /// A derivation.
    public static let derivation = "derive"
}

/// An import of a Complete OCL document, such as `import 'school.ecore'`.
public struct CompleteOCLImport: Sendable, Hashable {
    /// The keyword used: `import`, `include` or `library`.
    public var keyword: String

    /// The name under which the import is known, if any.
    public var alias: String?

    /// The URI or qualified name of the import, as written.
    public var target: String

    /// Whether the import ends with `::*`.
    public var isAll: Bool

    /// The source range of the import.
    public var range: SourceRange?

    /// Creates an import.
    ///
    /// - Parameters:
    ///   - keyword: The keyword used.
    ///   - alias: The name under which the import is known.
    ///   - target: The URI or qualified name of the import.
    ///   - isAll: Whether the import ends with `::*`.
    ///   - range: The source range of the import.
    public init(keyword: String, alias: String?, target: String, isAll: Bool = false, range: SourceRange? = nil) {
        self.keyword = keyword
        self.alias = alias
        self.target = target
        self.isAll = isAll
        self.range = range
    }
}

/// A named constraint of a Complete OCL document: an invariant, condition, body, initial value
/// or derivation.
public struct CompleteOCLConstraint: Sendable, Hashable {
    /// The name of the constraint, if any.
    public var name: String?

    /// The verbatim text of the message expression, if any.
    public var message: String?

    /// The verbatim text of the expression.
    public var expression: String

    /// The parsed expression, or `nil` if it could not be parsed.
    public var parsedExpression: OCLExpression?

    /// The source range of the constraint.
    public var range: SourceRange?

    /// Creates a constraint.
    ///
    /// - Parameters:
    ///   - name: The name of the constraint.
    ///   - message: The verbatim text of the message expression.
    ///   - expression: The verbatim text of the expression.
    ///   - parsedExpression: The parsed expression.
    ///   - range: The source range of the constraint.
    public init(
        name: String? = nil, message: String? = nil, expression: String, parsedExpression: OCLExpression? = nil,
        range: SourceRange? = nil
    ) {
        self.name = name
        self.message = message
        self.expression = expression
        self.parsedExpression = parsedExpression
        self.range = range
    }
}

/// A parameter of an operation context or definition.
public struct CompleteOCLParameter: Sendable, Hashable {
    /// The name of the parameter, if written.
    public var name: String?

    /// The type of the parameter.
    public var type: OCLTypeReference

    /// Creates a parameter.
    ///
    /// - Parameters:
    ///   - name: The name of the parameter.
    ///   - type: The type of the parameter.
    public init(name: String?, type: OCLTypeReference) {
        self.name = name
        self.type = type
    }
}

/// A `def:` helper that adds an operation or a property to a classifier.
public struct CompleteOCLDefinition: Sendable, Hashable {
    /// Whether the definition is static.
    public var isStatic: Bool

    /// The name of the helper.
    public var name: String

    /// The parameters of an operation helper, or `nil` for a property helper.
    public var parameters: [CompleteOCLParameter]?

    /// The type of the helper, if written.
    public var type: OCLTypeReference?

    /// The defining expression.
    public var specification: CompleteOCLConstraint

    /// The source range of the definition.
    public var range: SourceRange?

    /// Creates a definition.
    ///
    /// - Parameters:
    ///   - isStatic: Whether the definition is static.
    ///   - name: The name of the helper.
    ///   - parameters: The parameters of an operation helper, or `nil` for a property helper.
    ///   - type: The type of the helper.
    ///   - specification: The defining expression.
    ///   - range: The source range of the definition.
    public init(
        isStatic: Bool = false, name: String, parameters: [CompleteOCLParameter]?, type: OCLTypeReference?,
        specification: CompleteOCLConstraint, range: SourceRange? = nil
    ) {
        self.isStatic = isStatic
        self.name = name
        self.parameters = parameters
        self.type = type
        self.specification = specification
        self.range = range
    }

    /// Whether the helper is an operation.
    public var isOperation: Bool { parameters != nil }
}

/// A `context` declaration for a classifier, with invariants and definitions.
public struct CompleteOCLClassifierContext: Sendable, Hashable {
    /// The path of the enclosing package declarations.
    public var packagePath: [String]

    /// The qualified name of the classifier as written.
    public var path: [String]

    /// The name given to `self`, if any.
    public var selfName: String?

    /// The invariants.
    public var invariants: [CompleteOCLConstraint]

    /// The definitions.
    public var definitions: [CompleteOCLDefinition]

    /// The source range of the declaration.
    public var range: SourceRange?

    /// The source range of the classifier name.
    public var nameRange: SourceRange?

    /// Creates a classifier context.
    ///
    /// - Parameters:
    ///   - packagePath: The path of the enclosing package declarations.
    ///   - path: The qualified name of the classifier.
    ///   - selfName: The name given to `self`.
    ///   - invariants: The invariants.
    ///   - definitions: The definitions.
    ///   - range: The source range of the declaration.
    ///   - nameRange: The source range of the classifier name.
    public init(
        packagePath: [String] = [], path: [String], selfName: String? = nil, invariants: [CompleteOCLConstraint] = [],
        definitions: [CompleteOCLDefinition] = [], range: SourceRange? = nil, nameRange: SourceRange? = nil
    ) {
        self.packagePath = packagePath
        self.path = path
        self.selfName = selfName
        self.invariants = invariants
        self.definitions = definitions
        self.range = range
        self.nameRange = nameRange
    }
}

/// A `context` declaration for an operation, with its conditions and body.
public struct CompleteOCLOperationContext: Sendable, Hashable {
    /// The path of the enclosing package declarations.
    public var packagePath: [String]

    /// The qualified name of the operation as written, ending with its name.
    public var path: [String]

    /// The parameters as written.
    public var parameters: [CompleteOCLParameter]

    /// The result type, if written.
    public var resultType: OCLTypeReference?

    /// The preconditions.
    public var preconditions: [CompleteOCLConstraint]

    /// The postconditions.
    public var postconditions: [CompleteOCLConstraint]

    /// The bodies (at most one is meaningful).
    public var bodies: [CompleteOCLConstraint]

    /// The source range of the declaration.
    public var range: SourceRange?

    /// The source range of the operation name.
    public var nameRange: SourceRange?

    /// Creates an operation context.
    ///
    /// - Parameters:
    ///   - packagePath: The path of the enclosing package declarations.
    ///   - path: The qualified name of the operation.
    ///   - parameters: The parameters.
    ///   - resultType: The result type.
    ///   - preconditions: The preconditions.
    ///   - postconditions: The postconditions.
    ///   - bodies: The bodies.
    ///   - range: The source range of the declaration.
    ///   - nameRange: The source range of the operation name.
    public init(
        packagePath: [String] = [], path: [String], parameters: [CompleteOCLParameter] = [], resultType: OCLTypeReference? = nil,
        preconditions: [CompleteOCLConstraint] = [], postconditions: [CompleteOCLConstraint] = [],
        bodies: [CompleteOCLConstraint] = [], range: SourceRange? = nil, nameRange: SourceRange? = nil
    ) {
        self.packagePath = packagePath
        self.path = path
        self.parameters = parameters
        self.resultType = resultType
        self.preconditions = preconditions
        self.postconditions = postconditions
        self.bodies = bodies
        self.range = range
        self.nameRange = nameRange
    }
}

/// A `context` declaration for a property, with its initial value and derivation.
public struct CompleteOCLPropertyContext: Sendable, Hashable {
    /// The path of the enclosing package declarations.
    public var packagePath: [String]

    /// The qualified name of the property as written, ending with its name.
    public var path: [String]

    /// The type as written.
    public var type: OCLTypeReference?

    /// The initial values (at most one is meaningful).
    public var initialisers: [CompleteOCLConstraint]

    /// The derivations (at most one is meaningful).
    public var derivations: [CompleteOCLConstraint]

    /// The source range of the declaration.
    public var range: SourceRange?

    /// The source range of the property name.
    public var nameRange: SourceRange?

    /// Creates a property context.
    ///
    /// - Parameters:
    ///   - packagePath: The path of the enclosing package declarations.
    ///   - path: The qualified name of the property.
    ///   - type: The type.
    ///   - initialisers: The initial values.
    ///   - derivations: The derivations.
    ///   - range: The source range of the declaration.
    ///   - nameRange: The source range of the property name.
    public init(
        packagePath: [String] = [], path: [String], type: OCLTypeReference? = nil, initialisers: [CompleteOCLConstraint] = [],
        derivations: [CompleteOCLConstraint] = [], range: SourceRange? = nil, nameRange: SourceRange? = nil
    ) {
        self.packagePath = packagePath
        self.path = path
        self.type = type
        self.initialisers = initialisers
        self.derivations = derivations
        self.range = range
        self.nameRange = nameRange
    }
}

/// A `package ... endpackage` declaration.
public struct CompleteOCLPackageDeclaration: Sendable, Hashable {
    /// The qualified name of the package.
    public var path: [String]

    /// The source range of the declaration.
    public var range: SourceRange?

    /// Creates a package declaration.
    ///
    /// - Parameters:
    ///   - path: The qualified name of the package.
    ///   - range: The source range of the declaration.
    public init(path: [String], range: SourceRange? = nil) {
        self.path = path
        self.range = range
    }
}

/// A Complete OCL document: imports, package declarations and contexts.
///
/// The contexts are listed by kind, in source order; each records the package declaration
/// that encloses it, if any.
public struct CompleteOCLDocument: Sendable, Hashable {
    /// The imports.
    public var imports: [CompleteOCLImport]

    /// The package declarations.
    public var packages: [CompleteOCLPackageDeclaration]

    /// The classifier contexts, with their invariants and definitions.
    public var classifierContexts: [CompleteOCLClassifierContext]

    /// The operation contexts, with their preconditions, postconditions and bodies.
    public var operationContexts: [CompleteOCLOperationContext]

    /// The property contexts, with their initial values and derivations.
    public var propertyContexts: [CompleteOCLPropertyContext]

    /// Creates a document.
    ///
    /// - Parameters:
    ///   - imports: The imports.
    ///   - packages: The package declarations.
    ///   - classifierContexts: The classifier contexts.
    ///   - operationContexts: The operation contexts.
    ///   - propertyContexts: The property contexts.
    public init(
        imports: [CompleteOCLImport] = [], packages: [CompleteOCLPackageDeclaration] = [],
        classifierContexts: [CompleteOCLClassifierContext] = [], operationContexts: [CompleteOCLOperationContext] = [],
        propertyContexts: [CompleteOCLPropertyContext] = []
    ) {
        self.imports = imports
        self.packages = packages
        self.classifierContexts = classifierContexts
        self.operationContexts = operationContexts
        self.propertyContexts = propertyContexts
    }

    /// Every constraint of the document, with the kind of outline node that describes it.
    public var allConstraints: [(kind: String, constraint: CompleteOCLConstraint)] {
        /// The kinds of outline node.
        typealias Kind = CompleteOCLOutlineKind
        var result: [(kind: String, constraint: CompleteOCLConstraint)] = []
        for context in classifierContexts {
            for invariant in context.invariants { result.append((Kind.invariant, invariant)) }
            for definition in context.definitions { result.append((Kind.definition, definition.specification)) }
        }
        for context in operationContexts {
            for condition in context.preconditions { result.append((Kind.precondition, condition)) }
            for body in context.bodies { result.append((Kind.body, body)) }
            for condition in context.postconditions { result.append((Kind.postcondition, condition)) }
        }
        for context in propertyContexts {
            for initial in context.initialisers { result.append((Kind.initial, initial)) }
            for derivation in context.derivations { result.append((Kind.derivation, derivation)) }
        }
        return result
    }
}
