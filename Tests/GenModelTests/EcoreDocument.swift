//
// EcoreDocument.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation
import SwiftXML

/// A minimal reader of the attributes of an Ecore document, independent of the library's loader.
///
/// The library's loader does not keep every Ecore attribute (for example `unsettable`, `derived`
/// and the flags of references), so tests that must see the document's complete content read it
/// through this plain XML view instead.
struct EcoreDocument {
    /// One element's attributes, with its children.
    struct Node {
        let tag: String
        let attributes: [String: String]
        let children: [Node]

        subscript(_ name: String) -> String? { attributes[name] }

        func children(named tag: String) -> [Node] { children.filter { $0.tag == tag } }
    }

    /// The root package element.
    let root: Node

    /// Reads an Ecore document.
    ///
    /// - Parameter url: The location of the document.
    init(url: URL) throws {
        let document = try parseXML(fromPath: url.path)
        guard let element = document.children.first(where: { _ in true }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        root = Self.node(element)
    }

    private static func node(_ element: XElement) -> Node {
        var attributes: [String: String] = [:]
        for name in element.attributeNames { attributes[name] = element[name] }
        return Node(
            tag: element.name, attributes: attributes, children: element.children.map(node))
    }

    /// The classifiers of the root package.
    var classifiers: [Node] { root.children(named: "eClassifiers") }

    /// The classifier with a name.
    func classifier(_ name: String) -> Node? { classifiers.first { $0["name"] == name } }
}
