//
// ASDLWriterTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("ASDL writer")
struct ASDLWriterTests {
    /// The shapes fixture in the writer's layout.
    static let canonicalShapes = """
        module Shapes version "1.0" {
            shape = Circle(point centre, int radius)
                  | Polygon(point* vertices, string? label)
                  | Empty
                    attributes (int line, int? column)

            point = (int x, int y)
                    attributes (string? source)

            colour = Red
                   | Green
                   | Blue

            tag = (identifier, identifier, int)

            note = Remark(string?* parts)
                 | Mark(constant)
        }

        """

    @Test("Writing what was read reproduces the description in canonical layout")
    func canonicalText() {
        let read = ASDLReader.parse(ASDLFixtures.shapes)
        let written = ASDLWriter.write(read.packages)
        #expect(written.diagnostics.isEmpty)
        #expect(written.text == Self.canonicalShapes)
    }

    @Test("Reading what was written gives the same metamodel", arguments: [
        ASDLFixtures.shapes, ASDLFixtures.arithmetic,
        "module A version \"x\\\"y\" (imports B) { t = (B.u v) }",
        "module A { s = X(int, int) | Y attributes (string?) }",
    ])
    func roundTrip(source: String) {
        let first = ASDLReader.parse(source)
        let written = ASDLWriter.write(first.packages)
        let second = ASDLReader.parse(written.text)
        #expect(GrammarMetamodelDescription.describe(second.packages) == GrammarMetamodelDescription.describe(first.packages))
        #expect(ASDLWriter.write(second.packages).text == written.text)
    }

    @Test("Writing with enumerations turned off keeps classes and reads back as classes")
    func classesRoundTrip() {
        let options = ASDLImportOptions(enumerations: .never)
        let first = ASDLReader.parse(ASDLFixtures.arithmetic, options: options)
        let written = ASDLWriter.write(first.packages)
        #expect(written.diagnostics.isEmpty)
        let second = ASDLReader.parse(written.text, options: options)
        #expect(GrammarMetamodelDescription.describe(second.packages) == GrammarMetamodelDescription.describe(first.packages))
    }

