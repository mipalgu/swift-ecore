//
// DeepModelValidationTests.swift
// MultiLevelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import MultiLevel

/// Tests the structural validation of deep models.
@Suite("Deep model validation")
struct DeepModelValidationTests {
    /// The codes of the structural diagnostics of a text, which must read without errors.
    static func codes(_ text: String, policy: LevelCrossingPolicy = .strict) throws -> [String] {
        var model = try MultiLevelFixtures.model(text)
        model.levelCrossing = policy
        return model.validateStructure().map(\.code)
    }

    /// The messages of the structural diagnostics of a text.
    static func messages(_ text: String) throws -> [String] {
        try MultiLevelFixtures.model(text).validateStructure().map(\.message)
    }

    @Test("every fixture is structurally valid", arguments: MetaDepthTextTests.fixtures)
    func fixturesAreValid(text: String) throws {
        let diagnostics = try MultiLevelFixtures.model(text).validateStructure()
        #expect(diagnostics.isEmpty, "\(diagnostics.map(\.message))")
    }

    // MARK: - Strictness

    static let crossing = """
        Model Cycling@2 {
          Node BicycleType {
            alternative : BicycleType[0..1];
          }
        }
        Cycling Catalogue {
          BicycleType Racer {}
        }
        Catalogue Inventory {
          Racer bike {
            alternative = Racer;
          }
        }
        """

    @Test("an undeclared level crossing is an error under the strict policy")
    func undeclaredCrossingIsStrictError() throws {
        let messages = try Self.messages(Self.crossing)
        #expect(messages.contains { $0.contains("refers to 'Catalogue.Racer' at level 1") })
        #expect(try Self.codes(Self.crossing) == [MultiLevelDiagnosticCode.levelCrossing])
    }

    @Test("the non-strict policy lets any reference cross levels")
    func nonStrictAdmitsCrossing() throws {
        #expect(try Self.codes(Self.crossing, policy: .nonStrict).isEmpty)
    }

    @Test("a declared level-crossing reference must reach exactly its declared level")
    func declaredCrossing() throws {
        let declared = Self.crossing.replacingOccurrences(of: "[0..1];", with: "[0..1] {level=1};")
        #expect(try Self.codes(declared).isEmpty)
        let wrongLevel = Self.crossing.replacingOccurrences(of: "[0..1];", with: "[0..1] {level=0};")
        #expect(try Self.codes(wrongLevel) == [MultiLevelDiagnosticCode.levelCrossing])
        let missingLevel = Self.crossing.replacingOccurrences(of: "[0..1];", with: "[0..1] {level=5};")
        #expect(try Self.codes(missingLevel).contains(MultiLevelDiagnosticCode.levelCrossing))
    }

    @Test("deep references accept only targets of the declared potency")
    func deepReferencePotency() throws {
        let text = MultiLevelFixtures.arcade.replacingOccurrences(of: "elements = [c1, p];", with: "elements = [Coin];")
        let messages = try Self.messages(text)
        #expect(messages == ["'Maze.Coin' in the deep reference 'Play.t1.elements' must have potency 0"])
    }

    @Test("reference targets must be deep instances of the target type")
    func referenceTargetType() throws {
        let text = MultiLevelFixtures.arcade.replacingOccurrences(of: "next = [t1];", with: "next = [m];")
        #expect(try Self.codes(text) == [MultiLevelDiagnosticCode.referenceTarget])
    }

    // MARK: - Instantiation

    @Test("a clabject of potency zero cannot be instantiated")
    func potencyZero() throws {
        let text = """
            Model M@2 {
              Node A@1 {}
            }
            M N {
              A a {}
            }
            N O {
              a x {}
            }
            """
        #expect(try Self.codes(text).contains(MultiLevelDiagnosticCode.notInstantiable))
    }

    @Test("abstract clabjects and misplaced leap instances are rejected")
    func abstractAndLeap() throws {
        let abstract = MultiLevelFixtures.arcade.replacingOccurrences(
            of: "EvilKind Phantom {}", with: "EvilKind Phantom {}\n  ElementKind Thing {}")
        #expect(try Self.messages(abstract).contains("'Maze.Thing' instantiates the abstract clabject 'Arcade.ElementKind'"))
        let leap = MultiLevelFixtures.arcade.replacingOccurrences(of: "EvilKind Phantom {}", with: "EvilKind Phantom {}\n  Tile Room {}")
        #expect(try Self.codes(leap).contains(MultiLevelDiagnosticCode.typeLevel))
    }

    @Test("a strict model rejects linguistic extensions")
    func strictModelRejectsExtensions() throws {
        let text = MultiLevelFixtures.products.replacingOccurrences(of: "Commerce BookStore {", with: "strict Commerce BookStore {")
        let codes = try Self.codes(text)
        #expect(codes.filter { $0 == MultiLevelDiagnosticCode.linguisticExtension }.count == 3)
    }

    @Test("type-facet names must be unique along the instantiation chain")
    func typeFacetNames() throws {
        let text = MultiLevelFixtures.products.replacingOccurrences(of: "Node Author {", with: "Node ProductType {")
            .replacingOccurrences(of: "Author[*]", with: "ProductType[*]")
            .replacingOccurrences(of: "Author gamma", with: "ProductType gamma")
            .replacingOccurrences(of: "Author helm", with: "ProductType helm")
        let result = MetaDepthReader.parse(text)
        let model = try #require(result.model)
        #expect(model.validateStructure().contains { $0.code == MultiLevelDiagnosticCode.duplicateName })
    }

    @Test("generalisation stays within one level, keeps potency and has no cycles")
    func inheritance() throws {
        let text = """
            Model M@2 {
              Node A : B {}
              Node B : A {}
              Node C@1 {}
              Node D : C {}
            }
            """
        let codes = try Self.codes(text)
        #expect(codes.filter { $0 == MultiLevelDiagnosticCode.inheritance }.count == 3)
    }

