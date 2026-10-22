//
// BundledMetamodel.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - Resource Bundles

/// The name of the resource directory that Swift Package Manager builds for a target.
///
/// A target that declares resources gets a resource bundle named after its package and
/// itself, `<package>_<target>.resources`, which is placed beside the executables that link
/// the target. Where a ``Foundation/Bundle`` for the target is not available, such as on
/// WASI, ``BundledResources`` looks for this directory instead.
///
/// ```swift
/// let bundleName = ResourceBundleName(package: "swift-example", target: "Metamodels")
/// print(bundleName.directoryName)   // swift-example_Metamodels.resources
/// ```
public struct ResourceBundleName: Sendable, Hashable {
    /// The separator between the package name and the target name.
    public static let separator = "_"

    /// The extension of the resource directory, without the leading dot.
    public static let directoryExtension = "resources"

    /// The name of the package that declares the target, as given in its manifest.
    public let package: String

    /// The name of the target that declares the resources.
    public let target: String

    /// Creates the name of the resource directory of a target.
    ///
    /// - Parameters:
    ///   - package: The name of the package that declares the target.
    ///   - target: The name of the target that declares the resources.
    public init(package: String, target: String) {
        self.package = package
        self.target = target
    }

    /// The name of the resource directory, such as `swift-example_Metamodels.resources`.
    public var directoryName: String {
        package + Self.separator + target + "." + Self.directoryExtension
    }
}

/// Locates files that a package ships as resources.
///
/// On platforms with resource bundles, a resource is looked up in the ``Foundation/Bundle``
/// of its target, which a target obtains as `Bundle.module`. Where that bundle is not
/// available, the resource is looked up in the resource directory of the target (see
/// ``ResourceBundleName``) beside the running executable and in the current directory.
public enum BundledResources {
    /// Finds a file or directory that a target ships as a resource.
    ///
    /// With a bundle, the resource is looked up in it. Without one, or on WASI, where the
    /// bundle of a target cannot be used, the resource is looked up in the resource directory
    /// that `bundleName` names, first beside the running executable and then in the current
    /// directory.
    ///
    /// - Parameters:
    ///   - name: The name of the resource without its extension.
    ///   - ext: The extension, or `nil` for a directory or a file without an extension.
    ///   - subdirectory: The directory within the resource bundle that holds the resource, if any.
    ///   - bundle: The resource bundle of the target, or `nil` if it is not available.
    ///   - bundleName: The name of the resource directory of the target, if it is known.
    /// - Returns: The location of the resource, or `nil` if no accessible resource exists.
    public static func url(
        forResource name: String,
        withExtension ext: String?,
        subdirectory: String? = nil,
        in bundle: Bundle?,
        bundleName: ResourceBundleName? = nil
    ) -> URL? {
        #if !os(WASI)
        if let bundle {
            return bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
        }
        #endif
        guard let bundleName else { return nil }
        return url(
            forResource: name, withExtension: ext, subdirectory: subdirectory, bundleName: bundleName,
            searching: searchRoots)
    }

    /// The directories in which resource directories are looked for: that of the running
    /// executable, followed by the current directory.
    static var searchRoots: [URL] {
        var roots: [URL] = []
        if let executable = CommandLine.arguments.first {
            roots.append(URL(fileURLWithPath: executable).deletingLastPathComponent())
        }
        roots.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        return roots
    }

    /// Finds a resource in the resource directory of a target under one of several roots.
    ///
    /// - Parameters:
    ///   - name: The name of the resource without its extension.
    ///   - ext: The extension, or `nil` for a directory or a file without an extension.
    ///   - subdirectory: The directory within the resource directory, if any.
    ///   - bundleName: The name of the resource directory.
    ///   - roots: The directories that may hold the resource directory, in search order.
    /// - Returns: The location of the first existing resource, or `nil` if there is none.
    static func url(
        forResource name: String, withExtension ext: String?, subdirectory: String?,
        bundleName: ResourceBundleName, searching roots: [URL]
    ) -> URL? {
        for root in roots {
            var resource = root.appendingPathComponent(bundleName.directoryName, isDirectory: true)
            if let subdirectory { resource.appendPathComponent(subdirectory, isDirectory: true) }
            resource.appendPathComponent(name)
            if let ext { resource.appendPathExtension(ext) }
            if FileManager.default.fileExists(atPath: resource.path) { return resource }
        }
        return nil
    }
}

