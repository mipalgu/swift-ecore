//
// MetamodelEditor.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import OrderedCollections

/// Applies edits to the roots of a document and keeps the record of what changed.
///
/// An editor works on a copy of the roots. Every edit is validated against the index, then
/// applied to the roots by replacing the elements along the containment path, and the index
/// is rebuilt before the next edit needs it. Once all edits have been applied, ``finish(label:)``
/// refreshes the class snapshots and the index, and summarises the changes.
struct MetamodelEditor {
    /// How much of the index is out of date.
    private enum Staleness: Int, Comparable {
        case fresh, values, structure
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The root packages, including every edit applied so far.
    private(set) var roots: [EPackage]

    /// The index over the roots.
    private(set) var index: MetamodelIndex

    private let externals: [EPackage]
    private let policy: EditPolicy
    private var staleness = Staleness.fresh
    private var changes: [MetamodelChange] = []
    private var added: Set<EUUID> = []
    private var removed: Set<EUUID> = []
    private var created: [EUUID] = []
    private var structure: Set<EUUID> = []
    private var modified: [EUUID: Set<EcoreFeatureName>] = [:]
    private var diagnostics: [SourceDiagnostic] = []

    /// Starts editing.
    ///
    /// - Parameters:
    ///   - roots: The root packages.
    ///   - index: The index over the roots.
    ///   - policy: What to do about edits that break rules of Ecore.
    init(roots: [EPackage], index: MetamodelIndex, policy: EditPolicy) {
        self.roots = roots
        self.index = index
        self.externals = index.externals
        self.policy = policy
    }

    // MARK: Applying

    /// Applies an edit.
    mutating func apply(_ edit: MetamodelEdit) throws(MetamodelEditError) {
        if case .compound(_, let edits) = edit {
            for nested in edits { try apply(nested) }
            return
        }
        freshen()
        switch edit {
        case .create(let kind, let container, let feature, let position, let name, let identifier):
            try create(kind, in: container, feature: feature, at: position, name: name, identifier: identifier)
        case .delete(let ids): try delete(ids)
        case .move(let ids, let container, let feature, let position):
            try move(ids, to: container, feature: feature, at: position)
        case .set(let identifier, let feature, let value): try set(identifier, feature, value)
        case .setOpposite(let identifier, let partner): try setOpposite(identifier, partner)
        case .setDetail(let annotation, let key, let value, let position):
            try setDetail(annotation: annotation, key: key, value: value, at: position)
        case .renameDetailKey(let annotation, let old, let new):
            try renameDetailKey(annotation: annotation, from: old, to: new)
        case .paste(let clipboard, let container, let feature, let position):
            try paste(clipboard, into: container, feature: feature, at: position)
        case .compound: break
        }
    }

    /// Refreshes the class snapshots and the index, and summarises the changes.
    ///
    /// - Parameter label: What the edits did.
    /// - Returns: The change set; empty if nothing changed.
    mutating func finish(label: String) -> MetamodelChangeSet {
        guard !changes.isEmpty else { return MetamodelChangeSet(label: label) }
        roots = MetamodelLinker.relinked(roots, externals: externals)
        index = MetamodelIndex(roots: roots, externals: externals)
        staleness = .fresh
        for identifier in removed.union(added) { modified[identifier] = nil }
        structure.subtract(removed)
        structure.subtract(added)
        let affected = LabelImpact.affected(
            modified: modified, structure: structure, added: added, index: index)
        return MetamodelChangeSet(
            label: label, changes: changes, added: added, removed: removed, modified: modified,
            structureChanged: structure, labelsAffected: affected.subtracting(removed),
            createdIDs: created, diagnostics: diagnostics)
    }

    // MARK: Navigation

    /// Rebuilds the index if edits have made it stale.
    private mutating func freshen() {
        guard staleness != .fresh else { return }
        index = MetamodelIndex(roots: roots, externals: externals)
        staleness = .fresh
    }

