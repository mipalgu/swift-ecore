//
// UMLToEcoreOptionPasses.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

extension UMLToEcoreConverter {
    /// Applies the options to the converted metamodel, in the order of Eclipse UML2.
    ///
    /// Derived features and derived unions come first, then the tagged values of the Ecore
    /// profile, redefinitions and subsets, duplicates, the order of super classes, annotation
    /// details, operation bodies, default value expressions and untyped properties.
    func processOptions() async {
        if options.derivedFeatures != .ignore { processDerivedFeatures() }
        if options.unionProperties != .ignore { await processUnionProperties() }
        if options.ecoreTaggedValues != .ignore { await processTaggedValues() }
        if options.redefiningOperations != .ignore { await processRedefinitions(operations: true) }
        if options.redefiningProperties != .ignore { await processRedefinitions(operations: false) }
        if options.subsettingProperties != .ignore { await processSubsets() }
        if options.duplicateOperations != .ignore { processDuplicateOperations() }
        if options.duplicateFeatures != .ignore { processDuplicateFeatures() }
        if options.superClassOrder != .ignore { await processSuperClassOrder() }
        if options.annotationDetails != .ignore { await processAnnotationDetails() }
        if options.operationBodies != .ignore { await processOperationBodies() }
        if options.propertyDefaultExpressions != .ignore { await processDefaultExpressions() }
        if options.untypedProperties != .ignore { await processUntypedProperties() }
    }

    /// The converted UML elements with their drafts, in the order of their conversion.
    var conversions: [(element: EUUID, draft: EcoreDraft)] {
        conversionOrder.compactMap { element in converted[element].map { (element, $0) } }
    }

    // MARK: - Derived features and unions

    /// Makes derived features that are containments or not volatile transient and volatile,
    /// and not containments.
    private func processDerivedFeatures() {
        for (_, draft) in conversions where draft.kind.isFeature && draft.derived
            && (draft.containment || !draft.volatile)
        {
            if options.derivedFeatures == .process {
                draft.containment = false
                draft.transient = true
                draft.volatile = true
            }
            report(options.derivedFeatures, UMLToEcore.Diagnostic.derivedFeature,
                   "The derived feature '\(draft.qualifiedName)' is stored")
        }
    }

    /// Marks derived unions with a `union` annotation and makes them read-only, transient and volatile.
    private func processUnionProperties() async {
        for (element, draft) in conversions where draft.kind.isFeature {
            guard await bool(element, UMLToEcore.Syntax.Feature.isDerivedUnion) else { continue }
            if options.unionProperties == .process {
                _ = draft.annotation(UMLToEcore.Syntax.unionAnnotation)
                draft.changeable = false
                draft.transient = true
                draft.volatile = true
            }
            report(options.unionProperties, UMLToEcore.Diagnostic.unionProperty,
                   "'\(draft.qualifiedName)' is a derived union")
        }
    }

    // MARK: - Redefinitions and subsets

    /// Records the operations or properties that converted operations or properties redefine.
    ///
    /// - Parameter operations: `true` for operations, `false` for properties.
    private func processRedefinitions(operations: Bool) async {
        let choice = operations ? options.redefiningOperations : options.redefiningProperties
        let code = operations ? UMLToEcore.Diagnostic.redefiningOperation : UMLToEcore.Diagnostic.redefiningProperty
        let feature = operations ? UMLToEcore.Syntax.Feature.redefinedOperation : UMLToEcore.Syntax.Feature.redefinedProperty
        for (element, draft) in conversions where operations ? draft.kind == .operation : draft.kind.isFeature {
            for redefined in await referencedElements(element, feature) {
                if !operations, await isKind(await owner(of: redefined), UMLToEcore.Syntax.Metaclass.association) {
                    continue
                }
                guard let redefinedDraft = converted[redefined] else { continue }
                if choice == .process {
                    draft.annotation(UMLToEcore.Syntax.redefinesAnnotation).addReference(redefinedDraft)
                }
                report(choice, code, "'\(draft.qualifiedName)' redefines '\(redefinedDraft.qualifiedName)'")
            }
        }
    }

