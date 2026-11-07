//
// GrammarMetamodelAssembler.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import OrderedCollections

/// The kinds of problem that assembling a metamodel from drafts can find.
///
/// The raw value is the last segment of a diagnostic code; the full code is
/// prefixed with the notation, for example `asdl.duplicateClassifier`.
enum AssemblyProblem: String, Sendable, CaseIterable {
    /// Two classifiers of a package have the same name; the later one is dropped.
    case duplicateClassifier
    /// A class declares two features with the same name; the later one is dropped.
    case duplicateFeature
    /// A type name resolves to no classifier.
    case unresolvedType
    /// A supertype is not a class, or would make inheritance circular; it is dropped.
    case invalidSupertype
}

/// Builds native Ecore packages from drafts.
///
/// The assembler gives every classifier an identifier, builds features and
/// supertypes that name their targets by identifier, and finally lets
/// ``MetamodelLinker`` replace every placeholder with a snapshot of the
/// canonical class, as the JSON metamodel reader does for documents. It
/// reports problems instead of failing, so that a partly valid source still
/// yields a metamodel.
struct GrammarMetamodelAssembler {
    /// The prefix of the diagnostic codes, such as `asdl`.
    let codePrefix: String

    /// The identifier of the document the drafts were read from.
    let document: String?

    /// Creates an assembler.
    ///
    /// - Parameters:
    ///   - codePrefix: The prefix of the diagnostic codes.
    ///   - document: The identifier of the document the drafts were read from.
    init(codePrefix: String, document: String?) {
        self.codePrefix = codePrefix
        self.document = document
    }

    /// The diagnostic code of a problem.
    ///
    /// - Parameter problem: The kind of problem.
    /// - Returns: The code, prefixed with the notation.
    func code(_ problem: AssemblyProblem) -> String { codePrefix + "." + problem.rawValue }

    /// The identifiers of the classifiers, by package name and classifier name.
    private typealias Identifiers = [String: [String: EUUID]]

    /// Builds packages from drafts.
    ///
    /// - Parameter drafts: The packages to build, which may refer to each other's classifiers.
    /// - Returns: The linked packages, in the order of the drafts, and the problems found.
    func assemble(_ drafts: [GrammarDraftPackage]) -> (packages: [EPackage], diagnostics: [SourceDiagnostic]) {
        var collector = DiagnosticCollector(document: document)
        var drafts = drafts
        for index in drafts.indices { removeDuplicates(in: &drafts[index], collector: &collector) }
        var identifiers: Identifiers = [:]
        for draft in drafts {
            var names: [String: EUUID] = identifiers[draft.name] ?? [:]
            for classifier in draft.classifiers where names[classifier.name] == nil {
                names[classifier.name] = EUUID()
            }
            identifiers[draft.name] = names
        }
        let acyclic = removingCycles(drafts, collector: &collector)
        var builtNonClasses: [EUUID: any EClassifier] = [:]
        for draft in acyclic {
            for classifier in draft.classifiers {
                guard let id = identifiers[draft.name]?[classifier.name] else { continue }
                switch classifier {
                case .dataType(let value): builtNonClasses[id] = dataType(value, id: id)
                case .eEnum(let value): builtNonClasses[id] = enumeration(value, id: id)
                case .eClass: break
                }
            }
        }
        let context = Context(drafts: acyclic, identifiers: identifiers, nonClasses: builtNonClasses)
        var packages: [EPackage] = []
        for draft in acyclic {
            var classifiers: [any EClassifier] = []
            for classifier in draft.classifiers {
                guard let id = identifiers[draft.name]?[classifier.name] else { continue }
                switch classifier {
                case .eClass(let value):
                    classifiers.append(eClass(value, id: id, in: draft, context: context, collector: &collector))
                default:
                    if let built = builtNonClasses[id] { classifiers.append(built) }
                }
            }
            packages.append(EPackage(
                name: draft.name, nsURI: draft.nsURI, nsPrefix: draft.nsPrefix, eClassifiers: classifiers,
                eAnnotations: annotations(draft.annotations)))
        }
        return (MetamodelLinker.relinked(packages), collector.diagnostics)
    }

    // MARK: Checks

    /// Drops classifiers and features whose names repeat earlier ones.
    ///
    /// - Parameters:
    ///   - draft: The package to check.
    ///   - collector: Receives a diagnostic for every dropped element.
    private func removeDuplicates(in draft: inout GrammarDraftPackage, collector: inout DiagnosticCollector) {
        var seen: Set<String> = []
        var kept: [GrammarDraftClassifier] = []
        for classifier in draft.classifiers {
            guard seen.insert(classifier.name).inserted else {
                collector.error(
                    code(.duplicateClassifier),
                    "The package '\(draft.name)' already has a classifier named '\(classifier.name)'",
                    at: classifier.range)
                continue
            }
            if case .eClass(var value) = classifier {
                var featureNames: Set<String> = []
                value.features = value.features.filter { feature in
                    guard featureNames.insert(feature.name).inserted else {
                        collector.error(
                            code(.duplicateFeature),
                            "The class '\(value.name)' already has a feature named '\(feature.name)'",
                            at: feature.range ?? value.range)
                        return false
                    }
                    return true
                }
                kept.append(.eClass(value))
            } else {
                kept.append(classifier)
            }
        }
        draft.classifiers = kept
    }

