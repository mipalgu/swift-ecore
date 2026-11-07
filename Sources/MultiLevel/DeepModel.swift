//
// DeepModel.swift
// MultiLevel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import OrderedCollections

/// A multi-level model: a chain of level models, from the top level down.
///
/// Each level model is an ontological instance of the one above it. Clabjects are typed by
/// clabjects one level up (or, with leap potency, further up), and features take effect at
/// the levels that their potency determines (see ``PotencyScheme``). The model is a value;
/// queries compute deep typing, visible features and slot values on demand.
///
/// ```swift
/// let parsed = MetaDepthReader.parse(text)
/// let model = try #require(parsed.model)
/// let book = try #require(model.clabject(named: "Book"))
/// model.deepTypes(of: book.id).map(\.name)  // ["Book", "ProductType"]
/// ```
public struct DeepModel: Sendable {
    /// The level models, from the top level down.
    public var levels: [LevelModel]

    /// The potency scheme that governs instantiation and features.
    public var potencyScheme: any PotencyScheme

    /// Which references may cross levels.
    public var levelCrossing: LevelCrossingPolicy

    /// Creates a deep model.
    ///
    /// - Parameters:
    ///   - levels: The level models, from the top level down (default none).
    ///   - potencyScheme: The potency scheme (default MetaDepth).
    ///   - levelCrossing: The level-crossing policy (default strict).
    public init(
        levels: [LevelModel] = [], potencyScheme: any PotencyScheme = MetaDepthPotencyScheme(),
        levelCrossing: LevelCrossingPolicy = .strict
    ) {
        self.levels = levels
        self.potencyScheme = potencyScheme
        self.levelCrossing = levelCrossing
    }

    /// The name of the top level model, or an empty string for an empty model.
    public var name: String { levels.first?.name ?? "" }

    /// The potency variant of the scheme.
    public var potencyVariant: PotencyVariant { potencyScheme.variant }

    // MARK: - Levels

    /// The level number of the level model at a position in ``levels``.
    ///
    /// The level of the top model is its potency; each model below is one level lower. If
    /// the top potency is unbounded or missing, the bottom model is at level zero.
    ///
    /// - Parameter index: The position of the level model.
    /// - Returns: The level number.
    public func levelNumber(ofModelAt index: Int) -> Int {
        if let top = levels.first?.potency?.finiteValue { return top - index }
        return levels.count - 1 - index
    }

    /// The level numbers of all level models, from the top down.
    public var levelNumbers: [Int] { levels.indices.map(levelNumber(ofModelAt:)) }

    /// The level model at a level number.
    ///
    /// - Parameter level: The level number.
    /// - Returns: The level model, or `nil` if no model is at that level.
    public func levelModel(atLevel level: Int) -> LevelModel? {
        levels.indices.first { levelNumber(ofModelAt: $0) == level }.map { levels[$0] }
    }

    /// The level of a clabject.
    ///
    /// - Parameter id: The identifier of the clabject.
    /// - Returns: The level number, or `nil` if the model has no such clabject.
    public func level(of id: EUUID) -> Int? {
        index.location[id].map { levelNumber(ofModelAt: $0.model) }
    }

    // MARK: - Clabjects

    /// The clabject with an identifier.
    ///
    /// - Parameter id: The identifier.
    /// - Returns: The clabject, or `nil`.
    public func clabject(_ id: EUUID) -> Clabject? {
        index.clabject(id)
    }

    /// The first clabject with a name, searching from the top level down.
    ///
    /// - Parameters:
    ///   - name: The name.
    ///   - level: The level to search, or `nil` to search every level.
    /// - Returns: The clabject, or `nil`.
    public func clabject(named name: String, atLevel level: Int? = nil) -> Clabject? {
        for (position, model) in levels.enumerated() where level == nil || levelNumber(ofModelAt: position) == level {
            if let found = model.clabject(named: name) { return found }
        }
        return nil
    }

    /// Every clabject, from the top level down, in declaration order.
    public var allClabjects: [Clabject] { levels.flatMap(\.clabjects) }

    /// Replaces a clabject, keeping its position.
    ///
    /// - Parameter clabject: The new version of the clabject.
    /// - Returns: `true` if a clabject with its identifier was replaced.
    @discardableResult
    public mutating func update(_ clabject: Clabject) -> Bool {
        guard let location = index.location[clabject.id] else { return false }
        levels[location.model].clabjects[location.position] = clabject
        return true
    }

    // MARK: - Potency

