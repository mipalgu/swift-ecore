//
// EditPerformanceTests.swift
// ECoreEditTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ECoreEdit

extension Tag {
    /// Marks the timing tests of metamodel editing; skip them with `--skip-tag`.
    @Tag static var editPerformance: Self
}

@MainActor
@Suite("Edit Performance Tests", .tags(.editPerformance))
struct EditPerformanceTests {
    /// The number of elements that each generated class contributes.
    private static let elementsPerClass = 10
    private static let elementCount = 5_000
    private static let editCount = 100

    /// The edit budget accounts for interpretation on WebAssembly CI hosts.
    #if os(WASI)
    private static let bound = Duration.seconds(180)
    #else
    private static let bound = Duration.seconds(60)
    #endif

    private static func syntheticPackage() -> EPackage {
        let count = elementCount / elementsPerClass
        let string = EcorePackage.dataType(.eString)!
        let classes = (0..<count).map { EClass(name: "Class\($0)") }
        var built: [EClass] = []
        for (position, eClass) in classes.enumerated() {
            var result = eClass
            if position % 20 != 0 { result.eSuperTypes = [classes[position - 1]] }
            var features: [any EStructuralFeature] = (0..<3).map { EAttribute(name: "attribute\($0)", eType: string) }
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
    @Test("100 edits of a 5,000-element metamodel complete in bounded time")
    #else
    @Test("100 edits of a 5,000-element metamodel complete in bounded time", .timeLimit(.minutes(5)))
    #endif
    func hundredEdits() throws {
        let package = Self.syntheticPackage()
        let clock = ContinuousClock()
        var document = MetamodelDocument(roots: MetamodelLinker.relinked([package]))
        #expect(document.index.allElements.count >= Self.elementCount)
        let classes = document.index.children(of: package.id, feature: .eClassifiers).map(\.id)
        let domain = MetamodelEditingDomain(document: document)
        var timings: [(String, Duration)] = []
        let start = clock.now
        for step in 0..<Self.editCount {
            let target = classes[(step * 37) % classes.count]
            let edit: MetamodelEdit
            let label: String
            switch step % 5 {
            case 0: (edit, label) = (.set(target, .name, "Renamed\(step)"), "rename")
            case 1: (edit, label) = (.create(.eAttribute, in: target, feature: .eStructuralFeatures, name: "added\(step)"), "create")
            case 2: (edit, label) = (.set(target, .abstract, true), "set flag")
            case 3: (edit, label) = (.move([classes[(step * 11) % classes.count]], to: package.id, at: 0), "move")
            default:
                let attribute = domain.document.index.children(of: target, feature: .eStructuralFeatures).first!.id
                (edit, label) = (.delete([attribute]), "delete")
            }
            let began = clock.now
            try domain.perform(edit)
            timings.append((label, clock.now - began))
        }
        let total = clock.now - start
        document = domain.document
        for kind in ["rename", "create", "set flag", "move", "delete"] {
            let samples = timings.filter { $0.0 == kind }.map(\.1)
            let sum = samples.reduce(Duration.zero, +)
            print("edit timing \(kind): \(samples.count) edits, mean \(sum / samples.count)")
        }
        print("edit timing total: \(Self.editCount) edits on \(document.index.allElements.count) elements in \(total)")
        #expect(total < Self.bound)
        var undone = 0
        let undoStart = clock.now
        while domain.undo() != nil { undone += 1 }
        print("undo timing: \(undone) undos in \(clock.now - undoStart)")
        #expect(undone == Self.editCount)
    }

    #if os(WASI)
    @Test("copying and pasting a class in a 5,000-element metamodel is quick")
    #else
    @Test("copying and pasting a class in a 5,000-element metamodel is quick", .timeLimit(.minutes(2)))
    #endif
    func pasteTiming() throws {
        let package = Self.syntheticPackage()
        var document = MetamodelDocument(roots: MetamodelLinker.relinked([package]))
        let classes = document.index.children(of: package.id, feature: .eClassifiers).map(\.id)
        let clock = ContinuousClock()
        let began = clock.now
        for step in 0..<20 {
            let clipboard = document.copy([classes[step]])
            try document.apply(.paste(clipboard, into: package.id))
        }
        print("paste timing: 20 copies and pastes in \(clock.now - began)")
        #expect(clock.now - began < Self.bound)
    }
}