    /// The editable element with an identifier.
    private func existing(_ identifier: EUUID) throws(MetamodelEditError) -> EcoreElement {
        guard let element = index.element(identifier) else { throw .unknownElement(identifier) }
        guard !index.isExternal(identifier) else { throw .externalElement(identifier) }
        return element
    }

    /// The root position and containment steps that lead to an element.
    private func path(of identifier: EUUID) -> (root: Int, steps: [EcoreContainment])? {
        var steps: [EcoreContainment] = []
        var current = identifier
        while let place = index.container(of: current) {
            steps.append(place)
            current = place.container
        }
        guard let root = roots.firstIndex(where: { $0.id == current }) else { return nil }
        return (root, steps.reversed())
    }

    /// The current version of an element, including the edits applied so far.
    private func fetch(_ identifier: EUUID) -> EcoreElement? {
        guard let (root, steps) = path(of: identifier) else { return nil }
        var current = EcoreElement.package(roots[root])
        for step in steps {
            let children = ElementTree.children(of: current, feature: step.feature)
            guard step.index < children.count else { return nil }
            current = children[step.index]
        }
        return current
    }

    /// Replaces an element, keeping its place.
    private mutating func store(_ element: EcoreElement, _ identifier: EUUID) {
        guard let (root, steps) = path(of: identifier) else { return }
        if steps.isEmpty {
            if case .package(let package) = element { roots[root] = package }
            return
        }
        guard case .package(let package)? = Self.replace(in: .package(roots[root]), steps: steps[...], with: element)
        else { return }
        roots[root] = package
    }

    private static func replace(in element: EcoreElement, steps: ArraySlice<EcoreContainment>, with new: EcoreElement)
        -> EcoreElement?
    {
        guard let step = steps.first else { return new }
        var children = ElementTree.children(of: element, feature: step.feature)
        guard step.index < children.count,
            let updated = replace(in: children[step.index], steps: steps.dropFirst(), with: new)
        else { return nil }
        children[step.index] = updated
        return ElementTree.replacing(step.feature, with: children, in: element)
    }

    /// The value of a property of an element, as recorded in change sets.
    private func value(of feature: EcoreFeatureName, in element: EcoreElement) -> EditValue? {
        guard let descriptor = EcorePackage.feature(feature, of: element.kind) else { return nil }
        return EditValue(element.object.eGet(descriptor))
    }

    /// Changes an element in place and records the properties that differ afterwards.
    private mutating func mutate(
        _ identifier: EUUID, _ features: [EcoreFeatureName], _ body: (inout EcoreElement) -> Void
    ) {
        guard var element = fetch(identifier) else { return }
        let before = features.map { value(of: $0, in: element) }
        body(&element)
        let after = features.map { value(of: $0, in: element) }
        guard before != after else { return }
        store(element, identifier)
        staleness = max(staleness, .values)
        for (position, feature) in features.enumerated() where before[position] != after[position] {
            changes.append(
                MetamodelChange(
                    kind: .set, element: identifier, feature: feature, oldValue: before[position],
                    newValue: after[position]))
            modified[identifier, default: []].insert(feature)
        }
    }

    // MARK: Bookkeeping

    /// Every identifier in an element and what it contains.
    private static func subtree(_ element: EcoreElement) -> [EUUID] {
        var result = [element.id]
        for child in element.children { result.append(contentsOf: subtree(child.element)) }
        return result
    }

    private mutating func noteAdded(_ elements: [EcoreElement], in container: EUUID, feature: EcoreFeatureName, at start: Int, created isCreated: Bool) {
        for (offset, element) in elements.enumerated() {
            changes.append(
                MetamodelChange(
                    kind: .add, element: element.id, feature: feature, newValue: .identifier(container),
                    index: start + offset))
            added.formUnion(Self.subtree(element))
            if isCreated { created.append(element.id) }
        }
        structure.insert(container)
    }

    private mutating func noteRemoved(_ identifiers: [EUUID]) {
        for identifier in identifiers where added.remove(identifier) == nil {
            removed.insert(identifier)
        }
        let gone = Set(identifiers)
        created.removeAll { gone.contains($0) }
    }

    // MARK: Insertion and removal