    /// Drops supertypes that are not classes or that would close an inheritance cycle.
    ///
    /// - Parameters:
    ///   - drafts: The packages to check.
    ///   - collector: Receives a diagnostic for every dropped supertype.
    /// - Returns: The packages without the offending supertypes.
    private func removingCycles(_ drafts: [GrammarDraftPackage], collector: inout DiagnosticCollector) -> [GrammarDraftPackage] {
        var result = drafts
        /// A key that identifies a classifier across packages.
        let keyOf: (String, String) -> String = { $0 + "\u{0}" + $1 }
        /// The package name and draft of the classifier a supertype reference names.
        ///
        /// - Parameters:
        ///   - reference: The supertype reference.
        ///   - package: The package of the class that names it.
        /// - Returns: The package name and classifier, or `nil` if none matches.
        func target(_ reference: GrammarDraftTypeReference, from package: String) -> (String, GrammarDraftClassifier)? {
            guard case .named(let name, let explicit) = reference else { return nil }
            let candidates = explicit.map { [$0] } ?? [package] + drafts.map(\.name).filter { $0 != package }
            for candidate in candidates {
                if let found = result.first(where: { $0.name == candidate })?.classifier(named: name) {
                    return (candidate, found)
                }
            }
            return nil
        }
        for packageIndex in result.indices {
            for classifierIndex in result[packageIndex].classifiers.indices {
                guard case .eClass(var value) = result[packageIndex].classifiers[classifierIndex] else { continue }
                let packageName = result[packageIndex].name
                var kept: [GrammarDraftTypeReference] = []
                for superType in value.superTypes {
                    if superType == .eObject { kept.append(superType); continue }
                    guard let (superPackage, classifier) = target(superType, from: packageName) else {
                        collector.error(
                            code(.unresolvedType),
                            "The supertype '\(superType.displayName)' of '\(value.name)' does not exist",
                            at: value.range)
                        continue
                    }
                    guard classifier.isClass else {
                        collector.error(
                            code(.invalidSupertype),
                            "The supertype '\(superType.displayName)' of '\(value.name)' is not a class",
                            at: value.range)
                        continue
                    }
                    // Does the supertype (transitively) inherit from this class already?
                    var visited: Set<String> = []
                    var stack = [(superPackage, classifier.name)]
                    var closesCycle = false
                    while let (pkg, name) = stack.popLast() {
                        if pkg == packageName && name == value.name { closesCycle = true; break }
                        guard visited.insert(keyOf(pkg, name)).inserted,
                            case .eClass(let current)? = result.first(where: { $0.name == pkg })?.classifier(named: name)
                        else { continue }
                        for next in current.superTypes {
                            if let (nextPackage, nextClassifier) = target(next, from: pkg) {
                                stack.append((nextPackage, nextClassifier.name))
                            }
                        }
                    }
                    if closesCycle {
                        collector.error(
                            code(.invalidSupertype),
                            "Inheriting from '\(superType.displayName)' would make '\(value.name)' its own supertype",
                            at: value.range)
                        continue
                    }
                    if !kept.contains(superType) { kept.append(superType) }
                }
                value.superTypes = kept
                result[packageIndex].classifiers[classifierIndex] = .eClass(value)
            }
        }
        return result
    }

    // MARK: Building

    /// What building a class needs to know about the other classifiers.
    private struct Context {
        /// The packages being built.
        let drafts: [GrammarDraftPackage]
        /// The identifiers of the classifiers.
        let identifiers: Identifiers
        /// The data types and enumerations, already built.
        let nonClasses: [EUUID: any EClassifier]

        /// The identifier and draft of the classifier a reference names.
        ///
        /// - Parameters:
        ///   - name: The classifier name.
        ///   - explicit: The package that the reference names, if any.
        ///   - package: The package of the referring element.
        /// - Returns: The identifier and draft, or `nil` if none matches.
        func lookup(_ name: String, explicit: String?, from package: String) -> (EUUID, GrammarDraftClassifier)? {
            let candidates = explicit.map { [$0] } ?? [package] + drafts.map(\.name).filter { $0 != package }
            for candidate in candidates {
                if let draft = drafts.first(where: { $0.name == candidate }),
                    let classifier = draft.classifier(named: name), let id = identifiers[candidate]?[name]
                {
                    return (id, classifier)
                }
            }
            return nil
        }
    }

