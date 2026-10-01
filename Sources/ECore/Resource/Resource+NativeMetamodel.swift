//
// Resource+NativeMetamodel.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

extension Resource {
    /// Creates a native package from a parsed Ecore package object.
    ///
    /// The object graph that the XMI parser builds from an `.ecore` document is converted
    /// into native metamodel values: nested packages, classes (with all of their supertypes,
    /// attributes, references, operations, and parameters), enumerations, and data types.
    /// The converted elements keep the identifiers of the parsed objects, so opposite
    /// references and name-based fragments identify the same elements in both forms.
    ///
    /// Types are resolved to the real classifier wherever the type is a class, enumeration,
    /// or data type of the document (including nested packages), a classifier of another
    /// document that the resource set can load as a native metamodel, or a built-in of the
    /// Ecore metamodel (see ``EcorePackage``). A type that cannot be resolved becomes the
    /// `EString` data type for an attribute and the `EObject` class for a reference.
    ///
    /// A type given by an `eGenericType` child is read as its raw classifier. Type arguments,
    /// type parameters, and generic bounds are not represented, so a reference to a type
    /// parameter has no type.
    ///
    /// Because native classes are value types, a reference records a snapshot of its target
    /// class. Snapshots are accurate to a fixed depth of reference hops; use the identifier
    /// of a reference's type to find the complete class in the package.
    ///
    /// - Parameters:
    ///   - object: The parsed object that represents the package.
    ///   - shouldIgnoreUnresolvedClassifiers: If `true`, classifiers that cannot be converted
    ///     are skipped; if `false`, the first conversion failure is thrown (default `false`).
    /// - Returns: The package, with all classifiers and subpackages converted.
    /// - Throws: ``XMIError`` if the object is not a package object, a name is missing, or a
    ///   classifier cannot be converted and failures are not ignored.
    public func createEPackage(
        from object: any EObject, shouldIgnoreUnresolvedClassifiers: Bool = false
    ) async throws -> EPackage {
        guard let root = object as? DynamicEObject else {
            throw XMIError.invalidObjectType("Expected DynamicEObject, got \(type(of: object))")
        }
        guard root.eGet(XMIAttribute.name.rawValue) is String else {
            throw XMIError.missingRequiredAttribute(XMIAttribute.name.rawValue)
        }
        var parsed: [EUUID: DynamicEObject] = [:]
        for case let candidate as DynamicEObject in getAllObjects() { parsed[candidate.id] = candidate }
        var converter = NativeMetamodelConverter(
            objects: parsed, ignoresFailures: shouldIgnoreUnresolvedClassifiers)
        converter.external = await resolveExternalClassifiers(converter.collectProxies(from: root))
        return try converter.convert(root)
    }

    /// Resolves the classifiers of other documents that a package refers to.
    ///
    /// - Parameter proxies: The cross-document references to resolve.
    /// - Returns: The native classifier for each reference that could be resolved.
    private func resolveExternalClassifiers(_ proxies: [ResourceProxy]) async
        -> [ResourceProxy: any EClassifier]
    {
        guard let resourceSet else { return [:] }
        var resolved: [ResourceProxy: any EClassifier] = [:]
        for proxy in proxies {
            guard let target = await resourceSet.nativeResource(uri: proxy.uri) else { continue }
            let navigator = FragmentNavigator(resource: target)
            if let classifier = await navigator.resolve(proxy.fragment) as? any EClassifier {
                resolved[proxy] = classifier
            }
        }
        return resolved
    }
}

// MARK: - Converter

/// Converts the parsed object graph of an Ecore document into native metamodel values.
struct NativeMetamodelConverter {
    /// The number of conversion passes; each pass deepens the class snapshots held by
    /// references by one level.
    private static let snapshotDepth = 4

    /// A target of a reference value: an object of the document or one in another document.
    private enum Target {
        case local(EUUID)
        case external(ResourceProxy)
    }

    /// The parsed objects of the document, by identifier.
    private let objects: [EUUID: DynamicEObject]

    /// Whether classifiers that cannot be converted are skipped.
    let ignoresFailures: Bool

    /// The classifiers of other documents, by the reference that names them.
    var external: [ResourceProxy: any EClassifier] = [:]

    /// The converted enumerations and data types, by identifier.
    private var dataTypes: [EUUID: any EClassifier] = [:]

    /// The latest snapshot of each converted class, by identifier.
    private var classes: [EUUID: EClass] = [:]

    init(objects: [EUUID: DynamicEObject], ignoresFailures: Bool) {
        self.objects = objects
        self.ignoresFailures = ignoresFailures
    }

    // MARK: Reading parsed objects

    /// Reads a text value.
    private func string(_ object: DynamicEObject, _ name: String) -> String? {
        object.eGet(name) as? String
    }

