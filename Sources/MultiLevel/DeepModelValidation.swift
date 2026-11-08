//
// DeepModelValidation.swift
// MultiLevel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

extension DeepModel {
    /// Checks the structure of the model without evaluating constraints.
    ///
    /// The checks cover the level chain; the uniqueness of names within each level model and
    /// of type-facet names along the chain; potencies and leap potency; the level, potency and
    /// abstractness of ontological types; generalisation; linguistic extensions in strict
    /// models; slots, their mutability, value types and multiplicities; reference targets,
    /// deep references and level crossings under the ``levelCrossing`` policy; edges; and the
    /// potency and language of constraints. Use ``validate(evaluator:)`` to evaluate
    /// constraints as well.
    ///
    /// - Returns: The problems found, in model order.
    public func validateStructure() -> [SourceDiagnostic] {
        var validator = DeepModelValidator(model: self)
        validator.run()
        return validator.diagnostics
    }
}

/// The state of one structural validation.
struct DeepModelValidator {
    /// The model being validated.
    let model: DeepModel
    /// The index of the model.
    let index: DeepIndex
    /// The problems found so far.
    var diagnostics: [SourceDiagnostic] = []

    /// Creates a validator.
    ///
    /// - Parameter model: The model to validate.
    init(model: DeepModel) {
        self.model = model
        self.index = DeepIndex(model)
    }

    /// Records a problem.
    ///
    /// - Parameters:
    ///   - code: The diagnostic code.
    ///   - message: A description of the problem.
    ///   - severity: The severity, defaulting to an error.
    mutating func report(_ code: String, _ message: String, severity: DiagnosticSeverity = .error) {
        diagnostics.append(SourceDiagnostic(severity: severity, code: code, message: message))
    }

    /// The name of a clabject qualified by its level model.
    func qualified(_ id: EUUID) -> String {
        guard let location = index.location[id] else { return id.uuidString }
        let level = model.levels[location.model]
        return "\(level.name).\(level.clabjects[location.position].name)"
    }

    /// Runs every structural check on the model and records the problems found.
    mutating func run() {
        checkChain()
        checkNames()
        for (position, level) in model.levels.enumerated() {
            let number = model.levelNumber(ofModelAt: position)
            for constraint in level.constraints {
                checkConstraint(constraint, holder: level.name, holderPotency: level.potency ?? Potency(number))
            }
            for clabject in level.clabjects {
                check(clabject, at: number, in: level, isTop: position == 0)
            }
        }
    }

    // MARK: - Chain and Names

    /// Checks the top model and that each level model instantiates the one above it with a consistent potency.
    mutating func checkChain() {
        guard let top = model.levels.first else { return }
        if top.typeModel != nil {
            report(MultiLevelDiagnosticCode.levelChain, "the top model '\(top.name)' has a type model")
        }
        if top.potency == nil {
            report(MultiLevelDiagnosticCode.potency, "the top model '\(top.name)' has no potency")
        }
        for position in model.levels.indices.dropFirst() {
            let level = model.levels[position]
            let above = model.levels[position - 1]
            if level.typeModel != above.name {
                report(
                    MultiLevelDiagnosticCode.levelChain,
                    "'\(level.name)' must be an instance of '\(above.name)', the model above it")
            }
            let number = model.levelNumber(ofModelAt: position)
            if let declared = level.potency, declared != Potency(number), top.potency?.isUnbounded == false {
                report(
                    MultiLevelDiagnosticCode.potency,
                    "'\(level.name)' is at level \(number) but declares potency \(declared)")
            }
        }
    }

    /// Checks that clabject names are unique within each level model and that type-facet names are unique along the chain.
    mutating func checkNames() {
        var typeFacets: [String: EUUID] = [:]
        for level in model.levels {
            var seen: Set<String> = []
            for clabject in level.clabjects {
                if !seen.insert(clabject.name).inserted {
                    report(MultiLevelDiagnosticCode.duplicateName, "'\(clabject.name)' is declared twice in '\(level.name)'")
                }
                guard index.potency(of: clabject.id)?.isZero == false else { continue }
                if let other = typeFacets[clabject.name], other != clabject.id {
                    report(
                        MultiLevelDiagnosticCode.duplicateName,
                        "the type facets '\(qualified(other))' and '\(qualified(clabject.id))' share a name; "
                            + "type names must be unique along the instantiation chain")
                } else {
                    typeFacets[clabject.name] = clabject.id
                }
            }
        }
    }

