//
// XcoreWriter.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import OrderedCollections
import Foundation

/// Writes native Ecore packages as Xcore text with their structure and preserved bodies.
///
/// The writer produces one document for one package: its annotations, the qualified
/// package name (prefixed with the GenModel base package), imports of the Ecore
/// classifiers that have no Java name, annotation directives, then the classifiers in
/// model order. Body text kept under ``XcoreLanguage/namespaceURI`` is written back as
/// operation bodies, feature accessors and data type `create` and `convert` bodies.
/// Built-in Ecore data types are written with their Java names, such as `String` or `int`.
///
/// Properties that Xcore has no keyword for are written as details of `@Ecore`, which
/// Xcore applies to the element, so that a round trip stays lossless. Anything that
/// cannot be expressed at all is reported as a warning with the code
/// ``XcoreDiagnosticCode/lossyWrite``. Uniqueness of single-valued elements, which has no
/// meaning, follows the Xcore defaults.
public enum XcoreWriter {
    /// Writes packages as an Xcore document.
    ///
    /// Xcore documents hold one package without subpackages, so only the first package
    /// is written and its subpackages and any further packages are reported as lost.
    ///
    /// - Parameter packages: The packages to write.
    /// - Returns: The Xcore text and the diagnostics about information it cannot express.
    public static func write(_ packages: [EPackage]) -> (text: String, diagnostics: [SourceDiagnostic]) {
        var writer = XcoreTextWriter(packages: packages)
        return writer.write()
    }
}

/// The state of writing one Xcore document.
struct XcoreTextWriter {
    /// The keywords of the Xcore notation.
    private typealias Keyword = XcoreLanguage.Keyword
    /// The Ecore attributes that the `@Ecore` annotation can set.
    private typealias EcoreAttribute = XcoreLanguage.EcoreAttribute
    /// The keys under which Xbase bodies are kept in annotations.
    private typealias BodyKey = XcoreLanguage.BodyKey

    /// The packages to write.
    private let packages: [EPackage]
    /// The factory that creates diagnostics.
    private let factory = DiagnosticFactory(namespace: XcoreLanguage.diagnosticNamespace)
    /// The names given to classifiers, qualified where necessary.
    private var naming = ClassifierNaming(packages: [])
    /// The qualified name of the package that is being written.
    private var packageKey = ""
    /// The diagnostics found while writing.
    private var diagnostics: [SourceDiagnostic] = []
    /// The names of the features of the packages, by identifier, used to write opposites and keys.
    private var featureNames: [EUUID: String] = [:]
    /// The annotation aliases, by annotation source.
    private var aliases: [String: String] = [:]
    /// The annotation directives in declaration order.
    private var directives: [(alias: String, source: String)] = []
    /// The qualified names of the classifiers that are imported.
    private var imports: [String] = []

    /// Creates a writer for packages.
    ///
    /// - Parameter packages: The packages to write; only the first is written.
    init(packages: [EPackage]) {
        self.packages = packages
    }

    /// Records that part of the model cannot be written.
    ///
    /// - Parameter message: The description of what is lost.
    private mutating func lose(_ message: String) {
        diagnostics.append(factory.warning(.lossyWrite, message, at: nil))
    }

