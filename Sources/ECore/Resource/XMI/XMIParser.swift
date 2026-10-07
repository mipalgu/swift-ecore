//
// XMIParser.swift
// ECore
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import OrderedCollections
import SwiftXML

/// Errors that can occur during XMI parsing
public enum XMIError: Error, Sendable {
    case invalidEncoding
    case invalidXML(String)
    case missingRequiredAttribute(String)
    case unsupportedXMIVersion(String)
    case invalidReference(String)
    case parseError(String)
    case unknownElement(String)
    case noRootObject
    case invalidObjectType(String)
    case unsupportedFeature(String)

    /// The resource set that a resource was loaded into no longer exists.
    ///
    /// A resource refers to its resource set weakly. Writing a resource needs the metamodels
    /// that the set holds, so a resource whose set has been released cannot be written
    /// faithfully. The associated value is the URI of the resource.
    case resourceSetReleased(String)
}

/// Parser for XMI (XML Metadata Interchange) files
///
/// The XMI parser converts XMI files into EMF-compatible object graphs stored in Resources.
/// It handles:
/// - Metamodel (.ecore) files with full Ecore support
/// - Model instance (.xmi) files with arbitrary user-defined attributes
/// - Dynamic attribute parsing without hardcoded attribute names
/// - Automatic type inference for Int, Double, Bool, and String values
/// - Cross-resource references via href attributes (creates `ResourceProxy` for external refs)
/// - XPath-style fragment identifiers
/// - Bidirectional reference resolution
///
/// ## Cross-Resource References
///
/// When parsing an href attribute with an external URI (e.g., `href="department-b.xmi#/"`),
/// the parser creates a `ResourceProxy` instead of resolving immediately. The proxy can be
/// resolved later using `ResourceProxy.resolve(in:)`, which will automatically load the
/// target resource if needed.
///
/// Same-resource references (e.g., `href="#//@employees.0"`) are resolved to `EUUID` values
/// during the two-pass parsing process.
///
/// ## Supported XMI Features
///
/// - **XMI Version**: 2.0 and later
/// - **Ecore Metamodel**: Full support for EPackage, EClass, EEnum, EDataType, EAttribute, EReference
/// - **Dynamic Attributes**: Arbitrary XML attributes parsed without hardcoding (EMF spec compliant)
/// - **Type Inference**: Automatic conversion of string values to Int, Double, Bool, or String
/// - **References**: Same-resource (#//ClassName) and external (ecore:Type http://...)
/// - **Multiplicity**: lowerBound and upperBound attributes
/// - **Containment**: Containment references and opposite references
/// - **Default Values**: defaultValueLiteral for attributes
///
/// ## Usage Example
///
/// ```swift
/// let parser = XMIParser()
/// let resource = try await parser.parse(ecoreURL)
/// let roots = await resource.getRootObjects()
/// ```
public actor XMIParser {
    private let resourceSet: ResourceSet?

    /// How attributes of reference features declared by registered metamodels are read.
    private let referenceParsing: XMIReferenceParsing

    /// Maps of parsed objects for reference resolution
    private var xmiIdMap: [String: EUUID] = [:]
    private var fragmentMap: [String: EUUID] = [:]
    private var referenceMap: [EUUID: OrderedDictionary<String, String>] = [:]  // object ID → (feature name → href)
    private var declaredReferenceMap: [EUUID: OrderedDictionary<String, [CrossReference]>] = [:]  // object ID → (declared reference name → references)
    private var eClassCache: [String: EClass] = [:]  // className → EClass for caching dynamically created classes
    private var builtinTypeCache: [String: DynamicEObject] = [:]  // typeName → EDataType for built-in Ecore types

    /// The lookup tables of the current reference resolution pass, if one is running.
    private var resolutionIndex: ClassIndex?

    /// The document order of the attributes of the document being parsed
    private var attributeOrder = XMIAttributeOrder()

    /// Debug mode flag for systematic tracing
    private var debug: Bool = false

    /// The policies used when parsing a native Ecore document.
    private let ecoreLoadOptions: EcoreLoadOptions

    /// Parsed object identities keyed by their source XML elements.
    private var parsedElementIDs: [ObjectIdentifier: EUUID] = [:]

    /// Diagnostics collected while retaining incomplete model elements.
    private var loadDiagnostics: [SourceDiagnostic] = []

    /// Initialises a new XMI parser.
    ///
    /// - Parameters:
    ///   - resourceSet: Optional ResourceSet for cross-resource reference resolution
    ///   - enableDebugging: Whether to enable debug output for systematic tracing
    ///   - referenceParsing: How reference attribute values are read (default ``XMIReferenceParsing/interpreted``).
    ///   - ecoreLoadOptions: The policies for incomplete Ecore elements.
    public init(
        resourceSet: ResourceSet? = nil, enableDebugging: Bool = false,
        referenceParsing: XMIReferenceParsing = .interpreted,
        ecoreLoadOptions: EcoreLoadOptions = EcoreLoadOptions()
    ) {
        self.resourceSet = resourceSet
        self.referenceParsing = referenceParsing
        self.ecoreLoadOptions = ecoreLoadOptions
        debug = enableDebugging
    }

    /// Reads a required Ecore attribute or reports its absence in tolerant mode.
    ///
    /// - Parameters:
    ///   - attribute: The attribute to read.
    ///   - element: The XML element holding the attribute.
    ///   - package: Whether the element is a package.
    ///   - uri: The document URI used by the diagnostic.
    /// - Returns: The attribute text, or an empty value in tolerant mode.
    /// - Throws: ``XMIError/missingRequiredAttribute(_:)`` in strict mode.
    private func requiredAttribute(_ attribute: EcoreFeatureName, on element: XElement,
        package: Bool = false, uri: String) throws -> String {
        if let value = element[attribute.rawValue] { return value }
        guard ecoreLoadOptions.tolerant else { throw XMIError.missingRequiredAttribute(attribute.rawValue) }
        let code: String
        switch attribute {
        case .nsURI: code = EcoreLoadDiagnostic.missingNamespaceURI
        case .nsPrefix: code = EcoreLoadDiagnostic.missingNamespacePrefix
        default: code = package ? EcoreLoadDiagnostic.missingPackageName : EcoreLoadDiagnostic.missingElementName
        }
        loadDiagnostics.append(SourceDiagnostic(severity: .error, code: code,
            message: "Missing required attribute '\(attribute.rawValue)'", document: uri))
        return ""
    }

    /// Collects comments and explicit identities from the parsed XML tree.
    ///
    /// - Parameter document: The parsed source document.
    /// - Returns: Metadata associated with the retained model elements.
    private func documentMetadata(_ document: XDocument) -> EcoreDocumentMetadata {
        var metadata = EcoreDocumentMetadata(encoding: document.encoding ?? EcoreDocumentMetadata.defaultEncoding)
        metadata.xmlIdentifiers = Dictionary(xmiIdMap.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        var encounteredRoot = false
        for content in document.content {
            if let comment = content as? XComment {
                let text = "<!--" + comment.value + "-->"
                if encounteredRoot { metadata.trailingComments.append(text) }
                else { metadata.leadingComments.append(text) }
            } else if content is XElement { encounteredRoot = true }
        }
        func visit(_ element: XElement) {
            if let identifier = parsedElementIDs[ObjectIdentifier(element)] {
                let names = attributeOrder.names(for: element)
                let referenceOrder = names.contains(EcoreFeatureName.containment.rawValue)
                    && names.contains(EcoreFeatureName.resolveProxies.rawValue)
                let dataTypeOrder = names.contains(EcoreFeatureName.instanceTypeName.rawValue)
                    && names.contains(EcoreFeatureName.serializable.rawValue)
                if referenceOrder || dataTypeOrder { metadata.attributeNames[identifier] = names }
            }
            var pending: [String] = []
            for content in element.content {
                if let comment = content as? XComment { pending.append("<!--" + comment.value + "-->") }
                else if let child = content as? XElement {
                    if let identifier = parsedElementIDs[ObjectIdentifier(child)], !pending.isEmpty {
                        metadata.commentsBefore[identifier] = pending
                    }
                    pending.removeAll()
                    visit(child)
                }
            }
            if let identifier = parsedElementIDs[ObjectIdentifier(element)], !pending.isEmpty {
                metadata.commentsAtEnd[identifier] = pending
            } else if element.name == XMIDocumentSyntax.multipleRootElement
                || element.name == CrossReferenceSyntax.xmiPrefix + ":" + XMIDocumentSyntax.multipleRootElement {
                metadata.wrapperTrailingComments = pending
            }
        }
        for element in document.children { visit(element) }
        return metadata
    }

    /// Enable or disable debug mode for systematic tracing
    ///
    /// - Parameter enabled: Whether to enable debug output
    public func enableDebugging(_ enabled: Bool = true) {
        debug = enabled
    }

    /// Get or create an EClass for the specified classifier type.
    ///
    /// This method ensures that metamodel classes (EPackage, EClass, etc.) are created
    /// consistently and cached for reuse within the same resource.
    ///
    /// - Parameters:
    ///   - classifierName: The name of the Ecore classifier (e.g., "EClass", "EPackage")
    ///   - resource: The resource to store the EClass in
    /// - Returns: An EClass instance for the specified classifier type
    private func getOrCreateEClass(_ classifierName: String, in resource: Resource) async -> EClass
    {
        // Check cache first
        if let cachedClass = eClassCache[classifierName] {
            return cachedClass
        }

        // Ecore metaclasses are described by the reflective Ecore package
        if let known = EcoreClassifier(rawValue: classifierName) {
            let descriptor = EcorePackage.metaClass(known)
            eClassCache[classifierName] = descriptor
            return descriptor
        }

        // Create new EClass for this classifier type
        let eClass = EClass(name: classifierName)

        // Cache and register the EClass
        eClassCache[classifierName] = eClass
        await resource.register(DynamicEObject(eClass: eClass))

        return eClass
    }

    /// Parse an XMI file and return a Resource containing the objects
    /// - Parameter url: The URL of the XMI file to parse
    /// - Returns: A Resource containing the parsed objects
    /// - Throws: XMIError if parsing fails
    public func parse(_ url: URL) async throws -> Resource {
        let uri = URIReference.canonicalise(url.absoluteString)
        if debug {
            print("[XMI] Starting to parse file: \(url.path)")
        }
        let data: Data
        if let resourceSet {
            data = try await resourceSet.readDocument(uri: uri)
        } else {
            data = try await FileURIHandler().read(uri)
        }
        return try await parse(data, uri: uri)
    }

    /// Parses the text of an XMI document.
    ///
    /// - Parameters:
    ///   - text: The text of the document.
    ///   - uri: The URI that the document has; relative references within the document are
    ///     resolved against it.
    /// - Returns: A resource with the URI that contains the parsed objects.
    /// - Throws: ``XMIError`` if parsing fails.
    public func parse(_ text: String, uri: String) async throws -> Resource {
        try await parse(Data(text.utf8), uri: uri)
    }

    /// Parses the bytes of an XMI document.
    ///
    /// - Parameters:
    ///   - data: The UTF-8 encoded document.
    ///   - uri: The URI that the document has; relative references within the document are
    ///     resolved against it.
    /// - Returns: A resource with the URI that contains the parsed objects.
    /// - Throws: ``XMIError/invalidEncoding`` if the data is not UTF-8, or another
    ///   ``XMIError`` if parsing fails.
    public func parse(_ data: Data, uri documentURI: String) async throws -> Resource {
        let uri = URIReference.canonicalise(documentURI)
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw XMIError.invalidEncoding
        }

        let document = try parseXML(fromText: xmlString, keepComments: true)
        attributeOrder = XMIAttributeOrder(document: document, source: xmlString)

        if debug {
            print("[XMI] Root element: '\(String(describing: document.name))'")
        }

        // Create resource via ResourceSet if available, otherwise create directly
        let resource: Resource
        if let resourceSet = resourceSet {
            resource = await resourceSet.createResource(uri: uri)
        } else {
            resource = Resource(uri: uri)
        }

        // Parse XMI content
        loadDiagnostics.removeAll()
        parsedElementIDs.removeAll()
        try await parseXMIContent(document, into: resource)
        await resource.setLoadDiagnostics(loadDiagnostics)
        await resource.setEcoreDocumentMetadata(documentMetadata(document))
        return resource
    }

    /// Parse XML document content into a Resource
    ///
    /// This method parses the root elements of an XMI document and populates the resource.
    /// It handles XMI version checking and delegates to element-specific parsers.
    ///
    /// - Parameters:
    ///   - document: The parsed XML document from SwiftXML
    ///   - resource: The Resource to populate with parsed objects
    /// - Throws: `XMIError` if the XMI version is unsupported or parsing fails
    private func parseXMIContent(_ document: XDocument, into resource: Resource) async throws {
        // Clear maps for this parse session
        xmiIdMap.removeAll()
        fragmentMap.removeAll()
        referenceMap.removeAll()
        declaredReferenceMap.removeAll()

        // Get the root element (e.g., <ecore:EPackage> or <xmi:XMI>)
        guard let rootElement = document.children.first else {
            throw XMIError.invalidXML("No root element found in document")
        }

        if debug {
            print("[XMI] parseXMIContent: root element name='\(rootElement.name)'")
            if let xmiVersion = rootElement[.xmiVersion] {
                print("[XMI]   XMI version: \(xmiVersion)")
            }
        }

        // Check XMI version if present in root element
        if let xmiVersion = rootElement[.xmiVersion] {
            // Accept XMI 2.0 and later
            if let version = Double(xmiVersion), version < 2.0 {
                throw XMIError.unsupportedXMIVersion(xmiVersion)
            }
        }

        // Check if root element is xmi:XMI wrapper (for multiple root objects)
        if rootElement.name == "xmi:XMI" || rootElement.name.hasSuffix(":XMI") {
            if debug {
                print("[XMI] Processing XMI wrapper with \(Array(rootElement.children).count) child elements")
            }
            // Multiple root objects wrapped in xmi:XMI
            var rootObjects: [any EObject] = []
            for childElement in rootElement.children {
                if let rootObject = try await parseElement(childElement, in: resource) {
                    rootObjects.append(rootObject)
                }
            }
            await resource.add(contentsOf: rootObjects)
        } else {
            if debug {
                print("[XMI] Processing single root element: '\(rootElement.name)'")
            }
            // Single root object
            if let rootObject = try await parseElement(rootElement, in: resource) {
                await resource.add(rootObject)
            }
        }

        if debug {
            let rootObjectCount = await resource.getRootObjects().count
            print("[XMI] Added \(rootObjectCount) root object(s) to resource")
        }

        // Second pass: resolve references
        try await resolveReferences(in: resource)
    }

    /// Parse an XML element into an EObject
    ///
    /// This method determines the element type and delegates to the appropriate parser.
    /// It handles both Ecore metamodel elements (EPackage, EClass, etc.) and model instances.
    ///
    /// - Parameters:
    ///   - element: The XML element to parse
    ///   - resource: The Resource for context and object storage
    /// - Returns: The parsed EObject, or `nil` if the element should be skipped
    /// - Throws: `XMIError` if parsing fails or required attributes are missing
    private func parseElement(_ element: XElement, in resource: Resource) async throws -> (
        any EObject
    )? {
        #if os(WASI)
        // Bound the cooperative executor's continuation stack while parsing siblings.
        await Task.yield()
        #endif
        let elementName = element.name

        if debug {
            print("[XMI] parseElement: element name='\(elementName)'")
            print("[XMI]   isEcoreType(.ePackage): \(element.isEcoreType(.ePackage))")
        }

        // Handle Ecore metamodel elements
        if elementName == "ecore:EPackage" || element.isEcoreType(.ePackage) {
            if debug {
                print("[XMI] Calling parseEPackage for element '\(elementName)'")
            }
            return try await parseEPackage(element, in: resource)
        } else if element.isEcoreType(.eClass) {
            if debug {
                print("[XMI] Calling parseEClass for element '\(elementName)'")
            }
            return try await parseEClass(element, in: resource)
        } else if element.isEcoreType(.eEnum) {
            return try await parseEEnum(element, in: resource)
        } else if element.isEcoreType(.eDataType) {
            return try await parseEDataType(element, in: resource)
        } else if element.isEcoreType(.eAttribute) {
            return try await parseEAttribute(element, in: resource)
        } else if element.isEcoreType(.eReference) {
            return try await parseEReference(element, in: resource)
        }

        if debug {
            print("[XMI] Calling parseInstanceElement for element '\(elementName)'")
        }
        // Handle model instance elements (non-Ecore elements)
        return try await parseInstanceElement(element, in: resource)
    }

    // MARK: - Type Inference

    /// Infer the ECore type from a string value
    ///
    /// This method attempts to parse the string as various primitive types in order:
    /// 1. Integer (`Int`)
    /// 2. Floating point (`Double`)
    /// 3. Boolean (`Bool`)
    /// 4. String (fallback)
    ///
    /// ## Type Inference Order
    ///
    /// The order is important to avoid false positives:
    /// - "42" → `Int` (not `Double`)
    /// - "3.14" → `Double`
    /// - "true"/"false" → `Bool` (case-insensitive)
    /// - "hello" → `String`
    ///
    /// ## Limitations
    ///
    /// - Enum literals are stored as strings until metamodel-guided conversion is available
    /// - Large integers beyond `Int.max` will be stored as strings
    /// - Date/time strings are stored as strings (no format detection yet)
    ///
    /// - Parameter string: The string value to convert
    /// - Returns: The inferred value as an `EcoreValue`
    private func inferType(from string: String) -> any EcoreValue {
        // Try Int first (before Double to avoid false positives)
        if let intValue = Int(string) {
            return intValue
        }

        // Try Double
        if let doubleValue = Double(string) {
            return doubleValue
        }

        // Try Bool (case-insensitive)
        let lowercased = string.lowercased()
        if lowercased == "true" {
            return true
        }
        if lowercased == "false" {
            return false
        }

        // Default to String
        return string
    }

    // MARK: - Model Instance Parsing

    /// Parse a model instance element
    ///
    /// This method handles elements that are instances of user-defined metamodels,
    /// as opposed to Ecore metamodel elements. It extracts the element type from
    /// the namespace prefix and local name, creates a DynamicEObject, and parses
    /// attributes and nested elements.
    ///
    /// ## Dynamic Attribute Parsing
    ///
    /// All XML attributes are parsed dynamically using SwiftXML's `attributeNames` property.
    /// This ensures arbitrary user-defined metamodels can be loaded without hardcoding
    /// attribute names, maintaining full EMF specification compliance for reflective access.
    ///
    /// XML namespace and XMI control attributes (xmlns:, xmi:, xsi:) are automatically
    /// filtered out and not stored as model features.
    ///
    /// ## Type Inference
    ///
    /// Attribute values (strings in XML) are converted to appropriate Swift types using
    /// heuristic type inference:
    /// - Integers: "42" → Int(42)
    /// - Floating-point: "3.14" → Double(3.14)
    /// - Booleans: "true"/"false" → Bool(true/false) (case-insensitive)
    /// - Strings: All other values remain as String
    ///
    /// **Note**: Enum literals are stored as strings until metamodel-guided type conversion
    /// is implemented in a future phase.
    ///
    /// - Parameters:
    ///   - element: The XML element representing the instance
    ///   - resource: The Resource for context and object storage
    /// - Returns: The parsed instance as a DynamicEObject
    /// - Throws: `XMIError` if parsing fails
    private func parseInstanceElement(
        _ element: XElement,
        in resource: Resource,
        parentEClass: EClass? = nil,
        referenceName: String? = nil
    ) async throws -> DynamicEObject {
        #if os(WASI)
        // Containment parsing calls this method directly, bypassing parseElement.
        await Task.yield()
        #endif
        // First pass: collect all structural information for this class
        let structureInfo = collectStructuralInfo(from: element)
        let className = structureInfo.className

        // Try to find EClass from registered metamodel, fall back to dynamic creation
        let eClass = await lookupEClass(
            className: className,
            element: element,
            resource: resource,
            parentEClass: parentEClass,
            referenceName: referenceName
        )

        // Then enhance it with discovered features (only for dynamically created classes)
        recordStructureInfo(for: className, with: structureInfo)

        // Get the enhanced EClass from cache (may have been enhanced)
        let enhancedEClass = eClassCache[className] ?? eClass
        var instance = DynamicEObject(eClass: enhancedEClass)

        // Register with xmi:id if present
        parsedElementIDs[ObjectIdentifier(element)] = instance.id
        if let xmiId = element[.xmiId] { xmiIdMap[xmiId] = instance.id }

        // Parse all attributes dynamically in document order
        let attributeNames = getAttributeNamesInDocumentOrder(for: element)

        for attributeName in attributeNames {
            // Skip XML namespace and XMI control attributes
            if attributeName.hasPrefix("xmlns:") || attributeName.hasPrefix("xmi:")
                || attributeName.hasPrefix("xsi:")
            {
                continue
            }

            guard let attributeValue = element[attributeName] else { continue }

            // References declared by the metamodel hold one or more (possibly cross-document) references
            if referenceParsing == .interpreted,
                let reference = enhancedEClass.getStructuralFeature(name: attributeName) as? EReference,
                !reference.containment
            {
                declaredReferenceMap[instance.id, default: [:]][attributeName, default: []]
                    .append(contentsOf: CrossReference.parseList(attributeValue))
                continue
            }

            // Check for XPath-style reference values (e.g., "//@stateMachine.0/@initialState")
            // These need to be resolved in the second pass rather than stored as strings
            if attributeValue.contains("//@") || (attributeValue.hasPrefix("#") && attributeValue.contains("//")) {
                let href = attributeValue.hasPrefix("#") ? attributeValue : "#\(attributeValue)"
                referenceMap[instance.id, default: [:]][attributeName] = href
                if debug {
                    print("[XMI]   Stored XPath reference attribute '\(attributeName)' = '\(href)' for second-pass resolution")
                }
                continue
            }

            // Strings declared by the metamodel stay strings; everything else is inferred
            if let attribute = enhancedEClass.getStructuralFeature(name: attributeName) as? EAttribute,
                !attribute.isMany, Self.isStringType(attribute.eType)
            {
                instance.eSet(attributeName, value: attributeValue)
                continue
            }

            // Enumerations are written by literal text and held by literal name
            if let attribute = enhancedEClass.getStructuralFeature(name: attributeName) as? EAttribute,
                let eEnum = attribute.eType as? EEnum
            {
                let texts = attribute.isMany
                    ? attributeValue.split(whereSeparator: \.isWhitespace).map(String.init) : [attributeValue]
                let names = texts.map { eEnum.storedValue(forText: $0) }
                instance.eSet(attributeName, value: attribute.isMany ? names : names[0])
                continue
            }

            // Use type inference to convert string to appropriate type
            let value = inferType(from: attributeValue)
            instance.eSet(attributeName, value: value)
        }

        // Parse child elements (may be attributes or references)
        var childReferences: OrderedDictionary<String, [EUUID]> = [:]
        var childAttributeValues: OrderedDictionary<String, [String]> = [:]

        for child in element.children {
            let childName = child.name
            let declaredFeature = enhancedEClass.getStructuralFeature(name: childName)

            // Check if it's a reference or a contained object
            if let href = child[CrossReferenceSyntax.hrefAttribute] {
                if referenceParsing == .interpreted, let reference = declaredFeature as? EReference,
                    !reference.containment
                {
                    // Declared reference in child-element style: keep every occurrence
                    declaredReferenceMap[instance.id, default: [:]][childName, default: []]
                        .append(contentsOf: CrossReference.parseList(href))
                } else {
                    // It's a reference - store for second pass resolution
                    referenceMap[instance.id, default: [:]][childName] = href
                }
            } else if declaredFeature is EAttribute {
                // Attribute values written as child elements (many-valued attributes)
                childAttributeValues[childName, default: []].append(child.immediateTextsCombined)
            } else {
                // It's a contained child object
                let childObject = try await parseInstanceElement(
                    child,
                    in: resource,
                    parentEClass: eClass,
                    referenceName: childName
                )
                await resource.register(childObject)

                // Add to containment reference array
                if childReferences[childName] == nil {
                    childReferences[childName] = []
                }
                childReferences[childName]?.append(childObject.id)
            }
        }

        for (attributeName, texts) in childAttributeValues {
            guard let attribute = enhancedEClass.getStructuralFeature(name: attributeName) as? EAttribute else {
                continue
            }
            instance.eSet(attributeName, value: attributeValue(from: texts, for: attribute))
        }

        // Set containment references and their opposites
        for (refName, ids) in childReferences {
            if ids.count == 1 {
                instance.eSet(refName, value: ids[0])
            } else {
                instance.eSet(refName, value: ids)
            }

            // Set opposite reference on contained elements
            if let eReference = eClass.getStructuralFeature(name: refName) as? EReference,
               let oppositeRef = await resource.resolveOpposite(eReference) {
                for childId in ids {
                    await resource.eSet(objectId: childId, feature: oppositeRef.name, value: instance.id)
                }
            }
        }

        // Register the instance
        await resource.register(instance)

        return instance
    }

    /// Whether a data type holds strings.
    ///
    /// - Parameter type: The attribute's type.
    /// - Returns: `true` for `EString` and its object wrapper.
    private static func isStringType(_ type: any EClassifier) -> Bool {
        type.name == EcoreDataType.eString.rawValue || type.name == EcoreDataType.eStringObject.rawValue
    }

    /// Converts the texts of an attribute written as child elements into a feature value.
    ///
    /// A single-valued attribute takes its only text; a many-valued attribute becomes an
    /// array whose element type follows the declared type (strings) or the inferred
    /// type of the values (integers, doubles, booleans, or strings). The values of an
    /// enumeration-typed attribute are the names of the literals that the texts denote.
    ///
    /// - Parameters:
    ///   - texts: The text contents of the child elements, in document order.
    ///   - attribute: The declared attribute.
    /// - Returns: The value to store.
    private func attributeValue(from texts: [String], for attribute: EAttribute) -> any EcoreValue {
        if let eEnum = attribute.eType as? EEnum {
            let names = texts.map { eEnum.storedValue(forText: $0) }
            return attribute.isMany ? names : (names.first ?? "")
        }
        if Self.isStringType(attribute.eType) {
            return attribute.isMany ? texts : (texts.first ?? "")
        }
        let inferred = texts.map { inferType(from: $0) }
        if !attribute.isMany, let first = inferred.first { return first }
        if let ints = inferred as? [Int] { return ints }
        if let doubles = inferred as? [Double] { return doubles }
        if let bools = inferred as? [Bool] { return bools }
        return texts
    }

    // MARK: - Ecore Metamodel Parsing

    // MARK: Annotations

    /// Parses the annotations of a model element.
    ///
    /// Every `eAnnotations` child becomes an `EAnnotation` object with its `source`, its
    /// `details` entries in document order, its nested annotations, and its `contents`. The
    /// `references` attribute is resolved with the other references of the document.
    ///
    /// - Parameters:
    ///   - element: The element whose `eAnnotations` children are parsed.
    ///   - resource: The Resource for object storage.
    /// - Returns: The identifiers of the registered annotation objects, in document order.
    /// - Throws: ``XMIError`` if the content of an annotation cannot be parsed.
    private func parseAnnotations(of element: XElement, in resource: Resource) async throws -> [EUUID] {
        var identifiers: [EUUID] = []
        for child in element.children(.eAnnotations) {
            identifiers.append(try await parseAnnotation(child, in: resource).id)
        }
        return identifiers
    }

    /// Parses one annotation element and registers it with its entries and contents.
    ///
    /// - Parameters:
    ///   - element: The `eAnnotations` element.
    ///   - resource: The Resource for object storage.
    /// - Returns: The registered annotation object.
    /// - Throws: ``XMIError`` if the content of the annotation cannot be parsed.
    private func parseAnnotation(_ element: XElement, in resource: Resource) async throws -> DynamicEObject {
        let metaclass = await getOrCreateEClass(EcoreClassifier.eAnnotation.rawValue, in: resource)
        var annotation = DynamicEObject(eClass: metaclass)
        parsedElementIDs[ObjectIdentifier(element)] = annotation.id
        if let xmiId = element[.xmiId] { xmiIdMap[xmiId] = annotation.id }
        if let source = element[EcoreFeatureName.source.rawValue] {
            annotation.eSet(EcoreFeatureName.source.rawValue, value: source)
        }

        let entryClass = await getOrCreateEClass(EcoreClassifier.eStringToStringMapEntry.rawValue, in: resource)
        var entryIdentifiers: [EUUID] = []
        for entryElement in element.children(EcoreFeatureName.details.rawValue) {
            let key = entryElement[EcoreFeatureName.key.rawValue] ?? ""
            var entry = DynamicEObject(id: ReflectiveValues.derivedID(from: annotation.id, key: key), eClass: entryClass)
            parsedElementIDs[ObjectIdentifier(entryElement)] = entry.id
            if let xmiId = entryElement[.xmiId] { xmiIdMap[xmiId] = entry.id }
            entry.eSet(EcoreFeatureName.key.rawValue, value: key)
            entry.eSet(EcoreFeatureName.value.rawValue, value: entryElement[EcoreFeatureName.value.rawValue] ?? "")
            await resource.register(entry)
            entryIdentifiers.append(entry.id)
        }
        if !entryIdentifiers.isEmpty {
            annotation.eSet(EcoreFeatureName.details.rawValue, value: entryIdentifiers)
        }

        let nested = try await parseAnnotations(of: element, in: resource)
        if !nested.isEmpty { annotation.eSet(XMIElement.eAnnotations, nested) }

        var contentIdentifiers: [EUUID] = []
        for contentElement in element.children(EcoreFeatureName.contents.rawValue) {
            if let content = try await parseElement(contentElement, in: resource) {
                contentIdentifiers.append(content.id)
            }
        }
        if !contentIdentifiers.isEmpty {
            annotation.eSet(EcoreFeatureName.contents.rawValue, value: contentIdentifiers)
        }

        if let references = element[EcoreFeatureName.references.rawValue], !references.isEmpty {
            annotation.eSet(EcoreClassifier.XMIParsingConstants.tempReferencesRef, value: references)
        }
        await resource.register(annotation)
        return annotation
    }

    /// Records the annotations of a model element on its parsed object.
    ///
    /// - Parameters:
    ///   - object: The object being built; its `eAnnotations` feature is set if there are any.
    ///   - element: The element whose annotations are parsed.
    ///   - resource: The Resource for object storage.
    /// - Throws: ``XMIError`` if the content of an annotation cannot be parsed.
    private func attachAnnotations(
        to object: inout DynamicEObject, from element: XElement, in resource: Resource
    ) async throws {
        let identifiers = try await parseAnnotations(of: element, in: resource)
        if !identifiers.isEmpty { object.eSet(XMIElement.eAnnotations, identifiers) }
    }

    /// Parse an EPackage element
    ///
    /// Parses an Ecore package with its classifiers and nested packages.
    ///
    /// - Parameters:
    ///   - element: The ecore:EPackage XML element
    ///   - resource: The Resource for object storage
    ///   - isSubpackage: Whether the element is a nested package, which need not declare `nsURI` and `nsPrefix`
    /// - Returns: A DynamicEObject representing the EPackage
    /// - Throws: `XMIError.missingRequiredAttribute` if name, nsURI, or nsPrefix is missing
    private func parseEPackage(_ element: XElement, in resource: Resource, isSubpackage: Bool = false)
        async throws -> DynamicEObject
    {
        let name = try requiredAttribute(.name, on: element, package: true, uri: resource.uri)
        let nsURI = isSubpackage ? element[EcoreFeatureName.nsURI.rawValue] ?? ""
            : try requiredAttribute(.nsURI, on: element, package: true, uri: resource.uri)
        let nsPrefix = isSubpackage ? element[EcoreFeatureName.nsPrefix.rawValue] ?? ""
            : try requiredAttribute(.nsPrefix, on: element, package: true, uri: resource.uri)

        // Create EPackage class if not already in resource
        let ePackageClass = await getOrCreateEClass(EcoreClassifier.ePackage.rawValue, in: resource)
        var pkg = DynamicEObject(eClass: ePackageClass)

        // Register with xmi:id if present
        parsedElementIDs[ObjectIdentifier(element)] = pkg.id
        if let xmiId = element[.xmiId] { xmiIdMap[xmiId] = pkg.id }

        // Set basic attributes BEFORE registering
        pkg.eSet(.name, name)
        pkg.eSet("nsURI", value: nsURI)
        pkg.eSet("nsPrefix", value: nsPrefix)

        if debug {
            print("[XMI] Parsed EPackage '\(name)' with nsURI='\(nsURI)', nsPrefix='\(nsPrefix)'")
            // Verify the values were stored correctly
            let retrievedNSURI = pkg.eGet("nsURI") as? String
            let retrievedNSPrefix = pkg.eGet("nsPrefix") as? String
            print("[XMI] Verification: retrieved nsURI='\(retrievedNSURI ?? "nil")', nsPrefix='\(retrievedNSPrefix ?? "nil")'")
        }

        try await attachAnnotations(to: &pkg, from: element, in: resource)

        // Parse classifiers (eClassifiers)
        var classifierIds: [EUUID] = []
        for child in element.children(.eClassifiers) {
            if let classifier = try await parseElement(child, in: resource) {
                // Note: Child parser already registered this object
                classifierIds.append(classifier.id)
                // Register fragment for cross-reference resolution
                if let classifierName = await resource.eGet(
                    objectId: classifier.id, feature: "name") as? String
                {
                    fragmentMap["//\(classifierName)"] = classifier.id
                }
            }
        }

        if !classifierIds.isEmpty {
            pkg.eSet(.eClassifiers, classifierIds)
        }

        // Parse nested packages
        var subpackageIds: [EUUID] = []
        for child in element.children(.eSubpackages) {
            let subpackage = try await parseEPackage(child, in: resource, isSubpackage: true)
            subpackageIds.append(subpackage.id)
        }
        if !subpackageIds.isEmpty {
            pkg.eSet(.eSubpackages, subpackageIds)
        }

        // Register the package object after all features are set (but not as a root - caller decides that)
        await resource.register(pkg)

        return pkg
    }

    /// Parse an EClass element
    ///
    /// Parses an Ecore class with its structural features and operations.
    ///
    /// - Parameters:
    ///   - element: The ecore:EClass XML element
    ///   - resource: The Resource for object storage
    /// - Returns: A DynamicEObject representing the EClass
    /// - Throws: `XMIError.missingRequiredAttribute` if name is missing
    private func parseEClass(_ element: XElement, in resource: Resource) async throws
        -> DynamicEObject
    {
        let name = try requiredAttribute(.name, on: element, uri: resource.uri)

        let eClassClass = await getOrCreateEClass(EcoreClassifier.eClass.rawValue, in: resource)
        var eClass = DynamicEObject(eClass: eClassClass)

        parsedElementIDs[ObjectIdentifier(element)] = eClass.id

        if let xmiId = element[.xmiId] { xmiIdMap[xmiId] = eClass.id }

        // Set basic attributes BEFORE registering
        eClass.eSet(.name, name)

        // Parse abstract attribute
        if let isAbstract = element.getBool(.abstract) {
            eClass.eSet(.abstract, isAbstract)
        }

        // Parse interface attribute
        if let isInterface = element.getBool(.interface) {
            eClass.eSet(.interface, isInterface)
        }

        if let instanceClassName = element[.instanceClassName] {
            eClass.eSet(.instanceClassName, instanceClassName)
        }
        if let instanceTypeName = element[EcoreFeatureName.instanceTypeName.rawValue] {
            eClass.eSet(EcoreFeatureName.instanceTypeName.rawValue, value: instanceTypeName)
        }

        // Parse eSuperTypes - will be resolved in second pass
        let genericSuperTypes = element.children(EcoreFeatureName.eGenericSuperTypes.rawValue)
            .compactMap { $0[EcoreFeatureName.eClassifier.rawValue] }
        let superTypeReferences = ([element[.eSuperTypes]].compactMap { $0 } + genericSuperTypes)
            .joined(separator: " ")
        if !superTypeReferences.isEmpty {
            eClass.eSet(EcoreClassifier.XMIParsingConstants.tempESuperTypesRef, value: superTypeReferences)
            if debug {
                print("[XMI DEBUG] parseEClass: Found eSuperTypes='\(superTypeReferences)' for class '\(name)'")
            }
        }

        try await attachAnnotations(to: &eClass, from: element, in: resource)
        try await attachTypeParameters(to: &eClass, from: element, in: resource)
        await attachGenericTypes(.eGenericSuperTypes, to: &eClass, from: element, in: resource)

        // Parse structural features
        var featureIds: [EUUID] = []
        for child in element.children(.eStructuralFeatures) {
            if let feature = try await parseElement(child, in: resource) {
                // Note: Child parser already registered this object
                featureIds.append(feature.id)
            }
        }

        if !featureIds.isEmpty {
            eClass.eSet(.eStructuralFeatures, featureIds)
        }

        // Parse operations
        var operationIds: [EUUID] = []
        for child in element.children(.eOperations) {
            operationIds.append(try await parseOperation(child, in: resource).id)
        }
        if !operationIds.isEmpty {
            eClass.eSet(.eOperations, operationIds)
        }

        // Register the object after all features are set
        await resource.register(eClass)

        return eClass
    }

    /// Parses the `eTypeParameters` children of an element.
    ///
    /// - Parameters:
    ///   - element: The element that declares the type parameters.
    ///   - object: The object being built; its `eTypeParameters` feature is set if there are any.
    ///   - resource: The Resource for object storage.
    /// - Throws: ``XMIError`` if an annotation of a type parameter cannot be parsed.
    private func attachTypeParameters(
        to object: inout DynamicEObject, from element: XElement, in resource: Resource
    ) async throws {
        var identifiers: [EUUID] = []
        for child in element.children(EcoreFeatureName.eTypeParameters.rawValue) {
            let metaclass = await getOrCreateEClass(EcoreClassifier.eTypeParameter.rawValue, in: resource)
            var parameter = DynamicEObject(eClass: metaclass)
            parsedElementIDs[ObjectIdentifier(child)] = parameter.id
            if let xmiId = child[.xmiId] { xmiIdMap[xmiId] = parameter.id }
            parameter.eSet(.name, child[.name] ?? "")
            try await attachAnnotations(to: &parameter, from: child, in: resource)
            var bounds: [EUUID] = []
            for bound in child.children(EcoreFeatureName.eBounds.rawValue) {
                bounds.append(await parseGenericType(bound, in: resource).id)
            }
            if !bounds.isEmpty { parameter.eSet(EcoreFeatureName.eBounds.rawValue, value: bounds) }
            await resource.register(parameter)
            identifiers.append(parameter.id)
        }
        if !identifiers.isEmpty {
            object.eSet(EcoreFeatureName.eTypeParameters.rawValue, value: identifiers)
        }
    }

    /// Parses the generic types that an element holds in a containment feature.
    ///
    /// - Parameters:
    ///   - feature: The name of the containment feature, such as `eGenericType`.
    ///   - element: The element that holds the generic types.
    ///   - object: The object being built; the feature is set if there are any generic types.
    ///   - resource: The Resource for object storage.
    private func attachGenericTypes(
        _ feature: EcoreFeatureName, to object: inout DynamicEObject, from element: XElement,
        in resource: Resource
    ) async {
        var identifiers: [EUUID] = []
        for child in element.children(feature.rawValue) {
            identifiers.append(await parseGenericType(child, in: resource).id)
        }
        guard !identifiers.isEmpty else { return }
        if feature == .eGenericType || feature == .eUpperBound || feature == .eLowerBound {
            object.eSet(feature.rawValue, value: identifiers[0])
        } else {
            object.eSet(feature.rawValue, value: identifiers)
        }
    }

    /// Parses an `EGenericType` element with its type arguments and bounds.
    ///
    /// The classifier and type parameter references are resolved in the second pass.
    ///
    /// - Parameters:
    ///   - element: The generic type element.
    ///   - resource: The Resource for object storage.
    /// - Returns: The registered generic type object.
    private func parseGenericType(_ element: XElement, in resource: Resource) async -> DynamicEObject {
        let metaclass = await getOrCreateEClass(EcoreClassifier.eGenericType.rawValue, in: resource)
        var type = DynamicEObject(eClass: metaclass)
        parsedElementIDs[ObjectIdentifier(element)] = type.id
        if let xmiId = element[.xmiId] { xmiIdMap[xmiId] = type.id }
        if let classifier = element[EcoreFeatureName.eClassifier.rawValue] {
            type.eSet(EcoreClassifier.XMIParsingConstants.tempEClassifierRef, value: classifier)
        }
        if let parameter = element[EcoreFeatureName.eTypeParameter.rawValue] {
            type.eSet(EcoreClassifier.XMIParsingConstants.tempETypeParameterRef, value: parameter)
        }
        await attachGenericTypes(.eUpperBound, to: &type, from: element, in: resource)
        await attachGenericTypes(.eTypeArguments, to: &type, from: element, in: resource)
        await attachGenericTypes(.eLowerBound, to: &type, from: element, in: resource)
        await resource.register(type)
        return type
    }

    /// The type reference of a typed element.
    ///
    /// The type is the `eType` attribute. If the element has none, the classifier of its
    /// `eGenericType` child is used, which is how Ecore writes a type that has type
    /// arguments; the raw classifier is the type, and type arguments are not represented.
    ///
    /// - Parameter element: The attribute, reference, operation, or parameter element.
    /// - Returns: The reference text, or `nil` if the element has no type.
    private func typeReference(of element: XElement) -> String? {
        if let eType = element[.eType] { return eType }
        return element.children(EcoreFeatureName.eGenericType.rawValue).first?[
            EcoreFeatureName.eClassifier.rawValue]
    }

    /// Parse an EOperation element together with its parameters.
    ///
    /// - Parameters:
    ///   - element: The eOperations XML element
    ///   - resource: The Resource for object storage
    /// - Returns: A DynamicEObject representing the EOperation
    /// - Throws: `XMIError.missingRequiredAttribute` if name is missing
    private func parseOperation(_ element: XElement, in resource: Resource) async throws -> DynamicEObject {
        var operation = try await parseTypedElement(
            element, metaclass: .eOperation, in: resource)
        var parameterIds: [EUUID] = []
        for child in element.children(.eParameters) {
            let parameter = try await parseTypedElement(child, metaclass: .eParameter, in: resource)
            parameterIds.append(parameter.id)
        }
        if !parameterIds.isEmpty {
            operation.eSet(.eParameters, parameterIds)
        }
        await resource.register(operation)
        return operation
    }

    /// Parse a named, typed Ecore element such as an operation or a parameter.
    ///
    /// - Parameters:
    ///   - element: The XML element
    ///   - metaclass: The Ecore metaclass of the element
    ///   - resource: The Resource for object storage
    /// - Returns: A registered DynamicEObject with name, bounds, and a pending type reference
    /// - Throws: `XMIError.missingRequiredAttribute` if name is missing
    private func parseTypedElement(
        _ element: XElement, metaclass: EcoreClassifier, in resource: Resource
    ) async throws -> DynamicEObject {
        let name = try requiredAttribute(.name, on: element, uri: resource.uri)
        let metaclassObject = await getOrCreateEClass(metaclass.rawValue, in: resource)
        var object = DynamicEObject(eClass: metaclassObject)
        parsedElementIDs[ObjectIdentifier(element)] = object.id
        if let xmiId = element[.xmiId] { xmiIdMap[xmiId] = object.id }
        object.eSet(.name, name)
        if let eType = typeReference(of: element) {
            object.eSet(EcoreClassifier.XMIParsingConstants.tempETypeRef, value: eType)
        }
        if let lowerBound = element.getInt(.lowerBound) { object.eSet(.lowerBound, lowerBound) }
        if let upperBound = element.getInt(.upperBound) { object.eSet(.upperBound, upperBound) }
        for flag in [XMIAttribute.ordered, .unique] {
            if let value = element.getBool(flag) { object.eSet(flag.rawValue, value: value) }
        }
        let genericExceptions = element.children(EcoreFeatureName.eGenericExceptions.rawValue)
            .compactMap { $0[EcoreFeatureName.eClassifier.rawValue] }
        await attachGenericTypes(.eGenericExceptions, to: &object, from: element, in: resource)
        await attachGenericTypes(.eGenericType, to: &object, from: element, in: resource)
        try await attachTypeParameters(to: &object, from: element, in: resource)
        let exceptions = ([element[EcoreFeatureName.eExceptions.rawValue]].compactMap { $0 }
            + genericExceptions).joined(separator: " ")
        if !exceptions.isEmpty {
            object.eSet(EcoreClassifier.XMIParsingConstants.tempEExceptionsRef, value: exceptions)
        }
        try await attachAnnotations(to: &object, from: element, in: resource)
        await resource.register(object)
        return object
    }

    /// Parse an EEnum element
    ///
    /// Parses an Ecore enumeration with its literals.
    ///
    /// - Parameters:
    ///   - element: The ecore:EEnum XML element
    ///   - resource: The Resource for object storage
    /// - Returns: A DynamicEObject representing the EEnum
    /// - Throws: `XMIError.missingRequiredAttribute` if name is missing
    private func parseEEnum(_ element: XElement, in resource: Resource) async throws
        -> DynamicEObject
    {
        let name = try requiredAttribute(.name, on: element, uri: resource.uri)

        let eEnumClass = await getOrCreateEClass(EcoreClassifier.eEnum.rawValue, in: resource)
        var eEnum = DynamicEObject(eClass: eEnumClass)

        parsedElementIDs[ObjectIdentifier(element)] = eEnum.id

        if let xmiId = element[.xmiId] { xmiIdMap[xmiId] = eEnum.id }

        // Set name before registering
        eEnum.eSet(.name, name)
        if let instanceClassName = element[.instanceClassName] {
            eEnum.eSet(.instanceClassName, instanceClassName)
        }
        if let instanceTypeName = element[EcoreFeatureName.instanceTypeName.rawValue] {
            eEnum.eSet(EcoreFeatureName.instanceTypeName.rawValue, value: instanceTypeName)
        }
        if let isSerializable = element.getBool(.serializable) {
            eEnum.eSet(.serializable, isSerializable)
        }

        try await attachAnnotations(to: &eEnum, from: element, in: resource)
        try await attachTypeParameters(to: &eEnum, from: element, in: resource)

        // Parse literals
        var literalIds: [EUUID] = []
        for child in element.children(.eLiterals) {
            let literal = try await parseEEnumLiteral(child, in: resource)
            // Note: parseEEnumLiteral already registered this object
            literalIds.append(literal.id)
        }

        if !literalIds.isEmpty {
            eEnum.eSet(.eLiterals, literalIds)
        }

        // Register after all features are set
        await resource.register(eEnum)

        return eEnum
    }

    /// Parse an EEnumLiteral element
    ///
    /// Parses an enumeration literal with its value.
    ///
    /// - Parameters:
    ///   - element: The eLiterals XML element
    ///   - resource: The Resource for object storage
    /// - Returns: A DynamicEObject representing the EEnumLiteral
    /// - Throws: `XMIError.missingRequiredAttribute` if name is missing
    private func parseEEnumLiteral(_ element: XElement, in resource: Resource) async throws
        -> DynamicEObject
    {
        let name = try requiredAttribute(.name, on: element, uri: resource.uri)

        let eEnumLiteralClass = await getOrCreateEClass(
            EcoreClassifier.eEnumLiteral.rawValue, in: resource)
        var literal = DynamicEObject(eClass: eEnumLiteralClass)
        parsedElementIDs[ObjectIdentifier(element)] = literal.id
        if let xmiId = element[.xmiId] { xmiIdMap[xmiId] = literal.id }

        // Set features before registering
        literal.eSet(.name, name)

        // Value defaults to ordinal position if not specified
        if let value = element.getInt(.value) {
            literal.eSet(.value, value)
        }

        // Literal string defaults to name if not specified
        let literalStr = element[.literal] ?? name
        literal.eSet(.literal, literalStr)

        try await attachAnnotations(to: &literal, from: element, in: resource)

        // Register after all features are set
        await resource.register(literal)

        return literal
    }

    /// Parse an EDataType element
    ///
    /// Parses an Ecore data type.
    ///
    /// - Parameters:
    ///   - element: The ecore:EDataType XML element
    ///   - resource: The Resource for object storage
    /// - Returns: A DynamicEObject representing the EDataType
    /// - Throws: `XMIError.missingRequiredAttribute` if name is missing
    private func parseEDataType(_ element: XElement, in resource: Resource) async throws
        -> DynamicEObject
    {
        let name = try requiredAttribute(.name, on: element, uri: resource.uri)

        let eDataTypeClass = await getOrCreateEClass(
            EcoreClassifier.eDataType.rawValue, in: resource)
        var dataType = DynamicEObject(eClass: eDataTypeClass)

        parsedElementIDs[ObjectIdentifier(element)] = dataType.id

        if let xmiId = element[.xmiId] { xmiIdMap[xmiId] = dataType.id }

        // Set features before registering
        dataType.eSet(.name, name)

        // Parse instanceClassName attribute
        if let instanceClassName = element[.instanceClassName] {
            dataType.eSet(.instanceClassName, instanceClassName)
        }

        if let instanceTypeName = element[EcoreFeatureName.instanceTypeName.rawValue] {
            dataType.eSet(EcoreFeatureName.instanceTypeName.rawValue, value: instanceTypeName)
        }

        // Parse serializable attribute
        if let isSerializable = element.getBool(.serializable) {
            dataType.eSet(.serializable, isSerializable)
        }

        try await attachAnnotations(to: &dataType, from: element, in: resource)
        try await attachTypeParameters(to: &dataType, from: element, in: resource)

        // Register after features are set
        await resource.register(dataType)

        return dataType
    }

    /// Parse an EAttribute element
    ///
    /// Parses an Ecore attribute with its type and multiplicity.
    ///
    /// - Parameters:
    ///   - element: The ecore:EAttribute XML element
    ///   - resource: The Resource for object storage
    /// - Returns: A DynamicEObject representing the EAttribute
    /// - Throws: `XMIError.missingRequiredAttribute` if name or eType is missing
    private func parseEAttribute(_ element: XElement, in resource: Resource) async throws
        -> DynamicEObject
    {
        let name = try requiredAttribute(.name, on: element, uri: resource.uri)

        let eAttributeClass = await getOrCreateEClass(
            EcoreClassifier.eAttribute.rawValue, in: resource)
        var attribute = DynamicEObject(eClass: eAttributeClass)
        parsedElementIDs[ObjectIdentifier(element)] = attribute.id
        if let xmiId = element[.xmiId] { xmiIdMap[xmiId] = attribute.id }

        // Set features before registering
        attribute.eSet(.name, name)

        // eType will be resolved in second pass
        if let eType = typeReference(of: element) {
            // Store for later resolution
            attribute.eSet(EcoreClassifier.XMIParsingConstants.tempETypeRef, value: eType)
        }

        // Parse multiplicity
        if let lowerBound = element.getInt(.lowerBound) {
            attribute.eSet(.lowerBound, lowerBound)
        }

        if let upperBound = element.getInt(.upperBound) {
            attribute.eSet(.upperBound, upperBound)
        }

        // Parse boolean attributes
        if let isID = element.getBool(.iD) {
            attribute.eSet(.iD, isID)
        }

        if let isChangeable = element.getBool(.changeable) {
            attribute.eSet(.changeable, isChangeable)
        }

        if let isVolatile = element.getBool(.volatile) {
            attribute.eSet(.volatile, isVolatile)
        }

        if let isTransient = element.getBool(.transient) {
            attribute.eSet(.transient, isTransient)
        }

        for flag in [XMIAttribute.ordered, .unique, .unsettable, .derived] {
            if let value = element.getBool(flag) { attribute.eSet(flag.rawValue, value: value) }
        }

        try await attachAnnotations(to: &attribute, from: element, in: resource)
        await attachGenericTypes(.eGenericType, to: &attribute, from: element, in: resource)

        // Default value
        if let defaultValue = element[.defaultValueLiteral] {
            attribute.eSet(.defaultValueLiteral, defaultValue)
        }

        // Register after features are set
        await resource.register(attribute)

        return attribute
    }

    /// Parse an EReference element
    ///
    /// Parses an Ecore reference with its type, containment, and multiplicity.
    ///
    /// - Parameters:
    ///   - element: The ecore:EReference XML element
    ///   - resource: The Resource for object storage
    /// - Returns: A DynamicEObject representing the EReference
    /// - Throws: `XMIError.missingRequiredAttribute` if name or eType is missing
    private func parseEReference(_ element: XElement, in resource: Resource) async throws
        -> DynamicEObject
    {
        let name = try requiredAttribute(.name, on: element, uri: resource.uri)

        let eReferenceClass = await getOrCreateEClass(
            EcoreClassifier.eReference.rawValue, in: resource)
        var reference = DynamicEObject(eClass: eReferenceClass)
        parsedElementIDs[ObjectIdentifier(element)] = reference.id
        if let xmiId = element[.xmiId] { xmiIdMap[xmiId] = reference.id }

        // Set features before registering
        reference.eSet(.name, name)

        // eType will be resolved in second pass
        if let eType = typeReference(of: element) {
            reference.eSet(EcoreClassifier.XMIParsingConstants.tempETypeRef, value: eType)
        }

        // eOpposite will be resolved in second pass - try both eOpposite and opposite attributes
        if let eOpposite = element[.eOpposite] {
            reference.eSet(EcoreClassifier.XMIParsingConstants.tempEOppositeRef, value: eOpposite)
            reference.eSet(EcoreClassifier.XMIParsingConstants.tempOppositeType, value: XMIAttribute.eOpposite.rawValue)
            if debug {
                print("[XMI DEBUG] parseEReference: Found eOpposite='\(eOpposite)' for reference '\(name)'")
            }
        } else if let opposite = element[.opposite] {
            reference.eSet(EcoreClassifier.XMIParsingConstants.tempEOppositeRef, value: opposite)
            reference.eSet(EcoreClassifier.XMIParsingConstants.tempOppositeType, value: XMIAttribute.opposite.rawValue)
            if debug {
                print("[XMI DEBUG] parseEReference: Found opposite='\(opposite)' for reference '\(name)'")
            }
        } else if debug {
            print("[XMI DEBUG] parseEReference: No eOpposite/opposite found for reference '\(name)'")
        }

        // Containment
        let isContainment = element.getBool(.containment) ?? false
        reference.eSet(.containment, isContainment)

        // Parse multiplicity
        if let lowerBound = element.getInt(.lowerBound) {
            reference.eSet(.lowerBound, lowerBound)
        }

        if let upperBound = element.getInt(.upperBound) {
            reference.eSet(.upperBound, upperBound)
        }

        let referenceFlags: [XMIAttribute] = [
            .ordered, .unique, .unsettable, .derived, .changeable, .volatile, .transient,
            .resolveProxies,
        ]
        for flag in referenceFlags {
            if let value = element.getBool(flag) { reference.eSet(flag.rawValue, value: value) }
        }

        try await attachAnnotations(to: &reference, from: element, in: resource)
        await attachGenericTypes(.eGenericType, to: &reference, from: element, in: resource)
        if let keys = element[EcoreFeatureName.eKeys.rawValue], !keys.isEmpty {
            reference.eSet(EcoreClassifier.XMIParsingConstants.tempEKeysRef, value: keys)
        }

        // Register after features are set
        await resource.register(reference)

        return reference
    }

    // MARK: - Reference Resolution

    /// Resolve references in the second pass
    ///
    /// This method resolves all stored reference strings to actual object IDs.
    ///
    /// - Parameter resource: The Resource containing all objects
    /// - Throws: `XMIError.invalidReference` if a reference cannot be resolved
    private func resolveReferences(in resource: Resource) async throws {
        let allObjects = await resource.getAllObjects()
        resolutionIndex = nil
        defer { resolutionIndex = nil }



        // Create XPath resolver for this resource
        let xpathResolver = XPathResolver(resource: resource)

        for object in allObjects {
            #if os(WASI)
            // Actor hops on the cooperative executor can run inline. Yield between
            // objects so large documents do not accumulate continuation frames.
            await Task.yield()
            #endif
            // Resolve eType references (metamodel)
            if let eTypeRef = await resource.eGet(objectId: object.id, feature: EcoreClassifier.XMIParsingConstants.tempETypeRef)
                as? String
            {
                await resolveDeclaredReference(
                    CrossReference.parseList(eTypeRef), feature: XMIAttribute.eType.rawValue,
                    of: object, using: xpathResolver, in: resource)
                // Clear temporary reference
                await resource.eSet(objectId: object.id, feature: EcoreClassifier.XMIParsingConstants.tempETypeRef, value: nil)
            }

            // Resolve eOpposite references (metamodel)
            if let eOppositeRef = await resource.eGet(objectId: object.id, feature: EcoreClassifier.XMIParsingConstants.tempEOppositeRef)
                as? String
            {
                if debug {
                    print("[XMI DEBUG] resolveReferences: Resolving eOpposite reference '\(eOppositeRef)' for object \(object.id)")
                }

                if let resolved = await resolveReference(
                    eOppositeRef, using: xpathResolver, in: resource) {
                    // Determine which attribute type was used and store accordingly
                    let oppositeType = await resource.eGet(objectId: object.id, feature: EcoreClassifier.XMIParsingConstants.tempOppositeType) as? String
                    let targetAttribute = oppositeType == XMIAttribute.eOpposite.rawValue ? XMIAttribute.eOpposite.rawValue : XMIAttribute.opposite.rawValue
                    await resource.eSet(objectId: object.id, feature: targetAttribute, value: resolved)

                    if debug {
                        print("[XMI DEBUG] resolveReferences: Successfully resolved '\(eOppositeRef)' to \(resolved) for attribute '\(targetAttribute)'")
                    }
                } else if debug {
                    print("[XMI DEBUG] resolveReferences: Failed to resolve eOpposite reference '\(eOppositeRef)'")
                }
                // Clear temporary references
                await resource.eSet(objectId: object.id, feature: EcoreClassifier.XMIParsingConstants.tempEOppositeRef, value: nil)
                await resource.eSet(objectId: object.id, feature: EcoreClassifier.XMIParsingConstants.tempOppositeType, value: nil)
            }

            // Resolve eSuperTypes, eExceptions, and annotation references (metamodel)
            for (temporary, feature) in [
                (EcoreClassifier.XMIParsingConstants.tempESuperTypesRef, XMIAttribute.eSuperTypes.rawValue),
                (EcoreClassifier.XMIParsingConstants.tempEExceptionsRef, EcoreFeatureName.eExceptions.rawValue),
                (EcoreClassifier.XMIParsingConstants.tempReferencesRef, EcoreFeatureName.references.rawValue),
                (EcoreClassifier.XMIParsingConstants.tempEClassifierRef, EcoreFeatureName.eClassifier.rawValue),
                (EcoreClassifier.XMIParsingConstants.tempETypeParameterRef, EcoreFeatureName.eTypeParameter.rawValue),
                (EcoreClassifier.XMIParsingConstants.tempEKeysRef, EcoreFeatureName.eKeys.rawValue),
            ] {
                guard let references = await resource.eGet(objectId: object.id, feature: temporary) as? String
                else { continue }
                if debug {
                    print("[XMI DEBUG] resolveReferences: Resolving \(feature) '\(references)' for object \(object.id)")
                }
                await resolveDeclaredReference(
                    CrossReference.parseList(references), feature: feature, of: object,
                    using: xpathResolver, in: resource)
                await resource.eSet(objectId: object.id, feature: temporary, value: nil)
            }

            // Resolve references declared by the metamodel
            if let declared = declaredReferenceMap[object.id] {
                for (featureName, references) in declared {
                    await resolveDeclaredReference(
                        references, feature: featureName, of: object, using: xpathResolver, in: resource)
                }
            }

            // Resolve instance-level references from referenceMap
            if let references = referenceMap[object.id] {
                for (featureName, href) in references {
                    if debug {
                        print("[XMI DEBUG] Resolving reference: object \(object.id), feature '\(featureName)', href '\(href)'")
                    }
                    // Resolve the href using XPath or fragment lookup
                    // This may return EUUID (same-resource) or ResourceProxy (cross-resource)
                    if let resolved = await resolveReference(
                        href, using: xpathResolver, in: resource)
                    {
                        if debug {
                            print("[XMI DEBUG] Reference resolved: '\(href)' -> \(resolved)")
                        }
                        await resource.eSet(
                            objectId: object.id, feature: featureName, value: resolved)
                    } else if debug {
                        print("[XMI DEBUG] Reference resolution failed for '\(href)'")
                    }
                }
            }
        }
    }

    /// Resolve the references of a metamodel-declared reference feature and store them.
    ///
    /// Same-document references become object identifiers and references to other documents
    /// become ``ResourceProxy`` values. A single-valued feature takes one value and a
    /// many-valued feature an array. If an array mixes both kinds, the same-document
    /// references are stored as proxies to this resource so that the array has one type.
    /// References that cannot be resolved yet are kept as proxies to this resource, so that they
    /// can be resolved later and are written back unchanged.
    ///
    /// - Parameters:
    ///   - references: The parsed references in document order.
    ///   - featureName: The name of the declared reference.
    ///   - object: The object that owns the feature.
    ///   - xpathResolver: The resolver for the document being parsed.
    ///   - resource: The resource being populated.
    private func resolveDeclaredReference(
        _ references: [CrossReference], feature featureName: String, of object: any EObject,
        using xpathResolver: XPathResolver, in resource: Resource
    ) async {
        var identifiers: [EUUID] = []
        var proxies: [ResourceProxy] = []
        var kinds: [Bool] = []  // true for same-document identifiers

        for reference in references {
            let href = reference.uri.isEmpty ? "#\(reference.fragment)" : reference.href
            guard let resolved = await resolveReference(href, using: xpathResolver, in: resource) else {
                if debug { print("[XMI DEBUG] Declared reference '\(href)' could not be resolved") }
                proxies.append(ResourceProxy(uri: resource.uri, fragment: reference.fragment, qualifier: reference.qualifier))
                kinds.append(false)
                continue
            }
            if let identifier = resolved as? EUUID {
                identifiers.append(identifier)
                proxies.append(ResourceProxy(uri: resource.uri, fragment: reference.fragment, qualifier: reference.qualifier))
                kinds.append(true)
            } else if let proxy = resolved as? ResourceProxy {
                proxies.append(ResourceProxy(uri: proxy.uri, fragment: proxy.fragment, qualifier: reference.qualifier))
                kinds.append(false)
            } else if let target = resolved as? any EObject {
                identifiers.append(target.id)
                proxies.append(ResourceProxy(uri: resource.uri, fragment: reference.fragment, qualifier: reference.qualifier))
                kinds.append(true)
            }
        }
        guard !kinds.isEmpty else { return }

        let isMany = (object.eClass as? EClass)?.getEReference(name: featureName)?.isMany ?? false
        let value: any EcoreValue
        if kinds.allSatisfy({ $0 }) {
            value = (isMany || identifiers.count > 1) ? identifiers : identifiers[0]
        } else if kinds.allSatisfy({ !$0 }) {
            value = (isMany || proxies.count > 1) ? proxies : proxies[0]
        } else {
            value = proxies
        }
        await resource.eSet(objectId: object.id, feature: featureName, value: value)
    }

    /// Resolve a reference string to an object ID or ResourceProxy
    ///
    /// Handles:
    /// - XPath references: `#//@members.0` (using XPathResolver)
    /// - Fragment references: `#//ClassName`
    /// - XMI ID references: `#xmi-id`
    /// - External references: `department-b.xmi#/` (creates ResourceProxy)
    ///
    /// - Parameters:
    ///   - reference: The reference string
    ///   - xpathResolver: Optional XPathResolver for XPath-style references
    ///   - resource: The current Resource for resolving relative URIs
    /// - Returns: The resolved object ID, or ResourceProxy for external references
    private func resolveReference(
        _ reference: String, using xpathResolver: XPathResolver? = nil, in resource: Resource
    ) async -> (any EcoreValue)? {
        // Handle Ecore built-in types
        if EcoreURI.isEcoreMetamodelReference(reference) {
            return await resolveEcoreBuiltinType(reference, in: resource)
        }

        if reference.hasPrefix("#") {
            let fragment = String(reference.dropFirst())

            // First try XPath resolution (for paths like //@members.0)
            if let resolver = xpathResolver, fragment.contains("/"), fragment.contains("@") {
                if debug {
                    print("[XMI DEBUG] Attempting XPath resolution for reference: '\(reference)'")
                }
                if let id = await resolver.resolve(reference) {
                    if debug {
                        print("[XMI DEBUG] XPath resolution successful: '\(reference)' -> \(id)")
                    }
                    return id
                } else if debug {
                    print("[XMI DEBUG] XPath resolution failed for reference: '\(reference)'")
                }
            }

            // The root object of the document
            if fragment == CrossReferenceSyntax.rootFragment {
                return await resource.getRootObjects().first?.id
            }

            // Then try EMF fragment resolution (for paths like //ClassName/featureName)
            if fragment.hasPrefix("//") && !fragment.contains("@") {
                if let resolved = await resolveEMFFragmentReference(fragment, in: resource) {
                    return resolved
                }
                return await FragmentNavigator(resource: resource).resolve(fragment)?.id
            }

            if fragment.hasPrefix("/"), let resolved = await FragmentNavigator(resource: resource).resolve(fragment) {
                return resolved.id
            }
            // Fall back to fragment map or xmi:id map
            return fragmentMap[fragment] ?? xmiIdMap[fragment]
        }

        // External reference - create ResourceProxy
        // Parse reference format: "uri#fragment" or just "uri"
        if let hashIndex = reference.firstIndex(of: "#") {
            let uri = String(reference[..<hashIndex])
            let fragment = String(reference[reference.index(after: hashIndex)...])

            // Resolve relative URI
            let resolvedURI = resolveRelativeURI(uri, relativeTo: resource.uri)

            return ResourceProxy(uri: resolvedURI, fragment: fragment)
        } else {
            // No fragment - reference to entire resource
            let resolvedURI = resolveRelativeURI(reference, relativeTo: resource.uri)
            return ResourceProxy(uri: resolvedURI, fragment: "/")
        }
    }

    /// Resolve references to the classifiers of the Ecore metamodel itself.
    ///
    /// URIs such as `ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EInt` and
    /// `ecore:EClass http://www.eclipse.org/emf/2002/Ecore#//EClass` name a built-in data
    /// type or a class of the Ecore metamodel. They resolve to the identifier of the real
    /// classifier of ``EcorePackage``, which a resource resolves back to that classifier.
    /// A name that Ecore does not define is represented by a data type of that name in the
    /// current resource.
    ///
    /// - Parameters:
    ///   - reference: The Ecore type URI reference.
    ///   - resource: The current resource used to register an unknown type.
    /// - Returns: The identifier of the classifier, or `nil` if the reference is not recognised.
    private func resolveEcoreBuiltinType(_ reference: String, in resource: Resource) async -> (
        any EcoreValue
    )? {
        // Extract the type name from the URI fragment
        guard let fragmentStart = reference.range(of: "#//") else { return nil }
        let typeName = String(reference[fragmentStart.upperBound...])

        if let classifier = EcorePackage.classifier(named: typeName) {
            return classifier.id
        }

        // Return cached type if available
        if let cachedType = builtinTypeCache[typeName] {
            return cachedType
        }

        // Represent a type that Ecore does not define by a data type of that name
        let eDataTypeClass = await getOrCreateEClass(
            EcoreClassifier.eDataType.rawValue, in: resource)
        var dataType = DynamicEObject(eClass: eDataTypeClass)
        dataType.eSet(.name, typeName)
        await resource.register(dataType)
        builtinTypeCache[typeName] = dataType

        return dataType
    }

    /// Resolve a relative URI against a base URI
    ///
    /// - Parameters:
    ///   - uri: The potentially relative URI
    ///   - baseURI: The base URI to resolve against
    /// - Returns: The resolved absolute or normalized URI
    private func resolveRelativeURI(_ uri: String, relativeTo baseURI: String) -> String {
        URIReference.resolve(uri, against: baseURI)
    }

    /// Resolve EMF fragment references like //ClassName/featureName
    ///
    /// Classes are found by name through an index that is built once per resolution pass, so
    /// that resolving a document takes time proportional to its size.
    ///
    /// - Parameters:
    ///   - fragment: The EMF fragment (without leading #) like "//Member/familyMother"
    ///   - resource: The current Resource containing all objects
    /// - Returns: The resolved object ID, or nil if not found
    private func resolveEMFFragmentReference(_ fragment: String, in resource: Resource) async -> (any EcoreValue)? {
        let components = fragment.dropFirst(2).split(separator: "/")
        guard components.count == 1 || components.count == 2 else {
            if debug {
                print("[XMI DEBUG] EMF fragment '\(fragment)' has invalid format, expected //ClassName or //ClassName/featureName")
            }
            return nil
        }
        let className = String(components[0])
        if debug { print("[XMI DEBUG] Resolving EMF fragment: class='\(className)'") }
        let index = await classIndex(in: resource)
        guard let classID = index.classes[className] else {
            if debug { print("[XMI DEBUG] Class '\(className)' not found") }
            return nil
        }
        guard components.count == 2 else { return classID }

        let featureName = String(components[1])
        let features = await featureIDs(ofClass: classID, in: resource)
        if debug && features[featureName] == nil {
            print("[XMI DEBUG] Feature '\(featureName)' not found in class '\(className)'")
        }
        return features[featureName]
    }

    /// The classes of the resource by name, built on first use in a resolution pass.
    ///
    /// The first class of a name in resource order wins, so that nested packages that reuse
    /// a name resolve as they always have.
    private func classIndex(in resource: Resource) async -> ClassIndex {
        if let index = resolutionIndex { return index }
        var index = ClassIndex()
        let classMetaclassName = EcoreClassifier.eClass.rawValue
        for object in await resource.getAllObjects() {
            guard let dynamicObject = object as? DynamicEObject,
                dynamicObject.eClass.name == classMetaclassName,
                let name = dynamicObject.eGet(XMIAttribute.name.rawValue) as? String,
                index.classes[name] == nil
            else { continue }
            index.classes[name] = dynamicObject.id
        }
        resolutionIndex = index
        return index
    }

    /// The structural features of a class by name, built on first use for that class.
    private func featureIDs(ofClass classID: EUUID, in resource: Resource) async -> [String: EUUID] {
        if let cached = resolutionIndex?.features[classID] { return cached }
        var features: [String: EUUID] = [:]
        if let owner = await resource.resolve(classID) as? DynamicEObject,
            let identifiers = owner.eGet(EcoreFeatureName.eStructuralFeatures.rawValue) as? [EUUID]
        {
            for identifier in identifiers {
                guard let feature = await resource.resolve(identifier) as? DynamicEObject,
                    let name = feature.eGet(XMIAttribute.name.rawValue) as? String,
                    features[name] == nil
                else { continue }
                features[name] = identifier
            }
        }
        resolutionIndex?.features[classID] = features
        return features
    }

    // MARK: - Helper Methods

    /// Get attribute names in document order to preserve EMF compliance
    ///
    /// SwiftXML's element.attributeNames returns attributes in alphabetical order,
    /// but EMF requires preserving insertion/document order. This method extracts
    /// the attribute names from the element's string representation to maintain
    /// the original XML document order.
    ///
    /// - Parameter element: The XElement to extract attribute names from
    /// - Returns: Array of attribute names in document order
    private func getAttributeNamesInDocumentOrder(for element: XElement) -> [String] {
        attributeOrder.names(for: element)
    }

    /// Looks up an EClass from registered metamodels, falling back to dynamic creation
    ///
    /// This method attempts to resolve the EClass in the following order:
    /// 1. If parent context is available, look up the reference's eType
    /// 2. Otherwise, resolve from ResourceSet using namespace URI
    /// 3. Fall back to creating a new dynamic EClass
    ///
    /// - Parameters:
    ///   - className: The name of the class to look up
    ///   - element: The XML element being parsed (for namespace resolution)
    ///   - resource: The resource being populated
    ///   - parentEClass: The parent element's EClass (if parsing a child element)
    ///   - referenceName: The name of the reference feature (XML element name)
    /// - Returns: The EClass from metamodel if found, otherwise a new dynamic EClass
    private func lookupEClass(
        className: String,
        element: XElement,
        resource: Resource,
        parentEClass: EClass? = nil,
        referenceName: String? = nil
    ) async -> EClass {
        // Step 1: Determine the actual type name from parent reference context.
        // The parent reference's eType may indicate the expected type, but since
        // EClass is a value type, it may be a stale copy. We use it only for the
        // type name, then prefer the canonical metamodel version.
        var referenceTypeName: String? = nil
        var referenceTypeFallback: EClass? = nil
        if let parentEClass = parentEClass,
            let referenceName = referenceName
        {
            if debug {
                print("[XMI] Resolving child '\(className)' via parent reference '\(parentEClass.name).\(referenceName)'")
            }
            if let reference = parentEClass.allReferences.first(where: { $0.name == referenceName })
            {
                if let referenceType = reference.eType as? EClass {
                    referenceTypeName = referenceType.name
                    referenceTypeFallback = referenceType
                    if debug {
                        print("[XMI]   Found reference type: \(referenceType.name) with \(referenceType.eStructuralFeatures.count) own features, \(referenceType.allStructuralFeatures.count) total")
                    }
                } else if debug {
                    print("[XMI]   Reference '\(referenceName)' eType is not EClass")
                }
            } else if debug {
                print("[XMI]   Reference '\(referenceName)' not found on parent '\(parentEClass.name)'")
                print("[XMI]   Parent has \(parentEClass.allReferences.count) references: \(parentEClass.allReferences.map { $0.name }.joined(separator: ", "))")
            }
        }

        // Determine the effective class name to look up.
        // When xsi:type is present, className is the specific polymorphic type
        // (e.g., "AssignmentIntegerLHS") and should take precedence over the
        // reference's declared type (e.g., "Statement"). Use the reference type
        // name only when className matches the element name (no xsi:type).
        let hasXsiType = element[XMIAttribute.xsiType.rawValue] != nil
        let effectiveName = hasXsiType ? className : (referenceTypeName ?? className)

        // Step 2: Always prefer canonical version from the metamodel
        if let resourceSet = self.resourceSet {
            if let namespaceURI = extractNamespaceURI(from: element) {
                if debug {
                    print("[XMI] Resolving class '\(effectiveName)' with namespace '\(namespaceURI)'")
                }
                if let metamodel = await resourceSet.getMetamodel(uri: namespaceURI) {
                    if debug {
                        print("[XMI]   Found metamodel: \(metamodel.name)")
                    }
                    if let eClass = metamodel.getClassifier(effectiveName) as? EClass {
                        if debug {
                            print("[XMI]   Found canonical EClass '\(eClass.name)' with \(eClass.eStructuralFeatures.count) own features, \(eClass.allStructuralFeatures.count) total")
                        }
                        eClassCache[effectiveName] = eClass
                        return eClass
                    } else if debug {
                        print("[XMI]   EClass '\(effectiveName)' not found in metamodel")
                    }
                } else if debug {
                    print("[XMI]   No metamodel registered for namespace '\(namespaceURI)'")
                }
            } else if debug {
                print("[XMI] No namespace URI found for element '\(element.name)'")
            }
        } else if debug {
            print("[XMI] No ResourceSet available for class lookup")
        }

        // Step 3: Check cache
        if let cachedClass = eClassCache[effectiveName] {
            return cachedClass
        }

        // Step 4: Use the reference type fallback if available
        if let fallback = referenceTypeFallback {
            if debug {
                print("[XMI] Using reference type fallback for '\(effectiveName)'")
            }
            eClassCache[effectiveName] = fallback
            return fallback
        }

        // Step 5: Fall back to dynamic EClass creation
        if debug {
            print("[XMI] Creating dynamic EClass for '\(effectiveName)'")
        }
        let eClass = EClass(name: effectiveName)
        eClassCache[effectiveName] = eClass
        return eClass
    }

    /// Extracts the namespace URI from an XML element
    ///
    /// Examines the element and its ancestors to find the namespace URI that should be used
    /// for metamodel lookup. Handles both default namespaces (xmlns="...") and prefixed
    /// namespaces (xmlns:prefix="...").
    ///
    /// - Parameter element: The XML element to extract namespace from
    /// - Returns: The namespace URI if found, nil otherwise
    private func extractNamespaceURI(from element: XElement) -> String? {
        // Case 1: Default namespace (xmlns="...")
        if let defaultNS = element[XMLNamespace.xmlns], !defaultNS.isEmpty {
            return defaultNS
        }

        // Case 2: Prefixed namespace (e.g., <fam:Member> with xmlns:fam="...")
        if element.name.contains(":") {
            let parts = element.name.split(separator: ":", maxSplits: 1)
            let prefix = String(parts[0])

            // Look up xmlns:prefix in attributes or ancestors
            let nsKey = XMLNamespace.prefixed(prefix)
            if let namespaceURI = element[nsKey] {
                return namespaceURI
            }
            // Also check ancestors for the prefixed namespace
            var current = element.parent
            while let parent = current {
                if let namespaceURI = parent[nsKey] {
                    return namespaceURI
                }
                current = parent.parent
            }
        }

        // Case 3: Check parent elements for namespace declarations
        // In XMI, child elements without a prefix inherit the metamodel namespace
        // from the root element. Check for both default (xmlns="...") and prefixed
        // (xmlns:prefix="...") namespace declarations, excluding standard XMI/XSI
        // namespaces.
        var current = element.parent
        while let parent = current {
            if let defaultNS = parent[XMLNamespace.xmlns], !defaultNS.isEmpty {
                return defaultNS
            }
            // Check prefixed namespaces on ancestors (for XMI instance models
            // where the root uses xmlns:metamodel="..." rather than xmlns="...")
            if let metamodelNS = extractMetamodelNamespace(from: parent) {
                return metamodelNS
            }
            current = parent.parent
        }

        return nil
    }

    /// Extracts the metamodel namespace URI from an element's prefixed xmlns declarations.
    ///
    /// Finds the first `xmlns:prefix` declaration that is not a standard XMI/XSI namespace,
    /// which in an XMI instance document is the metamodel namespace.
    ///
    /// - Parameter element: The XML element to examine.
    /// - Returns: The metamodel namespace URI if found, `nil` otherwise.
    private func extractMetamodelNamespace(from element: XElement) -> String? {
        // Standard namespaces to exclude
        let standardNamespaces: Set<String> = [
            EcoreURI.xmiNamespace.rawValue,
            EcoreURI.xsiNamespace.rawValue,
            EcoreURI.ecoreNamespace.rawValue,
        ]
        // Check for prefixed namespaces by examining the element's name for a prefix
        // then looking for xmlns:prefix on this element
        if element.name.contains(":") {
            let prefix = String(element.name.split(separator: ":", maxSplits: 1)[0])
            let nsKey = XMLNamespace.prefixed(prefix)
            if let uri = element[nsKey], !standardNamespaces.contains(uri) {
                return uri
            }
        }
        return nil
    }

    /// Lookup tables that make name-based fragment resolution linear.
    private struct ClassIndex {
        /// The identifier of the first class of each name.
        var classes: [String: EUUID] = [:]

        /// The structural features of each class by name, filled on demand.
        var features: [EUUID: [String: EUUID]] = [:]
    }

    /// Structure information collected during element analysis
    private struct ElementStructureInfo {
        let className: String
        let attributes: OrderedDictionary<String, String>  // name -> value
        let containmentRefs: OrderedDictionary<String, Bool>  // name -> isMultiValued
        let crossRefs: [String]  // feature names
    }

    /// Collect structural information from an XML element before creating objects
    private func collectStructuralInfo(from element: XElement) -> ElementStructureInfo {
        // Extract class name, preferring xsi:type if present (for polymorphic elements)
        let className: String
        if let xsiType = element[XMIAttribute.xsiType.rawValue] {
            // xsi:type="prefix:TypeName": extract the type name after the colon
            if xsiType.contains(":") {
                let parts = xsiType.split(separator: ":")
                className = String(parts.last ?? "")
            } else {
                className = xsiType
            }
        } else if element.name.contains(":") {
            let parts = element.name.split(separator: ":")
            className = String(parts.last ?? "")
        } else {
            className = element.name
        }

        var attributes: OrderedDictionary<String, String> = [:]
        var containmentRefs: OrderedDictionary<String, Bool> = [:]
        var crossRefs: [String] = []

        // Collect attributes
        for attributeName in element.attributeNames {
            if attributeName.hasPrefix("xmlns:") || attributeName.hasPrefix("xmi:")
                || attributeName.hasPrefix("xsi:")
            {
                continue
            }

            if let value = element[attributeName] {
                attributes[attributeName] = value
            }
        }

        // Collect child elements
        var childCounts: OrderedDictionary<String, Int> = [:]
        for child in element.children {
            let childName = child.name
            childCounts[childName, default: 0] += 1

            if child["href"] != nil {
                // Cross-reference
                if !crossRefs.contains(childName) {
                    crossRefs.append(childName)
                }
            } else {
                // Containment reference - we'll determine multiplicity after counting
            }
        }

        // Set multiplicity for containment references
        for (childName, count) in childCounts {
            if !crossRefs.contains(childName) {
                containmentRefs[childName] = count > 1
            }
        }

        return ElementStructureInfo(
            className: className,
            attributes: attributes,
            containmentRefs: containmentRefs,
            crossRefs: crossRefs
        )
    }

    /// Enhance an EClass with features discovered during parsing
    private func recordStructureInfo(for className: String, with info: ElementStructureInfo) {
        guard var eClass = eClassCache[className] else {
            return  // Class not found in cache
        }

        // Add attributes
        for (attrName, attrValue) in info.attributes {
            if eClass.getStructuralFeature(name: attrName) == nil {
                let value = inferType(from: attrValue)
                let dataType: EDataType
                switch value {
                case is String:
                    dataType = EDataType(name: "EString")
                case is Int:
                    dataType = EDataType(name: "EInt")
                case is Bool:
                    dataType = EDataType(name: "EBoolean")
                case is Double:
                    dataType = EDataType(name: "EDouble")
                case is Float:
                    dataType = EDataType(name: "EFloat")
                default:
                    dataType = EDataType(name: "EString")
                }

                let attribute = EAttribute(name: attrName, eType: dataType)
                eClass.eStructuralFeatures.append(attribute)
            }
        }

        // Add containment references
        for (refName, isMultiValued) in info.containmentRefs {
            if eClass.getStructuralFeature(name: refName) == nil {
                let targetType = EClass(name: "EObject")
                var reference = EReference(name: refName, eType: targetType)
                reference.containment = true
                reference.upperBound = isMultiValued ? -1 : 1
                eClass.eStructuralFeatures.append(reference)
            }
        }

        // Add cross-references
        for refName in info.crossRefs {
            if eClass.getStructuralFeature(name: refName) == nil {
                let targetType = EClass(name: "EObject")
                let reference = EReference(name: refName, eType: targetType)
                // Cross-references are not containment by default
                eClass.eStructuralFeatures.append(reference)
            }
        }

        // Update the cached EClass
        eClassCache[className] = eClass
    }
}
