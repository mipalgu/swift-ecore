//
// MetamodelDraft.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// A key and value of an annotation as written in a textual notation.
struct DraftDetail: Sendable, Hashable {
    /// The key of the detail.
    var key: String

    /// The value of the detail.
    var value: String

    /// Creates a detail.
    ///
    /// - Parameters:
    ///   - key: The key of the detail.
    ///   - value: The value of the detail.
    init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// An annotation as written in a textual notation, with its source already resolved.
struct DraftAnnotation: Sendable, Hashable {
    /// The source URI of the annotation.
    var source: String

    /// The details of the annotation in source order.
    var details: [DraftDetail]

    /// The source range of the annotation.
    var range: SourceRange?

    /// Creates an annotation.
    ///
    /// - Parameters:
    ///   - source: The source URI of the annotation.
    ///   - details: The details in source order.
    ///   - range: The source range of the annotation.
    init(source: String, details: [DraftDetail] = [], range: SourceRange? = nil) {
        self.source = source
        self.details = details
        self.range = range
    }
}

/// A generic type as written in a textual notation, before its names are resolved.
struct DraftType: Sendable, Hashable {
    /// The kind of wildcard that a type argument is.
    enum Wildcard: Sendable, Hashable {
        /// A wildcard without a bound, written `?`.
        case unbounded

        /// A wildcard with an upper bound, written `? extends T`.
        case upper

        /// A wildcard with a lower bound, written `? super T`.
        case lower
    }

    /// The type name as written, possibly qualified, or empty for a wildcard.
    var name: String

    /// The type arguments, in source order.
    var arguments: [DraftType]

    /// The kind of wildcard, or `nil` if the type is not a wildcard.
    var wildcard: Wildcard?

    /// The bound of a wildcard: empty, or one type.
    var bounds: [DraftType]

    /// The source range of the type.
    var range: SourceRange?

    /// Creates a type reference.
    ///
    /// - Parameters:
    ///   - name: The type name as written.
    ///   - arguments: The type arguments.
    ///   - wildcard: The kind of wildcard, if the type is one.
    ///   - bounds: The bound of a wildcard.
    ///   - range: The source range of the type.
    init(
        name: String, arguments: [DraftType] = [], wildcard: Wildcard? = nil, bounds: [DraftType] = [],
        range: SourceRange? = nil
    ) {
        self.name = name
        self.arguments = arguments
        self.wildcard = wildcard
        self.bounds = bounds
        self.range = range
    }

    /// The type as text, in the common notation `Name<Argument, ? extends Bound>`.
    var text: String {
        switch wildcard {
        case .unbounded: return "?"
        case .upper: return "? extends " + (bounds.first?.text ?? "")
        case .lower: return "? super " + (bounds.first?.text ?? "")
        case nil:
            guard !arguments.isEmpty else { return name }
            return name + "<" + arguments.map(\.text).joined(separator: ", ") + ">"
        }
    }
}

/// A type parameter as written in a textual notation.
struct DraftTypeParameter: Sendable, Hashable {
    /// The name of the parameter.
    var name: String

    /// The bounds of the parameter.
    var bounds: [DraftType]

    /// The annotations of the parameter.
    var annotations: [DraftAnnotation]

    /// The source range of the parameter.
    var range: SourceRange?

    /// Creates a type parameter.
    ///
    /// - Parameters:
    ///   - name: The name of the parameter.
    ///   - bounds: The bounds of the parameter.
    ///   - annotations: The annotations of the parameter.
    ///   - range: The source range of the parameter.
    init(
        name: String, bounds: [DraftType] = [], annotations: [DraftAnnotation] = [], range: SourceRange? = nil
    ) {
        self.name = name
        self.bounds = bounds
        self.annotations = annotations
        self.range = range
    }
}

/// The source ranges of a declaration: all of it, and its name.
struct DraftLocation: Sendable, Hashable {
    /// The range of the whole declaration.
    var range: SourceRange

    /// The range of the name of the declaration.
    var nameRange: SourceRange

    /// Creates a location.
    ///
    /// - Parameters:
    ///   - range: The range of the whole declaration.
    ///   - nameRange: The range of the name.
    init(range: SourceRange, nameRange: SourceRange) {
        self.range = range
        self.nameRange = nameRange
    }

