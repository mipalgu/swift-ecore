//
// MetamodelSignature.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// Describes the structure of packages as text that does not depend on identifiers.
///
/// Two metamodels with the same signature declare the same packages, classifiers,
/// features, operations, annotations and properties, in the same order, and refer to the
/// same classifiers and features by name. Signatures make it possible to compare
/// metamodels read from different notations, whose identifiers always differ.
struct MetamodelSignature {
    /// Options that relax the comparison where notations legitimately differ.
    struct Options: Sendable {
        /// Whether uniqueness and order of single-valued elements are ignored.
        ///
        /// Uniqueness and order have no meaning for an element that holds at most one
        /// value, and notations disagree on their defaults for such elements.
        var ignoresSingleValuedCollectionFlags: Bool

        /// The annotation sources that are left out of the signature.
        var ignoredAnnotationSources: Set<String>

        /// Creates options.
        ///
        /// - Parameters:
        ///   - ignoresSingleValuedCollectionFlags: Whether to ignore uniqueness and order of
        ///     single-valued elements.
        ///   - ignoredAnnotationSources: The annotation sources to leave out.
        init(ignoresSingleValuedCollectionFlags: Bool = false, ignoredAnnotationSources: Set<String> = []) {
            self.ignoresSingleValuedCollectionFlags = ignoresSingleValuedCollectionFlags
            self.ignoredAnnotationSources = ignoredAnnotationSources
        }
    }

    /// The qualified names of the classifiers, by identifier.
    private var classifierNames: [EUUID: String] = [:]
    /// The qualified names of the features, by identifier.
    private var featureNames: [EUUID: String] = [:]
    /// The options that relax the comparison.
    private let options: Options
    /// The lines of the signature produced so far.
    private var lines: [String] = []

    /// Computes the signature of packages.
    ///
    /// - Parameters:
    ///   - packages: The packages to describe.
    ///   - options: The options that relax the comparison.
    /// - Returns: The signature text, one element per line.
    static func of(_ packages: [EPackage], options: Options = Options()) -> String {
        var signature = MetamodelSignature(options: options)
        for package in packages { signature.index(package, path: package.name) }
        for package in packages { signature.describe(package, depth: 0) }
        return signature.lines.joined(separator: "\n")
    }

    /// Creates an empty signature builder.
    ///
    /// - Parameter options: The options that relax the comparison.
    private init(options: Options) {
        self.options = options
    }

    /// Records the names of the classifiers and features of a package.
    ///
    /// - Parameters:
    ///   - package: The package to index.
    ///   - path: The qualified name of the package.
    private mutating func index(_ package: EPackage, path: String) {
        for classifier in package.eClassifiers {
            classifierNames[classifier.id] = path + "." + classifier.name
            if let eClass = classifier as? EClass {
                for feature in eClass.eStructuralFeatures {
                    featureNames[feature.id] = eClass.name + "." + feature.name
                }
            }
        }
        for subpackage in package.eSubpackages { index(subpackage, path: path + "." + subpackage.name) }
    }

    /// The name of a classifier in the signature.
    ///
    /// - Parameter classifier: The classifier, or `nil` for no type.
    /// - Returns: The qualified name, or `void` if there is no classifier.
    private func name(of classifier: (any EClassifier)?) -> String {
        guard let classifier else { return "void" }
        if let local = classifierNames[classifier.id] { return local }
        if EcoreBuiltins.isBuiltin(classifier) { return "ecore." + classifier.name }
        return "external." + classifier.name
    }

    /// Describes a type from its generic form if present, otherwise from its raw classifier.
    ///
    /// - Parameters:
    ///   - generic: The generic type, if any.
    ///   - raw: The raw classifier.
    ///   - parameters: The names of the type parameters in scope.
    /// - Returns: The description of the type.
    private func type(_ generic: EGenericType?, raw: (any EClassifier)?, parameters: [EUUID: String]) -> String {
        guard let generic else { return name(of: raw) }
        return type(generic, parameters: parameters)
    }

