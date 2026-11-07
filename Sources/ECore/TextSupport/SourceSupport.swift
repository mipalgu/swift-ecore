//
// SourceSupport.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// The kinds of outline node that the textual notations report.
enum OutlineKind {
    /// A package or subpackage.
    static let package = "package"

    /// A class.
    static let `class` = "class"

    /// An interface.
    static let interface = "interface"

    /// A data type.
    static let dataType = "datatype"

    /// An enumeration.
    static let enumeration = "enum"

    /// A literal of an enumeration.
    static let literal = "literal"

    /// An attribute.
    static let attribute = "attribute"

    /// A reference.
    static let reference = "reference"

    /// An operation.
    static let operation = "operation"
}

/// Builds the outline of a document from its declarations.
enum OutlineBuilder {
    /// The separator between the segments of an outline node identifier.
    static let pathSeparator = "/"

    /// The separator between the kind and the name in an identifier segment.
    static let kindSeparator = ":"

    /// The marker that numbers a repeated identifier.
    static let repeatMarker = "#"

    /// Builds the outline nodes of packages.
    ///
    /// Every node identifier is the path of kind and name segments from the root, such as
    /// `package:library/class:Book/attribute:title`, with `#2`, `#3` and so on appended
    /// to a repeated identifier so that identifiers stay unique.
    ///
    /// - Parameter packages: The packages of the document.
    /// - Returns: One node per package, with nested nodes for its contents.
    static func outline(of packages: [DraftPackage]) -> [OutlineNode] {
        var used: Set<String> = []
        return packages.map { node(for: $0, parent: nil, used: &used) }
    }

    /// Creates a unique identifier for an outline node.
    ///
    /// - Parameters:
    ///   - kind: The kind of the node.
    ///   - name: The name of the node.
    ///   - parent: The identifier of the parent node, if any.
    ///   - used: The identifiers already in use, which is updated.
    /// - Returns: The unique identifier.
    private static func identifier(kind: String, name: String, parent: String?, used: inout Set<String>) -> String {
        let segment = kind + kindSeparator + name
        let base = parent.map { $0 + pathSeparator + segment } ?? segment
        var candidate = base
        var suffix = 1
        while !used.insert(candidate).inserted {
            suffix += 1
            candidate = base + repeatMarker + String(suffix)
        }
        return candidate
    }

    /// Creates the outline node of a package.
    ///
    /// - Parameters:
    ///   - package: The package.
    ///   - parent: The identifier of the parent node, if any.
    ///   - used: The identifiers already in use, which is updated.
    /// - Returns: The node, with nested nodes for its contents.
    private static func node(for package: DraftPackage, parent: String?, used: inout Set<String>) -> OutlineNode {
        let identifier = identifier(kind: OutlineKind.package, name: package.name, parent: parent, used: &used)
        var children = package.classifiers.map { node(for: $0, parent: identifier, used: &used) }
        children += package.subpackages.map { node(for: $0, parent: identifier, used: &used) }
        return OutlineNode(
            id: identifier, kind: OutlineKind.package, name: package.name,
            detail: package.nsURI.isEmpty ? nil : package.nsURI, range: package.location.range,
            selectionRange: package.location.nameRange, children: children)
    }

    /// Creates the outline node of a classifier.
    ///
    /// - Parameters:
    ///   - classifier: The classifier.
    ///   - parent: The identifier of the parent node.
    ///   - used: The identifiers already in use, which is updated.
    /// - Returns: The node, with nested nodes for its members.
    private static func node(for classifier: DraftClassifier, parent: String, used: inout Set<String>) -> OutlineNode {
        let kind: String
        var detail: String?
        switch classifier.kind {
        case .class:
            kind = classifier.isInterface ? OutlineKind.interface : OutlineKind.class
            if !classifier.superTypes.isEmpty { detail = classifier.superTypes.map(\.text).joined(separator: ", ") }
        case .dataType:
            kind = OutlineKind.dataType
            detail = classifier.instanceTypeName
        case .enumeration:
            kind = OutlineKind.enumeration
        }
        let identifier = identifier(kind: kind, name: classifier.name, parent: parent, used: &used)
        var children: [OutlineNode] = []
        for literal in classifier.literals {
            children.append(OutlineNode(
                id: self.identifier(kind: OutlineKind.literal, name: literal.name, parent: identifier, used: &used),
                kind: OutlineKind.literal, name: literal.name, detail: String(literal.value),
                range: literal.location.range, selectionRange: literal.location.nameRange))
        }
        for feature in classifier.features {
            let featureKind = feature.kind == .reference ? OutlineKind.reference : OutlineKind.attribute
            children.append(OutlineNode(
                id: self.identifier(kind: featureKind, name: feature.name, parent: identifier, used: &used),
                kind: featureKind, name: feature.name,
                detail: feature.type.text + multiplicity(feature.lowerBound, feature.upperBound),
                range: feature.location.range, selectionRange: feature.location.nameRange))
        }
        for operation in classifier.operations {
            let parameters = operation.parameters.map { $0.type.text + multiplicity($0.lowerBound, $0.upperBound) }
            let result = operation.returnType.map { " : " + $0.text + multiplicity(operation.lowerBound, operation.upperBound) } ?? ""
            children.append(OutlineNode(
                id: self.identifier(kind: OutlineKind.operation, name: operation.name, parent: identifier, used: &used),
                kind: OutlineKind.operation, name: operation.name,
                detail: "(" + parameters.joined(separator: ", ") + ")" + result,
                range: operation.location.range, selectionRange: operation.location.nameRange))
        }
        return OutlineNode(
            id: identifier, kind: kind, name: classifier.name, detail: detail, range: classifier.location.range,
            selectionRange: classifier.location.nameRange, children: children)
    }

