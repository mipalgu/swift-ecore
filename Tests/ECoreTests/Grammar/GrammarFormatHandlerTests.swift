//
// GrammarFormatHandlerTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that ASDL descriptions, Langium and Xtext grammars and SDF3 definitions are
/// recognised and read through ``ModelIO`` and the ``ModelFormatRegistry``, and that ASDL is
/// written.
@Suite("Grammar importers through the format registry")
struct GrammarFormatHandlerTests {
    /// The formats of the grammar importers with their fixtures.
    static let fixtures: [(format: ModelFormat, text: String)] = [
        (.asdl, ArithmeticFixtures.asdl), (.langium, ArithmeticFixtures.langium),
        (.xtext, ArithmeticFixtures.xtext), (.sdf3, ArithmeticFixtures.sdf3),
    ]

    /// The formats that are read but not written.
    static let readOnly: [ModelFormat] = [.langium, .xtext, .sdf3]

    /// A new temporary directory, which the caller removes.
    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrammarFormatHandlerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Reads a fixture with the reader of its format, called directly.
    static func direct(_ format: ModelFormat, _ text: String, sourceName: String) -> (packages: [EPackage], diagnostics: [SourceDiagnostic]) {
        switch format {
        case .asdl:
            let result = ASDLReader.parse(text, sourceName: sourceName)
            return (result.packages, result.diagnostics)
        case .langium:
            let result = LangiumReader.parse(text, sourceName: sourceName)
            return (result.packages, result.diagnostics)
        case .xtext:
            let result = XtextReader.parse(text, sourceName: sourceName)
            return (result.packages, result.diagnostics)
        default:
            let result = SDF3Reader.parse(text, sourceName: sourceName)
            return (result.packages, result.diagnostics)
        }
    }

    // MARK: - Formats

    @Test("the grammar formats are named by their file extensions and names")
    func formatsAreNamed() {
        #expect(ModelFormat.asdl.fileExtension == "asdl")
        #expect(ModelFormat.langium.fileExtension == "langium")
        #expect(ModelFormat.xtext.fileExtension == "xtext")
        #expect(ModelFormat.sdf3.fileExtension == "sdf3")
        #expect([ModelFormat.asdl, .langium, .xtext, .sdf3].map(\.description) == ["ASDL", "Langium", "Xtext", "SDF3"])
        #expect(ModelFormat(fileExtension: "SDF3") == .sdf3)
        #expect(ModelFormat.detect(url: URL(fileURLWithPath: "Python.asdl")) == .asdl)
    }

    @Test("the fixtures are recognised by their contents", arguments: [0, 1, 2, 3])
    func fixturesAreRecognised(index: Int) async {
        let (format, text) = Self.fixtures[index]
        let data = Data(text.utf8)
        #expect(ModelFormat.detect(data: data) == format)
        #expect(await ModelFormatRegistry().handler(recognising: data)?.format == format)
    }

    @Test("ASDL is told apart from SDF3 by what follows the module name", arguments: [
        ("-- Arithmetic\nmodule Arith version \"1.0\" { expr = Num(int n) }", ModelFormat.asdl),
        ("module Python (imports Base) { mod = Module(stmt* body) }", .asdl),
        ("module lang/Shapes\nimports Common\ncontext-free syntax\n  Shape.Circle = <circle>", .sdf3),
        ("// Signatures\nmodule signatures/Arith-sig\nsignature\n  constructors\n    Num : INT -> Expr", .sdf3),
        ("module Arith\nsorts Expr", .sdf3),
    ])
    func moduleNotationsAreToldApart(text: String, format: ModelFormat) {
        #expect(ASDLSyntax.looksLikeASDL(text) == (format == .asdl))
        #expect(SDF3Syntax.looksLikeSDF3(text) == (format == .sdf3))
        #expect(ModelFormat.detect(data: Data(text.utf8)) == format)
    }

    @Test("Xtext is told apart from Langium by what follows the grammar name", arguments: [
        ("grammar org.example.Arith with org.eclipse.xtext.common.Terminals\ngenerate arith \"x\"", ModelFormat.xtext),
        ("grammar Arith with org.eclipse.xtext.common.Terminals\nExpr: Num;", .xtext),
        ("grammar Arith\ngenerate arith \"http://example.org/arith\"\nExpr: Num;", .xtext),
        ("grammar Arith\nimport \"http://www.eclipse.org/emf/2002/Ecore\" as ecore\nExpr: Num;", .xtext),
        ("grammar Arith hidden(WS, ML_COMMENT)\nExpr: Num;", .xtext),
        ("/* Arithmetic */\ngrammar Arith\nentry Expr: Num;", .langium),
        ("grammar Arith with Terminals\nimport './terminals';\nentry Expr: Num;", .langium),
        ("grammar Arith\ninterface Expr {}\ntype Value = Expr;", .langium),
    ])
    func grammarNotationsAreToldApart(text: String, format: ModelFormat) {
        #expect(XtextSyntax.looksLikeXtext(text) == (format == .xtext))
        #expect(LangiumSyntax.looksLikeLangium(text) == (format == .langium))
        #expect(ModelFormat.detect(data: Data(text.utf8)) == format)
    }

    @Test("other text is taken for none of the grammar formats", arguments: [
        "module Arith", "module Arith =", "module { }", "grammar Arith", "grammar", "grammar Arith import",
        "module module {", "plain text", "",
    ])
    func otherTextIsNotRecognised(text: String) {
        #expect(!ASDLSyntax.looksLikeASDL(text))
        #expect(!SDF3Syntax.looksLikeSDF3(text))
        #expect(!XtextSyntax.looksLikeXtext(text))
        #expect(!LangiumSyntax.looksLikeLangium(text))
        #expect(ModelFormat.detect(data: Data(text.utf8)) == nil)
    }

