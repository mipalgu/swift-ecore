//
// MultiLevelSyntax.swift
// MultiLevel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore

/// The vocabulary of multi-level models: keywords, punctuation, names and identifiers.
///
/// Every word and symbol with a meaning in the MetaDepth text notation, in the bundled
/// linguistic metamodel, in the views and in the diagnostics is defined here once, so that the
/// reader, the writer, the encoders and the views agree.
public enum MultiLevelSyntax {
    // MARK: - Format

    /// The identifier of the MetaDepth text format in a ``ECore/ModelFormatRegistry``.
    public static let formatIdentifier = ModelFormat.metadepth.rawValue

    /// The prose name of the MetaDepth text format.
    public static let formatName = "MetaDepth"

    /// The conventional file extension of MetaDepth documents, without the leading dot.
    public static let fileExtension = ModelFormat.metadepth.fileExtension

    // MARK: - Keywords

    /// The keyword that introduces a top-level model.
    public static let modelKeyword = "Model"

    /// The keyword, and linguistic type, of a node clabject.
    public static let nodeKeyword = "Node"

    /// The keyword, and linguistic type, of an edge clabject.
    public static let edgeKeyword = "Edge"

    /// The modifier of an abstract clabject.
    public static let abstractKeyword = "abstract"

    /// The modifier of a model that admits linguistic extensions.
    public static let extensibleKeyword = "ext"

    /// The modifier of a model that rejects linguistic extensions.
    public static let strictKeyword = "strict"

    /// The keyword with which a model imports another model.
    public static let importsKeyword = "imports"

    /// The literal `true`.
    public static let trueLiteral = "true"

    /// The literal `false`.
    public static let falseLiteral = "false"

    // MARK: - Punctuation

    /// The marker that precedes a potency.
    public static let potencyMarker: Character = "@"

    /// The text of an unbounded potency.
    public static let unboundedPotency = "*"

    /// The separator between the durability and the mutability of a feature.
    public static let mutabilitySeparator: Character = "/"

    /// The marker of a derived feature, which precedes its name.
    public static let derivedMarker: Character = "/"

    /// The delimiter that surrounds a constraint or derivation expression.
    public static let expressionDelimiter: Character = "$"

    /// The marker of an embedded-language block, as in `# EOL`.
    public static let embeddedBlockMarker: Character = "#"

    /// The separator of a range of multiplicity, as in `[0..1]`.
    public static let rangeSeparator = ".."

    /// The separator of the two ends of an edge and of a qualified end, as in `Task.perfBy`.
    public static let memberSeparator: Character = "."

    // MARK: - Feature Modifiers

    /// The modifier of an ordered multi-valued feature.
    public static let orderedModifier = "ordered"

    /// The modifier of a feature whose values are unique.
    public static let uniqueModifier = "unique"

    /// The modifier of a containment reference.
    public static let containmentModifier = "containment"

    /// The modifier that declares a level-crossing reference, as in `{level=1}`.
    public static let levelModifier = "level"

    /// The separator between a modifier and its value.
    public static let modifierValueSeparator: Character = "="

    // MARK: - Data Types

    /// The data type names of the notation, with the Ecore data types they denote.
    public static let dataTypes: [String: String] = [
        "int": "EInt", "Integer": "EInt",
        "long": "ELong",
        "double": "EDouble", "Real": "EDouble",
        "float": "EFloat",
        "boolean": "EBoolean", "Boolean": "EBoolean",
        "String": "EString", "string": "EString",
        "Date": "EDate",
    ]

    // MARK: - Potency Variants

    /// The model modifier that selects Melanee-style potency (durability and mutability).
    public static let melaneeKeyword = "melanee"

    /// The model modifier that selects MetaDepth potency (the default).
    public static let metaDepthKeyword = "metadepth"

    // MARK: - Constraints

    /// The language of constraint bodies.
    public static let constraintLanguage = "aql"

    /// The embedded languages of MetaDepth that are recognised but not supported.
    public static let unsupportedLanguages: Set<String> = ["EOL", "ETL", "EGL", "EVL"]

    /// The tokens that occur in EOL bodies but never in AQL.
    public static let eolOnlyMarkers: [String] = [":=", "var ", ".println(", ".isDefined()", "new "]

    // MARK: - Names

    /// The prefix of generated names of anonymous clabjects.
    public static let anonymousPrefix = "MD_"

    // MARK: - Linguistic Metamodel

