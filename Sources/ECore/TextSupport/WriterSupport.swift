//
// WriterSupport.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// Accumulates the lines of a text with indentation.
struct IndentedText {
    /// The text that indents one level.
    let indentUnit: String

    /// The current indentation depth.
    private(set) var depth = 0

    /// The lines written so far.
    private(set) var lines: [String] = []

    /// Creates an empty text.
    ///
    /// - Parameter indentUnit: The text that indents one level, by default a tab.
    init(indentUnit: String = "\t") {
        self.indentUnit = indentUnit
    }

    /// Appends a line at the current indentation, or an empty line.
    ///
    /// Every line of a multi-line text is indented.
    ///
    /// - Parameter text: The line to append.
    mutating func line(_ text: String = "") {
        guard !text.isEmpty else {
            lines.append("")
            return
        }
        let prefix = String(repeating: indentUnit, count: depth)
        for part in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append(part.isEmpty ? "" : prefix + part)
        }
    }

    /// Appends a text verbatim, indenting only its first line.
    ///
    /// - Parameter text: The text to append.
    mutating func verbatim(_ text: String) {
        let prefix = String(repeating: indentUnit, count: depth)
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, part) in parts.enumerated() {
            lines.append(index == 0 ? prefix + part : String(part))
        }
    }

    /// Appends an empty line unless the text is empty or already ends with one.
    mutating func separate() {
        if let last = lines.last, !last.isEmpty { lines.append("") }
    }

    /// Removes trailing empty lines.
    mutating func trimTrailingEmptyLines() {
        while lines.last?.isEmpty == true { lines.removeLast() }
    }

    /// Increases the indentation by one level.
    mutating func indent() { depth += 1 }

    /// Decreases the indentation by one level.
    mutating func outdent() { depth = max(0, depth - 1) }

    /// The text, with a final line break.
    var text: String {
        lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }
}

/// Names the classifiers of written packages the way a reader resolves them back.
///
/// A reader looks a name up in the enclosing packages from the innermost outwards, so a
/// classifier in another package needs a qualified name and a classifier hidden by a
/// closer one needs a longer qualified name. This type finds the shortest name that
/// resolves to the intended classifier.
struct ClassifierNaming {
    /// The qualified names of the classifiers, by identifier.
    private var keys: [EUUID: String] = [:]
    /// The qualified names of all indexed classifiers.
    private var names: Set<String> = []

    /// Indexes the classifiers of packages.
    ///
    /// - Parameters:
    ///   - packages: The packages to be written.
    ///   - rootKey: The qualified name of a root package, by default its name.
    init(packages: [EPackage], rootKey: (EPackage) -> String = { $0.name }) {
        for package in packages { index(package, key: rootKey(package)) }
    }

    /// Records the classifiers of a package and its subpackages.
    ///
    /// - Parameters:
    ///   - package: The package to index.
    ///   - key: The qualified key of the package.
    private mutating func index(_ package: EPackage, key: String) {
        for classifier in package.eClassifiers {
            let qualified = Self.qualified(key, classifier.name)
            if keys[classifier.id] == nil { keys[classifier.id] = qualified }
            names.insert(qualified)
        }
        for subpackage in package.eSubpackages { index(subpackage, key: Self.qualified(key, subpackage.name)) }
    }

    /// Joins a scope and a name.
    ///
    /// - Parameters:
    ///   - scope: The enclosing scope, which may be empty.
    ///   - name: The name to qualify.
    /// - Returns: The qualified name.
    private static func qualified(_ scope: String, _ name: String) -> String {
        scope.isEmpty ? name : scope + "." + name
    }

    /// The scopes visible from a package, innermost first.
    ///
    /// - Parameter key: The qualified name of the package.
    /// - Returns: The package, its enclosing packages and the empty root scope.
    static func scopes(of key: String) -> [String] {
        var result: [String] = []
        var current = key
        while true {
            result.append(current)
            guard let dot = current.lastIndex(of: ".") else { break }
            current = String(current[..<dot])
        }
        result.append("")
        return result
    }

    /// Whether a classifier is declared by one of the written packages.
    ///
    /// - Parameter classifier: The classifier.
    /// - Returns: `true` if the classifier belongs to the written packages.
    func isLocal(_ classifier: any EClassifier) -> Bool { keys[classifier.id] != nil }

