//
// JSONMetamodelWriter.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// Writes native metamodel packages as a JSON document.
///
/// The document holds the same information as the `.ecore` document that ``XMISerializer``
/// writes for the packages, in the layout that emfjson uses for Ecore models.
struct JSONMetamodelWriter {
    /// The members of the object that is being built.
    private typealias Members = [OrderedJSON.Member]

    /// The root packages, in document order.
    private let roots: [EPackage]

    /// The URI against which references to other documents are made relative.
    private let documentURI: String?

    /// The fragment of every element of the document, by identifier.
    private var fragments: [EUUID: String] = [:]

    /// The metaclass of every element of the document, by identifier.
    private var metaclasses: [EUUID: EcoreClassifier] = [:]

    /// Prepares to write root packages.
    ///
    /// - Parameters:
    ///   - roots: The root packages, in document order.
    ///   - documentURI: The URI that the document will have, or `nil` to use the URI of the
    ///     document from which the first package was loaded.
    init(roots: [EPackage], documentURI: String?) {
        self.roots = roots
        self.documentURI = documentURI ?? roots.first?.origin?.documentURI
        for (index, root) in roots.enumerated() {
            let rootFragments = EcoreFragment.fragments(in: root, rootIndex: roots.count == 1 ? nil : index)
            fragments.merge(rootFragments) { first, _ in first }
            indexMetaclasses(of: .package(root))
        }
    }

    /// Records the metaclass of an element and of everything it contains.
    ///
    /// - Parameter element: The element.
    private mutating func indexMetaclasses(of element: EcoreElement) {
        metaclasses[element.id] = Self.metaclass(of: element)
        for child in element.children { indexMetaclasses(of: child.element) }
    }

    /// The metaclass of an element.
    ///
    /// - Parameter element: The element.
    /// - Returns: Its metaclass.
    private static func metaclass(of element: EcoreElement) -> EcoreClassifier {
        switch element {
        case .package: return .ePackage
        case .eClass: return .eClass
        case .dataType: return .eDataType
        case .eEnum: return .eEnum
        case .literal: return .eEnumLiteral
        case .attribute: return .eAttribute
        case .reference: return .eReference
        case .operation: return .eOperation
        case .parameter: return .eParameter
        case .annotation: return .eAnnotation
        case .typeParameter: return .eTypeParameter
        case .detail: return .eStringToStringMapEntry
        }
    }

    /// The document: the object of the only root package, or an array of the root packages.
    var document: OrderedJSON {
        let packages = roots.map { package($0) }
        return packages.count == 1 ? packages[0] : .array(packages)
    }

    // MARK: Packages

    /// The JSON object of a package with everything it contains.
    ///
    /// - Parameter package: The package.
    /// - Returns: The object.
    private func package(_ package: EPackage) -> OrderedJSON {
        var members = header(.ePackage, name: package.name)
        members.append(member(.nsURI, .string(package.nsURI)))
        members.append(member(.nsPrefix, .string(package.nsPrefix)))
        append(.eAnnotations, package.eAnnotations.map { annotation($0) }, to: &members)
        append(.eClassifiers, package.eClassifiers.compactMap { classifier($0) }, to: &members)
        append(.eSubpackages, package.eSubpackages.map { self.package($0) }, to: &members)
        return .object(members)
    }

    // MARK: Classifiers

    /// The JSON object of a class, enumeration or data type.
    ///
    /// - Parameter classifier: The classifier.
    /// - Returns: The object, or `nil` for any other kind of classifier.
    private func classifier(_ classifier: any EClassifier) -> OrderedJSON? {
        switch classifier {
        case let eClass as EClass: return self.eClass(eClass)
        case let eEnum as EEnum: return self.eEnum(eEnum)
        case let dataType as EDataType: return self.dataType(dataType)
        default: return nil
        }
    }

