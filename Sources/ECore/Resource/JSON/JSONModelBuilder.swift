//
// JSONModelBuilder.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// The classes of the metamodels that are registered with a resource set.
struct MetamodelClasses: JSONClassResolver {
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

    /// Finds the class that the `eClass` value of an object held by a reference names.
    ///
    /// A package-qualified value names its class directly. A bare name is looked up among
    /// the declared type and its subclasses in the registered packages first, so that a
    /// name shared by classes of several packages selects the one the reference admits.
    ///
    /// - Parameters:
    ///   - identifier: `"<nsURI>#//<Name>"` or a bare `"<Name>"`.
    ///   - expected: The declared type of the reference.
    /// - Returns: The registered class, or `nil` if none matches.
    func resolve(_ identifier: String, below expected: EClass) -> EClass? {
        let parts = URIReference.split(identifier)
        guard parts.fragment == nil || parts.uri.isEmpty else { return resolve(identifier) }
        let name = jsonClassName(of: identifier)
        if expected.name == name { return expected }
        for uri in order {
            guard let package = packages[uri] else { continue }
            if let found = Self.subclass(named: name, of: expected, in: package) { return found }
        }
        return resolve(identifier)
    }

    /// Finds a class of a package or its subpackages that the declared type of a reference admits.
    ///
    /// - Parameters:
    ///   - name: The name of the class.
    ///   - expected: The declared type of the reference.
    ///   - package: The package to search.
    /// - Returns: The class of that name if it is `expected` or one of its subclasses, otherwise `nil`.
    private static func subclass(named name: String, of expected: EClass, in package: EPackage) -> EClass? {
        if let found = package.getEClass(name), found.id == expected.id || expected.isSuperTypeOf(found) {
            return found
        }
        for sub in package.eSubpackages {
            if let found = subclass(named: name, of: expected, in: sub) { return found }
        }
        return nil
    }
}

/// The references of one feature of one object that are linked once all objects exist.
private struct PendingLink {
    /// One entry of the feature in the document.
    enum Item {
        /// A nested object, built from the document.
        case object(EUUID)

        /// The text of a `$ref` object: a fragment, or a document URI and fragment.
        case reference(String)

        /// A bare string, as earlier releases wrote references: an identifier or a fragment.
        case text(String)
    }

    /// The identifier of the object that holds the feature.
    let owner: EUUID

    /// The name of the class of the object that holds the feature.
    let ownerClass: String

    /// The feature.
    let feature: EReference

    /// The entries of the feature in document order.
    let items: [Item]
}

/// Builds the objects of a JSON document from the classes of registered metamodels or of
/// classes synthesised from the document.
///
/// Every object, including every nested one, is registered with the resource, and contained
/// objects are held by their identifiers.
struct JSONModelBuilder {
    private let classes: any JSONClassResolver
    private let factory = EFactory(ePackage: EPackage(name: ""))
    private var objects: [DynamicEObject] = []
    private var links: [PendingLink] = []

    /// The objects by the values of their identifier attributes.
    private var identified: [String: EUUID] = [:]

    /// The classes found for the `eClass` values of nested objects, by value and declared type.
    private var nestedClasses: [String: [EUUID: EClass]] = [:]

    /// The warnings recorded while the objects were built.
    private(set) var diagnostics = ConversionDiagnostics()

    /// Creates a builder.
    ///
    /// - Parameter classes: The classes that the document may use.
    init(classes: any JSONClassResolver) {
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
        let rootSet = Set(rootIdentifiers)
        for link in links where !(link.feature.isContainerSide && !rootSet.contains(link.owner)) {
            await linkReferences(of: link, in: resource)
        }
    }

    // MARK: - Building

    private mutating func build(_ document: [String: Any], expected: EClass?) throws -> DynamicEObject {
        let eClass = try resolveClass(of: document, expected: expected)
        var object = DynamicEObject(eClass: eClass)
        for attribute in eClass.allAttributes {
            guard let json = document[attribute.name], !(json is NSNull) else { continue }
            let value = try convert(json, for: attribute)
            object.eSet(attribute, value)
            if attribute.isID, let identifier = value as? String, identified[identifier] == nil {
                identified[identifier] = object.id
            }
        }
        var known = Set([JSONSyntax.eClassKey])
        known.formUnion(eClass.allAttributes.map(\.name))
        for reference in eClass.allReferences {
            known.insert(reference.name)
            guard let json = document[reference.name], !(json is NSNull) else { continue }
            var items: [PendingLink.Item] = []
            for entry in (json as? [Any]) ?? [json] {
                if let text = entry as? String {
                    items.append(.text(text))
                } else if let nested = entry as? [String: Any] {
                    if let target = nested[JSONSyntax.referenceKey] as? String {
                        items.append(.reference(target))
                    } else {
                        items.append(.object(try build(nested, expected: reference.eType as? EClass).id))
                    }
                }
            }
            if !items.isEmpty {
                links.append(PendingLink(owner: object.id, ownerClass: eClass.name, feature: reference, items: items))
            }
        }
        for (key, json) in document.sorted(by: { $0.key < $1.key }) where !known.contains(key) && !(json is NSNull) {
            if let value = Self.scalar(json) {
                object.eSet(key, value: value)
            } else if (json as? [Any])?.isEmpty != true {
                diagnostics.record(.droppedFeature(name: key, className: eClass.name))
            }
        }
        objects.append(object)
        return object
    }

