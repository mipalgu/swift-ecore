//
// GrammarMetamodelDraft.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// A type named by a draft feature or supertype list.
///
/// Drafts name types instead of holding them, so that a front end can describe
/// classifiers in any order, including classifiers that refer to each other.
enum GrammarDraftTypeReference: Sendable, Hashable {
    /// A classifier of a draft package, by name.
    ///
    /// Without a package name the classifier is looked up in the package of
    /// the element that names it, then in the other draft packages.
    case named(String, package: String? = nil)

    /// A built-in data type of Ecore.
    case ecore(EcoreDataType)

    /// The root class `EObject` of Ecore.
    case eObject

    /// A short description for diagnostics.
    var displayName: String {
        switch self {
        case .named(let name, let package): package.map { "\($0).\(name)" } ?? name
        case .ecore(let type): type.rawValue
        case .eObject: EcoreClassifier.eObject.rawValue
        }
    }
}

/// An annotation of a draft element.
struct GrammarDraftAnnotation: Sendable, Hashable {
    /// The source URI of the annotation.
    var source: String

    /// The detail entries, in order.
    var details: [GrammarDraftDetail]

    /// Creates an annotation.
    ///
    /// - Parameters:
    ///   - source: The source URI of the annotation.
    ///   - details: The detail entries, in order.
    init(source: String, details: [GrammarDraftDetail]) {
        self.source = source
        self.details = details
    }
}

/// A key and value of an annotation.
struct GrammarDraftDetail: Sendable, Hashable {
    /// The key.
    var key: String

    /// The value.
    var value: String

    /// Creates a detail entry.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - value: The value.
    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }
}

/// A structural feature to be built.
///
/// Whether the feature becomes an attribute or a reference follows from its
/// type: a feature typed by a class is a reference, any other an attribute.
struct GrammarDraftFeature: Sendable, Hashable {
    /// The name of the feature.
    var name: String

    /// The type of the feature.
    var type: GrammarDraftTypeReference

    /// The lower bound.
    var lowerBound: Int

    /// The upper bound, where `-1` is unbounded.
    var upperBound: Int

    /// Whether a reference contains its targets.
    var isContainment: Bool

    /// Whether the values are ordered.
    var isOrdered: Bool

    /// Whether the values are unique.
    var isUnique: Bool

    /// The default value as text, if any.
    var defaultValueLiteral: String?

    /// The annotations of the feature.
    var annotations: [GrammarDraftAnnotation]

    /// The source text that defines the feature, for diagnostics.
    var range: SourceRange?

    /// Creates a feature.
    ///
    /// - Parameters:
    ///   - name: The name of the feature.
    ///   - type: The type of the feature.
    ///   - lowerBound: The lower bound; defaults to zero.
    ///   - upperBound: The upper bound; defaults to one.
    ///   - isContainment: Whether a reference contains its targets; defaults to `true`.
    ///   - isOrdered: Whether the values are ordered; defaults to `true`.
    ///   - isUnique: Whether the values are unique; defaults to `true`.
    ///   - defaultValueLiteral: The default value as text.
    ///   - annotations: The annotations of the feature.
    ///   - range: The source text that defines the feature.
    init(
        name: String, type: GrammarDraftTypeReference, lowerBound: Int = 0, upperBound: Int = 1,
        isContainment: Bool = true, isOrdered: Bool = true, isUnique: Bool = true,
        defaultValueLiteral: String? = nil, annotations: [GrammarDraftAnnotation] = [], range: SourceRange? = nil
    ) {
        self.name = name
        self.type = type
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.isContainment = isContainment
        self.isOrdered = isOrdered
        self.isUnique = isUnique
        self.defaultValueLiteral = defaultValueLiteral
        self.annotations = annotations
        self.range = range
    }

    /// Whether the feature holds more than one value.
    var isMany: Bool { upperBound == -1 || upperBound > 1 }
}

/// A class to be built.
struct GrammarDraftClass: Sendable, Hashable {
    /// The name of the class.
    var name: String

    /// Whether the class is abstract.
    var isAbstract: Bool

    /// Whether the class is an interface.
    var isInterface: Bool

    /// The direct supertypes, in order.
    var superTypes: [GrammarDraftTypeReference]

    /// The features the class declares, in order.
    var features: [GrammarDraftFeature]

    /// The annotations of the class.
    var annotations: [GrammarDraftAnnotation]

    /// The source text that defines the class, for diagnostics.
    var range: SourceRange?

    /// Creates a class.
    ///
    /// - Parameters:
    ///   - name: The name of the class.
    ///   - isAbstract: Whether the class is abstract.
    ///   - isInterface: Whether the class is an interface.
    ///   - superTypes: The direct supertypes.
    ///   - features: The features the class declares.
    ///   - annotations: The annotations of the class.
    ///   - range: The source text that defines the class.
    init(
        name: String, isAbstract: Bool = false, isInterface: Bool = false,
        superTypes: [GrammarDraftTypeReference] = [], features: [GrammarDraftFeature] = [],
        annotations: [GrammarDraftAnnotation] = [], range: SourceRange? = nil
    ) {
        self.name = name
        self.isAbstract = isAbstract
        self.isInterface = isInterface
        self.superTypes = superTypes
        self.features = features
        self.annotations = annotations
        self.range = range
    }
}