    // MARK: - Clabjects

    /// Checks a clabject: its potency, type, supertypes, features, slots, edge ends and constraints.
    ///
    /// - Parameters:
    ///   - clabject: The clabject to check.
    ///   - level: The level of the clabject.
    ///   - levelModel: The level model that holds the clabject.
    ///   - isTop: Whether the level model is the top of the chain.
    mutating func check(_ clabject: Clabject, at level: Int, in levelModel: LevelModel, isTop: Bool) {
        let name = qualified(clabject.id)
        let potency = index.potency(of: clabject.id) ?? .zero
        checkPotency(potency, of: name, at: level)
        if clabject.isLeap, potency.finiteValue == nil || potency.isZero {
            report(MultiLevelDiagnosticCode.potency, "the leap potency of '\(name)' must be a positive number")
        }
        if let type = clabject.type {
            checkType(type, of: clabject, at: level)
        } else if !isTop, !levelModel.isExtensible {
            report(
                MultiLevelDiagnosticCode.linguisticExtension,
                "'\(name)' has no ontological type, but '\(levelModel.name)' admits no linguistic extensions")
        }
        checkSupertypes(of: clabject, at: level)
        for feature in clabject.features {
            checkFeature(feature, of: clabject, potency: potency, in: levelModel, isTop: isTop)
        }
        checkSlots(of: clabject, at: level, potency: potency)
        if let ends = clabject.ends { checkEnds(ends, of: clabject, at: level) }
        for constraint in clabject.constraints {
            checkConstraint(constraint, holder: name, holderPotency: potency)
        }
    }

    /// Checks that a potency is admissible at a level.
    ///
    /// - Parameters:
    ///   - potency: The potency to check.
    ///   - name: The qualified name of the element, for diagnostics.
    ///   - level: The level of the element.
    mutating func checkPotency(_ potency: Potency, of name: String, at level: Int) {
        if potency.isUnbounded, !model.potencyScheme.permitsUnboundedPotency {
            report(
                MultiLevelDiagnosticCode.potency,
                "'\(name)' has an unbounded potency, which \(model.potencyVariant) potency does not permit")
        }
        if let value = potency.finiteValue, value > level {
            report(MultiLevelDiagnosticCode.potency, "'\(name)' has potency \(value) but is at level \(level)")
        }
    }

    /// Checks the ontological type of a clabject: its level, potency, abstractness and kind.
    ///
    /// - Parameters:
    ///   - type: The identifier of the type.
    ///   - clabject: The clabject that instantiates the type.
    ///   - level: The level of the clabject.
    mutating func checkType(_ type: EUUID, of clabject: Clabject, at level: Int) {
        let name = qualified(clabject.id)
        guard let typeClabject = index.clabject(type), let typeLevel = index.level(of: type) else {
            report(MultiLevelDiagnosticCode.unresolvedName, "the type of '\(name)' does not exist")
            return
        }
        let typeName = qualified(type)
        let offset = index.instantiationOffset(of: type)
        if typeLevel - level != offset {
            report(
                MultiLevelDiagnosticCode.typeLevel,
                "'\(name)' at level \(level) instantiates '\(typeName)' at level \(typeLevel), whose instances reside at level \(typeLevel - offset)"
            )
        }
        let typePotency = index.potency(of: type) ?? .zero
        if model.potencyScheme.instancePotency(ofTypePotency: typePotency, isLeap: typeClabject.isLeap) == nil {
            report(MultiLevelDiagnosticCode.notInstantiable, "'\(name)' instantiates '\(typeName)', whose potency is zero")
        } else if let declared = clabject.potency,
            !model.potencyScheme.admitsInstancePotency(declared, ofTypePotency: typePotency, isLeap: typeClabject.isLeap)
        {
            report(
                MultiLevelDiagnosticCode.potency,
                "'\(name)' declares potency \(declared), which an instance of '\(typeName)' (potency \(typePotency)) cannot have")
        }
        if typeClabject.isAbstract {
            report(MultiLevelDiagnosticCode.notInstantiable, "'\(name)' instantiates the abstract clabject '\(typeName)'")
        }
        if typeClabject.isEdge != clabject.isEdge {
            report(
                MultiLevelDiagnosticCode.edge,
                "'\(name)' and its type '\(typeName)' must both be nodes or both be edges")
        }
    }

