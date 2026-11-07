//
// GrammarNaming.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// Naming rules shared by the grammar importers.
enum GrammarNaming {
    /// The package name used when neither the source, the options nor the source name give one.
    static let fallbackPackageName = "model"

    /// Turns arbitrary text into a name that Ecore accepts.
    ///
    /// Every character that cannot occur in an identifier becomes an underscore,
    /// and a name that would start with a digit, or be empty, gains a leading
    /// underscore.
    ///
    /// - Parameter text: The text to turn into a name, such as an SDF3 sort `STRING-CHAR`.
    /// - Returns: A valid identifier, such as `STRING_CHAR`.
    static func identifier(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            let isLetter = scalar.properties.isAlphabetic && scalar.isASCII
            let isDigit = scalar.value >= 0x30 && scalar.value <= 0x39
            result.unicodeScalars.append(isLetter || isDigit || scalar == "_" ? scalar : "_")
        }
        if result.isEmpty || result.unicodeScalars.first.map({ $0.value >= 0x30 && $0.value <= 0x39 }) == true {
            result = "_" + result
        }
        return result
    }

    /// The name with its first letter in lower case.
    ///
    /// A leading run of capitals is lowered as a whole, except for the last
    /// capital when it starts a new word, so `ID` becomes `id` and `URLPath`
    /// becomes `urlPath`. A name without lower-case letters, such as
    /// `STRING_CHAR`, is lowered as a whole.
    ///
    /// - Parameter name: The name to convert.
    /// - Returns: The converted name.
    static func lowerFirst(_ name: String) -> String {
        if !name.contains(where: \.isLowercase) { return name.lowercased() }
        let characters = Array(name)
        var upperRun = 0
        while upperRun < characters.count, characters[upperRun].isUppercase { upperRun += 1 }
        guard upperRun > 0 else { return name }
        if upperRun == characters.count { return name.lowercased() }
        let lowered = upperRun == 1 ? 1 : upperRun - 1
        return String(characters[..<lowered]).lowercased() + String(characters[lowered...])
    }

    /// The name with its first letter in upper case.
    ///
    /// - Parameter name: The name to convert.
    /// - Returns: The converted name.
    static func upperFirst(_ name: String) -> String {
        guard let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }

    /// Generates names for unnamed positional fields.
    ///
    /// The names follow the convention of the ASDL paper's generated code:
    /// the field type's name in lower case, followed by its occurrence among the
    /// fields of that type, so the fields of `Assign(identifier, exp)` are
    /// `identifier1` and `exp1`. A name given explicitly is kept, and a
    /// generated name never repeats a given one.
    ///
    /// - Parameter fields: For each field, its type name and its explicit name, if any.
    /// - Returns: The names, in the order of the fields.
    static func fieldNames(_ fields: [(typeName: String, name: String?)]) -> [String] {
        var taken = Set(fields.compactMap(\.name))
        var counts: [String: Int] = [:]
        return fields.map { field in
            if let name = field.name { return name }
            let base = lowerFirst(identifier(field.typeName))
            var candidate: String
            repeat {
                counts[base, default: 0] += 1
                candidate = base + String(counts[base]!)
            } while taken.contains(candidate)
            taken.insert(candidate)
            return candidate
        }
    }

    /// The namespace URI used when neither the source nor the options give one.
    ///
    /// - Parameters:
    ///   - notation: A short name of the notation, such as `asdl`.
    ///   - packageName: The name of the package.
    /// - Returns: A URN that names the notation and package, such as `urn:asdl:Python`.
    static func defaultNsURI(notation: String, packageName: String) -> String {
        "urn:" + notation + ":" + packageName
    }

    /// The namespace prefix used when neither the source nor the options give one.
    ///
    /// The prefix is the package name in lower case, made a valid XML name that
    /// does not start with the reserved letters `xml`.
    ///
    /// - Parameter packageName: The name of the package.
    /// - Returns: The prefix.
    static func defaultNsPrefix(packageName: String) -> String {
        let prefix = identifier(packageName).lowercased()
        return prefix.hasPrefix("xml") ? "_" + prefix : prefix
    }

    /// The package name to use for a source.
    ///
    /// - Parameters:
    ///   - declared: The name the source declares, if any.
    ///   - option: The name the options give, if any.
    ///   - sourceName: The name of the source document, if any; its last path
    ///     component without extension is used.
    /// - Returns: The first of the declared name, the option and the source
    ///   name, made a valid identifier, or ``fallbackPackageName``.
    static func packageName(declared: String?, option: String?, sourceName: String?) -> String {
        if let declared, !declared.isEmpty { return identifier(declared) }
        if let option, !option.isEmpty { return identifier(option) }
        if let sourceName {
            let last = sourceName.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? sourceName
            let stem = last.split(separator: ".").first.map(String.init) ?? last
            if !stem.isEmpty { return identifier(stem) }
        }
        return fallbackPackageName
    }
}
