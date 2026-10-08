//
// GenModelPackage.swift
// GenModel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import Foundation

/// Errors raised while loading generator models and their metamodel.
public enum GenModelError: Error, Sendable, Equatable {
    /// The bundled generator metamodel resource could not be found.
    case metamodelResourceMissing

    /// A document does not have a generator model as its root object.
    ///
    /// The associated value is the location of the offending document.
    case notAGenModel(String)

    /// A source model named by a generator model could not be loaded.
    ///
    /// The first associated value is the location, the second a description of the cause.
    case foreignModelUnreadable(String, String)
}

/// Provides the generator metamodel as an Ecore package.
///
/// The metamodel is bundled with this library as an Ecore document and loaded
/// with the standard Ecore loader. The loaded package is cached, so repeated
/// calls are cheap and always return the same package, including its element
/// identifiers.
///
/// ## Example
///
/// ```swift
/// let package = try await GenModelPackage.load()
/// let genClass = package.getEClass("GenClass")
/// ```
public enum GenModelPackage {
    /// The location of the bundled metamodel document.
    ///
    /// - Returns: The file URL of the bundled generator metamodel, or `nil` if the
    ///   resource bundle does not contain it.
    public static var resourceURL: URL? {
        GenModelResources.url(
            forResource: GenModelConstants.metamodelResourceName,
            withExtension: GenModelConstants.metamodelResourceExtension,
            subdirectory: GenModelConstants.resourceDirectory)
    }

    /// Loads the generator metamodel.
    ///
    /// The first call parses the bundled document; later calls return the cached package.
    ///
    /// - Returns: The generator metamodel package.
    /// - Throws: ``GenModelError/metamodelResourceMissing`` if the bundled document is
    ///   missing, or the loader's error if it cannot be parsed.
    public static func load() async throws -> EPackage {
        try await cache.package()
    }

    private static let cache = PackageCache()

    private actor PackageCache {
        private var loading: Task<EPackage, Error>?

        func package() async throws -> EPackage {
            if let loading { return try await loading.value }
            let task = Task { () async throws -> EPackage in
                guard let url = GenModelPackage.resourceURL else {
                    throw GenModelError.metamodelResourceMissing
                }
                return try await EPackage(url: url)
            }
            loading = task
            do {
                return try await task.value
            } catch {
                loading = nil
                throw error
            }
        }
    }
}
