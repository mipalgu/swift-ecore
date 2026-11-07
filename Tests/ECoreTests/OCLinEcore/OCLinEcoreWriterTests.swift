//
// OCLinEcoreWriterTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OCL
import Testing

@testable import ECore


@Suite("OCLinEcore writer")
struct OCLinEcoreWriterTests {
    @Test("A document in the writer's layout round-trips exactly")
    func exactRoundTrip() {
        let result = OCLinEcoreReader.parse(OCLinEcoreFixtures.school)
        let written = OCLinEcoreWriter.write(result.packages)
        #expect(written.diagnostics.isEmpty, "\(written.diagnostics.map(\.message))")
        #expect(written.text == OCLinEcoreFixtures.school)
    }

    @Test("Reading what was written gives the same packages", arguments: [OCLinEcoreFixtures.school, OCLinEcoreFixtures.informal])
    func structuralRoundTrip(_ text: String) {
        let first = OCLinEcoreReader.parse(text).packages
        let written = OCLinEcoreWriter.write(first).text
        let second = OCLinEcoreReader.parse(written)
        #expect(second.isValid, "\(second.diagnostics.map(\.message))")
        #expect(MetamodelSummary.describe(second.packages) == MetamodelSummary.describe(first))
        #expect(OCLinEcoreWriter.write(second.packages).text == written)
    }

    @Test("Packages built in code are written and read back")
    func programmaticPackages() {
        let string = EcorePackage.dataType(.eString)!
        var colour = EEnum(name: "Colour", literals: [EEnumLiteral(name: "red", value: 1), EEnumLiteral(name: "green", value: 2)])
        colour.serialisable = true
        var shape = EClass(name: "Shape", isAbstract: true)
        shape.eStructuralFeatures = [
            EAttribute(name: "label", eType: string),
            EAttribute(name: "colour", eType: colour, lowerBound: 0),
            EAttribute(name: "count", eType: EcorePackage.dataType(.eInt)!, lowerBound: 1),
            EAttribute(name: "flag", eType: EcorePackage.dataType(.eBoolean)!, lowerBound: 0),
        ]
        var operation = EOperation(name: "area", eType: EcorePackage.dataType(.eDouble)!, lowerBound: 1, ordered: true, unique: true)
        OCLConstraintAnnotations.setBody("0.0", of: &operation)
        shape.eOperations = [operation]
        OCLConstraintAnnotations.addInvariant(OCLConstraintText(name: "Labelled", expression: "label <> ''"), to: &shape)
        var package = EPackage(name: "shapes", nsURI: "http://example.org/shapes", nsPrefix: "shapes", eClassifiers: [colour, shape])
        OCLConstraintAnnotations.installDelegates(on: &package)
        let written = OCLinEcoreWriter.write([package])
        #expect(written.text.hasPrefix("import ecore : 'http://www.eclipse.org/emf/2002/Ecore#/';\n"))
        #expect(written.text.contains("attribute colour : Colour[?] { ordered };"))
        #expect(written.text.contains("attribute count : ecore::EInt { ordered };"))
        #expect(written.text.contains("attribute flag : ecore::EBoolean[?] { ordered };"))
        #expect(written.text.contains("operation area() : ecore::EDouble { ordered }"))
        #expect(written.text.contains("literal red = 1;\n"))
        #expect(written.text.contains("literal green;\n"))
        let read = OCLinEcoreReader.parse(written.text)
        #expect(read.isValid, "\(read.diagnostics.map(\.message))")
        var expected = package
        OCLConstraintAnnotations.addImport(alias: "ecore", uri: EcorePackage.nsURI, to: &expected)
        #expect(MetamodelSummary.describe(read.packages) == MetamodelSummary.describe([expected]))
    }

    @Test("Names are escaped where OCL reserves them", arguments: [
        ("plain", "plain"), ("Set", "_'Set'"), ("self", "_'self'"), ("odd name", "_'odd name'"), ("x1", "x1"), ("1x", "_'1x'"),
        ("it's", "_'it\\'s'"), ("class", "class"),
    ])
    func escaping(_ name: String, _ expected: String) {
        #expect(OCLinEcoreWriter.Writer.name(name) == expected)
    }

    @Test("Classifiers outside the written packages are reported")
    func externalClassifiers() {
        var holder = EClass(name: "Holder")
        holder.eStructuralFeatures = [EReference(name: "other", eType: EClass(name: "Elsewhere"))]
        let written = OCLinEcoreWriter.write([EPackage(name: "p", eClassifiers: [holder])])
        #expect(written.diagnostics.map(\.code) == [OCLDiagnosticCode.unwritableElement])
        #expect(written.text.contains("property other : Elsewhere[?] { ordered };"))
    }

    @Test("Other annotations are written as annotation blocks")
    func annotations() throws {
        var eClass = EClass(name: "A")
        eClass.eAnnotations = [
            EAnnotation(source: "http://example.org/a", orderedDetails: ["k": "v", "l": "it's"],
                eAnnotations: [EAnnotation(source: "http://example.org/nested")]),
            EAnnotation(source: AnnotationSource.genModel, orderedDetails: ["documentation": "Docs", "other": "x"]),
        ]
        let written = OCLinEcoreWriter.write([EPackage(name: "p", eClassifiers: [eClass])])
        #expect(written.text.contains("annotation 'http://example.org/a'(k = 'v', l = 'it\\'s')\n"))
        #expect(written.text.contains("annotation 'http://example.org/nested';"))
        #expect(written.text.contains("annotation 'http://www.eclipse.org/emf/2002/GenModel'(documentation = 'Docs', other = 'x');"))
        let read = OCLinEcoreReader.parse(written.text)
        #expect(read.isValid)
        #expect(MetamodelSummary.describe(read.packages) == MetamodelSummary.describe([EPackage(name: "p", eClassifiers: [eClass])]))
    }
}
