//
// XMIAttributeOrderTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation
import SwiftXML
import Testing

@testable import ECore

/// The attribute name extraction that preceded the single pass scanner, kept as an oracle.
///
/// For every element it searches the raw text for the first start tag whose attribute values
/// match, which takes time proportional to the document for each element.
struct ReferenceAttributeOrder {
    let rawXML: String

    func names(for element: XElement) -> [String] {
        var uniqueAttributes: [String: String] = [:]
        for attrName in element.attributeNames {
            if let value = element[attrName] { uniqueAttributes[attrName] = value }
        }
        let elementRegex = /<\s*\w*:?\w+(?:\s+([^>]*?))?\s*\/?>/
        for match in rawXML.matches(of: elementRegex) {
            guard let attributesCapture = match.1, !String(attributesCapture).isEmpty else { continue }
            let attributesString = String(attributesCapture)
            if attributesString.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let attrRegex = /(\w+(?::\w+)?)\s*=\s*"([^"]*)"|(\w+(?::\w+)?)\s*=\s*'([^']*)'/
            var found: [String: String] = [:]
            for attrMatch in attributesString.matches(of: attrRegex) {
                if let name = attrMatch.1, let value = attrMatch.2 {
                    found[String(name)] = String(value)
                } else if let name = attrMatch.3, let value = attrMatch.4 {
                    found[String(name)] = String(value)
                }
            }
            var isMatch = true
            for (attrName, expectedValue) in uniqueAttributes {
                if attrName.hasPrefix("xmlns") || attrName.hasPrefix("xmi:") { continue }
                if found[attrName] != expectedValue { isMatch = false; break }
            }
            if isMatch {
                var ordered: [String] = []
                let nameOnly = /(\w+(?::\w+)?)\s*=\s*(?:"[^"]*"|'[^']*')/
                for nameMatch in attributesString.matches(of: nameOnly) {
                    let name = String(nameMatch.1)
                    if element.attributeNames.contains(name) { ordered.append(name) }
                }
                if !ordered.isEmpty { return ordered }
            }
        }
        return element.attributeNames
    }
}

@Suite("XMI Attribute Order Tests")
struct XMIAttributeOrderTests {
    @Test("start tags list attribute names in document order")
    func startTagOrder() {
        let text = #"<a z="1" b='2' m:n="3"><b/><c y="1" x="2"/></a>"#
        #expect(
            XMIAttributeOrder.startTagAttributeNames(in: text)
                == [["z", "b", "m:n"], [], ["y", "x"]])
    }

    @Test("comments, CDATA, processing instructions, and doctypes are not elements")
    func nonElementMarkup() {
        let text = """
            <?xml version="1.0"?>
            <!DOCTYPE root [ <!ENTITY e "<fake a='1'/>"> ]>
            <!-- <ignored q="1"/> -->
            <root b="1" a="2"><![CDATA[<notanelement c="3"/>]]><child d="4" c=">"/></root>
            """
        #expect(
            XMIAttributeOrder.startTagAttributeNames(in: text) == [["b", "a"], ["d", "c"]])
    }

    @Test("attribute values may contain angle brackets, quotes, and newlines")
    func awkwardValues() {
        let text = "<a x=\"<>'\" y='\"' z=\"line\none\"\n   w = \"1\"/>"
        #expect(XMIAttributeOrder.startTagAttributeNames(in: text) == [["x", "y", "z", "w"]])
    }

    @Test("hyphenated and dotted attribute names are kept")
    func punctuatedNames() {
        let text = #"<a data-x="1" a.b="2" _u="3"/>"#
        #expect(XMIAttributeOrder.startTagAttributeNames(in: text) == [["data-x", "a.b", "_u"]])
    }

    @Test("an order index answers document order for every element of a parsed document")
    func indexMatchesElements() throws {
        let text = #"<r z="1" a="2"><c y="1" b="2"><d q="1" p="2"/></c><c x="1"/></r>"#
        let document = try parseXML(fromText: text)
        let order = XMIAttributeOrder(document: document, source: text)
        let root = try #require(document.children.first)
        #expect(order.names(for: root) == ["z", "a"])
        let all = Array(root.descendants)
        #expect(all.map { order.names(for: $0) } == [["y", "b"], ["q", "p"], ["x"]])
    }

    @Test("an element that the index does not know falls back to sorted names")
    func unknownElementFallsBack() throws {
        let document = try parseXML(fromText: #"<r b="1" a="2"/>"#)
        let other = try parseXML(fromText: #"<s b="1" a="2"/>"#)
        let order = XMIAttributeOrder(document: document, source: #"<r b="1" a="2"/>"#)
        let stranger = try #require(other.children.first)
        #expect(order.names(for: stranger) == ["a", "b"])
    }

    @Test("a source whose element count differs from the document yields the sorted fallback")
    func mismatchedSource() throws {
        let document = try parseXML(fromText: #"<r b="1" a="2"/>"#)
        let order = XMIAttributeOrder(document: document, source: #"<r b="1" a="2"/><extra/>"#)
        let root = try #require(document.children.first)
        #expect(order.names(for: root) == ["a", "b"])
    }

    @Test("results are identical to the reference extraction on a medium fixture")
    func identicalToReference() throws {
        let fixture = try TreeFixture(depth: 3, branching: 2)
        defer { fixture.remove() }
        let text = try String(
            contentsOf: fixture.directory.appendingPathComponent("instance.xmi"), encoding: .utf8)
        let document = try parseXML(fromText: text)
        let order = XMIAttributeOrder(document: document, source: text)
        let reference = ReferenceAttributeOrder(rawXML: text)
        let root = try #require(document.children.first)
        var count = 0
        for element in [root] + Array(root.descendants) {
            #expect(order.names(for: element) == reference.names(for: element))
            count += 1
        }
        #expect(count > 85)
    }
}
