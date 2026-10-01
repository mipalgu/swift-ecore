//
// EAnnotationLoadingTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Locates the annotation fixtures.
enum AnnotationFixtures {
    /// The URL of a document in the `annotations` fixture directory.
    static func url(_ name: String = "annotated.ecore") throws -> URL {
        try ReflectionFixtures.resourcesURL().appendingPathComponent("annotations")
            .appendingPathComponent(name)
    }

    /// The package of a native load of a fixture.
    static func package(_ name: String = "annotated.ecore") async throws -> EPackage {
        try await EPackage(url: try url(name))
    }

    /// The text of a fixture.
    static func text(_ name: String = "annotated.ecore") throws -> String {
        try String(contentsOf: try url(name), encoding: .utf8)
    }
}

@Suite("Native Annotation Loading Tests")
struct NativeAnnotationLoadingTests {
    private let genModel = AnnotationSource.genModel

    private func documentation(of element: some EModelElement) -> String? {
        element.getEAnnotationDetail(
            source: genModel, key: AnnotationSource.GenModelKey.documentation)
    }

    @Test("every kind of element carries its annotations")
    func everyElementKind() async throws {
        let package = try await AnnotationFixtures.package()
        #expect(documentation(of: package) == "The annotated package.")
        let book = try #require(package.getEClass("Book"))
        #expect(book.getEAnnotationDetail(
            source: AnnotationSource.ecore, key: AnnotationSource.EcoreKey.constraints)
            == "NonEmpty Positive")
        let title = try #require(book.eAttributes.first { $0.name == "title" })
        #expect(documentation(of: title) == "The title.")
        let author = try #require(book.eReferences.first { $0.name == "author" })
        #expect(documentation(of: author) == "The author.")
        let borrow = try #require(book.eOperations.first)
        #expect(documentation(of: borrow) == "Borrows the book.")
        #expect(borrow.getEAnnotationDetail(source: genModel, key: AnnotationSource.GenModelKey.body)
            == "return days > 0;")
        let days = try #require(borrow.eParameters.first)
        #expect(documentation(of: days) == "The number of days.")
        let format = try #require(package.eClassifiers.first { $0.name == "Format" } as? EEnum)
        #expect(documentation(of: format) == "The format.")
        #expect(documentation(of: try #require(format.literals.first)) == "Hard cover.")
        #expect(format.literals.last?.eAnnotations.isEmpty == true)
        let isbn = try #require(package.eClassifiers.first { $0.name == "ISBN" } as? EDataType)
        #expect(documentation(of: isbn) == "An ISBN.")
        #expect(documentation(of: try #require(package.eSubpackages.first)) == "The inner package.")
        #expect(try #require(package.getEClass("Author")).eAnnotations.isEmpty)
    }

    @Test("sources are listed in document order and found by source")
    func sourcesInOrder() async throws {
        let package = try await AnnotationFixtures.package()
        #expect(package.eAnnotations.map(\.source) == [genModel, AnnotationSource.extendedMetaData])
        let extended = try #require(package.getEAnnotation(source: AnnotationSource.extendedMetaData))
        #expect(extended.details.keys.elements == ["name", "kind", "namespace"])
        #expect(extended.details[AnnotationSource.ExtendedMetaDataKey.namespace] == "##targetNamespace")
        #expect(package.getEAnnotation(source: "urn:missing") == nil)
        #expect(package.getEAnnotationDetail(source: genModel, key: "missing") == nil)
    }

    @Test("details keep the order of the document, not alphabetical order")
    func detailOrder() async throws {
        let book = try #require(try await AnnotationFixtures.package().getEClass("Book"))
        let annotation = try #require(book.getEAnnotation(source: genModel))
        #expect(annotation.details.keys.elements == ["zeta", "alpha", "mid"])
        #expect(annotation.detailEntries.map(\.key) == ["zeta", "alpha", "mid"])
    }

    @Test("multi-line values and XML entities are preserved")
    func entitiesAndNewlines() async throws {
        let package = try await AnnotationFixtures.package()
        let copyright = try #require(
            package.getEAnnotationDetail(source: genModel, key: "copyright"))
        #expect(copyright == "Line one\nLine two & <three> \"four\"\tfive")
    }

    @Test("annotations nest inside annotations")
    func nestedAnnotations() async throws {
        let book = try #require(try await AnnotationFixtures.package().getEClass("Book"))
        let outer = try #require(book.getEAnnotation(source: "urn:example:outer"))
        #expect(outer.details["depth"] == "1")
        let inner = try #require(outer.getEAnnotation(source: "urn:example:inner"))
        #expect(inner.details["depth"] == "2")
        #expect(inner.eContainerID == outer.id)
        #expect(outer.eContents.count == 2)
        #expect(outer.getEAnnotationDetail(source: "urn:example:inner", key: "depth") == "2")
    }

    @Test("references name local elements by identifier and other documents by proxy")
    func references() async throws {
        let package = try await AnnotationFixtures.package()
        let book = try #require(package.getEClass("Book"))
        let annotation = try #require(book.getEAnnotation(source: "urn:example:references"))
        let title = try #require(book.eAttributes.first { $0.name == "title" })
        let format = try #require(package.eClassifiers.first { $0.name == "Format" } as? EEnum)
        let days = try #require(book.eOperations.first?.eParameters.first)
        #expect(annotation.references.count == 4)
        #expect(annotation.references[0] == .local(title.id))
        #expect(annotation.references[1] == .local(try #require(format.literals.first).id))
        #expect(annotation.references[2] == .local(days.id))
        guard case .external(let proxy) = annotation.references[3] else {
            Issue.record("expected an external reference")
            return
        }
        #expect(proxy.uri == (try AnnotationFixtures.url("annotated-other.ecore")).absoluteString)
        #expect(proxy.fragment == "//Other")
    }

    @Test("contents are kept as objects")
    func contents() async throws {
        let book = try #require(try await AnnotationFixtures.package().getEClass("Book"))
        let annotation = try #require(book.getEAnnotation(source: "urn:example:contents"))
        #expect(annotation.contents.count == 1)
        let embedded = try #require(annotation.contents.first as? DynamicEObject)
        #expect(embedded.eGet("name") as? String == "Embedded")
        #expect(embedded.eClass.name == "EClass")
    }

    @Test("annotations load identically through the resource set")
    func resourceSetLoad() async throws {
        let set = ResourceSet()
        let resource = try await set.loadEcoreResource(uri: try AnnotationFixtures.url().absoluteString)
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        #expect(documentation(of: package) == "The annotated package.")
        let annotation = try #require(package.getEAnnotation(source: genModel))
        #expect(await resource.resolve(annotation.id) != nil)
    }

    @Test("annotation features are navigable reflectively")
    func reflectiveNavigation() async throws {
        let package = try await AnnotationFixtures.package()
        let annotations = try #require(
            try ReflectionFixtures.value(of: package, "eAnnotations") as? EcoreValueArray)
        #expect(annotations.values.count == 2)
        let first = try #require(annotations.values.first as? EAnnotation)
        #expect(try ReflectionFixtures.value(of: first, "source") as? String == genModel)
        let entries = try #require(
            try ReflectionFixtures.value(of: first, "details") as? EcoreValueArray)
        let entry = try #require(entries.values.first as? EStringToStringMapEntry)
        #expect(try ReflectionFixtures.value(of: entry, "key") as? String == "documentation")
        #expect(try ReflectionFixtures.value(of: entry, "value") as? String == "The annotated package.")

        let book = try #require(package.getEClass("Book"))
        let referencing = try #require(book.getEAnnotation(source: "urn:example:references"))
        let references = try #require(
            try ReflectionFixtures.value(of: referencing, "references") as? EcoreValueArray)
        #expect(references.values.count == 4)
        #expect(references.values[0] is EUUID)
        #expect(references.values[3] is ResourceProxy)

        let containing = try #require(book.getEAnnotation(source: "urn:example:contents"))
        let contents = try #require(
            try ReflectionFixtures.value(of: containing, "contents") as? EcoreValueArray)
        #expect(contents.values.count == 1)

        let outer = try #require(book.getEAnnotation(source: "urn:example:outer"))
        let nested = try #require(
            try ReflectionFixtures.value(of: outer, "eAnnotations") as? EcoreValueArray)
        #expect(nested.values.count == 1)
    }

    @Test("reflective setters change annotation features")
    func reflectiveSetters() throws {
        var annotation = EAnnotation(source: "urn:a")
        let eAnnotation = EcorePackage.metaClass(.eAnnotation)
        func feature(_ name: String) throws -> any EStructuralFeature {
            try #require(eAnnotation.getStructuralFeature(name: name))
        }
        let identifier = EUUID()
        annotation.set(
            try feature("references"),
            EcoreValueArray([identifier, ResourceProxy(uri: "u", fragment: "//X")]))
        #expect(annotation.references == [.local(identifier), .external(ResourceProxy(uri: "u", fragment: "//X"))])
        annotation.set(try feature("eAnnotations"), EcoreValueArray([EAnnotation(source: "urn:b")]))
        #expect(annotation.eAnnotations.map(\.source) == ["urn:b"])
        #expect(annotation.eAnnotations.first?.eContainerID == annotation.id)
        let content = DynamicEObject(eClass: EClass(name: "Thing"))
        annotation.set(try feature("contents"), EcoreValueArray([content]))
        #expect(annotation.contents.map(\.id) == [content.id])
        #expect(annotation.eContents.count == 2)
        annotation.set(try feature("references"), EcoreValueArray([identifier as EUUID, 3]))
        #expect(annotation.references == [.local(identifier)])
        #expect(EAnnotationReference(value: 3) == nil)
    }

    @Test("annotations compare equal only if everything they hold is equal")
    func equality() {
        let identifier = EUUID()
        let base = EAnnotation(id: identifier, source: "urn:a", details: ["k": "v"])
        #expect(base == EAnnotation(id: identifier, source: "urn:a", details: ["k": "v"]))
        #expect(base != EAnnotation(id: identifier, source: "urn:a", details: ["k": "w"]))
        #expect(base != EAnnotation(id: identifier, source: "urn:a", details: ["k": "v"],
            eAnnotations: [EAnnotation(source: "urn:b")]))
        #expect(base != EAnnotation(id: identifier, source: "urn:a", details: ["k": "v"],
            references: [.local(EUUID())]))
        let thing = DynamicEObject(eClass: EClass(name: "Thing"))
        let withContent = EAnnotation(id: identifier, source: "urn:a", details: ["k": "v"], contents: [thing])
        #expect(base != withContent)
        #expect(withContent == EAnnotation(id: identifier, source: "urn:a", details: ["k": "v"], contents: [thing]))
        #expect(Set([base, withContent]).count == 2)
        #expect(EAnnotation(id: identifier, source: "urn:a", orderedDetails: ["a": "1", "b": "2"])
            != EAnnotation(id: identifier, source: "urn:a", orderedDetails: ["b": "2", "a": "1"]))
        #expect(EAnnotation(id: identifier, source: "urn:a", details: ["a": "1", "b": "2"])
            == EAnnotation(id: identifier, source: "urn:a", details: ["b": "2", "a": "1"]))
        #expect(EAnnotation(source: "urn:a", details: ["b": "2", "a": "1"]).details.keys.elements == ["a", "b"])
    }
}

