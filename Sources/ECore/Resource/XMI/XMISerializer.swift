//
// XMISerializer.swift
// ECore
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import SwiftXML

/// Serialises EMF objects to XMI (XML Metadata Interchange) format
///
/// The XMI serialiser converts in-memory object graphs stored in Resources to XMI files.
/// It handles:
/// - Metamodel (.ecore) files with full Ecore support
/// - Model instance (.xmi) files with arbitrary attributes
/// - Containment references (nested elements)
/// - Same-resource references (href attributes with XPath, e.g., `href="#//@employees.0"`)
/// - Cross-resource references (href attributes with URI and fragment, e.g., `href="department-b.xmi#/"`)
/// - Proper XML namespace declarations
///
/// ## Cross-Resource References
///
/// When a reference points to an object in another resource (represented as a `ResourceProxy`),
/// the serializer generates an href with the target resource's URI and fragment:
/// ```xml
/// <mainDepartment href="department-b.xmi#/"/>
/// ```
///
/// ## Usage Example
///
/// ```swift
/// let serializer = XMISerializer()
/// try await serializer.serialize(resource, to: outputURL)
/// ```
public struct XMISerializer: Sendable {

    /// The options that control the layout of serialised documents.
    public let options: XMISerializationOptions

    /// Initialise a new XMI serialiser
    ///
    /// - Parameter options: The serialisation options. The default, ``XMISerializationOptions/legacy``,
    ///   keeps the original layout; use ``XMISerializationOptions/emf`` for the layout that EMF writes.
    public init(options: XMISerializationOptions = .legacy) {
        self.options = options
    }

    /// Serialise a Resource to an XMI file
    ///
    /// With the EMF-style layout, relative URIs of references are computed against the
    /// location that is written, which need not be the URI of the resource.
    ///
    /// - Parameters:
    ///   - resource: The Resource containing objects to serialise
    ///   - url: The URL where the XMI file should be written
    /// - Throws: `XMIError` if serialisation fails or I/O errors occur
    public func serialize(_ resource: Resource, to url: URL) async throws {
        try await serialize(resource, relativeTo: url).write(to: url, atomically: FileURIHandler.writesAtomically, encoding: .utf8)
    }

    /// Serialise a Resource to an XMI string for a document at a given location
    ///
    /// With the EMF-style layout, relative URIs of references are computed against the
    /// given location, which need not be the URI of the resource.
    ///
    /// - Parameters:
    ///   - resource: The Resource containing objects to serialise
    ///   - documentURL: The location that the document will have
    /// - Returns: XMI formatted string
    /// - Throws: `XMIError` if serialisation fails
    public func serialize(_ resource: Resource, relativeTo documentURL: URL) async throws -> String {
        var diagnostics = ConversionDiagnostics()
        return try await serialize(resource, relativeTo: documentURL, diagnostics: &diagnostics)
    }

    /// Serialise a Resource to an XMI string for a document at a given location, recording what cannot be kept
    ///
    /// With the EMF-style layout, relative URIs of references are computed against the
    /// given location, which need not be the URI of the resource.
    ///
    /// - Parameters:
    ///   - resource: The Resource containing objects to serialise
    ///   - documentURL: The location that the document will have
    ///   - diagnostics: Receives a ``ConversionWarning`` for every value that is written less
    ///     faithfully than it is held, or not at all
    /// - Returns: XMI formatted string
    /// - Throws: `XMIError` if serialisation fails
    public func serialize(
        _ resource: Resource, relativeTo documentURL: URL, diagnostics: inout ConversionDiagnostics
    ) async throws -> String {
        options != .legacy
            ? try await serializeEMFStyle(
                resource, documentURI: URIReference.canonicalise(documentURL.absoluteURL.absoluteString),
                diagnostics: &diagnostics)
            : try await serialize(resource, diagnostics: &diagnostics)
    }

    /// Serialise a Resource to an XMI string
    ///
    /// A resource without root objects is written as ``XMIDocumentSyntax/emptyDocument``.
    ///
    /// - Parameter resource: The Resource containing objects to serialise
    /// - Returns: XMI formatted string
    /// - Throws: `XMIError` if serialisation fails
    public func serialize(_ resource: Resource) async throws -> String {
        var diagnostics = ConversionDiagnostics()
        return try await serialize(resource, diagnostics: &diagnostics)
    }

