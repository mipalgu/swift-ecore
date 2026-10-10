//
// JSONWritingContext.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// The state that the JSON serialiser needs to turn the objects of a resource into JSON values.
struct JSONWritingContext {
    private let resource: Resource
    private let fragments: [EUUID: String]
    private let packages: [EPackage]
    private var classNames: [EUUID: String] = [:]
    private var remoteFragments: [String: [EUUID: String]] = [:]

    /// Prepares to write the objects of a resource.
    ///
    /// - Parameter resource: The resource to write.
    init(resource: Resource) async {
        self.resource = resource
        fragments = await JSONFragments.index(of: resource)
        var registered: [EPackage] = []
        if let resourceSet = await resource.resourceSet {
            for uri in await resourceSet.getMetamodelURIs().sorted() {
                if let package = await resourceSet.getMetamodel(uri: uri) { registered.append(package) }
            }
        }
        packages = registered
    }

    /// The JSON dictionary of an object and everything it contains.
    ///
    /// - Parameter object: The object to write.
    /// - Returns: The dictionary, with the `eClass` key, the set attributes, and the set references.
    /// - Throws: ``JSONError`` if a reference cannot be written.
    mutating func dictionary(for object: DynamicEObject) async throws -> [String: Any] {
        let current = await resource.resolve(object.id) as? DynamicEObject ?? object
        var result: [String: Any] = [JSONSyntax.eClassKey: className(of: current.eClass)]
        for attribute in current.eClass.allAttributes {
            guard current.eIsSet(attribute), let value = current.eGet(attribute) else { continue }
            result[attribute.name] = Self.json(for: value)
        }
        for reference in current.eClass.allReferences {
            guard current.eIsSet(reference), let value = current.eGet(reference) else { continue }
            if let written = try await referenceJSON(value, for: reference) { result[reference.name] = written }
        }
        let defined = Set(current.eClass.allStructuralFeatures.map(\.name))
        for name in current.getFeatureNames() where !defined.contains(name) {
            if let value = current.eGet(name) { result[name] = try await dynamicJSON(value) }
        }
        return result
    }

    // MARK: - Classes

    private mutating func className(of eClass: EClass) -> String {
        if let known = classNames[eClass.id] { return known }
        var name = eClass.name
        for package in packages {
            if let qualified = Self.qualifiedName(of: eClass, in: package) {
                name = qualified
                break
            }
        }
        classNames[eClass.id] = name
        return name
    }

    private static func qualifiedName(of eClass: EClass, in package: EPackage) -> String? {
        if !package.nsURI.isEmpty, package.eClassifiers.contains(where: { $0.id == eClass.id }) {
            return package.nsURI + JSONSyntax.classFragmentPrefix + eClass.name
        }
        for sub in package.eSubpackages {
            if let found = qualifiedName(of: eClass, in: sub) { return found }
        }
        return nil
    }

    // MARK: - Values

    /// The JSON value of an attribute value.
    private static func json(for value: any EcoreValue) -> Any {
        switch value {
        case let string as String: return string
        case let int as Int: return int
        case let bool as Bool: return bool
        case let double as Double: return double
        case let float as Float: return Double(String(float)) ?? Double(float)
        case let date as Date: return EcoreDateCoding.fractionalString(from: date)
        case let array as EcoreValueArray: return array.values.map { json(for: $0) }
        case let array as [any EcoreValue]: return array.map { json(for: $0) }
        default: return String(describing: value)
        }
    }

    /// The JSON value of a feature that the class does not define.
    private mutating func dynamicJSON(_ value: any EcoreValue) async throws -> Any {
        switch value {
        case let object as DynamicEObject: return try await dictionary(for: object)
        case let objects as [DynamicEObject]:
            var result: [[String: Any]] = []
            for object in objects { result.append(try await dictionary(for: object)) }
            return result
        case let identifier as EUUID: return identifier.uuidString
        default: return Self.json(for: value)
        }
    }

    private mutating func referenceJSON(_ value: any EcoreValue, for reference: EReference) async throws -> Any? {
        var entries: [Any] = []
        switch value {
        case let object as DynamicEObject: entries = [try await dictionary(for: object)]
        case let objects as [DynamicEObject]:
            for object in objects { entries.append(try await dictionary(for: object)) }
        default:
            for target in Self.targets(of: value) {
                entries.append(try await entry(for: target, containment: reference.containment))
            }
        }
        if entries.isEmpty { return nil }
        return reference.isMany || entries.count > 1 ? entries : entries[0]
    }

    private mutating func entry(for target: any EcoreValue, containment: Bool) async throws -> Any {
        if let proxy = target as? ResourceProxy {
            return [JSONSyntax.referenceKey: JSONFragments.reference(
                uri: proxy.uri, fragment: proxy.fragment, from: resource.uri)]
        }
        guard let identifier = target as? EUUID else { return String(describing: target) }
        if containment, let child = await resource.resolve(identifier) as? DynamicEObject {
            return try await dictionary(for: child)
        }
        if let text = await referenceText(to: identifier) { return [JSONSyntax.referenceKey: text] }
        return identifier.uuidString
    }

    private mutating func referenceText(to identifier: EUUID) async -> String? {
        if let local = fragments[identifier] { return local }
        guard let resourceSet = await resource.resourceSet,
            let located = await resourceSet.resolve(identifier), located.resource !== resource
        else { return nil }
        let uri = located.resource.uri
        if remoteFragments[uri] == nil { remoteFragments[uri] = await JSONFragments.index(of: located.resource) }
        guard let fragment = remoteFragments[uri]?[identifier] else { return nil }
        return JSONFragments.reference(uri: uri, fragment: fragment, from: resource.uri)
    }

    private static func targets(of value: any EcoreValue) -> [any EcoreValue] {
        switch value {
        case let identifier as EUUID: return [identifier]
        case let proxy as ResourceProxy: return [proxy]
        case let identifiers as [EUUID]: return identifiers
        case let proxies as [ResourceProxy]: return proxies
        case let array as EcoreValueArray: return array.values
        default: return []
        }
    }
}
