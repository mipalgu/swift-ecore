//
// UnsetFeatureReads.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// How model navigation reads a structural feature that has not been set.
///
/// The Eclipse Modeling Framework, and every query and transformation language built on it,
/// reads an unset feature through `eGet`, which yields the feature's default value. This
/// type lets an ``ECoreExecutionEngine`` either follow that convention, which it does by
/// default, or report unset features as having no value at all.
///
/// The raw value of each case is a lower-case word that can double as a command-line
/// spelling, so that a tool can parse an option with ``init(rawValue:)`` and list the
/// accepted spellings through ``allCases``.
public enum UnsetFeatureReads: String, Sendable, CaseIterable {
    /// Unset features read as their defaults, as the Eclipse Modeling Framework's `eGet` does.
    ///
    /// An unset single-valued attribute reads as its declared default value literal or, when
    /// it declares none, as the default of its data type, such as `false` or zero. An unset
    /// many-valued feature reads as an empty collection, while an unset string attribute or
    /// single-valued reference without a declared default reads as `nil`.
    case defaults

    /// Unset features read as `nil`.
    ///
    /// This is a non-standard mode for callers that want to detect whether a feature has been
    /// set, rather than observe the value that the Eclipse Modeling Framework would report.
    case undefined
}