    /// Records the properties that converted properties subset, adjusting containment and
    /// proxy resolution as Eclipse UML2 does.
    private func processSubsets() async {
        for (element, draft) in conversions where draft.kind.isFeature {
            for subsetted in await referencedElements(element, UMLToEcore.Syntax.Feature.subsettedProperty) {
                if await isKind(await owner(of: subsetted), UMLToEcore.Syntax.Metaclass.association) { continue }
                guard let subsettedDraft = converted[subsetted] else { continue }
                if options.subsettingProperties == .process {
                    if !subsettedDraft.derived, subsettedDraft.kind == .reference, draft.kind == .reference {
                        let compositeSubset = await isCompositeSubset(subsetted)
                        if subsettedDraft.containment || compositeSubset { draft.containment = false }
                        if !draft.containment { draft.resolveProxies = subsettedDraft.resolveProxies }
                    }
                    draft.annotation(UMLToEcore.Syntax.subsetsAnnotation).addReference(subsettedDraft)
                }
                report(options.subsettingProperties, UMLToEcore.Diagnostic.subsettingProperty,
                       "'\(draft.qualifiedName)' subsets '\(subsettedDraft.qualifiedName)'")
            }
        }
    }

    /// Whether a property subsets a composite property, directly or indirectly.
    ///
    /// - Parameter property: The property.
    /// - Returns: `true` if one of the properties it subsets is composite or subsets one.
    private func isCompositeSubset(_ property: EUUID) async -> Bool {
        var pending = await referencedElements(property, UMLToEcore.Syntax.Feature.subsettedProperty)
        var seen: Set<EUUID> = [property]
        while let next = pending.popLast() {
            guard seen.insert(next).inserted else { continue }
            if await isComposite(next) { return true }
            pending += await referencedElements(next, UMLToEcore.Syntax.Feature.subsettedProperty)
        }
        return false
    }

    // MARK: - Duplicates

    /// The classes of the conversion, in the order of their conversion.
    private var classes: [EcoreDraft] {
        conversions.map(\.draft).filter { $0.kind == .eClass }
    }

    /// Moves, removes or reports operations whose signatures duplicate inherited ones.
    private func processDuplicateOperations() {
        var duplicates: [EcoreDraft] = []
        for eClass in classes {
            var index = 0
            while index < eClass.operations.count {
                let operation = eClass.operations[index]
                var removed = false
                for other in eClass.allOperations {
                    if other === operation { break }
                    guard Self.sameSignature(operation, other) else { continue }
                    let message = "'\(operation.qualifiedName)' duplicates '\(other.qualifiedName)'"
                    report(options.duplicateOperations, UMLToEcore.Diagnostic.duplicateOperation, message)
                    if options.duplicateOperations == .process {
                        if !duplicates.contains(where: { $0 === operation }) { duplicates.append(operation) }
                        ensureConformity(operation, other)
                        operation.annotation(UMLToEcore.Syntax.redefinesAnnotation).addReference(other)
                    } else if options.duplicateOperations == .discard {
                        eClass.operations.remove(at: index)
                        operation.container = nil
                        removed = true
                        break
                    }
                }
                if !removed { index += 1 }
            }
        }
        for operation in duplicates {
            guard let eClass = operation.container else { continue }
            eClass.operations.removeAll { $0 === operation }
            eClass.annotation(UMLToEcore.Syntax.duplicatesAnnotation).contents.append(operation)
        }
    }

    /// Whether two operations have the same signature: the same name and type, and parameters
    /// with the same names and types.
    ///
    /// - Parameters:
    ///   - operation: An operation.
    ///   - other: Another operation.
    /// - Returns: `true` if the signatures match.
    static func sameSignature(_ operation: EcoreDraft, _ other: EcoreDraft) -> Bool {
        guard operation.name == other.name, sameType(operation.type, other.type),
            operation.parameters.count == other.parameters.count
        else { return false }
        return zip(operation.parameters, other.parameters).allSatisfy { $0.name == $1.name && sameType($0.type, $1.type) }
    }

    /// Whether two optional types are the same.
    ///
    /// - Parameters:
    ///   - type: A type.
    ///   - other: Another type.
    /// - Returns: `true` if both are absent or both stand for the same element.
    static func sameType(_ type: EcoreDraftType?, _ other: EcoreDraftType?) -> Bool {
        guard let type else { return other == nil }
        return type.isSame(as: other)
    }

