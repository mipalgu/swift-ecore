//
// GenModelResource.swift
// GenModel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import SwiftXML

/// The outcome of loading a generator model document.
///
/// Besides the loaded resource, the document records the native packages that were
/// loaded from the source models named by the generator model, keyed by their
/// absolute location, which is what reference resolution needs.
public struct GenModelDocument: Sendable {
    /// The resource holding the generator model objects.
    public let resource: Resource

    /// The absolute location of the generator model file.
    public let url: URL

    /// The root packages of the source models, keyed by absolute location.
    public let foreignPackages: [URL: EPackage]
}

/// How `ecore*` references of a loaded generator model are resolved.
public enum EcoreReferenceResolution: Sendable {
    /// Reference attributes are kept as the text of the document.
    ///
    /// The attribute values are lossless and uninterpreted, for example
    /// `ecore:EAttribute library.ecore#//Book/title`. Source models named by the
    /// generator model are still loaded, but nothing is resolved.
    case deferred

    /// Reference attributes are read as references and resolved through the resource set.
    ///
    /// The source models named by the generator model are loaded as native Ecore
    /// packages into the same resource set, and the references of the generator model
    /// are replaced by the identifiers of the native elements they name. References
    /// that cannot be resolved stay unresolved proxies.
    case nameFragments
}

/// Loads generator model files and the source models they describe.
///
/// Loading registers the generator metamodel in the resource set, parses the `.genmodel`
/// file with the standard XMI parser, loads every source model named by `foreignModel`
/// (or referenced by an `ecore*` attribute) relative to the generator model into the same
/// resource set, and registers each loaded package as a metamodel by its namespace URI.
///
/// Resolving `ecore*` references to the loaded Ecore elements is a separate step selected
/// by ``EcoreReferenceResolution``.
///
/// ## Example
///
/// ```swift
/// let resourceSet = ResourceSet()
/// let resource = try await GenModelResource.load(url: genModelURL, resourceSet: resourceSet)
/// let context = await GenModelContext.snapshot(of: resourceSet)
/// ```
public enum GenModelResource {
    /// Loads a generator model.
    ///
    /// - Parameters:
    ///   - url: The location of the `.genmodel` file.
    ///   - resourceSet: The resource set to load into; a new one by default.
    ///   - resolution: How to resolve `ecore*` references after loading.
    /// - Returns: The resource holding the generator model objects.
    /// - Throws: ``GenModelError`` if the document is not a generator model or a source model
    ///   cannot be loaded, or the loader's error if parsing fails.
    public static func load(
        url: URL,
        resourceSet: ResourceSet = ResourceSet(),
        resolution: EcoreReferenceResolution = .deferred
    ) async throws -> Resource {
        try await loadDocument(url: url, resourceSet: resourceSet, resolution: resolution).resource
    }

    /// Loads a generator model together with its source models.
    ///
    /// - Parameters:
    ///   - url: The location of the `.genmodel` file.
    ///   - resourceSet: The resource set to load into; a new one by default.
    ///   - resolution: How to resolve `ecore*` references after loading.
    /// - Returns: The loaded document.
    /// - Throws: ``GenModelError`` if the document is not a generator model or a source model
    ///   cannot be loaded, or the loader's error if parsing fails.
    public static func loadDocument(
        url: URL,
        resourceSet: ResourceSet = ResourceSet(),
        resolution: EcoreReferenceResolution = .deferred
    ) async throws -> GenModelDocument {
        let documentURL = url.absoluteURL
        if await resourceSet.getMetamodel(uri: GenModelConstants.nsURI) == nil {
            let package = try await GenModelPackage.load()
            await resourceSet.registerMetamodel(package, uri: GenModelConstants.nsURI)
        }
        await GenModelFragments.register(in: resourceSet)
        await GenModelDerivedFeatures.register(in: resourceSet)

        let resolvesReferences = resolution == .nameFragments
        let resource = try await resourceSet.loadXMIResource(
            uri: URIReference.canonicalise(documentURL.absoluteString),
            referenceParsing: resolvesReferences ? .interpreted : .rawText)
        let roots = await resource.getRootObjects()
        guard let root = roots.first as? DynamicEObject,
            root.eClass.name == GenModelConstants.ClassName.genModel
        else {
            throw GenModelError.notAGenModel(documentURL.absoluteString)
        }

        var locations = try foreignModelLocations(in: documentURL)
        let explicit = Set(locations)
        for location in await referencedLocations(in: resource) where !explicit.contains(location) {
            locations.append(location)
        }

        var foreignPackages: [URL: EPackage] = [:]
        for location in locations {
            guard let foreignURL = URL(string: location, relativeTo: documentURL)?.absoluteURL,
                foreignPackages[foreignURL] == nil
            else { continue }
            let isExplicit = explicit.contains(location)
            guard foreignURL.isFileURL,
                foreignURL.pathExtension == GenModelConstants.metamodelResourceExtension
            else { continue }
            guard FileManager.default.fileExists(atPath: foreignURL.path) else {
                if isExplicit {
                    throw GenModelError.foreignModelUnreadable(
                        foreignURL.absoluteString, "file not found")
                }
                continue
            }
            foreignPackages[foreignURL] =
                resolvesReferences
                ? try await loadNativeForeignModel(at: foreignURL, resourceSet: resourceSet)
                : try await loadForeignModel(at: foreignURL, resourceSet: resourceSet)
        }

        if resolvesReferences { await resource.resolveProxies() }
        return GenModelDocument(
            resource: resource, url: documentURL, foreignPackages: foreignPackages)
    }

