//
// PropertyDescriptor.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

/// The group that a property belongs to in a property sheet.
public enum PropertyCategory: String, Sendable, Hashable, CaseIterable {
    /// Names, locations, and other text that identifies an element.
    case identity
    /// Types, supertypes, exceptions, and other references.
    case typing
    /// Multiplicity and the ordering and uniqueness of values.
    case multiplicity
    /// Flags that change how an element behaves.
    case behaviour
}

/// The kind of editor that suits a property.
public enum PropertyEditor: Sendable, Hashable {
    /// A single line of text.
    case text
    /// A text that can span several lines.
    case multiLine
    /// A flag.
    case flag
    /// An integer, with optional bounds.
    case integer(minimum: Int?, maximum: Int?)
    /// One element out of the candidates that ``MetamodelDocument/choices(for:feature:)`` lists.
    case choice
    /// Several elements out of the candidates, in order.
    case multiChoice
    /// A value that is shown but cannot be edited.
    case readOnly
}

/// Describes one property of a metamodel element for a property sheet.
///
/// Descriptors are derived reflectively from the features of the element's metaclass in
/// ``EcorePackage``. Derived and volatile features, and features that are not changeable, are
/// shown read-only.
public struct PropertyDescriptor: Sendable, Hashable {
    /// The feature that holds the property.
    public let feature: EcoreFeatureName

    /// The name that a property sheet shows, such as `Lower Bound`.
    public let displayName: String

    /// The group that the property belongs to.
    public let category: PropertyCategory

    /// The kind of editor that suits the property.
    public let editor: PropertyEditor

    /// Creates a descriptor.
    ///
    /// - Parameters:
    ///   - feature: The feature that holds the property.
    ///   - displayName: The name that a property sheet shows.
    ///   - category: The group that the property belongs to.
    ///   - editor: The kind of editor that suits the property.
    public init(feature: EcoreFeatureName, displayName: String, category: PropertyCategory, editor: PropertyEditor) {
        self.feature = feature
        self.displayName = displayName
        self.category = category
        self.editor = editor
    }

    /// The display name of a feature: the name split at lower-to-upper case changes, with the
    /// first letter in upper case (`lowerBound` is `Lower Bound`, `nsURI` is `Ns URI`).
    ///
    /// - Parameter feature: The feature.
    /// - Returns: The display name.
    public static func displayName(of feature: EcoreFeatureName) -> String {
        var result = ""
        var previousIsLower = false
        for (position, character) in feature.rawValue.enumerated() {
            if position == 0 {
                result += character.uppercased()
            } else {
                if character.isUppercase && previousIsLower { result += " " }
                result.append(character)
            }
            previousIsLower = position > 0 && character.isLowercase
        }
        return result
    }
}

extension EcoreEditSchema {
    /// The category of a feature.
    static func category(of feature: EcoreFeatureName) -> PropertyCategory {
        switch feature {
        case .name, .nsURI, .nsPrefix, .source, .key, .value, .literal, .instanceClassName:
            return .identity
        case .eType, .eSuperTypes, .eExceptions, .eOpposite, .references, .eKeys:
            return .typing
        case .ordered, .unique, .lowerBound, .upperBound, .many, .required:
            return .multiplicity
        default:
            return .behaviour
        }
    }

    /// The properties of each kind of element, derived from the reflective Ecore metamodel.
    static let propertyDescriptors: [EcoreClassifier: [PropertyDescriptor]] = {
        var result: [EcoreClassifier: [PropertyDescriptor]] = [:]
        for kind in elementKinds {
            var descriptors: [PropertyDescriptor] = []
            for metaFeature in EcorePackage.metaClass(kind).eAllStructuralFeatures {
                guard let feature = EcoreFeatureName(rawValue: metaFeature.name),
                    !unsupportedFeatures.contains(feature)
                else { continue }
                let reference = metaFeature as? EReference
                if let reference, reference.containment || reference.derived { continue }
                let editor: PropertyEditor
                if isReadOnly(metaFeature) {
                    editor = .readOnly
                } else if let reference {
                    editor = reference.upperBound == 1 ? .choice : .multiChoice
                } else {
                    editor = attributeEditor(feature, type: (metaFeature as? EAttribute)?.eType.name)
                }
                descriptors.append(
                    PropertyDescriptor(
                        feature: feature, displayName: PropertyDescriptor.displayName(of: feature),
                        category: category(of: feature), editor: editor))
            }
            result[kind] = descriptors
        }
        return result
    }()

    /// Whether a metaclass feature is derived, volatile, or not changeable.
    static func isReadOnly(_ feature: any EStructuralFeature) -> Bool {
        switch feature {
        case let attribute as EAttribute: return !attribute.changeable || attribute.derived || attribute.volatile
        case let reference as EReference: return !reference.changeable || reference.derived || reference.volatile
        default: return true
        }
    }

    private static func attributeEditor(_ feature: EcoreFeatureName, type: String?) -> PropertyEditor {
        switch type {
        case EcoreDataType.eBoolean.rawValue: return .flag
        case EcoreDataType.eInt.rawValue: return .integer(minimum: nil, maximum: nil)
        default: return feature == .value ? .multiLine : .text
        }
    }
}

extension MetamodelDocument {
    /// Describes the properties of an element for a property sheet.
    ///
    /// The integer bounds of ``PropertyEditor/integer(minimum:maximum:)`` follow the element:
    /// a lower bound is at least zero and at most the upper bound, unless that is unbounded;
    /// an upper bound is at least `-1`, which stands for unbounded.
    ///
    /// - Parameter identifier: The identifier of the element.
    /// - Returns: The descriptors in the order of the features of the element's metaclass;
    ///   empty for an unknown element.
    public func propertyDescriptors(for identifier: EUUID) -> [PropertyDescriptor] {
        guard let element = index.element(identifier),
            let descriptors = EcoreEditSchema.propertyDescriptors[element.kind]
        else { return [] }
        return descriptors.map { descriptor in
            guard case .integer = descriptor.editor else { return descriptor }
            switch descriptor.feature {
            case .lowerBound:
                var maximum: Int?
                if case .int(let upper)? = value(of: .upperBound, for: identifier), upper >= 0 { maximum = upper }
                return PropertyDescriptor(
                    feature: .lowerBound, displayName: descriptor.displayName, category: descriptor.category,
                    editor: .integer(minimum: 0, maximum: maximum))
            case .upperBound:
                return PropertyDescriptor(
                    feature: .upperBound, displayName: descriptor.displayName, category: descriptor.category,
                    editor: .integer(minimum: EcoreEditDefaults.unbounded, maximum: nil))
            default:
                return descriptor
            }
        }
    }

    /// The value of a property of an element.
    ///
    /// - Parameters:
    ///   - feature: The feature that holds the property.
    ///   - identifier: The identifier of the element.
    /// - Returns: The value, with references as identifiers; `nil` if the property is unset or
    ///   the element has no such feature.
    public func value(of feature: EcoreFeatureName, for identifier: EUUID) -> EditValue? {
        guard let element = index.element(identifier),
            let metaFeature = EcorePackage.feature(feature, of: element.kind)
        else { return nil }
        return EditValue(element.object.eGet(metaFeature))
    }
}
