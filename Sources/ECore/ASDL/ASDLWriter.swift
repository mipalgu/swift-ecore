//
// ASDLWriter.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Writes Ecore metamodels as Zephyr ASDL descriptions.
///
/// The writer is the inverse of ``ASDLReader`` for the subset of Ecore that
/// ASDL can express, so a description read and written again is the same
/// apart from layout and comments. It writes every package as a module and:
///
/// | Ecore | ASDL |
/// |---|---|
/// | abstract class without supertypes whose subclasses in the package are concrete, have no subclasses and only that supertype | sum type; the subclasses are its constructors and the class's own features its `attributes` |
/// | concrete class without supertypes and subclasses, with features | product type; features annotated as attributes form its `attributes` clause |
/// | `EEnum` | sum of constructors without fields |
/// | containment reference or attribute | field |
/// | `[1..1]`, `[0..1]`, `[0..*]` | no quantifier, `?`, `*` |
/// | `EString`, `EInt`, `EJavaObject`, `EByteArray` | `string`, `int`, `constant`, `bytes` (or the type recorded in an annotation, such as `identifier`) |
///
/// Everything else is reported as a warning: it is either written as the
/// closest construct (for example a non-containment reference as a field, a
/// `[1..*]` feature as a sequence, or an `EBoolean` as an `int`) or left out
/// (data types, operations, subpackages, deeper inheritance, and classes
/// without features that are not constructors).
public enum ASDLWriter {
    /// The built-in ASDL types that Ecore data types are written as, unless an annotation names one.
    static let builtinNames: [String: String] = [
        EcoreDataType.eString.rawValue: "string",
        EcoreDataType.eInt.rawValue: "int",
        EcoreDataType.eBigInteger.rawValue: "int",
        EcoreDataType.eLong.rawValue: "int",
        EcoreDataType.eShort.rawValue: "int",
        EcoreDataType.eByte.rawValue: "int",
        EcoreDataType.eIntegerObject.rawValue: "int",
        EcoreDataType.eLongObject.rawValue: "int",
        EcoreDataType.eJavaObject.rawValue: "constant",
        EcoreDataType.eByteArray.rawValue: "bytes",
    ]

    /// The indentation of definitions within a module.
    static let indentation = "    "

    /// Writes packages as ASDL modules.
    ///
    /// - Parameter packages: The packages; each becomes one module, in order.
    /// - Returns: The ASDL text and warnings about everything that could not be
    ///   written exactly. Warnings have no source range; their messages name
    ///   the element concerned.
    public static func write(_ packages: [EPackage]) -> (text: String, diagnostics: [SourceDiagnostic]) {
        var writer = Writer()
        let modules = packages.map { writer.module($0) }
        return (modules.joined(separator: "\n"), writer.diagnostics)
    }

    /// The properties of an attribute or reference that writing needs.
    private struct FeatureView {
        /// The name of the feature.
        let name: String
        /// The type of the feature.
        let eType: any EClassifier
        /// The lower bound.
        let lowerBound: Int
        /// The upper bound, where `-1` is unbounded.
        let upperBound: Int
        /// The ASDL annotation of the feature, if any.
        let annotation: EAnnotation?

        /// Extracts the properties of a feature.
        ///
        /// - Parameter feature: An attribute or reference.
        init(_ feature: any EStructuralFeature) {
            if let reference = feature as? EReference {
                name = reference.name
                eType = reference.eType
                lowerBound = reference.lowerBound
                upperBound = reference.upperBound
                annotation = reference.getEAnnotation(source: ASDLSyntax.annotationSource)
            } else if let attribute = feature as? EAttribute {
                name = attribute.name
                eType = attribute.eType
                lowerBound = attribute.lowerBound
                upperBound = attribute.upperBound
                annotation = attribute.getEAnnotation(source: ASDLSyntax.annotationSource)
            } else {
                name = ""
                eType = EcorePackage.dataType(.eString) ?? EDataType(name: EcoreDataType.eString.rawValue)
                lowerBound = 0
                upperBound = 1
                annotation = nil
            }
        }
    }

    /// The state of one call of ``write(_:)``.
    private struct Writer {
        /// The warnings found so far.
        var diagnostics: [SourceDiagnostic] = []

