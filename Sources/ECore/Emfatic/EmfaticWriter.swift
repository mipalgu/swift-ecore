//
// EmfaticWriter.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import OrderedCollections
import Foundation

/// Writes native Ecore packages as canonical Emfatic text.
///
/// The writer produces one document for one root package and its subpackages: the
/// package annotations, `@namespace` with the URI and prefix, the package declaration,
/// then the classifiers in model order followed by the subpackages. Members are written
/// with their annotations on the lines before them, attributes and references first and
/// operations after them. Built-in Ecore types are written with their Emfatic basic type
/// names where one exists, and names that are keywords are escaped with `~`.
///
/// Everything that Emfatic cannot express is reported as a warning with the code
/// ``EmfaticDiagnosticCode/lossyWrite``, so that a round trip through the writer and
/// ``EmfaticReader`` is lossless whenever no warning is reported.
public enum EmfaticWriter {
    /// Writes packages as an Emfatic document.
    ///
    /// Emfatic documents hold one root package, so only the first package is written; any
    /// further packages are reported as lost.
    ///
    /// - Parameter packages: The packages to write.
    /// - Returns: The Emfatic text and the warnings about information it cannot express.
    public static func write(_ packages: [EPackage]) -> (text: String, diagnostics: [SourceDiagnostic]) {
        var writer = EmfaticTextWriter(packages: packages)
        return writer.write()
    }
}

/// The state of writing one Emfatic document.
struct EmfaticTextWriter {
    /// The keyword vocabulary of the Emfatic language.
    private typealias Keyword = EmfaticLanguage.Keyword

    /// The packages to write.
    private let packages: [EPackage]
    /// The naming scheme that qualifies classifier names.
    private let naming: ClassifierNaming
    /// The factory that creates diagnostics.
    private let factory = DiagnosticFactory(namespace: EmfaticLanguage.diagnosticNamespace)
    /// The text written so far.
    private var output = IndentedText()
    /// The diagnostics reported while writing.
    private var diagnostics: [SourceDiagnostic] = []
    /// The names of structural features, by identifier.
    private var featureNames: [EUUID: String] = [:]
    /// The annotation labels, by source.
    private var labels: [String: String] = [:]

    /// Creates a writer for packages.
    ///
    /// - Parameter packages: The packages to write; only the first is written.
    init(packages: [EPackage]) {
        self.packages = packages
        naming = ClassifierNaming(packages: Array(packages.prefix(1)))
        for (label, source) in EmfaticLanguage.annotationLabels { labels[label.lowercased()] = source }
        for package in packages.prefix(1) { indexFeatures(of: package) }
    }

    /// Records the names of all features of a package and its subpackages.
    ///
    /// - Parameter package: The package to index.
    private mutating func indexFeatures(of package: EPackage) {
        for case let eClass as EClass in package.eClassifiers {
            for feature in eClass.eStructuralFeatures { featureNames[feature.id] = feature.name }
        }
        for subpackage in package.eSubpackages { indexFeatures(of: subpackage) }
    }

    /// Writes the document.
    ///
    /// - Returns: The text and the diagnostics.
    mutating func write() -> (text: String, diagnostics: [SourceDiagnostic]) {
        guard let root = packages.first else {
            lose("There is no package to write")
            return ("", diagnostics)
        }
        if packages.count > 1 {
            lose("An Emfatic document holds one root package; \(packages.count - 1) further package(s) are not written")
        }
        for name in ExternalClassifiers.names(in: [root], naming: naming) {
            lose("The classifier '\(name)' is not declared by the written package; no import is written for it")
        }
        writePackage(root, key: root.name, isRoot: true)
        output.trimTrailingEmptyLines()
        return (output.text, diagnostics)
    }

    /// Reports a construct that cannot be represented in Emfatic.
    ///
    /// - Parameter message: The text of the warning.
    private mutating func lose(_ message: String) {
        diagnostics.append(factory.warning(.lossyWrite, message, at: nil))
    }

    // MARK: Names

    /// Escapes a name if it is a keyword.
    ///
    /// - Parameter name: The name to escape.
    /// - Returns: The name, escaped where necessary.
    private static func escaped(_ name: String) -> String {
        EmfaticLanguage.keywords.contains(name) ? String(EmfaticLanguage.escapeCharacter) + name : name
    }

