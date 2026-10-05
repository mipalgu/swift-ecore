//
// ModelDiagnostic.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// How serious a problem found in a model is.
public enum ModelDiagnosticSeverity: String, Sendable, Hashable, Comparable, CaseIterable {
    /// Information that needs no action.
    case info
    /// A questionable construct that does not make the model invalid.
    case warning
    /// A constraint violation.
    case error

    private var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .error: return 2
        }
    }

    public static func < (lhs: ModelDiagnosticSeverity, rhs: ModelDiagnosticSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// The constraints that ``ModelValidator`` checks, with stable identifiers.
public enum ModelDiagnosticCode: String, Sendable, Hashable, CaseIterable {
    /// A feature has fewer values than its lower bound requires.
    case lowerBound = "model.lowerBound"
    /// A feature has more values than its upper bound allows.
    case upperBound = "model.upperBound"
    /// An attribute value does not conform to the attribute's data type.
    case invalidValue = "model.invalidValue"
    /// An attribute value is not a literal of the attribute's enumeration.
    case invalidEnumLiteral = "model.invalidEnumLiteral"
    /// A reference points at an object of a class that the reference does not accept.
    case referenceTypeMismatch = "model.referenceTypeMismatch"
    /// A reference points at an object that does not exist.
    case danglingReference = "model.danglingReference"
    /// Two objects have the same value for an identifying attribute.
    case duplicateID = "model.duplicateID"
    /// An object is an instance of an abstract class or an interface.
    case abstractInstance = "model.abstractInstance"
}

/// A problem found in a model.
public struct ModelDiagnostic: Sendable, Equatable, Hashable {
    /// How serious the problem is.
    public let severity: ModelDiagnosticSeverity

    /// Which constraint is violated.
    public let code: ModelDiagnosticCode

    /// The object that has the problem.
    public let objectID: EUUID

    /// The name of the feature that has the problem, if the problem concerns a feature.
    public let feature: String?

    /// The values that fill the placeholders of the message template, in order.
    public let arguments: [String]

    /// Creates a diagnostic.
    ///
    /// - Parameters:
    ///   - severity: How serious the problem is.
    ///   - code: Which constraint is violated.
    ///   - objectID: The object that has the problem.
    ///   - feature: The feature that has the problem, if any.
    ///   - arguments: The values for the message template's placeholders.
    public init(
        severity: ModelDiagnosticSeverity = .error, code: ModelDiagnosticCode, objectID: EUUID,
        feature: String? = nil, arguments: [String] = []
    ) {
        self.severity = severity
        self.code = code
        self.objectID = objectID
        self.feature = feature
        self.arguments = arguments
    }

    /// The human-readable message, from ``ModelDiagnosticMessages``.
    public var message: String { ModelDiagnosticMessages.message(for: code, arguments: arguments) }
}