    /// A location at the start of a text, for declarations made without source.
    static let none = DraftLocation(
        range: SourceRange(start: .start, end: .start), nameRange: SourceRange(start: .start, end: .start))
}

/// A structural feature (attribute or reference) as written in a textual notation.
struct DraftFeature: Sendable, Hashable {
    /// Whether a feature is an attribute or a reference.
    enum Kind: Sendable, Hashable {
        /// An attribute, whose type is a data type.
        case attribute

        /// A reference, whose type is a class.
        case reference

        /// An attribute if the type resolves to a data type, otherwise a reference.
        case inferred
    }

    /// Whether the feature is an attribute or a reference.
    var kind: Kind

    /// The name of the feature.
    var name: String

    /// The type of the feature.
    var type: DraftType

    /// The lower bound of the multiplicity.
    var lowerBound = 0

    /// The upper bound of the multiplicity, `-1` for unbounded and `-2` for unspecified.
    var upperBound = 1

    /// Whether the value of the feature can be changed.
    var changeable = true

    /// Whether the value of the feature is computed rather than stored in a field.
    var volatile = false

    /// Whether the value of the feature is not serialised.
    var transient = false

    /// Whether the feature distinguishes an unset value from the default.
    var unsettable = false

    /// Whether the value of the feature is derived from other features.
    var derived = false

    /// Whether the values of a many-valued feature are unique.
    var unique = true

    /// Whether the values of a many-valued feature are ordered.
    var ordered = true

    /// Whether a reference resolves proxies.
    var resolveProxies = true

    /// Whether an attribute identifies its object.
    var isID = false

    /// Whether a reference contains its values.
    var containment = false

    /// The name of the opposite reference in the target class, if any.
    var opposite: String?

    /// The source range of the opposite name, if any.
    var oppositeRange: SourceRange?

    /// The names of the key attributes of a reference.
    var keys: [String] = []

    /// The source ranges of the key names.
    var keyRanges: [SourceRange] = []

    /// The default value literal of an attribute, if any.
    var defaultValue: String?

    /// The annotations of the feature.
    var annotations: [DraftAnnotation] = []

    /// The source location of the feature.
    var location: DraftLocation

    /// Creates a feature with default flags.
    ///
    /// - Parameters:
    ///   - kind: Whether the feature is an attribute or a reference.
    ///   - name: The name of the feature.
    ///   - type: The type of the feature.
    ///   - location: The source location of the feature.
    init(kind: Kind, name: String, type: DraftType, location: DraftLocation = .none) {
        self.kind = kind
        self.name = name
        self.type = type
        self.location = location
    }
}

/// A parameter of an operation as written in a textual notation.
struct DraftParameter: Sendable, Hashable {
    /// The name of the parameter.
    var name: String

    /// The type of the parameter.
    var type: DraftType

    /// The lower bound of the multiplicity.
    var lowerBound = 0

    /// The upper bound of the multiplicity.
    var upperBound = 1

    /// Whether the values of a many-valued parameter are ordered.
    var ordered = true

    /// Whether the values of a many-valued parameter are unique.
    var unique = true

    /// The annotations of the parameter.
    var annotations: [DraftAnnotation] = []

    /// The source location of the parameter.
    var location: DraftLocation

    /// Creates a parameter with default flags.
    ///
    /// - Parameters:
    ///   - name: The name of the parameter.
    ///   - type: The type of the parameter.
    ///   - location: The source location of the parameter.
    init(name: String, type: DraftType, location: DraftLocation = .none) {
        self.name = name
        self.type = type
        self.location = location
    }
}

/// An operation as written in a textual notation.
struct DraftOperation: Sendable, Hashable {
    /// The name of the operation.
    var name: String

    /// The type parameters of the operation.
    var typeParameters: [DraftTypeParameter] = []

    /// The return type, or `nil` for `void`.
    var returnType: DraftType?

    /// The lower bound of the multiplicity of the result.
    var lowerBound = 0

    /// The upper bound of the multiplicity of the result.
    var upperBound = 1

    /// Whether the values of a many-valued result are ordered.
    var ordered = true

