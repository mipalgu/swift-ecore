//
// EcoreExtensions.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import SwiftXML

// MARK: - XElement Extensions for Type-Safe Access

extension XElement {
    /// Strongly-typed subscript for XMI attributes.
    ///
    /// Provides type-safe access to XMI attributes using the `XMIAttribute` enum
    /// instead of raw strings. This ensures compile-time checking of attribute names
    /// and prevents typos in attribute access.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let name = element[.name]
    /// let isAbstract = element[.abstract]
    /// element[.interface] = "true"
    /// ```
    ///
    /// - Parameter attribute: The XMI attribute to access
    /// - Returns: The string value of the attribute, or nil if not present
    subscript(attribute: XMIAttribute) -> String? {
        get {
            return self[attribute.rawValue]
        }
        set {
            self[attribute.rawValue] = newValue
        }
    }

    /// Retrieves a boolean value from an XMI attribute.
    ///
    /// Converts string representations of boolean values to actual boolean types,
    /// supporting both "true"/"false" strings and proper boolean parsing with
    /// case-insensitive matching.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let isAbstract = element.getBool(.abstract) ?? false
    /// let isInterface = element.getBool(.interface) ?? false
    /// ```
    ///
    /// - Parameter attribute: The XMI attribute to read as boolean
    /// - Returns: Boolean value, or nil if attribute is missing or invalid
    func getBool(_ attribute: XMIAttribute) -> Bool? {
        guard let stringValue = self[attribute] else { return nil }
        return BooleanString.fromString(stringValue)
    }

    /// Sets a boolean value to an XMI attribute.
    ///
    /// Converts boolean values to their string representations suitable for
    /// XMI serialisation using standardised "true"/"false" strings.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// element.setBool(.abstract, true)
    /// element.setBool(.interface, false)
    /// ```
    ///
    /// - Parameters:
    ///   - attribute: The XMI attribute to set
    ///   - value: The boolean value to set
    func setBool(_ attribute: XMIAttribute, _ value: Bool) {
        self[attribute] = BooleanString.toString(value)
    }

    /// Retrieves an integer value from an XMI attribute.
    ///
    /// Converts string representations to integer values with proper error handling
    /// for invalid numeric formats.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let lowerBound = element.getInt(.lowerBound) ?? 0
    /// let upperBound = element.getInt(.upperBound) ?? 1
    /// ```
    ///
    /// - Parameter attribute: The XMI attribute to read as integer
    /// - Returns: Integer value, or nil if attribute is missing or invalid
    func getInt(_ attribute: XMIAttribute) -> Int? {
        guard let stringValue = self[attribute] else { return nil }
        return Int(stringValue)
    }

    /// Sets an integer value to an XMI attribute.
    ///
    /// Converts integer values to their string representations for XMI serialisation.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// element.setInt(.lowerBound, 0)
    /// element.setInt(.upperBound, -1)
    /// ```
    ///
    /// - Parameters:
    ///   - attribute: The XMI attribute to set
    ///   - value: The integer value to set
    func setInt(_ attribute: XMIAttribute, _ value: Int) {
        self[attribute] = String(value)
    }

    /// Strongly-typed method for accessing child elements.
    ///
    /// Provides type-safe access to child elements using the `XMIElement` enum
    /// instead of raw strings, ensuring compile-time checking of element names.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let features = element.children(.eStructuralFeatures)
    /// let literals = element.children(.eLiterals)
    /// ```
    ///
    /// - Parameter elementType: The XMI element type to search for
    /// - Returns: Array of matching child elements
    func children(_ elementType: XMIElement) -> [XElement] {
        return self.children.filter { $0.name == elementType.rawValue }
    }

    /// Checks if element represents a specific Ecore classifier.
    ///
    /// Determines whether this XElement represents a specific Ecore metamodel
    /// classifier by checking both the element name and xsi:type attribute.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// if element.isEcoreType(.eClass) {
    ///     // Handle EClass element
    /// }
    /// ```
    ///
    /// - Parameter classifier: The Ecore classifier to check for
    /// - Returns: True if element represents the specified classifier
    func isEcoreType(_ classifier: EcoreClassifier) -> Bool {
        let expectedType = "ecore:\(classifier.rawValue)"
        return self.name == expectedType || self[.xmiType] == expectedType
            || self[.xsiType] == expectedType
    }

