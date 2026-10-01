//
// EMetaObject.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// An object of the Ecore metamodel itself, such as a package, class, or attribute.
///
/// Metamodel objects are the native Swift types that make up a loaded or hand-built
/// `.ecore` metamodel. They report their descriptor from ``EObject/eClass`` (an ``EClass``
/// of ``EcorePackage``), answer reflective access to the features of that descriptor, and
/// expose the containment structure of the metamodel.
///
/// Because the metamodel types are value types, each contained object records the identifier
/// of the object that contains it. The identifier is maintained whenever a contained object
/// is added to its container, so ``eContainerID`` identifies the current container of any
/// object that has been placed in one. A container can be looked up by identifier through a
/// ``Resource`` that holds the metamodel.
///
/// ## Containment
///
/// - ``eContents`` lists the directly contained objects in feature order.
/// - ``eAllContents`` lists all contained objects, depth first.
public protocol EMetaObject: EObject {
    /// The identifier of the object that contains this object, if any.
    ///
    /// The value is `nil` for objects that are not contained, such as a root package.
    var eContainerID: EUUID? { get }

    /// The objects directly contained by this object.
    ///
    /// Contained objects are returned in the order of the containment features of the
    /// object's descriptor, and in declaration order within each feature.
    var eContents: [any EObject] { get }
}

extension EMetaObject {
    /// All objects contained by this object, transitively.
    ///
    /// The result is in depth-first (pre-order) order, so that each object is followed by
    /// its own contents before its next sibling.
    public var eAllContents: [any EObject] {
        var result: [any EObject] = []
        for child in eContents {
            result.append(child)
            if let metaChild = child as? any EMetaObject {
                result.append(contentsOf: metaChild.eAllContents)
            }
        }
        return result
    }
}

/// The outcome of a reflective feature lookup on a metamodel object.
enum ReflectiveValue {
    /// The feature is not answered reflectively; fall back to generic storage.
    case unsupported

    /// The feature is answered reflectively with the given value (which may be `nil`).
    case value((any EcoreValue)?)
}

/// Internal contract implemented by the native metamodel types to answer reflective access.
protocol EcoreReflective: EMetaObject {
    /// Computes the value of the named metamodel feature.
    ///
    /// - Parameter name: The feature to read.
    /// - Returns: The value, or ``ReflectiveValue/unsupported`` if the feature does not apply.
    func reflectiveGet(_ name: EcoreFeatureName) -> ReflectiveValue

    /// Changes the value of the named metamodel feature.
    ///
    /// - Parameters:
    ///   - name: The feature to modify.
    ///   - value: The new value, or `nil` to reset the feature.
    /// - Returns: `true` if the feature was handled, `false` to fall back to generic storage.
    mutating func reflectiveSet(_ name: EcoreFeatureName, _ value: (any EcoreValue)?) -> Bool

    /// The containment features and objects of this object in feature order.
    var containedObjects: [(feature: EcoreFeatureName, object: any EObject)] { get }
}

extension EcoreReflective {
    /// The directly contained objects, in feature order.
    public var eContents: [any EObject] {
        containedObjects.map { $0.object }
    }

    /// Reflectively reads a feature if it belongs to the Ecore metamodel.
    func reflectiveEGet(_ feature: some EStructuralFeature) -> ReflectiveValue {
        guard let name = EcorePackage.featureName(forID: feature.id) else { return .unsupported }
        return reflectiveGet(name)
    }

    /// Reflectively writes a feature if it belongs to the Ecore metamodel.
    mutating func reflectiveESet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?)
        -> Bool
    {
        guard let name = EcorePackage.featureName(forID: feature.id) else { return false }
        return reflectiveSet(name, value)
    }

    /// Reflectively determines whether a metamodel feature differs from its default.
    func reflectiveEIsSet(_ feature: some EStructuralFeature) -> Bool? {
        guard let name = EcorePackage.featureName(forID: feature.id),
            case .value(let current) = reflectiveGet(name)
        else { return nil }
        return EcorePackage.isSet(current, for: feature)
    }

    /// Reflectively resets a metamodel feature to its default.
    mutating func reflectiveEUnset(_ feature: some EStructuralFeature) -> Bool {
        guard let name = EcorePackage.featureName(forID: feature.id) else { return false }
        return reflectiveSet(name, nil)
    }
}

// MARK: - Value Conversion