        /// Records a warning.
        ///
        /// - Parameters:
        ///   - code: The kind of problem.
        ///   - message: A description that names the element concerned.
        mutating func warn(_ code: ASDLDiagnosticCode, _ message: String) {
            diagnostics.append(SourceDiagnostic(severity: .warning, code: code.rawValue, message: message))
        }

        /// Writes one package as a module.
        ///
        /// - Parameter package: The package.
        /// - Returns: The module text, ending with a line end.
        mutating func module(_ package: EPackage) -> String {
            let asdl = package.getEAnnotation(source: ASDLSyntax.annotationSource)
            var header = ASDLSyntax.Keyword.module + " " + package.name
            if let version = asdl?.details[ASDLSyntax.AnnotationKey.version] {
                header += " " + ASDLSyntax.Keyword.version + " \"" + escaped(version) + "\""
            }
            if let imports = asdl?.details[ASDLSyntax.AnnotationKey.imports], !imports.isEmpty {
                header += " (" + ASDLSyntax.Keyword.imports + " " + imports + ")"
            }
            for subpackage in package.eSubpackages {
                warn(.unsupportedElement, "The subpackage '\(package.name).\(subpackage.name)' is not written")
            }
            let classes = package.eClassifiers.compactMap { $0 as? EClass }
            var subclasses: [EUUID: [EClass]] = [:]
            for eClass in classes {
                for superType in eClass.eSuperTypes { subclasses[superType.id, default: []].append(eClass) }
            }
            let roots = package.eClassifiers.compactMap { $0 as? EClass }.filter(isSumRoot)
            var constructors: Set<EUUID> = []
            for root in roots { constructors.formUnion((subclasses[root.id] ?? []).map(\.id)) }
            var definitions: [String] = []
            for classifier in package.eClassifiers {
                if let eEnum = classifier as? EEnum {
                    if let text = enumeration(eEnum) { definitions.append(text) }
                    continue
                }
                guard let eClass = classifier as? EClass else {
                    warn(
                        .unsupportedElement,
                        "The data type '\(package.name).\(classifier.name)' has no ASDL counterpart and is not written")
                    continue
                }
                if constructors.contains(eClass.id) { continue }
                if isSumRoot(eClass) {
                    let members = subclasses[eClass.id] ?? []
                    if let text = sum(eClass, members: members, subclasses: subclasses, package: package) {
                        definitions.append(text)
                    }
                } else if !eClass.eSuperTypes.isEmpty || subclasses[eClass.id] != nil {
                    warn(
                        .unsupportedElement,
                        "The class '\(eClass.name)' takes part in inheritance that ASDL cannot express and is not written")
                } else if let text = product(eClass, package: package) {
                    definitions.append(text)
                }
            }
            var text = header + " {\n"
            text += definitions.joined(separator: "\n")
            text += "}\n"
            return text
        }

        /// Whether a class is written as a sum type.
        ///
        /// - Parameter eClass: The class.
        /// - Returns: `true` for an abstract class or interface without supertypes.
        func isSumRoot(_ eClass: EClass) -> Bool {
            (eClass.isAbstract || eClass.isInterface) && eClass.eSuperTypes.isEmpty
        }

        /// Writes an enumeration as a sum of constructors without fields.
        ///
        /// - Parameter eEnum: The enumeration.
        /// - Returns: The definition, or `nil` for an enumeration without literals.
        mutating func enumeration(_ eEnum: EEnum) -> String? {
            guard !eEnum.literals.isEmpty else {
                warn(.unsupportedElement, "The enumeration '\(eEnum.name)' has no literals and is not written")
                return nil
            }
            checkTypeName(eEnum.name)
            for literal in eEnum.literals { checkConstructorName(literal.name) }
            return alternatives(eEnum.name, eEnum.literals.map(\.name), attributes: nil)
        }

