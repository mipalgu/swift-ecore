//
// XMIAttributeLayoutTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation
import Testing

@testable import ECore

@Suite("XMI attribute layout")
struct XMIAttributeLayoutTests {
    private let layout = XMIAttributeLayout(lineWidth: 80)

    /// An attribute whose text is exactly `width` characters wide.
    private func attribute(width: Int) -> String {
        let prefix = "a=\""
        return prefix + String(repeating: "x", count: width - prefix.count - 1) + "\""
    }

    @Test("without a line width all attributes share one line")
    func unwrapped() {
        let text = XMIAttributeLayout(lineWidth: nil).attributes(
            [attribute(width: 90), attribute(width: 90)], afterColumn: 10, indentation: 0)
        #expect(!text.contains("\n"))
    }

    @Test("an attribute that starts beyond the width begins a new line")
    func breaksBeyondWidth() {
        let text = layout.attributes(
            [attribute(width: 70), "b=\"1\""], afterColumn: 11, indentation: 2)
        #expect(text == " " + attribute(width: 70) + "\n      b=\"1\"")
    }

    @Test("a line that ends exactly at the width does not break")
    func boundary() {
        let atWidth = layout.attributes([attribute(width: 69), "b=\"1\""], afterColumn: 10, indentation: 0)
        #expect(!atWidth.contains("\n"))
        let beyond = layout.attributes([attribute(width: 70), "b=\"1\""], afterColumn: 10, indentation: 0)
        #expect(beyond.contains("\n"))
    }

    @Test("an attribute is never split, however long it is")
    func longAttribute() {
        let text = layout.attributes([attribute(width: 300), "b=\"1\""], afterColumn: 5, indentation: 0)
        #expect(text == " " + attribute(width: 300) + "\n    b=\"1\"")
    }

    @Test("continuation lines are indented four spaces beyond the element")
    func continuationIndent() {
        let text = layout.attributes(
            [attribute(width: 90), "b=\"1\""], afterColumn: 4, indentation: 6)
        #expect(text.hasSuffix("\n          b=\"1\""))
    }

    @Test("the width of a continuation line counts from its indentation")
    func widthAfterBreak() {
        let text = layout.attributes(
            [attribute(width: 90), attribute(width: 78), "c=\"1\""], afterColumn: 4, indentation: 0)
        #expect(text.components(separatedBy: "\n").count == 3)
        let shorter = layout.attributes(
            [attribute(width: 90), attribute(width: 70), "c=\"1\""], afterColumn: 4, indentation: 0)
        #expect(shorter.components(separatedBy: "\n").count == 2)
    }

    @Test("widths count UTF-16 code units")
    func utf16Widths() {
        let wide = "n=\"" + String(repeating: "\u{1F600}", count: 20) + "\""
        let text = layout.attributes([wide, "b=\"1\""], afterColumn: 40, indentation: 0)
        #expect(text.contains("\n"))
        let narrow = "n=\"" + String(repeating: "\u{00E9}", count: 20) + "\""
        #expect(!layout.attributes([narrow, "b=\"1\""], afterColumn: 40, indentation: 0).contains("\n"))
    }

    // MARK: Root element

    private let declarations = [
        "xmi:version=\"2.0\"", "xmlns:xmi=\"http://www.omg.org/XMI\"",
        "xmlns:ecore=\"http://www.eclipse.org/emf/2002/Ecore\"",
        "xmlns:demo=\"http://example.org/demo\"",
    ]

    @Test("declarations wrap after the line has grown beyond the width")
    func standardDeclarations() {
        let text = layout.rootTag(name: "demo:Root", declarations: declarations, attributes: [])
        #expect(
            text == """
                <demo:Root xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
                    xmlns:demo="http://example.org/demo"
                """.trimmingCharacters(in: .newlines))
    }

    @Test("root attributes are laid out as though the declarations were absent")
    func standardVirtualLayout() {
        let attributes = [attribute(width: 50), attribute(width: 20), attribute(width: 20)]
        let text = layout.rootTag(name: "demo:Root", declarations: declarations, attributes: attributes)
        let lines = text.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[1].hasPrefix("    xmlns:demo"))
        #expect(lines[1].hasSuffix(attribute(width: 20)))
        #expect(lines[2] == "    " + attribute(width: 20))
    }

    @Test("the first root attribute breaks only if the declarations ended beyond the width")
    func firstRootAttribute() {
        let short = ["xmi:version=\"2.0\"", "xmlns:xmi=\"http://www.omg.org/XMI\""]
        let sameLine = layout.rootTag(name: "demo:Root", declarations: short, attributes: ["a=\"1\""])
        #expect(!sameLine.contains("\n"))
        let long = short + ["xmlns:demo=\"http://example.org/a/very/long/namespace/uri/that/goes/on\""]
        let broken = layout.rootTag(name: "demo:Root", declarations: long, attributes: ["a=\"1\""])
        #expect(broken.hasSuffix("\n    a=\"1\""))
    }

    @Test("the version-first layout starts the declarations on a new line")
    func versionFirstDeclarations() {
        let versionFirst = XMIAttributeLayout(lineWidth: 80, rootLayout: .versionFirst)
        let text = versionFirst.rootTag(name: "demo:Root", declarations: declarations, attributes: [])
        #expect(
            text == """
                <demo:Root xmi:version="2.0"
                    xmlns:xmi="http://www.omg.org/XMI" xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
                    xmlns:demo="http://example.org/demo"
                """.trimmingCharacters(in: .newlines))
    }

    @Test("in the version-first layout the second root attribute always starts a line")
    func versionFirstAttributes() {
        let versionFirst = XMIAttributeLayout(lineWidth: 80, rootLayout: .versionFirst)
        let text = versionFirst.rootTag(
            name: "demo:Root", declarations: Array(declarations.prefix(2)),
            attributes: ["a=\"1\"", "b=\"2\"", "c=\"3\""])
        #expect(
            text == """
                <demo:Root xmi:version="2.0"
                    xmlns:xmi="http://www.omg.org/XMI" a="1"
                    b="2" c="3"
                """.trimmingCharacters(in: .newlines))
    }

    @Test("without a line width the root layouts agree")
    func unwrappedRoot() {
        let one = XMIAttributeLayout(lineWidth: nil, rootLayout: .versionFirst)
        let two = XMIAttributeLayout(lineWidth: nil, rootLayout: .standard)
        #expect(
            one.rootTag(name: "r", declarations: declarations, attributes: ["a=\"1\"", "b=\"2\""])
                == two.rootTag(name: "r", declarations: declarations, attributes: ["a=\"1\"", "b=\"2\""]))
    }

    @Test("a root layout is detected from the line after xmi:version")
    func detection() {
        #expect(XMIRootLayout.detect(in: "<r xmi:version=\"2.0\"\n    xmlns:xmi=\"x\">") == .versionFirst)
        #expect(XMIRootLayout.detect(in: "<r xmi:version=\"2.0\" xmlns:xmi=\"x\"\n    xmlns:a=\"y\">") == .standard)
        #expect(XMIRootLayout.detect(in: "<r xmi:version=\"2.0\" name=\"x\">") == .standard)
        #expect(XMIRootLayout.detect(in: "<r>") == .standard)
    }
}