    /// Inserts elements into a feature of a container.
    ///
    /// - Returns: The elements as they are held after the insertion.
    private mutating func insert(
        _ elements: [EcoreElement], into container: EUUID, feature: EcoreFeatureName, at position: Int?
    ) throws(MetamodelEditError) -> (stored: [EcoreElement], start: Int) {
        guard let current = fetch(container) else { throw .unknownElement(container) }
        var children = ElementTree.children(of: current, feature: feature)
        let start = position ?? children.count
        guard (0...children.count).contains(start) else { throw .indexOutOfRange(start, count: children.count) }
        children.insert(contentsOf: elements, at: start)
        guard let updated = ElementTree.replacing(feature, with: children, in: current) else {
            throw .illegalChild(container: container, feature: feature, kind: elements.first?.kind ?? .eObject)
        }
        store(updated, container)
        staleness = .structure
        let stored = ElementTree.children(of: updated, feature: feature)
        return (Array(stored[start..<(start + elements.count)]), start)
    }

    /// Takes elements out of their containers, deepest containers first.
    private mutating func take(_ identifiers: [EUUID]) {
        let doomed = Set(identifiers)
        var byContainer: [EUUID: Set<EcoreFeatureName>] = [:]
        var rootsGone: Set<EUUID> = []
        for identifier in identifiers {
            if let place = index.container(of: identifier) {
                byContainer[place.container, default: []].insert(place.feature)
            } else {
                rootsGone.insert(identifier)
            }
        }
        let ordered = byContainer.keys.sorted {
            let (left, right) = (index.ancestors(of: $0).count, index.ancestors(of: $1).count)
            return left != right ? left > right : $0.uuidString < $1.uuidString
        }
        for container in ordered {
            guard var element = fetch(container) else { continue }
            for feature in byContainer[container] ?? [] {
                let children = ElementTree.children(of: element, feature: feature).filter { !doomed.contains($0.id) }
                if let updated = ElementTree.replacing(feature, with: children, in: element) { element = updated }
            }
            store(element, container)
        }
        roots.removeAll { rootsGone.contains($0.id) }
        staleness = .structure
    }

    // MARK: Create

    private mutating func create(
        _ kind: EcoreClassifier, in container: EUUID, feature: EcoreFeatureName, at position: Int?,
        name: String?, identifier: EUUID?
    ) throws(MetamodelEditError) {
        let parent = try existing(container)
        guard EcoreEditSchema.accepts(container: parent.kind, feature: feature, kind: kind) else {
            throw .illegalChild(container: container, feature: feature, kind: kind)
        }
        let element = try makeElement(kind, name: name, identifier: identifier ?? EUUID(), parent: parent)
        let (stored, start) = try insert([element], into: container, feature: feature, at: position)
        noteAdded(stored, in: container, feature: feature, at: start, created: true)
    }

    private func makeElement(_ kind: EcoreClassifier, name: String?, identifier: EUUID, parent: EcoreElement)
        throws(MetamodelEditError) -> EcoreElement
    {
        let text = name ?? ""
        switch kind {
        case .ePackage: return .package(EPackage(id: identifier, name: text))
        case .eClass: return .eClass(EClass(id: identifier, name: text))
        case .eDataType: return .dataType(EDataType(id: identifier, name: text))
        case .eEnum: return .eEnum(EEnum(id: identifier, name: text))
        case .eEnumLiteral:
            var next = 0
            if case .eEnum(let owner) = parent { next = (owner.literals.map(\.value).max() ?? -1) + 1 }
            return .literal(EEnumLiteral(id: identifier, name: text, value: next))
        case .eAttribute:
            return .attribute(EAttribute(id: identifier, name: text, eType: EcoreBuiltIns.newAttributeType))
        case .eReference:
            return .reference(EReference(id: identifier, name: text, eType: EcoreBuiltIns.replacementReferenceType))
        case .eOperation: return .operation(EOperation(id: identifier, name: text))
        case .eParameter: return .parameter(EParameter(id: identifier, name: text))
        case .eAnnotation: return .annotation(EAnnotation(id: identifier, source: text))
        case .eStringToStringMapEntry:
            guard case .annotation(let annotation) = parent else { throw .illegalChild(container: parent.id, feature: .details, kind: kind) }
            if let name {
                guard annotation.details[name] == nil else { throw .duplicateDetailKey(name) }
                return .detail(EStringToStringMapEntry(key: name, value: ""))
            }
            return .detail(EStringToStringMapEntry(key: Self.freshKey(in: annotation), value: ""))
        default:
            throw .illegalChild(container: parent.id, feature: .eClassifiers, kind: kind)
        }
    }

