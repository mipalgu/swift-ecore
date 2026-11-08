//
// Potency.swift
// MultiLevel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The number of levels over which a model element can still be instantiated or endure.
///
/// A potency is a natural number or, in schemes that permit it, unbounded (written `*`).
/// Each instantiation step decreases a finite potency by one; a potency of zero denotes a
/// pure object, which cannot be instantiated further. An unbounded potency stays unbounded.
///
/// ```swift
/// let potency = Potency(2)
/// potency.decremented()   // Potency(1)
/// Potency.unbounded.decremented()  // Potency.unbounded
/// ```
public struct Potency: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// The finite value of the potency, or `nil` if it is unbounded.
    public let finiteValue: Int?

    /// Creates a finite potency.
    ///
    /// - Parameter value: The number of levels; a negative number is taken as zero.
    public init(_ value: Int) {
        finiteValue = max(0, value)
    }

    /// Creates a potency from an optional finite value.
    ///
    /// - Parameter finiteValue: The value, or `nil` for an unbounded potency.
    private init(finiteValue: Int?) {
        self.finiteValue = finiteValue.map { max(0, $0) }
    }

    /// Creates a potency from its textual form.
    ///
    /// - Parameter text: A natural number, or `*` for an unbounded potency.
    /// - Returns: The potency, or `nil` if the text is neither.
    public init?(text: String) {
        if text == MultiLevelSyntax.unboundedPotency {
            self = .unbounded
        } else if let value = Int(text), value >= 0 {
            self.init(value)
        } else {
            return nil
        }
    }

    /// The potency of a pure object.
    public static let zero = Potency(0)

    /// The unbounded potency `*`, which permits any number of instantiation steps.
    public static let unbounded = Potency(finiteValue: nil)

    /// Whether the potency is unbounded.
    public var isUnbounded: Bool { finiteValue == nil }

    /// Whether the potency is zero, so that the element cannot be instantiated.
    public var isZero: Bool { finiteValue == 0 }

    /// Whether at least a given number of instantiation steps remain.
    ///
    /// - Parameter steps: The number of steps.
    /// - Returns: `true` if the potency is unbounded or at least `steps`.
    public func admits(_ steps: Int) -> Bool {
        guard let finiteValue else { return true }
        return steps <= finiteValue
    }

    /// The potency after a number of instantiation steps.
    ///
    /// - Parameter steps: The number of steps (default one).
    /// - Returns: The decreased potency, the unbounded potency if this one is unbounded, or
    ///   `nil` if fewer than `steps` steps remain.
    public func decremented(by steps: Int = 1) -> Potency? {
        guard let finiteValue else { return self }
        guard steps <= finiteValue else { return nil }
        return Potency(finiteValue - steps)
    }

    /// Orders potencies by their value, with the unbounded potency above every finite one.
    ///
    /// - Parameters:
    ///   - lhs: The first potency.
    ///   - rhs: The second potency.
    /// - Returns: `true` if `lhs` is below `rhs`.
    public static func < (lhs: Potency, rhs: Potency) -> Bool {
        switch (lhs.finiteValue, rhs.finiteValue) {
        case let (left?, right?): return left < right
        case (.some, nil): return true
        default: return false
        }
    }

    /// The textual form: the number, or `*` for an unbounded potency.
    public var description: String {
        finiteValue.map(String.init) ?? MultiLevelSyntax.unboundedPotency
    }
}

/// The identifier of a potency variant, such as MetaDepth or Melanee potency.
///
/// A variant names a ``PotencyScheme``. New variants are added by defining a new value and a
/// scheme for it; existing switches over variants are not affected, as the type is a struct.
public struct PotencyVariant: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    /// The identifier of the variant, as written in text and in the linguistic encoding.
    public let rawValue: String

    /// Creates a variant identifier.
    ///
    /// - Parameter rawValue: The identifier of the variant.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// MetaDepth potency: one potency per model, clabject, feature and constraint, with leap
    /// potency on clabjects.
    public static let metaDepth = PotencyVariant(rawValue: MultiLevelSyntax.metaDepthKeyword)

    /// Melanee potency: clabject potency, feature durability and mutability, and unbounded
    /// potency `*`.
    public static let melanee = PotencyVariant(rawValue: MultiLevelSyntax.melaneeKeyword)

    /// The identifier of the variant.
    public var description: String { rawValue }
}

