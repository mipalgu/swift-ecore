//
// GenModelResourceTests.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import GenModel

@Suite("GenModel loading")
struct GenModelResourceTests {
    private static func fixtureURL(_ name: String, _ ext: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources"))
    }

    private static var genModelURL: URL {
        get throws { try fixtureURL("library", "genmodel") }
    }

    private func names(_ elements: [GenElement]) -> [String] { elements.map(\.name) }

    // MARK: - Loading

    @Test("loading registers the generator metamodel and returns a generator model")
    func registersMetamodel() async throws {
        let resourceSet = ResourceSet()
        let resource = try await GenModelResource.load(
            url: Self.genModelURL, resourceSet: resourceSet)
        let metamodel = await resourceSet.getMetamodel(uri: GenModelConstants.nsURI)
        #expect(metamodel?.name == "genmodel")
        let roots = await resource.getRootObjects()
        #expect(roots.count == 1)
        let root = try #require(roots.first as? DynamicEObject)
        #expect(root.eClass.name == "GenModel")
    }

    @Test("loading with a default resource set works")
    func defaultResourceSet() async throws {
        let resource = try await GenModelResource.load(url: Self.genModelURL)
        #expect(await resource.getRootObjects().count == 1)
    }

    @Test("an existing registration of the metamodel is kept")
    func keepsRegistration() async throws {
        let resourceSet = ResourceSet()
        let package = try await GenModelPackage.load()
        await resourceSet.registerMetamodel(package, uri: GenModelConstants.nsURI)
        _ = try await GenModelResource.load(url: Self.genModelURL, resourceSet: resourceSet)
        #expect(await resourceSet.getMetamodel(uri: GenModelConstants.nsURI)?.id == package.id)
    }

    @Test("attributes of the generator model are read with their types")
    func attributes() async throws {
        let resourceSet = ResourceSet()
        let resource = try await GenModelResource.load(
            url: Self.genModelURL, resourceSet: resourceSet)
        let context = await GenModelContext.snapshot(of: resourceSet)
        let genModel = try #require(context.genModels.first)
        #expect(genModel.stringValue("modelName") == "Library")
        #expect(genModel.stringValue("modelDirectory") == "/library/src")
        #expect(genModel.stringValue("modelPluginID") == "library")
        #expect(genModel.stringValue("complianceLevel") == "17.0")
        #expect(genModel.name == "Library")
        let package = try #require(genModel.genPackages.first)
        #expect(package.stringValue("prefix") == "Library")
        #expect(package.stringValue("basePackage") == "org.example")
        #expect(package.boolValue("disposableProviderFactory"))
        #expect(!package.boolValue("adapterFactory"))
        _ = resource
    }

