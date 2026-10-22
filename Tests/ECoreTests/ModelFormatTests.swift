//
// ModelFormatTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation
import Testing

@testable import ECore

/// Tests that model formats are recognised from file names and from document contents.
@Suite("Model format detection")
struct ModelFormatTests {
    private static let ecoreHeader = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
        xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="p" nsURI="http://example.org/p" nsPrefix="p"/>
        """

    private static func data(_ text: String) -> Data { Data(text.utf8) }

    /// A file in a fresh temporary directory that holds the given text.
    private static func temporaryFile(named name: String, containing text: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelFormatTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: testWritesAtomically, encoding: .utf8)
        return url
    }

    // MARK: - Cases

    @Test("the raw value of each format is its file extension")
    func rawValuesAreExtensions() {
        #expect(ModelFormat.allCases == [.xmi, .json, .ecore])
        #expect(ModelFormat.allCases.map(\.rawValue) == ["xmi", "json", "ecore"])
        #expect(ModelFormat.allCases.map(\.fileExtension) == ["xmi", "json", "ecore"])
        #expect(ModelFormat.allCases.map(\.description) == ["XMI", "JSON", "Ecore"])
    }

    @Test("a format name is recognised regardless of case", arguments: [
        ("xmi", ModelFormat.xmi), ("XMI", .xmi), ("Json", .json), ("ECORE", .ecore),
    ])
    func formatNamesIgnoreCase(name: String, format: ModelFormat) {
        #expect(ModelFormat(fileExtension: name) == format)
    }

    @Test("an unknown format name is not recognised")
    func unknownFormatName() {
        #expect(ModelFormat(fileExtension: "yaml") == nil)
        #expect(ModelFormat(fileExtension: "") == nil)
    }

    // MARK: - File Names

    @Test("the format of a file is detected from its extension regardless of case", arguments: [
        ("model.xmi", ModelFormat.xmi), ("model.XMI", .xmi), ("data/model.json", .json),
        ("Model.Json", .json), ("meta.ecore", .ecore), ("META.ECORE", .ecore),
    ])
    func detectsFormatFromExtension(path: String, format: ModelFormat) {
        #expect(ModelFormat.detect(url: URL(fileURLWithPath: path)) == format)
    }

    @Test("a file without a known extension has no detected format")
    func unknownExtensionIsNotDetected() {
        #expect(ModelFormat.detect(url: URL(fileURLWithPath: "model.txt")) == nil)
        #expect(ModelFormat.detect(url: URL(fileURLWithPath: "model")) == nil)
    }

    // MARK: - Contents

    @Test("an Ecore package document is detected as Ecore")
    func detectsEcoreDocument() {
        #expect(ModelFormat.detect(data: Self.data(Self.ecoreHeader)) == .ecore)
    }

    @Test("an Ecore package with another prefix, comments and a byte order mark is detected as Ecore")
    func detectsEcoreWithOtherPrefix() {
        let text = "\u{FEFF}\n<!-- a comment -->\n<?xml-stylesheet href=\"x\"?>\n"
            + "<meta:EPackage xmlns:meta='http://www.eclipse.org/emf/2002/Ecore' name='p'>\n</meta:EPackage>"
        #expect(ModelFormat.detect(data: Self.data(text)) == .ecore)
    }

    @Test("an XMI wrapper around Ecore packages is detected as Ecore")
    func detectsWrappedEcorePackages() {
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore">
              <ecore:EPackage name="a" nsURI="http://example.org/a" nsPrefix="a"/>
              <ecore:EPackage name="b" nsURI="http://example.org/b" nsPrefix="b"/>
            </xmi:XMI>
            """
        #expect(ModelFormat.detect(data: Self.data(text)) == .ecore)
    }

    @Test("a package element of a namespace other than Ecore is detected as XMI")
    func packageOfOtherNamespaceIsXMI() {
        let text = "<p:EPackage xmlns:p=\"http://example.org/not-ecore\" name=\"p\"/>"
        #expect(ModelFormat.detect(data: Self.data(text)) == .xmi)
    }

    @Test("any other XML document is detected as XMI")
    func detectsInstanceDocument() {
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <lib:Library xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
            xmlns:lib="http://example.org/library" name="City"/>
            """
        #expect(ModelFormat.detect(data: Self.data(text)) == .xmi)
        #expect(ModelFormat.detect(data: Self.data("<Library/>")) == .xmi)
    }

    @Test("a document that starts with an object or an array is detected as JSON", arguments: [
        "{\"eClass\": \"http://example.org/library#//Library\"}", "  \n[ ]", "\u{FEFF}{}",
    ])
    func detectsJSON(text: String) {
        #expect(ModelFormat.detect(data: Self.data(text)) == .json)
    }

    @Test("a document in no known format is not detected", arguments: ["", "   ", "name: value", "\u{FEFF}"])
    func unknownContentsAreNotDetected(text: String) {
        #expect(ModelFormat.detect(data: Self.data(text)) == nil)
    }

    @Test("the format of a file is detected from its contents whatever its name")
    func detectsFormatOfFileContents() throws {
        let ecore = try Self.temporaryFile(named: "metamodel.txt", containing: Self.ecoreHeader)
        let json = try Self.temporaryFile(named: "model.xmi", containing: "[{\"eClass\": \"Thing\"}]")
        defer {
            try? FileManager.default.removeItem(at: ecore.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: json.deletingLastPathComponent())
        }
        #expect(try ModelFormat.detect(contentsOf: ecore) == .ecore)
        #expect(try ModelFormat.detect(contentsOf: json) == .json)
    }

    @Test("detecting the contents of a missing file throws")
    func missingFileThrows() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelFormatTests-missing-\(UUID().uuidString).xmi")
        #expect(throws: (any Error).self) { try ModelFormat.detect(contentsOf: missing) }
    }

    // MARK: - Errors

    @Test("a format error names the document and the formats that are supported")
    func errorDescription() {
        let error = ModelFormatError.undetectableFormat("model.txt")
        #expect(error.description.contains("model.txt"))
        for format in ModelFormat.allCases { #expect(error.description.contains(format.rawValue)) }
        #expect(error.errorDescription == error.description)
        #expect(ModelFormatError.unsupportedFormat("yaml").description.contains("yaml"))
    }
}
