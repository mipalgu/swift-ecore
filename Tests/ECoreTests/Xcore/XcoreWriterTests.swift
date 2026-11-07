//
// XcoreWriterTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OrderedCollections
import Testing

@testable import ECore

/// Tests that native packages are written as Xcore and read back unchanged.
@Suite("Xcore writer")
struct XcoreWriterTests {
    /// The structure of a document, ignoring the uniqueness of single-valued elements.
    private func signature(_ packages: [EPackage]) -> String {
        MetamodelSignature.of(packages, options: .init(ignoresSingleValuedCollectionFlags: true))
    }

    /// A canonical document is written back exactly, bodies included.
    @Test func canonicalRoundTrip() {
        let result = XcoreReader.parse(XcoreFixtures.library)
        let written = XcoreWriter.write(result.packages)
        #expect(written.diagnostics.isEmpty, "\(written.diagnostics.map(\.message))")
        #expect(written.text == XcoreFixtures.library + "\n")
    }

    /// Text that is not canonical becomes canonical after one round trip and then stays so.
    @Test func textRoundTripIsStable() {
        let source = """
            package shop class Order{String[0..*]codes contains Line[*]lines opposite order op void f(String[?] x){}}
            class Line{container Order order opposite lines} enum Kind{a,b=2}
            """
        let first = XcoreWriter.write(XcoreReader.parse(source).packages).text
        let second = XcoreWriter.write(XcoreReader.parse(first).packages).text
        #expect(first == second)
        #expect(first.contains("\tString[] codes"))
        #expect(first.contains("\top void f(String x) {}"))
        #expect(first.contains("\tb = 2"))
    }

    /// A package built in code survives writing and reading with the same structure.
    @Test func modelRoundTrip() throws {
        let original = XcoreSampleMetamodel.make()
        let written = XcoreWriter.write([original])
        #expect(written.diagnostics.isEmpty, "\(written.diagnostics.map(\.message))")
        let read = parseCleanXcore(written.text)
        #expect(read.diagnostics.allSatisfy { $0.code == XcoreDiagnosticCode.bodyNotExecuted.rawValue })
        #expect(signature(read.packages) == signature([original]))
    }

