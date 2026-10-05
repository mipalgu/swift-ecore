//
// EcoreValidationRun+Generics.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

extension EcoreValidationRun {
    /// Checks a type parameter.
    ///
    /// - Parameter value: The type parameter to check.
    func checkTypeParameter(_ value: ETypeParameter) {
        checkName(of: value.id, value.name)
    }
}
