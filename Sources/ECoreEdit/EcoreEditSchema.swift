//
// EcoreEditSchema.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

/// A kind of child that can be created inside a metamodel element.
///
/// A descriptor pairs a containment feature of the container's metaclass with a concrete
/// metaclass that the feature accepts. Descriptors drive the "New Child" and "New Sibling"
/// menus of metamodel editors.
public struct ChildDescriptor: Sendable, Hashable {
    /// The identifier of the container that would hold the new element.
    public let container: EUUID

    /// The containment feature of the container that would hold the new element.
    public let feature: EcoreFeatureName

    /// The metaclass of the new element.
    public let kind: EcoreClassifier

    /// The position of the new element, or `nil` to append it.
    public let index: Int?

    /// Creates a descriptor.
    ///
    /// - Parameters:
    ///   - container: The identifier of the container.
    ///   - feature: The containment feature.
    ///   - kind: The metaclass of the new element.
    ///   - index: The position of the new element, or `nil` to append it.
    public init(container: EUUID, feature: EcoreFeatureName, kind: EcoreClassifier, index: Int? = nil) {
        self.container = container
        self.feature = feature
        self.kind = kind
        self.index = index
    }

    /// The edit that creates the element.
    ///
    /// - Parameter name: The name of the new element, or `nil` for none.
    /// - Returns: A ``MetamodelEdit/create(_:in:feature:at:name:identifier:)`` edit.
    public func edit(name: String? = nil) -> MetamodelEdit {
        .create(kind, in: container, feature: feature, at: index, name: name)
    }
}

extension EcoreEditSchema {
    /// A containment feature and the metaclasses that it accepts.
    struct ContainmentRule: Sendable {
        /// The containment feature.
        let feature: EcoreFeatureName
        /// The concrete metaclasses that the feature accepts, in the order of ``EcoreEditSchema/elementKinds``.
        let kinds: [EcoreClassifier]
    }

    /// The containment rules of each kind of element, derived from the reflective Ecore metamodel.
    ///
    /// Each containment reference of a metaclass (inherited ones included) is crossed with
    /// the concrete metaclasses of Ecore that conform to its type, restricted to the kinds of
    /// element that native metamodels consist of.
    static let containmentRules: [EcoreClassifier: [ContainmentRule]] = {
        var result: [EcoreClassifier: [ContainmentRule]] = [:]
        for kind in elementKinds {
            var rules: [ContainmentRule] = []
            for reference in EcorePackage.metaClass(kind).eAllContainments {
                guard let feature = EcoreFeatureName(rawValue: reference.name),
                    !unsupportedFeatures.contains(feature),
                    let target = EcoreClassifier(rawValue: reference.eType.name)
                else { continue }
                let accepted = elementKinds.filter { candidate in
                    !EcorePackage.metaClass(candidate).isAbstract && conforms(candidate, to: target)
                }
                if !accepted.isEmpty { rules.append(ContainmentRule(feature: feature, kinds: accepted)) }
            }
            result[kind] = rules
        }
        return result
    }()

    /// Whether a metaclass is, or inherits from, another.
    static func conforms(_ kind: EcoreClassifier, to target: EcoreClassifier) -> Bool {
        kind == target || EcorePackage.metaClass(kind).eAllSuperTypes.contains { $0.name == target.rawValue }
    }

    /// Whether a container of a kind accepts an element of a kind in a feature.
    static func accepts(container: EcoreClassifier, feature: EcoreFeatureName, kind: EcoreClassifier) -> Bool {
        containmentRules[container]?.contains { $0.feature == feature && $0.kinds.contains(kind) } ?? false
    }

    /// The first containment feature of a container that accepts every kind.
    static func feature(of container: EcoreClassifier, accepting kinds: [EcoreClassifier]) -> EcoreFeatureName? {
        containmentRules[container]?.first { rule in kinds.allSatisfy(rule.kinds.contains) }?.feature
    }
}

extension MetamodelDocument {
    /// Lists the elements that can be created inside an element.
    ///
    /// Every containment feature of the element's metaclass is crossed with each concrete
    /// metaclass that it accepts. Annotations (and details entries inside annotations) are
    /// included.
    ///
    /// - Parameter identifier: The identifier of the prospective container.
    /// - Returns: The descriptors in the order of the features, and within a feature in
    ///   the order of the metaclasses; empty for an unknown or external element.
    public func childDescriptors(for identifier: EUUID) -> [ChildDescriptor] {
        descriptors(container: identifier, index: nil, restrictedTo: nil)
    }

    /// Lists the elements that can be created next to an element.
    ///
    /// These are the children that the element's container accepts. A new element of the
    /// same containment feature as the element is placed right after it; the others are
    /// appended.
    ///
    /// - Parameter identifier: The identifier of the element.
    /// - Returns: The descriptors; empty for a root package and for unknown elements.
    public func siblingDescriptors(for identifier: EUUID) -> [ChildDescriptor] {
        guard let place = index.container(of: identifier) else { return [] }
        return descriptors(container: place.container, index: place.index + 1, restrictedTo: place.feature)
    }

    private func descriptors(container: EUUID, index position: Int?, restrictedTo feature: EcoreFeatureName?)
        -> [ChildDescriptor]
    {
        guard let element = index.element(container), !index.isExternal(container),
            let rules = EcoreEditSchema.containmentRules[element.kind]
        else { return [] }
        var result: [ChildDescriptor] = []
        for rule in rules {
            for kind in rule.kinds {
                result.append(
                    ChildDescriptor(
                        container: container, feature: rule.feature, kind: kind,
                        index: rule.feature == feature ? position : nil))
            }
        }
        return result
    }
}