/// What a feature is at a level below the clabject that declares it.
///
/// A feature declared at level *L* may be a *definition* at levels from which it is still
/// instantiated, a *slot* at levels whose clabjects hold values for it, and *mutable* where a
/// value may be given. Values given where the feature is still a definition act as defaults
/// for deeper levels.
public struct FeatureRole: Hashable, Sendable {
    /// Whether the feature exists at the level at all.
    public var exists: Bool

    /// Whether the feature is part of the type facet, so that instances below receive it.
    public var isDefinition: Bool

    /// Whether clabjects at the level hold a value for the feature as part of their
    /// instance facet.
    public var isSlot: Bool

    /// Whether a value may be given at the level.
    public var isMutable: Bool

    /// Creates a role.
    ///
    /// - Parameters:
    ///   - exists: Whether the feature exists at the level.
    ///   - isDefinition: Whether the feature is part of the type facet.
    ///   - isSlot: Whether clabjects hold a value for the feature.
    ///   - isMutable: Whether a value may be given.
    public init(exists: Bool, isDefinition: Bool, isSlot: Bool, isMutable: Bool) {
        self.exists = exists
        self.isDefinition = isDefinition
        self.isSlot = isSlot
        self.isMutable = isMutable
    }

    /// The role of a feature at a level where it does not exist.
    public static let absent = FeatureRole(exists: false, isDefinition: false, isSlot: false, isMutable: false)
}

/// The rules by which potency governs instantiation and features.
///
/// A scheme decides how clabject potency decreases with instantiation and what a feature is
/// at each level below its declaration. ``MetaDepthPotencyScheme`` and
/// ``MelaneePotencyScheme`` are built in; further schemes can be supplied to a ``DeepModel``.
public protocol PotencyScheme: Sendable {
    /// The variant that the scheme implements.
    var variant: PotencyVariant { get }

    /// Whether unbounded potency (`*`) may be used.
    var permitsUnboundedPotency: Bool { get }

    /// Whether features may have a mutability separate from their durability.
    var permitsMutability: Bool { get }

    /// The role of a feature at a number of levels below its declaration.
    ///
    /// - Parameters:
    ///   - durability: The potency (durability) of the feature.
    ///   - mutability: The mutability of the feature, or `nil` if none is declared.
    ///   - levelsBelow: The number of levels between the declaration and the level asked
    ///     about; zero for the declaring level.
    /// - Returns: The role of the feature at that level.
    func role(durability: Potency, mutability: Potency?, levelsBelow: Int) -> FeatureRole

    /// The potency that instances of a clabject receive.
    ///
    /// - Parameters:
    ///   - typePotency: The potency of the type.
    ///   - isLeap: Whether the type has leap potency.
    /// - Returns: The potency of its instances, or `nil` if the type cannot be instantiated.
    func instancePotency(ofTypePotency typePotency: Potency, isLeap: Bool) -> Potency?

    /// Whether an explicitly declared potency of an instance is admissible.
    ///
    /// - Parameters:
    ///   - potency: The declared potency of the instance.
    ///   - typePotency: The potency of its type.
    ///   - isLeap: Whether the type has leap potency.
    /// - Returns: `true` if the instance may declare the potency.
    func admitsInstancePotency(_ potency: Potency, ofTypePotency typePotency: Potency, isLeap: Bool) -> Bool
}

extension PotencyScheme {
    /// The potency that instances receive: one less than the type, zero after a leap, and
    /// unbounded for an unbounded type.
    ///
    /// - Parameters:
    ///   - typePotency: The potency of the type.
    ///   - isLeap: Whether the type has leap potency.
    /// - Returns: The potency of its instances, or `nil` if the type has potency zero.
    public func instancePotency(ofTypePotency typePotency: Potency, isLeap: Bool) -> Potency? {
        guard !typePotency.isZero else { return nil }
        return isLeap ? .zero : typePotency.decremented()
    }

    /// Admits exactly the potency that ``instancePotency(ofTypePotency:isLeap:)`` gives.
    ///
    /// - Parameters:
    ///   - potency: The declared potency of the instance.
    ///   - typePotency: The potency of its type.
    ///   - isLeap: Whether the type has leap potency.
    /// - Returns: `true` if the declared potency is the derived one.
    public func admitsInstancePotency(_ potency: Potency, ofTypePotency typePotency: Potency, isLeap: Bool) -> Bool {
        instancePotency(ofTypePotency: typePotency, isLeap: isLeap) == potency
    }
}

