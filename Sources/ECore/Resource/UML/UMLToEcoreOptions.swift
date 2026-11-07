//
// UMLToEcoreOptions.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

extension UMLToEcore {
    /// What the converter does when it meets a construct that an option governs.
    ///
    /// The choices are those of the Eclipse UML2 converter (`UMLUtil.UML2EcoreConverter`).
    /// Not every option offers every choice; an option treats a choice it does not offer as
    /// ``report``.
    public enum Choice: String, Sendable, Hashable, CaseIterable, Codable {
        /// Leave the construct as the plain mapping produces it, silently.
        case ignore = "IGNORE"
        /// Leave the construct as the plain mapping produces it, and report it as a warning.
        case report = "REPORT"
        /// Remove the construct from the metamodel, and report that as a warning.
        case discard = "DISCARD"
        /// Change the metamodel as Eclipse UML2 does, and report that as information.
        case process = "PROCESS"
    }

    /// The Ecore types that the primitive types of UML become.
    public enum PrimitiveTypeMapping: String, Sendable, Hashable, CaseIterable, Codable {
        /// The Ecore data types with the same instance classes: `Boolean` becomes `EBoolean`,
        /// `Integer` and `UnlimitedNatural` become `EInt`, `Real` becomes `EDouble` and
        /// `String` becomes `EString`.
        case ecore
        /// The data types of the Eclipse UML2 types package (`http://www.eclipse.org/uml2/5.0.0/Types`),
        /// as Eclipse UML2 refers to them; the package is registered with the resource set of
        /// the converted metamodel.
        case umlTypes
    }

    /// The settings of a conversion of UML class models into Ecore metamodels.
    ///
    /// The options mirror those of the Eclipse UML2 converter, under the same names in lower
    /// camel case (for example ``derivedFeatures`` for `DERIVED_FEATURES`). Three presets are
    /// provided:
    ///
    /// - ``standard`` (the default): the choices of the Eclipse UML2 "Convert to Ecore" dialog,
    ///   except that names are kept as they are, invariants become OCL constraints rather than
    ///   validation operations, and OCL expressions are recorded for the Eclipse OCL Pivot
    ///   delegates;
    /// - ``eclipseDialog``: the choices of the Eclipse UML2 "Convert to Ecore" dialog;
    /// - ``eclipseAPI``: every option ignored, as `UMLUtil.convertToEcore` does without options.
    ///
    /// ```swift
    /// var options = UMLToEcore.Options()
    /// options.duplicateFeatures = .discard
    /// let converted = try await UMLToEcore.convert(resource, options: options)
    /// ```
    public struct Options: Sendable, Hashable, Codable {
        /// Applies the tagged values of the Ecore profile, such as `nsURI` or `isTransient`.
        public var ecoreTaggedValues: Choice
        /// Records the operations that an operation redefines in a `redefines` annotation.
        public var redefiningOperations: Choice
        /// Records the features that a feature redefines in a `redefines` annotation.
        public var redefiningProperties: Choice
        /// Records the features that a feature subsets in a `subsets` annotation.
        public var subsettingProperties: Choice
        /// Makes derived unions read-only, transient and volatile, with a `union` annotation.
        public var unionProperties: Choice
        /// Makes derived features transient and volatile, and not containments.
        public var derivedFeatures: Choice
        /// Moves (``Choice/process``) or removes (``Choice/discard``) operations with the
        /// signature of an inherited operation.
        public var duplicateOperations: Choice
        /// Handles operations inherited more than once; only ``Choice/ignore`` is implemented.
        public var duplicateOperationInheritance: Choice
        /// Moves (``Choice/process``) or removes (``Choice/discard``) features with the name of
        /// an inherited feature.
        public var duplicateFeatures: Choice
        /// Handles features inherited more than once; only ``Choice/ignore`` is implemented.
        public var duplicateFeatureInheritance: Choice
        /// Orders the super classes of each class by the number of their features.
        public var superClassOrder: Choice
        /// Copies the details of the annotations of UML elements to the Ecore elements.
        public var annotationDetails: Choice
        /// Converts the named constraints of classifiers into invariants.
        public var invariantConstraints: Choice
        /// Records OCL invariants for validation delegates.
        public var validationDelegates: Choice
        /// Records invariants as constraints of their classifier rather than as validation operations.
        public var nonAPIInvariants: Choice
        /// Records the bodies of operations as annotations.
        public var operationBodies: Choice
        /// Records OCL operation bodies for invocation delegates.
        public var invocationDelegates: Choice
        /// Records OCL default value expressions as initial values or derivations of setting delegates.
        public var propertyDefaultExpressions: Choice
        /// Records comments as GenModel documentation.
        public var comments: Choice
        /// Converts names into camel case.
        public var camelCaseNames: Choice
        /// Types untyped properties as references to `EObject` (``Choice/process``) or removes
        /// them (``Choice/discard``).
        public var untypedProperties: Choice
        /// Records the name of the opposite end of a unidirectional reference.
        public var oppositeRoleNames: Choice
        /// Makes optional single-valued attributes of primitive types unsettable.
        public var unsettablePrimitiveAttributes: Choice
        /// Types optional single-valued enumeration attributes by a nullable data type.
        public var nullableEnumAttributes: Choice
        /// Converts navigable association ends that the association owns into features of the
        /// class at the other end.
        ///
        /// Eclipse UML2 converts only the properties that classifiers own, so this option has no
        /// counterpart there: ``Choice/ignore`` is the behaviour of Eclipse UML2.
        public var navigableAssociationOwnedEnds: Choice
        /// The delegate URI under which OCL expressions are recorded.
        public var oclDelegateURI: String
        /// The separator between the paragraphs of documentation that is assembled from several comments.
        public var lineSeparator: String
        /// The Ecore types that the primitive types of UML become.
        public var primitiveTypes: PrimitiveTypeMapping