    /// Escapes each segment of a qualified name.
    ///
    /// - Parameter name: The qualified name.
    /// - Returns: The name with keyword segments escaped.
    private static func escapedQualified(_ name: String) -> String {
        var result = ""
        var segment = ""
        for character in name {
            if character == "." || character == "$" {
                result += escaped(segment) + String(character)
                segment = ""
            } else {
                segment.append(character)
            }
        }
        return result + escaped(segment)
    }

    /// Returns whether text is a valid Emfatic identifier.
    ///
    /// - Parameter text: The text to check.
    /// - Returns: `true` if the text can be written without quoting.
    private static func isIdentifier(_ text: Substring) -> Bool {
        guard let first = text.first, first.isLetter || first == "_" else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Whether a text can be written as an unquoted qualified name.
    private static func isQualifiedName(_ text: String) -> Bool {
        let segments = text.split(separator: ".", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: "$", omittingEmptySubsequences: false) }
        return !segments.isEmpty && segments.allSatisfy { isIdentifier($0) && !EmfaticLanguage.keywords.contains(String($0)) }
    }

    /// Quotes text as a string literal.
    ///
    /// - Parameter text: The text to quote.
    /// - Returns: The quoted and escaped text.
    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: Packages

    /// Writes a package and its contents.
    ///
    /// - Parameters:
    ///   - package: The package to write.
    ///   - key: The qualified key that identifies the package.
    ///   - isRoot: Whether the package is the root package of the document.
    private mutating func writePackage(_ package: EPackage, key: String, isRoot: Bool) {
        for annotation in package.eAnnotations { writeAnnotation(annotation, onPackage: true) }
        output.verbatim(
            "@" + EmfaticLanguage.namespaceLabel + "(" + EmfaticLanguage.NamespaceKey.uri.rawValue + "="
                + Self.quoted(package.nsURI) + ", " + EmfaticLanguage.NamespaceKey.prefix.rawValue + "="
                + Self.quoted(package.nsPrefix) + ")")
        if package.name.isEmpty { lose("A package without a name cannot be written as Emfatic") }
        if isRoot {
            output.verbatim(Keyword.package.rawValue + " " + Self.escapedQualified(package.name) + ";")
            output.line()
        } else {
            if package.name.contains(".") { lose("The subpackage name '\(package.name)' is not a simple name") }
            output.verbatim(Keyword.package.rawValue + " " + Self.escaped(package.name) + " {")
            output.indent()
        }
        for classifier in package.eClassifiers {
            writeClassifier(classifier, packageKey: key)
            output.separate()
        }
        for subpackage in package.eSubpackages {
            writePackage(subpackage, key: key + "." + subpackage.name, isRoot: false)
            output.separate()
        }
        if !isRoot {
            output.trimTrailingEmptyLines()
            output.outdent()
            output.verbatim("}")
        }
    }

    // MARK: Annotations

    /// Renders an annotation as text.
    ///
    /// - Parameters:
    ///   - annotation: The annotation to render.
    ///   - onPackage: Whether the annotation belongs to a package.
    /// - Returns: The annotation text.
    private mutating func annotationText(_ annotation: EAnnotation, onPackage: Bool = false) -> String {
        if !annotation.references.isEmpty || !annotation.contents.isEmpty || !annotation.eAnnotations.isEmpty {
            lose("The references, contents and nested annotations of the annotation '\(annotation.source)' are not written")
        }
        var label: String
        if let known = EmfaticLanguage.annotationLabels.first(where: { $0.source == annotation.source }) {
            label = known.label
        } else if Self.isQualifiedName(annotation.source), labels[annotation.source.lowercased()] == nil,
            !(onPackage && annotation.source.lowercased() == EmfaticLanguage.namespaceLabel)
        {
            label = annotation.source
        } else {
            label = Self.quoted(annotation.source)
        }
        if annotation.source == EmfaticLanguage.annotationMapSource {
            for (key, value) in annotation.details {
                let name = key.split(separator: "(").first.map(String.init) ?? key
                labels[name.lowercased()] = value
            }
        }
        label = "@" + label
        guard !annotation.details.isEmpty else { return label }
        let details = annotation.details.map { key, value in
            (Self.isIdentifier(Substring(key)) && !EmfaticLanguage.keywords.contains(key) ? key : Self.quoted(key))
                + "=" + Self.quoted(value)
        }
        return label + "(" + details.joined(separator: ", ") + ")"
    }

