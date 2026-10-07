//
// EcoreLoaderFidelityTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Locates the fixtures of the loader fidelity tests.
enum FidelityFixtures {
    /// The URL of a document in the `fidelity` fixture directory.
    static func url(_ name: String) throws -> URL {
        try ReflectionFixtures.resourcesURL().appendingPathComponent("fidelity")
            .appendingPathComponent(name)
    }

    /// Writes an Ecore document to a temporary directory.
    ///
    /// - Parameters:
    ///   - body: The content of the `ecore:EPackage` element.
    ///   - attributes: Extra attributes of the package element.
    /// - Returns: The file URL; the caller removes its directory.
    static func writeDocument(_ body: String, name: String = "temporary.ecore") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="temporary"
                nsURI="http://example.org/temporary" nsPrefix="tmp">
            \(body)
            </ecore:EPackage>
            """
        try text.write(to: url, atomically: testWritesAtomically, encoding: .utf8)
        return url
    }

    /// The package of a native load of a fixture.
    static func package(_ name: String = "library-full.ecore") async throws -> EPackage {
        try await EPackage(url: try url(name))
    }
}

extension EPackage {
    /// Finds a class of this package or of any nested package by name.
    func deepClass(_ name: String) -> EClass? {
        if let found = getEClass(name) { return found }
        for subpackage in eSubpackages {
            if let found = subpackage.deepClass(name) { return found }
        }
        return nil
    }
}

extension EClass {
    /// Finds a declared attribute by name.
    func attribute(_ name: String) -> EAttribute? { eAttributes.first { $0.name == name } }

    /// Finds a declared reference by name.
    func reference(_ name: String) -> EReference? { eReferences.first { $0.name == name } }
}

@Suite("Native Ecore Loader Fidelity Tests")
struct NativeLoaderFidelityTests {
    private let ecoreEString = EcorePackage.dataType(.eString)

    // MARK: Supertypes

    @Test("multi-valued eSuperTypes keep all supertypes in order")
    func multipleSupertypes() async throws {
        let package = try await FidelityFixtures.package()
        let book = try #require(package.getEClass("Book"))
        #expect(book.eSuperTypes.map(\.name) == ["Named", "Lendable"])
        #expect(book.eAllSuperTypes.map(\.name) == ["Named", "Lendable"])
        #expect(
            book.eAllStructuralFeatures.map(\.name)
                == [
                    "name", "loanDays", "onLoan", "pages", "category", "isbn", "location", "shelf",
                    "tags", "subtitle", "author", "library", "related", "metaclass",
                ])
        #expect(book.eAllOperations.map(\.name) == ["borrow", "giveBack", "holder"])
        #expect(try #require(package.getEClass("LoanFailure")).eSuperTypes.map(\.name) == ["Named"])
    }

    @Test("a single supertype and class flags are kept")
    func singleSupertypeAndFlags() async throws {
        let package = try await FidelityFixtures.package()
        let writer = try #require(package.getEClass("Writer"))
        #expect(writer.eSuperTypes.map(\.name) == ["Named"])
        #expect(try #require(package.getEClass("Named")).isAbstract)
        let lendable = try #require(package.getEClass("Lendable"))
        #expect(lendable.isAbstract && lendable.isInterface)
        #expect(!writer.isAbstract && !writer.isInterface)
    }

    @Test("supertypes are the complete classes")
    func supertypeSnapshots() async throws {
        let package = try await FidelityFixtures.package()
        let book = try #require(package.getEClass("Book"))
        let named = try #require(book.eSuperTypes.first)
        #expect(named.id == (try #require(package.getEClass("Named"))).id)
        #expect(named.eStructuralFeatures.map(\.name) == ["name"])
        let lendable = try #require(book.eSuperTypes.last)
        #expect(lendable.eOperations.count == 3)
    }

    // MARK: Types

    @Test("attribute types resolve to local enumerations and data types")
    func localTypes() async throws {
        let package = try await FidelityFixtures.package()
        let book = try #require(package.getEClass("Book"))
        let category = try #require(book.attribute("category"))
        let enumeration = try #require(category.eType as? EEnum)
        #expect(enumeration.id == (try #require(package.getEEnum("BookCategory"))).id)
        #expect(enumeration.literals.map(\.name) == ["Fiction", "Mystery", "Biography"])
        #expect(enumeration.literals.map(\.value) == [0, 1, 2])
        #expect(enumeration.literals[1].literal == "MYSTERY")

        let isbn = try #require(book.attribute("isbn")?.eType as? EDataType)
        #expect(isbn.name == "ISBN")
        #expect(isbn.instanceClassName == "java.lang.String")
        #expect(isbn.id == (try #require(package.getEDataType("ISBN"))).id)

        let path = try #require(book.attribute("location")?.eType as? EDataType)
        #expect(path.name == "Path")
        #expect(path.instanceClassName == "java.nio.file.Path")
        #expect(!path.serialisable)
        #expect(try #require(package.getEDataType("ISBN")).serialisable)
    }

    @Test("attribute types resolve into nested packages")
    func nestedPackageTypes() async throws {
        let package = try await FidelityFixtures.package()
        let book = try #require(package.getEClass("Book"))
        let shelf = try #require(book.attribute("shelf")?.eType as? EEnum)
        let catalogue = try #require(package.getSubpackage("catalogue"))
        #expect(shelf.id == (try #require(catalogue.getEEnum("Shelf"))).id)
        let section = try #require(catalogue.getEClass("Section"))
        #expect(section.attribute("shelf")?.eType.id == shelf.id)
        let sections = try #require(package.getEClass("Library")?.reference("sections"))
        #expect(sections.eType.id == section.id)
    }

    @Test("built-in data types resolve to the Ecore package")
    func builtInTypes() async throws {
        let package = try await FidelityFixtures.package()
        let named = try #require(package.getEClass("Named"))
        #expect(named.attribute("name")?.eType.id == ecoreEString?.id)
        let lendable = try #require(package.getEClass("Lendable"))
        #expect(lendable.attribute("loanDays")?.eType.id == EcorePackage.dataType(.eInt)?.id)
        #expect(lendable.attribute("onLoan")?.eType.id == EcorePackage.dataType(.eBoolean)?.id)
    }

    @Test("Ecore metaclasses resolve to the real descriptors")
    func metaclassTypes() async throws {
        let package = try await FidelityFixtures.package()
        let book = try #require(package.getEClass("Book"))
        let metaclass = try #require(book.reference("metaclass")?.eType as? EClass)
        #expect(metaclass.id == EcorePackage.metaClass(.eClass).id)
        #expect(metaclass.eAllStructuralFeatures.map(\.name).contains("eStructuralFeatures"))
        let writer = try #require(package.getEClass("Writer"))
        #expect(writer.reference("feature")?.eType.id == EcorePackage.metaClass(.eStructuralFeature).id)
        #expect(writer.reference("package")?.eType.id == EcorePackage.metaClass(.ePackage).id)
        #expect(
            EcorePackage.isMetaClass(try #require(writer.reference("package")?.eType)))
        #expect(package.getClassifier("EClass") == nil)
    }

    @Test("reference types are complete classes")
    func referenceTypes() async throws {
        let package = try await FidelityFixtures.package()
        let writer = try #require(package.getEClass("Writer"))
        let books = try #require(writer.reference("books"))
        let target = try #require(books.eType as? EClass)
        #expect(target.id == (try #require(package.getEClass("Book"))).id)
        #expect(target.eSuperTypes.map(\.name) == ["Named", "Lendable"])
        #expect(target.eAllStructuralFeatures.count == 14)
        let author = try #require(target.reference("author"))
        #expect((author.eType as? EClass)?.name == "Writer")
        #expect(author.opposite == books.id)
        #expect(books.opposite == author.id)
    }

    // MARK: Flags

    @Test("attribute flags, bounds, and defaults are kept")
    func attributeFlags() async throws {
        let package = try await FidelityFixtures.package()
        let named = try #require(package.getEClass("Named"))
        let name = try #require(named.attribute("name"))
        #expect(name.isID && name.lowerBound == 1 && name.upperBound == 1 && name.isRequired)
        #expect(name.ordered && name.unique && name.changeable)
        #expect(!name.volatile && !name.transient && !name.unsettable && !name.derived)
        #expect(name.defaultValueLiteral == nil)

        let lendable = try #require(package.getEClass("Lendable"))
        #expect(lendable.attribute("loanDays")?.defaultValueLiteral == "14")
        let onLoan = try #require(lendable.attribute("onLoan"))
        #expect(!onLoan.changeable && onLoan.volatile && onLoan.transient && onLoan.derived)

        let book = try #require(package.getEClass("Book"))
        #expect(book.attribute("pages")?.defaultValueLiteral == "100")
        #expect(book.attribute("category")?.defaultValueLiteral == "Mystery")
        let tags = try #require(book.attribute("tags"))
        #expect(tags.upperBound == -1 && tags.isMany && !tags.unique && tags.ordered)
        #expect(try #require(book.attribute("subtitle")).unsettable)
    }

    @Test("reference flags, bounds, and container are kept")
    func referenceFlags() async throws {
        let package = try await FidelityFixtures.package()
        let book = try #require(package.getEClass("Book"))
        let author = try #require(book.reference("author"))
        #expect(author.lowerBound == 1 && author.isRequired && !author.containment && !author.container)
        let library = try #require(book.reference("library"))
        #expect(library.container && !library.containment)
        let related = try #require(book.reference("related"))
        #expect(related.isMany && !related.ordered && !related.unique && !related.resolveProxies)
        #expect(related.opposite == nil && !related.container)
        let books = try #require(package.getEClass("Library")?.reference("books"))
        #expect(books.containment && books.isMany && !books.container)
        #expect(books.resolveProxies)
        #expect(books.opposite == library.id && library.opposite == books.id)
    }

    @Test("container reads through reflection")
    func reflectiveContainer() async throws {
        let package = try await FidelityFixtures.package()
        let library = try #require(package.getEClass("Book")?.reference("library"))
        #expect(try ReflectionFixtures.value(of: library, "container") as? Bool == true)
        let books = try #require(package.getEClass("Library")?.reference("books"))
        #expect(try ReflectionFixtures.value(of: books, "container") as? Bool == false)
    }

    @Test("instance class names of classes are kept")
    func classInstanceClassName() async throws {
        let package = try await FidelityFixtures.package()
        let entry = try #require(package.getEClass("StringToBookEntry"))
        #expect(entry.instanceClassName == "java.util.Map$Entry")
        #expect(try ReflectionFixtures.value(of: entry, "instanceClassName") as? String == "java.util.Map$Entry")
        #expect(try #require(package.getEClass("Book")).instanceClassName == nil)
    }

    // MARK: Operations

    @Test("operations keep types, bounds, parameters, and exceptions")
    func operations() async throws {
        let package = try await FidelityFixtures.package()
        let lendable = try #require(package.getEClass("Lendable"))
        #expect(lendable.eOperations.map(\.name) == ["borrow", "giveBack", "holder"])
        let borrow = lendable.eOperations[0]
        #expect(borrow.eType?.id == EcorePackage.dataType(.eBoolean)?.id)
        #expect(borrow.lowerBound == 1 && borrow.isRequired)
        #expect(borrow.eParameters.map(\.name) == ["days", "notes"])
        let days = borrow.eParameters[0]
        #expect(days.eType?.id == EcorePackage.dataType(.eInt)?.id && days.lowerBound == 1)
        let notes = borrow.eParameters[1]
        #expect(notes.isMany && !notes.ordered && !notes.unique)
        #expect(borrow.eExceptions.map(\.name) == ["LoanFailure"])
        #expect(borrow.eExceptions[0].id == (try #require(package.getEClass("LoanFailure"))).id)
        #expect(lendable.eOperations[1].eType == nil)
        #expect(lendable.eOperations[2].eType?.id == (try #require(package.getEClass("Writer"))).id)
        #expect(borrow.eContainerID == lendable.id)
        #expect(days.eContainerID == borrow.id)
    }

    // MARK: Subpackages

    @Test("subpackages are parsed into native packages")
    func subpackages() async throws {
        let package = try await FidelityFixtures.package()
        #expect(package.eSubpackages.map(\.name) == ["catalogue"])
        let catalogue = try #require(package.getSubpackage("catalogue"))
        #expect(catalogue.nsURI == "http://example.org/fidelity/library/catalogue")
        #expect(catalogue.nsPrefix == "cat")
        #expect(catalogue.eClassifiers.map(\.name) == ["Shelf", "Section"])
        #expect(catalogue.eContainerID == package.id)
        let archive = try #require(catalogue.getSubpackage("archive"))
        #expect(archive.getEClass("Box") != nil)
        #expect(archive.eContainerID == catalogue.id)
        let section = try #require(catalogue.getEClass("Section"))
        #expect(section.eSuperTypes.map(\.name) == ["Named"])
        let featured = try #require(section.reference("featured"))
        #expect(featured.eType.id == (try #require(package.getEClass("Book"))).id)
        let sections = try #require(archive.getEClass("Box")?.reference("sections"))
        #expect(sections.eType.id == section.id)
        #expect(try ReflectionFixtures.value(of: archive, "eSuperPackage") as? EUUID == catalogue.id)
    }

    // MARK: Resources

    @Test("a native resource enumerates and navigates every element")
    func resourceNavigation() async throws {
        let set = ResourceSet()
        let uri = try FidelityFixtures.url("library-full.ecore").absoluteString
        let resource = try await set.loadEcoreResource(uri: uri)
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        let classes = await resource.getAllInstancesOf(EcorePackage.metaClass(.eClass))
        #expect(
            classes.compactMap { ($0 as? EClass)?.name }
                == [
                    "Named", "Lendable", "Book", "Writer", "Library", "StringToBookEntry",
                    "LoanFailure", "Section", "Box",
                ])
        let operations = await resource.getAllInstancesOf(EcorePackage.metaClass(.eOperation))
        #expect(operations.count == 3)
        let parameters = await resource.getAllInstancesOf(EcorePackage.metaClass(.eParameter))
        #expect(parameters.count == 2)
        let packages = await resource.getAllInstancesOf(EcorePackage.metaClass(.ePackage))
        #expect(packages.compactMap { ($0 as? EPackage)?.name } == ["library", "catalogue", "archive"])
        let navigator = FragmentNavigator(resource: resource)
        let days = try #require(await navigator.resolve("//Lendable/borrow/days") as? EParameter)
        #expect(days.name == "days")
        #expect(try #require(await navigator.resolve("//catalogue/archive/Box")) is EClass)
        #expect(try #require(await navigator.resolve("//catalogue/Shelf/Bottom")) is EEnumLiteral)
        let box = try #require(package.getSubpackage("catalogue")?.getSubpackage("archive")?.getEClass("Box"))
        #expect(await navigator.fragment(for: box.id) == "//catalogue/archive/Box")
    }

    @Test("registered metamodels are available by namespace")
    func metamodelRegistration() async throws {
        let set = ResourceSet()
        _ = try await set.loadEcoreResource(uri: try FidelityFixtures.url("library-full.ecore").absoluteString)
        let registered = await set.getMetamodel(uri: "http://example.org/fidelity/library")
        #expect(registered?.name == "library")
    }

    // MARK: Cross-document types

    @Test("types and supertypes of other documents resolve natively")
    func crossDocument() async throws {
        let package = try await FidelityFixtures.package("consumer.ecore")
        let widget = try #require(package.getEClass("Widget"))
        #expect(widget.eSuperTypes.map(\.name) == ["Audited"])
        #expect(widget.eAllStructuralFeatures.map(\.name) == ["revision", "colour", "uuid", "stamp", "parent"])
        let colour = try #require(widget.attribute("colour")?.eType as? EEnum)
        #expect(colour.name == "Colour" && colour.literals.map(\.name) == ["Red", "Green"])
        let uuid = try #require(widget.attribute("uuid")?.eType as? EDataType)
        #expect(uuid.name == "Identifier" && uuid.instanceClassName == "java.util.UUID")
        let stamp = try #require(widget.reference("stamp")?.eType as? EClass)
        #expect(stamp.name == "Stamp")
        #expect(widget.reference("parent")?.eType.id == widget.id)
    }

    @Test("documents of a resource set share their loaded packages")
    func crossDocumentSharing() async throws {
        let set = ResourceSet()
        let sharedURI = try FidelityFixtures.url("shared.ecore").absoluteString
        let consumerURI = try FidelityFixtures.url("consumer.ecore").absoluteString
        let consumer = try await set.loadEcoreResource(uri: consumerURI)
        let sharedResource = try #require(await set.getResource(uri: sharedURI))
        let shared = try #require(await sharedResource.getRootObjects().first as? EPackage)
        let widget = try #require(
            (await consumer.getRootObjects().first as? EPackage)?.getEClass("Widget"))
        #expect(widget.eSuperTypes.first?.id == shared.getEClass("Audited")?.id)
        #expect(await set.getMetamodel(uri: "http://example.org/fidelity/shared") != nil)
    }

    @Test("a missing document leaves the type at its default")
    func unresolvedCrossDocument() async throws {
        let url = try FidelityFixtures.writeDocument(
            """
              <eClassifiers xsi:type="ecore:EClass" name="Lost" eSuperTypes="nowhere.ecore#//Gone">
                <eStructuralFeatures xsi:type="ecore:EAttribute" name="a" eType="ecore:EDataType nowhere.ecore#//Gone"/>
                <eStructuralFeatures xsi:type="ecore:EReference" name="r" eType="ecore:EClass nowhere.ecore#//Gone"/>
              </eClassifiers>
            """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let package = try await EPackage(url: url)
        let lost = try #require(package.getEClass("Lost"))
        #expect(lost.eSuperTypes.isEmpty)
        #expect(lost.attribute("a")?.eType.id == ecoreEString?.id)
        #expect(lost.reference("r")?.eType.id == EcorePackage.metaClass(.eObject).id)
    }

    @Test("documents that refer to each other do not loop")
    func cyclicDocuments() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func document(_ name: String, other: String) -> String {
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="\(name)"
                nsURI="http://example.org/\(name)" nsPrefix="\(name)">
              <eClassifiers xsi:type="ecore:EClass" name="Own">
                <eStructuralFeatures xsi:type="ecore:EReference" name="peer" eType="ecore:EClass \(other).ecore#//Own"/>
              </eClassifiers>
            </ecore:EPackage>
            """
        }
        try document("ping", other: "pong").write(
            to: directory.appendingPathComponent("ping.ecore"), atomically: testWritesAtomically, encoding: .utf8)
        try document("pong", other: "ping").write(
            to: directory.appendingPathComponent("pong.ecore"), atomically: testWritesAtomically, encoding: .utf8)
        let package = try await EPackage(url: directory.appendingPathComponent("ping.ecore"))
        let peer = try #require(package.getEClass("Own")?.reference("peer"))
        #expect((peer.eType as? EClass)?.name == "Own")
    }

    // MARK: Generic types

    @Test("eGenericType children supply the type")
    func genericTypes() async throws {
        let url = try FidelityFixtures.writeDocument(
            """
              <eClassifiers xsi:type="ecore:EClass" name="Base"/>
              <eClassifiers xsi:type="ecore:EClass" name="Other"/>
              <eClassifiers xsi:type="ecore:EClass" name="Holder">
                <eGenericSuperTypes eClassifier="#//Base"/>
                <eStructuralFeatures xsi:type="ecore:EReference" name="items" upperBound="-1">
                  <eGenericType eClassifier="#//Other">
                    <eTypeArguments eClassifier="#//Base"/>
                  </eGenericType>
                </eStructuralFeatures>
                <eStructuralFeatures xsi:type="ecore:EAttribute" name="label">
                  <eGenericType eClassifier="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EInt"/>
                </eStructuralFeatures>
                <eOperations name="make">
                  <eGenericType eClassifier="#//Other"/>
                  <eParameters name="seed">
                    <eGenericType eClassifier="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EInt"/>
                  </eParameters>
                </eOperations>
              </eClassifiers>
            """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let package = try await EPackage(url: url)
        let holder = try #require(package.getEClass("Holder"))
        #expect(holder.eSuperTypes.map(\.name) == ["Base"])
        #expect(holder.reference("items")?.eType.id == package.getEClass("Other")?.id)
        #expect(holder.reference("items")?.isMany == true)
        #expect(holder.attribute("label")?.eType.id == EcorePackage.dataType(.eInt)?.id)
        let make = try #require(holder.eOperations.first)
        #expect(make.eType?.id == package.getEClass("Other")?.id)
        #expect(make.eParameters.first?.eType?.id == EcorePackage.dataType(.eInt)?.id)
    }

    // MARK: Loading through the other entry points

    @Test("a package loaded through a resource set equals one loaded directly")
    func entryPointsAgree() async throws {
        let direct = try await FidelityFixtures.package()
        let set = ResourceSet()
        let resource = try await set.loadEcoreResource(
            uri: try FidelityFixtures.url("library-full.ecore").absoluteString)
        let viaSet = try #require(await resource.getRootObjects().first as? EPackage)
        #expect(direct.eClassifiers.map(\.name) == viaSet.eClassifiers.map(\.name))
        #expect(
            direct.getEClass("Book")?.eAllStructuralFeatures.map(\.name)
                == viaSet.getEClass("Book")?.eAllStructuralFeatures.map(\.name))
    }
}
