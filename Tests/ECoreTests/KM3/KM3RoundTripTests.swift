//
// KM3RoundTripTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@Suite("Round trips")
struct KM3RoundTripTests {
    @Test("KM3 text is stable after one normalisation", arguments: [KM3Fixtures.library, KM3Fixtures.nested])
    func textRoundTrip(text: String) {
        let once = KM3Writer.write(KM3Reader.parse(text).packages).text
        let twice = KM3Writer.write(KM3Reader.parse(once).packages).text
        #expect(once == twice)
    }

    @Test("Text round trips are stable with the declared mapping too")
    func declaredTextRoundTrip() {
        let options = KM3ReadOptions.declaredDataTypes
        let once = KM3Writer.write(KM3Reader.parse(KM3Fixtures.library, sourceName: nil, options: options).packages).text
        let twice = KM3Writer.write(KM3Reader.parse(once, sourceName: nil, options: options).packages).text
        #expect(once == twice)
    }

    @Test("Packages survive writing and reading", arguments: [KM3Fixtures.library, KM3Fixtures.nested])
    func structuralRoundTrip(text: String) {
        let packages = KM3Reader.parse(text).packages
        let reread = KM3Reader.parse(KM3Writer.write(packages).text)
        #expect(reread.diagnostics.isEmpty)
        #expect(KM3Structure.describe(reread.packages) == KM3Structure.describe(packages))
    }

    @Test("Packages built in code survive writing and reading")
    func builtPackages() throws {
        let string = try #require(EcorePackage.dataType(.eString))
        let int = try #require(EcorePackage.dataType(.eInt))
        let double = try #require(EcorePackage.dataType(.eDouble))
        let date = try #require(EcorePackage.dataType(.eDate))
        let ordersID = EUUID()
        let customerID = EUUID()
        let customerClassID = EUUID()
        let orderClassID = EUUID()
        let status = EEnum(
            name: "Status", literals: [EEnumLiteral(name: "open", value: 1), EEnumLiteral(name: "closed", value: 2)])
        let placeholderOrder = EClass(id: orderClassID, name: "Order")
        let placeholderCustomer = EClass(id: customerClassID, name: "Customer")
        let party = EClass(
            name: "Party", isAbstract: true,
            eStructuralFeatures: [EAttribute(name: "name", eType: string, lowerBound: 1)])
        let customer = EClass(
            id: customerClassID, name: "Customer", eSuperTypes: [party],
            eStructuralFeatures: [
                EReference(
                    id: ordersID, name: "orders", eType: placeholderOrder, upperBound: -1, containment: true,
                    opposite: customerID),
                EAttribute(name: "tags", eType: string, upperBound: -1, ordered: false, unique: false),
            ],
            eOperations: [
                EOperation(
                    name: "total", eType: double,
                    eParameters: [EParameter(name: "since", eType: date), EParameter(name: "limit", eType: int)])
            ])
        let order = EClass(
            id: orderClassID, name: "Order",
            eStructuralFeatures: [
                EReference(
                    id: customerID, name: "customer", eType: placeholderCustomer, lowerBound: 1, opposite: ordersID,
                    container: true),
                EAttribute(name: "status", eType: status, lowerBound: 1, unique: false),
                EAttribute(name: "lines", eType: int, lowerBound: 2, upperBound: 7),
            ])
        let shop = EPackage(
            name: "Shop", nsURI: "http://example.org/shop", nsPrefix: "shop",
            eClassifiers: [party, customer, order, status],
            eSubpackages: [EPackage(name: "Extras", nsURI: "http://example.org/shop/extras", nsPrefix: "x")])
        let packages = MetamodelLinker.relinked([shop])
        let written = KM3Writer.write(packages)
        #expect(written.diagnostics.isEmpty, "\(written.diagnostics)")
        let reread = KM3Reader.parse(written.text)
        #expect(reread.diagnostics.isEmpty, "\(reread.diagnostics)")
        #expect(KM3Structure.describe(reread.packages) == KM3Structure.describe(packages))
    }
}
