//
//  ATLModule.swift
//  ATL
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import OrderedCollections

/// Represents an ATL (Atlas Transformation Language) module.
///
/// An ATL module is the root container for a transformation specification, containing
/// source and target metamodels, helper functions, transformation rules, and module-level
/// configuration. ATL modules define unidirectional transformations from source models
/// to target models using declarative matched rules and imperative called rules.
///
/// ## Overview
///
/// ATL modules follow a structured approach to model transformation:
/// - **Source models**: Read-only input models conforming to source metamodels
/// - **Target models**: Write-only output models conforming to target metamodels
/// - **Helpers**: Reusable functions that extend OCL with custom operations
/// - **Matched rules**: Declarative transformation rules triggered automatically
/// - **Called rules**: Imperative transformation rules invoked explicitly
///
/// ## Example Usage
///
/// ```swift
/// let module = ATLModule(
///     name: "Families2Persons",
///     sourceMetamodels: ["Families": familiesPackage],
///     targetMetamodels: ["Persons": personsPackage],
///     helpers: ["familyName": familyNameHelper],
///     matchedRules: [member2MaleRule, member2FemaleRule]
/// )
/// ```
///
/// - Note: ATL modules are designed as immutable value types to enable safe concurrent
///   processing and transformation execution across multiple actors.
public struct ATLModule: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the ATL module.
    ///
    /// Module names must be valid identifiers and are used for namespace resolution
    /// and debugging purposes during transformation execution.
    public let name: String

    /// Source metamodels indexed by their namespace aliases.
    ///
    /// Source metamodels define the structure of input models that will be transformed.
    /// Each metamodel is associated with an alias used in ATL expressions for type
    /// references and navigation operations.
    public let sourceMetamodels: OrderedDictionary<String, EPackage>

    /// Target metamodels indexed by their namespace aliases.
    ///
    /// Target metamodels define the structure of output models that will be created
    /// during transformation execution. Each metamodel is associated with an alias
    /// used in ATL rules for element creation and property assignment.
    public let targetMetamodels: OrderedDictionary<String, EPackage>

    /// Helper functions indexed by their names.
    ///
    /// Helpers extend the OCL standard library with custom operations that can be
    /// invoked from transformation rules and other helpers. They support both
    /// context-dependent and context-independent implementations.
    public let helpers: OrderedDictionary<String, ATLHelper>

    /// Matched rules for automatic transformation execution.
    ///
    /// Matched rules are executed automatically for all source elements that match
    /// their input patterns and satisfy their guard conditions. They form the
    /// declarative backbone of ATL transformations.
    public let matchedRules: [ATLMatchedRule]

    /// Called rules indexed by their names.
    ///
    /// Called rules are executed explicitly through rule invocation expressions.
    /// They support parameterised transformations and imperative control flow
    /// within the otherwise declarative ATL framework.
    public let calledRules: OrderedDictionary<String, ATLCalledRule>

    // MARK: - Initialisation

    /// Creates a new ATL module with the specified configuration.
    ///
    /// - Parameters:
    ///   - name: The module name, used for identification and debugging
    ///   - sourceMetamodels: Source metamodels indexed by namespace aliases
    ///   - targetMetamodels: Target metamodels indexed by namespace aliases
    ///   - helpers: Helper functions indexed by their names (default: empty)
    ///   - matchedRules: Matched rules for automatic execution (default: empty)
    ///   - calledRules: Called rules indexed by their names (default: empty)
    ///
    /// - Precondition: The module name must be a non-empty string
    /// - Precondition: At least one source metamodel must be specified
    /// - Precondition: At least one target metamodel must be specified
    public init(
        name: String,
        sourceMetamodels: OrderedDictionary<String, EPackage>,
        targetMetamodels: OrderedDictionary<String, EPackage>,
        helpers: OrderedDictionary<String, ATLHelper> = [:],
        matchedRules: [ATLMatchedRule] = [],
        calledRules: OrderedDictionary<String, ATLCalledRule> = [:]
    ) {
        precondition(!name.isEmpty, "Module name must not be empty")
        precondition(!sourceMetamodels.isEmpty, "At least one source metamodel must be specified")
        precondition(!targetMetamodels.isEmpty, "At least one target metamodel must be specified")

        self.name = name
        self.sourceMetamodels = sourceMetamodels
        self.targetMetamodels = targetMetamodels
        self.helpers = helpers
        self.matchedRules = matchedRules
        self.calledRules = calledRules
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(sourceMetamodels.keys.sorted())
        hasher.combine(targetMetamodels.keys.sorted())
        hasher.combine(helpers.keys.sorted())
        hasher.combine(matchedRules.count)
        hasher.combine(calledRules.keys.sorted())
    }
}

// MARK: - ATL Helper

