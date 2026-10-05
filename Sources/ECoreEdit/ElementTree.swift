//
// ElementTree.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import OrderedCollections

/// Reads and replaces the children that an element holds in one containment feature.
enum ElementTree {
    /// The elements that an element holds in a containment feature, in order.
    static func children(of element: EcoreElement, feature: EcoreFeatureName) -> [EcoreElement] {
        element.children.filter { $0.feature == feature }.map(\.element)
    }

    /// The number of elements that an element holds in a containment feature.
    static func count(of element: EcoreElement, feature: EcoreFeatureName) -> Int {
        element.children.reduce(0) { $0 + ($1.feature == feature ? 1 : 0) }
    }

    /// The element with the children of one feature replaced.
    ///
    /// - Returns: The new element, or `nil` if the element has no such feature or a child
    ///   does not suit it.
    static func replacing(
        _ feature: EcoreFeatureName, with children: [EcoreElement], in element: EcoreElement
    ) -> EcoreElement? {
        if feature == .eAnnotations { return withAnnotations(children, in: element) }
        switch (element, feature) {
        case (.package(var value), .eClassifiers):
            guard let classifiers = all(children, classifier) else { return nil }
            value.eClassifiers = classifiers
            return .package(value)
        case (.package(var value), .eSubpackages):
            guard let packages = all(children, package) else { return nil }
            value.eSubpackages = packages
            return .package(value)
        case (.eClass(var value), .eTypeParameters):
            guard let parameters = all(children, typeParameter) else { return nil }
            value.eTypeParameters = parameters
            return .eClass(value)
        case (.eEnum(var value), .eTypeParameters):
            guard let parameters = all(children, typeParameter) else { return nil }
            value.eTypeParameters = parameters
            return .eEnum(value)
        case (.dataType(var value), .eTypeParameters):
            guard let parameters = all(children, typeParameter) else { return nil }
            value.eTypeParameters = parameters
            return .dataType(value)
        case (.operation(var value), .eTypeParameters):
            guard let parameters = all(children, typeParameter) else { return nil }
            value.eTypeParameters = parameters
            return .operation(value)
        case (.eClass(var value), .eOperations):
            guard let operations = all(children, operation) else { return nil }
            value.eOperations = operations
            return .eClass(value)
        case (.eClass(var value), .eStructuralFeatures):
            guard let features = all(children, structuralFeature) else { return nil }
            value.eStructuralFeatures = features
            return .eClass(value)
        case (.eEnum(var value), .eLiterals):
            guard let literals = all(children, literal) else { return nil }
            value.literals = literals
            return .eEnum(value)
        case (.operation(var value), .eParameters):
            guard let parameters = all(children, parameter) else { return nil }
            value.eParameters = parameters
            return .operation(value)
        case (.annotation(var value), .details):
            guard let entries = all(children, detail) else { return nil }
            var details = OrderedDictionary<String, String>()
            for entry in entries { details[entry.key] = entry.value }
            guard details.count == entries.count else { return nil }
            value.details = details
            return .annotation(value)
        default:
            return nil
        }
    }

    private static func all<T>(_ elements: [EcoreElement], _ convert: (EcoreElement) -> T?) -> [T]? {
        var result: [T] = []
        result.reserveCapacity(elements.count)
        for element in elements {
            guard let value = convert(element) else { return nil }
            result.append(value)
        }
        return result
    }

    private static func classifier(_ element: EcoreElement) -> (any EClassifier)? {
        switch element {
        case .eClass(let value): return value
        case .dataType(let value): return value
        case .eEnum(let value): return value
        default: return nil
        }
    }

    private static func structuralFeature(_ element: EcoreElement) -> (any EStructuralFeature)? {
        switch element {
        case .attribute(let value): return value
        case .reference(let value): return value
        default: return nil
        }
    }

    private static func package(_ element: EcoreElement) -> EPackage? {
        if case .package(let value) = element { return value }
        return nil
    }

    private static func operation(_ element: EcoreElement) -> EOperation? {
        if case .operation(let value) = element { return value }
        return nil
    }

    private static func literal(_ element: EcoreElement) -> EEnumLiteral? {
        if case .literal(let value) = element { return value }
        return nil
    }

    private static func parameter(_ element: EcoreElement) -> EParameter? {
        if case .parameter(let value) = element { return value }
        return nil
    }

    private static func typeParameter(_ element: EcoreElement) -> ETypeParameter? {
        if case .typeParameter(let value) = element { return value }
        return nil
    }

    private static func detail(_ element: EcoreElement) -> EStringToStringMapEntry? {
        if case .detail(let value) = element { return value }
        return nil
    }

    private static func withAnnotations(_ children: [EcoreElement], in element: EcoreElement)
        -> EcoreElement?
    {
        var annotations: [EAnnotation] = []
        for child in children {
            guard case .annotation(let annotation) = child else { return nil }
            annotations.append(annotation)
        }
        switch element {
        case .package(var value): value.eAnnotations = annotations; return .package(value)
        case .eClass(var value): value.eAnnotations = annotations; return .eClass(value)
        case .dataType(var value): value.eAnnotations = annotations; return .dataType(value)
        case .eEnum(var value): value.eAnnotations = annotations; return .eEnum(value)
        case .literal(var value): value.eAnnotations = annotations; return .literal(value)
        case .attribute(var value): value.eAnnotations = annotations; return .attribute(value)
        case .reference(var value): value.eAnnotations = annotations; return .reference(value)
        case .operation(var value): value.eAnnotations = annotations; return .operation(value)
        case .parameter(var value): value.eAnnotations = annotations; return .parameter(value)
        case .annotation(var value): value.eAnnotations = annotations; return .annotation(value)
        case .typeParameter(var value): value.eAnnotations = annotations; return .typeParameter(value)
        case .detail: return nil
        }
    }
}

/// The classifiers of Ecore that edits refer to by identifier.
enum EcoreBuiltIns {
    /// Every classifier of the Ecore package by identifier.
    static let classifiers: [EUUID: any EClassifier] = {
        var result: [EUUID: any EClassifier] = [:]
        for classifier in EcorePackage.instance.eClassifiers { result[classifier.id] = classifier }
        return result
    }()

    /// The built-in data types, in the order of the Ecore package.
    static let dataTypes: [EDataType] = EcorePackage.instance.eClassifiers.compactMap { $0 as? EDataType }

    /// The metaclasses of Ecore, in the order of the Ecore package.
    static let metaClasses: [EClass] = EcorePackage.instance.eClassifiers.compactMap { $0 as? EClass }

    /// The classifier that replaces a deleted class as the type of a reference.
    static var replacementReferenceType: EClass {
        EcorePackage.metaClass(EcoreEditDefaults.replacementReferenceType)
    }

    /// The classifier that replaces a deleted classifier as the type of an attribute.
    static var replacementAttributeType: any EClassifier {
        EcorePackage.dataType(EcoreEditDefaults.replacementAttributeType) ?? EDataType(name: EcoreEditDefaults.replacementAttributeType.rawValue)
    }

    /// The type that new attributes have.
    static var newAttributeType: any EClassifier {
        EcorePackage.dataType(EcoreEditDefaults.newAttributeType) ?? EDataType(name: EcoreEditDefaults.newAttributeType.rawValue)
    }
}