    /// The JSON object of a class with its features, operations and type parameters.
    ///
    /// Plain supertypes are written as `eSuperTypes` references; supertypes with type arguments
    /// as `eGenericSuperTypes`.
    ///
    /// - Parameter eClass: The class.
    /// - Returns: The object.
    private func eClass(_ eClass: EClass) -> OrderedJSON {
        var members = header(.eClass, name: eClass.name)
        if let name = eClass.instanceClassName { members.append(member(.instanceClassName, .string(name))) }
        if let name = eClass.instanceTypeName { members.append(member(.instanceTypeName, .string(name))) }
        if eClass.isAbstract { members.append(member(.abstract, .boolean(true))) }
        if eClass.isInterface { members.append(member(.interface, .boolean(true))) }
        let genericSuperTypes = eClass.eGenericSuperTypes.filter(\.isParameterised)
        if genericSuperTypes.isEmpty {
            let superTypes = eClass.eSuperTypes.map { reference(to: $0, declaredType: .eClass) }
                + retainedReferences(of: eClass.id, feature: .eSuperTypes)
            append(.eSuperTypes, superTypes, to: &members)
        }
        append(.eAnnotations, eClass.eAnnotations.map { annotation($0) }, to: &members)
        append(.eTypeParameters, eClass.eTypeParameters.map { typeParameter($0) }, to: &members)
        append(.eOperations, eClass.eOperations.map { operation($0) }, to: &members)
        append(.eStructuralFeatures, eClass.eStructuralFeatures.compactMap { feature($0) }, to: &members)
        if !genericSuperTypes.isEmpty {
            append(.eGenericSuperTypes, eClass.eGenericSuperTypes.map { genericType($0) }, to: &members)
        }
        return .object(members)
    }

    /// The JSON object of an enumeration with its literals.
    ///
    /// - Parameter eEnum: The enumeration.
    /// - Returns: The object.
    private func eEnum(_ eEnum: EEnum) -> OrderedJSON {
        var members = header(.eEnum, name: eEnum.name)
        if let name = eEnum.instanceClassName { members.append(member(.instanceClassName, .string(name))) }
        appendDataTypeFlags(instanceTypeName: eEnum.instanceTypeName, serialisable: eEnum.serialisable, to: &members)
        append(.eAnnotations, eEnum.eAnnotations.map { annotation($0) }, to: &members)
        append(.eTypeParameters, eEnum.eTypeParameters.map { typeParameter($0) }, to: &members)
        append(.eLiterals, eEnum.literals.map { literal($0) }, to: &members)
        return .object(members)
    }

    /// The JSON object of an enumeration literal.
    ///
    /// The value is written unless it is zero, and the literal text unless it is the name.
    ///
    /// - Parameter literal: The literal.
    /// - Returns: The object.
    private func literal(_ literal: EEnumLiteral) -> OrderedJSON {
        var members = header(.eEnumLiteral, name: literal.name)
        if literal.value != 0 { members.append(member(.value, .integer(literal.value))) }
        if let text = literal.literal, text != literal.name { members.append(member(.literal, .string(text))) }
        append(.eAnnotations, literal.eAnnotations.map { annotation($0) }, to: &members)
        return .object(members)
    }

    /// The JSON object of a data type.
    ///
    /// - Parameter dataType: The data type.
    /// - Returns: The object.
    private func dataType(_ dataType: EDataType) -> OrderedJSON {
        var members = header(.eDataType, name: dataType.name)
        if let name = dataType.instanceClassName { members.append(member(.instanceClassName, .string(name))) }
        appendDataTypeFlags(
            instanceTypeName: dataType.instanceTypeName, serialisable: dataType.serialisable, to: &members)
        append(.eAnnotations, dataType.eAnnotations.map { annotation($0) }, to: &members)
        append(.eTypeParameters, dataType.eTypeParameters.map { typeParameter($0) }, to: &members)
        return .object(members)
    }