    /// Moves, removes or reports features whose names duplicate inherited ones.
    ///
    /// A moved feature is kept in a `duplicates` annotation of its class with a `redefines`
    /// annotation that refers to the inherited feature. Where a stored feature duplicates a
    /// derived one, the derived one is moved instead. The opposite of a moved reference loses
    /// its opposite and becomes volatile.
    private func processDuplicateFeatures() {
        var duplicates: [EcoreDraft] = []
        var removals: [EcoreDraft] = []
        for eClass in classes {
            var index = 0
            while index < eClass.features.count {
                let feature = eClass.features[index]
                var removed = false
                for other in eClass.allFeatures {
                    if other === feature { break }
                    guard other.name == feature.name else { continue }
                    let message = "'\(feature.qualifiedName)' duplicates '\(other.qualifiedName)'"
                    report(options.duplicateFeatures, UMLToEcore.Diagnostic.duplicateFeature, message)
                    if options.duplicateFeatures == .process {
                        let lower = feature.lowerBound
                        let upper = feature.upperBound
                        let type = feature.type
                        if !duplicates.contains(where: { $0 === feature }) {
                            let duplicate = other.derived && !feature.derived ? other : feature
                            if !duplicates.contains(where: { $0 === duplicate }) { duplicates.append(duplicate) }
                            ensureConformity(feature, other)
                        }
                        let redefines = feature.annotation(UMLToEcore.Syntax.redefinesAnnotation)
                        redefines.addReference(other)
                        if feature.lowerBound != lower {
                            redefines.details[EcoreFeatureName.lowerBound.rawValue] = String(lower)
                        }
                        if feature.upperBound != upper {
                            redefines.details[EcoreFeatureName.upperBound.rawValue] = String(upper)
                        }
                        if let type, !type.isSame(as: feature.type) {
                            redefines.details[EcoreFeatureName.eType.rawValue] = type.name
                        }
                    } else if options.duplicateFeatures == .discard {
                        if let opposite = feature.opposite { removals.append(opposite) }
                        eClass.features.remove(at: index)
                        feature.container = nil
                        removed = true
                        break
                    }
                }
                if !removed { index += 1 }
            }
        }
        for feature in duplicates {
            guard let eClass = feature.container else { continue }
            eClass.features.removeAll { $0 === feature }
            let annotation = eClass.annotation(UMLToEcore.Syntax.duplicatesAnnotation)
            annotation.contents.append(feature)
            if let redefines = feature.existingAnnotation(UMLToEcore.Syntax.redefinesAnnotation),
                !redefines.details.isEmpty
            {
                let details = annotation.annotation(feature.name)
                for (key, value) in redefines.details { details.details[key] = value }
                redefines.details = [:]
            }
            if let opposite = feature.opposite, !duplicates.contains(where: { $0 === opposite }) {
                opposite.opposite = nil
                if feature.containment {
                    opposite.changeable = false
                    opposite.transient = true
                }
                opposite.volatile = true
            }
        }
        for feature in removals {
            feature.container?.features.removeAll { $0 === feature }
            feature.container = nil
        }
    }

    /// Makes a duplicate and the element it duplicates conform, as Eclipse UML2 does: their
    /// lower bounds become the lesser if only one is required, their upper bounds the greater
    /// if only one is many, single-valued elements take a common type, and the duplicate takes
    /// the ordering and uniqueness of the element it duplicates.
    ///
    /// - Parameters:
    ///   - element: The duplicate feature or operation.
    ///   - other: The inherited feature or operation it duplicates.
    func ensureConformity(_ element: EcoreDraft, _ other: EcoreDraft) {
        if (element.lowerBound >= 1) != (other.lowerBound >= 1) {
            let lesser = min(other.lowerBound, element.lowerBound)
            other.lowerBound = lesser
            element.lowerBound = lesser
        }
        let isMany = element.isMany
        let otherIsMany = other.isMany
        if isMany != otherIsMany {
            let greater = element.upperBound == -1 || other.upperBound == -1 ? -1 : max(other.upperBound, element.upperBound)
            other.upperBound = greater
            element.upperBound = greater
        }
        if !isMany && !otherIsMany, let common = commonType(other.type, element.type) {
            if !common.isSame(as: other.type) { other.type = common }
            if !common.isSame(as: element.type) { element.type = common }
        }
        element.ordered = other.ordered
        element.unique = other.unique
    }