    @Test("the containment structure of the fixture is complete")
    func structure() async throws {
        let resourceSet = ResourceSet()
        _ = try await GenModelResource.load(url: Self.genModelURL, resourceSet: resourceSet)
        let context = await GenModelContext.snapshot(of: resourceSet)
        let genModel = try #require(context.genModels.first)
        #expect(genModel.genPackages.count == 1)
        let package = try #require(genModel.genPackages.first)
        #expect(package.genClasses.count == 5)
        #expect(package.genEnums.count == 1)
        #expect(package.genDataTypes.count == 1)
        #expect(package.genEnums.first?.genEnumLiterals.count == 3)
        #expect(package.genClasses.map(\.genFeatures.count) == [1, 2, 5, 1, 2])
        #expect(package.genClassifiers.count == 7)
        let feature = try #require(package.genClasses[2].genFeatures.first)
        #expect(feature.genClass == package.genClasses[2])
        #expect(feature.genPackage == package)
        #expect(feature.genModel == genModel)
        #expect(package.genEnums.first?.boolValue("typeSafeEnumCompatible", default: true) == false)
        #expect(package.genClasses[0].boolValue("image", default: true) == false)
        #expect(
            package.genClasses[2].genFeatures[4].stringValue("property") == "None")
    }

    @Test("source models are located relative to the generator model")
    func foreignModels() async throws {
        let locations = try GenModelResource.foreignModelLocations(in: Self.genModelURL)
        #expect(locations == ["library.ecore"])
    }

    @Test("source models are loaded and registered by namespace")
    func foreignModelsLoaded() async throws {
        let resourceSet = ResourceSet()
        let document = try await GenModelResource.loadDocument(
            url: Self.genModelURL, resourceSet: resourceSet)
        #expect(document.foreignPackages.count == 1)
        let package = try #require(document.foreignPackages.values.first)
        #expect(package.name == "library")
        #expect(package.nsURI == "http://example.org/library/1.0")
        #expect(package.eClassifiers.count == 7)
        let registered = await resourceSet.getMetamodel(uri: "http://example.org/library/1.0")
        #expect(registered?.id == package.id)
        #expect(await resourceSet.count() == 2)
        let key = try #require(document.foreignPackages.keys.first)
        #expect(key.lastPathComponent == "library.ecore")
        #expect(document.url.lastPathComponent == "library.genmodel")
    }

    @Test("native classes keep their supertypes and features once loaded")
    func nativeLoad() async throws {
        let document = try await GenModelResource.loadDocument(url: Self.genModelURL)
        let package = try #require(document.foreignPackages.values.first)
        let writer = try #require(package.getEClass("Writer"))
        #expect(writer.eSuperTypes.map(\.name) == ["Named"])
        #expect(writer.eStructuralFeatures.map(\.name) == ["books"])
        let book = try #require(package.getEClass("Book"))
        #expect(book.eStructuralFeatures.map(\.name) == ["pages", "category", "isbn", "author", "library"])
        #expect(try #require(package.getEClass("Lendable")).isInterface)
        #expect(try #require(package.getEClass("Named")).isAbstract)
    }

    @Test("a class with several supertypes keeps all of them once loaded")
    func multipleSupertypesLoaded() async throws {
        let document = try await GenModelResource.loadDocument(url: Self.genModelURL)
        let package = try #require(document.foreignPackages.values.first)
        let book = try #require(package.getEClass("Book"))
        #expect(book.eSuperTypes.map(\.name) == ["Named", "Lendable"])
    }

    // MARK: - Errors

    @Test("a missing file raises an error")
    func missingFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(UUID().uuidString).genmodel")
        await #expect(throws: (any Error).self) {
            _ = try await GenModelResource.load(url: url)
        }
    }

    @Test("an Ecore document is not a generator model")
    func notAGenModel() async throws {
        let url = try Self.fixtureURL("library", "ecore")
        await #expect(throws: GenModelError.notAGenModel(url.absoluteString)) {
            _ = try await GenModelResource.load(url: url)
        }
    }

    @Test("a missing named source model raises an error")
    func missingForeignModel() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("broken.genmodel")
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <genmodel:GenModel xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
                xmlns:genmodel="http://www.eclipse.org/emf/2002/GenModel" modelName="Broken">
              <foreignModel>missing.ecore</foreignModel>
            </genmodel:GenModel>
            """
        try text.write(to: url, atomically: true, encoding: .utf8)
        do {
            _ = try await GenModelResource.load(url: url)
            Issue.record("expected an error")
        } catch let error as GenModelError {
            guard case .foreignModelUnreadable(let location, _) = error else {
                Issue.record("unexpected error \(error)")
                return
            }
            #expect(location.hasSuffix("missing.ecore"))
        }
    }

    @Test("a source model that is not valid XML raises an error")
    func unreadableForeignModel() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "<not-closed".write(
            to: directory.appendingPathComponent("bad.ecore"), atomically: true, encoding: .utf8)
        let url = directory.appendingPathComponent("bad.genmodel")
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <genmodel:GenModel xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
                xmlns:genmodel="http://www.eclipse.org/emf/2002/GenModel" modelName="Bad">
              <foreignModel>bad.ecore</foreignModel>
            </genmodel:GenModel>
            """
        try text.write(to: url, atomically: true, encoding: .utf8)
        await #expect(throws: GenModelError.self) {
            _ = try await GenModelResource.load(url: url)
        }
    }

    @Test("unreferenced non-Ecore locations are ignored")
    func ignoresOtherLocations() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("other.genmodel")
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <genmodel:GenModel xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
                xmlns:genmodel="http://www.eclipse.org/emf/2002/GenModel" modelName="Other">
              <genPackages prefix="Other" ecorePackage="missing.ecore#/"
                  usedGenPackages="Ecore.genmodel#//ecore"/>
            </genmodel:GenModel>
            """
        try text.write(to: url, atomically: true, encoding: .utf8)
        let document = try await GenModelResource.loadDocument(url: url)
        #expect(document.foreignPackages.isEmpty)
    }

    // MARK: - Reference resolution through this library's fragment resolver

    private func resolvedContext() async throws -> (GenModelContext, GenElement) {
        let resourceSet = ResourceSet()
        _ = try await GenModelResource.load(
            url: Self.genModelURL, resourceSet: resourceSet, resolution: .nameFragments)
        let context = await GenModelContext.snapshot(of: resourceSet)
        let package = try #require(context.genModels.first?.genPackages.first)
        return (context, package)
    }

    @Test("deferred loading leaves references as text")
    func deferredLeavesText() async throws {
        let resourceSet = ResourceSet()
        let resource = try await GenModelResource.load(
            url: Self.genModelURL, resourceSet: resourceSet, resolution: .deferred)
        let objects = await resource.getAllObjects().compactMap { $0 as? DynamicEObject }
        let genClass = try #require(objects.first { $0.eClass.name == "GenClass" })
        #expect(genClass.eGet("ecoreClass") is String)
    }

    @Test("name fragment resolution connects the generator model to the Ecore model")
    func nameFragmentResolution() async throws {
        let (_, package) = try await resolvedContext()
        #expect(package.name == "library")
        #expect(names(package.genClasses) == ["Named", "Lendable", "Book", "Writer", "Library"])
        #expect(names(package.genEnums) == ["BookCategory"])
        #expect(names(package.genEnums[0].genEnumLiterals) == ["Mystery", "ScienceFiction", "Biography"])
        #expect(names(package.genDataTypes) == ["ISBN"])
    }

    @Test("facade over a loaded generator model orders inherited features first")
    func loadedFeatureOrder() async throws {
        let (_, package) = try await resolvedContext()
        let writer = package.genClasses[3]
        #expect(names(writer.allGenFeatures) == ["name", "books"])
        #expect(names(writer.allBaseGenClasses) == ["Named"])
        #expect(writer.featureCount == 2)
        let books = try #require(writer.genFeatures.first)
        #expect(writer.featureID(of: books) == 1)
        #expect(writer.classExtendsGenClass?.name == "Named")
        #expect(names(writer.implementedGenFeatures) == ["books"])
        #expect(writer.labelFeature?.name == "name")
        #expect(!writer.isAbstract)
        #expect(package.genClasses[0].isAbstract)
        #expect(package.genClasses[1].isInterface)
    }

    @Test("multiple inheritance of a loaded class orders features by supertype")
    func loadedMultipleInheritance() async throws {
        let (_, package) = try await resolvedContext()
        let book = package.genClasses[2]
        #expect(
            names(book.allGenFeatures)
                == ["name", "loanDays", "onLoan", "pages", "category", "isbn", "author", "library"])
        #expect(names(book.allBaseGenClasses) == ["Named", "Lendable"])
        #expect(book.featureCount == 8)
        let pages = try #require(book.genFeatures.first { $0.name == "pages" })
        #expect(book.featureID(of: pages) == 3)
        #expect(book.classExtendsGenClass?.name == "Named")
        #expect(
            names(book.implementedGenFeatures)
                == ["loanDays", "onLoan", "pages", "category", "isbn", "author", "library"])
        #expect(book.labelFeature?.name == "name")
    }

    @Test("facade over a loaded generator model numbers classifiers")
    func loadedClassifierOrder() async throws {
        let (_, package) = try await resolvedContext()
        #expect(
            names(package.genClassifiers)
                == ["Named", "Lendable", "Book", "Writer", "Library", "BookCategory", "ISBN"])
        #expect(package.genClasses[2].classifierID == 2)
        #expect(package.genEnums[0].classifierID == 5)
        #expect(package.genDataTypes[0].classifierID == 6)
        #expect(names(package.orderedGenClasses) == ["Named", "Lendable", "Book", "Writer", "Library"])
        #expect(package.genClasses[2].classifierIDName == "BOOK")
        #expect(package.genEnums[0].classifierIDName == "BOOK_CATEGORY")
    }

    @Test("facade over a loaded generator model reads feature properties")
    func loadedFeatureProperties() async throws {
        let (_, package) = try await resolvedContext()
        let library = package.genClasses[4]
        let books = try #require(library.genFeatures.first { $0.name == "books" })
        #expect(books.isContainment)
        #expect(books.isBidirectional)
        #expect(books.isListType)
        let bookClass = package.genClasses[2]
        let pages = try #require(bookClass.genFeatures.first { $0.name == "pages" })
        #expect(pages.hasDefault)
        #expect(pages.defaultValueLiteral == "100")
        let loanDays = try #require(package.genClasses[1].genFeatures.first)
        #expect(loanDays.defaultValueLiteral == "14")
        let owner = try #require(bookClass.genFeatures.first { $0.name == "library" })
        #expect(owner.isContainer)
        #expect(owner.reverseGenFeature == books)
    }

    // MARK: - Cross-document resolution by the resource set (not available yet)

    @Test(
        "ecore references resolve automatically when loaded with deferred resolution",
        .disabled("requires cross-document XMI references"))
    func automaticResolutionOfClasses() async throws {
        let resourceSet = ResourceSet()
        let resource = try await GenModelResource.load(
            url: Self.genModelURL, resourceSet: resourceSet, resolution: .deferred)
        let objects = await resource.getAllObjects().compactMap { $0 as? DynamicEObject }
        let genClass = try #require(objects.first { $0.eClass.name == "GenClass" })
        #expect(!(genClass.eGet("ecoreClass") is String))
    }

    @Test(
        "the facade works on a model loaded with deferred resolution",
        .disabled("requires cross-document XMI references"))
    func facadeAfterAutomaticResolution() async throws {
        let resourceSet = ResourceSet()
        _ = try await GenModelResource.load(
            url: Self.genModelURL, resourceSet: resourceSet, resolution: .deferred)
        let context = await GenModelContext.snapshot(of: resourceSet)
        let package = try #require(context.genModels.first?.genPackages.first)
        let book = try #require(package.genClasses.first { $0.name == "Book" })
        #expect(book.featureCount == 8)
    }
}
