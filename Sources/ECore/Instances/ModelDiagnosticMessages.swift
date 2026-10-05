//
// ModelDiagnosticMessages.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// The catalogue of messages for model diagnostics.
///
/// Each message is a template whose placeholders `{0}`, `{1}`, and so on take the
/// diagnostic's arguments in order. All wording lives here, so messages can be reviewed and
/// translated in one place.
public enum ModelDiagnosticMessages {

    /// The message template of each diagnostic code.
    public static let templates: [ModelDiagnosticCode: String] = [
        .lowerBound: "Feature '{0}' needs at least {1} value(s) but has {2}",
        .upperBound: "Feature '{0}' allows at most {1} value(s) but has {2}",
        .invalidValue: "Value '{1}' is not a valid {2} for feature '{0}'",
        .invalidEnumLiteral: "Value '{1}' is not a literal of enumeration {2} (feature '{0}')",
        .referenceTypeMismatch: "Feature '{0}' refers to an instance of {1}, which is not a {2}",
        .danglingReference: "Feature '{0}' refers to missing object {1}",
        .duplicateID: "Identifier '{1}' of feature '{0}' is used by more than one object",
        .abstractInstance: "Class {0} is abstract and cannot be instantiated",
    ]

    /// Builds the message for a diagnostic.
    ///
    /// - Parameters:
    ///   - code: The diagnostic code.
    ///   - arguments: The values for the template's placeholders.
    /// - Returns: The message with the placeholders filled in.
    public static func message(for code: ModelDiagnosticCode, arguments: [String]) -> String {
        var text = templates[code] ?? code.rawValue
        for (position, argument) in arguments.enumerated() {
            text = text.replacingOccurrences(of: "{\(position)}", with: argument)
        }
        return text
    }
}
