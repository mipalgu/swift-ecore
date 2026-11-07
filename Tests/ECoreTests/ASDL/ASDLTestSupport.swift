//
// ASDLTestSupport.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

@testable import ECore

/// Self-authored ASDL fixtures and helpers shared by the tests.
enum ASDLFixtures {
    /// Arithmetic expressions with let-bindings, the language that every notation describes.
    static let arithmetic = """
        -- Arithmetic expressions with let-bindings
        module Arith {
            expr = Num(int value)
                 | Var(identifier name)
                 | BinOp(expr left, op operator, expr right)
                 | Let(identifier name, expr init, expr body)

            op = Add | Sub | Mul | Div
        }
        """

    /// A description that uses every construct the reader maps.
    static let shapes = """
        module Shapes version "1.0"
        {
            shape = Circle(point centre, int radius)
                  | Polygon(point* vertices, string? label)
                  | Empty
                  attributes (int line, int? column)

            point = (int x, int y)
                    attributes (string? source)

            colour = Red | Green | Blue

            tag = (identifier, identifier, int)

            note = Remark(string?* parts) | Mark(constant)
        }
        """
}

/// The class of a package with a name.
///
/// - Parameters:
///   - name: The class name.
///   - package: The package.
/// - Returns: The class, or `nil`.
func eClass(_ name: String, in package: EPackage) -> EClass? {
    package.eClassifiers.first { $0.name == name } as? EClass
}

/// The attribute of a class with a name.
///
/// - Parameters:
///   - name: The feature name.
///   - eClass: The class that declares it.
/// - Returns: The attribute, or `nil`.
func attribute(_ name: String, of eClass: EClass?) -> EAttribute? {
    eClass?.eStructuralFeatures.first { $0.name == name } as? EAttribute
}

/// The reference of a class with a name.
///
/// - Parameters:
///   - name: The feature name.
///   - eClass: The class that declares it.
/// - Returns: The reference, or `nil`.
func reference(_ name: String, of eClass: EClass?) -> EReference? {
    eClass?.eStructuralFeatures.first { $0.name == name } as? EReference
}

/// The errors that Ecore validation finds in packages.
///
/// - Parameter packages: The packages.
/// - Returns: The messages of the error diagnostics.
func validationErrors(_ packages: [EPackage]) -> [String] {
    EcoreValidator().validate(MetamodelIndex(roots: packages)).filter { $0.severity == .error }.map(\.message)
}

/// The diagnostics with a code.
///
/// - Parameters:
///   - code: The code.
///   - result: The parse result.
/// - Returns: The matching diagnostics.
func diagnostics(_ code: ASDLDiagnosticCode, in result: ASDLParseResult) -> [SourceDiagnostic] {
    result.diagnostics.filter { $0.code == code.rawValue }
}
