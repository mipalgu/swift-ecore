//
// UMLMetamodel.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// The Eclipse UML2 metamodel that this package ships, with which UML models are read.
///
/// The package ships the metamodel of Eclipse UML2 5.x (`UML.ecore`) and the primitive types
/// it refers to (`Types.ecore`) unchanged, under the terms of the Eclipse Public License 2.0,
/// whose text and a notice of their origin accompany them among the resources of this module.
///
/// The metamodel is loaded once per program on first use and then shared. ``register(in:)``
/// registers it with a resource set under its own namespace URI and under every namespace
/// that ``UMLNamespaces`` reads as Eclipse UML2 5.x, so that a model in any of those
/// namespaces is read with its classes.
///
/// ```swift
/// let resourceSet = ResourceSet()
/// let uml = try await UMLMetamodel.register(in: resourceSet)
/// print(uml.getEClass("Class")?.allStructuralFeatures.count ?? 0)
/// ```
public enum UMLMetamodel {
    /// The name of the resource directory of this module.
    public static let bundleName = ResourceBundleName(package: "swift-ecore", target: "ECore")

    /// The directory within the resources of this module that holds the UML metamodel.
    public static let subdirectory = "Resources/UML"

    /// The name of the document of the UML metamodel, without its extension.
    public static let metamodelName = "UML"

    /// The name of the document of the UML primitive types, without its extension.
    public static let typesName = "Types"

    /// The location by which the UML metamodel refers to its primitive types.
    static let typesPlatformURI = "platform:/plugin/org.eclipse.uml2.types/model/Types.ecore"

    /// The location by which Eclipse tools refer to the UML metamodel document.
    static let metamodelPlatformURI = "platform:/plugin/org.eclipse.uml2.uml/model/UML.ecore"

    /// The cache that loads the metamodel once per program.
    private static let cache = UMLMetamodelCache()

    /// The location of a document of the bundled metamodel.
    ///
    /// - Parameter name: ``metamodelName`` or ``typesName``.
    /// - Returns: The location of the `.ecore` document, or `nil` if the resources of this
    ///   module are not available.
    public static func url(of name: String) -> URL? {
        BundledResources.url(
            forResource: name, withExtension: ModelFormat.ecore.fileExtension, subdirectory: subdirectory,
            in: .module, bundleName: bundleName)
    }

    /// The root packages of the UML metamodel and of its primitive types.
    ///
    /// The documents are loaded on first use and the same packages are returned afterwards.
    ///
    /// - Returns: The `uml` package and the `types` package.
    /// - Throws: ``BundledMetamodelError/resourceMissing(_:)`` if the documents are not among
    ///   the resources of this module, or the error of the loader.
    public static func packages() async throws -> (uml: EPackage, types: EPackage) {
        try await cache.packages()
    }

    /// Registers the UML metamodel and its primitive types with a resource set.
    ///
    /// The UML package is registered under ``UMLNamespaces/uml`` and under every namespace in
    /// ``UMLNamespaces/metamodelAliases``; the package of primitive types under
    /// ``UMLNamespaces/types``. A namespace under which another package is already registered
    /// keeps that package.
    ///
    /// - Parameter resourceSet: The resource set to register the packages with.
    /// - Returns: The UML package.
    /// - Throws: The errors of ``packages()``.
    @discardableResult
    public static func register(in resourceSet: ResourceSet) async throws -> EPackage {
        let (uml, types) = try await packages()
        for (package, uris) in [(types, [UMLNamespaces.types]), (uml, [UMLNamespaces.uml] + UMLNamespaces.metamodelAliases)] {
            for uri in uris where await resourceSet.getMetamodel(uri: uri) == nil {
                await resourceSet.registerMetamodel(package, uri: uri)
            }
        }
        return uml
    }

    /// Registers the UML metamodel with a resource set if a document refers to its classes.
    ///
    /// A UML model written in a format other than UML, such as JSON, names the class of each
    /// object by a URI in one of the namespaces that ``register(in:)`` registers, such as
    /// `http://www.eclipse.org/uml2/5.0.0/UML#//Class`. Registering the metamodel before the
    /// document is read lets its objects keep the classes of UML, so that the model can be
    /// written as UML again. Nothing is registered for a document that refers to no such class.
    ///
    /// - Parameters:
    ///   - data: The contents of the document.
    ///   - resourceSet: The resource set to register the packages with.
    /// - Returns: Whether the document refers to a class of the UML metamodel.
    /// - Throws: The errors of ``register(in:)``.
    @discardableResult
    public static func registerIfReferenced(by data: Data, in resourceSet: ResourceSet) async throws -> Bool {
        let namespaces = [UMLNamespaces.uml, UMLNamespaces.types] + UMLNamespaces.metamodelAliases
        guard namespaces.contains(where: { data.range(of: Data(($0 + classReferenceSeparator).utf8)) != nil }) else {
            return false
        }
        try await register(in: resourceSet)
        return true
    }

    /// The text between a namespace URI and the path of a class in a reference to the class.
    static let classReferenceSeparator = "#//"

    /// Loads the bundled documents into a new resource set.
    ///
    /// The primitive types are made available under the location by which the metamodel
    /// refers to them, so that the metamodel is read with its own data types.
    ///
    /// - Returns: The `uml` package and the `types` package.
    /// - Throws: ``BundledMetamodelError/resourceMissing(_:)`` or the error of the loader.
    static func load() async throws -> (uml: EPackage, types: EPackage) {
        guard let typesURL = url(of: typesName) else {
            throw BundledMetamodelError.resourceMissing(typesName + "." + ModelFormat.ecore.fileExtension)
        }
        guard let metamodelURL = url(of: metamodelName) else {
            throw BundledMetamodelError.resourceMissing(metamodelName + "." + ModelFormat.ecore.fileExtension)
        }
        let resourceSet = ResourceSet()
        await resourceSet.mapURI(from: typesPlatformURI, to: URIReference.canonicalise(typesURL.absoluteString))
        let typesResource = try await resourceSet.loadEcoreResource(uri: typesPlatformURI)
        let umlResource = try await resourceSet.loadEcoreResource(
            uri: URIReference.canonicalise(metamodelURL.absoluteString))
        guard let types = await typesResource.getRootObjects().first as? EPackage,
            let uml = await umlResource.getRootObjects().first as? EPackage
        else { throw XMIError.noRootObject }
        return (uml, types)
    }
}

/// Loads the bundled UML metamodel once and hands out the same packages afterwards.
///
/// A load that fails is not kept, so that the next request tries again.
actor UMLMetamodelCache {
    /// The load that has succeeded or is in progress.
    private var load: Task<(uml: EPackage, types: EPackage), Error>?

    /// The packages of the bundled metamodel, loaded on first use.
    ///
    /// - Returns: The `uml` package and the `types` package.
    /// - Throws: The error of ``UMLMetamodel/load()``.
    func packages() async throws -> (uml: EPackage, types: EPackage) {
        if let load { return try await load.value }
        let task = Task { try await UMLMetamodel.load() }
        load = task
        do {
            return try await task.value
        } catch {
            load = nil
            throw error
        }
    }
}
