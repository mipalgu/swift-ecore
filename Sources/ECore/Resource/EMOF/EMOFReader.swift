//
// EMOFReader.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import SwiftXML

/// Translates an EMOF document into the Ecore document that it describes.
///
/// The translation follows the mapping of ``EMOFSyntax``. Every element keeps its `xmi:id`, and
/// references within the document are written as references to those identifiers, so that
/// the Ecore loader resolves them as EMF resolves the identifiers of an EMOF document.
struct EMOFReader {
    /// A tag that annotates elements of the document.
    private struct Tag {
        /// The name of the tag.
        var name: String?
        /// The value of the tag.
        var value: String?
        /// The references to the tagged elements, in Ecore form.
        var references: [String]
    }

    /// The URI of the document, for diagnostics.
    let document: String

    /// What the translation could not keep.
    private(set) var diagnostics: [SourceDiagnostic] = []

    /// The EMOF kind of each element with an identifier, such as `Class` or `Property`.
    private var kinds: [String: String] = [:]

    /// The tags to write as annotations of each element, by the identifier of the element.
    private var tags: [String: [Tag]] = [:]

    /// The Ecore document being written.
    private var out = XMLTextBuilder()

    /// The Ecore qualifiers of the EMOF classifier kinds.
    private static let qualifiers: [String: String] = [
        EMOFSyntax.Name.class: "ecore:" + EcoreClassifier.eClass.rawValue,
        EMOFSyntax.Name.enumeration: "ecore:" + EcoreClassifier.eEnum.rawValue,
        EMOFSyntax.Name.primitiveType: "ecore:" + EcoreClassifier.eDataType.rawValue,
        EMOFSyntax.Name.dataType: "ecore:" + EcoreClassifier.eDataType.rawValue,
    ]

    /// The EMOF kinds of the elements that their containing feature implies.
    private static let impliedKinds: [String: String] = [
        EMOFSyntax.Name.nestedPackage: EMOFSyntax.Name.package,
        EMOFSyntax.Name.ownedAttribute: EMOFSyntax.Name.property,
        EMOFSyntax.Name.ownedOperation: EMOFSyntax.Name.operation,
        EMOFSyntax.Name.ownedParameter: EMOFSyntax.Name.parameter,
        EMOFSyntax.Name.ownedLiteral: EMOFSyntax.Name.enumerationLiteral,
    ]

    /// Creates a reader for a document.
    ///
    /// - Parameter document: The URI of the document.
    init(document: String) {
        self.document = document
    }

    // MARK: - Translation

    /// Translates the EMOF document with a given root element into the text of an Ecore document.
    ///
    /// - Parameter root: The root element, an EMOF `Package` or an `xmi:XMI` element holding packages.
    /// - Returns: The text of the Ecore document.
    /// - Throws: ``EMOFError`` if the document is not EMOF or is CMOF.
    mutating func translate(_ root: XElement) throws -> String {
        let packages = try packageElements(of: root)
        index(root)
        collectTags(of: root)
        var declarations = [
            (XMIAttribute.xmiVersion.rawValue, CrossReferenceSyntax.xmiVersion),
            (CrossReferenceSyntax.namespaceAttribute(for: CrossReferenceSyntax.xmiPrefix), EcoreURI.xmiNamespace.rawValue),
            (CrossReferenceSyntax.namespaceAttribute(for: CrossReferenceSyntax.xsiPrefix), EcoreURI.xsiNamespace.rawValue),
            (CrossReferenceSyntax.namespaceAttribute(for: CrossReferenceSyntax.ecorePrefix), EcoreURI.ecoreNamespace.rawValue),
        ]
        let reserved = Set([CrossReferenceSyntax.xmiPrefix, CrossReferenceSyntax.xsiPrefix, CrossReferenceSyntax.ecorePrefix])
        for (prefix, uri) in XMLTree.declaredNamespaces(of: root).sorted(by: { $0.key < $1.key })
        where !prefix.isEmpty && !reserved.contains(prefix) && !EMOFSyntax.namespaceURIs.contains(uri) {
            declarations.append((CrossReferenceSyntax.namespaceAttribute(for: prefix), uri))
        }
        let packageElement = CrossReferenceSyntax.ecorePrefix + ":" + EcoreClassifier.ePackage.rawValue
        if packages.count == 1 {
            writePackage(packages[0], elementName: packageElement, leading: declarations)
        } else {
            out.open(CrossReferenceSyntax.xmiPrefix + ":" + XMIDocumentSyntax.multipleRootElement, declarations)
            for package in packages { writePackage(package, elementName: packageElement, leading: []) }
            out.close()
        }
        return out.text
    }