/// Conversions between reflective values and typed Swift values.
enum ReflectiveValues {
    /// Wraps objects as a collection value.
    static func collection(_ elements: [any EcoreValue]) -> ReflectiveValue {
        .value(EcoreValueArray(elements))
    }

    /// Extracts the elements of a collection value as the requested type.
    ///
    /// Accepts an ``EcoreValueArray`` as well as a typed Swift array.
    static func elements<T>(_ value: (any EcoreValue)?, as type: T.Type) -> [T]? {
        if let array = value as? EcoreValueArray {
            return array.values.compactMap { $0 as? T }
        }
        if let typed = value as? [T] {
            return typed
        }
        if let anyArray = value as? [any EcoreValue] {
            return anyArray.compactMap { $0 as? T }
        }
        return nil
    }

    /// Derives a stable identifier from a base identifier and a key.
    ///
    /// Used for objects that are synthesised from other data, so that repeated reads
    /// answer objects with the same identity.
    static func derivedID(from base: EUUID, key: String) -> EUUID {
        var bytes = withUnsafeBytes(of: base.uuid) { Array($0) }
        bytes.append(contentsOf: Array(key.utf8))
        var low: UInt64 = 0xcbf2_9ce4_8422_2325
        var high: UInt64 = 0x8422_2325_cbf2_9ce4
        for byte in bytes {
            low = (low ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            high = (high &+ UInt64(byte)) &* 0x0000_0100_0000_01b3 ^ (high >> 29)
        }
        let uuid: uuid_t = (
            UInt8(truncatingIfNeeded: low), UInt8(truncatingIfNeeded: low >> 8),
            UInt8(truncatingIfNeeded: low >> 16), UInt8(truncatingIfNeeded: low >> 24),
            UInt8(truncatingIfNeeded: low >> 32), UInt8(truncatingIfNeeded: low >> 40),
            UInt8(truncatingIfNeeded: low >> 48), UInt8(truncatingIfNeeded: low >> 56),
            UInt8(truncatingIfNeeded: high), UInt8(truncatingIfNeeded: high >> 8),
            UInt8(truncatingIfNeeded: high >> 16), UInt8(truncatingIfNeeded: high >> 24),
            UInt8(truncatingIfNeeded: high >> 32), UInt8(truncatingIfNeeded: high >> 40),
            UInt8(truncatingIfNeeded: high >> 48), UInt8(truncatingIfNeeded: high >> 56)
        )
        return UUID(uuid: uuid)
    }
}

// MARK: - Container Stamping

/// Maintains the container identifier of objects held in the containment collections of
/// metamodel objects.
enum ContainerStamp {
    /// Records `container` as the container of every annotation in the collection.
    static func stamp(_ annotations: inout [EAnnotation], container: EUUID) {
        for index in annotations.indices where annotations[index].eContainerID != container {
            annotations[index].eContainerID = container
        }
    }

    /// Records `container` as the container of every classifier in the collection.
    static func stamp(_ classifiers: inout [any EClassifier], container: EUUID) {
        for index in classifiers.indices {
            if var eClass = classifiers[index] as? EClass {
                if eClass.eContainerID != container {
                    eClass.eContainerID = container
                    classifiers[index] = eClass
                }
            } else if var eEnum = classifiers[index] as? EEnum {
                if eEnum.eContainerID != container {
                    eEnum.eContainerID = container
                    classifiers[index] = eEnum
                }
            } else if var dataType = classifiers[index] as? EDataType {
                if dataType.eContainerID != container {
                    dataType.eContainerID = container
                    classifiers[index] = dataType
                }
            }
        }
    }

    /// Records `container` as the container of every feature in the collection.
    static func stamp(_ features: inout [any EStructuralFeature], container: EUUID) {
        for index in features.indices {
            if var attribute = features[index] as? EAttribute {
                if attribute.eContainerID != container {
                    attribute.eContainerID = container
                    features[index] = attribute
                }
            } else if var reference = features[index] as? EReference {
                if reference.eContainerID != container {
                    reference.eContainerID = container
                    features[index] = reference
                }
            }
        }
    }

    /// Records `container` as the container of every package in the collection.
    static func stamp(_ packages: inout [EPackage], container: EUUID) {
        for index in packages.indices where packages[index].eContainerID != container {
            packages[index].eContainerID = container
        }
    }

    /// Records `container` as the container of every literal in the collection.
    static func stamp(_ literals: inout [EEnumLiteral], container: EUUID) {
        for index in literals.indices where literals[index].eContainerID != container {
            literals[index].eContainerID = container
        }
    }
}
