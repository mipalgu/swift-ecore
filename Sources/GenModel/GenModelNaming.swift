//
// GenModelNaming.swift
// GenModel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// Language-neutral name formatting shared by all code generators.
///
/// The functions split names into words at underscores, at changes of case and at
/// digits, and recombine them in the shapes that generated code commonly needs:
/// capitalised, uncapitalised, and upper case with underscores. They know nothing
/// about the reserved words or naming conventions of any target language.
///
/// ## Example
///
/// ```swift
/// GenModelNaming.capName("loanDays")        // "LoanDays"
/// GenModelNaming.upperName("loanDays")      // "LOAN_DAYS"
/// GenModelNaming.upperName("XSDElement")    // "XSD_ELEMENT"
/// ```
public enum GenModelNaming {
    /// The word separator recognised in source names.
    public static let sourceSeparator: Character = "_"

    /// Capitalises the first character of a name.
    ///
    /// The remaining characters are left unchanged. An empty name is returned as is.
    ///
    /// - Parameter name: The name to capitalise.
    /// - Returns: The name with its first character in upper case.
    public static func capName(_ name: String) -> String {
        guard let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }

    /// Lowercases the first character of a name.
    ///
    /// The remaining characters are left unchanged. An empty name is returned as is.
    ///
    /// - Parameter name: The name to uncapitalise.
    /// - Returns: The name with its first character in lower case.
    public static func uncapName(_ name: String) -> String {
        guard let first = name.first else { return name }
        return first.lowercased() + name.dropFirst()
    }

    /// Lowercases the leading upper case run of a name, keeping the last capital of the run.
    ///
    /// A run of several leading capitals is lowered except for its last capital when
    /// that capital begins a further word, so that `XSDElementContent` becomes
    /// `xsdElementContent`. A name consisting only of capitals is lowered entirely, so
    /// that `CPU` becomes `cpu`.
    ///
    /// - Parameters:
    ///   - name: The name to uncapitalise.
    ///   - forceDifferent: If `true` and the lowered prefix equals the original prefix,
    ///     an underscore is prepended so that the result always differs from the input.
    /// - Returns: The uncapitalised name.
    public static func uncapPrefixedName(_ name: String, forceDifferent: Bool = false) -> String {
        let characters = Array(name)
        guard !characters.isEmpty else { return name }
        var prefixLength = 0
        while prefixLength < characters.count,
            characters[prefixLength].lowercased() != String(characters[prefixLength])
        {
            prefixLength += 1
        }
        if prefixLength > 1, prefixLength < characters.count,
            !isDigit(characters[prefixLength])
        {
            prefixLength -= 1
        }
        let prefix = String(characters[..<prefixLength])
        var lowered = prefix.lowercased()
        if forceDifferent && lowered == prefix {
            lowered = "_" + lowered
        }
        return lowered + String(characters[prefixLength...])
    }

    /// Converts a name to upper case words joined by underscores.
    ///
    /// Leading underscores of the source name are preserved as a single leading underscore.
    ///
    /// - Parameter name: The name to convert.
    /// - Returns: The upper case name, for example `LOAN_DAYS` for `loanDays`.
    public static func upperName(_ name: String) -> String {
        format(name, separator: "_", prefix: nil, includePrefix: false, includeLeadingSeparator: true)
            .uppercased()
    }

    /// Splits a name into words and rejoins them with another separator.
    ///
    /// Words are delimited by the source separator, by changes from lower to upper
    /// case, and by digits. A prefix can be recognised as a word of its own or be
    /// removed, and leading separators can be kept as a single leading separator.
    ///
    /// - Parameters:
    ///   - name: The name to format.
    ///   - separator: The character that joins the words of the result.
    ///   - prefix: An optional prefix that, when the name starts with it followed by an
    ///     upper case letter, is treated as a separate word or removed.
    ///   - includePrefix: Whether a recognised prefix is kept as the first word.
    ///   - includeLeadingSeparator: Whether leading underscores yield one leading underscore.
    /// - Returns: The reformatted name.
    public static func format(
        _ name: String,
        separator: Character,
        prefix: String?,
        includePrefix: Bool,
        includeLeadingSeparator: Bool = false
    ) -> String {
        var remaining = name
        var hasLeadingSeparator = false
        if includeLeadingSeparator, remaining.first == sourceSeparator {
            hasLeadingSeparator = true
            remaining = String(remaining.drop(while: { $0 == sourceSeparator }))
        }

        var words: [String] = []
        if let prefix, remaining.hasPrefix(prefix), remaining.count > prefix.count {
            let next = remaining[remaining.index(remaining.startIndex, offsetBy: prefix.count)]
            if isUpperCase(next) {
                remaining = String(remaining.dropFirst(prefix.count))
                if includePrefix {
                    words = parseName(prefix, separator: sourceSeparator)
                }
            }
        }
        if !remaining.isEmpty {
            words.append(contentsOf: parseName(remaining, separator: sourceSeparator))
        }

        var result = ""
        for (index, word) in words.enumerated() {
            result += word
            if index < words.count - 1 && word.count > 1 {
                result.append(separator)
            }
        }
        if result.isEmpty, let prefix {
            result = prefix
        }
        return hasLeadingSeparator ? "_" + result : result
    }

    /// Breaks a name into words at separators, case changes and digits.
    ///
    /// A run of capitals followed by a lower case letter ends before its last capital,
    /// so that `XSDElement` yields `XSD` and `Element`.
    ///
    /// - Parameters:
    ///   - name: The name to split.
    ///   - separator: The character that delimits words in the source name.
    /// - Returns: The words of the name, in order.
    public static func parseName(_ name: String, separator: Character) -> [String] {
        var result: [String] = []
        var word = ""
        var lastIsLower = false
        for character in name {
            if isUpperCase(character) || (!lastIsLower && isDigit(character))
                || character == separator
            {
                if (lastIsLower && word.count > 1) || (character == separator && !word.isEmpty) {
                    result.append(word)
                    word = ""
                }
                lastIsLower = false
            } else {
                if !lastIsLower, word.count > 1, let last = word.popLast() {
                    result.append(word)
                    word = String(last)
                }
                lastIsLower = true
            }
            if character != separator {
                word.append(character)
            }
        }
        result.append(word)
        return result
    }

    private static func isUpperCase(_ character: Character) -> Bool {
        if let ascii = character.asciiValue {
            return ascii >= 65 && ascii <= 90
        }
        return character.isUppercase
    }

    private static func isDigit(_ character: Character) -> Bool {
        if let ascii = character.asciiValue {
            return ascii >= 48 && ascii <= 57
        }
        return character.isNumber
    }
}
