//
// OCLinEcoreWriter.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OCL

/// Writes Ecore packages as OCLinEcore text.
///
/// The writer is the inverse of ``OCLinEcoreReader``: the OCL annotations that the reader
/// creates become invariants, bodies, conditions, initial values and derivations again, the
/// delegate and import annotations become the document's imports, and every other annotation
/// is written as an `annotation` or `documentation` block. Multiplicities and qualifiers are
/// written only where they differ from the OCLinEcore defaults, and Ecore types other than
/// those that OCL's primitive types denote are written with the `ecore` import.
///
/// Text that the writer produced reads back into the same packages, and reading then writing a
/// document in the writer's layout reproduces the text.
public enum OCLinEcoreWriter {
    /// The indentation of one nesting level.
    public static let indentation = "\t"

    /// The alias of the Ecore import that the writer adds for Ecore types.
    public static let ecoreAlias = "ecore"

    /// The URI of the Ecore import that the writer adds for Ecore types.
    public static let ecoreImportURI = EcorePackage.nsURI + "#/"

    /// Writes packages as an OCLinEcore document.
    ///
    /// - Parameter packages: The root packages.
    /// - Returns: The text, and diagnostics for elements that have no OCLinEcore form (such as
    ///   generic types) or that refer to classifiers outside the packages.
    public static func write(_ packages: [EPackage]) -> (text: String, diagnostics: [SourceDiagnostic]) {
        var writer = Writer(roots: packages)
        let body = packages.map { writer.package($0, path: [], depth: 0) }.joined(separator: "\n")
        var imports: [(alias: String, uri: String)] = []
        for package in packages {
            for annotation in package.eAnnotations where annotation.source == OCLAnnotation.importSource {
                for (alias, uri) in annotation.details where !imports.contains(where: { $0.alias == alias }) {
                    imports.append((alias, OCLTypeResolver.isEcoreURI(uri) ? ecoreImportURI : uri))
                }
            }
        }
        if writer.usesEcore, !imports.contains(where: { $0.alias == ecoreAlias }) {
            imports.insert((ecoreAlias, ecoreImportURI), at: 0)
        }
        var text = imports.map { "import \(Writer.name($0.alias)) : \(Writer.quoted($0.uri));\n" }.joined()
        if !imports.isEmpty { text += "\n" }
        return (text + body, writer.diagnostics)
    }

    /// The state of one writing pass.
    struct Writer {
        /// The vocabulary of OCLinEcore.
        typealias Syntax = OCLinEcoreSyntax

        /// The root packages being written.
        let roots: [EPackage]
        /// The diagnostics collected so far.
        var diagnostics: [SourceDiagnostic] = []
        /// Whether the output refers to the Ecore package, so that it needs an import.
        var usesEcore = false
        /// Every reference of the packages by identifier.
        var references: [EUUID: EReference] = [:]
        /// Every attribute of the packages by identifier.
        var attributes: [EUUID: EAttribute] = [:]
        /// The qualified name of every classifier by identifier.
        var classifierPaths: [EUUID: [String]] = [:]

        /// Creates a writer and indexes the packages.
        ///
        /// - Parameter roots: The root packages to write.
        init(roots: [EPackage]) {
            self.roots = roots
            for root in roots { index(root, path: []) }
        }

        /// Indexes the references, attributes and classifier names of a package and its subpackages.
        ///
        /// - Parameters:
        ///   - package: The package to index.
        ///   - path: The names of the enclosing packages.
        mutating func index(_ package: EPackage, path: [String]) {
            let packagePath = path + [package.name]
            for classifier in package.eClassifiers {
                classifierPaths[classifier.id] = packagePath + [classifier.name]
                guard let eClass = classifier as? EClass else { continue }
                for feature in eClass.eStructuralFeatures {
                    if let reference = feature as? EReference { references[reference.id] = reference }
                    if let attribute = feature as? EAttribute { attributes[attribute.id] = attribute }
                }
            }
            for subpackage in package.eSubpackages { index(subpackage, path: packagePath) }
        }

