//
// EMOFWriter.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import SwiftXML

/// Translates an Ecore document into the EMOF document that EMF writes for it.
///
/// The translation follows the mapping of ``EMOFSyntax``. Every element receives the
/// identifier that EMF gives it: the names of the element and its containers joined by dots,
/// such as `library.Book.title`. References within the document refer to these identifiers;
/// references to other documents keep their URIs and fragments.
struct EMOFWriter {
    /// A tag to write after the packages.
    private struct Tag {
        /// The identifier of the tag.
        var identifier: String
        /// The name of the tag.
        var name: String?
        /// The value of the tag.
        var value: String?
        /// The identifiers of the tagged elements of the document.
        var elements: [String]
        /// The references to tagged elements of other documents.
        var hrefs: [String]
    }

    /// The identifier of each element of the Ecore document.
    private var identifiers: [ObjectIdentifier: String] = [:]

    /// The identifier of the element that each name-based fragment, or `xmi:id`, of the
    /// Ecore document names.
    private var fragments: [String: String] = [:]

    /// The tags of the document, written after its packages.
    private var tags: [Tag] = []

    /// Whether elements of the Ecore namespace were copied into extensions.
    private var copiesEcore = false

    /// The EMOF document being written.
    private var out = XMLTextBuilder()

    /// The marker that stands for the namespace declarations until they are known.
    private static let declarationsMarker = "\u{0}declarations\u{0}"

    /// The EMOF kinds of the Ecore classifiers, by the local name of their Ecore class.
    private static let kinds: [String: String] = [
        EcoreClassifier.eClass.rawValue: EMOFSyntax.Name.class,
        EcoreClassifier.eEnum.rawValue: EMOFSyntax.Name.enumeration,
        EcoreClassifier.eDataType.rawValue: EMOFSyntax.Name.primitiveType,
    ]

    // MARK: - Translation

    /// Translates the Ecore document with a given root element into the text of an EMOF document.
    ///
    /// - Parameter root: The root element, an `ecore:EPackage` or an `xmi:XMI` element holding packages.
    /// - Returns: The text of the EMOF document.
    mutating func translate(_ root: XElement) -> String {
        let packages = XMLTree.parts(of: root.name).local == XMIDocumentSyntax.multipleRootElement
            ? Array(root.children) : [root]
        var used = Set<String>()
        for (index, package) in packages.enumerated() {
            let base = packages.count == 1 ? "/" : "/\(index)"
            assignIdentifiers(package, prefix: nil, path: [], base: base, alternative: index == 0 ? "/" : nil, used: &used)
        }
        let wrapper = CrossReferenceSyntax.xmiPrefix + ":" + XMIDocumentSyntax.multipleRootElement
        out.open(wrapper, [(Self.declarationsMarker, "")])
        for package in packages { writePackage(package, elementName: EMOFSyntax.prefix + ":" + EMOFSyntax.Name.package) }
        for tag in tags {
            var attributes = [
                (XMIAttribute.xmiId.rawValue, tag.identifier),
            ]
            if let name = tag.name { attributes.append((EMOFSyntax.Name.name, name)) }
            if let value = tag.value { attributes.append((EMOFSyntax.Name.value, value)) }
            if !tag.elements.isEmpty { attributes.append((EMOFSyntax.Name.element, tag.elements.joined(separator: " "))) }
            let name = EMOFSyntax.prefix + ":" + EMOFSyntax.Name.tag
            if tag.hrefs.isEmpty {
                out.empty(name, attributes)
            } else {
                out.open(name, attributes)
                for href in tag.hrefs { out.empty(EMOFSyntax.Name.element, [(CrossReferenceSyntax.hrefAttribute, href)]) }
                out.close()
            }
        }
        out.close()
        var declarations = [
            (XMIAttribute.xmiVersion.rawValue, CrossReferenceSyntax.xmiVersion),
            (CrossReferenceSyntax.namespaceAttribute(for: CrossReferenceSyntax.xmiPrefix), EcoreURI.xmiNamespace.rawValue),
        ]
        if copiesEcore {
            declarations += [
                (CrossReferenceSyntax.namespaceAttribute(for: CrossReferenceSyntax.xsiPrefix), EcoreURI.xsiNamespace.rawValue),
                (CrossReferenceSyntax.namespaceAttribute(for: CrossReferenceSyntax.ecorePrefix), EcoreURI.ecoreNamespace.rawValue),
            ]
        }
        declarations.append((CrossReferenceSyntax.namespaceAttribute(for: EMOFSyntax.prefix), EMOFSyntax.namespaceURI))
        let text = declarations.map { "\($0.0)=\"\(XMISerializer.escapeAttribute($0.1))\"" }.joined(separator: " ")
        return out.text.replacingOccurrences(of: " \(Self.declarationsMarker)=\"\"", with: " " + text)
    }