    @Test("Features without annotations use the built-in names of their Ecore types")
    func plainMetamodel() throws {
        let leaf = EClass(name: "Leaf", eSuperTypes: [EClass(name: "node", isAbstract: true)])
        let node = EClass(name: "node", isAbstract: true)
        var fixedLeaf = leaf
        fixedLeaf.eSuperTypes = [node]
        fixedLeaf.eStructuralFeatures = [
            EAttribute(name: "label", eType: try #require(EcorePackage.dataType(.eString)), lowerBound: 1),
            EAttribute(name: "weight", eType: try #require(EcorePackage.dataType(.eInt)), upperBound: -1),
            EAttribute(name: "payload", eType: try #require(EcorePackage.dataType(.eJavaObject))),
        ]
        let package = MetamodelLinker.relinked([EPackage(name: "tree", nsURI: "urn:t", nsPrefix: "t", eClassifiers: [node, fixedLeaf])])
        let written = ASDLWriter.write(package)
        #expect(written.diagnostics.isEmpty)
        #expect(written.text == "module tree {\n    node = Leaf(string label, int* weight, constant? payload)\n}\n")
    }

    @Test("Elements that ASDL cannot express are reported and approximated or left out")
    func unsupported() throws {
        let string = try #require(EcorePackage.dataType(.eString))
        let flag = try #require(EcorePackage.dataType(.eBoolean))
        let target = EClass(name: "target", eStructuralFeatures: [EAttribute(name: "id", eType: string, lowerBound: 1)])
        let base = EClass(name: "Base", isAbstract: true)
        let middle = EClass(name: "Middle", isAbstract: true, eSuperTypes: [base])
        let deep = EClass(name: "Deep", eSuperTypes: [middle])
        let holder = EClass(name: "holder", eStructuralFeatures: [
            EReference(name: "link", eType: target, containment: false),
            EAttribute(name: "enabled", eType: flag, lowerBound: 1),
            EReference(name: "many", eType: target, lowerBound: 1, upperBound: -1, containment: true),
        ], eOperations: [EOperation(name: "check")])
        let empty = EClass(name: "empty")
        let package = MetamodelLinker.relinked([EPackage(
            name: "Mixed", nsURI: "urn:m", nsPrefix: "m",
            eClassifiers: [EDataType(name: "Custom"), target, base, middle, deep, holder, empty],
            eSubpackages: [EPackage(name: "sub")])])
        let written = ASDLWriter.write(package)
        let messages = written.diagnostics.map(\.message)
        #expect(written.diagnostics.allSatisfy { $0.severity == .warning })
        #expect(messages.contains { $0.contains("subpackage 'Mixed.sub'") })
        #expect(messages.contains { $0.contains("data type 'Mixed.Custom'") })
        #expect(messages.contains { $0.contains("non-containment reference 'holder.link'") })
        #expect(messages.contains { $0.contains("'EBoolean' of 'holder.enabled'") })
        #expect(messages.contains { $0.contains("[1..*] of 'holder.many'") })
        #expect(messages.contains { $0.contains("operation 'holder.check'") })
        #expect(messages.contains { $0.contains("'Middle'") })
        #expect(messages.contains { $0.contains("class 'empty' has no fields") })
        #expect(written.text.contains("holder = (target? link, int enabled, target* many)"))
        #expect(!written.text.contains("Deep"))
        #expect(ASDLReader.parse(written.text).diagnostics.filter { $0.severity == .error }.isEmpty)
    }
}

@Suite("ASDL reference corpus")
struct ASDLCorpusTests {
    /// The environment variable naming an ASDL file to check, such as CPython's `Parser/Python.asdl`.
    static let variable = "ASDL_REFERENCE_FILE"

    @Test(
        "Every type of a reference description maps, and the result validates and round-trips",
        .enabled(if: ProcessInfo.processInfo.environment[variable] != nil))
    func referenceFile() throws {
        let path = try #require(ProcessInfo.processInfo.environment[Self.variable])
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let result = ASDLReader.parse(text, sourceName: URL(fileURLWithPath: path).lastPathComponent)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map(\.message))")
        let package = try #require(result.packages.first)
        let module = try #require(result.outline.first)
        for definition in module.children {
            #expect(package.eClassifiers.contains { $0.name == definition.name }, "type \(definition.name) is mapped")
            for constructor in definition.children where constructor.kind == ASDLOutlineKind.constructor {
                let mapped = package.eClassifiers.contains { $0.name == constructor.name }
                    || package.eClassifiers.contains { ($0 as? EEnum)?.getLiteral(name: constructor.name) != nil }
                #expect(mapped, "constructor \(constructor.name) is mapped")
            }
        }
        let validation = EcoreValidator().validate(MetamodelIndex(roots: result.packages))
        let validationErrors = validation.filter { $0.severity == .error }
        #expect(validationErrors.isEmpty, "\(validationErrors.map(\.message))")
        let written = ASDLWriter.write(result.packages)
        #expect(written.diagnostics.isEmpty, "\(written.diagnostics.map(\.message))")
        let reread = ASDLReader.parse(written.text)
        #expect(GrammarMetamodelDescription.describe(reread.packages) == GrammarMetamodelDescription.describe(result.packages))
        let classes = package.eClassifiers.compactMap { $0 as? EClass }
        let summary = [
            "types=\(module.children.count)",
            "sums=\(module.children.filter { $0.kind == ASDLOutlineKind.sum }.count)",
            "products=\(module.children.filter { $0.kind == ASDLOutlineKind.product }.count)",
            "classes=\(classes.count)", "abstract=\(classes.filter(\.isAbstract).count)",
            "enums=\(package.eClassifiers.filter { $0 is EEnum }.count)",
            "features=\(classes.reduce(0) { $0 + $1.eStructuralFeatures.count })",
            "diagnostics=\(result.diagnostics.map { "\($0.severity):\($0.message)" })",
            "validationWarnings=\(validation.filter { $0.severity == .warning }.map(\.message))",
        ]
        print("ASDL corpus \(path): " + summary.joined(separator: "; "))
    }
}