    /// A multiplicity in the common bracket notation, or nothing for the default `[0..1]`.
    ///
    /// - Parameters:
    ///   - lower: The lower bound.
    ///   - upper: The upper bound, `-1` for unbounded and `-2` for unspecified.
    /// - Returns: The bracketed multiplicity, or an empty text for `[0..1]`.
    static func multiplicity(_ lower: Int, _ upper: Int) -> String {
        if lower == 0 && upper == 1 { return "" }
        return "[" + MultiplicityText.bounds(lower, upper) + "]"
    }
}

/// Formats the bounds of a multiplicity in the shorthand that both notations share.
enum MultiplicityText {
    /// The symbol of an unbounded upper bound.
    static let unbounded = "*"

    /// The symbol of one or more values.
    static let oneOrMore = "+"

    /// The symbol of an optional value, or of an unspecified upper bound.
    static let optional = "?"

    /// The separator between the lower and the upper bound.
    static let rangeSeparator = ".."

    /// The upper bound that stands for no limit.
    static let unboundedValue = -1

    /// The upper bound that stands for an unspecified limit.
    static let unspecifiedValue = -2

    /// The text between the brackets of a multiplicity.
    ///
    /// - Parameters:
    ///   - lower: The lower bound.
    ///   - upper: The upper bound.
    /// - Returns: The shortest text for the bounds, such as `*`, `+`, `?`, `3` or `1..4`.
    static func bounds(_ lower: Int, _ upper: Int) -> String {
        switch (lower, upper) {
        case (0, unboundedValue): return unbounded
        case (1, unboundedValue): return oneOrMore
        case (0, 1): return optional
        case let (lower, upper) where lower == upper: return String(lower)
        default: return String(lower) + rangeSeparator + bound(upper)
        }
    }

    /// The text of an upper bound.
    ///
    /// - Parameter upper: The upper bound.
    /// - Returns: `*` for unbounded, `?` for unspecified, otherwise the number.
    static func bound(_ upper: Int) -> String {
        switch upper {
        case unboundedValue: return unbounded
        case unspecifiedValue: return optional
        default: return String(upper)
        }
    }

    /// Reads one bound of a multiplicity from its token.
    ///
    /// - Parameter text: The text of the bound token.
    /// - Returns: The bound value, or `nil` if the text is no bound.
    static func value(of text: String) -> Int? {
        switch text {
        case unbounded: return unboundedValue
        case oneOrMore: return unboundedValue
        case optional: return unspecifiedValue
        default: return Int(text.replacingOccurrences(of: "_", with: ""))
        }
    }
}

/// Classifies the tokens of a scan for tools such as editors.
struct TokenClassifier {
    /// The words that are keywords of the notation.
    var keywords: Set<String>

    /// The punctuation that is shown as an operator.
    var operators: Set<String>

    /// The words that are built-in type names of the notation.
    var typeNames: Set<String>

    /// Creates a classifier.
    ///
    /// - Parameters:
    ///   - keywords: The keywords of the notation.
    ///   - operators: The punctuation shown as operators.
    ///   - typeNames: The built-in type names.
    init(keywords: Set<String>, operators: Set<String>, typeNames: Set<String>) {
        self.keywords = keywords
        self.operators = operators
        self.typeNames = typeNames
    }

    /// The word values that are literals of the Boolean type.
    static let booleans: Set<String> = ["true", "false"]

    /// Classifies every token and comment of a scan.
    ///
    /// - Parameters:
    ///   - scan: The scanned text.
    ///   - overrides: Kinds that the parser assigned to tokens, by the start offset of the token.
    /// - Returns: The classified tokens in source order.
    func sourceTokens(of scan: LexicalScan, overrides: [Int: SourceTokenKind] = [:]) -> [SourceToken] {
        scan.allTokens.map { token in
            SourceToken(kind: overrides[token.range.start.utf8Offset] ?? kind(of: token), range: token.range)
        }
    }

    /// The default kind of a token, without parser context.
    ///
    /// - Parameter token: The token to classify.
    /// - Returns: The kind of the token.
    func kind(of token: TextToken) -> SourceTokenKind {
        switch token.kind {
        case .identifier:
            if token.isEscaped { return .identifier }
            if Self.booleans.contains(token.text) { return .boolean }
            if keywords.contains(token.text) { return .keyword }
            if typeNames.contains(token.text) { return .typeName }
            return .identifier
        case .string, .character: return .string
        case .integer, .real: return .number
        case .punctuation: return operators.contains(token.text) ? .operator : .punctuation
        case .lineComment, .blockComment: return .comment
        case .documentationComment: return .documentation
        case .invalid, .endOfFile: return .invalid
        }
    }
}