    /// The document classifier that a name resolves to from a scope, if any.
    ///
    /// - Parameters:
    ///   - name: The name as written.
    ///   - scopes: The visible scopes, innermost first.
    /// - Returns: The qualified name of the classifier found.
    func resolve(_ name: String, scopes: [String]) -> String? {
        for scope in scopes {
            let candidate = Self.qualified(scope, name)
            if names.contains(candidate) { return candidate }
        }
        return nil
    }

    /// The shortest name of a document classifier that resolves to it from a package.
    ///
    /// - Parameters:
    ///   - classifier: The classifier to name.
    ///   - packageKey: The qualified name of the package that refers to it.
    ///   - shadowing: Names, such as type parameters, that hide classifiers.
    /// - Returns: The name, or `nil` if the classifier is not declared by the written packages.
    func name(of classifier: any EClassifier, from packageKey: String, shadowing: Set<String> = []) -> String? {
        guard let key = keys[classifier.id] else { return nil }
        let scopes = Self.scopes(of: packageKey)
        for scope in scopes {
            guard scope.isEmpty || key.hasPrefix(scope + ".") else { continue }
            let candidate = scope.isEmpty ? key : String(key.dropFirst(scope.count + 1))
            if shadowing.contains(candidate) { continue }
            if resolve(candidate, scopes: scopes) == key { return candidate }
        }
        return key
    }

    /// The first spelling of an external classifier that no document classifier hides.
    ///
    /// - Parameters:
    ///   - candidates: The spellings that the notation accepts, preferred first.
    ///   - packageKey: The qualified name of the package that refers to the classifier.
    ///   - shadowing: Names, such as type parameters, that hide classifiers.
    /// - Returns: The first unhidden spelling, or the last candidate if all are hidden.
    func externalName(_ candidates: [String], from packageKey: String, shadowing: Set<String> = []) -> String? {
        let scopes = Self.scopes(of: packageKey)
        for candidate in candidates where !shadowing.contains(candidate) && resolve(candidate, scopes: scopes) == nil {
            return candidate
        }
        return candidates.last
    }
}

/// Identifies the built-in classifiers of Ecore.
enum EcoreBuiltins {
    /// Whether a classifier is one of the built-in classifiers of Ecore.
    ///
    /// - Parameter classifier: The classifier.
    /// - Returns: `true` if the classifier has the identity of the Ecore classifier of its name.
    static func isBuiltin(_ classifier: any EClassifier) -> Bool {
        EcorePackage.classifier(named: classifier.name)?.id == classifier.id
    }
}

/// The properties that attributes and references share, read from either.
struct FeatureFacts {
    /// The attribute, if the feature is one.
    let attribute: EAttribute?

    /// The reference, if the feature is one.
    let reference: EReference?

    /// Reads the shared properties of a feature.
    ///
    /// - Parameter feature: The feature.
    /// - Returns: The facts, or `nil` if the feature is neither an attribute nor a reference.
    init?(_ feature: any EStructuralFeature) {
        attribute = feature as? EAttribute
        reference = feature as? EReference
        if attribute == nil && reference == nil { return nil }
    }

    /// Selects the value for the kind of feature.
    ///
    /// - Parameters:
    ///   - attributeValue: The value to use for an attribute.
    ///   - referenceValue: The value to use for a reference.
    /// - Returns: The selected value.
    private func value<T>(_ attributeValue: (EAttribute) -> T, _ referenceValue: (EReference) -> T) -> T {
        if let attribute { return attributeValue(attribute) }
        return referenceValue(reference!)
    }

