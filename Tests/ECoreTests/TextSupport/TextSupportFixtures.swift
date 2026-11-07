//
// TextSupportFixtures.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

@testable import ECore



/// The factory that the assembler tests use for their diagnostics.
let shopFactory = DiagnosticFactory(namespace: "shop", document: "shop.txt")

/// Resolves the shop notation's built-in type names to Ecore data types.
func shopExternal(aliases: [String: String] = [:]) -> ExternalTypeNames {
    ExternalTypeNames(aliases: aliases) { name in
        let table = ["String": "EString", "Int": "EInt", "Boolean": "EBoolean"]
        return table[name].flatMap { EcorePackage.classifier(named: $0) }
    }
}

/// Assembles the drafts and returns the packages with the diagnostics.
func assemble(
    _ drafts: [DraftPackage], aliases: [String: String] = [:], severity: DiagnosticSeverity = .error
) -> (packages: [EPackage], diagnostics: [SourceDiagnostic]) {
    MetamodelAssembler.assemble(
        drafts, factory: shopFactory, external: shopExternal(aliases: aliases), unresolvedSeverity: severity)
}

/// Creates a range with distinct offsets so that diagnostics can be located.
func range(_ offset: Int) -> SourceRange {
    SourceRange(
        start: SourcePosition(utf8Offset: offset, line: 1, column: offset + 1),
        end: SourcePosition(utf8Offset: offset + 1, line: 1, column: offset + 2))
}

/// Creates a location whose name range starts at the given offset.
func location(_ offset: Int) -> DraftLocation {
    DraftLocation(range: range(offset), nameRange: range(offset))
}

/// Creates a class draft with the given features.
func classDraft(_ name: String, supers: [String] = [], features: [DraftFeature] = []) -> DraftClassifier {
    var draft = DraftClassifier(kind: .class, name: name)
    draft.superTypes = supers.map { DraftType(name: $0) }
    draft.features = features
    return draft
}

/// Creates a feature draft of the given kind and type name.
func featureDraft(_ kind: DraftFeature.Kind, _ name: String, _ type: String) -> DraftFeature {
    DraftFeature(kind: kind, name: name, type: DraftType(name: type))
}

/// Creates a package draft holding the given classifiers.
func packageDraft(_ name: String, _ classifiers: [DraftClassifier] = []) -> DraftPackage {
    var draft = DraftPackage(name: name, nsURI: "http://example.org/" + name, nsPrefix: name)
    draft.classifiers = classifiers
    return draft
}

/// Finds the class with the given name in a package.
func eClass(_ package: EPackage, _ name: String) -> EClass? {
    package.eClassifiers.first { $0.name == name } as? EClass
}

/// Finds the attribute with the given name in a class.
func attribute(_ eClass: EClass?, _ name: String) -> EAttribute? {
    eClass?.eStructuralFeatures.first { $0.name == name } as? EAttribute
}

/// Finds the reference with the given name in a class.
func reference(_ eClass: EClass?, _ name: String) -> EReference? {
    eClass?.eStructuralFeatures.first { $0.name == name } as? EReference
}