    /// Extracts Ecore built-in type name from a type reference.
    ///
    /// Parses Ecore built-in type URIs to extract the actual type name,
    /// handling the standard URI format used for built-in Ecore types.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// if let typeName = element.extractEcoreTypeName(.eType) {
    ///     // Use extracted type name
    /// }
    /// ```
    ///
    /// - Parameter attribute: The attribute containing the type reference
    /// - Returns: The extracted type name, or nil if not an Ecore built-in type
    func extractEcoreTypeName(_ attribute: XMIAttribute) -> String? {
        guard let typeReference = self[attribute] else { return nil }
        return EcoreURI.extractTypeName(from: typeReference)
    }
}

// MARK: - DynamicEObject Extensions for Type-Safe Access

extension DynamicEObject {

    /// Type-safe getter for EObject properties using XMI attribute names.
    ///
    /// Provides strongly-typed access to DynamicEObject properties using
    /// the `XMIAttribute` enum, ensuring consistency between XMI parsing
    /// and object property access.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let name: String? = dynamicObj.eGet(.name)
    /// let isAbstract: Bool? = dynamicObj.eGet(.abstract)
    /// ```
    ///
    /// - Parameter attribute: The XMI attribute corresponding to the property
    /// - Returns: The property value cast to the expected type, or nil if not present/wrong type
    func eGet<T>(_ attribute: XMIAttribute) -> T? {
        return eGet(attribute.rawValue) as? T
    }

    /// Type-safe setter for EObject properties using XMI attribute names.
    ///
    /// Provides strongly-typed access to set DynamicEObject properties using
    /// the `XMIAttribute` enum, ensuring consistency between object manipulation
    /// and XMI serialisation.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// dynamicObj.eSet(.name, "Person")
    /// dynamicObj.eSet(.abstract, true)
    /// ```
    ///
    /// - Parameters:
    ///   - attribute: The XMI attribute corresponding to the property
    ///   - value: The value to set for the property
    mutating func eSet(_ attribute: XMIAttribute, _ value: any EcoreValue) {
        eSet(attribute.rawValue, value: value)
    }

    /// Retrieves a boolean property with fallback conversion from string.
    ///
    /// Attempts to get a boolean value from the object, with fallback logic
    /// to convert string representations ("true"/"false") to boolean values.
    /// This handles cases where XMI attributes are stored as strings but
    /// should be interpreted as booleans.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let isAbstract = dynamicObj.getBoolProperty(.abstract, defaultValue: false)
    /// ```
    ///
    /// - Parameters:
    ///   - attribute: The XMI attribute to retrieve as boolean
    ///   - defaultValue: Default value if property is not set or invalid
    /// - Returns: Boolean value or the specified default
    func getBoolProperty(_ attribute: XMIAttribute, defaultValue: Bool = false) -> Bool {
        if let boolValue = eGet(attribute.rawValue) as? Bool {
            return boolValue
        } else if let stringValue = eGet(attribute.rawValue) as? String {
            return BooleanString.fromString(stringValue) ?? defaultValue
        }
        return defaultValue
    }

    /// Retrieves an integer property with safe conversion.
    ///
    /// Attempts to get an integer value from the object with safe type conversion
    /// and fallback to a default value if the property is not set or invalid.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let lowerBound = dynamicObj.getIntProperty(.lowerBound, defaultValue: 0)
    /// ```
    ///
    /// - Parameters:
    ///   - attribute: The XMI attribute to retrieve as integer
    ///   - defaultValue: Default value if property is not set or invalid
    /// - Returns: Integer value or the specified default
    func getIntProperty(_ attribute: XMIAttribute, defaultValue: Int = 0) -> Int {
        return eGet(attribute.rawValue) as? Int ?? defaultValue
    }