    /// The EMOF packages of a document.
    ///
    /// - Parameter root: The root element of the document.
    /// - Returns: The root element itself if it is a package, or the packages it holds.
    /// - Throws: ``EMOFError`` if the document holds no EMOF package or is CMOF.
    private mutating func packageElements(of root: XElement) throws -> [XElement] {
        let (namespace, local) = XMLTree.expandedName(root.name, at: root)
        if let namespace, EMOFSyntax.cmofNamespaceURIs.contains(namespace) { throw EMOFError.cmofNotSupported(document) }
        if let namespace, EMOFSyntax.namespaceURIs.contains(namespace) {
            guard local == EMOFSyntax.Name.package else { throw EMOFError.notEMOF(document) }
            return [root]
        }
        guard local == XMIDocumentSyntax.multipleRootElement else { throw EMOFError.notEMOF(document) }
        var packages: [XElement] = []
        for child in root.children {
            let (childNamespace, childLocal) = XMLTree.expandedName(child.name, at: child)
            if let childNamespace, EMOFSyntax.cmofNamespaceURIs.contains(childNamespace) {
                throw EMOFError.cmofNotSupported(document)
            }
            guard let childNamespace, EMOFSyntax.namespaceURIs.contains(childNamespace) else {
                if !XMIDialectSyntax.isDocumentationOrExtension(child.name) { unsupported("the element '\(child.name)'") }
                continue
            }
            if childLocal == EMOFSyntax.Name.package { packages.append(child) }
            else if childLocal != EMOFSyntax.Name.tag { unsupported("the element '\(child.name)'") }
        }
        guard !packages.isEmpty else { throw EMOFError.notEMOF(document) }
        return packages
    }

    /// Records the EMOF kind of every element with an identifier.
    ///
    /// - Parameter root: The root element of the document.
    private mutating func index(_ root: XElement) {
        var stack = [root]
        while let element = stack.popLast() {
            if let identifier = element[XMIAttribute.xmiId.rawValue], let kind = kind(of: element) {
                kinds[identifier] = kind
            }
            stack += element.children
        }
    }

    /// The EMOF kind of an element: its `xmi:type`, its own name, or what its feature implies.
    ///
    /// - Parameter element: The element.
    /// - Returns: The local name of the kind, or `nil` if it cannot be told.
    private func kind(of element: XElement) -> String? {
        if let type = element[XMITypeAttribute.xmi.rawValue] ?? element[XMITypeAttribute.xsi.rawValue] {
            return XMLTree.parts(of: type).local
        }
        let (namespace, local) = XMLTree.expandedName(element.name, at: element)
        if let namespace, EMOFSyntax.namespaceURIs.contains(namespace) { return local }
        return Self.impliedKinds[element.name]
    }

