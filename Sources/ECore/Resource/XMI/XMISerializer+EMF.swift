//
// XMISerializer+EMF.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

extension XMISerializer {
    /// Serialises a resource using the EMF-style layout selected by the serialiser's options.
    ///
    /// - Parameters:
    ///   - resource: The resource to serialise.
    ///   - documentURI: The URI that relative references are computed against; the URI of the
    ///     resource if `nil`.
    /// - Returns: The XMI document text.
    /// - Throws: ``XMIError`` if the resource has no root object, a root object is not a
    ///   ``DynamicEObject``, or a reference cannot be resolved.
    func serializeEMFStyle(_ resource: Resource, documentURI: String? = nil) async throws -> String {
        var writer = EMFDocumentWriter(resource: resource, options: options, documentURI: documentURI)
        await writer.prepare()
        return try await writer.document()
    }
}

/// Writes the EMF-style XMI document of one resource.
///
/// The writer renders the objects of the resource while it records which namespaces
/// the document needs, then assembles the namespace declarations of the root element in
/// a fixed order: `xmi`, `xsi` (only if a type is written), `ecore`, the prefix of the
/// root object's package, then any other prefixes alphabetically.
struct EMFDocumentWriter {
    /// A namespace prefix and URI.
    struct PackageInfo: Equatable {
        /// The namespace prefix.
        var prefix: String
        /// The namespace URI.
        var nsURI: String
    }

    /// A reference ready to be written.
    struct ResolvedReference {
        /// The `uri#fragment` text (with the URI part omitted for the same document).
        var href: String
        /// The referenced object, if it could be found.
        var target: (any EObject)?
    }

    /// The marker in the root start tag where the namespace declarations are inserted.
    private static let namespacePlaceholder = "\u{0}namespaces\u{0}"

    private let resource: Resource
    private let options: XMISerializationOptions
    private let documentURI: String
    private var resourceSet: ResourceSet?
    private var packagesByClassId: [EUUID: PackageInfo] = [:]
    private var packagesByClassName: [String: PackageInfo] = [:]
    private var packagesByPrefix: [String: PackageInfo] = [:]
    private var usedPrefixes: [String: String] = [:]
    private var needsXSI = false
    private var rootAttributes: [String] = []

    private static let ecorePackage = PackageInfo(
        prefix: CrossReferenceSyntax.ecorePrefix, nsURI: EcoreURI.ecoreNamespace.rawValue)

    /// Creates a writer for a resource.
    ///
    /// - Parameters:
    ///   - resource: The resource to write.
    ///   - options: The serialisation options.
    ///   - documentURI: The URI that relative references are computed against; the URI of the
    ///     resource if `nil`.
    init(resource: Resource, options: XMISerializationOptions, documentURI: String? = nil) {
        self.resource = resource
        self.options = options
        self.documentURI = documentURI ?? resource.uri
    }

    /// Looks up the resource set and indexes the registered metamodels by class.
    ///
    /// Call once before ``document()`` or ``reference(to:)``.
    ///
    ///
    /// The namespaces come from the metamodels of the resource's set. If the set has been
    /// released, the metamodels that it held remain available through the resource.
    mutating func prepare() async {
        resourceSet = await resource.resourceSet
        if let resourceSet {
            for uri in await resourceSet.getMetamodelURIs().sorted() {
                if let package = await resourceSet.getMetamodel(uri: uri) {
                    index(package, inherited: nil)
                }
            }
        } else if let snapshot = await resource.metamodelSnapshot {
            for package in snapshot.all { index(package, inherited: nil) }
        } else {
            return
        }
        packagesByPrefix[Self.ecorePackage.prefix] = Self.ecorePackage
    }

    // MARK: - Document