    /// Whether the values of a many-valued result are unique.
    var unique = true

    /// The parameters in source order.
    var parameters: [DraftParameter] = []

    /// The exceptions that the operation declares.
    var exceptions: [DraftType] = []

    /// The annotations of the operation.
    var annotations: [DraftAnnotation] = []

    /// The source location of the operation.
    var location: DraftLocation

    /// Creates an operation without parameters.
    ///
    /// - Parameters:
    ///   - name: The name of the operation.
    ///   - location: The source location of the operation.
    init(name: String, location: DraftLocation = .none) {
        self.name = name
        self.location = location
    }
}

/// A literal of an enumeration as written in a textual notation.
struct DraftLiteral: Sendable, Hashable {
    /// The name of the literal.
    var name: String

    /// The integer value of the literal.
    var value: Int

    /// The literal text, if it differs from the name.
    var literal: String?

    /// The annotations of the literal.
    var annotations: [DraftAnnotation] = []

    /// The source location of the literal.
    var location: DraftLocation

    /// Creates a literal.
    ///
    /// - Parameters:
    ///   - name: The name of the literal.
    ///   - value: The integer value.
    ///   - literal: The literal text, if it differs from the name.
    ///   - location: The source location of the literal.
    init(name: String, value: Int, literal: String? = nil, location: DraftLocation = .none) {
        self.name = name
        self.value = value
        self.literal = literal
        self.location = location
    }
}

/// A classifier (class, data type or enumeration) as written in a textual notation.
struct DraftClassifier: Sendable, Hashable {
    /// The kind of classifier.
    enum Kind: Sendable, Hashable {
        /// A class or interface.
        case `class`

        /// A data type.
        case dataType

        /// An enumeration.
        case enumeration
    }

    /// The kind of classifier.
    var kind: Kind

    /// The name of the classifier.
    var name: String

    /// Whether a class is abstract.
    var isAbstract = false

    /// Whether a class is an interface.
    var isInterface = false

    /// Whether a data type can be serialised.
    var serialisable = true

    /// The instance type name as written, if any.
    var instanceTypeName: String?

    /// The type parameters of the classifier.
    var typeParameters: [DraftTypeParameter] = []

    /// The supertypes of a class.
    var superTypes: [DraftType] = []

    /// The structural features of a class.
    var features: [DraftFeature] = []

    /// The operations of a class.
    var operations: [DraftOperation] = []

    /// The literals of an enumeration.
    var literals: [DraftLiteral] = []

    /// The annotations of the classifier.
    var annotations: [DraftAnnotation] = []

    /// The source location of the classifier.
    var location: DraftLocation

    /// Creates an empty classifier.
    ///
    /// - Parameters:
    ///   - kind: The kind of classifier.
    ///   - name: The name of the classifier.
    ///   - location: The source location of the classifier.
    init(kind: Kind, name: String, location: DraftLocation = .none) {
        self.kind = kind
        self.name = name
        self.location = location
    }
}

/// A package as written in a textual notation.
struct DraftPackage: Sendable, Hashable {
    /// The name of the package.
    var name: String

    /// The fully qualified name of a root package, if it differs from its name.
    ///
    /// Classifiers of the package can be named with this prefix, as in `a.b.c.Class` for a
    /// package `c` declared as `package a.b.c`.
    var qualifiedName: String?

    /// The namespace URI of the package.
    var nsURI: String

    /// The namespace prefix of the package.
    var nsPrefix: String

    /// The annotations of the package.
    var annotations: [DraftAnnotation] = []

    /// The classifiers of the package in source order.
    var classifiers: [DraftClassifier] = []

    /// The subpackages in source order.
    var subpackages: [DraftPackage] = []

    /// The source location of the package.
    var location: DraftLocation

    /// Creates an empty package.
    ///
    /// - Parameters:
    ///   - name: The name of the package.
    ///   - nsURI: The namespace URI.
    ///   - nsPrefix: The namespace prefix.
    ///   - location: The source location of the package.
    init(name: String, nsURI: String = "", nsPrefix: String = "", location: DraftLocation = .none) {
        self.name = name
        self.nsURI = nsURI
        self.nsPrefix = nsPrefix
        self.location = location
    }
}