    /// Writes an annotation on its own line.
    ///
    /// - Parameters:
    ///   - annotation: The annotation to write.
    ///   - onPackage: Whether the annotation belongs to a package.
    private mutating func writeAnnotation(_ annotation: EAnnotation, onPackage: Bool = false) {
        output.verbatim(annotationText(annotation, onPackage: onPackage))
    }

    // MARK: Types

    /// The context in which type names are written.
    private struct TypeScope {
        var packageKey: String
        var parameters: [EUUID: String] = [:]
        var shadowing: Set<String> { Set(parameters.values) }
    }

    /// Returns the name of a classifier as seen from a scope.
    ///
    /// - Parameters:
    ///   - classifier: The classifier to name.
    ///   - scope: The scope in which the name is written.
    /// - Returns: The escaped, suitably qualified name.
    private func classifierName(_ classifier: any EClassifier, in scope: TypeScope) -> String {
        if let local = naming.name(of: classifier, from: scope.packageKey, shadowing: scope.shadowing) {
            return Self.escapedQualified(local)
        }
        if EcoreBuiltins.isBuiltin(classifier) {
            return naming.externalName(
                EmfaticLanguage.builtinSpellings(of: classifier.name), from: scope.packageKey, shadowing: scope.shadowing)
                ?? classifier.name
        }
        return Self.escapedQualified(classifier.name)
    }

    /// Renders a generic type.
    ///
    /// - Parameters:
    ///   - generic: The generic type to render.
    ///   - scope: The scope in which the type is written.
    /// - Returns: The type text.
    private func typeText(_ generic: EGenericType, in scope: TypeScope) -> String {
        if let parameter = generic.eTypeParameter {
            return Self.escaped(scope.parameters[parameter] ?? EcoreDataType.eJavaObject.rawValue)
        }
        guard let classifier = generic.eClassifier else {
            if let upper = generic.eUpperBound { return "? " + Keyword.extends.rawValue + " " + typeText(upper, in: scope) }
            if let lower = generic.eLowerBound { return "? " + Keyword.super.rawValue + " " + typeText(lower, in: scope) }
            return "?"
        }
        let name = classifierName(classifier, in: scope)
        guard !generic.eTypeArguments.isEmpty else { return name }
        return name + "<" + generic.eTypeArguments.map { typeText($0, in: scope) }.joined(separator: ", ") + ">"
    }

    /// Renders a generic type, or a raw classifier if there is no generic type.
    ///
    /// - Parameters:
    ///   - generic: The generic type, if any.
    ///   - raw: The raw classifier used when there is no generic type.
    ///   - scope: The scope in which the type is written.
    /// - Returns: The type text, defaulting to the Java object type.
    private func typeText(generic: EGenericType?, raw: (any EClassifier)?, in scope: TypeScope) -> String {
        if let generic { return typeText(generic, in: scope) }
        if let raw { return classifierName(raw, in: scope) }
        return EcoreDataType.eJavaObject.rawValue
    }

    /// Renders type parameters with their bounds.
    ///
    /// - Parameters:
    ///   - parameters: The type parameters to render.
    ///   - scope: The scope in which the parameters are written.
    /// - Returns: The text, empty if there are no parameters.
    private mutating func typeParametersText(_ parameters: [ETypeParameter], in scope: TypeScope) -> String {
        guard !parameters.isEmpty else { return "" }
        let texts = parameters.map { parameter -> String in
            if !parameter.eAnnotations.isEmpty { lose("The annotations of type parameter '\(parameter.name)' are not written") }
            guard !parameter.eBounds.isEmpty else { return Self.escaped(parameter.name) }
            return Self.escaped(parameter.name) + " " + Keyword.extends.rawValue + " "
                + parameter.eBounds.map { typeText($0, in: scope) }.joined(separator: " & ")
        }
        return "<" + texts.joined(separator: ", ") + ">"
    }

    /// Renders a multiplicity.
    ///
    /// - Parameters:
    ///   - lower: The lower bound.
    ///   - upper: The upper bound.
    /// - Returns: The multiplicity text.
    private static func multiplicity(_ lower: Int, _ upper: Int) -> String {
        OutlineBuilder.multiplicity(lower, upper)
    }

    // MARK: Classifiers

