//
// EPackage.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - EPackage

/// A package in the Ecore metamodel.
///
/// `EPackage` is a container for classifiers (classes, data types, enums) and provides
/// a namespace for metamodel elements. Packages are the top-level organisational unit
/// in Ecore, similar to packages in Java or modules in Swift.
///
/// Each package has:
/// - **Namespace URI** (``nsURI``): Unique identifier for the package across systems
/// - **Namespace Prefix** (``nsPrefix``): Short prefix used in XML serialisation
/// - **Classifiers**: The types (classes, data types, enums) defined in this package
/// - **Subpackages**: Nested packages for hierarchical organisation
///
/// ## Example
///
/// ```swift
/// let companyPackage = EPackage(
///     name: "company",
///     nsURI: "http://example.org/company",
///     nsPrefix: "company",
///     classifiers: [
///         EClass(name: "Employee"),
///         EClass(name: "Department")
///     ]
/// )
///
/// // Look up a classifier
/// if let employee = companyPackage.getClassifier("Employee") as? EClass {
///     print("Found class: \(employee.name)")
/// }
/// ```
///
/// ## Namespace URIs
///
/// The namespace URI uniquely identifies the package across different systems and
/// versions. By convention, it uses a reverse domain name format:
/// - `http://www.eclipse.org/emf/2002/Ecore` - The Ecore metamodel itself
/// - `http://example.org/mymodel` - Custom metamodel
///
/// ## XML Namespace Prefixes
///
/// The namespace prefix is used in XMI serialisation to abbreviate element names:
/// ```xml
/// <company:Employee xmlns:company="http://example.org/company" name="Alice"/>
/// ```
public struct EPackage: ENamedElement {
    /// The type of classifier for this package.
    ///
    /// All instances of `EPackage` use ``EPackageClassifier`` as their metaclass.
    public typealias Classifier = EPackageClassifier

    /// Unique identifier for this package.
    ///
    /// Used for identity-based equality and hashing.
    public let id: EUUID

    /// The metaclass describing this package.
    public let eClass: Classifier

    /// The name of this package.
    ///
    /// Should be unique within the containing package (if any). By convention,
    /// package names use lowercase with underscores.
    public var name: String

    /// Annotations attached to this package.
    ///
    /// Commonly used for code generation hints, documentation, or tooling metadata.
    public var eAnnotations: [EAnnotation]

    /// The namespace URI for this package.
    ///
    /// Must be globally unique. Used for identification across systems and versions.
    /// By convention, uses reverse domain name format (e.g., "http://example.org/mymodel").
    public var nsURI: String

    /// The namespace prefix for this package.
    ///
    /// Used in XML serialisation to abbreviate element names. Should be short and
    /// memorable (e.g., "ecore", "company").
    public var nsPrefix: String

    /// The classifiers (types) defined in this package.
    ///
    /// Includes classes (``EClass``), data types (``EDataType``), and enumerations (``EEnum``).
    /// Classifiers in a package should have unique names.
    public var eClassifiers: [any EClassifier]

    /// Nested subpackages within this package.
    ///
    /// Allows hierarchical organisation of metamodel elements. For example, a
    /// "company" package might have "hr" and "finance" subpackages.
    public var eSubpackages: [EPackage]

    /// The factory instance for creating objects of this package's classes.
    ///
    /// Returns a factory that can create instances of any classifier defined in this package.
    /// The factory is created lazily when first accessed.
    public var eFactoryInstance: EFactory {
        return EFactory(ePackage: self)
    }

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a new package.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - name: The name of the package.
    ///   - nsURI: The namespace URI (defaults to empty string).
    ///   - nsPrefix: The namespace prefix (defaults to empty string).
    ///   - eClassifiers: The classifiers in this package (empty by default).
    ///   - eSubpackages: Nested subpackages (empty by default).
    ///   - eAnnotations: Annotations (empty by default).
    public init(
        id: EUUID = EUUID(),
        name: String,
        nsURI: String = "",
        nsPrefix: String = "",
        eClassifiers: [any EClassifier] = [],
        eSubpackages: [EPackage] = [],
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.eClass = EPackageClassifier()
        self.name = name
        self.nsURI = nsURI
        self.nsPrefix = nsPrefix
        self.eClassifiers = eClassifiers
        self.eSubpackages = eSubpackages
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
    }

