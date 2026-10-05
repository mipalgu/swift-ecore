//
// XMIAttributeLayout.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// Lays out the attributes of an element start tag the way the Eclipse Modeling Framework does.
///
/// With a line width, an attribute that follows a line that has grown beyond the width
/// begins a new line, indented ``continuationIndent`` spaces further than the element.
/// Without one, all attributes follow the element name on one line. Widths are counted in
/// UTF-16 code units, the unit in which the framework counts them.
struct XMIAttributeLayout {
    /// The number of spaces by which a continued attribute line is indented further than its element.
    static let continuationIndent = 4

    /// The width after which attributes continue on a new line, or `nil` for none.
    let lineWidth: Int?

    /// Lays out the attributes of an element.
    ///
    /// - Parameters:
    ///   - attributes: The attributes, each as `name="value"`.
    ///   - afterColumn: The width of the line once the element name has been written.
    ///   - indentation: The number of spaces that the element is indented.
    /// - Returns: The attribute text; each attribute is preceded by a space or a line break.
    func attributes(_ attributes: [String], afterColumn: Int, indentation: Int) -> String {
        var text = ""
        var column = afterColumn
        for attribute in attributes {
            let separator = separator(for: column, indentation: indentation)
            text += separator.text + attribute
            column = separator.isBreak ? separator.text.utf16.count - 1 + attribute.utf16.count : column + 1 + attribute.utf16.count
        }
        return text
    }

    /// Lays out the start tag of a root element that carries namespace declarations.
    ///
    /// The declarations are laid out in sequence after the element name. The element's own
    /// attributes are laid out as though the declarations were absent, with one exception:
    /// the first of them starts a new line if the declarations ended beyond the line width.
    ///
    /// - Parameters:
    ///   - name: The qualified element name.
    ///   - declarations: The declaration attributes, each as `name="value"`, starting with the version.
    ///   - attributes: The element's own attributes, each as `name="value"`.
    /// - Returns: The start tag text without its closing bracket.
    func rootTag(name: String, declarations: [String], attributes: [String]) -> String {
        let nameColumn = name.utf16.count + 1
        var text = "<" + name
        var column = nameColumn
        for declaration in declarations {
            let separator = separator(for: column, indentation: 0)
            text += separator.text + declaration
            column = separator.isBreak ? separator.text.utf16.count - 1 + declaration.utf16.count : column + 1 + declaration.utf16.count
        }
        guard let first = attributes.first else { return text }
        text += separator(for: column, indentation: 0).text + first
        text += self.attributes(
            Array(attributes.dropFirst()), afterColumn: nameColumn + 1 + first.utf16.count, indentation: 0)
        return text
    }

    /// Chooses what separates an attribute from the text before it.
    ///
    /// - Parameters:
    ///   - column: The width of the line so far.
    ///   - indentation: The number of spaces that the element is indented.
    /// - Returns: The separator text and whether it starts a new line.
    private func separator(for column: Int, indentation: Int) -> (text: String, isBreak: Bool) {
        guard let lineWidth, column > lineWidth else { return (" ", false) }
        return ("\n" + String(repeating: " ", count: indentation + Self.continuationIndent), true)
    }
}
