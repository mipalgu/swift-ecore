//
// OCLinEcoreDeclarations.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OCL

/// An import of an OCLinEcore document, such as `import ecore : 'http://www.eclipse.org/emf/2002/Ecore#/';`.
public struct OCLinEcoreImport: Sendable, Hashable {
    /// The name under which the imported package is known, if any.
    public var alias: String?

    /// The URI or qualified name of the imported package, as written.
    public var target: String

    /// Whether the import names an OCL library rather than a metamodel.
    public var isLibrary: Bool

    /// The source range of the import.
    public var range: SourceRange?

    /// Creates an import.
    ///
    /// - Parameters:
    ///   - alias: The name under which the package is known.
    ///   - target: The URI or qualified name of the package.
    ///   - isLibrary: Whether the import names an OCL library.
    ///   - range: The source range of the import.
    public init(alias: String?, target: String, isLibrary: Bool = false, range: SourceRange? = nil) {
        self.alias = alias
        self.target = target
        self.isLibrary = isLibrary
        self.range = range
    }
}

/// A specification: the verbatim text of an OCL expression and where it was written.
struct SpecificationDeclaration {
    /// The name written after the keyword, if any.
    var name: String?

    /// The verbatim text of the message expression, if any.
    var message: String?

    /// The verbatim text of the expression, or `nil` if none was written.
    var text: String?

    /// The source range of the whole declaration.
    var range: SourceRange
}

/// An annotation, documentation or SysML block.
struct AnnotationDeclaration {
    /// The kinds of annotation blocks.
    enum Kind {
        /// `annotation 'source' (...)`.
        case annotation(source: String?)

        /// `documentation 'text' (...)`.
        case documentation(text: String?)

        /// `sysml { ... }`.
        case sysml
    }

    /// The kind of block.
    var kind: Kind

    /// The details in order.
    var details: [(key: String, value: String)] = []

    /// The nested annotations.
    var children: [AnnotationDeclaration] = []

    /// The source range of the block.
    var range: SourceRange
}

/// The parts shared by every named declaration.
struct DeclarationHeader {
    /// The name of the element.
    var name: String

    /// The source range of the name.
    var nameRange: SourceRange

    /// The source range of the declaration.
    var range: SourceRange
}

/// A structural feature declaration.
struct FeatureDeclaration {
    /// Whether the declaration used `attribute` rather than `property`.
    var isAttribute: Bool

    /// The name and ranges.
    var header: DeclarationHeader

    /// The opposite named after `#`, if any.
    var opposite: String?

    /// The type, if any.
    var type: OCLTypeReference?

    /// The default value literal, if any.
    var defaultValue: String?

    /// The qualifiers, with `true` for a positive and `false` for a negated one.
    var qualifiers: [String: Bool] = [:]

    /// The prefixes `static` or `definition` written before the keyword.
    var prefixes: [String] = []

    /// The annotations.
    var annotations: [AnnotationDeclaration] = []

    /// The initial value specification, if any.
    var initial: SpecificationDeclaration?

    /// The derivation specification, if any.
    var derivation: SpecificationDeclaration?

    /// The names of the keys of a reference.
    var keys: [(name: String, range: SourceRange)] = []
}

/// A parameter declaration.
struct ParameterDeclaration {
    /// The name and ranges.
    var header: DeclarationHeader

    /// The type, if any.
    var type: OCLTypeReference?

    /// The qualifiers.
    var qualifiers: [String: Bool] = [:]

    /// The annotations.
    var annotations: [AnnotationDeclaration] = []
}

/// An operation declaration.
struct OperationDeclaration {
    /// The name and ranges.
    var header: DeclarationHeader

    /// The parameters in order.
    var parameters: [ParameterDeclaration] = []

    /// The return type, if any.
    var type: OCLTypeReference?

    /// The exceptions.
    var exceptions: [OCLTypeReference] = []

    /// The qualifiers.
    var qualifiers: [String: Bool] = [:]

    /// The annotations.
    var annotations: [AnnotationDeclaration] = []

    /// The preconditions.
    var preconditions: [SpecificationDeclaration] = []

    /// The postconditions.
    var postconditions: [SpecificationDeclaration] = []

    /// The body, if any.
    var body: SpecificationDeclaration?
}

/// A class, data type or enumeration declaration.
struct ClassifierDeclaration {
    /// The kinds of classifiers.
    enum Kind {
        /// A class.
        case `class`(isAbstract: Bool, isInterface: Bool)

        /// A data type.
        case dataType(isPrimitive: Bool)

        /// An enumeration.
        case enumeration
    }

    /// The kind of classifier.
    var kind: Kind

    /// The name and ranges.
    var header: DeclarationHeader

    /// The supertypes of a class.
    var superTypes: [OCLTypeReference] = []

    /// The instance class name, if any.
    var instanceClassName: String?

    /// Whether a data type or enumeration is serialisable, if stated.
    var isSerializable: Bool?

    /// The annotations.
    var annotations: [AnnotationDeclaration] = []

    /// The invariants.
    var invariants: [SpecificationDeclaration] = []

    /// The structural features of a class.
    var features: [FeatureDeclaration] = []

    /// The operations of a class.
    var operations: [OperationDeclaration] = []

    /// The literals of an enumeration: name, literal string, value and annotations.
    var literals: [(header: DeclarationHeader, literal: String?, value: Int?, annotations: [AnnotationDeclaration])] = []
}

/// A package declaration.
struct PackageDeclaration {
    /// The name and ranges.
    var header: DeclarationHeader

    /// The namespace prefix, if any.
    var nsPrefix: String?

    /// The namespace URI, if any.
    var nsURI: String?

    /// The annotations.
    var annotations: [AnnotationDeclaration] = []

    /// The subpackages.
    var packages: [PackageDeclaration] = []

    /// The classifiers.
    var classifiers: [ClassifierDeclaration] = []
}

/// An OCLinEcore document as declared.
struct OCLinEcoreDocumentDeclaration {
    /// The module name, if any.
    var module: String?

    /// The imports.
    var imports: [OCLinEcoreImport] = []

    /// The root packages.
    var packages: [PackageDeclaration] = []
}