    private static func freshKey(in annotation: EAnnotation) -> String {
        var key = EcoreEditDefaults.newDetailKey
        var number = 0
        while annotation.details[key] != nil {
            number += 1
            key = EcoreEditDefaults.newDetailKey + String(number)
        }
        return key
    }

    // MARK: Delete

    private mutating func delete(_ ids: [EUUID]) throws(MetamodelEditError) {
        let tops = try topLevel(ids)
        guard !tops.isEmpty else { return }
        var doomedList: [EUUID] = []
        for top in tops { doomedList.append(contentsOf: subtreeIdentifiers(top)) }
        let doomed = Set(doomedList)
        var referrers: [EUUID] = []
        var seen: Set<EUUID> = []
        for identifier in doomedList {
            for usage in index.usages(of: identifier)
            where !doomed.contains(usage.referrer) && seen.insert(usage.referrer).inserted {
                referrers.append(usage.referrer)
            }
        }
        for referrer in referrers { purge(referrer, of: doomed) }
        var places: [(EUUID, EcoreContainment?)] = []
        for top in tops { places.append((top, index.container(of: top))) }
        take(tops)
        for (identifier, place) in places {
            changes.append(
                MetamodelChange(
                    kind: .remove, element: identifier, feature: place?.feature,
                    oldValue: place.map { .identifier($0.container) }, index: place?.index))
            if let place { structure.insert(place.container) }
        }
        noteRemoved(doomedList)
    }

    private func subtreeIdentifiers(_ identifier: EUUID) -> [EUUID] {
        var result = [identifier]
        for child in index.children(of: identifier) { result.append(contentsOf: subtreeIdentifiers(child.id)) }
        return result
    }

    /// The distinct, editable elements of a list that do not lie inside another listed element.
    private func topLevel(_ ids: [EUUID]) throws(MetamodelEditError) -> [EUUID] {
        var unique: [EUUID] = []
        var seen: Set<EUUID> = []
        for identifier in ids {
            _ = try existing(identifier)
            if seen.insert(identifier).inserted { unique.append(identifier) }
        }
        return unique.filter { identifier in !index.ancestors(of: identifier).contains(where: seen.contains) }
    }

    /// Removes every reference that an element holds to the deleted elements.
    private mutating func purge(_ referrer: EUUID, of doomed: Set<EUUID>) {
        guard let element = fetch(referrer) else { return }
        let features: [EcoreFeatureName]
        switch element {
        case .eClass: features = [.eSuperTypes]
        case .attribute: features = [.eType]
        case .reference: features = [.eType, .eOpposite, .container]
        case .operation: features = [.eType, .eExceptions]
        case .parameter: features = [.eType]
        case .annotation: features = [.references]
        default: return
        }
        mutate(referrer, features) { element in
            switch element {
            case .eClass(var value):
                value.eSuperTypes.removeAll { doomed.contains($0.id) }
                element = .eClass(value)
            case .attribute(var value):
                if doomed.contains(value.eType.id) { value.eType = EcoreBuiltIns.replacementAttributeType }
                element = .attribute(value)
            case .reference(var value):
                if doomed.contains(value.eType.id) { value.eType = EcoreBuiltIns.replacementReferenceType }
                if let opposite = value.opposite, doomed.contains(opposite) {
                    value.opposite = nil
                    value.container = false
                }
                element = .reference(value)
            case .operation(var value):
                if let type = value.eType, doomed.contains(type.id) { value.eType = nil }
                value.eExceptions.removeAll { doomed.contains($0.id) }
                element = .operation(value)
            case .parameter(var value):
                if let type = value.eType, doomed.contains(type.id) {
                    value.eType = type is EClass ? EcoreBuiltIns.replacementReferenceType : EcoreBuiltIns.replacementAttributeType
                }
                element = .parameter(value)
            case .annotation(var value):
                value.references.removeAll { reference in
                    if case .local(let target) = reference { return doomed.contains(target) }
                    return false
                }
                element = .annotation(value)
            default: break
            }
        }
    }

