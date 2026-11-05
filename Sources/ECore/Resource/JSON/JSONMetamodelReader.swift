//
// JSONMetamodelReader.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// Reads a metamodel document in JSON into the object graph from which native packages are made.
///
/// The objects are instances of the metaclasses of ``EcorePackage``, with the features that
/// the XMI parser gives the objects of an `.ecore` document: contained elements are held by
/// their identifiers, references within the document are resolved to the identifiers of
/// their targets, references to the classes and data types of Ecore to the identifiers of
/// those classifiers, and references to other documents are kept as ``ResourceProxy`` values.
struct JSONMetamodelReader {
    /// An element of the document.
    private struct Node {
        /// The identifier that the element and the native element made from it have.
        let id: EUUID

        /// The metaclass of the element.
        let metaclass: EcoreClassifier

        /// The members of the JSON object of the element.
        let members: OrderedJSON

        /// The positional fragment of the element, which names it in errors.
        let path: String

        /// The name of a named element.
        var name: String?

        /// The source of an annotation.
        var source: String?

        /// The elements that the element contains, in the order in which EMF lists them.
        var children: [Child] = []

        /// The objects that an annotation holds as free-form content.
        var contents: [EUUID] = []
    }

    /// An element as a child of its container.
    private struct Child {
        /// The containment feature that holds the child.
        let feature: EcoreFeatureName

        /// The position of the child in the feature.
        let index: Int

        /// The position of the child among the nodes.
        let node: Int

        /// Whether the child has a name-based fragment segment.
        let isNamed: Bool
    }

    /// The URI of the document.
    private let uri: String

    /// Whether missing names and namespaces are accepted.
    private let tolerant: Bool

    /// The elements of the document, containers before what they contain.
    private var nodes: [Node] = []

    /// The positions of the nodes of the root packages.
    private var roots: [Int] = []

    /// The objects of the document, by identifier, as they are built.
    private var objects: [EUUID: DynamicEObject] = [:]

    /// The identifiers of the objects in the order in which they are registered.
    private var order: [EUUID] = []

    /// Prepares to read a document.
    ///
    /// - Parameters:
    ///   - uri: The URI of the document, against which references are resolved.
    ///   - options: The load options; when they are tolerant, missing names and namespaces are
    ///     read as empty texts instead of being errors.
    init(uri: String, options: EcoreLoadOptions = EcoreLoadOptions()) {
        self.uri = uri
        self.tolerant = options.tolerant
    }

    /// Whether decoded JSON documents are a metamodel: every root names the `EPackage`
    /// metaclass of Ecore by its qualified name.
    ///
    /// - Parameter documents: The root objects of a document.
    /// - Returns: `true` if there is at least one root and every root is a package.
    static func isMetamodel(_ documents: [[String: Any]]) -> Bool {
        let packageClass = JSONMetamodelSyntax.className(.ePackage)
        return !documents.isEmpty && documents.allSatisfy { $0[JSONSyntax.eClassKey] as? String == packageClass }
    }

    /// Reads a document into a resource of objects that represent its packages.
    ///
    /// - Parameter data: The UTF-8 text of the document.
    /// - Returns: A resource with the URI of the document whose roots are the package objects.
    /// - Throws: ``JSONError`` if the document is not well-formed JSON, if a root is not a
    ///   package, if an `eClass` names no metaclass of Ecore or one that cannot be held where
    ///   it is, if a name is missing, or if a reference names no element.
    mutating func read(_ data: Data) async throws -> Resource {
        let document = try OrderedJSON.parse(data)
        let rootValues: [OrderedJSON]
        switch document {
        case .array(let values): rootValues = values
        case .object: rootValues = [document]
        default: throw JSONError.invalidFormat("\(uri) is neither an object nor an array of objects")
        }
        guard !rootValues.isEmpty else { throw JSONError.invalidFormat("\(uri) holds no package") }
        for (index, value) in rootValues.enumerated() {
            let path = rootValues.count == 1
                ? CrossReferenceSyntax.rootFragment : CrossReferenceSyntax.rootFragment + String(index)
            guard value.members != nil, let className = value[JSONSyntax.eClassKey]?.text,
                JSONMetamodelSyntax.metaclass(named: className) == .ePackage
            else {
                throw JSONError.invalidFormat(
                    "\(uri) is not a metamodel: its root \(path) is not an object of class "
                        + JSONMetamodelSyntax.className(.ePackage))
            }
            roots.append(try node(value, metaclass: .ePackage, path: path, isRoot: true))
        }
        for position in nodes.indices { try build(position) }
        let resource = Resource(uri: uri)
        let rootIDs = Set(roots.map { nodes[$0].id })
        for identifier in order where !rootIDs.contains(identifier) {
            if let object = objects[identifier] { await resource.register(object) }
        }
        await resource.add(contentsOf: roots.compactMap { objects[nodes[$0].id] })
        return resource
    }

