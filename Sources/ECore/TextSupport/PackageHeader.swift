//
// PackageHeader.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The declaration with which a textual metamodel starts: annotations, then `package` and a
/// qualified name.
///
/// Emfatic and Xcore documents both start this way and differ in what follows the name: a
/// semicolon and the next declaration in Emfatic, and the next declaration directly in Xcore.
/// Recognising a format from the start of a document therefore reads the header and
/// examines the tokens after it. A declaration must follow, so that a lone line such as
/// `package shop;` is not taken for a document of either notation.
enum PackageHeader {
    /// The number of characters at the start of a text that are scanned, enough for a
    /// licence comment before the header.
    static let scannedLength = 16 * 1024

    /// The keyword that declares the package.
    static let packageKeyword = "package"

    /// The symbol that starts an annotation.
    static let annotationMarker = "@"

    /// The symbol that separates the parts of a qualified name.
    static let nameSeparator = "."

    /// The symbol that opens the arguments of an annotation.
    static let argumentsOpener = "("

    /// The symbol that closes the arguments of an annotation.
    static let argumentsCloser = ")"

    /// Whether a token starts a declaration of a notation: an annotation or a keyword.
    ///
    /// - Parameters:
    ///   - token: The token, or `nil` past the end of the scanned text.
    ///   - keywords: The keywords of the notation.
    /// - Returns: `true` if the token is the annotation marker or an unescaped keyword.
    static func startsDeclaration(_ token: TextToken?, keywords: Set<String>) -> Bool {
        guard let token else { return false }
        switch token.kind {
        case .punctuation: return token.text == annotationMarker
        case .identifier: return !token.isEscaped && keywords.contains(token.text)
        default: return false
        }
    }

    /// The tokens after the qualified name of the package declaration that starts a text.
    ///
    /// Comments and any annotations before the declaration are skipped. Only the first
    /// ``scannedLength`` characters are scanned.
    ///
    /// - Parameters:
    ///   - text: The start of the document.
    ///   - configuration: The lexical conventions of the notation.
    /// - Returns: The tokens after the name, ending with the end-of-file token, or `nil` if
    ///   the text does not start with a package declaration.
    static func tokensAfterName(in text: String, configuration: LexicalConfiguration) -> ArraySlice<TextToken>? {
        let tokens = TextLexer.scan(String(text.prefix(scannedLength)), configuration: configuration).tokens
        var index = 0
        func isSymbol(_ symbol: String, at position: Int) -> Bool {
            position < tokens.count && tokens[position].kind == .punctuation && tokens[position].text == symbol
        }
        func isName(at position: Int) -> Bool {
            position < tokens.count && tokens[position].kind == .identifier
        }
        func skipQualifiedName() -> Bool {
            guard isName(at: index) else { return false }
            index += 1
            while isSymbol(nameSeparator, at: index) {
                guard isName(at: index + 1) else { return false }
                index += 2
            }
            return true
        }
        while isSymbol(annotationMarker, at: index) {
            index += 1
            guard skipQualifiedName() else { return nil }
            guard isSymbol(argumentsOpener, at: index) else { continue }
            var depth = 0
            repeat {
                guard index < tokens.count, tokens[index].kind != .endOfFile else { return nil }
                if isSymbol(argumentsOpener, at: index) { depth += 1 }
                if isSymbol(argumentsCloser, at: index) { depth -= 1 }
                index += 1
            } while depth > 0
        }
        guard isName(at: index), tokens[index].text == packageKeyword else { return nil }
        index += 1
        guard skipQualifiedName(), index < tokens.count else { return nil }
        return tokens[index...]
    }
}
