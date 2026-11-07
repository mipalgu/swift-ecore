//
// ModelFormatRegistryTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests that the format registry finds handlers by format, by file extension and by content.
@Suite("Model format registry")
struct ModelFormatRegistryTests {
    private static let ecoreDocument = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
        xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="p" nsURI="http://example.org/p" nsPrefix="p"/>
        """

    private static let xmiDocument = """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:Thing xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:p="http://example.org/p"/>
        """

    private static let jsonDocument = #"{"eClass": "http://example.org/p#//Thing"}"#

    private static let sketchDocument = """
        sketch package shapes http://example.org/shapes shp
        class Shape
        """

    private static func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: - Built-in Formats

    @Test("the built-in handlers are the formats that ModelFormat names, in order")
    func builtInHandlers() async {
        let registry = ModelFormatRegistry()
        let handlers = await registry.handlers
        #expect(handlers.map(\.identifier) == ModelFormat.allCases.map(\.rawValue))
        #expect(handlers.map(\.name) == ModelFormat.allCases.map(\.description))
        #expect(handlers.map(\.fileExtensions) == ModelFormat.allCases.map { [$0.fileExtension] })
        #expect(handlers.map(\.format) == ModelFormat.allCases.map { Optional($0) })
        #expect(handlers.map(\.role) == [
            .model, .both, .metamodel, .metamodel, .metamodel, .model, .metamodel, .metamodel, .metamodel, .metamodel,
            .metamodel, .metamodel, .metamodel, .model,
        ])
        #expect(handlers.filter { ![.km3, .emof, .uml, .emfatic, .xcore, .oclinecore, .asdl, .langium, .xtext, .sdf3].contains($0.format) }.allSatisfy { $0.priority == .generic })
        #expect(handlers.first { $0.format == .km3 }?.priority == .specific)
        #expect(handlers.first { $0.format == .emof }?.priority == .specific)
        #expect(handlers.first { $0.format == .uml }?.priority == .specific)
        #expect(handlers.first { $0.format == .emfatic }?.priority == .specific)
        #expect(handlers.first { $0.format == .xcore }?.priority == .specific)
        #expect(handlers.first { $0.format == .oclinecore }?.priority == .specific)
        for format in [ModelFormat.asdl, .langium, .xtext, .sdf3] {
            #expect(handlers.first { $0.format == format }?.priority == .specific)
        }
        let readOnly: [ModelFormat?] = [.langium, .xtext, .sdf3]
        #expect(handlers.filter { !readOnly.contains($0.format) }.allSatisfy { $0 is any WritableModelFormatHandler })
        #expect(!handlers.filter { readOnly.contains($0.format) }.contains { $0 is any WritableModelFormatHandler })
    }

    @Test("the shared registry starts with the built-in handlers")
    func sharedRegistryHasBuiltIns() async {
        for format in ModelFormat.allCases {
            #expect(await ModelFormatRegistry.shared.handler(for: format)?.identifier == format.rawValue)
        }
    }

    @Test("a built-in handler is found by its format and by its identifier regardless of case")
    func handlerByFormat() async {
        let registry = ModelFormatRegistry()
        for format in ModelFormat.allCases {
            #expect(await registry.handler(for: format)?.format == format)
            #expect(await registry.handler(identifier: format.rawValue.uppercased())?.format == format)
        }
        #expect(await registry.handler(identifier: "yaml") == nil)
    }

    @Test("a handler is found by file extension as ModelFormat finds the format", arguments: [
        "model.xmi", "model.XMI", "data/model.json", "Model.Json", "meta.ecore", "META.ECORE", "model.txt", "model",
    ])
    func handlerByExtensionMatchesModelFormat(path: String) async {
        let registry = ModelFormatRegistry()
        let url = URL(fileURLWithPath: path)
        #expect(await registry.handler(forFileExtension: url.pathExtension)?.format == ModelFormat.detect(url: url))
        #expect(await registry.handler(for: url)?.format == ModelFormat.detect(url: url))
    }

    @Test("a handler is found by content as ModelFormat detects the format", arguments: [
        ecoreDocument, xmiDocument, jsonDocument, "[]", "\u{FEFF}  <root/>", "plain text", "", "<?xml version=\"1.0\"?>",
    ])
    func handlerByContentMatchesModelFormat(text: String) async {
        let registry = ModelFormatRegistry()
        let data = Self.data(text)
        #expect(await registry.handler(recognising: data)?.format == ModelFormat.detect(data: data))
    }

    @Test("only the start of a document is examined")
    func onlyThePrefixIsExamined() async {
        let registry = ModelFormatRegistry()
        await registry.register(SketchFormatHandler())
        let padding = String(repeating: " ", count: ModelFormatRegistry.recognitionPrefixLength)
        #expect(await registry.handler(recognising: Self.data(padding + Self.sketchDocument)) == nil)
        let sliced = Self.data("xx" + Self.sketchDocument).dropFirst(2)
        #expect(await registry.handler(recognising: sliced)?.identifier == SketchSyntax.identifier)
    }

    // MARK: - Registration

    @Test("a registered handler is found by identifier, extension and content")
    func registeredHandlerIsFound() async {
        let registry = ModelFormatRegistry()
        await registry.register(SketchFormatHandler())
        #expect(await registry.handlers.map(\.identifier) == [
            "xmi", "json", "ecore", "km3", "emof", "uml", "emf", "xcore", "oclinecore", "asdl", "langium", "xtext", "sdf3",
            "mdepth", "sketch",
        ])
        #expect(await registry.handler(identifier: "Sketch")?.name == SketchSyntax.name)
        #expect(await registry.handler(forFileExtension: "SKETCH")?.identifier == SketchSyntax.identifier)
        #expect(await registry.handler(recognising: Self.data(Self.sketchDocument))?.identifier == "sketch")
        #expect(await registry.handler(recognising: Self.data(Self.xmiDocument))?.format == .xmi)
        #expect(SketchFormatHandler().format == nil)
        #expect(SketchFormatHandler().priority == .specific)
    }

    @Test("a handler registered under an existing identifier replaces the earlier one")
    func registrationReplacesSameIdentifier() async {
        let registry = ModelFormatRegistry()
        await registry.register(GreedyXMLFormatHandler(identifier: "XMI", priority: .specific))
        let handlers = await registry.handlers
        #expect(handlers.map(\.identifier) == [
            "json", "ecore", "km3", "emof", "uml", "emf", "xcore", "oclinecore", "asdl", "langium", "xtext", "sdf3", "mdepth",
            "XMI",
        ])
        #expect(await registry.handler(for: .xmi)?.name == "Greedy XML")
        #expect(await registry.handler(forFileExtension: "xmi") == nil)
    }

    @Test("a later handler that claims an extension takes precedence over an earlier one")
    func laterExtensionTakesPrecedence() async {
        let registry = ModelFormatRegistry()
        await registry.register(ExtensionOverrideFormatHandler())
        #expect(await registry.handler(forFileExtension: "xmi")?.identifier == "override")
        #expect(await registry.handler(for: .xmi)?.identifier == "xmi")
    }

    @Test("a registry can start with chosen handlers")
    func chosenHandlers() async {
        let registry = ModelFormatRegistry(handlers: [SketchFormatHandler()])
        #expect(await registry.handlers.map(\.identifier) == ["sketch"])
        #expect(await registry.handler(for: .xmi) == nil)
        #expect(ModelFormatRegistry.builtInHandlers.map(\.identifier) == [
            "xmi", "json", "ecore", "km3", "emof", "uml", "emf", "xcore", "oclinecore", "asdl", "langium", "xtext", "sdf3",
            "mdepth",
        ])
    }

    // MARK: - Priority

    @Test("a specific handler examines a document before the generic built-in handlers")
    func specificBeforeGeneric() async {
        let registry = ModelFormatRegistry()
        await registry.register(GreedyXMLFormatHandler(priority: .specific))
        #expect(await registry.handler(recognising: Self.data(Self.ecoreDocument))?.identifier == "greedy")
        #expect(await registry.handler(recognising: Self.data(Self.jsonDocument))?.format == .json)
    }

    @Test("among handlers of equal priority, the one registered later is asked first")
    func laterRegistrationFirstAmongEquals() async {
        let registry = ModelFormatRegistry()
        await registry.register(GreedyXMLFormatHandler(identifier: "first", priority: .generic))
        await registry.register(GreedyXMLFormatHandler(identifier: "second", priority: .generic))
        #expect(await registry.handler(recognising: Self.data(Self.xmiDocument))?.identifier == "second")
    }

    @Test("a handler of lower priority is asked only after the generic built-in handlers")
    func lowerPriorityAfterGeneric() async {
        let registry = ModelFormatRegistry()
        await registry.register(GreedyXMLFormatHandler(priority: ModelFormatPriority(rawValue: -1)))
        #expect(await registry.handler(recognising: Self.data(Self.xmiDocument))?.format == .xmi)
    }

    @Test("priorities are ordered by their raw values")
    func priorityOrder() {
        #expect(ModelFormatPriority.generic < .specific)
        #expect(ModelFormatPriority(rawValue: -1) < .generic)
        #expect(ModelFormatPriority.generic.rawValue == 0)
    }

    @Test("a handler that does not recognise documents is found only by name and extension")
    func defaultRecognitionIsNone() async {
        let registry = ModelFormatRegistry(handlers: [ReadOnlySketchFormatHandler()])
        #expect(await registry.handler(recognising: Self.data(Self.sketchDocument)) == nil)
        #expect(await registry.handler(forFileExtension: "rosketch")?.identifier == "readonlysketch")
    }

    // MARK: - Concurrency

    @Test("concurrent registrations and lookups leave the registry consistent")
    func concurrentAccess() async {
        let registry = ModelFormatRegistry()
        let count = 64
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<count {
                group.addTask {
                    await registry.register(GreedyXMLFormatHandler(identifier: "greedy\(index)", priority: .init(rawValue: -1)))
                }
                group.addTask {
                    let handler = await registry.handler(recognising: Self.data(Self.ecoreDocument))
                    #expect(handler?.format == .ecore)
                }
                group.addTask {
                    #expect(await registry.handler(forFileExtension: "json")?.format == .json)
                }
            }
        }
        let identifiers = await registry.handlers.map(\.identifier)
        #expect(identifiers.count == count + ModelFormat.allCases.count)
        #expect(Set(identifiers).count == identifiers.count)
    }
}
