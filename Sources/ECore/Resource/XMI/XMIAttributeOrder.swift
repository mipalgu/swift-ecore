//
// XMIAttributeOrder.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation
import SwiftXML

/// The order in which the attributes of each element appear in an XML document.
///
/// The XML library lists attributes alphabetically, but model instances list their
/// features in the order of the document. An index is built from the text of a document
/// in one pass over the text and one pass over the parsed elements, so that looking up
/// the order of an element takes constant time however large the document is.
///
/// If the text and the parsed document disagree about the number of elements (for example
/// because entities were expanded into elements), the index is empty and every lookup
/// answers the sorted names that the XML library provides.
struct XMIAttributeOrder {
    /// The attribute names of each element in document order, by element identity.
    private var namesByElement: [ObjectIdentifier: [String]] = [:]

    /// Creates an empty index that answers the sorted attribute names of every element.
    init() {}

    /// Creates the index of a parsed document.
    ///
    /// - Parameters:
    ///   - document: The parsed document.
    ///   - source: The text that the document was parsed from.
    init(document: XDocument, source: String) {
        let lists = Self.startTagAttributeNames(in: source)
        let elements = Array(document.descendants)
        guard elements.count == lists.count else { return }
        namesByElement.reserveCapacity(elements.count)
        for (element, names) in zip(elements, lists) {
            namesByElement[ObjectIdentifier(element)] = names
        }
    }

    /// The attribute names of an element in document order.
    ///
    /// Attributes that the document text lists but the parsed element does not have are
    /// omitted, and attributes of the parsed element that the text does not list follow
    /// in sorted order.
    ///
    /// - Parameter element: The parsed element.
    /// - Returns: The attribute names, in document order where the document is known.
    func names(for element: XElement) -> [String] {
        let known = element.attributeNames
        guard let listed = namesByElement[ObjectIdentifier(element)] else { return known }
        let present = Set(known)
        var result = listed.filter { present.contains($0) }
        if result.count != known.count {
            let seen = Set(result)
            result.append(contentsOf: known.filter { !seen.contains($0) })
        }
        return result
    }

    /// Lists the attribute names of every start tag of an XML text in document order.
    ///
    /// Comments, CDATA sections, processing instructions, declarations, and end tags are
    /// skipped. The result has one entry per element, in document order, so it lines up
    /// with a pre-order traversal of the parsed document.
    ///
    /// - Parameter text: The XML text.
    /// - Returns: For each element, the names of its attributes as written.
    static func startTagAttributeNames(in text: String) -> [[String]] {
        let bytes = Array(text.utf8)
        var result: [[String]] = []
        var position = 0
        while let open = bytes[position...].firstIndex(of: Byte.lessThan) {
            position = open + 1
            guard position < bytes.count else { break }
            switch bytes[position] {
            case Byte.exclamation:
                position = endOfDeclaration(in: bytes, from: position)
            case Byte.question:
                position = indexAfter(Array("?>".utf8), in: bytes, from: position)
            case Byte.slash:
                position = (bytes[position...].firstIndex(of: Byte.greaterThan) ?? bytes.count - 1) + 1
            default:
                result.append(scanStartTag(in: bytes, position: &position))
            }
        }
        return result
    }

    // MARK: Scanning

    private enum Byte {
        static let lessThan = UInt8(ascii: "<")
        static let greaterThan = UInt8(ascii: ">")
        static let exclamation = UInt8(ascii: "!")
        static let question = UInt8(ascii: "?")
        static let slash = UInt8(ascii: "/")
        static let equals = UInt8(ascii: "=")
        static let doubleQuote = UInt8(ascii: "\"")
        static let singleQuote = UInt8(ascii: "'")
        static let openBracket = UInt8(ascii: "[")
        static let closeBracket = UInt8(ascii: "]")
        static let hyphen = UInt8(ascii: "-")
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    /// The position after the first occurrence of a marker, or the end of the text.
    private static func indexAfter(_ marker: [UInt8], in bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index + marker.count <= bytes.count {
            if bytes[index] == marker[0], bytes[index..<index + marker.count].elementsEqual(marker) {
                return index + marker.count
            }
            index += 1
        }
        return bytes.count
    }

    /// The position after a comment, CDATA section, or declaration that starts at `<!`.
    private static func endOfDeclaration(in bytes: [UInt8], from start: Int) -> Int {
        let comment: [UInt8] = [Byte.exclamation, Byte.hyphen, Byte.hyphen]
        if bytes[start...].starts(with: comment) {
            return indexAfter(Array("-->".utf8), in: bytes, from: start + comment.count)
        }
        if bytes[start...].starts(with: Array("![CDATA[".utf8)) {
            return indexAfter(Array("]]>".utf8), in: bytes, from: start)
        }
        var depth = 0
        var quote: UInt8?
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if let open = quote {
                if byte == open { quote = nil }
            } else if byte == Byte.doubleQuote || byte == Byte.singleQuote {
                quote = byte
            } else if byte == Byte.openBracket {
                depth += 1
            } else if byte == Byte.closeBracket {
                depth -= 1
            } else if byte == Byte.greaterThan && depth <= 0 {
                return index + 1
            }
            index += 1
        }
        return bytes.count
    }

    /// Reads the attribute names of the start tag whose name begins at `position`.
    private static func scanStartTag(in bytes: [UInt8], position: inout Int) -> [String] {
        var names: [String] = []
        while position < bytes.count, !isSpace(bytes[position]), bytes[position] != Byte.slash,
            bytes[position] != Byte.greaterThan
        {
            position += 1
        }
        while position < bytes.count {
            while position < bytes.count, isSpace(bytes[position]) || bytes[position] == Byte.slash {
                position += 1
            }
            guard position < bytes.count, bytes[position] != Byte.greaterThan else {
                position += 1
                return names
            }
            let nameStart = position
            while position < bytes.count, !isSpace(bytes[position]), bytes[position] != Byte.equals,
                bytes[position] != Byte.slash, bytes[position] != Byte.greaterThan
            {
                position += 1
            }
            let name = String(decoding: bytes[nameStart..<position], as: UTF8.self)
            while position < bytes.count, isSpace(bytes[position]) { position += 1 }
            guard position < bytes.count, bytes[position] == Byte.equals else {
                if !name.isEmpty { names.append(name) }
                continue
            }
            position += 1
            while position < bytes.count, isSpace(bytes[position]) { position += 1 }
            guard position < bytes.count else { return names }
            let quote = bytes[position]
            if quote == Byte.doubleQuote || quote == Byte.singleQuote {
                position += 1
                while position < bytes.count, bytes[position] != quote { position += 1 }
                position += 1
            }
            names.append(name)
        }
        return names
    }
}
