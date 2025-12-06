//
//  ATLVirtualMachine.swift
//  ATL
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import OrderedCollections

/// Actor responsible for executing ATL transformations.
///
/// The ATL Virtual Machine orchestrates the execution of Atlas Transformation Language
/// modules, coordinating matched rule evaluation, called rule invocation, and helper
/// function execution. It provides a concurrent execution environment that maintains
/// transformation state consistency while enabling parallel rule processing.
///
/// ## Overview
///
/// The virtual machine operates through several execution phases:
/// - **Initialisation**: Module validation and execution context setup
/// - **Matched Rule Execution**: Automatic rule triggering for matching elements
/// - **Lazy Binding Resolution**: Deferred property binding and reference resolution
/// - **Called Rule Processing**: Explicit rule invocation as requested
/// - **Finalisation**: Target model validation and resource cleanup
///
/// ## Execution Model
///
/// ATL transformations follow a hybrid declarative-imperative model:
/// - **Declarative Phase**: Matched rules execute automatically for all matching source elements
/// - **Imperative Phase**: Called rules execute on-demand through explicit invocations
/// - **Resolution Phase**: Lazy bindings resolve forward references and circular dependencies
///
/// ## Concurrency Design
///
/// The virtual machine is implemented as an actor to ensure thread-safe transformation
/// execution. Rule processing can occur concurrently for independent elements while
/// maintaining serialised access to shared transformation state.
///
/// ## Example Usage
///
/// ```swift
/// let vm = ATLVirtualMachine(module: transformationModule)
///
/// try await vm.execute(
///     sources: ["IN": sourceResource],
///     targets: ["OUT": targetResource]
/// )
/// ```
public actor ATLVirtualMachine {

    // MARK: - Properties

    /// The ATL module to execute.
    ///
    /// The module contains transformation rules, helper functions, and metamodel
    /// specifications that define the transformation behaviour.
    public let module: ATLModule

    /// The execution context managing transformation state.
    ///
    /// The execution context provides access to models, variables, trace links,
    /// and other state required for transformation execution.
    private var executionContext: ATLExecutionContext

    /// Statistics tracking transformation execution.
    ///
    /// Execution statistics provide insights into transformation performance
    /// and rule invocation patterns for debugging and optimisation.
    public private(set) var statistics: ATLExecutionStatistics

    // MARK: - Initialisation

    /// Creates a new ATL virtual machine for the specified module.
    ///
    /// - Parameter module: The ATL module to execute
    public init(module: ATLModule) {
        self.module = module
        self.executionContext = ATLExecutionContext(module: module)
        self.statistics = ATLExecutionStatistics()
    }

    // MARK: - Transformation Execution

    /// Executes the ATL transformation with the specified models.
    ///
    /// This method orchestrates the complete transformation process, including
    /// matched rule execution, lazy binding resolution, and statistics collection.
    ///
    /// - Parameters:
    ///   - sources: Source models indexed by namespace aliases
    ///   - targets: Target models indexed by namespace aliases
    /// - Throws: ATL execution errors for transformation failures
    ///
    /// - Note: Source and target model aliases must match the module's metamodel specifications
    public func execute(
        sources: OrderedDictionary<String, Resource>,
        targets: OrderedDictionary<String, Resource>
    ) async throws {
        statistics.reset()
        let startTime = Date()

        // Validate model aliases against module specifications
        try validateModelAliases(sources: sources, targets: targets)

        // Configure execution context with models
        for (alias, resource) in sources {
            await executionContext.addSource(alias, resource: resource)
        }
        for (alias, resource) in targets {
            await executionContext.addTarget(alias, resource: resource)
        }

        do {
            // Execute matched rules for all applicable source elements
            try await executeMatchedRules()

            // Resolve lazy bindings for forward references
            try await executionContext.resolveLazyBindings()

            // Update execution statistics
            statistics.executionTime = Date().timeIntervalSince(startTime)
            statistics.successful = true

        } catch {
            statistics.executionTime = Date().timeIntervalSince(startTime)
            statistics.successful = false
            statistics.lastError = error
            throw error
        }
    }

    // MARK: - Matched Rule Execution

    /// Executes all matched rules for applicable source elements.
    ///
    /// Matched rule execution involves iterating through all source model elements,
    /// testing rule applicability, and executing transformation logic for matching elements.
    ///
    /// - Throws: ATL execution errors for rule execution failures
    private func executeMatchedRules() async throws {
        for rule in module.matchedRules {
            try await executeMatchedRule(rule)
        }
    }

    /// Executes a specific matched rule for all applicable source elements.
    ///
    /// - Parameter rule: The matched rule to execute
    /// - Throws: ATL execution errors for rule execution failures
    private func executeMatchedRule(_ rule: ATLMatchedRule) async throws {
        statistics.rulesExecuted += 1

        // Parse source pattern to determine element type and namespace
        let typeComponents = rule.sourcePattern.type.split(separator: "!")
        guard typeComponents.count == 2 else {
            throw ATLExecutionError.typeError(
                "Invalid source type specification: '\(rule.sourcePattern.type)'"
            )
        }

        let sourceAlias = String(typeComponents[0])
        let sourceClassName = String(typeComponents[1])

        // Get source resource
        guard let sourceResource = await executionContext.getSource(sourceAlias) else {
            throw ATLExecutionError.invalidOperation("Source model '\(sourceAlias)' not found")
        }

        // Get source metamodel
        guard let sourceMetamodel = module.sourceMetamodels[sourceAlias] else {
            throw ATLExecutionError.invalidOperation("Source metamodel '\(sourceAlias)' not found")
        }

        // Find source class
        guard let sourceClass = sourceMetamodel.getClassifier(sourceClassName) as? EClass else {
            throw ATLExecutionError.typeError(
                "Class '\(sourceClassName)' not found in metamodel '\(sourceAlias)'"
            )
        }

        // Get all elements of the specified type
        let sourceElements = await sourceResource.getAllInstancesOf(sourceClass)

        // Execute rule for each matching element
        for sourceElement in sourceElements {
            try await executeRuleForElement(rule, sourceElement: sourceElement)
            statistics.elementsProcessed += 1
        }
    }

    /// Executes a matched rule for a specific source element.
    ///
    /// - Parameters:
    ///   - rule: The matched rule to execute
    ///   - sourceElement: The source element to transform
    /// - Throws: ATL execution errors for rule execution failures
    private func executeRuleForElement(_ rule: ATLMatchedRule, sourceElement: any EObject)
        async throws
    {
        // Create new execution scope for rule
        await executionContext.pushScope()
        defer {
            Task {
                await executionContext.popScope()
            }
        }

        // Bind source element to pattern variable
        await executionContext.setVariable(rule.sourcePattern.variableName, value: sourceElement)

        // Evaluate guard condition if present
        if let guardExpression = rule.`guard` {
            let guardResult = try await guardExpression.evaluate(in: executionContext)
            guard let guardBool = guardResult as? Bool, guardBool else {
                return  // Guard failed, skip rule execution
            }
        }

        // Create target elements for each target pattern
        var createdElements: [EUUID] = []

        for targetPattern in rule.targetPatterns {
            let targetElement = try await createTargetElement(targetPattern)
            createdElements.append(targetElement.id)

            // Bind target element to pattern variable
            await executionContext.setVariable(targetPattern.variableName, value: targetElement)

            // Apply property bindings
            try await applyPropertyBindings(targetPattern, targetElement: targetElement)
        }

        // Record trace link
        await executionContext.addTraceLink(
            ruleName: rule.name,
            sourceElement: sourceElement.id,
            targetElements: createdElements
        )
    }

    /// Creates a target element according to the target pattern specification.
    ///
    /// - Parameter pattern: The target pattern defining element creation
    /// - Returns: The created target element
    /// - Throws: ATL execution errors for element creation failures
    private func createTargetElement(_ pattern: ATLTargetPattern) async throws -> any EObject {
        // Parse target type specification
        let typeComponents = pattern.type.split(separator: "!")
        guard typeComponents.count == 2 else {
            throw ATLExecutionError.typeError(
                "Invalid target type specification: '\(pattern.type)'"
            )
        }

        let targetAlias = String(typeComponents[0])

        return try await executionContext.createElement(type: pattern.type, in: targetAlias)
    }

    /// Applies property bindings to a target element.
    ///
    /// - Parameters:
    ///   - pattern: The target pattern containing property bindings
    ///   - targetElement: The target element to configure
    /// - Throws: ATL execution errors for binding failures
    private func applyPropertyBindings(_ pattern: ATLTargetPattern, targetElement: any EObject)
        async throws
    {
        for (propertyName, expression) in pattern.bindings {
            do {
                let propertyValue = try await expression.evaluate(in: executionContext)
                try setElementProperty(targetElement, property: propertyName, value: propertyValue)
            } catch {
                // For forward references, create lazy binding
                let lazyBinding = ATLLazyBinding(
                    targetElement: targetElement.id,
                    property: propertyName,
                    expression: expression
                )
                await executionContext.addLazyBinding(lazyBinding)
            }
        }
    }

    /// Sets a property value on a target element.
    ///
    /// - Parameters:
    ///   - element: The target element to modify
    ///   - property: The property name to set
    ///   - value: The property value to assign
    /// - Throws: ATL execution errors for invalid property operations
    private func setElementProperty(_ element: any EObject, property: String, value: Any?) throws {
        guard let eClass = element.eClass as? EClass else {
            throw ATLExecutionError.typeError(
                "Element eClass is not an EClass: \(type(of: element.eClass))"
            )
        }

        guard let feature = eClass.getStructuralFeature(name: property) else {
            throw ATLExecutionError.invalidOperation(
                "Property '\(property)' not found in class '\(eClass.name)'"
            )
        }

        var mutableElement = element
        mutableElement.eSet(feature, value as? (any EcoreValue))
    }

    // MARK: - Called Rule Execution

    /// Executes a called rule with the specified parameters.
    ///
    /// Called rules provide imperative transformation capabilities within the
    /// otherwise declarative ATL framework. They are invoked explicitly with
    /// parameters and can create multiple target elements.
    ///
    /// - Parameters:
    ///   - ruleName: The name of the called rule to execute
    ///   - arguments: The argument values to pass to the rule
    /// - Returns: The created target elements
    /// - Throws: ATL execution errors for rule execution failures
    public func executeCalledRule(_ ruleName: String, arguments: [(any EcoreValue)?]) async throws
        -> [any EObject]
    {
        guard let rule = module.calledRules[ruleName] else {
            throw ATLExecutionError.invalidOperation("Called rule '\(ruleName)' not found")
        }

        // Verify argument count
        guard arguments.count == rule.parameters.count else {
            throw ATLExecutionError.invalidOperation(
                "Called rule '\(ruleName)' expects \(rule.parameters.count) arguments, got \(arguments.count)"
            )
        }

        // Create new execution scope
        await executionContext.pushScope()
        defer {
            Task {
                await executionContext.popScope()
            }
        }

        // Bind parameters
        for (parameter, argument) in zip(rule.parameters, arguments) {
            await executionContext.setVariable(parameter.name, value: argument)
        }

        // Create target elements
        var createdElements: [any EObject] = []
        for targetPattern in rule.targetPatterns {
            let targetElement = try await createTargetElement(targetPattern)
            createdElements.append(targetElement)

            // Bind target element variable
            await executionContext.setVariable(targetPattern.variableName, value: targetElement)

            // Apply property bindings
            try await applyPropertyBindings(targetPattern, targetElement: targetElement)
        }

        // Execute rule body statements
        for statement in rule.body {
            try await statement.execute(in: executionContext)
        }

        statistics.calledRulesExecuted += 1
        return createdElements
    }

    // MARK: - Validation

    /// Validates that model aliases match module specifications.
    ///
    /// - Parameters:
    ///   - sources: Source models to validate
    ///   - targets: Target models to validate
    /// - Throws: ATL execution errors for mismatched aliases
    private func validateModelAliases(
        sources: OrderedDictionary<String, Resource>,
        targets: OrderedDictionary<String, Resource>
    ) throws {
        // Validate source aliases
        for sourceAlias in module.sourceMetamodels.keys {
            guard sources[sourceAlias] != nil else {
                throw ATLExecutionError.invalidOperation(
                    "Source model '\(sourceAlias)' required by module but not provided"
                )
            }
        }

        // Validate target aliases
        for targetAlias in module.targetMetamodels.keys {
            guard targets[targetAlias] != nil else {
                throw ATLExecutionError.invalidOperation(
                    "Target model '\(targetAlias)' required by module but not provided"
                )
            }
        }
    }

    // MARK: - Statistics Access

    /// Retrieves current execution statistics.
    ///
    /// - Returns: The current execution statistics
    public func getStatistics() -> ATLExecutionStatistics {
        return statistics
    }
}

