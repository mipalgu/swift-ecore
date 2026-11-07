//
// KM3SyntaxTree.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// A name in KM3 text with the range of its token.
struct KM3NameNode: Equatable {
    /// The decoded name.
    let text: String

    /// The range of the token that spells the name.
    let range: SourceRange
}

/// The multiplicity of a typed element.
struct KM3MultiplicityNode: Equatable {
    /// The lower bound.
    var lower: Int

    /// The upper bound, or `-1` for an unbounded one.
    var upper: Int

    /// The range of the bracketed multiplicity, or `nil` if it was not written.
    var range: SourceRange?

    /// The multiplicity of an element without a written one: exactly one.
    static let exactlyOne = KM3MultiplicityNode(lower: 1, upper: 1, range: nil)
}

/// A package declaration.
struct KM3PackageNode: Equatable {
    /// The name of the package.
    var name: KM3NameNode

    /// The namespace URI that an `@nsURI` directive gives the package.
    var nsURI: String?

    /// The namespace prefix that an `@nsPrefix` directive gives the package.
    var nsPrefix: String?

    /// The classifiers and nested packages, in source order.
    var elements: [KM3ElementNode] = []

    /// The range of the whole declaration.
    var range: SourceRange
}

/// A declaration inside a package.
enum KM3ElementNode: Equatable {
    /// A nested package.
    case package(KM3PackageNode)

    /// A data type.
    case dataType(KM3DataTypeNode)

    /// An enumeration.
    case enumeration(KM3EnumerationNode)

    /// A class.
    case `class`(KM3ClassNode)
}

/// A data type declaration.
struct KM3DataTypeNode: Equatable {
    /// The name of the data type.
    var name: KM3NameNode

    /// The range of the whole declaration.
    var range: SourceRange
}

/// An enumeration declaration.
struct KM3EnumerationNode: Equatable {
    /// The name of the enumeration.
    var name: KM3NameNode

    /// The literals, in source order.
    var literals: [KM3LiteralNode] = []

    /// The range of the whole declaration.
    var range: SourceRange
}

/// An enumeration literal declaration.
struct KM3LiteralNode: Equatable {
    /// The name of the literal.
    var name: KM3NameNode

    /// The range of the whole declaration.
    var range: SourceRange
}

/// A class declaration.
struct KM3ClassNode: Equatable {
    /// The name of the class.
    var name: KM3NameNode

    /// Whether the class is abstract.
    var isAbstract: Bool

    /// The names of the supertypes, in source order.
    var supertypes: [KM3NameNode] = []

    /// The attributes and references, in source order.
    var features: [KM3FeatureNode] = []

    /// The operations, in source order.
    var operations: [KM3OperationNode] = []

    /// The range of the whole declaration.
    var range: SourceRange
}

/// An attribute or reference declaration.
struct KM3FeatureNode: Equatable {
    /// Whether the feature is an attribute or a reference.
    enum Kind: Equatable {
        /// An attribute, declared with `attribute`.
        case attribute

        /// A reference, declared with `reference`.
        case reference
    }

    /// Whether the feature is an attribute or a reference.
    var kind: Kind

    /// The name of the feature.
    var name: KM3NameNode

    /// The multiplicity of the feature.
    var multiplicity = KM3MultiplicityNode.exactlyOne

    /// Whether the feature is ordered.
    var isOrdered = false

    /// Whether the attribute is unique; references ignore the flag.
    var isUnique = false

    /// Whether the reference contains its targets.
    var isContainer = false

    /// The names of the features that the reference subsets.
    var subsets: [KM3NameNode] = []

    /// The name of the type, or `nil` if it is missing.
    var type: KM3NameNode?

    /// The name of the opposite reference, if any.
    var opposite: KM3NameNode?

    /// The range of the whole declaration.
    var range: SourceRange
}

/// An operation declaration.
struct KM3OperationNode: Equatable {
    /// The name of the operation.
    var name: KM3NameNode

    /// The parameters, in source order.
    var parameters: [KM3ParameterNode] = []

    /// The name of the result type, or `nil` for an operation without a result.
    var returnType: KM3NameNode?

    /// The range of the whole declaration.
    var range: SourceRange
}

/// A parameter of an operation.
struct KM3ParameterNode: Equatable {
    /// The name of the parameter.
    var name: KM3NameNode

    /// The name of the type, or `nil` if it is missing.
    var type: KM3NameNode?

    /// The range of the whole parameter.
    var range: SourceRange
}
