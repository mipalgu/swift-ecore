//
// MultiLevelViewTests.swift
// MultiLevelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import MultiLevel

/// Reads values of view objects by name.
extension Resource {
    /// The object of the resource with an identifier, as a dynamic object.
    func dynamic(_ id: EUUID) -> DynamicEObject? {
        resolve(id) as? DynamicEObject
    }
}

/// The class of a package with a name.
func eClass(_ package: EPackage, _ name: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> EClass {
    try #require(package.eClassifiers.first { $0.name == name } as? EClass, sourceLocation: sourceLocation)
}

/// Tests the deep level views of deep models.
@Suite("Deep level views")
struct DeepLevelViewTests {
    @Test("type facets above the level become classes, with instantiation rendered as specialisation")
    func classes() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        let view = try await model.deepLevelView(atLevel: 0)
        #expect(Set(view.package.eClassifiers.map(\.name)) == ["ProductType", "Book", "Disc", "Author"])
        #expect(view.package.name == "BookStore")
        #expect(view.namespaceURI == "urn:swift-ecore:multilevel:view:Commerce:Shop:deep")
        let book = try eClass(view.package, "Book")
        #expect(book.eSuperTypes.map(\.name) == ["ProductType"])
        #expect(try view.clabject(ofClass: book)?.name == "Book")
        #expect(try view.eClass(of: model.id("Book"))?.name == "Book")
        let productType = try eClass(view.package, "ProductType")
        let price = try #require(productType.getEAttribute(name: "price"))
        #expect(!price.derived && price.eType.name == "EDouble")
        let vat = try #require(productType.getEAttribute(name: "vat"))
        #expect(vat.derived && !vat.changeable)
        #expect(book.getEAttribute(name: "pages") != nil && book.getEReference(name: "authors") != nil)
        #expect(book.getStructuralFeature(name: "price") != nil && !book.eStructuralFeatures.contains { $0.name == "price" })
    }

    @Test("the clabjects of the level become objects that hold slots, defaults and type-level slots")
    func objects() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        let view = try await model.deepLevelView(atLevel: 0)
        let resource = view.resource
        #expect(await resource.count() == 5)
        let patterns = try #require(await resource.dynamic(model.id("patterns")))
        #expect(patterns.eClass.name == "Book")
        #expect(view.clabject(of: patterns)?.name == "patterns")
        #expect(patterns.eGet("price") as? Double == 35)
        #expect(patterns.eGet("pages") as? Int == 395)
        #expect(patterns.eGet("vat") as? Double == 4)
        #expect(try patterns.eGet("authors") as? [EUUID] == [model.id("gamma"), model.id("helm")])
        let draft = try #require(await resource.dynamic(model.id("draft")))
        #expect(draft.eGet("price") as? Double == 10)
        #expect(try await resource.dynamic(model.id("album"))?.eGet("vat") as? Double == 10)
    }

    @Test("Ecore instance matching by supertypes finds every deep instance")
    func deepMatching() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        let view = try await model.deepLevelView(atLevel: 0)
        let productType = try eClass(view.package, "ProductType")
        let matched = await view.resource.getAllInstancesOf(productType).compactMap { view.clabject(of: $0)?.name }
        #expect(Set(matched) == ["patterns", "album", "draft"])
        let arcade = try MultiLevelFixtures.model(MultiLevelFixtures.arcade)
        let arcadeView = try await arcade.deepLevelView(atLevel: 0)
        let elements = await arcadeView.resource.getAllInstancesOf(try eClass(arcadeView.package, "ElementKind"))
        #expect(Set(elements.compactMap { arcadeView.clabject(of: $0)?.name }) == ["m", "p", "c0", "c1"])
    }

    @Test("every object is kind of each of its deep types and of nothing else", arguments: MetaDepthTextTests.fixtures)
    func deepTypingProperty(text: String) async throws {
        let model = try MultiLevelFixtures.model(text)
        for level in model.levelNumbers {
            let view = try await model.deepLevelView(atLevel: level)
            for object in await view.resource.getAllObjects() {
                let clabject = try #require(view.clabject(of: object))
                guard let eClass = object.eClass as? EClass, view.clabject(ofClass: eClass)?.id != clabject.id else { continue }
                let kinds = Set(([eClass] + eClass.allSuperTypes).compactMap { view.clabject(ofClass: $0)?.id })
                let expected = Set(model.deepTypes(of: clabject.id).map(\.id))
                #expect(kinds == expected, "\(clabject.name) at level \(level)")
            }
        }
    }

    @Test("leap potency and deep references are shown at the level of their slots")
    func arcade() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.arcade)
        let view = try await model.deepLevelView(atLevel: 0)
        let t0 = try #require(await view.resource.dynamic(model.id("t0")))
        #expect(t0.eClass.name == "Tile")
        #expect(try t0.eGet("next") as? [EUUID] == [model.id("t1")])
        #expect(try t0.eGet("elements") as? [EUUID] == [model.id("c0"), model.id("m")])
        let m = try #require(await view.resource.dynamic(model.id("m")))
        #expect(m.eGet("initLives") as? Int == 5)
        #expect(m.eGet("lives") as? Int == 3)
        #expect(try await view.resource.dynamic(model.id("c1"))?.eGet("value") as? Int == 20)
    }

    @Test("a feature instantiated below under another name holds the values of its instances")
    func instantiatedFeatures() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.process)
        let view = try await model.deepLevelView(atLevel: 0)
        let coding = try #require(await view.resource.dynamic(model.id("uiCoding")))
        #expect(try coding.eGet("tests") as? [EUUID] == [model.id("layoutTest")])
        #expect(try coding.eGet("next") as? [EUUID] == [model.id("layoutTest")])
        #expect(try coding.eGet("perfBy") as? [EUUID] == [model.id("alice")])
        #expect(coding.eGet("name") as? String == "programming")
    }

    @Test("views of every level share a resource set and resolve level-crossing references")
    func levelCrossingViews() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.bicycles)
        let resourceSet = ResourceSet()
        let views = try await model.deepLevelViews(in: resourceSet)
        #expect(views.map(\.level) == [3, 2, 1, 0])
        let inventory = try #require(views.last)
        let bike = try #require(await inventory.resource.dynamic(model.id("bike1")))
        let alternative = try #require(bike.eGet("alternative") as? EUUID)
        #expect(try alternative == model.id("Sprinter"))
        #expect(await resourceSet.resolve(alternative) != nil)
        #expect(try bike.eGet("frame") as? EUUID == model.id("frame1"))
        #expect(bike.eGet("listPrice") as? Double == 4999)
        #expect(bike.eGet("categoryName") as? String == "racing")
        let frame = try #require(await inventory.resource.dynamic(model.id("frame1")))
        #expect(frame.eGet("material") as? String == "carbon")
        #expect(frame.eGet("weight") as? Double == 0.9)
        let catalogue = views[2]
        #expect(try await catalogue.resource.dynamic(model.id("Challenger"))?.eGet("topSpeed") as? Double == 70)
    }

    @Test("Melanee attributes are slots wherever they endure")
    func melanee() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.retail)
        let view = try await model.deepLevelView(atLevel: 0)
        let novel = try #require(await view.resource.dynamic(model.id("novel")))
        #expect(novel.eGet("price") as? Double == 12)
        #expect(novel.eGet("discount") as? Double == 1.5)
        #expect(novel.eGet("vat") as? Double == 20)
        #expect(try await view.resource.dynamic(model.id("thriller"))?.eGet("label") as? String == "thriller")
        let top = try await model.deepLevelView(atLevel: 2)
        let productType = try #require(await top.resource.dynamic(model.id("ProductType")))
        #expect(productType.eGet("price") as? Double == 10)
    }

    @Test("edges become objects with their ends, and their ends' references hold the edges' targets")
    func edges() async throws {
        let text = """
            Model Library@2 {
              Node Writer {
                books@1 : Volume[*];
              }
              Node Volume {}
              Edge Writes(Writer.books, Volume.writers) {}
            }
            Library Catalogue {
              Writer author {}
              Volume novel {}
              Writes credit(author, novel) {}
            }
            """
        let model = try MultiLevelFixtures.model(text)
        let view = try await model.deepLevelView(atLevel: 1)
        let credit = try #require(await view.resource.dynamic(model.id("credit")))
        #expect(credit.eClass.name == "Writes")
        #expect(try credit.eGet(MultiLevelSyntax.edgeSourceName) as? EUUID == model.id("author"))
        #expect(try credit.eGet(MultiLevelSyntax.edgeTargetName) as? EUUID == model.id("novel"))
        #expect(try await view.resource.dynamic(model.id("author"))?.eGet("books") as? [EUUID] == [model.id("novel")])
    }

    @Test("a level that the model does not have is reported")
    func missingLevel() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        await #expect(throws: MultiLevelError.noSuchLevel(9)) { try await model.deepLevelView(atLevel: 9) }
        await #expect(throws: MultiLevelError.noSuchLevel(-1)) { try await model.levelPairView(atLevel: -1) }
        #expect(throws: MultiLevelError.noSuchLevel(3)) { try model.ecorePackage(forLevel: 3) }
    }
}

