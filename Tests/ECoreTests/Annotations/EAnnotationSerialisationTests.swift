//
// EAnnotationSerialisationTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Serialisation options that wrap lines as EMF's editors do.
private let wrapped = XMISerializationOptions(lineWidth: XMISerializationOptions.emfLineWidth)

/// Copies fixtures into a fresh temporary directory so that documents can be written next to them.
private struct TemporaryModels {
    let directory: URL

    init(copying names: [(directory: String, name: String)]) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for entry in names {
            let source = try ReflectionFixtures.resourcesURL().appendingPathComponent(entry.directory)
                .appendingPathComponent(entry.name)
            try FileManager.default.copyItem(
                at: source, to: directory.appendingPathComponent(entry.name))
        }
    }

    func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

/// The annotations of a classifier or feature held as an existential.
private func modelAnnotations(_ element: Any) -> [EAnnotation] {
    (element as? any EModelElement)?.eAnnotations ?? []
}

/// Describes every annotation of a package in a form that is independent of identifiers.
private func describe(_ package: EPackage) -> [String] {
    var lines: [String] = []
    var paths: [EUUID: String] = [:]
    func index(_ package: EPackage, prefix: String) {
        paths[package.id] = prefix
        for classifier in package.eClassifiers {
            paths[classifier.id] = prefix + "/" + classifier.name
            if let eClass = classifier as? EClass {
                for feature in eClass.eStructuralFeatures { paths[feature.id] = paths[classifier.id]! + "/" + feature.name }
                for operation in eClass.eOperations {
                    paths[operation.id] = paths[classifier.id]! + "/" + operation.name
                    for parameter in operation.eParameters {
                        paths[parameter.id] = paths[operation.id]! + "/" + parameter.name
                    }
                }
            }
            if let eEnum = classifier as? EEnum {
                for literal in eEnum.literals { paths[literal.id] = paths[classifier.id]! + "/" + literal.name }
            }
        }
        for subpackage in package.eSubpackages { index(subpackage, prefix: prefix + "/" + subpackage.name) }
    }
    index(package, prefix: package.name)

    func annotations(_ list: [EAnnotation], owner: String, indent: String) {
        for annotation in list {
            let references = annotation.references.map { reference -> String in
                switch reference {
                case .local(let identifier): return paths[identifier] ?? "?"
                case .external(let proxy): return "\(proxy.uri.split(separator: "/").last ?? "")#\(proxy.fragment)"
                }
            }
            lines.append(
                "\(indent)\(owner) source=\(annotation.source) details=\(Array(annotation.details))"
                    + " references=\(references) contents=\(annotation.contents.count)")
            annotations(annotation.eAnnotations, owner: "nested", indent: indent + "  ")
        }
    }
    func visit(_ package: EPackage) {
        annotations(package.eAnnotations, owner: paths[package.id] ?? "?", indent: "")
        for classifier in package.eClassifiers {
            annotations(modelAnnotations(classifier), owner: paths[classifier.id] ?? "?", indent: "")
            if let eClass = classifier as? EClass {
                for feature in eClass.eStructuralFeatures {
                    annotations(modelAnnotations(feature), owner: paths[feature.id] ?? "?", indent: "")
                }
                for operation in eClass.eOperations {
                    annotations(operation.eAnnotations, owner: paths[operation.id] ?? "?", indent: "")
                    for parameter in operation.eParameters {
                        annotations(parameter.eAnnotations, owner: paths[parameter.id] ?? "?", indent: "")
                    }
                }
            }
            if let eEnum = classifier as? EEnum {
                for literal in eEnum.literals {
                    annotations(literal.eAnnotations, owner: paths[literal.id] ?? "?", indent: "")
                }
            }
        }
        for subpackage in package.eSubpackages { visit(subpackage) }
    }
    visit(package)
    return lines
}