    // MARK: Move

    private mutating func move(
        _ ids: [EUUID], to container: EUUID, feature requested: EcoreFeatureName?, at position: Int?
    ) throws(MetamodelEditError) {
        let tops = try topLevel(ids)
        guard !tops.isEmpty else { return }
        let target = try existing(container)
        var kinds: [EcoreClassifier] = []
        var elements: [EcoreElement] = []
        var oldPlaces: [EcoreContainment] = []
        for top in tops {
            guard let place = index.container(of: top) else { throw .cannotMoveRoot(top) }
            if top == container || index.ancestors(of: container).contains(top) { throw .moveIntoDescendant(top) }
            guard let element = fetch(top) else { throw .unknownElement(top) }
            if case .detail = element, place.container != container { throw .cannotMoveDetail(top) }
            kinds.append(element.kind)
            elements.append(element)
            oldPlaces.append(place)
        }
        let feature: EcoreFeatureName
        if let requested {
            guard kinds.allSatisfy({ EcoreEditSchema.accepts(container: target.kind, feature: requested, kind: $0) }) else {
                throw .illegalChild(container: container, feature: requested, kind: kinds[0])
            }
            feature = requested
        } else if let found = EcoreEditSchema.feature(of: target.kind, accepting: kinds) {
            feature = found
        } else {
            throw .illegalChild(container: container, feature: .eClassifiers, kind: kinds[0])
        }
        take(tops)
        freshen()
        let (stored, start) = try insert(elements, into: container, feature: feature, at: position)
        for (offset, element) in stored.enumerated() {
            let old = oldPlaces[offset]
            guard old.container != container || old.feature != feature || old.index != start + offset else { continue }
            changes.append(
                MetamodelChange(
                    kind: .move, element: element.id, feature: feature, oldValue: .identifier(old.container),
                    newValue: .identifier(container), index: start + offset, oldIndex: old.index,
                    oldFeature: old.feature))
            structure.insert(old.container)
            structure.insert(container)
        }
    }

    // MARK: Set

    private mutating func set(_ identifier: EUUID, _ feature: EcoreFeatureName, _ value: (any EcoreValue)?)
        throws(MetamodelEditError)
    {
        let element = try existing(identifier)
        if case .detail(let entry) = element {
            guard let annotation = index.container(of: identifier)?.container else { throw .unknownElement(identifier) }
            switch feature {
            case .key:
                guard let key = value as? String else { throw .invalidValue(feature) }
                return try renameDetailKey(annotation: annotation, from: entry.key, to: key)
            case .value:
                return try setDetail(annotation: annotation, key: entry.key, value: value as? String ?? "", at: nil)
            default: throw .unknownFeature(identifier, feature)
            }
        }
        if feature == .eOpposite {
            guard case .reference = element else { throw .unknownFeature(identifier, feature) }
            if value == nil { return try setOpposite(identifier, nil) }
            guard let partner = value as? EUUID else { throw .invalidValue(feature) }
            return try setOpposite(identifier, partner)
        }
        guard let metaFeature = EcorePackage.feature(feature, of: element.kind) else {
            throw .unknownFeature(identifier, feature)
        }
        let isContainment = (metaFeature as? EReference)?.containment ?? false
        guard !EcoreEditSchema.unsupportedFeatures.contains(feature),
            !EcoreEditSchema.isReadOnly(metaFeature), !isContainment
        else { throw .notSettable(feature) }
        let converted = try convert(value, feature: feature, metaFeature: metaFeature, element: element)
        if feature == .eSuperTypes, case .eClass = element {
            try checkCycle(of: identifier, supertypes: (value as? [EUUID]) ?? [])
        }
        mutate(identifier, [feature]) { element in
            var object = element.object
            object.eSet(metaFeature, converted)
            if let updated = EcoreElement(object) { element = updated }
        }
        if feature == .containment, case .reference(let reference) = element, let partner = reference.opposite,
            let flag = value as? Bool
        {
            mutate(partner, [.container]) { element in
                if case .reference(var other) = element {
                    other.container = flag
                    element = .reference(other)
                }
            }
        }
    }

