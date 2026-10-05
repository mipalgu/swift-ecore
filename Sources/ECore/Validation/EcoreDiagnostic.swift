//
// EcoreDiagnostic.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// A problem that validation found in a native metamodel.
///
/// A diagnostic names the element that has the problem by identifier, never by snapshot, so
/// it stays meaningful while the metamodel is edited. The message is built from a template
/// and its arguments; a host application that localises its messages can use the ``template``
/// and ``arguments`` instead of ``message``.
public struct EcoreDiagnostic: Sendable, Hashable, Identifiable {
    /// How serious the problem is.
    public let severity: DiagnosticSeverity

    /// The constraint that is violated.
    public let code: EcoreConstraint

    /// The kind of message, which identifies the wording and the meaning of the arguments.
    public let template: EcoreValidationMessage

    /// The element that has the problem.
    public let element: EUUID

    /// The feature of the element that has the problem, if the problem concerns one.
    public let feature: EcoreFeatureName?

    /// The values that fill the placeholders of the message template, in order.
    public let arguments: [String]

    /// The other elements that take part in the problem, such as the clashing elements of a
    /// duplicate name, in document order.
    public let related: [EUUID]

    /// Creates a diagnostic.
    ///
    /// - Parameters:
    ///   - severity: How serious the problem is.
    ///   - code: The constraint that is violated.
    ///   - template: The kind of message.
    ///   - element: The element that has the problem.
    ///   - feature: The feature that has the problem, if any.
    ///   - arguments: The values for the placeholders of the template.
    ///   - related: The other elements that take part in the problem.
    public init(
        severity: DiagnosticSeverity, code: EcoreConstraint, template: EcoreValidationMessage,
        element: EUUID, feature: EcoreFeatureName? = nil, arguments: [String] = [],
        related: [EUUID] = []
    ) {
        self.severity = severity
        self.code = code
        self.template = template
        self.element = element
        self.feature = feature
        self.arguments = arguments
        self.related = related
    }

    /// The human-readable message, from ``EcoreValidationMessages``.
    public var message: String {
        EcoreValidationMessages.message(template, arguments: arguments)
    }

    /// A stable identifier: equal for diagnostics that report the same problem, whatever the
    /// run that found them.
    public var id: String {
        let parts = [code.rawValue, template.rawValue, element.uuidString, feature?.rawValue ?? ""]
            + related.map(\.uuidString) + arguments
        return parts.joined(separator: "|")
    }
}

extension EcoreDiagnostic {
    /// Converts an error that a validation delegate reported.
    ///
    /// The result has the constraint ``EcoreConstraint/delegate``, the delegate's message as
    /// its only argument, and the severity that corresponds to the error's severity.
    ///
    /// - Parameter error: The error that a delegate reported.
    public init(_ error: ECoreValidationError) {
        let severity: DiagnosticSeverity =
            switch error.severity {
            case .error: .error
            case .warning: .warning
            case .info: .information
            }
        self.init(
            severity: severity, code: .delegate, template: .delegateMessage, element: error.objectId,
            feature: error.feature.flatMap { EcoreFeatureName(rawValue: $0) },
            arguments: [error.message])
    }
}

extension Array where Element == EcoreDiagnostic {
    /// The diagnostics followed by those of delegate validation errors.
    ///
    /// - Parameter delegateErrors: The errors that validation delegates reported.
    /// - Returns: A new array with the converted errors appended in order.
    public func merging(delegateErrors: [ECoreValidationError]) -> [EcoreDiagnostic] {
        self + delegateErrors.map { EcoreDiagnostic($0) }
    }
}
