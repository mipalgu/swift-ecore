//
// ModelIOFidelityTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests that ``ModelIO`` reads and writes the built-in formats exactly as their parsers and
/// serialisers do when they are called directly.
///
/// Every `.ecore`, `.xmi` and `.json` test resource is loaded through ``ModelIO`` and through
/// the parser of its format, and each resource is written in every format, with and without
/// a document location and with both legacy and EMF options. The texts must be identical.
@Suite("Model loading and saving fidelity")
struct ModelIOFidelityTests {
    /// The extensions of the documents that are compared.
    private static let extensions: Set<String> = Set(ModelFormat.allCases.map(\.fileExtension))

    /// The XMI options with which every document is written.
    private static let xmiOptions: [XMISerializationOptions] = [.legacy, .emf]

    /// The formats that accept any document of their syntax.
    private static let genericFormats: Set<ModelFormat> = [.xmi, .json, .ecore]

    /// The format in which a file is read: the one its extension names, unless that is a
    /// generic format and the contents are detected as a more specific one.
    private static func format(of url: URL, data: Data) -> ModelFormat? {
        let detected = ModelFormat.detect(data: data)
        guard let named = ModelFormat.detect(url: url) else { return detected }
        if genericFormats.contains(named), let detected, !genericFormats.contains(detected) { return detected }
        return named
    }

