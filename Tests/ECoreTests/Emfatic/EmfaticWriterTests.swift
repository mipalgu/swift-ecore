//
// EmfaticWriterTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OrderedCollections
import Testing

@testable import ECore

/// Tests that native packages are written as canonical Emfatic and read back unchanged.
@Suite("Emfatic writer")
struct EmfaticWriterTests {
    /// A canonical document is written back exactly.
    @Test func canonicalRoundTrip() {
        let result = parseCleanEmfatic(EmfaticFixtures.library)
        let written = EmfaticWriter.write(result.packages)
        #expect(written.diagnostics.isEmpty)
        #expect(written.text == EmfaticFixtures.library + "\n")
    }

    /// Text that is not canonical becomes canonical after one round trip and then stays so.
    @Test func textRoundTripIsStable() {
        let source = """
            package shop ;   class   Order{attr String[1..1]code;ref Line[0..*]lines;op void f(String[?] x);}
            class Line { }  enum Kind { a ; b ; }
            """
        let first = EmfaticWriter.write(parseCleanEmfatic(source).packages).text
        let second = EmfaticWriter.write(parseCleanEmfatic(first).packages).text
        #expect(first == second)
        #expect(first.contains("\tattr String[1] code;"))
        #expect(first.contains("\tref Line[*] lines;"))
        #expect(first.contains("\top void f(String x);"))
        #expect(first.contains("\ta = 0;"))
    }

    /// A package built in code survives writing and reading with the same structure.
    @Test func modelRoundTrip() throws {
        let original = EmfaticSampleMetamodel.make()
        let written = EmfaticWriter.write([original])
        #expect(written.diagnostics.isEmpty, "\(written.diagnostics.map(\.message))")
        let read = parseCleanEmfatic(written.text)
        #expect(read.diagnostics.isEmpty, "\(read.diagnostics.map(\.message))")
        #expect(MetamodelSignature.of(read.packages) == MetamodelSignature.of([original]))
    }

    /// The fixture survives text, model and text again with the same structure.
    @Test func fixtureModelRoundTrip() {
        let first = parseCleanEmfatic(EmfaticFixtures.library)
        let again = parseCleanEmfatic(EmfaticWriter.write(first.packages).text)
        #expect(MetamodelSignature.of(first.packages) == MetamodelSignature.of(again.packages))
    }

