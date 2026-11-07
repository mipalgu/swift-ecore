//
// RuleInference.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Infers Ecore classifiers from the rules of an Xtext or Langium grammar.
///
/// The inference follows Xtext's documented metamodel inference and its
/// implementation (`Xtext2EcoreTransformer`, `Xtext2EcoreInterpretationContext`
/// and `TypeHierarchyHelper`) in five passes:
///
/// 1. Classification: parser rules without assignments and actions that call
///    only terminal and datatype rules are datatype rules.
/// 2. Types: every rule return type becomes a classifier; parser rules give
///    classes, enum rules enumerations, terminal and datatype rules data types
///    (or built-in Ecore data types). Action and cross-reference types are
///    created when first named.
/// 3. Hierarchy: in a parser rule, every action and every unassigned call of a
///    parser rule (outside assignments) makes that type a subtype of the rule's
///    type; calling a (non-inlined) parser fragment makes the rule's type a
///    subtype of the fragment's type.
/// 4. Features: each rule body is interpreted with a set of current types.
///    Assignments add features to every current type; a mandatory unassigned
///    parser-rule call or an action replaces the set; optional elements merge
///    with the set before them; repeated groups are interpreted twice.
/// 5. Normalisation: features that all direct subtypes share move to their
///    supertype, features that repeat inherited ones are removed, and features
///    that repeat a uniquely inherited one widen its type instead.
///
/// The configuration adapts the passes to Langium, which inlines fragments,
/// keeps features where they are assigned and treats types that no rule
/// instantiates as unions (abstract classes).
struct RuleInference {
    /// The notation-specific settings.
    let configuration: RuleInferenceConfiguration

    /// The notation, for diagnostic codes.
    let dialect: RuleGrammarDialect

    /// The packages to fill, without classifiers.
    let packages: [GrammarDraftPackage]

    /// Resolves a written type reference.
    private let resolver: @Sendable (RuleTypeReference, TypeRole) -> TypeResolution

    /// Describes a rule that the grammar does not define, or `nil` if it is unknown.
    private let externalRule: @Sendable (String) -> ExternalRule?

    /// The problems found.
    private(set) var collector: DiagnosticCollector

    /// The generated classifiers in creation order.
    private var classifiers: [InferredClassifier] = []

    /// The positions of the generated classifiers, by key.
    private var positions: [TypeKey: Int] = [:]

    /// The rules by name; grammar rules replace predefined ones.
    private var rules: [String: GrammarRule] = [:]

    /// The names of the parser rules that are datatype rules.
    private var datatypeRules: Set<String> = []

    /// The types of the rules, once computed.
    private var ruleTypes: [String: TypeKey] = [:]

    /// The types of which some rule or action creates instances.
    private var instantiated: Set<TypeKey> = []

    /// Messages already reported, to report each external type or unknown rule once.
    private var reported: Set<String> = []

    /// Union memberships declared before the member types exist, as member and union.
    private var pendingMemberships: [(member: TypeKey, union: TypeKey, range: SourceRange?)] = []

    /// Creates an inference.
    ///
    /// - Parameters:
    ///   - configuration: The notation-specific settings.
    ///   - dialect: The notation, for diagnostic codes.
    ///   - packages: The packages to fill, without classifiers.
    ///   - collector: The collector that receives problems.
    ///   - resolver: Resolves a written type reference in a role.
    ///   - externalRule: Describes a rule the grammar does not define, or answers `nil`.
    init(
        configuration: RuleInferenceConfiguration, dialect: RuleGrammarDialect, packages: [GrammarDraftPackage],
        collector: DiagnosticCollector,
        resolver: @escaping @Sendable (RuleTypeReference, TypeRole) -> TypeResolution,
        externalRule: @escaping @Sendable (String) -> ExternalRule?
    ) {
        self.configuration = configuration
        self.dialect = dialect
        self.packages = packages
        self.collector = collector
        self.resolver = resolver
        self.externalRule = externalRule
    }

    /// Reports a problem found by a notation outside the inference.
    ///
    /// - Parameters:
    ///   - severity: How serious the problem is.
    ///   - problem: The kind of problem.
    ///   - message: A human-readable description.
    ///   - range: The affected text.
    mutating func report(
        _ severity: DiagnosticSeverity, _ problem: RuleGrammarProblem, _ message: String, at range: SourceRange?
    ) {
        collector.report(severity, dialect.code(problem), message, at: range)
    }

    // MARK: Declared types

    /// Declares a class, as a Langium interface or union type does.
    ///
    /// - Parameters:
    ///   - package: The package that holds the class.
    ///   - name: The name of the class.
    ///   - isAbstract: Whether the class is abstract.
    ///   - range: The text of the declaration.
    mutating func declareClass(package: String, name: String, isAbstract: Bool, range: SourceRange?) {
        let key = TypeKey.generated(package: package, name: name)
        guard positions[key] == nil else { return }
        add(InferredClassifier(
            key: key, package: package, name: name, kind: .eClass, isDeclared: true, isAbstract: isAbstract,
            range: range))
    }

    /// Adds a supertype to a declared class.
    ///
    /// - Parameters:
    ///   - superType: The supertype.
    ///   - subType: The class that inherits.
    mutating func declareSuperType(_ superType: TypeKey, of subType: TypeKey) {
        guard let index = positions[subType], superType != subType,
            !classifiers[index].superTypes.contains(superType)
        else { return }
        classifiers[index].superTypes.append(superType)
    }

    /// Makes a type a member of a declared union, once both exist.
    ///
    /// The member may be a declared type or a type that the rules infer; the
    /// membership is applied after the rule types have been created, and is
    /// reported if the member never comes to exist.
    ///
    /// - Parameters:
    ///   - member: The member type.
    ///   - union: The declared union class.
    ///   - range: The text that names the member.
    mutating func declareUnionMember(_ member: TypeKey, of union: TypeKey, range: SourceRange?) {
        pendingMemberships.append((member, union, range))
    }

    /// Applies the union memberships declared so far.
    private mutating func applyMemberships() {
        for (member, union, range) in pendingMemberships {
            guard let memberIndex = index(member) else {
                if reported.insert("missing\u{0}\(member.displayName)").inserted {
                    collector.warning(
                        dialect.code(.externalType),
                        "The type '\(member.displayName)' of the union '\(union.displayName)' is not defined here",
                        at: range)
                }
                continue
            }
            guard classifiers[memberIndex].kind == .eClass else { continue }
            if !classifiers[memberIndex].superTypes.contains(union) && member != union {
                classifiers[memberIndex].superTypes.append(union)
            }
        }
        pendingMemberships = []
    }

