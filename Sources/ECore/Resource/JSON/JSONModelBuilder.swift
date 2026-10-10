//
// JSONModelBuilder.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// The classes of the metamodels that are registered with a resource set.
struct MetamodelClasses: Sendable {
    /// The registered packages by namespace URI.
    private let packages: [String: EPackage]

    /// The namespace URIs in the deterministic order in which bare class names are searched.
    private let order: [String]

    /// Captures the metamodels registered with a resource set.
    ///
    /// - Parameter resourceSet: The resource set, if any.
    /// - Returns: The captured classes, or `nil` if there is no resource set or no metamodel.
    init?(resourceSet: ResourceSet?) async {
        guard let resourceSet else { return nil }
        let uris = await resourceSet.getMetamodelURIs().sorted()
        var captured: [String: EPackage] = [:]
        for uri in uris {
            if let package = await resourceSet.getMetamodel(uri: uri) { captured[uri] = package }
        }
        guard !captured.isEmpty else { return nil }
        packages = captured
        order = uris.filter { captured[$0] != nil }
    }

    /// The package that has a namespace URI, including nested packages.
    private func package(nsURI: String) -> EPackage? {
        if let registered = packages[nsURI] { return registered }
        for uri in order {
            if let found = packages[uri].flatMap({ Self.nested(nsURI, in: $0) }) { return found }
        }
        return nil
    }

    private static func nested(_ nsURI: String, in package: EPackage) -> EPackage? {
        if package.nsURI == nsURI { return package }
        for sub in package.eSubpackages {
            if let found = nested(nsURI, in: sub) { return found }
        }
        return nil
    }

    private static func find(_ name: String, in package: EPackage) -> EClass? {
        if let found = package.getEClass(name) { return found }
        for sub in package.eSubpackages {
            if let found = find(name, in: sub) { return found }
        }
        return nil
    }

    /// Finds the class that a JSON `eClass` value names.
    ///
    /// - Parameter identifier: `"<nsURI>#//<Name>"` or a bare `"<Name>"`.
    /// - Returns: The registered class, or `nil` if none matches.
    func resolve(_ identifier: String) -> EClass? {
        let parts = URIReference.split(identifier)
        guard let fragment = parts.fragment else {
            for uri in order {
                if let found = packages[uri].flatMap({ Self.find(identifier, in: $0) }) { return found }
            }
            return nil
        }
        let name = fragment.split(separator: CrossReferenceSyntax.segmentSeparator).last.map(String.init) ?? fragment
        if parts.uri.isEmpty { return resolve(name) }
        return package(nsURI: parts.uri).flatMap { Self.find(name, in: $0) }
    }
}

/// The references of one feature of one object that are linked once all objects exist.
private struct PendingLink {
    enum Item {
        case object(EUUID)
        case reference(String)
    }

    let owner: EUUID
    let feature: EReference
    let items: [Item]
}

/// Builds the objects of a JSON document from the classes of registered metamodels.
struct JSONModelBuilder {
    private let classes: MetamodelClasses
    private let factory = EFactory(ePackage: EPackage(name: ""))
    private var objects: [DynamicEObject] = []
    private var links: [PendingLink] = []

    /// Creates a builder.
    ///
    /// - Parameter classes: The registered classes that the document may use.
    init(classes: MetamodelClasses) {
        self.classes = classes
    }

    /// Builds the objects of the documents and adds them to a resource.
    ///
    /// - Parameters:
    ///   - resource: The resource that receives the objects.
    ///   - documents: The JSON objects of the roots.
    /// - Throws: ``JSONError`` if a class is unknown or a value does not fit its data type.
    mutating func populate(_ resource: Resource, from documents: [[String: Any]]) async throws {
        var rootIdentifiers: [EUUID] = []
        for document in documents {
            rootIdentifiers.append(try build(document, expected: nil).id)
        }
        for object in objects { await resource.register(object) }
        for link in links where link.feature.containment {
            await store(link.items.compactMap(\.objectIdentifier), for: link, in: resource)
        }
        var roots: [any EObject] = []
        for identifier in rootIdentifiers {
            if let root = await resource.resolve(identifier) { roots.append(root) }
        }
        await resource.add(contentsOf: roots)
        for link in links { await linkReferences(of: link, in: resource) }
    }

    // MARK: - Building

    private mutating func build(_ document: [String: Any], expected: EClass?) throws -> DynamicEObject {
        let eClass = try resolveClass(of: document, expected: expected)
        var object = DynamicEObject(eClass: eClass)
        for attribute in eClass.allAttributes {
            guard let json = document[attribute.name], !(json is NSNull) else { continue }
            object.eSet(attribute, try convert(json, for: attribute))
        }
        var known = Set([JSONSyntax.eClassKey])
        known.formUnion(eClass.allAttributes.map(\.name))
        for reference in eClass.allReferences {
            known.insert(reference.name)
            guard let json = document[reference.name], !(json is NSNull) else { continue }
            var items: [PendingLink.Item] = []
            for entry in (json as? [Any]) ?? [json] {
                if let text = entry as? String {
                    items.append(.reference(text))
                } else if let nested = entry as? [String: Any] {
                    if let target = nested[JSONSyntax.referenceKey] as? String {
                        items.append(.reference(target))
                    } else {
                        items.append(.object(try build(nested, expected: reference.eType as? EClass).id))
                    }
                }
            }
            if !items.isEmpty { links.append(PendingLink(owner: object.id, feature: reference, items: items)) }
        }
        for (key, json) in document where !known.contains(key) {
            if let value = Self.scalar(json) { object.eSet(key, value: value) }
        }
        objects.append(object)
        return object
    }

