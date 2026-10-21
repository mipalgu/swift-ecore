//
// DateTextTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for the text of `EDate` values in written documents.
///
/// EMF writes dates as `yyyy-MM-dd'T'HH:mm:ss.SSSZ`, which its own parser reads back;
/// the legacy layout and JSON keep the PyEcore form with six fractional digits.
@Suite("Date text")
struct DateTextTests {
    /// A date with milliseconds.
    static let date = EcoreDateCoding.date(from: "2026-01-02T03:04:05.123Z") ?? Date(timeIntervalSince1970: 0)

    /// A resource with one object whose `EDate` attribute holds ``date``.
    static func resource() async throws -> Resource {
        let set = ResourceSet()
        let package = LegacyJSONTests.cataloguePackage()
        await set.registerMetamodel(package, uri: package.nsURI)
        var catalogue = DynamicEObject(eClass: try #require(package.getEClass("Catalogue")))
        catalogue.eSet("issued", value: date)
        let resource = await set.createResource(uri: "file:///dated.xmi")
        await resource.add(catalogue)
        _ = set
        return resource
    }

    @Test("both date forms read back to the same date")
    func readsBothForms() {
        #expect(EcoreDateCoding.emfString(from: Self.date) == "2026-01-02T03:04:05.123+0000")
        #expect(EcoreDateCoding.date(from: "2026-01-02T03:04:05.123+0000") == Self.date)
        #expect(EcoreDateCoding.date(from: "2026-01-02T03:04:05.123000Z") == Self.date)
    }

    @Test("the EMF presets write the EMF date form", arguments: [XMISerializationOptions.emf, .emfWrapped])
    func emfPresets(options: XMISerializationOptions) async throws {
        let text = try await XMISerializer(options: options).serialize(try await Self.resource())
        #expect(text.contains("issued=\"2026-01-02T03:04:05.123+0000\""), "\(text)")
    }

    @Test("the legacy layout and JSON write the PyEcore date form")
    func legacyAndJSON() async throws {
        let resource = try await Self.resource()
        let text = try await XMISerializer().serialize(resource)
        #expect(text.contains("issued=\"2026-01-02T03:04:05.123000Z\""), "\(text)")
        let json = try await JSONSerializer().serialize(resource)
        #expect(json.contains("2026-01-02T03:04:05.123000Z"), "\(json)")
    }
}
