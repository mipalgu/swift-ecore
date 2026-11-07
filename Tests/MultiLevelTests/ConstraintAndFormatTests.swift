//
// ConstraintAndFormatTests.swift
// MultiLevelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Synchronization
import Testing

@testable import MultiLevel

/// An evaluator that records its evaluations and answers from a table.
final class RecordingEvaluator: DeepConstraintEvaluator {
    /// The constraint names that are violated, and those whose evaluation fails.
    let violated: Set<String>
    let failing: Set<String>
    private let recorded = Mutex<[String]>([])

    init(violated: Set<String> = [], failing: Set<String> = []) {
        self.violated = violated
        self.failing = failing
    }

    /// The evaluations, as `constraint@level:subject`.
    var evaluations: [String] { recorded.withLock { $0 } }

    func evaluate(_ context: DeepConstraintContext) async throws -> Bool {
        let subject = context.object.flatMap { context.view.clabject(of: $0)?.name } ?? "-"
        recorded.withLock { $0.append("\(context.constraint.name)@\(context.view.level):\(subject)") }
        if failing.contains(context.constraint.name) { throw MultiLevelError.invalidValue("body") }
        return !violated.contains(context.constraint.name)
    }
}

/// Tests when and on what deep constraints are evaluated.
@Suite("Deep constraint evaluation")
struct DeepConstraintEvaluationTests {
    @Test("a constraint of potency p is evaluated on the deep instances p levels below its holder")
    func evaluationLevel() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        let evaluator = RecordingEvaluator()
        #expect(await model.validate(evaluator: evaluator).isEmpty)
        #expect(evaluator.evaluations == [
            "someProducts@0:-", "posPrice@0:patterns", "posPrice@0:album", "posPrice@0:draft",
        ])
    }

    @Test("constraints of potency zero apply to their holder, and inherited ones to subclabject instances")
    func holderAndInheritance() async throws {
        let text = """
            Model M@2 {
              Node Base {
                x : int = 1;
                positive@2 : $self.x > 0$
                itself@0 : $true$
              }
              Node Derived : Base {}
            }
            M N {
              Derived d {
                local : $true$
              }
            }
            N O {
              d o {}
            }
            """
        let model = try MultiLevelFixtures.model(text)
        let evaluator = RecordingEvaluator()
        _ = await model.validate(evaluator: evaluator)
        #expect(evaluator.evaluations == ["positive@0:o", "itself@2:Base", "local@0:o"])
        let onlyTop = RecordingEvaluator()
        _ = await model.evaluateConstraints(atLevel: 2, evaluator: onlyTop)
        #expect(onlyTop.evaluations == ["itself@2:Base"])
    }

    @Test("violated and failing constraints are reported with their holder and subject")
    func diagnostics() async throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        let evaluator = RecordingEvaluator(violated: ["posPrice"], failing: ["someProducts"])
        let diagnostics = await model.validate(evaluator: evaluator)
        #expect(diagnostics.map(\.code) == [
            MultiLevelDiagnosticCode.constraintError, MultiLevelDiagnosticCode.constraintViolated,
            MultiLevelDiagnosticCode.constraintViolated, MultiLevelDiagnosticCode.constraintViolated,
        ])
        #expect(diagnostics[1].message == "constraint 'posPrice' of 'Commerce.ProductType' is violated on 'Shop.patterns'")
        #expect(diagnostics[0].message.hasPrefix("constraint 'someProducts' of 'Commerce' cannot be evaluated at level 0"))
        #expect(await model.validate().isEmpty)
    }
}

/// Tests the MetaDepth format handler.
@Suite("MetaDepth format handler")
struct MetaDepthFormatHandlerTests {
    @Test("a registered handler reads MetaDepth documents, recognised by content or extension")
    func readThroughModelIO() async throws {
        let registry = ModelFormatRegistry()
        await MultiLevelFormats.register(in: registry)
        let handler = try #require(await registry.handler(identifier: MultiLevelSyntax.formatIdentifier))
        #expect(handler.name == "MetaDepth" && handler.role == .model && handler.priority == .specific)
        #expect(await registry.handler(forFileExtension: "mdepth")?.identifier == MultiLevelSyntax.formatIdentifier)
        let data = Data(MultiLevelFixtures.arcade.utf8)
        #expect(await registry.handler(recognising: data)?.identifier == MultiLevelSyntax.formatIdentifier)
        let loaded = try await ModelIO.load(data: data, uri: "memory:arcade.mdepth", resourceSet: ResourceSet(), registry: registry)
        #expect(loaded.formatIdentifier == MultiLevelSyntax.formatIdentifier)
        #expect(loaded.format == .metadepth)
        #expect(ModelFormat(fileExtension: "metadepth") == .metadepth)
        var written = ConversionDiagnostics()
        let text = try await ModelIO.serialise(loaded.resource, format: .metadepth, registry: registry, diagnostics: &written)
        #expect(text == MetaDepthWriter.write(try MultiLevelFixtures.model(MultiLevelFixtures.arcade)).text)
        let model = try await LinguisticEncoding.model(from: loaded.resource)
        #expect(model == (try MultiLevelFixtures.model(MultiLevelFixtures.arcade)))
    }

    @Test("MetaDepth converts to XMI and JSON and back through the registry")
    func conversions() async throws {
        let registry = ModelFormatRegistry()
        await MultiLevelFormats.register(in: registry)
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(
            data: Data(MultiLevelFixtures.products.utf8), uri: "memory:products.mdepth", resourceSet: resourceSet,
            registry: registry)
        var diagnostics = ConversionDiagnostics()
        let xmi = try await ModelIO.serialise(loaded.resource, format: .xmi, registry: registry, diagnostics: &diagnostics)
        let fromXMI = try await ModelIO.load(
            data: Data(xmi.utf8), uri: "memory:products.xmi", resourceSet: await LinguisticEncoding.resourceSet(),
            registry: registry)
        let writer = try #require(await registry.handler(identifier: MultiLevelSyntax.formatIdentifier) as? any WritableModelFormatHandler)
        let text = try await writer.write(fromXMI.resource, relativeTo: nil, xmiOptions: .legacy, diagnostics: &diagnostics)
        #expect(text == MetaDepthWriter.write(try MultiLevelFixtures.model(MultiLevelFixtures.products)).text)
        let json = try await ModelIO.serialise(loaded.resource, format: .json, registry: registry, diagnostics: &diagnostics)
        #expect(json.contains(MultiLevelSyntax.linguisticNamespaceURI))
    }

    @Test("unreadable text and resources without a deep model are reported")
    func errors() async throws {
        let handler = MetaDepthFormatHandler()
        let request = ModelFormatReadRequest(data: Data("Model M@1 { Node A { x : Missing; } }".utf8), uri: "memory:bad", resourceSet: ResourceSet())
        await #expect(throws: MultiLevelError.unreadableText(["unknown type 'Missing' of feature 'x'"])) {
            try await handler.read(request)
        }
        var diagnostics = ConversionDiagnostics()
        await #expect(throws: MultiLevelError.notALinguisticModel("memory:none")) {
            try await handler.write(Resource(uri: "memory:none"), relativeTo: nil, xmiOptions: .legacy, diagnostics: &diagnostics)
        }
        #expect(!handler.recognises(Data("<xml/>".utf8)))
        let placeholder = try #require(await ModelFormatRegistry().handler(for: .metadepth))
        await #expect(throws: ModelFormatError.unsupportedFormat("mdepth")) { try await placeholder.read(request) }
    }
}
