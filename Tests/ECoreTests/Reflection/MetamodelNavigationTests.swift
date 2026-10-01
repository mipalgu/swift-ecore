//
// MetamodelNavigationTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Metamodel Navigation Tests")
struct MetamodelNavigationTests {
    private let library = ReflectionFixtures.makeLibraryPackage()

    private func makeEngine(_ package: EPackage) async -> (ECoreExecutionEngine, Resource) {
        let resource = Resource(uri: "test://metamodel/\(package.name)")
        await resource.add(package)
        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(resource, alias: "MM")
        return (engine, resource)
    }

    private func names(_ value: (any EcoreValue)?) -> [String] {
        ReflectionFixtures.names(value)
    }

    // MARK: - Engine navigation by feature name

    @Test("Navigate package collections by name")
    func navigatePackage() async throws {
        let (engine, _) = await makeEngine(library)
        #expect(try await engine.navigate(from: library, property: "name") as? String == "library")
        #expect(try await engine.navigate(from: library, property: "nsURI") as? String == "http://example.org/library")
        #expect(
            names(try await engine.navigate(from: library, property: "eClassifiers"))
                == ["Item", "Book", "Library", "Genre", "EString", "EInt"])
        #expect(names(try await engine.navigate(from: library, property: "eSubpackages")) == ["archive"])
    }

    @Test("Navigate class features by name")
    func navigateClass() async throws {
        let (engine, _) = await makeEngine(library)
        let book = try #require(library.getEClass("Book"))
        #expect(
            names(try await engine.navigate(from: book, property: "eAllStructuralFeatures"))
                == ["title", "pages", "genre", "tags"])
        #expect(names(try await engine.navigate(from: book, property: "eStructuralFeatures")) == ["genre", "tags"])
        #expect(names(try await engine.navigate(from: book, property: "eAllAttributes")).count == 4)
        #expect(names(try await engine.navigate(from: book, property: "eSuperTypes")) == ["Item"])
        #expect(names(try await engine.navigate(from: book, property: "eAllSuperTypes")) == ["Item"])
        #expect(try await engine.navigate(from: book, property: "abstract") as? Bool == false)
        let idAttribute = try await engine.navigate(from: book, property: "eIDAttribute") as? EAttribute
        #expect(idAttribute?.name == "title")
    }

    @Test("Navigate feature properties by name")
    func navigateFeatures() async throws {
        let (engine, _) = await makeEngine(library)
        let libraryClass = try #require(library.getEClass("Library"))
        let items = try #require(libraryClass.getStructuralFeature(name: "items") as? EReference)
        #expect(try await engine.navigate(from: items, property: "containment") as? Bool == true)
        #expect(try await engine.navigate(from: items, property: "upperBound") as? Int == -1)
        #expect(try await engine.navigate(from: items, property: "many") as? Bool == true)
        let type = try await engine.navigate(from: items, property: "eType") as? EClass
        #expect(type?.name == "Item")
        let referenceType = try await engine.navigate(from: items, property: "eReferenceType") as? EClass
        #expect(referenceType?.name == "Item")
        let book = try #require(library.getEClass("Book"))
        let title = try #require(book.getStructuralFeature(name: "title") as? EAttribute)
        #expect(try await engine.navigate(from: title, property: "iD") as? Bool == true)
        #expect(try await engine.navigate(from: title, property: "required") as? Bool == true)
        let genre = try #require(book.getStructuralFeature(name: "genre") as? EAttribute)
        let genreType = try await engine.navigate(from: genre, property: "eType") as? EEnum
        #expect(genreType?.name == "Genre")
    }

    @Test("Navigate through a stand-in type reaches the complete class")
    func navigateThroughStandIn() async throws {
        let (engine, _) = await makeEngine(library)
        let libraryClass = try #require(library.getEClass("Library"))
        let items = try #require(libraryClass.getStructuralFeature(name: "items") as? EReference)
        let target = try #require(try await engine.navigate(from: items, property: "eType") as? EClass)
        let features = try await engine.navigate(from: target, property: "eStructuralFeatures")
        #expect(names(features) == ["title", "pages"])
    }

    @Test("Navigate enumerations and annotations")
    func navigateEnumerationsAndAnnotations() async throws {
        let (engine, _) = await makeEngine(library)
        let genre = try #require(library.getEEnum("Genre"))
        let literals = try #require(
            try await engine.navigate(from: genre, property: "eLiterals") as? EcoreValueArray)
        #expect(names(literals) == ["fiction", "history"])
        let history = try #require(literals.values.last as? EEnumLiteral)
        #expect(try await engine.navigate(from: history, property: "value") as? Int == 1)
        #expect(try await engine.navigate(from: history, property: "literal") as? String == "HISTORY")
        let annotations = try #require(
            try await engine.navigate(from: library, property: "eAnnotations") as? EcoreValueArray)
        let annotation = try #require(annotations.values.first as? EAnnotation)
        #expect(try await engine.navigate(from: annotation, property: "source") as? String == "doc")
        let details = try #require(
            try await engine.navigate(from: annotation, property: "details") as? EcoreValueArray)
        let entry = try #require(details.values.first as? EStringToStringMapEntry)
        #expect(try await engine.navigate(from: entry, property: "key") as? String == "a")
        #expect(try await engine.navigate(from: entry, property: "value") as? String == "1")
    }

    @Test("Unknown metamodel properties are rejected")
    func unknownProperty() async throws {
        let (engine, _) = await makeEngine(library)
        await #expect(throws: ECoreExecutionError.self) {
            _ = try await engine.navigate(from: library, property: "noSuchFeature")
        }
    }

    // MARK: - Container navigation

    @Test("Container features resolve to the containing object")
    func containerFeatures() async throws {
        let (engine, _) = await makeEngine(library)
        let book = try #require(library.getEClass("Book"))
        let genre = try #require(book.getStructuralFeature(name: "genre") as? EAttribute)
        let container = try await engine.navigate(from: genre, property: "eContainingClass") as? EClass
        #expect(container?.name == "Book")
        let owningPackage = try await engine.navigate(from: book, property: "ePackage") as? EPackage
        #expect(owningPackage?.id == library.id)
        let literal = try #require(library.getEEnum("Genre")?.literals.first)
        let owner = try await engine.navigate(from: literal, property: "eEnum") as? EEnum
        #expect(owner?.name == "Genre")
        let archive = try #require(library.getSubpackage("archive"))
        let parent = try await engine.navigate(from: archive, property: "eSuperPackage") as? EPackage
        #expect(parent?.name == "library")
        let annotation = try #require(library.eAnnotations.first)
        let element = try await engine.navigate(from: annotation, property: "eModelElement") as? EPackage
        #expect(element?.id == library.id)
        let box = try #require(archive.getEClass("Box"))
        let boxPackage = try await engine.navigate(from: box, property: "ePackage") as? EPackage
        #expect(boxPackage?.name == "archive")
    }

    @Test("eContainer and eContainingFeature pseudo-properties")
    func containerPseudoProperties() async throws {
        let (engine, _) = await makeEngine(library)
        let book = try #require(library.getEClass("Book"))
        let genre = try #require(book.getStructuralFeature(name: "genre") as? EAttribute)
        let container = try await engine.navigate(from: genre, property: "eContainer") as? EClass
        #expect(container?.id == book.id)
        let feature = try await engine.navigate(from: genre, property: "eContainingFeature") as? EReference
        #expect(feature?.name == "eStructuralFeatures")
        let packageContainer = try await engine.navigate(from: book, property: "eContainer") as? EPackage
        #expect(packageContainer?.id == library.id)
        #expect(try await engine.navigate(from: book, property: "eContainingFeature") != nil)
        #expect(try await engine.navigate(from: library, property: "eContainer") == nil)
        #expect(try await engine.navigate(from: library, property: "eContainingFeature") == nil)
        let archive = try #require(library.getSubpackage("archive"))
        let archiveFeature = try await engine.navigate(from: archive, property: "eContainingFeature") as? EReference
        #expect(archiveFeature?.name == "eSubpackages")
        let nested = try #require(archive.getEClass("Box"))
        let nestedFeature = try await engine.navigate(from: nested, property: "eContainingFeature") as? EReference
        #expect(nestedFeature?.name == "eClassifiers")
    }

    @Test("eContents and eAllContents of a metamodel")
    func contents() async throws {
        let (engine, _) = await makeEngine(library)
        let genre = try #require(library.getEEnum("Genre"))
        #expect(names(try await engine.navigate(from: genre, property: "eContents")) == ["fiction", "history"])
        let book = try #require(library.getEClass("Book"))
        #expect(names(try await engine.navigate(from: book, property: "eContents")) == ["genre", "tags"])
        let direct = try #require(
            try await engine.navigate(from: library, property: "eContents") as? EcoreValueArray)
        // One annotation, six classifiers, one subpackage
        #expect(direct.values.count == 8)
        let all = try #require(
            try await engine.navigate(from: library, property: "eAllContents") as? EcoreValueArray)
        #expect(all.values.count == library.eAllContents.count)
        let ids = Set(all.values.compactMap { ($0 as? any EObject)?.id })
        #expect(ids.count == all.values.count)
        let allNames = names(all)
        let itemIndex = try #require(allNames.firstIndex(of: "Item"))
        #expect(allNames[itemIndex + 1] == "title")
        #expect(allNames[itemIndex + 2] == "pages")
    }

    @Test("Contents of an unregistered metamodel object")
    func unregisteredContents() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let book = try #require(library.getEClass("Book"))
        let contents = try await engine.navigate(from: book, property: "eContents")
        #expect(names(contents) == ["genre", "tags"])
        let allContents = try await engine.navigate(from: library, property: "eAllContents") as? EcoreValueArray
        #expect(allContents?.values.count == library.eAllContents.count)
        #expect(try await engine.navigate(from: book, property: "eContainer") == nil)
        #expect(try await engine.navigate(from: book, property: "eContainingFeature") == nil)
        let genre = try #require(book.getStructuralFeature(name: "genre") as? EAttribute)
        #expect(try await engine.navigate(from: genre, property: "eAnnotations") != nil)
    }

    @Test("Containment of objects without a metamodel resource")
    func plainContainment() throws {
        let book = try #require(library.getEClass("Book"))
        #expect(book.eContents.count == 2)
        #expect(book.eAllContents.count == 2)
        #expect(book.eContainerID == library.id)
        #expect(library.eContainerID == nil)
        #expect(library.eAllContents.count == 19)
    }

    // MARK: - Resource enumeration

    @Test("getAllInstancesOf enumerates metamodel objects honouring subtyping")
    func instancesOf() async throws {
        let (_, resource) = await makeEngine(library)
        func count(_ classifier: EcoreClassifier) async -> Int {
            await resource.getAllInstancesOf(EcorePackage.metaClass(classifier)).count
        }
        // Item, Book, Library, Box
        #expect(await count(.eClass) == 4)
        // title, pages, genre, tags
        #expect(await count(.eAttribute) == 4)
        // items, featured
        #expect(await count(.eReference) == 2)
        #expect(await count(.eStructuralFeature) == 6)
        #expect(await count(.eTypedElement) == 6)
        // two packages
        #expect(await count(.ePackage) == 2)
        #expect(await count(.eEnum) == 1)
        #expect(await count(.eEnumLiteral) == 2)
        // Genre (an EEnum is an EDataType), EString, EInt
        #expect(await count(.eDataType) == 3)
        // classes, enum, data types
        #expect(await count(.eClassifier) == 4 + 1 + 2)
        #expect(await count(.eAnnotation) == 1)
        #expect(await count(.eStringToStringMapEntry) == 2)
        // package, annotation, classes... every contained element is an EModelElement except map entries
        let total = await resource.getAllObjectsIncludingContents().count
        #expect(await count(.eModelElement) == total - 2)
        #expect(await count(.eOperation) == 0)
    }

    @Test("getAllInstancesOf lists each object once in containment order")
    func instancesOrder() async throws {
        let (_, resource) = await makeEngine(library)
        let classes = await resource.getAllInstancesOf(EcorePackage.metaClass(.eClass))
        #expect(ReflectionFixtures.names(EcoreValueArray(classes)) == ["Item", "Book", "Library", "Box"])
        let features = await resource.getAllInstancesOf(EcorePackage.metaClass(.eStructuralFeature))
        #expect(
            ReflectionFixtures.names(EcoreValueArray(features))
                == ["title", "pages", "genre", "tags", "items", "featured"])
    }

    @Test("Native contents can be resolved by identifier")
    func resolveContents() async throws {
        let (_, resource) = await makeEngine(library)
        let book = try #require(library.getEClass("Book"))
        let genre = try #require(book.getStructuralFeature(name: "genre") as? EAttribute)
        #expect(await resource.contains(id: genre.id))
        #expect(await resource.resolve(genre.id)?.id == genre.id)
        #expect(await resource.getObject(book.id)?.id == book.id)
        let typed = await resource.resolve(genre.id, as: EAttribute.self)
        #expect(typed?.name == "genre")
        #expect(await resource.count() == 1)
        #expect(await resource.getAllObjects().count == 1)
    }

    @Test("Removing a metamodel removes its contents")
    func removeContents() async throws {
        let (_, resource) = await makeEngine(library)
        let book = try #require(library.getEClass("Book"))
        #expect(await resource.contains(id: book.id))
        await resource.remove(library)
        #expect(!(await resource.contains(id: book.id)))
        #expect(await resource.getAllInstancesOf(EcorePackage.metaClass(.eClass)).isEmpty)
        await resource.add(library)
        #expect(await resource.contains(id: book.id))
        await resource.clear()
        #expect(!(await resource.contains(id: book.id)))
    }

    @Test("Re-adding a modified metamodel refreshes its index")
    func reindex() async throws {
        let (_, resource) = await makeEngine(library)
        var modified = library
        modified.eClassifiers.append(EClass(name: "Magazine"))
        await resource.add(modified)
        let classes = await resource.getAllInstancesOf(EcorePackage.metaClass(.eClass))
        #expect(ReflectionFixtures.names(EcoreValueArray(classes)).contains("Magazine"))
        #expect(classes.count == 5)
    }

    @Test("Registered resources enumerate metamodel objects through the model wrapper")
    func engineInstances() async throws {
        let (engine, _) = await makeEngine(library)
        let attributes = await engine.allInstancesOf(EcorePackage.metaClass(.eAttribute))
        #expect(attributes.count == 4)
        let features = await engine.allInstancesOf(EcorePackage.metaClass(.eStructuralFeature))
        #expect(features.count == 6)
        let first = await engine.firstInstanceOf(EcorePackage.metaClass(.eReference))
        #expect((first as? EReference)?.name == "items")
    }

    // MARK: - Parsed fixtures

    @Test("Parsed organisation metamodel enumerates and navigates")
    func parsedOrganisation() async throws {
        let package = try await ReflectionFixtures.loadPackage("xmi/organisation.ecore")
        let (engine, resource) = await makeEngine(package)
        #expect(await resource.getAllInstancesOf(EcorePackage.metaClass(.eClass)).count == 3)
        let attributes = await resource.getAllInstancesOf(EcorePackage.metaClass(.eAttribute))
        let references = await resource.getAllInstancesOf(EcorePackage.metaClass(.eReference))
        let features = await resource.getAllInstancesOf(EcorePackage.metaClass(.eStructuralFeature))
        #expect(features.count == attributes.count + references.count)
        #expect(references.count >= 2)
        let team = try #require(package.getEClass("Team"))
        #expect(
            names(try await engine.navigate(from: team, property: "eStructuralFeatures"))
                == ["name", "members", "leader"])
        let members = try #require(team.getStructuralFeature(name: "members") as? EReference)
        let owner = try await engine.navigate(from: members, property: "eContainingClass") as? EClass
        #expect(owner?.name == "Team")
    }

    @Test("Parsed families metamodel resolves opposites by navigation")
    func parsedFamilies() async throws {
        let package = try await ReflectionFixtures.loadPackage("metamodels/Families.ecore")
        let (engine, resource) = await makeEngine(package)
        let family = try #require(package.getEClass("Family"))
        let father = try #require(family.getStructuralFeature(name: "father") as? EReference)
        let opposite = try await engine.navigate(from: father, property: "eOpposite") as? EReference
        #expect(opposite?.name == "familyFather")
        let back = try await engine.navigate(from: try #require(opposite), property: "eOpposite") as? EReference
        #expect(back?.id == father.id)
        #expect(await resource.getAllInstancesOf(EcorePackage.metaClass(.eReference)).count == 8)
        #expect(await resource.getAllInstancesOf(EcorePackage.metaClass(.eAttribute)).count == 2)
    }

    @Test("Parsed animals metamodel enumerates enumerations and literals")
    func parsedAnimals() async throws {
        let package = try await ReflectionFixtures.loadPackage("xmi/animals.ecore")
        let (_, resource) = await makeEngine(package)
        #expect(await resource.getAllInstancesOf(EcorePackage.metaClass(.eEnum)).count == 1)
        #expect(await resource.getAllInstancesOf(EcorePackage.metaClass(.eEnumLiteral)).count == 3)
        #expect(await resource.getAllInstancesOf(EcorePackage.metaClass(.eClassifier)).count == 2)
    }

    // MARK: - Resource set

    @Test("Resource sets provide the Ecore package")
    func resourceSet() async throws {
        let resourceSet = ResourceSet()
        let found = await resourceSet.getMetamodel(uri: "http://www.eclipse.org/emf/2002/Ecore")
        #expect(found?.id == EcorePackage.instance.id)
        #expect(await resourceSet.ecorePackage.id == EcorePackage.instance.id)
        #expect(await resourceSet.getMetamodel(uri: "http://example.org/none") == nil)
        #expect(await resourceSet.getMetamodelURIs().isEmpty)
        let replacement = EPackage(name: "ecore", nsURI: EcorePackage.nsURI, nsPrefix: "ecore")
        await resourceSet.registerMetamodel(replacement, uri: EcorePackage.nsURI)
        #expect(await resourceSet.getMetamodel(uri: EcorePackage.nsURI)?.id == replacement.id)
        #expect(await resourceSet.ecorePackage.id == replacement.id)
    }
}
