//
// ModelIOEncodingTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests that models are saved in a chosen character encoding.
@Suite("Saving models in a character encoding")
struct ModelIOEncodingTests {
    /// A metamodel whose names and documentation hold characters outside ASCII.
    private static let metamodel = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
        xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="caf\u{E9}" \
        nsURI="http://example.org/cafe" nsPrefix="cafe">
          <eClassifiers xsi:type="ecore:EClass" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" name="Men\u{FC}">
            <eAnnotations source="http://www.eclipse.org/emf/2002/GenModel">
              <details key="documentation" value="Costs 5 \u{20AC}, served \u{2603}"/>
            </eAnnotations>
          </eClassifiers>
        </ecore:EPackage>

        """

    /// A fresh temporary directory, removed by the caller.
    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelIOEncodingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Loads the metamodel.
    private static func loaded() async throws -> Resource {
        try await ModelIO.load(data: Data(metamodel.utf8), uri: "memory:/cafe.ecore", resourceSet: ResourceSet()).resource
    }

    @Test("Saving in UTF-8 writes exactly the bytes of saving without an encoding", arguments: ["ecore", "xmi", "km3", "emf", "json"])
    func utf8Unchanged(extension: String) async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resource = try await Self.loaded()
        let plain = directory.appendingPathComponent("plain.\(`extension`)")
        let encoded = directory.appendingPathComponent("encoded.\(`extension`)")
        try await ModelIO.save(resource, to: plain)
        var diagnostics = ConversionDiagnostics()
        let used = try await ModelIO.save(resource, to: encoded, encoding: .utf8, diagnostics: &diagnostics)
        #expect(used == .utf8)
        #expect(try Data(contentsOf: encoded) == Data(contentsOf: plain))
    }

    @Test("An Ecore document in ISO-8859-1 declares it and refers to other characters by number")
    func latin1Ecore() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("cafe.ecore")
        var diagnostics = ConversionDiagnostics()
        let used = try await ModelIO.save(try await Self.loaded(), to: target, encoding: .isoLatin1, diagnostics: &diagnostics)
        #expect(used == .isoLatin1)
        let bytes = try Data(contentsOf: target)
        let text = try #require(TextEncoding.isoLatin1.decode(bytes))
        #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>"))
        #expect(bytes.contains(0xE9))
        #expect(text.contains("name=\"caf\u{E9}\""))
        #expect(text.contains("Costs 5 &#x20AC;, served &#x2603;"))
        let reloaded = try await ModelIO.load(url: target, resourceSet: ResourceSet())
        let package = try #require(reloaded.packages.first)
        #expect(package.name == "caf\u{E9}")
    }

    @Test("A textual notation in an encoding that cannot hold a character is an error and writes no file")
    func unrepresentableText() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("cafe.emf")
        var diagnostics = ConversionDiagnostics()
        let resource = try await Self.loaded()
        await #expect(throws: TextEncodingError.self) {
            try await ModelIO.save(resource, to: target, encoding: .usASCII, diagnostics: &diagnostics)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        let latin = directory.appendingPathComponent("cafe.km3")
        try await ModelIO.save(resource, to: latin, encoding: .isoLatin1, diagnostics: &diagnostics)
        #expect(try Data(contentsOf: latin).contains(0xE9))
    }

    @Test("JSON is written in UTF-8 whatever encoding is asked for")
    func jsonStaysUTF8() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resource = try await Self.loaded()
        let plain = directory.appendingPathComponent("plain.json")
        let target = directory.appendingPathComponent("cafe.json")
        try await ModelIO.save(resource, to: plain)
        var diagnostics = ConversionDiagnostics()
        let used = try await ModelIO.save(resource, to: target, encoding: .isoLatin1, diagnostics: &diagnostics)
        #expect(used == .utf8)
        #expect(try Data(contentsOf: target) == Data(contentsOf: plain))
    }

    @Test("The kind of a document follows its format and contents")
    func documentKinds() {
        #expect(ModelIO.documentKind(of: "{}", identifier: "json") == .json)
        #expect(ModelIO.documentKind(of: "{}", identifier: "JSON") == .json)
        #expect(ModelIO.documentKind(of: "<?xml version=\"1.0\"?><a/>", identifier: "ecore") == .xml)
        #expect(ModelIO.documentKind(of: "package a;", identifier: "km3") == .text)
    }
}