    /// Gives an element and its descendants their identifiers and records their fragments.
    ///
    /// - Parameters:
    ///   - element: An Ecore package, classifier, feature, operation, parameter or literal.
    ///   - prefix: The identifier of the container, or `nil` for a root package.
    ///   - path: The names of the containers below the root package.
    ///   - base: The fragment of the root package (`/`, or `/1` for the second of several roots).
    ///   - alternative: Another spelling of the fragment of the root package, if any.
    ///   - used: The identifiers given so far.
    private mutating func assignIdentifiers(
        _ element: XElement, prefix: String?, path: [String], base: String, alternative: String?, used: inout Set<String>
    ) {
        let name = element[XMIAttribute.name.rawValue] ?? ""
        var identifier = prefix.map { $0 + "." + name } ?? name
        if used.contains(identifier) {
            var counter = 2
            while used.contains(identifier + "_\(counter)") { counter += 1 }
            identifier += "_\(counter)"
        }
        used.insert(identifier)
        identifiers[ObjectIdentifier(element)] = identifier
        if let xmlIdentifier = element[XMIAttribute.xmiId.rawValue], fragments[xmlIdentifier] == nil {
            fragments[xmlIdentifier] = identifier
        }
        let elementPath = prefix == nil ? [] : path + [name]
        for root in [base] + (alternative.map { [$0] } ?? []) {
            let fragment = root + (elementPath.isEmpty ? "" : "/" + elementPath.joined(separator: "/"))
            if fragments[fragment] == nil { fragments[fragment] = identifier }
        }
        let contained = [
            EcoreFeatureName.eClassifiers, .eSubpackages, .eStructuralFeatures, .eOperations, .eParameters, .eLiterals,
        ].map(\.rawValue)
        for child in element.children where contained.contains(child.name) {
            assignIdentifiers(child, prefix: identifier, path: elementPath, base: base, alternative: alternative, used: &used)
        }
    }

    // MARK: - Elements

    /// Writes a package with its types and nested packages.
    ///
    /// - Parameters:
    ///   - element: The Ecore package.
    ///   - elementName: The name of the EMOF element.
    private mutating func writePackage(_ element: XElement, elementName: String) {
        var attributes = identity(of: element)
        if let uri = element[EcoreFeatureName.nsURI.rawValue] { attributes.append((EMOFSyntax.Name.uri, uri)) }
        out.open(elementName, attributes)
        writeExtension(of: element, features: [.nsPrefix])
        writeComments(of: element)
        for child in element.children(EcoreFeatureName.eClassifiers.rawValue) { writeClassifier(child) }
        for child in element.children(EcoreFeatureName.eSubpackages.rawValue) {
            writePackage(child, elementName: EMOFSyntax.Name.nestedPackage)
        }
        out.close()
    }

    /// Writes a classifier as an `ownedType`.
    ///
    /// - Parameter element: The Ecore classifier.
    private mutating func writeClassifier(_ element: XElement) {
        let ecoreClass = XMLTree.parts(of: XMIParser.typeQualifier(of: element) ?? "").local
        guard let kind = Self.kinds[ecoreClass] else { return }
        var attributes = [(XMITypeAttribute.xmi.rawValue, EMOFSyntax.prefix + ":" + kind)] + identity(of: element)
        var superTypeHrefs: [(kind: String?, href: String)] = []
        if kind == EMOFSyntax.Name.class {
            if element[XMIAttribute.abstract.rawValue] == "true" { attributes.append((EMOFSyntax.Name.isAbstract, "true")) }
            let superTypes = element[XMIAttribute.eSuperTypes.rawValue]
                ?? element.children(EcoreFeatureName.eGenericSuperTypes.rawValue)
                    .compactMap { $0[EcoreFeatureName.eClassifier.rawValue] }.joined(separator: " ")
            let translated = references(superTypes)
            if !translated.identifiers.isEmpty {
                attributes.append((EMOFSyntax.Name.superClass, translated.identifiers.joined(separator: " ")))
            }
            superTypeHrefs = translated.hrefs
        }
        out.open(EMOFSyntax.Name.ownedType, attributes)
        writeExtension(
            of: element, features: [.instanceClassName, .instanceTypeName, .serializable, .interface],
            copying: [.eTypeParameters, .eGenericSuperTypes])
        writeComments(of: element)
        writeHrefs(EMOFSyntax.Name.superClass, superTypeHrefs)
        for child in element.children(EcoreFeatureName.eStructuralFeatures.rawValue) { writeProperty(child) }
        for child in element.children(EcoreFeatureName.eOperations.rawValue) { writeOperation(child) }
        for literal in element.children(EcoreFeatureName.eLiterals.rawValue) {
            out.open(EMOFSyntax.Name.ownedLiteral, identity(of: literal))
            writeExtension(of: literal, features: [.value])
            writeComments(of: literal)
            out.close()
        }
        out.close()
    }

