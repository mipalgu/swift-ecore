//
// ModellingSemantics.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// A choice between the recommended behaviours of the modelling languages and those of
/// version 0.6.
///
/// Each language offers a set of options with a ``standard`` and a ``legacy`` preset: in this
/// package ``ContainerLookupScope``, and in the expression, generation and transformation
/// languages their own options types. A choice of semantics selects the matching preset of
/// each, for example through ``ContainerLookupScope/init(semantics:)``.
///
/// The raw value of each case is its lower-case command-line spelling, which is also the
/// value that the ``environmentVariable`` takes. A process can therefore let its environment
/// choose the semantics:
///
/// ```swift
/// let semantics = try ModellingSemantics.fromEnvironment() ?? .standard
/// let resourceSet = ResourceSet(defaultContainerLookupScope: ContainerLookupScope(semantics: semantics))
/// ```
public enum ModellingSemantics: String, Sendable, CaseIterable, Hashable {
    /// The recommended behaviours.
    case standard

    /// The behaviours of version 0.6.
    case legacy

    /// The name of the environment variable that selects the semantics,
    /// `SWIFT_MODELLING_SEMANTICS`.
    public static let environmentVariable = "SWIFT_MODELLING_SEMANTICS"

    /// Reads the semantics that an environment selects.
    ///
    /// The value of ``environmentVariable`` must be the raw value of a case, spelt exactly.
    /// An empty value counts as unset.
    ///
    /// - Parameter environment: The environment variables to read; by default those of the
    ///   current process.
    /// - Returns: The selected semantics, or `nil` if the variable is unset or empty.
    /// - Throws: ``ModellingSemanticsError/invalidValue(_:variable:)`` if the variable holds
    ///   any other value.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws(ModellingSemanticsError) -> ModellingSemantics? {
        guard let value = environment[environmentVariable], !value.isEmpty else { return nil }
        guard let semantics = ModellingSemantics(rawValue: value) else {
            throw .invalidValue(value, variable: environmentVariable)
        }
        return semantics
    }
}

/// An error raised while reading a choice of ``ModellingSemantics``.
public enum ModellingSemanticsError: Error, Sendable, Hashable, CustomStringConvertible {
    /// A variable holds a value that names no semantics.
    ///
    /// - Parameters:
    ///   - value: The value found.
    ///   - variable: The name of the variable that holds it.
    case invalidValue(String, variable: String)

    /// A message that names the variable, its value and the accepted values.
    public var description: String {
        switch self {
        case .invalidValue(let value, let variable):
            let accepted = ModellingSemantics.allCases.map(\.rawValue).joined(separator: " or ")
            return "Invalid value '\(value)' for \(variable): expected \(accepted)"
        }
    }
}
