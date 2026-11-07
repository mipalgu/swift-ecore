//
// KM3Writer.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// Writes native Ecore packages as KM3 (Kernel MetaMetaModel) text.
///
/// Writing is the inverse of ``KM3Reader``: each root package becomes a `package`
/// declaration with `-- @nsURI` and `-- @nsPrefix` directives for its non-empty namespace
/// URI and prefix, subpackages become nested packages, and classes, attributes, references,
/// operations, data types and enumerations become the corresponding declarations. A
/// built-in Ecore data type that the packages use is declared in a `PrimitiveTypes`
/// package under its KM3 name (see ``KM3PrimitiveTypes``), which is added to an existing
/// root package of that name or appended as a new one.
///
/// KM3 cannot express everything that Ecore can. Each property that writing has to drop
/// is reported as a warning: annotations (including operation bodies), default values, the
/// derived, transient, volatile, unsettable and identifier flags, unchangeable features,
/// references that are not unique or do not resolve proxies, reference keys, interfaces,
/// instance class and type names, generic types and type parameters, serialisability,
/// operation and parameter bounds and flags, exceptions, enumeration literal values and texts
/// that differ from the defaults, and types outside the written packages.
///
/// The output is deterministic: declarations follow the order of the packages, and the
/// primitive types are sorted by name. Lines are indented with tabs and end with `\n`.
public enum KM3Writer {
    /// Writes packages as KM3 text.
    ///
    /// - Parameter packages: The root packages to write.
    /// - Returns: The KM3 text, and a warning for every property that KM3 cannot express.
    public static func write(_ packages: [EPackage]) -> (text: String, diagnostics: [SourceDiagnostic]) {
        var context = KM3WritingContext(packages: packages)
        return (context.write(), context.diagnostics)
    }

    /// The text of a multiplicity, or the empty text for exactly one.
    ///
    /// - Parameters:
    ///   - lower: The lower bound.
    ///   - upper: The upper bound, `-1` for unbounded.
    /// - Returns: The empty text, `[*]`, `[n-*]` or `[n-m]`.
    static func multiplicity(lower: Int, upper: Int) -> String {
        if lower == 1 && upper == 1 { return "" }
        if upper < 0 {
            return lower == 0
                ? KM3Symbol.openBracket + KM3Symbol.star + KM3Symbol.closeBracket
                : KM3Symbol.openBracket + "\(lower)" + KM3Symbol.minus + KM3Symbol.star + KM3Symbol.closeBracket
        }
        return KM3Symbol.openBracket + "\(lower)" + KM3Symbol.minus + "\(upper)" + KM3Symbol.closeBracket
    }

    /// The KM3 spelling of a name, in double quotes if it cannot be written plainly.
    ///
    /// Names that are reserved words, that are `true` or `false`, that are empty, or that
    /// contain anything but letters, digits and underscores (or start with a digit) are
    /// quoted, with backslash escapes for quotes, backslashes and line breaks.
    ///
    /// - Parameter name: The name.
    /// - Returns: The spelling.
    static func spell(_ name: String) -> String {
        if KM3Lexer.isPlainName(name) && !reservedLiterals.contains(name) { return name }
        var escaped = ""
        for character in name {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.append(character)
            }
        }
        return "\"" + escaped + "\""
    }

    /// The words that the original KM3 lexer reads as Boolean literals rather than names.
    private static let reservedLiterals: Set<String> = ["true", "false"]
}

/// The state of writing a set of packages.
struct KM3WritingContext {
    /// The root packages.
    private let packages: [EPackage]

    /// The classifiers of the packages, by identifier.
    private var classifiers: [EUUID: any EClassifier] = [:]

    /// The features of the classes of the packages, by identifier.
    private var features: [EUUID: any EStructuralFeature] = [:]

    /// The built-in Ecore data types that the packages use.
    private var builtIns: Set<EcoreDataType> = []

    /// The warnings so far.
    private(set) var diagnostics: [SourceDiagnostic] = []

    /// The text so far.
    private var output = ""

    /// Prepares to write packages.
    ///
    /// - Parameter packages: The root packages.
    init(packages: [EPackage]) {
        self.packages = packages
        for package in packages { index(package) }
    }