    /// Collects the tags of the document and assigns each to the first element it tags.
    ///
    /// - Parameter root: The root element of the document.
    private mutating func collectTags(of root: XElement) {
        var stack = [root]
        while let element = stack.popLast() {
            stack += element.children
            let (namespace, local) = XMLTree.expandedName(element.name, at: element)
            guard let namespace, EMOFSyntax.namespaceURIs.contains(namespace), local == EMOFSyntax.Name.tag else {
                continue
            }
            var targets = element[EMOFSyntax.Name.element].map {
                $0.split(whereSeparator: \.isWhitespace).map(String.init)
            } ?? []
            var references = targets.map { String(CrossReferenceSyntax.fragmentSeparator) + $0 }
            for child in element.children(EMOFSyntax.Name.element) {
                if let href = child[CrossReferenceSyntax.hrefAttribute] { references.append(href) }
                if let idref = child[XMIDialectSyntax.idref] {
                    targets.append(idref)
                    references.append(String(CrossReferenceSyntax.fragmentSeparator) + idref)
                }
            }
            let tag = Tag(
                name: element[EMOFSyntax.Name.name] ?? element.children(EMOFSyntax.Name.name).first?.immediateTextsCombined,
                value: element[EMOFSyntax.Name.value]
                    ?? element.children(EMOFSyntax.Name.value).first?.immediateTextsCombined,
                references: references)
            guard let owner = targets.first(where: { kinds[$0] != nil }) else {
                unsupported("the tag '\(tag.name ?? "")', which tags no element of the document")
                continue
            }
            tags[owner, default: []].append(tag)
        }
    }

    // MARK: - Elements

    /// Writes a package with its classifiers and nested packages.
    ///
    /// - Parameters:
    ///   - element: The EMOF package.
    ///   - elementName: The name of the Ecore element.
    ///   - leading: The attributes that precede those of the package, such as declarations.
    private mutating func writePackage(_ element: XElement, elementName: String, leading: [(String, String)]) {
        let extensions = extensionContent(of: element)
        var attributes = leading + identity(of: element)
        if let uri = text(EMOFSyntax.Name.uri, of: element) { attributes.append((EcoreFeatureName.nsURI.rawValue, uri)) }
        attributes += extensionValues(extensions.values, [.nsPrefix])
        out.open(elementName, attributes)
        writeAnnotations(of: element, copied: extensions.copied)
        for child in element.children(EMOFSyntax.Name.ownedType) { writeClassifier(child) }
        for child in element.children(EMOFSyntax.Name.nestedPackage) {
            writePackage(child, elementName: EcoreFeatureName.eSubpackages.rawValue, leading: [])
        }
        out.close()
    }

    /// Writes a classifier: a class, an enumeration, or a data type.
    ///
    /// - Parameter element: The `ownedType` element.
    private mutating func writeClassifier(_ element: XElement) {
        let kind = kind(of: element) ?? ""
        let extensions = extensionContent(of: element)
        let classifierFeatures: [EcoreFeatureName] = [.instanceClassName, .instanceTypeName]
        let elementName = EcoreFeatureName.eClassifiers.rawValue
        switch kind {
        case EMOFSyntax.Name.class:
            var attributes = [typeAttribute(.eClass)] + identity(of: element)
            if flag(EMOFSyntax.Name.isAbstract, of: element) == true {
                attributes.append((XMIAttribute.abstract.rawValue, "true"))
            }
            attributes += extensionValues(extensions.values, [.interface] + classifierFeatures)
            let generic = extensions.copied.contains { $0.name == EcoreFeatureName.eGenericSuperTypes.rawValue }
            let superTypes = references(EMOFSyntax.Name.superClass, of: element)
            if !generic && !superTypes.isEmpty {
                attributes.append((XMIAttribute.eSuperTypes.rawValue, superTypes.joined(separator: " ")))
            }
            out.open(elementName, attributes)
            writeAnnotations(of: element, copied: extensions.copied)
            for child in element.children(EMOFSyntax.Name.ownedAttribute) { writeProperty(child) }
            for child in element.children(EMOFSyntax.Name.ownedOperation) { writeOperation(child) }
            out.close()
        case EMOFSyntax.Name.enumeration:
            var attributes = [typeAttribute(.eEnum)] + identity(of: element)
            attributes += extensionValues(extensions.values, classifierFeatures + [.serializable])
            out.open(elementName, attributes)
            writeAnnotations(of: element, copied: extensions.copied)
            for literal in element.children(EMOFSyntax.Name.ownedLiteral) {
                let literalExtensions = extensionContent(of: literal)
                let literalAttributes = identity(of: literal) + extensionValues(literalExtensions.values, [.value])
                out.open(EcoreFeatureName.eLiterals.rawValue, literalAttributes)
                writeAnnotations(of: literal, copied: literalExtensions.copied)
                out.close()
            }
            out.close()
        case EMOFSyntax.Name.primitiveType, EMOFSyntax.Name.dataType:
            var attributes = [typeAttribute(.eDataType)] + identity(of: element)
            attributes += extensionValues(extensions.values, classifierFeatures + [.serializable])
            out.open(elementName, attributes)
            writeAnnotations(of: element, copied: extensions.copied)
            out.close()
        default:
            unsupported("the type '\(kind)' of '\(text(EMOFSyntax.Name.name, of: element) ?? "")'")
        }
    }