    /// Serialise a Resource to an XMI string, recording what cannot be kept
    ///
    /// The serialiser records a ``ConversionWarning`` wherever it writes a value less faithfully
    /// than it is held: a class of no known package in a namespace derived from its name, a
    /// reference to an object without a fragment as the object's identifier, and a value that
    /// it leaves out, such as a contained object that the resource does not hold or a value
    /// of an undeclared feature that is not a primitive. A resource without root objects is
    /// written as ``XMIDocumentSyntax/emptyDocument``.
    ///
    /// - Parameters:
    ///   - resource: The Resource containing objects to serialise
    ///   - diagnostics: Receives the warnings, in the order in which they first occur
    /// - Returns: XMI formatted string
    /// - Throws: `XMIError` if serialisation fails
    public func serialize(_ resource: Resource, diagnostics: inout ConversionDiagnostics) async throws -> String {
        if options != .legacy {
            return try await serializeEMFStyle(resource, diagnostics: &diagnostics)
        }
        let roots = await resource.getRootObjects()

        guard !roots.isEmpty else { return XMIDocumentSyntax.emptyDocument }

        // The writer of references computes the fragments of each resource once
        var references = EMFDocumentWriter(resource: resource, options: options)
        await references.prepare()
        defer { diagnostics.merge(references.diagnostics) }

        // Build XML document
        var xml = XMIDocumentSyntax.xmlDeclaration + "\n"

        if roots.count == 1 {
            // Single root object - serialize directly as the root element
            let rootObject = roots[0]
            xml += try await serializeObject(rootObject, in: resource, indentLevel: 0, references: &references)
        } else {
            // Serialise each root object as a child of xmi:XMI
            var bodies = ""
            for rootObject in roots {
                bodies += try await serializeObject(rootObject, in: resource, indentLevel: 1, references: &references)
                bodies += "\n"
            }

            // Multiple root objects - wrap in xmi:XMI element like pyecore
            xml += "<\(Self.wrapperElement) \(Self.xmiDeclarations)"

            // Collect all namespaces from all root objects and the types of contained objects
            var namespaces: Set<String> = []
            for rootObject in roots {
                namespaces.formUnion(collectNamespaces(rootObject, references: &references))
            }
            for (prefix, uri) in references.usedPrefixes {
                namespaces.insert(Self.namespaceDeclaration(prefix: prefix, uri: uri))
            }

            // Add namespace declarations
            for namespace in namespaces.sorted() {
                xml += " \(namespace)"
            }
            xml += ">\n" + bodies + "</\(Self.wrapperElement)>"
        }
        xml += "\n"

        return xml
    }

    // MARK: - Private Serialization Methods

    /// Serialise an object to XML
    ///
    /// - Parameters:
    ///   - object: The object to serialise
    ///   - resource: The Resource for context and navigation
    ///   - indentLevel: Current indentation level for formatting
    ///   - references: The writer that computes the text of references
    /// - Returns: XML string representation
    /// - Throws: `XMIError` if serialisation fails
    private func serializeObject(
        _ object: any EObject, in resource: Resource, indentLevel: Int, references writer: inout EMFDocumentWriter
    ) async throws -> String {
        let indent = String(repeating: "    ", count: indentLevel)

        // Determine namespace and element name
        let namespace = namespace(of: object, references: &writer)
        let elementName = getElementName(object, namespace: namespace)

        // Start element; the namespace declarations of a root element follow once its contents are known
        let startTag = "\(indent)<\(elementName)"

        // Add attributes
        var xml = await addAttributes(object, in: resource, references: &writer)

        // Get contained children
        let children = await getContainedChildren(object, in: resource, references: &writer)

        // Get cross-references
        let references = try await getCrossReferences(object, in: resource)

        // Get the values of many-valued attributes, written as child elements
        let valueChildren = await getManyValuedAttributes(object, in: resource)

        // Check if we need to close element
        if children.isEmpty && references.isEmpty && valueChildren.isEmpty {
            xml += "/>"
        } else {
            xml += ">\n"

            xml += serializeManyValuedAttributes(valueChildren, indentLevel: indentLevel + 1)

            // Serialise contained children
            for (featureName, childObjects) in children {
                for childObject in childObjects {
                    if childObject is DynamicEObject {
                        // Contained child as nested element
                        xml += try await serializeContainedChild(
                            childObject, featureName: featureName, of: object, in: resource,
                            indentLevel: indentLevel + 1, references: &writer)
                    }
                }
            }

            // Serialise cross-references
            for (featureName, target) in references {
                xml += try await serializeCrossReference(
                    featureName: featureName, target: target, of: object, in: resource,
                    indentLevel: indentLevel + 1, references: &writer)
            }

            // Close element
            xml += "\(indent)</\(elementName)>"
        }

        return startTag + (indentLevel == 0 ? addNamespaceDeclarations(namespace, references: writer) : "") + xml
    }

