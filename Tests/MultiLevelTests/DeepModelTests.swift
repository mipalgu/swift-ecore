//
// DeepModelTests.swift
// MultiLevelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import MultiLevel

/// Tests potency, deep instantiation, feature visibility and slot lookup.
@Suite("Deep model semantics")
struct DeepModelTests {
    // MARK: - Potency

    @Test("a finite potency decreases by one per instantiation step and stops at zero")
    func finitePotency() {
        #expect(Potency(2).decremented() == Potency(1))
        #expect(Potency(2).decremented(by: 2) == .zero)
        #expect(Potency(1).decremented(by: 2) == nil)
        #expect(Potency.zero.isZero)
        #expect(Potency(-3) == .zero)
        #expect(Potency(2).admits(2) && !Potency(2).admits(3))
        #expect(Potency(3).description == "3")
    }

    @Test("an unbounded potency stays unbounded and orders above every finite potency")
    func unboundedPotency() {
        #expect(Potency.unbounded.decremented(by: 100) == .unbounded)
        #expect(Potency.unbounded.admits(1_000))
        #expect(Potency(1_000) < .unbounded)
        #expect(!(Potency.unbounded < Potency(1)))
        #expect(Potency(text: "*") == .unbounded)
        #expect(Potency(text: "4") == Potency(4))
        #expect(Potency(text: "-1") == nil)
        #expect(Potency.unbounded.description == "*")
    }

    @Test("MetaDepth features are definitions above their slot level and slots exactly at it")
    func metaDepthRoles() {
        let scheme = MetaDepthPotencyScheme()
        let two = Potency(2)
        #expect(scheme.role(durability: two, mutability: nil, levelsBelow: 0).isDefinition)
        #expect(!scheme.role(durability: two, mutability: nil, levelsBelow: 1).isSlot)
        #expect(scheme.role(durability: two, mutability: nil, levelsBelow: 2).isSlot)
        #expect(!scheme.role(durability: two, mutability: nil, levelsBelow: 2).isDefinition)
        #expect(scheme.role(durability: two, mutability: nil, levelsBelow: 3) == .absent)
        #expect(scheme.role(durability: two, mutability: nil, levelsBelow: -1) == .absent)
        #expect(!scheme.permitsUnboundedPotency && !scheme.permitsMutability)
    }

    @Test("Melanee features hold values wherever they endure and change only while mutable")
    func melaneeRoles() {
        let scheme = MelaneePotencyScheme()
        let fixed = scheme.role(durability: Potency(2), mutability: .zero, levelsBelow: 1)
        #expect(fixed.exists && fixed.isSlot && fixed.isDefinition && !fixed.isMutable)
        #expect(scheme.role(durability: Potency(2), mutability: .zero, levelsBelow: 0).isMutable)
        #expect(scheme.role(durability: Potency(2), mutability: nil, levelsBelow: 2).isMutable)
        #expect(!scheme.role(durability: Potency(2), mutability: nil, levelsBelow: 2).isDefinition)
        #expect(scheme.role(durability: .unbounded, mutability: nil, levelsBelow: 50).isDefinition)
        #expect(scheme.role(durability: Potency(1), mutability: nil, levelsBelow: 2) == .absent)
        #expect(scheme.admitsInstancePotency(Potency(7), ofTypePotency: .unbounded, isLeap: false))
        #expect(!scheme.admitsInstancePotency(Potency(7), ofTypePotency: Potency(2), isLeap: false))
        #expect(scheme.instancePotency(ofTypePotency: .zero, isLeap: false) == nil)
    }

    @Test("the built-in schemes are found by their variants")
    func schemeLookup() {
        #expect(PotencySchemes.scheme(for: .metaDepth)?.variant == .metaDepth)
        #expect(PotencySchemes.scheme(for: .melanee)?.variant == .melanee)
        #expect(PotencySchemes.scheme(for: PotencyVariant(rawValue: "dual")) == nil)
    }

    // MARK: - Deep Instantiation

