//
// EcoreConstants.swift
// ECore
//
//  Created by Rene Hexel on 17/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//

import Foundation
import BigInt

// MARK: - XMI Attribute Names

/// XMI attribute names used in Ecore metamodel serialisation.
///
/// Provides type-safe access to XMI attribute names used throughout the Ecore
/// metamodel serialisation and deserialisation process. These correspond to
/// standard Ecore XMI attributes defined by the Eclipse Modeling Framework.
///
/// ## Usage
///
/// ```swift
/// let name = element[XMIAttribute.name.rawValue]
/// let isAbstract = element[XMIAttribute.abstract.rawValue]
/// ```
///
/// ## XML Namespace Handling
///
/// Attributes with XML namespace prefixes are included with their full qualified names
/// for proper XMI compliance.
public enum XMIAttribute: String, CaseIterable, Sendable {
    // MARK: - Core Metamodel Attributes

    /// The name attribute for all named elements.
    case name = "name"

    /// The abstract flag for EClass elements.
    case abstract = "abstract"

    /// The interface flag for EClass elements.
    case interface = "interface"

    /// The containment flag for EReference elements.
    case containment = "containment"

    /// The changeable flag for structural features.
    case changeable = "changeable"

    /// The volatile flag for structural features.
    case volatile = "volatile"

    /// The transient flag for structural features.
    case transient = "transient"

    /// The ID flag for EAttribute elements (note: Ecore uses "iD", not "isID").
    case iD = "iD"

    /// The serialisable flag for EDataType elements.
    case serializable = "serializable"

    /// The instance class name for EDataType elements.
    case instanceClassName = "instanceClassName"

    /// The default value literal for structural features.
    case defaultValueLiteral = "defaultValueLiteral"

    /// The resolve proxies flag for EReference elements.
    case resolveProxies = "resolveProxies"

    // MARK: - Multiplicity Attributes

    /// The lower bound for structural features.
    case lowerBound = "lowerBound"

    /// The upper bound for structural features.
    case upperBound = "upperBound"

    // MARK: - Type References

    /// The type reference for structural features.
    case eType = "eType"

    /// The opposite reference for EReference elements.
    case opposite = "opposite"

    // MARK: - XMI-Specific Attributes

    /// The XMI identifier attribute.
    case xmiId = "xmi:id"

    /// The XMI type attribute.
    case xmiType = "xmi:type"

    /// The XSI type attribute.
    case xsiType = "xsi:type"

    /// The XMI version attribute.
    case xmiVersion = "xmi:version"

    /// The XMI UUID attribute.
    case xmiUuid = "xmi:uuid"

    // MARK: - Enum-Specific Attributes

    /// The literal value for EEnumLiteral elements.
    case literal = "literal"

    /// The enumeration value for EEnumLiteral elements.
    case value = "value"

    // MARK: - Documentation

    /// Brief description of the attribute's purpose.
    ///
    /// Provides a human-readable description of what this XMI attribute represents
    /// in the Ecore metamodel.
    public var description: String {
        switch self {
        case .name: return "Element name identifier"
        case .abstract: return "Abstract class flag"
        case .interface: return "Interface class flag"
        case .containment: return "Containment reference flag"
        case .changeable: return "Modifiable feature flag"
        case .volatile: return "Transient storage flag"
        case .transient: return "Serialisation exclusion flag"
        case .iD: return "Primary key attribute flag"
        case .serializable: return "Serialisable data type flag"
        case .instanceClassName: return "Java class name mapping"
        case .defaultValueLiteral: return "Default value expression"
        case .resolveProxies: return "Proxy resolution flag"
        case .lowerBound: return "Minimum multiplicity bound"
        case .upperBound: return "Maximum multiplicity bound"
        case .eType: return "Feature type reference"
        case .opposite: return "Bidirectional reference opposite"
        case .xmiId: return "XMI element identifier"
        case .xmiType: return "XMI element type declaration"
        case .xsiType: return "XSI element type declaration"
        case .xmiVersion: return "XMI specification version"
        case .xmiUuid: return "XMI universally unique identifier"
        case .literal: return "Enumeration literal name"
        case .value: return "Enumeration literal ordinal"
        }
    }
}

