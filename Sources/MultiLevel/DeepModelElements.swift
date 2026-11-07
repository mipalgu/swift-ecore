//
// DeepModelElements.swift
// MultiLevel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// A value held by a slot or given as the default of a feature.
public enum DeepValue: Hashable, Sendable {
    /// A string.
    case string(String)

    /// An integer.
    case integer(Int)

    /// A real number.
    case real(Double)

    /// A Boolean.
    case boolean(Bool)

    /// An enumeration literal or another name that does not denote a clabject.
    case literal(String)

    /// A clabject, by identifier.
    case object(EUUID)

    /// The clabject that the value denotes, if it is a reference.
    public var object: EUUID? {
        if case .object(let id) = self { return id }
        return nil
    }
}

/// The values that a clabject holds for one feature.
public struct DeepSlot: Hashable, Sendable {
    /// The name of the feature, which must be visible at the clabject.
    public var feature: String

    /// The values, in order; a single-valued feature holds at most one.
    public var values: [DeepValue]

    /// Creates a slot.
    ///
    /// - Parameters:
    ///   - feature: The name of the feature.
    ///   - values: The values.
    public init(feature: String, values: [DeepValue]) {
        self.feature = feature
        self.values = values
    }
}

/// A feature named by the clabject that declares it.
public struct FeatureReference: Hashable, Sendable, CustomStringConvertible {
    /// The clabject that declares the feature.
    public var clabject: EUUID

    /// The name of the feature.
    public var name: String

    /// Creates a feature reference.
    ///
    /// - Parameters:
    ///   - clabject: The declaring clabject.
    ///   - name: The name of the feature.
    public init(clabject: EUUID, name: String) {
        self.clabject = clabject
        self.name = name
    }

    /// The identifier of the clabject and the name of the feature.
    public var description: String { "\(clabject).\(name)" }
}

/// The type of a deep feature: a data type or a target clabject.
public enum DeepFeatureType: Hashable, Sendable {
    /// An attribute of a data type of the notation, such as `int` or `String`.
    case data(String)

    /// A reference to (deep) instances of a clabject.
    case reference(EUUID)

    /// The target clabject, if the feature is a reference.
    public var target: EUUID? {
        if case .reference(let id) = self { return id }
        return nil
    }
}

/// A feature of a clabject, with its potency, multiplicity and default.
///
/// A feature without an explicit potency takes the potency of the feature it instantiates
/// minus one, or else the potency of its clabject. A feature that instantiates another one
/// (its ``ontologicalType``) replaces that feature below the instantiating clabject; one
/// without an ontological type at a level below the top is a linguistic extension.
public struct DeepFeature: Hashable, Sendable {
    /// The name of the feature.
    public var name: String

    /// The potency (in the Melanee variant, the durability), or `nil` for the default.
    public var potency: Potency?

    /// The mutability in the Melanee variant, or `nil` for the durability.
    public var mutability: Potency?

    /// The data type or target clabject.
    public var type: DeepFeatureType

    /// The minimum number of values.
    public var lowerBound: Int

    /// The maximum number of values, or `-1` for unbounded.
    public var upperBound: Int

    /// Whether the feature is a containment reference.
    public var isContainment: Bool

    /// Whether the values are ordered.
    public var isOrdered: Bool

    /// Whether the values are unique.
    public var isUnique: Bool

    /// Whether the feature is derived.
    public var isDerived: Bool

    /// The derivation expression of a derived feature, without delimiters.
    public var derivation: String?

    /// The default values, given at the declaration.
    public var defaultValues: [DeepValue]

    /// The feature that this feature instantiates, or `nil` for a new feature.
    public var ontologicalType: FeatureReference?

    /// The potency that the targets of a deep reference must have (written `T@0`).
    public var targetPotency: Potency?

    /// The level at which the targets of a declared level-crossing reference reside.
    public var targetLevel: Int?

