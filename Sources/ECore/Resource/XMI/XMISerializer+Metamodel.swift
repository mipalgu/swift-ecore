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
    /// fragments such as `#//Person` and `#//Member/familyFather`. Attributes equal to their
    /// defaults are omitted.
    ///
    /// A reference to a classifier that the package does not define is written with the URI
    /// of the document that defines it: `shared.ecore#//Audited`, relative to the document
    /// that the package was loaded from (see ``EPackage/origin``), or the Ecore namespace URI
    /// for the classes and data types of Ecore itself (`http://www.eclipse.org/emf/2002/Ecore#//EString`).
    /// As EMF does, a type that lies in another document is preceded by the kind of the
    /// classifier (`ecore:EDataType`, `ecore:EClass`, or `ecore:EEnum`).
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
        var writer = MetamodelWriter(
            root: package, documentURI: package.origin?.documentURI, lineWidth: options.lineWidth)
        return writer.document()
    }

    /// Serialises a metamodel package for a document at a given location.
    ///
    /// References to classifiers of other documents are written relative to the location,
    /// as they must be for the document to be loadable from there. See
    /// ``serialize(_:)`` for the layout of the document.
    ///
    /// - Parameters:
    ///   - package: The root package to serialise.
    ///   - documentURL: The location that the document will have.
    /// - Returns: The `.ecore` document text.
    public func serialize(_ package: EPackage, relativeTo documentURL: URL) -> String {
        var writer = MetamodelWriter(
            root: package, documentURI: documentURL.absoluteString, lineWidth: options.lineWidth)
        return writer.document()
    }

    /// Serialises a metamodel package to an `.ecore` file.
    ///
    /// References to classifiers of other documents are written relative to the file.
    ///
    /// - Parameters:
    ///   - package: The root package to serialise.
    ///   - url: The location of the file to write.
    /// - Throws: An error if the file cannot be written.
    public func serialize(_ package: EPackage, to url: URL) throws {
        try serialize(package, relativeTo: url).write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Writer

/// The text written so far, with the width of its last line.
private struct WrittenText {
    /// The text.
    private(set) var text = ""

    /// The number of UTF-16 code units on the last line.
    private(set) var column = 0

    /// Appends text, keeping track of the width of the last line.
    mutating func append(_ addition: String) {
        text += addition
        if let newline = addition.lastIndex(of: "\n") {
            column = addition[addition.index(after: newline)...].utf16.count
        } else {
            column += addition.utf16.count
        }
    }

    /// Appends text, keeping track of the width of the last line.
    static func += (output: inout WrittenText, addition: String) {
        output.append(addition)
    }
}

/// Writes a native metamodel as `.ecore` XMI text.
private struct MetamodelWriter {
    /// The number of spaces by which a continued attribute line is indented further than its element.
    private static let continuationIndent = 4

    /// The number of spaces of indentation per level of nesting.
    private static let indentWidth = 2

    /// How a reference to a classifier is qualified when it points into another document.
    private enum Expected {
        /// The declared type is abstract, so a target in another document is preceded by its kind.
        case abstractType
        /// The declared type is the target's own kind, so no qualifier is written.
        case exactType
    }

    /// The XML schema-instance attribute carrying an element's metaclass.
    private let typeAttribute = XMIAttribute.xsiType.rawValue

    /// The fragment paths of the elements of the root package, by identifier.
    private var paths: [EUUID: String] = [:]

    private let root: EPackage
    private let documentURI: String?
    private let lineWidth: Int?
    private var output = WrittenText()

    /// The depth of the element whose attributes are being written.
    private var elementDepth = 0

    init(root: EPackage, documentURI: String?, lineWidth: Int?) {
        self.root = root
        self.documentURI = documentURI
        self.lineWidth = lineWidth
        indexPaths(of: root, prefix: "//")
    }

    // MARK: Fragment paths

    /// Records the name-based fragment path of every element that a reference can name.
    private mutating func indexPaths(of package: EPackage, prefix: String) {
        for classifier in package.eClassifiers {
            let path = prefix + classifier.name
            paths[classifier.id] = path
            if let eClass = classifier as? EClass {
                for feature in eClass.eStructuralFeatures {
                    paths[feature.id] = path + "/" + feature.name
                }
                for operation in eClass.eOperations {
                    let operationPath = path + "/" + operation.name
                    paths[operation.id] = operationPath
                    for parameter in operation.eParameters {
                        paths[parameter.id] = operationPath + "/" + parameter.name
                    }
                }
            } else if let eEnum = classifier as? EEnum {
                for literal in eEnum.literals {
                    paths[literal.id] = path + "/" + literal.name
                }
            }
        }
        for subpackage in package.eSubpackages {
            paths[subpackage.id] = prefix + subpackage.name
            indexPaths(of: subpackage, prefix: prefix + subpackage.name + "/")
        }
    }

    /// The URI text of a document, relative to the document being written where possible.
    private func relativeURI(_ uri: String) -> String {
        guard let documentURI else { return uri }
        return URIReference.relativise(uri, against: documentURI)
    }

    /// The kind qualifier of a classifier, as in `ecore:EDataType`.
    private func qualifier(of classifier: any EClassifier) -> String {
        let kind: EcoreClassifier
        switch classifier {
        case is EEnum: kind = .eEnum
        case is EDataType: kind = .eDataType
        default: kind = .eClass
        }
        return "\(ecorePrefixed(kind.rawValue)) "
    }

    /// Whether a classifier that is not part of the written package is named like a class or
    /// data type of Ecore itself.
    private func namesEcoreBuiltIn(_ classifier: any EClassifier) -> Bool {
        if root.origin?.externalReferences[classifier.id] != nil { return false }
        if classifier is EClass { return EcoreClassifier(rawValue: classifier.name) != nil }
        return EcoreDataType(rawValue: classifier.name) != nil
    }

    /// The reference text for a classifier.
    ///
    /// - Parameters:
    ///   - classifier: The classifier to refer to.
    ///   - expected: Whether a target in another document is preceded by its kind.
    private func reference(to classifier: any EClassifier, expecting expected: Expected = .abstractType) -> String {
        if let path = paths[classifier.id] {
            return "#" + path
        }
        let location: String
        if EcorePackage.classifier(id: classifier.id) != nil || namesEcoreBuiltIn(classifier) {
            location = "\(EcoreURI.ecoreNamespace.rawValue)#//\(classifier.name)"
        } else if let proxy = root.origin?.externalReferences[classifier.id] {
            let fragment = proxy.fragment.hasPrefix("#") ? String(proxy.fragment.dropFirst()) : proxy.fragment
            location = "\(relativeURI(proxy.uri))#\(fragment)"
        } else {
            return "#//" + classifier.name
        }
        return (expected == .abstractType ? qualifier(of: classifier) : "") + location
    }

    // MARK: Document

    mutating func document() -> String {
        output = WrittenText()
        output += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        let metaclass = EcorePackage.metaClass(.ePackage).name
        elementDepth = 0
        output += "<\(ecorePrefixed(metaclass))"
        let declarations = [
            (XMIAttribute.xmiVersion.rawValue, "2.0"),
            (XMLNamespace.prefixed("xmi"), EcoreURI.xmiNamespace.rawValue),
            (XMLNamespace.prefixed("xsi"), EcoreURI.xsiNamespace.rawValue),
            (XMLNamespace.prefixed(EcorePackage.nsPrefix), EcoreURI.ecoreNamespace.rawValue),
        ]
        guard lineWidth != nil else {
            for (name, value) in declarations { rawAttribute(name, value) }
            writePackageAttributes(root)
            output += ">\n"
            return finish(metaclass)
        }

        // The package's own attributes are laid out as if the declarations were absent; the
        // declarations are laid out after them and a line break follows if they ran long.
        let tagColumn = output.column
        for (name, value) in declarations { rawAttribute(name, value) }
        let remaining = packageAttributeLayout(startingAt: tagColumn)
        if output.column > (lineWidth ?? Int.max) {
            output += "\n" + String(repeating: " ", count: Self.continuationIndent - 1)
        }
        output += remaining
        output += ">\n"
        return finish(metaclass)
    }

    /// Completes the document after its root start tag.
    private mutating func finish(_ metaclass: String) -> String {
        writePackageContents(root, depth: 1)
        output += "</\(ecorePrefixed(metaclass))>\n"
        return output.text
    }

    /// Lays out the attributes of the root package as they would follow the start tag name.
    ///
    /// - Parameter column: The width of the line when the start tag name has been written.
    /// - Returns: The attribute text, each attribute preceded by a space or a line break.
    private mutating func packageAttributeLayout(startingAt column: Int) -> String {
        let saved = output
        output = WrittenText()
        output += String(repeating: " ", count: column)
        writePackageAttributes(root)
        let laidOut = String(output.text.dropFirst(column))
        output = saved
        return laidOut
    }

    private func ecorePrefixed(_ name: String) -> String {
        "\(EcorePackage.nsPrefix):\(name)"
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
            openTag(tag, depth: depth)
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
        openTag(tag, depth: depth, type: .eClass)
        attribute(EcoreFeatureName.name, eClass.name)
        if let instanceClassName = eClass.instanceClassName {
            attribute(EcoreFeatureName.instanceClassName, instanceClassName)
        }
        if eClass.isAbstract { attribute(EcoreFeatureName.abstract, true) }
        if eClass.isInterface { attribute(EcoreFeatureName.interface, true) }
        if !eClass.eSuperTypes.isEmpty {
            attribute(
                EcoreFeatureName.eSuperTypes,
                eClass.eSuperTypes.map { reference(to: $0, expecting: .exactType) }.joined(separator: " "))
        }
        if eClass.eAnnotations.isEmpty && eClass.eStructuralFeatures.isEmpty
            && eClass.eOperations.isEmpty
        {
            output += "/>\n"
            return
        }
        output += ">\n"
        writeAnnotations(eClass.eAnnotations, depth: depth + 1)
        for operation in eClass.eOperations {
            writeOperation(operation, depth: depth + 1)
        }
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

    private mutating func writeOperation(_ operation: EOperation, depth: Int) {
        let tag = EcoreFeatureName.eOperations.rawValue
        openTag(tag, depth: depth)
        writeTypedElementAttributes(operation)
        if !operation.eExceptions.isEmpty {
            attribute(
                EcoreFeatureName.eExceptions,
                operation.eExceptions.map { reference(to: $0) }.joined(separator: " "))
        }
        if operation.eAnnotations.isEmpty && operation.eParameters.isEmpty {
            output += "/>\n"
            return
        }
        output += ">\n"
        writeAnnotations(operation.eAnnotations, depth: depth + 1)
        for parameter in operation.eParameters {
            let parameterTag = EcoreFeatureName.eParameters.rawValue
            openTag(parameterTag, depth: depth + 1)
            writeTypedElementAttributes(parameter)
            if parameter.eAnnotations.isEmpty {
                output += "/>\n"
            } else {
                output += ">\n"
                writeAnnotations(parameter.eAnnotations, depth: depth + 2)
                indent(depth + 1)
                output += "</\(parameterTag)>\n"
            }
        }
        indent(depth)
        output += "</\(tag)>\n"
    }

    /// Writes the name, multiplicity, and type that operations and parameters share.
    private mutating func writeTypedElementAttributes<Element: ETypedElement & ENamedElement>(
        _ element: Element
    ) {
        attribute(EcoreFeatureName.name, element.name)
        if !element.ordered { attribute(EcoreFeatureName.ordered, false) }
        if !element.unique { attribute(EcoreFeatureName.unique, false) }
        if element.lowerBound != 0 { attribute(EcoreFeatureName.lowerBound, element.lowerBound) }
        if element.upperBound != 1 { attribute(EcoreFeatureName.upperBound, element.upperBound) }
        if let type = element.eType { attribute(EcoreFeatureName.eType, reference(to: type)) }
    }

    private mutating func writeEnum(_ eEnum: EEnum, depth: Int) {
        let tag = EcoreFeatureName.eClassifiers.rawValue
        openTag(tag, depth: depth, type: .eEnum)
        attribute(EcoreFeatureName.name, eEnum.name)
        if eEnum.eAnnotations.isEmpty && eEnum.literals.isEmpty {
            output += "/>\n"
            return
        }
        output += ">\n"
        writeAnnotations(eEnum.eAnnotations, depth: depth + 1)
        for literal in eEnum.literals {
            openTag(EcoreFeatureName.eLiterals.rawValue, depth: depth + 1)
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
        openTag(tag, depth: depth, type: .eDataType)
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
        openTag(tag, depth: depth, type: .eAttribute)
        writeCommonFeatureAttributes(attribute)
        if attribute.isID { self.attribute(EcoreFeatureName.iD, true) }
        finishFeature(tag: tag, annotations: attribute.eAnnotations, depth: depth)
    }

    private mutating func writeReference(_ reference: EReference, depth: Int) {
        let tag = EcoreFeatureName.eStructuralFeatures.rawValue
        openTag(tag, depth: depth, type: .eReference)
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

    /// The reference text of an annotation's references, or `nil` if none can be written.
    private func referenceText(of annotation: EAnnotation) -> String? {
        let texts = annotation.references.compactMap { reference -> String? in
            switch reference {
            case .local(let identifier):
                return paths[identifier].map { "#" + $0 }
            case .external(let proxy):
                let fragment = proxy.fragment.hasPrefix("#") ? String(proxy.fragment.dropFirst()) : proxy.fragment
                if proxy.uri.isEmpty || proxy.uri == documentURI { return "#" + fragment }
                return "\(relativeURI(proxy.uri))#\(fragment)"
            }
        }
        return texts.isEmpty ? nil : texts.joined(separator: String(CrossReferenceSyntax.listSeparator))
    }

    private mutating func writeAnnotations(_ annotations: [EAnnotation], depth: Int) {
        for annotation in annotations {
            let tag = EcoreFeatureName.eAnnotations.rawValue
            openTag(tag, depth: depth)
            if !annotation.source.isEmpty { attribute(EcoreFeatureName.source, annotation.source) }
            if let references = referenceText(of: annotation) {
                attribute(EcoreFeatureName.references, references)
            }
            let entries = annotation.detailEntries
            if entries.isEmpty && annotation.eAnnotations.isEmpty && annotation.contents.isEmpty {
                output += "/>\n"
                continue
            }
            output += ">\n"
            writeAnnotations(annotation.eAnnotations, depth: depth + 1)
            for entry in entries {
                openTag(EcoreFeatureName.details.rawValue, depth: depth + 1)
                attribute(EcoreFeatureName.key, entry.key)
                attribute(EcoreFeatureName.value, entry.value)
                output += "/>\n"
            }
            for content in annotation.contents { writeContent(content, depth: depth + 1) }
            indent(depth)
            output += "</\(tag)>\n"
        }
    }

    /// Writes an object that an annotation contains.
    ///
    /// The object is written with the metaclass in `xsi:type` and its single-valued
    /// primitive attributes. Objects that the content itself contains are not written.
    private mutating func writeContent(_ content: any EObject, depth: Int) {
        openTag(EcoreFeatureName.contents.rawValue, depth: depth)
        if let metaclass = content.eClass as? EClass {
            let qualified = EcoreClassifier(rawValue: metaclass.name) != nil
                ? ecorePrefixed(metaclass.name) : metaclass.name
            rawAttribute(typeAttribute, qualified)
            for attribute in Self.attributes(of: metaclass) where !attribute.transient {
                guard let value = content.eGet(attribute), !(value is EUUID) else { continue }
                switch value {
                case let text as String: rawAttribute(attribute.name, text)
                case let flag as Bool: rawAttribute(attribute.name, BooleanString.toString(flag))
                case let number as Int: rawAttribute(attribute.name, String(number))
                default: break
                }
            }
        }
        output += "/>\n"
    }

    /// The attributes of a class with those of its supertypes first, as EMF lists features.
    private static func attributes(of eClass: EClass) -> [EAttribute] {
        var seen = Set<EUUID>()
        var result: [EAttribute] = []
        func collect(_ current: EClass) {
            for superType in current.eSuperTypes { collect(superType) }
            for case let attribute as EAttribute in current.eStructuralFeatures
            where seen.insert(attribute.id).inserted {
                result.append(attribute)
            }
        }
        collect(eClass)
        return result
    }

    // MARK: Text output

    /// Writes the indentation of an element line.
    private mutating func indent(_ depth: Int) {
        output += String(repeating: " ", count: depth * Self.indentWidth)
    }

    /// Starts an element: its indentation, name, and optionally its metaclass.
    private mutating func openTag(_ tag: String, depth: Int, type: EcoreClassifier? = nil) {
        indent(depth)
        elementDepth = depth
        output += "<\(tag)"
        if let type { rawAttribute(typeAttribute, ecorePrefixed(type.rawValue)) }
    }

    /// Writes an attribute, starting a new line first if the current line is already too wide.
    private mutating func rawAttribute(_ name: String, _ value: String) {
        if let lineWidth, output.column > lineWidth {
            output += "\n" + String(repeating: " ", count: elementDepth * Self.indentWidth + Self.continuationIndent)
        } else {
            output += " "
        }
        output += "\(name)=\"\(XMISerializer.escapeAttribute(value))\""
    }

    private mutating func attribute(_ name: EcoreFeatureName, _ value: String) {
        rawAttribute(name.rawValue, value)
    }

    private mutating func attribute(_ name: EcoreFeatureName, _ value: Bool) {
        rawAttribute(name.rawValue, BooleanString.toString(value))
    }

    private mutating func attribute(_ name: EcoreFeatureName, _ value: Int) {
        rawAttribute(name.rawValue, String(value))
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