@Suite("Dynamic Annotation Loading Tests")
struct DynamicAnnotationLoadingTests {
    private func parse() async throws -> Resource {
        try await XMIParser().parse(try AnnotationFixtures.url())
    }

    private func element(_ fragment: String, in resource: Resource) async throws -> DynamicEObject {
        try #require(await FragmentNavigator(resource: resource).resolve(fragment) as? DynamicEObject)
    }

    private func identifiers(_ value: (any EcoreValue)?) -> [EUUID] {
        switch value {
        case let identifier as EUUID: return [identifier]
        case let identifiers as [EUUID]: return identifiers
        default: return []
        }
    }

    private func annotations(of object: DynamicEObject, in resource: Resource) async -> [DynamicEObject] {
        var result: [DynamicEObject] = []
        for identifier in identifiers(object.eGet("eAnnotations")) {
            if let annotation = await resource.resolve(identifier) as? DynamicEObject { result.append(annotation) }
        }
        return result
    }

    private func details(of annotation: DynamicEObject, in resource: Resource) async -> [(String, String)] {
        var result: [(String, String)] = []
        for identifier in identifiers(annotation.eGet("details")) {
            if let entry = await resource.resolve(identifier) as? DynamicEObject {
                result.append((entry.eGet("key") as? String ?? "", entry.eGet("value") as? String ?? ""))
            }
        }
        return result
    }