        /// Records that an element cannot be written.
        ///
        /// - Parameter message: The description of what is not written.
        mutating func note(_ message: String) {
            diagnostics.append(SourceDiagnostic(severity: .warning, code: OCLDiagnosticCode.unwritableElement, message: message))
        }

        // MARK: Lexical forms

        /// Writes a name, escaping it if it is not a simple name or is reserved.
        static func name(_ name: String) -> String {
            let utf8 = Array(name.utf8)
            let isSimple = !utf8.isEmpty && utf8.enumerated().allSatisfy { index, byte in
                (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F
                    || (index > 0 && byte >= 0x30 && byte <= 0x39)
            } && !(utf8.count > 1 && utf8[0] == 0x5F && utf8[1] == 0x27)
            if isSimple && !Syntax.escapedWords.contains(name) { return name }
            return "_" + quoted(name)
        }

        /// Writes a string literal with OCL escapes.
        static func quoted(_ value: String) -> String {
            var result = "'"
            for character in value {
                switch character {
                case "'": result += "\\'"
                case "\\": result += "\\\\"
                case "\n": result += "\\n"
                case "\r": result += "\\r"
                case "\t": result += "\\t"
                case "\u{08}": result += "\\b"
                case "\u{0C}": result += "\\f"
                default: result.append(character)
                }
            }
            return result + "'"
        }

        /// The indentation for a nesting depth.
        ///
        /// - Parameter depth: The nesting depth.
        /// - Returns: The indentation text.
        static func indent(_ depth: Int) -> String { String(repeating: OCLinEcoreWriter.indentation, count: depth) }

        /// Writes a header followed by a braced body of lines, or by `;` when there are none.
        static func block(_ header: String, _ lines: [String], depth: Int) -> String {
            let prefix = indent(depth)
            guard !lines.isEmpty else { return prefix + header + ";\n" }
            return prefix + header + "\n" + prefix + "{\n" + lines.joined() + prefix + "}\n"
        }

        // MARK: Types

        /// The text that names a classifier from within a package.
        ///
        /// - Parameters:
        ///   - classifier: The classifier, or `nil` for no type.
        ///   - lower: The lower bound of the multiplicity.
        ///   - packagePath: The path of the package that contains the reference.
        /// - Returns: The unqualified name inside the same package, otherwise the qualified name.
        mutating func typeName(_ classifier: (any EClassifier)?, lower: Int, from packagePath: [String]) -> String {
            guard let classifier else { return "OclVoid" }
            if let path = classifierPaths[classifier.id] {
                if Array(path.dropLast()) == packagePath { return Self.name(classifier.name) }
                return path.map(Self.name).joined(separator: OCLSyntax.pathSeparator)
            }
            if let builtin = EcorePackage.classifier(named: classifier.name), builtin.id == classifier.id {
                switch classifier.name {
                case EcoreDataType.eString.rawValue: return "String"
                case EcoreDataType.eBigInteger.rawValue: return "Integer"
                case EcoreDataType.eBigDecimal.rawValue: return "Real"
                case EcoreDataType.eBoolean.rawValue where lower >= 1: return "Boolean"
                case EcoreDataType.eBooleanObject.rawValue where lower < 1: return "Boolean"
                default:
                    usesEcore = true
                    return OCLinEcoreWriter.ecoreAlias + OCLSyntax.pathSeparator + classifier.name
                }
            }
            note("The classifier '\(classifier.name)' is not among the written packages")
            return Self.name(classifier.name)
        }

        /// The text of a multiplicity.
        ///
        /// - Parameters:
        ///   - lower: The lower bound.
        ///   - upper: The upper bound.
        /// - Returns: The multiplicity in brackets, which is empty for exactly one.
        static func multiplicity(lower: Int, upper: Int) -> String {
            lower == 1 && upper == 1 ? "" : OCLMultiplicity(lower: lower, upper: upper).text
        }

        /// The text of a list of qualifiers.
        ///
        /// - Parameters:
        ///   - values: Whether each qualifier is set.
        ///   - order: The order in which qualifiers are written.
        /// - Returns: The qualifiers in braces, which is empty if none differ from their defaults.
        static func qualifiers(_ values: [String: Bool], order: [String]) -> String {
            let written = order.compactMap { name -> String? in
                guard let value = values[name], value != Syntax.qualifierDefaults[name] else { return nil }
                return value ? name : Syntax.negation + name
            }
            return written.isEmpty ? "" : " { " + written.joined(separator: ", ") + " }"
        }

        // MARK: Annotations

        /// Writes the annotations that the OCL constructs have not consumed.
        mutating func annotations(_ annotations: [EAnnotation], consumed: Set<String>, depth: Int) -> [String] {
            annotations.compactMap { annotation in
                var remaining = annotation
                if annotation.source == AnnotationSource.ecore {
                    for key in consumed { remaining.details.removeValue(forKey: key) }
                    for key in OCLAnnotation.delegateKeys where consumed.contains(OCLAnnotation.pivotSource) {
                        if let value = remaining.details[key], OCLAnnotation.expressionSources.contains(value) {
                            remaining.details.removeValue(forKey: key)
                        }
                    }
                    if remaining.details.isEmpty && remaining.eAnnotations.isEmpty { return nil }
                } else if annotation.source == OCLAnnotation.importSource {
                    return nil
                } else if OCLAnnotation.expressionSources.contains(annotation.source) {
                    for key in consumed { remaining.details.removeValue(forKey: key) }
                    if remaining.details.isEmpty && remaining.eAnnotations.isEmpty { return nil }
                }
                return self.annotation(remaining, depth: depth)
            }
        }

        /// Writes an annotation.
        ///
        /// - Parameters:
        ///   - annotation: The annotation.
        ///   - depth: The nesting depth.
        /// - Returns: The text of the annotation.
        mutating func annotation(_ annotation: EAnnotation, depth: Int) -> String {
            let prefix = Self.indent(depth)
            if annotation.source == AnnotationSource.genModel, annotation.details.count == 1,
                let text = annotation.details[AnnotationSource.GenModelKey.documentation], annotation.eAnnotations.isEmpty
            {
                return prefix + "documentation " + Self.quoted(text) + ";\n"
            }
            if !annotation.contents.isEmpty || !annotation.references.isEmpty {
                note("The contents and references of the annotation '\(annotation.source)' are not written")
            }
            var header = Syntax.annotationKeyword
            if !annotation.source.isEmpty { header += " " + Self.quoted(annotation.source) }
            if !annotation.details.isEmpty {
                header += "(" + annotation.details.map { Self.name($0.key) + " = " + Self.quoted($0.value) }.joined(separator: ", ") + ")"
            }
            let children = annotation.eAnnotations.map { self.annotation($0, depth: depth + 1) }
            return Self.block(header, children, depth: depth)
        }

        // MARK: Packages and classifiers

        /// Writes a package and everything inside it.
        ///
        /// - Parameters:
        ///   - package: The package.
        ///   - path: The names of the enclosing packages.
        ///   - depth: The nesting depth.
        /// - Returns: The text of the package.
        mutating func package(_ package: EPackage, path: [String], depth: Int) -> String {
            let packagePath = path + [package.name]
            var header = Syntax.packageKeyword + " " + Self.name(package.name)
            if !package.nsPrefix.isEmpty { header += " : " + Self.name(package.nsPrefix) }
            if !package.nsURI.isEmpty { header += " = " + Self.quoted(package.nsURI) }
            var lines = annotations(package.eAnnotations, consumed: [OCLAnnotation.pivotSource], depth: depth + 1)
            lines += package.eSubpackages.map { self.package($0, path: packagePath, depth: depth + 1) }
            lines += package.eClassifiers.map { classifier($0, packagePath: packagePath, depth: depth + 1) }
            return Self.block(header, lines, depth: depth)
        }

        /// Writes a classifier.
        ///
        /// - Parameters:
        ///   - classifier: The classifier.
        ///   - packagePath: The path of the enclosing package.
        ///   - depth: The nesting depth.
        /// - Returns: The text of the classifier.
        mutating func classifier(_ classifier: any EClassifier, packagePath: [String], depth: Int) -> String {
            switch classifier {
            case let eClass as EClass: return self.eClass(eClass, packagePath: packagePath, depth: depth)
            case let eEnum as EEnum: return enumeration(eEnum, depth: depth)
            case let dataType as EDataType: return self.dataType(dataType, depth: depth)
            default:
                note("The classifier '\(classifier.name)' has no OCLinEcore form")
                return ""
            }
        }

        /// Writes the invariants of an element.
        ///
        /// - Parameters:
        ///   - element: The element.
        ///   - depth: The nesting depth.
        /// - Returns: The lines of the invariants.
        mutating func invariants(of element: some EModelElement, depth: Int) -> [String] {
            OCLConstraintAnnotations.invariants(of: element).map { invariant in
                var header = Self.indent(depth) + Syntax.invariantKeyword
                if let name = invariant.name {
                    header += " " + Self.name(name)
                    if let message = invariant.message { header += "(" + message + ")" }
                }
                return header + ": " + invariant.expression + ";\n"
            }
        }

        /// The keys that invariants consume from the annotations of a classifier.
        func invariantKeys(of element: some EModelElement) -> Set<String> {
            let keys = Set(OCLConstraintAnnotations.expressionDetails(of: element).keys)
            let names = OCLConstraintAnnotations.constraintNames(of: element)
            return names.allSatisfy(keys.contains) ? keys.union([AnnotationSource.EcoreKey.constraints]) : keys
        }

        /// Writes a class and its members.
        ///
        /// - Parameters:
        ///   - eClass: The class.
        ///   - packagePath: The path of the enclosing package.
        ///   - depth: The nesting depth.
        /// - Returns: The text of the class.
        mutating func eClass(_ eClass: EClass, packagePath: [String], depth: Int) -> String {
            var header = (eClass.isAbstract ? Syntax.abstractKeyword + " " : "") + Syntax.classKeyword + " " + Self.name(eClass.name)
            if !eClass.eTypeParameters.isEmpty || !eClass.eGenericSuperTypes.isEmpty {
                note("The type parameters and generic supertypes of '\(eClass.name)' are not written")
            }
            if !eClass.eSuperTypes.isEmpty {
                header += " " + Syntax.extendsKeyword + " "
                    + eClass.eSuperTypes.map { typeName($0, lower: 1, from: packagePath) }.joined(separator: ", ")
            }
            if let instanceClassName = eClass.instanceClassName { header += " : " + Self.quoted(instanceClassName) }
            if eClass.isInterface { header += " { " + Syntax.interfaceKeyword + " }" }
            var lines = annotations(eClass.eAnnotations, consumed: invariantKeys(of: eClass), depth: depth + 1)
            lines += invariants(of: eClass, depth: depth + 1)
            for feature in eClass.eStructuralFeatures {
                if let attribute = feature as? EAttribute { lines.append(self.attribute(attribute, packagePath: packagePath, depth: depth + 1)) }
                if let reference = feature as? EReference { lines.append(self.reference(reference, packagePath: packagePath, depth: depth + 1)) }
            }
            lines += eClass.eOperations.map { operation($0, packagePath: packagePath, depth: depth + 1) }
            return Self.block(header, lines, depth: depth)
        }

        /// Writes a datatype.
        ///
        /// - Parameters:
        ///   - dataType: The datatype.
        ///   - depth: The nesting depth.
        /// - Returns: The text of the datatype.
        mutating func dataType(_ dataType: EDataType, depth: Int) -> String {
            var header = Syntax.datatypeKeyword + " " + Self.name(dataType.name)
            if let instanceClassName = dataType.instanceClassName { header += " : " + Self.quoted(instanceClassName) }
            if dataType.serialisable { header += " { " + Syntax.serializableKeyword + " }" }
            var lines = annotations(dataType.eAnnotations, consumed: invariantKeys(of: dataType), depth: depth + 1)
            lines += invariants(of: dataType, depth: depth + 1)
            return Self.block(header, lines, depth: depth)
        }

        /// Writes an enumeration and its literals.
        ///
        /// - Parameters:
        ///   - eEnum: The enumeration.
        ///   - depth: The nesting depth.
        /// - Returns: The text of the enumeration.
        mutating func enumeration(_ eEnum: EEnum, depth: Int) -> String {
            var header = Syntax.enumKeyword + " " + Self.name(eEnum.name)
            if let instanceClassName = eEnum.instanceClassName { header += " : " + Self.quoted(instanceClassName) }
            if eEnum.serialisable { header += " { " + Syntax.serializableKeyword + " }" }
            var lines = annotations(eEnum.eAnnotations, consumed: invariantKeys(of: eEnum), depth: depth + 1)
            lines += invariants(of: eEnum, depth: depth + 1)
            var next = 0
            for literal in eEnum.literals {
                var line = Syntax.literalKeyword + " " + Self.name(literal.name)
                if let text = literal.literal { line += " : " + Self.quoted(text) }
                if literal.value != next { line += " = \(literal.value)" }
                next = literal.value + 1
                lines.append(Self.block(line, annotations(literal.eAnnotations, consumed: [], depth: depth + 2), depth: depth + 1))
            }
            return Self.block(header, lines, depth: depth)
        }

        // MARK: Features and operations

        /// Writes the body lines of a feature: annotations, initial value and derivation.
        mutating func featureBody(_ feature: some EModelElement, depth: Int) -> [String] {
            var lines = annotations(feature.eAnnotations, consumed: [OCLAnnotation.initialKey, OCLAnnotation.derivationKey], depth: depth)
            if let initial = OCLConstraintAnnotations.initial(of: feature) {
                lines.append(Self.indent(depth) + Syntax.initialKeyword + ": " + initial + ";\n")
            }
            if let derivation = OCLConstraintAnnotations.derivation(of: feature) {
                lines.append(Self.indent(depth) + Syntax.derivationKeyword + ": " + derivation + ";\n")
            }
            return lines
        }

        /// Writes an attribute.
        ///
        /// - Parameters:
        ///   - attribute: The attribute.
        ///   - packagePath: The path of the enclosing package.
        ///   - depth: The nesting depth.
        /// - Returns: The text of the attribute.
        mutating func attribute(_ attribute: EAttribute, packagePath: [String], depth: Int) -> String {
            var header = Syntax.attributeKeyword + " " + Self.name(attribute.name) + " : "
                + typeName(attribute.eType, lower: attribute.lowerBound, from: packagePath)
                + Self.multiplicity(lower: attribute.lowerBound, upper: attribute.upperBound)
            if let value = attribute.defaultValueLiteral { header += " = " + Self.quoted(value) }
            header += Self.qualifiers(
                [Syntax.derived: attribute.derived, Syntax.id: attribute.isID, Syntax.ordered: attribute.ordered,
                 Syntax.readonly: !attribute.changeable, Syntax.transient: attribute.transient, Syntax.unique: attribute.unique,
                 Syntax.unsettable: attribute.unsettable, Syntax.volatile: attribute.volatile],
                order: Syntax.attributeQualifiers)
            return Self.block(header, featureBody(attribute, depth: depth + 1), depth: depth)
        }

        /// Writes a reference.
        ///
        /// - Parameters:
        ///   - reference: The reference.
        ///   - packagePath: The path of the enclosing package.
        ///   - depth: The nesting depth.
        /// - Returns: The text of the reference.
        mutating func reference(_ reference: EReference, packagePath: [String], depth: Int) -> String {
            var header = Syntax.propertyKeyword + " " + Self.name(reference.name)
            if let opposite = reference.opposite {
                if let name = references[opposite]?.name {
                    header += "#" + Self.name(name)
                } else {
                    note("The opposite of '\(reference.name)' is not among the written packages")
                }
            }
            header += " : " + typeName(reference.eType, lower: reference.lowerBound, from: packagePath)
                + Self.multiplicity(lower: reference.lowerBound, upper: reference.upperBound)
            if let value = reference.defaultValueLiteral { header += " = " + Self.quoted(value) }
            header += Self.qualifiers(
                [Syntax.composes: reference.containment, Syntax.derived: reference.derived, Syntax.ordered: reference.ordered,
                 Syntax.readonly: !reference.changeable, Syntax.resolve: reference.resolveProxies, Syntax.transient: reference.transient,
                 Syntax.unique: reference.unique, Syntax.unsettable: reference.unsettable, Syntax.volatile: reference.volatile],
                order: Syntax.referenceQualifiers)
            var lines = featureBody(reference, depth: depth + 1)
            let keys = reference.eKeys.compactMap { attributes[$0]?.name }
            if !keys.isEmpty {
                lines.append(Self.indent(depth + 1) + Syntax.keyKeyword + " " + keys.map(Self.name).joined(separator: ", ") + ";\n")
            }
            return Self.block(header, lines, depth: depth)
        }

        /// Writes an operation with its parameters and conditions.
        ///
        /// - Parameters:
        ///   - operation: The operation.
        ///   - packagePath: The path of the enclosing package.
        ///   - depth: The nesting depth.
        /// - Returns: The text of the operation.
        mutating func operation(_ operation: EOperation, packagePath: [String], depth: Int) -> String {
            if !operation.eTypeParameters.isEmpty { note("The type parameters of '\(operation.name)' are not written") }
            let parameters = operation.eParameters.map { parameter -> String in
                var text = Self.name(parameter.name)
                if let type = parameter.eType {
                    text += " : " + typeName(type, lower: parameter.lowerBound, from: packagePath)
                        + Self.multiplicity(lower: parameter.lowerBound, upper: parameter.upperBound)
                }
                text += Self.qualifiers([Syntax.ordered: parameter.ordered, Syntax.unique: parameter.unique], order: Syntax.parameterQualifiers)
                if !parameter.eAnnotations.isEmpty {
                    note("The annotations of the parameter '\(parameter.name)' are not written")
                }
                return text
            }
            var header = Syntax.operationKeyword + " " + Self.name(operation.name) + "(" + parameters.joined(separator: ", ") + ")"
            if let type = operation.eType {
                header += " : " + typeName(type, lower: operation.lowerBound, from: packagePath)
                    + Self.multiplicity(lower: operation.lowerBound, upper: operation.upperBound)
            }
            if !operation.eExceptions.isEmpty {
                header += " " + Syntax.throwsKeyword + " "
                    + operation.eExceptions.map { typeName($0, lower: 1, from: packagePath) }.joined(separator: ", ")
            }
            if operation.eType != nil {
                header += Self.qualifiers([Syntax.ordered: operation.ordered, Syntax.unique: operation.unique], order: Syntax.operationQualifiers)
            }
            let preconditions = OCLConstraintAnnotations.preconditions(of: operation)
            let postconditions = OCLConstraintAnnotations.postconditions(of: operation)
            let body = OCLConstraintAnnotations.body(of: operation)
            var consumed = Set(OCLConstraintAnnotations.expressionDetails(of: operation).keys.filter { key in
                key == OCLAnnotation.bodyKey || key == OCLAnnotation.preconditionKey || key == OCLAnnotation.postconditionKey
                    || key.hasPrefix(OCLAnnotation.preconditionKey + OCLAnnotation.conditionNameSeparator)
                    || key.hasPrefix(OCLAnnotation.postconditionKey + OCLAnnotation.conditionNameSeparator)
            })
            consumed.insert(OCLAnnotation.bodyKey)
            var lines = annotations(operation.eAnnotations, consumed: consumed, depth: depth + 1)
            let prefix = Self.indent(depth + 1)
            /// Writes a precondition, postcondition or body line.
            ///
            /// - Parameters:
            ///   - keyword: The keyword that introduces the condition.
            ///   - condition: The condition.
            /// - Returns: The line of text.
            func condition(_ keyword: String, _ condition: OCLConstraintText) -> String {
                var line = prefix + keyword
                if let name = condition.name {
                    line += " " + Self.name(name)
                    if let message = condition.message { line += "(" + message + ")" }
                }
                return line + ": " + condition.expression + ";\n"
            }
            lines += preconditions.map { condition(Syntax.preconditionKeyword, $0) }
            if let body { lines.append(prefix + Syntax.bodyKeyword + ": " + body + ";\n") }
            lines += postconditions.map { condition(Syntax.postconditionKeyword, $0) }
            return Self.block(header, lines, depth: depth)
        }
    }
}