    /// Writes the document.
    ///
    /// - Returns: The text and the diagnostics.
    mutating func write() -> (text: String, diagnostics: [SourceDiagnostic]) {
        guard let package = packages.first else {
            lose("There is no package to write")
            return ("", diagnostics)
        }
        if packages.count > 1 {
            lose("An Xcore document holds one package; \(packages.count - 1) further package(s) are not written")
        }
        if !package.eSubpackages.isEmpty {
            lose("Xcore has no subpackages; \(package.eSubpackages.count) subpackage(s) of '\(package.name)' are not written")
        }
        if package.name.isEmpty { lose("A package without a name is written as '_'") }
        var annotations = package.eAnnotations
        var basePackage: String?
        if let index = annotations.firstIndex(where: { $0.source == AnnotationSource.genModel }),
            let base = annotations[index].details[XcoreLanguage.basePackageKey]
        {
            basePackage = base.isEmpty ? nil : base
            annotations[index].details.removeValue(forKey: XcoreLanguage.basePackageKey)
            if annotations[index].details.isEmpty && annotations[index].references.isEmpty
                && annotations[index].contents.isEmpty && annotations[index].eAnnotations.isEmpty
            {
                annotations.remove(at: index)
            }
        }
        if let index = annotations.firstIndex(where: { $0.source == XcoreLanguage.namespaceURI }) {
            for (alias, source) in annotations[index].details { declare(alias: alias, source: source) }
            annotations.remove(at: index)
        }
        let simpleName = package.name.isEmpty ? "_" : package.name
        let qualified = basePackage.map { $0 + "." + simpleName } ?? simpleName
        packageKey = qualified
        naming = ClassifierNaming(packages: [package]) { _ in qualified }
        for case let eClass as EClass in package.eClassifiers {
            for feature in eClass.eStructuralFeatures { featureNames[feature.id] = feature.name }
        }
        for (alias, source) in XcoreLanguage.annotationAliases { aliases[source] = aliases[source] ?? alias }

        for name in ExternalClassifiers.names(in: [package], naming: naming) {
            if name.contains(".") {
                imports.append(name)
            } else {
                lose("The classifier '\(name)' is not declared by the written package and has no qualified name to import")
            }
        }
        var body = IndentedText()
        for classifier in package.eClassifiers {
            body.separate()
            writeClassifier(classifier, into: &body)
        }

        var header = IndentedText()
        var packageAttributes: [(EcoreAttribute, String)] = []
        let defaultURI = qualified == XcoreLanguage.ecorePackageName ? EcorePackage.nsURI : qualified
        if package.nsURI != defaultURI { packageAttributes.append((.nsURI, package.nsURI)) }
        if package.nsPrefix != XcoreLanguage.defaultPrefix(for: simpleName) {
            packageAttributes.append((.nsPrefix, package.nsPrefix))
        }
        writeAnnotations(annotations, attributes: packageAttributes, into: &header)
        header.line(Keyword.package.rawValue + " " + Self.escapedQualified(qualified))
        if !imports.isEmpty || !directives.isEmpty { header.line() }
        for name in imports { header.line(Keyword.import.rawValue + " " + Self.escapedQualified(name)) }
        for directive in directives {
            header.line(
                Keyword.annotation.rawValue + " " + StringEscapes.quoted(directive.source) + " " + Keyword.as.rawValue
                    + " " + Self.escaped(directive.alias))
        }
        var text = header.text
        if !body.lines.isEmpty { text += "\n" + body.text }
        return (text, diagnostics)
    }

    // MARK: Names

    /// Escapes a name that is a keyword.
    ///
    /// - Parameter name: The name to escape.
    /// - Returns: The name, prefixed with the escape character if it is a keyword.
    private static func escaped(_ name: String) -> String {
        XcoreLanguage.keywords.contains(name) ? String(XcoreLanguage.escapeCharacter) + name : name
    }

    /// Escapes the keyword segments of a qualified name.
    ///
    /// - Parameter name: The dot-separated name.
    /// - Returns: The name with keyword segments escaped.
    private static func escapedQualified(_ name: String) -> String {
        name.split(separator: ".", omittingEmptySubsequences: false).map { escaped(String($0)) }.joined(separator: ".")
    }

    /// Returns whether text forms an identifier.
    ///
    /// - Parameter text: The text to test.
    /// - Returns: `true` if the text is a valid identifier.
    private static func isIdentifier(_ text: Substring) -> Bool {
        guard let first = text.first, first.isLetter || first == "_" || first == "$" else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
    }

    /// Returns whether text forms a dot-separated qualified name.
    ///
    /// - Parameter text: The text to test.
    /// - Returns: `true` if every segment is an identifier.
    private static func isQualifiedName(_ text: String) -> Bool {
        let segments = text.split(separator: ".", omittingEmptySubsequences: false)
        return !segments.isEmpty && segments.allSatisfy { isIdentifier($0) }
    }

    /// Whether a text reads back unchanged as the Java type reference after `wraps`.
    private static func isTypeReference(_ text: String) -> Bool {
        var core = Substring(text)
        while core.hasSuffix("[]") { core = core.dropLast(2) }
        guard let open = core.firstIndex(of: "<") else { return isQualifiedName(String(core)) }
        guard core.last == ">", isQualifiedName(String(core[..<open])) else { return false }
        let result = XcoreReader.parse("package p class C wraps \(text) {}")
        guard let eClass = result.packages.first?.eClassifiers.first as? EClass, !result.hasErrors else { return false }
        return (eClass.instanceTypeName ?? eClass.instanceClassName) == text
    }

    // MARK: Annotations