    /// Writes a property as an attribute or a reference.
    ///
    /// A property whose type is a data type or an enumeration is an attribute; any other
    /// property, including one whose type cannot be told, is a reference, as in EMF.
    ///
    /// - Parameter element: The `ownedAttribute` element.
    private mutating func writeProperty(_ element: XElement) {
        let extensions = extensionContent(of: element)
        let type = typeReference(of: element)
        let isAttribute = type?.isClass == false
        var attributes = [typeAttribute(isAttribute ? .eAttribute : .eReference)] + identity(of: element)
        attributes += typedAttributes(of: element, type: type, copied: extensions.copied)
        if flag(EMOFSyntax.Name.isReadOnly, of: element) == true {
            attributes.append((XMIAttribute.changeable.rawValue, "false"))
        }
        attributes += extensionValues(extensions.values, [.volatile, .transient])
        if let value = text(EMOFSyntax.Name.default, of: element) {
            attributes.append((XMIAttribute.defaultValueLiteral.rawValue, value))
        }
        attributes += extensionValues(extensions.values, [.unsettable])
        if flag(EMOFSyntax.Name.isDerived, of: element) == true {
            attributes.append((EcoreFeatureName.derived.rawValue, "true"))
        }
        if isAttribute {
            if flag(EMOFSyntax.Name.isID, of: element) == true { attributes.append((XMIAttribute.iD.rawValue, "true")) }
        } else {
            if flag(EMOFSyntax.Name.isComposite, of: element) == true {
                attributes.append((XMIAttribute.containment.rawValue, "true"))
            }
            attributes += extensionValues(extensions.values, [.resolveProxies])
            if let opposite = references(EMOFSyntax.Name.opposite, of: element).first {
                attributes.append((XMIAttribute.eOpposite.rawValue, opposite))
            }
        }
        out.open(EcoreFeatureName.eStructuralFeatures.rawValue, attributes)
        writeAnnotations(of: element, copied: extensions.copied)
        out.close()
    }

    /// Writes an operation with its parameters.
    ///
    /// - Parameter element: The `ownedOperation` element.
    private mutating func writeOperation(_ element: XElement) {
        let extensions = extensionContent(of: element)
        var attributes = identity(of: element)
        attributes += typedAttributes(of: element, type: typeReference(of: element), copied: extensions.copied)
        let generic = extensions.copied.contains { $0.name == EcoreFeatureName.eGenericExceptions.rawValue }
        let exceptions = references(EMOFSyntax.Name.raisedException, of: element)
        if !generic && !exceptions.isEmpty {
            attributes.append((EcoreFeatureName.eExceptions.rawValue, exceptions.joined(separator: " ")))
        }
        out.open(EcoreFeatureName.eOperations.rawValue, attributes)
        writeAnnotations(of: element, copied: extensions.copied)
        for parameter in element.children(EMOFSyntax.Name.ownedParameter) {
            let parameterExtensions = extensionContent(of: parameter)
            let parameterAttributes = identity(of: parameter) + typedAttributes(
                of: parameter, type: typeReference(of: parameter), copied: parameterExtensions.copied)
            out.open(EcoreFeatureName.eParameters.rawValue, parameterAttributes)
            writeAnnotations(of: parameter, copied: parameterExtensions.copied)
            out.close()
        }
        out.close()
    }