    /// Serialise a contained child element
    ///
    /// A child whose class differs from the declared type of the containment reference is
    /// written with an `xsi:type` that names its class, as EMF writes it.
    ///
    /// - Parameters:
    ///   - object: The child object to serialise
    ///   - featureName: The feature name for the child
    ///   - container: The object that contains the child
    ///   - resource: The Resource for context
    ///   - indentLevel: Current indentation level
    ///   - writer: The writer that computes the text of references
    /// - Returns: XML string
    /// - Throws: `XMIError` if serialisation fails
    private func serializeContainedChild(
        _ object: any EObject, featureName: String, of container: any EObject, in resource: Resource,
        indentLevel: Int, references writer: inout EMFDocumentWriter
    ) async throws -> String {
        let indent = String(repeating: "    ", count: indentLevel)

        guard let dynamicObject = object as? DynamicEObject else {
            return "\(indent)<\(featureName)/>\n"
        }

        // Get contained children of this child
        let children = await getContainedChildren(object, in: resource, references: &writer)

        // Get cross-references
        let references = try await getCrossReferences(object, in: resource)

        // Get the values of many-valued attributes, written as child elements
        let valueChildren = await getManyValuedAttributes(object, in: resource)

        var xml = "\(indent)<\(featureName)"

        // Name the class of a child whose class differs from the declared type
        if let declared = ((container as? DynamicEObject)?.eClass.getStructuralFeature(name: featureName) as? EReference)?.eType,
            let qualifier = writer.typeQualifier(of: dynamicObject, declared: declared)
        {
            xml += " \(XMIAttribute.xsiType.rawValue)=\"\(qualifier)\""
        }

        // Add attributes in insertion order (preserving EMF semantic ordering)
        xml += await addAttributes(dynamicObject, in: resource, references: &writer)

        if children.isEmpty && references.isEmpty && valueChildren.isEmpty {
            xml += "/>\n"
        } else {
            xml += ">\n"

            xml += serializeManyValuedAttributes(valueChildren, indentLevel: indentLevel + 1)

            // Serialise nested children
            for (childFeatureName, childObjects) in children {
                for childObject in childObjects {
                    xml += try await serializeContainedChild(
                        childObject, featureName: childFeatureName, of: dynamicObject, in: resource,
                        indentLevel: indentLevel + 1, references: &writer)
                }
            }

            // Serialise cross-references
            for (refFeatureName, target) in references {
                xml += try await serializeCrossReference(
                    featureName: refFeatureName, target: target, of: object, in: resource,
                    indentLevel: indentLevel + 1, references: &writer)
            }

            xml += "\(indent)</\(featureName)>\n"
        }

        return xml
    }