// MARK: - XMI Element Names

/// XMI element names used in Ecore metamodel structure.
///
/// Provides type-safe access to XMI element names that define the structure
/// of Ecore metamodel documents. These correspond to the containment relationships
/// in the Ecore metamodel.
///
/// ## Usage
///
/// ```swift
/// for child in element.children(XMIElement.eStructuralFeatures.rawValue) {
///     // Process structural features
/// }
/// ```
public enum XMIElement: String, CaseIterable, Sendable {
    /// Structural features containment for EClass elements.
    case eStructuralFeatures = "eStructuralFeatures"

    /// Enum literals containment for EEnum elements.
    case eLiterals = "eLiterals"

    /// Supertypes reference for EClass elements.
    case eSuperTypes = "eSuperTypes"

    /// Classifiers containment for EPackage elements.
    case eClassifiers = "eClassifiers"

    /// Subpackages containment for EPackage elements.
    case eSubpackages = "eSubpackages"

    /// Operations containment for EClass elements.
    case eOperations = "eOperations"

    /// Parameters containment for EOperation elements.
    case eParameters = "eParameters"

    /// Annotations containment for annotated elements.
    case eAnnotations = "eAnnotations"

    /// Generic types containment for parameterised types.
    case eGenericTypes = "eGenericTypes"

    /// Type parameters containment for generic classifiers.
    case eTypeParameters = "eTypeParameters"

    /// Brief description of the element's purpose.
    ///
    /// Provides a human-readable description of what this XMI element represents
    /// in the Ecore metamodel structure.
    public var description: String {
        switch self {
        case .eStructuralFeatures: return "Class attributes and references"
        case .eLiterals: return "Enumeration literal values"
        case .eSuperTypes: return "Class inheritance hierarchy"
        case .eClassifiers: return "Package type definitions"
        case .eSubpackages: return "Nested package structure"
        case .eOperations: return "Class method definitions"
        case .eParameters: return "Operation parameter list"
        case .eAnnotations: return "Metadata annotations"
        case .eGenericTypes: return "Parameterised type declarations"
        case .eTypeParameters: return "Generic type parameters"
        }
    }
}

// MARK: - Ecore Classifier Names

/// Ecore metamodel classifier names.
///
/// Provides type-safe access to the names of built-in Ecore metamodel classifiers.
/// These are the fundamental types that make up the Ecore metamodel itself.
///
/// ## Usage
///
/// ```swift
/// let eClassClass = getOrCreateEClass(EcoreClassifier.eClass.rawValue, in: resource)
/// ```
public enum EcoreClassifier: String, CaseIterable, Sendable {
    /// The EClass metaclass name.
    case eClass = "EClass"

    /// The EAttribute metaclass name.
    case eAttribute = "EAttribute"

    /// The EReference metaclass name.
    case eReference = "EReference"

    /// The EDataType metaclass name.
    case eDataType = "EDataType"

    /// The EEnum metaclass name.
    case eEnum = "EEnum"

    /// The EEnumLiteral metaclass name.
    case eEnumLiteral = "EEnumLiteral"

    /// The EPackage metaclass name.
    case ePackage = "EPackage"

    /// The EOperation metaclass name.
    case eOperation = "EOperation"

    /// The EParameter metaclass name.
    case eParameter = "EParameter"

    /// The EFactory metaclass name.
    case eFactory = "EFactory"

    /// The EObject base class name.
    case eObject = "EObject"

    /// The EAnnotation metaclass name.
    case eAnnotation = "EAnnotation"

    /// The EStringToStringMapEntry metaclass name.
    case eStringToStringMapEntry = "EStringToStringMapEntry"

    /// The EGenericType metaclass name.
    case eGenericType = "EGenericType"

    /// The ETypeParameter metaclass name.
    case eTypeParameter = "ETypeParameter"