    /// Describes a generic type.
    ///
    /// - Parameters:
    ///   - generic: The generic type.
    ///   - parameters: The names of the type parameters in scope.
    /// - Returns: The description of the type.
    private func type(_ generic: EGenericType, parameters: [EUUID: String]) -> String {
        if let parameter = generic.eTypeParameter { return "param:" + (parameters[parameter] ?? "?") }
        guard let classifier = generic.eClassifier else {
            if let upper = generic.eUpperBound { return "? extends " + type(upper, parameters: parameters) }
            if let lower = generic.eLowerBound { return "? super " + type(lower, parameters: parameters) }
            return "?"
        }
        let arguments = generic.eTypeArguments.map { type($0, parameters: parameters) }
        return name(of: classifier) + (arguments.isEmpty ? "" : "<" + arguments.joined(separator: ", ") + ">")
    }

    /// Describes type parameters and their bounds.
    ///
    /// - Parameters:
    ///   - parameters: The type parameters.
    ///   - scope: The names of the type parameters in scope.
    /// - Returns: The description, which is empty if there are no parameters.
    private func typeParameters(_ parameters: [ETypeParameter], scope: [EUUID: String]) -> String {
        guard !parameters.isEmpty else { return "" }
        return "<" + parameters.map { parameter in
            parameter.name + (parameter.eBounds.isEmpty
                ? "" : " extends " + parameter.eBounds.map { type($0, parameters: scope) }.joined(separator: " & "))
        }.joined(separator: ", ") + ">"
    }

    /// Appends an indented line to the signature.
    ///
    /// - Parameters:
    ///   - depth: The indentation depth.
    ///   - text: The text of the line.
    private mutating func line(_ depth: Int, _ text: String) {
        lines.append(String(repeating: "  ", count: depth) + text)
    }

    /// Appends the annotations that are not ignored.
    ///
    /// - Parameters:
    ///   - annotations: The annotations to describe.
    ///   - depth: The indentation depth.
    private mutating func describe(_ annotations: [EAnnotation], depth: Int) {
        for annotation in annotations where !options.ignoredAnnotationSources.contains(annotation.source) {
            let details = annotation.details.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            line(depth, "@" + annotation.source + "(" + details + ")")
        }
    }

    /// The description of the collection flags of a feature.
    ///
    /// - Parameters:
    ///   - unique: Whether the values are unique.
    ///   - ordered: Whether the values are ordered.
    ///   - upper: The upper bound of the multiplicity.
    /// - Returns: The flags text, which is empty if the flags are ignored for the feature.
    private func collectionFlags(unique: Bool, ordered: Bool, upper: Int) -> String {
        let isMany = upper > 1 || upper < 0
        if options.ignoresSingleValuedCollectionFlags && !isMany { return "" }
        return " unique=\(unique) ordered=\(ordered)"
    }

    /// Appends the description of a package and its contents.
    ///
    /// - Parameters:
    ///   - package: The package to describe.
    ///   - depth: The indentation depth.
    private mutating func describe(_ package: EPackage, depth: Int) {
        line(depth, "package \(package.name) uri=\(package.nsURI) prefix=\(package.nsPrefix)")
        describe(package.eAnnotations, depth: depth + 1)
        for classifier in package.eClassifiers { describe(classifier, depth: depth + 1) }
        for subpackage in package.eSubpackages { describe(subpackage, depth: depth + 1) }
    }

    /// Appends the description of a classifier and its members.
    ///
    /// - Parameters:
    ///   - classifier: The classifier to describe.
    ///   - depth: The indentation depth.
    private mutating func describe(_ classifier: any EClassifier, depth: Int) {
        switch classifier {
        case let eClass as EClass:
            var scope: [EUUID: String] = [:]
            for parameter in eClass.eTypeParameters { scope[parameter.id] = parameter.name }
            let supers = eClass.eGenericSuperTypes.isEmpty
                ? eClass.eSuperTypes.map { name(of: $0) }
                : eClass.eGenericSuperTypes.map { type($0, parameters: scope) }
            line(depth, "class \(eClass.name)\(typeParameters(eClass.eTypeParameters, scope: scope))"
                + " abstract=\(eClass.isAbstract) interface=\(eClass.isInterface)"
                + " supers=[\(supers.joined(separator: ", "))]"
                + " instance=\(eClass.instanceClassName ?? "-")/\(eClass.instanceTypeName ?? "-")")
            describe(eClass.eAnnotations, depth: depth + 1)
            for parameter in eClass.eTypeParameters { describe(parameter.eAnnotations, depth: depth + 1) }
            for feature in eClass.eStructuralFeatures { describe(feature, scope: scope, depth: depth + 1) }
            for operation in eClass.eOperations { describe(operation, scope: scope, depth: depth + 1) }
        case let eEnum as EEnum:
            line(depth, "enum \(eEnum.name) serialisable=\(eEnum.serialisable)"
                + " instance=\(eEnum.instanceClassName ?? "-")/\(eEnum.instanceTypeName ?? "-")")
            describe(eEnum.eAnnotations, depth: depth + 1)
            for literal in eEnum.literals {
                line(depth + 1, "literal \(literal.name)=\(literal.value) \"\(literal.literal ?? literal.name)\"")
                describe(literal.eAnnotations, depth: depth + 2)
            }
        case let dataType as EDataType:
            line(depth, "datatype \(dataType.name)\(typeParameters(dataType.eTypeParameters, scope: [:]))"
                + " serialisable=\(dataType.serialisable)"
                + " instance=\(dataType.instanceClassName ?? "-")/\(dataType.instanceTypeName ?? "-")")
            describe(dataType.eAnnotations, depth: depth + 1)
        default:
            line(depth, "classifier \(classifier.name)")
        }
    }

