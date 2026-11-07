//
// MultiLevelFixtures.swift
// MultiLevelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import MultiLevel

/// Self-authored multi-level models that re-create published patterns.
enum MultiLevelFixtures {
    /// The product type pattern: product types (level 2), books and discs (level 1), and
    /// individual products (level 0), with a linguistic extension (`Author`).
    static let products = """
        Model Commerce@2 {
          Node ProductType {
            vat@1 : double = 7.5;
            price : double = 10.0;
            posPrice@2 : $self.price > 0$
          }
          someProducts@2 : $ProductType.allInstances()->size() >= 1$
        }

        Commerce BookStore {
          ProductType Book {
            vat = 4.0;
            pages : int;
            authors : Author[*];
          }
          ProductType Disc {
            vat = 10.0;
          }
          Node Author {
            name : String;
          }
        }

        BookStore Shop {
          Book patterns {
            price = 35.0;
            pages = 395;
            authors = [gamma, helm];
          }
          Disc album {
            price = 20.0;
          }
          Book draft {}
          Author gamma {
            name = "E. Gamma";
          }
          Author helm {
            name = "R. Helm";
          }
        }
        """

    /// An arcade game language with leap potency (`Tile`) and a deep reference (`elements`).
    static let arcade = """
        Model Arcade@2 {
          Node Tile@(2) {
            next : Tile[*];
            elements : ElementKind@0[*];
          }
          abstract Node ElementKind {}
          abstract Node CharacterKind : ElementKind {}
          Node HeroKind : CharacterKind {
            initLives@1 : int = 3;
            lives : int = 3;
            score : int = 0;
          }
          Node EvilKind : CharacterKind {}
          Node TreasureKind : ElementKind {}
        }

        Arcade Maze {
          TreasureKind Coin {
            value : int = 10;
          }
          HeroKind Muncher {
            initLives = 5;
          }
          EvilKind Phantom {}
        }

        Maze Play {
          Tile t0 {
            next = [t1];
            elements = [c0, m];
          }
          Tile t1 {
            next = [t0];
            elements = [c1, p];
          }
          Muncher m {}
          Phantom p {}
          Coin c0 {}
          Coin c1 {
            value = 20;
          }
        }
        """

    /// A process language: task and performer kinds, whose references are instantiated with
    /// cardinalities at the level below.
    static let process = """
        Model Process@2 {
          Node TaskKind {
            name@1 : String;
            duration : double;
            next : TaskKind[*];
            perfBy : PerformerKind[*];
          }
          Node PerformerKind {
            name : String;
          }
        }

        Process Software {
          TaskKind Coding {
            name = "programming";
            tests : Testing[1..*] {next};
            progs : Programmer[1..*] {perfBy};
          }
          TaskKind Testing {
            name = "testing";
          }
          PerformerKind Programmer {}
        }

        Software Project {
          Coding uiCoding {
            duration = 20.0;
            tests = [layoutTest];
            progs = [alice];
          }
          Testing layoutTest {
            duration = 2.0;
          }
          Programmer alice {
            name = "Alice";
          }
        }
        """

    /// The core of the MULTI bicycle challenge: a domain level, bicycle categories, catalogue
    /// models and physical bicycles, with a declared level-crossing reference.
    static let bicycles = """
        Model Cycling@3 {
          Node BicycleType {
            categoryName@1 : String;
            topSpeed@2 : double;
            listPrice@2 : double;
            salesPrice : double;
            serialNumber : String;
            frame : FrameType[1];
            alternative : BicycleType[0..1] {level=1};
          }
          Node FrameType {
            material@2 : String;
            weight@2 : double;
            serialNumber : String;
          }
        }

        Cycling Categories {
          BicycleType RacingBike {
            categoryName = "racing";
            racingFrame : RacingFrame[1] {frame};
          }
          BicycleType MountainBike {
            categoryName = "mountain";
          }
          FrameType RacingFrame {
            material = "carbon";
          }
        }

        Categories Catalogue {
          RacingBike Challenger {
            topSpeed = 70.0;
            listPrice = 4999.0;
          }
          RacingBike Sprinter {
            topSpeed = 65.0;
            listPrice = 3999.0;
          }
          RacingFrame AeroFrame {
            weight = 0.9;
          }
        }

        Catalogue Inventory {
          Challenger bike1 {
            salesPrice = 4599.0;
            serialNumber = "C-0001";
            racingFrame = frame1;
            alternative = Sprinter;
          }
          AeroFrame frame1 {
            serialNumber = "F-0001";
          }
        }
        """

    /// A retail language with Melanee potency: durability, mutability and unbounded potency.
    static let retail = """
        Model Retail@2 melanee {
          Node ProductType {
            vat@1/0 : double = 20.0;
            price@2/1 : double = 10.0;
            discount@2 : double = 0.0;
          }
          Node Category@* {
            label@* : String;
          }
        }

        Retail Shelf {
          ProductType Book {
            price = 12.0;
          }
          Category Fiction {
            label = "fiction";
          }
        }

        Shelf Stock {
          Book novel {
            discount = 1.5;
          }
          Fiction thriller {
            label = "thriller";
          }
        }
        """

    /// Reads a fixture, requiring that it has no errors.
    static func model(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> DeepModel {
        let result = MetaDepthReader.parse(text)
        #expect(!result.hasErrors, "\(result.diagnostics.map(\.message))", sourceLocation: sourceLocation)
        return try #require(result.model, sourceLocation: sourceLocation)
    }
}

extension DeepModel {
    /// The identifier of the clabject with a name, failing the test if there is none.
    func id(_ name: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> EUUID {
        try #require(clabject(named: name), sourceLocation: sourceLocation).id
    }
}