    /// Adds features to a declared class.
    ///
    /// - Parameters:
    ///   - features: The features as declared.
    ///   - owner: The class.
    mutating func declareFeatures(_ features: [DeclaredFeature], of owner: TypeKey) {
        guard let index = positions[owner] else { return }
        for feature in features {
            classifiers[index].features.append(InferredFeature(
                name: feature.name, type: feature.types.first ?? .eObject,
                unionTypes: feature.types.count > 1 ? feature.types : [], isMany: feature.isMany,
                isContainment: feature.isContainment, isRequired: feature.isRequired,
                defaultValueLiteral: feature.defaultValueLiteral, range: feature.range))
        }
    }

    /// Declares an enumeration.
    ///
    /// - Parameters:
    ///   - package: The package that holds the enumeration.
    ///   - name: The name of the enumeration.
    ///   - literals: The literals.
    ///   - range: The text of the declaration.
    mutating func declareEnum(package: String, name: String, literals: [GrammarDraftLiteral], range: SourceRange?) {
        let key = TypeKey.generated(package: package, name: name)
        guard positions[key] == nil else { return }
        add(InferredClassifier(
            key: key, package: package, name: name, kind: .eEnum, isDeclared: true, literals: literals, range: range))
    }

    /// Declares a data type.
    ///
    /// - Parameters:
    ///   - package: The package that holds the data type.
    ///   - name: The name of the data type.
    ///   - instanceClassName: The class that implements its values.
    ///   - range: The text of the declaration.
    mutating func declareDataType(
        package: String, name: String, instanceClassName: String?, range: SourceRange?
    ) {
        let key = TypeKey.generated(package: package, name: name)
        guard positions[key] == nil else { return }
        add(InferredClassifier(
            key: key, package: package, name: name, kind: .dataType, isDeclared: true,
            instanceClassName: instanceClassName, range: range))
    }

    /// Whether a generated classifier exists.
    ///
    /// - Parameter key: The key of the classifier.
    /// - Returns: `true` if it has been declared or inferred.
    func exists(_ key: TypeKey) -> Bool { positions[key] != nil }

    /// Records a new classifier.
    ///
    /// - Parameter classifier: The classifier.
    private mutating func add(_ classifier: InferredClassifier) {
        positions[classifier.key] = classifiers.count
        classifiers.append(classifier)
    }

    // MARK: Running

    /// Infers the classifiers of a grammar.
    ///
    /// - Parameters:
    ///   - grammarRules: The rules written in the grammar, in order.
    ///   - inheritedRules: Predefined rules, such as Xtext's common terminals,
    ///     which grammar rules of the same name replace.
    /// - Returns: The packages with their classifiers.
    mutating func run(_ grammarRules: [GrammarRule], inheritedRules: [GrammarRule] = []) -> [GrammarDraftPackage] {
        for rule in inheritedRules { rules[rule.name] = rule }
        var seen: Set<String> = []
        for rule in grammarRules {
            if !seen.insert(rule.name).inserted {
                collector.error(
                    dialect.code(.duplicateRule), "The rule '\(rule.name)' is defined more than once",
                    at: rule.nameRange)
            }
            rules[rule.name] = rule
        }
        let ordered = grammarRules.filter { rules[$0.name] == $0 }
        classifyDatatypeRules(ordered)
        for rule in ordered { _ = type(of: rule) }
        applyMemberships()
        for rule in ordered { deriveHierarchy(rule) }
        for rule in ordered { deriveFeatures(rule) }
        for rule in ordered where rule.kind == .infix { deriveInfixFeatures(rule) }
        for rule in ordered where rule.kind == .enumeration { deriveLiterals(rule) }
        if configuration.liftsCommonFeatures { liftCommonFeatures() }
        pushFeaturesUp()
        removeDuplicatedFeatures()
        return emit()
    }

    // MARK: Pass 1: classification

    /// Decides which parser rules are datatype rules.
    ///
    /// A rule whose declared return type is a data type is one. Otherwise a
    /// rule qualifies when its body has no assignments and no actions and calls
    /// only terminal rules and other datatype rules; the qualifying set is
    /// found by removing rules that fail until nothing changes.
    ///
    /// - Parameter ordered: The grammar rules.
    private mutating func classifyDatatypeRules(_ ordered: [GrammarRule]) {
        var candidates: Set<String> = []
        for rule in ordered where rule.kind == .parser && !rule.isFragment {
            if let declared = rule.returnType {
                switch resolver(declared, .parserRule) {
                case .ecore:
                    datatypeRules.insert(rule.name)
                    continue
                case .eObject, .external, .unresolved:
                    continue
                case .generated(let package, let name):
                    if let index = positions[.generated(package: package, name: name)] {
                        if classifiers[index].kind != .eClass { datatypeRules.insert(rule.name) }
                        continue
                    }
                }
            }
            guard let body = rule.body else { continue }
            let structural = body.contains { element in
                switch element.kind {
                case .assignment, .action: true
                default: false
                }
            }
            if !structural { candidates.insert(rule.name) }
        }
        var changed = true
        while changed {
            changed = false
            for name in candidates {
                guard let body = rules[name]?.body else { continue }
                let callsObjects = body.contains { element in
                    guard case .ruleCall(let called) = element.kind else { return false }
                    if datatypeRules.contains(called) || candidates.contains(called) { return false }
                    if let target = rules[called] { return target.kind != .terminal }
                    if case .dataType = externalRule(called) { return false }
                    return true
                }
                if callsObjects {
                    candidates.remove(name)
                    changed = true
                }
            }
        }
        datatypeRules.formUnion(candidates)
    }

    /// Whether a rule yields values rather than objects.
    ///
    /// - Parameter rule: The rule.
    /// - Returns: `true` for terminal and datatype rules.
    private func isDataRule(_ rule: GrammarRule) -> Bool {
        rule.kind == .terminal || (rule.kind == .parser && datatypeRules.contains(rule.name))
    }