    /// Renders the whole document.
    ///
    /// - Returns: The XMI text, ending in a newline.
    /// - Throws: ``XMIError`` if there is no root object, a root is not a dynamic object,
    ///   or a reference cannot be resolved.
    mutating func document() async throws -> String {
        let roots = await resource.getRootObjects()
        guard !roots.isEmpty else {
            throw XMIError.parseError("No root object to serialise")
        }
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        let rootPrefix: String
        if roots.count == 1 {
            let root = try dynamicObject(roots[0])
            let info = packageInfo(for: root.eClass)
            markUsed(info)
            rootPrefix = info.prefix
            let body = try await render(
                root, elementName: "\(info.prefix):\(root.eClass.name)", xsiType: nil, indent: 0,
                isRoot: true)
            let startTag = XMIAttributeLayout(lineWidth: options.lineWidth, rootLayout: options.rootLayout).rootTag(
                name: "\(info.prefix):\(root.eClass.name)",
                declarations: namespaceDeclarations(rootPrefix: rootPrefix), attributes: rootAttributes)
            xml += body.replacingOccurrences(of: Self.namespacePlaceholder, with: startTag)
        } else {
            var bodies = ""
            var firstPrefix = CrossReferenceSyntax.ecorePrefix
            for (index, rootObject) in roots.enumerated() {
                let root = try dynamicObject(rootObject)
                let info = packageInfo(for: root.eClass)
                markUsed(info)
                if index == 0 { firstPrefix = info.prefix }
                bodies += try await render(
                    root, elementName: "\(info.prefix):\(root.eClass.name)", xsiType: nil, indent: 1,
                    isRoot: false)
            }
            let wrapper = "\(CrossReferenceSyntax.xmiPrefix):\(XMIDocumentSyntax.multipleRootElement)"
            let startTag = XMIAttributeLayout(lineWidth: options.lineWidth, rootLayout: options.rootLayout).rootTag(
                name: wrapper, declarations: namespaceDeclarations(rootPrefix: firstPrefix), attributes: [])
            xml += startTag + ">\n" + bodies + "</\(wrapper)>\n"
        }
        return xml
    }

    // MARK: - References

    /// Computes the reference text that points at an object.
    ///
    /// Objects of the written resource yield a same-document fragment (`#//@entries.0`).
    /// Objects of another resource in the same resource set yield the URI of that resource
    /// (relative if the options ask for it) and a fragment within it.
    ///
    /// - Parameter id: The identifier of the referenced object.
    /// - Returns: The reference text and the referenced object.
    /// - Throws: ``XMIError/resourceSetReleased(_:)`` if the object is not in the written
    ///   resource and the resource set that might hold it has been released;
    ///   ``XMIError/invalidReference(_:)`` if no resource of the set holds the object.
    func reference(to id: EUUID) async throws -> ResolvedReference {
        if let object = await resource.resolve(id) {
            let fragment = try await fragment(for: object, in: resource)
            return ResolvedReference(href: fragment, target: object)
        }
        if let resourceSet, let found = await resourceSet.resolve(id) {
            let fragment = try await fragment(for: found.object, in: found.resource)
            let targetURI = found.resource.uri
            let uri = options.relativeURIs ? URIReference.relativise(targetURI, against: documentURI) : targetURI
            return ResolvedReference(href: uri + fragment, target: found.object)
        }
        if await resource.lostResourceSet { throw XMIError.resourceSetReleased(resource.uri) }
        throw XMIError.invalidReference("Cannot resolve object \(id)")
    }

    // MARK: - Private Helpers

    /// Escapes the characters that are special in XML text and attribute values.
    ///
    /// - Parameter string: The text to escape.
    /// - Returns: The escaped text.
    private func escapeXML(_ string: String) -> String {
        XMISerializer().escapeXML(string)
    }

    /// Converts a primitive value into its textual form.
    ///
    /// - Parameter value: The value.
    /// - Returns: The text written to the document.
    private func convertToString(_ value: any EcoreValue) -> String {
        XMISerializer().convertToString(value)
    }

    /// Registers a package's classes in the lookup tables.
    ///
    /// - Parameters:
    ///   - package: The package to index.
    ///   - inherited: The namespace of the enclosing package, used when the package has none.
    private mutating func index(_ package: EPackage, inherited: PackageInfo?) {
        var info = inherited
        if !package.nsURI.isEmpty {
            info = PackageInfo(prefix: package.nsPrefix.isEmpty ? package.name : package.nsPrefix, nsURI: package.nsURI)
        }
        if let info {
            packagesByPrefix[info.prefix] = packagesByPrefix[info.prefix] ?? info
            for classifier in package.eClassifiers {
                guard let eClass = classifier as? EClass else { continue }
                packagesByClassId[eClass.id] = info
                packagesByClassName[eClass.name] = packagesByClassName[eClass.name] ?? info
            }
        }
        for subpackage in package.eSubpackages {
            index(subpackage, inherited: info)
        }
    }