    /// Creates a feature.
    ///
    /// - Parameters:
    ///   - name: The name of the feature.
    ///   - type: The data type or target clabject.
    ///   - potency: The potency or durability, or `nil` for the default.
    ///   - mutability: The Melanee mutability, or `nil`.
    ///   - lowerBound: The minimum number of values (default 0).
    ///   - upperBound: The maximum number of values, `-1` for unbounded (default 1).
    ///   - isContainment: Whether the feature is a containment reference (default `false`).
    ///   - isOrdered: Whether the values are ordered (default `true`).
    ///   - isUnique: Whether the values are unique (default `true`).
    ///   - isDerived: Whether the feature is derived (default `false`).
    ///   - derivation: The derivation expression (default `nil`).
    ///   - defaultValues: The default values (default none).
    ///   - ontologicalType: The feature this one instantiates (default `nil`).
    ///   - targetPotency: The potency of the targets of a deep reference (default `nil`).
    ///   - targetLevel: The level of the targets of a declared level-crossing reference
    ///     (default `nil`).
    public init(
        name: String, type: DeepFeatureType, potency: Potency? = nil, mutability: Potency? = nil,
        lowerBound: Int = 0, upperBound: Int = 1, isContainment: Bool = false, isOrdered: Bool = true,
        isUnique: Bool = true, isDerived: Bool = false, derivation: String? = nil,
        defaultValues: [DeepValue] = [], ontologicalType: FeatureReference? = nil,
        targetPotency: Potency? = nil, targetLevel: Int? = nil
    ) {
        self.name = name
        self.type = type
        self.potency = potency
        self.mutability = mutability
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.isContainment = isContainment
        self.isOrdered = isOrdered
        self.isUnique = isUnique
        self.isDerived = isDerived
        self.derivation = derivation
        self.defaultValues = defaultValues
        self.ontologicalType = ontologicalType
        self.targetPotency = targetPotency
        self.targetLevel = targetLevel
    }

    /// Whether the feature may hold more than one value.
    public var isMany: Bool { upperBound < 0 || upperBound > 1 }
}

/// A constraint with a potency, written in AQL.
///
/// A constraint of potency *p* attached at level *L* is evaluated on the (deep) instances at
/// level *L* − *p* of the clabject that holds it, or once at that level if a model holds it.
/// Without an explicit potency it takes the potency of its holder.
public struct DeepConstraint: Hashable, Sendable {
    /// The name of the constraint.
    public var name: String

    /// The potency, or `nil` for the potency of the holder.
    public var potency: Potency?

    /// The body of the constraint, without delimiters.
    public var body: String

    /// The language of the body (``MultiLevelSyntax/constraintLanguage``).
    public var language: String

    /// Creates a constraint.
    ///
    /// - Parameters:
    ///   - name: The name of the constraint.
    ///   - potency: The potency, or `nil` for the potency of the holder.
    ///   - body: The body, without delimiters.
    ///   - language: The language of the body (default AQL).
    public init(
        name: String, potency: Potency? = nil, body: String, language: String = MultiLevelSyntax.constraintLanguage
    ) {
        self.name = name
        self.potency = potency
        self.body = body
        self.language = language
    }
}

/// One end of an edge clabject: a clabject and, for an edge type, the reference that the edge
/// reifies.
public struct EdgeEnd: Hashable, Sendable {
    /// The clabject at the end.
    public var clabject: EUUID

    /// The reference feature of the end clabject that the edge reifies, if any.
    public var feature: String?

    /// Creates an end.
    ///
    /// - Parameters:
    ///   - clabject: The clabject at the end.
    ///   - feature: The reference feature, or `nil`.
    public init(clabject: EUUID, feature: String? = nil) {
        self.clabject = clabject
        self.feature = feature
    }
}

/// The two ends of an edge clabject.
public struct EdgeEnds: Hashable, Sendable {
    /// The source end.
    public var source: EdgeEnd

    /// The target end.
    public var target: EdgeEnd

    /// Creates the ends of an edge.
    ///
    /// - Parameters:
    ///   - source: The source end.
    ///   - target: The target end.
    public init(source: EdgeEnd, target: EdgeEnd) {
        self.source = source
        self.target = target
    }
}

/// An element that is at once a class and an object.
///
/// A clabject has an *instance facet* (its ontological type and its slots) and a *type facet*
/// (its features, which its instances receive). A clabject without an ontological type is a
/// linguistic extension. An edge clabject (``ends`` is set) reifies an association.
public struct Clabject: Identifiable, Hashable, Sendable {
    /// The stable identifier of the clabject.
    public let id: EUUID

    /// The name, unique within its level model.
    public var name: String

    /// The ends, if the clabject is an edge.
    public var ends: EdgeEnds?

    /// The potency, or `nil` for the default.
    ///
    /// The default is the potency of the type minus one for an instance, and the potency of
    /// the level model for a linguistic extension.
    public var potency: Potency?

    /// Whether the potency is a leap potency, written `@(n)`: instances reside *n* levels
    /// below without identity instances in between.
    public var isLeap: Bool

    /// Whether the clabject is abstract and cannot be instantiated directly.
    public var isAbstract: Bool