    @Test("every kind of element carries its annotations")
    func everyElementKind() async throws {
        let resource = try await parse()
        for fragment in [
            "/", "//Book", "//Book/title", "//Book/author", "//Book/borrow", "//Book/borrow/days",
            "//Format", "//Format/Hardback", "//ISBN", "//inner",
        ] {
            let object = try await element(fragment, in: resource)
            let found = await annotations(of: object, in: resource)
            #expect(!found.isEmpty, "\(fragment) has annotations")
            #expect(found.allSatisfy { $0.eClass.name == "EAnnotation" })
        }
        let author = try await element("//Author", in: resource)
        #expect(await annotations(of: author, in: resource).isEmpty)
    }

    @Test("sources, details, and entities are preserved in order")
    func sourcesAndDetails() async throws {
        let resource = try await parse()
        let package = try await element("/", in: resource)
        let found = await annotations(of: package, in: resource)
        #expect(found.map { $0.eGet("source") as? String } == [
            AnnotationSource.genModel, AnnotationSource.extendedMetaData,
        ])
        let entries = await details(of: found[0], in: resource)
        #expect(entries.map(\.0) == ["documentation", "copyright"])
        #expect(entries[1].1 == "Line one\nLine two & <three> \"four\"\tfive")
        let book = try await element("//Book", in: resource)
        let order = await annotations(of: book, in: resource)[1]
        #expect(await details(of: order, in: resource).map(\.0) == ["zeta", "alpha", "mid"])
    }

    @Test("nested annotations, contents, and references are loaded")
    func nestedContentsAndReferences() async throws {
        let resource = try await parse()
        let book = try await element("//Book", in: resource)
        let found = await annotations(of: book, in: resource)
        let referencing = try #require(found.first { $0.eGet("source") as? String == "urn:example:references" })
        let references = referencing.eGet("references")
        let proxies = try #require(references as? [ResourceProxy])
        #expect(proxies.count == 4)
        #expect(proxies[3].fragment == "//Other")
        #expect(proxies[3].uri.hasSuffix("annotated-other.ecore"))
        let outer = try #require(found.first { $0.eGet("source") as? String == "urn:example:outer" })
        let nested = await annotations(of: outer, in: resource)
        #expect(nested.map { $0.eGet("source") as? String } == ["urn:example:inner"])
        let containing = try #require(found.first { $0.eGet("source") as? String == "urn:example:contents" })
        let contentID = try #require(identifiers(containing.eGet("contents")).first)
        let content = try #require(await resource.resolve(contentID) as? DynamicEObject)
        #expect(content.eGet("name") as? String == "Embedded")
    }

    @Test("references to elements of the same document resolve to identifiers")
    func localReferences() async throws {
        let set = ResourceSet()
        let resource = try await set.loadXMIResource(uri: try AnnotationFixtures.url().absoluteString)
        let book = try await element("//Book", in: resource)
        let referencing = try #require(
            await annotations(of: book, in: resource).first {
                $0.eGet("source") as? String == "urn:example:references"
            })
        let title = try await element("//Book/title", in: resource)
        let values = try #require(referencing.eGet("references") as? [ResourceProxy])
        #expect(values.first?.fragment == "//Book/title")
        #expect(values.first?.uri == resource.uri)
        #expect(title.eGet("name") as? String == "title")
    }

    @Test("a document with only same-document references stores identifiers")
    func onlyLocalReferences() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try FidelityFixtures.writeDocument(
            """
              <eClassifiers xsi:type="ecore:EClass" name="A">
                <eAnnotations source="urn:x" references="#//A #//B"/>
              </eClassifiers>
              <eClassifiers xsi:type="ecore:EClass" name="B"/>
            """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let resource = try await XMIParser().parse(url)
        let a = try await element("//A", in: resource)
        let annotation = try #require(await annotations(of: a, in: resource).first)
        let targets = identifiers(annotation.eGet("references"))
        #expect(targets.count == 2)
        let b = try await element("//B", in: resource)
        #expect(targets[1] == b.id)
    }
}
