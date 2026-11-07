//
// OCLTypeResolver.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import OCL

/// A type reference resolved to an Ecore classifier.
public struct OCLResolvedType: Sendable {
    /// The classifier of the type, or of the elements of a collection type.
    public var classifier: any EClassifier

    /// The name of the collection type that wraps the classifier, such as `Set`, if any.
    public var collectionKind: String?

    /// Creates a resolved type.
    ///
    /// - Parameters:
    ///   - classifier: The classifier of the type or of its elements.
    ///   - collectionKind: The name of the wrapping collection type.
    public init(classifier: any EClassifier, collectionKind: String? = nil) {
        self.classifier = classifier
        self.collectionKind = collectionKind
    }

    /// Whether the collection keeps its elements in order, if the type is a collection.
    public var isOrdered: Bool? {
        collectionKind.map { $0 == "OrderedSet" || $0 == "Sequence" }
    }

    /// Whether the collection holds each element once, if the type is a collection.
    public var isUnique: Bool? {
        collectionKind.map { $0 == "OrderedSet" || $0 == "Set" }
    }
}

/// Resolves OCL type references to Ecore classifiers.
///
/// A simple name is looked up among the classifiers of the packages, then among the primitive
/// types of OCL, then among the built-in classifiers of Ecore. A qualified name starts with an
/// import alias or the name of a root package and continues through subpackages to a
/// classifier. The primitive types map to Ecore as Eclipse OCL maps them: `String` to
/// `EString`, `Integer` and `UnlimitedNatural` to `EBigInteger`, `Real` to `EBigDecimal`, and
/// `Boolean` to `EBoolean` when a value is required or `EBooleanObject` otherwise.
public struct OCLTypeResolver: Sendable {
    /// The URIs under which an import refers to the Ecore metamodel.
    public static let ecoreURIs: Set<String> = [EcorePackage.nsURI, EcorePackage.nsURI + "#/", EcorePackage.nsURI + "#"]

    /// The Ecore data types that the primitive types of OCL denote.
    public static let primitiveTypes: [String: EcoreDataType] = [
        "String": .eString, "Integer": .eBigInteger, "Real": .eBigDecimal, "UnlimitedNatural": .eBigInteger,
        "Boolean": .eBoolean,
    ]

    /// The packages whose classifiers simple and qualified names refer to.
    public var packages: [EPackage]

    /// The packages that import aliases refer to.
    public var aliases: [String: EPackage]

    /// Creates a resolver.
    ///
    /// - Parameters:
    ///   - packages: The packages whose classifiers names refer to.
    ///   - aliases: The packages that import aliases refer to.
    public init(packages: [EPackage], aliases: [String: EPackage] = [:]) {
        self.packages = packages
        self.aliases = aliases
    }

    /// Whether a URI refers to the Ecore metamodel.
    ///
    /// - Parameter uri: The URI of an import.
    /// - Returns: `true` for the namespace URI of Ecore, with or without a fragment.
    public static func isEcoreURI(_ uri: String) -> Bool { ecoreURIs.contains(uri) }

    /// The URI of an import without its fragment.
    ///
    /// - Parameter uri: The URI as written.
    /// - Returns: The URI up to `#`.
    public static func namespaceURI(of uri: String) -> String {
        uri.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? uri
    }

    /// Resolves a type reference.
    ///
    /// - Parameters:
    ///   - type: The type reference.
    ///   - isRequired: Whether a value is required, which selects `EBoolean` over `EBooleanObject`.
    /// - Returns: The classifier, or `nil` if the name cannot be found.
    public func resolve(_ type: OCLTypeReference, isRequired: Bool = true) -> OCLResolvedType? {
        if OCLSyntax.collectionTypeNames.contains(type.name), type.path.count == 1 {
            guard let element = type.arguments.first, let resolved = resolve(element, isRequired: isRequired) else { return nil }
            return OCLResolvedType(classifier: resolved.classifier, collectionKind: type.name)
        }
        return classifier(at: type.path, isRequired: isRequired).map { OCLResolvedType(classifier: $0) }
    }

    /// Resolves a qualified name to a classifier.
    ///
    /// - Parameters:
    ///   - path: The segments of the name.
    ///   - isRequired: Whether a value is required, which selects `EBoolean` over `EBooleanObject`.
    /// - Returns: The classifier, or `nil` if the name cannot be found.
    public func classifier(at path: [String], isRequired: Bool = true) -> (any EClassifier)? {
        guard let first = path.first else { return nil }
        if path.count == 1 {
            for package in packages {
                if let found = package.getClassifier(first, includingSubpackages: true) { return found }
            }
            if let primitive = Self.primitiveTypes[first] {
                let dataType: EcoreDataType = primitive == .eBoolean && !isRequired ? .eBooleanObject : primitive
                return EcorePackage.dataType(dataType)
            }
            return EcorePackage.classifier(named: first)
        }
        if let package = aliases[first] {
            return classifier(in: package, at: path.dropFirst())
        }
        for package in packages where package.name == first {
            if let found = classifier(in: package, at: path.dropFirst()) { return found }
        }
        if first == EcorePackage.name { return classifier(in: EcorePackage.instance, at: path.dropFirst()) }
        return nil
    }

    /// The package a qualified name refers to, if any.
    ///
    /// - Parameter path: The segments of the name.
    /// - Returns: The package.
    public func package(at path: [String]) -> EPackage? {
        guard let first = path.first else { return nil }
        var candidates = packages.filter { $0.name == first }
        if let aliased = aliases[first] { candidates.insert(aliased, at: 0) }
        for candidate in candidates {
            var current: EPackage? = candidate
            for segment in path.dropFirst() { current = current?.getSubpackage(segment) }
            if let current { return current }
        }
        return nil
    }

    /// Finds a classifier by its path within a package.
    private func classifier(in package: EPackage, at path: ArraySlice<String>) -> (any EClassifier)? {
        guard let first = path.first else { return nil }
        if path.count == 1 {
            if package.nsURI == EcorePackage.nsURI { return EcorePackage.classifier(named: first) }
            return package.getClassifier(first)
        }
        guard let subpackage = package.getSubpackage(first) else { return nil }
        return classifier(in: subpackage, at: path.dropFirst())
    }
}
