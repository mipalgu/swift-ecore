//
// EcoreConstraint.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The constraints that ``EcoreValidator`` checks on a native metamodel.
///
/// The raw values are the names that Eclipse's Ecore validator gives its constraints, so a
/// diagnostic can be related to its Eclipse counterpart and used as a stable key for
/// configuration and localisation.
public enum EcoreConstraint: String, Sendable, Hashable, CaseIterable {
    // MARK: Names, packages, and annotations

    /// A name is a well-formed Java identifier (see ``EcoreValidator/Options/strictNames``).
    case wellFormedName = "WellFormedName"
    /// A package's namespace URI is a well-formed URI.
    case wellFormedNsURI = "WellFormedNsURI"
    /// A package's namespace prefix is empty or a valid XML name that does not start with `xml`.
    case wellFormedNsPrefix = "WellFormedNsPrefix"
    /// The subpackages of a package have different names.
    case uniqueSubpackageNames = "UniqueSubpackageNames"
    /// The classifiers of a package have different names; names that differ only by case or
    /// underscores are reported as warnings.
    case uniqueClassifierNames = "UniqueClassifierNames"
    /// No two packages have the same namespace URI.
    case uniqueNsURIs = "UniqueNsURIs"
    /// An annotation's source is a well-formed URI.
    case wellFormedSourceURI = "WellFormedSourceURI"
    /// A classifier's instance class name has the form of a (possibly parameterised) type name.
    case wellFormedInstanceTypeName = "WellFormedInstanceTypeName"

    // MARK: Classes

    /// A class that is an interface is also abstract.
    case interfaceIsAbstract = "InterfaceIsAbstract"
    /// A class has at most one attribute that is an identifier, counting inherited ones.
    case atMostOneID = "AtMostOneID"
    /// The features of a class, including inherited ones, have different names; names that
    /// differ only by case or underscores are reported as warnings.
    case uniqueFeatureNames = "UniqueFeatureNames"
    /// The operations of a class have different signatures.
    case uniqueOperationSignatures = "UniqueOperationSignatures"
    /// No operation of a class has the signature of an accessor of one of its features.
    case disjointFeatureAndOperationSignatures = "DisjointFeatureAndOperationSignatures"
    /// A class is not its own supertype, directly or indirectly.
    case noCircularSuperTypes = "NoCircularSuperTypes"
    /// A map entry class has a key and a value feature, and only map entry classes inherit
    /// from one.
    case wellFormedMapEntryClass = "WellFormedMapEntryClass"

    // MARK: Typed elements and features

    /// A lower bound is not negative.
    case validLowerBound = "ValidLowerBound"
    /// An upper bound is positive, unbounded, or unspecified.
    case validUpperBound = "ValidUpperBound"
    /// A lower bound does not exceed a bounded upper bound.
    case consistentBounds = "ConsistentBounds"
    /// A typed element has a type, an attribute's type is a data type, and a reference's type
    /// is a class.
    case validType = "ValidType"
    /// An operation without a type (void) has an upper bound of one.
    case noRepeatingVoid = "NoRepeatingVoid"
    /// The parameters of an operation have different names.
    case uniqueParameterNames = "UniqueParameterNames"
    /// An attribute's default value literal is a literal of its type.
    case validDefaultValueLiteral = "ValidDefaultValueLiteral"
    /// A non-transient attribute has a serialisable data type.
    case consistentTransient = "ConsistentTransient"

    // MARK: References

    /// Opposite references refer to each other, belong to each other's types, are not their
    /// own opposites, are transient consistently, and are not both containments.
    case consistentOpposite = "ConsistentOpposite"
    /// A container reference is single-valued.
    case singleContainer = "SingleContainer"
    /// The type of a containment does not require its instances to be contained elsewhere.
    case consistentContainer = "ConsistentContainer"
    /// A many-valued containment or bidirectional reference is unique.
    case consistentUnique = "ConsistentUnique"

    // MARK: Enumerations

    /// The literals of an enumeration have different names; names that differ only by case or
    /// underscores are reported as warnings.
    case uniqueEnumeratorNames = "UniqueEnumeratorNames"
    /// The literals of an enumeration have different literal texts.
    case uniqueEnumeratorLiterals = "UniqueEnumeratorLiterals"

    // MARK: Generic declarations and retained references

    /// The keys of a reference are features of its type.
    case consistentKeys = "ConsistentKeys"
    /// A class's generic supertypes are not duplicated or inconsistent.
    case consistentSuperTypes = "ConsistentSuperTypes"
    /// The type parameters of a classifier or operation have different names.
    case uniqueTypeParameterNames = "UniqueTypeParameterNames"
    /// A generic type refers to a suitable classifier or type parameter.
    case consistentType = "ConsistentType"
    /// The bounds of a generic type are well formed.
    case consistentGenericBounds = "ConsistentGenericBounds"
    /// The arguments of a generic type match the type parameters of its classifier.
    case consistentArguments = "ConsistentArguments"
    /// Every reference to another document resolves.
    case everyProxyResolves = "EveryProxyResolves"

    // MARK: Delegates

    /// A problem that a validation delegate reported; see ``EcoreDiagnostic/init(_:)``.
    case delegate = "Delegate"

    /// Whether ``EcoreValidator`` currently checks the constraint.
    ///
    /// Native constraints include generic declarations, keys and retained proxies.
    /// Delegate diagnostics are supplied by validation delegates.
    public var isImplemented: Bool { true }
}