    /// Reads a flag stored as a Boolean or as its text spelling.
    private func flag(_ object: DynamicEObject, _ name: String, _ defaultValue: Bool) -> Bool {
        if let value = object.eGet(name) as? Bool { return value }
        if let text = object.eGet(name) as? String { return BooleanString.fromString(text) ?? defaultValue }
        return defaultValue
    }

    /// Reads a number stored as an integer or as its text spelling.
    private func number(_ object: DynamicEObject, _ name: String, _ defaultValue: Int) -> Int {
        if let value = object.eGet(name) as? Int { return value }
        if let text = object.eGet(name) as? String, let value = Int(text) { return value }
        return defaultValue
    }

    /// The targets that a reference value denotes, in order.
    private func targets(_ value: (any EcoreValue)?) -> [Target] {
        switch value {
        case let identifier as EUUID: return [.local(identifier)]
        case let identifiers as [EUUID]: return identifiers.map { .local($0) }
        case let proxy as ResourceProxy: return [.external(proxy)]
        case let proxies as [ResourceProxy]: return proxies.map { .external($0) }
        case let object as any EObject: return [.local(object.id)]
        case let array as EcoreValueArray: return array.values.flatMap { targets($0) }
        default: return []
        }
    }

    /// The parsed objects that a containment value denotes, in order.
    private func contained(_ object: DynamicEObject, _ name: String)
        -> [DynamicEObject]
    {
        targets(object.eGet(name)).compactMap { target in
            guard case .local(let identifier) = target else { return nil }
            return objects[identifier]
        }
    }

    /// The cross-document references held by a package and everything it contains.
    ///
    /// - Parameters:
    ///   - root: The parsed package.
    /// - Returns: The distinct references, in document order.
    func collectProxies(from root: DynamicEObject) -> [ResourceProxy] {
        var result: [ResourceProxy] = []
        var seen: Set<ResourceProxy> = []
        func note(_ value: (any EcoreValue)?) {
            for case .external(let proxy) in targets(value) where seen.insert(proxy).inserted {
                result.append(proxy)
            }
        }
        func visit(_ object: DynamicEObject) {
            for name in Self.typeReferenceNames { note(object.eGet(name)) }
            for name in Self.containmentNames {
                for child in contained(object, name) { visit(child) }
            }
        }
        visit(root)
        return result
    }

    private static let typeReferenceNames = [
        XMIAttribute.eType.rawValue, EcoreFeatureName.eSuperTypes.rawValue,
        EcoreFeatureName.eExceptions.rawValue,
    ]

    private static let containmentNames = [
        EcoreFeatureName.eClassifiers.rawValue, EcoreFeatureName.eSubpackages.rawValue,
        EcoreFeatureName.eStructuralFeatures.rawValue, EcoreFeatureName.eOperations.rawValue,
        EcoreFeatureName.eParameters.rawValue,
    ]

    // MARK: Conversion

    /// Converts a parsed package and everything it contains.
    ///
    /// - Parameters:
    ///   - root: The parsed package.
    /// - Returns: The native package.
    /// - Throws: ``XMIError`` if an element cannot be converted and failures are not ignored.
    mutating func convert(_ root: DynamicEObject) throws -> EPackage {
        var classObjects: [DynamicEObject] = []
        try convertDataTypes(of: root, classObjects: &classObjects)
        buildClasses(classObjects)
        return try assemble(root)
    }

    /// Converts the enumerations and data types of a package tree and lists its classes.
    private mutating func convertDataTypes(
        of package: DynamicEObject, classObjects: inout [DynamicEObject]
    ) throws {
        for classifier in contained(package, EcoreFeatureName.eClassifiers.rawValue) {
            switch classifier.eClass.name {
            case EcoreClassifier.eClass.rawValue:
                classObjects.append(classifier)
            case EcoreClassifier.eEnum.rawValue:
                if let name = string(classifier, XMIAttribute.name.rawValue) {
                    dataTypes[classifier.id] = EEnum(
                        id: classifier.id, name: name,
                        literals: literals(of: classifier))
                } else {
                    try failMissingName()
                }
            case EcoreClassifier.eDataType.rawValue:
                if let name = string(classifier, XMIAttribute.name.rawValue) {
                    dataTypes[classifier.id] = EDataType(
                        id: classifier.id, name: name,
                        serialisable: flag(classifier, XMIAttribute.serializable.rawValue, true),
                        instanceClassName: string(classifier, XMIAttribute.instanceClassName.rawValue))
                } else {
                    try failMissingName()
                }
            default:
                if !ignoresFailures {
                    throw XMIError.unknownElement(
                        "Unsupported classifier type: \(classifier.eClass.name)")
                }
            }
        }
        for subpackage in contained(package, EcoreFeatureName.eSubpackages.rawValue) {
            try convertDataTypes(of: subpackage, classObjects: &classObjects)
        }
    }