    /// Finds the class of an object.
    ///
    /// The class is the one that the object's `eClass` entry names, looked up below the
    /// declared type of the reference that holds the object first; without an entry, or if
    /// the entry names no known class, it is the declared type. The classes of nested objects
    /// are remembered by entry and declared type, so that each pair is looked up once.
    ///
    /// - Parameters:
    ///   - document: The JSON object.
    ///   - expected: The declared type of the reference that holds the object, or `nil` for a root.
    /// - Returns: The class to build the object from.
    /// - Throws: ``JSONError/unresolvedMetamodel(_:)`` if a root names an unknown class, or
    ///   ``JSONError/missingEClass`` if a root names no class.
    private mutating func resolveClass(of document: [String: Any], expected: EClass?) throws -> EClass {
        if let identifier = document[JSONSyntax.eClassKey] as? String {
            if let expected {
                if let known = nestedClasses[identifier]?[expected.id] { return known }
                let found = classes.resolve(identifier, below: expected) ?? classes.resolve(identifier)
                    ?? classes.refined(expected)
                nestedClasses[identifier, default: [:]][expected.id] = found
                return found
            }
            if let resolved = classes.resolve(identifier) { return resolved }
            throw JSONError.unresolvedMetamodel("No registered metamodel defines the class \(identifier)")
        }
        guard let expected else { throw JSONError.missingEClass }
        return classes.refined(expected)
    }

    /// An untyped JSON scalar as a value, for keys that the class does not define.
    ///
    /// - Parameter json: The JSON value.
    /// - Returns: The string, Boolean, integer, or floating-point value, or `nil` for any other value.
    private static func scalar(_ json: Any) -> (any EcoreValue)? {
        switch JSONScalarKind.of(json) {
        case .string: return json as? String
        case .boolean: return (json as? NSNumber)?.boolValue ?? (json as? Bool)
        case .integer: return (json as? NSNumber)?.intValue ?? (json as? Int)
        case .double: return (json as? NSNumber)?.doubleValue ?? (json as? Double)
        case nil: return nil
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
                .contains(dataType.name) || JSONScalarKind.of(number) == .boolean
            literal = isBoolean ? (number.boolValue ? "true" : "false") : number.stringValue
        default: throw mismatch(json, attribute)
        }
        if dataType.name == EcoreDataType.eDate.rawValue {
            guard let date = EcoreDateCoding.date(from: literal) else { throw mismatch(json, attribute) }
            return date
        }
        guard let value = factory.createFromString(dataType, literal) else { throw mismatch(json, attribute) }
        return value
    }

    private func mismatch(_ json: Any, _ attribute: EAttribute) -> JSONError {
        JSONError.parseError("Cannot convert \(json) to \(attribute.eType.name) for attribute \(attribute.name)")
    }

    // MARK: - Linking

    /// Stores the objects a feature refers to, resolving the references of the document.
    ///
    /// A reference into the document that names no object is kept as a proxy and recorded as
    /// a ``ConversionWarning/Kind/unresolvedProxy(uri:fragment:)`` warning. A bare string, as
    /// earlier releases wrote references, denotes the object whose identifier attribute holds
    /// that value. Failing that, a string that is a fragment or URI is resolved like a `$ref`,
    /// and any other string is kept as a proxy and recorded as a
    /// ``ConversionWarning/Kind/referenceWithoutFragment(feature:className:)`` warning. Such a
    /// proxy is left out of a containment, which holds objects of the document only.
    private mutating func linkReferences(of link: PendingLink, in resource: Resource) async {
        let ownURI = resource.uri
        var targets: [JSONReferenceTarget] = []
        for item in link.items {
            switch item {
            case .object(let identifier):
                if !link.feature.containment { targets.append(.object(identifier)) }
            case .text(let text):
                if let identifier = identified[text] {
                    targets.append(.object(identifier))
                } else if Self.isIdentifierReference(text) {
                    diagnostics.record(.referenceWithoutFragment(feature: link.feature.name, className: link.ownerClass))
                    targets.append(.proxy(ResourceProxy(uri: ownURI, fragment: text)))
                } else {
                    targets.append(await resolveFragment(text, in: resource))
                }
            case .reference(let text):
                targets.append(await resolveFragment(text, in: resource))
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

    /// Resolves the text of a reference as a fragment or a document URI and fragment.
    ///
    /// A reference into the document that names no object is recorded as a
    /// ``ConversionWarning/Kind/unresolvedProxy(uri:fragment:)`` warning.
    ///
    /// - Parameters:
    ///   - text: The text of the reference.
    ///   - resource: The resource being built.
    /// - Returns: The object of the resource, or a proxy.
    private mutating func resolveFragment(_ text: String, in resource: Resource) async -> JSONReferenceTarget {
        let target = await JSONFragments.resolve(text, from: resource)
        if case .proxy(let proxy) = target, proxy.uri == resource.uri {
            diagnostics.record(.unresolvedProxy(uri: proxy.uri, fragment: proxy.fragment))
        }
        return target
    }

    /// Whether the text of a reference is a bare identifier rather than a fragment or a URI.
    ///
    /// - Parameter text: The text of the reference.
    /// - Returns: `true` if the text holds no `#`, no `/`, and no `:`.
    static func isIdentifierReference(_ text: String) -> Bool {
        !text.isEmpty && !text.contains(CrossReferenceSyntax.fragmentSeparator)
            && !text.contains(CrossReferenceSyntax.segmentSeparator)
            && !text.contains(CrossReferenceSyntax.qualifierSeparator)
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
