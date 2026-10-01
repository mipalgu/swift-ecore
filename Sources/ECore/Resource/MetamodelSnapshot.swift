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
    private let packages = Mutex<OrderedDictionary<String, EPackage>>([:])

    /// Records a registered metamodel.
    ///
    /// - Parameters:
    ///   - package: The root package of the metamodel.
    ///   - uri: The namespace URI that the metamodel is registered under.
    func register(_ package: EPackage, uri: String) {
        packages.withLock { $0[uri] = package }
    }

    /// Forgets a metamodel.
    ///
    /// - Parameter uri: The namespace URI that the metamodel was registered under.
    func unregister(uri: String) {
        packages.withLock { _ = $0.removeValue(forKey: uri) }
    }

    /// The registered metamodels, ordered by namespace URI.
    var all: [EPackage] {
        packages.withLock { registry in registry.keys.sorted().compactMap { registry[$0] } }
    }
}