    /// Writes an attribute or a reference as an `ownedAttribute`.
    ///
    /// - Parameter element: The Ecore structural feature.
    private mutating func writeProperty(_ element: XElement) {
        var attributes = identity(of: element) + typedAttributes(of: element)
        let type = typeReferences(of: element)
        attributes += type.identifiers.map { (EMOFSyntax.Name.type, $0) }
        if element[XMIAttribute.changeable.rawValue] == "false" { attributes.append((EMOFSyntax.Name.isReadOnly, "true")) }
        if let value = element[XMIAttribute.defaultValueLiteral.rawValue] {
            attributes.append((EMOFSyntax.Name.default, value))
        }
        if element[EcoreFeatureName.derived.rawValue] == "true" { attributes.append((EMOFSyntax.Name.isDerived, "true")) }
        if element[XMIAttribute.iD.rawValue] == "true" { attributes.append((EMOFSyntax.Name.isID, "true")) }
        if element[XMIAttribute.containment.rawValue] == "true" {
            attributes.append((EMOFSyntax.Name.isComposite, "true"))
        }
        let opposite = references(element[XMIAttribute.eOpposite.rawValue] ?? "")
        if let identifier = opposite.identifiers.first { attributes.append((EMOFSyntax.Name.opposite, identifier)) }
        out.open(EMOFSyntax.Name.ownedAttribute, attributes)
        writeExtension(
            of: element, features: [.volatile, .transient, .unsettable, .resolveProxies], copying: [.eGenericType])
        writeComments(of: element)
        writeHrefs(EMOFSyntax.Name.type, type.hrefs)
        writeHrefs(EMOFSyntax.Name.opposite, opposite.hrefs)
        out.close()
    }

    /// Writes an operation with its parameters as an `ownedOperation`.
    ///
    /// - Parameter element: The Ecore operation.
    private mutating func writeOperation(_ element: XElement) {
        var attributes = identity(of: element) + typedAttributes(of: element)
        let type = typeReferences(of: element)
        attributes += type.identifiers.map { (EMOFSyntax.Name.type, $0) }
        let exceptionText = element[EcoreFeatureName.eExceptions.rawValue]
            ?? element.children(EcoreFeatureName.eGenericExceptions.rawValue)
                .compactMap { $0[EcoreFeatureName.eClassifier.rawValue] }.joined(separator: " ")
        let exceptions = references(exceptionText)
        if !exceptions.identifiers.isEmpty {
            attributes.append((EMOFSyntax.Name.raisedException, exceptions.identifiers.joined(separator: " ")))
        }
        out.open(EMOFSyntax.Name.ownedOperation, attributes)
        writeExtension(of: element, features: [], copying: [.eTypeParameters, .eGenericType, .eGenericExceptions])
        writeComments(of: element)
        writeHrefs(EMOFSyntax.Name.type, type.hrefs)
        writeHrefs(EMOFSyntax.Name.raisedException, exceptions.hrefs)
        for parameter in element.children(EcoreFeatureName.eParameters.rawValue) {
            let parameterType = typeReferences(of: parameter)
            let parameterAttributes = identity(of: parameter) + typedAttributes(of: parameter)
                + parameterType.identifiers.map { (EMOFSyntax.Name.type, $0) }
            out.open(EMOFSyntax.Name.ownedParameter, parameterAttributes)
            writeExtension(of: parameter, features: [], copying: [.eGenericType])
            writeComments(of: parameter)
            writeHrefs(EMOFSyntax.Name.type, parameterType.hrefs)
            out.close()
        }
        out.close()
    }

