//
// EmfaticTestSupport.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// Lookup helpers that keep the Emfatic tests short.
extension EmfaticParseResult {
    /// The first package of the result.
    var package: EPackage? { packages.first }

    /// The errors of the result.
    var errors: [SourceDiagnostic] { diagnostics.filter { $0.severity == .error } }

    /// The warnings of the result.
    var warnings: [SourceDiagnostic] { diagnostics.filter { $0.severity == .warning } }

    /// The class of the first package with the given name.
    func eClass(_ name: String) -> EClass? { package?.getEClass(name) }

    /// The attribute of a class with the given name.
    func attribute(_ owner: String, _ name: String) -> EAttribute? {
        eClass(owner)?.eStructuralFeatures.first { $0.name == name } as? EAttribute
    }

    /// The reference of a class with the given name.
    func reference(_ owner: String, _ name: String) -> EReference? {
        eClass(owner)?.eStructuralFeatures.first { $0.name == name } as? EReference
    }

    /// The operation of a class with the given name.
    func operation(_ owner: String, _ name: String) -> EOperation? {
        eClass(owner)?.eOperations.first { $0.name == name }
    }

    /// Whether a diagnostic with the code was reported.
    func reports(_ code: EmfaticDiagnosticCode) -> Bool {
        diagnostics.contains { $0.code == code.rawValue }
    }
}

/// Reads Emfatic text and expects it to be free of errors.
///
/// - Parameters:
///   - text: The Emfatic text.
///   - sourceLocation: The location of the caller.
/// - Returns: The parse result.
func parseCleanEmfatic(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) -> EmfaticParseResult {
    let result = EmfaticReader.parse(text)
    #expect(result.errors.isEmpty, "\(result.errors.map(\.message))", sourceLocation: sourceLocation)
    return result
}

/// The Ecore name of a classifier, for comparing types.
func typeName(_ classifier: (any EClassifier)?) -> String? { classifier?.name }