    /// Properties without a keyword are written through `@Ecore` and read back.
    @Test func ecoreAttributeEscapes() throws {
        let string = try #require(EcorePackage.dataType(.eString))
        var sample = EClass(name: "Sample", isInterface: true)
        let target = EClass(name: "Target")
        var getter = EAttribute(name: "computed", eType: string)
        getter.eAnnotations = [EAnnotation(source: XcoreLanguage.namespaceURI, orderedDetails: ["get": "{ \"x\" }"])]
        sample.eStructuralFeatures = [
            EReference(name: "many", eType: target, upperBound: -1, unique: false),
            EReference(name: "back", eType: target, resolveProxies: false),
            getter,
        ]
        var opaque = EDataType(name: "Opaque", serialisable: false)
        opaque.instanceClassName = nil
        var odd = EDataType(name: "Odd", instanceClassName: "not a type")
        odd.serialisable = true
        var kind = EEnum(name: "Kind", literals: [EEnumLiteral(name: "a", value: 0)])
        kind.serialisable = false
        kind.instanceClassName = "org.example.Kind"
        let package = EPackage(name: "p", nsURI: "urn:p", nsPrefix: "p", eClassifiers: [sample, target, opaque, odd, kind])
        let written = XcoreWriter.write([package])
        #expect(written.diagnostics.isEmpty, "\(written.diagnostics.map(\.message))")
        #expect(written.text.contains("@Ecore(^abstract=\"false\")"))
        #expect(written.text.contains("@Ecore(^unique=\"false\")"))
        #expect(written.text.contains(
            "@Ecore(changeable=\"true\", ^transient=\"false\", ^volatile=\"false\", ^derived=\"false\")"))
        let read = parseCleanXcore(written.text)
        #expect(signature(read.packages) == signature([package]))
    }

    /// Package names, namespaces and directives are written in the Xcore header.
    @Test func header() throws {
        let package = EPackage(
            name: "shop", nsURI: "org.example.shop", nsPrefix: "shop",
            eClassifiers: [EClass(name: "Item", eAnnotations: [EAnnotation(source: "http://example.org/notes", details: [:])])],
            eAnnotations: [
                EAnnotation(source: AnnotationSource.genModel, orderedDetails: [XcoreLanguage.basePackageKey: "org.example"]),
                EAnnotation(source: XcoreLanguage.namespaceURI, orderedDetails: ["Other": "urn:other"]),
            ])
        let written = XcoreWriter.write([package])
        #expect(written.text.hasPrefix("package org.example.shop\n\nannotation \"urn:other\" as Other\nannotation \"http://example.org/notes\" as Notes\n"))
        #expect(written.text.contains("@Notes\nclass Item {"))
        #expect(written.diagnostics.contains { $0.severity == .information })
        let read = parseCleanXcore(written.text)
        #expect(read.eClass("Item")?.eAnnotations.first?.source == "http://example.org/notes")
        #expect(read.package?.nsURI == "org.example.shop")
    }

    /// Ecore classifiers without Java names are imported; hidden names are qualified.
    @Test func ecoreImports() throws {
        var holder = EClass(name: "Holder")
        holder.eStructuralFeatures = [
            EReference(name: "any", eType: EcorePackage.metaClass(.eObject)),
            EReference(name: "meta", eType: EcorePackage.metaClass(.eClass)),
        ]
        let local = EClass(name: "EClass")
        let package = EPackage(name: "p", nsURI: "urn:p", nsPrefix: "p", eClassifiers: [holder, local])
        let text = XcoreWriter.write([package]).text
        #expect(text.contains("import org.eclipse.emf.ecore.EObject"))
        #expect(text.contains("refers EObject any"))
        #expect(text.contains("refers org.eclipse.emf.ecore.EClass meta"))
        let read = parseCleanXcore(text)
        #expect(read.reference("Holder", "meta")?.eType.id == EcorePackage.metaClass(.eClass).id)
    }

    /// Names that are keywords are escaped.
    @Test func keywordNames() throws {
        var eClass = EClass(name: "type")
        eClass.eStructuralFeatures = [EAttribute(name: "id", eType: try #require(EcorePackage.dataType(.eString)))]
        let text = XcoreWriter.write([EPackage(name: "op", nsURI: "op", nsPrefix: "op", eClassifiers: [eClass])]).text
        #expect(text.contains("package ^op"))
        #expect(text.contains("class ^type {"))
        #expect(text.contains("String ^id"))
        #expect(parseCleanXcore(text).eClass("type") != nil)
    }

    /// Information that Xcore cannot express is reported.
    @Test func lossyWrites() throws {
        let string = try #require(EcorePackage.dataType(.eString))
        var target = EClass(name: "Target")
        var reference = EReference(name: "target", eType: target)
        reference.defaultValueLiteral = "x"
        var outside = EReference(name: "outside", eType: target)
        outside.opposite = EUUID()
        outside.eKeys = [EUUID()]
        var operation = EOperation(name: "f")
        operation.eAnnotations = [EAnnotation(source: XcoreLanguage.namespaceURI, orderedDetails: ["get": "{}"])]
        target.eStructuralFeatures = [reference, outside, EAttribute(name: "s", eType: string)]
        target.eOperations = [operation]
        var dataType = EDataType(name: "D", instanceClassName: "java.lang.Object")
        dataType.defaultValueLiteral = "0"
        var eEnum = EEnum(name: "E")
        eEnum.eTypeParameters = [ETypeParameter(name: "T")]
        let annotated = EClass(name: "Annotated", eAnnotations: [
            EAnnotation(source: AnnotationSource.genModel, details: [:]),
            EAnnotation(source: AnnotationSource.genModel, details: [:]),
            EAnnotation(source: AnnotationSource.ecore, orderedDetails: ["name": "x", "bad key": "y"]),
            EAnnotation(source: "urn:x", details: [:], contents: [EAnnotation(source: "urn:y", details: [:])]),
        ])
        let package = EPackage(
            name: "", nsURI: "urn:p", nsPrefix: "p", eClassifiers: [target, dataType, eEnum, annotated],
            eSubpackages: [EPackage(name: "sub")])
        let written = XcoreWriter.write([package, EPackage(name: "other")])
        let messages = written.diagnostics.filter { $0.severity == .warning }.map(\.message)
        for fragment in [
            "further package", "subpackage", "written as '_'", "default value of reference", "opposite of 'Target.outside'",
            "keys of 'Target.outside'", "get body of 'f'", "default value of data type", "type parameters of enumeration",
            "merges the annotations", "would be read as an attribute", "not a qualified name", "nested annotations",
        ] {
            #expect(messages.contains { $0.contains(fragment) }, "missing: \(fragment)")
        }
        #expect(XcoreWriter.write([]).text.isEmpty)
    }

    /// Bodies stored without braces are wrapped in a block.
    @Test func bodiesWithoutBraces() throws {
        var operation = EOperation(name: "answer", eType: try #require(EcorePackage.dataType(.eInt)))
        operation.eAnnotations = [EAnnotation(source: XcoreLanguage.namespaceURI, orderedDetails: ["body": "42"])]
        let text = XcoreWriter.write([EPackage(name: "p", eClassifiers: [EClass(name: "C", eOperations: [operation])])]).text
        #expect(text.contains("op int answer() {\n42\n}"))
        #expect(body(parseCleanXcore(text).operation("C", "answer")?.eAnnotations ?? [], .body) == "{\n42\n}")
    }
}

/// A metamodel built with the native API, covering the constructs that Xcore expresses.
enum XcoreSampleMetamodel {
    /// Builds the sample package.
    static func make() -> EPackage {
        let string = EcorePackage.dataType(.eString) ?? EDataType(name: "EString")
        let int = EcorePackage.dataType(.eInt) ?? EDataType(name: "EInt")
        let money = EDataType(name: "Money", instanceClassName: "java.math.BigDecimal")
        let status = EEnum(name: "Status", literals: [
            EEnumLiteral(name: "open", value: 0), EEnumLiteral(name: "closed", value: 3, literal: "CLOSED"),
        ])
        var named = EClass(name: "Named", isAbstract: true)
        named.eStructuralFeatures = [EAttribute(name: "name", eType: string, lowerBound: 1, isID: true)]
        let orderID = EUUID()
        let lineOrder = EUUID()
        let orderLines = EUUID()
        let quantity = EAttribute(name: "quantity", eType: int, defaultValueLiteral: "1")
        var line = EClass(name: "Line")
        line.eStructuralFeatures = [
            quantity,
            EReference(id: lineOrder, name: "order", eType: EClass(id: orderID, name: "Order"), opposite: orderLines,
                container: true),
        ]
        var lines = EReference(id: orderLines, name: "lines", eType: line, upperBound: -1, containment: true,
            opposite: lineOrder, resolveProxies: false)
        lines.eKeys = [quantity.id]
        var order = EClass(id: orderID, name: "Order", eSuperTypes: [named])
        var total = EAttribute(name: "total", eType: money, changeable: false, volatile: true, transient: true, derived: true)
        total.eAnnotations = [EAnnotation(source: XcoreLanguage.namespaceURI, orderedDetails: ["get": "{ 0 }"])]
        order.eStructuralFeatures = [
            lines,
            EAttribute(name: "status", eType: status, unsettable: true),
            total,
            EAttribute(name: "notes", eType: string, upperBound: -1, ordered: false, unique: false),
        ]
        var parameter = EParameter(name: "count", eType: int, lowerBound: 1)
        parameter.eAnnotations = [EAnnotation(source: AnnotationSource.genModel, orderedDetails: ["documentation": "How many"])]
        var first = EOperation(name: "first", eType: line, upperBound: -1, unique: false, eParameters: [parameter])
        first.eAnnotations = [EAnnotation(source: XcoreLanguage.namespaceURI, orderedDetails: ["body": "{\n\tlines.head\n}"])]
        order.eOperations = [EOperation(name: "reset"), first]
        var box = EClass(name: "Box")
        let element = ETypeParameter(name: "E", eBounds: [EGenericType(eClassifier: named)])
        box.eTypeParameters = [element]
        var contents = EReference(name: "contents", eType: named, upperBound: -1)
        contents.eGenericType = EGenericType(eTypeParameter: element.id)
        box.eStructuralFeatures = [contents]
        var orderBox = EClass(name: "OrderBox", eSuperTypes: [box])
        orderBox.eGenericSuperTypes = [EGenericType(eClassifier: box, eTypeArguments: [EGenericType(eClassifier: order)])]
        return EPackage(
            name: "shop", nsURI: "http://example.org/shop", nsPrefix: "shop",
            eClassifiers: [named, order, line, box, orderBox, status, money],
            eAnnotations: [EAnnotation(source: AnnotationSource.genModel, orderedDetails: ["prefix": "Shop"])])
    }
}
