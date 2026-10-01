//
// NativeReflectionTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Native Metamodel Reflection Tests")
struct NativeReflectionTests {
    private let library = ReflectionFixtures.makeLibraryPackage()

    private func get(_ object: some EObject, _ name: String) throws -> (any EcoreValue)? {
        try ReflectionFixtures.value(of: object, name)
    }

    // MARK: - Metaclasses

    @Test("Native objects report real descriptors")
    func descriptors() throws {
        let book = try #require(library.getEClass("Book"))
        let title = try #require(book.getStructuralFeature(name: "title") as? EAttribute)
        let items = try #require(
            library.getEClass("Library")?.getStructuralFeature(name: "items") as? EReference)
        let genre = try #require(library.getEEnum("Genre"))
        let literal = try #require(genre.literals.first)
        let string = try #require(library.getEDataType("EString"))
        let annotation = try #require(library.eAnnotations.first)

        #expect(library.eClass.id == EcorePackage.metaClass(.ePackage).id)
        #expect(book.eClass.id == EcorePackage.metaClass(.eClass).id)
        #expect(title.eClass.id == EcorePackage.metaClass(.eAttribute).id)
        #expect(items.eClass.id == EcorePackage.metaClass(.eReference).id)
        #expect(genre.eClass.id == EcorePackage.metaClass(.eEnum).id)
        #expect(literal.eClass.id == EcorePackage.metaClass(.eEnumLiteral).id)
        #expect(string.eClass.id == EcorePackage.metaClass(.eDataType).id)
        #expect(annotation.eClass.id == EcorePackage.metaClass(.eAnnotation).id)
        #expect(EFactory(ePackage: library).eClass.name == "EFactory")
        #expect(book.eClass.name == "EClass")
        #expect(EcorePackage.metaClass(.eClass).eClass.name == "EClass")
    }

    // MARK: - EPackage

    @Test("Package features")
    func packageFeatures() throws {
        #expect(try get(library, "name") as? String == "library")
        #expect(try get(library, "nsURI") as? String == "http://example.org/library")
        #expect(try get(library, "nsPrefix") as? String == "lib")
        #expect(
            ReflectionFixtures.names(try get(library, "eClassifiers"))
                == ["Item", "Book", "Library", "Genre", "EString", "EInt"])
        #expect(ReflectionFixtures.names(try get(library, "eSubpackages")) == ["archive"])
        #expect(try get(library, "eSuperPackage") == nil)
        #expect((try get(library, "eAnnotations") as? EcoreValueArray)?.values.count == 1)
        #expect(try get(library, "eFactoryInstance") is EFactory)
        let archive = try #require(library.getSubpackage("archive"))
        #expect(try get(archive, "eSuperPackage") as? EUUID == library.id)
    }

    // MARK: - EClass

    @Test("Class features")
    func classFeatures() throws {
        let book = try #require(library.getEClass("Book"))
        let item = try #require(library.getEClass("Item"))
        #expect(try get(book, "name") as? String == "Book")
        #expect(try get(book, "abstract") as? Bool == false)
        #expect(try get(item, "abstract") as? Bool == true)
        #expect(try get(book, "interface") as? Bool == false)
        #expect(ReflectionFixtures.names(try get(book, "eSuperTypes")) == ["Item"])
        #expect(ReflectionFixtures.names(try get(book, "eAllSuperTypes")) == ["Item"])
        #expect(ReflectionFixtures.names(try get(book, "eStructuralFeatures")) == ["genre", "tags"])
        #expect(
            ReflectionFixtures.names(try get(book, "eAllStructuralFeatures"))
                == ["title", "pages", "genre", "tags"])
        #expect(
            ReflectionFixtures.names(try get(book, "eAllAttributes"))
                == ["title", "pages", "genre", "tags"])
        #expect(ReflectionFixtures.names(try get(book, "eAttributes")) == ["genre", "tags"])
        #expect(ReflectionFixtures.names(try get(book, "eReferences")).isEmpty)
        #expect(ReflectionFixtures.names(try get(book, "eAllReferences")).isEmpty)
        #expect(ReflectionFixtures.names(try get(book, "eAllContainments")).isEmpty)
        #expect(ReflectionFixtures.names(try get(book, "eOperations")).isEmpty)
        #expect(ReflectionFixtures.names(try get(book, "eAllOperations")).isEmpty)
        #expect((try get(book, "eIDAttribute") as? EAttribute)?.name == "title")
        #expect(try get(book, "ePackage") as? EUUID == library.id)
        let libraryClass = try #require(library.getEClass("Library"))
        #expect(ReflectionFixtures.names(try get(libraryClass, "eReferences")) == ["items", "featured"])
        #expect(ReflectionFixtures.names(try get(libraryClass, "eAllContainments")) == ["items"])
    }

    @Test("Class features can be changed")
    func classSetters() throws {
        var book = try #require(library.getEClass("Book"))
        let eClass = EcorePackage.metaClass(.eClass)
        let name = try #require(eClass.getStructuralFeature(name: "name"))
        let abstract = try #require(eClass.getStructuralFeature(name: "abstract"))
        let interface = try #require(eClass.getStructuralFeature(name: "interface"))
        let supers = try #require(eClass.getStructuralFeature(name: "eSuperTypes"))
        let features = try #require(eClass.getStructuralFeature(name: "eStructuralFeatures"))
        let annotations = try #require(eClass.getStructuralFeature(name: "eAnnotations"))

        book.set(name, "Volume")
        book.set(abstract, true)
        book.set(interface, true)
        #expect(book.name == "Volume" && book.isAbstract && book.isInterface)
        #expect(book.isSet(abstract))
        book.unset(abstract)
        #expect(!book.isAbstract && !book.isSet(abstract))

        let note = EClass(name: "Note")
        book.set(supers, EcoreValueArray([note]))
        #expect(book.eSuperTypes.map(\.name) == ["Note"])
        let extra = EAttribute(name: "extra", eType: EDataType(name: "EString"))
        book.set(features, EcoreValueArray([extra]))
        #expect(book.eStructuralFeatures.map(\.name) == ["extra"])
        #expect(extra.eContainerID == nil)
        #expect((book.eStructuralFeatures.first as? EAttribute)?.eContainerID == book.id)
        book.set(annotations, EcoreValueArray([EAnnotation(source: "x")]))
        #expect(book.eAnnotations.map(\.source) == ["x"])
        book.unset(features)
        #expect(book.eStructuralFeatures.isEmpty)
        #expect(!book.isSet(features))
    }

    // MARK: - EAttribute and EReference

    @Test("Attribute features")
    func attributeFeatures() throws {
        let item = try #require(library.getEClass("Item"))
        let title = try #require(item.getStructuralFeature(name: "title") as? EAttribute)
        let tags = try #require(
            library.getEClass("Book")?.getStructuralFeature(name: "tags") as? EAttribute)
        #expect(try get(title, "name") as? String == "title")
        #expect(try get(title, "lowerBound") as? Int == 1)
        #expect(try get(title, "upperBound") as? Int == 1)
        #expect(try get(title, "many") as? Bool == false)
        #expect(try get(title, "required") as? Bool == true)
        #expect(try get(title, "iD") as? Bool == true)
        #expect(try get(title, "ordered") as? Bool == true)
        #expect(try get(title, "unique") as? Bool == true)
        #expect(try get(title, "changeable") as? Bool == true)
        #expect(try get(title, "volatile") as? Bool == false)
        #expect(try get(title, "transient") as? Bool == false)
        #expect(try get(title, "unsettable") as? Bool == false)
        #expect(try get(title, "derived") as? Bool == false)
        #expect(try get(title, "defaultValueLiteral") == nil)
        #expect(try get(title, "defaultValue") == nil)
        #expect(try get(title, "eGenericType") == nil)
        #expect((try get(title, "eType") as? EDataType)?.name == "EString")
        #expect((try get(title, "eAttributeType") as? EDataType)?.name == "EString")
        #expect(try get(title, "eContainingClass") as? EUUID == item.id)
        #expect(try get(tags, "many") as? Bool == true)
        #expect(try get(tags, "upperBound") as? Int == -1)
        let pages = try #require(item.getStructuralFeature(name: "pages") as? EAttribute)
        #expect(try get(pages, "defaultValueLiteral") as? String == "1")
        let genre = try #require(
            library.getEClass("Book")?.getStructuralFeature(name: "genre") as? EAttribute)
        #expect((try get(genre, "eAttributeType") as? EEnum)?.name == "Genre")
    }

    @Test("Attribute features can be changed")
    func attributeSetters() throws {
        var title = EAttribute(name: "title", eType: EDataType(name: "EString"))
        let eAttribute = EcorePackage.metaClass(.eAttribute)
        func feature(_ name: String) throws -> any EStructuralFeature {
            try #require(eAttribute.getStructuralFeature(name: name))
        }
        title.set(try feature("name"), "heading")
        title.set(try feature("lowerBound"), 2)
        title.set(try feature("upperBound"), -1)
        title.set(try feature("changeable"), false)
        title.set(try feature("volatile"), true)
        title.set(try feature("transient"), true)
        title.set(try feature("unsettable"), true)
        title.set(try feature("derived"), true)
        title.set(try feature("ordered"), false)
        title.set(try feature("unique"), false)
        title.set(try feature("iD"), true)
        title.set(try feature("defaultValueLiteral"), "x")
        title.set(try feature("eType"), EDataType(name: "EInt"))
        #expect(title.name == "heading" && title.lowerBound == 2 && title.upperBound == -1)
        #expect(!title.changeable && title.volatile && title.transient)
        #expect(title.unsettable && title.derived && !title.ordered && !title.unique)
        #expect(title.isID && title.defaultValueLiteral == "x" && title.eType.name == "EInt")
        #expect(title.isSet(try feature("lowerBound")))
        title.unset(try feature("lowerBound"))
        title.unset(try feature("changeable"))
        title.unset(try feature("defaultValueLiteral"))
        #expect(title.lowerBound == 0 && title.changeable && title.defaultValueLiteral == nil)
        #expect(!title.isSet(try feature("lowerBound")))
        title.set(try feature("eType"), 5)
        #expect(title.eType.name == "EInt")
        title.set(try feature("eAnnotations"), EcoreValueArray([EAnnotation(source: "s")]))
        #expect(title.eAnnotations.first?.eContainerID == title.id)
    }

    @Test("Reference features")
    func referenceFeatures() throws {
        let libraryClass = try #require(library.getEClass("Library"))
        let items = try #require(libraryClass.getStructuralFeature(name: "items") as? EReference)
        let featured = try #require(
            libraryClass.getStructuralFeature(name: "featured") as? EReference)
        #expect(try get(items, "containment") as? Bool == true)
        #expect(try get(items, "container") as? Bool == false)
        #expect(try get(items, "many") as? Bool == true)
        #expect(try get(items, "resolveProxies") as? Bool == true)
        #expect(try get(featured, "resolveProxies") as? Bool == false)
        #expect((try get(items, "eType") as? EClass)?.name == "Item")
        #expect((try get(items, "eReferenceType") as? EClass)?.name == "Item")
        #expect(try get(items, "eOpposite") == nil)
        #expect(ReflectionFixtures.names(try get(items, "eKeys")).isEmpty)
        #expect(try get(items, "eContainingClass") as? EUUID == libraryClass.id)
    }

    @Test("Reference features can be changed")
    func referenceSetters() throws {
        var reference = EReference(name: "r", eType: EClass(name: "T"))
        let other = EReference(name: "o", eType: EClass(name: "T"))
        let eReference = EcorePackage.metaClass(.eReference)
        func feature(_ name: String) throws -> any EStructuralFeature {
            try #require(eReference.getStructuralFeature(name: name))
        }
        reference.set(try feature("containment"), true)
        reference.set(try feature("resolveProxies"), false)
        reference.set(try feature("eOpposite"), other)
        #expect(reference.containment && !reference.resolveProxies && reference.opposite == other.id)
        reference.set(try feature("eOpposite"), other.id)
        #expect(reference.opposite == other.id)
        reference.set(try feature("eOpposite"), nil)
        #expect(reference.opposite == nil)
        reference.unset(try feature("containment"))
        reference.unset(try feature("resolveProxies"))
        #expect(!reference.containment && reference.resolveProxies)
    }

    // MARK: - Data types, enumerations, literals

    @Test("Enumeration and literal features")
    func enumerationFeatures() throws {
        let genre = try #require(library.getEEnum("Genre"))
        #expect(try get(genre, "name") as? String == "Genre")
        #expect(ReflectionFixtures.names(try get(genre, "eLiterals")) == ["fiction", "history"])
        #expect(try get(genre, "serializable") as? Bool == true)
        #expect(try get(genre, "ePackage") as? EUUID == library.id)
        #expect(ReflectionFixtures.names(try get(genre, "eTypeParameters")).isEmpty)
        let history = try #require(genre.getLiteral(name: "history"))
        let fiction = try #require(genre.getLiteral(name: "fiction"))
        #expect(try get(history, "name") as? String == "history")
        #expect(try get(history, "value") as? Int == 1)
        #expect(try get(history, "literal") as? String == "HISTORY")
        #expect(try get(fiction, "literal") as? String == "fiction")
        #expect(try get(history, "eEnum") as? EUUID == genre.id)
        #expect(try get(history, "instance") == nil)
    }

    @Test("Enumeration and literal features can be changed")
    func enumerationSetters() throws {
        var genre = EEnum(name: "G", literals: [EEnumLiteral(name: "a", value: 0)])
        let eEnum = EcorePackage.metaClass(.eEnum)
        let eLiteral = EcorePackage.metaClass(.eEnumLiteral)
        genre.set(try #require(eEnum.getStructuralFeature(name: "name")), "H")
        #expect(genre.name == "H")
        let literals = try #require(eEnum.getStructuralFeature(name: "eLiterals"))
        genre.set(literals, EcoreValueArray([EEnumLiteral(name: "b", value: 1)]))
        #expect(genre.literals.map(\.name) == ["b"])
        #expect(genre.literals.first?.eContainerID == genre.id)
        genre.set(
            try #require(eEnum.getStructuralFeature(name: "eAnnotations")),
            EcoreValueArray([EAnnotation(source: "z")]))
        #expect(genre.eAnnotations.count == 1)

        var literal = EEnumLiteral(name: "x", value: 0)
        literal.set(try #require(eLiteral.getStructuralFeature(name: "name")), "y")
        literal.set(try #require(eLiteral.getStructuralFeature(name: "value")), 7)
        literal.set(try #require(eLiteral.getStructuralFeature(name: "literal")), "Y")
        #expect(literal.name == "y" && literal.value == 7 && literal.literal == "Y")
        literal.set(
            try #require(eLiteral.getStructuralFeature(name: "eAnnotations")),
            EcoreValueArray([EAnnotation(source: "z")]))
        #expect(literal.eAnnotations.count == 1)
        literal.unset(try #require(eLiteral.getStructuralFeature(name: "value")))
        #expect(literal.value == 0)
    }

    @Test("Data type features")
    func dataTypeFeatures() throws {
        let string = try #require(library.getEDataType("EString"))
        #expect(try get(string, "name") as? String == "EString")
        #expect(try get(string, "serializable") as? Bool == true)
        #expect(try get(string, "instanceClassName") as? String == "Swift.String")
        #expect(try get(string, "ePackage") as? EUUID == library.id)
        #expect(try get(string, "instanceClass") == nil)
        #expect(ReflectionFixtures.names(try get(string, "eTypeParameters")).isEmpty)
        var custom = EDataType(name: "URI")
        let eDataType = EcorePackage.metaClass(.eDataType)
        custom.set(try #require(eDataType.getStructuralFeature(name: "name")), "Link")
        custom.set(try #require(eDataType.getStructuralFeature(name: "serializable")), false)
        custom.set(try #require(eDataType.getStructuralFeature(name: "instanceClassName")), "Foo.Bar")
        custom.set(
            try #require(eDataType.getStructuralFeature(name: "eAnnotations")),
            EcoreValueArray([EAnnotation(source: "q")]))
        #expect(custom.name == "Link" && !custom.serialisable && custom.instanceClassName == "Foo.Bar")
        #expect(custom.eAnnotations.count == 1)
        custom.unset(try #require(eDataType.getStructuralFeature(name: "serializable")))
        #expect(custom.serialisable)
    }

    // MARK: - Annotations

    @Test("Annotation features")
    func annotationFeatures() throws {
        let annotation = try #require(library.eAnnotations.first)
        #expect(try get(annotation, "source") as? String == "doc")
        let details = try #require(try get(annotation, "details") as? EcoreValueArray)
        let entries = details.values.compactMap { $0 as? EStringToStringMapEntry }
        #expect(entries.map(\.key) == ["a", "b"])
        #expect(entries.map(\.value) == ["1", "2"])
        #expect(try get(annotation, "eModelElement") as? EUUID == library.id)
        #expect((try get(annotation, "contents") as? EcoreValueArray)?.values.isEmpty == true)
        #expect((try get(annotation, "references") as? EcoreValueArray)?.values.isEmpty == true)
        #expect(entries[0].eClass.name == "EStringToStringMapEntry")
        #expect(entries[0].eContainerID == annotation.id)
        #expect(try get(entries[0], "key") as? String == "a")
        #expect(try get(entries[0], "value") as? String == "1")
        #expect(annotation.detailEntries.map(\.id) == entries.map(\.id))
    }

    @Test("Annotation features can be changed")
    func annotationSetters() throws {
        var annotation = EAnnotation(source: "doc")
        let eAnnotation = EcorePackage.metaClass(.eAnnotation)
        annotation.set(try #require(eAnnotation.getStructuralFeature(name: "source")), "other")
        let details = try #require(eAnnotation.getStructuralFeature(name: "details"))
        annotation.set(
            details,
            EcoreValueArray([
                EStringToStringMapEntry(key: "k", value: "v"),
                EStringToStringMapEntry(key: "z", value: "y"),
            ]))
        #expect(annotation.source == "other")
        #expect(annotation.details == ["k": "v", "z": "y"])
        #expect(annotation.isSet(details))
        annotation.unset(details)
        #expect(annotation.details.isEmpty)
        #expect(!annotation.isSet(details))

        var entry = EStringToStringMapEntry(key: "a", value: "b")
        let eEntry = EcorePackage.metaClass(.eStringToStringMapEntry)
        let key = try #require(eEntry.getStructuralFeature(name: "key"))
        let value = try #require(eEntry.getStructuralFeature(name: "value"))
        entry.set(key, "c")
        entry.set(value, "d")
        #expect(entry.key == "c" && entry.value == "d")
        #expect(entry.isSet(key) && entry.isSet(value))
        entry.unset(key)
        #expect(entry.key.isEmpty && !entry.isSet(key))
        #expect(entry.eContents.isEmpty)
        #expect(entry.value(try #require(EcorePackage.feature(.name, of: .eNamedElement))) == nil)
        #expect(!entry.isSet(try #require(EcorePackage.feature(.name, of: .eNamedElement))))
    }

    // MARK: - Package changes

    @Test("Package features can be changed")
    func packageSetters() throws {
        var package = EPackage(name: "p")
        let ePackage = EcorePackage.metaClass(.ePackage)
        func feature(_ name: String) throws -> any EStructuralFeature {
            try #require(ePackage.getStructuralFeature(name: name))
        }
        package.set(try feature("name"), "q")
        package.set(try feature("nsURI"), "http://q")
        package.set(try feature("nsPrefix"), "qq")
        package.set(try feature("eClassifiers"), EcoreValueArray([EClass(name: "C"), EDataType(name: "D")]))
        package.set(try feature("eSubpackages"), EcoreValueArray([EPackage(name: "sub")]))
        package.set(try feature("eAnnotations"), EcoreValueArray([EAnnotation(source: "a")]))
        #expect(package.name == "q" && package.nsURI == "http://q" && package.nsPrefix == "qq")
        #expect(package.eClassifiers.map(\.name) == ["C", "D"])
        #expect(package.eSubpackages.first?.eContainerID == package.id)
        #expect(package.eAnnotations.first?.eContainerID == package.id)
        #expect(package.isSet(try feature("nsURI")))
        package.unset(try feature("nsURI"))
        package.unset(try feature("eClassifiers"))
        #expect(package.nsURI.isEmpty && package.eClassifiers.isEmpty)
        #expect(!package.isSet(try feature("eClassifiers")))
    }

    @Test("Features outside the Ecore metamodel use generic storage")
    func genericStorage() throws {
        var book = try #require(library.getEClass("Book"))
        let custom = EAttribute(name: "custom", eType: EDataType(name: "EString"))
        #expect(book.value(custom) == nil)
        #expect(!book.isSet(custom))
        book.set(custom, "value")
        #expect(book.value(custom) as? String == "value")
        #expect(book.isSet(custom))
        book.unset(custom)
        #expect(book.value(custom) == nil)
    }

    // MARK: - Parsed fixtures

    @Test("Parsed organisation metamodel reflects like a hand-built one")
    func parsedOrganisation() async throws {
        let package = try await ReflectionFixtures.loadPackage("xmi/organisation.ecore")
        #expect(ReflectionFixtures.names(try get(package, "eClassifiers")) == ["Person", "Team", "Organisation"])
        let team = try #require(package.getEClass("Team"))
        #expect(ReflectionFixtures.names(try get(team, "eStructuralFeatures")) == ["name", "members", "leader"])
        let members = try #require(team.getStructuralFeature(name: "members") as? EReference)
        #expect(try get(members, "containment") as? Bool == true)
        #expect(try get(members, "upperBound") as? Int == -1)
        #expect((try get(members, "eType") as? EClass)?.name == "Person")
        let leader = try #require(team.getStructuralFeature(name: "leader") as? EReference)
        #expect(try get(leader, "required") as? Bool == true)
        #expect(try get(leader, "containment") as? Bool == false)
        #expect(try get(team, "ePackage") as? EUUID == package.id)
    }

    @Test("Parsed animals metamodel exposes enumerations")
    func parsedAnimals() async throws {
        let package = try await ReflectionFixtures.loadPackage("xmi/animals.ecore")
        let species = try #require(package.getEEnum("Species"))
        #expect(ReflectionFixtures.names(try get(species, "eLiterals")) == ["cat", "dog", "bird"])
        let animal = try #require(package.getEClass("Animal"))
        let speciesAttribute = try #require(animal.getStructuralFeature(name: "species") as? EAttribute)
        #expect(try get(speciesAttribute, "defaultValueLiteral") as? String == "cat")
        let name = try #require(animal.getStructuralFeature(name: "name") as? EAttribute)
        #expect(try get(name, "defaultValueLiteral") as? String == "Unnamed")
    }

    @Test("Parsed families metamodel exposes opposites")
    func parsedFamilies() async throws {
        let package = try await ReflectionFixtures.loadPackage("metamodels/Families.ecore")
        let family = try #require(package.getEClass("Family"))
        let member = try #require(package.getEClass("Member"))
        let father = try #require(family.getStructuralFeature(name: "father") as? EReference)
        let familyFather = try #require(member.getStructuralFeature(name: "familyFather") as? EReference)
        #expect(try get(father, "eOpposite") as? EUUID == familyFather.id)
        #expect(try get(familyFather, "eOpposite") as? EUUID == father.id)
        #expect(try get(father, "containment") as? Bool == true)
        #expect(try get(father, "lowerBound") as? Int == 1)
        #expect(try get(father, "ordered") as? Bool == false)
        #expect(try get(father, "unique") as? Bool == true)
        let lastName = try #require(family.getStructuralFeature(name: "lastName") as? EAttribute)
        #expect(try get(lastName, "ordered") as? Bool == false)
        #expect(try get(lastName, "unique") as? Bool == false)
        #expect(try get(lastName, "unsettable") as? Bool == false)
        #expect(try get(lastName, "derived") as? Bool == false)
    }

    @Test("Parsed feature flags are read from the document")
    func parsedFlags() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flags-\(UUID().uuidString).ecore")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="f" nsURI="http://f" nsPrefix="f">
              <eClassifiers xsi:type="ecore:EClass" name="C">
                <eStructuralFeatures xsi:type="ecore:EAttribute" name="a" unsettable="true"
                    derived="true" ordered="false" unique="false"
                    eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
                <eStructuralFeatures xsi:type="ecore:EReference" name="r" unsettable="true"
                    derived="true" ordered="false" unique="false" changeable="false"
                    volatile="true" transient="true" resolveProxies="false" eType="#//C"/>
              </eClassifiers>
            </ecore:EPackage>
            """
        try text.write(to: url, atomically: true, encoding: .utf8)
        let package = try await EPackage(url: url)
        let c = try #require(package.getEClass("C"))
        let a = try #require(c.getStructuralFeature(name: "a") as? EAttribute)
        let r = try #require(c.getStructuralFeature(name: "r") as? EReference)
        #expect(a.unsettable && a.derived && !a.ordered && !a.unique)
        #expect(r.unsettable && r.derived && !r.ordered && !r.unique)
        #expect(!r.changeable && r.volatile && r.transient && !r.resolveProxies)
        #expect(try get(r, "derived") as? Bool == true)
        #expect(try get(r, "unsettable") as? Bool == true)
        #expect(try get(a, "unique") as? Bool == false)
    }
}