    /// The ontological type, or `nil` for a linguistic extension.
    public var type: EUUID?

    /// The direct supertypes, at the same level.
    public var supertypes: [EUUID]

    /// The features declared by the clabject.
    public var features: [DeepFeature]

    /// The slots, in declaration order.
    public var slots: [DeepSlot]

    /// The constraints declared by the clabject.
    public var constraints: [DeepConstraint]

    /// Creates a clabject.
    ///
    /// - Parameters:
    ///   - id: The stable identifier.
    ///   - name: The name.
    ///   - type: The ontological type (default none).
    ///   - potency: The potency (default `nil` for the default).
    ///   - isLeap: Whether the potency is a leap potency (default `false`).
    ///   - isAbstract: Whether the clabject is abstract (default `false`).
    ///   - supertypes: The direct supertypes (default none).
    ///   - ends: The ends, for an edge (default `nil`).
    ///   - features: The features (default none).
    ///   - slots: The slots (default none).
    ///   - constraints: The constraints (default none).
    public init(
        id: EUUID, name: String, type: EUUID? = nil, potency: Potency? = nil, isLeap: Bool = false,
        isAbstract: Bool = false, supertypes: [EUUID] = [], ends: EdgeEnds? = nil, features: [DeepFeature] = [],
        slots: [DeepSlot] = [], constraints: [DeepConstraint] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.potency = potency
        self.isLeap = isLeap
        self.isAbstract = isAbstract
        self.supertypes = supertypes
        self.ends = ends
        self.features = features
        self.slots = slots
        self.constraints = constraints
    }

    /// Whether the clabject is an edge.
    public var isEdge: Bool { ends != nil }

    /// The slot for a feature, if the clabject holds one.
    ///
    /// - Parameter feature: The name of the feature.
    /// - Returns: The slot, or `nil`.
    public func slot(named feature: String) -> DeepSlot? {
        slots.first { $0.feature == feature }
    }

    /// The feature declared by the clabject with a name.
    ///
    /// - Parameter name: The name of the feature.
    /// - Returns: The feature, or `nil`.
    public func feature(named name: String) -> DeepFeature? {
        features.first { $0.name == name }
    }
}

/// The model at one level of a deep model.
public struct LevelModel: Hashable, Sendable {
    /// The name of the model.
    public var name: String

    /// The declared potency of the model, or `nil` to derive it from the type model.
    ///
    /// The potency of a model equals its level.
    public var potency: Potency?

    /// The name of the ontological type model, or `nil` for the top model.
    public var typeModel: String?

    /// Whether the model admits linguistic extensions (MetaDepth `ext`, the default) or
    /// rejects them (MetaDepth `strict`).
    public var isExtensible: Bool

    /// The clabjects, in declaration order.
    public var clabjects: [Clabject]

    /// The constraints declared by the model itself.
    public var constraints: [DeepConstraint]

    /// Creates a level model.
    ///
    /// - Parameters:
    ///   - name: The name.
    ///   - potency: The declared potency (default `nil`).
    ///   - typeModel: The name of the type model (default `nil` for the top model).
    ///   - isExtensible: Whether linguistic extensions are admitted (default `true`).
    ///   - clabjects: The clabjects (default none).
    ///   - constraints: The model constraints (default none).
    public init(
        name: String, potency: Potency? = nil, typeModel: String? = nil, isExtensible: Bool = true,
        clabjects: [Clabject] = [], constraints: [DeepConstraint] = []
    ) {
        self.name = name
        self.potency = potency
        self.typeModel = typeModel
        self.isExtensible = isExtensible
        self.clabjects = clabjects
        self.constraints = constraints
    }

    /// The clabject with a name.
    ///
    /// - Parameter name: The name.
    /// - Returns: The clabject, or `nil`.
    public func clabject(named name: String) -> Clabject? {
        clabjects.first { $0.name == name }
    }
}

/// Which references may connect clabjects at different levels.
public struct LevelCrossingPolicy: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    /// The identifier of the policy.
    public let rawValue: String

    /// Creates a policy identifier.
    ///
    /// - Parameter rawValue: The identifier.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Strict metamodelling: a reference connects clabjects of one level, unless it is a
    /// deep reference or a declared level-crossing reference. Other crossings are errors.
    public static let strict = LevelCrossingPolicy(rawValue: "strict")

    /// Non-strict metamodelling: any reference may cross levels.
    public static let nonStrict = LevelCrossingPolicy(rawValue: "nonStrict")

    /// The identifier of the policy.
    public var description: String { rawValue }
}