    /// Writes a classifier.
    ///
    /// - Parameters:
    ///   - classifier: The classifier to write.
    ///   - packageKey: The qualified key of the owning package.
    private mutating func writeClassifier(_ classifier: any EClassifier, packageKey: String) {
        let scope = TypeScope(packageKey: packageKey)
        switch classifier {
        case let eClass as EClass:
            if writeMapEntry(eClass, scope: scope) { return }
            writeClass(eClass, scope: scope)
        case let eEnum as EEnum:
            writeEnum(eEnum)
        case let dataType as EDataType:
            writeDataType(dataType)
        default:
            lose("The classifier '\(classifier.name)' of an unknown kind is not written")
        }
    }

    /// Renders an instance class name.
    ///
    /// - Parameter text: The instance class name.
    /// - Returns: The name, quoted if it is not a qualified name.
    private static func instanceText(_ text: String) -> String {
        isQualifiedName(text) ? text : quoted(text)
    }

    /// Writes a class or interface with its members.
    ///
    /// - Parameters:
    ///   - eClass: The class to write.
    ///   - outer: The scope enclosing the class.
    private mutating func writeClass(_ eClass: EClass, scope outer: TypeScope) {
        var scope = outer
        for parameter in eClass.eTypeParameters { scope.parameters[parameter.id] = parameter.name }
        for annotation in eClass.eAnnotations { writeAnnotation(annotation) }
        var header = ""
        if eClass.isAbstract { header += Keyword.abstract.rawValue + " " }
        header += (eClass.isInterface ? Keyword.interface : Keyword.class).rawValue + " " + Self.escaped(eClass.name)
        header += typeParametersText(eClass.eTypeParameters, in: scope)
        let superTypes = eClass.eGenericSuperTypes.isEmpty
            ? eClass.eSuperTypes.map { classifierName($0, in: scope) }
            : eClass.eGenericSuperTypes.map { typeText($0, in: scope) }
        if !superTypes.isEmpty { header += " " + Keyword.extends.rawValue + " " + superTypes.joined(separator: ", ") }
        if let instance = eClass.instanceTypeName ?? eClass.instanceClassName {
            header += " : " + Self.instanceText(instance)
        }
        output.verbatim(header + " {")
        output.indent()
        var first = true
        for feature in eClass.eStructuralFeatures {
            writeFeature(feature, owner: eClass, scope: scope, first: first)
            first = false
        }
        for operation in eClass.eOperations {
            writeOperation(operation, scope: scope, first: first)
            first = false
        }
        output.outdent()
        output.verbatim("}")
    }

    /// Writes a class in the `mapentry` shorthand if it has exactly that form.
    private mutating func writeMapEntry(_ eClass: EClass, scope: TypeScope) -> Bool {
        guard eClass.instanceClassName == EmfaticLanguage.mapEntryInstanceClassName, eClass.instanceTypeName == nil,
            !eClass.isAbstract, !eClass.isInterface, eClass.eSuperTypes.isEmpty, eClass.eTypeParameters.isEmpty,
            eClass.eOperations.isEmpty, eClass.eStructuralFeatures.count == 2,
            eClass.eStructuralFeatures[0].name == EmfaticLanguage.MapEntryFeature.key.rawValue,
            eClass.eStructuralFeatures[1].name == EmfaticLanguage.MapEntryFeature.value.rawValue,
            eClass.eStructuralFeatures.allSatisfy(Self.isPlainMapEntryFeature)
        else { return false }
        for annotation in eClass.eAnnotations { writeAnnotation(annotation) }
        let types = eClass.eStructuralFeatures.compactMap(FeatureFacts.init).map { feature in
            typeText(generic: feature.eGenericType, raw: feature.eType, in: scope)
                + Self.multiplicity(feature.lowerBound, feature.upperBound)
        }
        output.verbatim(Keyword.mapentry.rawValue + " " + Self.escaped(eClass.name) + " : " + types[0] + " -> " + types[1] + ";")
        return true
    }

    /// Whether a feature reads back identically from the `mapentry` shorthand.
    private static func isPlainMapEntryFeature(_ feature: any EStructuralFeature) -> Bool {
        guard let facts = FeatureFacts(feature) else { return false }
        return isPlainMapEntryFeature(facts)
    }

    /// Returns whether a feature is a plain key or value feature of a map entry.
    ///
    /// - Parameter feature: The feature to check.
    /// - Returns: `true` if the feature needs no annotation or modifiers.
    private static func isPlainMapEntryFeature(_ feature: FeatureFacts) -> Bool {
        guard feature.eAnnotations.isEmpty, feature.changeable, !feature.volatile, !feature.transient,
            !feature.unsettable, !feature.derived, feature.unique, feature.ordered, feature.defaultValueLiteral == nil
        else { return false }
        if let attribute = feature.attribute { return !attribute.isID && !(attribute.eType is EClass) }
        guard let reference = feature.reference else { return false }
        return reference.eType is EClass && !reference.containment && reference.opposite == nil
            && reference.resolveProxies && reference.eKeys.isEmpty
    }

