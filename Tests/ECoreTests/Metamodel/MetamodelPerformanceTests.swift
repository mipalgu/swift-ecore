//
// MetamodelPerformanceTests.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

extension Tag {
    /// Marks the timing tests of the metamodel index and linker; skip them with `--skip-tag`.
    @Tag static var metamodelPerformance: Self
}

@Suite("Metamodel Performance Tests", .tags(.metamodelPerformance))
struct MetamodelPerformanceTests {
    /// The number of model elements that each generated class contributes.
    private static let elementsPerClass = 10

    /// The number of elements of the synthetic metamodel.
    private static let elementCount = 5_000

    /// The time that building an index or relinking may take.
    private static let bound = Duration.seconds(10)

    /// Builds a package of classes in hierarchies of at most twenty classes.
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
                EAttribute(name: "attribute\($0)", eType: string)
            }
            features.append(EReference(name: "next", eType: classes[(position + 1) % count]))
            features.append(EReference(name: "other", eType: classes[(position * 7 + 3) % count], upperBound: -1))
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

    // Timeout traits block the WASI executor; keep the explicit timing assertions.
    #if os(WASI)
    @Test("an index of 5,000 elements builds and answers queries in bounded time")
    #else
    @Test("an index of 5,000 elements builds and answers queries in bounded time", .timeLimit(.minutes(2)))
    #endif
    func indexTiming() {
        let package = Self.syntheticPackage(elements: Self.elementCount)
        let clock = ContinuousClock()
        var index = MetamodelIndex(roots: [package])
        let build = clock.measure { index = MetamodelIndex(roots: [package]) }
        let elements = index.allElements.count
        let query = clock.measure {
            for element in index.allElements.prefix(2_000) {
                _ = index.fragment(of: element.id)
                _ = index.container(of: element.id)
                _ = index.usages(of: element.id)
            }
        }
        print("metamodel index: \(elements) elements built in \(build), 2000 queries in \(query)")
        #expect(elements >= Self.elementCount)
        #expect(build < Self.bound)
        #expect(query < Self.bound)
    }

    #if os(WASI)
    @Test("relinking 5,000 elements takes bounded time")
    #else
    @Test("relinking 5,000 elements takes bounded time", .timeLimit(.minutes(2)))
    #endif
    func relinkTiming() throws {
        let package = Self.syntheticPackage(elements: Self.elementCount)
        let clock = ContinuousClock()
        var relinked: [EPackage] = []
        let relink = clock.measure { relinked = MetamodelLinker.relinked([package]) }
        var renamed = try #require(relinked[0].getEClass("Class0"))
        renamed.name = "Renamed"
        var edited = relinked[0]
        edited.eClassifiers[0] = renamed
        var second: [EPackage] = []
        let again = clock.measure { second = MetamodelLinker.relinked([edited]) }
        var index = MetamodelIndex(roots: second)
        let both = clock.measure {
            index = MetamodelIndex(roots: MetamodelLinker.relinked([edited]))
        }
        print("metamodel relink: first \(relink), after an edit \(again), relink and index \(both)")
        #expect(second[0].getEClass("Class1")?.eSuperTypes.first?.name == "Renamed")
        #expect(index.allElements.count >= Self.elementCount)
        #expect(relink < Self.bound)
        #expect(again < Self.bound)
        #expect(both < Self.bound * 2)
    }
}
