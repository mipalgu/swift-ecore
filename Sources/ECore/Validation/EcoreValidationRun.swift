//
// EcoreValidationRun.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// The state of one validation: the index to resolve against, the settings, and the findings.
///
/// A run is created for each call of the validator and never shared, so the caches that it
/// keeps can never be stale.
final class EcoreValidationRun {
    /// The index that every reference is resolved through.
    let index: MetamodelIndex

    /// The settings of the validator.
    let options: EcoreValidator.Options

    /// The diagnostics found so far.
    private(set) var diagnostics: [EcoreDiagnostic] = []

    /// The position of each constraint in declaration order.
    private static let rank: [EcoreConstraint: Int] = Dictionary(
        uniqueKeysWithValues: EcoreConstraint.allCases.enumerated().map { ($1, $0) })

    private var superTypeCache: [EUUID: [EClass]] = [:]
    private var featureCache: [EUUID: [any EStructuralFeature]] = [:]
    private var namespaceGroups: [String: [EUUID]]?

    /// Starts a run.
    ///
    /// - Parameters:
    ///   - index: The index to resolve references through.
    ///   - options: The settings of the validator.
    init(index: MetamodelIndex, options: EcoreValidator.Options) {
        self.index = index
        self.options = options
    }

    // MARK: Reporting

    /// Whether a constraint is checked.
    func isEnabled(_ constraint: EcoreConstraint) -> Bool {
        !options.disabledConstraints.contains(constraint)
    }

    /// Records a diagnostic, unless its constraint is disabled.
    func report(
        _ code: EcoreConstraint, _ template: EcoreValidationMessage,
        severity: DiagnosticSeverity = .error, element: EUUID, feature: EcoreFeatureName? = nil,
        arguments: [String] = [], related: [EUUID] = []
    ) {
        guard isEnabled(code) else { return }
        diagnostics.append(
            EcoreDiagnostic(
                severity: severity, code: code, template: template, element: element,
                feature: feature, arguments: arguments, related: related))
    }

    /// Checks one element and orders what it finds by constraint.
    ///
    /// - Parameter element: The element to check.
    func check(_ element: EcoreElement) {
        let start = diagnostics.count
        switch element {
        case .package(let value): checkPackage(value)
        case .eClass(let value): checkClass(value)
        case .dataType(let value): checkDataType(value)
        case .eEnum(let value): checkEnum(value)
        case .literal(let value): checkName(of: value.id, value.name)
        case .attribute(let value): checkAttribute(value)
        case .reference(let value): checkReference(value)
        case .operation(let value): checkOperation(value)
        case .parameter(let value): checkParameter(value)
        case .annotation(let value): checkAnnotation(value)
        case .detail: break
        }
        guard diagnostics.count - start > 1 else { return }
        let ordered = diagnostics[start...].enumerated().sorted {
            let (left, right) = (Self.rank[$0.element.code] ?? 0, Self.rank[$1.element.code] ?? 0)
            return left != right ? left < right : $0.offset < $1.offset
        }
        diagnostics.replaceSubrange(start..., with: ordered.map(\.element))
    }

    // MARK: Resolution

    /// The element of the index that a classifier snapshot denotes.
    ///
    /// - Parameter type: A classifier, possibly a stale snapshot.
    /// - Returns: The canonical classifier, or the snapshot itself if the index does not
    ///   know it (a built-in or foreign classifier).
    func canonical(_ type: any EClassifier) -> any EClassifier {
        switch index.element(type.id) {
        case .eClass(let value)?: return value
        case .dataType(let value)?: return value
        case .eEnum(let value)?: return value
        default: return type
        }
    }

    /// The canonical class that a class snapshot denotes.
    func canonical(_ eClass: EClass) -> EClass {
        if case .eClass(let value)? = index.element(eClass.id) { return value }
        return eClass
    }

    /// The class that contains a feature or operation.
    func containingClass(of identifier: EUUID) -> EClass? {
        guard let container = index.container(of: identifier)?.container,
            case .eClass(let value)? = index.element(container)
        else { return nil }
        return value
    }

    /// The supertypes of a class, nearest-first within each branch, without repeats and
    /// without the class itself, whether or not the hierarchy is circular.
    func allSuperTypes(of eClass: EClass) -> [EClass] {
        if let cached = superTypeCache[eClass.id] { return cached }
        var seen: Set<EUUID> = [eClass.id]
        var result: [EClass] = []
        func visit(_ current: EClass) {
            for snapshot in current.eSuperTypes {
                let next = canonical(snapshot)
                guard seen.insert(next.id).inserted else { continue }
                visit(next)
                result.append(next)
            }
        }
        visit(eClass)
        superTypeCache[eClass.id] = result
        return result
    }