    // MARK: Elements

    /// Records an element and everything it contains.
    ///
    /// - Parameters:
    ///   - value: The JSON object of the element.
    ///   - metaclass: The metaclass of the element.
    ///   - path: The positional fragment of the element.
    ///   - isRoot: Whether the element is a root package, which must have a namespace.
    /// - Returns: The position of the element among the nodes.
    private mutating func node(
        _ value: OrderedJSON, metaclass: EcoreClassifier, path: String, isRoot: Bool = false
    ) throws -> Int {
        let position = nodes.count
        let identifier = EUUID()
        nodes.append(Node(id: identifier, metaclass: metaclass, members: value, path: path))
        nodes[position].name = try name(of: value, metaclass: metaclass, path: path, isRoot: isRoot)
        nodes[position].source = value[EcoreFeatureName.source.rawValue]?.text
        var children: [Child] = []
        for containment in JSONMetamodelSyntax.containments(of: metaclass) {
            guard let held = value[containment.feature.rawValue] else { continue }
            let elements: [OrderedJSON]
            if case .array(let values) = held { elements = values } else { elements = [held] }
            for (index, element) in elements.enumerated() {
                let segment = String(CrossReferenceSyntax.positionalMarker) + containment.feature.rawValue
                    + (containment.isMany ? String(CrossReferenceSyntax.indexSeparator) + String(index) : "")
                let childPath = Self.childPath(path, segment)
                let kind = try self.metaclass(of: element, in: containment, path: childPath)
                children.append(Child(
                    feature: containment.feature, index: index,
                    node: try node(element, metaclass: kind, path: childPath), isNamed: containment.isNamed))
            }
        }
        if metaclass == .eAnnotation {
            children += try details(of: value, annotation: identifier, path: path)
            nodes[position].contents = try contents(of: value, path: path)
        }
        nodes[position].children = children
        return position
    }

    /// The path of a child element.
    ///
    /// - Parameters:
    ///   - path: The path of the container.
    ///   - segment: The positional segment of the child.
    /// - Returns: The path of the child.
    private static func childPath(_ path: String, _ segment: String) -> String {
        path + String(CrossReferenceSyntax.segmentSeparator) + segment
    }

    /// The name of an element, checking that a named element has one.
    ///
    /// - Parameters:
    ///   - value: The JSON object of the element.
    ///   - metaclass: The metaclass of the element.
    ///   - path: The path of the element, for errors.
    ///   - isRoot: Whether the element is a root package, which must also have a namespace.
    /// - Returns: The name, an empty name for a missing one when the options are tolerant, or
    ///   `nil` for an element without a name.
    /// - Throws: ``JSONError/parseError(_:)`` if a name or namespace is missing.
    private func name(of value: OrderedJSON, metaclass: EcoreClassifier, path: String, isRoot: Bool) throws -> String? {
        let unnamed: Set<EcoreClassifier> = [.eAnnotation, .eGenericType, .eStringToStringMapEntry]
        guard !unnamed.contains(metaclass) else { return nil }
        let required: [EcoreFeatureName] = metaclass == .ePackage && isRoot ? [.name, .nsURI, .nsPrefix] : [.name]
        for feature in required where value[feature.rawValue]?.text == nil && !tolerant {
            throw JSONError.parseError(
                "The \(metaclass.rawValue) at \(path) of \(uri) has no '\(feature.rawValue)' text")
        }
        return value[EcoreFeatureName.name.rawValue]?.text ?? ""
    }

