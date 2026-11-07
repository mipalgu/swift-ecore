//
// SDF3Mapper.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// Turns the sorts, constructors and injections of a module into a draft package.
///
/// The mapping is documented in ``SDF3Reader``.
struct SDF3Mapper {
    /// Whether a sort becomes a class or a data type.
    private enum SortKind {
        /// A context-free sort, which becomes an abstract class.
        case contextFree
        /// A lexical sort, which becomes a data type or a string.
        case lexical
    }

    /// The settings of the import.
    let options: SDF3ImportOptions

    /// The name of the source document, used for the default package name.
    let sourceName: String?

    /// Maps a module to a draft package.
    ///
    /// - Parameters:
    ///   - definition: What the parser read.
    ///   - collector: Receives the problems found while mapping.
    /// - Returns: The draft package.
    func map(_ definition: SDF3Definition, collector: inout DiagnosticCollector) -> GrammarDraftPackage {
        let kinds = sortKinds(definition, collector: &collector)
        var taken = Set(definition.sortOrder.filter { kinds[$0] == .contextFree || options.lexicalSortsAsDataTypes }
            .map(GrammarNaming.identifier))
        var classes: [String: GrammarDraftClass] = [:]
        var buckets: [String: [GrammarDraftClass]] = [:]
        for sort in definition.sortOrder where kinds[sort] == .contextFree {
            classes[sort] = GrammarDraftClass(
                name: GrammarNaming.identifier(sort), isAbstract: true, range: definition.sortRanges[sort])
        }
        var seen: [String: [(sort: String, arity: Int)]] = [:]
        for constructor in definition.constructors {
            if seen[constructor.name]?.contains(where: { $0.sort == constructor.sort && $0.arity == constructor.arguments.count }) == true {
                continue
            }
            seen[constructor.name, default: []].append((constructor.sort, constructor.arguments.count))
            let base = GrammarNaming.identifier(constructor.name)
            var name = base
            if taken.contains(name) {
                name = unique(base + GrammarNaming.identifier(constructor.sort), taken: taken)
                collector.warning(
                    SDF3DiagnosticCode.constructorRenamed.rawValue,
                    "The constructor '\(constructor.name)' of '\(constructor.sort)' clashes with another classifier and is named '\(name)'",
                    at: constructor.nameRange)
            }
            taken.insert(name)
            let names = GrammarNaming.fieldNames(constructor.arguments.map { argument in
                (argument.type.nameForGeneratedFeature,
                 options.useLabels ? argument.label.map(GrammarNaming.identifier) : nil)
            })
            let features = zip(constructor.arguments, names).map { argument, featureName in
                feature(featureName, argument.type, kinds: kinds, range: argument.range, collector: &collector)
            }
            buckets[constructor.sort, default: []].append(GrammarDraftClass(
                name: name, superTypes: [.named(GrammarNaming.identifier(constructor.sort))], features: features,
                range: constructor.range))
        }
        var wrappers: Set<String> = []
        for injection in definition.injections {
            guard kinds[injection.target] == .contextFree else { continue }
            let target = GrammarNaming.identifier(injection.target)
            switch injection.source {
            case .sort(let source) where kinds[source] == .contextFree:
                guard source != injection.target, var sub = classes[source] else { continue }
                if !sub.superTypes.contains(.named(target)) { sub.superTypes.append(.named(target)) }
                classes[source] = sub
            case .sort(let source), .builtin(let source):
                let wrapped = GrammarNaming.upperFirst(GrammarNaming.identifier(source))
                guard wrappers.insert(injection.target + "\u{0}" + wrapped).inserted else { continue }
                let name = unique(target + wrapped, taken: taken)
                taken.insert(name)
                collector.information(
                    SDF3DiagnosticCode.lexicalInjection.rawValue,
                    "The injection of '\(source)' into '\(injection.target)' is represented by the class '\(name)'",
                    at: injection.range)
                let value = feature(
                    SDF3Language.wrapperFeatureName, injection.source, kinds: kinds, range: injection.range,
                    collector: &collector)
                buckets[injection.target, default: []].append(GrammarDraftClass(
                    name: name, superTypes: [.named(target)], features: [value], range: injection.range))
            default:
                collector.warning(
                    SDF3DiagnosticCode.unsupportedSymbol.rawValue,
                    "The injection into '\(injection.target)' cannot be represented", at: injection.range)
            }
        }
        var classifiers: [GrammarDraftClassifier] = []
        for sort in definition.sortOrder where kinds[sort] == .contextFree {
            if let sortClass = classes[sort] { classifiers.append(.eClass(sortClass)) }
            classifiers += (buckets[sort] ?? []).map(GrammarDraftClassifier.eClass)
        }
        if options.lexicalSortsAsDataTypes {
            for sort in definition.sortOrder where kinds[sort] == .lexical {
                classifiers.append(.dataType(GrammarDraftDataType(
                    name: GrammarNaming.identifier(sort), instanceClassName: SDF3Language.lexicalInstanceClassName,
                    range: definition.sortRanges[sort])))
            }
        }
        let declared = definition.moduleName?.split(separator: "/").last.map(String.init)
        let packageName = GrammarNaming.packageName(
            declared: declared, option: options.packageName, sourceName: sourceName)
        return GrammarDraftPackage(
            name: packageName,
            nsURI: options.nsURI ?? GrammarNaming.defaultNsURI(notation: SDF3Language.notation, packageName: packageName),
            nsPrefix: options.nsPrefix ?? GrammarNaming.defaultNsPrefix(packageName: packageName),
            classifiers: classifiers)
    }

