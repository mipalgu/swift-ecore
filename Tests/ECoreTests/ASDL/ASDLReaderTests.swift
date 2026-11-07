//
// ASDLReaderTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

@Suite("ASDL reader mapping")
struct ASDLReaderMappingTests {
    /// The shapes fixture read with default options.
    let shapes = ASDLReader.parse(ASDLFixtures.shapes, sourceName: "shapes.asdl")

    @Test("A module becomes a package with default namespace and version annotation")
    func modulePackage() throws {
        let package = try #require(shapes.packages.first)
        #expect(shapes.packages.count == 1)
        #expect(package.name == "Shapes")
        #expect(package.nsURI == "urn:asdl:Shapes")
        #expect(package.nsPrefix == "shapes")
        #expect(package.getEAnnotationDetail(source: ASDLSyntax.annotationSource, key: "version") == "1.0")
    }

    @Test("A sum type becomes an abstract class whose attributes are its features")
    func sumType() throws {
        let package = try #require(shapes.packages.first)
        let shape = try #require(eClass("shape", in: package))
        #expect(shape.isAbstract)
        #expect(shape.eSuperTypes.isEmpty)
        let line = try #require(attribute("line", of: shape))
        #expect(line.eType.name == "EInt")
        #expect(line.lowerBound == 1 && line.upperBound == 1)
        #expect(line.getEAnnotationDetail(source: ASDLSyntax.annotationSource, key: "attribute") == "true")
        let column = try #require(attribute("column", of: shape))
        #expect(column.lowerBound == 0 && column.upperBound == 1)
    }

    @Test("Constructors become concrete subclasses with their fields")
    func constructors() throws {
        let package = try #require(shapes.packages.first)
        let circle = try #require(eClass("Circle", in: package))
        #expect(!circle.isAbstract)
        #expect(circle.eSuperTypes.map(\.name) == ["shape"])
        let centre = try #require(reference("centre", of: circle))
        #expect(centre.containment)
        #expect(centre.eType.name == "point")
        #expect(centre.lowerBound == 1 && centre.upperBound == 1)
        let polygon = try #require(eClass("Polygon", in: package))
        let vertices = try #require(reference("vertices", of: polygon))
        #expect(vertices.containment && vertices.lowerBound == 0 && vertices.upperBound == -1 && vertices.ordered)
        let label = try #require(attribute("label", of: polygon))
        #expect(label.eType.name == "EString" && label.upperBound == 1 && label.lowerBound == 0)
        #expect(label.getEAnnotationDetail(source: ASDLSyntax.annotationSource, key: "type") == "string")
        let empty = try #require(eClass("Empty", in: package))
        #expect(empty.eStructuralFeatures.isEmpty && !empty.isAbstract)
        #expect(empty.eAllStructuralFeatures.map(\.name) == ["line", "column"])
    }

    @Test("A product type becomes a concrete class whose attributes follow its fields")
    func productType() throws {
        let package = try #require(shapes.packages.first)
        let point = try #require(eClass("point", in: package))
        #expect(!point.isAbstract && point.eSuperTypes.isEmpty)
        #expect(point.eStructuralFeatures.map(\.name) == ["x", "y", "source"])
        let source = try #require(attribute("source", of: point))
        #expect(source.getEAnnotationDetail(source: ASDLSyntax.annotationSource, key: "attribute") == "true")
        #expect(attribute("x", of: point)?.getEAnnotation(source: ASDLSyntax.annotationSource)?.details["attribute"] == nil)
    }

    @Test("A sum of constructors without fields becomes an enumeration by default")
    func enumeration() throws {
        let package = try #require(shapes.packages.first)
        let colour = try #require(package.eClassifiers.first { $0.name == "colour" } as? EEnum)
        #expect(colour.literals.map(\.name) == ["Red", "Green", "Blue"])
        #expect(colour.literals.map(\.value) == [0, 1, 2])
    }

    @Test("Enumerations can be turned off so that every sum becomes classes")
    func enumerationsOff() throws {
        let result = ASDLReader.parse(ASDLFixtures.shapes, options: .init(enumerations: .never))
        let package = try #require(result.packages.first)
        let colour = try #require(eClass("colour", in: package))
        #expect(colour.isAbstract)
        #expect(eClass("Red", in: package)?.eSuperTypes.map(\.name) == ["colour"])
        #expect(validationErrors(result.packages).isEmpty)
    }

    @Test("Enumeration types of fields become attributes typed by the enumeration")
    func enumerationField() throws {
        let result = ASDLReader.parse(ASDLFixtures.arithmetic)
        let package = try #require(result.packages.first)
        let binOp = try #require(eClass("BinOp", in: package))
        let operation = try #require(attribute("operator", of: binOp))
        #expect(operation.eType is EEnum)
        #expect(operation.eType.name == "op")
        #expect(reference("left", of: binOp)?.containment == true)
    }

    @Test("Unnamed fields get names from their type and occurrence, as in the ASDL paper")
    func generatedNames() throws {
        let package = try #require(shapes.packages.first)
        let tag = try #require(eClass("tag", in: package))
        #expect(tag.eStructuralFeatures.map(\.name) == ["identifier1", "identifier2", "int1"])
        let first = try #require(attribute("identifier1", of: tag))
        #expect(first.getEAnnotationDetail(source: ASDLSyntax.annotationSource, key: "generatedName") == "true")
        #expect(first.getEAnnotationDetail(source: ASDLSyntax.annotationSource, key: "type") == "identifier")
        let mark = try #require(eClass("Mark", in: package))
        #expect(attribute("constant1", of: mark)?.eType.name == "EJavaObject")
    }