        /// Creates options, by default those of ``standard``.
        ///
        /// - Parameters:
        ///   - ecoreTaggedValues: The choice for Ecore tagged values (default ``Choice/process``).
        ///   - redefiningOperations: The choice for redefining operations (default ``Choice/process``).
        ///   - redefiningProperties: The choice for redefining properties (default ``Choice/process``).
        ///   - subsettingProperties: The choice for subsetting properties (default ``Choice/process``).
        ///   - unionProperties: The choice for derived unions (default ``Choice/process``).
        ///   - derivedFeatures: The choice for derived features (default ``Choice/process``).
        ///   - duplicateOperations: The choice for duplicate operations (default ``Choice/process``).
        ///   - duplicateOperationInheritance: The choice for operations inherited more than once
        ///     (default ``Choice/ignore``).
        ///   - duplicateFeatures: The choice for duplicate features (default ``Choice/process``).
        ///   - duplicateFeatureInheritance: The choice for features inherited more than once
        ///     (default ``Choice/ignore``).
        ///   - superClassOrder: The choice for the order of super classes (default ``Choice/process``).
        ///   - annotationDetails: The choice for annotation details (default ``Choice/process``).
        ///   - invariantConstraints: The choice for invariant constraints (default ``Choice/process``).
        ///   - validationDelegates: The choice for validation delegates (default ``Choice/process``).
        ///   - nonAPIInvariants: The choice for non-API invariants (default ``Choice/process``).
        ///   - operationBodies: The choice for operation bodies (default ``Choice/process``).
        ///   - invocationDelegates: The choice for invocation delegates (default ``Choice/process``).
        ///   - propertyDefaultExpressions: The choice for default value expressions (default ``Choice/process``).
        ///   - comments: The choice for comments (default ``Choice/process``).
        ///   - camelCaseNames: The choice for camel case names (default ``Choice/ignore``).
        ///   - untypedProperties: The choice for untyped properties (default ``Choice/report``).
        ///   - oppositeRoleNames: The choice for opposite role names (default ``Choice/ignore``).
        ///   - unsettablePrimitiveAttributes: The choice for optional primitive attributes (default ``Choice/ignore``).
        ///   - nullableEnumAttributes: The choice for optional enumeration attributes (default ``Choice/ignore``).
        ///   - navigableAssociationOwnedEnds: The choice for navigable ends that associations own
        ///     (default ``Choice/report``).
        ///   - oclDelegateURI: The OCL delegate URI (default ``Syntax/oclPivotDelegate``).
        ///   - lineSeparator: The separator of documentation paragraphs (default a line feed).
        ///   - primitiveTypes: The mapping of UML primitive types (default ``PrimitiveTypeMapping/ecore``).
        public init(
            ecoreTaggedValues: Choice = .process, redefiningOperations: Choice = .process,
            redefiningProperties: Choice = .process, subsettingProperties: Choice = .process,
            unionProperties: Choice = .process, derivedFeatures: Choice = .process,
            duplicateOperations: Choice = .process, duplicateOperationInheritance: Choice = .ignore,
            duplicateFeatures: Choice = .process, duplicateFeatureInheritance: Choice = .ignore,
            superClassOrder: Choice = .process, annotationDetails: Choice = .process,
            invariantConstraints: Choice = .process, validationDelegates: Choice = .process,
            nonAPIInvariants: Choice = .process, operationBodies: Choice = .process,
            invocationDelegates: Choice = .process, propertyDefaultExpressions: Choice = .process,
            comments: Choice = .process, camelCaseNames: Choice = .ignore, untypedProperties: Choice = .report,
            oppositeRoleNames: Choice = .ignore, unsettablePrimitiveAttributes: Choice = .ignore,
            nullableEnumAttributes: Choice = .ignore, navigableAssociationOwnedEnds: Choice = .report,
            oclDelegateURI: String = Syntax.oclPivotDelegate, lineSeparator: String = "\n",
            primitiveTypes: PrimitiveTypeMapping = .ecore
        ) {
            self.ecoreTaggedValues = ecoreTaggedValues
            self.redefiningOperations = redefiningOperations
            self.redefiningProperties = redefiningProperties
            self.subsettingProperties = subsettingProperties
            self.unionProperties = unionProperties
            self.derivedFeatures = derivedFeatures
            self.duplicateOperations = duplicateOperations
            self.duplicateOperationInheritance = duplicateOperationInheritance
            self.duplicateFeatures = duplicateFeatures
            self.duplicateFeatureInheritance = duplicateFeatureInheritance
            self.superClassOrder = superClassOrder
            self.annotationDetails = annotationDetails
            self.invariantConstraints = invariantConstraints
            self.validationDelegates = validationDelegates
            self.nonAPIInvariants = nonAPIInvariants
            self.operationBodies = operationBodies
            self.invocationDelegates = invocationDelegates
            self.propertyDefaultExpressions = propertyDefaultExpressions
            self.comments = comments
            self.camelCaseNames = camelCaseNames
            self.untypedProperties = untypedProperties
            self.oppositeRoleNames = oppositeRoleNames
            self.unsettablePrimitiveAttributes = unsettablePrimitiveAttributes
            self.nullableEnumAttributes = nullableEnumAttributes
            self.navigableAssociationOwnedEnds = navigableAssociationOwnedEnds
            self.oclDelegateURI = oclDelegateURI
            self.lineSeparator = lineSeparator
            self.primitiveTypes = primitiveTypes
        }