    /// Serialise a cross-reference as href
    ///
    /// - Parameters:
    ///   - featureName: The feature name
    ///   - target: Target of the reference (EUUID for same-resource, ResourceProxy for cross-resource)
    ///   - owner: The object that holds the reference
    ///   - resource: The Resource for context
    ///   - indentLevel: Current indentation level
    ///   - writer: The writer that computes the text of references
    /// - Returns: XML string
    /// - Throws: `XMIError` if serialisation fails
    private func serializeCrossReference(
        featureName: String, target: any EcoreValue, of owner: any EObject, in resource: Resource, indentLevel: Int,
        references writer: inout EMFDocumentWriter
    ) async throws -> String {
        let indent = String(repeating: "    ", count: indentLevel)

        // Many-valued references are written as one element per target, in order
        if target is [EUUID] || target is [ResourceProxy] || target is EcoreValueArray {
            var xml = ""
            for single in referenceTargets(of: target) {
                xml += try await serializeCrossReference(
                    featureName: featureName, target: single, of: owner, in: resource, indentLevel: indentLevel,
                    references: &writer)
            }
            return xml
        }

        let href: String

        if let targetId = target as? EUUID {
            // Positional fragment in this resource or URI and fragment in another resource of the set
            let resolved = try await writer.reference(to: targetId)
            if !resolved.located {
                writer.diagnostics.record(.referenceWithoutFragment(feature: featureName, className: getClassName(owner)))
            }
            href = resolved.href
        } else if let proxy = target as? ResourceProxy {
            // Cross-resource reference: Use proxy's URI and fragment
            await writer.checkDangling(proxy)
            let fragment = proxy.fragment.hasPrefix("#") ? proxy.fragment : "#\(proxy.fragment)"
            href = "\(proxy.uri)\(fragment)"
        } else {
            throw XMIError.invalidReference("Unsupported reference type: \(type(of: target))")
        }

        return "\(indent)<\(featureName) href=\"\(href)\"/>\n"
    }

    /// Generate XPath reference for an object
    ///
    /// The reference is the positional fragment of the object (see ``PositionalFragments``):
    /// `#/` or `#//@members.0` in a resource with one root, `#/1` or `#/1/@members.0` in a
    /// resource with several roots.
    ///
    /// - Parameters:
    ///   - objectId: The target object ID
    ///   - resource: The Resource containing the object
    ///   - index: The positional fragments of the resource, if already computed
    /// - Returns: XPath string (e.g., "#//@members.0"), or the object ID after `#` if the
    ///   object cannot be reached through containment from a root
    /// - Throws: `XMIError` if the object cannot be resolved
    func generateXPath(for objectId: EUUID, in resource: Resource, index: [EUUID: String]? = nil) async throws -> String {
        guard await resource.resolve(objectId) != nil else {
            throw XMIError.invalidReference("Cannot resolve object \(objectId)")
        }
        let fragments: [EUUID: String]
        if let index {
            fragments = index
        } else {
            fragments = await PositionalFragments.index(of: resource)
        }
        return String(CrossReferenceSyntax.fragmentSeparator) + (fragments[objectId] ?? objectId.uuidString)
    }

    /// The qualified name of the wrapper element of a document with several roots.
    private static let wrapperElement =
        CrossReferenceSyntax.xmiPrefix + String(CrossReferenceSyntax.qualifierSeparator)
        + XMIDocumentSyntax.multipleRootElement

    /// The `xmi:version` attribute and the XMI namespace declaration of a root element.
    private static let xmiDeclarations =
        "\(XMIAttribute.xmiVersion.rawValue)=\"\(CrossReferenceSyntax.xmiVersion)\" "
        + namespaceDeclaration(prefix: CrossReferenceSyntax.xmiPrefix, uri: EcoreURI.xmiNamespace.rawValue)

    /// Formats a namespace declaration attribute.
    ///
    /// - Parameters:
    ///   - prefix: The namespace prefix.
    ///   - uri: The namespace URI.
    /// - Returns: The `xmlns:prefix="uri"` attribute text.
    private static func namespaceDeclaration(prefix: String, uri: String) -> String {
        "\(CrossReferenceSyntax.namespaceAttribute(for: prefix))=\"\(uri)\""
    }

    /// Finds the namespace in which the element of an object is written.
    ///
    /// The namespace of a dynamic object is that of the registered package holding its
    /// class (see ``EMFDocumentWriter/namespace(for:)``). Any other object takes the
    /// namespace derived from its class name.
    ///
    /// - Parameters:
    ///   - object: The object.
    ///   - writer: The writer that knows the registered packages.
    /// - Returns: The namespace prefix and URI.
    private func namespace(of object: any EObject, references writer: inout EMFDocumentWriter)
        -> EMFDocumentWriter.PackageInfo
    {
        guard let dynamicObject = object as? DynamicEObject else {
            return EMFDocumentWriter.fallbackPackageInfo(for: getClassName(object))
        }
        return writer.namespace(for: dynamicObject.eClass)
    }