    /// Finds the namespace of a class.
    ///
    /// - Parameter eClass: The class (or Ecore metaclass).
    /// - Returns: The namespace of the registered package that holds the class.
    private func packageInfo(for eClass: any EClassifier) -> PackageInfo {
        let identifier = (eClass as? EClass)?.id
        if let identifier, let info = packagesByClassId[identifier] { return info }
        if FragmentNavigator.isEcoreMetaclass(eClass.name) { return Self.ecorePackage }
        if let info = packagesByClassName[eClass.name] { return info }
        let prefix = eClass.name.lowercased()
        return PackageInfo(prefix: prefix, nsURI: XMIDocumentSyntax.fallbackNamespaceBase + prefix)
    }

    /// Records that a namespace is used by the document.
    ///
    /// - Parameter info: The namespace to declare.
    private mutating func markUsed(_ info: PackageInfo) {
        usedPrefixes[info.prefix] = info.nsURI
    }

    /// Builds the namespace declarations of the root element.
    ///
    /// - Parameter rootPrefix: The prefix of the root object's package.
    /// - Returns: The declaration attributes (`xmlns:ecore="..."`), `xmi:version` first.
    private func namespaceDeclarations(rootPrefix: String) -> [String] {
        var result = ["\(XMIAttribute.xmiVersion.rawValue)=\"\(CrossReferenceSyntax.xmiVersion)\""]
        result.append(declaration(CrossReferenceSyntax.xmiPrefix, EcoreURI.xmiNamespace.rawValue))
        if needsXSI { result.append(declaration(CrossReferenceSyntax.xsiPrefix, EcoreURI.xsiNamespace.rawValue)) }
        var ordered: [String] = []
        for prefix in [CrossReferenceSyntax.ecorePrefix, rootPrefix] where usedPrefixes[prefix] != nil && !ordered.contains(prefix) {
            ordered.append(prefix)
        }
        ordered += usedPrefixes.keys.filter { !ordered.contains($0) }.sorted()
        for prefix in ordered {
            if let uri = usedPrefixes[prefix] { result.append(declaration(prefix, uri)) }
        }
        return result
    }

    /// Formats a namespace declaration attribute.
    ///
    /// - Parameters:
    ///   - prefix: The namespace prefix.
    ///   - uri: The namespace URI.
    /// - Returns: The attribute text.
    private func declaration(_ prefix: String, _ uri: String) -> String {
        "\(CrossReferenceSyntax.namespaceAttribute(for: prefix))=\"\(uri)\""
    }

    /// Casts a root or child object to a dynamic object.
    ///
    /// - Parameter object: The object to cast.
    /// - Returns: The dynamic object.
    /// - Throws: ``XMIError/invalidObjectType(_:)`` for any other kind of object.
    private func dynamicObject(_ object: any EObject) throws -> DynamicEObject {
        guard let dynamic = object as? DynamicEObject else {
            throw XMIError.invalidObjectType("Cannot serialise \(type(of: object)) in EMF layout")
        }
        return dynamic
    }

    /// Lists the structural features of a class in EMF order: inherited features first.
    ///
    /// - Parameter eClass: The class.
    /// - Returns: The features without duplicates.
    private func orderedFeatures(of eClass: EClass) -> [any EStructuralFeature] {
        var seen = Set<EUUID>()
        var result: [any EStructuralFeature] = []
        func collect(_ current: EClass) {
            for superType in current.eSuperTypes { collect(superType) }
            for feature in current.eStructuralFeatures where seen.insert(feature.id).inserted {
                result.append(feature)
            }
        }
        collect(eClass)
        return result
    }