    /// Whether a rule is inlined into its callers instead of having a type.
    ///
    /// - Parameter rule: The rule.
    /// - Returns: `true` for wildcard fragments and, when configured, all parser fragments.
    private func isInlined(_ rule: GrammarRule) -> Bool {
        rule.kind == .parser && (rule.isWildcardFragment || (rule.isFragment && configuration.inlinesFragments))
    }

    // MARK: Pass 2: types

    /// The type of a rule, creating its classifier on first use.
    ///
    /// - Parameter rule: The rule.
    /// - Returns: The type, or `nil` for rules without one (terminal fragments, inlined fragments).
    private mutating func type(of rule: GrammarRule) -> TypeKey? {
        if let known = ruleTypes[rule.name] { return known }
        if isInlined(rule) || (rule.kind == .terminal && rule.isFragment) { return nil }
        let key: TypeKey
        switch rule.kind {
        case .terminal:
            key = dataType(rule.returnType)
        case .parser where datatypeRules.contains(rule.name):
            key = dataType(rule.returnType)
        case .enumeration:
            key = classifier(rule.typeReference, role: .enumRule, kind: .eEnum)
        case .parser, .infix:
            key = classifier(rule.typeReference, role: .parserRule, kind: .eClass)
        }
        ruleTypes[rule.name] = key
        return key
    }

    /// The value type of a terminal or datatype rule.
    ///
    /// - Parameter reference: The declared return type, if any.
    /// - Returns: The type; `EString` when none is declared, as in Xtext and Langium.
    private mutating func dataType(_ reference: RuleTypeReference?) -> TypeKey {
        guard let reference else { return .ecore(.eString) }
        return classifier(reference, role: .dataRule, kind: .dataType)
    }

    /// The type a reference denotes, creating a generated classifier if needed.
    ///
    /// - Parameters:
    ///   - reference: The written reference.
    ///   - role: Where the reference occurs.
    ///   - kind: The kind of classifier to create.
    /// - Returns: The type.
    private mutating func classifier(
        _ reference: RuleTypeReference, role: TypeRole, kind: InferredClassifierKind
    ) -> TypeKey {
        switch resolver(reference, role) {
        case .ecore(let type): return .ecore(type)
        case .eObject: return .eObject
        case .external(let name, let origin):
            noteExternal(name: name, origin: origin, isData: kind == .dataType, range: reference.range)
            return kind == .dataType ? .externalData(name: name, origin: origin) : .externalClass(name: name, origin: origin)
        case .unresolved(let message):
            collector.error(dialect.code(.unresolvedTypeReference), message, at: reference.range)
            return kind == .dataType ? .ecore(.eString) : .excluded(reference.name)
        case .generated(let package, let name):
            let key = TypeKey.generated(package: package, name: name)
            if positions[key] != nil { return key }
            if !configuration.allowsInferredTypes {
                collector.error(
                    dialect.code(.inferredTypeNotAllowed),
                    "The type '\(name)' is not declared, and only declared types are allowed",
                    at: reference.range)
                return kind == .dataType ? .ecore(.eString) : .excluded(name)
            }
            add(InferredClassifier(
                key: key, package: package, name: name, kind: kind, isDeclared: false,
                instanceClassName: kind == .dataType ? "java.lang.String" : nil, range: reference.range))
            return key
        }
    }

    /// Reports, once per type, that a type belongs to a package that is not generated.
    ///
    /// - Parameters:
    ///   - name: The name of the type.
    ///   - origin: The package it belongs to.
    ///   - isData: Whether it is used as a data type.
    ///   - range: Where it is first named.
    private mutating func noteExternal(name: String, origin: String, isData: Bool, range: SourceRange?) {
        guard reported.insert("external\u{0}\(origin)\u{0}\(name)").inserted else { return }
        let stand = isData ? EcoreDataType.eString.rawValue : EcoreClassifier.eObject.rawValue
        collector.warning(
            dialect.code(.externalType),
            "The type '\(name)' belongs to '\(origin)', which is not generated; '\(stand)' stands in for it",
            at: range)
    }

    /// The position of a generated classifier.
    ///
    /// - Parameter key: The key.
    /// - Returns: The position, or `nil` for types that are not generated.
    private func index(_ key: TypeKey) -> Int? { positions[key] }

    /// Whether a type is a class.
    ///
    /// - Parameter key: The type.
    /// - Returns: `true` for generated classes, `EObject`, external and excluded classes.
    private func isClass(_ key: TypeKey) -> Bool {
        switch key {
        case .generated: index(key).map { classifiers[$0].kind == .eClass } ?? false
        case .eObject, .externalClass, .excluded: true
        case .ecore, .externalData: false
        }
    }

    // MARK: Pass 3: hierarchy

    /// Derives the supertype relations that a parser rule implies.
    ///
    /// - Parameter rule: The rule.
    private mutating func deriveHierarchy(_ rule: GrammarRule) {
        guard rule.kind == .parser, !isDataRule(rule), !isInlined(rule), let body = rule.body,
            let ruleType = type(of: rule)
        else { return }
        var visiting: Set<String> = [rule.name]
        hierarchy(of: body, rule: rule, ruleType: ruleType, visiting: &visiting)
    }

    /// Derives supertype relations from an element and what it contains, skipping assignments.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - rule: The rule that contains it.
    ///   - ruleType: The type of the rule.
    ///   - visiting: The fragments being visited, to stop recursion.
    private mutating func hierarchy(
        of element: RuleElement, rule: GrammarRule, ruleType: TypeKey, visiting: inout Set<String>
    ) {
        switch element.kind {
        case .action(let reference, _, _):
            let actionType = classifier(reference, role: .action, kind: .eClass)
            addSuperType(ruleType, to: actionType, range: element.range)
        case .group(let elements), .alternatives(let elements), .unorderedGroup(let elements):
            for child in elements { hierarchy(of: child, rule: rule, ruleType: ruleType, visiting: &visiting) }
        case .ruleCall(let name):
            guard let called = rules[name] else {
                if case .parserRule(let resolution)? = externalRule(name), case .generated = resolution {
                    let calledType = classifier(RuleTypeReference(name: name), role: .parserRule, kind: .eClass)
                    addSuperType(ruleType, to: calledType, range: element.range)
                }
                return
            }
            if isDataRule(called) { return }
            switch called.kind {
            case .enumeration:
                collector.error(
                    dialect.code(.invalidRuleCall),
                    "The enum rule '\(name)' cannot be called without an assignment", at: element.range)
            case .terminal:
                return
            case .parser where isInlined(called):
                guard configuration.inlinesFragments, visiting.insert(name).inserted, let body = called.body else {
                    return
                }
                hierarchy(of: body, rule: rule, ruleType: ruleType, visiting: &visiting)
                visiting.remove(name)
            case .parser where called.isFragment:
                if let fragmentType = type(of: called) {
                    addSuperType(fragmentType, to: ruleType, range: element.range)
                }
                if visiting.insert(name).inserted, let body = called.body {
                    hierarchy(of: body, rule: rule, ruleType: ruleType, visiting: &visiting)
                    visiting.remove(name)
                }
            case .parser:
                if let calledType = type(of: called) { addSuperType(ruleType, to: calledType, range: element.range) }
            case .infix:
                if let calledType = type(of: called) { addSuperType(ruleType, to: calledType, range: element.range) }
                if let operand = called.infixOperand, let operandRule = rules[operand], !isDataRule(operandRule),
                    let operandType = type(of: operandRule)
                {
                    addSuperType(ruleType, to: operandType, range: element.range)
                }
            }
        default:
            return
        }
    }