    /// Loads an EPackage from a .ecore file.
    ///
    /// Parses the .ecore file and constructs a fully-formed EPackage with all classifiers
    /// and subpackages.
    ///
    /// - Parameter url: URL to the .ecore file.
    /// - Throws: XMIError if the file cannot be read or parsed.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let url = URL(fileURLWithPath: "/path/to/Model.ecore")
    /// let package = try await EPackage(url: url)
    /// print("Loaded package: \(package.name)")
    /// ```
    public init(url: URL) async throws {
        let parser = XMIParser()
        let resource = try await parser.parse(url)

        let rootObjects = await resource.getRootObjects()
        guard let dynamicPackage = rootObjects.first else {
            throw XMIError.noRootObject
        }

        self = try await resource.createEPackage(from: dynamicPackage)
    }

    /// Initialise an EPackage from a DynamicEObject (without resource context).
    ///
    /// This initialiser handles cases where cross-references are already resolved
    /// or when the object contains direct references instead of UUIDs. When classifiers
    /// cannot be resolved, behaviour depends on the `shouldIgnoreUnresolvedClassifiers` parameter.
    ///
    /// - Parameters:
    ///   - object: The DynamicEObject representing an EPackage.
    ///   - shouldIgnoreUnresolvedClassifiers: If `true`, continues processing when classifier resolution fails; if `false`, throws on resolution failure (default: `false`).
    /// - Returns: A new EPackage instance.
    /// - Throws: XMIError if the object is invalid, missing required attributes, or classifier resolution fails when not ignored.
    ///
    /// ## Example
    /// ```swift
    /// let dynamicPackage: DynamicEObject = // ... from XMI parsing
    /// let package = try EPackage(object: dynamicPackage)
    /// ```
    public init(object: any EObject, shouldIgnoreUnresolvedClassifiers: Bool = false) throws {
        guard let dynamicObj = object as? DynamicEObject else {
            throw XMIError.invalidObjectType("Expected DynamicEObject, got \(type(of: object))")
        }
        guard let name: String = dynamicObj.eGet("name") as? String else {
            throw XMIError.missingRequiredAttribute("name")
        }

        let nsURI: String = dynamicObj.eGet("nsURI") as? String ?? "http://\(name.lowercased())"
        let nsPrefix: String = dynamicObj.eGet("nsPrefix") as? String ?? name.lowercased()

        // Extract classifiers using type resolver
        var eClassifiers: [any EClassifier] = []
        if let classifiersList: [any EObject] = dynamicObj.eGet(.eClassifiers) {
            for classifierObj in classifiersList {
                do {
                    let classifier = try EClassifierResolver.resolvingType(classifierObj)
                    eClassifiers.append(classifier)
                } catch {
                    if shouldIgnoreUnresolvedClassifiers {
                        // Continue processing other classifiers
                        continue
                    } else {
                        throw error
                    }
                }
            }
        }

        // Extract subpackages recursively
        var eSubpackages: [EPackage] = []
        if let subpackagesList: [any EObject] = dynamicObj.eGet(.eSubpackages) {
            for subpackageObj in subpackagesList {
                if let subpackage = try? EPackage(
                    object: subpackageObj,
                    shouldIgnoreUnresolvedClassifiers: shouldIgnoreUnresolvedClassifiers
                ) {
                    eSubpackages.append(subpackage)
                }
            }
        }

        // Call existing designated initializer
        self.init(
            name: name,
            nsURI: nsURI,
            nsPrefix: nsPrefix,
            eClassifiers: eClassifiers,
            eSubpackages: eSubpackages
        )
    }

    // MARK: - Classifier Lookup

    /// Retrieves a classifier by its name.
    ///
    /// Searches only the classifiers directly contained in this package, not in subpackages.
    ///
    /// - Parameter name: The name of the classifier to find.
    /// - Returns: The matching classifier, or `nil` if not found.
    ///
    /// ## Example
    ///
    /// ```swift
    /// if let employeeClass = package.getClassifier("Employee") as? EClass {
    ///     print("Found class with \(employeeClass.allAttributes.count) attributes")
    /// }
    /// ```
    public func getClassifier(_ name: String) -> (any EClassifier)? {
        return eClassifiers.first { $0.name == name }
    }

