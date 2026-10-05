//
// EcoreValidatorPerformanceTests.swift
// ECoreTests
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

extension Tag {
    /// Marks the timing tests of the metamodel validator; skip them with `--skip-tag`.
    @Tag static var validatorPerformance: Self
}

@Suite("EcoreValidator Performance Tests", .tags(.validatorPerformance))
struct EcoreValidatorPerformanceTests {
    /// The number of elements that each generated class contributes.
    private static let elementsPerClass = 10

    /// The number of elements of the synthetic metamodel.
    private static let elementCount = 5_000

    /// The time that validating the whole synthetic metamodel may take.
    private static let bound = Duration.seconds(10)

    /// Builds a package of classes in hierarchies of at most twenty classes.
    ///
    /// The feature names include the position of the class, because a subclass that repeated the
    /// name of an inherited feature would be invalid.
    ///
    /// Each class has three attributes, two references to other classes, an operation with a
    /// parameter, and an annotation, so it contributes ten elements with itself.
    private static func syntheticPackage(elements: Int) -> EPackage {
        let count = elements / elementsPerClass
        let string = EcorePackage.dataType(.eString)!
        let classes = (0..<count).map { EClass(name: "Class\($0)") }
        var built: [EClass] = []
        for (position, eClass) in classes.enumerated() {
            var result = eClass
            if position % 20 != 0 { result.eSuperTypes = [classes[position - 1]] }
            var features: [any EStructuralFeature] = (0..<3).map {
                EAttribute(name: "attribute\(position)_\($0)", eType: string)
            }
            features.append(EReference(name: "next\(position)", eType: classes[(position + 1) % count]))
            features.append(EReference(name: "other\(position)", eType: classes[(position * 7 + 3) % count], upperBound: -1))
            result.eStructuralFeatures = features
            result.eOperations = [
                EOperation(
                    name: "operation", eType: classes[(position + 5) % count],
                    eParameters: [EParameter(name: "argument", eType: classes[(position + 9) % count])])
            ]
            result.eAnnotations = [EAnnotation(source: "http://example.org/note", orderedDetails: ["k": "v"])]
            built.append(result)
        }
        return EPackage(name: "synthetic", nsURI: "http://example.org/synthetic", nsPrefix: "syn", eClassifiers: built)
    }

    @Test("validating 5,000 elements takes bounded time", .timeLimit(.minutes(2)))
    func validationTiming() throws {
        let package = Self.syntheticPackage(elements: Self.elementCount)
        let index = MetamodelIndex(roots: [package])
        let validator = EcoreValidator()
        let clock = ContinuousClock()
        var full: [EcoreDiagnostic] = []
        let whole = clock.measure { full = validator.validate(index) }
        let sample = Set(index.allElements.prefix(100).map(\.id))
        var scoped: [EcoreDiagnostic] = []
        let part = clock.measure { scoped = validator.validate(sample, in: index) }
        print(
            "metamodel validation: \(index.allElements.count) elements validated in \(whole) "
                + "(\(full.count) diagnostics), 100 elements in \(part)")
        #expect(index.allElements.count >= Self.elementCount)
        #expect(full.isEmpty)
        #expect(scoped.isEmpty)
        #expect(whole < Self.bound)
        #expect(part < Self.bound)
    }
}