    private func failMissingName() throws {
        if !ignoresFailures { throw XMIError.missingRequiredAttribute(XMIAttribute.name.rawValue) }
    }

    private func literals(of eEnum: DynamicEObject) -> [EEnumLiteral] {
        contained(eEnum, EcoreFeatureName.eLiterals.rawValue).compactMap { literal in
            guard let name = string(literal, XMIAttribute.name.rawValue) else { return nil }
            return EEnumLiteral(
                id: literal.id, name: name, value: number(literal, XMIAttribute.value.rawValue, 0),
                literal: string(literal, XMIAttribute.literal.rawValue) ?? name)
        }
    }

    /// Builds the class snapshots in several passes.
    ///
    /// Supertypes are built before their subtypes within a pass, so that inherited features
    /// are always available. The type of each feature is the snapshot of the previous pass.
    private mutating func buildClasses(_ objects: [DynamicEObject]) {
        for object in objects {
            guard let name = string(object, XMIAttribute.name.rawValue) else { continue }
            classes[object.id] = EClass(
                id: object.id, name: name,
                isAbstract: flag(object, XMIAttribute.abstract.rawValue, false),
                isInterface: flag(object, XMIAttribute.interface.rawValue, false),
                instanceClassName: string(object, XMIAttribute.instanceClassName.rawValue))
        }
        let order = supertypesFirst(objects)
        for _ in 0..<Self.snapshotDepth {
            var built: [EUUID: EClass] = [:]
            for object in order {
                if let converted = convertClass(object, previous: classes, built: built) {
                    built[object.id] = converted
                }
            }
            for (identifier, converted) in built { classes[identifier] = converted }
        }
    }

