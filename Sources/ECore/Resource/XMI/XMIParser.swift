//
// XMIParser.swift
// ECore
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
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

    /// Maps of parsed objects for reference resolution
    private var xmiIdMap: [String: EUUID] = [:]
    private var fragmentMap: [String: EUUID] = [:]
    private var referenceMap: [EUUID: [String: String]] = [:]  // object ID → (feature name → href)
    private var eClassCache: [String: EClass] = [:]  // className → EClass for caching dynamically created classes
    private var builtinTypeCache: [String: DynamicEObject] = [:]  // typeName → EDataType for built-in Ecore types

    /// Raw XML content for attribute order extraction
    private var rawXMLContent: String = ""

    /// Debug mode flag for systematic tracing
    private var debug: Bool = false

    /// Initialises a new XMI parser.
    ///
    /// - Parameters:
    ///   - resourceSet: Optional ResourceSet for cross-resource reference resolution
    ///   - enableDebugging: Whether to enable debug output for systematic tracing
    public init(resourceSet: ResourceSet? = nil, enableDebugging: Bool = false) {
        self.resourceSet = resourceSet
        debug = enableDebugging
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
        if debug {
            print("[XMI] Starting to parse file: \(url.path)")
        }

        let data = try Data(contentsOf: url)
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw XMIError.invalidEncoding
        }

        // Store raw XML content for attribute order extraction
        self.rawXMLContent = xmlString

        let document = try parseXML(fromText: xmlString)

        if debug {
            print("[XMI] Root element: '\(String(describing: document.name))'")
        }

        // Create resource via ResourceSet if available, otherwise create directly
        let resource: Resource
        if let resourceSet = resourceSet {
            resource = await resourceSet.createResource(uri: url.absoluteString)
        } else {
            resource = Resource(uri: url.absoluteString)
        }

        // Parse XMI content
        try await parseXMIContent(document, into: resource)

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
            for childElement in rootElement.children {
                if let rootObject = try await parseElement(childElement, in: resource) {
                    await resource.add(rootObject)
                }
            }
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
        if let xmiId = element[.xmiId] {
            xmiIdMap[xmiId] = instance.id
        }

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

            // Use type inference to convert string to appropriate type
            let value = inferType(from: attributeValue)
            instance.eSet(attributeName, value: value)
        }

        // Parse child elements (may be attributes or references)
        var childReferences: [String: [EUUID]] = [:]

        for child in element.children {
            let childName = child.name

            // Check if it's a reference or a contained object
            if let href = child["href"] {
                // It's a reference - store for second pass resolution
                referenceMap[instance.id, default: [:]][childName] = href
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

    // MARK: - Ecore Metamodel Parsing

    /// Parse an EPackage element
    ///
    /// Parses an Ecore package with its classifiers and nested packages.
    ///
    /// - Parameters:
    ///   - element: The ecore:EPackage XML element
    ///   - resource: The Resource for object storage
    /// - Returns: A DynamicEObject representing the EPackage
    /// - Throws: `XMIError.missingRequiredAttribute` if name, nsURI, or nsPrefix is missing
    private func parseEPackage(_ element: XElement, in resource: Resource) async throws
        -> DynamicEObject
    {
        guard let name = element[.name] else {
            throw XMIError.missingRequiredAttribute(ErrorMessage.missingNameAttribute.rawValue)
        }
        guard let nsURI = element["nsURI"] else {
            throw XMIError.missingRequiredAttribute("nsURI")
        }
        guard let nsPrefix = element["nsPrefix"] else {
            throw XMIError.missingRequiredAttribute("nsPrefix")
        }

        // Create EPackage class if not already in resource
        let ePackageClass = await getOrCreateEClass(EcoreClassifier.ePackage.rawValue, in: resource)
        var pkg = DynamicEObject(eClass: ePackageClass)

        // Register with xmi:id if present
        if let xmiId = element[.xmiId] {
            xmiIdMap[xmiId] = pkg.id
        }

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
        guard let name = element[.name] else {
            throw XMIError.missingRequiredAttribute(ErrorMessage.missingNameAttribute.rawValue)
        }

        let eClassClass = await getOrCreateEClass(EcoreClassifier.eClass.rawValue, in: resource)
        var eClass = DynamicEObject(eClass: eClassClass)

        if let xmiId = element[.xmiId] {
            xmiIdMap[xmiId] = eClass.id
        }

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

        // Parse eSuperTypes - will be resolved in second pass
        if let eSuperTypesAttr = element[.eSuperTypes] {
            eClass.eSet(EcoreClassifier.XMIParsingConstants.tempESuperTypesRef, value: eSuperTypesAttr)
            if debug {
                print("[XMI DEBUG] parseEClass: Found eSuperTypes='\(eSuperTypesAttr)' for class '\(name)'")
            }
        }

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

        // Register the object after all features are set
        await resource.register(eClass)

        return eClass
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
        guard let name = element[.name] else {
            throw XMIError.missingRequiredAttribute(ErrorMessage.missingNameAttribute.rawValue)
        }

        let eEnumClass = await getOrCreateEClass(EcoreClassifier.eEnum.rawValue, in: resource)
        var eEnum = DynamicEObject(eClass: eEnumClass)

        if let xmiId = element[.xmiId] {
            xmiIdMap[xmiId] = eEnum.id
        }

        // Set name before registering
        eEnum.eSet(.name, name)

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
        guard let name = element[.name] else {
            throw XMIError.missingRequiredAttribute(ErrorMessage.missingNameAttribute.rawValue)
        }

        let eEnumLiteralClass = await getOrCreateEClass(
            EcoreClassifier.eEnumLiteral.rawValue, in: resource)
        var literal = DynamicEObject(eClass: eEnumLiteralClass)

        // Set features before registering
        literal.eSet(.name, name)

        // Value defaults to ordinal position if not specified
        if let value = element.getInt(.value) {
            literal.eSet(.value, value)
        }

        // Literal string defaults to name if not specified
        let literalStr = element[.literal] ?? name
        literal.eSet(.literal, literalStr)

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
        guard let name = element[.name] else {
            throw XMIError.missingRequiredAttribute(ErrorMessage.missingNameAttribute.rawValue)
        }

        let eDataTypeClass = await getOrCreateEClass(
            EcoreClassifier.eDataType.rawValue, in: resource)
        var dataType = DynamicEObject(eClass: eDataTypeClass)

        if let xmiId = element[.xmiId] {
            xmiIdMap[xmiId] = dataType.id
        }

        // Set features before registering
        dataType.eSet(.name, name)

        // Parse instanceClassName attribute
        if let instanceClassName = element[.instanceClassName] {
            dataType.eSet(.instanceClassName, instanceClassName)
        }

        // Parse serializable attribute
        if let isSerializable = element.getBool(.serializable) {
            dataType.eSet(.serializable, isSerializable)
        }

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
        guard let name = element[.name] else {
            throw XMIError.missingRequiredAttribute(ErrorMessage.missingNameAttribute.rawValue)
        }

        let eAttributeClass = await getOrCreateEClass(
            EcoreClassifier.eAttribute.rawValue, in: resource)
        var attribute = DynamicEObject(eClass: eAttributeClass)

        // Set features before registering
        attribute.eSet(.name, name)

        // eType will be resolved in second pass
        if let eType = element[.eType] {
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
        guard let name = element[.name] else {
            throw XMIError.missingRequiredAttribute(ErrorMessage.missingNameAttribute.rawValue)
        }

        let eReferenceClass = await getOrCreateEClass(
            EcoreClassifier.eReference.rawValue, in: resource)
        var reference = DynamicEObject(eClass: eReferenceClass)

        // Set features before registering
        reference.eSet(.name, name)

        // eType will be resolved in second pass
        if let eType = element[.eType] {
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



        // Create XPath resolver for this resource
        let xpathResolver = XPathResolver(resource: resource)

        for object in allObjects {
            // Resolve eType references (metamodel)
            if let eTypeRef = await resource.eGet(objectId: object.id, feature: EcoreClassifier.XMIParsingConstants.tempETypeRef)
                as? String
            {
                if let resolved = await resolveReference(
                    eTypeRef, using: xpathResolver, in: resource)
                {
                    await resource.eSet(objectId: object.id, feature: XMIAttribute.eType.rawValue, value: resolved)
                }
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

            // Resolve eSuperTypes references (metamodel)
            if let eSuperTypesRef = await resource.eGet(objectId: object.id, feature: EcoreClassifier.XMIParsingConstants.tempESuperTypesRef)
                as? String
            {
                if debug {
                    print("[XMI DEBUG] resolveReferences: Resolving eSuperTypes reference '\(eSuperTypesRef)' for object \(object.id)")
                }

                // eSuperTypes can be a space-separated list of references
                let superTypeRefs = eSuperTypesRef.split(separator: " ").map(String.init)
                var resolvedSuperTypes: [EUUID] = []

                for superTypeRef in superTypeRefs {
                    if let resolved = await resolveReference(
                        superTypeRef, using: xpathResolver, in: resource),
                       let uuid = resolved as? EUUID
                    {
                        resolvedSuperTypes.append(uuid)
                        if debug {
                            print("[XMI DEBUG] resolveReferences: Successfully resolved superType '\(superTypeRef)' to \(uuid)")
                        }
                    } else if debug {
                        print("[XMI DEBUG] resolveReferences: Failed to resolve superType '\(superTypeRef)'")
                    }
                }

                // Set the resolved eSuperTypes
                if !resolvedSuperTypes.isEmpty {
                    // For single supertype, set it directly; for multiple, set as array
                    if resolvedSuperTypes.count == 1 {
                        await resource.eSet(objectId: object.id, feature: XMIAttribute.eSuperTypes.rawValue, value: resolvedSuperTypes[0])
                    } else {
                        await resource.eSet(objectId: object.id, feature: XMIAttribute.eSuperTypes.rawValue, value: resolvedSuperTypes)
                    }
                }

                // Clear temporary reference
                await resource.eSet(objectId: object.id, feature: EcoreClassifier.XMIParsingConstants.tempESuperTypesRef, value: nil)
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
        if reference.contains("http://www.eclipse.org/emf/2002/Ecore#//") {
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

            // Then try EMF fragment resolution (for paths like //ClassName/featureName)
            if fragment.hasPrefix("//") && !fragment.contains("@") {
                return await resolveEMFFragmentReference(fragment, in: resource)
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

    /// Resolve Ecore built-in types from URIs like "ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EInt"
    ///
    /// - Parameters:
    ///   - reference: The Ecore type URI reference
    ///   - resource: The current Resource for object storage
    /// - Returns: A DynamicEObject representing the built-in type, or nil if not recognized
    private func resolveEcoreBuiltinType(_ reference: String, in resource: Resource) async -> (
        any EcoreValue
    )? {
        // Extract the type name from the URI fragment
        guard let fragmentStart = reference.range(of: "#//") else { return nil }
        let typeName = String(reference[fragmentStart.upperBound...])

        // Return cached type if available
        if let cachedType = builtinTypeCache[typeName] {
            return cachedType
        }

        // Create appropriate built-in type
        let eDataTypeClass = await getOrCreateEClass(
            EcoreClassifier.eDataType.rawValue, in: resource)
        var dataType = DynamicEObject(eClass: eDataTypeClass)

        // Set the name based on the fragment
        dataType.eSet(.name, typeName)

        // Register with resource and cache
        Task {
            await resource.register(dataType)
        }
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
        // If URI has a scheme (protocol), it's absolute
        if uri.contains("://") {
            return uri
        }

        // Get the base directory from baseURI
        if let baseURL = URL(string: baseURI) {
            let baseDir = baseURL.deletingLastPathComponent()
            let resolvedURL = baseDir.appendingPathComponent(uri)
            return resolvedURL.absoluteString
        }

        // Fallback: simple concatenation
        if let lastSlash = baseURI.lastIndex(of: "/") {
            let baseDir = String(baseURI[...lastSlash])
            return baseDir + uri
        }

        return uri
    }

    /// Resolve EMF fragment references like //ClassName/featureName
    ///
    /// - Parameters:
    ///   - fragment: The EMF fragment (without leading #) like "//Member/familyMother"
    ///   - resource: The current Resource containing all objects
    /// - Returns: The resolved object ID, or nil if not found
    private func resolveEMFFragmentReference(_ fragment: String, in resource: Resource) async -> (any EcoreValue)? {
        // Remove leading "//"
        let path = String(fragment.dropFirst(2))
        let components = path.split(separator: "/")

        if components.count == 1 {
            // Format: //ClassName - resolve to the EClass itself
            let className = String(components[0])

            if debug {
                print("[XMI DEBUG] Resolving EMF fragment to class: '\(className)'")
            }

            // Find the EClass with the given name
            let allObjects = await resource.getAllObjects()
            for object in allObjects {
                if let dynamicObj = object as? DynamicEObject,
                   dynamicObj.eClass.name == "EClass",
                   let objName = dynamicObj.eGet("name") as? String,
                   objName == className {

                    if debug {
                        print("[XMI DEBUG] Found class '\(className)' with ID \(object.id)")
                    }
                    return object.id
                }
            }

            if debug {
                print("[XMI DEBUG] Class '\(className)' not found")
            }
            return nil

        } else if components.count == 2 {
            // Format: //ClassName/featureName - resolve to a feature within the class
            let className = String(components[0])
            let featureName = String(components[1])

            if debug {
                print("[XMI DEBUG] Resolving EMF fragment: class='\(className)', feature='\(featureName)'")
            }

            // Find the EClass with the given name
            let allObjects = await resource.getAllObjects()
            for object in allObjects {
                if let dynamicObj = object as? DynamicEObject,
                   dynamicObj.eClass.name == "EClass",
                   let objName = dynamicObj.eGet("name") as? String,
                   objName == className {

                    if debug {
                        print("[XMI DEBUG] Found class '\(className)' with ID \(object.id)")
                    }

                    // Find the feature within this class
                    if let featureIds = dynamicObj.eGet("eStructuralFeatures") as? [EUUID] {
                        for featureId in featureIds {
                            if let featureObj = await resource.resolve(featureId) as? DynamicEObject,
                               let featureObjName = featureObj.eGet("name") as? String,
                               featureObjName == featureName {

                                if debug {
                                    print("[XMI DEBUG] Found feature '\(featureName)' with ID \(featureId)")
                                }
                                return featureId
                            }
                        }
                    }

                    if debug {
                        print("[XMI DEBUG] Feature '\(featureName)' not found in class '\(className)'")
                    }
                    return nil
                }
            }

            if debug {
                print("[XMI DEBUG] Class '\(className)' not found")
            }
            return nil

        } else {
            if debug {
                print("[XMI DEBUG] EMF fragment '\(fragment)' has invalid format, expected //ClassName or //ClassName/featureName")
            }
            return nil
        }
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
        // Get the element name (strip namespace prefix for matching)
        // elementName not needed for current matching approach

        // Create unique signature for this element by using its attribute values
        // This helps us identify which specific element instance we're parsing
        var uniqueAttributes: [String: String] = [:]
        for attrName in element.attributeNames {
            if let value = element[attrName] {
                uniqueAttributes[attrName] = value
            }
        }

        // Create regex to match all elements with this tag name
        let elementRegex = /<\s*\w*:?\w+(?:\s+([^>]*?))?\s*\/?>/

        // Find all matches and identify the specific one by attribute values
        let matches = rawXMLContent.matches(of: elementRegex)

        for match in matches {
            guard let attributesCapture = match.1,
                !String(attributesCapture).isEmpty
            else { continue }

            let attributesString = String(attributesCapture)

            // Skip empty attribute strings
            if attributesString.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }

            // Extract all attributes from this element
            let attrRegex = /(\w+(?::\w+)?)\s*=\s*"([^"]*)"|(\w+(?::\w+)?)\s*=\s*'([^']*)'/
            var foundAttributes: [String: String] = [:]

            for attrMatch in attributesString.matches(of: attrRegex) {
                if let name = attrMatch.1, let value = attrMatch.2 {
                    foundAttributes[String(name)] = String(value)
                } else if let name = attrMatch.3, let value = attrMatch.4 {
                    foundAttributes[String(name)] = String(value)
                }
            }

            // Check if this matches our target element by comparing attribute values
            var isMatch = true
            for (attrName, expectedValue) in uniqueAttributes {
                // Skip namespace attributes for matching as they might differ in representation
                if attrName.hasPrefix("xmlns") || attrName.hasPrefix("xmi:") { continue }

                if foundAttributes[attrName] != expectedValue {
                    isMatch = false
                    break
                }
            }

            if isMatch {
                // Extract attribute names in document order for this specific element
                var orderedNames: [String] = []
                let nameOnlyRegex = /(\w+(?::\w+)?)\s*=\s*(?:"[^"]*"|'[^']*')/

                for nameMatch in attributesString.matches(of: nameOnlyRegex) {
                    let attributeName = String(nameMatch.1)
                    // Only include attributes that exist in SwiftXML's list
                    if element.attributeNames.contains(attributeName) {
                        orderedNames.append(attributeName)
                    }
                }

                if !orderedNames.isEmpty {
                    return orderedNames
                }
            }
        }

        // Fallback to SwiftXML's alphabetical order
        return element.attributeNames
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
        // Step 1: If we have parent context, try to resolve from the reference type
        if let parentEClass = parentEClass,
            let referenceName = referenceName
        {
            if debug {
                print("[XMI] Resolving child '\(className)' via parent reference '\(parentEClass.name).\(referenceName)'")
            }
            // Look for a reference feature with this name
            if let reference = parentEClass.allReferences.first(where: { $0.name == referenceName })
            {
                // Get the eType of the reference
                if let referenceType = reference.eType as? EClass {
                    if debug {
                        print("[XMI]   Found from parent reference: \(referenceType.name) with \(referenceType.eStructuralFeatures.count) features")
                        print("[XMI]   EClass ID: \(referenceType.id)")
                        if referenceType.name == "Member" {
                            print("[XMI]   Member features: \(referenceType.eStructuralFeatures.map { $0.name }.joined(separator: ", "))")
                        }
                    }
                    // Cache using the actual type name, not the element name
                    eClassCache[referenceType.name] = referenceType
                    return referenceType
                } else if debug {
                    print("[XMI]   Reference '\(referenceName)' eType is not EClass")
                }
            } else if debug {
                print("[XMI]   Reference '\(referenceName)' not found on parent '\(parentEClass.name)'")
                print("[XMI]   Parent has \(parentEClass.allReferences.count) references: \(parentEClass.allReferences.map { $0.name }.joined(separator: ", "))")
            }
        }

        // Step 2: Check cache
        if let cachedClass = eClassCache[className] {
            return cachedClass
        }

        // Step 3: Try to resolve from ResourceSet using namespace
        if let resourceSet = self.resourceSet {
            // Extract namespace URI from element
            if let namespaceURI = extractNamespaceURI(from: element) {
                if debug {
                    print("[XMI] Resolving class '\(className)' with namespace '\(namespaceURI)'")
                }
                // Query ResourceSet for metamodel
                if let metamodel = await resourceSet.getMetamodel(uri: namespaceURI) {
                    if debug {
                        print("[XMI]   Found metamodel: \(metamodel.name)")
                    }
                    // Look up EClass by name
                    if let eClass = metamodel.getClassifier(className) as? EClass {
                        if debug {
                            print("[XMI]   Found EClass with \(eClass.eStructuralFeatures.count) features")
                            print("[XMI]   EClass ID: \(eClass.id)")
                            if eClass.name == "Member" {
                                print("[XMI]   Member features: \(eClass.eStructuralFeatures.map { $0.name }.joined(separator: ", "))")
                            }
                        }
                        // Cache and return
                        eClassCache[className] = eClass
                        return eClass
                    } else if debug {
                        print("[XMI]   EClass '\(className)' not found in metamodel")
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

        // Step 4: Fall back to dynamic EClass creation
        if debug {
            print("[XMI] Creating dynamic EClass for '\(className)'")
        }
        let eClass = EClass(name: className)
        eClassCache[className] = eClass
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

            // Look up xmlns:prefix in attributes
            let nsKey = XMLNamespace.prefixed(prefix)
            if let namespaceURI = element[nsKey] {
                return namespaceURI
            }
        }

        // Case 3: Check parent elements for namespace declarations
        // (XMI namespace can be declared on root and inherited)
        var current = element.parent
        while let parent = current {
            if let defaultNS = parent[XMLNamespace.xmlns], !defaultNS.isEmpty {
                return defaultNS
            }
            current = parent.parent
        }

        return nil
    }

    /// Structure information collected during element analysis
    private struct ElementStructureInfo {
        let className: String
        let attributes: [String: String]  // name -> value
        let containmentRefs: [String: Bool]  // name -> isMultiValued
        let crossRefs: [String]  // feature names
    }

    /// Collect structural information from an XML element before creating objects
    private func collectStructuralInfo(from element: XElement) -> ElementStructureInfo {
        // Extract class name
        let className: String
        if element.name.contains(":") {
            let parts = element.name.split(separator: ":")
            className = String(parts.last ?? "")
        } else {
            className = element.name
        }

        var attributes: [String: String] = [:]
        var containmentRefs: [String: Bool] = [:]
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
        var childCounts: [String: Int] = [:]
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