    /// Appends the instance type name and the serialisability of a data type or enumeration.
    ///
    /// - Parameters:
    ///   - instanceTypeName: The instance type name, if any.
    ///   - serialisable: Whether the type is serialisable; only `false` is written.
    ///   - members: The members of the object being built.
    private func appendDataTypeFlags(instanceTypeName: String?, serialisable: Bool, to members: inout Members) {
        if let instanceTypeName { members.append(member(.instanceTypeName, .string(instanceTypeName))) }
        if !serialisable { members.append(member(.serializable, .boolean(false))) }
    }

    // MARK: Features and operations

    /// The JSON object of an attribute or reference.
    ///
    /// - Parameter feature: The structural feature.
    /// - Returns: The object, or `nil` for any other kind of feature.
    private func feature(_ feature: any EStructuralFeature) -> OrderedJSON? {
        if let attribute = feature as? EAttribute {
            var members = header(.eAttribute, name: attribute.name)
            appendFeatureMembers(of: attribute, to: &members)
            if attribute.isID { members.append(member(.iD, .boolean(true))) }
            appendContents(
                annotations: attribute.eAnnotations, generic: explicitGenericType(attribute.eGenericType), to: &members)
            return .object(members)
        }
        guard let reference = feature as? EReference else { return nil }
        var members = header(.eReference, name: reference.name)
        appendFeatureMembers(of: reference, to: &members)
        if reference.containment { members.append(member(.containment, .boolean(true))) }
        if !reference.resolveProxies { members.append(member(.resolveProxies, .boolean(false))) }
        if let opposite = reference.opposite, let fragment = fragments[opposite] {
            members.append(member(.eOpposite, referenceObject(fragment)))
        } else if let proxy = origin?.externalOpposites[reference.id] {
            members.append(member(.eOpposite, referenceObject(external(proxy))))
        }
        let keys = reference.eKeys.compactMap { fragments[$0].map { referenceObject($0) } }
            + retainedReferences(of: reference.id, feature: .eKeys)
        append(.eKeys, keys, to: &members)
        appendContents(
            annotations: reference.eAnnotations, generic: explicitGenericType(reference.eGenericType), to: &members)
        return .object(members)
    }

    /// Appends the multiplicity, type and flags that attributes and references share.
    ///
    /// - Parameters:
    ///   - feature: The attribute or reference.
    ///   - members: The members of the object being built.
    private func appendFeatureMembers(of feature: some JSONWritableFeature, to members: inout Members) {
        appendMultiplicity(ordered: feature.ordered, unique: feature.unique, lowerBound: feature.lowerBound,
            upperBound: feature.upperBound, to: &members)
        if explicitGenericType(feature.eGenericType) == nil {
            members.append(member(.eType, typeReference(of: feature.id, type: feature.eType)))
        }
        if !feature.changeable { members.append(member(.changeable, .boolean(false))) }
        if feature.volatile { members.append(member(.volatile, .boolean(true))) }
        if feature.transient { members.append(member(.transient, .boolean(true))) }
        if let literal = feature.defaultValueLiteral { members.append(member(.defaultValueLiteral, .string(literal))) }
        if feature.unsettable { members.append(member(.unsettable, .boolean(true))) }
        if feature.derived { members.append(member(.derived, .boolean(true))) }
    }

    /// Appends the flags and bounds of a typed element that differ from their defaults.
    ///
    /// - Parameters:
    ///   - ordered: Whether the element is ordered.
    ///   - unique: Whether the element is unique.
    ///   - lowerBound: The lower bound.
    ///   - upperBound: The upper bound.
    ///   - members: The members of the object being built.
    private func appendMultiplicity(
        ordered: Bool, unique: Bool, lowerBound: Int, upperBound: Int, to members: inout Members
    ) {
        if !ordered { members.append(member(.ordered, .boolean(false))) }
        if !unique { members.append(member(.unique, .boolean(false))) }
        if lowerBound != 0 { members.append(member(.lowerBound, .integer(lowerBound))) }
        if upperBound != 1 { members.append(member(.upperBound, .integer(upperBound))) }
    }