    @Test("levels are numbered from the potency of the top model")
    func levelNumbers() throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        #expect(model.name == "Commerce")
        #expect(model.levelNumbers == [2, 1, 0])
        #expect(model.levelModel(atLevel: 1)?.name == "BookStore")
        #expect(try model.level(of: model.id("patterns")) == 0)
        #expect(model.levelModel(atLevel: 7) == nil)
    }

    @Test("clabject potency defaults to the potency of the type minus one")
    func clabjectPotency() throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        #expect(try model.potency(of: model.id("ProductType")) == Potency(2))
        #expect(try model.potency(of: model.id("Book")) == Potency(1))
        #expect(try model.potency(of: model.id("patterns")) == .zero)
        #expect(try model.potency(of: model.id("Author")) == Potency(1))
        #expect(model.potency(of: EUUID()) == nil)
    }

    @Test("deep types include the type, its supertypes and their deep types")
    func deepTypes() throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        let patterns = try model.id("patterns")
        #expect(model.deepTypes(of: patterns).map(\.name) == ["Book", "ProductType"])
        #expect(model.ontologicalTypeChain(of: patterns).map(\.name) == ["Book", "ProductType"])
        #expect(try model.isDeepInstance(patterns, of: model.id("ProductType")))
        #expect(try !model.isDeepInstance(patterns, of: model.id("Disc")))
        let arcade = try MultiLevelFixtures.model(MultiLevelFixtures.arcade)
        #expect(try arcade.deepTypes(of: arcade.id("m")).map(\.name) == [
            "Muncher", "HeroKind", "CharacterKind", "ElementKind",
        ])
    }

    @Test("all instances of a type are its direct and indirect instances, optionally at one level")
    func transitiveInstances() throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        let productType = try model.id("ProductType")
        #expect(model.instances(of: productType).map(\.name) == ["Book", "Disc", "patterns", "album", "draft"])
        #expect(model.instances(of: productType, atLevel: 0).map(\.name) == ["patterns", "album", "draft"])
        #expect(try model.instances(of: model.id("Author"), atLevel: 0).map(\.name) == ["gamma", "helm"])
    }

    @Test("leap potency places instances several levels below without identity instances")
    func leapPotency() throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.arcade)
        let tile = try model.id("Tile")
        #expect(model.instantiationOffset(of: tile) == 2)
        #expect(try model.instantiationOffset(of: model.id("HeroKind")) == 1)
        #expect(model.instances(of: tile).map(\.name) == ["t0", "t1"])
        #expect(try model.potency(of: model.id("t0")) == .zero)
        let next = try #require(try model.feature(named: "next", at: model.id("t0")))
        #expect(next.role.isSlot && next.levelsBelow == 2)
    }

    // MARK: - Features and Slots

    @Test("a feature becomes a slot at the level its potency determines")
    func featurePotency() throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        let book = try model.id("Book")
        let patterns = try model.id("patterns")
        let atBook = model.features(of: book)
        #expect(atBook.first { $0.feature.name == "vat" }?.role.isSlot == true)
        #expect(atBook.first { $0.feature.name == "price" }?.role.isDefinition == true)
        #expect(atBook.first { $0.feature.name == "pages" }?.durability == Potency(1))
        let atPatterns = Set(model.features(of: patterns).map(\.feature.name))
        #expect(atPatterns == ["pages", "authors", "price"])
        #expect(model.feature(named: "vat", at: patterns) == nil)
        #expect(model.feature(named: "price", at: patterns)?.role.isSlot == true)
    }

    @Test("defaults flow down and type-level slots are read along the type chain")
    func slotValues() throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        #expect(try model.values(of: "price", at: model.id("patterns")) == [.real(35)])
        #expect(try model.values(of: "price", at: model.id("draft")) == [.real(10)])
        #expect(try model.values(of: "vat", at: model.id("draft")) == [.real(4)])
        #expect(try model.values(of: "vat", at: model.id("album")) == [.real(10)])
        #expect(try model.values(of: "pages", at: model.id("draft")) == nil)
        #expect(try model.values(of: "authors", at: model.id("patterns")) == [
            .object(model.id("gamma")), .object(model.id("helm")),
        ])
    }

    @Test("a feature that instantiates another one replaces it below")
    func featureInstantiation() throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.process)
        let coding = try #require(model.clabject(named: "Coding"))
        let tests = try #require(coding.feature(named: "tests"))
        #expect(try tests.ontologicalType == FeatureReference(clabject: model.id("TaskKind"), name: "next"))
        let atCoding = Set(model.features(of: coding.id).map(\.feature.name))
        #expect(!atCoding.contains("next") && atCoding.contains("tests"))
        let atInstance = try model.features(of: model.id("uiCoding"))
        #expect(atInstance.first { $0.feature.name == "tests" }?.role.isSlot == true)
        #expect(atInstance.first { $0.feature.name == "tests" }?.durability == Potency(1))
        #expect(!atInstance.contains { $0.feature.name == "next" })
    }

    @Test("a feature declared again with its name refines the default for deeper instances")
    func refinement() throws {
        let text = """
            Model Commerce@2 {
              Node ProductType {
                price : double = 10.0;
              }
            }
            Commerce Store {
              ProductType Book {
                price : double = 35.0;
              }
            }
            Store Shelf {
              Book copy {}
            }
            """
        let model = try MultiLevelFixtures.model(text)
        let book = try #require(model.clabject(named: "Book"))
        #expect(try book.feature(named: "price")?.ontologicalType?.clabject == model.id("ProductType"))
        #expect(try model.values(of: "price", at: model.id("copy")) == [.real(35)])
        #expect(try model.features(of: model.id("copy")).map(\.feature.name) == ["price"])
    }

    @Test("Melanee durability and mutability govern where attributes exist and change")
    func melanee() throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.retail)
        #expect(model.potencyVariant == .melanee)
        let novel = try model.id("novel")
        let atNovel = Dictionary(uniqueKeysWithValues: model.features(of: novel).map { ($0.feature.name, $0) })
        #expect(atNovel["vat"] == nil)
        #expect(atNovel["price"]?.role.isMutable == false)
        #expect(atNovel["discount"]?.role.isMutable == true)
        #expect(model.values(of: "price", at: novel) == [.real(12)])
        #expect(model.values(of: "vat", at: novel) == [.real(20)])
        #expect(try model.potency(of: model.id("Category")) == .unbounded)
        #expect(try model.potency(of: model.id("thriller")) == .unbounded)
        #expect(try model.feature(named: "label", at: model.id("thriller"))?.role.isMutable == true)
    }

    @Test("updating a clabject replaces it in place")
    func update() throws {
        var model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        var draft = try #require(model.clabject(named: "draft"))
        draft.slots.append(DeepSlot(feature: "price", values: [.real(1)]))
        let updated = model.update(draft)
        #expect(updated)
        #expect(model.values(of: "price", at: draft.id) == [.real(1)])
        let ghost = model.update(Clabject(id: EUUID(), name: "ghost"))
        #expect(!ghost)
    }
}