    // MARK: - Values

    /// The identifier and name of an element.
    ///
    /// - Parameter element: The Ecore element.
    /// - Returns: Its EMOF `xmi:id` and its `name`.
    private func identity(of element: XElement) -> [(String, String)] {
        var attributes: [(String, String)] = []
        if let identifier = identifiers[ObjectIdentifier(element)] {
            attributes.append((XMIAttribute.xmiId.rawValue, identifier))
        }
        if let name = element[XMIAttribute.name.rawValue] { attributes.append((EMOFSyntax.Name.name, name)) }
        return attributes
    }

    /// The ordering, uniqueness and multiplicity of a typed element in EMOF form.
    ///
    /// A value is written wherever it differs from the EMOF default: `isOrdered` when the
    /// element is ordered, `isUnique` when it is not unique, `lower` when it is not 1, and
    /// `upper` when it is not 1, with `*` for an unbounded element.
    ///
    /// - Parameter element: The Ecore feature, operation or parameter.
    /// - Returns: The EMOF attributes.
    private func typedAttributes(of element: XElement) -> [(String, String)] {
        var attributes: [(String, String)] = []
        if element[XMIAttribute.ordered.rawValue] != "false" { attributes.append((EMOFSyntax.Name.isOrdered, "true")) }
        if element[XMIAttribute.unique.rawValue] == "false" { attributes.append((EMOFSyntax.Name.isUnique, "false")) }
        let lower = element[XMIAttribute.lowerBound.rawValue].flatMap { Int($0) } ?? 0
        if lower != 1 { attributes.append((EMOFSyntax.Name.lower, String(lower))) }
        let upper = element[XMIAttribute.upperBound.rawValue].flatMap { Int($0) } ?? 1
        if upper != 1 { attributes.append((EMOFSyntax.Name.upper, upper == -1 ? EMOFSyntax.Name.unbounded : String(upper))) }
        return attributes
    }

    /// The type of a typed element in EMOF form.
    ///
    /// - Parameter element: The Ecore feature, operation or parameter.
    /// - Returns: The identifier of a type of the document, or the reference to a type elsewhere.
    private func typeReferences(of element: XElement) -> (identifiers: [String], hrefs: [(kind: String?, href: String)]) {
        let type = element[XMIAttribute.eType.rawValue]
            ?? element.children(EcoreFeatureName.eGenericType.rawValue).first?[EcoreFeatureName.eClassifier.rawValue]
        guard let type else { return ([], []) }
        let translated = references(type)
        return (Array(translated.identifiers.prefix(1)), Array(translated.hrefs.prefix(1)))
    }

    /// Translates the references of an Ecore attribute value.
    ///
    /// References to elements of the document become their identifiers. References to the
    /// data types of Ecore become references to the primitive types of EMOF or to the EMOF
    /// descriptions of the Ecore data types; other references keep their URI and fragment.
    ///
    /// - Parameter value: The attribute value, such as `#//Book` or
    ///   `ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString`.
    /// - Returns: The identifiers, and the references to other documents with the EMOF kind
    ///   of their targets.
    private func references(_ value: String) -> (identifiers: [String], hrefs: [(kind: String?, href: String)]) {
        var identifiers: [String] = []
        var hrefs: [(kind: String?, href: String)] = []
        for reference in CrossReference.parseList(value) {
            let kind = reference.qualifier.flatMap { Self.kinds[XMLTree.parts(of: $0).local] }
            if reference.uri.isEmpty {
                if let identifier = fragments[reference.fragment] { identifiers.append(identifier) }
                else { hrefs.append((kind, String(CrossReferenceSyntax.fragmentSeparator) + reference.fragment)) }
                continue
            }
            if EcoreURI.isEcoreMetamodelReference(reference.href),
                let name = EcoreURI.extractTypeName(from: reference.href)
            {
                if let emof = EMOFSyntax.emofName(ofEcoreType: name) {
                    hrefs.append((EMOFSyntax.Name.primitiveType, EMOFSyntax.namespaceURI + "#" + emof))
                } else {
                    let isClass = EcorePackage.classifier(named: name) is EClass
                    hrefs.append((
                        isClass ? EMOFSyntax.Name.class : EMOFSyntax.Name.primitiveType,
                        EMOFSyntax.ecoreTypesDocument + "#" + EMOFSyntax.ecoreTypesFragmentPrefix + name))
                }
                continue
            }
            hrefs.append((kind, reference.href))
        }
        return (identifiers, hrefs)
    }