    /// Writes a data type.
    ///
    /// - Parameter dataType: The data type to write.
    private mutating func writeDataType(_ dataType: EDataType) {
        for annotation in dataType.eAnnotations { writeAnnotation(annotation) }
        if !dataType.eTypeParameters.isEmpty { lose("The type parameters of data type '\(dataType.name)' are not written") }
        if dataType.defaultValueLiteral != nil { lose("The default value of data type '\(dataType.name)' is not written") }
        let prefix = dataType.serialisable ? "" : Keyword.transient.rawValue + " "
        let instance = dataType.instanceTypeName ?? dataType.instanceClassName ?? ""
        output.verbatim(prefix + Keyword.datatype.rawValue + " " + Self.escaped(dataType.name) + " : " + Self.instanceText(instance) + ";")
    }

    /// Writes an enumeration with its literals.
    ///
    /// - Parameter eEnum: The enumeration to write.
    private mutating func writeEnum(_ eEnum: EEnum) {
        for annotation in eEnum.eAnnotations { writeAnnotation(annotation) }
        if !eEnum.serialisable { lose("Enumeration '\(eEnum.name)' is written as serialisable") }
        if eEnum.instanceClassName != nil || eEnum.instanceTypeName != nil {
            lose("The instance class name of enumeration '\(eEnum.name)' is not written")
        }
        if !eEnum.eTypeParameters.isEmpty { lose("The type parameters of enumeration '\(eEnum.name)' are not written") }
        output.verbatim(Keyword.enum.rawValue + " " + Self.escaped(eEnum.name) + " {")
        output.indent()
        for literal in eEnum.literals {
            if let text = literal.literal, text != literal.name {
                lose("The literal text '\(text)' of '\(eEnum.name).\(literal.name)' is not written")
            }
            let annotations = literal.eAnnotations.map { annotationText($0) }
            for annotation in annotations { output.verbatim(annotation) }
            output.verbatim(Self.escaped(literal.name) + " = " + String(literal.value) + ";")
        }
        output.outdent()
        output.verbatim("}")
    }

    // MARK: Members

    /// Writes the annotations of a member.
    ///
    /// - Parameters:
    ///   - annotations: The annotations to write.
    ///   - first: Whether the member is the first in its container.
    private mutating func writeMemberAnnotations(_ annotations: [EAnnotation], first: Bool) {
        guard !annotations.isEmpty else { return }
        if !first { output.separate() }
        for annotation in annotations { writeAnnotation(annotation) }
    }

    /// Renders a modifier keyword.
    ///
    /// - Parameters:
    ///   - keyword: The modifier keyword.
    ///   - negated: Whether the modifier is written negated.
    /// - Returns: The modifier text followed by a space.
    private static func modifierText(_ keyword: Keyword, negated: Bool = false) -> String {
        (negated ? EmfaticLanguage.negation : "") + keyword.rawValue + " "
    }

    /// Writes an attribute or reference.
    ///
    /// - Parameters:
    ///   - structuralFeature: The feature to write.
    ///   - owner: The class that owns the feature.
    ///   - scope: The scope in which the feature is written.
    ///   - first: Whether the feature is the first member of its class.
    private mutating func writeFeature(_ structuralFeature: any EStructuralFeature, owner: EClass, scope: TypeScope, first: Bool) {
        guard let feature = FeatureFacts(structuralFeature) else {
            lose("The feature '\(owner.name).\(structuralFeature.name)' of an unknown kind is not written")
            return
        }
        writeMemberAnnotations(feature.eAnnotations, first: first)
        var line = ""
        if !feature.unique { line += Self.modifierText(.unique, negated: true) }
        if !feature.ordered { line += Self.modifierText(.ordered, negated: true) }
        if !feature.changeable { line += Self.modifierText(.readonly) }
        if feature.volatile { line += Self.modifierText(.volatile) }
        if feature.transient { line += Self.modifierText(.transient) }
        if feature.unsettable { line += Self.modifierText(.unsettable) }
        if feature.derived { line += Self.modifierText(.derived) }
        let type = typeText(generic: feature.eGenericType, raw: feature.eType, in: scope)
            + Self.multiplicity(feature.lowerBound, feature.upperBound)
        let name = Self.escaped(feature.name)
        if let attribute = feature.attribute {
            if attribute.isID { line += Self.modifierText(.id) }
            line += Keyword.attr.rawValue + " " + type + " " + name
            if let literal = attribute.defaultValueLiteral { line += " = " + defaultValueText(literal, type: attribute.eType) }
        } else if let reference = feature.reference {
            if !reference.resolveProxies { line += Self.modifierText(.resolve, negated: true) }
            line += (reference.containment ? Keyword.val : Keyword.ref).rawValue + " " + type
            if let opposite = reference.opposite {
                if let oppositeName = featureNames[opposite] {
                    line += "#" + Self.escaped(oppositeName)
                } else {
                    lose("The opposite of '\(owner.name).\(reference.name)' is outside the written package and is not written")
                }
            }
            line += " " + name
            if !reference.eKeys.isEmpty { lose("The keys of '\(owner.name).\(reference.name)' are not written") }
            if reference.defaultValueLiteral != nil {
                lose("The default value of reference '\(owner.name).\(reference.name)' is not written")
            }
        }
        output.verbatim(line + ";")
    }