    /// Builds a class with placeholders for the classes it names.
    ///
    /// - Parameters:
    ///   - draft: The class to build.
    ///   - id: The identifier of the class.
    ///   - package: The package that contains it.
    ///   - context: The other classifiers.
    ///   - collector: Receives a diagnostic for every type that cannot be resolved.
    /// - Returns: The class, whose supertypes and reference types are placeholders until linked.
    private func eClass(
        _ draft: GrammarDraftClass, id: EUUID, in package: GrammarDraftPackage, context: Context,
        collector: inout DiagnosticCollector
    ) -> EClass {
        var superTypes: [EClass] = []
        for reference in draft.superTypes {
            switch reference {
            case .eObject: superTypes.append(EcorePackage.metaClass(.eObject))
            case .named(let name, let explicit):
                if let (target, _) = context.lookup(name, explicit: explicit, from: package.name) {
                    superTypes.append(EClass(id: target, name: name))
                }
            case .ecore: break
            }
        }
        var features: [any EStructuralFeature] = []
        for feature in draft.features {
            let type = resolve(feature, owner: draft, in: package, context: context, collector: &collector)
            let annotations = annotations(feature.annotations)
            if let eClass = type as? EClass {
                features.append(EReference(
                    name: feature.name, eType: eClass, lowerBound: feature.lowerBound,
                    upperBound: feature.upperBound, containment: feature.isContainment,
                    resolveProxies: !feature.isContainment, eAnnotations: annotations,
                    ordered: feature.isOrdered, unique: feature.isUnique))
            } else {
                features.append(EAttribute(
                    name: feature.name, eType: type, lowerBound: feature.lowerBound,
                    upperBound: feature.upperBound, defaultValueLiteral: feature.defaultValueLiteral,
                    eAnnotations: annotations, ordered: feature.isOrdered, unique: feature.isUnique))
            }
        }
        return EClass(
            id: id, name: draft.name, isAbstract: draft.isAbstract || draft.isInterface,
            isInterface: draft.isInterface, eSuperTypes: superTypes, eStructuralFeatures: features,
            eAnnotations: annotations(draft.annotations))
    }

    /// The classifier that types a feature, or a string type if it cannot be resolved.
    ///
    /// - Parameters:
    ///   - feature: The feature.
    ///   - owner: The class that declares it.
    ///   - package: The package that contains the class.
    ///   - context: The other classifiers.
    ///   - collector: Receives a diagnostic if the type cannot be resolved.
    /// - Returns: A placeholder for a class, the built data type or enumeration, or `EString`.
    private func resolve(
        _ feature: GrammarDraftFeature, owner: GrammarDraftClass, in package: GrammarDraftPackage, context: Context,
        collector: inout DiagnosticCollector
    ) -> any EClassifier {
        let fallback: any EClassifier = EcorePackage.dataType(.eString) ?? EDataType(name: EcoreDataType.eString.rawValue)
        switch feature.type {
        case .ecore(let type):
            return EcorePackage.dataType(type) ?? fallback
        case .eObject:
            return EcorePackage.metaClass(.eObject)
        case .named(let name, let explicit):
            guard let (id, classifier) = context.lookup(name, explicit: explicit, from: package.name) else {
                collector.error(
                    code(.unresolvedType),
                    "The type '\(feature.type.displayName)' of '\(owner.name).\(feature.name)' does not exist",
                    at: feature.range ?? owner.range)
                return fallback
            }
            if classifier.isClass { return EClass(id: id, name: name) }
            return context.nonClasses[id] ?? fallback
        }
    }

    /// Builds a data type.
    ///
    /// - Parameters:
    ///   - draft: The data type to build.
    ///   - id: The identifier of the data type.
    /// - Returns: The data type.
    private func dataType(_ draft: GrammarDraftDataType, id: EUUID) -> EDataType {
        EDataType(
            id: id, name: draft.name, instanceClassName: draft.instanceClassName,
            eAnnotations: annotations(draft.annotations))
    }

    /// Builds an enumeration whose literal values are their positions.
    ///
    /// - Parameters:
    ///   - draft: The enumeration to build.
    ///   - id: The identifier of the enumeration.
    /// - Returns: The enumeration.
    private func enumeration(_ draft: GrammarDraftEnum, id: EUUID) -> EEnum {
        EEnum(
            id: id, name: draft.name,
            literals: draft.literals.enumerated().map { index, literal in
                EEnumLiteral(name: literal.name, value: index, literal: literal.literal)
            },
            eAnnotations: annotations(draft.annotations))
    }

    /// Builds annotations.
    ///
    /// - Parameter drafts: The annotations to build.
    /// - Returns: The annotations, with their details in order.
    private func annotations(_ drafts: [GrammarDraftAnnotation]) -> [EAnnotation] {
        drafts.map { draft in
            var details: OrderedDictionary<String, String> = [:]
            for detail in draft.details { details[detail.key] = detail.value }
            return EAnnotation(source: draft.source, orderedDetails: details)
        }
    }
}
