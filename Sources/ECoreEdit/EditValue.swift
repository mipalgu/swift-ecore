//
// EditValue.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

/// A value of a property of a metamodel element, as recorded in change sets.
///
/// Values that name other elements are recorded by identifier, so that a change set stays
/// meaningful after the elements it mentions have been edited.
public enum EditValue: Sendable, Hashable {
    /// A string value.
    case string(String)
    /// A flag.
    case bool(Bool)
    /// An integer.
    case int(Int)
    /// The identifier of one element.
    case identifier(EUUID)
    /// The identifiers of several elements, in order.
    case identifiers([EUUID])

    /// Records a reflective value.
    ///
    /// - Parameter value: A string, flag, integer, identifier, metamodel object, or a
    ///   collection of identifiers and metamodel objects.
    /// - Returns: The recorded value, or `nil` for `nil` and for any other kind of value.
    public init?(_ value: (any EcoreValue)?) {
        guard let value else { return nil }
        switch value {
        case let text as String: self = .string(text)
        case let flag as Bool: self = .bool(flag)
        case let number as Int: self = .int(number)
        case let identifier as EUUID: self = .identifier(identifier)
        case let identifiers as [EUUID]: self = .identifiers(identifiers)
        case let array as EcoreValueArray:
            self = .identifiers(array.values.compactMap(Self.identifier(of:)))
        default:
            guard let identifier = Self.identifier(of: value) else { return nil }
            self = .identifier(identifier)
        }
    }

    /// The identifier that a reflective value stands for.
    private static func identifier(of value: any EcoreValue) -> EUUID? {
        if let identifier = value as? EUUID { return identifier }
        return (value as? any EObject)?.id
    }

    /// The identifiers that the value holds: one for an identifier, several for a list.
    public var identifierList: [EUUID] {
        switch self {
        case .identifier(let identifier): return [identifier]
        case .identifiers(let identifiers): return identifiers
        default: return []
        }
    }
}