    /// Checks that the supertypes of a clabject exist, share its level and potency, and form no cycle.
    ///
    /// - Parameters:
    ///   - clabject: The clabject to check.
    ///   - level: The level of the clabject.
    mutating func checkSupertypes(of clabject: Clabject, at level: Int) {
        let name = qualified(clabject.id)
        for supertype in clabject.supertypes {
            guard index.clabject(supertype) != nil else {
                report(MultiLevelDiagnosticCode.unresolvedName, "a supertype of '\(name)' does not exist")
                continue
            }
            if index.level(of: supertype) != level {
                report(MultiLevelDiagnosticCode.inheritance, "'\(name)' specialises '\(qualified(supertype))' at another level")
            }
            if index.potency(of: supertype) != index.potency(of: clabject.id) {
                report(
                    MultiLevelDiagnosticCode.inheritance,
                    "'\(name)' and its supertype '\(qualified(supertype))' must have the same potency")
            }
            if index.superTypesInclusive(of: supertype).contains(clabject.id) {
                report(MultiLevelDiagnosticCode.inheritance, "the supertypes of '\(name)' form a cycle")
            }
        }
    }

    // MARK: - Features

    /// Checks a feature declaration: its potency, mutability, type, multiplicity and instantiated feature.
    ///
    /// - Parameters:
    ///   - feature: The feature to check.
    ///   - clabject: The clabject that owns the feature.
    ///   - potency: The effective potency of the clabject.
    ///   - levelModel: The level model that holds the clabject.
    ///   - isTop: Whether the level model is the top of the chain.
    mutating func checkFeature(
        _ feature: DeepFeature, of clabject: Clabject, potency: Potency, in levelModel: LevelModel, isTop: Bool
    ) {
        let name = "\(qualified(clabject.id)).\(feature.name)"
        let (durability, mutability) = index.durability(of: feature, ownedBy: clabject.id)
        if feature.mutability != nil, !model.potencyScheme.permitsMutability {
            report(
                MultiLevelDiagnosticCode.potency, "'\(name)' declares a mutability, which \(model.potencyVariant) potency does not permit")
        }
        for value in [durability, mutability].compactMap({ $0 }) where value.isUnbounded {
            if !model.potencyScheme.permitsUnboundedPotency {
                report(
                    MultiLevelDiagnosticCode.potency,
                    "'\(name)' has an unbounded potency, which \(model.potencyVariant) potency does not permit")
            }
        }
        if let value = durability.finiteValue, let limit = potency.finiteValue, value > limit {
            report(MultiLevelDiagnosticCode.potency, "'\(name)' has potency \(value), more than its clabject (\(limit))")
        }
        if feature.ontologicalType == nil, clabject.type != nil, !isTop, !levelModel.isExtensible {
            report(
                MultiLevelDiagnosticCode.linguisticExtension,
                "'\(name)' is a new feature, but '\(levelModel.name)' admits no linguistic extensions")
        }
        if let target = feature.type.target, index.clabject(target) == nil {
            report(MultiLevelDiagnosticCode.unresolvedName, "the target of '\(name)' does not exist")
        }
        if let level = feature.targetLevel, !model.levelNumbers.contains(level) {
            report(MultiLevelDiagnosticCode.levelCrossing, "'\(name)' declares target level \(level), which does not exist")
        }
        if let typeReference = feature.ontologicalType {
            checkInstantiatedFeature(feature, named: name, typeReference: typeReference)
        }
    }

    /// Checks that a feature agrees in kind and type with the feature that it instantiates.
    ///
    /// - Parameters:
    ///   - feature: The instantiating feature.
    ///   - name: The qualified name of the feature, for diagnostics.
    ///   - typeReference: The reference to the instantiated feature.
    mutating func checkInstantiatedFeature(_ feature: DeepFeature, named name: String, typeReference: FeatureReference) {
        guard let typeFeature = index.clabject(typeReference.clabject)?.feature(named: typeReference.name) else {
            report(MultiLevelDiagnosticCode.unresolvedName, "the feature that '\(name)' instantiates does not exist")
            return
        }
        switch (feature.type, typeFeature.type) {
        case (.data(let own), .data(let inherited)):
            if MultiLevelSyntax.dataTypes[own] != MultiLevelSyntax.dataTypes[inherited] {
                report(MultiLevelDiagnosticCode.valueType, "'\(name)' has type \(own) but instantiates a feature of type \(inherited)")
            }
        case (.reference(let own), .reference(let inherited)):
            if !conforms(own, to: inherited) {
                report(
                    MultiLevelDiagnosticCode.referenceTarget,
                    "the target '\(qualified(own))' of '\(name)' is no instance of '\(qualified(inherited))'")
            }
        default:
            report(MultiLevelDiagnosticCode.valueType, "'\(name)' and the feature it instantiates differ in kind")
        }
    }