    /// Renders a default value literal.
    ///
    /// - Parameters:
    ///   - literal: The default value literal.
    ///   - type: The type of the feature.
    /// - Returns: The literal text, quoted where the type requires it.
    private func defaultValueText(_ literal: String, type: any EClassifier) -> String {
        guard EcoreBuiltins.isBuiltin(type) else { return Self.quoted(literal) }
        switch type.name {
        case EcoreDataType.eBoolean.rawValue where TokenClassifier.booleans.contains(literal):
            return literal
        case EcoreDataType.eInt.rawValue where Int(literal) != nil:
            return literal
        case EcoreDataType.eChar.rawValue where literal.count == 1 && literal != "'" && literal != "\\":
            return "'" + literal + "'"
        default:
            return Self.quoted(literal)
        }
    }

    /// Writes an operation.
    ///
    /// - Parameters:
    ///   - operation: The operation to write.
    ///   - outer: The scope enclosing the operation.
    ///   - first: Whether the operation is the first member of its class.
    private mutating func writeOperation(_ operation: EOperation, scope outer: TypeScope, first: Bool) {
        var scope = outer
        for parameter in operation.eTypeParameters { scope.parameters[parameter.id] = parameter.name }
        writeMemberAnnotations(operation.eAnnotations, first: first)
        var line = ""
        if !operation.unique { line += Self.modifierText(.unique, negated: true) }
        if !operation.ordered { line += Self.modifierText(.ordered, negated: true) }
        line += Keyword.op.rawValue + " "
        let parameters = typeParametersText(operation.eTypeParameters, in: scope)
        if !parameters.isEmpty { line += parameters + " " }
        if operation.eType == nil && operation.eGenericType == nil {
            line += Keyword.void.rawValue
        } else {
            line += typeText(generic: operation.eGenericType, raw: operation.eType, in: scope)
                + Self.multiplicity(operation.lowerBound, operation.upperBound)
        }
        line += " " + Self.escaped(operation.name) + "("
        line += operation.eParameters.map { parameterText($0, scope: scope) }.joined(separator: ", ") + ")"
        let exceptions = operation.eGenericExceptions.isEmpty
            ? operation.eExceptions.map { classifierName($0, in: scope) }
            : operation.eGenericExceptions.map { typeText($0, in: scope) }
        if !exceptions.isEmpty { line += " " + Keyword.throws.rawValue + " " + exceptions.joined(separator: ", ") }
        output.verbatim(line + ";")
    }

    /// Renders an operation parameter.
    ///
    /// - Parameters:
    ///   - parameter: The parameter to render.
    ///   - scope: The scope in which the parameter is written.
    /// - Returns: The parameter text.
    private mutating func parameterText(_ parameter: EParameter, scope: TypeScope) -> String {
        var text = parameter.eAnnotations.map { annotationText($0) + " " }.joined()
        if !parameter.unique { text += Self.modifierText(.unique, negated: true) }
        if !parameter.ordered { text += Self.modifierText(.ordered, negated: true) }
        text += typeText(generic: parameter.eGenericType, raw: parameter.eType, in: scope)
            + Self.multiplicity(parameter.lowerBound, parameter.upperBound)
        return text + " " + Self.escaped(parameter.name)
    }
}