    /// The effective potency of a clabject.
    ///
    /// An explicit potency is taken as declared. Otherwise an instance receives the potency
    /// that the scheme derives from its type, and a linguistic extension the potency of its
    /// level model.
    ///
    /// - Parameter id: The identifier of the clabject.
    /// - Returns: The potency, or `nil` if the model has no such clabject.
    public func potency(of id: EUUID) -> Potency? {
        index.potency(of: id)
    }

    /// The level offset of instantiating a clabject: its potency for a leap, otherwise one.
    ///
    /// - Parameter id: The identifier of the type.
    /// - Returns: The number of levels between the type and its instances.
    public func instantiationOffset(of id: EUUID) -> Int {
        index.instantiationOffset(of: id)
    }

    // MARK: - Typing

    /// The clabject and its direct and indirect supertypes, in breadth-first order.
    ///
    /// - Parameter id: The identifier of the clabject.
    /// - Returns: The clabjects, starting with the clabject itself.
    public func superTypesInclusive(of id: EUUID) -> [Clabject] {
        index.superTypesInclusive(of: id).compactMap(index.clabject)
    }

    /// The ontological types above a clabject: its type, the type of its type, and so on.
    ///
    /// - Parameter id: The identifier of the clabject.
    /// - Returns: The chain of types, nearest first.
    public func ontologicalTypeChain(of id: EUUID) -> [Clabject] {
        index.typeChain(of: id).compactMap(index.clabject)
    }

    /// The deep types of a clabject.
    ///
    /// With *S* the supertypes of its type, including the type, the deep types are *S* and
    /// the deep types of every member of *S*.
    ///
    /// - Parameter id: The identifier of the clabject.
    /// - Returns: The deep types, nearest first, without repetitions.
    public func deepTypes(of id: EUUID) -> [Clabject] {
        index.deepTypes(of: id).compactMap(index.clabject)
    }

    /// Whether a clabject is a direct or indirect (deep) instance of a type.
    ///
    /// - Parameters:
    ///   - id: The identifier of the clabject.
    ///   - type: The identifier of the type.
    /// - Returns: `true` if the type is among the deep types of the clabject.
    public func isDeepInstance(_ id: EUUID, of type: EUUID) -> Bool {
        index.deepTypes(of: id).contains(type)
    }

    /// The direct and indirect instances of a type, optionally at one level.
    ///
    /// - Parameters:
    ///   - type: The identifier of the type.
    ///   - level: The level to restrict to, or `nil` for every level.
    /// - Returns: The deep instances, from the top level down, in declaration order.
    public func instances(of type: EUUID, atLevel level: Int? = nil) -> [Clabject] {
        levels.indices.flatMap { position -> [Clabject] in
            guard level == nil || levelNumber(ofModelAt: position) == level else { return [] }
            return levels[position].clabjects.filter { index.deepTypes(of: $0.id).contains(type) }
        }
    }

    // MARK: - Features

    /// The features visible at a clabject, with their roles there.
    ///
    /// The clabject sees the features that it and its supertypes declare, and the features of
    /// its type chain that still exist at its level and that no clabject in between has
    /// instantiated.
    ///
    /// - Parameter id: The identifier of the clabject.
    /// - Returns: The features, by name, nearest declaration first.
    public func features(of id: EUUID) -> [ResolvedFeature] {
        index.visibleFeatures(of: id)
    }

    /// The feature visible at a clabject with a name.
    ///
    /// - Parameters:
    ///   - name: The name of the feature.
    ///   - id: The identifier of the clabject.
    /// - Returns: The feature, or `nil` if none with that name is visible.
    public func feature(named name: String, at id: EUUID) -> ResolvedFeature? {
        index.visibleFeatures(of: id).first { $0.feature.name == name }
    }

    /// The values of a feature at a clabject, including defaults and type-level slots.
    ///
    /// The values are those of the clabject's own slot, else those of a supertype's slot, else
    /// the nearest along the ontological type chain: a slot of a type or of a supertype of a
    /// type, or the default of a declaration.
    ///
    /// - Parameters:
    ///   - name: The name of the feature.
    ///   - id: The identifier of the clabject.
    /// - Returns: The values, or `nil` if neither the clabject nor its types give any.
    public func values(of name: String, at id: EUUID) -> [DeepValue]? {
        index.values(of: name, at: id)
    }

    /// The index of the model, computed afresh.
    var index: DeepIndex { DeepIndex(self) }
}

extension DeepModel: Hashable {
    /// Compares the levels, the potency variant and the level-crossing policy.
    ///
    /// - Parameters:
    ///   - lhs: The first model.
    ///   - rhs: The second model.
    /// - Returns: `true` if the models are equal.
    public static func == (lhs: DeepModel, rhs: DeepModel) -> Bool {
        lhs.levels == rhs.levels && lhs.potencyVariant == rhs.potencyVariant && lhs.levelCrossing == rhs.levelCrossing
    }