    /// Add namespace declarations to root element
    ///
    /// The XMI namespace comes first, then the XML Schema instance namespace if a contained
    /// object is written with an `xsi:type`, the namespace of the root object, and the other
    /// namespaces of those types in alphabetical order.
    ///
    /// - Parameters:
    ///   - namespace: The namespace of the root object.
    ///   - writer: The writer that recorded the namespaces of the types of contained objects.
    /// - Returns: The `xmi:version` attribute and the namespace declarations, each preceded by a space.
    private func addNamespaceDeclarations(
        _ namespace: EMFDocumentWriter.PackageInfo, references writer: EMFDocumentWriter
    ) -> String {
        var declarations = " \(Self.xmiDeclarations)"
        if writer.needsXSI {
            declarations += " " + Self.namespaceDeclaration(prefix: CrossReferenceSyntax.xsiPrefix, uri: EcoreURI.xsiNamespace.rawValue)
        }
        declarations += " " + Self.namespaceDeclaration(prefix: namespace.prefix, uri: namespace.nsURI)
        for (prefix, uri) in writer.usedPrefixes.sorted(by: { $0.key < $1.key }) where prefix != namespace.prefix {
            declarations += " " + Self.namespaceDeclaration(prefix: prefix, uri: uri)
        }
        return declarations
    }

    /// Add attributes to element
    ///
    /// Single primitive values are written as attributes. References, contained objects, and
    /// many-valued attributes are written as child elements elsewhere; a reference value or an
    /// object held by an undeclared feature, or an object held by a declared non-containment
    /// reference, cannot be written and is recorded as a
    /// ``ConversionWarning/Kind/droppedFeature(name:className:)`` warning.
    ///
    /// - Parameters:
    ///   - object: The object
    ///   - resource: The Resource
    ///   - writer: The writer that records the warnings
    /// - Returns: Attributes string
    private func addAttributes(
        _ object: any EObject, in resource: Resource, references writer: inout EMFDocumentWriter
    ) async -> String {
        var attributes = ""

        guard let dynamicObject = object as? DynamicEObject else {
            return attributes
        }

        // Get feature names in insertion order (preserving EMF semantic ordering)
        let featureNames = await resource.getFeatureNames(objectId: dynamicObject.id)

        for featureName in featureNames {
            // Skip internal features
            if featureName.hasPrefix("_") || featureName == XMIDocumentSyntax.classFeatureName {
                continue
            }

            guard let value = await resource.eGet(objectId: dynamicObject.id, feature: featureName)
            else {
                continue
            }

            // Only serialise single primitive values as attributes
            let holdsObjects = Self.holdsObjects(value)
            if isReferenceValue(value) || holdsObjects {
                // References and contained objects are written as child elements
                let reference = dynamicObject.eClass.getStructuralFeature(name: featureName) as? EReference
                if holdsObjects && reference?.containment != true {
                    writer.diagnostics.record(.droppedFeature(name: featureName, className: dynamicObject.eClass.name))
                }
                continue
            }
            if manyValuedTexts(of: value) != nil {
                // Many-valued attributes are written as child elements
                continue
            }

            // Convert value to string and add to attributes in insertion order
            attributes += " \(featureName)=\"\(escapeXML(attributeText(value, feature: featureName, of: dynamicObject)))\""
        }

        return attributes
    }

    /// Whether a stored value holds objects themselves rather than their identifiers.
    ///
    /// - Parameter value: The stored value.
    /// - Returns: `true` for an object or a list of objects.
    private static func holdsObjects(_ value: any EcoreValue) -> Bool {
        value is any EObject || value is [any EObject]
    }

