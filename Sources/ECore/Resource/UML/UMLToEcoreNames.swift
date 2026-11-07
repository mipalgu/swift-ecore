//
// UMLToEcoreNames.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

extension UMLToEcore {
    /// The separator of words that camel case conversion recognises besides changes of case.
    static let wordSeparator: Character = "_"

    /// Converts a name into camel case as Eclipse UML2 does.
    ///
    /// The name is split into words at white space, at underscores and where the case changes
    /// (`XMLParser` is made of `XML` and `Parser`). Each word is written with an upper-case
    /// first letter and the rest in lower case; the first word starts with an upper-case
    /// letter only for names of classifiers and type parameters.
    ///
    /// - Parameters:
    ///   - name: The name to convert.
    ///   - capitalised: Whether the first word starts with an upper-case letter.
    /// - Returns: The name in camel case.
    static func camelCase(_ name: String, capitalised: Bool) -> String {
        var result = ""
        for (index, word) in words(of: name).enumerated() where !word.isEmpty {
            let first = String(word.prefix(1))
            result += index == 0 && !capitalised ? first.lowercased() : first.uppercased()
            result += word.dropFirst().lowercased()
        }
        return result
    }

    /// Splits a name into the words that camel case conversion capitalises.
    ///
    /// - Parameter name: The name.
    /// - Returns: The words, in order; the first may be empty if the name starts with a separator.
    static func words(of name: String) -> [String] {
        var result: [String] = []
        for part in name.split(omittingEmptySubsequences: false, whereSeparator: \.isWhitespace) {
            var current = ""
            var lastIsLower = false
            for character in part {
                if character.isUppercase || (!lastIsLower && character.isNumber) || character == wordSeparator {
                    if lastIsLower && current.count > 1 || character == wordSeparator && !current.isEmpty {
                        result.append(current)
                        current = ""
                    }
                    lastIsLower = false
                } else {
                    if !lastIsLower && current.count > 1 {
                        let last = current.removeLast()
                        result.append(current)
                        current = String(last)
                    }
                    lastIsLower = true
                }
                if character != wordSeparator { current.append(character) }
            }
            result.append(current)
        }
        return result
    }

    /// Makes a name a valid identifier as Eclipse UML2 does for Java.
    ///
    /// An empty name becomes `_`. A first character that cannot start an identifier is
    /// preceded by `_` (and dropped if it cannot occur in one either), and later characters
    /// that cannot occur in an identifier are dropped.
    ///
    /// - Parameter name: The name.
    /// - Returns: A valid identifier.
    static func validIdentifier(_ name: String) -> String {
        guard let first = name.first else { return String(wordSeparator) }
        var result = ""
        if isIdentifierStart(first) {
            result.append(first)
        } else {
            result.append(wordSeparator)
            if isIdentifierPart(first) { result.append(first) }
        }
        for character in name.dropFirst() where isIdentifierPart(character) { result.append(character) }
        return result
    }