    /// Appends the description of an attribute or reference.
    ///
    /// - Parameters:
    ///   - structuralFeature: The feature to describe.
    ///   - scope: The names of the type parameters in scope.
    ///   - depth: The indentation depth.
    private mutating func describe(_ structuralFeature: any EStructuralFeature, scope: [EUUID: String], depth: Int) {
        guard let feature = FeatureFacts(structuralFeature) else {
            line(depth, "feature \(structuralFeature.name)")
            return
        }
        var text = (feature.attribute != nil ? "attribute " : "reference ") + feature.name
        text += " : " + type(feature.eGenericType, raw: feature.eType, parameters: scope)
        text += " [\(feature.lowerBound)..\(feature.upperBound)]"
        text += " changeable=\(feature.changeable) volatile=\(feature.volatile) transient=\(feature.transient)"
        text += " unsettable=\(feature.unsettable) derived=\(feature.derived)"
        text += collectionFlags(unique: feature.unique, ordered: feature.ordered, upper: feature.upperBound)
        text += " default=\(feature.defaultValueLiteral ?? "-")"
        if let attribute = feature.attribute { text += " id=\(attribute.isID)" }
        if let reference = feature.reference {
            text += " containment=\(reference.containment) container=\(reference.container)"
            text += " resolve=\(reference.resolveProxies)"
            text += " opposite=\(reference.opposite.map { featureNames[$0] ?? "?" } ?? "-")"
            text += " keys=[\(reference.eKeys.map { featureNames[$0] ?? "?" }.joined(separator: ", "))]"
        }
        line(depth, text)
        describe(feature.eAnnotations, depth: depth + 1)
    }

    /// Appends the description of an operation.
    ///
    /// - Parameters:
    ///   - operation: The operation to describe.
    ///   - outer: The names of the type parameters already in scope.
    ///   - depth: The indentation depth.
    private mutating func describe(_ operation: EOperation, scope outer: [EUUID: String], depth: Int) {
        var scope = outer
        for parameter in operation.eTypeParameters { scope[parameter.id] = parameter.name }
        let parameters = operation.eParameters.map { parameter in
            parameter.name + " : " + type(parameter.eGenericType, raw: parameter.eType, parameters: scope)
                + " [\(parameter.lowerBound)..\(parameter.upperBound)]"
                + collectionFlags(unique: parameter.unique, ordered: parameter.ordered, upper: parameter.upperBound)
        }
        let exceptions = operation.eGenericExceptions.isEmpty
            ? operation.eExceptions.map { name(of: $0) }
            : operation.eGenericExceptions.map { type($0, parameters: scope) }
        line(depth, "operation \(typeParameters(operation.eTypeParameters, scope: scope))\(operation.name)"
            + "(\(parameters.joined(separator: "; "))) : "
            + type(operation.eGenericType, raw: operation.eType, parameters: scope)
            + " [\(operation.lowerBound)..\(operation.upperBound)]"
            + collectionFlags(unique: operation.unique, ordered: operation.ordered, upper: operation.upperBound)
            + " throws=[\(exceptions.joined(separator: ", "))]")
        describe(operation.eAnnotations, depth: depth + 1)
        for parameter in operation.eParameters { describe(parameter.eAnnotations, depth: depth + 2) }
    }
}