    /// Converts a value to what the feature stores, resolving identifiers through the index.
    private func convert(
        _ value: (any EcoreValue)?, feature: EcoreFeatureName, metaFeature: any EStructuralFeature,
        element: EcoreElement
    ) throws(MetamodelEditError) -> (any EcoreValue)? {
        if let attribute = metaFeature as? EAttribute {
            guard let value else { return nil }
            let matches: Bool
            switch attribute.eType.name {
            case EcoreDataType.eString.rawValue: matches = value is String
            case EcoreDataType.eBoolean.rawValue: matches = value is Bool
            case EcoreDataType.eInt.rawValue: matches = value is Int
            default: matches = false
            }
            guard matches else { throw .invalidValue(feature) }
            return value
        }
        switch feature {
        case .eType:
            guard let value else {
                switch element {
                case .operation, .parameter: return nil
                default: throw .invalidValue(feature)
                }
            }
            guard let identifier = value as? EUUID else { throw .invalidValue(feature) }
            let classifier = try resolveClassifier(identifier)
            switch element {
            case .attribute: guard !(classifier is EClass) else { throw .invalidValue(feature) }
            case .reference: guard classifier is EClass else { throw .invalidValue(feature) }
            default: break
            }
            return classifier as? any EcoreValue
        case .eSuperTypes:
            guard let identifiers = (value ?? [EUUID]()) as? [EUUID] else { throw .invalidValue(feature) }
            var classes: [EClass] = []
            for identifier in identifiers {
                guard let eClass = try resolveClassifier(identifier) as? EClass else { throw .invalidValue(feature) }
                classes.append(eClass)
            }
            return classes
        case .eExceptions:
            guard let identifiers = (value ?? [EUUID]()) as? [EUUID] else { throw .invalidValue(feature) }
            var classifiers: [any EcoreValue] = []
            for identifier in identifiers {
                if let classifier = try resolveClassifier(identifier) as? any EcoreValue { classifiers.append(classifier) }
            }
            return EcoreValueArray(classifiers)
        case .references:
            guard let identifiers = (value ?? [EUUID]()) as? [EUUID] else { throw .invalidValue(feature) }
            for identifier in identifiers where !index.contains(identifier) && EcoreBuiltIns.classifiers[identifier] == nil {
                throw .unresolvedReference(identifier)
            }
            return EcoreValueArray(identifiers)
        default:
            throw .notSettable(feature)
        }
    }

    /// The classifier that an identifier names: a classifier of the document, of an external
    /// package, or of Ecore itself.
    private func resolveClassifier(_ identifier: EUUID) throws(MetamodelEditError) -> any EClassifier {
        if let element = index.element(identifier) {
            switch element {
            case .eClass(let value): return value
            case .dataType(let value): return value
            case .eEnum(let value): return value
            default: throw .unresolvedReference(identifier)
            }
        }
        guard let builtIn = EcoreBuiltIns.classifiers[identifier] else { throw .unresolvedReference(identifier) }
        return builtIn
    }

    private mutating func checkCycle(of identifier: EUUID, supertypes: [EUUID]) throws(MetamodelEditError) {
        for start in supertypes {
            guard let path = supertypePath(from: start, to: identifier) else { continue }
            let cycle = [identifier] + path
            switch policy.supertypeCycles {
            case .reject: throw .supertypeCycle(cycle)
            case .allowAndDiagnose:
                diagnostics.append(
                    SourceDiagnostic(
                        severity: .warning, code: EcoreEditDefaults.supertypeCycleCode,
                        message: MetamodelEditError.supertypeCycle(cycle).description))
                return
            }
        }
    }