@Suite("Annotation Serialisation Tests")
struct AnnotationSerialisationTests {
    @Test("an annotated document round-trips byte for byte")
    func byteStableRoundTrip() async throws {
        let models = try TemporaryModels(copying: [
            (directory: "annotations", name: "annotated.ecore"),
            (directory: "annotations", name: "annotated-other.ecore"),
        ])
        defer { models.remove() }
        let package = try await EPackage(url: models.url("annotated.ecore"))
        let text = XMISerializer(options: wrapped).serialize(package)
        #expect(text == (try AnnotationFixtures.text()))
    }

    @Test("annotations survive a write and a reload")
    func semanticRoundTrip() async throws {
        let models = try TemporaryModels(copying: [
            (directory: "annotations", name: "annotated.ecore"),
            (directory: "annotations", name: "annotated-other.ecore"),
        ])
        defer { models.remove() }
        let original = try await EPackage(url: models.url("annotated.ecore"))
        let target = models.url("written.ecore")
        try XMISerializer().serialize(original, to: target)
        let reloaded = try await EPackage(url: target)
        let before = describe(original)
        #expect(!before.isEmpty)
        #expect(describe(reloaded) == before)
        let again = XMISerializer().serialize(reloaded, relativeTo: target)
        #expect(again == (try String(contentsOf: target, encoding: .utf8)))
    }

    @Test("newlines, tabs, quotes, and ampersands are escaped as EMF writes them")
    func escaping() {
        let annotation = EAnnotation(
            source: "urn:s",
            orderedDetails: ["k": "a\nb\r\tc & <d> \"e\" 'f'"])
        let package = EPackage(
            name: "p", nsURI: "http://p", nsPrefix: "p", eAnnotations: [annotation])
        let text = XMISerializer().serialize(package)
        #expect(text.contains("value=\"a&#xA;b&#xD;&#x9;c &amp; &lt;d> &quot;e&quot; 'f'\""))
    }

    @Test("an annotation without a source or details is written as an empty element")
    func emptyAnnotation() {
        let package = EPackage(
            name: "p", nsURI: "http://p", nsPrefix: "p",
            eAnnotations: [EAnnotation(source: "")])
        #expect(XMISerializer().serialize(package).contains("  <eAnnotations/>\n"))
    }

    @Test("references that cannot be written are left out")
    func unwritableReferences() {
        let annotation = EAnnotation(source: "urn:s", references: [.local(EUUID())])
        let package = EPackage(name: "p", nsURI: "http://p", nsPrefix: "p", eAnnotations: [annotation])
        #expect(!XMISerializer().serialize(package).contains("references="))
    }

    @Test("an external reference to the written document becomes a local fragment")
    func sameDocumentProxy() {
        let target = URL(fileURLWithPath: "/models/self.ecore")
        let proxy = ResourceProxy(uri: target.absoluteString, fragment: "//A")
        let annotation = EAnnotation(source: "urn:s", references: [.external(proxy)])
        let package = EPackage(name: "p", nsURI: "http://p", nsPrefix: "p", eAnnotations: [annotation])
        let text = XMISerializer().serialize(package, relativeTo: target)
        #expect(text.contains("references=\"#//A\""))
    }

    @Test("contents are written with their metaclass and primitive attributes")
    func contents() {
        let metaclass = EcorePackage.metaClass(.eClass)
        var object = DynamicEObject(eClass: metaclass)
        object.eSet("name", value: "Embedded")
        object.eSet("abstract", value: true)
        var embedded = DynamicEObject(
            eClass: EClass(
                name: "Custom",
                eStructuralFeatures: [
                    EAttribute(name: "count", eType: EcorePackage.dataType(.eInt)!),
                    EAttribute(name: "label", eType: EcorePackage.dataType(.eString)!),
                ]))
        embedded.eSet("count", value: 3)
        embedded.eSet("label", value: "x")
        let package = EPackage(
            name: "p", nsURI: "http://p", nsPrefix: "p",
            eAnnotations: [EAnnotation(source: "urn:s", contents: [object, embedded])])
        let text = XMISerializer().serialize(package)
        #expect(text.contains("<contents xsi:type=\"ecore:EClass\" name=\"Embedded\" abstract=\"true\"/>"))
        #expect(text.contains("<contents xsi:type=\"Custom\" count=\"3\" label=\"x\"/>"))
    }
}
