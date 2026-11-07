//
// XMLTree.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import SwiftXML

/// Reads and writes the XML of documents that are translated rather than parsed directly.
///
/// The readers of UML profiles and of EMOF examine the XML tree of a document before, or
/// instead of, handing it to an ``XMIParser``. This type gathers what they share: decoding
/// and parsing a document, the namespace declarations of an element, and the text of new
/// elements.
enum XMLTree {
    /// Parses a document into its XML tree.
    ///
    /// The document is decoded as the XMI parser decodes it (see
    /// ``DecodedText/init(decodingXML:encoding:)``).
    ///
    /// - Parameter data: The bytes of the document.
    /// - Returns: The root element.
    /// - Throws: ``XMIError/invalidEncoding`` if the document cannot be decoded, or
    ///   ``XMIError/invalidXML(_:)`` if it is not well formed or has no root element.
    static func root(of data: Data) throws -> XElement {
        let decoded: DecodedText
        do {
            decoded = try DecodedText(decodingXML: data)
        } catch {
            throw XMIError.invalidEncoding
        }
        let document: XDocument
        do {
            document = try parseXML(fromText: decoded.text)
        } catch {
            throw XMIError.invalidXML(String(describing: error))
        }
        guard let root = document.children.first else {
            throw XMIError.invalidXML("No root element found in document")
        }
        return root
    }

    /// The namespace declarations of an element, by prefix (empty for the default namespace).
    ///
    /// - Parameter element: The element.
    /// - Returns: The namespace URIs that the element itself declares.
    static func declaredNamespaces(of element: XElement) -> [String: String] {
        var namespaces: [String: String] = [:]
        let prefixed = XMLNamespace.prefixed("")
        for name in element.attributeNames {
            guard let value = element[name] else { continue }
            if name == XMLNamespace.xmlns {
                namespaces[""] = value
            } else if name.hasPrefix(prefixed) {
                namespaces[String(name.dropFirst(prefixed.count))] = value
            }
        }
        return namespaces
    }

    /// The namespace that a prefix denotes at an element, declared there or on an ancestor.
    ///
    /// - Parameters:
    ///   - prefix: The prefix, or the empty string for the default namespace.
    ///   - element: The element at which the prefix is used.
    /// - Returns: The namespace URI, or `nil` if the prefix is not declared.
    static func namespace(ofPrefix prefix: String, at element: XElement) -> String? {
        let key = prefix.isEmpty ? XMLNamespace.xmlns : XMLNamespace.prefixed(prefix)
        var current: XElement? = element
        while let scope = current {
            if let uri = scope[key] { return uri }
            current = scope.parent
        }
        return nil
    }

    /// Splits a qualified name into its prefix and local name.
    ///
    /// - Parameter qualifiedName: A name such as `emof:Class` or `Class`.
    /// - Returns: The prefix, empty for an unprefixed name, and the local name.
    static func parts(of qualifiedName: String) -> (prefix: String, local: String) {
        guard let separator = qualifiedName.firstIndex(of: CrossReferenceSyntax.qualifierSeparator) else {
            return ("", qualifiedName)
        }
        return (String(qualifiedName[..<separator]), String(qualifiedName[qualifiedName.index(after: separator)...]))
    }

    /// The namespace and local name of a qualified name used at an element.
    ///
    /// - Parameters:
    ///   - qualifiedName: A name such as `emof:Class`.
    ///   - element: The element at which the name is used.
    /// - Returns: The namespace URI of the prefix, if declared, and the local name.
    static func expandedName(_ qualifiedName: String, at element: XElement) -> (namespace: String?, local: String) {
        let (prefix, local) = parts(of: qualifiedName)
        return (namespace(ofPrefix: prefix, at: element), local)
    }
}

/// Builds the text of an XML document with two spaces of indentation per level.
struct XMLTextBuilder {
    /// The text built so far.
    private(set) var text = XMIDocumentSyntax.xmlDeclaration + "\n"

    /// The names of the elements that are open, innermost last.
    private var open: [String] = []

    /// The indentation of one level.
    private static let indentUnit = "  "

    /// The indentation of the current level.
    private var indentation: String { String(repeating: Self.indentUnit, count: open.count) }

    /// The text of the attributes of a start tag.
    ///
    /// - Parameter attributes: The attribute names and unescaped values, in order.
    /// - Returns: The attributes, each preceded by a space.
    private static func attributeText(_ attributes: [(String, String)]) -> String {
        attributes.map { " \($0.0)=\"\(XMISerializer.escapeAttribute($0.1))\"" }.joined()
    }

    /// The length of the text after the start tag of the innermost open element, while the
    /// element has no content yet.
    private var emptyOpenEnd: Int?

    /// Opens an element that may have children.
    ///
    /// An element that is closed without content is written as an empty-element tag.
    ///
    /// - Parameters:
    ///   - name: The qualified name of the element.
    ///   - attributes: The attribute names and unescaped values, in order.
    mutating func open(_ name: String, _ attributes: [(String, String)] = []) {
        text += indentation + "<" + name + Self.attributeText(attributes) + ">\n"
        open.append(name)
        emptyOpenEnd = text.utf8.count
    }

    /// Closes the innermost open element.
    mutating func close() {
        guard let name = open.popLast() else { return }
        if emptyOpenEnd == text.utf8.count {
            text.removeLast(2)
            text += "/>\n"
        } else {
            text += indentation + "</" + name + ">\n"
        }
        emptyOpenEnd = nil
    }

    /// Adds an element without children.
    ///
    /// - Parameters:
    ///   - name: The qualified name of the element.
    ///   - attributes: The attribute names and unescaped values, in order.
    mutating func empty(_ name: String, _ attributes: [(String, String)] = []) {
        text += indentation + "<" + name + Self.attributeText(attributes) + "/>\n"
    }

    /// Adds an element that holds text.
    ///
    /// - Parameters:
    ///   - name: The qualified name of the element.
    ///   - value: The unescaped text.
    mutating func element(_ name: String, text value: String) {
        text += indentation + "<" + name + ">" + XMISerializer().escapeXML(value) + "</" + name + ">\n"
    }

    /// Adds an element of another document with its attributes and descendants.
    ///
    /// The element is laid out like the rest of the document: white space between elements
    /// is replaced by the indentation of this builder, and the text of an element without
    /// child elements is kept.
    ///
    /// - Parameter element: The element to copy.
    mutating func copy(_ element: XElement) {
        let attributes = element.attributeNames.compactMap { name in element[name].map { (name, $0) } }
        let children = Array(element.children)
        if children.isEmpty {
            let content = element.immediateTextsCombined
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                empty(element.name, attributes)
            } else {
                text += indentation + "<" + element.name + Self.attributeText(attributes) + ">"
                    + XMISerializer().escapeXML(content) + "</" + element.name + ">\n"
            }
            return
        }
        open(element.name, attributes)
        for child in children { copy(child) }
        close()
    }
}

/// A namespace prefix of an XML document with the namespace URI bound to it.
struct XMLNamespaceBinding: Sendable, Hashable {
    /// The prefix, such as `uml`.
    var prefix: String

    /// The namespace URI bound to the prefix.
    var uri: String
}
