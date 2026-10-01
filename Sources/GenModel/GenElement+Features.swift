//
// GenElement+Features.swift
// GenModel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore

extension GenElement {
    /// Whether the Ecore feature of a generator feature is a reference.
    public var isReferenceType: Bool { ecoreFeature is EReference }

    /// Whether the Ecore feature of a generator feature is an attribute.
    public var isAttributeType: Bool { ecoreFeature is EAttribute }

    private var ecoreReference: EReference? { ecoreFeature as? EReference }

    private var oppositeReference: EReference? {
        ecoreReference?.opposite.flatMap { context.ecoreFeature(id: $0) as? EReference }
    }

    /// Whether the feature is a containment reference.
    public var isContainment: Bool { ecoreReference?.containment ?? false }

    /// Whether the feature is the container end of a containment relationship.
    ///
    /// This holds for a reference whose opposite reference is a containment.
    public var isContainer: Bool { oppositeReference?.containment ?? false }

    /// Whether the feature is a reference with an opposite reference.
    public var isBidirectional: Bool { ecoreReference?.opposite != nil }

    /// The generator feature of the opposite reference, if the context holds one.
    public var reverseGenFeature: GenElement? {
        guard let opposite = ecoreReference?.opposite else { return nil }
        return context.elements(ofKind: GenModelConstants.ClassName.genFeature).first {
            ($0.ecoreFeature?.id) == opposite
        }
    }

    /// The Ecore element that carries the type and multiplicity of a feature, operation or parameter.
    private var ecoreTypedElement: (any ETypedElement)? { ecoreOperation ?? ecoreParameter }

    /// The type of the Ecore element that a feature, operation or parameter describes.
    ///
    /// - Returns: The type, or `nil` if the element is not typed, has no type (an operation
    ///   without a result), or its Ecore element is not resolved.
    public var ecoreType: (any EClassifier)? {
        switch ecoreFeature {
        case let attribute as EAttribute: return attribute.eType
        case let reference as EReference: return reference.eType
        default: return ecoreTypedElement?.eType
        }
    }

    /// The lower bound of the multiplicity of a feature, operation or parameter.
    public var lowerBound: Int {
        switch ecoreFeature {
        case let attribute as EAttribute: return attribute.lowerBound
        case let reference as EReference: return reference.lowerBound
        default: return ecoreTypedElement?.lowerBound ?? 0
        }
    }

    /// The upper bound of the multiplicity of a feature, operation or parameter; negative values mean unbounded.
    public var upperBound: Int {
        switch ecoreFeature {
        case let attribute as EAttribute: return attribute.upperBound
        case let reference as EReference: return reference.upperBound
        default: return ecoreTypedElement?.upperBound ?? 1
        }
    }

    /// Whether the element can hold more than one value.
    public var isListType: Bool { upperBound > 1 || upperBound < 0 }

    /// Whether the feature is required, with a lower bound of at least one.
    public var isRequired: Bool { lowerBound >= 1 }

    /// Whether values of the feature can be modified.
    public var isChangeable: Bool {
        switch ecoreFeature {
        case let attribute as EAttribute: return attribute.changeable
        case let reference as EReference: return reference.changeable
        default: return true
        }
    }

    /// Whether the feature is volatile, that is, not backed by storage.
    ///
    /// A reference is also treated as volatile when its opposite reference is volatile.
    public var isVolatile: Bool {
        let own: Bool
        switch ecoreFeature {
        case let attribute as EAttribute: own = attribute.volatile
        case let reference as EReference: own = reference.volatile
        default: own = false
        }
        return own || (oppositeReference?.volatile ?? false)
    }

    /// Whether the feature is transient, that is, not persisted.
    public var isTransient: Bool {
        switch ecoreFeature {
        case let attribute as EAttribute: return attribute.transient
        case let reference as EReference: return reference.transient
        default: return false
        }
    }

    /// Whether the feature is derived from other features.
    public var isDerived: Bool {
        switch ecoreFeature {
        case let attribute as EAttribute: return attribute.derived
        case let reference as EReference: return reference.derived
        default: return false
        }
    }

    /// Whether the feature distinguishes the unset state from the default value.
    public var isUnsettable: Bool {
        switch ecoreFeature {
        case let attribute as EAttribute: return attribute.unsettable
        case let reference as EReference: return reference.unsettable
        default: return false
        }
    }

    /// Whether the feature has a default value literal.
    public var hasDefault: Bool { defaultValueLiteral != nil }

    /// The default value literal of an attribute, as written in the Ecore model.
    public var defaultValueLiteral: String? {
        (ecoreFeature as? EAttribute)?.defaultValueLiteral
    }
}
