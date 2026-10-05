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
            root: package, documentURI: package.origin?.documentURI, lineWidth: options.lineWidth,
            rootLayout: options.rootLayout)
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
            root: package, documentURI: URIReference.canonicalise(documentURL.absoluteString), lineWidth: options.lineWidth,
            rootLayout: options.rootLayout)
        return writer.document()
    }

    /// Serialises native root packages as one Ecore document.
    ///
    /// Multiple packages share an XMI wrapper and document-relative fragment paths.
    ///
    /// - Parameters:
    ///   - packages: The root packages in document order.
    ///   - documentURL: The output location, or `nil` to use the first package's origin.
    /// - Returns: The document text, ending in a newline, or an empty string when there are no roots.
    public func serialize(_ packages: [EPackage], relativeTo documentURL: URL? = nil) -> String {
        guard !packages.isEmpty else { return "" }
        let uri = documentURL.map { URIReference.canonicalise($0.absoluteString) } ?? packages.first?.origin?.documentURI
        var writer = MetamodelWriter(roots: packages, documentURI: uri,
            lineWidth: options.lineWidth, rootLayout: options.rootLayout)
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

    /// The root packages in document order.
    private let roots: [EPackage]
    private let documentURI: String?
    private let lineWidth: Int?
    private let rootLayout: XMIRootLayout
    private var output = WrittenText()

    /// The source metadata shared by the root packages.
    private var metadata: EcoreDocumentMetadata { root.origin?.documentMetadata ?? EcoreDocumentMetadata() }

    /// The declaration and leading comments of the document.
    private var documentPreamble: String {
        "<?xml version=\"1.0\" encoding=\"" + XMISerializer.escapeAttribute(metadata.encoding)
            + "\"?>\n" + metadata.leadingComments.map { $0 + "\n" }.joined()
    }

    /// The depth of the element whose attributes are being written.
    private var elementDepth = 0

    init(root: EPackage, documentURI: String?, lineWidth: Int?, rootLayout: XMIRootLayout = .standard) {
        self.init(roots: [root], documentURI: documentURI, lineWidth: lineWidth, rootLayout: rootLayout)
    }

    /// Creates a writer with a shared index for all document roots.
    ///
    /// - Parameters:
    ///   - roots: The non-empty list of root packages.
    ///   - documentURI: The URI against which references are made relative.
    ///   - lineWidth: The preferred line width, or `nil` to disable wrapping.
    ///   - rootLayout: The layout of the namespace declarations.
    init(roots: [EPackage], documentURI: String?, lineWidth: Int?, rootLayout: XMIRootLayout) {
        self.root = roots[0]
        self.roots = roots
        self.documentURI = documentURI
        self.lineWidth = lineWidth
        self.rootLayout = rootLayout
        for (index, package) in roots.enumerated() {
            paths[package.id] = roots.count == 1 ? "/" : "/\(index)"
            indexPaths(of: package, prefix: roots.count == 1 ? "//" : "/\(index)/")
        }
    }

    // MARK: Fragment paths

    /// Records the name-based fragment path of every element that a reference can name.
    private mutating func indexPaths(of package: EPackage, prefix: String) {
        for classifier in package.eClassifiers {
            let path = prefix + classifier.name
            paths[classifier.id] = path
            for parameter in typeParameters(of: classifier) {
                paths[parameter.id] = path + "/" + parameter.name
            }
            if let eClass = classifier as? EClass {
                for feature in eClass.eStructuralFeatures {
                    paths[feature.id] = path + "/" + feature.name
                }
                for operation in eClass.eOperations {
                    let operationPath = path + "/" + operation.name
                    paths[operation.id] = operationPath
                    for parameter in operation.eTypeParameters {
                        paths[parameter.id] = operationPath + "/" + parameter.name
                    }
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

    /// The reference text for the type of a typed element.
    ///
    /// A type of another document that could not be loaded is written as it was read.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the typed element.
    ///   - type: The type that the element holds.
    private func typeReference(of identifier: EUUID, type: any EClassifier) -> String {
        guard let proxy = root.origin?.unresolvedTypes[identifier] else { return reference(to: type) }
        let fragment = proxy.fragment.hasPrefix("#") ? String(proxy.fragment.dropFirst()) : proxy.fragment
        let prefix = proxy.qualifier.map { $0 + " " } ?? ""
        return prefix + relativeURI(proxy.uri) + "#" + fragment
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
        output += documentPreamble
        if roots.count > 1 { return multipleRootDocument() }
        let metaclass = EcorePackage.metaClass(.ePackage).name
        elementDepth = 0
        output += "<\(ecorePrefixed(metaclass))"
        let declarations = [
            (XMIAttribute.xmiVersion.rawValue, CrossReferenceSyntax.xmiVersion),
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

        if rootLayout == .versionFirst {
            let tag = XMIAttributeLayout(lineWidth: lineWidth, rootLayout: rootLayout).rootTag(
                name: ecorePrefixed(metaclass),
                declarations: declarations.map { "\($0.0)=\"\(XMISerializer.escapeAttribute($0.1))\"" },
                attributes: packageAttributeTexts(root))
            output = WrittenText()
            output += documentPreamble + tag + ">\n"
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

    /// Writes an XMI wrapper holding each native package.
    ///
    /// - Returns: The completed multi-root document text.
    private mutating func multipleRootDocument() -> String {
        openTag(CrossReferenceSyntax.xmiPrefix + ":" + XMIDocumentSyntax.multipleRootElement, depth: 0)
        rawAttribute(XMIAttribute.xmiVersion.rawValue, CrossReferenceSyntax.xmiVersion)
        for (prefix, uri) in [("xmi", EcoreURI.xmiNamespace.rawValue),
            ("xsi", EcoreURI.xsiNamespace.rawValue), (EcorePackage.nsPrefix, EcoreURI.ecoreNamespace.rawValue)] {
            rawAttribute(XMLNamespace.prefixed(prefix), uri)
        }
        output += ">\n"
        let tag = ecorePrefixed(EcoreClassifier.ePackage.rawValue)
        for package in roots {
            openTag(tag, depth: 1, identifier: package.id, writesIdentifier: false)
            writePackageAttributes(package)
            output += ">\n"
            writePackageContents(package, depth: 2)
            indent(1)
            output += "</\(tag)>\n"
        }
        writeComments(metadata.wrapperTrailingComments, depth: 1)
        output += "</\(CrossReferenceSyntax.xmiPrefix):\(XMIDocumentSyntax.multipleRootElement)>\n"
        writeComments(metadata.trailingComments, depth: 0)
        return output.text
    }

    /// Completes the document after its root start tag.
    private mutating func finish(_ metaclass: String) -> String {
        writePackageContents(root, depth: 1)
        output += "</\(ecorePrefixed(metaclass))>\n"
        writeComments(metadata.trailingComments, depth: 0)
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

    /// The attributes of a package as `name="value"` texts.
    private func packageAttributeTexts(_ package: EPackage) -> [String] {
        var attributes = [(EcoreFeatureName.name.rawValue, package.name), (EcoreFeatureName.nsURI.rawValue, package.nsURI),
            (EcoreFeatureName.nsPrefix.rawValue, package.nsPrefix)]
        if let identifier = metadata.xmlIdentifiers[package.id] {
            attributes.insert((XMIAttribute.xmiId.rawValue, identifier), at: 0)
        }
        return attributes.map { "\($0.0)=\"\(XMISerializer.escapeAttribute($0.1))\"" }
    }

    private mutating func writePackageAttributes(_ package: EPackage) {
        if let identifier = metadata.xmlIdentifiers[package.id] { rawAttribute(XMIAttribute.xmiId.rawValue, identifier) }
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
            openTag(tag, depth: depth, identifier: subpackage.id, writesIdentifier: false)
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
        writeComments(metadata.commentsAtEnd[package.id] ?? [], depth: depth)
    }

    // MARK: Classifiers

    private mutating func writeClass(_ eClass: EClass, depth: Int) {
        let tag = EcoreFeatureName.eClassifiers.rawValue
        openTag(tag, depth: depth, type: .eClass, identifier: eClass.id)
        attribute(EcoreFeatureName.name, eClass.name)
        if let instanceClassName = eClass.instanceClassName {
            attribute(EcoreFeatureName.instanceClassName, instanceClassName)
        }
        if let name = eClass.instanceTypeName { attribute(.instanceTypeName, name) }
        if eClass.isAbstract { attribute(EcoreFeatureName.abstract, true) }
        if eClass.isInterface { attribute(EcoreFeatureName.interface, true) }
        let genericSuperTypes = eClass.eGenericSuperTypes.filter { $0.isParameterised
            || metadata.xmlIdentifiers[$0.id] != nil || metadata.commentsBefore[$0.id] != nil || hasEndComments($0.id) }
        if genericSuperTypes.isEmpty && (!eClass.eSuperTypes.isEmpty || !retainedReferences(of: eClass.id, feature: .eSuperTypes).isEmpty) {
            attribute(
                EcoreFeatureName.eSuperTypes,
                (eClass.eSuperTypes.map { reference(to: $0, expecting: .exactType) }
                    + retainedReferences(of: eClass.id, feature: .eSuperTypes)).joined(separator: " "))
        }
        if eClass.eAnnotations.isEmpty && eClass.eStructuralFeatures.isEmpty
            && eClass.eOperations.isEmpty && eClass.eTypeParameters.isEmpty && genericSuperTypes.isEmpty && !hasEndComments(eClass.id)
        {
            output += "/>\n"
            return
        }
        output += ">\n"
        writeAnnotations(eClass.eAnnotations, depth: depth + 1)
        writeTypeParameters(eClass.eTypeParameters, depth: depth + 1)
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
        for type in eClass.eGenericSuperTypes where !genericSuperTypes.isEmpty {
            writeGenericType(type, tag: .eGenericSuperTypes, depth: depth + 1)
        }
        writeComments(metadata.commentsAtEnd[eClass.id] ?? [], depth: depth + 1)
        indent(depth)
        output += "</\(tag)>\n"
    }

    private mutating func writeOperation(_ operation: EOperation, depth: Int) {
        let tag = EcoreFeatureName.eOperations.rawValue
        openTag(tag, depth: depth, identifier: operation.id)
        writeTypedElementAttributes(operation)
        if operation.eGenericExceptions.isEmpty && (!operation.eExceptions.isEmpty || !retainedReferences(of: operation.id, feature: .eExceptions).isEmpty) {
            attribute(
                EcoreFeatureName.eExceptions,
                (operation.eExceptions.map { reference(to: $0) }
                    + retainedReferences(of: operation.id, feature: .eExceptions)).joined(separator: " "))
        }
        if operation.eAnnotations.isEmpty && operation.eParameters.isEmpty
            && operation.eTypeParameters.isEmpty && explicitGenericType(of: operation) == nil
            && operation.eGenericExceptions.isEmpty && !hasEndComments(operation.id) {
            output += "/>\n"
            return
        }
        output += ">\n"
        writeAnnotations(operation.eAnnotations, depth: depth + 1)
        if let type = explicitGenericType(of: operation) {
            writeGenericType(type, tag: .eGenericType, depth: depth + 1)
        }
        writeTypeParameters(operation.eTypeParameters, depth: depth + 1)
        for parameter in operation.eParameters {
            let parameterTag = EcoreFeatureName.eParameters.rawValue
            openTag(parameterTag, depth: depth + 1, identifier: parameter.id)
            writeTypedElementAttributes(parameter)
            if parameter.eAnnotations.isEmpty && explicitGenericType(of: parameter) == nil && !hasEndComments(parameter.id) {
                output += "/>\n"
            } else {
                output += ">\n"
                writeAnnotations(parameter.eAnnotations, depth: depth + 2)
                if let type = explicitGenericType(of: parameter) {
                    writeGenericType(type, tag: .eGenericType, depth: depth + 2)
                }
                writeComments(metadata.commentsAtEnd[parameter.id] ?? [], depth: depth + 2)
                indent(depth + 1)
                output += "</\(parameterTag)>\n"
            }
        }
        for type in operation.eGenericExceptions {
            writeGenericType(type, tag: .eGenericExceptions, depth: depth + 1)
        }
        writeComments(metadata.commentsAtEnd[operation.id] ?? [], depth: depth + 1)
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
        if explicitGenericType(of: element) == nil, let type = element.eType {
            attribute(EcoreFeatureName.eType, typeReference(of: element.id, type: type))
        }
    }

    private mutating func writeEnum(_ eEnum: EEnum, depth: Int) {
        let tag = EcoreFeatureName.eClassifiers.rawValue
        openTag(tag, depth: depth, type: .eEnum, identifier: eEnum.id)
        attribute(EcoreFeatureName.name, eEnum.name)
        if let name = eEnum.instanceClassName { attribute(.instanceClassName, name) }
        writeDataTypeFlags(identifier: eEnum.id, instanceTypeName: eEnum.instanceTypeName,
            serialisable: eEnum.serialisable)
        if eEnum.eAnnotations.isEmpty && eEnum.literals.isEmpty && eEnum.eTypeParameters.isEmpty && !hasEndComments(eEnum.id) {
            output += "/>\n"
            return
        }
        output += ">\n"
        writeAnnotations(eEnum.eAnnotations, depth: depth + 1)
        writeTypeParameters(eEnum.eTypeParameters, depth: depth + 1)
        for literal in eEnum.literals {
            openTag(EcoreFeatureName.eLiterals.rawValue, depth: depth + 1, identifier: literal.id)
            attribute(EcoreFeatureName.name, literal.name)
            if literal.value != 0 { attribute(EcoreFeatureName.value, literal.value) }
            if let text = literal.literal, text != literal.name {
                attribute(EcoreFeatureName.literal, text)
            }
            if literal.eAnnotations.isEmpty && !hasEndComments(literal.id) {
                output += "/>\n"
            } else {
                output += ">\n"
                writeAnnotations(literal.eAnnotations, depth: depth + 2)
                writeComments(metadata.commentsAtEnd[literal.id] ?? [], depth: depth + 2)
                indent(depth + 1)
                output += "</\(EcoreFeatureName.eLiterals.rawValue)>\n"
            }
        }
        writeComments(metadata.commentsAtEnd[eEnum.id] ?? [], depth: depth + 1)
        indent(depth)
        output += "</\(tag)>\n"
    }

    private mutating func writeDataType(_ dataType: EDataType, depth: Int) {
        let tag = EcoreFeatureName.eClassifiers.rawValue
        openTag(tag, depth: depth, type: .eDataType, identifier: dataType.id)
        attribute(EcoreFeatureName.name, dataType.name)
        if let name = dataType.instanceClassName {
            attribute(EcoreFeatureName.instanceClassName, name)
        }
        writeDataTypeFlags(identifier: dataType.id, instanceTypeName: dataType.instanceTypeName,
            serialisable: dataType.serialisable)
        if dataType.eAnnotations.isEmpty && dataType.eTypeParameters.isEmpty && !hasEndComments(dataType.id) {
            output += "/>\n"
        } else {
            output += ">\n"
            writeAnnotations(dataType.eAnnotations, depth: depth + 1)
            writeTypeParameters(dataType.eTypeParameters, depth: depth + 1)
            writeComments(metadata.commentsAtEnd[dataType.id] ?? [], depth: depth + 1)
            indent(depth)
            output += "</\(tag)>\n"
        }
    }

    /// Writes classifier and data type attributes in their retained source order.
    ///
    /// - Parameters:
    ///   - identifier: The classifier identity.
    ///   - instanceTypeName: The optional instance type name.
    ///   - serialisable: Whether the data type supports literal serialisation.
    private mutating func writeDataTypeFlags(identifier: EUUID, instanceTypeName: String?, serialisable: Bool) {
        if sourcePlaces(.serializable, before: .instanceTypeName, on: identifier, default: false) {
            if !serialisable { attribute(.serializable, false) }
            if let instanceTypeName { attribute(.instanceTypeName, instanceTypeName) }
        } else {
            if let instanceTypeName { attribute(.instanceTypeName, instanceTypeName) }
            if !serialisable { attribute(.serializable, false) }
        }
    }

    /// Whether a pair of attributes appeared in the given order in the source document.
    ///
    /// - Parameters:
    ///   - first: The attribute that may precede the other.
    ///   - second: The attribute that may follow the first.
    ///   - identifier: The model element holding the attributes.
    ///   - defaultOrder: The order to use when either attribute was absent.
    /// - Returns: Whether the first attribute should precede the second.
    private func sourcePlaces(_ first: EcoreFeatureName, before second: EcoreFeatureName,
        on identifier: EUUID, default defaultOrder: Bool) -> Bool {
        guard let names = metadata.attributeNames[identifier], let a = names.firstIndex(of: first.rawValue),
            let b = names.firstIndex(of: second.rawValue) else { return defaultOrder }
        return a < b
    }

    // MARK: Features

    private mutating func writeAttribute(_ attribute: EAttribute, depth: Int) {
        let tag = EcoreFeatureName.eStructuralFeatures.rawValue
        openTag(tag, depth: depth, type: .eAttribute, identifier: attribute.id)
        writeCommonFeatureAttributes(attribute)
        if attribute.isID { self.attribute(EcoreFeatureName.iD, true) }
        finishFeature(tag: tag, identifier: attribute.id, annotations: attribute.eAnnotations, generic: explicitGenericType(of: attribute), depth: depth)
    }

    private mutating func writeReference(_ reference: EReference, depth: Int) {
        let tag = EcoreFeatureName.eStructuralFeatures.rawValue
        openTag(tag, depth: depth, type: .eReference, identifier: reference.id)
        writeCommonFeatureAttributes(reference)
        if sourcePlaces(.containment, before: .resolveProxies, on: reference.id, default: false) {
            if reference.containment { attribute(.containment, true) }
            if !reference.resolveProxies { attribute(.resolveProxies, false) }
        } else {
            if !reference.resolveProxies { attribute(.resolveProxies, false) }
            if reference.containment { attribute(.containment, true) }
        }
        if let opposite = reference.opposite, let path = paths[opposite] {
            attribute(EcoreFeatureName.eOpposite, "#" + path)
        } else if let proxy = root.origin?.externalOpposites[reference.id] {
            let fragment = proxy.fragment.hasPrefix("#") ? String(proxy.fragment.dropFirst()) : proxy.fragment
            attribute(EcoreFeatureName.eOpposite, "\(relativeURI(proxy.uri))#\(fragment)")
        }
        let keys = reference.eKeys.compactMap { paths[$0].map { "#" + $0 } }
            + retainedReferences(of: reference.id, feature: .eKeys)
        if !keys.isEmpty { attribute(.eKeys, keys.joined(separator: " ")) }
        finishFeature(tag: tag, identifier: reference.id, annotations: reference.eAnnotations, generic: explicitGenericType(of: reference), depth: depth)
    }

    /// Completes a structural feature with its annotations and explicit generic type.
    ///
    /// - Parameters:
    ///   - tag: The containing feature tag.
    ///   - identifier: The feature identity used for its XML metadata.
    ///   - annotations: The feature's annotations.
    ///   - generic: The generic type, if the feature uses one.
    ///   - depth: The feature's nesting depth.
    private mutating func finishFeature(tag: String, identifier: EUUID, annotations: [EAnnotation], generic: EGenericType?, depth: Int) {
        if annotations.isEmpty && generic == nil && !hasEndComments(identifier) {
            output += "/>\n"
        } else {
            output += ">\n"
            writeAnnotations(annotations, depth: depth + 1)
            if let generic { writeGenericType(generic, tag: .eGenericType, depth: depth + 1) }
            writeComments(metadata.commentsAtEnd[identifier] ?? [], depth: depth + 1)
            indent(depth)
            output += "</\(tag)>\n"
        }
    }

    private mutating func writeCommonFeatureAttributes<Feature: ReflectiveFeatureAttributes & EObject>(
        _ feature: Feature
    ) {
        attribute(EcoreFeatureName.name, feature.name)
        if !feature.ordered { attribute(EcoreFeatureName.ordered, false) }
        if !feature.unique { attribute(EcoreFeatureName.unique, false) }
        if feature.lowerBound != 0 { attribute(EcoreFeatureName.lowerBound, feature.lowerBound) }
        if feature.upperBound != 1 { attribute(EcoreFeatureName.upperBound, feature.upperBound) }
        if explicitGenericType(of: feature) == nil {
            attribute(EcoreFeatureName.eType, typeReference(of: feature.id, type: feature.eType))
        }
        if !feature.changeable { attribute(EcoreFeatureName.changeable, false) }
        if feature.volatile { attribute(EcoreFeatureName.volatile, true) }
        if feature.transient { attribute(EcoreFeatureName.transient, true) }
        if let literal = feature.defaultValueLiteral {
            attribute(EcoreFeatureName.defaultValueLiteral, literal)
        }
        if feature.unsettable { attribute(EcoreFeatureName.unsettable, true) }
        if feature.derived { attribute(EcoreFeatureName.derived, true) }
    }

    // MARK: Generic types

    /// The type parameters declared by a classifier.
    ///
    /// - Parameter classifier: The classifier whose declarations to read.
    /// - Returns: The parameters in declaration order.
    private func typeParameters(of classifier: any EClassifier) -> [ETypeParameter] {
        switch classifier {
        case let value as EClass: return value.eTypeParameters
        case let value as EEnum: return value.eTypeParameters
        case let value as EDataType: return value.eTypeParameters
        default: return []
        }
    }

    /// The explicit generic type of a typed element.
    ///
    /// - Parameter element: The element whose type to read.
    /// - Returns: A parameterised type, or `nil` for a plain classifier reference.
    private func explicitGenericType(of element: any EObject) -> EGenericType? {
        let type: EGenericType?
        switch element {
        case let value as EAttribute: type = value.eGenericType
        case let value as EReference: type = value.eGenericType
        case let value as EOperation: type = value.eGenericType
        case let value as EParameter: type = value.eGenericType
        default: type = nil
        }
        return type.flatMap { $0.isParameterised || metadata.xmlIdentifiers[$0.id] != nil
            || metadata.commentsBefore[$0.id] != nil || hasEndComments($0.id) ? $0 : nil }
    }

    /// Writes the type parameters of a classifier or operation.
    ///
    /// - Parameters:
    ///   - parameters: The parameters in declaration order.
    ///   - depth: The nesting depth of the parameter elements.
    private mutating func writeTypeParameters(_ parameters: [ETypeParameter], depth: Int) {
        for parameter in parameters {
            let tag = EcoreFeatureName.eTypeParameters.rawValue
            openTag(tag, depth: depth, identifier: parameter.id)
            attribute(.name, parameter.name)
            if parameter.eAnnotations.isEmpty && parameter.eBounds.isEmpty && !hasEndComments(parameter.id) {
                output += "/>\n"
                continue
            }
            output += ">\n"
            writeAnnotations(parameter.eAnnotations, depth: depth + 1)
            for bound in parameter.eBounds { writeGenericType(bound, tag: .eBounds, depth: depth + 1) }
            writeComments(metadata.commentsAtEnd[parameter.id] ?? [], depth: depth + 1)
            indent(depth)
            output += "</\(tag)>\n"
        }
    }

    /// Writes a generic type, its arguments and wildcard bounds.
    ///
    /// - Parameters:
    ///   - type: The type to write.
    ///   - tag: The containment feature that names the XML element.
    ///   - depth: The nesting depth of the element.
    private mutating func writeGenericType(_ type: EGenericType, tag: EcoreFeatureName, depth: Int) {
        openTag(tag.rawValue, depth: depth, identifier: type.id)
        if let parameter = type.eTypeParameter, let path = paths[parameter] {
            attribute(.eTypeParameter, "#" + path)
        } else if let proxy = retainedReferences(of: type.id, feature: .eTypeParameter).first {
            attribute(.eTypeParameter, proxy)
        }
        if let classifier = type.eClassifier {
            attribute(.eClassifier, typeReference(of: type.id, type: classifier))
        }
        if type.containedTypes.isEmpty && !hasEndComments(type.id) {
            output += "/>\n"
            return
        }
        output += ">\n"
        for child in type.containedTypes {
            writeGenericType(child.object, tag: child.feature, depth: depth + 1)
        }
        writeComments(metadata.commentsAtEnd[type.id] ?? [], depth: depth + 1)
        indent(depth)
        output += "</\(tag.rawValue)>\n"
    }

    // MARK: Annotations

    /// The saved spelling of retained proxies in a reference family.
    ///
    /// - Parameters:
    ///   - identifier: The element holding the reference.
    ///   - feature: The reference feature.
    /// - Returns: The retained cross-document references in source order.
    private func retainedReferences(of identifier: EUUID, feature: EcoreFeatureName) -> [String] {
        (root.origin?.unresolvedReferences[identifier]?[feature] ?? []).map {
            "\(relativeURI($0.uri))#\($0.fragment)"
        }
    }

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
            openTag(tag, depth: depth, identifier: annotation.id)
            if !annotation.source.isEmpty { attribute(EcoreFeatureName.source, annotation.source) }
            if let references = referenceText(of: annotation) {
                attribute(EcoreFeatureName.references, references)
            }
            let entries = annotation.detailEntries
            if entries.isEmpty && annotation.eAnnotations.isEmpty && annotation.contents.isEmpty && !hasEndComments(annotation.id) {
                output += "/>\n"
                continue
            }
            output += ">\n"
            writeAnnotations(annotation.eAnnotations, depth: depth + 1)
            for entry in entries {
                openTag(EcoreFeatureName.details.rawValue, depth: depth + 1, identifier: entry.id)
                attribute(EcoreFeatureName.key, entry.key)
                attribute(EcoreFeatureName.value, entry.value)
                if hasEndComments(entry.id) {
                    output += ">\n"
                    writeComments(metadata.commentsAtEnd[entry.id] ?? [], depth: depth + 2)
                    indent(depth + 1)
                    output += "</\(EcoreFeatureName.details.rawValue)>\n"
                } else { output += "/>\n" }
            }
            for content in annotation.contents { writeContent(content, depth: depth + 1) }
            writeComments(metadata.commentsAtEnd[annotation.id] ?? [], depth: depth + 1)
            indent(depth)
            output += "</\(tag)>\n"
        }
    }

    /// Writes an object that an annotation contains.
    ///
    /// The object is written with the metaclass in `xsi:type` and its single-valued
    /// primitive attributes. Objects that the content itself contains are not written.
    private mutating func writeContent(_ content: any EObject, depth: Int) {
        openTag(EcoreFeatureName.contents.rawValue, depth: depth, identifier: content.id)
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

    /// Whether a model element has comments after its final child.
    ///
    /// - Parameter identifier: The element identity.
    /// - Returns: Whether the owner requires a closing tag for its comments.
    private func hasEndComments(_ identifier: EUUID) -> Bool {
        !(metadata.commentsAtEnd[identifier] ?? []).isEmpty
    }

    /// Starts an element with its indentation, name, metadata and optional metaclass.
    ///
    /// - Parameters:
    ///   - tag: The element's XML tag.
    ///   - depth: The element's nesting depth.
    ///   - type: The optional Ecore metaclass qualifier.
    ///   - identifier: The identity associated with retained XML metadata.
    ///   - writesIdentifier: Whether to include an explicit XML identifier here.
    private mutating func openTag(_ tag: String, depth: Int, type: EcoreClassifier? = nil,
        identifier: EUUID? = nil, writesIdentifier: Bool = true) {
        if let identifier { writeComments(metadata.commentsBefore[identifier] ?? [], depth: depth) }
        indent(depth)
        elementDepth = depth
        output += "<\(tag)"
        if let type { rawAttribute(typeAttribute, ecorePrefixed(type.rawValue)) }
        if writesIdentifier, let identifier, let text = metadata.xmlIdentifiers[identifier] {
            rawAttribute(XMIAttribute.xmiId.rawValue, text)
        }
    }

    /// Writes XML comments at a model element's nesting depth.
    ///
    /// - Parameters:
    ///   - comments: Comments including their XML delimiters.
    ///   - depth: The nesting depth of the comments.
    private mutating func writeComments(_ comments: [String], depth: Int) {
        for comment in comments { indent(depth); output += comment + "\n" }
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
    var id: EUUID { get }
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
