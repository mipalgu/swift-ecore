//
// MultiLevelIdentifiers.swift
// MultiLevel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Deterministic identifiers for clabjects read from text and for the facets of views.
///
/// Text carries no identifiers, so a clabject read from MetaDepth text receives one derived
/// from the names of its deep model, its level model and itself. Reading the same text twice
/// therefore yields the same identifiers, which keeps interchange documents byte-stable. The
/// derivation is a non-cryptographic hash; it distinguishes names, it does not protect them.
public enum MultiLevelIdentifiers {
    /// The marker that distinguishes the identifier of a type facet from its clabject.
    static let typeFacetComponent = "type-facet"

    /// The marker that distinguishes the identifier of a view package.
    static let packageComponent = "view-package"

    /// The separator between the components of a derived identifier.
    static let componentSeparator: UInt8 = 0x1F

    /// The 64-bit FNV-1a offset basis.
    static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325

    /// The 64-bit FNV-1a prime.
    static let prime: UInt64 = 0x0000_0100_0000_01b3

    /// The salt that makes the second half of an identifier independent of the first.
    static let secondHalfSalt: UInt64 = 0x9e37_79b9_7f4a_7c15

    /// An identifier derived deterministically from a sequence of names.
    ///
    /// - Parameter components: The names, such as a model name and a clabject name.
    /// - Returns: A version 8 (custom) UUID determined by the names.
    public static func identifier(for components: [String]) -> EUUID {
        var bytes: [UInt8] = []
        for component in components {
            bytes.append(contentsOf: Array(component.utf8))
            bytes.append(componentSeparator)
        }
        let first = hash(bytes, basis: offsetBasis)
        let second = hash(bytes, basis: offsetBasis ^ secondHalfSalt)
        var raw = withUnsafeBytes(of: first.bigEndian, Array.init) + withUnsafeBytes(of: second.bigEndian, Array.init)
        raw[6] = (raw[6] & 0x0F) | 0x80
        raw[8] = (raw[8] & 0x3F) | 0x80
        return EUUID(uuid: (
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]))
    }

    /// The identifier of a clabject read from text.
    ///
    /// - Parameters:
    ///   - name: The name of the clabject.
    ///   - levelModel: The name of its level model.
    ///   - deepModel: The name of the top model of its deep model.
    /// - Returns: The identifier.
    public static func clabjectIdentifier(named name: String, inLevelModel levelModel: String, of deepModel: String)
        -> EUUID
    {
        identifier(for: [deepModel, levelModel, name])
    }

    /// The identifier of the type facet of a clabject in a view.
    ///
    /// - Parameter clabject: The identifier of the clabject.
    /// - Returns: The identifier of its class.
    public static func typeFacetIdentifier(of clabject: EUUID) -> EUUID {
        identifier(for: [typeFacetComponent, clabject.uuidString])
    }

    /// The identifier of the package of a view.
    ///
    /// - Parameter namespaceURI: The namespace URI of the view.
    /// - Returns: The identifier of its package.
    static func packageIdentifier(of namespaceURI: String) -> EUUID {
        identifier(for: [packageComponent, namespaceURI])
    }

    /// The FNV-1a hash of bytes from a basis.
    private static func hash(_ bytes: [UInt8], basis: UInt64) -> UInt64 {
        var value = basis
        for byte in bytes {
            value ^= UInt64(byte)
            value = value &* prime
        }
        return value
    }
}