    /// Writes the annotations of an element: its comments, its tags, and the Ecore elements
    /// of its extensions.
    ///
    /// - Parameters:
    ///   - element: The EMOF element.
    ///   - copied: The Ecore elements of the extensions of the element.
    private mutating func writeAnnotations(of element: XElement, copied: [XElement]) {
        for comment in element.children(EMOFSyntax.Name.ownedComment) {
            let nested = comment.children(EMOFSyntax.Name.ownedComment).first
            let source = nested.flatMap { text(EMOFSyntax.Name.body, of: $0) } ?? EMOFSyntax.commentSource
            out.open(EcoreFeatureName.eAnnotations.rawValue, [(EcoreFeatureName.source.rawValue, source)])
            if let body = text(EMOFSyntax.Name.body, of: comment) {
                out.empty(EcoreFeatureName.details.rawValue, [
                    (EcoreFeatureName.key.rawValue, EMOFSyntax.Name.body), (EcoreFeatureName.value.rawValue, body),
                ])
            }
            out.close()
        }
        if let identifier = element[XMIAttribute.xmiId.rawValue] {
            for tag in tags[identifier] ?? [] {
                var attributes = [(EcoreFeatureName.source.rawValue, EMOFSyntax.namespaceURI)]
                let others = tag.references.dropFirst()
                if !others.isEmpty {
                    attributes.append((EcoreFeatureName.references.rawValue, others.joined(separator: " ")))
                }
                out.open(EcoreFeatureName.eAnnotations.rawValue, attributes)
                for (key, value) in [(EMOFSyntax.Name.name, tag.name), (EMOFSyntax.Name.value, tag.value)] {
                    guard let value else { continue }
                    out.empty(EcoreFeatureName.details.rawValue, [
                        (EcoreFeatureName.key.rawValue, key), (EcoreFeatureName.value.rawValue, value),
                    ])
                }
                out.close()
            }
        }
        for child in copied { out.copy(child) }
    }

    // MARK: - Values

    /// The `xsi:type` attribute of an Ecore element.
    ///
    /// - Parameter classifier: The Ecore class of the element.
    /// - Returns: The attribute, such as `xsi:type="ecore:EClass"`.
    private func typeAttribute(_ classifier: EcoreClassifier) -> (String, String) {
        (XMITypeAttribute.xsi.rawValue, CrossReferenceSyntax.ecorePrefix + ":" + classifier.rawValue)
    }

    /// The identifier and name of an element.
    ///
    /// - Parameter element: The EMOF element.
    /// - Returns: Its `xmi:id` and `name` attributes, where present.
    private func identity(of element: XElement) -> [(String, String)] {
        var attributes: [(String, String)] = []
        if let identifier = element[XMIAttribute.xmiId.rawValue] {
            attributes.append((XMIAttribute.xmiId.rawValue, identifier))
        }
        if let name = text(EMOFSyntax.Name.name, of: element) { attributes.append((XMIAttribute.name.rawValue, name)) }
        return attributes
    }

    /// The text of a value written as an attribute or as a child element.
    ///
    /// - Parameters:
    ///   - name: The name of the value.
    ///   - element: The EMOF element.
    /// - Returns: The text, or `nil` if the element has no such value.
    private func text(_ name: String, of element: XElement) -> String? {
        element[name] ?? element.children(name).first?.immediateTextsCombined
    }

    /// A Boolean value written as an attribute or as a child element.
    ///
    /// - Parameters:
    ///   - name: The name of the value.
    ///   - element: The EMOF element.
    /// - Returns: The value, or `nil` if the element has no such value.
    private func flag(_ name: String, of element: XElement) -> Bool? {
        text(name, of: element).map { $0.trimmingCharacters(in: .whitespaces) == "true" }
    }