    /// The metaclass of an element held by a containment feature.
    ///
    /// An element without an `eClass` takes the metaclass that the feature implies, if it implies
    /// one.
    ///
    /// - Parameters:
    ///   - element: The JSON object of the element.
    ///   - containment: The feature that holds the element.
    ///   - path: The path of the element, for errors.
    /// - Returns: The metaclass.
    /// - Throws: ``JSONError`` if the element is not an object, names no metaclass of Ecore, or
    ///   names one that the feature cannot hold.
    private func metaclass(
        of element: OrderedJSON, in containment: JSONMetamodelSyntax.Containment, path: String
    ) throws -> EcoreClassifier {
        guard element.members != nil else {
            throw JSONError.parseError(
                "The '\(containment.feature.rawValue)' at \(path) of \(uri) is not a JSON object")
        }
        guard let className = element[JSONSyntax.eClassKey] else {
            guard containment.metaclasses.count == 1 else {
                throw JSONError.parseError(
                    "The element at \(path) of \(uri) has no '\(JSONSyntax.eClassKey)' that names its class")
            }
            return containment.metaclasses[0]
        }
        guard let name = className.text, let metaclass = JSONMetamodelSyntax.metaclass(named: name) else {
            throw JSONError.unresolvedMetamodel(
                "The Ecore metamodel defines no class \(className.text ?? "\(className)") (at \(path) of \(uri))")
        }
        guard containment.metaclasses.contains(metaclass) else {
            throw JSONError.parseError(
                "An \(metaclass.rawValue) cannot be held by '\(containment.feature.rawValue)' (at \(path) of \(uri))")
        }
        return metaclass
    }

    /// Records the detail entries of an annotation.
    ///
    /// Details are a JSON object of keys and texts, as emfjson writes a map; a list of objects
    /// with a `key` and a `value` is read as well.
    ///
    /// - Parameters:
    ///   - value: The JSON object of the annotation.
    ///   - annotation: The identifier of the annotation, from which those of the entries derive.
    ///   - path: The path of the annotation, for errors.
    /// - Returns: The entries as children of the annotation.
    /// - Throws: ``JSONError/parseError(_:)`` if the details are malformed.
    private mutating func details(of value: OrderedJSON, annotation: EUUID, path: String) throws -> [Child] {
        guard let details = value[EcoreFeatureName.details.rawValue] else { return [] }
        let entries: [(key: String, value: String)]
        switch details {
        case .object(let members):
            entries = try members.map { member in
                guard let text = member.value.text else {
                    throw JSONError.parseError("The detail '\(member.key)' at \(path) of \(uri) is not a text")
                }
                return (member.key, text)
            }
        case .array(let values):
            entries = values.map {
                ($0[EcoreFeatureName.key.rawValue]?.text ?? "", $0[EcoreFeatureName.value.rawValue]?.text ?? "")
            }
        default:
            throw JSONError.parseError("The details at \(path) of \(uri) are neither an object nor an array")
        }
        var children: [Child] = []
        for (index, entry) in entries.enumerated() {
            let entryPath = Self.childPath(
                path, String(CrossReferenceSyntax.positionalMarker) + EcoreFeatureName.details.rawValue
                    + String(CrossReferenceSyntax.indexSeparator) + String(index))
            let members = OrderedJSON.object([
                OrderedJSON.Member(key: EcoreFeatureName.key.rawValue, value: .string(entry.key)),
                OrderedJSON.Member(key: EcoreFeatureName.value.rawValue, value: .string(entry.value)),
            ])
            children.append(Child(feature: .details, index: index, node: nodes.count, isNamed: false))
            nodes.append(Node(
                id: ReflectiveValues.derivedID(from: annotation, key: entry.key),
                metaclass: .eStringToStringMapEntry, members: members, path: entryPath))
        }
        return children
    }