    /// A chain of supertypes that leads from one class to another, if there is one.
    private func supertypePath(from start: EUUID, to goal: EUUID) -> [EUUID]? {
        var visited: Set<EUUID> = []
        func visit(_ current: EUUID) -> [EUUID]? {
            if current == goal { return [current] }
            guard visited.insert(current).inserted, case .eClass(let value)? = index.element(current) else { return nil }
            for parent in value.eSuperTypes {
                if let rest = visit(parent.id) { return [current] + rest }
            }
            return nil
        }
        return visit(start)
    }

    // MARK: Opposites

    private mutating func setOpposite(_ identifier: EUUID, _ partner: EUUID?) throws(MetamodelEditError) {
        guard case .reference(let reference) = try existing(identifier) else { throw .invalidOpposite(identifier) }
        guard let partner else {
            if let old = reference.opposite { clearPartner(old, pointingAt: identifier) }
            mutate(identifier, [.eOpposite, .container]) { element in
                if case .reference(var value) = element {
                    value.opposite = nil
                    value.container = false
                    element = .reference(value)
                }
            }
            return
        }
        guard partner != identifier, case .reference(let other) = try existing(partner) else {
            throw .invalidOpposite(partner)
        }
        if let old = reference.opposite, old != partner { clearPartner(old, pointingAt: identifier) }
        if let old = other.opposite, old != identifier { clearPartner(old, pointingAt: partner) }
        pair(identifier, with: partner, partnerContainment: other.containment)
        pair(partner, with: identifier, partnerContainment: reference.containment)
    }

    private mutating func pair(_ identifier: EUUID, with partner: EUUID, partnerContainment: Bool) {
        mutate(identifier, [.eOpposite, .container]) { element in
            if case .reference(var value) = element {
                value.opposite = partner
                value.container = partnerContainment
                element = .reference(value)
            }
        }
    }

    private mutating func clearPartner(_ partner: EUUID, pointingAt identifier: EUUID) {
        guard case .reference(let value)? = fetch(partner), value.opposite == identifier else { return }
        mutate(partner, [.eOpposite, .container]) { element in
            if case .reference(var value) = element {
                value.opposite = nil
                value.container = false
                element = .reference(value)
            }
        }
    }

    // MARK: Details

    private mutating func setDetail(annotation identifier: EUUID, key: String, value: String, at position: Int?)
        throws(MetamodelEditError)
    {
        guard case .annotation(let annotation) = try existing(identifier) else {
            throw .illegalChild(container: identifier, feature: .details, kind: .eStringToStringMapEntry)
        }
        if let current = annotation.details[key] {
            guard current != value, let entry = annotation.detailEntries.first(where: { $0.key == key }) else { return }
            var updated = annotation
            updated.details[key] = value
            store(.annotation(updated), identifier)
            staleness = max(staleness, .values)
            changes.append(
                MetamodelChange(kind: .set, element: entry.id, feature: .value, oldValue: .string(current), newValue: .string(value)))
            modified[entry.id, default: []].insert(.value)
            return
        }
        let (stored, start) = try insert(
            [.detail(EStringToStringMapEntry(key: key, value: value))], into: identifier, feature: .details, at: position)
        noteAdded(stored, in: identifier, feature: .details, at: start, created: true)
    }