    /// The multiplicity, ordering, uniqueness and type of a typed element in Ecore form.
    ///
    /// EMOF defaults differ from those of Ecore: a missing lower bound is 1, a missing
    /// `isOrdered` is `false`. The Ecore attributes are written wherever the value differs
    /// from the Ecore default.
    ///
    /// - Parameters:
    ///   - element: The property, operation or parameter.
    ///   - type: The type of the element, if it has one.
    ///   - copied: The Ecore elements of its extensions; a generic type among them stands for the type.
    /// - Returns: The Ecore attributes.
    private func typedAttributes(
        of element: XElement, type: (reference: String, isClass: Bool?)?, copied: [XElement]
    ) -> [(String, String)] {
        var attributes: [(String, String)] = []
        if flag(EMOFSyntax.Name.isOrdered, of: element) != true { attributes.append((XMIAttribute.ordered.rawValue, "false")) }
        if flag(EMOFSyntax.Name.isUnique, of: element) == false { attributes.append((XMIAttribute.unique.rawValue, "false")) }
        let lower = text(EMOFSyntax.Name.lower, of: element).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 1
        if lower != 0 { attributes.append((XMIAttribute.lowerBound.rawValue, String(lower))) }
        let upperText = text(EMOFSyntax.Name.upper, of: element)?.trimmingCharacters(in: .whitespaces)
        let upper = upperText == EMOFSyntax.Name.unbounded ? -1 : upperText.flatMap { Int($0) } ?? 1
        if upper != 1 { attributes.append((XMIAttribute.upperBound.rawValue, String(upper))) }
        let generic = copied.contains { $0.name == EcoreFeatureName.eGenericType.rawValue }
        if let type, !generic { attributes.append((XMIAttribute.eType.rawValue, type.reference)) }
        return attributes
    }

    /// The type of a typed element in Ecore form, and whether it is a class.
    ///
    /// - Parameter element: The property, operation or parameter.
    /// - Returns: The Ecore reference to the type, and `true` for a class, `false` for a data
    ///   type or enumeration, or `nil` if that cannot be told; `nil` if the element has no type.
    private mutating func typeReference(of element: XElement) -> (reference: String, isClass: Bool?)? {
        if let identifier = element[EMOFSyntax.Name.type]?.trimmingCharacters(in: .whitespaces), !identifier.isEmpty {
            return local(identifier)
        }
        guard let child = element.children(EMOFSyntax.Name.type).first else { return nil }
        if let identifier = child[XMIDialectSyntax.idref] { return local(identifier) }
        guard let href = child[CrossReferenceSyntax.hrefAttribute] else { return nil }
        let kind = child[XMITypeAttribute.xmi.rawValue].map { XMLTree.parts(of: $0).local }
        return external(href, kind: kind)
    }

    /// A reference to an element of the document by identifier.
    ///
    /// - Parameter identifier: The `xmi:id` of the element.
    /// - Returns: The Ecore reference and whether the element is a class.
    private func local(_ identifier: String) -> (reference: String, isClass: Bool?) {
        let kind = kinds[identifier]
        let isClass = kind.map { $0 == EMOFSyntax.Name.class }
        return (String(CrossReferenceSyntax.fragmentSeparator) + identifier, isClass)
    }

    /// A reference to an element of another document, in Ecore form.
    ///
    /// The primitive types of EMOF and the EMOF descriptions of the Ecore data types become
    /// references to the Ecore data types.
    ///
    /// - Parameters:
    ///   - href: The `uri#fragment` reference.
    ///   - kind: The EMOF kind of the target, if the reference names it.
    /// - Returns: The Ecore reference and whether the target is a class.
    private mutating func external(_ href: String, kind: String?) -> (reference: String, isClass: Bool?) {
        let parts = href.split(separator: CrossReferenceSyntax.fragmentSeparator, maxSplits: 1).map(String.init)
        let uri = parts.first ?? ""
        let fragment = parts.count > 1 ? parts[1] : ""
        let ecoreTypes = EcoreURI.ecoreDataTypePrefix.rawValue
        if EMOFSyntax.namespaceURIs.contains(uri) {
            guard let name = EMOFSyntax.ecoreName(ofEMOFType: fragment) else {
                unsupported("the primitive type '\(fragment)', which is read as EString")
                return (ecoreTypes + EcoreDataType.eString.rawValue, false)
            }
            return (ecoreTypes + name, false)
        }
        if uri == EMOFSyntax.ecoreTypesDocument, fragment.hasPrefix(EMOFSyntax.ecoreTypesFragmentPrefix) {
            let name = String(fragment.dropFirst(EMOFSyntax.ecoreTypesFragmentPrefix.count))
            if EcorePackage.classifier(named: name) is EClass {
                return (EcoreURI.ecoreClassPrefix.rawValue + name, true)
            }
            return (ecoreTypes + name, false)
        }
        guard let kind, let qualifier = Self.qualifiers[kind] else { return (href, nil) }
        return (qualifier + " " + href, kind == EMOFSyntax.Name.class)
    }

