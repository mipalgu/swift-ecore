//
// GenModelMetamodelTests.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import Testing

@testable import GenModel

@Suite("GenModel metamodel")
struct GenModelMetamodelTests {
    typealias Expect = GenModelMetamodelExpectations

    private static func document() throws -> EcoreDocument {
        try EcoreDocument(url: #require(GenModelPackage.resourceURL))
    }

    private struct Row {
        let owner: String
        let kind: String
        let type: String
        let lower: String
        let upper: String
        let flags: String
        let defaultValue: String
        let opposite: String
        let name: String

        init(_ text: String, name: String) {
            let parts = text.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            owner = parts[0]
            kind = parts[1]
            type = parts[2]
            lower = parts[3]
            upper = parts[4]
            flags = parts[5]
            defaultValue = parts[6]
            opposite = parts[7]
            self.name = name
        }
    }

    /// Pairs each expected row with the feature name from the metamodel document, in order.
    private static func rows() throws -> [Row] {
        let document = try document()
        var names: [String] = []
        for classifier in document.classifiers where classifier["xsi:type"] == "ecore:EClass" {
            for feature in classifier.children(named: "eStructuralFeatures") {
                names.append(feature["name"] ?? "")
            }
        }
        #expect(names.count == Expect.featureRows.count)
        return zip(Expect.featureRows, names).map { Row($0, name: $1) }
    }

    @Test("bundled resource exists")
    func resourceExists() throws {
        let url = try #require(GenModelPackage.resourceURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("package identity and classifier counts")
    func packageIdentity() async throws {
        let package = try await GenModelPackage.load()
        #expect(package.name == GenModelConstants.packageName)
        #expect(package.nsURI == "http://www.eclipse.org/emf/2002/GenModel")
        #expect(package.nsPrefix == "genmodel")
        let classes = package.eClassifiers.compactMap { $0 as? EClass }
        let enums = package.eClassifiers.compactMap { $0 as? EEnum }
        let dataTypes = package.eClassifiers.compactMap { $0 as? EDataType }
        #expect(classes.count == Expect.classes.count)
        #expect(enums.count == Expect.enums.count)
        #expect(dataTypes.count == Expect.dataTypes.count)
    }

    @Test("package is cached")
    func packageIsCached() async throws {
        let first = try await GenModelPackage.load()
        let second = try await GenModelPackage.load()
        #expect(first.id == second.id)
    }

    @Test("constants name every classifier of the metamodel")
    func constantsMatchMetamodel() async throws {
        let package = try await GenModelPackage.load()
        let names = Set(package.eClassifiers.map(\.name))
        let constants = Set(
            GenModelConstants.ClassName.all + GenModelConstants.EnumName.all
                + GenModelConstants.DataTypeName.all)
        #expect(names == constants)
    }

    @Test("every feature name used by constants exists in the metamodel")
    func featureConstantsExist() throws {
        let document = try Self.document()
        let all = Set(
            document.classifiers.flatMap { $0.children(named: "eStructuralFeatures") }
                .compactMap { $0["name"] })
        for name in GenModelConstants.FeatureName.containments
            + GenModelConstants.FeatureName.ecoreReferences
            + [
                GenModelConstants.FeatureName.foreignModel,
                GenModelConstants.FeatureName.usedGenPackages,
                GenModelConstants.FeatureName.labelFeature, GenModelConstants.FeatureName.prefix,
                GenModelConstants.FeatureName.modelName,
            ]
        {
            #expect(all.contains(name), "missing feature \(name)")
        }
    }

    @Test("classes have the expected supertypes and abstractness", arguments: Expect.classes)
    func classStructure(expected: (name: String, supertypes: String, isAbstract: Bool)) async throws {
        let package = try await GenModelPackage.load()
        let eClass = try #require(package.getEClass(expected.name))
        let supertypes = expected.supertypes.split(separator: ",").map(String.init)
        #expect(eClass.eSuperTypes.map(\.name) == supertypes)
        #expect(eClass.isAbstract == expected.isAbstract)
    }

    @Test("classes list their features in metamodel order")
    func featureOrder() async throws {
        let package = try await GenModelPackage.load()
        let rows = try Self.rows()
        for expected in Expect.classes {
            let eClass = try #require(package.getEClass(expected.name))
            let names = rows.filter { $0.owner == expected.name }.map(\.name)
            #expect(eClass.eStructuralFeatures.map(\.name) == names, "\(expected.name)")
        }
    }

    @Test("features as loaded keep kind, bounds, containment and default")
    func loadedFeatures() async throws {
        let package = try await GenModelPackage.load()
        for row in try Self.rows() {
            let eClass = try #require(package.getEClass(row.owner))
            let feature = try #require(eClass.eStructuralFeatures.first { $0.name == row.name })
            let lower = try #require(Int(row.lower))
            let upper = try #require(Int(row.upper))
            let defaultLiteral: String? =
                row.defaultValue == "-" ? nil : (row.defaultValue == "~" ? "" : row.defaultValue)
            let label = "\(row.owner).\(row.name)"
            switch row.kind {
            case "A":
                let attribute = try #require(feature as? EAttribute, Comment(rawValue: label))
                #expect(attribute.lowerBound == lower, Comment(rawValue: label))
                #expect(attribute.upperBound == upper, Comment(rawValue: label))
                #expect(attribute.defaultValueLiteral == defaultLiteral, Comment(rawValue: label))
                if row.type.hasPrefix("ecore.") {
                    #expect(attribute.eType.name == String(row.type.dropFirst(6)), Comment(rawValue: label))
                }
            default:
                let reference = try #require(feature as? EReference, Comment(rawValue: label))
                #expect(reference.lowerBound == lower, Comment(rawValue: label))
                #expect(reference.upperBound == upper, Comment(rawValue: label))
                #expect(reference.containment == row.flags.contains("C"), Comment(rawValue: label))
                #expect((reference.opposite != nil) == (row.opposite != "-"), Comment(rawValue: label))
                #expect(reference.eType.name == String(row.type.split(separator: ".").last ?? ""),
                    Comment(rawValue: label))
            }
        }
    }

    @Test("feature declarations in the document match the expectation table exactly")
    func documentFeatures() throws {
        let document = try Self.document()
        let rows = try Self.rows()
        var index = 0
        for classifier in document.classifiers where classifier["xsi:type"] == "ecore:EClass" {
            for feature in classifier.children(named: "eStructuralFeatures") {
                let row = rows[index]
                index += 1
                let label = "\(row.owner).\(row.name)"
                #expect(classifier["name"] == row.owner, Comment(rawValue: label))
                let isReference = feature["xsi:type"] == "ecore:EReference"
                #expect(isReference == (row.kind == "R"), Comment(rawValue: label))
                #expect((feature["lowerBound"] ?? "0") == row.lower, Comment(rawValue: label))
                #expect((feature["upperBound"] ?? "1") == row.upper, Comment(rawValue: label))
                let type = try #require(feature["eType"], Comment(rawValue: label))
                if row.type.hasPrefix("ecore.") {
                    #expect(
                        type.hasSuffix("http://www.eclipse.org/emf/2002/Ecore#//\(row.type.dropFirst(6))"),
                        Comment(rawValue: label))
                } else {
                    #expect(type == "#//\(row.type)", Comment(rawValue: label))
                }
                func flag(_ attribute: String, _ letter: Character, inverse: Bool = false) {
                    let isSet = inverse ? feature[attribute] == "false" : feature[attribute] == "true"
                    #expect(isSet == row.flags.contains(letter), Comment(rawValue: "\(label) \(attribute)"))
                }
                flag("containment", "C")
                flag("changeable", "N", inverse: true)
                flag("volatile", "V")
                flag("transient", "T")
                flag("unsettable", "U")
                flag("derived", "D")
                flag("resolveProxies", "P", inverse: true)
                let defaultValue = feature["defaultValueLiteral"]
                let expected = row.defaultValue == "-" ? nil : (row.defaultValue == "~" ? "" : row.defaultValue)
                #expect(defaultValue == expected, Comment(rawValue: label))
                let expectedOpposite = row.opposite == "-" ? "-" : "#//\(row.opposite)"
                #expect((feature["eOpposite"] ?? "-") == expectedOpposite, Comment(rawValue: label))
            }
        }
        #expect(index == rows.count)
    }