    /// Computes the fragment (with leading `#`) of an object in a resource.
    ///
    /// - Parameters:
    ///   - object: The object.
    ///   - target: The resource that holds the object.
    /// - Returns: A name-based fragment for Ecore elements if the options ask for it,
    ///   otherwise a positional fragment.
    /// - Throws: ``XMIError/invalidReference(_:)`` if a positional fragment cannot be built.
    private func fragment(for object: any EObject, in target: Resource) async throws -> String {
        let navigator = FragmentNavigator(resource: target)
        if options.nameBasedFragments, await navigator.segmentName(of: object) != nil,
            let name = await navigator.fragment(for: object.id)
        {
            return String(CrossReferenceSyntax.fragmentSeparator) + name
        }
        return try await XMISerializer().generateXPath(for: object.id, in: target)
    }

    /// Renders an object and its descendants.
    ///
    /// - Parameters:
    ///   - object: The object to write.
    ///   - elementName: The qualified element name.
    ///   - xsiType: The `xsi:type` value to write, if the object's class differs from the declared one.
    ///   - indent: The indentation level.
    ///   - isRoot: Whether this is the root start tag that carries the namespace declarations.
    /// - Returns: The element text, ending in a newline.
    private mutating func render(
        _ object: DynamicEObject, elementName: String, xsiType: String?, indent: Int, isRoot: Bool
    ) async throws -> String {
        let indentation = String(repeating: XMIDocumentSyntax.indentUnit, count: indent)
        let childIndentation = indentation + XMIDocumentSyntax.indentUnit
        var attributes: [String] = []
        var children = ""
        var handled = Set<String>()

        for feature in orderedFeatures(of: object.eClass) {
            handled.insert(feature.name)
            guard let value = await resource.eGet(objectId: object.id, feature: feature.name) else { continue }
            switch feature {
            case let attribute as EAttribute where !attribute.transient:
                renderAttribute(
                    attribute, value: value, of: object, into: &attributes, children: &children,
                    indentation: childIndentation)
            case let reference as EReference where !reference.transient:
                if isContainerOpposite(reference, of: object.eClass) { continue }
                if reference.containment {
                    children += try await renderContainment(reference, value: value, indent: indent + 1)
                } else {
                    try await renderReference(reference, value: value, into: &attributes, children: &children, indentation: childIndentation)
                }
            default:
                break
            }
        }

        for name in await resource.getFeatureNames(objectId: object.id)
        where !handled.contains(name) && !name.hasPrefix("_") && name != XMIDocumentSyntax.classFeatureName {
            guard let value = await resource.eGet(objectId: object.id, feature: name),
                value is String || value is Int || value is Double || value is Bool
            else { continue }
            attributes.append("\(name)=\"\(XMISerializer.escapeAttribute(convertToString(value)))\"")
        }

        var allAttributes: [String] = []
        if let xsiType {
            needsXSI = true
            allAttributes.append("\(XMIAttribute.xsiType.rawValue)=\"\(xsiType)\"")
        }
        allAttributes += attributes
        let ending = children.isEmpty ? "/>\n" : ">\n" + children + "\(indentation)</\(elementName)>\n"
        if isRoot {
            rootAttributes = allAttributes
            return Self.namespacePlaceholder + ending
        }
        let layout = XMIAttributeLayout(lineWidth: options.lineWidth, rootLayout: options.rootLayout)
        let tag = "\(indentation)<\(elementName)"
        return tag + layout.attributes(allAttributes, afterColumn: tag.utf16.count, indentation: indentation.utf16.count)
            + ending
    }

    /// Whether a reference is the container side of a containment reference.
    ///
    /// - Parameters:
    ///   - reference: The reference to test.
    ///   - eClass: The class that owns the reference.
    /// - Returns: `true` if the opposite of the reference is a containment.
    private func isContainerOpposite(_ reference: EReference, of eClass: EClass) -> Bool {
        guard let oppositeId = reference.opposite else { return false }
        return eClass.allReferences.first(where: { $0.id == oppositeId })?.containment ?? false
    }

