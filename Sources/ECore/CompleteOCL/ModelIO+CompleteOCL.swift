//
// ModelIO+CompleteOCL.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

extension ModelIO {
    /// Adds the constraints of a Complete OCL document to loaded metamodels.
    ///
    /// The document is read through the URI handlers of the resource set and applied as
    /// ``applyCompleteOCL(data:uri:to:in:options:)`` describes.
    ///
    /// - Parameters:
    ///   - url: The location of the Complete OCL document (`.ocl`).
    ///   - resources: The resources of the metamodels that the document constrains, such as
    ///     the ``Loaded/resource`` of a loaded metamodel, in the order in which contexts are
    ///     looked up.
    ///   - resourceSet: The resource set that reads the document and with which the
    ///     metamodels are registered.
    ///   - options: The options that control reading; their ``LoadOptions/textEncoding``
    ///     selects the encoding of the document (default options).
    /// - Returns: The constrained packages, the number of specifications added, and what
    ///   could not be read or applied.
    /// - Throws: ``ModelIOError/unconstrainableResource(_:)`` if a root object of a resource
    ///   is not a package, `TextDecodingError.malformed(_:)` if the document is not valid in
    ///   an explicit encoding, or the error of the URI handler.
    @discardableResult
    public static func applyCompleteOCL(
        at url: URL, to resources: [Resource], in resourceSet: ResourceSet, options: LoadOptions = LoadOptions()
    ) async throws -> CompleteOCLApplication {
        let uri = URIReference.canonicalise(url.absoluteString)
        return try await applyCompleteOCL(
            data: try await resourceSet.readDocument(uri: uri), uri: uri, to: resources, in: resourceSet,
            options: options)
    }

    /// Adds the constraints of a Complete OCL document, given as bytes, to loaded metamodels.
    ///
    /// The document is decoded as text (UTF-8, falling back to ISO-8859-1 with a warning,
    /// unless ``LoadOptions/textEncoding`` names an encoding), read by ``CompleteOCLReader``
    /// and applied to the root packages of the resources by ``CompleteOCLApplier``. The
    /// constrained packages then replace the root packages of their resources, and every
    /// registration of a replaced package with the resource set, under its namespace URI or
    /// its name, refers to the constrained package instead, so that models read afterwards,
    /// and metamodels written afterwards, carry the constraints.
    ///
    /// The document is applied as far as it can be: contexts that the metamodels lack are
    /// reported as errors in the diagnostics of the result, after the warnings of decoding
    /// and the syntax errors of the document.
    ///
    /// ```swift
    /// let resourceSet = ResourceSet()
    /// let metamodel = try await ModelIO.load(url: schoolURL, resourceSet: resourceSet)
    /// let applied = try await ModelIO.applyCompleteOCL(
    ///     at: constraintsURL, to: [metamodel.resource], in: resourceSet)
    /// for diagnostic in applied.diagnostics { print(diagnostic.message) }
    /// ```
    ///
    /// - Parameters:
    ///   - data: The bytes of the Complete OCL document.
    ///   - uri: The URI of the document, which its diagnostics name.
    ///   - resources: The resources of the metamodels that the document constrains, in the
    ///     order in which contexts are looked up.
    ///   - resourceSet: The resource set with which the metamodels are registered.
    ///   - options: The options that control reading (default options).
    /// - Returns: The constrained packages, the number of specifications added, and what
    ///   could not be read or applied.
    /// - Throws: ``ModelIOError/unconstrainableResource(_:)`` if a root object of a resource
    ///   is not a package, or `TextDecodingError.malformed(_:)` if the document is not valid
    ///   in an explicit encoding.
    @discardableResult
    public static func applyCompleteOCL(
        data: Data, uri: String, to resources: [Resource], in resourceSet: ResourceSet,
        options: LoadOptions = LoadOptions()
    ) async throws -> CompleteOCLApplication {
        let uri = URIReference.canonicalise(uri)
        var originals: [(resource: Resource, packages: [EPackage])] = []
        for resource in resources {
            guard let packages = await metamodelPackages(of: resource) else {
                throw ModelIOError.unconstrainableResource(resource.uri)
            }
            originals.append((resource, packages))
        }
        let decoded = try DecodedText(decoding: data, encoding: options.textEncoding, document: uri)
        let parsed = CompleteOCLReader.parse(decoded.text, sourceName: uri)
        let applied = CompleteOCLApplier.apply(
            parsed.document, to: originals.flatMap(\.packages), sourceName: uri)
        var constrained = applied.packages[...]
        for (resource, packages) in originals {
            let replacements = Array(constrained.prefix(packages.count))
            constrained = constrained.dropFirst(packages.count)
            for package in packages { await resource.remove(id: package.id) }
            for package in replacements { await resource.registerNativePackage(package) }
            for (original, replacement) in zip(packages, replacements) {
                await reregister(original, as: replacement, in: resourceSet)
            }
        }
        let diagnostics = (decoded.warning.map { [$0] } ?? []) + parsed.diagnostics + applied.diagnostics
        return CompleteOCLApplication(packages: applied.packages, diagnostics: diagnostics, appliedCount: applied.appliedCount)
    }

    /// Makes the registrations of a package with a resource set refer to its replacement.
    ///
    /// - Parameters:
    ///   - original: The package that was registered.
    ///   - replacement: The package that replaces it.
    ///   - resourceSet: The resource set.
    private static func reregister(_ original: EPackage, as replacement: EPackage, in resourceSet: ResourceSet) async {
        for uri in Set([original.nsURI, original.name]) where !uri.isEmpty {
            guard await resourceSet.getMetamodel(uri: uri)?.id == original.id else { continue }
            await resourceSet.registerMetamodel(replacement, uri: uri)
        }
    }
}