    /// Every test resource in a built-in format, in path order.
    private static func documents() throws -> [URL] {
        let root = try ReflectionFixtures.resourcesURL()
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var urls: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if extensions.contains(url.pathExtension.lowercased()) { urls.append(url) }
        }
        return urls.sorted { $0.path < $1.path }
    }

    /// Loads a document with the parser of its format, called directly.
    private static func referenceLoad(_ url: URL, resourceSet: ResourceSet) async throws -> ModelIO.Loaded {
        let uri = URIReference.canonicalise(url.absoluteString)
        let data = try await resourceSet.readDocument(uri: uri)
        let format = try #require(Self.format(of: url, data: data))
        switch format {
        case .ecore:
            let resource = try await resourceSet.loadEcoreResource(data: data, uri: uri, enableDebugging: false)
            return ModelIO.Loaded(resource: resource, format: format, packages: await register(resource, in: resourceSet))
        case .xmi:
            let parser = XMIParser(resourceSet: resourceSet)
            let resource = try await parser.parse(data, uri: uri)
            return ModelIO.Loaded(resource: resource, format: format, diagnostics: await parser.diagnostics)
        case .json:
            let requiresMetamodel = !(await resourceSet.getMetamodelURIs().isEmpty)
            let parser = JSONParser(resourceSet: resourceSet, options: JSONParseOptions(requiresMetamodel: requiresMetamodel))
            let resource = try await parser.parse(data, uri: uri)
            let roots = await resource.getRootObjects()
            let packages = !roots.isEmpty && roots.allSatisfy({ $0 is EPackage })
                ? await register(resource, in: resourceSet) : []
            return ModelIO.Loaded(
                resource: resource, format: format, diagnostics: await parser.diagnostics, packages: packages)
        case .km3:
            let decoded = try DecodedText(decoding: data, document: uri)
            let parsed = KM3Reader.parse(decoded.text, sourceName: uri)
            let resource = await resourceSet.createResource(uri: uri)
            for package in parsed.packages { await resource.registerNativePackage(package) }
            let packages = await register(resource, in: resourceSet)
            let warnings = await ModelIO.registerUnnamespacedPackages(packages, of: uri, in: resourceSet)
            await resource.setLoadDiagnostics((decoded.warning.map { [$0] } ?? []) + parsed.diagnostics + warnings)
            return ModelIO.Loaded(resource: resource, format: format, packages: packages)
        case .emfatic, .xcore, .oclinecore, .asdl, .langium, .xtext, .sdf3:
            let decoded = try DecodedText(decoding: data, document: uri)
            let parsed: (packages: [EPackage], diagnostics: [SourceDiagnostic])
            if format == .emfatic {
                let result = EmfaticReader.parse(decoded.text, sourceName: uri)
                parsed = (result.packages, result.diagnostics)
            } else if format == .asdl {
                let result = ASDLReader.parse(decoded.text, sourceName: uri)
                parsed = (result.packages, result.diagnostics)
            } else if format == .langium {
                let result = LangiumReader.parse(decoded.text, sourceName: uri)
                parsed = (result.packages, result.diagnostics)
            } else if format == .xtext {
                let result = XtextReader.parse(decoded.text, sourceName: uri)
                parsed = (result.packages, result.diagnostics)
            } else if format == .sdf3 {
                let result = SDF3Reader.parse(decoded.text, sourceName: uri)
                parsed = (result.packages, result.diagnostics)
            } else if format == .oclinecore {
                let externals = await OCLinEcoreFormatHandler.registeredPackages(of: resourceSet)
                let result = OCLinEcoreReader.parse(decoded.text, sourceName: uri, importing: externals)
                parsed = (result.packages, result.diagnostics)
            } else {
                let result = XcoreReader.parse(decoded.text, sourceName: uri)
                parsed = (result.packages, result.diagnostics)
            }
            let diagnostics = parsed.diagnostics
            let resource = await resourceSet.createResource(uri: uri)
            for package in parsed.packages { await resource.registerNativePackage(package) }
            let packages = await register(resource, in: resourceSet)
            let warnings = await ModelIO.registerUnnamespacedPackages(packages, of: uri, in: resourceSet)
            await resource.setLoadDiagnostics((decoded.warning.map { [$0] } ?? []) + diagnostics + warnings)
            return ModelIO.Loaded(resource: resource, format: format, packages: packages)
        case .emof:
            let read = try await EMOFFormat.read(data: data, uri: uri, resourceSet: resourceSet)
            let warnings = await ModelIO.registerUnnamespacedPackages(read.packages, of: uri, in: resourceSet)
            await read.resource.setLoadDiagnostics(read.diagnostics + warnings)
            return ModelIO.Loaded(resource: read.resource, format: format, packages: read.packages)
        case .uml:
            let read = try await UMLFormat.readResource(
                data: data, uri: uri, resourceSet: resourceSet, options: ModelIO.LoadOptions())
            if !read.profileDiagnostics.isEmpty {
                await read.resource.setLoadDiagnostics(read.profileDiagnostics + (await read.resource.loadDiagnostics))
            }
            return ModelIO.Loaded(resource: read.resource, format: format, diagnostics: read.conversion)
        }
    }

    /// Registers the root packages of a resource as metamodels.
    private static func register(_ resource: Resource, in resourceSet: ResourceSet) async -> [EPackage] {
        let packages = await resource.getRootObjects().compactMap { $0 as? EPackage }
        for package in packages where !package.nsURI.isEmpty { await resourceSet.registerMetamodel(package) }
        return packages
    }

    /// Writes a resource with the serialiser of a format, called directly.
    private static func referenceSerialise(
        _ resource: Resource, format: ModelFormat, relativeTo documentURL: URL?,
        xmiOptions: XMISerializationOptions, diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        if [.langium, .xtext, .sdf3].contains(format) {
            throw ModelFormatError.unwritableFormat(format.description)
        }
        if format == .uml {
            return try await UMLFormat.serialise(
                resource, relativeTo: documentURL, options: .uml, diagnostics: &diagnostics)
        }
        let roots = await resource.getRootObjects()
        let packages = roots.compactMap { $0 as? EPackage }
        if !roots.isEmpty && packages.count == roots.count {
            if format == .emof { return EMOFFormat.write(packages, relativeTo: documentURL).text }
            if [.km3, .emfatic, .xcore, .oclinecore, .asdl].contains(format) {
                let written: (text: String, diagnostics: [SourceDiagnostic])
                switch format {
                case .km3: written = KM3Writer.write(packages)
                case .emfatic: written = EmfaticWriter.write(packages)
                case .xcore: written = XcoreWriter.write(packages)
                case .asdl: written = ASDLWriter.write(packages)
                default: written = OCLinEcoreWriter.write(packages)
                }
                if let error = written.diagnostics.first(where: { $0.severity == .error }) { throw error }
                for diagnostic in written.diagnostics { diagnostics.record(.sourceDiagnostic(diagnostic)) }
                return written.text
            }
            if format == .json { return JSONSerializer().serialize(packages, relativeTo: documentURL) }
            return XMISerializer(options: xmiOptions).serialize(packages, relativeTo: documentURL)
        }
        switch format {
        case .ecore, .km3, .emof, .emfatic, .xcore, .oclinecore, .asdl, .langium, .xtext, .sdf3:
            throw ModelIOError.notAMetamodel(documentURL?.absoluteString ?? resource.uri)
        case .xmi, .uml:
            let serializer = XMISerializer(options: xmiOptions)
            if let documentURL {
                return try await serializer.serialize(resource, relativeTo: documentURL, diagnostics: &diagnostics)
            }
            return try await serializer.serialize(resource, diagnostics: &diagnostics)
        case .json:
            return try await JSONSerializer().serialize(resource, diagnostics: &diagnostics)
        }
    }

    /// The text, or the error, and the warnings of a serialisation.
    private static func outcome(
        _ body: (inout ConversionDiagnostics) async throws -> String
    ) async -> String {
        var diagnostics = ConversionDiagnostics()
        do {
            let text = try await body(&diagnostics)
            return text + "\n--\n" + diagnostics.warnings.map(\.message).joined(separator: "\n")
        } catch {
            return "error: \(error)"
        }
    }

    @Test("the test resources include documents of every built-in format")
    func resourcesCoverEveryFormat() throws {
        let formats = Set(try Self.documents().compactMap { ModelFormat.detect(url: $0) })
        #expect(formats == Set(ModelFormat.allCases))
    }

    @Test("every document loads and writes exactly as with its parser and serialiser")
    func everyDocumentMatchesDirectCalls() async throws {
        let documents = try Self.documents()
        #expect(!documents.isEmpty)
        for url in documents {
            let reference: ModelIO.Loaded
            do {
                reference = try await Self.referenceLoad(url, resourceSet: ResourceSet())
            } catch {
                await #expect(throws: (any Error).self, "\(url.lastPathComponent)") {
                    try await ModelIO.load(url: url, resourceSet: ResourceSet())
                }
                continue
            }
            let loaded = try await ModelIO.load(url: url, resourceSet: ResourceSet())
            #expect(loaded.format == reference.format, "\(url.lastPathComponent)")
            #expect(loaded.formatIdentifier == reference.format.rawValue, "\(url.lastPathComponent)")
            #expect(loaded.diagnostics == reference.diagnostics, "\(url.lastPathComponent)")
            #expect(loaded.packages.map(\.name) == reference.packages.map(\.name), "\(url.lastPathComponent)")
            #expect(await loaded.resource.loadDiagnostics == reference.resource.loadDiagnostics)
            for format in ModelFormat.allCases {
                for options in Self.xmiOptions {
                    for documentURL in [nil, url.deletingLastPathComponent().appendingPathComponent("out.\(format.fileExtension)")] {
                        let actual = await Self.outcome {
                            try await ModelIO.serialise(
                                loaded.resource, format: format, relativeTo: documentURL, xmiOptions: options,
                                diagnostics: &$0)
                        }
                        let expected = await Self.outcome {
                            try await Self.referenceSerialise(
                                reference.resource, format: format, relativeTo: documentURL, xmiOptions: options,
                                diagnostics: &$0)
                        }
                        #expect(
                            actual == expected,
                            "\(url.lastPathComponent) as \(format)")
                    }
                }
            }
        }
    }

    @Test("a document loaded from its bytes matches the document loaded from its file")
    func dataLoadsMatchURLLoads() async throws {
        for url in try Self.documents() {
            guard let fromURL = try? await ModelIO.load(url: url, resourceSet: ResourceSet()) else { continue }
            let data = try Data(contentsOf: url)
            let detected = try await ModelIO.load(data: data, uri: url.absoluteString, resourceSet: ResourceSet())
            let named = try await ModelIO.load(
                data: data, uri: url.absoluteString, format: Self.format(of: url, data: data), resourceSet: ResourceSet())
            #expect(named.format == fromURL.format, "\(url.lastPathComponent)")
            #expect(detected.format == ModelFormat.detect(data: data), "\(url.lastPathComponent)")
            var first = ConversionDiagnostics()
            var second = ConversionDiagnostics()
            let expected = try? await ModelIO.serialise(fromURL.resource, format: .xmi, diagnostics: &first)
            let actual = try? await ModelIO.serialise(named.resource, format: .xmi, diagnostics: &second)
            #expect(actual == expected, "\(url.lastPathComponent)")
        }
    }
}