    /// Declares an annotation directive for an alias.
    ///
    /// - Parameters:
    ///   - alias: The alias to declare.
    ///   - source: The annotation source that the alias stands for.
    private mutating func declare(alias: String, source: String) {
        guard aliases[source] == nil else { return }
        aliases[source] = alias
        directives.append((alias, source))
    }

    /// The alias of an annotation source, declaring a new one if needed.
    private mutating func alias(for source: String) -> String {
        if let known = aliases[source] { return known }
        let base = source.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).last.map(String.init) ?? ""
        var candidate = base.isEmpty || !(base.first?.isLetter ?? false)
            ? "Annotation" : base.prefix(1).uppercased() + base.dropFirst()
        let used = Set(aliases.values)
        var suffix = 1
        let stem = candidate
        while used.contains(candidate) || XcoreLanguage.keywords.contains(candidate) {
            suffix += 1
            candidate = stem + String(suffix)
        }
        declare(alias: candidate, source: source)
        diagnostics.append(SourceDiagnostic(
            severity: .information, code: factory.code(.lossyWrite),
            message: "The annotation source '\(source)' is written with a new directive for the alias '\(candidate)'"))
        return candidate
    }

    /// Renders an annotation as Xcore text.
    ///
    /// - Parameters:
    ///   - source: The annotation source.
    ///   - details: The key and value pairs of the annotation.
    /// - Returns: The annotation text.
    private mutating func annotationText(_ source: String, details: [(String, String)]) -> String {
        var text = "@" + Self.escaped(alias(for: source))
        guard !details.isEmpty else { return text }
        var written: [String] = []
        for (key, value) in details {
            guard Self.isQualifiedName(key) else {
                lose("The annotation detail '\(key)' of '\(source)' is not a qualified name and is not written")
                continue
            }
            written.append(Self.escapedQualified(key) + "=" + StringEscapes.quoted(value))
        }
        if !written.isEmpty { text += "(" + written.joined(separator: ", ") + ")" }
        return text
    }

    /// Writes the annotations of an element, adding Ecore attributes that Xcore has no keyword for.
    ///
    /// - Parameters:
    ///   - annotations: The annotations of the element.
    ///   - attributes: The Ecore attributes to write as details of `@Ecore`.
    ///   - output: The text to write to.
    private mutating func writeAnnotations(
        _ annotations: [EAnnotation], attributes: [(EcoreAttribute, String)] = [], into output: inout IndentedText
    ) {
        for line in annotationLines(annotations, attributes: attributes) { output.line(line) }
    }

    /// The body text kept in the Xcore annotation of an element, by key.
    private static func bodies(in annotations: [EAnnotation]) -> [BodyKey: String] {
        var result: [BodyKey: String] = [:]
        for annotation in annotations where annotation.source == XcoreLanguage.namespaceURI {
            for (key, value) in annotation.details {
                if let bodyKey = BodyKey(rawValue: key) { result[bodyKey] = value }
            }
        }
        return result
    }

    /// The annotation lines of an element, without the body text, which is written in place.
    private mutating func annotationLines(
        _ annotations: [EAnnotation], attributes: [(EcoreAttribute, String)] = []
    ) -> [String] {
        var lines: [String] = []
        var wroteEcore = false
        var seenPredefined: Set<String> = []
        let predefined = Set(XcoreLanguage.annotationAliases.map(\.source))
        let attributeDetails = attributes.map { ($0.0.rawValue, $0.1) }
        for annotation in annotations {
            if !annotation.references.isEmpty || !annotation.contents.isEmpty || !annotation.eAnnotations.isEmpty {
                lose("The references, contents and nested annotations of the annotation '\(annotation.source)' are not written")
            }
            var details = annotation.details.map { ($0.key, $0.value) }
            if annotation.source == XcoreLanguage.namespaceURI {
                details = details.filter { BodyKey(rawValue: $0.0) == nil }
                if details.isEmpty { continue }
            }
            if predefined.contains(annotation.source), !seenPredefined.insert(annotation.source).inserted {
                lose("Xcore merges the annotations with source '\(annotation.source)' of an element into one")
            }
            if annotation.source == AnnotationSource.ecore {
                for (key, _) in details where EcoreAttribute(rawValue: key) != nil {
                    lose("The Ecore annotation detail '\(key)' would be read as an attribute of the element")
                }
                details = attributeDetails + details
                wroteEcore = true
            }
            lines.append(annotationText(annotation.source, details: details))
        }
        if !wroteEcore && !attributeDetails.isEmpty {
            lines.insert(annotationText(AnnotationSource.ecore, details: attributeDetails), at: 0)
        }
        return lines
    }

    // MARK: Types

    /// The type parameters that are visible while writing a type.
    private struct TypeScope {
        /// The names of the type parameters in scope, by identifier.
        var parameters: [EUUID: String] = [:]
        /// The names that the type parameters in scope shadow.
        var shadowing: Set<String> { Set(parameters.values) }
    }

    /// Returns the name to use for a classifier.
    ///
    /// - Parameters:
    ///   - classifier: The classifier to name.
    ///   - scope: The type parameters in scope.
    /// - Returns: The escaped, possibly qualified name.
    private mutating func classifierName(_ classifier: any EClassifier, in scope: TypeScope) -> String {
        if let local = naming.name(of: classifier, from: packageKey, shadowing: scope.shadowing) {
            return Self.escapedQualified(local)
        }
        guard EcoreBuiltins.isBuiltin(classifier) else { return Self.escapedQualified(classifier.name) }
        if let java = XcoreLanguage.javaTypes.first(where: { $0.classifier == classifier.name }) {
            return naming.externalName([java.simple, java.qualified], from: packageKey, shadowing: scope.shadowing)
                ?? java.qualified
        }
        let qualified = XcoreLanguage.ecorePackageName + "." + classifier.name
        let chosen = naming.externalName([classifier.name, qualified], from: packageKey, shadowing: scope.shadowing)
            ?? qualified
        if chosen == classifier.name, !imports.contains(qualified) { imports.append(qualified) }
        return chosen
    }

    /// Renders a generic type.
    ///
    /// - Parameters:
    ///   - generic: The generic type.
    ///   - scope: The type parameters in scope.
    /// - Returns: The type text.
    private mutating func typeText(_ generic: EGenericType, in scope: TypeScope) -> String {
        if let parameter = generic.eTypeParameter {
            return Self.escaped(scope.parameters[parameter] ?? "Object")
        }
        guard let classifier = generic.eClassifier else {
            if let upper = generic.eUpperBound { return "? " + Keyword.extends.rawValue + " " + typeText(upper, in: scope) }
            if let lower = generic.eLowerBound { return "? " + Keyword.super.rawValue + " " + typeText(lower, in: scope) }
            return "?"
        }
        let name = classifierName(classifier, in: scope)
        guard !generic.eTypeArguments.isEmpty else { return name }
        var arguments: [String] = []
        for argument in generic.eTypeArguments { arguments.append(typeText(argument, in: scope)) }
        return name + "<" + arguments.joined(separator: ", ") + ">"
    }

    /// Renders a generic type, falling back to the raw type.
    ///
    /// - Parameters:
    ///   - generic: The generic type, if any.
    ///   - raw: The raw classifier, if any.
    ///   - scope: The type parameters in scope.
    /// - Returns: The type text, or `Object` if neither is available.
    private mutating func typeText(generic: EGenericType?, raw: (any EClassifier)?, in scope: TypeScope) -> String {
        if let generic { return typeText(generic, in: scope) }
        if let raw { return classifierName(raw, in: scope) }
        return "Object"
    }

    /// Renders a list of type parameters.
    ///
    /// - Parameters:
    ///   - parameters: The type parameters.
    ///   - scope: The type parameters in scope.
    /// - Returns: The text including angle brackets, empty if there are no parameters.
    private mutating func typeParametersText(_ parameters: [ETypeParameter], in scope: TypeScope) -> String {
        guard !parameters.isEmpty else { return "" }
        var texts: [String] = []
        for parameter in parameters {
            var text = annotationLines(parameter.eAnnotations).map { $0 + " " }.joined() + Self.escaped(parameter.name)
            if !parameter.eBounds.isEmpty {
                var bounds: [String] = []
                for bound in parameter.eBounds { bounds.append(typeText(bound, in: scope)) }
                text += " " + Keyword.extends.rawValue + " " + bounds.joined(separator: " & ")
            }
            texts.append(text)
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
        if lower == 0 && upper == MultiplicityText.unboundedValue { return "[]" }
        return OutlineBuilder.multiplicity(lower, upper)
    }

    /// Returns whether an upper bound allows more than one value.
    ///
    /// - Parameter upper: The upper bound, negative if unbounded.
    /// - Returns: `true` if many values are allowed.
    private static func isMany(_ upper: Int) -> Bool { upper > 1 || upper < 0 }

    // MARK: Classifiers

    /// Writes a classifier.
    ///
    /// - Parameters:
    ///   - classifier: The classifier to write.
    ///   - output: The text that receives the declaration.
    private mutating func writeClassifier(_ classifier: any EClassifier, into output: inout IndentedText) {
        switch classifier {
        case let eClass as EClass: writeClass(eClass, into: &output)
        case let eEnum as EEnum: writeEnum(eEnum, into: &output)
        case let dataType as EDataType: writeDataType(dataType, into: &output)
        default: lose("The classifier '\(classifier.name)' of an unknown kind is not written")
        }
    }

    /// The `wraps` clause of a classifier, or an Ecore attribute if the name cannot be written there.
    private func instanceClause(
        _ instance: String?, attributes: inout [(EcoreAttribute, String)], required: Bool
    ) -> String {
        guard let instance, !instance.isEmpty else {
            if required {
                attributes.append((.instanceClassName, ""))
                return " " + Keyword.wraps.rawValue + " Object"
            }
            return ""
        }
        if Self.isTypeReference(instance) { return " " + Keyword.wraps.rawValue + " " + instance }
        attributes.append((.instanceTypeName, instance))
        return required ? " " + Keyword.wraps.rawValue + " Object" : ""
    }

    /// Writes a class or interface.
    ///
    /// - Parameters:
    ///   - eClass: The class to write.
    ///   - output: The text that receives the declaration.
    private mutating func writeClass(_ eClass: EClass, into output: inout IndentedText) {
        var scope = TypeScope()
        for parameter in eClass.eTypeParameters { scope.parameters[parameter.id] = parameter.name }
        var attributes: [(EcoreAttribute, String)] = []
        var header: String
        if eClass.isInterface {
            header = Keyword.interface.rawValue
            if !eClass.isAbstract { attributes.append((.abstract, "false")) }
        } else {
            header = (eClass.isAbstract ? Keyword.abstract.rawValue + " " : "") + Keyword.class.rawValue
        }
        header += " " + Self.escaped(eClass.name) + typeParametersText(eClass.eTypeParameters, in: scope)
        var superTypes: [String] = []
        if eClass.eGenericSuperTypes.isEmpty {
            for superType in eClass.eSuperTypes { superTypes.append(classifierName(superType, in: scope)) }
        } else {
            for superType in eClass.eGenericSuperTypes { superTypes.append(typeText(superType, in: scope)) }
        }
        if !superTypes.isEmpty { header += " " + Keyword.extends.rawValue + " " + superTypes.joined(separator: ", ") }
        header += instanceClause(eClass.instanceTypeName ?? eClass.instanceClassName, attributes: &attributes, required: false)
        writeAnnotations(eClass.eAnnotations, attributes: attributes, into: &output)
        output.line(header + " {")
        output.indent()
        for feature in eClass.eStructuralFeatures { writeFeature(feature, owner: eClass, scope: scope, into: &output) }
        for operation in eClass.eOperations { writeOperation(operation, scope: scope, into: &output) }
        output.outdent()
        output.line("}")
    }

    /// Writes a data type.
    ///
    /// - Parameters:
    ///   - dataType: The data type to write.
    ///   - output: The text that receives the declaration.
    private mutating func writeDataType(_ dataType: EDataType, into output: inout IndentedText) {
        var attributes: [(EcoreAttribute, String)] = []
        if !dataType.serialisable { attributes.append((.serializable, "false")) }
        if dataType.defaultValueLiteral != nil { lose("The default value of data type '\(dataType.name)' is not written") }
        let scope = TypeScope()
        var line = Keyword.type.rawValue + " " + Self.escaped(dataType.name)
            + typeParametersText(dataType.eTypeParameters, in: scope)
        line += instanceClause(
            dataType.instanceTypeName ?? dataType.instanceClassName, attributes: &attributes, required: true)
        let bodies = Self.bodies(in: dataType.eAnnotations)
        writeAnnotations(dataType.eAnnotations, attributes: attributes, into: &output)
        for key in [BodyKey.create, .convert] {
            if let body = bodies[key] { line += " " + key.rawValue + " " + Self.block(body) }
        }
        output.verbatim(line)
        Self.reportUnusedBodies(bodies, allowed: [.create, .convert], element: dataType.name, writer: &self)
    }

    /// Writes an enumeration.
    ///
    /// - Parameters:
    ///   - eEnum: The enumeration to write.
    ///   - output: The text that receives the declaration.
    private mutating func writeEnum(_ eEnum: EEnum, into output: inout IndentedText) {
        var attributes: [(EcoreAttribute, String)] = []
        if !eEnum.serialisable { attributes.append((.serializable, "false")) }
        if let instance = eEnum.instanceTypeName ?? eEnum.instanceClassName { attributes.append((.instanceTypeName, instance)) }
        if !eEnum.eTypeParameters.isEmpty { lose("The type parameters of enumeration '\(eEnum.name)' are not written") }
        writeAnnotations(eEnum.eAnnotations, attributes: attributes, into: &output)
        output.line(Keyword.enum.rawValue + " " + Self.escaped(eEnum.name) + " {")
        output.indent()
        for literal in eEnum.literals {
            writeAnnotations(literal.eAnnotations, into: &output)
            var line = Self.escaped(literal.name)
            if let text = literal.literal, text != literal.name {
                line += " " + Keyword.as.rawValue + " " + StringEscapes.quoted(text)
            }
            if literal.value != 0 { line += " = " + String(literal.value) }
            output.line(line)
        }
        output.outdent()
        output.line("}")
    }

    // MARK: Members

    /// Wraps body text in braces unless it already is a block.
    private static func block(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") { return trimmed }
        return "{\n" + body + "\n}"
    }

    /// Reports bodies that have no place in Xcore.
    ///
    /// - Parameters:
    ///   - bodies: The bodies found on an element.
    ///   - allowed: The body keys that can be written.
    ///   - element: The name of the element, for diagnostics.
    ///   - writer: The writer that records the losses.
    private static func reportUnusedBodies(
        _ bodies: [BodyKey: String], allowed: Set<BodyKey>, element: String, writer: inout XcoreTextWriter
    ) {
        for key in bodies.keys.sorted(by: { $0.rawValue < $1.rawValue }) where !allowed.contains(key) {
            writer.lose("The \(key.rawValue) body of '\(element)' has no place in Xcore and is not written")
        }
    }

    /// Writes an attribute or reference.
    ///
    /// - Parameters:
    ///   - structuralFeature: The feature to write.
    ///   - owner: The class that owns the feature.
    ///   - scope: The type parameters in scope.
    ///   - output: The text that receives the declaration.
    private mutating func writeFeature(
        _ structuralFeature: any EStructuralFeature, owner: EClass, scope: TypeScope, into output: inout IndentedText
    ) {
        guard let feature = FeatureFacts(structuralFeature) else {
            lose("The feature '\(owner.name).\(structuralFeature.name)' of an unknown kind is not written")
            return
        }
        let bodies = Self.bodies(in: feature.eAnnotations)
        var attributes: [(EcoreAttribute, String)] = []
        var words: [Keyword] = []
        let hasGetter = bodies[.get] != nil
        let hasSetter = bodies[.set] != nil
        if let reference = feature.reference {
            if reference.containment {
                words.append(.contains)
                if reference.resolveProxies { words.append(.resolving) }
            } else if reference.container {
                words.append(.container)
                if !reference.resolveProxies { attributes.append((.resolveProxies, "false")) }
            } else {
                if !reference.resolveProxies { words.append(.local) }
                words.append(.refers)
            }
            if !reference.unique { attributes.append((.unique, "false")) }
            if reference.defaultValueLiteral != nil {
                lose("The default value of reference '\(owner.name).\(reference.name)' is not written")
            }
        }
        if !feature.ordered { words.append(.unordered) }
        if feature.attribute != nil && feature.unique && Self.isMany(feature.upperBound) { words.append(.unique) }
        if !feature.changeable && !(hasGetter && !hasSetter) { words.append(.readonly) }
        if feature.changeable && hasGetter && !hasSetter { attributes.append((.changeable, "true")) }
        for (flag, keyword, attribute) in [
            (feature.transient, Keyword.transient, EcoreAttribute.transient),
            (feature.volatile, .volatile, .volatile), (feature.derived, .derived, .derived),
        ] {
            if flag && !hasGetter { words.append(keyword) }
            if !flag && hasGetter { attributes.append((attribute, "false")) }
        }
        if feature.unsettable { words.append(.unsettable) }
        if feature.attribute?.isID == true { words.append(.id) }
        writeAnnotations(feature.eAnnotations, attributes: attributes, into: &output)
        var line = words.map { $0.rawValue + " " }.joined()
        line += typeText(generic: feature.eGenericType, raw: feature.eType, in: scope)
            + Self.multiplicity(feature.lowerBound, feature.upperBound) + " " + Self.escaped(feature.name)
        if let attribute = feature.attribute, let literal = attribute.defaultValueLiteral {
            line += " = " + StringEscapes.quoted(literal)
        }
        if let reference = feature.reference {
            if let opposite = reference.opposite {
                if let name = featureNames[opposite] {
                    line += " " + Keyword.opposite.rawValue + " " + Self.escaped(name)
                } else {
                    lose("The opposite of '\(owner.name).\(reference.name)' is outside the written package and is not written")
                }
            }
            let keys = reference.eKeys.compactMap { featureNames[$0] }
            if keys.count < reference.eKeys.count {
                lose("Some keys of '\(owner.name).\(reference.name)' are outside the written package and are not written")
            }
            if !keys.isEmpty { line += " " + Keyword.keys.rawValue + " " + keys.map(Self.escaped).joined(separator: ", ") }
        }
        for accessor in XcoreLanguage.accessorKeywords {
            if let key = BodyKey(rawValue: accessor.rawValue), let body = bodies[key] {
                line += " " + accessor.rawValue + " " + Self.block(body)
            }
        }
        output.verbatim(line)
        Self.reportUnusedBodies(bodies, allowed: [.get, .set, .isSet, .unset], element: owner.name + "." + feature.name, writer: &self)
    }

    /// Writes an operation.
    ///
    /// - Parameters:
    ///   - operation: The operation to write.
    ///   - outer: The type parameters of the enclosing classifier.
    ///   - output: The text that receives the declaration.
    private mutating func writeOperation(_ operation: EOperation, scope outer: TypeScope, into output: inout IndentedText) {
        var scope = outer
        for parameter in operation.eTypeParameters { scope.parameters[parameter.id] = parameter.name }
        let bodies = Self.bodies(in: operation.eAnnotations)
        writeAnnotations(operation.eAnnotations, into: &output)
        var line = Keyword.op.rawValue + " "
        if !operation.ordered { line += Keyword.unordered.rawValue + " " }
        if operation.unique && Self.isMany(operation.upperBound) { line += Keyword.unique.rawValue + " " }
        let parameters = typeParametersText(operation.eTypeParameters, in: scope)
        if !parameters.isEmpty { line += parameters + " " }
        if operation.eType == nil && operation.eGenericType == nil {
            line += Keyword.void.rawValue
        } else {
            line += typeText(generic: operation.eGenericType, raw: operation.eType, in: scope)
        }
        line += Self.multiplicity(operation.lowerBound, operation.upperBound) + " " + Self.escaped(operation.name) + "("
        var texts: [String] = []
        for parameter in operation.eParameters { texts.append(parameterText(parameter, scope: scope)) }
        line += texts.joined(separator: ", ") + ")"
        var exceptions: [String] = []
        if operation.eGenericExceptions.isEmpty {
            for exception in operation.eExceptions { exceptions.append(classifierName(exception, in: scope)) }
        } else {
            for exception in operation.eGenericExceptions { exceptions.append(typeText(exception, in: scope)) }
        }
        if !exceptions.isEmpty { line += " " + Keyword.throws.rawValue + " " + exceptions.joined(separator: ", ") }
        if let body = bodies[.body] { line += " " + Self.block(body) }
        output.verbatim(line)
        Self.reportUnusedBodies(bodies, allowed: [.body], element: operation.name, writer: &self)
    }

    /// Renders an operation parameter.
    ///
    /// - Parameters:
    ///   - parameter: The parameter to render.
    ///   - scope: The type parameters in scope.
    /// - Returns: The parameter text.
    private mutating func parameterText(_ parameter: EParameter, scope: TypeScope) -> String {
        var text = annotationLines(parameter.eAnnotations).map { $0 + " " }.joined()
        if !parameter.ordered { text += Keyword.unordered.rawValue + " " }
        if parameter.unique && Self.isMany(parameter.upperBound) { text += Keyword.unique.rawValue + " " }
        text += typeText(generic: parameter.eGenericType, raw: parameter.eType, in: scope)
            + Self.multiplicity(parameter.lowerBound, parameter.upperBound)
        return text + " " + Self.escaped(parameter.name)
    }
}