    /// The features of a class and of its supertypes: inherited ones first.
    func allFeatures(of eClass: EClass) -> [any EStructuralFeature] {
        if let cached = featureCache[eClass.id] { return cached }
        var seen: Set<EUUID> = []
        var result: [any EStructuralFeature] = []
        for owner in allSuperTypes(of: eClass) + [eClass] {
            for feature in owner.eStructuralFeatures where seen.insert(feature.id).inserted {
                result.append(feature)
            }
        }
        featureCache[eClass.id] = result
        return result
    }

    /// The name of a classifier snapshot, as a message argument.
    func typeName(_ type: (any EClassifier)?) -> String? {
        type.map { canonical($0).name }
    }

    // MARK: Shared checks

    /// Checks that a name is well formed.
    func checkName(of identifier: EUUID, _ name: String) {
        guard options.strictNames, isEnabled(.wellFormedName),
            !EcoreValidationSyntax.isWellFormedIdentifier(name)
        else { return }
        report(
            .wellFormedName, .nameNotWellFormed, element: identifier, feature: .name,
            arguments: [name])
    }

    /// Checks the multiplicity of a typed element.
    func checkBounds(of identifier: EUUID, lower: Int, upper: Int) {
        if lower < 0 {
            report(
                .validLowerBound, .lowerBoundNegative, element: identifier, feature: .lowerBound,
                arguments: [EcoreValidationMessages.argument(forBound: lower)])
        }
        if !(upper > 0 || upper == EcoreValidationSyntax.unbounded
            || upper == EcoreValidationSyntax.unspecified)
        {
            report(
                .validUpperBound, .upperBoundInvalid, element: identifier, feature: .upperBound,
                arguments: [EcoreValidationMessages.argument(forBound: upper)])
        }
        if upper >= 0 && lower > upper {
            report(
                .consistentBounds, .boundsInconsistent, element: identifier, feature: .lowerBound,
                arguments: [
                    EcoreValidationMessages.argument(forBound: lower),
                    EcoreValidationMessages.argument(forBound: upper),
                ])
        }
    }

    /// Checks that a classifier's instance class name is well formed.
    func checkInstanceClassName(of identifier: EUUID, _ name: String?) {
        guard let name, !EcoreValidationSyntax.isWellFormedInstanceClassName(name) else { return }
        report(
            .wellFormedInstanceTypeName, .instanceTypeNameNotWellFormed, element: identifier,
            feature: .instanceClassName, arguments: [name])
    }

    /// Checks a data type.
    private func checkDataType(_ value: EDataType) {
        checkName(of: value.id, value.name)
        checkInstanceClassName(of: value.id, value.instanceClassName)
    }

    /// Checks an annotation.
    private func checkAnnotation(_ value: EAnnotation) {
        guard isEnabled(.wellFormedSourceURI),
            !EcoreValidationSyntax.isWellFormedURI(value.source)
        else { return }
        report(
            .wellFormedSourceURI, .sourceURINotWellFormed, element: value.id, feature: .source,
            arguments: [value.source])
    }

    /// Reports the groups of items whose names clash.
    ///
    /// - Parameters:
    ///   - container: The element that holds the items.
    ///   - feature: The containment feature that holds the items.
    ///   - items: The identifiers and names of the items, in order.
    ///   - code: The constraint to report under.
    ///   - duplicate: The message for items with the same name.
    ///   - similar: The message for items whose names differ only by case or underscores.
    ///   - isExcused: Whether a group of item identifiers is already reported elsewhere.
    func reportNameClashes(
        in container: EUUID, feature: EcoreFeatureName, items: [(id: EUUID, name: String)],
        code: EcoreConstraint, duplicate: EcoreValidationMessage, similar: EcoreValidationMessage,
        isExcused: ([EUUID]) -> Bool = { _ in false }
    ) {
        guard isEnabled(code), items.count > 1 else { return }
        var order: [String] = []
        var groups: [String: [(id: EUUID, name: String)]] = [:]
        for item in items {
            let key = EcoreValidationSyntax.similarityKey(item.name)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        for key in order {
            guard let group = groups[key], group.count > 1 else { continue }
            let ids = group.map(\.id)
            if isExcused(ids) { continue }
            let names = group.map(\.name)
            if Set(names).count == names.count {
                report(
                    code, similar, severity: .warning, element: container, feature: feature,
                    arguments: EcoreValidationMessages.arguments(forNames: names), related: ids)
            } else {
                report(
                    code, duplicate, element: container, feature: feature, arguments: [names[0]],
                    related: ids)
            }
        }
    }

    // MARK: Namespaces

    /// The packages that have a namespace URI in common with a package.
    func packagesSharingNamespace(with package: EPackage) -> [EUUID] {
        if namespaceGroups == nil {
            var groups: [String: [EUUID]] = [:]
            for element in index.allElements {
                if case .package(let value) = element, !value.nsURI.isEmpty {
                    groups[value.nsURI, default: []].append(value.id)
                }
            }
            namespaceGroups = groups
        }
        return namespaceGroups?[package.nsURI] ?? []
    }
}
