//
// ECoreDelegateRegistry.swift
// ECore
//
// Created by Rene Hexel on 7/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

/// Registry for delegates.
///
/// The delegate registry provides a central location for managing operation,
/// validation, and setting delegates, supporting namespace-based organisation
/// and URI-based lookup compatible with Eclipse EMF delegate patterns.
public actor ECoreDelegateRegistry: Sendable {
    /// Operation delegates indexed by namespace URI.
    private var operationDelegates: [String: ECoreOperationDelegate] = [:]

    /// Validation delegates indexed by namespace URI.
    private var validationDelegates: [String: ECoreValidationDelegate] = [:]

    /// Setting delegates indexed by namespace URI.
    private var settingDelegates: [String: ECoreSettingDelegate] = [:]

    /// Shared registry instance.
    public static let shared = ECoreDelegateRegistry()

    private init() {}

    // MARK: - Operation Delegates

    /// Register an operation delegate for a namespace URI.
    ///
    /// - Parameters:
    ///   - delegate: The operation delegate to register
    ///   - uri: The namespace URI for this delegate
    public func register(operationDelegate delegate: ECoreOperationDelegate,
                        forURI uri: String) {
        operationDelegates[uri] = delegate
    }

    /// Get the operation delegate for a namespace URI.
    ///
    /// - Parameter uri: The namespace URI
    /// - Returns: The registered delegate, or `nil` if none found
    public func getOperationDelegate(forURI uri: String) -> ECoreOperationDelegate? {
        return operationDelegates[uri]
    }

    // MARK: - Validation Delegates

    /// Register a validation delegate for a namespace URI.
    ///
    /// - Parameters:
    ///   - delegate: The validation delegate to register
    ///   - uri: The namespace URI for this delegate
    public func register(validationDelegate delegate: ECoreValidationDelegate,
                        forURI uri: String) {
        validationDelegates[uri] = delegate
    }

    /// Get the validation delegate for a namespace URI.
    ///
    /// - Parameter uri: The namespace URI
    /// - Returns: The registered delegate, or `nil` if none found
    public func getValidationDelegate(forURI uri: String) -> ECoreValidationDelegate? {
        return validationDelegates[uri]
    }

    // MARK: - Setting Delegates

    /// Register a setting delegate for a namespace URI.
    ///
    /// - Parameters:
    ///   - delegate: The setting delegate to register
    ///   - uri: The namespace URI for this delegate
    public func register(settingDelegate delegate: ECoreSettingDelegate,
                        forURI uri: String) {
        settingDelegates[uri] = delegate
    }

    /// Get the setting delegate for a namespace URI.
    ///
    /// - Parameter uri: The namespace URI
    /// - Returns: The registered delegate, or `nil` if none found
    public func getSettingDelegate(forURI uri: String) -> ECoreSettingDelegate? {
        return settingDelegates[uri]
    }

    // MARK: - Registry Management

    /// Remove all delegates for a namespace URI.
    ///
    /// - Parameter uri: The namespace URI to clear
    public func clearDelegates(forURI uri: String) {
        operationDelegates.removeValue(forKey: uri)
        validationDelegates.removeValue(forKey: uri)
        settingDelegates.removeValue(forKey: uri)
    }

    /// Get all registered namespace URIs.
    ///
    /// - Returns: Set of all registered URIs
    public func getRegisteredURIs() -> Set<String> {
        let operationURIs = Set(operationDelegates.keys)
        let validationURIs = Set(validationDelegates.keys)
        let settingURIs = Set(settingDelegates.keys)
        return operationURIs.union(validationURIs).union(settingURIs)
    }

    /// Remove all registered delegates.
    public func clearAll() {
        operationDelegates.removeAll()
        validationDelegates.removeAll()
        settingDelegates.removeAll()
    }

    /// Get statistics about registered delegates.
    ///
    /// - Returns: Dictionary containing delegate counts by type
    public func getStatistics() -> [String: Int] {
        return [
            "operationDelegates": operationDelegates.count,
            "validationDelegates": validationDelegates.count,
            "settingDelegates": settingDelegates.count,
            "totalURIs": getRegisteredURIs().count
        ]
    }
}
