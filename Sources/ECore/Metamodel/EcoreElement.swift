//
// EcoreElement.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// A position in the containment tree: the feature that holds an element and its place in it.
public struct EcoreContainment: Sendable, Hashable {
    /// The identifier of the containing element.
    public let container: EUUID

    /// The containment feature of the container that holds the element.
    public let feature: EcoreFeatureName

    /// The zero-based position of the element within that feature.
    public let index: Int

    /// Creates a position.
    ///
    /// - Parameters:
    ///   - container: The identifier of the containing element.
    ///   - feature: The containment feature that holds the element.
    ///   - index: The zero-based position of the element within the feature.
    public init(container: EUUID, feature: EcoreFeatureName, index: Int) {
        self.container = container
        self.feature = feature
        self.index = index
    }
}

/// An element contained by another element, with the feature and position that hold it.
public struct EcoreChild: Sendable {
    /// The containment feature of the parent that holds the element.
    public let feature: EcoreFeatureName

    /// The zero-based position of the element within that feature.
    public let index: Int

    /// The contained element.
    public let element: EcoreElement

    /// Creates a child entry.
    ///
    /// - Parameters:
    ///   - feature: The containment feature of the parent that holds the element.
    ///   - index: The zero-based position of the element within the feature.
    ///   - element: The contained element.
    public init(feature: EcoreFeatureName, index: Int, element: EcoreElement) {
        self.feature = feature
        self.index = index
        self.element = element
    }
}

/// An element of a native metamodel, whatever its kind.
///
/// The native metamodel types are separate value types. This enumeration wraps each of them so
/// that code which handles elements generically (indexes, editors, and fragment paths) can
/// hold, compare, and traverse any of them uniformly. Every case holds the element exactly as
/// it appears in the metamodel; modifying a wrapped copy never changes the metamodel.
public enum EcoreElement: Sendable {
    /// A package.
    case package(EPackage)
    /// A class.
    case eClass(EClass)
    /// A data type that is neither a class nor an enumeration.
    case dataType(EDataType)
    /// An enumeration.
    case eEnum(EEnum)
    /// An enumeration literal.
    case literal(EEnumLiteral)
    /// An attribute.
    case attribute(EAttribute)
    /// A reference.
    case reference(EReference)
    /// An operation.
    case operation(EOperation)
    /// An operation parameter.
    case parameter(EParameter)
    /// An annotation.
    case annotation(EAnnotation)
    /// A key and value entry of an annotation.
    case detail(EStringToStringMapEntry)

    /// Wraps a metamodel object.
    ///
    /// - Parameter object: A package, classifier, feature, literal, operation, parameter,
    ///   annotation, or annotation detail entry.
    /// - Returns: The wrapped element, or `nil` for any other kind of object.
    public init?(_ object: any EObject) {
        switch object {
        case let value as EPackage: self = .package(value)
        case let value as EClass: self = .eClass(value)
        case let value as EEnum: self = .eEnum(value)
        case let value as EDataType: self = .dataType(value)
        case let value as EEnumLiteral: self = .literal(value)
        case let value as EAttribute: self = .attribute(value)
        case let value as EReference: self = .reference(value)
        case let value as EOperation: self = .operation(value)
        case let value as EParameter: self = .parameter(value)
        case let value as EAnnotation: self = .annotation(value)
        case let value as EStringToStringMapEntry: self = .detail(value)
        default: return nil
        }
    }

    /// The wrapped object.
    public var object: any EObject {
        switch self {
        case .package(let value): return value
        case .eClass(let value): return value
        case .dataType(let value): return value
        case .eEnum(let value): return value
        case .literal(let value): return value
        case .attribute(let value): return value
        case .reference(let value): return value
        case .operation(let value): return value
        case .parameter(let value): return value
        case .annotation(let value): return value
        case .detail(let value): return value
        }
    }

    /// The identifier of the element.
    public var id: EUUID { object.id }

    /// The metaclass of the element, as a case of ``EcoreClassifier``.
    public var kind: EcoreClassifier {
        switch self {
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
        case .detail: return .eStringToStringMapEntry
        }
    }

    /// The name of a named element, or `nil` for annotations and detail entries.
    public var name: String? {
        switch self {
        case .package(let value): return value.name
        case .eClass(let value): return value.name
        case .dataType(let value): return value.name
        case .eEnum(let value): return value.name
        case .literal(let value): return value.name
        case .attribute(let value): return value.name
        case .reference(let value): return value.name
        case .operation(let value): return value.name
        case .parameter(let value): return value.name
        case .annotation, .detail: return nil
        }
    }

    /// The annotations that the element carries; detail entries carry none.
    public var annotations: [EAnnotation] {
        switch self {
        case .package(let value): return value.eAnnotations
        case .eClass(let value): return value.eAnnotations
        case .dataType(let value): return value.eAnnotations
        case .eEnum(let value): return value.eAnnotations
        case .literal(let value): return value.eAnnotations
        case .attribute(let value): return value.eAnnotations
        case .reference(let value): return value.eAnnotations
        case .operation(let value): return value.eAnnotations
        case .parameter(let value): return value.eAnnotations
        case .annotation(let value): return value.eAnnotations
        case .detail: return []
        }
    }

    /// The elements that this element contains, in the order of EMF's `eContents`.
    ///
    /// Annotations come first. A package then holds its classifiers and subpackages; a class
    /// its operations and structural features; an enumeration its literals; an operation its
    /// parameters; and an annotation its detail entries. Objects that an annotation
    /// contains as free-form content are not elements and are not listed.
    public var children: [EcoreChild] {
        var result: [EcoreChild] = []
        func add(_ feature: EcoreFeatureName, _ elements: [EcoreElement]) {
            for (index, element) in elements.enumerated() {
                result.append(EcoreChild(feature: feature, index: index, element: element))
            }
        }
        add(.eAnnotations, annotations.map { .annotation($0) })
        switch self {
        case .package(let value):
            add(.eClassifiers, value.eClassifiers.compactMap { Self.classifier($0) })
            add(.eSubpackages, value.eSubpackages.map { .package($0) })
        case .eClass(let value):
            add(.eOperations, value.eOperations.map { .operation($0) })
            add(.eStructuralFeatures, value.eStructuralFeatures.compactMap { Self.feature($0) })
        case .eEnum(let value):
            add(.eLiterals, value.literals.map { .literal($0) })
        case .operation(let value):
            add(.eParameters, value.eParameters.map { .parameter($0) })
        case .annotation(let value):
            add(.details, value.detailEntries.map { .detail($0) })
        case .dataType, .literal, .attribute, .reference, .parameter, .detail:
            break
        }
        return result
    }

    /// Wraps a classifier.
    ///
    /// - Parameter classifier: A class, enumeration, or data type.
    /// - Returns: The wrapped element, or `nil` for any other kind of classifier.
    public static func classifier(_ classifier: any EClassifier) -> EcoreElement? {
        (classifier as? any EObject).flatMap { EcoreElement($0) }
    }

    /// Wraps a structural feature.
    ///
    /// - Parameter feature: An attribute or a reference.
    /// - Returns: The wrapped element, or `nil` for any other kind of feature.
    public static func feature(_ feature: any EStructuralFeature) -> EcoreElement? {
        (feature as? any EObject).flatMap { EcoreElement($0) }
    }
}