    /// Writes the packages.
    ///
    /// - Returns: The KM3 text.
    mutating func write() -> String {
        reportAmbiguousNames()
        collectBuiltIns()
        let primitiveNames = builtIns.map { KM3PrimitiveTypes.name(for: $0) }.sorted()
        var wrotePrimitives = false
        for (index, package) in packages.enumerated() {
            if index > 0 { output += "\n" }
            var extra: [String] = []
            if package.name == KM3Format.primitiveTypesPackageName && !wrotePrimitives {
                let declared = Set(package.eClassifiers.map(\.name))
                extra = primitiveNames.filter { !declared.contains($0) }
                wrotePrimitives = true
            }
            write(package, path: package.name, depth: 0, extraDataTypes: extra)
        }
        if !wrotePrimitives && !primitiveNames.isEmpty {
            if !packages.isEmpty { output += "\n" }
            write(
                EPackage(name: KM3Format.primitiveTypesPackageName), path: KM3Format.primitiveTypesPackageName,
                depth: 0, extraDataTypes: primitiveNames)
        }
        return output
    }

    // MARK: Indexing

    /// Records the classifiers and features of a package and its subpackages.
    ///
    /// - Parameter package: The package.
    private mutating func index(_ package: EPackage) {
        for classifier in package.eClassifiers {
            classifiers[classifier.id] = classifier
            if let eClass = classifier as? EClass {
                for feature in eClass.eStructuralFeatures { features[feature.id] = feature }
            }
        }
        for subpackage in package.eSubpackages { index(subpackage) }
    }

    /// Reports classifier names that several packages declare, which KM3 cannot tell apart.
    private mutating func reportAmbiguousNames() {
        var counts: [String: Int] = [:]
        var order: [String] = []
        /// Counts the classifier names of a package and its subpackages.
        ///
        /// - Parameter package: The package.
        func visit(_ package: EPackage) {
            for classifier in package.eClassifiers {
                if counts[classifier.name] == nil { order.append(classifier.name) }
                counts[classifier.name, default: 0] += 1
            }
            package.eSubpackages.forEach(visit)
        }
        packages.forEach(visit)
        for name in order where counts[name, default: 0] > 1 {
            diagnostics.append(
                SourceDiagnostic(
                    severity: .warning, code: KM3DiagnosticCode.ambiguousName.rawValue,
                    message: "Several classifiers are named '\(name)'; KM3 resolves the name to the first one"))
        }
    }

    /// Collects the built-in Ecore data types that the packages use.
    private mutating func collectBuiltIns() {
        /// Records a type if it is a built-in Ecore data type; a missing type stands for
        /// `EJavaObject`, which is how writing spells it.
        ///
        /// - Parameter type: The type, or `nil` for a parameter without one.
        func note(_ type: (any EClassifier)?) {
            guard let type else {
                builtIns.insert(.eJavaObject)
                return
            }
            if let builtIn = builtIn(type) { builtIns.insert(builtIn) }
        }
        /// Records the types that the classes of a package and its subpackages use.
        ///
        /// - Parameter package: The package.
        func visit(_ package: EPackage) {
            for case let eClass as EClass in package.eClassifiers {
                for feature in eClass.eStructuralFeatures { note(Self.type(of: feature)) }
                for operation in eClass.eOperations {
                    if let type = operation.eType { note(type) }
                    for parameter in operation.eParameters { note(parameter.eType) }
                }
            }
            package.eSubpackages.forEach(visit)
        }
        packages.forEach(visit)
        let declaredNames = Set(classifiers.values.map(\.name))
        for type in builtIns.sorted(by: { $0.rawValue < $1.rawValue }) {
            let name = KM3PrimitiveTypes.name(for: type)
            guard declaredNames.contains(name) else { continue }
            diagnostics.append(
                SourceDiagnostic(
                    severity: .warning, code: KM3DiagnosticCode.ambiguousName.rawValue,
                    message: "The Ecore data type \(type.rawValue) is written as '\(name)', "
                        + "which is also the name of a classifier of the packages"))
        }
    }

    /// The built-in Ecore data type that a classifier outside the packages is.
    ///
    /// - Parameter type: The classifier.
    /// - Returns: The built-in data type, or `nil` for a classifier of the packages, a class or
    ///   any other classifier.
    private func builtIn(_ type: any EClassifier) -> EcoreDataType? {
        guard classifiers[type.id] == nil, !(type is EClass) else { return nil }
        return EcoreDataType(rawValue: type.name)
    }

    /// The type of a feature.
    ///
    /// - Parameter feature: An attribute or reference.
    /// - Returns: Its type, or `nil` for any other feature.
    private static func type(of feature: any EStructuralFeature) -> (any EClassifier)? {
        switch feature {
        case let attribute as EAttribute: return attribute.eType
        case let reference as EReference: return reference.eType
        default: return nil
        }
    }