    @Test("Generated names avoid names that are given or inherited")
    func generatedNamesAvoidClashes() throws {
        let text = """
            module M {
                t = C(int, int x) attributes (int)
                p = (int, string int1)
            }
            """
        let result = ASDLReader.parse(text)
        let package = try #require(result.packages.first)
        #expect(eClass("t", in: package)?.eStructuralFeatures.map(\.name) == ["int1"])
        #expect(eClass("C", in: package)?.eStructuralFeatures.map(\.name) == ["int2", "x"])
        #expect(eClass("p", in: package)?.eStructuralFeatures.map(\.name) == ["int2", "int1"])
        #expect(validationErrors(result.packages).isEmpty)
    }

    @Test("Combined quantifiers become sequences and are kept in an annotation")
    func combinedQuantifiers() throws {
        let package = try #require(shapes.packages.first)
        let parts = try #require(attribute("parts", of: eClass("Remark", in: package)))
        #expect(parts.lowerBound == 0 && parts.upperBound == -1 && !parts.unique)
        #expect(parts.getEAnnotationDetail(source: ASDLSyntax.annotationSource, key: "quantifiers") == "?*")
        let notes = diagnostics(.approximatedQuantifier, in: shapes)
        #expect(notes.count == 1)
        #expect(notes.first?.severity == .information)
        #expect(notes.first?.range?.start.line == 15)
    }

    @Test("The built-in type table can be replaced")
    func builtinOverride() throws {
        var types = ASDLImportOptions.defaultBuiltinTypes
        types["int"] = .eBigInteger
        let result = ASDLReader.parse(ASDLFixtures.arithmetic, options: .init(builtinTypes: types))
        let package = try #require(result.packages.first)
        let num = try #require(eClass("Num", in: package))
        #expect(attribute("value", of: num)?.eType.name == "EBigInteger")
    }

    @Test("Options supply namespace and package name")
    func namespaceOptions() throws {
        let result = ASDLReader.parse(
            ASDLFixtures.arithmetic, options: .init(packageName: "ignored", nsURI: "http://example.org/arith", nsPrefix: "ar"))
        let package = try #require(result.packages.first)
        #expect(package.name == "Arith")
        #expect(package.nsURI == "http://example.org/arith")
        #expect(package.nsPrefix == "ar")
    }

    @Test("The arithmetic language maps to an abstract expression class with four constructors")
    func arithmetic() throws {
        let result = ASDLReader.parse(ASDLFixtures.arithmetic)
        #expect(result.diagnostics.isEmpty)
        let package = try #require(result.packages.first)
        #expect(package.eClassifiers.map(\.name) == ["expr", "Num", "Var", "BinOp", "Let", "op"])
        #expect(eClass("Let", in: package)?.eStructuralFeatures.map(\.name) == ["name", "init", "body"])
        #expect(validationErrors(result.packages).isEmpty)
    }

    @Test("Every result of the fixtures validates without errors")
    func validates() {
        #expect(validationErrors(shapes.packages).isEmpty)
    }
}

@Suite("ASDL modules and names")
struct ASDLModuleTests {
    @Test("Several modules refer to each other's types by qualified name")
    func qualifiedNames() throws {
        let text = """
            module Base { pos = (int line, int column) }
            module Tree {
                node = Leaf(Base.pos at) | Branch(node* children)
            }
            """
        let result = ASDLReader.parse(text, options: .init(nsURI: "http://example.org/lang"))
        #expect(result.diagnostics.isEmpty)
        #expect(result.packages.map(\.name) == ["Base", "Tree"])
        #expect(result.packages.map(\.nsURI) == ["http://example.org/lang/Base", "http://example.org/lang/Tree"])
        let leaf = try #require(eClass("Leaf", in: result.packages[1]))
        let at = try #require(reference("at", of: leaf))
        #expect(at.eType.name == "pos" && at.containment)
        #expect(validationErrors(result.packages).isEmpty)
    }

    @Test("Types of modules outside the text become containments of EObject")
    func externalTypes() throws {
        let text = "module M (imports Other) { t = (Other.thing x) }"
        let result = ASDLReader.parse(text)
        #expect(diagnostics(.externalType, in: result).count == 1)
        #expect(diagnostics(.unresolvedImport, in: result).count == 1)
        let package = try #require(result.packages.first)
        #expect(package.getEAnnotationDetail(source: ASDLSyntax.annotationSource, key: "imports") == "Other")
        let x = try #require(reference("x", of: eClass("t", in: package)))
        #expect(x.eType.name == "EObject")
        #expect(validationErrors(result.packages).isEmpty)
    }

    @Test("A module without a name takes its package name from the options or the source name")
    func packageNames() throws {
        #expect(ASDLReader.parse("module { t = (int x) }", sourceName: "dir/lang.asdl").packages.first?.name == "lang")
        #expect(ASDLReader.parse("module { t = (int x) }", options: .init(packageName: "given")).packages.first?.name == "given")
        #expect(ASDLReader.parse("module { t = (int x) }").packages.first?.name == "model")
    }

    @Test("Names that break the case convention are accepted with a warning")
    func namingConvention() {
        let result = ASDLReader.parse("module M { Thing = lower(int x) }")
        let warnings = diagnostics(.namingConvention, in: result)
        #expect(warnings.count == 2)
        #expect(warnings.allSatisfy { $0.severity == .warning })
        #expect(result.packages.first?.eClassifiers.map(\.name) == ["Thing", "lower"])
    }
}
