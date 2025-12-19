//
// ECoreExecutionEngine.swift
// ECore
//
//  Created by Rene Hexel on 7/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation
import OCL
import OrderedCollections

/// Core execution engine providing model navigation and query capabilities.
///
/// The execution engine serves as the central coordinator for model operations,
/// providing thread-safe access to navigation, querying, and expression evaluation.
/// It maintains performance optimisations through caching whilst ensuring consistency
/// across concurrent operations.
///
/// ## Architecture
///
/// The engine follows a layered approach:
/// - **Model Access**: Unified interface to source and target models
/// - **Navigation**: Property traversal with caching and type checking
/// - **Expression Evaluation**: OCL-like expression processing
/// - **Type Resolution**: Dynamic type lookup and validation
/// - **Performance**: Intelligent caching and batch operations
///
/// ## Example Usage
///
/// ```swift
/// let engine = ECoreExecutionEngine(models: [
///     "source": sourceModel,
///     "target": targetModel
/// ])
///
/// let result = try await engine.navigate(from: person, property: "name")
/// let instances = engine.allInstancesOf(personClass)
/// ```
public actor ECoreExecutionEngine: Sendable {

    // MARK: - Properties

    /// Models indexed by their namespace aliases.
    private let models: [String: IModel]

    /// Type provider for ECore type operations.
    private let typeProvider: EcoreTypeProvider

    /// Navigation result cache for performance optimisation.
    private var navigationCache: [String: any EcoreValue] = [:]

    /// Type instance cache for frequent queries.
    private var typeCache: [String: OrderedSet<EUUID>] = [:]

    /// Cross-reference resolution cache.
    private var resolutionCache: [EUUID: any EObject] = [:]

    /// Debug mode flag for systematic tracing.
    private var debug: Bool = false

    // MARK: - Initialisation

    /// Creates a new execution engine with the specified models.
    ///
    /// - Parameter models: Dictionary of model aliases to IModel instances
    public init(models: [String: IModel], enableDebugging: Bool = false) {
        self.models = models
        typeProvider = EcoreTypeProvider()
        debug = enableDebugging
    }

    // MARK: - Debug Configuration

    /// Enable or disable debug output for systematic tracing.
    ///
    /// When enabled, the execution engine prints detailed trace information
    /// for navigation operations, method invocations, and expression evaluation.
    ///
    /// - Parameter enabled: Whether to enable debug output
    public func enableDebugging(_ enabled: Bool = true) {
        debug = enabled
    }

    // MARK: - Navigation Operations

    /// Navigate a property from a source object.
    ///
    /// This method provides type-safe property navigation with automatic caching
    /// and cross-reference resolution. It handles both attributes and references,
    /// including collection-valued properties.
    ///
    /// - Parameters:
    ///   - source: The source EObject to navigate from
    ///   - property: The name of the property to navigate
    /// - Returns: The property value, which may be a primitive, EObject, or collection
    /// - Throws: `ECoreExecutionError` if navigation fails
    public func navigate(from source: any EObject, property: String) async throws -> (
        any EcoreValue
    )? {
        if debug {
            print("[ECORE] Navigate: \(source.eClass.name).\(property)")
        }

        let cacheKey = "\(source.id).\(property)"
        if let cached = navigationCache[cacheKey] {
            if debug {
                print("[ECORE]   Cached value: \(String(describing: cached))")
            }
            return cached
        }

        // Get the latest version of the object from its resource
        let currentObject = await getLatestObject(source) ?? source

        let feature = try findStructuralFeature(for: currentObject, named: property)
        let result = currentObject.eGet(feature)

        if debug {
            print("[ECORE]   Value: \(String(describing: result))")
        }

        // Cache the result for future use if it's an EcoreValue
        if let ecoreResult = result {
            navigationCache[cacheKey] = ecoreResult
        }

        return result
    }

    /// Set a property value on an object.
    ///
    /// - Parameters:
    ///   - object: The target EObject to modify
    ///   - property: The name of the property to set
    ///   - value: The new value for the property
    /// - Throws: `ECoreExecutionError` if setting fails or model is read-only
    public func setProperty(_ object: any EObject, property: String, value: (any EcoreValue)?)
        async throws
    {
        // Find the target model that contains this object
        var targetModel: IModel?
        for model in models.values {
            if model.isTarget {
                let isModelOf = await model.isModelOf(object)
                if isModelOf {
                    targetModel = model
                    break
                }
            }
        }

        guard let model = targetModel else {
            throw ECoreExecutionError.readOnlyObject(object.id)
        }

        let feature = try findStructuralFeature(for: object, named: property)

        // Validate value type compatibility
        try validateValueType(value, for: feature)

        // Set the value on a mutable copy and update it in the resource
        var mutableObject = object
        mutableObject.eSet(feature, value)

        // Update the object in the resource
        await model.resource.add(mutableObject)

        // Invalidate navigation cache for this object
        invalidateCache(for: object)
    }

    // MARK: - Query Operations

    /// Find all objects of a given type across all models.
    ///
    /// - Parameter type: The EClass to search for
    /// - Returns: Array of all instances (including subtype instances)
    public func allInstancesOf(_ type: EClass) async -> [any EObject] {
        let cacheKey = type.name

        if let cached = typeCache[cacheKey] {
            var results: [any EObject] = []
            for id in cached {
                for model in models.values {
                    if let obj = await model.resource.resolve(id) {
                        results.append(obj)
                        break
                    }
                }
            }
            return results
        }

        var instances = OrderedSet<EUUID>()
        for model in models.values {
            let modelInstances = await model.getElementsByType(type)
            instances.formUnion(modelInstances)
        }

        typeCache[cacheKey] = instances
        var results: [any EObject] = []
        for id in instances {
            for model in models.values {
                if let obj = await model.resource.resolve(id) {
                    results.append(obj)
                    break
                }
            }
        }
        return results
    }

    /// Find the first object of a given type.
    ///
    /// - Parameter type: The EClass to search for
    /// - Returns: The first matching instance, or `nil` if none found
    public func firstInstanceOf(_ type: EClass) async -> (any EObject)? {
        for model in models.values {
            let typeInstances = await model.getElementsByType(type)
            if let firstId = typeInstances.first {
                if let obj = await model.resource.resolve(firstId) {
                    return obj
                }
            }
        }
        return nil
    }

    // MARK: - Expression Evaluation

    /// Evaluate an expression in the context of given bindings.
    ///
    /// This method provides the core expression evaluation capability,
    /// supporting navigation, variable references, and literal values.
    ///
    /// - Parameters:
    ///   - expression: The expression to evaluate
    ///   - context: Variable bindings for the evaluation context
    /// - Returns: The result of evaluating the expression
    /// - Throws: `ECoreExecutionError` if evaluation fails
    public func evaluate(
        _ expression: ECoreExpression,
        context: [String: any EcoreValue]
    ) async throws -> (any EcoreValue)? {
        if debug {
            print("[ECORE] Evaluating expression: \(expression)")
        }

        switch expression {
        case .navigation(let source, let property):
            if debug {
                print("[ECORE]   Navigation: \(property)")
            }
            let sourceValue = try await evaluateValue(source, context: context)
            guard let sourceObject = sourceValue as? (any EObject) else {
                throw ECoreExecutionError.invalidNavigation(
                    "Source is not an EObject: \(String(describing: sourceValue))")
            }
            let result = try await navigate(from: sourceObject, property: property)
            return result

        case .variable(let name):
            if debug {
                print("[ECORE]   Variable: \(name)")
            }
            return context[name]

        case .literal(let value):
            if debug {
                print("[ECORE]   Literal: \(value)")
            }
            return value.anyValue as? (any EcoreValue)

        case .methodCall(let receiver, let methodName, let arguments):
            let receiverValue = try await evaluateValue(receiver, context: context)
            let argValues = try await evaluateArguments(arguments, context: context)
            let result = try await invokeMethod(
                on: receiverValue, method: methodName, arguments: argValues)
            return result

        case .filter(let collection, let condition):
            let collectionValue = try await evaluateValue(collection, context: context)
            let result = try await filterCollection(
                collectionValue, condition: condition, context: context)
            return EcoreValueArray(result)

        case .select(let collection, let mapper):
            let collectionValue = try await evaluateValue(collection, context: context)
            let result = try await selectFromCollection(
                collectionValue, mapper: mapper, context: context)
            return EcoreValueArray(result)
        }
    }

    // MARK: - Cache Management

    /// Clear all caches to free memory.
    public func clearCaches() {
        navigationCache.removeAll()
        typeCache.removeAll()
        resolutionCache.removeAll()
    }

    /// Get cache statistics for performance monitoring.
    ///
    /// - Returns: Dictionary containing cache hit rates and sizes
    public func getCacheStatistics() -> [String: Int] {
        return [
            "navigationCacheSize": navigationCache.count,
            "typeCacheSize": typeCache.count,
            "resolutionCacheSize": resolutionCache.count,
        ]
    }

    // MARK: - Private Implementation

    private func findStructuralFeature(
        for object: any EObject,
        named property: String
    ) throws -> any EStructuralFeature {
        guard let eClass = object.eClass as? EClass else {
            throw ECoreExecutionError.typeError("Object does not have a valid EClass")
        }
        guard let feature = eClass.getStructuralFeature(name: property) else {
            throw ECoreExecutionError.unknownProperty(property, eClass.name)
        }
        return feature
    }

    private func isInTargetModel(_ object: any EObject) async -> Bool {
        for model in models.values {
            if model.isTarget {
                let isModelOf = await model.isModelOf(object)
                if isModelOf {
                    return true
                }
            }
        }
        return false
    }

    private func validateValueType(_ value: (any EcoreValue)?, for feature: any EStructuralFeature)
        throws
    {
        // Implementation would validate type compatibility
        // For now, we'll skip detailed type checking
    }

    private func invalidateCache(for object: any EObject) {
        let objectId = object.id.uuidString
        navigationCache.keys
            .filter { $0.hasPrefix(objectId) }
            .forEach { navigationCache.removeValue(forKey: $0) }
    }

    private func getLatestObject(_ object: any EObject) async -> (any EObject)? {
        // Find the object in any of our models' resources
        for model in models.values {
            if let latestObject = await model.resource.resolve(object.id) {
                return latestObject
            }
        }
        return nil
    }

    private func evaluateValue(_ expression: ECoreExpression, context: [String: any EcoreValue])
        async throws -> (any EcoreValue)?
    {
        return try await evaluate(expression, context: context)
    }

    private func evaluateArguments(
        _ arguments: [ECoreExpression], context: [String: any EcoreValue]
    ) async throws -> [any EcoreValue] {
        var results: [any EcoreValue] = []
        for arg in arguments {
            if let value = try await evaluate(arg, context: context) {
                results.append(value)
            }
        }
        return results
    }

    private func invokeMethod(on receiver: (any EcoreValue)?, method: String, arguments: [any EcoreValue]) async throws -> (any EcoreValue)? {
        if debug {
            print("[ECORE] Invoking method: \(method)")
            print("[ECORE]   Receiver: \(String(describing: receiver))")
            print("[ECORE]   Arguments: \(arguments.map { String(describing: $0) })")
        }

        // Special handling for oclIsUndefined() - works on nil values
        if arguments.isEmpty, let m = OCLUnaryMethod(rawValue: method), m == .oclIsUndefined {
            let result = (receiver == nil) as any EcoreValue
            if debug {
                print("[ECORE]   Result: \(result)")
            }
            return result
        }

        // Try unary methods (no arguments)
        if arguments.isEmpty, let receiver = receiver {
            if let m = OCLUnaryMethod(rawValue: method) {
                do {
                    let result = try invokeUnaryMethod(m, on: receiver)
                    if debug {
                        print("[ECORE]   Result: \(String(describing: result))")
                    }
                    return result
                } catch {
                    if debug {
                        print("[ECORE]   Error: \(error)")
                    }
                    throw ECoreExecutionError.unsupportedOperation(
                        "Error in \(method): \(error)")
                }
            }
        }

        // Try binary methods (one argument)
        if arguments.count == 1, let receiver = receiver {
            if let m = OCLBinaryMethod(rawValue: method) {
                do {
                    let result = try invokeBinaryMethod(m, on: receiver, with: arguments[0])
                    if debug {
                        print("[ECORE]   Result: \(String(describing: result))")
                    }
                    return result
                } catch {
                    if debug {
                        print("[ECORE]   Error: \(error)")
                    }
                    throw ECoreExecutionError.unsupportedOperation(
                        "Error in \(method): \(error)")
                }
            }
        }

        // Try ternary methods (two arguments)
        if arguments.count == 2, let receiver = receiver {
            if let m = OCLTernaryMethod(rawValue: method) {
                do {
                    let result = try invokeTernaryMethod(m, on: receiver, with: arguments[0], and: arguments[1])
                    if debug {
                        print("[ECORE]   Result: \(String(describing: result))")
                    }
                    return result
                } catch {
                    if debug {
                        print("[ECORE]   Error: \(error)")
                    }
                    throw ECoreExecutionError.unsupportedOperation(
                        "Error in \(method): \(error)")
                }
            }
        }

        // Method not found in OCL enums
        if debug {
            print("[ECORE]   Error: Method not supported")
        }
        throw ECoreExecutionError.unsupportedOperation(
            "Method not supported: \(method) with \(arguments.count) arguments")
    }

    private func filterCollection(
        _ collection: (any EcoreValue)?, condition: ECoreExpression,
        context: [String: any EcoreValue]
    ) async throws -> [any EcoreValue] {
        guard let array = collection as? [any EcoreValue] else {
            throw ECoreExecutionError.typeError(
                "Cannot filter non-collection: \(String(describing: collection))")
        }

        var filtered: [any EcoreValue] = []
        for item in array {
            var itemContext = context
            itemContext["self"] = item

            let conditionResult = try await evaluate(condition, context: itemContext)
            if let boolResult = conditionResult as? Bool, boolResult {
                filtered.append(item)
            }
        }

        return filtered
    }

    private func selectFromCollection(
        _ collection: (any EcoreValue)?, mapper: ECoreExpression, context: [String: any EcoreValue]
    ) async throws -> [any EcoreValue] {
        guard let array = collection as? [any EcoreValue] else {
            throw ECoreExecutionError.typeError(
                "Cannot select from non-collection: \(String(describing: collection))")
        }

        var mapped: [any EcoreValue] = []
        for item in array {
            var itemContext = context
            itemContext["self"] = item

            let mappedValue = try await evaluate(mapper, context: itemContext)
            if let value = mappedValue {
                mapped.append(value)
            }
        }

        return mapped
    }
}