    private func resolveClass(of document: [String: Any], expected: EClass?) throws -> EClass {
        if let identifier = document[JSONSyntax.eClassKey] as? String {
            if let resolved = classes.resolve(identifier) { return resolved }
            if let expected { return expected }
            throw JSONError.unresolvedMetamodel("No registered metamodel defines the class \(identifier)")
        }
        guard let expected else { throw JSONError.missingEClass }
        return expected
    }

    /// An untyped JSON scalar as a value, for keys that the class does not define.
    private static func scalar(_ json: Any) -> (any EcoreValue)? {
        switch json {
        case let text as String: return text
        case let number as NSNumber:
            let isFloatingPoint = ["f", "d"].contains(String(cString: number.objCType))
            return isFloatingPoint ? number.doubleValue : number.intValue
        default: return nil
        }
    }

    // MARK: - Attribute Values

    private func convert(_ json: Any, for attribute: EAttribute) throws -> (any EcoreValue)? {
        guard attribute.isMany else { return try single(json, for: attribute) }
        let values = try ((json as? [Any]) ?? [json]).compactMap { try single($0, for: attribute) }
        if let strings = values as? [String] { return strings }
        if let integers = values as? [Int] { return integers }
        if let doubles = values as? [Double] { return doubles }
        if let flags = values as? [Bool] { return flags }
        return EcoreValueArray(values)
    }

    private func single(_ json: Any, for attribute: EAttribute) throws -> (any EcoreValue)? {
        if let eEnum = attribute.eType as? EEnum {
            if let text = json as? String { return eEnum.storedValue(forText: text) }
            if let number = json as? NSNumber {
                return eEnum.getLiteral(value: number.intValue)?.name ?? number.stringValue
            }
            throw mismatch(json, attribute)
        }
        guard let dataType = attribute.eType as? EDataType else { throw mismatch(json, attribute) }
        let literal: String
        switch json {
        case let text as String: literal = text
        case let number as NSNumber:
            let isBoolean = [EcoreDataType.eBoolean.rawValue, EcoreDataType.eBooleanObject.rawValue]
                .contains(dataType.name)
            literal = isBoolean ? (number.boolValue ? "true" : "false") : number.stringValue
        default: throw mismatch(json, attribute)
        }
        guard let value = factory.createFromString(dataType, literal) else { throw mismatch(json, attribute) }
        return value
    }

    private func mismatch(_ json: Any, _ attribute: EAttribute) -> JSONError {
        JSONError.parseError("Cannot convert \(json) to \(attribute.eType.name) for attribute \(attribute.name)")
    }

    // MARK: - Linking

    /// Stores the objects a feature refers to, resolving the references of the document.
    private func linkReferences(of link: PendingLink, in resource: Resource) async {
        let ownURI = resource.uri
        var targets: [JSONReferenceTarget] = []
        for item in link.items {
            switch item {
            case .object(let identifier):
                if !link.feature.containment { targets.append(.object(identifier)) }
            case .reference(let text):
                targets.append(await JSONFragments.resolve(text, from: resource))
            }
        }
        if link.feature.containment {
            guard !targets.isEmpty else { return }
            var identifiers = identifiers(of: await resource.eGet(objectId: link.owner, feature: link.feature.name))
            identifiers += targets.compactMap(\.objectIdentifier)
            await store(identifiers, for: link, in: resource)
            return
        }
        let identifiers = targets.compactMap(\.objectIdentifier)
        if identifiers.count == targets.count {
            await store(identifiers, for: link, in: resource)
            return
        }
        var proxies: [ResourceProxy] = []
        for target in targets {
            switch target {
            case .proxy(let proxy): proxies.append(proxy)
            case .object(let identifier):
                let fragment = await JSONFragments.fragment(for: identifier, in: resource) ?? ""
                proxies.append(ResourceProxy(uri: ownURI, fragment: fragment))
            }
        }
        let value: any EcoreValue = link.feature.isMany || proxies.count > 1 ? proxies : proxies[0]
        await resource.eSet(objectId: link.owner, feature: link.feature.name, value: value)
    }

    private func identifiers(of value: (any EcoreValue)?) -> [EUUID] {
        switch value {
        case let identifier as EUUID: return [identifier]
        case let identifiers as [EUUID]: return identifiers
        default: return []
        }
    }

    private func store(_ identifiers: [EUUID], for link: PendingLink, in resource: Resource) async {
        guard !identifiers.isEmpty else { return }
        let value: any EcoreValue = link.feature.isMany || identifiers.count > 1 ? identifiers : identifiers[0]
        await resource.eSet(objectId: link.owner, feature: link.feature.name, value: value)
    }
}

private extension PendingLink.Item {
    var objectIdentifier: EUUID? {
        if case .object(let identifier) = self { return identifier }
        return nil
    }
}

private extension JSONReferenceTarget {
    var objectIdentifier: EUUID? {
        if case .object(let identifier) = self { return identifier }
        return nil
    }
}