    /// Decides for every sort whether it is context-free or lexical.
    ///
    /// Context-free evidence wins over lexical evidence; a plain declaration
    /// makes a sort context-free; a sort that is only used is undefined and
    /// is guessed from its spelling.
    ///
    /// - Parameters:
    ///   - definition: What the parser read.
    ///   - collector: Receives warnings about conflicting and undefined sorts.
    /// - Returns: The kind of every sort.
    private func sortKinds(_ definition: SDF3Definition, collector: inout DiagnosticCollector) -> [String: SortKind] {
        var kinds: [String: SortKind] = [:]
        for sort in definition.sortOrder {
            let evidence = definition.evidence[sort] ?? []
            let range = definition.sortRanges[sort]
            if !evidence.isDisjoint(with: .contextFree) {
                if !evidence.isDisjoint(with: [.lexicalDeclaration, .lexicalProduction]) {
                    collector.warning(
                        SDF3DiagnosticCode.sortKindConflict.rawValue,
                        "The sort '\(sort)' is defined both lexically and context-free; it is treated as context-free",
                        at: range)
                }
                kinds[sort] = .contextFree
            } else if !evidence.isDisjoint(with: .lexical) {
                kinds[sort] = .lexical
            } else if evidence.contains(.plainDeclaration) {
                kinds[sort] = .contextFree
            } else {
                let guess: SortKind = SDF3Language.isConventionallyLexical(sort) ? .lexical : .contextFree
                collector.warning(
                    SDF3DiagnosticCode.undefinedSort.rawValue,
                    "The sort '\(sort)' is not defined in this module; it is assumed to be "
                        + (guess == .lexical ? "lexical" : "context-free"),
                    at: range)
                kinds[sort] = guess
            }
        }
        return kinds
    }

    /// Builds the feature of an argument.
    ///
    /// - Parameters:
    ///   - name: The feature name.
    ///   - type: The argument type.
    ///   - kinds: The kind of every sort.
    ///   - range: The source text of the argument.
    ///   - collector: Receives a warning for a type that has no representation.
    /// - Returns: The feature.
    private func feature(
        _ name: String, _ type: SDF3Type, kinds: [String: SortKind], range: SourceRange,
        collector: inout DiagnosticCollector
    ) -> GrammarDraftFeature {
        let reference: GrammarDraftTypeReference
        var isClass = true
        switch type.element {
        case .sort(let sort) where kinds[sort] == .contextFree:
            reference = .named(GrammarNaming.identifier(sort))
        case .sort(let sort):
            reference = options.lexicalSortsAsDataTypes ? .named(GrammarNaming.identifier(sort)) : .ecore(.eString)
            isClass = false
        case .builtin(let builtin):
            reference = .ecore(SDF3Language.builtinTypes[builtin] ?? .eString)
            isClass = false
        case .variable:
            reference = .eObject
        default:
            collector.warning(
                SDF3DiagnosticCode.unsupportedSymbol.rawValue,
                "The argument type cannot be represented exactly and is typed as EObject", at: range)
            reference = .eObject
        }
        let bounds = type.bounds
        let isMany = bounds.upper == -1
        return GrammarDraftFeature(
            name: name, type: reference, lowerBound: bounds.lower, upperBound: bounds.upper, isContainment: isClass,
            isUnique: !(isMany && !isClass), range: range)
    }

    /// A name that differs from every taken name, made by appending a number if needed.
    ///
    /// - Parameters:
    ///   - candidate: The preferred name.
    ///   - taken: The names already in use.
    /// - Returns: The candidate, or the candidate followed by the smallest number that is free.
    private func unique(_ candidate: String, taken: Set<String>) -> String {
        guard taken.contains(candidate) else { return candidate }
        var counter = 2
        while taken.contains(candidate + String(counter)) { counter += 1 }
        return candidate + String(counter)
    }
}