    // MARK: Packages

    /// Writes a package with its classifiers and subpackages.
    ///
    /// - Parameters:
    ///   - package: The package.
    ///   - path: The qualified name of the package, for diagnostics.
    ///   - depth: The nesting depth, which sets the indentation.
    ///   - extraDataTypes: The names of primitive types to declare after the classifiers.
    private mutating func write(_ package: EPackage, path: String, depth: Int, extraDataTypes: [String] = []) {
        let indent = String(repeating: "\t", count: depth)
        checkAnnotations(package.eAnnotations, of: path)
        if !package.nsURI.isEmpty {
            output += indent + directive(KM3Directive.nsURI, package.nsURI, of: path) + "\n"
        }
        if !package.nsPrefix.isEmpty {
            output += indent + directive(KM3Directive.nsPrefix, package.nsPrefix, of: path) + "\n"
        }
        output += indent + KM3Keyword.package.rawValue + " " + KM3Writer.spell(package.name) + " "
            + KM3Symbol.openBrace + "\n"
        var previousWasDataType = true
        /// Writes the blank line that separates declarations, except between data types.
        ///
        /// - Parameter isDataType: Whether the next declaration is a data type.
        func separate(isDataType: Bool) {
            if !(isDataType && previousWasDataType) { output += "\n" }
            previousWasDataType = isDataType
        }
        for classifier in package.eClassifiers {
            let classifierPath = path + "::" + classifier.name
            switch classifier {
            case let eClass as EClass:
                separate(isDataType: false)
                write(eClass, path: classifierPath, depth: depth + 1)
            case let eEnum as EEnum:
                separate(isDataType: false)
                write(eEnum, path: classifierPath, depth: depth + 1)
            case let dataType as EDataType:
                separate(isDataType: true)
                write(dataType, path: classifierPath, depth: depth + 1)
            default:
                warn(classifierPath, "a classifier that is neither a class, an enumeration nor a data type")
            }
        }
        for name in extraDataTypes {
            separate(isDataType: true)
            output += indent + "\t" + KM3Keyword.datatype.rawValue + " " + KM3Writer.spell(name) + KM3Symbol.semicolon
                + "\n"
        }
        for subpackage in package.eSubpackages {
            separate(isDataType: false)
            write(subpackage, path: path + "::" + subpackage.name, depth: depth + 1)
        }
        output += indent + KM3Symbol.closeBrace + "\n"
    }

    /// The comment line of a namespace directive.
    ///
    /// A value that spans several lines cannot be written; only its first line is kept.
    ///
    /// - Parameters:
    ///   - name: The name of the directive.
    ///   - value: The value.
    ///   - path: The qualified name of the package, for diagnostics.
    /// - Returns: The comment line without its line end.
    private mutating func directive(_ name: String, _ value: String, of path: String) -> String {
        let lines = value.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r" }
        if lines.count > 1 { warn(path, "a \(name) that spans several lines; only its first line is kept") }
        return KM3Directive.commentMarker + " " + String(KM3Directive.marker) + name + " " + String(lines.first ?? "")
    }

    // MARK: Classifiers

    /// Writes a class with its features and operations.
    ///
    /// - Parameters:
    ///   - eClass: The class.
    ///   - path: The qualified name of the class, for diagnostics.
    ///   - depth: The nesting depth.
    private mutating func write(_ eClass: EClass, path: String, depth: Int) {
        let indent = String(repeating: "\t", count: depth)
        checkAnnotations(eClass.eAnnotations, of: path)
        if eClass.isInterface { warn(path, "the interface flag") }
        if let name = eClass.instanceClassName { warn(path, "the instance class name '\(name)'") }
        if let name = eClass.instanceTypeName { warn(path, "the instance type name '\(name)'") }
        if !eClass.eTypeParameters.isEmpty { warn(path, "type parameters") }
        if !eClass.eGenericSuperTypes.isEmpty { warn(path, "generic supertypes (they are written as raw types)") }
        var line = indent
        if eClass.isAbstract { line += KM3Keyword.abstract.rawValue + " " }
        line += KM3Keyword.class.rawValue + " " + KM3Writer.spell(eClass.name)
        if !eClass.eSuperTypes.isEmpty {
            let names = eClass.eSuperTypes.map { typeName($0, of: path) }
            line += " " + KM3Keyword.extends.rawValue + " " + names.joined(separator: KM3Symbol.comma + " ")
        }
        output += line + " " + KM3Symbol.openBrace + "\n"
        for feature in eClass.eStructuralFeatures {
            let featurePath = path + "." + feature.name
            switch feature {
            case let attribute as EAttribute: write(attribute, path: featurePath, depth: depth + 1)
            case let reference as EReference: write(reference, path: featurePath, depth: depth + 1)
            default: continue
            }
        }
        for operation in eClass.eOperations { write(operation, path: path + "." + operation.name, depth: depth + 1) }
        output += indent + KM3Symbol.closeBrace + "\n"
    }