    /// Brief description of the classifier's purpose.
    ///
    /// Provides a human-readable description of what this Ecore classifier represents
    /// in the metamodel.
    public var description: String {
        switch self {
        case .eClass: return "Class definition metaclass"
        case .eAttribute: return "Attribute definition metaclass"
        case .eReference: return "Reference definition metaclass"
        case .eDataType: return "Data type definition metaclass"
        case .eEnum: return "Enumeration definition metaclass"
        case .eEnumLiteral: return "Enumeration literal metaclass"
        case .ePackage: return "Package definition metaclass"
        case .eOperation: return "Operation definition metaclass"
        case .eParameter: return "Parameter definition metaclass"
        case .eFactory: return "Factory definition metaclass"
        case .eObject: return "Base model object class"
        case .eAnnotation: return "Annotation metaclass"
        case .eStringToStringMapEntry: return "String map entry metaclass"
        case .eGenericType: return "Generic type metaclass"
        case .eTypeParameter: return "Type parameter metaclass"
        }
    }
}

// MARK: - Ecore Data Type Names

/// Ecore built-in data type names.
///
/// Provides type-safe access to the names of built-in Ecore data types.
/// These correspond to primitive types and common classes used in Ecore models.
///
/// ## Usage
///
/// ```swift
/// let stringType = resolveBuiltinType(EcoreDataType.eString.rawValue)
/// ```
///
/// ## Built-in Type Hierarchy
///
/// The Ecore data types map to corresponding platform types:
/// - Primitive types: `EString`, `EInt`, `EBoolean`, etc.
/// - Object wrapper types: `EStringObject`, `EIntegerObject`, etc.
/// - Collection types: Various Java collection interfaces
public enum EcoreDataType: String, CaseIterable, Sendable {
    // MARK: - Primitive Types

    /// String primitive type.
    case eString = "EString"

    /// Integer primitive type.
    case eInt = "EInt"

    /// Boolean primitive type.
    case eBoolean = "EBoolean"

    /// Single-precision float primitive type.
    case eFloat = "EFloat"

    /// Double-precision float primitive type.
    case eDouble = "EDouble"

    /// Date primitive type.
    case eDate = "EDate"

    /// Character primitive type.
    case eChar = "EChar"

    /// Byte primitive type.
    case eByte = "EByte"

    /// Short integer primitive type.
    case eShort = "EShort"

    /// Long integer primitive type.
    case eLong = "ELong"

    /// Arbitrary precision decimal type.
    case eBigDecimal = "EBigDecimal"

    /// Arbitrary precision integer type.
    case eBigInteger = "EBigInteger"

    // MARK: - Object Wrapper Types

    /// String object wrapper type.
    case eStringObject = "EStringObject"

    /// Integer object wrapper type.
    case eIntegerObject = "EIntegerObject"

    /// Boolean object wrapper type.
    case eBooleanObject = "EBooleanObject"

    /// Float object wrapper type.
    case eFloatObject = "EFloatObject"

    /// Double object wrapper type.
    case eDoubleObject = "EDoubleObject"

    /// Character object wrapper type.
    case eCharacterObject = "ECharacterObject"

    /// Byte object wrapper type.
    case eByteObject = "EByteObject"

    /// Short object wrapper type.
    case eShortObject = "EShortObject"

    /// Long object wrapper type.
    case eLongObject = "ELongObject"

    // MARK: - Collection Types

    /// List interface type.
    case eEList = "EEList"

    /// Tree iterator interface type.
    case eTreeIterator = "ETreeIterator"

    /// Feature map interface type.
    case eFeatureMap = "EFeatureMap"

    /// Feature map entry interface type.
    case eFeatureMapEntry = "EFeatureMapEntry"

    /// Resource interface type.
    case eResource = "EResource"

    /// Resource set interface type.
    case eResourceSet = "EResourceSet"

    // MARK: - Java Class Types

    /// Java Class type.
    case eJavaClass = "EJavaClass"

    /// Java Object type.
    case eJavaObject = "EJavaObject"

    /// Corresponding Swift type for this data type.
    ///
    /// Maps Ecore data types to their equivalent Swift types for type-safe
    /// value handling and conversion.
    public var swiftType: Any.Type {
        switch self {
        case .eString, .eStringObject: return String.self
        case .eInt, .eIntegerObject: return Int.self
        case .eBoolean, .eBooleanObject: return Bool.self
        case .eFloat, .eFloatObject: return Float.self
        case .eDouble, .eDoubleObject: return Double.self
        case .eDate: return Date.self
        case .eChar, .eCharacterObject: return Character.self
        case .eByte, .eByteObject: return Int8.self
        case .eShort, .eShortObject: return Int16.self
        case .eLong, .eLongObject: return Int64.self
        case .eBigDecimal: return Decimal.self
        case .eBigInteger: return BigInt.self
        case .eEList: return Array<Any>.self
        case .eTreeIterator: return AnyIterator<Any>.self
        default: return Any.self
        }
    }

