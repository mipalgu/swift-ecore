//
// EMFDateFormTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// A metamodel and documents whose objects hold `EDate` values.
private enum DiaryFixture {
    /// The namespace URI of the diary package.
    static let nsURI = "http://www.example.org/diary"

    /// A diary package whose `Entry` class has single- and many-valued dates.
    static func package() -> EPackage {
        let date = EcorePackage.dataType(.eDate) ?? EDataType(name: EcoreDataType.eDate.rawValue)
        let entry = EClass(
            name: "Entry",
            eStructuralFeatures: [
                EAttribute(name: "written", eType: date),
                EAttribute(name: "reminders", eType: date, upperBound: -1),
                EAttribute(name: "started", eType: date, defaultValueLiteral: "2024-03-15"),
            ])
        return EPackage(name: "diary", nsURI: nsURI, nsPrefix: "diary", eClassifiers: [entry])
    }

    /// An instance document whose root entry carries the given XML attributes.
    ///
    /// - Parameter attributes: The XML attribute text of the root element.
    /// - Returns: The document text.
    static func document(_ attributes: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <diary:Entry xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:diary="\(nsURI)" \(attributes)/>
        """
    }

    /// Reads a document into a resource whose resource set knows the diary package.
    ///
    /// - Parameters:
    ///   - text: The document text.
    ///   - package: The diary package to register.
    /// - Returns: The resource and its root entry.
    static func read(_ text: String, package: EPackage) async throws -> (Resource, DynamicEObject) {
        let set = ResourceSet()
        await set.registerMetamodel(package, uri: package.nsURI)
        let resource = try await XMIParser(resourceSet: set).parse(text, uri: "file:///diary/entry.xmi")
        let root = try #require(await resource.getRootObjects().first as? DynamicEObject)
        return (resource, root)
    }

    /// A JSON document whose root entry carries the given members.
    ///
    /// - Parameter members: The JSON members of the root object, without braces.
    /// - Returns: The document text.
    static func json(_ members: String) -> String {
        #"{"eClass": "\#(nsURI)#//Entry", \#(members)}"#
    }

    /// Reads a JSON document into a resource whose resource set knows the diary package.
    ///
    /// - Parameters:
    ///   - text: The document text.
    ///   - package: The diary package to register.
    /// - Returns: The resource and its root entry.
    static func readJSON(_ text: String, package: EPackage) async throws -> (Resource, DynamicEObject) {
        let set = ResourceSet()
        await set.registerMetamodel(package, uri: package.nsURI)
        let resource = try await JSONParser(resourceSet: set).parse(Data(text.utf8), uri: "memory:/diary/entry.json")
        let root = try #require(await resource.getRootObjects().first as? DynamicEObject)
        return (resource, root)
    }

    /// The instant that the text denotes, as seconds since 1970 in UTC.
    ///
    /// - Parameter text: A date in a form that ``EcoreDateCoding/date(from:)`` reads.
    /// - Returns: The seconds since 1970, or `nil` if the text is not read.
    static func seconds(_ text: String) -> Double? {
        EcoreDateCoding.emfDate(from: text)?.timeIntervalSince1970
    }

    /// 2024-03-15T00:00:00Z.
    static let midnight = 1_710_460_800.0

    /// 2024-03-15T10:30:00Z.
    static let morning: Double = 1_710_498_600

    /// The lexical forms that EMF reads, with the instants they denote.
    static let emfForms: [(String, Double)] = [
        ("2024-03-15T10:30:00.250+1000", 1_710_462_600.25),
        ("2024-03-15T10:30:00.250-0530", 1_710_518_400.25),
        ("2024-03-15T10:30:00.250+10:00", 1_710_462_600.25),
        ("2024-03-15T10:30:00.250+0000", 1_710_498_600.25),
        ("2024-03-15T10:30:00.250", 1_710_498_600.25),
        ("2024-03-15T10:30:00", 1_710_498_600),
        ("2024-03-15T10:30", 1_710_498_600),
        ("2024-03-15", 1_710_460_800),
    ]

    /// Forms with ISO 8601 time zone designators, with the instants they denote.
    static let isoZones: [(String, Double)] = [
        ("2024-03-15T10:30:00Z", 1_710_498_600),
        ("2024-03-15T10:30:00+10:00", 1_710_462_600),
        ("2024-03-15T10:30Z", 1_710_498_600),
        ("2024-03-15T10:30-01:00", 1_710_502_200),
        ("2024-03-15T10:30:00.250Z", 1_710_498_600.25),
    ]

    /// XMI attribute texts, with the instants they denote.
    static let attributeTexts: [(String, Double)] = [
        ("2024-03-15", 1_710_460_800),
        ("2024-03-15T10:30:00", 1_710_498_600),
        ("2024-03-15T10:30:00.000+1000", 1_710_462_600),
    ]
}

@Suite("EDate forms that EMF reads and writes")
struct EMFDateFormTests {
    @Test("reads every lexical form that EMF reads", arguments: DiaryFixture.emfForms)
    func emfForms(_ text: String, _ expected: Double) {
        #expect(DiaryFixture.seconds(text) == expected)
    }

    @Test("reads ISO 8601 time zone designators on any form with a time", arguments: DiaryFixture.isoZones)
    func isoZones(_ text: String, _ expected: Double) {
        #expect(DiaryFixture.seconds(text) == expected)
    }

    @Test("reads everything that the general date reader reads", arguments: [
        "2025-01-02T03:04:05Z", "2025-01-02T03:04:05.123456Z", "2025-01-02T03:04:05 +10:00",
        "2025-1-2T3:4:5Z", "2025-01-02T03:04:05GMT+10", "2025-02-30T03:04:05Z",
    ])
    func superset(_ text: String) {
        #expect(EcoreDateCoding.emfDate(from: text) == EcoreDateCoding.date(from: text))
        #expect(EcoreDateCoding.emfDate(from: text) != nil)
    }

    @Test("rejects text that is not a date", arguments: [
        "", "yesterday", "15/03/2024", "2024-03", "2024-13-15", "2024-02-30", "2024-03-00",
        "2024-03-15T", "2024-03-15T10", "2024-03-15T25:00", "2024-03-15T10:60",
        "2024-03-15T10:30:00.", "2024-03-15junk", "2024-03-15T10:30junk", "2024-03-15 10:30",
    ])
    func rejects(_ text: String) {
        #expect(EcoreDateCoding.emfDate(from: text) == nil)
    }

    @Test("writes the canonical EMF form in UTC", arguments: [
        ("2024-03-15", "2024-03-15T00:00:00.000+0000"),
        ("2024-03-15T10:30", "2024-03-15T10:30:00.000+0000"),
        ("2024-03-15T10:30:00.250+1000", "2024-03-15T00:30:00.250+0000"),
        ("2024-03-15T00:30:00.000+1000", "2024-03-14T14:30:00.000+0000"),
    ])
    func canonical(_ text: String, _ written: String) throws {
        let date = try #require(EcoreDateCoding.emfDate(from: text))
        #expect(EcoreDateCoding.emfString(from: date) == written)
        #expect(EcoreDateCoding.emfDate(from: written) == date)
    }

    @Test("the Ecore factory converts dates as EMF does")
    func factory() throws {
        let type = try #require(EcorePackage.dataType(.eDate))
        let factory = EFactory(ePackage: EcorePackage.instance)
        let date = try #require(factory.createFromString(type, "2024-03-15") as? Date)
        #expect(date.timeIntervalSince1970 == DiaryFixture.midnight)
        #expect(factory.convertToString(type, date) == "2024-03-15T00:00:00.000+0000")
        #expect(factory.createFromString(type, "2024-03-15T10:30:00.000+1000") as? Date
            == Date(timeIntervalSince1970: 1_710_462_600))
        #expect(factory.createFromString(type, "2026-10-05T10:00:00Z") != nil)
        #expect(factory.createFromString(type, "yesterday") == nil)
    }

    @Test("a date default value literal denotes a date")
    func defaultLiteral() throws {
        let entry = try #require(DiaryFixture.package().getEClass("Entry"))
        let object = DynamicEObject(eClass: entry)
        #expect(object.eGetWithDefault("started") as? Date == Date(timeIntervalSince1970: DiaryFixture.midnight))
    }

    @Test("XMI attributes of type EDate are read as dates", arguments: DiaryFixture.attributeTexts)
    func readsXMI(_ text: String, _ expected: Double) async throws {
        let package = DiaryFixture.package()
        let (resource, root) = try await DiaryFixture.read(DiaryFixture.document("written=\"\(text)\""), package: package)
        #expect(root.eGet("written") as? Date == Date(timeIntervalSince1970: expected))
        #expect(ModelValidator(metamodels: [package]).validate(await resource.snapshot()).isEmpty)
    }

    @Test("many-valued XMI attributes of type EDate are read as dates")
    func readsManyValuedXMI() async throws {
        let package = DiaryFixture.package()
        let text = DiaryFixture.document(#"reminders="2024-03-15 2024-03-15T10:30:00.000+0000""#)
        let (resource, root) = try await DiaryFixture.read(text, package: package)
        #expect(root.eGet("reminders") as? [Date] == [
            Date(timeIntervalSince1970: DiaryFixture.midnight), Date(timeIntervalSince1970: DiaryFixture.morning),
        ])
        #expect(ModelValidator(metamodels: [package]).validate(await resource.snapshot()).isEmpty)
    }

    @Test("an XMI date that cannot be read is reported as an invalid value")
    func invalidXMI() async throws {
        let package = DiaryFixture.package()
        let (resource, root) = try await DiaryFixture.read(DiaryFixture.document(#"written="yesterday""#), package: package)
        #expect(root.eGet("written") as? String == "yesterday")
        let found = ModelValidator(metamodels: [package]).validate(await resource.snapshot())
        #expect(found.map(\.code) == [.invalidValue])
    }

    @Test("dates keep their instant through an EMF round trip", arguments: [XMISerializationOptions.emf, .emfWrapped])
    func roundTrip(options: XMISerializationOptions) async throws {
        let package = DiaryFixture.package()
        let original = DiaryFixture.document(
            #"written="2024-03-15T10:30:00.250+1000" reminders="2024-03-15 2024-03-16T08:00""#)
        let (resource, root) = try await DiaryFixture.read(original, package: package)
        let written = try await XMISerializer(options: options).serialize(resource)
        #expect(written.contains(#"written="2024-03-15T00:30:00.250+0000""#), "\(written)")
        #expect(written.contains("2024-03-15T00:00:00.000+0000"), "\(written)")
        #expect(written.contains("2024-03-16T08:00:00.000+0000"), "\(written)")
        let (_, reread) = try await DiaryFixture.read(written, package: package)
        #expect(reread.eGet("written") as? Date == root.eGet("written") as? Date)
        #expect(reread.eGet("reminders") as? [Date] == root.eGet("reminders") as? [Date])
    }

    @Test("dates keep their instant through a round trip in the default layout")
    func defaultLayoutRoundTrip() async throws {
        let package = DiaryFixture.package()
        let original = DiaryFixture.document(
            #"written="2024-03-15T10:30:00.250+1000" reminders="2024-03-15 2024-03-16T08:00""#)
        let (resource, root) = try await DiaryFixture.read(original, package: package)
        let written = try await XMISerializer().serialize(resource)
        let (_, reread) = try await DiaryFixture.read(written, package: package)
        #expect(reread.eGet("written") as? Date == root.eGet("written") as? Date, "\(written)")
        #expect(reread.eGet("reminders") as? [Date] == root.eGet("reminders") as? [Date], "\(written)")
    }

    @Test("JSON attributes of type EDate are read in the forms that EMF reads", arguments: DiaryFixture.attributeTexts)
    func readsJSON(_ text: String, _ expected: Double) async throws {
        let package = DiaryFixture.package()
        let (resource, root) = try await DiaryFixture.readJSON(DiaryFixture.json("\"written\": \"\(text)\""), package: package)
        #expect(root.eGet("written") as? Date == Date(timeIntervalSince1970: expected))
        #expect(ModelValidator(metamodels: [package]).validate(await resource.snapshot()).isEmpty)
    }

    @Test("many-valued JSON attributes of type EDate are read as dates")
    func readsManyValuedJSON() async throws {
        let package = DiaryFixture.package()
        let text = DiaryFixture.json(#""reminders": ["2024-03-15", "2024-03-15T10:30:00.000+0000"]"#)
        let (resource, root) = try await DiaryFixture.readJSON(text, package: package)
        #expect(root.eGet("reminders") as? [Date] == [
            Date(timeIntervalSince1970: DiaryFixture.midnight), Date(timeIntervalSince1970: DiaryFixture.morning),
        ])
        #expect(ModelValidator(metamodels: [package]).validate(await resource.snapshot()).isEmpty)
    }

    @Test("a JSON date that cannot be read is an error")
    func invalidJSON() async throws {
        let package = DiaryFixture.package()
        await #expect(throws: JSONError.self) {
            _ = try await DiaryFixture.readJSON(DiaryFixture.json(#""written": "yesterday""#), package: package)
        }
    }

    @Test("dates keep their instant through a JSON round trip")
    func jsonRoundTrip() async throws {
        let package = DiaryFixture.package()
        let original = DiaryFixture.json(
            #""written": "2024-03-15T10:30:00.250+1000", "reminders": ["2024-03-15", "2024-03-16T08:00"]"#)
        let (resource, root) = try await DiaryFixture.readJSON(original, package: package)
        let written = try await JSONSerializer().serialize(resource)
        let (_, reread) = try await DiaryFixture.readJSON(written, package: package)
        #expect(reread.eGet("written") as? Date == root.eGet("written") as? Date, "\(written)")
        #expect(reread.eGet("reminders") as? [Date] == root.eGet("reminders") as? [Date], "\(written)")
    }

    @Test("dates keep their instant from XMI through JSON back to XMI", arguments: [XMISerializationOptions(), .emf])
    func xmiJSONXMIRoundTrip(options: XMISerializationOptions) async throws {
        let package = DiaryFixture.package()
        let original = DiaryFixture.document(
            #"written="2024-03-15T10:30:00.250+1000" reminders="2024-03-15 2024-03-16T08:00""#)
        let (resource, root) = try await DiaryFixture.read(original, package: package)
        let json = try await JSONSerializer().serialize(resource)
        let (fromJSON, _) = try await DiaryFixture.readJSON(json, package: package)
        let xmi = try await XMISerializer(options: options).serialize(fromJSON)
        let (_, reread) = try await DiaryFixture.read(xmi, package: package)
        #expect(reread.eGet("written") as? Date == root.eGet("written") as? Date, "\(json)\n\(xmi)")
        #expect(reread.eGet("reminders") as? [Date] == root.eGet("reminders") as? [Date], "\(json)\n\(xmi)")
    }
}
