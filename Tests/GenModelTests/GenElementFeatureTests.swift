//
// GenElementFeatureTests.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import GenModel

@Suite("GenElement feature shortcuts")
struct GenElementFeatureTests {
    /// A bookshelf model with a containment relationship and its opposite.
    private struct Bookshelf {
        let shelf: GenElement
        let book: GenElement

        init() async throws {
            var sample = try await SampleModel()
            let contentsID = EUUID()
            let shelfID = EUUID()
            let bookClassStub = EClass(name: "Book")
            let shelfClassStub = EClass(name: "Shelf")
            let contents = EReference(
                id: contentsID, name: "books", eType: bookClassStub, upperBound: -1, containment: true,
                opposite: shelfID)
            let shelf = EReference(
                id: shelfID, name: "shelf", eType: shelfClassStub, containment: false,
                opposite: contentsID)
            let author = EReference(
                name: "author", eType: shelfClassStub, lowerBound: 1, changeable: false,
                volatile: true, transient: true)
            let bookClass = EClass(
                name: "Book",
                eStructuralFeatures: [
                    SampleModel.attribute("title"),
                    SampleModel.attribute("pages", type: SampleModel.intType, defaultValue: "100"),
                    SampleModel.attribute("tags", upper: -1),
                    SampleModel.attribute("note", upper: 3), shelf, author,
                ])
            let shelfClass = EClass(name: "Shelf", eStructuralFeatures: [contents])
            let ecore = EPackage(
                name: "bs", nsURI: "http://example.org/bs", nsPrefix: "bs",
                eClassifiers: [bookClass, shelfClass])
            sample.addPackage(ecore)
            let bookGen = try sample.genClass(bookClass)
            let shelfGen = try sample.genClass(shelfClass)
            let package = try sample.genPackage(
                ecore, prefix: "Bs", classes: [bookGen.genClass, shelfGen.genClass])
            _ = try sample.genModel(packages: [package])
            let context = sample.context
            book = try #require(context.element(id: bookGen.genClass.id))
            self.shelf = try #require(context.element(id: shelfGen.genClass.id))
        }

        func feature(_ name: String) throws -> GenElement {
            try #require((book.genFeatures + shelf.genFeatures).first { $0.name == name })
        }
    }

    @Test("attribute shortcuts")
    func attributes() async throws {
        let model = try await Bookshelf()
        let title = try model.feature("title")
        #expect(title.isAttributeType)
        #expect(!title.isReferenceType)
        #expect(!title.isContainment)
        #expect(!title.isContainer)
        #expect(!title.isBidirectional)
        #expect(title.reverseGenFeature == nil)
        #expect(!title.hasDefault)
        #expect(title.defaultValueLiteral == nil)
        #expect(title.lowerBound == 0)
        #expect(title.upperBound == 1)
        #expect(!title.isListType)
        #expect(!title.isRequired)
        #expect(title.isChangeable)
        #expect(!title.isVolatile)
        #expect(!title.isTransient)
        #expect(!title.isDerived)
        #expect(!title.isUnsettable)
    }

    @Test("default value literals")
    func defaults() async throws {
        let model = try await Bookshelf()
        let pages = try model.feature("pages")
        #expect(pages.hasDefault)
        #expect(pages.defaultValueLiteral == "100")
        #expect(try model.feature("shelf").defaultValueLiteral == nil)
        #expect(try !model.feature("shelf").hasDefault)
    }

    @Test("multiplicity decides list types")
    func lists() async throws {
        let model = try await Bookshelf()
        #expect(try model.feature("tags").isListType)
        #expect(try model.feature("tags").upperBound == -1)
        #expect(try model.feature("note").isListType)
        #expect(try model.feature("note").upperBound == 3)
        #expect(try model.feature("books").isListType)
        #expect(try !model.feature("pages").isListType)
        #expect(try model.feature("author").isRequired)
        #expect(try model.feature("author").lowerBound == 1)
    }

    @Test("containment, container and bidirectional shortcuts")
    func containment() async throws {
        let model = try await Bookshelf()
        let books = try model.feature("books")
        let shelf = try model.feature("shelf")
        #expect(books.isReferenceType)
        #expect(books.isContainment)
        #expect(!books.isContainer)
        #expect(books.isBidirectional)
        #expect(shelf.isContainer)
        #expect(!shelf.isContainment)
        #expect(shelf.isBidirectional)
        #expect(books.reverseGenFeature == shelf)
        #expect(shelf.reverseGenFeature == books)
        #expect(try !model.feature("author").isBidirectional)
        #expect(try model.feature("author").reverseGenFeature == nil)
    }

    @Test("flags of references")
    func referenceFlags() async throws {
        let model = try await Bookshelf()
        let author = try model.feature("author")
        #expect(!author.isChangeable)
        #expect(author.isVolatile)
        #expect(author.isTransient)
        #expect(try model.feature("books").isChangeable)
        #expect(try !model.feature("books").isVolatile)
    }

    @Test("attribute flags")
    func attributeFlags() async throws {
        var sample = try await SampleModel()
        let attribute = EAttribute(
            name: "computed", eType: SampleModel.stringType, changeable: false, volatile: true,
            transient: true)
        let eClass = EClass(name: "Calc", eStructuralFeatures: [attribute])
        let ecore = EPackage(name: "c", nsURI: "http://example.org/c", nsPrefix: "c", eClassifiers: [eClass])
        sample.addPackage(ecore)
        let generated = try sample.genClass(eClass)
        let package = try sample.genPackage(ecore, prefix: "C", classes: [generated.genClass])
        _ = try sample.genModel(packages: [package])
        let feature = try #require(sample.context.element(id: generated.features[0].id))
        #expect(!feature.isChangeable)
        #expect(feature.isVolatile)
        #expect(feature.isTransient)
    }

    @Test("a volatile opposite makes the reference volatile")
    func volatileOpposite() async throws {
        var sample = try await SampleModel()
        let firstID = EUUID()
        let secondID = EUUID()
        let stub = EClass(name: "Node")
        let first = EReference(id: firstID, name: "first", eType: stub, opposite: secondID)
        let second = EReference(id: secondID, name: "second", eType: stub, volatile: true, opposite: firstID)
        let node = EClass(name: "Node", eStructuralFeatures: [first, second])
        let ecore = EPackage(name: "n", nsURI: "http://example.org/n", nsPrefix: "n", eClassifiers: [node])
        sample.addPackage(ecore)
        let generated = try sample.genClass(node)
        let package = try sample.genPackage(ecore, prefix: "N", classes: [generated.genClass])
        _ = try sample.genModel(packages: [package])
        let context = sample.context
        #expect(try #require(context.element(id: generated.features[0].id)).isVolatile)
        #expect(try #require(context.element(id: generated.features[1].id)).isVolatile)
    }

    @Test("an unresolved Ecore feature yields neutral answers")
    func unresolved() async throws {
        var sample = try await SampleModel()
        var feature = try sample.make("GenFeature")
        feature.eSet("ecoreFeature", value: "missing.ecore#//A/b")
        sample.add(feature)
        let element = try #require(sample.context.element(id: feature.id))
        #expect(element.ecoreFeature == nil)
        #expect(element.name == "")
        #expect(!element.isReferenceType)
        #expect(!element.isListType)
        #expect(element.upperBound == 1)
        #expect(element.isChangeable)
        #expect(!element.isVolatile)
    }
}