    /// Writes an attribute value as an XML attribute or, for many-valued attributes, child elements.
    ///
    /// With the option to omit default values, an attribute whose value equals its default is
    /// left out unless the attribute is unsettable: an unsettable attribute has a value only
    /// if it was set, so a value that is present is always written.
    ///
    /// - Parameters:
    ///   - attribute: The declared attribute.
    ///   - value: The stored value.
    ///   - object: The object that holds the value.
    ///   - attributes: The attribute text of the element being written.
    ///   - children: The child element text of the element being written.
    ///   - indentation: The indentation for child elements.
    private func renderAttribute(
        _ attribute: EAttribute, value: any EcoreValue, of object: DynamicEObject,
        into attributes: inout [String], children: inout String, indentation: String
    ) {
        let serialiser = XMISerializer()
        if let stored = arrayTexts(of: value) {
            let texts = serialiser.attributeTexts(stored, feature: attribute.name, of: object)
            guard !texts.isEmpty else { return }
            if options.manyValuedAttributesAsElements {
                for text in texts {
                    children += "\(indentation)<\(attribute.name)>\(escapeXML(text))</\(attribute.name)>\n"
                }
            } else {
                attributes.append(
                    "\(attribute.name)=\"\(XMISerializer.escapeAttribute(texts.joined(separator: String(CrossReferenceSyntax.listSeparator))))\"")
            }
            return
        }
        let text = convertToString(value)
        if options.omitDefaultValues && !attribute.unsettable && isDefault(text, of: attribute) { return }
        let written = serialiser.attributeText(value, feature: attribute.name, of: object)
        attributes.append("\(attribute.name)=\"\(XMISerializer.escapeAttribute(written))\"")
    }

    /// Converts an array value into the texts of its elements.
    ///
    /// - Parameter value: The stored value.
    /// - Returns: The texts, or `nil` if the value is not an array of primitives.
    private func arrayTexts(of value: any EcoreValue) -> [String]? {
        switch value {
        case let strings as [String]: return strings
        case let ints as [Int]: return ints.map(String.init)
        case let doubles as [Double]: return doubles.map { "\($0)" }
        case let bools as [Bool]: return bools.map { $0 ? "true" : "false" }
        default: return nil
        }
    }

    /// Whether the text equals the default value of an attribute.
    ///
    /// The default is the attribute's default value literal if it has one; otherwise the
    /// zero value of a primitive type (`false`, `0`, `0.0`) or the first literal of an enumeration.
    ///
    /// - Parameters:
    ///   - text: The textual value.
    ///   - attribute: The attribute.
    /// - Returns: `true` if the value need not be written.
    private func isDefault(_ text: String, of attribute: EAttribute) -> Bool {
        if let literal = attribute.defaultValueLiteral { return text == literal }
        if let eEnum = attribute.eType as? EEnum { return eEnum.literals.first?.name == text }
        switch EcoreDataType(rawValue: attribute.eType.name) {
        case .eBoolean: return text == "false"
        case .eInt, .eShort, .eLong, .eByte: return text == "0"
        case .eFloat, .eDouble: return text == "0.0"
        default: return false
        }
    }

    /// Renders the children of a containment reference.
    ///
    /// - Parameters:
    ///   - reference: The containment reference.
    ///   - value: The stored identifier or identifiers.
    ///   - indent: The indentation level of the children.
    /// - Returns: The text of the child elements.
    private mutating func renderContainment(_ reference: EReference, value: any EcoreValue, indent: Int) async throws -> String {
        let identifiers: [EUUID]
        if let single = value as? EUUID {
            identifiers = [single]
        } else if let many = value as? [EUUID] {
            identifiers = many
        } else {
            return ""
        }
        var text = ""
        for identifier in identifiers {
            guard let child = await resource.resolve(identifier) as? DynamicEObject else { continue }
            var xsiType: String?
            if child.eClass.name != reference.eType.name {
                let info = packageInfo(for: child.eClass)
                markUsed(info)
                xsiType = "\(info.prefix)\(CrossReferenceSyntax.qualifierSeparator)\(child.eClass.name)"
            }
            text += try await render(child, elementName: reference.name, xsiType: xsiType, indent: indent, isRoot: false)
        }
        return text
    }

