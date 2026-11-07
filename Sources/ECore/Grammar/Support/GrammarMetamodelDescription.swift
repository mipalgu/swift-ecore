//
// GrammarMetamodelDescription.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// Describes metamodels as stable text, for comparing them structurally.
///
/// The description leaves out identifiers, so two metamodels built separately
/// from equivalent sources describe the same. Annotations are included only
/// when asked for, so that importers of different notations can be compared.
enum GrammarMetamodelDescription {
    /// Describes packages, one line per element.
    ///
    /// - Parameters:
    ///   - packages: The packages to describe.
    ///   - includeAnnotations: Whether annotation details are part of the description.
    /// - Returns: The description, with classifiers in package order and features in class order.
    static func describe(_ packages: [EPackage], includeAnnotations: Bool = true) -> String {
        var lines: [String] = []
        for package in packages {
            lines.append("package \(package.name) \(package.nsURI) \(package.nsPrefix)")
            if includeAnnotations { lines += annotationLines(package.eAnnotations, indent: "  ") }
            for classifier in package.eClassifiers { lines += describe(classifier, includeAnnotations: includeAnnotations) }
        }
        return lines.joined(separator: "\n")
    }

    /// Describes one classifier.
    ///
    /// - Parameters:
    ///   - classifier: The classifier.
    ///   - includeAnnotations: Whether annotation details are part of the description.
    /// - Returns: The lines of the classifier and its members.
    static func describe(_ classifier: any EClassifier, includeAnnotations: Bool = true) -> [String] {
        var lines: [String] = []
        if let eClass = classifier as? EClass {
            let flags = (eClass.isInterface ? "interface " : eClass.isAbstract ? "abstract " : "")
            let supers = eClass.eSuperTypes.map(\.name).joined(separator: ", ")
            lines.append("  \(flags)class \(eClass.name)" + (supers.isEmpty ? "" : " extends \(supers)"))
            if includeAnnotations { lines += annotationLines(eClass.eAnnotations, indent: "    ") }
            for feature in eClass.eStructuralFeatures { lines += describe(feature, includeAnnotations: includeAnnotations) }
        } else if let eEnum = classifier as? EEnum {
            lines.append("  enum \(eEnum.name) { " + eEnum.literals.map { literal in
                literal.name + (literal.literal.map { $0 == literal.name ? "" : "='\($0)'" } ?? "")
            }.joined(separator: ", ") + " }")
        } else if let dataType = classifier as? EDataType {
            lines.append("  datatype \(dataType.name)" + (dataType.instanceClassName.map { " : \($0)" } ?? ""))
        }
        return lines
    }

    /// Describes one feature.
    ///
    /// - Parameters:
    ///   - feature: An attribute or reference.
    ///   - includeAnnotations: Whether annotation details are part of the description.
    /// - Returns: The line of the feature and those of its annotations.
    static func describe(_ feature: any EStructuralFeature, includeAnnotations: Bool = true) -> [String] {
        if let reference = feature as? EReference {
            let kind = reference.containment ? "contains" : "refers"
            return ["    \(kind) \(reference.name) : \(reference.eType.name)\(bounds(reference.lowerBound, reference.upperBound))"]
                + (includeAnnotations ? annotationLines(reference.eAnnotations, indent: "      ") : [])
        }
        if let attribute = feature as? EAttribute {
            let defaultValue = attribute.defaultValueLiteral.map { " = \($0)" } ?? ""
            return ["    attribute \(attribute.name) : \(attribute.eType.name)\(bounds(attribute.lowerBound, attribute.upperBound))\(defaultValue)"]
                + (includeAnnotations ? annotationLines(attribute.eAnnotations, indent: "      ") : [])
        }
        return ["    feature \(feature.name)"]
    }

    /// Writes bounds as Ecore editors show them.
    ///
    /// - Parameters:
    ///   - lower: The lower bound.
    ///   - upper: The upper bound, where `-1` is unbounded.
    /// - Returns: Text such as `[0..*]`.
    static func bounds(_ lower: Int, _ upper: Int) -> String {
        "[\(lower)..\(upper == -1 ? "*" : String(upper))]"
    }

    /// Describes annotations.
    ///
    /// - Parameters:
    ///   - annotations: The annotations.
    ///   - indent: The indentation of each line.
    /// - Returns: One line per annotation with its details in order.
    static func annotationLines(_ annotations: [EAnnotation], indent: String) -> [String] {
        annotations.map { annotation in
            indent + "@" + annotation.source + " " + annotation.details.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        }
    }
}