    /// The name of the bundled linguistic metamodel.
    public static let linguisticPackageName = "multilevel"

    /// The namespace URI of the bundled linguistic metamodel.
    public static let linguisticNamespaceURI = "urn:swift-ecore:multilevel:1.0"

    /// The namespace prefix of the bundled linguistic metamodel.
    public static let linguisticNamespacePrefix = "ml"

    /// The scheme prefix of the namespace URIs of views.
    public static let viewNamespacePrefix = "urn:swift-ecore:multilevel:view:"

    /// The suffix of the namespace URI of a deep level view.
    public static let deepViewSuffix = "deep"

    /// The suffix of the namespace URI of a level-pair view.
    public static let pairViewSuffix = "pair"

    /// The source of the annotations that record levels and potencies in exported Ecore.
    public static let annotationSource = "urn:swift-ecore:multilevel"

    /// The annotation detail key of a level.
    public static let levelKey = "level"

    /// The annotation detail key of a potency or durability.
    public static let potencyKey = "potency"

    /// The annotation detail key of a mutability.
    public static let mutabilityKey = "mutability"

    /// The annotation detail key of a leap potency.
    public static let leapKey = "leap"

    /// The annotation detail key of the clabject that a class facet stands for.
    public static let clabjectKey = "clabject"

    /// The annotation detail key that marks a derived type-level slot.
    public static let typeLevelSlotKey = "typeLevelSlot"

    /// The names of the end references of an edge class in a view.
    public static let edgeSourceName = "source"

    /// The name of the target end reference of an edge class in a view.
    public static let edgeTargetName = "target"
}

/// The names of the classes of the bundled linguistic metamodel.
public enum LinguisticClass: String, CaseIterable, Sendable {
    /// A deep model: the chain of level models.
    case deepModel = "DeepModel"

    /// A model at one level.
    case levelModel = "LevelModel"

    /// A clabject.
    case clabject = "Clabject"

    /// An end of an edge clabject.
    case edgeEnd = "EdgeEnd"

    /// A feature of a clabject.
    case feature = "Feature"

    /// A slot of a clabject.
    case slot = "Slot"

    /// A value of a slot or a default.
    case value = "Value"

    /// A constraint.
    case constraint = "Constraint"
}

/// The names of the features of the bundled linguistic metamodel.
public enum LinguisticFeature: String, CaseIterable, Sendable {
    /// The name of a named element.
    case name

    /// The stable identifier of a clabject.
    case identifier

    /// The potency variant of a deep model.
    case potencyVariant

    /// The level-crossing policy of a deep model.
    case levelCrossing

    /// The level models of a deep model.
    case levels

    /// The potency of a model, clabject, feature or constraint.
    case potency

    /// The mutability of a feature.
    case mutability

    /// The name of the ontological type model of a level model.
    case typeModel

    /// Whether a level model admits linguistic extensions.
    case extensible

    /// The clabjects of a level model.
    case clabjects

    /// The constraints of a level model or clabject.
    case constraints

    /// The linguistic kind of a clabject: `Node` or `Edge`.
    case kind

    /// Whether a clabject is abstract.
    case isAbstract

    /// Whether a clabject has leap potency.
    case leap

    /// The ontological type of a clabject or feature.
    case type

    /// The supertypes of a clabject.
    case supertypes

    /// The features of a clabject.
    case features

    /// The slots of a clabject.
    case slots

    /// The source end of an edge.
    case source

    /// The target end of an edge.
    case target

    /// The clabject of an edge end.
    case clabject

    /// The reference feature of an edge end.
    case feature

    /// The data type of an attribute.
    case dataType

    /// The target clabject of a reference.
    case targetClabject

    /// The potency of the targets of a deep reference.
    case targetPotency

    /// The declared target level of a level-crossing reference.
    case targetLevel

    /// The lower bound of a feature.
    case lowerBound

    /// The upper bound of a feature.
    case upperBound

    /// Whether a reference is a containment.
    case containment

    /// Whether a feature is ordered.
    case ordered

    /// Whether the values of a feature are unique.
    case unique

    /// Whether a feature is derived.
    case derived

    /// The derivation expression of a derived feature.
    case derivation

    /// The default values of a feature.
    case defaults

    /// The values of a slot.
    case values

    /// The kind of a value.
    case valueKind

    /// The literal of a value.
    case literal

    /// The clabject that a reference value denotes.
    case object

    /// The body of a constraint.
    case body

    /// The language of a constraint body.
    case language
}