    /// Writes a data type.
    ///
    /// - Parameters:
    ///   - dataType: The data type.
    ///   - path: The qualified name of the data type, for diagnostics.
    ///   - depth: The nesting depth.
    private mutating func write(_ dataType: EDataType, path: String, depth: Int) {
        checkAnnotations(dataType.eAnnotations, of: path)
        if let name = dataType.instanceClassName, !isConventional(name, for: dataType.name) {
            warn(path, "the instance class name '\(name)'")
        }
        if let name = dataType.instanceTypeName { warn(path, "the instance type name '\(name)'") }
        if !dataType.serialisable { warn(path, "the serialisable flag") }
        if let literal = dataType.defaultValueLiteral { warn(path, "the default value '\(literal)'") }
        if !dataType.eTypeParameters.isEmpty { warn(path, "type parameters") }
        output += String(repeating: "\t", count: depth) + KM3Keyword.datatype.rawValue + " "
            + KM3Writer.spell(dataType.name) + KM3Symbol.semicolon + "\n"
    }

    /// Whether an instance class name is the one that a data type of a name has anyway.
    ///
    /// - Parameters:
    ///   - instanceClassName: The instance class name.
    ///   - name: The name of the data type.
    /// - Returns: `true` if the name is the conventional Java class of a primitive type or the
    ///   class that a built-in Ecore data type of that name receives by default.
    private func isConventional(_ instanceClassName: String, for name: String) -> Bool {
        KM3PrimitiveTypes.primitiveType(named: name)?.instanceClassName == instanceClassName
            || EDataType(name: name).instanceClassName == instanceClassName
    }

    /// Writes an enumeration with its literals.
    ///
    /// - Parameters:
    ///   - eEnum: The enumeration.
    ///   - path: The qualified name of the enumeration, for diagnostics.
    ///   - depth: The nesting depth.
    private mutating func write(_ eEnum: EEnum, path: String, depth: Int) {
        let indent = String(repeating: "\t", count: depth)
        checkAnnotations(eEnum.eAnnotations, of: path)
        if let name = eEnum.instanceClassName { warn(path, "the instance class name '\(name)'") }
        if let name = eEnum.instanceTypeName { warn(path, "the instance type name '\(name)'") }
        if !eEnum.serialisable { warn(path, "the serialisable flag") }
        if !eEnum.eTypeParameters.isEmpty { warn(path, "type parameters") }
        output += indent + KM3Keyword.enumeration.rawValue + " " + KM3Writer.spell(eEnum.name) + " "
            + KM3Symbol.openBrace + "\n"
        for (index, literal) in eEnum.literals.enumerated() {
            let literalPath = path + "." + literal.name
            let position = index + 1
            checkAnnotations(literal.eAnnotations, of: literalPath)
            if literal.value != position { warn(literalPath, "the value \(literal.value) (it becomes \(position))") }
            if let text = literal.literal, text != literal.name { warn(literalPath, "the literal text '\(text)'") }
            output += indent + "\t" + KM3Keyword.literal.rawValue + " " + KM3Writer.spell(literal.name)
                + KM3Symbol.semicolon + "\n"
        }
        output += indent + KM3Symbol.closeBrace + "\n"
    }

    // MARK: Features

    /// Writes an attribute.
    ///
    /// - Parameters:
    ///   - attribute: The attribute.
    ///   - path: The qualified name of the attribute, for diagnostics.
    ///   - depth: The nesting depth.
    private mutating func write(_ attribute: EAttribute, path: String, depth: Int) {
        checkAnnotations(attribute.eAnnotations, of: path)
        checkFeatureFlags(
            path: path, defaultValue: attribute.defaultValueLiteral, derived: attribute.derived,
            transient: attribute.transient, volatile: attribute.volatile, changeable: attribute.changeable,
            unsettable: attribute.unsettable, hasGenericType: attribute.eGenericType != nil)
        if attribute.isID { warn(path, "the identifier flag") }
        var line = String(repeating: "\t", count: depth) + KM3Keyword.attribute.rawValue + " "
            + KM3Writer.spell(attribute.name)
            + bounds(lower: attribute.lowerBound, upper: attribute.upperBound, of: path)
        if attribute.ordered { line += " " + KM3Keyword.ordered.rawValue }
        if attribute.unique { line += " " + KM3Keyword.unique.rawValue }
        line += " " + KM3Symbol.colon + " " + typeName(attribute.eType, of: path)
        output += line + KM3Symbol.semicolon + "\n"
    }