    /// Retrieves a string property with safe access.
    ///
    /// Provides safe access to string properties with optional default value
    /// handling for cases where the property might not be set.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let name = dynamicObj.getStringProperty(.name, defaultValue: "Unnamed")
    /// ```
    ///
    /// - Parameters:
    ///   - attribute: The XMI attribute to retrieve as string
    ///   - defaultValue: Default value if property is not set
    /// - Returns: String value or the specified default
    func getStringProperty(_ attribute: XMIAttribute, defaultValue: String = "") -> String {
        return eGet(attribute.rawValue) as? String ?? defaultValue
    }

    /// Type-safe getter for EObject properties using XMI element names.
    ///
    /// Provides strongly-typed access to DynamicEObject properties using
    /// the `XMIElement` enum for containment relationships and collections.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let features: [any EObject]? = dynamicObj.eGet(.eStructuralFeatures)
    /// let literals: [any EObject]? = dynamicObj.eGet(.eLiterals)
    /// ```
    ///
    /// - Parameter element: The XMI element corresponding to the property
    /// - Returns: The property value cast to the expected type, or nil if not present/wrong type
    func eGet<T>(_ element: XMIElement) -> T? {
        return eGet(element.rawValue) as? T
    }

    /// Type-safe setter for EObject properties using XMI element names.
    ///
    /// Provides strongly-typed access to set DynamicEObject properties using
    /// the `XMIElement` enum for containment relationships and collections.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// dynamicObj.eSet(.eStructuralFeatures, featureIds)
    /// dynamicObj.eSet(.eLiterals, literalIds)
    /// ```
    ///
    /// - Parameters:
    ///   - element: The XMI element corresponding to the property
    ///   - value: The value to set for the property
    mutating func eSet(_ element: XMIElement, _ value: any EcoreValue) {
        eSet(element.rawValue, value: value)
    }
}

// MARK: - String Extensions for Ecore Type Handling

extension String {

    /// Checks if this string represents an Ecore built-in data type.
    ///
    /// Determines whether the string matches any of the standard Ecore
    /// built-in data type names, useful for type resolution and validation.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// if typeName.isEcoreBuiltinType {
    ///     // Handle as built-in type
    /// }
    /// ```
    ///
    /// - Returns: True if the string matches an Ecore built-in type name
    var isEcoreBuiltinType: Bool {
        return EcoreDataType.allCases.contains { $0.rawValue == self }
    }

    /// Converts this string to the corresponding EcoreDataType enum case.
    ///
    /// Attempts to match the string against known Ecore data type names
    /// and returns the corresponding enum case for type-safe handling.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// if let dataType = typeName.asEcoreDataType {
    ///     let swiftType = dataType.swiftType
    /// }
    /// ```
    ///
    /// - Returns: The corresponding EcoreDataType enum case, or nil if not found
    var asEcoreDataType: EcoreDataType? {
        return EcoreDataType.allCases.first { $0.rawValue == self }
    }

    /// Checks if this string represents an Ecore classifier name.
    ///
    /// Determines whether the string matches any of the Ecore metamodel
    /// classifier names, useful for metamodel element identification.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// if className.isEcoreClassifier {
    ///     // Handle as metamodel classifier
    /// }
    /// ```
    ///
    /// - Returns: True if the string matches an Ecore classifier name
    var isEcoreClassifier: Bool {
        return EcoreClassifier.allCases.contains { $0.rawValue == self }
    }

    /// Converts this string to the corresponding EcoreClassifier enum case.
    ///
    /// Attempts to match the string against known Ecore classifier names
    /// and returns the corresponding enum case for type-safe handling.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// if let classifier = className.asEcoreClassifier {
    ///     // Handle specific classifier type
    /// }
    /// ```
    ///
    /// - Returns: The corresponding EcoreClassifier enum case, or nil if not found
    var asEcoreClassifier: EcoreClassifier? {
        return EcoreClassifier.allCases.first { $0.rawValue == self }
    }
}