        /// Writes an abstract class and its subclasses as a sum type.
        ///
        /// - Parameters:
        ///   - eClass: The abstract class.
        ///   - members: Its direct subclasses in the package.
        ///   - subclasses: The direct subclasses of every class of the package.
        ///   - package: The package.
        /// - Returns: The definition, or `nil` if no subclass can be a constructor.
        mutating func sum(
            _ eClass: EClass, members: [EClass], subclasses: [EUUID: [EClass]], package: EPackage
        ) -> String? {
            operations(of: eClass)
            var written: [String] = []
            for member in members {
                guard !member.isAbstract, !member.isInterface, member.eSuperTypes.count == 1,
                    subclasses[member.id] == nil
                else {
                    warn(
                        .unsupportedElement,
                        "The subclass '\(member.name)' of '\(eClass.name)' is not a constructor ASDL can express"
                            + " (it is abstract, has other supertypes or has subclasses) and is not written")
                    continue
                }
                operations(of: member)
                checkConstructorName(member.name)
                let fields = member.eStructuralFeatures.map { field($0, owner: member, package: package) }
                written.append(member.name + (fields.isEmpty ? "" : "(" + fields.joined(separator: ", ") + ")"))
            }
            guard !written.isEmpty else {
                warn(.unsupportedElement, "The abstract class '\(eClass.name)' has no constructors and is not written")
                return nil
            }
            checkTypeName(eClass.name)
            let attributes = eClass.eStructuralFeatures.map { field($0, owner: eClass, package: package) }
            return alternatives(eClass.name, written, attributes: attributes.isEmpty ? nil : attributes)
        }

        /// Writes a concrete class as a product type.
        ///
        /// - Parameters:
        ///   - eClass: The class.
        ///   - package: The package.
        /// - Returns: The definition, or `nil` for a class without features.
        mutating func product(_ eClass: EClass, package: EPackage) -> String? {
            operations(of: eClass)
            let isAttribute: (any EStructuralFeature) -> Bool = {
                FeatureView($0).annotation?.details[ASDLSyntax.AnnotationKey.attribute] == ASDLSyntax.markerValue
            }
            let fields = eClass.eStructuralFeatures.filter { !isAttribute($0) }
            let attributes = eClass.eStructuralFeatures.filter(isAttribute)
            guard !fields.isEmpty else {
                warn(.unsupportedElement, "The class '\(eClass.name)' has no fields and is not written")
                return nil
            }
            checkTypeName(eClass.name)
            var text = indentation + eClass.name + " = (" + fields.map { field($0, owner: eClass, package: package) }
                .joined(separator: ", ") + ")"
            if !attributes.isEmpty {
                text += "\n" + indentation + String(repeating: " ", count: eClass.name.count + 1) + "  "
                    + ASDLSyntax.Keyword.attributes + " ("
                    + attributes.map { field($0, owner: eClass, package: package) }.joined(separator: ", ") + ")"
            }
            return text + "\n"
        }

        /// Lays out a sum type with one constructor per line.
        ///
        /// - Parameters:
        ///   - name: The type name.
        ///   - constructors: The constructors as written.
        ///   - attributes: The attributes as written, if any.
        /// - Returns: The definition, ending with a line end.
        func alternatives(_ name: String, _ constructors: [String], attributes: [String]?) -> String {
            let continuation = indentation + String(repeating: " ", count: name.count + 1)
            var text = indentation + name + " = " + constructors[0] + "\n"
            for constructor in constructors.dropFirst() { text += continuation + "| " + constructor + "\n" }
            if let attributes {
                text += continuation + "  " + ASDLSyntax.Keyword.attributes + " ("
                    + attributes.joined(separator: ", ") + ")\n"
            }
            return text
        }

        /// Writes a feature as a field.
        ///
        /// - Parameters:
        ///   - structural: The feature.
        ///   - owner: The class that declares it.
        ///   - package: The package being written.
        /// - Returns: The type, quantifiers and, unless generated, the name.
        mutating func field(_ structural: any EStructuralFeature, owner: EClass, package: EPackage) -> String {
            let feature = FeatureView(structural)
            let path = owner.name + "." + feature.name
            let annotation = feature.annotation
            var type: String
            if let reference = structural as? EReference {
                type = annotation?.details[ASDLSyntax.AnnotationKey.type]
                    ?? typeName(of: reference.eType, path: path, package: package)
                if !reference.containment {
                    warn(.approximatedElement, "The non-containment reference '\(path)' is written as a field, which reads back as a containment")
                }
            } else if let eEnum = feature.eType as? EEnum {
                type = typeName(of: eEnum, path: path, package: package)
            } else if let recorded = annotation?.details[ASDLSyntax.AnnotationKey.type] {
                type = recorded
            } else if let builtin = builtinNames[feature.eType.name], EcorePackage.dataType(EcoreDataType(rawValue: feature.eType.name) ?? .eString)?.id == feature.eType.id {
                type = builtin
            } else {
                type = feature.eType.name == EcoreDataType.eBoolean.rawValue ? "int" : "string"
                warn(.approximatedElement, "The type '\(feature.eType.name)' of '\(path)' has no ASDL counterpart and is written as '\(type)'")
            }
            return type + quantifiers(feature, annotation: annotation, path: path)
                + (annotation?.details[ASDLSyntax.AnnotationKey.generatedName] == ASDLSyntax.markerValue ? "" : " " + feature.name)
        }