    /// Appends the annotations and the generic type of a typed element.
    ///
    /// - Parameters:
    ///   - annotations: The annotations of the element.
    ///   - generic: The generic type to write, if the element has a parameterised one.
    ///   - members: The members of the object being built.
    private func appendContents(annotations: [EAnnotation], generic: EGenericType?, to members: inout Members) {
        append(.eAnnotations, annotations.map { annotation($0) }, to: &members)
        if let generic { members.append(member(.eGenericType, genericType(generic))) }
    }

    /// The JSON object of an operation with its parameters, exceptions and type parameters.
    ///
    /// - Parameter operation: The operation.
    /// - Returns: The object.
    private func operation(_ operation: EOperation) -> OrderedJSON {
        var members = header(.eOperation, name: operation.name)
        appendTypedMembers(
            id: operation.id, ordered: operation.ordered, unique: operation.unique, lowerBound: operation.lowerBound,
            upperBound: operation.upperBound, type: operation.eType, generic: operation.eGenericType, to: &members)
        if operation.eGenericExceptions.isEmpty {
            let exceptions = operation.eExceptions.map { reference(to: $0, declaredType: .eClassifier) }
                + retainedReferences(of: operation.id, feature: .eExceptions)
            append(.eExceptions, exceptions, to: &members)
        }
        append(.eAnnotations, operation.eAnnotations.map { annotation($0) }, to: &members)
        if let generic = explicitGenericType(operation.eGenericType) {
            members.append(member(.eGenericType, genericType(generic)))
        }
        append(.eTypeParameters, operation.eTypeParameters.map { typeParameter($0) }, to: &members)
        append(.eParameters, operation.eParameters.map { parameter($0) }, to: &members)
        append(.eGenericExceptions, operation.eGenericExceptions.map { genericType($0) }, to: &members)
        return .object(members)
    }

    /// The JSON object of an operation parameter.
    ///
    /// - Parameter parameter: The parameter.
    /// - Returns: The object.
    private func parameter(_ parameter: EParameter) -> OrderedJSON {
        var members = header(.eParameter, name: parameter.name)
        appendTypedMembers(
            id: parameter.id, ordered: parameter.ordered, unique: parameter.unique, lowerBound: parameter.lowerBound,
            upperBound: parameter.upperBound, type: parameter.eType, generic: parameter.eGenericType, to: &members)
        appendContents(
            annotations: parameter.eAnnotations, generic: explicitGenericType(parameter.eGenericType), to: &members)
        return .object(members)
    }

    /// Appends the multiplicity and the type of an operation or parameter.
    ///
    /// - Parameters:
    ///   - id: The identifier of the element, which names a type that could not be loaded.
    ///   - ordered: Whether the element is ordered.
    ///   - unique: Whether the element is unique.
    ///   - lowerBound: The lower bound.
    ///   - upperBound: The upper bound.
    ///   - type: The type of the element, if any.
    ///   - generic: The generic type of the element, if any.
    ///   - members: The members of the object being built.
    private func appendTypedMembers(
        id: EUUID, ordered: Bool, unique: Bool, lowerBound: Int, upperBound: Int, type: (any EClassifier)?,
        generic: EGenericType?, to members: inout Members
    ) {
        appendMultiplicity(
            ordered: ordered, unique: unique, lowerBound: lowerBound, upperBound: upperBound, to: &members)
        if explicitGenericType(generic) == nil, let type {
            members.append(member(.eType, typeReference(of: id, type: type)))
        }
    }

    // MARK: Generic types

    /// The generic type of a typed element if it says more than its classifier.
    ///
    /// - Parameter type: The generic type of the element, if any.
    /// - Returns: The generic type if it is parameterised, otherwise `nil`.
    private func explicitGenericType(_ type: EGenericType?) -> EGenericType? {
        type.flatMap { $0.isParameterised ? $0 : nil }
    }

    /// The JSON object of a type parameter with its bounds.
    ///
    /// - Parameter parameter: The type parameter.
    /// - Returns: The object.
    private func typeParameter(_ parameter: ETypeParameter) -> OrderedJSON {
        var members = header(.eTypeParameter, name: parameter.name)
        append(.eAnnotations, parameter.eAnnotations.map { annotation($0) }, to: &members)
        append(.eBounds, parameter.eBounds.map { genericType($0) }, to: &members)
        return .object(members)
    }

