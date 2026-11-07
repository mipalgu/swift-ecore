//
// OCLAnnotation.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The annotation sources and detail keys with which Ecore models carry OCL constraints.
///
/// The constraints follow the convention of Eclipse OCL, so that a model written by either
/// tool is read the same way by the other:
///
/// - An invariant of a classifier is a detail of an annotation with the ``pivotSource`` source,
///   keyed by the name of the invariant, and the name is listed in the `constraints` detail of
///   the annotation with the ``AnnotationSource/ecore`` source.
/// - The body of an operation is the ``bodyKey`` detail; its preconditions and postconditions
///   are the ``preconditionKey`` and ``postconditionKey`` details, followed by an underscore
///   and the name of the condition when it has one.
/// - The derivation and initial value of a structural feature are the ``derivationKey`` and
///   ``initialKey`` details.
/// - The root package names the ``pivotSource`` as its validation, invocation and setting
///   delegate in its annotation with the ``AnnotationSource/ecore`` source.
public enum OCLAnnotation {
    /// The source of the annotations that hold OCL expressions for the Pivot delegates.
    public static let pivotSource = AnnotationSource.ocl + "/Pivot"

    /// The source of the annotations that hold OCL expressions for the legacy delegates.
    public static let legacySource = AnnotationSource.ocl

    /// The sources whose annotations hold OCL expressions, the preferred one first.
    public static let expressionSources = [pivotSource, legacySource]

    /// The source of the annotation of a package that records its imports.
    public static let importSource = "http://www.eclipse.org/OCL/Import"

    /// The detail key of the body of an operation.
    public static let bodyKey = "body"

    /// The detail key of an unnamed precondition, and the prefix of a named one.
    public static let preconditionKey = "pre"

    /// The detail key of an unnamed postcondition, and the prefix of a named one.
    public static let postconditionKey = "post"

    /// The separator between the key prefix of a condition and its name.
    public static let conditionNameSeparator = "_"

    /// The detail key of the derivation of a structural feature.
    public static let derivationKey = "derivation"

    /// The detail key of the initial value of a structural feature.
    public static let initialKey = "initial"

    /// The detail key of an invariant without a name.
    public static let unnamedInvariantKey = "null"

    /// The separator between the names of the `constraints` detail.
    public static let constraintNameSeparator = " "

    /// The characters that separate the names of the `constraints` detail when reading it.
    public static let constraintNameSeparators: Set<Character> = [" ", "\t", "\n", ","]

    /// The delegate details of the root package that select the OCL delegates.
    public static let delegateKeys = [
        AnnotationSource.EcoreKey.invocationDelegates,
        AnnotationSource.EcoreKey.settingDelegates,
        AnnotationSource.EcoreKey.validationDelegates,
    ]

    /// The detail key of a precondition with the given name.
    ///
    /// - Parameter name: The name of the precondition, or `nil` for an unnamed one.
    /// - Returns: The key under which the precondition is stored.
    public static func preconditionKey(named name: String?) -> String {
        name.map { preconditionKey + conditionNameSeparator + $0 } ?? preconditionKey
    }

    /// The detail key of a postcondition with the given name.
    ///
    /// - Parameter name: The name of the postcondition, or `nil` for an unnamed one.
    /// - Returns: The key under which the postcondition is stored.
    public static func postconditionKey(named name: String?) -> String {
        name.map { postconditionKey + conditionNameSeparator + $0 } ?? postconditionKey
    }
}
