//
// SDF3TestSupport.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

@testable import ECore

/// Reads SDF3 or Stratego text with the given options.
///
/// - Parameters:
///   - text: The source text.
///   - options: The import options.
/// - Returns: The parse result.
func read(_ text: String, options: SDF3ImportOptions = .init()) -> SDF3ParseResult {
    SDF3Reader.parse(text, sourceName: "test.sdf3", options: options)
}

/// Shortcuts for inspecting parse results in tests.
extension SDF3ParseResult {
    /// The only package of the result.
    var package: EPackage { packages[0] }

    /// The class with a name in the only package.
    ///
    /// - Parameter name: The class name.
    /// - Returns: The class, or `nil` if there is none.
    func eClass(_ name: String) -> EClass? { package.getEClass(name) }

    /// The diagnostics with a code.
    ///
    /// - Parameter code: The diagnostic code.
    /// - Returns: The matching diagnostics.
    func diagnostics(_ code: SDF3DiagnosticCode) -> [SourceDiagnostic] {
        diagnostics.filter { $0.code == code.rawValue }
    }

    /// The error diagnostics.
    var errors: [SourceDiagnostic] { diagnostics.filter { $0.severity == .error } }

    /// The errors that validating the packages with the Ecore validator reports.
    var validationErrors: [EcoreDiagnostic] {
        EcoreValidator().validate(MetamodelIndex(roots: packages)).filter { $0.severity == .error }
    }
}

/// Shortcuts for inspecting classes in tests.
extension EClass {
    /// The reference with a name, declared or inherited.
    ///
    /// - Parameter name: The feature name.
    /// - Returns: The reference, or `nil` if there is none.
    func anyReference(_ name: String) -> EReference? { getStructuralFeature(name: name) as? EReference }

    /// The attribute with a name, declared or inherited.
    ///
    /// - Parameter name: The feature name.
    /// - Returns: The attribute, or `nil` if there is none.
    func anyAttribute(_ name: String) -> EAttribute? { getStructuralFeature(name: name) as? EAttribute }

    /// The names of the declared features, in order.
    var featureNames: [String] { eStructuralFeatures.map(\.name) }

    /// The names of the types of the declared features, in order.
    var featureTypeNames: [String] {
        eStructuralFeatures.map { feature in
            (feature as? EAttribute)?.eType.name ?? (feature as? EReference)?.eType.name ?? ""
        }
    }

    /// The names of the direct supertypes, in order.
    var superTypeNames: [String] { eSuperTypes.map(\.name) }
}
