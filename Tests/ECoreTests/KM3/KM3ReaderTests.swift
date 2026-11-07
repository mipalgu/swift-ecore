//
// KM3ReaderTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@Suite("Reading KM3")
struct KM3ReaderTests {
    let result = KM3Reader.parse(KM3Fixtures.library, sourceName: "library.km3")

    @Test("The library fixture reads without diagnostics")
    func readsWithoutDiagnostics() {
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics)")
        #expect(result.packages.map(\.name) == ["Library", "People"])
    }

    @Test("Directives give namespace URIs and prefixes; other directives are ignored")
    func namespaces() throws {
        let library = try #require(result.packages.package(named: "Library"))
        #expect(library.nsURI == "http://example.org/library")
        #expect(library.nsPrefix == "lib")
        #expect(library.eAnnotations.isEmpty)
        let people = try #require(result.packages.package(named: "People"))
        #expect(people.nsURI == "http://example.org/people")
        #expect(people.nsPrefix == "people")
    }

    @Test("A package without directives has empty namespaces")
    func emptyNamespaces() throws {
        let parsed = KM3Reader.parse("package P { class C {} }")
        let package = try #require(parsed.packages.first)
        #expect(package.nsURI.isEmpty)
        #expect(package.nsPrefix.isEmpty)
    }

    @Test("Classes keep their abstract flag and their supertypes, across packages and forwards")
    func classes() throws {
        let book = try #require(result.packages.eClass(named: "Book"))
        #expect(!book.isAbstract)
        #expect(book.eSuperTypes.map(\.name) == ["NamedElement", "Lendable"])
        let named = try #require(result.packages.eClass(named: "NamedElement"))
        #expect(named.isAbstract)
        #expect(book.eSuperTypes.first?.id == named.id)
        #expect(book.eAllStructuralFeatures.contains { $0.name == "available" })
        let member = try #require(result.packages.eClass(named: "Member"))
        #expect(member.eSuperTypes.map(\.name) == ["Person"])
    }

    @Test("Attributes map multiplicities and flags as KM32EMF does")
    func attributes() throws {
        let book = try #require(result.packages.eClass(named: "Book"))
        let isbn = try #require(book.getEAttribute(name: "isbn"))
        #expect(isbn.lowerBound == 0 && isbn.upperBound == 1)
        #expect(!isbn.ordered && !isbn.unique)
        let pages = try #require(book.getEAttribute(name: "pages"))
        #expect(pages.lowerBound == 1 && pages.upperBound == 1)
        let keywords = try #require(book.getEAttribute(name: "keywords"))
        #expect(keywords.lowerBound == 0 && keywords.upperBound == -1)
        #expect(keywords.ordered && keywords.unique)
        let lendable = try #require(result.packages.eClass(named: "Lendable"))
        let rating = try #require(lendable.getEAttribute(name: "rating"))
        #expect(rating.lowerBound == 2 && rating.upperBound == 5)
    }

    @Test("Primitive types stand for the built-in Ecore data types by default")
    func primitiveTypesMapToEcore() throws {
        let book = try #require(result.packages.eClass(named: "Book"))
        let expected: [(String, EcoreDataType)] = [("isbn", .eString), ("pages", .eInt)]
        for (name, type) in expected {
            let attribute = try #require(book.getEAttribute(name: name))
            #expect(attribute.eType.id == EcorePackage.dataType(type)?.id)
        }
        let lendable = try #require(result.packages.eClass(named: "Lendable"))
        #expect(lendable.getEAttribute(name: "available")?.eType.id == EcorePackage.dataType(.eBoolean)?.id)
        #expect(lendable.getEAttribute(name: "rating")?.eType.id == EcorePackage.dataType(.eDouble)?.id)
        #expect(result.packages.package(named: "PrimitiveTypes") == nil)
    }

    @Test("Declared data types that are not primitive types stay in their package")
    func dataTypes() throws {
        let library = try #require(result.packages.package(named: "Library"))
        let money = try #require(library.getEDataType("Money"))
        #expect(money.instanceClassName == nil)
        let book = try #require(result.packages.eClass(named: "Book"))
        #expect(book.getEAttribute(name: "price")?.eType.id == money.id)
    }

    @Test("Ecore data type names map to themselves")
    func ecoreNames() throws {
        let parsed = KM3Reader.parse(
            "package P { class C { attribute a : EString; attribute b : ELong; } }\n"
                + "package Q { datatype EString; datatype ELong; }")
        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let eClass = try #require(parsed.packages.eClass(named: "C"))
        #expect(eClass.getEAttribute(name: "a")?.eType.id == EcorePackage.dataType(.eString)?.id)
        #expect(eClass.getEAttribute(name: "b")?.eType.id == EcorePackage.dataType(.eLong)?.id)
        #expect(parsed.packages.map(\.name) == ["P"])
    }

    @Test("Every primitive type of the table maps to its Ecore data type")
    func primitiveTable() throws {
        for primitive in KM3PrimitiveTypes.all {
            let text = "package P { class C { attribute a : \(primitive.name); } datatype \(primitive.name); }"
            let parsed = KM3Reader.parse(text)
            #expect(parsed.diagnostics.isEmpty, "\(primitive.name): \(parsed.diagnostics)")
            let attribute = try #require(parsed.packages.eClass(named: "C")?.getEAttribute(name: "a"))
            #expect(attribute.eType.id == EcorePackage.dataType(primitive.ecoreType)?.id, "\(primitive.name)")
            #expect(parsed.packages.first?.getEDataType(primitive.name) == nil)
        }
    }

    @Test("The declared mapping keeps primitive types as plain data types, as KM32EMF does")
    func declaredMapping() throws {
        let parsed = KM3Reader.parse(KM3Fixtures.library, sourceName: nil, options: .declaredDataTypes)
        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let primitives = try #require(parsed.packages.package(named: "PrimitiveTypes"))
        #expect(primitives.eClassifiers.map(\.name) == ["Boolean", "Double", "Integer", "String"])
        #expect(primitives.eClassifiers.allSatisfy { ($0 as? EDataType)?.instanceClassName == nil })
        let book = try #require(parsed.packages.eClass(named: "Book"))
        #expect(book.getEAttribute(name: "isbn")?.eType.id == primitives.getEDataType("String")?.id)
        #expect(parsed.packages.package(named: "Library")?.getEDataType("Money")?.instanceClassName == nil)
    }

    @Test("A package that mixes primitive types with other classifiers is kept")
    func mixedPrimitivePackage() throws {
        let parsed = KM3Reader.parse("package P { datatype String; class C { attribute a : String; } }")
        #expect(parsed.packages.map(\.name) == ["P"])
        #expect(parsed.packages.first?.eClassifiers.map(\.name) == ["C"])
    }

    @Test("References map containment, order, multiplicities and opposites")
    func references() throws {
        let library = try #require(result.packages.eClass(named: "Library"))
        let book = try #require(result.packages.eClass(named: "Book"))
        let books = try #require(library.getEReference(name: "books"))
        #expect(books.containment && books.ordered && books.unique)
        #expect(books.lowerBound == 0 && books.upperBound == -1)
        #expect(books.eType.id == book.id)
        let back = try #require(book.getEReference(name: "library"))
        #expect(books.opposite == back.id)
        #expect(back.opposite == books.id)
        #expect(back.container)
        #expect(!back.containment)
        #expect(back.lowerBound == 1 && back.upperBound == 1)
        let authors = try #require(book.getEReference(name: "authors"))
        #expect(authors.lowerBound == 1 && authors.upperBound == -1 && authors.ordered)
        #expect(authors.eType.name == "Person")
        let members = try #require(library.getEReference(name: "members"))
        #expect(members.containment && !members.ordered && members.opposite == nil)
    }

    @Test("An attribute of a class type becomes a containment reference")
    func classTypedAttribute() throws {
        let library = try #require(result.packages.eClass(named: "Library"))
        let address = try #require(library.getEReference(name: "address"))
        #expect(address.containment)
        #expect(address.eType.name == "Address")
        #expect(library.getEAttribute(name: "address") == nil)
    }

    @Test("Quoted names may be reserved words")
    func quotedNames() throws {
        let book = try #require(result.packages.eClass(named: "Book"))
        let category = try #require(book.getEReference(name: "class"))
        #expect(category.lowerBound == 0 && category.upperBound == 1)
        let genre = try #require(result.packages.package(named: "Library")?.getEEnum("Genre"))
        #expect(genre.literals.map(\.name) == ["fiction", "science", "package"])
    }

    @Test("Quoted names decode escapes")
    func escapes() throws {
        let parsed = KM3Reader.parse(#"package P { class "A\"B\\C\tD\101" {} }"#)
        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(parsed.packages.first?.eClassifiers.first?.name == "A\"B\\C\tDA")
    }

    @Test("Enumerations number their literals from one, as KM32EMF does")
    func enumerations() throws {
        let book = try #require(result.packages.eClass(named: "Book"))
        let genre = try #require(result.packages.package(named: "Library")?.getEEnum("Genre"))
        #expect(genre.literals.map(\.value) == [1, 2, 3])
        #expect(genre.literals.allSatisfy { $0.literal == nil })
        #expect(book.getEAttribute(name: "genre")?.eType.id == genre.id)
    }

    @Test("Operations keep their parameters and result types with Ecore defaults")
    func operations() throws {
        let book = try #require(result.packages.eClass(named: "Book"))
        let lend = try #require(book.getOperation(name: "lend"))
        #expect(lend.eParameters.map(\.name) == ["borrower", "days"])
        #expect(lend.eParameters.first?.eType?.name == "Member")
        #expect(lend.eParameters.last?.eType?.id == EcorePackage.dataType(.eInt)?.id)
        #expect(lend.eType?.id == EcorePackage.dataType(.eBoolean)?.id)
        #expect(lend.lowerBound == 0 && lend.upperBound == 1 && lend.ordered && lend.unique)
        let reset = try #require(book.getOperation(name: "reset"))
        #expect(reset.eType == nil)
        #expect(reset.eParameters.isEmpty)
    }

    @Test("Nested packages become subpackages with their own directives")
    func nestedPackages() throws {
        let parsed = KM3Reader.parse(KM3Fixtures.nested)
        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let outer = try #require(parsed.packages.first)
        #expect(parsed.packages.count == 1)
        let inner = try #require(outer.getSubpackage("Inner"))
        #expect(inner.nsURI == "http://example.org/inner")
        #expect(inner.nsPrefix == "inner")
        let holder = try #require(outer.getEClass("Holder"))
        #expect(holder.getEReference(name: "items")?.eType.id == inner.getEClass("Item")?.id)
    }

    @Test("Directives of later packages come from the comments right before them")
    func directivePlacement() throws {
        let parsed = KM3Reader.parse(
            """
            -- @nsURI http://example.org/a
            package A {
            \t-- @nsURI http://example.org/ignored
            \tclass C {}
            }
            package B {}
            -- @nsPrefix b
            package C {}
            """)
        #expect(parsed.packages.map(\.nsURI) == ["http://example.org/a", "", ""])
        #expect(parsed.packages.map(\.nsPrefix) == ["", "", "b"])
    }

    @Test("Directives accept tabs and extra spaces")
    func directiveSpacing() throws {
        let parsed = KM3Reader.parse("--   @nsURI\thttp://example.org/x  \n--@nsPrefix x\npackage X {}")
        #expect(parsed.packages.first?.nsURI == "http://example.org/x")
        #expect(parsed.packages.first?.nsPrefix == "x")
    }

    @Test("Snapshots of types are linked to complete classes")
    func linkedSnapshots() throws {
        let library = try #require(result.packages.eClass(named: "Library"))
        let books = try #require(library.getEReference(name: "books"))
        let bookSnapshot = try #require(books.eType as? EClass)
        #expect(bookSnapshot.eStructuralFeatures.map(\.name).contains("isbn"))
        #expect(bookSnapshot.eSuperTypes.map(\.name) == ["NamedElement", "Lendable"])
    }

    @Test("CRLF and lone CR line ends are read")
    func lineEnds() {
        let text = KM3Fixtures.library.replacingOccurrences(of: "\n", with: "\r\n")
        let parsed = KM3Reader.parse(text)
        #expect(parsed.diagnostics.isEmpty)
        #expect(KM3Structure.describe(parsed.packages) == KM3Structure.describe(result.packages))
        let classic = KM3Reader.parse(KM3Fixtures.library.replacingOccurrences(of: "\n", with: "\r"))
        #expect(classic.diagnostics.isEmpty)
        #expect(KM3Structure.describe(classic.packages) == KM3Structure.describe(result.packages))
    }

    @Test("An empty text has no packages and no diagnostics")
    func emptyText() {
        let parsed = KM3Reader.parse("")
        #expect(parsed.packages.isEmpty)
        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.tokens.isEmpty)
        #expect(parsed.outline.isEmpty)
        #expect(!parsed.hasErrors)
    }

    @Test("Options default to the Ecore mapping")
    func options() {
        #expect(KM3ReadOptions().primitiveTypes == .ecore)
        #expect(KM3ReadOptions.standard.primitiveTypes == .ecore)
        #expect(KM3ReadOptions.declaredDataTypes.primitiveTypes == .declared)
        #expect(KM3PrimitiveTypeMapping.allCases.count == 2)
    }

    @Test("The primitive type table answers lookups both ways")
    func primitiveLookups() {
        #expect(KM3PrimitiveTypes.ecoreType(forName: "Real") == .eDouble)
        #expect(KM3PrimitiveTypes.ecoreType(forName: "EFloat") == .eFloat)
        #expect(KM3PrimitiveTypes.ecoreType(forName: "Unknown") == nil)
        #expect(KM3PrimitiveTypes.name(for: .eDouble) == "Double")
        #expect(KM3PrimitiveTypes.name(for: .eChar) == "Character")
        #expect(KM3PrimitiveTypes.name(for: .eIntegerObject) == "EIntegerObject")
        #expect(KM3PrimitiveTypes.primitiveType(named: "Date")?.instanceClassName == "java.util.Date")
        #expect(KM3PrimitiveTypes.primitiveType(named: "Nope") == nil)
    }
}