    @Test("potencies above the level and unbounded potencies outside Melanee are rejected")
    func potencyBounds() throws {
        let text = """
            Model M@1 {
              Node A@2 {
                x@* : int;
              }
              Node B@* {
                y@1/0 : int;
              }
            }
            """
        let messages = try Self.messages(text)
        #expect(messages.contains("'M.A' has potency 2 but is at level 1"))
        #expect(messages.contains("'M.A.x' has an unbounded potency, which metadepth potency does not permit"))
        #expect(messages.contains("'M.B' has an unbounded potency, which metadepth potency does not permit"))
        #expect(messages.contains("'M.B.y' declares a mutability, which metadepth potency does not permit"))
    }

    // MARK: - Slots

    @Test("a slot needs a visible, mutable feature and values of its type")
    func slots() throws {
        let invisible = MultiLevelFixtures.products.replacingOccurrences(of: "price = 35.0;", with: "vat = 1.0;")
        #expect(try Self.messages(invisible) == ["no feature 'vat' is visible at 'Shop.patterns'"])
        let wrongType = MultiLevelFixtures.products.replacingOccurrences(of: "price = 35.0;", with: "price = \"dear\";")
        #expect(try Self.codes(wrongType) == [MultiLevelDiagnosticCode.valueType])
        let notObject = MultiLevelFixtures.products.replacingOccurrences(of: "authors = [gamma, helm];", with: "authors = [3];")
        #expect(try Self.codes(notObject) == [MultiLevelDiagnosticCode.valueType])
    }

    @Test("Melanee mutability fixes values below the levels where they may change")
    func melaneeMutability() throws {
        let fixedVat = MultiLevelFixtures.retail.replacingOccurrences(of: "price = 12.0;", with: "price = 12.0;\n    vat = 5.0;")
        #expect(try Self.messages(fixedVat) == ["'vat' cannot be changed at 'Shelf.Book'"])
        let fixedPrice = MultiLevelFixtures.retail.replacingOccurrences(of: "discount = 1.5;", with: "price = 1.0;")
        #expect(try Self.messages(fixedPrice) == ["'price' cannot be changed at 'Stock.novel'"])
    }

    @Test("cardinalities of instantiated references apply at the level below")
    func multiplicities() throws {
        let missing = MultiLevelFixtures.process.replacingOccurrences(of: "tests = [layoutTest];", with: "")
        #expect(try Self.messages(missing) == ["'Project.uiCoding.tests' holds 0 values, at least 1 are required"])
        let tooMany = MultiLevelFixtures.bicycles.replacingOccurrences(
            of: "alternative = Sprinter;", with: "alternative = [Sprinter, Challenger];")
        #expect(try Self.codes(tooMany) == [MultiLevelDiagnosticCode.multiplicity])
        let frameless = MultiLevelFixtures.bicycles.replacingOccurrences(of: "racingFrame = frame1;", with: "")
        #expect(try Self.codes(frameless) == [MultiLevelDiagnosticCode.multiplicity])
    }

    @Test("an instantiating feature must keep the kind and target of the feature it instantiates")
    func instantiatedFeatureTypes() throws {
        let text = MultiLevelFixtures.process.replacingOccurrences(of: "tests : Testing[1..*] {next};", with: "tests : alice[1..*] {next};")
        #expect(try MetaDepthReader.parse(text).model?.validateStructure().map(\.code).contains(MultiLevelDiagnosticCode.referenceTarget) == true)
        let kind = MultiLevelFixtures.process.replacingOccurrences(of: "tests : Testing[1..*] {next};", with: "tests : int {next};")
        #expect(try Self.codes(kind).contains(MultiLevelDiagnosticCode.valueType))
    }

    // MARK: - Edges and Constraints

    @Test("edge ends must instantiate the ends of the edge type at the same level")
    func edges() throws {
        let text = """
            Model Library@2 {
              Node Writer { books : Volume[*]; }
              Node Volume {}
              Edge Writes(Writer.books, Volume.missing) {}
            }
            Library Catalogue {
              Writer author {}
              Volume novel {}
              Writes credit(novel, author) {}
              Node plain(author, novel) {}
            }
            """
        let messages = try Self.messages(text)
        #expect(messages.contains("'Library.Volume' of edge 'Library.Writes' has no feature 'missing'"))
        #expect(messages.contains("the ends of 'Catalogue.credit' do not instantiate the ends of 'Library.Writes'"))
    }

    @Test("constraint potency is bounded by its holder and bodies must be AQL")
    func constraints() throws {
        var model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        model.levels[1].constraints = [
            DeepConstraint(name: "tooDeep", potency: Potency(3), body: "true"),
            DeepConstraint(name: "eol", body: "self.x := 1"),
            DeepConstraint(name: "ocl", body: "true", language: "ocl"),
        ]
        let messages = model.validateStructure().map(\.message)
        #expect(messages.contains("constraint 'tooDeep' of 'BookStore' has potency 3, more than its holder (1)"))
        #expect(messages.contains("constraint 'eol' of 'BookStore' uses ':=', which is EOL"))
        #expect(messages.contains("constraint 'ocl' of 'BookStore' is written in ocl; only AQL is supported"))
    }

    @Test("the level chain must link each model to the one above")
    func chain() throws {
        var model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        model.levels[2].typeModel = "Commerce"
        model.levels[1].potency = Potency(5)
        model.levels[0].potency = nil
        let codes = model.validateStructure().map(\.code)
        #expect(codes.contains(MultiLevelDiagnosticCode.levelChain))
        #expect(codes.contains(MultiLevelDiagnosticCode.potency))
    }
}