    private mutating func renameDetailKey(annotation identifier: EUUID, from old: String, to new: String)
        throws(MetamodelEditError)
    {
        guard case .annotation(let annotation) = try existing(identifier) else {
            throw .illegalChild(container: identifier, feature: .details, kind: .eStringToStringMapEntry)
        }
        guard annotation.details[old] != nil, let entry = annotation.detailEntries.first(where: { $0.key == old }),
            let position = annotation.details.keys.firstIndex(of: old)
        else { throw .missingDetailKey(old) }
        guard old != new else { return }
        guard annotation.details[new] == nil else { throw .duplicateDetailKey(new) }
        var updated = annotation
        var details = OrderedDictionary<String, String>()
        for (key, value) in annotation.details { details[key == old ? new : key] = value }
        updated.details = details
        store(.annotation(updated), identifier)
        staleness = .structure
        guard let renamed = updated.detailEntries.first(where: { $0.key == new }) else { return }
        changes.append(
            MetamodelChange(
                kind: .remove, element: entry.id, feature: .details, oldValue: .identifier(identifier), index: position))
        noteRemoved([entry.id])
        noteAdded([.detail(renamed)], in: identifier, feature: .details, at: position, created: true)
    }

    // MARK: Paste

    private mutating func paste(
        _ clipboard: EcoreClipboard, into container: EUUID, feature requested: EcoreFeatureName?, at position: Int?
    ) throws(MetamodelEditError) {
        guard !clipboard.isEmpty else { throw .incompatibleClipboard }
        let target = try existing(container)
        let kinds = clipboard.kinds
        let feature: EcoreFeatureName
        if let requested {
            guard kinds.allSatisfy({ EcoreEditSchema.accepts(container: target.kind, feature: requested, kind: $0) }) else {
                throw .incompatibleClipboard
            }
            feature = requested
        } else if let found = EcoreEditSchema.feature(of: target.kind, accepting: kinds) {
            feature = found
        } else {
            throw .incompatibleClipboard
        }
        let copy = EcoreCopier.copy(clipboard.elements)
        let pasted = Set(copy.identifiers.values)
        if case .annotation(let annotation) = target {
            var keys = Set(annotation.details.keys)
            for case .detail(let entry) in copy.elements {
                guard keys.insert(entry.key).inserted else { throw .duplicateDetailKey(entry.key) }
            }
        }
        let elements = copy.elements.map { Self.clearingForeignOpposites($0, pasted: pasted) }
        let (stored, start) = try insert(elements, into: container, feature: feature, at: position)
        noteAdded(stored, in: container, feature: feature, at: start, created: true)
    }

    private static func clearingForeignOpposites(_ element: EcoreElement, pasted: Set<EUUID>) -> EcoreElement {
        var result = element
        if case .reference(var reference) = element, let opposite = reference.opposite, !pasted.contains(opposite) {
            reference.opposite = nil
            reference.container = false
            result = .reference(reference)
        }
        var features: [EcoreFeatureName] = []
        for child in element.children where !features.contains(child.feature) { features.append(child.feature) }
        for feature in features {
            let children = ElementTree.children(of: result, feature: feature).map {
                clearingForeignOpposites($0, pasted: pasted)
            }
            if let updated = ElementTree.replacing(feature, with: children, in: result) { result = updated }
        }
        return result
    }
}

/// Works out which labels an edit may have changed.
enum LabelImpact {
    /// The elements whose label or decoration may read differently after an edit.
    ///
    /// - Parameters:
    ///   - modified: The modified properties by element.
    ///   - structure: The containers whose children changed.
    ///   - added: The elements that were added.
    ///   - index: The index after the edit.
    /// - Returns: The modified elements, the elements that refer to renamed elements, and the
    ///   operations whose parameters were modified, added, or removed.
    static func affected(
        modified: [EUUID: Set<EcoreFeatureName>], structure: Set<EUUID>, added: Set<EUUID>, index: MetamodelIndex
    ) -> Set<EUUID> {
        var result = Set(modified.keys)
        for (identifier, features) in modified {
            if features.contains(.name) {
                for usage in index.usages(of: identifier) {
                    result.insert(usage.referrer)
                    if case .parameter? = index.element(usage.referrer),
                        let owner = index.container(of: usage.referrer)?.container
                    {
                        result.insert(owner)
                    }
                }
            }
            if case .parameter? = index.element(identifier), let owner = index.container(of: identifier)?.container {
                result.insert(owner)
            }
        }
        for identifier in structure {
            if case .operation? = index.element(identifier) { result.insert(identifier) }
        }
        return result
    }
}