    /// Whether a clabject is the type, a subtype of it, or a deep instance of it.
    func conforms(_ id: EUUID, to type: EUUID) -> Bool {
        index.superTypesInclusive(of: id).contains(type) || index.deepTypes(of: id).contains(type)
    }

    // MARK: - Slots

    /// Checks the slots of a clabject: visibility, mutability, value types, multiplicities and, at potency zero, required values.
    ///
    /// - Parameters:
    ///   - clabject: The clabject to check.
    ///   - level: The level of the clabject.
    ///   - potency: The effective potency of the clabject.
    mutating func checkSlots(of clabject: Clabject, at level: Int, potency: Potency) {
        let name = qualified(clabject.id)
        let visible = index.visibleFeatures(of: clabject.id)
        for slot in clabject.slots {
            guard let resolved = visible.first(where: { $0.feature.name == slot.feature }) else {
                report(MultiLevelDiagnosticCode.slot, "no feature '\(slot.feature)' is visible at '\(name)'")
                continue
            }
            if !resolved.role.isMutable {
                report(MultiLevelDiagnosticCode.slot, "'\(slot.feature)' cannot be changed at '\(name)'")
            }
            let feature = resolved.feature
            if feature.upperBound >= 0, slot.values.count > feature.upperBound {
                report(
                    MultiLevelDiagnosticCode.multiplicity,
                    "'\(name).\(slot.feature)' holds \(slot.values.count) values, at most \(feature.upperBound) are allowed")
            }
            for value in slot.values { checkValue(value, of: resolved, at: clabject, level: level) }
        }
        guard potency.isZero else { return }
        for resolved in visible where resolved.role.isSlot && resolved.feature.lowerBound > 0 && !resolved.feature.isDerived {
            let count = index.values(of: resolved.feature.name, at: clabject.id)?.count ?? 0
            if count < resolved.feature.lowerBound {
                report(
                    MultiLevelDiagnosticCode.multiplicity,
                    "'\(name).\(resolved.feature.name)' holds \(count) values, at least \(resolved.feature.lowerBound) are required")
            }
        }
    }

    /// Checks that a slot value fits the type of its feature.
    ///
    /// - Parameters:
    ///   - value: The value to check.
    ///   - resolved: The feature that the slot fills.
    ///   - clabject: The clabject that holds the slot.
    ///   - level: The level of the clabject.
    mutating func checkValue(_ value: DeepValue, of resolved: ResolvedFeature, at clabject: Clabject, level: Int) {
        let name = "\(qualified(clabject.id)).\(resolved.feature.name)"
        switch resolved.feature.type {
        case .data(let dataType):
            if !Self.value(value, fits: dataType) {
                report(MultiLevelDiagnosticCode.valueType, "a value of '\(name)' does not fit its type \(dataType)")
            }
        case .reference(let target):
            guard let object = value.object, index.clabject(object) != nil else {
                report(MultiLevelDiagnosticCode.valueType, "a value of '\(name)' is not a clabject")
                return
            }
            checkTarget(object, of: resolved.feature, target: target, named: name, sourceLevel: level)
        }
    }