// MARK: - ATL Execution Statistics

/// Statistics tracking ATL transformation execution performance and behaviour.
///
/// Execution statistics provide insights into transformation performance,
/// rule invocation patterns, and element processing metrics for debugging
/// and optimisation purposes.
public struct ATLExecutionStatistics: Sendable {

    // MARK: - Properties

    /// The total execution time for the transformation.
    public var executionTime: TimeInterval = 0

    /// Whether the transformation completed successfully.
    public var successful: Bool = false

    /// The number of matched rules executed.
    public var rulesExecuted: Int = 0

    /// The number of called rules executed.
    public var calledRulesExecuted: Int = 0

    /// The number of source elements processed.
    public var elementsProcessed: Int = 0

    /// The number of target elements created.
    public var elementsCreated: Int = 0

    /// The number of trace links recorded.
    public var traceLinksCreated: Int = 0

    /// The number of lazy bindings resolved.
    public var lazyBindingsResolved: Int = 0

    /// The last error encountered during execution, if any.
    public var lastError: Error?

    // MARK: - Initialisation

    /// Creates new execution statistics with default values.
    public init() {}

    // MARK: - Statistics Management

    /// Resets all statistics to their initial values.
    public mutating func reset() {
        executionTime = 0
        successful = false
        rulesExecuted = 0
        calledRulesExecuted = 0
        elementsProcessed = 0
        elementsCreated = 0
        traceLinksCreated = 0
        lazyBindingsResolved = 0
        lastError = nil
    }

    /// Provides a formatted summary of execution statistics.
    ///
    /// - Returns: A human-readable statistics summary
    public func summary() -> String {
        let status = successful ? "✅ Success" : "❌ Failed"
        let duration = String(format: "%.3f", executionTime * 1000)

        return """
            ATL Execution Summary:
            Status: \(status)
            Duration: \(duration)ms
            Rules Executed: \(rulesExecuted)
            Called Rules: \(calledRulesExecuted)
            Elements Processed: \(elementsProcessed)
            Elements Created: \(elementsCreated)
            Trace Links: \(traceLinksCreated)
            Lazy Bindings: \(lazyBindingsResolved)
            """
    }
}