    /// The JSON object of a generic type with its classifier or type parameter, arguments and bounds.
    ///
    /// - Parameter type: The generic type.
    /// - Returns: The object.
    private func genericType(_ type: EGenericType) -> OrderedJSON {
        var members = [member(JSONSyntax.eClassKey, .string(JSONMetamodelSyntax.className(.eGenericType)))]
        if let parameter = type.eTypeParameter, let fragment = fragments[parameter] {
            members.append(member(.eTypeParameter, referenceObject(fragment)))
        } else if let proxy = origin?.unresolvedReferences[type.id]?[.eTypeParameter]?.first {
            members.append(member(.eTypeParameter, referenceObject(external(proxy))))
        }
        if let classifier = type.eClassifier {
            members.append(member(.eClassifier, typeReference(of: type.id, type: classifier)))
        }
        let contained = type.containedTypes
        if let upper = contained.first(where: { $0.feature == .eUpperBound }) {
            members.append(member(.eUpperBound, genericType(upper.object)))
        }
        let arguments = contained.filter { $0.feature == .eTypeArguments }.map { genericType($0.object) }
        append(.eTypeArguments, arguments, to: &members)
        if let lower = contained.first(where: { $0.feature == .eLowerBound }) {
            members.append(member(.eLowerBound, genericType(lower.object)))
        }
        return .object(members)
    }

    // MARK: Annotations

    /// The JSON object of an annotation with its references, details, nested annotations and contents.
    ///
    /// - Parameter annotation: The annotation.
    /// - Returns: The object.
    private func annotation(_ annotation: EAnnotation) -> OrderedJSON {
        var members = [member(JSONSyntax.eClassKey, .string(JSONMetamodelSyntax.className(.eAnnotation)))]
        if !annotation.source.isEmpty { members.append(member(.source, .string(annotation.source))) }
        let references = annotation.references.compactMap { reference -> OrderedJSON? in
            switch reference {
            case .local(let identifier):
                return fragments[identifier].map { referenceObject($0, metaclass: metaclasses[identifier]) }
            case .external(let proxy):
                let fragment = Self.bareFragment(proxy.fragment)
                if proxy.uri.isEmpty || proxy.uri == documentURI { return referenceObject(fragment) }
                return referenceObject(external(proxy))
            }
        }
        append(.references, references, to: &members)
        append(.eAnnotations, annotation.eAnnotations.map { self.annotation($0) }, to: &members)
        let entries = annotation.detailEntries
        if !entries.isEmpty {
            let details = entries.map { OrderedJSON.Member(key: $0.key, value: .string($0.value)) }
            members.append(member(.details, .object(details)))
        }
        append(.contents, annotation.contents.map { content($0) }, to: &members)
        return .object(members)
    }

    /// The JSON object of an object that an annotation contains: its class and its
    /// single-valued text, Boolean and integer attributes.
    ///
    /// - Parameter content: The contained object.
    /// - Returns: The object.
    private func content(_ content: any EObject) -> OrderedJSON {
        guard let metaclass = content.eClass as? EClass else { return .object([]) }
        let className = EcoreClassifier(rawValue: metaclass.name).map { JSONMetamodelSyntax.className($0) }
            ?? metaclass.name
        var members = [member(JSONSyntax.eClassKey, .string(className))]
        for attribute in Self.attributes(of: metaclass) where !attribute.transient {
            switch content.eGet(attribute) {
            case let text as String: members.append(OrderedJSON.Member(key: attribute.name, value: .string(text)))
            case let flag as Bool: members.append(OrderedJSON.Member(key: attribute.name, value: .boolean(flag)))
            case let number as Int: members.append(OrderedJSON.Member(key: attribute.name, value: .integer(number)))
            default: break
            }
        }
        return .object(members)
    }