        /// The default options: those of the Eclipse UML2 dialog, keeping names, with OCL
        /// constraints and the delegates of Eclipse OCL Pivot.
        public static let standard = Options()

        /// The choices of the "Convert to Ecore" dialog of Eclipse UML2.
        ///
        /// Names are converted into camel case, invariants become validation operations, and
        /// operation bodies are recorded under the UML2 GenModel source rather than for delegates.
        public static let eclipseDialog = Options(
            validationDelegates: .ignore, nonAPIInvariants: .ignore, invocationDelegates: .ignore,
            camelCaseNames: .process, navigableAssociationOwnedEnds: .ignore, oclDelegateURI: Syntax.oclDelegate)

        /// Every option ignored, as `UMLUtil.convertToEcore` converts without options.
        public static let eclipseAPI = Options(
            ecoreTaggedValues: .ignore, redefiningOperations: .ignore, redefiningProperties: .ignore,
            subsettingProperties: .ignore, unionProperties: .ignore, derivedFeatures: .ignore,
            duplicateOperations: .ignore, duplicateOperationInheritance: .ignore, duplicateFeatures: .ignore,
            duplicateFeatureInheritance: .ignore, superClassOrder: .ignore, annotationDetails: .ignore,
            invariantConstraints: .ignore, validationDelegates: .ignore, nonAPIInvariants: .ignore,
            operationBodies: .ignore, invocationDelegates: .ignore, propertyDefaultExpressions: .ignore,
            comments: .ignore, camelCaseNames: .ignore, untypedProperties: .ignore, oppositeRoleNames: .ignore,
            unsettablePrimitiveAttributes: .ignore, nullableEnumAttributes: .ignore,
            navigableAssociationOwnedEnds: .ignore, oclDelegateURI: Syntax.oclDelegate)

        /// The options whose choices beyond ``Choice/ignore`` this converter does not implement,
        /// with their Eclipse UML2 names.
        var unsupported: [(name: String, choice: Choice)] {
            [("DUPLICATE_OPERATION_INHERITANCE", duplicateOperationInheritance),
             ("DUPLICATE_FEATURE_INHERITANCE", duplicateFeatureInheritance)]
                .filter { $0.1 != .ignore }
        }
    }
}
