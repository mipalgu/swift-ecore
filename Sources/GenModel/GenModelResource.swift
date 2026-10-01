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
    /// Textual references are left as loaded.
    ///
    /// Use this when reference resolution is provided by the resource set.
    case deferred

    /// Textual references are resolved by walking name and position paths through the
    /// loaded source models, using ``EcoreFragmentResolver``.
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

        let resource = try await resourceSet.loadXMIResource(uri: documentURL.absoluteString)
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
            guard isExplicit || foreignURL.pathExtension == GenModelConstants.metamodelResourceExtension,
                FileManager.default.fileExists(atPath: foreignURL.path)
            else {
                if isExplicit {
                    throw GenModelError.foreignModelUnreadable(
                        foreignURL.absoluteString, "file not found")
                }
                continue
            }
            foreignPackages[foreignURL] = try await loadForeignModel(
                at: foreignURL, resourceSet: resourceSet)
        }

        let document = GenModelDocument(
            resource: resource, url: documentURL, foreignPackages: foreignPackages)
        if case .nameFragments = resolution {
            await resolveEcoreReferences(in: document)
        }
        return document
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

    /// Replaces textual `ecore*` references by references to the loaded native elements.
    ///
    /// References that cannot be resolved are left as text.
    ///
    /// - Parameter document: A document returned by ``loadDocument(url:resourceSet:resolution:)``.
    public static func resolveEcoreReferences(in document: GenModelDocument) async {
        let resolver = EcoreFragmentResolver(packages: document.foreignPackages)
        let generatorClassNames = Set(GenModelConstants.ClassName.all)
        for case let object as DynamicEObject in await document.resource.getAllObjects()
        where generatorClassNames.contains(object.eClass.name) {
            for feature in GenModelConstants.FeatureName.ecoreReferences {
                guard let text = object.eGet(feature) as? String,
                    let target = resolver.resolve(text, relativeTo: document.url)
                else { continue }
                await document.resource.eSet(objectId: object.id, feature: feature, value: target)
            }
        }
    }

    private static func referencedLocations(in resource: Resource) async -> [String] {
        let generatorClassNames = Set(GenModelConstants.ClassName.all)
        var locations: [String] = []
        for case let object as DynamicEObject in await resource.getAllObjects()
        where generatorClassNames.contains(object.eClass.name) {
            for feature in GenModelConstants.FeatureName.ecoreReferences {
                if let text = object.eGet(feature) as? String,
                    let reference = EcoreReference(text), !reference.location.isEmpty,
                    !locations.contains(reference.location)
                {
                    locations.append(reference.location)
                }
            }
        }
        return locations.sorted()
    }

    private static func loadForeignModel(at url: URL, resourceSet: ResourceSet) async throws
        -> EPackage
    {
        do {
            let resource = try await resourceSet.loadXMIResource(uri: url.absoluteString)
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
}