    /// The attributes of a class with those of its supertypes first, as EMF lists features.
    ///
    /// - Parameter eClass: The class.
    /// - Returns: The attributes, each once.
    private static func attributes(of eClass: EClass) -> [EAttribute] {
        var seen = Set<EUUID>()
        var result: [EAttribute] = []
        func collect(_ current: EClass) {
            for superType in current.eSuperTypes { collect(superType) }
            for case let attribute as EAttribute in current.eStructuralFeatures
            where seen.insert(attribute.id).inserted {
                result.append(attribute)
            }
        }
        collect(eClass)
        return result
    }

    // MARK: References

    /// The record of how the first package was loaded.
    private var origin: EPackageOrigin? { roots.first?.origin }

    /// A fragment without its leading `#`.
    ///
    /// - Parameter fragment: The fragment, with or without a leading `#`.
    /// - Returns: The fragment without it.
    private static func bareFragment(_ fragment: String) -> String {
        fragment.first == CrossReferenceSyntax.fragmentSeparator ? String(fragment.dropFirst()) : fragment
    }

    /// The text of a reference into another document, relative to the written document.
    ///
    /// - Parameter proxy: The reference.
    /// - Returns: The document URI, a `#`, and the fragment.
    private func external(_ proxy: ResourceProxy) -> String {
        let location = documentURI.map { URIReference.relativise(proxy.uri, against: $0) } ?? proxy.uri
        return location + String(CrossReferenceSyntax.fragmentSeparator) + Self.bareFragment(proxy.fragment)
    }

    /// A `$ref` object, preceded by the metaclass of its target if it is known.
    ///
    /// - Parameters:
    ///   - text: The reference text.
    ///   - metaclass: The metaclass of the target to name, or `nil` to name none.
    /// - Returns: The reference object.
    private func referenceObject(_ text: String, metaclass: EcoreClassifier? = nil) -> OrderedJSON {
        var members: Members = []
        if let metaclass {
            members.append(member(JSONSyntax.eClassKey, .string(JSONMetamodelSyntax.className(metaclass))))
        }
        members.append(member(JSONSyntax.referenceKey, .string(text)))
        return .object(members)
    }

    /// The metaclass of a classifier.
    ///
    /// - Parameter classifier: The classifier.
    /// - Returns: `EEnum`, `EDataType` or `EClass`.
    private static func metaclass(of classifier: any EClassifier) -> EcoreClassifier {
        switch classifier {
        case is EEnum: return .eEnum
        case is EDataType: return .eDataType
        default: return .eClass
        }
    }

    /// Whether a classifier that is not part of the written packages is named like a class or
    /// data type of Ecore itself.
    ///
    /// - Parameter classifier: The classifier.
    /// - Returns: `true` if the classifier stands for one of Ecore.
    private func namesEcoreBuiltIn(_ classifier: any EClassifier) -> Bool {
        if origin?.externalReferences[classifier.id] != nil { return false }
        if classifier is EClass { return EcoreClassifier(rawValue: classifier.name) != nil }
        return EcoreDataType(rawValue: classifier.name) != nil
    }

    /// The reference to a classifier.
    ///
    /// A classifier of the document is referred to by its fragment, a class or data type of
    /// Ecore by the Ecore namespace URI, and a classifier of another document by that
    /// document's URI. A classifier whose metaclass differs from the declared type of the
    /// feature names its metaclass.
    ///
    /// - Parameters:
    ///   - classifier: The classifier.
    ///   - declaredType: The declared type of the referring feature.
    /// - Returns: The reference object.
    private func reference(to classifier: any EClassifier, declaredType: EcoreClassifier) -> OrderedJSON {
        let metaclass = Self.metaclass(of: classifier)
        let qualifier = metaclass == declaredType ? nil : metaclass
        if let fragment = fragments[classifier.id] { return referenceObject(fragment, metaclass: qualifier) }
        if EcorePackage.classifier(id: classifier.id) != nil || namesEcoreBuiltIn(classifier) {
            let text = EcorePackage.nsURI + JSONSyntax.classFragmentPrefix + classifier.name
            return referenceObject(text, metaclass: qualifier)
        }
        if let proxy = origin?.externalReferences[classifier.id] {
            return referenceObject(external(proxy), metaclass: qualifier)
        }
        return referenceObject(CrossReferenceSyntax.fragmentPathPrefix + classifier.name, metaclass: qualifier)
    }