    /// Builds the objects that an annotation holds as free-form content.
    ///
    /// Each object keeps its class and its text, Boolean and integer values.
    ///
    /// - Parameters:
    ///   - value: The JSON object of the annotation.
    ///   - path: The path of the annotation, for errors.
    /// - Returns: The identifiers of the objects.
    /// - Throws: ``JSONError/parseError(_:)`` if a content is not an object.
    private mutating func contents(of value: OrderedJSON, path: String) throws -> [EUUID] {
        guard let contents = value[EcoreFeatureName.contents.rawValue] else { return [] }
        let elements: [OrderedJSON]
        if case .array(let values) = contents { elements = values } else { elements = [contents] }
        var identifiers: [EUUID] = []
        for element in elements {
            guard let members = element.members else {
                throw JSONError.parseError("The contents at \(path) of \(uri) are not JSON objects")
            }
            let className = element[JSONSyntax.eClassKey]?.text ?? ""
            let metaclass = JSONMetamodelSyntax.metaclass(named: className).map { EcorePackage.metaClass($0) }
                ?? EClass(name: String(className.split(separator: CrossReferenceSyntax.segmentSeparator).last ?? ""))
            var object = DynamicEObject(eClass: metaclass)
            for member in members where member.key != JSONSyntax.eClassKey {
                if let primitive = Self.primitive(member.value) { object.eSet(member.key, value: primitive) }
            }
            objects[object.id] = object
            order.append(object.id)
            identifiers.append(object.id)
        }
        return identifiers
    }

    // MARK: Objects

    /// Builds the object of a node with its values, contained elements and resolved references.
    ///
    /// - Parameter position: The position of the node.
    /// - Throws: ``JSONError/parseError(_:)`` if a reference names no element.
    private mutating func build(_ position: Int) throws {
        let node = nodes[position]
        var object = DynamicEObject(id: node.id, eClass: EcorePackage.metaClass(node.metaclass))
        let structural = Set(JSONMetamodelSyntax.containments(of: node.metaclass).map(\.feature.rawValue)
            + JSONMetamodelSyntax.references(of: node.metaclass).map(\.feature.rawValue)
            + [JSONSyntax.eClassKey, EcoreFeatureName.details.rawValue, EcoreFeatureName.contents.rawValue])
        for member in node.members.members ?? [] where !structural.contains(member.key) {
            if let primitive = Self.primitive(member.value) { object.eSet(member.key, value: primitive) }
        }
        if let name = node.name { object.eSet(EcoreFeatureName.name.rawValue, value: name) }
        for containment in JSONMetamodelSyntax.containments(of: node.metaclass) {
            let held = node.children.filter { $0.feature == containment.feature }.map { nodes[$0.node].id }
            guard !held.isEmpty else { continue }
            if containment.isMany { object.eSet(containment.feature.rawValue, value: held) }
            else { object.eSet(containment.feature.rawValue, value: held[0]) }
        }
        let details = node.children.filter { $0.feature == .details }.map { nodes[$0.node].id }
        if !details.isEmpty { object.eSet(EcoreFeatureName.details.rawValue, value: details) }
        if !node.contents.isEmpty { object.eSet(EcoreFeatureName.contents.rawValue, value: node.contents) }
        for reference in JSONMetamodelSyntax.references(of: node.metaclass) {
            guard let value = node.members[reference.feature.rawValue] else { continue }
            let targets = try resolve(value, of: reference, at: node.path)
            if let stored = Self.stored(targets, isMany: reference.isMany) {
                object.eSet(reference.feature.rawValue, value: stored)
            }
        }
        objects[object.id] = object
        order.append(object.id)
    }

