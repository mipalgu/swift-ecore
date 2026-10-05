//
// EcoreValidator.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Checks the constraints of Ecore on native metamodels.
///
/// The validator is the counterpart of Eclipse's `EcoreValidator`. It works on a
/// ``MetamodelIndex`` and resolves every reference (supertypes, types, opposites) by
/// identifier through that index, so a snapshot that has become stale after an edit never
/// affects the result. Validation is pure and synchronous, and its result is deterministic:
/// diagnostics follow the document order of the elements, and for one element the order of
/// ``EcoreConstraint``.
///
/// After an edit, validate again with ``validate(_:)``, or revalidate only the elements that
/// the edit touched, and those that depend on them, with ``validate(_:in:)``.
///
/// ```swift
/// let index = MetamodelIndex(roots: [package])
/// let diagnostics = EcoreValidator().validate(index)
/// ```
public struct EcoreValidator: Sendable {
    /// The settings that control validation.
    public struct Options: Sendable, Hashable {
        /// The constraints that are not checked.
        public var disabledConstraints: Set<EcoreConstraint>

        /// Whether names must be well-formed Java identifiers.
        ///
        /// This is Eclipse's `STRICT_NAMED_ELEMENT_NAMES` behaviour. When it is `false`, the
        /// constraint ``EcoreConstraint/wellFormedName`` is not checked at all.
        public var strictNames: Bool

        /// Creates options.
        ///
        /// - Parameters:
        ///   - disabledConstraints: The constraints that are not checked (none by default).
        ///   - strictNames: Whether names must be well-formed identifiers (`true` by default).
        public init(disabledConstraints: Set<EcoreConstraint> = [], strictNames: Bool = true) {
            self.disabledConstraints = disabledConstraints
            self.strictNames = strictNames
        }
    }

    /// The settings that control validation.
    public var options: Options

    /// Creates a validator.
    ///
    /// - Parameter options: The settings that control validation (the defaults check every
    ///   constraint strictly).
    public init(options: Options = Options()) {
        self.options = options
    }

    /// Validates every element of a metamodel.
    ///
    /// Elements of external packages are not validated, only the elements of the roots.
    ///
    /// - Parameter index: The index of the metamodel.
    /// - Returns: The problems found, in document order of the elements.
    public func validate(_ index: MetamodelIndex) -> [EcoreDiagnostic] {
        let run = EcoreValidationRun(index: index, options: options)
        for element in index.allElements { run.check(element) }
        return run.diagnostics
    }

    /// Validates some elements of a metamodel.
    ///
    /// Only the diagnostics whose element is one of the given elements are returned; they are
    /// the same diagnostics that ``validate(_:)`` reports for those elements. A constraint
    /// that concerns a container (such as unique names) is reported for the container, so
    /// include the container to recheck it. Identifiers that the index does not know, and
    /// those of external elements, are ignored.
    ///
    /// - Parameters:
    ///   - ids: The identifiers of the elements to validate.
    ///   - index: The index of the metamodel.
    /// - Returns: The problems found, in document order of the elements.
    public func validate(_ ids: Set<EUUID>, in index: MetamodelIndex) -> [EcoreDiagnostic] {
        guard !ids.isEmpty else { return [] }
        let run = EcoreValidationRun(index: index, options: options)
        for element in index.allElements where ids.contains(element.id) { run.check(element) }
        return run.diagnostics
    }
}