    /// Get contained children of an object
    ///
    /// Only children registered with the resource are returned. A child that cannot be found,
    /// or that is held inline rather than by its identifier, is recorded as a
    /// ``ConversionWarning/Kind/unregisteredContainedObject(className:)`` warning.
    ///
    /// - Parameters:
    ///   - object: The parent object
    ///   - resource: The Resource
    ///   - writer: The writer that records the warnings
    /// - Returns: The feature names with their child objects, in the order the features were set
    private func getContainedChildren(
        _ object: any EObject, in resource: Resource, references writer: inout EMFDocumentWriter
    ) async -> [(String, [any EObject])] {
        var children: [(String, [any EObject])] = []

        guard let dynamicObject = object as? DynamicEObject else {
            return children
        }

        let featureNames = await resource.getFeatureNames(objectId: dynamicObject.id)

        for featureName in featureNames {
            // Use metamodel to determine if this is a containment feature
            if let feature = dynamicObject.eClass.getStructuralFeature(name: featureName),
                let reference = feature as? EReference
            {
                // Only include containment references, never the container side of one
                guard reference.containment, !reference.isContainerSide else { continue }
            } else if let feature = dynamicObject.eClass.getStructuralFeature(name: featureName),
                feature is EAttribute
            {
                // Skip attributes - they're not containment
                continue
            } else {
                // Dynamic features without metamodel - assume non-containment
                continue
            }

            guard let value = await resource.eGet(objectId: dynamicObject.id, feature: featureName)
            else {
                continue
            }
            let declaredType = (dynamicObject.eClass.getStructuralFeature(name: featureName) as? EReference)?.eType.name ?? featureName

            if let childId = value as? EUUID {
                if let childObject = await resource.resolve(childId), childObject is DynamicEObject
                {
                    // This is containment - serialize as child elements
                    children.append((featureName, [childObject]))
                } else {
                    writer.diagnostics.record(.unregisteredContainedObject(className: declaredType))
                }
            } else if let childIds = value as? [EUUID] {
                var childObjects: [any EObject] = []
                for childId in childIds {
                    if let childObject = await resource.resolve(childId),
                        childObject is DynamicEObject
                    {
                        childObjects.append(childObject)
                    } else {
                        writer.diagnostics.record(.unregisteredContainedObject(className: declaredType))
                    }
                }
                if !childObjects.isEmpty {
                    children.append((featureName, childObjects))
                }
            } else if let inline = (value as? [any EObject]) ?? (value as? any EObject).map({ [$0] }) {
                for child in inline {
                    writer.diagnostics.record(.unregisteredContainedObject(className: getClassName(child)))
                }
            }
        }

        return children
    }

    /// Get cross-references (non-containment references)
    ///
    /// Returns both same-resource references (EUUID) and cross-resource references (ResourceProxy).
    ///
    /// - Parameters:
    ///   - object: The object
    ///   - resource: The Resource
    /// - Returns: The feature names with their targets (EUUID, ResourceProxy, or lists of them),
    ///   in the order the features were set
    private func getCrossReferences(_ object: any EObject, in resource: Resource) async throws
        -> [(String, any EcoreValue)]
    {
        var references: [(String, any EcoreValue)] = []

        guard let dynamicObject = object as? DynamicEObject else {
            return references
        }

        let featureNames = await resource.getFeatureNames(objectId: dynamicObject.id)

        for featureName in featureNames {
            // Use metamodel to determine if this is a cross-reference (non-containment reference)
            if let feature = dynamicObject.eClass.getStructuralFeature(name: featureName),
                let reference = feature as? EReference
            {
                // Only include non-containment references, never the container side of a containment
                guard !reference.containment, !reference.isContainerSide else { continue }

                if let value = await resource.eGet(objectId: dynamicObject.id, feature: featureName)
                {
                    // Can be EUUID (same-resource) or ResourceProxy (cross-resource),
                    // or a list of them for a many-valued reference
                    if !referenceTargets(of: value).isEmpty {
                        references.append((featureName, value))
                    }
                }
            } else if !featureName.hasPrefix("_"), featureName != XMIDocumentSyntax.classFeatureName,
                let value = await resource.eGet(objectId: dynamicObject.id, feature: featureName),
                EMFDocumentWriter.holdsReferences(value)
            {
                // Identifiers held by an attribute or an undeclared feature, as in untyped documents
                references.append((featureName, value))
            }
        }

        return references
    }