    /// The references that a feature of an element holds, in Ecore form.
    ///
    /// - Parameters:
    ///   - name: The EMOF name of the feature, such as `superClass`.
    ///   - element: The EMOF element.
    /// - Returns: References to identifiers of the document and to other documents, in order.
    private mutating func references(_ name: String, of element: XElement) -> [String] {
        var result = element[name].map {
            $0.split(whereSeparator: \.isWhitespace).map { String(CrossReferenceSyntax.fragmentSeparator) + $0 }
        } ?? []
        for child in element.children(name) {
            if let identifier = child[XMIDialectSyntax.idref] {
                result.append(String(CrossReferenceSyntax.fragmentSeparator) + identifier)
            } else if let href = child[CrossReferenceSyntax.hrefAttribute] {
                let kind = child[XMITypeAttribute.xmi.rawValue].map { XMLTree.parts(of: $0).local }
                result.append(external(href, kind: kind).reference)
            }
        }
        return result
    }

    // MARK: - Extensions

    /// The content of the Ecore extensions of an element.
    ///
    /// - Parameter element: The EMOF element.
    /// - Returns: The simple Ecore values by feature name, and the Ecore elements to copy.
    private mutating func extensionContent(of element: XElement) -> (values: [String: String], copied: [XElement]) {
        var values: [String: String] = [:]
        var copied: [XElement] = []
        for child in element.children where XMIDialectSyntax.isDocumentationOrExtension(child.name) {
            guard XMIDialectSyntax.extensionElements.contains(XMLTree.parts(of: child.name).local) else { continue }
            guard child[XMIDialectSyntax.extender] == EcoreURI.ecoreNamespace.rawValue else {
                unsupported("an extension of '\(child[XMIDialectSyntax.extender] ?? "")'")
                continue
            }
            for content in child.children {
                if EMOFSyntax.extensionElements.contains(content.name) {
                    copied.append(content)
                } else if EMOFSyntax.extensionFeatures.contains(where: { $0.rawValue == content.name }) {
                    values[content.name] = content.immediateTextsCombined
                } else {
                    unsupported("the Ecore extension '\(content.name)'")
                }
            }
        }
        return (values, copied)
    }

    /// The simple values of an extension in Ecore attribute form.
    ///
    /// - Parameters:
    ///   - values: The values of the extensions of an element, by feature name.
    ///   - features: The features to write, in order.
    /// - Returns: The attributes for the features that have a value.
    private func extensionValues(_ values: [String: String], _ features: [EcoreFeatureName]) -> [(String, String)] {
        features.compactMap { feature in values[feature.rawValue].map { (feature.rawValue, $0) } }
    }

    /// Records that a part of the document was left out.
    ///
    /// - Parameter what: A description of what was left out.
    private mutating func unsupported(_ what: String) {
        diagnostics.append(SourceDiagnostic(
            severity: .warning, code: ModelDocumentDiagnostic.unsupportedEMOF,
            message: "EMOF: \(what) has no equivalent in Ecore and was left out", document: document))
    }
}

/// Errors raised while an EMOF document is read.
public enum EMOFError: Error, Sendable, Equatable {
    /// The document is not an EMOF document. The associated value is its URI.
    case notEMOF(String)

    /// The document is a CMOF document, which is not read. The associated value is its URI.
    case cmofNotSupported(String)
}

extension EMOFError: CustomStringConvertible, LocalizedError {
    /// A sentence that describes the error and names the document.
    public var description: String {
        switch self {
        case .notEMOF(let document):
            return "\(document) is not an EMOF document: it holds no EMOF package"
        case .cmofNotSupported(let document):
            return "\(document) is a CMOF document; only EMOF documents can be read"
        }
    }

    /// The ``description`` of the error.
    public var errorDescription: String? { description }
}