    /// Brief description of the data type's purpose.
    ///
    /// Provides a human-readable description of what this Ecore data type represents.
    public var description: String {
        switch self {
        case .eString: return "String primitive type"
        case .eInt: return "Integer primitive type"
        case .eBoolean: return "Boolean primitive type"
        case .eFloat: return "Float primitive type"
        case .eDouble: return "Double primitive type"
        case .eDate: return "Date/time primitive type"
        case .eChar: return "Character primitive type"
        case .eByte: return "Byte primitive type"
        case .eShort: return "Short integer primitive type"
        case .eLong: return "Long integer primitive type"
        case .eBigDecimal: return "Arbitrary precision decimal type"
        case .eBigInteger: return "Arbitrary precision integer type"
        case .eStringObject: return "String object wrapper"
        case .eIntegerObject: return "Integer object wrapper"
        case .eBooleanObject: return "Boolean object wrapper"
        case .eFloatObject: return "Float object wrapper"
        case .eDoubleObject: return "Double object wrapper"
        case .eCharacterObject: return "Character object wrapper"
        case .eByteObject: return "Byte object wrapper"
        case .eShortObject: return "Short object wrapper"
        case .eLongObject: return "Long object wrapper"
        case .eEList: return "Ordered collection interface"
        case .eTreeIterator: return "Tree traversal iterator interface"
        case .eFeatureMap: return "Dynamic feature map interface"
        case .eFeatureMapEntry: return "Feature map entry interface"
        case .eResource: return "Model resource interface"
        case .eResourceSet: return "Resource collection interface"
        case .eJavaClass: return "Java class reflection type"
        case .eJavaObject: return "Java object base type"
        }
    }
}

// MARK: - Boolean String Constants

/// Boolean string representations used in XMI serialisation.
///
/// Provides type-safe access to string representations of boolean values
/// as they appear in XMI documents. Supports both standard and alternative
/// representations for robust parsing.
///
/// ## Usage
///
/// ```swift
/// let isAbstract = BooleanString.trueValue.rawValue == abstractAttribute
/// ```
public enum BooleanString: String, CaseIterable, Sendable {
    /// String representation of true value.
    case trueValue = "true"

    /// String representation of false value.
    case falseValue = "false"

    /// Converts string to boolean value.
    ///
    /// Performs case-insensitive conversion from string to boolean,
    /// supporting standard true/false representations.
    ///
    /// - Parameter string: String to convert
    /// - Returns: Boolean value, or nil if string is not recognised
    public static func fromString(_ string: String) -> Bool? {
        switch string.lowercased() {
        case trueValue.rawValue:
            return true
        case falseValue.rawValue:
            return false
        default:
            return nil
        }
    }

    /// Converts boolean to string representation.
    ///
    /// - Parameter value: Boolean value to convert
    /// - Returns: String representation suitable for XMI serialisation
    public static func toString(_ value: Bool) -> String {
        return value ? trueValue.rawValue : falseValue.rawValue
    }
}

// MARK: - URI Constants

/// URI constants for Ecore built-in types and namespaces.
///
/// Provides type-safe access to standard URIs used in Ecore models for
/// built-in types, namespaces, and cross-references.
///
/// ## Usage
///
/// ```swift
/// if reference.hasPrefix(EcoreURI.ecoreDataTypePrefix.rawValue) {
///     // Handle built-in type reference
/// }
/// ```
public enum EcoreURI: String, CaseIterable, Sendable {
    /// Ecore metamodel namespace URI.
    case ecoreNamespace = "http://www.eclipse.org/emf/2002/Ecore"

    /// Ecore data type URI prefix for built-in types.
    case ecoreDataTypePrefix = "ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//"