    // MARK: - Many-Valued Values

    /// Whether a stored value refers to other objects.
    ///
    /// - Parameter value: The stored value.
    /// - Returns: `true` for identifiers, proxies, and lists of them.
    private func isReferenceValue(_ value: any EcoreValue) -> Bool {
        value is EUUID || value is [EUUID] || value is ResourceProxy || value is [ResourceProxy]
    }

    /// The individual targets of a stored reference value.
    ///
    /// - Parameter value: The stored value.
    /// - Returns: The identifiers and proxies the value holds in order; empty if the value is not
    ///   a reference value.
    private func referenceTargets(of value: any EcoreValue) -> [any EcoreValue] {
        switch value {
        case let identifier as EUUID: return [identifier]
        case let proxy as ResourceProxy: return [proxy]
        case let identifiers as [EUUID]: return identifiers
        case let proxies as [ResourceProxy]: return proxies
        case let array as EcoreValueArray:
            let targets = array.values.filter { $0 is EUUID || $0 is ResourceProxy }
            return targets.count == array.values.count ? targets : []
        default: return []
        }
    }

    /// The texts of a many-valued attribute value.
    ///
    /// - Parameter value: The stored value.
    /// - Returns: The text of each element, or `nil` if the value is not a list of primitives.
    private func manyValuedTexts(of value: any EcoreValue) -> [String]? {
        switch value {
        case let strings as [String]: return strings
        case let ints as [Int]: return ints.map(String.init)
        case let doubles as [Double]: return doubles.map { convertToString($0) }
        case let bools as [Bool]: return bools.map { convertToString($0) }
        case let array as EcoreValueArray:
            let texts = array.values.map { element -> String? in
                switch element {
                case is EUUID, is ResourceProxy, is any EObject: return nil
                default: return convertToString(element)
                }
            }
            return texts.contains(where: { $0 == nil }) ? nil : texts.compactMap { $0 }
        default: return nil
        }
    }

    /// Gets the many-valued attributes of an object.
    ///
    /// - Parameters:
    ///   - object: The object.
    ///   - resource: The Resource.
    /// - Returns: The attribute names with the text of each element, in the order the
    ///   features were set.
    private func getManyValuedAttributes(_ object: any EObject, in resource: Resource) async
        -> [(String, [String])]
    {
        guard let dynamicObject = object as? DynamicEObject else { return [] }
        var result: [(String, [String])] = []
        for featureName in await resource.getFeatureNames(objectId: dynamicObject.id) {
            if featureName.hasPrefix("_") || featureName == XMIDocumentSyntax.classFeatureName { continue }
            guard let value = await resource.eGet(objectId: dynamicObject.id, feature: featureName),
                let texts = manyValuedTexts(of: value), !texts.isEmpty
            else { continue }
            result.append((featureName, attributeTexts(texts, feature: featureName, of: dynamicObject)))
        }
        return result
    }

    /// Writes many-valued attributes as one child element per value.
    ///
    /// - Parameters:
    ///   - attributes: The attribute names with the text of each element.
    ///   - indentLevel: The indentation level of the child elements.
    /// - Returns: The XML text.
    private func serializeManyValuedAttributes(_ attributes: [(String, [String])], indentLevel: Int) -> String {
        let indent = String(repeating: "    ", count: indentLevel)
        var xml = ""
        for (name, texts) in attributes {
            for text in texts {
                xml += "\(indent)<\(name)>\(escapeXML(text))</\(name)>\n"
            }
        }
        return xml
    }

    /// Collect the namespace declarations that a root object of a document with several roots needs
    ///
    /// - Parameters:
    ///   - object: The root object.
    ///   - writer: The writer that knows the registered packages.
    /// - Returns: The declaration of the object's namespace and of the XML Schema instance namespace.
    private func collectNamespaces(_ object: any EObject, references writer: inout EMFDocumentWriter) -> Set<String> {
        let namespace = namespace(of: object, references: &writer)
        return [
            Self.namespaceDeclaration(prefix: namespace.prefix, uri: namespace.nsURI),
            Self.namespaceDeclaration(prefix: CrossReferenceSyntax.xsiPrefix, uri: EcoreURI.xsiNamespace.rawValue),
        ]
    }

