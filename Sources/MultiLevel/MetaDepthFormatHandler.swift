//
// MetaDepthFormatHandler.swift
// MultiLevel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase
public import Foundation

/// Reads and writes multi-level models in the MetaDepth notation through ``ECore/ModelIO``.
///
/// Its identifier is that of ``ECore/ModelFormat/metadepth``, so registering it replaces the
/// built-in placeholder of that format.
///
/// A document is read into a resource of linguistic instances (see ``LinguisticEncoding``),
/// so that it converts to XMI or JSON like any model, and a resource of linguistic instances
/// is written back as canonical MetaDepth text. Register the handler to make the format
/// available, for example with ``MultiLevelFormats/register(in:)``.
///
/// ```swift
/// await MultiLevelFormats.register()
/// let loaded = try await ModelIO.load(url: storeURL, resourceSet: ResourceSet())
/// let model = try await LinguisticEncoding.model(from: loaded.resource)
/// ```
public struct MetaDepthFormatHandler: WritableModelFormatHandler {
    /// Creates the handler.
    ///
    /// - Parameter schemes: The potency schemes that documents may select (default the
    ///   built-in ones).
    public init(schemes: [any PotencyScheme] = PotencySchemes.builtIn) {
        self.schemes = schemes
    }

    /// The potency schemes that documents may select.
    public let schemes: [any PotencyScheme]

    /// ``MultiLevelSyntax/formatIdentifier``.
    public var identifier: String { MultiLevelSyntax.formatIdentifier }

    /// ``MultiLevelSyntax/formatName``.
    public var name: String { MultiLevelSyntax.formatName }

    /// The conventional extension of MetaDepth documents.
    public var fileExtensions: [String] { [MultiLevelSyntax.fileExtension] }

    /// Models: the document holds the levels of one deep model.
    public var role: ModelFormatRole { .model }

    /// Whether a document starts like a MetaDepth model (see
    /// ``MetaDepthReader/looksLikeMetaDepth(_:)``).
    ///
    /// - Parameter prefix: The start of the document.
    /// - Returns: `true` if the document starts with a MetaDepth model header.
    public func recognises(_ prefix: Data) -> Bool {
        MetaDepthReader.looksLikeMetaDepth(String(decoding: prefix, as: UTF8.self))
    }

    /// Reads a document into a resource of linguistic instances.
    ///
    /// - Parameter request: The document to read.
    /// - Returns: The resource, with the warnings of the reader.
    /// - Throws: ``MultiLevelError/unreadableText(_:)`` if the text has errors.
    public func read(_ request: ModelFormatReadRequest) async throws -> ModelFormatReadResult {
        let decoded = try request.decodedText()
        let result = MetaDepthReader.parse(decoded.text, sourceName: request.uri, schemes: schemes)
        guard !result.hasErrors, let model = result.model else {
            throw MultiLevelError.unreadableText(
                result.diagnostics.filter { $0.severity == .error }.map(\.message) + (result.model == nil ? ["no model"] : []))
        }
        let resource = await LinguisticEncoding.resource(for: model, in: request.resourceSet, uri: request.uri)
        var diagnostics = ConversionDiagnostics()
        for diagnostic in (decoded.warning.map { [$0] } ?? []) + result.diagnostics {
            diagnostics.record(.sourceDiagnostic(diagnostic))
        }
        return .resource(resource, diagnostics: diagnostics)
    }

    /// Writes a resource of linguistic instances as MetaDepth text.
    ///
    /// - Parameters:
    ///   - resource: The resource, whose deep model is written.
    ///   - documentURL: Not used.
    ///   - xmiOptions: Not used.
    ///   - diagnostics: Receives the warnings of the writer.
    /// - Returns: The text.
    /// - Throws: ``MultiLevelError/notALinguisticModel(_:)`` if the resource holds no deep
    ///   model, or the first error of the writer.
    public func write(
        _ resource: Resource, relativeTo documentURL: URL?, xmiOptions: XMISerializationOptions,
        diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        let model = try await LinguisticEncoding.model(from: resource, schemes: schemes)
        let written = MetaDepthWriter.write(model)
        if let error = written.diagnostics.first(where: { $0.severity == .error }) { throw error }
        for diagnostic in written.diagnostics { diagnostics.record(.sourceDiagnostic(diagnostic)) }
        return written.text
    }
}

/// Registration of the multi-level formats.
public enum MultiLevelFormats {
    /// Registers the MetaDepth format handler.
    ///
    /// - Parameter registry: The registry (default the shared registry of ``ECore/ModelIO``).
    public static func register(in registry: ModelFormatRegistry = .shared) async {
        await registry.register(MetaDepthFormatHandler())
    }
}