    /// Ecore class URI prefix for built-in classes.
    case ecoreClassPrefix = "ecore:EClass http://www.eclipse.org/emf/2002/Ecore#//"

    /// XMI namespace URI.
    case xmiNamespace = "http://www.omg.org/XMI"

    /// XML Schema instance namespace URI.
    case xsiNamespace = "http://www.w3.org/2001/XMLSchema-instance"

    /// Extracts type name from Ecore built-in type URI.
    ///
    /// Parses an Ecore built-in type URI to extract the type name
    /// from the fragment portion.
    ///
    /// - Parameter uri: The full URI to parse
    /// - Returns: The extracted type name, or nil if URI format is invalid
    public static func extractTypeName(from uri: String) -> String? {
        if let range = uri.range(of: "#//") {
            return String(uri[range.upperBound...])
        }
        return nil
    }

    /// Builds a full Ecore built-in type URI.
    ///
    /// Constructs a complete URI for referencing built-in Ecore types
    /// using the standard URI format.
    ///
    /// - Parameter typeName: The name of the built-in type
    /// - Returns: Complete URI for the specified type
    public static func buildEcoreTypeURI(for typeName: String) -> String {
        return "\(ecoreDataTypePrefix.rawValue)\(typeName)"
    }
}

// MARK: - Error Message Constants

/// Standardised error messages for Ecore operations.
///
/// Provides type-safe access to consistent error messages used throughout
/// the Ecore implementation. Supports internationalisation and consistent
/// error reporting.
///
/// ## Usage
///
/// ```swift
/// throw XMIError.missingRequiredAttribute(ErrorMessage.missingNameAttribute.rawValue)
/// ```
public enum ErrorMessage: String, CaseIterable, Sendable {
    /// Missing required name attribute.
    case missingNameAttribute = "Missing required 'name' attribute"

    /// Missing required type reference.
    case missingTypeReference = "Missing required 'eType' reference"

    /// Invalid boolean value format.
    case invalidBooleanValue = "Invalid boolean value format"

    /// Invalid integer value format.
    case invalidIntegerValue = "Invalid integer value format"

    /// Invalid multiplicity bounds.
    case invalidMultiplicityBounds = "Invalid multiplicity bounds specification"

    /// Unresolved type reference.
    case unresolvedTypeReference = "Unresolved type reference"

    /// Circular inheritance detected.
    case circularInheritance = "Circular inheritance relationship detected"

    /// Invalid XMI document structure.
    case invalidXMIStructure = "Invalid XMI document structure"

    /// Resource loading failure.
    case resourceLoadingFailed = "Resource loading failed"

    /// Unsupported operation.
    case unsupportedOperation = "Unsupported operation"

    /// Localised error message with additional context.
    ///
    /// Provides the base error message with support for additional
    /// contextual information and parameters.
    ///
    /// - Parameter context: Additional context to append to the message
    /// - Returns: Complete error message with context
    public func withContext(_ context: String) -> String {
        return "\(self.rawValue): \(context)"
    }
}

// MARK: - Logging Constants

/// Logging categories for structured logging in Ecore operations.
///
/// Provides type-safe logging categories for consistent log organisation
/// and filtering across the Ecore implementation.
///
/// ## Usage
///
/// ```swift
/// logger.debug("Parsing element", category: LoggingCategory.xmiParsing.rawValue)
/// ```
public enum LoggingCategory: String, CaseIterable, Sendable {
    /// XMI parsing operations.
    case xmiParsing = "ECore.XMI.Parsing"

    /// XMI serialisation operations.
    case xmiSerialisation = "ECore.XMI.Serialisation"

    /// Resource management operations.
    case resourceManagement = "ECore.Resource.Management"

    /// Type resolution operations.
    case typeResolution = "ECore.Type.Resolution"

    /// Model validation operations.
    case validation = "ECore.Validation"

    /// Factory operations.
    case factory = "ECore.Factory"

    /// Command execution operations.
    case commandExecution = "ECore.Command.Execution"

    /// Delegate operations.
    case delegates = "ECore.Delegates"

    /// Query operations.
    case query = "ECore.Query"

    /// Performance monitoring.
    case performance = "ECore.Performance"
}
