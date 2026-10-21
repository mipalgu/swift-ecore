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

    /// The identifiers of the root objects of the resource.
    private let roots: Set<EUUID>

    /// The warnings recorded while objects were written.
    private(set) var diagnostics = ConversionDiagnostics()

    /// Prepares to write the objects of a resource.
    ///
    /// The classes are qualified by the metamodels of the resource's set. If the set has been
    /// released, the metamodels that it held remain available through the resource.
    ///
    /// - Parameter resource: The resource to write.
    init(resource: Resource) async {
        self.resource = resource
        fragments = await JSONFragments.index(of: resource)
        roots = Set(await resource.getRootObjects().map(\.id))
        var registered: [EPackage] = []
        if let resourceSet = await resource.resourceSet {
            for uri in await resourceSet.getMetamodelURIs().sorted() {
                if let package = await resourceSet.getMetamodel(uri: uri) { registered.append(package) }
            }
        } else if let snapshot = await resource.metamodelSnapshot {
            registered = snapshot.all
        }
        packages = registered
    }

    /// The JSON dictionary of an object and everything it contains.
    ///
    /// The container side of a containment reference is left out of nested objects: it is
    /// implied by the nesting of the dictionaries. A root keeps it, since its container lies
    /// in another document.
    ///
    /// - Parameter object: The object to write.
    /// - Returns: The dictionary, with the `eClass` key, the set attributes, and the set references.
    /// - Throws: ``JSONError`` if a reference cannot be written.
    mutating func dictionary(for object: DynamicEObject) async throws -> [String: Any] {
        let current = await resource.resolve(object.id) as? DynamicEObject ?? object
        var result: [String: Any] = [JSONSyntax.eClassKey: className(of: current.eClass)]
        for attribute in current.eClass.allAttributes {
            guard current.eIsSet(attribute), let value = current.eGet(attribute) else { continue }
            if EMFDocumentWriter.holdsReferences(value) {
                result[attribute.name] = try await identifierJSON(value, feature: attribute.name, many: attribute.isMany, of: current)
            } else {
                result[attribute.name] = Self.json(for: value)
            }
        }
        let isRoot = roots.contains(current.id)
        for reference in current.eClass.allReferences where isRoot || !reference.isContainerSide {
            guard current.eIsSet(reference), let value = current.eGet(reference) else { continue }
            if let written = try await referenceJSON(value, for: reference, of: current) {
                result[reference.name] = written
            }
        }
        let defined = Set(current.eClass.allStructuralFeatures.map(\.name))
        for name in current.getFeatureNames() where !defined.contains(name) {
            if let value = current.eGet(name) { result[name] = try await dynamicJSON(value, feature: name, of: current) }
        }
        return result
    }

    // MARK: - Classes

    /// The `eClass` value of a class.
    ///
    /// A class of no registered package is written by its name alone and recorded as a
    /// ``ConversionWarning/Kind/untypedClass(name:)`` warning.
    ///
    /// - Parameter eClass: The class.
    /// - Returns: `"<nsURI>#//<Name>"`, or the bare name.
    private mutating func className(of eClass: EClass) -> String {
        if let known = classNames[eClass.id] { return known }
        var name = eClass.name
        var qualified = false
        for package in packages {
            if let found = Self.qualifiedName(of: eClass, in: package) {
                name = found
                qualified = true
                break
            }
        }
        if !qualified { diagnostics.record(.untypedClass(name: eClass.name)) }
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
    ///
    /// Object identifiers are written as they are and recorded as
    /// ``ConversionWarning/Kind/referenceWithoutFragment(feature:className:)`` warnings.
    ///
    /// - Parameters:
    ///   - value: The stored value.
    ///   - feature: The name of the feature.
    ///   - owner: The object that holds the value.
    /// - Returns: The JSON value.
    private mutating func dynamicJSON(_ value: any EcoreValue, feature: String, of owner: DynamicEObject) async throws
        -> Any
    {
        switch value {
        case let object as DynamicEObject: return try await dictionary(for: object)
        case let objects as [DynamicEObject]:
            var result: [[String: Any]] = []
            for object in objects { result.append(try await dictionary(for: object)) }
            return result
        case let value where EMFDocumentWriter.holdsReferences(value):
            return try await identifierJSON(value, feature: feature, many: value is [EUUID] || value is [ResourceProxy], of: owner)
        default: return Self.json(for: value)
        }
    }

    /// The JSON value of a feature that holds identifiers without being declared as a reference.
    ///
    /// Untyped documents hold their references this way. Each identifier of an object with a
    /// fragment is written as a `$ref` object; any other identifier is written as it is and
    /// recorded as a ``ConversionWarning/Kind/referenceWithoutFragment(feature:className:)`` warning.
    ///
    /// - Parameters:
    ///   - value: The stored identifier, proxy, or list of either.
    ///   - feature: The name of the feature.
    ///   - many: Whether the feature is written as an array.
    ///   - owner: The object that holds the value.
    /// - Returns: The JSON value.
    private mutating func identifierJSON(
        _ value: any EcoreValue, feature: String, many: Bool, of owner: DynamicEObject
    ) async throws -> Any {
        let reference = EReference(name: feature, eType: EClass(name: SynthesisedClasses.defaultClassName))
        var entries: [Any] = []
        for target in Self.targets(of: value) {
            entries.append(try await entry(for: target, reference: reference, of: owner))
        }
        return many || entries.count != 1 ? entries : entries[0]
    }

    /// The JSON value of a reference.
    ///
    /// - Parameters:
    ///   - value: The stored value.
    ///   - reference: The declared reference.
    ///   - owner: The object that holds the reference.
    /// - Returns: The nested dictionaries of contained objects and `$ref` objects of referenced
    ///   ones, as an array for a many-valued reference, or `nil` if there is nothing to write.
    private mutating func referenceJSON(_ value: any EcoreValue, for reference: EReference, of owner: DynamicEObject)
        async throws -> Any?
    {
        var entries: [Any] = []
        switch value {
        case let object as DynamicEObject: entries = [try await dictionary(for: object)]
        case let objects as [DynamicEObject]:
            for object in objects { entries.append(try await dictionary(for: object)) }
        default:
            for target in Self.targets(of: value) {
                entries.append(try await entry(for: target, reference: reference, of: owner))
            }
        }
        if entries.isEmpty { return nil }
        return reference.isMany || entries.count > 1 ? entries : entries[0]
    }

    /// The JSON value of one target of a reference.
    ///
    /// A contained object that the resource does not hold, a reference to a proxy into the
    /// written document, and a reference that has to be written as an object identifier are
    /// recorded as warnings.
    ///
    /// - Parameters:
    ///   - target: The identifier or proxy.
    ///   - reference: The declared reference.
    ///   - owner: The object that holds the reference.
    /// - Returns: A nested dictionary, a `$ref` object, or the identifier text.
    private mutating func entry(for target: any EcoreValue, reference: EReference, of owner: DynamicEObject)
        async throws -> Any
    {
        if let proxy = target as? ResourceProxy {
            if await EMFDocumentWriter.isDangling(proxy, in: resource) {
                diagnostics.record(.unresolvedProxy(uri: proxy.uri, fragment: proxy.fragment))
            }
            return [JSONSyntax.referenceKey: JSONFragments.reference(
                uri: proxy.uri, fragment: proxy.fragment, from: resource.uri)]
        }
        guard let identifier = target as? EUUID else {
            diagnostics.record(.referenceWithoutFragment(feature: reference.name, className: owner.eClass.name))
            return String(describing: target)
        }
        if reference.containment, let child = await resource.resolve(identifier) as? DynamicEObject {
            return try await dictionary(for: child)
        }
        if let text = await referenceText(to: identifier) { return [JSONSyntax.referenceKey: text] }
        if reference.containment, await resource.resolve(identifier) == nil {
            diagnostics.record(.unregisteredContainedObject(className: reference.eType.name))
        } else {
            diagnostics.record(.referenceWithoutFragment(feature: reference.name, className: owner.eClass.name))
        }
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
