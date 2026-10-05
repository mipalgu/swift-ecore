//
// EcoreValidationSyntax.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The names and syntax rules that metamodel validation relies on.
enum EcoreValidationSyntax {
    // MARK: Vocabulary

    /// The instance class name that marks a class as a map entry.
    static let mapEntryInstanceClassName = "java.util.Map$Entry"

    /// The name of the key feature of a map entry class.
    static let mapEntryKey = "key"

    /// The name of the value feature of a map entry class.
    static let mapEntryValue = "value"

    /// The namespace URI of XML itself, whose prefix may start with `xml`.
    static let xmlNamespaceURI = "http://www.w3.org/XML/1998/namespace"

    /// The prefix that namespace prefixes must not start with, in any case.
    static let reservedPrefix = "xml"

    /// The instance class names that denote a Boolean.
    static let booleanInstanceClassNames: Set<String> = ["boolean", "Swift.Bool"]

    /// The prefix of the getter of a feature.
    static let getPrefix = "get"

    /// The prefix of the getter of a single-valued Boolean feature.
    static let booleanGetPrefix = "is"

    /// The prefix of the setter of a feature.
    static let setPrefix = "set"

    /// The prefix of the operation that tells whether an unsettable feature is set.
    static let isSetPrefix = "isSet"

    /// The prefix of the operation that unsets an unsettable feature.
    static let unsetPrefix = "unset"

    /// The separator between a class name and a feature name in a qualified name.
    static let qualifiedNameSeparator = "."

    /// The upper bound that means unbounded.
    static let unbounded = -1

    /// The upper bound that means unspecified.
    static let unspecified = -2

    // MARK: Names

    /// The text of a name with case and underscores removed, which similar names share.
    ///
    /// - Parameter name: A name.
    /// - Returns: The lower-cased name without underscores.
    static func similarityKey(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: "").lowercased()
    }

    /// Whether a name is a well-formed Java identifier that does not contain a dollar sign.
    ///
    /// - Parameter name: A name.
    /// - Returns: `true` for a non-empty name that starts with a letter, currency symbol
    ///   other than the dollar sign, or connecting punctuation, and continues with those or
    ///   with digits, combining marks, or ignorable characters.
    static func isWellFormedIdentifier(_ name: String) -> Bool {
        var first = true
        for scalar in name.unicodeScalars {
            guard scalar != "$" else { return false }
            if first ? !isIdentifierStart(scalar) : !isIdentifierPart(scalar) { return false }
            first = false
        }
        return !first
    }

    /// Whether a character can start a Java identifier (including the dollar sign).
    private static func isIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
            .letterNumber, .currencySymbol, .connectorPunctuation:
            return true
        default:
            return false
        }
    }

    /// Whether a character can continue a Java identifier.
    private static func isIdentifierPart(_ scalar: Unicode.Scalar) -> Bool {
        if isIdentifierStart(scalar) { return true }
        switch scalar.properties.generalCategory {
        case .decimalNumber, .nonspacingMark, .spacingMark, .format:
            return true
        case .control:
            return scalar.value <= 0x08 || (0x0E...0x1B).contains(scalar.value)
                || (0x7F...0x9F).contains(scalar.value)
        default:
            return false
        }
    }

    /// Whether a text is an XML name without a colon.
    ///
    /// - Parameter text: The text to test.
    /// - Returns: `true` for a non-empty text that starts with a letter or underscore and
    ///   continues with letters, digits, dots, hyphens, underscores, or combining marks.
    static func isNCName(_ text: String) -> Bool {
        var first = true
        for scalar in text.unicodeScalars {
            let category = scalar.properties.generalCategory
            let isLetter = scalar == "_" || scalar.properties.isAlphabetic
                || category == .letterNumber
            if first {
                if !isLetter { return false }
            } else if !isLetter {
                switch category {
                case .decimalNumber, .nonspacingMark, .spacingMark, .enclosingMark, .modifierLetter:
                    break
                default:
                    if scalar != "." && scalar != "-" && scalar != "\u{B7}" { return false }
                }
            }
            first = false
        }
        return !first
    }

    // MARK: URIs

    /// Whether a text is a well-formed URI reference.
    ///
    /// - Parameter text: The text to test.
    /// - Returns: `true` for a non-empty text without spaces, control characters, or
    ///   characters that URIs must escape, and whose percent signs begin escapes.
    static func isWellFormedURI(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let forbidden: Set<Unicode.Scalar> = ["\"", "<", ">", "\\", "^", "`", "{", "|", "}", " "]
        let scalars = Array(text.unicodeScalars)
        var position = 0
        while position < scalars.count {
            let scalar = scalars[position]
            if forbidden.contains(scalar) || scalar.properties.generalCategory == .control {
                return false
            }
            if scalar == "%" {
                guard position + 2 < scalars.count,
                    scalars[position + 1].properties.isASCIIHexDigit,
                    scalars[position + 2].properties.isASCIIHexDigit
                else { return false }
                position += 2
            }
            position += 1
        }
        return true
    }

    // MARK: Instance class names

    /// Whether a text is a well-formed instance class name.
    ///
    /// The accepted form is a dotted name, optionally followed by type arguments in angle
    /// brackets (separated by a comma and a space, each a type or a wildcard with an optional
    /// `extends` or `super` bound) and by any number of array brackets.
    ///
    /// - Parameter text: The instance class name.
    /// - Returns: `true` if the whole text has that form.
    static func isWellFormedInstanceClassName(_ text: String) -> Bool {
        var parser = InstanceClassNameParser(scalars: Array(text.unicodeScalars))
        return parser.parseType() && parser.atEnd
    }

    /// A recursive-descent parser for instance class names.
    private struct InstanceClassNameParser {
        let scalars: [Unicode.Scalar]
        var position = 0

        init(scalars: [Unicode.Scalar]) { self.scalars = scalars }

        var atEnd: Bool { position == scalars.count }

        private func peek(_ text: String) -> Bool {
            let wanted = Array(text.unicodeScalars)
            return position + wanted.count <= scalars.count
                && Array(scalars[position..<position + wanted.count]) == wanted
        }

        private mutating func take(_ text: String) -> Bool {
            guard peek(text) else { return false }
            position += text.unicodeScalars.count
            return true
        }

        private mutating func parseIdentifier() -> Bool {
            let start = position
            while position < scalars.count {
                let scalar = scalars[position]
                let allowed = position == start
                    ? EcoreValidationSyntax.isIdentifierStart(scalar)
                    : EcoreValidationSyntax.isIdentifierPart(scalar)
                if !allowed { break }
                position += 1
            }
            return position > start
        }

        mutating func parseType() -> Bool {
            guard parseIdentifier() else { return false }
            while take(".") {
                guard parseIdentifier() else { return false }
            }
            if take("<") {
                repeat {
                    guard parseArgument() else { return false }
                } while take(", ")
                guard take(">") else { return false }
            }
            while take("[]") {}
            return true
        }

        private mutating func parseArgument() -> Bool {
            if take("?") {
                if take(" extends ") || take(" super ") { return parseType() }
                return true
            }
            return parseType()
        }
    }
}