    /// Get the qualified element name of an object
    ///
    /// - Parameters:
    ///   - object: The object.
    ///   - namespace: The namespace of the object's class.
    /// - Returns: The element name, `prefix:ClassName`.
    private func getElementName(_ object: any EObject, namespace: EMFDocumentWriter.PackageInfo) -> String {
        namespace.prefix + String(CrossReferenceSyntax.qualifierSeparator) + getClassName(object)
    }

    /// Get class name from object
    ///
    /// - Parameter object: The object
    /// - Returns: Class name
    func getClassName(_ object: any EObject) -> String {
        if let dynamicObject = object as? DynamicEObject {
            return dynamicObject.eClass.name
        }
        return XMIDocumentSyntax.untypedClassName
    }

    /// Convert a value to string representation
    ///
    /// Dates are written with fractional seconds in UTC (`2026-01-02T03:04:05.123000Z`).
    ///
    /// - Parameter value: The value to convert
    /// - Returns: String representation
    func convertToString(_ value: any EcoreValue) -> String {
        switch value {
        case let string as String:
            return string
        case let int as Int:
            return "\(int)"
        case let double as Double:
            return "\(double)"
        case let bool as Bool:
            return bool ? "true" : "false"
        case let date as Date:
            return EcoreDateCoding.fractionalString(from: date)
        case let uuid as EUUID:
            return uuid.uuidString
        default:
            return "\(value)"
        }
    }

    /// The enumeration that the type of an attribute of an object names, if it has one.
    ///
    /// - Parameters:
    ///   - featureName: The name of the feature.
    ///   - object: The object that has the feature.
    /// - Returns: The enumeration, or `nil` if the feature is not an enumeration-typed attribute.
    func enumeration(of featureName: String, in object: DynamicEObject) -> EEnum? {
        (object.eClass.getStructuralFeature(name: featureName) as? EAttribute)?.eType as? EEnum
    }

    /// The text that a document holds for the value of an attribute.
    ///
    /// The value of an enumeration-typed attribute is written as the text of its literal,
    /// as EMF writes it; any other value is converted to its textual form.
    ///
    /// - Parameters:
    ///   - value: The stored value.
    ///   - featureName: The name of the attribute.
    ///   - object: The object that has the attribute.
    /// - Returns: The text to write.
    func attributeText(_ value: any EcoreValue, feature featureName: String, of object: DynamicEObject) -> String {
        let text = convertToString(value)
        guard let eEnum = enumeration(of: featureName, in: object) else { return text }
        return eEnum.text(forStoredValue: text)
    }

    /// The texts that a document holds for the values of a many-valued attribute.
    ///
    /// - Parameters:
    ///   - texts: The textual forms of the stored values.
    ///   - featureName: The name of the attribute.
    ///   - object: The object that has the attribute.
    /// - Returns: The texts to write; literal texts for an enumeration-typed attribute.
    func attributeTexts(_ texts: [String], feature featureName: String, of object: DynamicEObject) -> [String] {
        guard let eEnum = enumeration(of: featureName, in: object) else { return texts }
        return texts.map { eEnum.text(forStoredValue: $0) }
    }

    /// Escapes text for use in an attribute value the way EMF does.
    ///
    /// The ampersand, the less-than sign, and the double quote become entities, and the
    /// line feed, carriage return, and tab become character references, so that a value
    /// reads back exactly as it was written. The greater-than sign and the apostrophe are
    /// written as they are.
    ///
    /// - Parameter value: The text to escape.
    /// - Returns: The escaped text.
    static func escapeAttribute(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)
        for character in value.unicodeScalars {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case "\"": result += "&quot;"
            case "\n": result += "&#xA;"
            case "\r": result += "&#xD;"
            case "\t": result += "&#x9;"
            default: result.unicodeScalars.append(character)
            }
        }
        return result
    }

    /// Escape XML special characters
    ///
    /// - Parameter string: The string to escape
    /// - Returns: Escaped string
    func escapeXML(_ string: String) -> String {
        return
            string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
