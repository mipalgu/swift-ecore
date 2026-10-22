//
// MetamodelSnapshot.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Synchronization

import OrderedCollections

/// The metamodels that a resource set has registered, shared with its resources.
///
/// A resource refers to its resource set weakly, so it cannot rely on the set to tell it which
/// namespace each metaclass belongs to once the set has been released. The set therefore keeps
/// its registered metamodels in a snapshot that every resource it creates also holds. The
/// snapshot follows registrations and removals for as long as the set lives, and it remains
/// available to the resources after the set is gone.
final class MetamodelSnapshot: Sendable {
    /// The registered root packages and the index of their nested packages.
    private struct Registry {
        var roots: OrderedDictionary<String, EPackage> = [:]
        var nested: OrderedDictionary<String, EPackage> = [:]
    }

    private let registry = Mutex(Registry())

    /// Records a registered metamodel.
    ///
    /// - Parameters:
    ///   - package: The root package of the metamodel.
    ///   - uri: The namespace URI that the metamodel is registered under.
    func register(_ package: EPackage, uri: String) {
        registry.withLock {
            $0.roots[uri] = package
            $0.nested = NestedPackageIndex.build(from: $0.roots)
        }
    }

    /// Forgets a metamodel.
    ///
    /// - Parameter uri: The namespace URI that the metamodel was registered under.
    func unregister(uri: String) {
        registry.withLock {
            _ = $0.roots.removeValue(forKey: uri)
            $0.nested = NestedPackageIndex.build(from: $0.roots)
        }
    }

    /// The registered metamodels, ordered by namespace URI.
    var all: [EPackage] {
        registry.withLock { registry in registry.roots.keys.sorted().compactMap { registry.roots[$0] } }
    }

    /// The package registered under a namespace URI, or nested in a registered package.
    ///
    /// - Parameter uri: The namespace URI.
    /// - Returns: The registered package, else the nested package with that URI, else `nil`.
    func package(uri: String) -> EPackage? {
        registry.withLock { $0.roots[uri] ?? $0.nested[uri] }
    }
}

/// Indexes the nested packages of registered metamodels by their namespace URIs.
enum NestedPackageIndex {
    /// Builds the index of the nested packages of some registered root packages.
    ///
    /// The roots are visited in registration order and their nested packages depth first. A
    /// nested package is indexed if it has a namespace URI under which no root is registered
    /// and that no earlier nested package has.
    ///
    /// - Parameter roots: The registered root packages by registration URI.
    /// - Returns: The nested packages by namespace URI, in visiting order.
    static func build(from roots: OrderedDictionary<String, EPackage>) -> OrderedDictionary<String, EPackage> {
        var index: OrderedDictionary<String, EPackage> = [:]
        for root in roots.values {
            for package in root.allPackages.dropFirst()
            where !package.nsURI.isEmpty && roots[package.nsURI] == nil && index[package.nsURI] == nil {
                index[package.nsURI] = package
            }
        }
        return index
    }
}