    /// Names that are keywords are escaped.
    @Test func keywordNames() throws {
        var eClass = EClass(name: "class")
        eClass.eStructuralFeatures = [EAttribute(name: "id", eType: try #require(EcorePackage.dataType(.eString)))]
        let package = EPackage(name: "op", nsURI: "urn:op", nsPrefix: "op", eClassifiers: [eClass])
        let text = EmfaticWriter.write([package]).text
        #expect(text.contains("package ~op;"))
        #expect(text.contains("class ~class {"))
        #expect(text.contains("attr String ~id;"))
        #expect(parseCleanEmfatic(text).eClass("class") != nil)
    }

    /// A built-in type hidden by a local classifier is written with its Ecore name.
    @Test func hiddenBuiltinNames() throws {
        let string = try #require(EcorePackage.dataType(.eString))
        let local = EClass(name: "String")
        var holder = EClass(name: "Holder")
        holder.eStructuralFeatures = [
            EAttribute(name: "text", eType: string), EReference(name: "local", eType: local),
        ]
        let package = EPackage(name: "p", nsURI: "urn:p", nsPrefix: "p", eClassifiers: [local, holder])
        let text = EmfaticWriter.write([package]).text
        #expect(text.contains("attr EString text;"))
        #expect(text.contains("ref String local;"))
        let read = parseCleanEmfatic(text)
        #expect(read.attribute("Holder", "text")?.eType.id == string.id)
    }

    /// Annotation sources that are not labels are quoted where needed.
    @Test func annotationSources() throws {
        let package = EPackage(
            name: "p", nsURI: "urn:p", nsPrefix: "p",
            eAnnotations: [
                EAnnotation(source: "namespace", orderedDetails: ["k": "v"]),
                EAnnotation(source: "GenModel", orderedDetails: [:]),
                EAnnotation(source: "plain.label", orderedDetails: ["key with space": "a \"quoted\" value"]),
                EAnnotation(source: "http://example.org/a", orderedDetails: ["class": "x"]),
            ])
        let text = EmfaticWriter.write([package]).text
        #expect(text.contains(#"@"namespace"(k="v")"#))
        #expect(text.contains(#"@"GenModel""#))
        #expect(text.contains(#"@plain.label("key with space"="a \"quoted\" value")"#))
        #expect(text.contains(#"@"http://example.org/a"("class"="x")"#))
        let read = parseCleanEmfatic(text)
        #expect(read.package?.eAnnotations.map(\.source) == ["namespace", "GenModel", "plain.label", "http://example.org/a"])
        #expect(read.package?.eAnnotations[2].details["key with space"] == #"a "quoted" value"#)
    }

    /// Default values are bare for Booleans and integers, quoted characters for characters.
    @Test func defaultValueForms() throws {
        func attribute(_ name: String, _ type: EcoreDataType, _ literal: String) throws -> EAttribute {
            EAttribute(name: name, eType: try #require(EcorePackage.dataType(type)), defaultValueLiteral: literal)
        }
        var sample = EClass(name: "Sample")
        sample.eStructuralFeatures = [
            try attribute("a", .eBoolean, "true"), try attribute("b", .eInt, "-3"), try attribute("c", .eChar, "z"),
            try attribute("d", .eDouble, "1.5"), try attribute("e", .eBoolean, "maybe"), try attribute("f", .eChar, "'"),
        ]
        let text = EmfaticWriter.write([EPackage(name: "p", eClassifiers: [sample])]).text
        #expect(text.contains("attr boolean a = true;"))
        #expect(text.contains("attr int b = -3;"))
        #expect(text.contains("attr char c = 'z';"))
        #expect(text.contains("attr double d = \"1.5\";"))
        #expect(text.contains("attr boolean e = \"maybe\";"))
        #expect(text.contains("attr char f = \"'\";"))
        let read = parseCleanEmfatic(text)
        #expect(read.eClass("Sample")?.eStructuralFeatures.compactMap { ($0 as? EAttribute)?.defaultValueLiteral }
            == ["true", "-3", "z", "1.5", "maybe", "'"])
    }

    /// A data type without an instance class name reads back without one.
    @Test func dataTypeWithoutInstanceClass() throws {
        let package = EPackage(name: "p", nsURI: "urn:p", nsPrefix: "p", eClassifiers: [EDataType(name: "Opaque")])
        let text = EmfaticWriter.write([package]).text
        #expect(text.contains("datatype Opaque : \"\";"))
        #expect(parseCleanEmfatic(text).package?.getEDataType("Opaque")?.instanceClassName == nil)
    }

    /// A map entry class whose value is contained is written as a class, not with `mapentry`.
    @Test func mapEntryForms() throws {
        let string = try #require(EcorePackage.dataType(.eString))
        let item = EClass(name: "Item")
        var plain = EClass(name: "Plain", instanceClassName: EmfaticLanguage.mapEntryInstanceClassName)
        plain.eStructuralFeatures = [EAttribute(name: "key", eType: string), EReference(name: "value", eType: item)]
        var owning = EClass(name: "Owning", instanceClassName: EmfaticLanguage.mapEntryInstanceClassName)
        owning.eStructuralFeatures = [
            EAttribute(name: "key", eType: string), EReference(name: "value", eType: item, containment: true),
        ]
        let package = EPackage(name: "p", nsURI: "urn:p", nsPrefix: "p", eClassifiers: [item, plain, owning])
        let text = EmfaticWriter.write([package]).text
        #expect(text.contains("mapentry Plain : String -> Item;"))
        #expect(text.contains("class Owning : java.util.Map$Entry {"))
        #expect(MetamodelSignature.of(parseCleanEmfatic(text).packages) == MetamodelSignature.of([package]))
    }

    /// Information that Emfatic cannot express is reported.
    @Test func lossyWrites() throws {
        let string = try #require(EcorePackage.dataType(.eString))
        var target = EClass(name: "Target")
        let key = EAttribute(name: "code", eType: string)
        target.eStructuralFeatures = [key]
        var reference = EReference(name: "target", eType: target)
        reference.eKeys = [key.id]
        reference.defaultValueLiteral = "x"
        var external = EReference(name: "outside", eType: target)
        external.opposite = EUUID()
        var source = EClass(name: "Source")
        source.eStructuralFeatures = [reference, external]
        var literal = EEnumLiteral(name: "first", value: 0, literal: "FIRST")
        literal.eAnnotations = []
        var eEnum = EEnum(name: "Kind", literals: [literal])
        eEnum.serialisable = false
        eEnum.instanceClassName = "org.example.Kind"
        eEnum.eTypeParameters = [ETypeParameter(name: "T")]
        var dataType = EDataType(name: "Data", instanceClassName: "java.lang.Object")
        dataType.eTypeParameters = [ETypeParameter(name: "T", eAnnotations: [EAnnotation(source: "urn:a", details: [:])])]
        dataType.defaultValueLiteral = "0"
        var generic = EClass(name: "Generic")
        generic.eTypeParameters = [ETypeParameter(name: "T", eAnnotations: [EAnnotation(source: "urn:a", details: [:])])]
        let annotation = EAnnotation(source: "urn:note", details: [:], eAnnotations: [EAnnotation(source: "urn:inner", details: [:])])
        let package = EPackage(
            name: "", nsURI: "urn:p", nsPrefix: "p", eClassifiers: [target, source, eEnum, dataType, generic],
            eAnnotations: [annotation])
        let written = EmfaticWriter.write([package, EPackage(name: "other")])
        let messages = written.diagnostics.map(\.message)
        #expect(written.diagnostics.allSatisfy { $0.code == EmfaticDiagnosticCode.lossyWrite.rawValue })
        #expect(written.diagnostics.allSatisfy { $0.severity == .warning })
        for fragment in [
            "further package", "without a name", "keys of 'Source.target'", "default value of reference",
            "opposite of 'Source.outside'", "literal text 'FIRST'", "written as serialisable",
            "instance class name of enumeration", "type parameters of enumeration", "type parameters of data type",
            "default value of data type", "annotations of type parameter", "nested annotations",
        ] {
            #expect(messages.contains { $0.contains(fragment) }, "missing: \(fragment)")
        }
    }

    /// Multi-line annotation values inside indented members are written without extra indentation.
    @Test func multiLineValues() throws {
        let source = "package p;\nclass C {\n\t@GenModel(body=\"first\n  second\")\n\top void f();\n}"
        let first = parseCleanEmfatic(source)
        #expect(first.operation("C", "f")?.eAnnotations.first?.details["body"] == "first\n  second")
        let written = EmfaticWriter.write(first.packages).text
        #expect(written.contains("\t@GenModel(body=\"first\n  second\")"))
        #expect(parseCleanEmfatic(written).operation("C", "f")?.eAnnotations.first?.details["body"] == "first\n  second")
    }

    /// Writing nothing reports that there is nothing to write.
    @Test func emptyInput() {
        let written = EmfaticWriter.write([])
        #expect(written.text.isEmpty)
        #expect(written.diagnostics.count == 1)
    }

    /// A subpackage with a qualified name is reported.
    @Test func qualifiedSubpackageName() {
        let package = EPackage(name: "p", eSubpackages: [EPackage(name: "a.b")])
        #expect(EmfaticWriter.write([package]).diagnostics.contains { $0.message.contains("not a simple name") })
    }
}

/// A metamodel built with the native API, covering the constructs that Emfatic expresses.
enum EmfaticSampleMetamodel {
    /// Builds the sample package.
    static func make() -> EPackage {
        let string = EcorePackage.dataType(.eString) ?? EDataType(name: "EString")
        let int = EcorePackage.dataType(.eInt) ?? EDataType(name: "EInt")
        let money = EDataType(name: "Money", serialisable: false, instanceClassName: "java.math.BigDecimal")
        let status = EEnum(name: "Status", literals: [
            EEnumLiteral(name: "open", value: 0), EEnumLiteral(name: "closed", value: 3),
        ])
        var named = EClass(name: "Named", isAbstract: true)
        named.eStructuralFeatures = [EAttribute(name: "name", eType: string, lowerBound: 1, isID: true)]
        let orderID = EUUID()
        let lineID = EUUID()
        var line = EClass(id: lineID, name: "Line")
        let lineOrder = EUUID()
        let orderLines = EUUID()
        line.eStructuralFeatures = [
            EAttribute(name: "quantity", eType: int, defaultValueLiteral: "1"),
            EReference(id: lineOrder, name: "order", eType: EClass(id: orderID, name: "Order"), opposite: orderLines,
                container: true),
        ]
        var order = EClass(id: orderID, name: "Order", eSuperTypes: [named])
        order.eStructuralFeatures = [
            EReference(id: orderLines, name: "lines", eType: line, upperBound: -1, containment: true,
                opposite: lineOrder, resolveProxies: false),
            EAttribute(name: "status", eType: status, unsettable: true),
            EAttribute(name: "total", eType: money, changeable: false, volatile: true, transient: true, derived: true),
            EAttribute(name: "notes", eType: string, upperBound: -1, ordered: false, unique: false),
        ]
        var parameter = EParameter(name: "count", eType: int, lowerBound: 1)
        parameter.eAnnotations = [EAnnotation(source: AnnotationSource.genModel, orderedDetails: ["documentation": "How many"])]
        order.eOperations = [
            EOperation(name: "reset"),
            EOperation(name: "first", eType: line, upperBound: -1, unique: false, eParameters: [parameter]),
        ]
        var box = EClass(name: "Box")
        let element = ETypeParameter(name: "E", eBounds: [EGenericType(eClassifier: named)])
        box.eTypeParameters = [element]
        var contents = EReference(name: "contents", eType: named, upperBound: -1)
        contents.eGenericType = EGenericType(eTypeParameter: element.id)
        box.eStructuralFeatures = [contents]
        var orderBox = EClass(name: "OrderBox", eSuperTypes: [box])
        orderBox.eGenericSuperTypes = [EGenericType(eClassifier: box, eTypeArguments: [EGenericType(eClassifier: order)])]
        let archived = EPackage(
            name: "archive", nsURI: "urn:archive", nsPrefix: "arc",
            eClassifiers: [EClass(name: "Shelf", eStructuralFeatures: [EReference(name: "orders", eType: order, upperBound: -1)])])
        return EPackage(
            name: "shop", nsURI: "http://example.org/shop", nsPrefix: "shop",
            eClassifiers: [named, order, line, box, orderBox, status, money], eSubpackages: [archived],
            eAnnotations: [EAnnotation(source: AnnotationSource.genModel, orderedDetails: ["prefix": "Shop"])])
    }
}