        /// The quantifiers that express the bounds of a feature.
        ///
        /// - Parameters:
        ///   - feature: The feature.
        ///   - annotation: Its ASDL annotation, which may record quantifiers.
        ///   - path: The qualified feature name, for warnings.
        /// - Returns: Nothing for `[1..1]`, `?` for `[0..1]`, and `*` (or the
        ///   recorded combination) for unbounded features.
        mutating func quantifiers(_ feature: FeatureView, annotation: EAnnotation?, path: String) -> String {
            let recorded = annotation?.details[ASDLSyntax.AnnotationKey.quantifiers]
            switch (feature.lowerBound, feature.upperBound) {
            case (1, 1): return ""
            case (0, 1): return recorded.flatMap { $0.contains(ASDLSyntax.Symbol.sequence) ? nil : $0 } ?? ASDLSyntax.Symbol.optional
            case (0, -1): return recorded.flatMap { $0.contains(ASDLSyntax.Symbol.sequence) ? $0 : nil } ?? ASDLSyntax.Symbol.sequence
            case (_, let upper) where upper == -1 || upper > 1:
                warn(
                    .approximatedElement,
                    "The bounds [\(feature.lowerBound)..\(upper == -1 ? "*" : String(upper))] of '\(path)' are written as a sequence '*'")
                return ASDLSyntax.Symbol.sequence
            default:
                warn(.approximatedElement, "The bounds [\(feature.lowerBound)..\(feature.upperBound)] of '\(path)' are written as '?'")
                return ASDLSyntax.Symbol.optional
            }
        }

        /// The name of a classifier as a field type.
        ///
        /// - Parameters:
        ///   - classifier: The class or enumeration.
        ///   - path: The qualified feature name, for warnings.
        ///   - package: The package being written.
        /// - Returns: The name, qualified with its package when it belongs to another package.
        mutating func typeName(of classifier: any EClassifier, path: String, package: EPackage) -> String {
            if package.eClassifiers.contains(where: { $0.id == classifier.id }) { return classifier.name }
            if classifier.id == EcorePackage.metaClass(.eObject).id {
                warn(.approximatedElement, "The type 'EObject' of '\(path)' has no ASDL counterpart and is written as 'constant'")
                return "constant"
            }
            warn(.approximatedElement, "The type '\(classifier.name)' of '\(path)' belongs to another package and is written as a qualified name")
            return "external" + ASDLSyntax.Symbol.dot + classifier.name
        }

        /// Warns about the operations of a class, which ASDL cannot express.
        ///
        /// - Parameter eClass: The class.
        mutating func operations(of eClass: EClass) {
            for operation in eClass.eOperations {
                warn(.unsupportedElement, "The operation '\(eClass.name).\(operation.name)' is not written")
            }
        }

        /// Warns if a type name does not start in lower case, as CPython's ASDL parser requires.
        ///
        /// - Parameter name: The type name.
        mutating func checkTypeName(_ name: String) {
            if let first = name.first, first.isUppercase {
                warn(.approximatedElement, "The type name '\(name)' should start with a lower-case letter")
            }
        }

        /// Warns if a constructor name does not start in upper case, as CPython's ASDL parser requires.
        ///
        /// - Parameter name: The constructor name.
        mutating func checkConstructorName(_ name: String) {
            if let first = name.first, !first.isUppercase {
                warn(.approximatedElement, "The constructor name '\(name)' should start with an upper-case letter")
            }
        }

        /// Escapes the quotes and backslashes of a string literal.
        ///
        /// - Parameter text: The text.
        /// - Returns: The text with each quote and backslash preceded by a backslash.
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
    }
}