    /// Writes references to other documents as child elements.
    ///
    /// - Parameters:
    ///   - name: The EMOF name of the feature.
    ///   - hrefs: The references with the EMOF kinds of their targets.
    private mutating func writeHrefs(_ name: String, _ hrefs: [(kind: String?, href: String)]) {
        for (kind, href) in hrefs {
            var attributes: [(String, String)] = []
            if let kind { attributes.append((XMITypeAttribute.xmi.rawValue, EMOFSyntax.prefix + ":" + kind)) }
            attributes.append((CrossReferenceSyntax.hrefAttribute, href))
            out.empty(name, attributes)
        }
    }

    // MARK: - Annotations and extensions

    /// Writes the Ecore extension of an element, if it has anything that EMOF cannot express.
    ///
    /// The extension holds the given features that the element sets, the given Ecore child
    /// elements, and every annotation that is neither a comment nor a tag.
    ///
    /// - Parameters:
    ///   - element: The Ecore element.
    ///   - features: The features to keep in the extension when they are set.
    ///   - copying: The Ecore child elements to keep in the extension as they are.
    private mutating func writeExtension(
        of element: XElement, features: [EcoreFeatureName], copying: [EcoreFeatureName] = []
    ) {
        let values = features.compactMap { feature in element[feature.rawValue].map { (feature.rawValue, $0) } }
        let copied = Array(element.children).filter { child in
            if child.name == EcoreFeatureName.eAnnotations.rawValue {
                return !Self.isEMOFAnnotation(child[EcoreFeatureName.source.rawValue] ?? "")
            }
            return copying.contains { $0.rawValue == child.name }
        }
        guard !values.isEmpty || !copied.isEmpty else { return }
        out.open(
            CrossReferenceSyntax.xmiPrefix + ":" + XMIDialectSyntax.extensionElement,
            [(XMIDialectSyntax.extender, EcoreURI.ecoreNamespace.rawValue)])
        for (name, value) in values { out.element(name, text: value) }
        for child in copied {
            out.copy(child)
            copiesEcore = true
        }
        out.close()
    }

    /// Whether an annotation is written as an EMOF comment or tag rather than in an extension.
    ///
    /// - Parameter source: The source of the annotation.
    /// - Returns: `true` for a source in the EMOF namespace.
    private static func isEMOFAnnotation(_ source: String) -> Bool {
        source.hasPrefix(EMOFSyntax.namespaceURI)
    }

    /// Writes the comments of an element and records its tags.
    ///
    /// An annotation with the comment source becomes an `ownedComment` with its `body`; one
    /// with another source in the EMOF namespace becomes an `ownedComment` whose nested
    /// comment holds the source. An annotation whose source is the EMOF namespace itself is a
    /// tag of the element and of the elements it refers to.
    ///
    /// - Parameter element: The Ecore element.
    private mutating func writeComments(of element: XElement) {
        for annotation in element.children(EcoreFeatureName.eAnnotations.rawValue) {
            let source = annotation[EcoreFeatureName.source.rawValue] ?? ""
            guard Self.isEMOFAnnotation(source) else { continue }
            var details: [String: String] = [:]
            for detail in annotation.children(EcoreFeatureName.details.rawValue) {
                if let key = detail[EcoreFeatureName.key.rawValue] {
                    details[key] = detail[EcoreFeatureName.value.rawValue] ?? ""
                }
            }
            if source == EMOFSyntax.namespaceURI {
                var tag = Tag(
                    identifier: "_tag\(tags.count)", name: details[EMOFSyntax.Name.name],
                    value: details[EMOFSyntax.Name.value],
                    elements: identifiers[ObjectIdentifier(element)].map { [$0] } ?? [], hrefs: [])
                let others = references(annotation[EcoreFeatureName.references.rawValue] ?? "")
                tag.elements += others.identifiers
                tag.hrefs += others.hrefs.map(\.href)
                tags.append(tag)
                continue
            }
            let body = [(EMOFSyntax.Name.body, details[EMOFSyntax.Name.body] ?? "")]
            if source == EMOFSyntax.commentSource {
                out.empty(EMOFSyntax.Name.ownedComment, body)
            } else {
                out.open(EMOFSyntax.Name.ownedComment, body)
                out.empty(EMOFSyntax.Name.ownedComment, [(EMOFSyntax.Name.body, source)])
                out.close()
            }
        }
    }
}