    /// Writes a reference.
    ///
    /// - Parameters:
    ///   - reference: The reference.
    ///   - path: The qualified name of the reference, for diagnostics.
    ///   - depth: The nesting depth.
    private mutating func write(_ reference: EReference, path: String, depth: Int) {
        checkAnnotations(reference.eAnnotations, of: path)
        checkFeatureFlags(
            path: path, defaultValue: reference.defaultValueLiteral, derived: reference.derived,
            transient: reference.transient, volatile: reference.volatile, changeable: reference.changeable,
            unsettable: reference.unsettable, hasGenericType: reference.eGenericType != nil)
        if !reference.unique { warn(path, "the non-unique flag (KM3 references are unique)") }
        if !reference.resolveProxies { warn(path, "the flag that turns off proxy resolution") }
        if !reference.eKeys.isEmpty { warn(path, "the reference keys") }
        var line = String(repeating: "\t", count: depth) + KM3Keyword.reference.rawValue + " "
            + KM3Writer.spell(reference.name)
            + bounds(lower: reference.lowerBound, upper: reference.upperBound, of: path)
        if reference.ordered { line += " " + KM3Keyword.ordered.rawValue }
        if reference.containment { line += " " + KM3Keyword.container.rawValue }
        line += " " + KM3Symbol.colon + " " + typeName(reference.eType, of: path)
        if let opposite = reference.opposite {
            if let target = features[opposite] {
                line += " " + KM3Keyword.oppositeOf.rawValue + " " + KM3Writer.spell(target.name)
            } else {
                warn(path, "an opposite that is not part of the written packages")
            }
        }
        output += line + KM3Symbol.semicolon + "\n"
    }

    /// Reports the flags of a feature that KM3 cannot express.
    ///
    /// - Parameters:
    ///   - path: The qualified name of the feature.
    ///   - defaultValue: The default value literal.
    ///   - derived: Whether the feature is derived.
    ///   - transient: Whether the feature is transient.
    ///   - volatile: Whether the feature is volatile.
    ///   - changeable: Whether the feature is changeable.
    ///   - unsettable: Whether the feature is unsettable.
    ///   - hasGenericType: Whether the feature has a generic type.
    private mutating func checkFeatureFlags(
        path: String, defaultValue: String?, derived: Bool, transient: Bool, volatile: Bool, changeable: Bool,
        unsettable: Bool, hasGenericType: Bool
    ) {
        if let defaultValue { warn(path, "the default value '\(defaultValue)'") }
        if derived { warn(path, "the derived flag") }
        if transient { warn(path, "the transient flag") }
        if volatile { warn(path, "the volatile flag") }
        if !changeable { warn(path, "the unchangeable flag") }
        if unsettable { warn(path, "the unsettable flag") }
        if hasGenericType { warn(path, "a generic type (it is written as its raw type)") }
    }

    /// The multiplicity text of a feature, reporting an unspecified upper bound.
    ///
    /// - Parameters:
    ///   - lower: The lower bound.
    ///   - upper: The upper bound.
    ///   - path: The qualified name of the feature, for diagnostics.
    /// - Returns: The multiplicity text.
    private mutating func bounds(lower: Int, upper: Int, of path: String) -> String {
        if upper < -1 { warn(path, "the unspecified upper bound \(upper) (it is written as '*')") }
        return KM3Writer.multiplicity(lower: lower, upper: upper < 0 ? -1 : upper)
    }

    // MARK: Operations