    /// Checks that a reference value is an instance of its target and respects the target potency and the level-crossing policy.
    ///
    /// - Parameters:
    ///   - object: The identifier of the referenced clabject.
    ///   - feature: The reference feature.
    ///   - target: The identifier of the declared target.
    ///   - name: The qualified name of the feature, for diagnostics.
    ///   - sourceLevel: The level of the clabject that holds the value.
    mutating func checkTarget(_ object: EUUID, of feature: DeepFeature, target: EUUID, named name: String, sourceLevel: Int) {
        let objectName = qualified(object)
        if !conforms(object, to: target) {
            report(
                MultiLevelDiagnosticCode.referenceTarget,
                "'\(objectName)' in '\(name)' is no instance of '\(qualified(target))'")
        }
        if let required = feature.targetPotency {
            if index.potency(of: object) != required {
                report(
                    MultiLevelDiagnosticCode.referenceTarget,
                    "'\(objectName)' in the deep reference '\(name)' must have potency \(required)")
            }
            return
        }
        guard model.levelCrossing != .nonStrict, let objectLevel = index.level(of: object) else { return }
        let expected = feature.targetLevel ?? sourceLevel
        if objectLevel != expected {
            let reason = feature.targetLevel == nil
                ? "may refer only to level \(sourceLevel), as it declares no other target level"
                : "is declared to refer to level \(expected)"
            report(
                MultiLevelDiagnosticCode.levelCrossing,
                "'\(name)' refers to '\(objectName)' at level \(objectLevel), but it \(reason)")
        }
    }

    /// Whether a value fits a data type of the notation.
    static func value(_ value: DeepValue, fits dataType: String) -> Bool {
        switch (MultiLevelSyntax.dataTypes[dataType], value) {
        case (nil, _): return value.object == nil
        case ("EInt", .integer), ("ELong", .integer): return true
        case ("EDouble", .real), ("EDouble", .integer), ("EFloat", .real), ("EFloat", .integer): return true
        case ("EBoolean", .boolean): return true
        case ("EString", .string), ("EDate", .string): return true
        default: return false
        }
    }

    // MARK: - Edges

    /// Checks that the ends of an edge exist, respect the level-crossing policy and instantiate the ends of the edge's type.
    ///
    /// - Parameters:
    ///   - ends: The ends of the edge.
    ///   - clabject: The edge.
    ///   - level: The level of the edge.
    mutating func checkEnds(_ ends: EdgeEnds, of clabject: Clabject, at level: Int) {
        let name = qualified(clabject.id)
        for end in [ends.source, ends.target] {
            guard index.clabject(end.clabject) != nil else {
                report(MultiLevelDiagnosticCode.edge, "an end of '\(name)' does not exist")
                continue
            }
            if let feature = end.feature, index.visibleFeatures(of: end.clabject).first(where: { $0.feature.name == feature }) == nil {
                report(MultiLevelDiagnosticCode.edge, "'\(qualified(end.clabject))' of edge '\(name)' has no feature '\(feature)'")
            }
            if model.levelCrossing != .nonStrict, index.level(of: end.clabject) != level {
                report(MultiLevelDiagnosticCode.levelCrossing, "an end of edge '\(name)' is at another level")
            }
        }
        guard let type = clabject.type, let typeEnds = index.clabject(type)?.ends else { return }
        if !conforms(ends.source.clabject, to: typeEnds.source.clabject)
            || !conforms(ends.target.clabject, to: typeEnds.target.clabject)
        {
            report(MultiLevelDiagnosticCode.edge, "the ends of '\(name)' do not instantiate the ends of '\(qualified(type))'")
        }
    }

    // MARK: - Constraints

    /// Checks that a constraint's potency does not exceed that of its holder and that it is written in a supported language.
    ///
    /// - Parameters:
    ///   - constraint: The constraint to check.
    ///   - holder: The qualified name of the holder, for diagnostics.
    ///   - holderPotency: The effective potency of the holder.
    mutating func checkConstraint(_ constraint: DeepConstraint, holder: String, holderPotency: Potency) {
        if let potency = constraint.potency, potency > holderPotency {
            report(
                MultiLevelDiagnosticCode.potency,
                "constraint '\(constraint.name)' of '\(holder)' has potency \(potency), more than its holder (\(holderPotency))")
        }
        if constraint.language != MultiLevelSyntax.constraintLanguage {
            report(
                MultiLevelDiagnosticCode.constraintLanguage,
                "constraint '\(constraint.name)' of '\(holder)' is written in \(constraint.language); only AQL is supported")
        } else if let marker = MultiLevelSyntax.eolOnlyMarkers.first(where: { constraint.body.contains($0) }) {
            report(
                MultiLevelDiagnosticCode.constraintLanguage,
                "constraint '\(constraint.name)' of '\(holder)' uses '\(marker.trimmingCharacters(in: .whitespaces))', which is EOL")
        }
    }
}