/// Tests the writable level-pair views and the per-level Ecore export.
@Suite("Level-pair views")
struct LevelPairViewTests {
    @Test("the classes of the level above carry the features whose slots fall at the level below")
    func classes() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        let view = try await model.levelPairView(atLevel: 0)
        #expect(Set(view.package.eClassifiers.map(\.name)) == ["Book", "Disc", "Author"])
        #expect(view.namespaceURI.hasSuffix(":pair"))
        let book = try eClass(view.package, "Book")
        #expect(book.eSuperTypes.isEmpty)
        let price = try #require(book.getEAttribute(name: "price"))
        #expect(price.changeable && !price.derived && price.defaultValueLiteral == "10.0")
        let vat = try #require(book.getEAttribute(name: "vat"))
        #expect(vat.derived && !vat.changeable)
        #expect(book.getEReference(name: "authors")?.upperBound == -1)
    }

    @Test("objects hold explicit slots only, so that defaults stay defaults when committed")
    func explicitSlots() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        let view = try await model.levelPairView(atLevel: 0)
        let draft = try #require(await view.resource.dynamic(model.id("draft")))
        #expect(!draft.eIsSet("price"))
        #expect(draft.eGetWithDefault("price") as? Double == 10)
        #expect(draft.eGet("vat") as? Double == 4)
        #expect(await view.committed() == model)
    }

    @Test("edits, new objects and removals are committed to the deep model")
    func commit() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        let view = try await model.levelPairView(atLevel: 0)
        let book = try eClass(view.package, "Book")
        var draft = try #require(await view.resource.dynamic(model.id("draft")))
        draft.eSet("price", value: 12.5)
        await view.resource.add(draft)
        var fresh = DynamicEObject(eClass: book)
        fresh.eSet("pages", value: 10)
        try fresh.eSet("authors", value: [model.id("helm")])
        await view.resource.add(fresh)
        _ = try await view.resource.remove(id: model.id("album"))
        let committed = await view.committed()
        #expect(try committed.values(of: "price", at: model.id("draft")) == [.real(12.5)])
        let created = try #require(committed.clabject(fresh.id))
        #expect(created.name.hasPrefix(MultiLevelSyntax.anonymousPrefix))
        #expect(try created.type == model.id("Book"))
        #expect(try created.slot(named: "authors")?.values == [.object(model.id("helm"))])
        #expect(committed.clabject(named: "album") == nil)
        #expect(committed.validateStructure().isEmpty)
        let text = MetaDepthWriter.write(committed).text
        #expect(text.contains("  Book \(created.name) {\n    pages = 10;\n    authors = [helm];\n  }"))
    }

    @Test("leap clabjects contribute classes to the level where their instances reside")
    func leap() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.arcade)
        let view = try await model.levelPairView(atLevel: 0)
        #expect(Set(view.package.eClassifiers.map(\.name)) == ["Coin", "Muncher", "Phantom", "Tile"])
        #expect(try await view.resource.dynamic(model.id("t0"))?.eClass.name == "Tile")
        let muncher = try eClass(view.package, "Muncher")
        #expect(muncher.getEAttribute(name: "initLives")?.derived == true)
        #expect(muncher.getEAttribute(name: "lives")?.defaultValueLiteral == "3")
        #expect(await view.committed() == model)
    }

    @Test("Melanee mutability decides which attributes are changeable")
    func melaneeMutability() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.retail)
        let view = try await model.levelPairView(atLevel: 0)
        let book = try eClass(view.package, "Book")
        #expect(book.getEAttribute(name: "price")?.changeable == false)
        #expect(book.getEAttribute(name: "discount")?.changeable == true)
        #expect(book.getEAttribute(name: "vat")?.derived == true)
    }

    @Test("the Ecore export of a level is an annotated metamodel that Ecore readers load")
    func ecoreExport() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        let package = try model.ecorePackage(forLevel: 0)
        let xmi = XMISerializer().serialize([package], relativeTo: nil)
        #expect(xmi.contains("source=\"\(MultiLevelSyntax.annotationSource)\""))
        #expect(xmi.contains("key=\"potency\""))
        let loaded = try await ModelIO.load(data: Data(xmi.utf8), uri: "memory:shop.ecore", resourceSet: ResourceSet())
        #expect(loaded.format == .ecore)
        #expect(Set(loaded.packages.first?.eClassifiers.map(\.name) ?? []) == ["Book", "Disc", "Author"])
        let top = try model.ecorePackage(forLevel: 2)
        #expect(top.eClassifiers.map(\.name) == ["ProductType"])
    }
}