// MARK: - Metamodel Cache

/// Errors raised while a bundled metamodel is located.
public enum BundledMetamodelError: Error, Sendable, Equatable {
    /// The metamodel document is not among the resources of the target.
    ///
    /// The associated value is the file name of the document that was looked for.
    case resourceMissing(String)
}

extension BundledMetamodelError: CustomStringConvertible, LocalizedError {
    /// A sentence that describes the error and names the missing document.
    public var description: String {
        switch self {
        case .resourceMissing(let name):
            return "The bundled metamodel \(name) cannot be found among the package resources"
        }
    }

    /// The ``description`` of the error.
    public var errorDescription: String? { description }
}

/// Loads metamodel documents once and hands out the same packages afterwards.
///
/// Each document is loaded with ``EPackage/init(url:enableDebugging:)`` the first time it is
/// asked for. Later requests for the same location, including requests made while the first
/// load is still in progress, return the same package with the same element identifiers, so
/// that every part of a program refers to one metamodel. A load that fails is not cached and
/// is attempted again by the next request.
///
/// ``shared`` serves a whole program; a separate cache keeps its own packages.
public actor BundledMetamodelCache {
    /// The cache that ``EPackage/bundled(named:withExtension:subdirectory:in:bundleName:registeringIn:cache:)``
    /// uses unless it is given another one.
    public static let shared = BundledMetamodelCache()

    /// The loads that have succeeded or are in progress, by canonical document URI.
    private var loads: [String: Task<EPackage, Error>] = [:]

    /// Creates an empty cache.
    public init() {}

    /// The root package of a metamodel document, loaded on first use.
    ///
    /// - Parameter url: The location of the `.ecore` document.
    /// - Returns: The root package of the document, the same for every request.
    /// - Throws: The error of the loader if the document cannot be read or parsed.
    public func package(at url: URL) async throws -> EPackage {
        let key = URIReference.canonicalise(url.absoluteString)
        if let load = loads[key] { return try await load.value }
        let load = Task { () async throws -> EPackage in try await EPackage(url: url) }
        loads[key] = load
        do {
            return try await load.value
        } catch {
            loads[key] = nil
            throw error
        }
    }
}

// MARK: - Bundled Packages

extension EPackage {
    /// Loads a metamodel that a target ships as a resource.
    ///
    /// The document is located with ``BundledResources/url(forResource:withExtension:subdirectory:in:bundleName:)``
    /// and loaded through a ``BundledMetamodelCache``, so that every call for the same
    /// document returns the same package. If a resource set is given, the package is
    /// registered with it under its namespace URI, together with its nested packages.
    ///
    /// ```swift
    /// let package = try await EPackage.bundled(
    ///     named: "Library", subdirectory: "Resources", in: .module,
    ///     bundleName: ResourceBundleName(package: "swift-example", target: "Metamodels"),
    ///     registeringIn: resourceSet)
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the document without its extension.
    ///   - ext: The extension of the document (default `ecore`).
    ///   - subdirectory: The directory within the resource bundle that holds the document, if any.
    ///   - bundle: The resource bundle of the target, usually `.module`, or `nil` where it is
    ///     not available.
    ///   - bundleName: The name of the resource directory of the target, which is searched
    ///     where the bundle is not available, such as on WASI.
    ///   - resourceSet: A resource set with which to register the package, if any.
    ///   - cache: The cache through which the document is loaded (default ``BundledMetamodelCache/shared``).
    /// - Returns: The root package of the document.
    /// - Throws: ``BundledMetamodelError/resourceMissing(_:)`` if the document cannot be
    ///   found, or the error of the loader if it cannot be read or parsed.
    public static func bundled(
        named name: String,
        withExtension ext: String = ModelFormat.ecore.fileExtension,
        subdirectory: String? = nil,
        in bundle: Bundle?,
        bundleName: ResourceBundleName? = nil,
        registeringIn resourceSet: ResourceSet? = nil,
        cache: BundledMetamodelCache = .shared
    ) async throws -> EPackage {
        guard
            let url = BundledResources.url(
                forResource: name, withExtension: ext, subdirectory: subdirectory, in: bundle,
                bundleName: bundleName)
        else {
            throw BundledMetamodelError.resourceMissing(ext.isEmpty ? name : name + "." + ext)
        }
        let package = try await cache.package(at: url)
        await resourceSet?.registerMetamodel(package)
        return package
    }
}