    /// Reads the locations of the source models named by a generator model file.
    ///
    /// - Parameter url: The location of the `.genmodel` file.
    /// - Returns: The text of each `foreignModel` element, in document order.
    /// - Throws: The XML parser's error if the file cannot be read or parsed.
    public static func foreignModelLocations(in url: URL) throws -> [String] {
        let document = try parseXML(fromPath: url.path)
        var locations: [String] = []
        for element in document.descendants(GenModelConstants.FeatureName.foreignModel) {
            var text = ""
            for fragment in element.immediateTexts { text += fragment.value }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { locations.append(text) }
        }
        return locations
    }

    private static func referencedLocations(in resource: Resource) async -> [String] {
        let generatorClassNames = Set(GenModelConstants.ClassName.all)
        var locations: [String] = []
        for case let object as DynamicEObject in await resource.getAllObjects()
        where generatorClassNames.contains(object.eClass.name) {
            for feature in GenModelConstants.FeatureName.ecoreReferences {
                for location in referencedLocations(of: object.eGet(feature))
                where !location.isEmpty && !locations.contains(location) {
                    locations.append(location)
                }
            }
        }
        return locations.sorted()
    }

    private static func referencedLocations(of value: (any EcoreValue)?) -> [String] {
        switch value {
        case let text as String: return EcoreReference(text).map { [$0.location] } ?? []
        case let proxy as ResourceProxy: return [proxy.uri]
        case let proxies as [ResourceProxy]: return proxies.map(\.uri)
        default: return []
        }
    }

    private static func loadNativeForeignModel(at url: URL, resourceSet: ResourceSet) async throws
        -> EPackage
    {
        do {
            let resource = try await resourceSet.loadEcoreResource(uri: URIReference.canonicalise(url.absoluteString))
            guard let package = await resource.getRootObjects().first as? EPackage else {
                throw XMIError.noRootObject
            }
            return package
        } catch {
            throw GenModelError.foreignModelUnreadable(url.absoluteString, String(describing: error))
        }
    }

    private static func loadForeignModel(at url: URL, resourceSet: ResourceSet) async throws
        -> EPackage
    {
        do {
            let resource = try await resourceSet.loadXMIResource(uri: URIReference.canonicalise(url.absoluteString))
            guard let root = await resource.getRootObjects().first else {
                throw XMIError.noRootObject
            }
            let package = try await resource.createEPackage(from: root)
            await resourceSet.registerMetamodel(package, uri: package.nsURI)
            return package
        } catch {
            throw GenModelError.foreignModelUnreadable(url.absoluteString, String(describing: error))
        }
    }

    /// Saves a generator model in the layout that the Eclipse Modeling Framework writes.
    ///
    /// References to source models are written as attributes, qualified by the type of
    /// the target where it differs from the declared type, with name-based fragments and
    /// URIs relative to the saved file, for example
    /// `ecoreFeature="ecore:EAttribute library.ecore#//Book/title"`. Generator packages
    /// are identified by the name of their Ecore package.
    ///
    /// - Parameters:
    ///   - resource: The resource holding the generator model, as returned by ``load(url:resourceSet:resolution:)``.
    ///   - url: The file to write.
    /// - Throws: The serialiser's error if a reference cannot be written or the file cannot be written.
    public static func save(_ resource: Resource, to url: URL) async throws {
        try await serialised(resource, for: url).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Renders a generator model as the text that ``save(_:to:)`` writes.
    ///
    /// - Parameters:
    ///   - resource: The resource holding the generator model.
    ///   - url: The location that the document will have; relative references are computed against it.
    /// - Returns: The document text in the layout of the Eclipse Modeling Framework.
    /// - Throws: The serialiser's error if a reference cannot be written.
    public static func serialised(_ resource: Resource, for url: URL) async throws -> String {
        if let resourceSet = await resource.resourceSet {
            await GenModelFragments.register(in: resourceSet)
        }
        return try await XMISerializer(options: .emfWrapped).serialize(resource, relativeTo: url)
    }
}