    /// Makes one type a direct supertype of another.
    ///
    /// Supertypes are only added to inferred generated classes; declared and
    /// external classes keep their own hierarchy. A type is never its own supertype.
    ///
    /// - Parameters:
    ///   - superType: The supertype.
    ///   - subType: The subtype.
    ///   - range: The element that implies the relation.
    private mutating func addSuperType(_ superType: TypeKey, to subType: TypeKey, range: SourceRange?) {
        guard superType != subType, let subIndex = index(subType), !classifiers[subIndex].isDeclared,
            classifiers[subIndex].kind == .eClass
        else { return }
        guard case .generated = superType else { return }
        guard isClass(superType) else {
            collector.error(
                dialect.code(.invalidRuleCall),
                "'\(subType.displayName)' cannot inherit from the data type '\(superType.displayName)'", at: range)
            return
        }
        if !classifiers[subIndex].superTypes.contains(superType) {
            classifiers[subIndex].superTypes.append(superType)
        }
    }

    /// All supertypes of a class, nearest first, without the class itself.
    ///
    /// - Parameter key: The class.
    /// - Returns: The generated supertypes in breadth-first order.
    private func allSuperTypes(_ key: TypeKey) -> [TypeKey] {
        var result: [TypeKey] = []
        var queue = index(key).map { classifiers[$0].superTypes } ?? []
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard !result.contains(next), next != key else { continue }
            result.append(next)
            queue += index(next).map { classifiers[$0].superTypes } ?? []
        }
        return result
    }

    /// Whether one type is a supertype of, or the same as, another.
    ///
    /// - Parameters:
    ///   - superType: The candidate supertype.
    ///   - subType: The candidate subtype.
    /// - Returns: `true` if values of `subType` are values of `superType`.
    private func isSuperType(_ superType: TypeKey, of subType: TypeKey) -> Bool {
        if superType == subType { return true }
        if superType == .eObject { return isClass(subType) }
        return allSuperTypes(subType).contains(superType)
    }

    /// The instance class that decides whether two data types are compatible.
    ///
    /// - Parameter key: A data type.
    /// - Returns: The name of the implementing class.
    private func instanceName(_ key: TypeKey) -> String {
        switch key {
        case .ecore(let type): type == .eString ? "java.lang.String" : type.rawValue
        case .generated:
            index(key).flatMap { classifiers[$0].kind == .dataType ? classifiers[$0].instanceClassName : nil }
                ?? key.displayName
        case .externalData: "java.lang.String"
        default: key.displayName
        }
    }

    /// The most specific type that two types share, after Xtext's `EcoreUtil2.getCompatibleType`.
    ///
    /// Classes meet at their most specific common supertype, or at `EObject`
    /// when they have none. Data types are compatible only when their values
    /// have the same implementing class.
    ///
    /// - Parameters:
    ///   - first: One type.
    ///   - second: The other type.
    /// - Returns: The compatible type, or `nil` if there is none.
    func compatibleType(_ first: TypeKey, _ second: TypeKey) -> TypeKey? {
        if first == second { return first }
        let firstIsClass = isClass(first)
        let secondIsClass = isClass(second)
        if firstIsClass && secondIsClass {
            if isSuperType(first, of: second) { return first }
            if isSuperType(second, of: first) { return second }
            let secondAncestors = Set(allSuperTypes(second))
            let common = allSuperTypes(first).filter { secondAncestors.contains($0) }
            let minimal = common.filter { candidate in
                !common.contains { other in other != candidate && isSuperType(candidate, of: other) }
            }
            return minimal.first ?? .eObject
        }
        if !firstIsClass && !secondIsClass, first.isDataLike, second.isDataLike,
            instanceName(first) == instanceName(second)
        {
            return first
        }
        return nil
    }

    /// The compatible type of a set of types.
    ///
    /// - Parameter types: The types; must not be empty to have a result.
    /// - Returns: The compatible type, or `nil` if there is none.
    private func compatibleType(of types: [TypeKey]) -> TypeKey? {
        guard var result = types.first else { return nil }
        for next in types.dropFirst() {
            guard let combined = compatibleType(result, next) else { return nil }
            result = combined
        }
        return result
    }

    // MARK: Pass 4: features

    /// The state of interpretation: the current types and whether the type may still change.
    private struct Context: Hashable {
        /// The types that receive features, in order of arrival.
        var types: [TypeKey]
        /// Whether an unassigned rule call may still change the type.
        var isRuleCallAllowed: Bool
        /// Whether some path to here has not changed the type, so the rule's own object may be current.
        var isFresh = true

        /// The union of several contexts; a type change is allowed only if every one allows it.
        ///
        /// - Parameter contexts: The contexts to merge.
        /// - Returns: The merged context.
        static func merged(_ contexts: [Context]) -> Context {
            var result = Context(types: [], isRuleCallAllowed: true, isFresh: false)
            for context in contexts {
                for type in context.types where !result.types.contains(type) { result.types.append(type) }
                result.isRuleCallAllowed = result.isRuleCallAllowed && context.isRuleCallAllowed
                result.isFresh = result.isFresh || context.isFresh
            }
            return result
        }
    }

    /// Derives the features that a rule's assignments and actions imply.
    ///
    /// - Parameter rule: The rule.
    private mutating func deriveFeatures(_ rule: GrammarRule) {
        guard rule.kind == .parser, !isDataRule(rule), !isInlined(rule), let body = rule.body,
            let ruleType = type(of: rule)
        else { return }
        var visiting: Set<String> = [rule.name]
        let end = derive(Context(types: [ruleType], isRuleCallAllowed: true), body, visiting: &visiting)
        if end.isFresh && !rule.isFragment { instantiated.insert(ruleType) }
    }

    /// Interprets an element in a context.
    ///
    /// - Parameters:
    ///   - context: The context before the element.
    ///   - element: The element.
    ///   - visiting: The inlined fragments being visited, to stop recursion.
    /// - Returns: The context after the element.
    private mutating func derive(_ context: Context, _ element: RuleElement, visiting: inout Set<String>) -> Context {
        switch element.kind {
        case .alternatives(let branches):
            var contexts: [Context] = element.cardinality.isOptional ? [context] : []
            for branch in branches { contexts.append(derive(context, branch, visiting: &visiting)) }
            let result = Context.merged(contexts)
            if element.cardinality.isMultiple {
                for branch in branches { _ = derive(result, branch, visiting: &visiting) }
            }
            return result
        case .unorderedGroup(let groups):
            var contexts: [Context] = []
            for group in groups { contexts.append(derive(context, group, visiting: &visiting)) }
            if element.cardinality.isOptional { contexts.insert(context, at: 0) }
            return Context.merged(contexts)
        case .group(let elements):
            return deriveSequence(context, elements, cardinality: element.cardinality, visiting: &visiting)
        case .assignment(let feature, let op, let terminal):
            addFeature(feature, operator: op, terminal: terminal, to: context.types, range: element.range)
            return context
        case .ruleCall(let name):
            return deriveRuleCall(context, name: name, element: element, visiting: &visiting)
        case .action(let reference, let feature, let op):
            let actionType = classifier(reference, role: .action, kind: .eClass)
            instantiated.insert(actionType)
            if let feature {
                let previous = compatibleType(of: context.types) ?? .eObject
                addFeature(
                    named: feature, types: [previous], isMany: op == .add, isContainment: true, to: [actionType],
                    range: element.range)
            }
            return Context(types: [actionType], isRuleCallAllowed: false, isFresh: false)
        case .keyword, .crossReference, .other:
            return context
        }
    }

    /// Interprets a sequence, applying its cardinality as Xtext does for groups.
    ///
    /// - Parameters:
    ///   - context: The context before the sequence.
    ///   - elements: The elements in order.
    ///   - cardinality: The cardinality of the sequence.
    ///   - visiting: The inlined fragments being visited.
    /// - Returns: The context after the sequence.
    private mutating func deriveSequence(
        _ context: Context, _ elements: [RuleElement], cardinality: RuleCardinality, visiting: inout Set<String>
    ) -> Context {
        var result = context
        for element in elements { result = derive(result, element, visiting: &visiting) }
        if cardinality.isMultiple {
            for element in elements { result = derive(result, element, visiting: &visiting) }
        }
        if cardinality.isOptional { result = Context.merged([context, result]) }
        return result
    }

    /// Interprets an unassigned rule call.
    ///
    /// - Parameters:
    ///   - context: The context before the call.
    ///   - name: The called rule.
    ///   - element: The call.
    ///   - visiting: The inlined fragments being visited.
    /// - Returns: The context after the call.
    private mutating func deriveRuleCall(
        _ context: Context, name: String, element: RuleElement, visiting: inout Set<String>
    ) -> Context {
        guard let called = rules[name] else {
            switch knownExternalRule(name, range: element.range) {
            case .parserRule(let resolution)?:
                guard !element.cardinality.isOptional else { return context }
                let key = externalRuleType(name, resolution)
                return switchType(context, to: key, range: element.range)
            default:
                return context
            }
        }
        if isInlined(called) {
            guard visiting.insert(name).inserted, let body = called.body else { return context }
            defer { visiting.remove(name) }
            return deriveSequence(context, [body], cardinality: element.cardinality, visiting: &visiting)
        }
        if called.kind == .parser && called.isFragment { return context }
        guard !element.cardinality.isOptional, called.kind == .parser || called.kind == .infix,
            !isDataRule(called), let calledType = type(of: called)
        else { return context }
        return switchType(context, to: calledType, range: element.range)
    }

    /// Replaces the current types after an unassigned rule call.
    ///
    /// - Parameters:
    ///   - context: The context before the call.
    ///   - type: The called rule's type.
    ///   - range: The call.
    /// - Returns: The context with only the called type, or the old one after reporting a second change.
    private mutating func switchType(_ context: Context, to type: TypeKey, range: SourceRange?) -> Context {
        guard context.isRuleCallAllowed else {
            collector.error(
                dialect.code(.typeChangedTwice), "A rule cannot change the type of the current object twice",
                at: range)
            return context
        }
        return Context(types: [type], isRuleCallAllowed: false, isFresh: false)
    }

    /// Describes a rule the grammar does not define, reporting it once.
    ///
    /// - Parameters:
    ///   - name: The rule name.
    ///   - range: The call.
    /// - Returns: What the rule stands for, or `nil` after reporting it as unknown.
    private mutating func knownExternalRule(_ name: String, range: SourceRange?) -> ExternalRule? {
        let external = externalRule(name)
        if reported.insert("rule\u{0}\(name)").inserted {
            switch external {
            case .dataType?:
                collector.warning(
                    dialect.code(.unknownRule),
                    "The rule '\(name)' is not defined in this grammar; it is taken to be a datatype rule",
                    at: range)
            case .parserRule?:
                collector.warning(
                    dialect.code(.unknownRule),
                    "The rule '\(name)' is not defined in this grammar; it is taken to be a parser rule of another grammar",
                    at: range)
            case nil:
                collector.error(dialect.code(.unknownRule), "The rule '\(name)' is not defined", at: range)
            }
        }
        return external
    }

    /// The type of a rule from another grammar.
    ///
    /// - Parameters:
    ///   - name: The rule name.
    ///   - resolution: What the rule's type resolves to.
    /// - Returns: The type.
    private mutating func externalRuleType(_ name: String, _ resolution: TypeResolution) -> TypeKey {
        switch resolution {
        case .ecore(let type): return .ecore(type)
        case .eObject: return .eObject
        case .external(let type, let origin): return .externalClass(name: type, origin: origin)
        case .unresolved: return .excluded(name)
        case .generated: return classifier(RuleTypeReference(name: name), role: .parserRule, kind: .eClass)
        }
    }

    /// The types that the terminal of an assignment yields.
    ///
    /// - Parameter terminal: What is assigned.
    /// - Returns: The types and whether any of them is contained (not a cross-reference),
    ///   or `nil` after reporting a problem.
    private mutating func terminalTypes(_ terminal: RuleElement) -> (types: [TypeKey], isContainment: Bool)? {
        switch terminal.kind {
        case .keyword:
            return ([.ecore(.eString)], true)
        case .crossReference(let reference, _, _):
            return ([classifier(reference, role: .crossReference, kind: .eClass)], false)
        case .alternatives(let choices):
            var types: [TypeKey] = []
            var containment = false
            for choice in choices {
                guard let (choiceTypes, contained) = terminalTypes(choice) else { return nil }
                for type in choiceTypes where !types.contains(type) { types.append(type) }
                containment = containment || contained
            }
            return (types, containment)
        case .ruleCall(let name):
            guard let called = rules[name] else {
                switch knownExternalRule(name, range: terminal.range) {
                case .dataType(let resolution)?:
                    switch resolution {
                    case .ecore(let type): return ([.ecore(type)], true)
                    default: return ([.ecore(.eString)], true)
                    }
                case .parserRule(let resolution)?:
                    return ([externalRuleType(name, resolution)], true)
                case nil:
                    return nil
                }
            }
            if called.isFragment && called.kind != .terminal {
                collector.error(
                    dialect.code(.invalidRuleCall), "The fragment '\(name)' cannot be called from an assignment",
                    at: terminal.range)
                return nil
            }
            guard let type = type(of: called) else { return nil }
            return ([type], true)
        default:
            return nil
        }
    }

    /// Adds the feature of an assignment to the current types.
    ///
    /// - Parameters:
    ///   - name: The feature name.
    ///   - op: The assignment operator.
    ///   - terminal: What is assigned.
    ///   - owners: The current types.
    ///   - range: The assignment.
    private mutating func addFeature(
        _ name: String, operator op: RuleAssignmentOperator, terminal: RuleElement, to owners: [TypeKey],
        range: SourceRange?
    ) {
        if op == .flag {
            addFeature(named: name, types: [.ecore(.eBoolean)], isMany: false, isContainment: false, to: owners, range: range)
            return
        }
        guard let (types, containment) = terminalTypes(terminal) else { return }
        var isMany = op == .add
        if case .crossReference(_, _, true) = terminal.kind, !isMany {
            isMany = true
            collector.information(
                dialect.code(.approximation), "The multi-reference '\(name)' becomes a list of references", at: range)
        }
        addFeature(named: name, types: types, isMany: isMany, isContainment: containment, to: owners, range: range)
    }

    /// Adds a feature to each of a set of types, merging it with an existing feature of the same name.
    ///
    /// - Parameters:
    ///   - name: The feature name.
    ///   - types: The types of the assigned values.
    ///   - isMany: Whether the feature holds a list.
    ///   - isContainment: Whether a reference contains its targets.
    ///   - owners: The types that receive the feature.
    ///   - range: The element that implies the feature.
    private mutating func addFeature(
        named name: String, types: [TypeKey], isMany: Bool, isContainment: Bool, to owners: [TypeKey],
        range: SourceRange?
    ) {
        guard !types.isEmpty else { return }
        var featureType = compatibleType(of: types)
        if featureType == nil {
            collector.error(
                dialect.code(.incompatibleTypes),
                "The values assigned to '\(name)' have no common type ("
                    + types.map(\.displayName).joined(separator: ", ") + ")", at: range)
            featureType = types[0]
        }
        guard let featureType else { return }
        for owner in owners {
            guard let ownerIndex = index(owner), classifiers[ownerIndex].kind == .eClass else {
                if case .externalClass = owner, reported.insert("sealed\u{0}\(owner.displayName)").inserted {
                    collector.warning(
                        dialect.code(.sealedType),
                        "Features cannot be added to '\(owner.displayName)', which is not generated; '\(name)' is ignored",
                        at: range)
                }
                continue
            }
            if classifiers[ownerIndex].isDeclared {
                if findFeature(name, in: owner) == nil,
                    reported.insert("undeclared\u{0}\(owner.displayName)\u{0}\(name)").inserted
                {
                    collector.warning(
                        dialect.code(.undeclaredProperty),
                        "The declared type '\(owner.displayName)' has no property '\(name)'", at: range)
                }
                continue
            }
            let isReference = isClass(featureType)
            let candidate = InferredFeature(
                name: name, type: featureType, isMany: isMany, isContainment: isReference && isContainment,
                range: range)
            guard let (holder, position) = findFeature(name, in: owner) else {
                classifiers[ownerIndex].features.append(candidate)
                continue
            }
            let existing = classifiers[holder].features[position]
            if isSemanticallyEqual(existing, candidate, assigned: types) { continue }
            let existingIsReference = isClass(existing.type)
            guard existing.isMany == candidate.isMany,
                !(existingIsReference && isReference) || existing.isContainment == candidate.isContainment
            else {
                collector.error(
                    dialect.code(.featureConflict),
                    "A feature '\(name)' with a different cardinality or containment already exists in '\(owner.displayName)'",
                    at: range)
                continue
            }
            guard let widened = compatibleType(existing.type, featureType) else {
                collector.error(
                    dialect.code(.incompatibleTypes),
                    "The feature '\(name)' of '\(owner.displayName)' cannot hold both '\(existing.type.displayName)' and '\(featureType.displayName)'",
                    at: range)
                continue
            }
            if !classifiers[holder].isDeclared { classifiers[holder].features[position].type = widened }
        }
    }

    /// Finds a feature of a class or of its supertypes.
    ///
    /// - Parameters:
    ///   - name: The feature name.
    ///   - owner: The class.
    /// - Returns: The position of the class that holds the feature and of the feature in it.
    private func findFeature(_ name: String, in owner: TypeKey) -> (Int, Int)? {
        for key in [owner] + allSuperTypes(owner) {
            guard let holder = index(key) else { continue }
            if let position = classifiers[holder].features.firstIndex(where: { $0.name == name }) {
                return (holder, position)
            }
        }
        return nil
    }

    /// Whether an existing feature already accommodates a new one, after Xtext's `isFeatureSemanticallyEqualTo`.
    ///
    /// - Parameters:
    ///   - existing: The existing feature.
    ///   - candidate: The new feature.
    ///   - assigned: The types of the values the new feature receives.
    /// - Returns: `true` if nothing needs to change.
    private func isSemanticallyEqual(_ existing: InferredFeature, _ candidate: InferredFeature, assigned: [TypeKey]) -> Bool {
        guard existing.name == candidate.name, existing.isMany == candidate.isMany else { return false }
        if isClass(existing.type) && isClass(candidate.type) {
            guard existing.isContainment == candidate.isContainment else { return false }
            return assigned.allSatisfy { isClass($0) && isSuperType(existing.type, of: $0) }
        }
        return compatibleType(existing.type, candidate.type) == existing.type
    }

    /// Adds the features of a Langium infix rule: `left`, `operator` and `right`.
    ///
    /// The operands are typed with the most specific type shared by the infix
    /// rule's own type and its operand rule's type.
    ///
    /// - Parameter rule: The infix rule.
    private mutating func deriveInfixFeatures(_ rule: GrammarRule) {
        guard let ruleType = type(of: rule) else { return }
        instantiated.insert(ruleType)
        var operandType: TypeKey = .eObject
        if let operand = rule.infixOperand {
            if let operandRule = rules[operand], let key = type(of: operandRule) {
                operandType = compatibleType(ruleType, key) ?? .eObject
            } else {
                collector.error(dialect.code(.unknownRule), "The rule '\(operand)' is not defined", at: rule.nameRange)
            }
        }
        addFeature(named: "left", types: [operandType], isMany: false, isContainment: true, to: [ruleType], range: rule.nameRange)
        addFeature(
            named: "operator", types: [.ecore(.eString)], isMany: false, isContainment: false, to: [ruleType],
            range: rule.nameRange)
        addFeature(named: "right", types: [operandType], isMany: false, isContainment: true, to: [ruleType], range: rule.nameRange)
    }

    /// Adds the literals of an enum rule to its enumeration.
    ///
    /// A literal named twice is kept once, as in Xtext; its text is the first keyword given.
    ///
    /// - Parameter rule: The enum rule.
    private mutating func deriveLiterals(_ rule: GrammarRule) {
        guard let key = type(of: rule), let position = index(key), classifiers[position].kind == .eEnum,
            !classifiers[position].isDeclared
        else { return }
        for literal in rule.literals where !classifiers[position].literals.contains(where: { $0.name == literal.name }) {
            classifiers[position].literals.append(GrammarDraftLiteral(
                name: literal.name, literal: literal.keyword ?? literal.name, range: literal.range))
        }
    }

    // MARK: Pass 5: normalisation

    /// The direct subtypes of every generated class, in creation order.
    ///
    /// - Returns: The subtypes by supertype.
    private func directSubTypes() -> [TypeKey: [TypeKey]] {
        var result: [TypeKey: [TypeKey]] = [:]
        for classifier in classifiers where classifier.kind == .eClass {
            for superType in classifier.superTypes where index(superType) != nil {
                result[superType, default: []].append(classifier.key)
            }
        }
        return result
    }

    /// Moves features that all direct subtypes of a class share into that class, deepest classes first.
    ///
    /// This follows Xtext's `TypeHierarchyHelper.liftUpFeaturesRecursively`:
    /// features are lifted only into an inferred class that is the compatible
    /// type of its direct subtypes, and are removed from the subtypes afterwards.
    private mutating func liftCommonFeatures() {
        let subTypes = directSubTypes()
        var traversed: Set<TypeKey> = []
        var removals: [TypeKey: [InferredFeature]] = [:]
        let roots = classifiers.filter { $0.kind == .eClass && $0.superTypes.isEmpty }.map(\.key)
        for root in roots { lift(into: root, subTypes: subTypes, traversed: &traversed, removals: &removals) }
        for (key, features) in removals {
            guard let position = index(key) else { continue }
            classifiers[position].features.removeAll { feature in features.contains { $0.name == feature.name } }
        }
    }

    /// Lifts features into one class after lifting into its subtypes.
    ///
    /// - Parameters:
    ///   - superType: The class.
    ///   - subTypes: The direct subtypes of every class.
    ///   - traversed: The classes already visited.
    ///   - removals: The features to remove from subtypes at the end.
    private mutating func lift(
        into superType: TypeKey, subTypes: [TypeKey: [TypeKey]], traversed: inout Set<TypeKey>,
        removals: inout [TypeKey: [InferredFeature]]
    ) {
        guard traversed.insert(superType).inserted, let children = subTypes[superType], !children.isEmpty else {
            return
        }
        for child in children { lift(into: child, subTypes: subTypes, traversed: &traversed, removals: &removals) }
        guard let superIndex = index(superType), !classifiers[superIndex].isDeclared,
            compatibleType(of: children) == superType, let first = index(children[0])
        else { return }
        var common = classifiers[first].features
        for child in children.dropFirst() {
            common = common.filter { feature in containsEqualFeature(feature, in: child) }
        }
        var lifted: [InferredFeature] = []
        for feature in common {
            if let (holder, position) = findFeature(feature.name, in: superType) {
                if isSemanticallyEqual(classifiers[holder].features[position], feature, assigned: [feature.type]) {
                    lifted.append(feature)
                }
            } else {
                classifiers[superIndex].features.append(feature)
                lifted.append(feature)
            }
        }
        for child in children {
            let owned = classifiers[index(child)!].features.filter { feature in
                lifted.contains { $0.name == feature.name && isSemanticallyEqual($0, feature, assigned: [feature.type]) }
            }
            removals[child, default: []] += owned
        }
    }

    /// Whether a class has (or inherits) a feature equal to a given one.
    ///
    /// - Parameters:
    ///   - feature: The feature to look for.
    ///   - owner: The class.
    /// - Returns: `true` if an equal feature exists.
    private func containsEqualFeature(_ feature: InferredFeature, in owner: TypeKey) -> Bool {
        guard let (holder, position) = findFeature(feature.name, in: owner) else { return false }
        return isSemanticallyEqual(classifiers[holder].features[position], feature, assigned: [feature.type])
    }

    /// Replaces a feature that repeats a uniquely inherited one by widening the inherited one, after Xtext's `pushFeaturesUp`.
    private mutating func pushFeaturesUp() {
        for position in classifiers.indices where classifiers[position].kind == .eClass && !classifiers[position].isDeclared {
            let key = classifiers[position].key
            var inherited: [String: (Int, Int)] = [:]
            var ambiguous: Set<String> = []
            for superType in allSuperTypes(key) {
                guard let holder = index(superType) else { continue }
                for (featureIndex, feature) in classifiers[holder].features.enumerated() {
                    if let previous = inherited[feature.name], previous != (holder, featureIndex) {
                        ambiguous.insert(feature.name)
                    } else {
                        inherited[feature.name] = (holder, featureIndex)
                    }
                }
            }
            var pushed: Set<String> = []
            for declared in classifiers[position].features {
                guard !ambiguous.contains(declared.name), let (holder, featureIndex) = inherited[declared.name],
                    !classifiers[holder].isDeclared
                else { continue }
                let existing = classifiers[holder].features[featureIndex]
                guard existing.isMany == declared.isMany,
                    let widened = compatibleType(declared.type, existing.type)
                else { continue }
                classifiers[holder].features[featureIndex].type = widened
                pushed.insert(declared.name)
            }
            classifiers[position].features.removeAll { pushed.contains($0.name) }
        }
    }

    /// Removes inferred features that a supertype already has in the same form.
    private mutating func removeDuplicatedFeatures() {
        for position in classifiers.indices where classifiers[position].kind == .eClass && !classifiers[position].isDeclared {
            let key = classifiers[position].key
            let superTypes = allSuperTypes(key)
            let duplicated = Set(classifiers[position].features.filter { feature in
                superTypes.contains { superType in
                    guard let holder = index(superType),
                        let existing = classifiers[holder].features.first(where: { $0.name == feature.name })
                    else { return false }
                    return isSemanticallyEqual(existing, feature, assigned: [feature.type])
                }
            }.map(\.name))
            classifiers[position].features.removeAll { duplicated.contains($0.name) }
        }
    }

    // MARK: Emitting

    /// Turns the inferred classifiers into draft packages.
    ///
    /// - Returns: The packages, in the order given, with classifiers in creation order.
    private mutating func emit() -> [GrammarDraftPackage] {
        let subTypes = directSubTypes()
        var result = packages
        for classifier in classifiers {
            guard let packageIndex = result.firstIndex(where: { $0.name == classifier.package }) else {
                collector.error(
                    dialect.code(.unresolvedTypeReference),
                    "The type '\(classifier.name)' belongs to no generated package '\(classifier.package)'",
                    at: classifier.range)
                continue
            }
            let draft: GrammarDraftClassifier
            switch classifier.kind {
            case .eEnum:
                draft = .eEnum(GrammarDraftEnum(name: classifier.name, literals: classifier.literals, range: classifier.range))
            case .dataType:
                draft = .dataType(GrammarDraftDataType(
                    name: classifier.name, instanceClassName: classifier.instanceClassName, range: classifier.range))
            case .eClass:
                let isUnion = configuration.marksUnionTypesAbstract && !classifier.isDeclared
                    && !instantiated.contains(classifier.key) && !(subTypes[classifier.key] ?? []).isEmpty
                draft = .eClass(GrammarDraftClass(
                    name: classifier.name, isAbstract: classifier.isAbstract || isUnion,
                    superTypes: classifier.superTypes.compactMap(draftReference),
                    features: classifier.features.map { draftFeature($0, owner: classifier) },
                    range: classifier.range))
            }
            result[packageIndex].classifiers.append(draft)
        }
        return result
    }

    /// The draft reference for a supertype.
    ///
    /// - Parameter key: The supertype.
    /// - Returns: The reference, or `nil` for supertypes that cannot be represented.
    private func draftReference(_ key: TypeKey) -> GrammarDraftTypeReference? {
        guard case .generated(let package, let name) = key, isClass(key) else { return nil }
        return .named(name, package: package)
    }

    /// The draft of a feature.
    ///
    /// The type of a declared union is resolved here, once every type exists.
    ///
    /// - Parameters:
    ///   - feature: The feature.
    ///   - owner: The class that holds it.
    /// - Returns: The draft feature.
    private mutating func draftFeature(_ feature: InferredFeature, owner: InferredClassifier) -> GrammarDraftFeature {
        var type = feature.type
        if !feature.unionTypes.isEmpty {
            let available = feature.unionTypes.map { candidate -> TypeKey in
                if case .generated = candidate, index(candidate) == nil { return .eObject }
                return candidate
            }
            if let compatible = compatibleType(of: available) {
                type = compatible
            } else if available.allSatisfy({ !isClass($0) }) {
                type = .ecore(.eString)
            } else {
                type = .eObject
            }
        }
        if case .generated = type, index(type) == nil {
            if reported.insert("missing\u{0}\(type.displayName)").inserted {
                collector.warning(
                    dialect.code(.externalType),
                    "The type '\(type.displayName)' of '\(owner.name).\(feature.name)' is not defined here; '\(EcoreClassifier.eObject.rawValue)' stands in for it",
                    at: feature.range)
            }
            type = .eObject
        }
        let isReference = isClass(type)
        let reference: GrammarDraftTypeReference
        switch type {
        case .generated(let package, let name): reference = .named(name, package: package)
        case .ecore(let dataType): reference = .ecore(dataType)
        case .eObject, .externalClass, .excluded: reference = .eObject
        case .externalData: reference = .ecore(.eString)
        }
        let containment = isReference && feature.isContainment
        return GrammarDraftFeature(
            name: feature.name, type: reference, lowerBound: feature.isRequired ? 1 : 0,
            upperBound: feature.isMany ? -1 : 1, isContainment: containment,
            isUnique: !feature.isMany || (containment && isReference),
            defaultValueLiteral: feature.defaultValueLiteral, range: feature.range)
    }
}

extension TypeKey {
    /// Whether the key can denote a data type.
    var isDataLike: Bool {
        switch self {
        case .ecore, .externalData, .generated: true
        case .eObject, .externalClass, .excluded: false
        }
    }
}