    /// The value of a primitive JSON value.
    ///
    /// - Parameter value: The JSON value.
    /// - Returns: The text, number or flag, or `nil` for any other value.
    private static func primitive(_ value: OrderedJSON) -> (any EcoreValue)? {
        switch value {
        case .string(let text): return text
        case .integer(let number): return number
        case .boolean(let flag): return flag
        case .number(let number): return number
        default: return nil
        }
    }

    /// The value in which a reference feature holds its targets.
    ///
    /// Targets of one kind are held as a list of identifiers or proxies; a list that mixes
    /// both is held as an ``EcoreValueArray``.
    ///
    /// - Parameters:
    ///   - targets: The resolved targets, in order.
    ///   - isMany: Whether the feature holds a list.
    /// - Returns: The value to store, or `nil` if there are no targets.
    private static func stored(_ targets: [any EcoreValue], isMany: Bool) -> (any EcoreValue)? {
        guard !targets.isEmpty else { return nil }
        guard isMany else { return targets[0] }
        let identifiers = targets.compactMap { $0 as? EUUID }
        if identifiers.count == targets.count { return identifiers }
        let proxies = targets.compactMap { $0 as? ResourceProxy }
        if proxies.count == targets.count { return proxies }
        return EcoreValueArray(targets)
    }

    // MARK: References

    /// Resolves the `$ref` objects (or bare reference texts) of a reference feature.
    ///
    /// - Parameters:
    ///   - value: The value of the feature: one reference or an array of references.
    ///   - reference: The reference feature.
    ///   - path: The path of the referring element, for errors.
    /// - Returns: The targets, in order.
    /// - Throws: ``JSONError/parseError(_:)`` if an entry is not a reference or names no element.
    private func resolve(
        _ value: OrderedJSON, of reference: JSONMetamodelSyntax.Reference, at path: String
    ) throws -> [any EcoreValue] {
        let entries: [OrderedJSON]
        if case .array(let values) = value { entries = values } else { entries = [value] }
        return try entries.map { entry in
            let text: String
            if let reference = entry[JSONSyntax.referenceKey]?.text {
                text = reference
            } else if let bare = entry.text {
                text = bare
            } else {
                throw JSONError.parseError(
                    "The '\(reference.feature.rawValue)' at \(path) of \(uri) is not a "
                        + "'\(JSONSyntax.referenceKey)' object")
            }
            let qualifier = entry[JSONSyntax.eClassKey]?.text.flatMap { JSONMetamodelSyntax.metaclass(named: $0) }
            return try target(of: text, qualifier: qualifier, feature: reference.feature, at: path)
        }
    }

    /// Resolves the text of one reference.
    ///
    /// - Parameters:
    ///   - text: The reference, a fragment of this document or a document URI and fragment.
    ///   - qualifier: The metaclass that the reference names for its target, if any.
    ///   - feature: The reference feature, for errors.
    ///   - path: The path of the referring element, for errors.
    /// - Returns: The identifier of an element of this document or of Ecore, or a proxy.
    /// - Throws: ``JSONError/parseError(_:)`` if the reference names no element.
    private func target(
        of text: String, qualifier: EcoreClassifier?, feature: EcoreFeatureName, at path: String
    ) throws -> any EcoreValue {
        let parts = URIReference.split(text)
        let fragment = parts.fragment ?? text
        let location = parts.fragment == nil ? "" : parts.uri
        let dangling = JSONError.parseError(
            "The '\(feature.rawValue)' reference \(text) at \(path) of \(uri) names no element")
        if location.isEmpty || URIReference.canonicalise(URIReference.resolve(location, against: uri)) == uri {
            guard let identifier = resolve(fragment: fragment) else { throw dangling }
            return identifier
        }
        if location == EcorePackage.nsURI {
            let name = fragment.split(separator: CrossReferenceSyntax.segmentSeparator).last.map(String.init) ?? ""
            if let classifier = EcorePackage.classifier(named: name) { return classifier.id }
            let typeFeatures: Set<EcoreFeatureName> = [.eType, .eSuperTypes, .eExceptions, .eClassifier]
            if typeFeatures.contains(feature) { throw dangling }
        }
        return ResourceProxy(
            uri: URIReference.resolve(location, against: uri), fragment: fragment,
            qualifier: qualifier.map { JSONMetamodelSyntax.qualifier($0) })
    }