/// Represents an ATL helper function.
///
/// ATL helpers extend the OCL standard library with custom operations that can be
/// reused across transformation rules and other helpers. They support both contextual
/// helpers (associated with a specific type) and contextual-free helpers (global functions).
///
/// ## Overview
///
/// Helpers in ATL serve multiple purposes:
/// - **Code reuse**: Complex expressions can be encapsulated and reused
/// - **Type extension**: New operations can be added to existing types
/// - **Modularity**: Complex transformations can be broken down into manageable functions
/// - **Testing**: Individual helper functions can be tested independently
///
/// ## Example Usage
///
/// ```swift
/// // Contextual helper for Family!Member
/// let familyNameHelper = ATLHelper(
///     name: "familyName",
///     contextType: "Families!Member",
///     returnType: "String",
///     parameters: [],
///     body: navigationExpression
/// )
///
/// // Context-free helper
/// let utilityHelper = ATLHelper(
///     name: "formatName",
///     contextType: nil,
///     returnType: "String",
///     parameters: [firstNameParam, lastNameParam],
///     body: concatenationExpression
/// )
/// ```
public struct ATLHelper: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the helper function.
    ///
    /// Helper names must be valid identifiers and are used for invocation
    /// from ATL expressions and other helpers.
    public let name: String

    /// The context type for contextual helpers, or `nil` for context-free helpers.
    ///
    /// Contextual helpers are associated with a specific type and can access
    /// the `self` variable. Context-free helpers operate as global functions
    /// and receive all data through explicit parameters.
    public let contextType: String?

    /// The return type of the helper function.
    ///
    /// Return types are specified using ATL type expressions, supporting
    /// both primitive types and metamodel element types.
    public let returnType: String

    /// The parameters accepted by the helper function.
    ///
    /// Parameters enable helpers to accept additional inputs beyond the
    /// contextual `self` variable for contextual helpers.
    public let parameters: [ATLParameter]

    /// The body expression that defines the helper's computation.
    ///
    /// The body expression is evaluated to compute the helper's return value.
    /// It has access to the contextual `self` variable (for contextual helpers)
    /// and all declared parameters.
    public let body: any ATLExpression

    // MARK: - Initialisation

    /// Creates a new ATL helper function.
    ///
    /// - Parameters:
    ///   - name: The helper name for invocation
    ///   - contextType: The context type, or `nil` for context-free helpers
    ///   - returnType: The return type specification
    ///   - parameters: The parameter list (default: empty)
    ///   - body: The expression that computes the helper's result
    ///
    /// - Precondition: The helper name must be a non-empty string
    /// - Precondition: The return type must be a non-empty string
    public init(
        name: String,
        contextType: String? = nil,
        returnType: String,
        parameters: [ATLParameter] = [],
        body: any ATLExpression
    ) {
        precondition(!name.isEmpty, "Helper name must not be empty")
        precondition(!returnType.isEmpty, "Return type must not be empty")

        self.name = name
        self.contextType = contextType
        self.returnType = returnType
        self.parameters = parameters
        self.body = body
    }

    // MARK: - Equatable

    public static func == (lhs: ATLHelper, rhs: ATLHelper) -> Bool {
        return lhs.name == rhs.name && lhs.contextType == rhs.contextType
            && lhs.returnType == rhs.returnType && lhs.parameters == rhs.parameters
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(contextType)
        hasher.combine(returnType)
        hasher.combine(parameters)
    }
}

// MARK: - ATL Parameter

/// Represents a parameter for ATL helpers and called rules.
///
/// Parameters define the interface for data passing into ATL functions and rules.
/// They specify both the parameter name for binding and the expected type for
/// validation during transformation compilation and execution.
///
/// ## Example Usage
///
/// ```swift
/// let nameParameter = ATLParameter(name: "firstName", type: "String")
/// let elementParameter = ATLParameter(name: "sourceElement", type: "Families!Member")
/// ```
public struct ATLParameter: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the parameter.
    ///
    /// Parameter names are used for variable binding within the scope of
    /// helper functions and called rules.
    public let name: String

    /// The type of the parameter.
    ///
    /// Parameter types are specified using ATL type expressions, supporting
    /// both primitive types and metamodel element types.
    public let type: String

    // MARK: - Initialisation

    /// Creates a new ATL parameter.
    ///
    /// - Parameters:
    ///   - name: The parameter name for variable binding
    ///   - type: The parameter type specification
    ///
    /// - Precondition: The parameter name must be a non-empty string
    /// - Precondition: The parameter type must be a non-empty string
    public init(name: String, type: String) {
        precondition(!name.isEmpty, "Parameter name must not be empty")
        precondition(!type.isEmpty, "Parameter type must not be empty")

        self.name = name
        self.type = type
    }
}