    /// The type that two types have in common, as Eclipse UML2 determines it.
    ///
    /// Two classes have the first class among themselves and their super classes that is a
    /// super type of the other in common, or else `EObject`. Data types with the same name have
    /// their type in common, two enumerations `EEnumerator`, and other data types `EJavaObject`.
    ///
    /// - Parameters:
    ///   - type: The type of the inherited element.
    ///   - other: The type of the duplicate.
    /// - Returns: The common type, or `nil` if the inherited element has no type.
    func commonType(_ type: EcoreDraftType?, _ other: EcoreDraftType?) -> EcoreDraftType? {
        guard let type, !type.isSame(as: other) else { return type }
        if case .classifier(let eClass, _) = type, eClass.kind == .eClass {
            if case .classifier(let otherClass, _)? = other, otherClass.kind == .eClass {
                if eClass.isSuperType(of: otherClass) { return type }
                if otherClass.isSuperType(of: eClass) { return other }
                for superType in eClass.allClasses.dropLast() where superType.isSuperType(of: otherClass) {
                    return .classifier(superType, arguments: [])
                }
                for superType in otherClass.allClasses.dropLast() where superType.isSuperType(of: eClass) {
                    return .classifier(superType, arguments: [])
                }
            }
            return ecoreClassifier(named: EcoreClassifier.eObject.rawValue)
        }
        if type.isClass { return ecoreClassifier(named: EcoreClassifier.eObject.rawValue) }
        if case .classifier(let eEnum, _) = type, eEnum.kind == .eEnum {
            if case .classifier(let otherEnum, _)? = other, otherEnum.kind == .eEnum { return ecoreType(.eEnumerator) }
            return ecoreType(.eJavaObject)
        }
        if let other, !other.isClass, other.name == type.name { return type }
        return ecoreType(.eJavaObject)
    }

    // MARK: - Super classes

    /// Orders the super classes of each class that its generalizations name: those of
    /// generalizations with the keyword `extend` first, then the others, then those with the
    /// keyword `mixin`, each group by descending number of features and then by name.
    private func processSuperClassOrder() async {
        for (element, eClass) in conversions where eClass.kind == .eClass {
            var groups: [[EcoreDraft]] = [[], [], []]
            for child in await contents(of: element) where await isKind(child, UMLToEcore.Syntax.Metaclass.generalization) {
                guard let general = await referencedElement(child, UMLToEcore.Syntax.Feature.general),
                    let generalDraft = converted[general], eClass.superClasses.contains(where: { $0 === generalDraft })
                else { continue }
                let keywords = await self.keywords(of: child)
                let group = keywords.contains("extend") ? 0 : keywords.contains("mixin") ? 2 : 1
                groups[group].append(generalDraft)
            }
            var ordered: [EcoreDraft] = []
            for group in groups {
                let sorted = group.sorted {
                    let left = $0.allFeatures.count
                    let right = $1.allFeatures.count
                    return left != right ? left > right : $0.name < $1.name
                }
                for superClass in sorted where !ordered.contains(where: { $0 === superClass }) { ordered.append(superClass) }
            }
            let current = eClass.superTypes.map { type -> EcoreDraft? in
                if case .classifier(let draft, _) = type { return draft }
                return nil
            }
            guard ordered.count != current.count || zip(ordered, current).contains(where: { $0 !== $1 }) else { continue }
            if options.superClassOrder == .process {
                for (position, superClass) in ordered.enumerated() {
                    guard let index = eClass.superTypes.firstIndex(where: {
                        if case .classifier(let draft, _) = $0 { return draft === superClass }
                        return false
                    }) else { continue }
                    let type = eClass.superTypes.remove(at: index)
                    eClass.superTypes.insert(type, at: min(position, eClass.superTypes.count))
                }
            }
            report(options.superClassOrder, UMLToEcore.Diagnostic.superClassOrder,
                   "The super classes of '\(eClass.qualifiedName)' are not ordered")
        }
    }

    /// The keywords of a UML element, which Eclipse UML2 keeps as the detail keys of an
    /// annotation with its own source.
    ///
    /// - Parameter element: The element.
    /// - Returns: The keywords.
    private func keywords(of element: EUUID) async -> [String] {
        await annotations(of: element).first { $0.source == UMLToEcore.Syntax.umlAnnotationSource }?.details.map(\.0) ?? []
    }

    // MARK: - Annotation details