    @Test("opposites are symmetrical")
    func oppositesSymmetrical() throws {
        let rows = try Self.rows()
        let byKey = Dictionary(uniqueKeysWithValues: rows.map { ("\($0.owner)/\($0.name)", $0) })
        for row in rows where row.opposite != "-" {
            let other = try #require(byKey[row.opposite], "unknown opposite \(row.opposite)")
            #expect(other.opposite == "\(row.owner)/\(row.name)")
        }
    }

    @Test("derived and volatile features are marked as in the published metamodel")
    func derivedFeatures() throws {
        let rows = try Self.rows()
        let derived = rows.filter { $0.flags.contains("D") }.map { "\($0.owner).\($0.name)" }
        #expect(
            Set(derived) == [
                "GenModel.richClientPlatform", "GenModel.reflectiveDelegation",
                "GenModel.richAjaxPlatform",
            ])
        let transientVolatile = rows.filter { $0.flags.contains("V") && $0.flags.contains("T") }
            .map { "\($0.owner).\($0.name)" }
        #expect(transientVolatile.contains("GenPackage.genClassifiers"))
        #expect(transientVolatile.contains("GenClassifier.genPackage"))
    }

    @Test("enumerations declare the expected literals", arguments: Expect.enums)
    func enumerations(expected: (name: String, literals: [(name: String, value: Int, literal: String)]))
        async throws
    {
        let package = try await GenModelPackage.load()
        let eEnum = try #require(package.getClassifier(expected.name) as? EEnum)
        #expect(eEnum.literals.map(\.name) == expected.literals.map(\.name))
        #expect(eEnum.literals.map(\.value) == expected.literals.map(\.value))

        let document = try Self.document()
        let node = try #require(document.classifier(expected.name))
        let literals = node.children(named: "eLiterals")
        #expect(literals.map { $0["name"] ?? "" } == expected.literals.map(\.name))
        #expect(literals.map { Int($0["value"] ?? "0") ?? -1 } == expected.literals.map(\.value))
        for (literal, expectedLiteral) in zip(literals, expected.literals) {
            #expect((literal["literal"] ?? literal["name"]) == expectedLiteral.literal)
        }
    }

    @Test("data types are declared", arguments: Expect.dataTypes)
    func dataTypes(expected: (name: String, instanceType: String)) async throws {
        let package = try await GenModelPackage.load()
        let dataType = try #require(package.getClassifier(expected.name) as? EDataType)
        #expect(dataType.instanceClassName == expected.instanceType)
    }

    @Test("GenBase declares the annotation lookup operation")
    func genBaseOperation() throws {
        let node = try #require(try Self.document().classifier("GenBase"))
        let operation = try #require(node.children(named: "eOperations").first)
        #expect(operation["name"] == "getGenAnnotation")
        #expect(operation["eType"] == "#//GenAnnotation")
        #expect(operation.children(named: "eParameters").map { $0["name"] } == ["source"])
    }

    @Test("documentation annotations use the generator source and key")
    func documentationAnnotations() throws {
        let document = try Self.document()
        for classifier in document.classifiers {
            let annotation = try #require(classifier.children(named: "eAnnotations").first)
            #expect(annotation["source"] == GenModelConstants.documentationSource)
            let detail = try #require(annotation.children(named: "details").first)
            #expect(detail["key"] == GenModelConstants.documentationKey)
            #expect(!(detail["value"] ?? "").isEmpty)
        }
    }
}
