//
// ConversionDiagnosticsTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for untyped JSON documents and for the warnings that parsers and serialisers
/// record when a conversion cannot keep all information.
@Suite("Conversion diagnostics")
struct ConversionDiagnosticsTests {
    /// The namespace URI of the shelf package.
    static let shelfURI = "http://www.example.org/shelf"

    /// A shelf metamodel: a shelf contains books and refers to a favourite book.
    static func shelfPackage() -> EPackage {
        let string = EcorePackage.dataType(.eString) ?? EDataType(name: "EString")
        let book = EClass(name: "Book", eStructuralFeatures: [EAttribute(name: "title", eType: string)])
        let shelf = EClass(
            name: "Shelf",
            eStructuralFeatures: [
                EAttribute(name: "label", eType: string),
                EReference(name: "books", eType: book, upperBound: -1, containment: true),
                EReference(name: "favourite", eType: book),
            ])
        return EPackage(name: "shelf", nsURI: shelfURI, nsPrefix: "shelf", eClassifiers: [shelf, book])
    }

    /// Creates a shelf resource in a resource set with the shelf metamodel.
    ///
    /// - Parameter configure: Adjusts the shelf, given the identifiers of its two books.
    /// - Returns: The resource set, the resource, and the two books.
    static func shelf(
        configure: (inout DynamicEObject, [DynamicEObject]) -> Void = { _, _ in }
    ) async throws -> (set: ResourceSet, resource: Resource, books: [DynamicEObject]) {
        let set = ResourceSet()
        let package = shelfPackage()
        await set.registerMetamodel(package, uri: package.nsURI)
        let bookClass = try #require(package.getEClass("Book"))
        let books = ["Engines", "Tides"].map { title -> DynamicEObject in
            var book = DynamicEObject(eClass: bookClass)
            book.eSet("title", value: title)
            return book
        }
        var shelf = DynamicEObject(eClass: try #require(package.getEClass("Shelf")))
        shelf.eSet("label", value: "Science")
        shelf.eSet("books", value: books.map(\.id))
        configure(&shelf, books)
        let resource = await set.createResource(uri: "file:///shelf.xmi")
        for book in books { await resource.register(book) }
        await resource.add(shelf)
        return (set, resource, books)
    }

    /// The warnings that every writer records for a resource.
    ///
    /// - Parameter resource: The resource to write.
    /// - Returns: The warnings of the legacy XMI writer, the EMF-style XMI writer, and the JSON writer.
    static func writerWarnings(_ resource: Resource) async throws -> [[ConversionWarning.Kind]] {
        var results: [[ConversionWarning.Kind]] = []
        for options in [XMISerializationOptions.legacy, .emf] {
            var diagnostics = ConversionDiagnostics()
            _ = try await XMISerializer(options: options).serialize(resource, diagnostics: &diagnostics)
            results.append(diagnostics.warnings.map(\.kind))
        }
        var diagnostics = ConversionDiagnostics()
        _ = try await JSONSerializer().serialize(resource, diagnostics: &diagnostics)
        results.append(diagnostics.warnings.map(\.kind))
        return results
    }

    /// Resolves the objects that a feature of an object holds.
    ///
    /// - Parameters:
    ///   - feature: The name of the feature.
    ///   - object: The object.
    ///   - resource: The resource that holds the objects.
    /// - Returns: The objects in order.
    static func objects(_ feature: String, of object: DynamicEObject, in resource: Resource) async throws
        -> [DynamicEObject]
    {
        var result: [DynamicEObject] = []
        for id in ReferenceValues.identifiers(object.eGet(feature)) {
            result.append(try #require(await resource.resolve(id) as? DynamicEObject))
        }
        return result
    }

    // MARK: - Untyped JSON documents

    @Test("an untyped JSON document registers every nested object with containment by identifier")
    func untypedJSONRegistersNestedObjects() async throws {
        let text = """
            {"eClass": "\(Self.shelfURI)#//Shelf", "label": "Science", "count": 2, "ratio": 0.5, "open": true,
             "books": [{"eClass": "\(Self.shelfURI)#//Book", "title": "Engines", "tags": ["a", "b"]},
                       {"eClass": "\(Self.shelfURI)#//Book", "title": "Tides"}],
             "favourite": {"$ref": "//@books.1"}}
            """
        let parser = JSONParser()
        let resource = try await parser.parse(Data(text.utf8), uri: "memory:/shelf.json")
        let roots = await resource.getRootObjects().compactMap { $0 as? DynamicEObject }
        try #require(roots.count == 1)
        let shelf = roots[0]
        #expect(await resource.getAllObjects().count == 3)
        let identifiers = try #require(shelf.eGet("books") as? [EUUID])
        let books = try await Self.objects("books", of: shelf, in: resource)
        #expect(books.map { $0.eGet("title") as? String } == ["Engines", "Tides"])
        #expect(books[0].eGet("tags") as? [String] == ["a", "b"])
        #expect(shelf.eGet("favourite") as? EUUID == identifiers[1])
        #expect(shelf.eGet("label") as? String == "Science")
        #expect(shelf.eGet("count") as? Int == 2)
        #expect(shelf.eGet("ratio") as? Double == 0.5)
        #expect(shelf.eGet("open") as? Bool == true)
        let warnings = await parser.diagnostics.warnings.map(\.kind)
        #expect(warnings == [.untypedClass(name: "Shelf"), .untypedClass(name: "Book")], "\(warnings)")
    }

    @Test("an untyped XMI document keeps every root's contents through JSON", arguments: [XMISerializationOptions.legacy, .emf])
    func untypedXMIJSONXMIRoundTrip(options: XMISerializationOptions) async throws {
        let url = try ReflectionFixtures.resourcesURL().appendingPathComponent("xmi/classifiers-two-roots.xmi")
        let original = try await XMIParser().parse(url)
        let json = try await JSONSerializer().serialize(original)
        let fromJSON = try await JSONParser().parse(Data(json.utf8), uri: "memory:/classifiers.json")
        let xmi = try await XMISerializer(options: options).serialize(fromJSON)
        let reloaded = try await XMIParser().parse(xmi, uri: "memory:/classifiers-again.xmi")
        let roots = await reloaded.getRootObjects().compactMap { $0 as? DynamicEObject }
        try #require(roots.count == 2, "\(xmi)")
        #expect(roots.map { $0.eGet("name") as? String } == ["library", "shop"])
        let library = try await Self.objects("classifiers", of: roots[0], in: reloaded)
        let shop = try await Self.objects("classifiers", of: roots[1], in: reloaded)
        #expect(library.map { $0.eGet("name") as? String } == ["String", "Book"], "\(xmi)")
        #expect(shop.map { $0.eGet("name") as? String } == ["Order", "Money"], "\(xmi)")
        try #require(library.count == 2)
        #expect(library[1].eGet("isAbstract") as? Bool == true, "\(xmi)")
        let attributes = try await Self.objects("attributes", of: library[1], in: reloaded)
        #expect(attributes.map { $0.eGet("name") as? String } == ["title"], "\(xmi)")
        if options == .emf {
            #expect(library.map(\.eClass.name) == ["DataType", "Class"], "\(xmi)")
            #expect(shop.map(\.eClass.name) == ["Class", "DataType"], "\(xmi)")
        }
    }

    // MARK: - Parser warnings

    @Test("the XMI parser reports the classes it fabricates")
    func xmiParserReportsUntypedClasses() async throws {
        let url = try ReflectionFixtures.resourcesURL().appendingPathComponent("xmi/classifiers-two-roots.xmi")
        let parser = XMIParser()
        _ = try await parser.parse(url)
        let warnings = await parser.diagnostics.warnings.map(\.kind)
        #expect(warnings.contains(.untypedClass(name: "Package")))
        #expect(warnings.contains(.untypedClass(name: "Class")))
        #expect(warnings.contains(.untypedClass(name: "DataType")))
        _ = try await parser.parse(EmptyDocumentTests.emptyXMI, uri: "memory:/empty.xmi")
        #expect(await parser.diagnostics.isEmpty)
    }

    @Test("the JSON parser reports dropped values and unresolved references")
    func jsonParserReportsLosses() async throws {
        let set = ResourceSet()
        let package = Self.shelfPackage()
        await set.registerMetamodel(package, uri: package.nsURI)
        let text = """
            {"eClass": "\(Self.shelfURI)#//Shelf", "label": "Science", "extra": {"depth": 3}, "empty": [],
             "favourite": {"$ref": "//@books.7"}}
            """
        let parser = JSONParser(resourceSet: set)
        _ = try await parser.parse(Data(text.utf8), uri: "memory:/lossy.json")
        let warnings = await parser.diagnostics.warnings.map(\.kind)
        #expect(
            warnings == [
                .droppedFeature(name: "extra", className: "Shelf"),
                .unresolvedProxy(uri: "memory:/lossy.json", fragment: "//@books.7"),
            ])
    }

    // MARK: - Writer warnings

    @Test("writers report classes of no known package")
    func writersReportUntypedClasses() async throws {
        let resource = Resource(uri: "file:///loose.xmi")
        var gadget = DynamicEObject(eClass: EClass(name: "Gadget"))
        gadget.eSet("size", value: 3)
        await resource.add(gadget)
        for warnings in try await Self.writerWarnings(resource) {
            #expect(warnings == [.untypedClass(name: "Gadget")], "\(warnings)")
        }
    }

    @Test("writers report references to objects that have no fragment")
    func writersReportReferencesWithoutFragment() async throws {
        let (_, resource, _) = try await Self.shelf { shelf, books in
            shelf.eSet("books", value: [books[0].id])
            shelf.eSet("favourite", value: books[1].id)
        }
        for warnings in try await Self.writerWarnings(resource) {
            #expect(warnings == [.referenceWithoutFragment(feature: "favourite", className: "Shelf")], "\(warnings)")
        }
    }

    @Test("writers report values that they leave out")
    func writersReportDroppedFeatures() async throws {
        let (_, resource, books) = try await Self.shelf()
        let shelfID = try #require(await resource.getRootObjects().first?.id)
        await resource.eSet(objectId: shelfID, feature: "shortlist", value: books[0])
        let warnings = try await Self.writerWarnings(resource)
        #expect(warnings[0] == [.droppedFeature(name: "shortlist", className: "Shelf")], "\(warnings[0])")
        #expect(warnings[1] == [.droppedFeature(name: "shortlist", className: "Shelf")], "\(warnings[1])")
        #expect(warnings[2].isEmpty, "\(warnings[2])")
    }

    @Test("writers report contained objects that the resource does not hold")
    func writersReportUnregisteredContainedObjects() async throws {
        let (_, resource, _) = try await Self.shelf { shelf, _ in
            shelf.eSet("books", value: [EUUID()])
        }
        for warnings in try await Self.writerWarnings(resource) {
            #expect(warnings == [.unregisteredContainedObject(className: "Book")], "\(warnings)")
        }
    }

    @Test("the XMI writers report contained objects stored inline")
    func xmiWritersReportInlineContainedObjects() async throws {
        let (_, resource, books) = try await Self.shelf { shelf, books in
            shelf.eSet("books", value: books)
        }
        #expect(books.count == 2)
        let warnings = try await Self.writerWarnings(resource)
        #expect(warnings[0] == [.unregisteredContainedObject(className: "Book")], "\(warnings[0])")
        #expect(warnings[1] == [.unregisteredContainedObject(className: "Book")], "\(warnings[1])")
    }

    @Test("writers report references into the document that name no object")
    func writersReportUnresolvedProxies() async throws {
        let (_, resource, _) = try await Self.shelf { shelf, _ in
            shelf.eSet("favourite", value: ResourceProxy(uri: "file:///shelf.xmi", fragment: "//@books.9"))
        }
        for warnings in try await Self.writerWarnings(resource) {
            #expect(warnings == [.unresolvedProxy(uri: "file:///shelf.xmi", fragment: "//@books.9")], "\(warnings)")
        }
    }

    // MARK: - Clean conversions

    @Test("a metamodel-aware conversion records no warnings")
    func cleanConversion() async throws {
        let (_, resource, books) = try await Self.shelf { shelf, books in
            shelf.eSet("favourite", value: books[1].id)
        }
        #expect(books.count == 2)
        for warnings in try await Self.writerWarnings(resource) {
            #expect(warnings.isEmpty, "\(warnings)")
        }

        let resourceSet = ResourceSet()
        let resources = try ReflectionFixtures.resourcesURL()
        _ = try await resourceSet.loadEcoreResource(
            text: try String(contentsOf: resources.appendingPathComponent("jsonmeta/JSONLibrary.ecore"), encoding: .utf8),
            uri: "memory:/jsonlibrary.ecore")
        let parser = JSONParser(resourceSet: resourceSet)
        let library = try await parser.parse(
            try Data(contentsOf: resources.appendingPathComponent("jsonmeta/library-fragments.json")),
            uri: "memory:/library.json")
        #expect(await parser.diagnostics.isEmpty)
        for warnings in try await Self.writerWarnings(library) {
            #expect(warnings.isEmpty, "\(warnings)")
        }

        let (classifierSet, _) = try await WrappedDocumentLoadingTests.makeResourceSet()
        let xmiParser = XMIParser(resourceSet: classifierSet)
        _ = try await xmiParser.parse(resources.appendingPathComponent("xmi/classifiers-two-roots.xmi"))
        #expect(await xmiParser.diagnostics.isEmpty)
    }

    @Test("a reused XMI parser reports the classes it fabricates on every parse")
    func reusedParserReportsAgain() async throws {
        let url = try ReflectionFixtures.resourcesURL().appendingPathComponent("xmi/classifiers-two-roots.xmi")
        let parser = XMIParser()
        _ = try await parser.parse(url)
        let first = await parser.diagnostics.warnings.map(\.kind)
        _ = try await parser.parse(url)
        let second = await parser.diagnostics.warnings.map(\.kind)
        #expect(second.contains(.untypedClass(name: "Package")), "\(second)")
        #expect(second == first)
    }

    @Test("valid targets of a reference that mixes resolved and unresolved entries are not reported")
    func mixedReferencesReportOnlyUnresolved() async throws {
        let set = await LegacyJSONTests.catalogueSet()
        let (resource, _) = try await LegacyJSONTests.load("fragments-container-side.json", in: set)
        let dangling = ConversionWarning.Kind.unresolvedProxy(
            uri: resource.uri, fragment: "6F1C2B4E-0D0A-4C47-9E6B-2B8E7B5C9A21")
        for warnings in try await Self.writerWarnings(resource) {
            #expect(warnings == [dangling], "\(warnings)")
        }
    }

    @Test("the JSON writer keeps the container side of a root contained in another document")
    func rootKeepsContainerSide() async throws {
        let set = await LegacyJSONTests.catalogueSet()
        let package = try #require(await set.getMetamodel(uri: LegacyJSONTests.catalogueURI))
        var section = DynamicEObject(eClass: try #require(package.getEClass("Section")))
        section.eSet("name", value: "Loose")
        section.eSet("catalogue", value: ResourceProxy(uri: "file:///catalogue.json", fragment: "/"))
        let resource = await set.createResource(uri: "file:///section.json")
        await resource.add(section)
        let json = try await JSONSerializer().serialize(resource)
        #expect(json.contains("catalogue"), "\(json)")
        let reloaded = try await JSONParser(resourceSet: set).parse(Data(json.utf8), uri: "file:///section-again.json")
        let root = try #require(await reloaded.getRootObjects().first as? DynamicEObject)
        #expect((root.eGet("catalogue") as? ResourceProxy)?.uri == "file:///catalogue.json")
    }

    // MARK: - Collecting warnings

    @Test("a warning describes itself and is recorded once")
    func warningsAreDistinct() {
        let warning = ConversionWarning(.untypedClass(name: "Gadget"))
        #expect(warning.description == warning.message)
        #expect(warning.message.contains("Gadget"))
        var diagnostics = ConversionDiagnostics()
        #expect(diagnostics.isEmpty)
        diagnostics.record(.untypedClass(name: "Gadget"))
        diagnostics.record(.droppedFeature(name: "size", className: "Gadget"))
        diagnostics.record(.untypedClass(name: "Gadget"))
        #expect(diagnostics.warnings.map(\.kind) == [
            .untypedClass(name: "Gadget"), .droppedFeature(name: "size", className: "Gadget"),
        ])
        var merged = ConversionDiagnostics()
        merged.record(.unresolvedProxy(uri: "a.xmi", fragment: "/"))
        merged.merge(diagnostics)
        #expect(merged.warnings.count == 3)
        let kinds: [ConversionWarning.Kind] = [
            .untypedClass(name: "A"), .referenceWithoutFragment(feature: "f", className: "A"),
            .droppedFeature(name: "g", className: "A"), .unregisteredContainedObject(className: "B"),
            .unresolvedProxy(uri: "a.xmi", fragment: "//@x.0"),
        ]
        #expect(Set(kinds.map { ConversionWarning($0).message }).count == kinds.count)
    }
}
