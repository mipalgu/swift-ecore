//
// RuleInferenceTypes.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// What a type reference of a grammar denotes, as decided by the notation.
enum TypeResolution: Sendable, Hashable {
    /// A classifier of a generated package, which is created if it does not exist.
    case generated(package: String, name: String)
    /// A built-in data type of Ecore.
    case ecore(EcoreDataType)
    /// The root class `EObject` of Ecore.
    case eObject
    /// A classifier of a package that is referred to but not generated, such as an imported one.
    case external(name: String, origin: String)
    /// A reference that cannot be resolved, with an explanation.
    case unresolved(String)
}

/// The position in which a type reference is resolved.
enum TypeRole: Sendable, Hashable {
    /// The return type of a parser rule, infix rule or parser fragment.
    case parserRule
    /// The return type of a terminal or datatype rule.
    case dataRule
    /// The return type of an enum rule.
    case enumRule
    /// The type of an action.
    case action
    /// The target type of a cross-reference.
    case crossReference
    /// The type of a declared property.
    case property
}

/// What a rule that the grammar does not define stands for, as decided by the notation.
enum ExternalRule: Sendable, Hashable {
    /// A terminal or datatype rule with the given value type.
    case dataType(TypeResolution)
    /// A parser rule with the given return type.
    case parserRule(TypeResolution)
}

/// The settings that adapt the Xtext inference to a notation.
struct RuleInferenceConfiguration: Sendable, Hashable {
    /// Whether features common to all direct subtypes are moved to their supertype, as Xtext does.
    var liftsCommonFeatures: Bool

    /// Whether inferred classes that no rule instantiates are abstract, as Langium union types are.
    var marksUnionTypesAbstract: Bool

    /// Whether every parser fragment is inlined into its callers instead of becoming a supertype.
    var inlinesFragments: Bool

    /// Whether types may be inferred; when not, only declared types are used.
    var allowsInferredTypes: Bool

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - liftsCommonFeatures: Whether common features move to supertypes.
    ///   - marksUnionTypesAbstract: Whether never-instantiated inferred classes are abstract.
    ///   - inlinesFragments: Whether parser fragments are inlined.
    ///   - allowsInferredTypes: Whether types may be inferred.
    init(
        liftsCommonFeatures: Bool = true, marksUnionTypesAbstract: Bool = false, inlinesFragments: Bool = false,
        allowsInferredTypes: Bool = true
    ) {
        self.liftsCommonFeatures = liftsCommonFeatures
        self.marksUnionTypesAbstract = marksUnionTypesAbstract
        self.inlinesFragments = inlinesFragments
        self.allowsInferredTypes = allowsInferredTypes
    }

    /// The configuration that follows Xtext.
    static let xtext = RuleInferenceConfiguration()

    /// The configuration that follows Langium.
    static let langium = RuleInferenceConfiguration(
        liftsCommonFeatures: false, marksUnionTypesAbstract: true, inlinesFragments: true)
}

/// The identity of a type during inference.
enum TypeKey: Sendable, Hashable {
    /// A classifier of a generated package.
    case generated(package: String, name: String)
    /// A built-in data type of Ecore.
    case ecore(EcoreDataType)
    /// The root class `EObject`.
    case eObject
    /// A class of a package that is not generated.
    case externalClass(name: String, origin: String)
    /// A data type of a package that is not generated.
    case externalData(name: String, origin: String)
    /// A type that could not be made, standing in silently for a class.
    case excluded(String)

    /// The name of the type, for messages.
    var displayName: String {
        switch self {
        case .generated(_, let name), .externalClass(let name, _), .externalData(let name, _), .excluded(let name):
            name
        case .ecore(let type): type.rawValue
        case .eObject: EcoreClassifier.eObject.rawValue
        }
    }
}

/// The kind of a generated classifier.
enum InferredClassifierKind: Sendable, Hashable {
    /// A class.
    case eClass
    /// An enumeration.
    case eEnum
    /// A data type.
    case dataType
}

/// A feature of a declared type, as written in a Langium interface.
struct DeclaredFeature: Sendable, Hashable {
    /// The name of the feature.
    var name: String

    /// The alternatives of the feature's type; more than one for a union.
    var types: [TypeKey]

    /// Whether the feature holds a list.
    var isMany: Bool

    /// Whether the feature must be set.
    var isRequired: Bool

    /// Whether a reference contains its targets.
    var isContainment: Bool

    /// The default value as text, if any.
    var defaultValueLiteral: String?

    /// The text of the declaration.
    var range: SourceRange?

    /// Creates a declared feature.
    ///
    /// - Parameters:
    ///   - name: The name of the feature.
    ///   - types: The alternatives of the feature's type.
    ///   - isMany: Whether the feature holds a list.
    ///   - isRequired: Whether the feature must be set.
    ///   - isContainment: Whether a reference contains its targets.
    ///   - defaultValueLiteral: The default value as text.
    ///   - range: The text of the declaration.
    init(
        name: String, types: [TypeKey], isMany: Bool, isRequired: Bool, isContainment: Bool,
        defaultValueLiteral: String? = nil, range: SourceRange? = nil
    ) {
        self.name = name
        self.types = types
        self.isMany = isMany
        self.isRequired = isRequired
        self.isContainment = isContainment
        self.defaultValueLiteral = defaultValueLiteral
        self.range = range
    }
}

/// A feature of a generated class during inference.
struct InferredFeature: Sendable, Hashable {
    /// The name of the feature.
    var name: String
    /// The type of the feature.
    var type: TypeKey
    /// The alternatives of a declared union type, resolved when the metamodel is emitted.
    var unionTypes: [TypeKey] = []
    /// Whether the feature holds a list.
    var isMany: Bool
    /// Whether a reference contains its targets.
    var isContainment: Bool
    /// Whether the feature must be set.
    var isRequired = false
    /// The default value as text.
    var defaultValueLiteral: String?
    /// The text that gave rise to the feature.
    var range: SourceRange?
}

/// A generated classifier during inference.
struct InferredClassifier: Sendable, Hashable {
    /// The identity of the classifier.
    var key: TypeKey
    /// The package that holds the classifier.
    var package: String
    /// The name of the classifier.
    var name: String
    /// What kind of classifier it is.
    var kind: InferredClassifierKind
    /// Whether the classifier was declared rather than inferred; declared classifiers get no inferred features.
    var isDeclared: Bool
    /// Whether a declared class is abstract.
    var isAbstract = false
    /// The direct supertypes of a class, in order.
    var superTypes: [TypeKey] = []
    /// The features of a class, in order.
    var features: [InferredFeature] = []
    /// The literals of an enumeration.
    var literals: [GrammarDraftLiteral] = []
    /// The instance class name of a data type.
    var instanceClassName: String?
    /// The text that gave rise to the classifier.
    var range: SourceRange?
}