    /// Orders classes so that every class follows its supertypes of the same document.
    private func supertypesFirst(_ objects: [DynamicEObject]) -> [DynamicEObject] {
        let byID = Dictionary(objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered: [DynamicEObject] = []
        var state: [EUUID: Bool] = [:]  // false while being visited, true once placed
        func place(_ object: DynamicEObject) {
            if state[object.id] != nil { return }
            state[object.id] = false
            for case .local(let identifier) in targets(object.eGet(EcoreFeatureName.eSuperTypes.rawValue)) {
                if let parent = byID[identifier] { place(parent) }
            }
            state[object.id] = true
            ordered.append(object)
        }
        objects.forEach(place)
        return ordered
    }

    private func convertClass(
        _ object: DynamicEObject, previous: [EUUID: EClass], built: [EUUID: EClass]
    ) -> EClass? {
        guard var result = previous[object.id] else { return nil }
        result.eSuperTypes = targets(object.eGet(EcoreFeatureName.eSuperTypes.rawValue)).compactMap {
            switch $0 {
            case .local(let identifier):
                return built[identifier] ?? previous[identifier]
                    ?? (EcorePackage.classifier(id: identifier) as? EClass)
            case .external(let proxy):
                return external[proxy] as? EClass
            }
        }
        result.eStructuralFeatures = contained(
            object, EcoreFeatureName.eStructuralFeatures.rawValue
        ).compactMap { convertFeature($0, previous: previous) }
        result.eOperations = contained(object, EcoreFeatureName.eOperations.rawValue)
            .compactMap { convertOperation($0, previous: previous) }
        return result
    }

    // MARK: Types

    /// The classifier that a type reference denotes, if it can be resolved.
    private func classifier(_ value: (any EcoreValue)?, previous: [EUUID: EClass]) -> (any EClassifier)? {
        guard let target = targets(value).first else { return nil }
        switch target {
        case .local(let identifier):
            return dataTypes[identifier] ?? previous[identifier] ?? EcorePackage.classifier(id: identifier)
        case .external(let proxy):
            return external[proxy]
        }
    }

    private func convertFeature(
        _ object: DynamicEObject, previous: [EUUID: EClass]
    ) -> (any EStructuralFeature)? {
        guard let name = string(object, XMIAttribute.name.rawValue) else { return nil }
        let resolved = classifier(object.eGet(XMIAttribute.eType.rawValue), previous: previous)
        let ordered = flag(object, XMIAttribute.ordered.rawValue, true)
        let unique = flag(object, XMIAttribute.unique.rawValue, true)
        let unsettable = flag(object, XMIAttribute.unsettable.rawValue, false)
        let derived = flag(object, XMIAttribute.derived.rawValue, false)
        let changeable = flag(object, XMIAttribute.changeable.rawValue, true)
        let volatile = flag(object, XMIAttribute.volatile.rawValue, false)
        let transient = flag(object, XMIAttribute.transient.rawValue, false)
        let lowerBound = number(object, XMIAttribute.lowerBound.rawValue, 0)
        let upperBound = number(object, XMIAttribute.upperBound.rawValue, 1)
        switch object.eClass.name {
        case EcoreClassifier.eAttribute.rawValue:
            return EAttribute(
                id: object.id, name: name, eType: resolved ?? Self.defaultAttributeType,
                lowerBound: lowerBound, upperBound: upperBound, changeable: changeable,
                volatile: volatile, transient: transient,
                defaultValueLiteral: string(object, XMIAttribute.defaultValueLiteral.rawValue),
                isID: flag(object, XMIAttribute.iD.rawValue, false), ordered: ordered,
                unique: unique, unsettable: unsettable, derived: derived)
        case EcoreClassifier.eReference.rawValue:
            let opposite = targets(object.eGet(XMIAttribute.eOpposite.rawValue)
                ?? object.eGet(XMIAttribute.opposite.rawValue)).compactMap { target -> EUUID? in
                    if case .local(let identifier) = target { return identifier }
                    return nil
                }.first
            let oppositeContains = opposite.flatMap { objects[$0] }
                .map { flag($0, XMIAttribute.containment.rawValue, false) } ?? false
            return EReference(
                id: object.id, name: name, eType: resolved ?? Self.defaultReferenceType,
                lowerBound: lowerBound, upperBound: upperBound, changeable: changeable,
                volatile: volatile, transient: transient,
                containment: flag(object, XMIAttribute.containment.rawValue, false),
                opposite: opposite,
                resolveProxies: flag(object, XMIAttribute.resolveProxies.rawValue, true),
                ordered: ordered, unique: unique, unsettable: unsettable, derived: derived,
                container: oppositeContains)
        default:
            return nil
        }
    }

    private func convertOperation(
        _ object: DynamicEObject, previous: [EUUID: EClass]
    ) -> EOperation? {
        guard let name = string(object, XMIAttribute.name.rawValue) else { return nil }
        let parameters = contained(object, EcoreFeatureName.eParameters.rawValue)
            .compactMap { parameter -> EParameter? in
                guard let parameterName = string(parameter, XMIAttribute.name.rawValue) else { return nil }
                return EParameter(
                    id: parameter.id, name: parameterName,
                    eType: classifier(parameter.eGet(XMIAttribute.eType.rawValue), previous: previous),
                    lowerBound: number(parameter, XMIAttribute.lowerBound.rawValue, 0),
                    upperBound: number(parameter, XMIAttribute.upperBound.rawValue, 1),
                    ordered: flag(parameter, XMIAttribute.ordered.rawValue, true),
                    unique: flag(parameter, XMIAttribute.unique.rawValue, true))
            }
        let exceptions = targets(object.eGet(EcoreFeatureName.eExceptions.rawValue)).compactMap {
            target -> (any EClassifier)? in
            switch target {
            case .local(let identifier):
                return previous[identifier] ?? dataTypes[identifier]
                    ?? EcorePackage.classifier(id: identifier)
            case .external(let proxy):
                return external[proxy]
            }
        }
        return EOperation(
            id: object.id, name: name,
            eType: classifier(object.eGet(XMIAttribute.eType.rawValue), previous: previous),
            lowerBound: number(object, XMIAttribute.lowerBound.rawValue, 0),
            upperBound: number(object, XMIAttribute.upperBound.rawValue, 1),
            ordered: flag(object, XMIAttribute.ordered.rawValue, true),
            unique: flag(object, XMIAttribute.unique.rawValue, true),
            eParameters: parameters, eExceptions: exceptions)
    }

    private static var defaultAttributeType: any EClassifier {
        EcorePackage.dataType(.eString) ?? EDataType(name: EcoreDataType.eString.rawValue)
    }

    private static var defaultReferenceType: any EClassifier {
        EcorePackage.metaClass(.eObject)
    }

    // MARK: Packages

    /// Assembles a package from its converted classifiers and subpackages.
    private func assemble(_ package: DynamicEObject) throws -> EPackage {
        guard let name = string(package, XMIAttribute.name.rawValue) else {
            throw XMIError.missingRequiredAttribute(XMIAttribute.name.rawValue)
        }
        var classifiers: [any EClassifier] = []
        for classifier in contained(package, EcoreFeatureName.eClassifiers.rawValue) {
            if let converted = classes[classifier.id] ?? dataTypes[classifier.id] {
                classifiers.append(converted)
            }
        }
        var subpackages: [EPackage] = []
        for subpackage in contained(package, EcoreFeatureName.eSubpackages.rawValue) {
            subpackages.append(try assemble(subpackage))
        }
        return EPackage(
            id: package.id, name: name,
            nsURI: string(package, EcoreFeatureName.nsURI.rawValue) ?? "http://\(name.lowercased())",
            nsPrefix: string(package, EcoreFeatureName.nsPrefix.rawValue) ?? name.lowercased(),
            eClassifiers: classifiers, eSubpackages: subpackages)
    }
}