    /// Whether a character can start a Java identifier.
    ///
    /// - Parameter character: The character.
    /// - Returns: `true` for letters, currency symbols and connecting punctuation such as `_`.
    static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character.isCurrencySymbol || character == wordSeparator
            || character.unicodeScalars.first?.properties.generalCategory == .connectorPunctuation
    }

    /// Whether a character can occur in a Java identifier after its first character.
    ///
    /// - Parameter character: The character.
    /// - Returns: `true` for the characters that can start one, digits and combining marks.
    static func isIdentifierPart(_ character: Character) -> Bool {
        if isIdentifierStart(character) || character.isNumber { return true }
        switch character.unicodeScalars.first?.properties.generalCategory {
        case .nonspacingMark, .spacingMark: return true
        default: return false
        }
    }

    /// Parses an annotation as the `annotations` tagged value of the Ecore profile writes it.
    ///
    /// The value is the source of the annotation followed by details of the form
    /// `key='value'` or `key="value"`, separated by white space. Backslash escapes as in Java
    /// string literals are recognised in the source, the keys and the values.
    ///
    /// - Parameter text: The tagged value.
    /// - Returns: The source and the details in order, or `nil` if the text holds no source.
    static func parseAnnotation(_ text: String) -> (source: String, details: [(String, String)])? {
        var scanner = AnnotationScanner(text)
        scanner.skipWhitespace()
        let source = scanner.token { $0.isWhitespace }
        guard !source.isEmpty else { return nil }
        var details: [(String, String)] = []
        while true {
            scanner.skipWhitespace()
            let key = scanner.token { $0.isWhitespace || $0 == "=" }
            scanner.skipWhitespace()
            guard !key.isEmpty, scanner.consume("="), let value = scanner.quoted() else { break }
            details.append((unescape(key), unescape(value)))
        }
        return (unescape(source), details)
    }

    /// Replaces the Java escape sequences of a text by the characters they stand for.
    ///
    /// - Parameter text: The text with escape sequences such as `\'`, `\n` or `A`.
    /// - Returns: The text with the sequences replaced.
    static func unescape(_ text: String) -> String {
        var result = ""
        var characters = Array(text)[...]
        while let character = characters.popFirst() {
            guard character == "\\", let next = characters.first else {
                result.append(character)
                continue
            }
            characters.removeFirst()
            switch next {
            case "b": result.append("\u{8}")
            case "t": result.append("\t")
            case "n": result.append("\n")
            case "f": result.append("\u{C}")
            case "r": result.append("\r")
            case "u":
                let digits = String(characters.prefix(4))
                if digits.count == 4, let value = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(value) {
                    result.unicodeScalars.append(scalar)
                    characters.removeFirst(4)
                } else {
                    result.append(next)
                }
            case "0"..."7":
                var digits = String(next)
                while digits.count < 3, let digit = characters.first, ("0"..."7").contains(digit) {
                    digits.append(characters.removeFirst())
                }
                if let value = UInt32(digits, radix: 8), let scalar = Unicode.Scalar(value) {
                    result.unicodeScalars.append(scalar)
                }
            default: result.append(next)
            }
        }
        return result
    }
}

/// Reads the parts of the `annotations` tagged value of the Ecore profile.
struct AnnotationScanner {
    /// The characters of the text.
    private let characters: [Character]

    /// The position of the next character.
    private var position = 0

    /// Creates a scanner at the start of a text.
    ///
    /// - Parameter text: The text to scan.
    init(_ text: String) {
        characters = Array(text)
    }

    /// Skips white space.
    mutating func skipWhitespace() {
        while position < characters.count, characters[position].isWhitespace { position += 1 }
    }

    /// Reads characters up to one that ends the token, keeping escape sequences as they are.
    ///
    /// - Parameter isEnd: Decides whether a character ends the token.
    /// - Returns: The token, possibly empty.
    mutating func token(until isEnd: (Character) -> Bool) -> String {
        var result = ""
        while position < characters.count {
            let character = characters[position]
            if character == "\\", position + 1 < characters.count {
                result.append(character)
                result.append(characters[position + 1])
                position += 2
                continue
            }
            if isEnd(character) { break }
            result.append(character)
            position += 1
        }
        return result
    }

    /// Consumes a character if it is next.
    ///
    /// - Parameter expected: The character.
    /// - Returns: Whether the character was next.
    mutating func consume(_ expected: Character) -> Bool {
        guard position < characters.count, characters[position] == expected else { return false }
        position += 1
        return true
    }

    /// Reads a value in single or double quotes, keeping escape sequences as they are.
    ///
    /// - Returns: The text between the quotes, or `nil` if no quoted value is next or it is not closed.
    mutating func quoted() -> String? {
        guard position < characters.count, characters[position] == "'" || characters[position] == "\"" else {
            return nil
        }
        let quote = characters[position]
        position += 1
        let value = token { $0 == quote }
        guard consume(quote) else { return nil }
        return value
    }
}