    /// The name of the feature.
    var name: String { value(\.name, \.name) }
    /// The type of the feature.
    var eType: any EClassifier { value({ $0.eType }, { $0.eType }) }
    /// The generic type of the feature, if it is parameterised.
    var eGenericType: EGenericType? { value(\.eGenericType, \.eGenericType) }
    /// The lower bound of the multiplicity.
    var lowerBound: Int { value(\.lowerBound, \.lowerBound) }
    /// The upper bound of the multiplicity.
    var upperBound: Int { value(\.upperBound, \.upperBound) }
    /// Whether the value can be changed.
    var changeable: Bool { value(\.changeable, \.changeable) }
    /// Whether the value is volatile.
    var volatile: Bool { value(\.volatile, \.volatile) }
    /// Whether the value is transient.
    var transient: Bool { value(\.transient, \.transient) }
    /// Whether the feature is unsettable.
    var unsettable: Bool { value(\.unsettable, \.unsettable) }
    /// Whether the feature is derived.
    var derived: Bool { value(\.derived, \.derived) }
    /// Whether the values are unique.
    var unique: Bool { value(\.unique, \.unique) }
    /// Whether the values are ordered.
    var ordered: Bool { value(\.ordered, \.ordered) }
    /// The default value literal, if any.
    var defaultValueLiteral: String? { value(\.defaultValueLiteral, \.defaultValueLiteral) }
    /// The annotations of the feature.
    var eAnnotations: [EAnnotation] { value(\.eAnnotations, \.eAnnotations) }
    /// Whether the feature can hold many values.
    var isMany: Bool { upperBound > 1 || upperBound < 0 }
}

/// Finds the classifiers that written packages use but neither declare nor take from Ecore.
///
/// Such classifiers come from other metamodels, such as those that a document imported,
/// and a writer can only name them; it reports them or declares their imports.
enum ExternalClassifiers {
    /// The names of the external classifiers used by packages, in first-use order.
    ///
    /// - Parameters:
    ///   - packages: The packages to be written.
    ///   - naming: The naming of the classifiers that the packages declare.
    /// - Returns: The names of the classifiers that are neither local nor built into Ecore.
    static func names(in packages: [EPackage], naming: ClassifierNaming) -> [String] {
        var collector = Collector(naming: naming)
        for package in packages { collector.visit(package) }
        return collector.names
    }

    /// Collects the names of the external classifiers that a package refers to.
    private struct Collector {
        /// The naming that tells local from external classifiers.
        let naming: ClassifierNaming
        /// The external names, in order of first use.
        var names: [String] = []
        /// The external names already collected.
        var seen: Set<String> = []

        /// Notes a classifier if it is external.
        ///
        /// - Parameter classifier: The classifier, if any.
        mutating func note(_ classifier: (any EClassifier)?) {
            guard let classifier, !naming.isLocal(classifier), !EcoreBuiltins.isBuiltin(classifier) else { return }
            if seen.insert(classifier.name).inserted { names.append(classifier.name) }
        }

        /// Notes the classifiers that a generic type refers to.
        ///
        /// - Parameter generic: The generic type, if any.
        mutating func note(_ generic: EGenericType?) {
            guard let generic else { return }
            note(generic.eClassifier)
            for argument in generic.eTypeArguments { note(argument) }
            note(generic.eUpperBound)
            note(generic.eLowerBound)
        }

        /// Notes the classifiers in the bounds of type parameters.
        ///
        /// - Parameter parameters: The type parameters.
        mutating func note(_ parameters: [ETypeParameter]) {
            for parameter in parameters { for bound in parameter.eBounds { note(bound) } }
        }

        /// Notes the external classifiers that a package refers to.
        ///
        /// - Parameter package: The package to visit.
        mutating func visit(_ package: EPackage) {
            for classifier in package.eClassifiers {
                if let dataType = classifier as? EDataType { note(dataType.eTypeParameters) }
                guard let eClass = classifier as? EClass else { continue }
                note(eClass.eTypeParameters)
                for superType in eClass.eSuperTypes { note(superType) }
                for superType in eClass.eGenericSuperTypes { note(superType) }
                for feature in eClass.eStructuralFeatures.compactMap(FeatureFacts.init) {
                    note(feature.eType)
                    note(feature.eGenericType)
                }
                for operation in eClass.eOperations {
                    note(operation.eTypeParameters)
                    note(operation.eType)
                    note(operation.eGenericType)
                    for exception in operation.eExceptions { note(exception) }
                    for exception in operation.eGenericExceptions { note(exception) }
                    for parameter in operation.eParameters {
                        note(parameter.eType)
                        note(parameter.eGenericType)
                    }
                }
            }
            for subpackage in package.eSubpackages { visit(subpackage) }
        }
    }
}