/// MetaDepth potency ([de Lara and Guerra](https://doi.org/10.1007/978-3-642-13953-6_1)).
///
/// A feature of potency *p* is a definition for *p* levels and becomes a slot exactly *p*
/// levels below its declaration; values given above that level are defaults. Unbounded
/// potency and separate mutability are not part of the scheme.
public struct MetaDepthPotencyScheme: PotencyScheme {
    /// Creates the scheme.
    public init() {}

    /// ``PotencyVariant/metaDepth``.
    public var variant: PotencyVariant { .metaDepth }

    /// `false`: MetaDepth potencies are natural numbers.
    public var permitsUnboundedPotency: Bool { false }

    /// `false`: MetaDepth has a single potency per feature.
    public var permitsMutability: Bool { false }

    /// The role of a feature of potency *p* at *k* levels below its declaration.
    ///
    /// The feature exists for `k <= p`, is a definition for `k < p`, a slot for `k == p`, and
    /// accepts a value (a default above its slot level) wherever it exists.
    ///
    /// - Parameters:
    ///   - durability: The potency of the feature.
    ///   - mutability: Ignored.
    ///   - levelsBelow: The number of levels below the declaration.
    /// - Returns: The role of the feature.
    public func role(durability: Potency, mutability: Potency?, levelsBelow: Int) -> FeatureRole {
        guard levelsBelow >= 0, durability.admits(levelsBelow) else { return .absent }
        let isSlot = durability.finiteValue == levelsBelow
        return FeatureRole(exists: true, isDefinition: !isSlot, isSlot: isSlot, isMutable: true)
    }
}

/// Melanee potency ([Atkinson and Gerbig](https://madoc.bib.uni-mannheim.de/40981)): durability
/// and mutability.
///
/// A feature of durability *d* endures *d* levels below its declaration and holds a value at
/// every level where it exists; its value may be changed at the declaring level and at the
/// *m* levels below it, where *m* is its mutability (by default its durability). Clabjects and
/// features may have unbounded potency `*`. Instances of an unbounded clabject may declare
/// any potency.
public struct MelaneePotencyScheme: PotencyScheme {
    /// Creates the scheme.
    public init() {}

    /// ``PotencyVariant/melanee``.
    public var variant: PotencyVariant { .melanee }

    /// `true`: Melanee permits `*`.
    public var permitsUnboundedPotency: Bool { true }

    /// `true`: features have a mutability.
    public var permitsMutability: Bool { true }

    /// The role of a feature of durability *d* and mutability *m* at *k* levels below its
    /// declaration.
    ///
    /// The feature exists and is a slot for `k <= d`, is a definition for `k < d`, and is
    /// mutable for `k == 0` and for `k <= m`.
    ///
    /// - Parameters:
    ///   - durability: The durability of the feature.
    ///   - mutability: The mutability of the feature, or `nil` for its durability.
    ///   - levelsBelow: The number of levels below the declaration.
    /// - Returns: The role of the feature.
    public func role(durability: Potency, mutability: Potency?, levelsBelow: Int) -> FeatureRole {
        guard levelsBelow >= 0, durability.admits(levelsBelow) else { return .absent }
        let isMutable = levelsBelow == 0 || (mutability ?? durability).admits(levelsBelow)
        return FeatureRole(
            exists: true, isDefinition: durability.admits(levelsBelow + 1), isSlot: true, isMutable: isMutable)
    }

    /// Admits any potency below an unbounded type, and otherwise the derived potency.
    ///
    /// - Parameters:
    ///   - potency: The declared potency of the instance.
    ///   - typePotency: The potency of its type.
    ///   - isLeap: Whether the type has leap potency.
    /// - Returns: `true` if the declared potency is admissible.
    public func admitsInstancePotency(_ potency: Potency, ofTypePotency typePotency: Potency, isLeap: Bool) -> Bool {
        if typePotency.isUnbounded && !isLeap { return true }
        return instancePotency(ofTypePotency: typePotency, isLeap: isLeap) == potency
    }
}

/// The potency schemes that are built in.
public enum PotencySchemes {
    /// The built-in schemes: MetaDepth and Melanee.
    public static let builtIn: [any PotencyScheme] = [MetaDepthPotencyScheme(), MelaneePotencyScheme()]

    /// The built-in scheme of a variant.
    ///
    /// - Parameters:
    ///   - variant: The variant.
    ///   - schemes: The schemes to choose from (default ``builtIn``).
    /// - Returns: The scheme, or `nil` if none implements the variant.
    public static func scheme(for variant: PotencyVariant, among schemes: [any PotencyScheme] = builtIn)
        -> (any PotencyScheme)?
    {
        schemes.first { $0.variant == variant }
    }
}