    /// Writes a non-containment reference as an attribute or as `href` child elements.
    ///
    /// - Parameters:
    ///   - reference: The declared reference.
    ///   - value: The stored identifier, proxy, or list of either.
    ///   - attributes: The attribute text of the element being written.
    ///   - children: The child element text of the element being written.
    ///   - indentation: The indentation for child elements.
    private mutating func renderReference(
        _ reference: EReference, value: any EcoreValue, into attributes: inout [String],
        children: inout String, indentation: String
    ) async throws {
        var entries: [(qualifier: String?, href: String)] = []
        let identifiers: [EUUID]
        let proxies: [ResourceProxy]
        switch value {
        case let id as EUUID: (identifiers, proxies) = ([id], [])
        case let ids as [EUUID]: (identifiers, proxies) = (ids, [])
        case let proxy as ResourceProxy: (identifiers, proxies) = ([], [proxy])
        case let list as [ResourceProxy]: (identifiers, proxies) = ([], list)
        default: return
        }
        for id in identifiers {
            let resolved = try await self.reference(to: id)
            entries.append((qualifier(for: resolved.target, declared: reference.eType), resolved.href))
        }
        for proxy in proxies {
            entries.append((proxyQualifier(proxy), proxyHref(proxy)))
        }
        guard !entries.isEmpty else { return }

        if options.attributeStyleReferences {
            let texts = entries.map { entry in
                entry.qualifier.map { "\($0)\(CrossReferenceSyntax.listSeparator)\(entry.href)" } ?? entry.href
            }
            attributes.append(
                "\(reference.name)=\"\(XMISerializer.escapeAttribute(texts.joined(separator: String(CrossReferenceSyntax.listSeparator))))\"")
        } else {
            for entry in entries {
                var tag = "\(indentation)<\(reference.name)"
                if let qualifier = entry.qualifier {
                    needsXSI = true
                    tag += " \(XMIAttribute.xsiType.rawValue)=\"\(qualifier)\""
                }
                children += "\(tag) \(CrossReferenceSyntax.hrefAttribute)=\"\(XMISerializer.escapeAttribute(entry.href))\"/>\n"
            }
        }
    }

    /// Computes the type qualifier of a reference to an object.
    ///
    /// - Parameters:
    ///   - target: The referenced object.
    ///   - declared: The declared type of the reference.
    /// - Returns: `prefix:Class` if qualifiers are enabled and the class of the target differs
    ///   from the declared type, otherwise `nil`.
    private mutating func qualifier(for target: (any EObject)?, declared: any EClassifier) -> String? {
        guard options.typeQualifiers, let target else { return nil }
        let targetClass = target.eClass
        guard targetClass.name != declared.name else { return nil }
        let info = packageInfo(for: targetClass)
        markUsed(info)
        return "\(info.prefix)\(CrossReferenceSyntax.qualifierSeparator)\(targetClass.name)"
    }

    /// Returns the qualifier recorded on an unresolved proxy, declaring its namespace.
    ///
    /// - Parameter proxy: The proxy.
    /// - Returns: The qualifier if qualifiers are enabled and the proxy has one.
    private mutating func proxyQualifier(_ proxy: ResourceProxy) -> String? {
        guard options.typeQualifiers, let qualifier = proxy.qualifier else { return nil }
        if let separator = qualifier.firstIndex(of: CrossReferenceSyntax.qualifierSeparator),
            let info = packagesByPrefix[String(qualifier[..<separator])]
        {
            markUsed(info)
        }
        return qualifier
    }

    /// Computes the reference text of an unresolved proxy.
    ///
    /// - Parameter proxy: The proxy.
    /// - Returns: `uri#fragment`, with the URI relative to the document if the options ask for it,
    ///   or only `#fragment` for a reference into the written resource.
    private func proxyHref(_ proxy: ResourceProxy) -> String {
        let separator = String(CrossReferenceSyntax.fragmentSeparator)
        let fragment = proxy.fragment.hasPrefix(separator) ? proxy.fragment : separator + proxy.fragment
        if proxy.uri.isEmpty || proxy.uri == resource.uri { return fragment }
        let uri = options.relativeURIs ? URIReference.relativise(proxy.uri, against: documentURI) : proxy.uri
        return uri + fragment
    }
}