    /// Retrieves a class by its name.
    ///
    /// Convenience method that searches only for ``EClass`` classifiers.
    ///
    /// - Parameter name: The name of the class to find.
    /// - Returns: The matching class, or `nil` if not found.
    public func getEClass(_ name: String) -> EClass? {
        return getClassifier(name) as? EClass
    }

    /// Retrieves a data type by its name.
    ///
    /// Convenience method that searches only for ``EDataType`` classifiers.
    ///
    /// - Parameter name: The name of the data type to find.
    /// - Returns: The matching data type, or `nil` if not found.
    public func getEDataType(_ name: String) -> EDataType? {
        return getClassifier(name) as? EDataType
    }

    /// Retrieves an enumeration by its name.
    ///
    /// Convenience method that searches only for ``EEnum`` classifiers.
    ///
    /// - Parameter name: The name of the enum to find.
    /// - Returns: The matching enum, or `nil` if not found.
    public func getEEnum(_ name: String) -> EEnum? {
        return getClassifier(name) as? EEnum
    }

    /// Retrieves a subpackage by its name.
    ///
    /// Searches only the direct subpackages, not nested subpackages.
    ///
    /// - Parameter name: The name of the subpackage to find.
    /// - Returns: The matching subpackage, or `nil` if not found.
    public func getSubpackage(_ name: String) -> EPackage? {
        return eSubpackages.first { $0.name == name }
    }

    // MARK: - EObject Protocol Implementation

    /// Reflectively retrieves the value of a feature.
    ///
    /// This method provides dynamic access to the package's properties without
    /// requiring compile-time knowledge of the feature.
    ///
    /// - Parameter feature: The structural feature whose value to retrieve.
    /// - Returns: The feature's current value, or `nil` if not set.
    public func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        return storage.get(feature: feature.id)
    }

    /// Reflectively sets the value of a feature.
    ///
    /// This method provides dynamic modification of the package's properties.
    /// Setting a value to `nil` has the same effect as calling ``eUnset(_:)``.
    ///
    /// - Parameters:
    ///   - feature: The structural feature to modify.
    ///   - value: The new value, or `nil` to unset.
    public mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?) {
        storage.set(feature: feature.id, value: value)
    }

    /// Checks whether a feature has been explicitly set.
    ///
    /// A feature is considered "set" if it has been assigned a value, even if that
    /// value equals the feature's default.
    ///
    /// - Parameter feature: The structural feature to check.
    /// - Returns: `true` if the feature has been set, `false` otherwise.
    public func eIsSet(_ feature: some EStructuralFeature) -> Bool {
        return storage.isSet(feature: feature.id)
    }

    /// Unsets a feature, returning it to its default value.
    ///
    /// After unsetting, ``eIsSet(_:)`` will return `false` for this feature,
    /// and ``eGet(_:)`` will return `nil`.
    ///
    /// - Parameter feature: The structural feature to unset.
    public mutating func eUnset(_ feature: some EStructuralFeature) {
        storage.unset(feature: feature.id)
    }

    // MARK: - Equatable & Hashable

    /// Compares two packages for equality.
    ///
    /// Packages are equal if they have the same identifier.
    ///
    /// - Parameters:
    ///   - lhs: The first package to compare.
    ///   - rhs: The second package to compare.
    /// - Returns: `true` if the packages are equal, `false` otherwise.
    public static func == (lhs: EPackage, rhs: EPackage) -> Bool {
        return lhs.id == rhs.id
    }

    /// Hashes the essential components of this package.
    ///
    /// Only the identifier is used for hashing to maintain consistency with equality.
    ///
    /// - Parameter hasher: The hasher to use for combining components.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Classifier Type

/// Metaclass for `EPackage`.
///
/// Describes the structure of `EPackage` itself within the metamodel hierarchy.
/// This is the classifier that describes all `EPackage` instances.
public struct EPackageClassifier: EClassifier {
    /// Unique identifier for this metaclass.
    ///
    /// Each instance creates its own unique identifier.
    public let id: EUUID = EUUID()

    /// The name of this classifier.
    ///
    /// Always returns `"EPackage"` to identify this as the metaclass for packages.
    public var name: String { EcoreClassifier.ePackage.rawValue }
}