    @Test("the grammar handlers are metamodel handlers of specific priority, and only ASDL writes")
    func handlersAreDescribed() async throws {
        let registry = ModelFormatRegistry()
        for (format, _) in Self.fixtures {
            let handler = try #require(await registry.handler(for: format))
            #expect(handler.role == .metamodel)
            #expect(handler.priority == .specific)
            #expect((handler is any WritableModelFormatHandler) == !Self.readOnly.contains(format))
        }
    }

    // MARK: - Reading and Writing

    @Test("each grammar loads through ModelIO as its reader reads it", arguments: [0, 1, 2, 3])
    func grammarsLoad(index: Int) async throws {
        let (format, text) = Self.fixtures[index]
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Arith.\(format.fileExtension)")
        try text.write(to: url, atomically: true, encoding: .utf8)
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(url: url, resourceSet: resourceSet)
        let direct = Self.direct(format, text, sourceName: URIReference.canonicalise(url.absoluteString))
        #expect(loaded.format == format)
        #expect(loaded.formatIdentifier == format.rawValue)
        #expect(await loaded.resource.loadDiagnostics == direct.diagnostics)
        #expect(XMISerializer(options: .emf).serialize(loaded.packages)
            == XMISerializer(options: .emf).serialize(direct.packages))
        for package in loaded.packages where !package.nsURI.isEmpty {
            #expect(await resourceSet.getMetamodel(uri: package.nsURI)?.id == package.id)
        }
        #expect(!loaded.packages.isEmpty)
    }

    @Test("a model is read with the classes of a metamodel inferred from a grammar")
    func modelsUseGrammarMetamodels() async throws {
        let resourceSet = ResourceSet()
        let metamodel = try await ModelIO.load(
            data: Data(ArithmeticFixtures.langium.utf8), uri: "memory:/Arith.langium", resourceSet: resourceSet)
        let package = try #require(metamodel.packages.first)
        let model = """
            <?xml version="1.0" encoding="UTF-8"?>
            <\(package.nsPrefix):Var xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
            xmlns:\(package.nsPrefix)="\(package.nsURI)" name="x"/>
            """
        let loaded = try await ModelIO.load(data: Data(model.utf8), uri: "memory:/x.xmi", resourceSet: resourceSet)
        let root = try #require(await loaded.resource.getRootObjects().first)
        #expect(root.eClass.id == package.getEClass("Var")?.id)
        #expect(loaded.diagnostics.warnings.isEmpty)
    }

    @Test("an ASDL metamodel is written as ASDLWriter writes it and read back")
    func asdlRoundTrips() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = try await ModelIO.load(
            data: Data(ArithmeticFixtures.asdl.utf8), uri: "memory:/Arith.asdl", resourceSet: ResourceSet())
        var diagnostics = ConversionDiagnostics()
        let text = try await ModelIO.serialise(loaded.resource, format: .asdl, diagnostics: &diagnostics)
        #expect(text == ASDLWriter.write(loaded.packages).text)
        let url = directory.appendingPathComponent("copy.asdl")
        try await ModelIO.save(loaded.resource, to: url)
        let reloaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
        let names = { (packages: [EPackage]) in packages.flatMap { $0.eClassifiers.map(\.name) }.sorted() }
        #expect(names(reloaded.packages) == names(loaded.packages))
    }

    @Test("a metamodel is not written as a read-only grammar format", arguments: [ModelFormat.langium, .xtext, .sdf3])
    func readOnlyFormatsAreNotWritten(format: ModelFormat) async throws {
        let loaded = try await ModelIO.load(
            data: Data(ArithmeticFixtures.asdl.utf8), uri: "memory:/Arith.asdl", resourceSet: ResourceSet())
        var diagnostics = ConversionDiagnostics()
        await #expect(throws: ModelFormatError.unwritableFormat(format.description)) {
            try await ModelIO.serialise(loaded.resource, format: format, diagnostics: &diagnostics)
        }
    }

    @Test("the import options of the load options apply", arguments: [0, 1, 2, 3])
    func importOptionsApply(index: Int) async throws {
        let (format, text) = Self.fixtures[index]
        let uri = "http://example.org/imported"
        let options = EcoreLoadOptions(
            asdlOptions: ASDLImportOptions(packageName: "imported", nsURI: uri, nsPrefix: "imp"),
            langiumOptions: LangiumImportOptions(packageName: "imported", nsURI: uri, nsPrefix: "imp"),
            xtextOptions: XtextImportOptions(packageName: "imported", nsURI: uri, nsPrefix: "imp"),
            sdf3Options: SDF3ImportOptions(packageName: "imported", nsURI: uri, nsPrefix: "imp"))
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(
            data: Data(text.utf8), uri: "memory:/Arith", format: format, resourceSet: resourceSet,
            options: ModelIO.LoadOptions(ecoreLoadOptions: options))
        #expect(loaded.packages.map(\.nsURI).contains(uri))
        #expect(await resourceSet.getMetamodel(uri: uri) != nil)
    }

    @Test("the metamodels of a load may be grammars")
    func grammarsAreRegisteredAsMetamodels() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var urls: [URL] = []
        for (format, text) in Self.fixtures {
            let url = directory.appendingPathComponent("Arith.\(format.fileExtension)")
            try text.write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
        }
        let packages = try await ModelIO.registerMetamodels(at: urls, in: ResourceSet())
        #expect(packages.count >= Self.fixtures.count)
    }
}