    /// Writes an operation with its parameters.
    ///
    /// - Parameters:
    ///   - operation: The operation.
    ///   - path: The qualified name of the operation, for diagnostics.
    ///   - depth: The nesting depth.
    private mutating func write(_ operation: EOperation, path: String, depth: Int) {
        checkAnnotations(operation.eAnnotations, of: path)
        checkTypedElement(
            path: path, lower: operation.lowerBound, upper: operation.upperBound, ordered: operation.ordered,
            unique: operation.unique, hasGenericType: operation.eGenericType != nil, what: "result")
        if !operation.eExceptions.isEmpty || !operation.eGenericExceptions.isEmpty { warn(path, "the exceptions") }
        if !operation.eTypeParameters.isEmpty { warn(path, "type parameters") }
        let parameters = operation.eParameters.map { parameter -> String in
            let parameterPath = path + "." + parameter.name
            checkAnnotations(parameter.eAnnotations, of: parameterPath)
            checkTypedElement(
                path: parameterPath, lower: parameter.lowerBound, upper: parameter.upperBound,
                ordered: parameter.ordered, unique: parameter.unique, hasGenericType: parameter.eGenericType != nil,
                what: "parameter")
            let type: String
            if let eType = parameter.eType {
                type = typeName(eType, of: parameterPath)
            } else {
                warn(parameterPath, "the absence of a type (it is written as \(EcoreDataType.eJavaObject.rawValue))")
                type = KM3PrimitiveTypes.name(for: .eJavaObject)
            }
            return KM3Writer.spell(parameter.name) + " " + KM3Symbol.colon + " " + type
        }
        var line = String(repeating: "\t", count: depth) + KM3Keyword.operation.rawValue + " "
            + KM3Writer.spell(operation.name) + KM3Symbol.openParenthesis
            + parameters.joined(separator: KM3Symbol.comma + " ") + KM3Symbol.closeParenthesis
        if let type = operation.eType { line += " " + KM3Symbol.colon + " " + typeName(type, of: path) }
        output += line + KM3Symbol.semicolon + "\n"
    }

    /// Reports the bounds and flags of an operation or parameter that KM3 cannot express.
    ///
    /// - Parameters:
    ///   - path: The qualified name of the element.
    ///   - lower: The lower bound.
    ///   - upper: The upper bound.
    ///   - ordered: Whether the element is ordered.
    ///   - unique: Whether the element is unique.
    ///   - hasGenericType: Whether the element has a generic type.
    ///   - what: What the element is, for diagnostics.
    private mutating func checkTypedElement(
        path: String, lower: Int, upper: Int, ordered: Bool, unique: Bool, hasGenericType: Bool, what: String
    ) {
        if lower != 0 || upper != 1 { warn(path, "the \(what) multiplicity [\(lower)..\(upper)]") }
        if !ordered { warn(path, "the unordered \(what) flag") }
        if !unique { warn(path, "the non-unique \(what) flag") }
        if hasGenericType { warn(path, "a generic type (it is written as its raw type)") }
    }

    // MARK: Names

    /// The KM3 name of a type.
    ///
    /// - Parameters:
    ///   - type: The type.
    ///   - path: The qualified name of the element that uses the type, for diagnostics.
    /// - Returns: The spelling of the name of the type in the packages, or of the KM3 name of a
    ///   built-in Ecore data type. A type outside the packages is reported and written by name.
    private mutating func typeName(_ type: any EClassifier, of path: String) -> String {
        if let local = classifiers[type.id] { return KM3Writer.spell(local.name) }
        if let builtIn = builtIn(type) { return KM3Writer.spell(KM3PrimitiveTypes.name(for: builtIn)) }
        diagnostics.append(
            SourceDiagnostic(
                severity: .warning, code: KM3DiagnosticCode.externalType.rawValue,
                message: "'\(path)' refers to '\(type.name)', which is not part of the written packages; "
                    + "the name is written without a declaration"))
        return KM3Writer.spell(type.name)
    }

    // MARK: Diagnostics

    /// Reports annotations, which KM3 cannot express.
    ///
    /// - Parameters:
    ///   - annotations: The annotations of an element.
    ///   - path: The qualified name of the element.
    private mutating func checkAnnotations(_ annotations: [EAnnotation], of path: String) {
        guard !annotations.isEmpty else { return }
        let sources = annotations.map(\.source).joined(separator: ", ")
        warn(path, annotations.count == 1 ? "the annotation \(sources)" : "the annotations \(sources)")
    }

    /// Reports a property that KM3 cannot express.
    ///
    /// - Parameters:
    ///   - path: The qualified name of the element.
    ///   - property: The property, as a phrase.
    private mutating func warn(_ path: String, _ property: String) {
        diagnostics.append(
            SourceDiagnostic(
                severity: .warning, code: KM3DiagnosticCode.inexpressible.rawValue,
                message: "KM3 cannot express \(property) of '\(path)'; it is dropped"))
    }
}