    /// The Ecore annotations of a UML element.
    ///
    /// - Parameter element: The element.
    /// - Returns: The source and details of each annotation, in order.
    func annotations(of element: EUUID) async -> [(source: String, details: [(String, String)])] {
        var result: [(source: String, details: [(String, String)])] = []
        for annotation in await referencedElements(element, UMLToEcore.Syntax.Feature.eAnnotations) {
            if let native = await object(annotation) as? EAnnotation {
                result.append((native.source, native.details.map { ($0.key, $0.value) }))
                continue
            }
            let source = await string(annotation, UMLToEcore.Syntax.Feature.source) ?? ""
            var details: [(String, String)] = []
            for entry in await referencedElements(annotation, UMLToEcore.Syntax.Feature.details) {
                if let native = await object(entry) as? EStringToStringMapEntry {
                    details.append((native.key, native.value))
                } else if let key = await string(entry, UMLToEcore.Syntax.Feature.key) {
                    details.append((key, await string(entry, UMLToEcore.Syntax.Feature.value) ?? ""))
                }
            }
            result.append((source, details))
        }
        return result
    }

    /// Copies the details of the annotations of converted UML elements, other than those of
    /// Eclipse UML2 itself, to their drafts.
    private func processAnnotationDetails() async {
        for (element, draft) in conversions {
            for annotation in await annotations(of: element)
            where annotation.source != UMLToEcore.Syntax.umlAnnotationSource && !annotation.details.isEmpty {
                if options.annotationDetails == .process {
                    let target = draft.annotation(annotation.source)
                    for (key, value) in annotation.details { target.details[key] = value }
                }
                report(options.annotationDetails, UMLToEcore.Diagnostic.annotationDetails,
                       "The details of the annotation '\(annotation.source)' of '\(draft.qualifiedName)'")
            }
        }
    }

    // MARK: - Bodies and default expressions

    /// Records the bodies of the opaque behaviours that implement converted operations and
    /// of their body conditions.
    private func processOperationBodies() async {
        for (element, draft) in conversions where draft.kind == .operation {
            guard await isKind(element, UMLToEcore.Syntax.Metaclass.operation) else { continue }
            for method in await referencedElements(element, UMLToEcore.Syntax.Feature.method) {
                guard await isKind(method, UMLToEcore.Syntax.Metaclass.opaqueBehavior),
                    let body = await opaqueBody(method)
                else { continue }
                processOperationBody(draft, body)
            }
            if let condition = await referencedElement(element, UMLToEcore.Syntax.Feature.bodyCondition),
                let body = await opaqueBody(await referencedElement(condition, UMLToEcore.Syntax.Feature.specification))
            {
                processOperationBody(draft, body)
            }
        }
    }

    /// Records the opaque default value expressions of converted properties as initial values
    /// or derivations, OCL expressions for the setting delegate.
    private func processDefaultExpressions() async {
        for (element, draft) in conversions where draft.kind.isFeature {
            guard let body = await opaqueBody(await referencedElement(element, UMLToEcore.Syntax.Feature.defaultValue))
            else { continue }
            for (language, text) in body {
                report(options.propertyDefaultExpressions, UMLToEcore.Diagnostic.propertyDefaultExpression,
                       "The \(language) default value of '\(draft.qualifiedName)'")
                guard options.propertyDefaultExpressions == .process else { continue }
                var source = UMLToEcore.Syntax.uml2GenModel
                if language == UMLToEcore.Syntax.oclLanguage {
                    if let package = draft.package { addDelegate(package, AnnotationSource.EcoreKey.settingDelegates) }
                    source = options.oclDelegateURI
                }
                let key = draft.changeable || !draft.derived ? UMLToEcore.Syntax.initialKey : UMLToEcore.Syntax.derivationKey
                draft.annotation(source).details[key] = text
            }
        }
    }

    // MARK: - Untyped properties

    /// Reports or removes the converted properties that have no type.
    private func processUntypedProperties() async {
        for (element, draft) in conversions where draft.kind.isFeature {
            guard await value(element, UMLToEcore.Syntax.Feature.type) == nil else { continue }
            switch options.untypedProperties {
            case .process:
                report(.information, UMLToEcore.Diagnostic.untypedProperty,
                       "The untyped property '\(draft.qualifiedName)' refers to EObject (processed)")
            case .report:
                report(.error, UMLToEcore.Diagnostic.untypedProperty,
                       "The property '\(draft.qualifiedName)' has no type")
            case .discard:
                report(.warning, UMLToEcore.Diagnostic.untypedProperty,
                       "The untyped property '\(draft.qualifiedName)' is removed (discarded)")
                draft.container?.features.removeAll { $0 === draft }
                draft.container = nil
                for (_, other) in conversions where other.opposite === draft { other.opposite = nil }
            case .ignore:
                break
            }
        }
    }
}