    /// Hashes the levels, the potency variant and the level-crossing policy.
    ///
    /// - Parameter hasher: The hasher.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(levels)
        hasher.combine(potencyVariant)
        hasher.combine(levelCrossing)
    }
}

/// A feature as it is visible at a clabject.
public struct ResolvedFeature: Hashable, Sendable {
    /// The declaration of the feature.
    public var feature: DeepFeature

    /// The clabject that declares the feature.
    public var owner: EUUID

    /// The number of levels between the declaration and the clabject.
    public var levelsBelow: Int

    /// The effective potency (durability) of the feature.
    public var durability: Potency

    /// The effective mutability, or `nil` if the scheme has none.
    public var mutability: Potency?

    /// The role of the feature at the clabject.
    public var role: FeatureRole

    /// A reference to the declaration.
    public var reference: FeatureReference { FeatureReference(clabject: owner, name: feature.name) }
}

/// Where a clabject is in a deep model.
struct ClabjectLocation: Hashable, Sendable {
    /// The position of its level model.
    let model: Int

    /// Its position within the level model.
    let position: Int
}

/// The precomputed lookups of a deep model.
struct DeepIndex: Sendable {
    /// The model.
    let model: DeepModel

    /// The location of each clabject.
    let location: [EUUID: ClabjectLocation]

    /// Builds the index of a model.
    ///
    /// - Parameter model: The model.
    init(_ model: DeepModel) {
        self.model = model
        var location: [EUUID: ClabjectLocation] = [:]
        for (modelPosition, level) in model.levels.enumerated() {
            for (position, clabject) in level.clabjects.enumerated() where location[clabject.id] == nil {
                location[clabject.id] = ClabjectLocation(model: modelPosition, position: position)
            }
        }
        self.location = location
    }

    /// The clabject with an identifier.
    func clabject(_ id: EUUID) -> Clabject? {
        location[id].map { model.levels[$0.model].clabjects[$0.position] }
    }

    /// The level number of a clabject.
    func level(of id: EUUID) -> Int? {
        location[id].map { model.levelNumber(ofModelAt: $0.model) }
    }

    /// The potency of the level model of a clabject.
    func modelPotency(of id: EUUID) -> Potency? {
        guard let location = location[id] else { return nil }
        return model.levels[location.model].potency ?? Potency(model.levelNumber(ofModelAt: location.model))
    }

    /// The effective potency of a clabject (see ``DeepModel/potency(of:)``).
    func potency(of id: EUUID, visited: Set<EUUID> = []) -> Potency? {
        guard let clabject = clabject(id) else { return nil }
        if let explicit = clabject.potency { return explicit }
        if let type = clabject.type, !visited.contains(type), let typePotency = potency(of: type, visited: visited.union([id])),
            let derived = model.potencyScheme.instancePotency(
                ofTypePotency: typePotency, isLeap: self.clabject(type)?.isLeap ?? false)
        {
            return derived
        }
        return modelPotency(of: id)
    }

    /// The level offset of instantiating a clabject.
    func instantiationOffset(of id: EUUID) -> Int {
        guard let clabject = clabject(id), clabject.isLeap, let leap = potency(of: id)?.finiteValue else { return 1 }
        return max(1, leap)
    }

    /// The clabject and its supertypes, breadth first, without repetitions.
    func superTypesInclusive(of id: EUUID) -> [EUUID] {
        var result = OrderedSet<EUUID>([id])
        var position = 0
        while position < result.count {
            for supertype in clabject(result[position])?.supertypes ?? [] { result.append(supertype) }
            position += 1
        }
        return result.elements
    }

    /// The ontological type chain of a clabject, nearest first, stopping at a cycle.
    func typeChain(of id: EUUID) -> [EUUID] {
        var chain = OrderedSet<EUUID>()
        var current = clabject(id)?.type
        while let type = current, !chain.contains(type), type != id {
            chain.append(type)
            current = clabject(type)?.type
        }
        return chain.elements
    }

    /// The deep types of a clabject (see ``DeepModel/deepTypes(of:)``).
    func deepTypes(of id: EUUID) -> [EUUID] {
        var result = OrderedSet<EUUID>()
        var pending: [EUUID] = [id]
        var expanded: Set<EUUID> = []
        while !pending.isEmpty {
            let current = pending.removeFirst()
            guard expanded.insert(current).inserted, let type = clabject(current)?.type else { continue }
            for member in superTypesInclusive(of: type) where !result.contains(member) {
                result.append(member)
                pending.append(member)
            }
        }
        return result.elements
    }

