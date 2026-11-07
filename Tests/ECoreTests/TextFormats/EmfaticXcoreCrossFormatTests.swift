//
// EmfaticXcoreCrossFormatTests.swift
// CrossFormatTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// The same neutral shop metamodel, written once in each notation.
enum ShopMetamodel {
    /// The shop metamodel in Emfatic.
    static let emfatic = """
        @GenModel(documentation="A neutral shop metamodel")
        @namespace(uri="http://example.org/shop", prefix="shop")
        package shop;

        abstract class Named {
        	id attr String[1] name;
        }

        abstract interface Priced {
        	op double price();
        }

        class Product extends Named, Priced {
        	attr double basePrice = "0.0";
        	!unique attr String[*] tags;
        	attr Category category;
        	readonly volatile transient derived attr int stockLevel;
        }

        class Order {
        	!resolve val Line[*]#order lines;
        	ref Customer#orders customer;
        	unsettable attr EDate placed;
        	op Line[*] linesFor(Product product) throws Problem;
        }

        class Line {
        	ref Order#lines order;
        	ref Product[1] product;
        	attr int quantity = 1;
        }

        class Customer extends Named {
        	ref Order[*]#customer orders;
        }

        class Problem {
        }

        class Basket<T extends Product> {
        	ref T[*] items;
        	op T cheapest();
        }

        class ProductBasket extends Basket<Product> {
        }

        enum Category {
        	food = 0;
        	tools = 1;
        	toys = 2;
        }

        datatype Money : java.math.BigDecimal;

        transient datatype Picture : "byte[]";
        """

    /// The shop metamodel in Xcore.
    static let xcore = """
        @Ecore(nsURI="http://example.org/shop")
        @GenModel(documentation="A neutral shop metamodel")
        package shop

        abstract class Named {
        	id String[1] name
        }

        interface Priced {
        	op double price()
        }

        class Product extends Named, Priced {
        	double basePrice = "0.0"
        	String[] tags
        	Category category
        	readonly transient volatile derived int stockLevel
        }

        class Order {
        	contains Line[] lines opposite order
        	refers Customer customer opposite orders
        	unsettable Date placed
        	op unique Line[] linesFor(Product product) throws Problem
        }

        class Line {
        	container Order order opposite lines
        	refers Product[1] product
        	int quantity = "1"
        }

        class Customer extends Named {
        	refers Order[] orders opposite customer
        }

        class Problem {
        }

        class Basket<T extends Product> {
        	refers T[] items
        	op T cheapest()
        }

        class ProductBasket extends Basket<Product> {
        }

        enum Category {
        	food
        	tools = 1
        	toys = 2
        }

        type Money wraps java.math.BigDecimal

        @Ecore(serializable="false")
        type Picture wraps byte[]
        """
}

/// Tests that the two notations describe the same metamodels.
@Suite("Emfatic and Xcore cross-format")
struct EmfaticXcoreCrossFormatTests {
    /// The structure of packages, ignoring the uniqueness of single-valued elements.
    private func signature(_ packages: [EPackage]) -> String {
        MetamodelSignature.of(packages, options: .init(ignoresSingleValuedCollectionFlags: true))
    }

    /// Emfatic and Xcore texts for the same metamodel give structurally equal packages.
    @Test func sameMetamodel() {
        let emfatic = EmfaticReader.parse(ShopMetamodel.emfatic)
        let xcore = XcoreReader.parse(ShopMetamodel.xcore)
        #expect(emfatic.diagnostics.isEmpty, "\(emfatic.diagnostics.map(\.message))")
        #expect(xcore.diagnostics.isEmpty, "\(xcore.diagnostics.map(\.message))")
        #expect(signature(emfatic.packages) == signature(xcore.packages))
    }

    /// Both texts are canonical for their writers.
    @Test func bothTextsAreCanonical() {
        #expect(EmfaticWriter.write(EmfaticReader.parse(ShopMetamodel.emfatic).packages).text == ShopMetamodel.emfatic + "\n")
        #expect(XcoreWriter.write(XcoreReader.parse(ShopMetamodel.xcore).packages).text == ShopMetamodel.xcore + "\n")
    }

    /// Emfatic read, written as Xcore and read again keeps its structure, and vice versa.
    @Test func conversions() {
        let fromEmfatic = EmfaticReader.parse(ShopMetamodel.emfatic).packages
        let asXcore = XcoreWriter.write(fromEmfatic)
        #expect(asXcore.diagnostics.isEmpty, "\(asXcore.diagnostics.map(\.message))")
        #expect(asXcore.text == ShopMetamodel.xcore + "\n")
        #expect(signature(XcoreReader.parse(asXcore.text).packages) == signature(fromEmfatic))

        let fromXcore = XcoreReader.parse(ShopMetamodel.xcore).packages
        let asEmfatic = EmfaticWriter.write(fromXcore)
        #expect(asEmfatic.diagnostics.isEmpty, "\(asEmfatic.diagnostics.map(\.message))")
        #expect(signature(EmfaticReader.parse(asEmfatic.text).packages) == signature(fromXcore))
    }

    /// The outlines of both notations have the same shape.
    @Test func outlinesAgree() {
        func shape(_ nodes: [OutlineNode]) -> [String] {
            nodes.flatMap { ["\($0.kind):\($0.name)"] + shape($0.children).map { "  " + $0 } }
        }
        let emfatic = shape(EmfaticReader.parse(ShopMetamodel.emfatic).outline)
        let xcore = shape(XcoreReader.parse(ShopMetamodel.xcore).outline)
        #expect(emfatic == xcore)
    }
}