/// A data type to be built.
struct GrammarDraftDataType: Sendable, Hashable {
    /// The name of the data type.
    var name: String

    /// The name of the class that implements the values, if any.
    var instanceClassName: String?

    /// The annotations of the data type.
    var annotations: [GrammarDraftAnnotation]

    /// The source text that defines the data type, for diagnostics.
    var range: SourceRange?

    /// Creates a data type.
    ///
    /// - Parameters:
    ///   - name: The name of the data type.
    ///   - instanceClassName: The name of the implementing class.
    ///   - annotations: The annotations of the data type.
    ///   - range: The source text that defines the data type.
    init(
        name: String, instanceClassName: String? = nil, annotations: [GrammarDraftAnnotation] = [],
        range: SourceRange? = nil
    ) {
        self.name = name
        self.instanceClassName = instanceClassName
        self.annotations = annotations
        self.range = range
    }
}

/// A literal of a draft enumeration.
struct GrammarDraftLiteral: Sendable, Hashable {
    /// The name of the literal.
    var name: String

    /// The literal text, if it differs from the name.
    var literal: String?

    /// The source text that defines the literal, for diagnostics.
    var range: SourceRange?

    /// Creates a literal.
    ///
    /// - Parameters:
    ///   - name: The name of the literal.
    ///   - literal: The literal text, if it differs from the name.
    ///   - range: The source text that defines the literal.
    init(name: String, literal: String? = nil, range: SourceRange? = nil) {
        self.name = name
        self.literal = literal
        self.range = range
    }
}

/// An enumeration to be built.
struct GrammarDraftEnum: Sendable, Hashable {
    /// The name of the enumeration.
    var name: String

    /// The literals, in order; their values are their positions.
    var literals: [GrammarDraftLiteral]

    /// The annotations of the enumeration.
    var annotations: [GrammarDraftAnnotation]

    /// The source text that defines the enumeration, for diagnostics.
    var range: SourceRange?

    /// Creates an enumeration.
    ///
    /// - Parameters:
    ///   - name: The name of the enumeration.
    ///   - literals: The literals, in order.
    ///   - annotations: The annotations of the enumeration.
    ///   - range: The source text that defines the enumeration.
    init(
        name: String, literals: [GrammarDraftLiteral] = [], annotations: [GrammarDraftAnnotation] = [], range: SourceRange? = nil
    ) {
        self.name = name
        self.literals = literals
        self.annotations = annotations
        self.range = range
    }
}

/// A classifier to be built.
enum GrammarDraftClassifier: Sendable, Hashable {
    /// A class.
    case eClass(GrammarDraftClass)
    /// A data type.
    case dataType(GrammarDraftDataType)
    /// An enumeration.
    case eEnum(GrammarDraftEnum)

    /// The name of the classifier.
    var name: String {
        switch self {
        case .eClass(let value): value.name
        case .dataType(let value): value.name
        case .eEnum(let value): value.name
        }
    }

    /// The source text that defines the classifier.
    var range: SourceRange? {
        switch self {
        case .eClass(let value): value.range
        case .dataType(let value): value.range
        case .eEnum(let value): value.range
        }
    }

    /// Whether the classifier is a class.
    var isClass: Bool {
        if case .eClass = self { return true }
        return false
    }
}

/// A package to be built.
struct GrammarDraftPackage: Sendable, Hashable {
    /// The name of the package.
    var name: String

    /// The namespace URI.
    var nsURI: String

    /// The namespace prefix.
    var nsPrefix: String

    /// The classifiers, in order.
    var classifiers: [GrammarDraftClassifier]

    /// The annotations of the package.
    var annotations: [GrammarDraftAnnotation]

    /// The source text that defines the package, for diagnostics.
    var range: SourceRange?

    /// Creates a package.
    ///
    /// - Parameters:
    ///   - name: The name of the package.
    ///   - nsURI: The namespace URI.
    ///   - nsPrefix: The namespace prefix.
    ///   - classifiers: The classifiers, in order.
    ///   - annotations: The annotations of the package.
    ///   - range: The source text that defines the package.
    init(
        name: String, nsURI: String, nsPrefix: String, classifiers: [GrammarDraftClassifier] = [],
        annotations: [GrammarDraftAnnotation] = [], range: SourceRange? = nil
    ) {
        self.name = name
        self.nsURI = nsURI
        self.nsPrefix = nsPrefix
        self.classifiers = classifiers
        self.annotations = annotations
        self.range = range
    }

    /// The classifier with a name, if any.
    ///
    /// - Parameter name: The name to look for.
    /// - Returns: The first classifier with that name.
    func classifier(named name: String) -> GrammarDraftClassifier? {
        classifiers.first { $0.name == name }
    }
}