    /// Resolves a fragment to an element of the document.
    ///
    /// Name-based fragments (`//Machine/tools`, `//Speed/Fast`, `//%source%`, with `.n` for
    /// a later element of the same name), positional fragments (`//@eClassifiers.2`), and
    /// mixtures of both are understood. The first segment selects the root: empty for the
    /// first root, or the position of the root in a document with several.
    ///
    /// - Parameter fragment: The fragment, with or without a leading `#`.
    /// - Returns: The identifier of the element, or `nil` if the fragment names none.
    private func resolve(fragment text: String) -> EUUID? {
        var fragment = Substring(text)
        if fragment.first == CrossReferenceSyntax.fragmentSeparator { fragment = fragment.dropFirst() }
        if fragment.isEmpty || fragment == CrossReferenceSyntax.rootFragment { return roots.first.map { nodes[$0].id } }
        guard fragment.first == CrossReferenceSyntax.segmentSeparator else { return nil }
        let segments = fragment.dropFirst().split(
            separator: CrossReferenceSyntax.segmentSeparator, omittingEmptySubsequences: false
        ).map(String.init)
        guard let rootSegment = segments.first else { return nil }
        var current: Int
        if rootSegment.isEmpty, let first = roots.first {
            current = first
        } else if let index = Int(rootSegment), roots.indices.contains(index) {
            current = roots[index]
        } else {
            return nil
        }
        for segment in segments.dropFirst() {
            guard let next = child(of: nodes[current], segment: segment) else { return nil }
            current = next
        }
        return nodes[current].id
    }

    /// The child of an element that a fragment segment names.
    ///
    /// - Parameters:
    ///   - node: The containing element.
    ///   - segment: A name-based or positional segment.
    /// - Returns: The position of the child, or `nil` if there is none.
    private func child(of node: Node, segment: String) -> Int? {
        guard let first = segment.first else { return nil }
        if first == CrossReferenceSyntax.positionalMarker {
            let body = segment.dropFirst()
            var feature = String(body)
            var index = 0
            if let separator = body.lastIndex(of: CrossReferenceSyntax.indexSeparator),
                let position = Int(body[body.index(after: separator)...])
            {
                feature = String(body[..<separator])
                index = position
            }
            return node.children.first { $0.feature.rawValue == feature && $0.index == index }?.node
        }
        let (name, count) = Self.counted(segment)
        let marker = EcoreFragment.annotationMarker
        if first == marker, name.count >= 2, name.last == marker {
            let source = EcoreFragment.decode(String(name.dropFirst().dropLast()))
            let annotations = node.children.filter { $0.feature == .eAnnotations }.map(\.node)
                .filter { (nodes[$0].source ?? "") == source }
            if annotations.indices.contains(count) { return annotations[count] }
        }
        let named = node.children.filter { $0.isNamed && $0.feature != .eAnnotations }.map(\.node)
        let wanted = name == EcoreFragment.missingName ? "" : EcoreFragment.decode(name)
        let matches = named.filter { nodes[$0].name == wanted }
        if matches.indices.contains(count) { return matches[count] }
        return named.first { nodes[$0].name == EcoreFragment.decode(segment) }
    }

    /// Splits a segment into a name and the number of earlier siblings of that name.
    ///
    /// - Parameter segment: The segment.
    /// - Returns: The name and the count, which is zero without a `.n` suffix.
    private static func counted(_ segment: String) -> (name: String, count: Int) {
        guard let separator = segment.lastIndex(of: CrossReferenceSyntax.indexSeparator),
            let count = Int(segment[segment.index(after: separator)...])
        else { return (segment, 0) }
        return (String(segment[..<separator]), count)
    }
}
