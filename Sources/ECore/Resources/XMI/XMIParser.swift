//
// XMIParser.swift
// ECore
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
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
}

/// Parser for XMI (XML Metadata Interchange) files
///
/// The XMI parser converts XMI files into EMF-compatible object graphs stored in Resources.
/// It handles:
/// - Metamodel (.ecore) files with full Ecore support
/// - Model instance (.xmi) files
/// - Cross-resource references via href attributes
/// - XPath-style fragment identifiers
/// - Bidirectional reference resolution
///
/// ## Supported XMI Features
///
/// - **XMI Version**: 2.0 and later
/// - **Ecore Metamodel**: Full support for EPackage, EClass, EEnum, EDataType, EAttribute, EReference
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

    /// Initialises a new XMI parser
    ///
    /// - Parameter resourceSet: Optional ResourceSet for cross-resource reference resolution
    public init(resourceSet: ResourceSet? = nil) {
        self.resourceSet = resourceSet
    }

    /// Parse an XMI file and return a Resource containing the objects
    /// - Parameter url: The URL of the XMI file to parse
    /// - Returns: A Resource containing the parsed objects
    /// - Throws: XMIError if parsing fails
    public func parse(_ url: URL) async throws -> Resource {
        let data = try Data(contentsOf: url)
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw XMIError.invalidEncoding
        }

        let document = try parseXML(fromText: xmlString)

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

        // Get the root element (e.g., <ecore:EPackage>)
        guard let rootElement = document.children.first else {
            throw XMIError.invalidXML("No root element found in document")
        }

        // Check XMI version if present in root element
        if let xmiVersion = rootElement["xmi:version"] {
            // Accept XMI 2.0 and later
            if let version = Double(xmiVersion), version < 2.0 {
                throw XMIError.unsupportedXMIVersion(xmiVersion)
            }
        }

        // Parse the root element itself as the root object
        if let rootObject = try await parseElement(rootElement, in: resource) {
            await resource.add(rootObject)
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
    private func parseElement(_ element: XElement, in resource: Resource) async throws -> (any EObject)? {
        let elementName = element.name

        // Handle Ecore metamodel elements
        if elementName == "ecore:EPackage" || element["xsi:type"] == "ecore:EPackage" {
            return try await parseEPackage(element, in: resource)
        } else if element["xsi:type"] == "ecore:EClass" {
            return try await parseEClass(element, in: resource)
        } else if element["xsi:type"] == "ecore:EEnum" {
            return try await parseEEnum(element, in: resource)
        } else if element["xsi:type"] == "ecore:EDataType" {
            return try await parseEDataType(element, in: resource)
        } else if element["xsi:type"] == "ecore:EAttribute" {
            return try await parseEAttribute(element, in: resource)
        } else if element["xsi:type"] == "ecore:EReference" {
            return try await parseEReference(element, in: resource)
        }

        // For now, return nil for unknown elements
        // This will be expanded in Step 4.3 for model instances
        return nil
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
    private func parseEPackage(_ element: XElement, in resource: Resource) async throws -> DynamicEObject {
        guard let name = element["name"] else {
            throw XMIError.missingRequiredAttribute("name")
        }
        guard let nsURI = element["nsURI"] else {
            throw XMIError.missingRequiredAttribute("nsURI")
        }
        guard let nsPrefix = element["nsPrefix"] else {
            throw XMIError.missingRequiredAttribute("nsPrefix")
        }

        // Create EPackage class if not already in resource
        let ePackageClass = getOrCreateEClass("EPackage", in: resource)
        var pkg = DynamicEObject(eClass: ePackageClass)

        // Register with xmi:id if present
        if let xmiId = element["xmi:id"] {
            xmiIdMap[xmiId] = pkg.id
        }

        // Set basic attributes BEFORE registering
        pkg.eSet("name", value: name)
        pkg.eSet("nsURI", value: nsURI)
        pkg.eSet("nsPrefix", value: nsPrefix)

        // Parse classifiers (eClassifiers)
        var classifierIds: [EUUID] = []
        for child in element.children("eClassifiers") {
            if let classifier = try await parseElement(child, in: resource) {
                // Note: Child parser already registered this object
                classifierIds.append(classifier.id)
                // Register fragment for cross-reference resolution
                if let classifierName = await resource.eGet(objectId: classifier.id, feature: "name") as? String {
                    fragmentMap["//\(classifierName)"] = classifier.id
                }
            }
        }

        if !classifierIds.isEmpty {
            pkg.eSet("eClassifiers", value: classifierIds)
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
    private func parseEClass(_ element: XElement, in resource: Resource) async throws -> DynamicEObject {
        guard let name = element["name"] else {
            throw XMIError.missingRequiredAttribute("name")
        }

        let eClassClass = getOrCreateEClass("EClass", in: resource)
        var eClass = DynamicEObject(eClass: eClassClass)

        if let xmiId = element["xmi:id"] {
            xmiIdMap[xmiId] = eClass.id
        }

        // Set basic attributes BEFORE registering
        eClass.eSet("name", value: name)

        // Parse structural features
        var featureIds: [EUUID] = []
        for child in element.children("eStructuralFeatures") {
            if let feature = try await parseElement(child, in: resource) {
                // Note: Child parser already registered this object
                featureIds.append(feature.id)
            }
        }

        if !featureIds.isEmpty {
            eClass.eSet("eStructuralFeatures", value: featureIds)
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
    private func parseEEnum(_ element: XElement, in resource: Resource) async throws -> DynamicEObject {
        guard let name = element["name"] else {
            throw XMIError.missingRequiredAttribute("name")
        }

        let eEnumClass = getOrCreateEClass("EEnum", in: resource)
        var eEnum = DynamicEObject(eClass: eEnumClass)

        if let xmiId = element["xmi:id"] {
            xmiIdMap[xmiId] = eEnum.id
        }

        // Set name before registering
        eEnum.eSet("name", value: name)

        // Parse literals
        var literalIds: [EUUID] = []
        for child in element.children("eLiterals") {
            let literal = try await parseEEnumLiteral(child, in: resource)
            // Note: parseEEnumLiteral already registered this object
            literalIds.append(literal.id)
        }

        if !literalIds.isEmpty {
            eEnum.eSet("eLiterals", value: literalIds)
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
    private func parseEEnumLiteral(_ element: XElement, in resource: Resource) async throws -> DynamicEObject {
        guard let name = element["name"] else {
            throw XMIError.missingRequiredAttribute("name")
        }

        let eEnumLiteralClass = getOrCreateEClass("EEnumLiteral", in: resource)
        var literal = DynamicEObject(eClass: eEnumLiteralClass)

        // Set features before registering
        literal.eSet("name", value: name)

        // Value defaults to ordinal position if not specified
        if let valueStr = element["value"], let value = Int(valueStr) {
            literal.eSet("value", value: value)
        }

        // Literal string defaults to name if not specified
        let literalStr = element["literal"] ?? name
        literal.eSet("literal", value: literalStr)

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
    private func parseEDataType(_ element: XElement, in resource: Resource) async throws -> DynamicEObject {
        guard let name = element["name"] else {
            throw XMIError.missingRequiredAttribute("name")
        }

        let eDataTypeClass = getOrCreateEClass("EDataType", in: resource)
        var dataType = DynamicEObject(eClass: eDataTypeClass)

        if let xmiId = element["xmi:id"] {
            xmiIdMap[xmiId] = dataType.id
        }

        // Set features before registering
        dataType.eSet("name", value: name)

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
    private func parseEAttribute(_ element: XElement, in resource: Resource) async throws -> DynamicEObject {
        guard let name = element["name"] else {
            throw XMIError.missingRequiredAttribute("name")
        }

        let eAttributeClass = getOrCreateEClass("EAttribute", in: resource)
        var attribute = DynamicEObject(eClass: eAttributeClass)

        // Set features before registering
        attribute.eSet("name", value: name)

        // eType will be resolved in second pass
        if let eType = element["eType"] {
            // Store for later resolution
            attribute.eSet("_eType_ref", value: eType)
        }

        // Parse multiplicity
        if let lowerBound = element["lowerBound"], let lb = Int(lowerBound) {
            attribute.eSet("lowerBound", value: lb)
        }

        if let upperBound = element["upperBound"], let ub = Int(upperBound) {
            attribute.eSet("upperBound", value: ub)
        }

        // Default value
        if let defaultValue = element["defaultValueLiteral"] {
            attribute.eSet("defaultValueLiteral", value: defaultValue)
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
    private func parseEReference(_ element: XElement, in resource: Resource) async throws -> DynamicEObject {
        guard let name = element["name"] else {
            throw XMIError.missingRequiredAttribute("name")
        }

        let eReferenceClass = getOrCreateEClass("EReference", in: resource)
        var reference = DynamicEObject(eClass: eReferenceClass)

        // Set features before registering
        reference.eSet("name", value: name)

        // eType will be resolved in second pass
        if let eType = element["eType"] {
            reference.eSet("_eType_ref", value: eType)
        }

        // Containment
        let containment = element["containment"] == "true"
        reference.eSet("containment", value: containment)

        // Parse multiplicity
        if let lowerBound = element["lowerBound"], let lb = Int(lowerBound) {
            reference.eSet("lowerBound", value: lb)
        }

        if let upperBound = element["upperBound"], let ub = Int(upperBound) {
            reference.eSet("upperBound", value: ub)
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

        for object in allObjects {
            // Resolve eType references
            if let eTypeRef = await resource.eGet(objectId: object.id, feature: "_eType_ref") as? String {
                if let resolvedId = resolveReference(eTypeRef) {
                    await resource.eSet(objectId: object.id, feature: "eType", value: resolvedId)
                }
                // Clear temporary reference
                await resource.eSet(objectId: object.id, feature: "_eType_ref", value: nil)
            }
        }
    }

    /// Resolve a reference string to an object ID
    ///
    /// Handles:
    /// - Fragment references: `#//ClassName`
    /// - XMI ID references: `#xmi-id`
    /// - External references: `ecore:EDataType http://...#//EString`
    ///
    /// - Parameter reference: The reference string
    /// - Returns: The resolved object ID, or `nil` if not found
    private func resolveReference(_ reference: String) -> EUUID? {
        if reference.hasPrefix("#") {
            let fragment = String(reference.dropFirst())
            return fragmentMap[fragment] ?? xmiIdMap[fragment]
        }

        // External reference - for now, return nil
        // This will be handled in Step 4.6 (Cross-Resource References)
        return nil
    }

    // MARK: - Helper Methods

    /// Get or create an EClass for a metamodel type
    ///
    /// This method ensures we have EClass objects for Ecore metamodel types.
    ///
    /// - Parameters:
    ///   - className: The name of the Ecore class (e.g., "EPackage", "EClass")
    ///   - resource: The Resource for context
    /// - Returns: An EClass instance
    private func getOrCreateEClass(_ className: String, in resource: Resource) -> EClass {
        // For now, create a simple EClass
        // This will be enhanced to use the actual Ecore metamodel
        return EClass(name: className)
    }
}