    /// The reference to the type of a typed element.
    ///
    /// A type of another document that could not be loaded is written as it was read.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the typed element or generic type.
    ///   - type: The type that the element holds.
    /// - Returns: The reference object.
    private func typeReference(of identifier: EUUID, type: any EClassifier) -> OrderedJSON {
        guard let proxy = origin?.unresolvedTypes[identifier] else {
            return reference(to: type, declaredType: .eClassifier)
        }
        let metaclass = proxy.qualifier.flatMap { JSONMetamodelSyntax.metaclass(qualifier: $0) }
        return referenceObject(external(proxy), metaclass: metaclass)
    }

    /// The references of a feature to other documents that could not be loaded.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the referring element.
    ///   - feature: The reference feature.
    /// - Returns: The reference objects, in document order.
    private func retainedReferences(of identifier: EUUID, feature: EcoreFeatureName) -> [OrderedJSON] {
        (origin?.unresolvedReferences[identifier]?[feature] ?? []).map { referenceObject(external($0)) }
    }

    // MARK: Members

    /// The `eClass` member and the name of a named element.
    ///
    /// - Parameters:
    ///   - metaclass: The metaclass of the element.
    ///   - name: The name of the element.
    /// - Returns: The first members of the object of the element.
    private func header(_ metaclass: EcoreClassifier, name: String) -> Members {
        [member(JSONSyntax.eClassKey, .string(JSONMetamodelSyntax.className(metaclass))), member(.name, .string(name))]
    }

    /// A member with a given key.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - value: The value.
    /// - Returns: The member.
    private func member(_ key: String, _ value: OrderedJSON) -> OrderedJSON.Member {
        OrderedJSON.Member(key: key, value: value)
    }

    /// A member named after a feature.
    ///
    /// - Parameters:
    ///   - feature: The feature whose name is the key.
    ///   - value: The value.
    /// - Returns: The member.
    private func member(_ feature: EcoreFeatureName, _ value: OrderedJSON) -> OrderedJSON.Member {
        OrderedJSON.Member(key: feature.rawValue, value: value)
    }

    /// Appends a list feature unless it is empty.
    ///
    /// - Parameters:
    ///   - feature: The feature whose name is the key.
    ///   - values: The elements of the list.
    ///   - members: The members of the object being built.
    private func append(_ feature: EcoreFeatureName, _ values: [OrderedJSON], to members: inout Members) {
        if !values.isEmpty { members.append(member(feature, .array(values))) }
    }
}

/// The properties that attributes and references share when they are written.
private protocol JSONWritableFeature {
    /// The identifier of the feature.
    var id: EUUID { get }
    /// Whether the values of the feature are ordered.
    var ordered: Bool { get }
    /// Whether the values of the feature are unique.
    var unique: Bool { get }
    /// The lower bound of the feature.
    var lowerBound: Int { get }
    /// The upper bound of the feature.
    var upperBound: Int { get }
    /// The type of the feature.
    var eType: any EClassifier { get }
    /// The generic type of the feature, if it has one.
    var eGenericType: EGenericType? { get }
    /// Whether the value of the feature can be changed.
    var changeable: Bool { get }
    /// Whether the value of the feature is computed rather than stored.
    var volatile: Bool { get }
    /// Whether the value of the feature is left out when an object is saved.
    var transient: Bool { get }
    /// The default value of the feature as text, if it has one.
    var defaultValueLiteral: String? { get }
    /// Whether the feature distinguishes an unset value from its default.
    var unsettable: Bool { get }
    /// Whether the value of the feature is derived from other values.
    var derived: Bool { get }
}

extension EAttribute: JSONWritableFeature {}
extension EReference: JSONWritableFeature {}
