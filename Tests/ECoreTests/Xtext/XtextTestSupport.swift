//
// XtextTestSupport.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// Helpers that inspect imported packages.
enum XtextInspect {
    /// The class of a package with a name.
    ///
    /// - Parameters:
    ///   - name: The class name.
    ///   - package: The package.
    /// - Returns: The class, or `nil`.
    static func eClass(_ name: String, in package: EPackage?) -> EClass? { package?.getEClass(name) }

    /// The names of a class's own features.
    ///
    /// - Parameter eClass: The class.
    /// - Returns: The feature names in order.
    static func featureNames(_ eClass: EClass?) -> [String] { eClass?.eStructuralFeatures.map(\.name) ?? [] }

    /// The names of a class's direct supertypes.
    ///
    /// - Parameter eClass: The class.
    /// - Returns: The supertype names in order.
    static func superTypeNames(_ eClass: EClass?) -> [String] { eClass?.eSuperTypes.map(\.name) ?? [] }

    /// A reference of a class.
    ///
    /// - Parameters:
    ///   - name: The reference name.
    ///   - eClass: The class.
    /// - Returns: The reference, or `nil`.
    static func reference(_ name: String, of eClass: EClass?) -> EReference? {
        eClass?.eStructuralFeatures.first { $0.name == name } as? EReference
    }

    /// An attribute of a class.
    ///
    /// - Parameters:
    ///   - name: The attribute name.
    ///   - eClass: The class.
    /// - Returns: The attribute, or `nil`.
    static func attribute(_ name: String, of eClass: EClass?) -> EAttribute? {
        eClass?.eStructuralFeatures.first { $0.name == name } as? EAttribute
    }

    /// The validation errors of packages.
    ///
    /// - Parameter packages: The packages.
    /// - Returns: The messages of the errors.
    static func validationErrors(_ packages: [EPackage]) -> [String] {
        EcoreValidator().validate(MetamodelIndex(roots: packages))
            .filter { $0.severity == .error }.map(\.message)
    }

    /// The diagnostics of a severity with a code.
    ///
    /// - Parameters:
    ///   - diagnostics: The diagnostics.
    ///   - code: The code.
    /// - Returns: The matching diagnostics.
    static func diagnostics(_ diagnostics: [SourceDiagnostic], code: String) -> [SourceDiagnostic] {
        diagnostics.filter { $0.code == code }
    }
}