    /// The effective durability and mutability of a declared feature.
    func durability(of feature: DeepFeature, ownedBy owner: EUUID, visited: Set<FeatureReference> = [])
        -> (durability: Potency, mutability: Potency?)
    {
        let mutability = model.potencyScheme.permitsMutability ? feature.mutability : nil
        if let explicit = feature.potency { return (explicit, mutability) }
        if let typeReference = feature.ontologicalType, !visited.contains(typeReference),
            let typeOwner = clabject(typeReference.clabject),
            let typeFeature = typeOwner.feature(named: typeReference.name)
        {
            let inherited = durability(
                of: typeFeature, ownedBy: typeOwner.id,
                visited: visited.union([FeatureReference(clabject: owner, name: feature.name)]))
            let steps = (level(of: typeOwner.id) ?? 0) - (level(of: owner) ?? 0)
            return (inherited.durability.decremented(by: max(steps, 0)) ?? .zero, mutability)
        }
        return (potency(of: owner) ?? .zero, mutability)
    }

    /// The features visible at a clabject (see ``DeepModel/features(of:)``).
    func visibleFeatures(of id: EUUID, visited: Set<EUUID> = []) -> [ResolvedFeature] {
        guard let level = level(of: id), !visited.contains(id) else { return [] }
        var result = OrderedDictionary<String, ResolvedFeature>()
        var instantiated: Set<FeatureReference> = []
        for member in superTypesInclusive(of: id) {
            guard let owner = clabject(member), self.level(of: member) == level else { continue }
            for feature in owner.features where result[feature.name] == nil {
                let (durability, mutability) = durability(of: feature, ownedBy: member)
                let role = model.potencyScheme.role(durability: durability, mutability: mutability, levelsBelow: 0)
                result[feature.name] = ResolvedFeature(
                    feature: feature, owner: member, levelsBelow: 0, durability: durability, mutability: mutability,
                    role: role)
                if let typeReference = feature.ontologicalType { instantiated.insert(typeReference) }
            }
        }
        for member in superTypesInclusive(of: id) {
            guard let type = clabject(member)?.type, let typeLevel = self.level(of: type) else { continue }
            let offset = typeLevel - level
            for inherited in visibleFeatures(of: type, visited: visited.union([id])) {
                guard result[inherited.feature.name] == nil, !instantiated.contains(inherited.reference) else { continue }
                let levelsBelow = inherited.levelsBelow + offset
                let role = model.potencyScheme.role(
                    durability: inherited.durability, mutability: inherited.mutability, levelsBelow: levelsBelow)
                guard role.exists else { continue }
                var resolved = inherited
                resolved.levelsBelow = levelsBelow
                resolved.role = role
                result[inherited.feature.name] = resolved
            }
        }
        return Array(result.values)
    }

    /// The values of a feature at a clabject (see ``DeepModel/values(of:at:)``).
    func values(of name: String, at id: EUUID) -> [DeepValue]? {
        for member in superTypesInclusive(of: id) {
            if let slot = clabject(member)?.slot(named: name) { return slot.values }
        }
        for type in typeChain(of: id) {
            for member in superTypesInclusive(of: type) {
                guard let clabject = clabject(member) else { continue }
                if let slot = clabject.slot(named: name) { return slot.values }
                if let feature = clabject.feature(named: name), !feature.defaultValues.isEmpty {
                    return feature.defaultValues
                }
            }
        }
        for member in superTypesInclusive(of: id) {
            if let feature = clabject(member)?.feature(named: name), !feature.defaultValues.isEmpty {
                return feature.defaultValues
            }
        }
        return nil
    }

    /// The values of the slots of a clabject whose features instantiate a feature, directly
    /// or through intermediate instantiations.
    func values(instantiating reference: FeatureReference, at id: EUUID) -> [DeepValue] {
        var collected: [DeepValue] = []
        for resolved in visibleFeatures(of: id) where resolved.role.isSlot && instantiates(resolved.reference, reference) {
            collected.append(contentsOf: values(of: resolved.feature.name, at: id) ?? [])
        }
        return collected
    }

    /// Whether one feature instantiates another, directly or transitively.
    func instantiates(_ feature: FeatureReference, _ type: FeatureReference) -> Bool {
        var visited: Set<FeatureReference> = []
        var current: FeatureReference? = feature
        while let reference = current, visited.insert(reference).inserted {
            if reference == type { return true }
            current = clabject(reference.clabject)?.feature(named: reference.name)?.ontologicalType
        }
        return false
    }
}
