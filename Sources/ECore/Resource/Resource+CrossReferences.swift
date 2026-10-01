//
// Resource+CrossReferences.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// The outcome of resolving cross-resource proxies.
///
/// A report counts the proxies that were replaced by direct references and
/// lists the proxies whose target could not be found (for example because the
/// target file is missing or the fragment names no element).
public struct ProxyResolutionReport: Sendable, Equatable {
    /// The number of proxies that were replaced by direct references.
    public var resolved: Int

    /// The proxies that could not be resolved and remain in place.
    public var unresolved: [ResourceProxy]

    /// Creates a report.
    ///
    /// - Parameters:
    ///   - resolved: The number of resolved proxies (default 0).
    ///   - unresolved: The proxies that remain unresolved (default empty).
    public init(resolved: Int = 0, unresolved: [ResourceProxy] = []) {
        self.resolved = resolved
        self.unresolved = unresolved
    }

    /// Adds the counts and unresolved proxies of another report to this one.
    ///
    /// - Parameter other: The report to merge in.
    public mutating func merge(_ other: ProxyResolutionReport) {
        resolved += other.resolved
        unresolved += other.unresolved
    }
}

extension Resource {
    /// Registers a native package and every element it contains.
    ///
    /// The package becomes a root object of the resource. Its subpackages, classifiers,
    /// features, and enumeration literals are registered so that they can be found by
    /// identifier and through name-based fragments (see ``FragmentNavigator``).
    ///
    /// - Parameter package: The native package to register.
    public func registerNativePackage(_ package: EPackage) {
        registerNativeElements(of: package)
        add(package)
    }

    /// Replaces cross-resource proxies by direct references.
    ///
    /// Every single-valued or multi-valued reference value that is a ``ResourceProxy``
    /// is resolved through the resource set, loading target resources on demand
    /// relative to the proxy's URI. Resolved values become identifiers of objects in
    /// the target resource; the resource set can map such an identifier back to its
    /// object and resource. A multi-valued reference is replaced only when all of
    /// its proxies resolve; otherwise it is left untouched and its proxies are reported.
    ///
    /// - Returns: A report with the number of resolved proxies and the unresolved ones.
    @discardableResult
    public func resolveProxies() async -> ProxyResolutionReport {
        var report = ProxyResolutionReport()
        for object in getAllObjects() {
            guard object is DynamicEObject else { continue }
            for feature in getFeatureNames(objectId: object.id) {
                let value = eGet(objectId: object.id, feature: feature)
                let proxies: [ResourceProxy]
                if let proxy = value as? ResourceProxy {
                    proxies = [proxy]
                } else if let list = value as? [ResourceProxy] {
                    proxies = list
                } else {
                    continue
                }

                var targets: [EUUID] = []
                for proxy in proxies {
                    guard let target = await resolveTarget(of: proxy) else { break }
                    targets.append(target)
                }
                guard targets.count == proxies.count else {
                    report.unresolved += proxies
                    continue
                }
                report.resolved += proxies.count
                let replacement: any EcoreValue = value is ResourceProxy ? targets[0] : targets
                await eSet(objectId: object.id, feature: feature, value: replacement)
            }
        }
        return report
    }

    /// Reads a reference value, resolving any cross-resource proxies first.
    ///
    /// If the feature holds a ``ResourceProxy`` (or a list of them) that can be
    /// resolved, the stored value is replaced by the resolved identifier(s) and
    /// returned. Unresolvable values and all other values are returned as stored.
    ///
    /// - Parameters:
    ///   - objectId: The identifier of the object to query.
    ///   - featureName: The name of the reference feature.
    /// - Returns: The (resolved) value of the feature, or `nil` if it is not set.
    public func eGetResolving(objectId: EUUID, feature featureName: String) async -> (any EcoreValue)? {
        let value = eGet(objectId: objectId, feature: featureName)
        if let proxy = value as? ResourceProxy {
            guard let target = await resolveTarget(of: proxy) else { return value }
            await eSet(objectId: objectId, feature: featureName, value: target)
            return target
        }
        if let proxies = value as? [ResourceProxy] {
            var targets: [EUUID] = []
            for proxy in proxies {
                guard let target = await resolveTarget(of: proxy) else { return value }
                targets.append(target)
            }
            await eSet(objectId: objectId, feature: featureName, value: targets)
            return targets
        }
        return value
    }

    /// Resolves a proxy to the identifier of its target object.
    ///
    /// - Parameter proxy: The proxy to resolve.
    /// - Returns: The target identifier, or `nil` if the target cannot be found.
    private func resolveTarget(of proxy: ResourceProxy) async -> EUUID? {
        if proxy.uri == uri {
            let fragment = proxy.fragment.hasPrefix(String(CrossReferenceSyntax.fragmentSeparator))
                ? proxy.fragment : String(CrossReferenceSyntax.fragmentSeparator) + proxy.fragment
            return await XPathResolver(resource: self).resolve(fragment)
        }
        guard let resourceSet else { return nil }
        return await proxy.resolve(in: resourceSet)
    }

    /// Registers the subpackages, classifiers, and features of a native package.
    ///
    /// - Parameter package: The package whose contents are registered.
    private func registerNativeElements(of package: EPackage) {
        register(package)
        for classifier in package.eClassifiers {
            switch classifier {
            case let eClass as EClass:
                register(eClass)
                for feature in eClass.eStructuralFeatures {
                    if let object = feature as? any EObject { register(object) }
                }
            case let eEnum as EEnum:
                register(eEnum)
                for literal in eEnum.literals { register(literal) }
            case let object as any EObject:
                register(object)
            default:
                break
            }
        }
        for subpackage in package.eSubpackages {
            registerNativeElements(of: subpackage)
        }
    }
}
