//
// ECoreDelegate.swift
// ECore
//
//  Created by Rene Hexel on 8/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Delegate for handling ECore operations.
///
/// Operation delegates provide custom implementation for EOperations,
/// allowing dynamic behaviour injection into the ECore model.
public protocol ECoreOperationDelegate: Sendable {
    /// Invoke an operation on an object.
    ///
    /// - Parameters:
    ///   - operation: The EOperationInfo to invoke
    ///   - object: The object to invoke the operation on
    ///   - arguments: The operation arguments
    /// - Returns: The operation result
    /// - Throws: Error if invocation fails
    func invoke(
        operation: EOperationInfo,
        on object: any EObject,
        arguments: [Any?]
    ) async throws -> Any?
}

/// Delegate for validating ECore constraints.
///
/// Validation delegates provide custom constraint checking,
/// extending beyond basic type validation to business rules.
public protocol ECoreValidationDelegate: Sendable {
    /// Validate an object against its constraints.
    ///
    /// - Parameter object: The object to validate
    /// - Returns: Array of validation errors (empty if valid)
    /// - Throws: Error if validation process fails
    func validate(_ object: any EObject) async throws -> [ECoreValidationError]
}

/// Delegate for derived feature computation.
///
/// Setting delegates provide computed values for derived features,
/// enabling dynamic property calculation based on other model elements.
public protocol ECoreSettingDelegate: Sendable {
    /// Get the computed value for a derived feature.
    ///
    /// - Parameters:
    ///   - feature: The structural feature to compute
    ///   - object: The object owning the feature
    /// - Returns: The computed value
    /// - Throws: Error if computation fails
    func getValue(
        for feature: any EStructuralFeature,
        from object: any EObject
    ) async throws -> Any?
}

/// Validation error information.
public struct ECoreValidationError: Sendable, Equatable, Hashable, CustomStringConvertible {
    /// The error message.
    public let message: String

    /// The object that failed validation.
    public let objectId: EUUID

    /// The feature that caused the error (if applicable).
    public let feature: String?

    /// The severity level of the error.
    public let severity: Severity

    public enum Severity: Sendable, Equatable, Hashable, CaseIterable {
        case error
        case warning
        case info
    }

    public init(
        message: String, objectId: EUUID, feature: String? = nil, severity: Severity = .error
    ) {
        self.message = message
        self.objectId = objectId
        self.feature = feature
        self.severity = severity
    }

    public var description: String {
        let featureText = feature.map { " (feature: \($0))" } ?? ""
        return "[\(severity)] \(message) [object: \(objectId)]\(featureText)"
    }
}

/// EOperation information for delegate operations.
///
/// This provides operation metadata without conflicting with the existing EOperation protocol.
public struct EOperationInfo: Sendable, Equatable, Hashable {
    public let name: String
    public let parameters: [EParameterInfo]
    public let returnTypeName: String?

    public init(name: String, parameters: [EParameterInfo] = [], returnTypeName: String? = nil) {
        self.name = name
        self.parameters = parameters
        self.returnTypeName = returnTypeName
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(parameters)
        hasher.combine(returnTypeName)
    }

    public static func == (lhs: EOperationInfo, rhs: EOperationInfo) -> Bool {
        return lhs.name == rhs.name && lhs.parameters == rhs.parameters
            && lhs.returnTypeName == rhs.returnTypeName
    }
}

/// EParameter information for operation parameters.
public struct EParameterInfo: Sendable, Equatable, Hashable {
    public let name: String
    public let eTypeName: String
    public let lowerBound: Int
    public let upperBound: Int

    public init(name: String, eTypeName: String, lowerBound: Int = 1, upperBound: Int = 1) {
        self.name = name
        self.eTypeName = eTypeName
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(eTypeName)
        hasher.combine(lowerBound)
        hasher.combine(upperBound)
    }

    public static func == (lhs: EParameterInfo, rhs: EParameterInfo) -> Bool {
        return lhs.name == rhs.name && lhs.eTypeName == rhs.eTypeName
            && lhs.lowerBound == rhs.lowerBound && lhs.upperBound == rhs.upperBound
    }
}
