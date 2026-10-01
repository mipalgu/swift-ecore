//
// XMISerializer+Metamodel.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

extension XMISerializer {
    /// Serialises a metamodel package to an `.ecore` XMI string.
    ///
    /// The package, its classifiers, structural features, literals, annotations, and nested
    /// packages are written as an `ecore:EPackage` document in the form that `XMIParser`
    /// reads and that other Ecore tools accept: contained elements are nested with an
    /// `xsi:type`, and references to classifiers and features are written as name-based
    /// fragments such as `#//Person` and `#//Member/familyFather`. References to the built-in
    /// Ecore data types and classes that the package does not define are written with the
    /// Ecore namespace URI. Attributes equal to their defaults are omitted.
    ///
    /// The same method serialises the reflective Ecore metamodel itself:
    ///
    /// ```swift
    /// let text = XMISerializer().serialize(EcorePackage.instance)
    /// ```
    ///
    /// - Parameter package: The root package to serialise.
    /// - Returns: The `.ecore` document text.
    public func serialize(_ package: EPackage) -> String {
        var writer = MetamodelWriter(root: package)
        return writer.document()
    }

    /// Serialises a metamodel package to an `.ecore` file.
    ///
    /// - Parameters:
    ///   - package: The root package to serialise.
    ///   - url: The location of the file to write.
    /// - Throws: An error if the file cannot be written.
    public func serialize(_ package: EPackage, to url: URL) throws {
        try serialize(package).write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Writer

/// Writes a native metamodel as `.ecore` XMI text.
private struct MetamodelWriter {
    /// The XML schema-instance attribute carrying an element's metaclass.
    private let typeAttribute = XMIAttribute.xsiType.rawValue

    /// The fragment paths of the elements of the root package, by identifier.
    private var paths: [EUUID: String] = [:]

    private let root: EPackage
    private var output = ""

    init(root: EPackage) {
        self.root = root
        indexPaths(of: root, prefix: "//")
    }

    // MARK: Fragment paths

    /// Records the name-based fragment path of every classifier, feature, and subpackage.
    private mutating func indexPaths(of package: EPackage, prefix: String) {
        for classifier in package.eClassifiers {
            let path = prefix + classifier.name
            paths[classifier.id] = path
            if let eClass = classifier as? EClass {
                for feature in eClass.eStructuralFeatures {
                    paths[feature.id] = path + "/" + feature.name
                }
            }
        }
        for subpackage in package.eSubpackages {
            paths[subpackage.id] = prefix + subpackage.name
            indexPaths(of: subpackage, prefix: prefix + subpackage.name + "/")
        }
    }

    /// The reference text for a classifier.
    private func reference(to classifier: any EClassifier) -> String {
        if let path = paths[classifier.id] {
            return "#" + path
        }
        if classifier is EClass, EcoreClassifier(rawValue: classifier.name) != nil {
            return EcoreURI.ecoreClassPrefix.rawValue + classifier.name
        }
        if !(classifier is EClass), EcoreDataType(rawValue: classifier.name) != nil {
            return EcoreURI.ecoreDataTypePrefix.rawValue + classifier.name
        }
        return "#//" + classifier.name
    }

    // MARK: Document

    mutating func document() -> String {
        output = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        let metaclass = EcorePackage.metaClass(.ePackage).name
        output += "<\(ecorePrefixed(metaclass))"
        output += " \(XMIAttribute.xmiVersion.rawValue)=\"2.0\""
        output += " \(XMLNamespace.prefixed("xmi"))=\"\(EcoreURI.xmiNamespace.rawValue)\""
        output += " \(XMLNamespace.prefixed("xsi"))=\"\(EcoreURI.xsiNamespace.rawValue)\""
        output += " \(XMLNamespace.prefixed(EcorePackage.nsPrefix))=\"\(EcoreURI.ecoreNamespace.rawValue)\""
        writePackageAttributes(root)
        output += ">\n"
        writePackageContents(root, depth: 1)
        output += "</\(ecorePrefixed(metaclass))>\n"
        return output
    }

    private func ecorePrefixed(_ name: String) -> String {
        "\(EcorePackage.nsPrefix):\(name)"
    }

    private func typed(_ classifier: EcoreClassifier) -> String {
        "\(typeAttribute)=\"\(ecorePrefixed(classifier.rawValue))\""
    }

    // MARK: Packages

    private mutating func writePackageAttributes(_ package: EPackage) {
        attribute(EcoreFeatureName.name, package.name)
        attribute(EcoreFeatureName.nsURI, package.nsURI)
        attribute(EcoreFeatureName.nsPrefix, package.nsPrefix)
    }

    private mutating func writePackageContents(_ package: EPackage, depth: Int) {
        writeAnnotations(package.eAnnotations, depth: depth)
        for classifier in package.eClassifiers {
            if let eClass = classifier as? EClass {
                writeClass(eClass, depth: depth)
            } else if let eEnum = classifier as? EEnum {
                writeEnum(eEnum, depth: depth)
            } else if let dataType = classifier as? EDataType {
                writeDataType(dataType, depth: depth)
            }
        }
        for subpackage in package.eSubpackages {
            let tag = EcoreFeatureName.eSubpackages.rawValue
            indent(depth)
            output += "<\(tag)"
            writePackageAttributes(subpackage)
            if subpackage.eAnnotations.isEmpty && subpackage.eClassifiers.isEmpty
                && subpackage.eSubpackages.isEmpty
            {
                output += "/>\n"
            } else {
                output += ">\n"
                writePackageContents(subpackage, depth: depth + 1)
                indent(depth)
                output += "</\(tag)>\n"
            }
        }
    }

    // MARK: Classifiers

    private mutating func writeClass(_ eClass: EClass, depth: Int) {
        let tag = EcoreFeatureName.eClassifiers.rawValue
        indent(depth)
        output += "<\(tag) \(typed(.eClass))"
        attribute(EcoreFeatureName.name, eClass.name)
        if eClass.isAbstract { attribute(EcoreFeatureName.abstract, true) }
        if eClass.isInterface { attribute(EcoreFeatureName.interface, true) }
        if !eClass.eSuperTypes.isEmpty {
            attribute(
                EcoreFeatureName.eSuperTypes,
                eClass.eSuperTypes.map { reference(to: $0) }.joined(separator: " "))
        }
        if eClass.eAnnotations.isEmpty && eClass.eStructuralFeatures.isEmpty {
            output += "/>\n"
            return
        }
        output += ">\n"
        writeAnnotations(eClass.eAnnotations, depth: depth + 1)
        for feature in eClass.eStructuralFeatures {
            if let attribute = feature as? EAttribute {
                writeAttribute(attribute, depth: depth + 1)
            } else if let reference = feature as? EReference {
                writeReference(reference, depth: depth + 1)
            }
        }
        indent(depth)
        output += "</\(tag)>\n"
    }

    private mutating func writeEnum(_ eEnum: EEnum, depth: Int) {
        let tag = EcoreFeatureName.eClassifiers.rawValue
        indent(depth)
        output += "<\(tag) \(typed(.eEnum))"
        attribute(EcoreFeatureName.name, eEnum.name)
        if eEnum.eAnnotations.isEmpty && eEnum.literals.isEmpty {
            output += "/>\n"
            return
        }
        output += ">\n"
        writeAnnotations(eEnum.eAnnotations, depth: depth + 1)
        for literal in eEnum.literals {
            indent(depth + 1)
            output += "<\(EcoreFeatureName.eLiterals.rawValue)"
            attribute(EcoreFeatureName.name, literal.name)
            if literal.value != 0 { attribute(EcoreFeatureName.value, literal.value) }
            if let text = literal.literal, text != literal.name {
                attribute(EcoreFeatureName.literal, text)
            }
            if literal.eAnnotations.isEmpty {
                output += "/>\n"
            } else {
                output += ">\n"
                writeAnnotations(literal.eAnnotations, depth: depth + 2)
                indent(depth + 1)
                output += "</\(EcoreFeatureName.eLiterals.rawValue)>\n"
            }
        }
        indent(depth)
        output += "</\(tag)>\n"
    }

    private mutating func writeDataType(_ dataType: EDataType, depth: Int) {
        let tag = EcoreFeatureName.eClassifiers.rawValue
        indent(depth)
        output += "<\(tag) \(typed(.eDataType))"
        attribute(EcoreFeatureName.name, dataType.name)
        if let name = dataType.instanceClassName {
            attribute(EcoreFeatureName.instanceClassName, name)
        }
        if !dataType.serialisable { attribute(EcoreFeatureName.serializable, false) }
        if dataType.eAnnotations.isEmpty {
            output += "/>\n"
        } else {
            output += ">\n"
            writeAnnotations(dataType.eAnnotations, depth: depth + 1)
            indent(depth)
            output += "</\(tag)>\n"
        }
    }

    // MARK: Features

    private mutating func writeAttribute(_ attribute: EAttribute, depth: Int) {
        let tag = EcoreFeatureName.eStructuralFeatures.rawValue
        indent(depth)
        output += "<\(tag) \(typed(.eAttribute))"
        writeCommonFeatureAttributes(attribute)
        if attribute.isID { self.attribute(EcoreFeatureName.iD, true) }
        finishFeature(tag: tag, annotations: attribute.eAnnotations, depth: depth)
    }

    private mutating func writeReference(_ reference: EReference, depth: Int) {
        let tag = EcoreFeatureName.eStructuralFeatures.rawValue
        indent(depth)
        output += "<\(tag) \(typed(.eReference))"
        writeCommonFeatureAttributes(reference)
        if reference.containment { attribute(EcoreFeatureName.containment, true) }
        if !reference.resolveProxies { attribute(EcoreFeatureName.resolveProxies, false) }
        if let opposite = reference.opposite, let path = paths[opposite] {
            attribute(EcoreFeatureName.eOpposite, "#" + path)
        }
        finishFeature(tag: tag, annotations: reference.eAnnotations, depth: depth)
    }

    private mutating func finishFeature(tag: String, annotations: [EAnnotation], depth: Int) {
        if annotations.isEmpty {
            output += "/>\n"
        } else {
            output += ">\n"
            writeAnnotations(annotations, depth: depth + 1)
            indent(depth)
            output += "</\(tag)>\n"
        }
    }

    private mutating func writeCommonFeatureAttributes<Feature: ReflectiveFeatureAttributes>(
        _ feature: Feature
    ) {
        attribute(EcoreFeatureName.name, feature.name)
        if !feature.ordered { attribute(EcoreFeatureName.ordered, false) }
        if !feature.unique { attribute(EcoreFeatureName.unique, false) }
        if feature.lowerBound != 0 { attribute(EcoreFeatureName.lowerBound, feature.lowerBound) }
        if feature.upperBound != 1 { attribute(EcoreFeatureName.upperBound, feature.upperBound) }
        attribute(EcoreFeatureName.eType, reference(to: feature.eType))
        if !feature.changeable { attribute(EcoreFeatureName.changeable, false) }
        if feature.volatile { attribute(EcoreFeatureName.volatile, true) }
        if feature.transient { attribute(EcoreFeatureName.transient, true) }
        if let literal = feature.defaultValueLiteral {
            attribute(EcoreFeatureName.defaultValueLiteral, literal)
        }
        if feature.unsettable { attribute(EcoreFeatureName.unsettable, true) }
        if feature.derived { attribute(EcoreFeatureName.derived, true) }
    }

    // MARK: Annotations

    private mutating func writeAnnotations(_ annotations: [EAnnotation], depth: Int) {
        for annotation in annotations {
            let tag = EcoreFeatureName.eAnnotations.rawValue
            indent(depth)
            output += "<\(tag)"
            attribute(EcoreFeatureName.source, annotation.source)
            let entries = annotation.detailEntries
            if entries.isEmpty {
                output += "/>\n"
                continue
            }
            output += ">\n"
            for entry in entries {
                indent(depth + 1)
                output += "<\(EcoreFeatureName.details.rawValue)"
                attribute(EcoreFeatureName.key, entry.key)
                attribute(EcoreFeatureName.value, entry.value)
                output += "/>\n"
            }
            indent(depth)
            output += "</\(tag)>\n"
        }
    }

    // MARK: Text output

    private mutating func indent(_ depth: Int) {
        output += String(repeating: "  ", count: depth)
    }

    private mutating func attribute(_ name: EcoreFeatureName, _ value: String) {
        output += " \(name.rawValue)=\"\(Self.escaped(value))\""
    }

    private mutating func attribute(_ name: EcoreFeatureName, _ value: Bool) {
        output += " \(name.rawValue)=\"\(BooleanString.toString(value))\""
    }

    private mutating func attribute(_ name: EcoreFeatureName, _ value: Int) {
        output += " \(name.rawValue)=\"\(value)\""
    }

    /// Escapes the characters that are significant in XML attribute values.
    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// The properties that attributes and references share when written as structural features.
private protocol ReflectiveFeatureAttributes {
    var name: String { get }
    var ordered: Bool { get }
    var unique: Bool { get }
    var lowerBound: Int { get }
    var upperBound: Int { get }
    var eType: any EClassifier { get }
    var changeable: Bool { get }
    var volatile: Bool { get }
    var transient: Bool { get }
    var defaultValueLiteral: String? { get }
    var unsettable: Bool { get }
    var derived: Bool { get }
}

extension EAttribute: ReflectiveFeatureAttributes {}
extension EReference: ReflectiveFeatureAttributes {}
