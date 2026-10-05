//
// Resource+NativeMetamodel.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation
import OrderedCollections

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
    /// The package records the URI of its document and the classifiers of other documents
    /// that it refers to (see ``EPackageOrigin``).
    ///
    /// Annotations are converted for every element, with their sources, details in document
    /// order, nested annotations, contents, and references. References to elements of the
    /// document keep the identifiers of those elements; references to other documents are
    /// kept as proxies.
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
        converter.localProxies = await resolveLocalAnnotationProxies(converter.annotationProxies())
        var package = try converter.convert(root)
        var references: [EUUID: ResourceProxy] = [:]
        for (proxy, classifier) in converter.external where references[classifier.id] == nil {
            references[classifier.id] = proxy
        }
        package.origin = EPackageOrigin(
            documentURI: uri, externalReferences: references,
            unresolvedTypes: converter.unresolvedTypes(in: parsed.values),
            externalOpposites: converter.externalOpposites(in: parsed.values))
        return package
    }

    /// Resolves the annotation references that point back into this document.
    ///
    /// A reference list that mixes references to this document and to other documents is
    /// stored with proxies for all of them; the proxies of this document are resolved here.
    ///
    /// - Parameter proxies: The annotation reference proxies.
    /// - Returns: The identifier of the element for each proxy of this document.
    private func resolveLocalAnnotationProxies(_ proxies: [ResourceProxy]) async -> [ResourceProxy: EUUID] {
        var resolved: [ResourceProxy: EUUID] = [:]
        let navigator = FragmentNavigator(resource: self)
        for proxy in proxies where proxy.uri == uri {
            if let target = await navigator.resolve(proxy.fragment) { resolved[proxy] = target.id }
        }
        return resolved
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

    /// The identifiers of the elements that annotation references of this document name.
    var localProxies: [ResourceProxy: EUUID] = [:]

    /// The converted annotations of each element, by the identifier of the element.
    private var annotationMap: [EUUID: [EAnnotation]] = [:]

    /// The converted enumerations and data types, by identifier.
    private var dataTypes: [EUUID: any EClassifier] = [:]

    /// The latest snapshot of each converted class, by identifier.
    private var classes: [EUUID: EClass] = [:]

    /// The options that govern how unresolved references are loaded.
    let options: EcoreLoadOptions

    /// The objects of the parsed data types and enumerations, whose type parameters are converted
    /// once the classes are known.
    private var dataTypeObjects: [DynamicEObject] = []

    init(
        objects: [EUUID: DynamicEObject], ignoresFailures: Bool,
        options: EcoreLoadOptions = EcoreLoadOptions()
    ) {
        self.objects = objects
        self.ignoresFailures = ignoresFailures
        self.options = options
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

    /// The types that name a classifier which could not be loaded.
    ///
    /// - Parameter parsed: The parsed objects of the document.
    /// - Returns: The proxy of the unresolved type of each typed element, by element identifier.
    func unresolvedTypes(in parsed: some Collection<DynamicEObject>) -> [EUUID: ResourceProxy] {
        var result: [EUUID: ResourceProxy] = [:]
        for object in parsed {
            let name = object.eClass.name == EcoreClassifier.eGenericType.rawValue
                ? EcoreFeatureName.eClassifier.rawValue : XMIAttribute.eType.rawValue
            guard let target = targets(object.eGet(name)).first,
                case .external(let proxy) = target, external[proxy] == nil
            else { continue }
            result[object.id] = proxy
        }
        return result
    }

    /// The opposites that lie in other documents.
    ///
    /// - Parameter parsed: The parsed objects of the document.
    /// - Returns: The proxy of the opposite of each reference that has one, by reference identifier.
    func externalOpposites(in parsed: some Collection<DynamicEObject>) -> [EUUID: ResourceProxy] {
        var result: [EUUID: ResourceProxy] = [:]
        for object in parsed where object.eClass.name == EcoreClassifier.eReference.rawValue {
            let value = object.eGet(XMIAttribute.eOpposite.rawValue) ?? object.eGet(XMIAttribute.opposite.rawValue)
            if let target = targets(value).first, case .external(let proxy) = target {
                result[object.id] = proxy
            }
        }
        return result
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
        EcoreFeatureName.eExceptions.rawValue, EcoreFeatureName.eClassifier.rawValue,
    ]

    private static let containmentNames = [
        EcoreFeatureName.eClassifiers.rawValue, EcoreFeatureName.eSubpackages.rawValue,
        EcoreFeatureName.eStructuralFeatures.rawValue, EcoreFeatureName.eOperations.rawValue,
        EcoreFeatureName.eParameters.rawValue, EcoreFeatureName.eTypeParameters.rawValue,
        EcoreFeatureName.eBounds.rawValue, EcoreFeatureName.eGenericType.rawValue,
        EcoreFeatureName.eGenericSuperTypes.rawValue, EcoreFeatureName.eGenericExceptions.rawValue,
        EcoreFeatureName.eTypeArguments.rawValue, EcoreFeatureName.eUpperBound.rawValue,
        EcoreFeatureName.eLowerBound.rawValue,
    ]

    // MARK: Annotations

    /// The references that the annotations of the document hold to other documents.
    ///
    /// - Returns: The distinct proxies, in no particular order.
    func annotationProxies() -> [ResourceProxy] {
        var result: Set<ResourceProxy> = []
        for object in objects.values where object.eClass.name == EcoreClassifier.eAnnotation.rawValue {
            for case .external(let proxy) in targets(object.eGet(EcoreFeatureName.references.rawValue)) {
                result.insert(proxy)
            }
        }
        return Array(result)
    }

    /// Converts the annotations of every parsed element.
    private mutating func convertAnnotations() {
        for object in objects.values where object.eClass.name != EcoreClassifier.eAnnotation.rawValue {
            let converted = annotations(of: object)
            if !converted.isEmpty { annotationMap[object.id] = converted }
        }
    }

    /// Converts the annotations that a parsed element holds.
    private func annotations(of object: DynamicEObject) -> [EAnnotation] {
        contained(object, EcoreFeatureName.eAnnotations.rawValue).map { annotation($0) }
    }

    /// Converts one parsed annotation, including everything it holds.
    private func annotation(_ object: DynamicEObject) -> EAnnotation {
        var details: OrderedDictionary<String, String> = [:]
        for entry in contained(object, EcoreFeatureName.details.rawValue) {
            details[string(entry, EcoreFeatureName.key.rawValue) ?? ""] =
                string(entry, EcoreFeatureName.value.rawValue) ?? ""
        }
        let references = targets(object.eGet(EcoreFeatureName.references.rawValue)).map {
            target -> EAnnotationReference in
            switch target {
            case .local(let identifier): return .local(identifier)
            case .external(let proxy): return localProxies[proxy].map { .local($0) } ?? .external(proxy)
            }
        }
        return EAnnotation(
            id: object.id, source: string(object, EcoreFeatureName.source.rawValue) ?? "",
            orderedDetails: details, eAnnotations: annotations(of: object), references: references,
            contents: contained(object, EcoreFeatureName.contents.rawValue))
    }

    /// The converted annotations of an element.
    private func annotations(forID identifier: EUUID) -> [EAnnotation] {
        annotationMap[identifier] ?? []
    }

    // MARK: Conversion

    /// Converts a parsed package and everything it contains.
    ///
    /// - Parameters:
    ///   - root: The parsed package.
    /// - Returns: The native package.
    /// - Throws: ``XMIError`` if an element cannot be converted and failures are not ignored.
    mutating func convert(_ root: DynamicEObject) throws -> EPackage {
        convertAnnotations()
        var classObjects: [DynamicEObject] = []
        try convertDataTypes(of: root, classObjects: &classObjects)
        buildClasses(classObjects)
        convertDataTypeParameters()
        let package = try assemble(root)
        return MetamodelLinker.relinked([package], externalClassifiers: externalClassifiers)[0]
    }

    /// The classifiers of other documents, by the identifier of the classifier.
    private var externalClassifiers: [EUUID: any EClassifier] {
        Dictionary(external.values.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
                    var eEnum = EEnum(
                        id: classifier.id, name: name,
                        literals: literals(of: classifier),
                        eAnnotations: annotations(forID: classifier.id))
                    eEnum.serialisable = flag(classifier, XMIAttribute.serializable.rawValue, true)
                    eEnum.instanceClassName = string(classifier, XMIAttribute.instanceClassName.rawValue)
                    eEnum.instanceTypeName = string(classifier, EcoreFeatureName.instanceTypeName.rawValue)
                    dataTypes[classifier.id] = eEnum
                    dataTypeObjects.append(classifier)
                } else {
                    try failMissingName()
                }
            case EcoreClassifier.eDataType.rawValue:
                if let name = string(classifier, XMIAttribute.name.rawValue) {
                    var dataType = EDataType(
                        id: classifier.id, name: name,
                        serialisable: flag(classifier, XMIAttribute.serializable.rawValue, true),
                        instanceClassName: string(classifier, XMIAttribute.instanceClassName.rawValue),
                        eAnnotations: annotations(forID: classifier.id))
                    dataType.instanceTypeName = string(classifier, EcoreFeatureName.instanceTypeName.rawValue)
                    dataTypes[classifier.id] = dataType
                    dataTypeObjects.append(classifier)
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
                literal: string(literal, XMIAttribute.literal.rawValue) ?? name,
                eAnnotations: annotations(forID: literal.id))
        }
    }

    /// Builds the classes with the features, operations, and supertypes they declare.
    ///
    /// The types and supertypes of the built classes are provisional; linking the finished
    /// package replaces them with snapshots of the canonical classes.
    private mutating func buildClasses(_ objects: [DynamicEObject]) {
        for object in objects {
            guard let name = string(object, XMIAttribute.name.rawValue) else { continue }
            var eClass = EClass(
                id: object.id, name: name,
                isAbstract: flag(object, XMIAttribute.abstract.rawValue, false),
                isInterface: flag(object, XMIAttribute.interface.rawValue, false),
                eAnnotations: annotations(forID: object.id),
                instanceClassName: string(object, XMIAttribute.instanceClassName.rawValue))
            eClass.instanceTypeName = string(object, EcoreFeatureName.instanceTypeName.rawValue)
            classes[object.id] = eClass
        }
        let provisional = classes
        for object in objects {
            if let converted = convertClass(object, previous: provisional) {
                classes[object.id] = converted
            }
        }
    }

    private func convertClass(_ object: DynamicEObject, previous: [EUUID: EClass]) -> EClass? {
        guard var result = previous[object.id] else { return nil }
        result.eSuperTypes = targets(object.eGet(EcoreFeatureName.eSuperTypes.rawValue)).compactMap {
            switch $0 {
            case .local(let identifier):
                return previous[identifier]
                    ?? (EcorePackage.classifier(id: identifier) as? EClass)
            case .external(let proxy):
                return external[proxy] as? EClass
            }
        }
        result.eTypeParameters = typeParameters(of: object, previous: previous)
        let parameterTable = Dictionary(
            result.eTypeParameters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        result.eGenericSuperTypes = contained(object, EcoreFeatureName.eGenericSuperTypes.rawValue)
            .map { genericType($0, previous: previous) }
        result.eStructuralFeatures = contained(
            object, EcoreFeatureName.eStructuralFeatures.rawValue
        ).compactMap { convertFeature($0, previous: previous, parameters: parameterTable) }
        result.eOperations = contained(object, EcoreFeatureName.eOperations.rawValue)
            .compactMap { convertOperation($0, previous: previous, classParameters: parameterTable) }
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

    // MARK: Generics

    /// The placeholder that stands for a classifier that cannot be loaded.
    private func placeholder(for proxy: ResourceProxy) -> any EClassifier {
        let name = proxy.fragment.split(separator: CrossReferenceSyntax.segmentSeparator).last
            .map(String.init) ?? proxy.fragment
        let identifier = ReflectiveValues.derivedID(
            from: EcoreLoadOptions.placeholderNamespace, key: proxy.uri + "#" + proxy.fragment)
        if proxy.qualifier == "\(EcorePackage.nsPrefix):\(EcoreClassifier.eClass.rawValue)" {
            return EClass(id: identifier, name: name)
        }
        return EDataType(id: identifier, name: name)
    }

    /// The type of a typed element, honouring the options for references that cannot be loaded.
    private func declaredType(_ object: DynamicEObject, previous: [EUUID: EClass]) -> (any EClassifier)? {
        let value = object.eGet(XMIAttribute.eType.rawValue)
        if options.unresolvedReferences == .keepAsProxies {
            return classifierOrPlaceholder(value, previous: previous)
        }
        return classifier(value, previous: previous)
    }

    /// The classifier that a type reference names, or a placeholder if it cannot be loaded.
    private func classifierOrPlaceholder(
        _ value: (any EcoreValue)?, previous: [EUUID: EClass]
    ) -> (any EClassifier)? {
        if let found = classifier(value, previous: previous) { return found }
        guard let target = targets(value).first, case .external(let proxy) = target else { return nil }
        return placeholder(for: proxy)
    }

    /// Converts a parsed generic type with its arguments and bounds.
    private func genericType(_ object: DynamicEObject, previous: [EUUID: EClass]) -> EGenericType {
        let parameter = targets(object.eGet(EcoreFeatureName.eTypeParameter.rawValue)).compactMap {
            target -> EUUID? in
            if case .local(let identifier) = target { return identifier }
            return nil
        }.first
        return EGenericType(
            id: object.id,
            eClassifier: classifierOrPlaceholder(
                object.eGet(EcoreFeatureName.eClassifier.rawValue), previous: previous),
            eTypeParameter: parameter,
            eTypeArguments: contained(object, EcoreFeatureName.eTypeArguments.rawValue)
                .map { genericType($0, previous: previous) },
            eUpperBound: contained(object, EcoreFeatureName.eUpperBound.rawValue).first
                .map { genericType($0, previous: previous) },
            eLowerBound: contained(object, EcoreFeatureName.eLowerBound.rawValue).first
                .map { genericType($0, previous: previous) })
    }

    /// Converts the type parameters that an object declares.
    private func typeParameters(of object: DynamicEObject, previous: [EUUID: EClass]) -> [ETypeParameter] {
        contained(object, EcoreFeatureName.eTypeParameters.rawValue).map { parameter in
            var result = ETypeParameter(
                id: parameter.id, name: string(parameter, XMIAttribute.name.rawValue) ?? "",
                eAnnotations: annotations(forID: parameter.id))
            result.eBounds = contained(parameter, EcoreFeatureName.eBounds.rawValue)
                .map { genericType($0, previous: previous) }
            return result
        }
    }

    /// Gives the data types and enumerations their type parameters.
    private mutating func convertDataTypeParameters() {
        for object in dataTypeObjects {
            let parameters = typeParameters(of: object, previous: classes)
            guard !parameters.isEmpty else { continue }
            if var dataType = dataTypes[object.id] as? EDataType {
                dataType.eTypeParameters = parameters
                dataTypes[object.id] = dataType
            } else if var eEnum = dataTypes[object.id] as? EEnum {
                eEnum.eTypeParameters = parameters
                dataTypes[object.id] = eEnum
            }
        }
    }

    /// The classifier that a generic type erases to, used as the `eType` of the element that holds it.
    private func rawType(of type: EGenericType, parameters: [EUUID: ETypeParameter]) -> (any EClassifier)? {
        if let classifier = type.eClassifier { return classifier }
        if let identifier = type.eTypeParameter, let parameter = parameters[identifier],
            let bound = parameter.eBounds.first, let classifier = bound.eClassifier
        {
            return classifier
        }
        return EcorePackage.dataType(.eJavaObject)
    }

    private func convertFeature(
        _ object: DynamicEObject, previous: [EUUID: EClass], parameters: [EUUID: ETypeParameter]
    ) -> (any EStructuralFeature)? {
        guard let name = string(object, XMIAttribute.name.rawValue) else { return nil }
        let generic = contained(object, EcoreFeatureName.eGenericType.rawValue).first
            .map { genericType($0, previous: previous) }
        let declared = declaredType(object, previous: previous)
            ?? generic.flatMap { $0.eTypeParameter == nil ? $0.eClassifier : nil }
        let resolved = declared ?? generic.flatMap { rawType(of: $0, parameters: parameters) }
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
            var attribute = EAttribute(
                id: object.id, name: name, eType: resolved ?? Self.defaultAttributeType,
                lowerBound: lowerBound, upperBound: upperBound, changeable: changeable,
                volatile: volatile, transient: transient,
                defaultValueLiteral: string(object, XMIAttribute.defaultValueLiteral.rawValue),
                isID: flag(object, XMIAttribute.iD.rawValue, false),
                eAnnotations: annotations(forID: object.id), ordered: ordered,
                unique: unique, unsettable: unsettable, derived: derived)
            attribute.eGenericType = generic.flatMap { $0.isParameterised ? $0 : nil }
            return attribute
        case EcoreClassifier.eReference.rawValue:
            let opposite = targets(object.eGet(XMIAttribute.eOpposite.rawValue)
                ?? object.eGet(XMIAttribute.opposite.rawValue)).compactMap { target -> EUUID? in
                    if case .local(let identifier) = target { return identifier }
                    return nil
                }.first
            let oppositeContains = opposite.flatMap { objects[$0] }
                .map { flag($0, XMIAttribute.containment.rawValue, false) } ?? false
            var reference = EReference(
                id: object.id, name: name, eType: resolved ?? Self.defaultReferenceType,
                lowerBound: lowerBound, upperBound: upperBound, changeable: changeable,
                volatile: volatile, transient: transient,
                containment: flag(object, XMIAttribute.containment.rawValue, false),
                opposite: opposite,
                resolveProxies: flag(object, XMIAttribute.resolveProxies.rawValue, true),
                eAnnotations: annotations(forID: object.id),
                ordered: ordered, unique: unique, unsettable: unsettable, derived: derived,
                container: oppositeContains)
            reference.eGenericType = generic.flatMap { $0.isParameterised ? $0 : nil }
            reference.eKeys = targets(object.eGet(EcoreFeatureName.eKeys.rawValue)).compactMap { target in
                if case .local(let identifier) = target { return identifier }
                return nil
            }
            return reference
        default:
            return nil
        }
    }

    private func convertOperation(
        _ object: DynamicEObject, previous: [EUUID: EClass], classParameters: [EUUID: ETypeParameter]
    ) -> EOperation? {
        guard let name = string(object, XMIAttribute.name.rawValue) else { return nil }
        let operationParameters = typeParameters(of: object, previous: previous)
        let parameterTable = classParameters.merging(
            operationParameters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let parameters = contained(object, EcoreFeatureName.eParameters.rawValue)
            .compactMap { parameter -> EParameter? in
                guard let parameterName = string(parameter, XMIAttribute.name.rawValue) else { return nil }
                let generic = contained(parameter, EcoreFeatureName.eGenericType.rawValue).first
                    .map { genericType($0, previous: previous) }
                var type = declaredType(parameter, previous: previous)
                if type == nil, let generic { type = rawType(of: generic, parameters: parameterTable) }
                var result = EParameter(
                    id: parameter.id, name: parameterName, eType: type,
                    lowerBound: number(parameter, XMIAttribute.lowerBound.rawValue, 0),
                    upperBound: number(parameter, XMIAttribute.upperBound.rawValue, 1),
                    ordered: flag(parameter, XMIAttribute.ordered.rawValue, true),
                    unique: flag(parameter, XMIAttribute.unique.rawValue, true),
                    eAnnotations: annotations(forID: parameter.id))
                result.eGenericType = generic.flatMap { $0.isParameterised ? $0 : nil }
                return result
            }
        let operationGeneric = contained(object, EcoreFeatureName.eGenericType.rawValue).first
            .map { genericType($0, previous: previous) }
        var operationType = declaredType(object, previous: previous)
        if operationType == nil, let operationGeneric {
            operationType = rawType(of: operationGeneric, parameters: parameterTable)
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
        var result = EOperation(
            id: object.id, name: name, eType: operationType,
            lowerBound: number(object, XMIAttribute.lowerBound.rawValue, 0),
            upperBound: number(object, XMIAttribute.upperBound.rawValue, 1),
            ordered: flag(object, XMIAttribute.ordered.rawValue, true),
            unique: flag(object, XMIAttribute.unique.rawValue, true),
            eParameters: parameters, eExceptions: exceptions,
            eAnnotations: annotations(forID: object.id))
        result.eGenericType = operationGeneric.flatMap { $0.isParameterised ? $0 : nil }
        result.eTypeParameters = operationParameters
        result.eGenericExceptions = contained(object, EcoreFeatureName.eGenericExceptions.rawValue)
            .map { genericType($0, previous: previous) }
        return result
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
            eClassifiers: classifiers, eSubpackages: subpackages,
            eAnnotations: annotations(forID: package.id))
    }
}
