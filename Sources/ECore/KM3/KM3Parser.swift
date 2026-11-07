//
// KM3Parser.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// Signals that a declaration could not be parsed; its diagnostic has been recorded.
private struct KM3SyntaxFailure: Error {}

/// Parses the tokens of KM3 text into a syntax tree, recovering from errors.
///
/// The grammar is that of the original KM3 concrete syntax:
///
/// ```text
/// document    ::= package*
/// package     ::= 'package' name '{' (package | datatype | enumeration | class)* '}'
/// datatype    ::= 'datatype' name ';'
/// enumeration ::= 'enumeration' name '{' ('literal' name ';')* '}'
/// class       ::= 'abstract'? 'class' name ('extends' name (',' name)*)?
///                 '{' (attribute | reference | operation)* '}'
/// attribute   ::= 'attribute' name multiplicity? 'ordered'? 'unique'? ':' name ';'
/// reference   ::= 'reference' name multiplicity? 'ordered'? 'container'?
///                 ('subsets' name (',' name)*)? ':' name ('oppositeOf' name)? ';'
/// operation   ::= 'operation' name '(' (name ':' name (',' name ':' name)*)? ')' (':' name)? ';'
/// multiplicity ::= '[' ('*' | integer '-' ('*' | integer)) ']'
/// ```
///
/// The parser accepts the modifiers of a feature in any order and a multiplicity of a
/// single bound (`[2]`), reporting the latter. Comments that precede a package declaration
/// can carry `-- @nsURI` and `-- @nsPrefix` directives. After an error the parser skips to
/// the next declaration it can recognise, so that every well-formed declaration is kept and
/// each problem has a diagnostic with a source range.
struct KM3Parser {
    /// The tokens without comments, ending with an end-of-file token.
    private let tokens: [KM3Token]

    /// The comments, in source order.
    private let comments: [KM3Token]

    /// The name of the document, for diagnostics.
    private let document: String?

    /// The index of the current token.
    private var position = 0

    /// The problems found so far.
    private(set) var diagnostics: [SourceDiagnostic] = []

    /// The reserved words that start a declaration inside a package.
    private static let elementStarts: Set<KM3Keyword> = [.package, .datatype, .enumeration, .abstract, .class]

    /// The reserved words that start a declaration inside a class.
    private static let memberStarts: Set<KM3Keyword> = [.attribute, .reference, .operation]

    /// The reserved words that are accepted, with an error, where a name is expected.
    private static let misusedNames: Set<KM3Keyword> = [
        .ordered, .unique, .container, .subsets, .oppositeOf, .extends,
    ]

    /// Creates a parser for a scan.
    ///
    /// - Parameters:
    ///   - scan: The tokens and comments of the text.
    ///   - document: The name of the document, which diagnostics carry.
    init(scan: KM3Scan, document: String?) {
        self.tokens = scan.tokens
        self.comments = scan.comments
        self.document = document
    }

    // MARK: Document

    /// Parses the whole text.
    ///
    /// - Returns: The package declarations, in source order.
    mutating func parseDocument() -> [KM3PackageNode] {
        var packages: [KM3PackageNode] = []
        while !isAtEnd {
            if current.isKeyword(.package) {
                packages.append(parsePackage())
            } else {
                skipUnexpected(expecting: "a package declaration") { $0.isKeyword(.package) }
            }
        }
        return packages
    }

    // MARK: Packages

    /// Parses a package declaration and everything it contains.
    ///
    /// - Returns: The package, which holds every element that could be parsed.
    private mutating func parsePackage() -> KM3PackageNode {
        let start = current.range.start
        let directives = packageDirectives(before: position)
        advance()
        let name = expectNameOrPlaceholder("a package name")
        var package = KM3PackageNode(
            name: name, nsURI: directives.nsURI, nsPrefix: directives.nsPrefix, range: rangeFromStart(start))
        guard openBody(of: "package '\(name.text)'") else {
            package.range = rangeFromStart(start)
            return package
        }
        while !isAtEnd && !current.isSymbol(KM3Symbol.closeBrace) {
            if Self.startsElement(current) {
                if let element = parseElement() { package.elements.append(element) }
            } else {
                skipUnexpected(expecting: "a classifier or package declaration") {
                    $0.isSymbol(KM3Symbol.closeBrace) || Self.startsElement($0)
                }
            }
        }
        closeBody(of: "package '\(name.text)'")
        package.range = rangeFromStart(start)
        return package
    }

    /// Parses a declaration inside a package; the current token starts one.
    ///
    /// - Returns: The declaration, or `nil` if it was abandoned after an error.
    private mutating func parseElement() -> KM3ElementNode? {
        guard case .keyword(let keyword) = current.kind else { return nil }
        let startIndex = position
        do {
            switch keyword {
            case .package: return .package(parsePackage())
            case .datatype: return .dataType(try parseDataType())
            case .enumeration: return .enumeration(try parseEnumeration())
            case .abstract, .class: return .class(try parseClass())
            default: return nil
            }
        } catch {
            recoverDeclaration(startedAt: startIndex)
            return nil
        }
    }

    /// Parses a data type declaration.
    ///
    /// - Returns: The data type.
    /// - Throws: ``KM3SyntaxFailure`` if the declaration is malformed.
    private mutating func parseDataType() throws -> KM3DataTypeNode {
        let start = current.range.start
        advance()
        let name = try expectName("a data type name")
        try expectTerminator(after: "data type '\(name.text)'", follows: Self.startsElementOrClose)
        return KM3DataTypeNode(name: name, range: rangeFromStart(start))
    }

    /// Parses an enumeration declaration and its literals.
    ///
    /// - Returns: The enumeration.
    /// - Throws: ``KM3SyntaxFailure`` if the header is malformed.
    private mutating func parseEnumeration() throws -> KM3EnumerationNode {
        let start = current.range.start
        advance()
        let name = try expectName("an enumeration name")
        var enumeration = KM3EnumerationNode(name: name, range: rangeFromStart(start))
        guard openBody(of: "enumeration '\(name.text)'") else { return enumeration }
        while !isAtEnd && !current.isSymbol(KM3Symbol.closeBrace) && !Self.startsElement(current) {
            guard current.isKeyword(.literal) else {
                skipUnexpected(expecting: "a literal declaration") {
                    $0.isKeyword(.literal) || $0.isSymbol(KM3Symbol.closeBrace) || Self.startsElement($0)
                }
                continue
            }
            let literalStart = current.range.start
            let startIndex = position
            do {
                advance()
                let literalName = try expectName("a literal name")
                try expectTerminator(after: "literal '\(literalName.text)'") {
                    $0.isKeyword(.literal) || $0.isSymbol(KM3Symbol.closeBrace)
                }
                enumeration.literals.append(KM3LiteralNode(name: literalName, range: rangeFromStart(literalStart)))
            } catch {
                recoverMember(startedAt: startIndex) { $0.isKeyword(.literal) }
            }
        }
        closeBody(of: "enumeration '\(name.text)'")
        enumeration.range = rangeFromStart(start)
        return enumeration
    }

    // MARK: Classes

    /// Parses a class declaration and its members.
    ///
    /// - Returns: The class.
    /// - Throws: ``KM3SyntaxFailure`` if the header is malformed.
    private mutating func parseClass() throws -> KM3ClassNode {
        let start = current.range.start
        var isAbstract = false
        if current.isKeyword(.abstract) {
            isAbstract = true
            advance()
        }
        guard current.isKeyword(.class) else {
            throw fail("Expected 'class' after 'abstract' but found \(describe(current))")
        }
        advance()
        let name = try expectName("a class name")
        var node = KM3ClassNode(name: name, isAbstract: isAbstract, range: rangeFromStart(start))
        if current.isKeyword(.extends) {
            advance()
            node.supertypes = try parseNameList("a supertype name")
        }
        guard openBody(of: "class '\(name.text)'") else {
            node.range = rangeFromStart(start)
            return node
        }
        while !isAtEnd && !current.isSymbol(KM3Symbol.closeBrace) && !Self.startsElement(current) {
            let startIndex = position
            do {
                if current.isKeyword(.attribute) {
                    node.features.append(try parseFeature(.attribute))
                } else if current.isKeyword(.reference) {
                    node.features.append(try parseFeature(.reference))
                } else if current.isKeyword(.operation) {
                    node.operations.append(try parseOperation())
                } else {
                    skipUnexpected(expecting: "an attribute, reference or operation declaration") {
                        Self.startsMember($0) || $0.isSymbol(KM3Symbol.closeBrace) || Self.startsElement($0)
                    }
                }
            } catch {
                recoverMember(startedAt: startIndex, stopsAt: Self.startsMember)
            }
        }
        closeBody(of: "class '\(name.text)'")
        node.range = rangeFromStart(start)
        return node
    }

    /// Parses an attribute or reference declaration.
    ///
    /// - Parameter kind: Whether the declaration is an attribute or a reference.
    /// - Returns: The feature.
    /// - Throws: ``KM3SyntaxFailure`` if the declaration is malformed.
    private mutating func parseFeature(_ kind: KM3FeatureNode.Kind) throws -> KM3FeatureNode {
        let start = current.range.start
        advance()
        let what = kind == .attribute ? "an attribute name" : "a reference name"
        let name = try expectName(what)
        var feature = KM3FeatureNode(kind: kind, name: name, range: rangeFromStart(start))
        if current.isSymbol(KM3Symbol.openBracket) { feature.multiplicity = try parseMultiplicity() }
        parseModifiers(of: &feature)
        if current.isKeyword(.subsets) {
            let keyword = current
            advance()
            feature.subsets = try parseNameList("the name of a subsetted feature")
            if kind == .attribute {
                report(.inapplicableModifier, "'subsets' applies to references only", keyword.range)
            }
        }
        try expectSymbol(KM3Symbol.colon, "before the type of '\(name.text)'")
        feature.type = try expectName("a type name")
        if current.isKeyword(.oppositeOf) {
            let keyword = current
            advance()
            feature.opposite = try expectName("the name of the opposite reference")
            if kind == .attribute {
                report(.inapplicableModifier, "'oppositeOf' applies to references only", keyword.range)
                feature.opposite = nil
            }
        }
        let description = (kind == .attribute ? "attribute" : "reference") + " '\(name.text)'"
        try expectTerminator(after: description, follows: Self.startsMemberOrClose)
        feature.range = rangeFromStart(start)
        return feature
    }

    /// Parses the `ordered`, `unique` and `container` modifiers of a feature.
    ///
    /// The modifiers may appear in any order. A repeated modifier, `unique` on a reference
    /// and `container` on an attribute are reported and otherwise ignored.
    ///
    /// - Parameter feature: The feature that receives the modifiers.
    private mutating func parseModifiers(of feature: inout KM3FeatureNode) {
        var seen: Set<KM3Keyword> = []
        while case .keyword(let keyword) = current.kind, [.ordered, .unique, .container].contains(keyword) {
            let token = current
            advance()
            guard seen.insert(keyword).inserted else {
                report(.inapplicableModifier, "'\(keyword.rawValue)' is repeated", token.range, severity: .warning)
                continue
            }
            switch keyword {
            case .ordered:
                feature.isOrdered = true
            case .unique where feature.kind == .attribute:
                feature.isUnique = true
            case .unique:
                report(
                    .inapplicableModifier, "'unique' applies to attributes only; references are always unique",
                    token.range, severity: .warning)
            case .container where feature.kind == .reference:
                feature.isContainer = true
            default:
                report(.inapplicableModifier, "'container' applies to references only", token.range)
            }
        }
    }

    /// Parses a bracketed multiplicity.
    ///
    /// - Returns: The multiplicity with its range.
    /// - Throws: ``KM3SyntaxFailure`` if the multiplicity is malformed.
    private mutating func parseMultiplicity() throws -> KM3MultiplicityNode {
        let start = current.range.start
        advance()
        var multiplicity = KM3MultiplicityNode(lower: 0, upper: -1, range: nil)
        var isSingleBound = false
        if current.isSymbol(KM3Symbol.star) {
            advance()
        } else if case .integer(let lower) = current.kind {
            advance()
            multiplicity.lower = lower
            if current.isSymbol(KM3Symbol.minus) {
                advance()
                if current.isSymbol(KM3Symbol.star) {
                    advance()
                } else if case .integer(let upper) = current.kind {
                    advance()
                    multiplicity.upper = upper
                } else {
                    throw fail(
                        "Expected an upper bound or '*' in the multiplicity but found \(describe(current))",
                        code: .invalidMultiplicity)
                }
            } else {
                multiplicity.upper = lower
                isSingleBound = true
            }
        } else {
            throw fail(
                "Expected a lower bound or '*' in the multiplicity but found \(describe(current))",
                code: .invalidMultiplicity)
        }
        guard current.isSymbol(KM3Symbol.closeBracket) else {
            throw fail("Expected ']' to close the multiplicity but found \(describe(current))", code: .invalidMultiplicity)
        }
        advance()
        let range = rangeFromStart(start)
        multiplicity.range = range
        if isSingleBound {
            report(
                .invalidMultiplicity,
                "A multiplicity is written '[n-m]', '[n-*]' or '[*]'; '[\(multiplicity.lower)]' is read as "
                    + "'[\(multiplicity.lower)-\(multiplicity.lower)]'",
                range, severity: .warning)
        }
        if multiplicity.upper != -1 && multiplicity.upper < multiplicity.lower {
            report(
                .invalidMultiplicity,
                "The upper bound \(multiplicity.upper) is below the lower bound \(multiplicity.lower)", range)
        } else if multiplicity.upper == 0 {
            report(.invalidMultiplicity, "The upper bound of a multiplicity must not be zero", range)
        }
        return multiplicity
    }

    /// Parses an operation declaration.
    ///
    /// - Returns: The operation.
    /// - Throws: ``KM3SyntaxFailure`` if the declaration is malformed.
    private mutating func parseOperation() throws -> KM3OperationNode {
        let start = current.range.start
        advance()
        let name = try expectName("an operation name")
        var operation = KM3OperationNode(name: name, range: rangeFromStart(start))
        try expectSymbol(KM3Symbol.openParenthesis, "to open the parameters of '\(name.text)'")
        if !current.isSymbol(KM3Symbol.closeParenthesis) {
            repeat {
                let parameterStart = current.range.start
                let parameterName = try expectName("a parameter name")
                try expectSymbol(KM3Symbol.colon, "before the type of parameter '\(parameterName.text)'")
                let type = try expectName("a type name")
                operation.parameters.append(
                    KM3ParameterNode(name: parameterName, type: type, range: rangeFromStart(parameterStart)))
            } while consumeSymbol(KM3Symbol.comma)
        }
        try expectSymbol(KM3Symbol.closeParenthesis, "to close the parameters of '\(name.text)'")
        if consumeSymbol(KM3Symbol.colon) { operation.returnType = try expectName("a result type name") }
        try expectTerminator(after: "operation '\(name.text)'", follows: Self.startsMemberOrClose)
        operation.range = rangeFromStart(start)
        return operation
    }

    /// Parses a comma-separated list of names.
    ///
    /// - Parameter what: What each name is, for diagnostics.
    /// - Returns: The names.
    /// - Throws: ``KM3SyntaxFailure`` if a name is missing.
    private mutating func parseNameList(_ what: String) throws -> [KM3NameNode] {
        var names = [try expectName(what)]
        while consumeSymbol(KM3Symbol.comma) { names.append(try expectName(what)) }
        return names
    }

    // MARK: Directives

    /// The `@nsURI` and `@nsPrefix` directives in the comments before a token.
    ///
    /// The comments are those between the previous token and the given one. The first
    /// directive of each kind counts; repeated and empty directives are reported.
    ///
    /// - Parameter index: The index of the token that the comments precede.
    /// - Returns: The namespace URI and prefix, if the comments give them.
    private mutating func packageDirectives(before index: Int) -> (nsURI: String?, nsPrefix: String?) {
        let lower = index > 0 ? tokens[index - 1].range.end.utf8Offset : 0
        let upper = tokens[index].range.start.utf8Offset
        var nsURI: String?
        var nsPrefix: String?
        for comment in comments where comment.range.start.utf8Offset >= lower && comment.range.start.utf8Offset < upper {
            guard case .comment(let body) = comment.kind, let directive = Self.directive(in: body) else { continue }
            switch directive.name {
            case KM3Directive.nsURI: assign(directive.value, to: &nsURI, directive: directive.name, at: comment.range)
            case KM3Directive.nsPrefix: assign(directive.value, to: &nsPrefix, directive: directive.name, at: comment.range)
            default: continue
            }
        }
        return (nsURI, nsPrefix)
    }

    /// Records the value of a namespace directive unless it is empty or repeated.
    ///
    /// - Parameters:
    ///   - value: The value of the directive.
    ///   - target: The value recorded so far.
    ///   - name: The name of the directive, for diagnostics.
    ///   - range: The range of the comment.
    private mutating func assign(_ value: String, to target: inout String?, directive name: String, at range: SourceRange) {
        if value.isEmpty {
            report(.invalidDirective, "The @\(name) directive has no value", range, severity: .warning)
        } else if target != nil {
            report(.invalidDirective, "The @\(name) directive is repeated; the first one is used", range, severity: .warning)
        } else {
            target = value
        }
    }

    /// The directive that the body of a comment holds.
    ///
    /// - Parameter body: The text of the comment after `--`.
    /// - Returns: The name and value of the directive, or `nil` if the comment holds none.
    static func directive(in body: String) -> (name: String, value: String)? {
        let trimmed = body.drop { $0 == " " || $0 == "\t" }
        guard trimmed.first == KM3Directive.marker else { return nil }
        let rest = trimmed.dropFirst()
        let name = rest.prefix { !$0.isWhitespace }
        guard !name.isEmpty else { return nil }
        let value = rest.dropFirst(name.count).drop { $0.isWhitespace }
        var end = value.endIndex
        while end > value.startIndex, value[value.index(before: end)].isWhitespace { end = value.index(before: end) }
        return (String(name), String(value[value.startIndex..<end]))
    }

    // MARK: Expectations

    /// Consumes a name, or fails.
    ///
    /// A reserved word that cannot start a declaration is accepted as a name, with an error
    /// that asks for quotes.
    ///
    /// - Parameter what: What the name is, for diagnostics.
    /// - Returns: The name.
    /// - Throws: ``KM3SyntaxFailure`` if the current token is not a name.
    private mutating func expectName(_ what: String) throws -> KM3NameNode {
        let token = current
        if let name = token.name {
            advance()
            return KM3NameNode(text: name, range: token.range)
        }
        if case .keyword(let keyword) = token.kind, Self.misusedNames.contains(keyword) {
            report(
                .unexpectedToken, "'\(keyword.rawValue)' is a reserved word; write \"\(keyword.rawValue)\" to use it as a name",
                token.range)
            advance()
            return KM3NameNode(text: keyword.rawValue, range: token.range)
        }
        throw fail("Expected \(what) but found \(describe(token))")
    }

    /// Consumes a name, or reports its absence and stands in an empty one.
    ///
    /// - Parameter what: What the name is, for diagnostics.
    /// - Returns: The name, or an empty name at the current token.
    private mutating func expectNameOrPlaceholder(_ what: String) -> KM3NameNode {
        do {
            return try expectName(what)
        } catch {
            return KM3NameNode(text: "", range: SourceRange(start: current.range.start, end: current.range.start))
        }
    }

    /// Consumes a symbol, or fails.
    ///
    /// - Parameters:
    ///   - symbol: The symbol.
    ///   - context: Where the symbol belongs, for diagnostics.
    /// - Throws: ``KM3SyntaxFailure`` if the current token is not the symbol.
    private mutating func expectSymbol(_ symbol: String, _ context: String) throws {
        guard consumeSymbol(symbol) else {
            throw fail("Expected '\(symbol)' \(context) but found \(describe(current))", code: .missingToken)
        }
    }

    /// Consumes the semicolon that ends a declaration.
    ///
    /// A missing semicolon is reported at the end of the previous token. If the current token
    /// can follow the declaration, the declaration is kept; otherwise parsing fails.
    ///
    /// - Parameters:
    ///   - description: The declaration that the semicolon ends, for diagnostics.
    ///   - follows: Whether a token can follow the declaration.
    /// - Throws: ``KM3SyntaxFailure`` if the semicolon is missing and the current token cannot
    ///   follow the declaration.
    private mutating func expectTerminator(after description: String, follows: (KM3Token) -> Bool) throws {
        if consumeSymbol(KM3Symbol.semicolon) { return }
        let end = position > 0 ? tokens[position - 1].range.end : current.range.start
        let message = "Expected ';' after \(description) but found \(describe(current))"
        if follows(current) || isAtEnd {
            report(.missingToken, message, SourceRange(start: end, end: end))
            return
        }
        throw fail(message, code: .missingToken)
    }

    /// Consumes the opening brace of a body.
    ///
    /// If the brace is missing, tokens up to the next opening brace are skipped, provided that
    /// no closing brace, semicolon or declaration comes first.
    ///
    /// - Parameter description: The declaration that the body belongs to, for diagnostics.
    /// - Returns: `true` if a body follows; `false` if the declaration has no body.
    private mutating func openBody(of description: String) -> Bool {
        if consumeSymbol(KM3Symbol.openBrace) { return true }
        report(.missingToken, "Expected '{' to open the body of \(description) but found \(describe(current))", current.range)
        var lookahead = position
        while lookahead < tokens.count - 1 {
            let token = tokens[lookahead]
            if token.isSymbol(KM3Symbol.openBrace) {
                position = lookahead + 1
                return true
            }
            if token.isSymbol(KM3Symbol.closeBrace) || token.isSymbol(KM3Symbol.semicolon) || Self.startsElement(token) {
                break
            }
            lookahead += 1
        }
        return false
    }

    /// Consumes the closing brace of a body, or reports its absence.
    ///
    /// - Parameter description: The declaration that the body belongs to, for diagnostics.
    private mutating func closeBody(of description: String) {
        if consumeSymbol(KM3Symbol.closeBrace) { return }
        let end = position > 0 ? tokens[position - 1].range.end : current.range.start
        report(
            .missingToken, "Expected '}' to close the body of \(description) but found \(describe(current))",
            SourceRange(start: end, end: end))
    }

    /// Consumes a symbol if it is the current token.
    ///
    /// - Parameter symbol: The symbol.
    /// - Returns: `true` if the symbol was consumed.
    private mutating func consumeSymbol(_ symbol: String) -> Bool {
        guard current.isSymbol(symbol) else { return false }
        advance()
        return true
    }

    // MARK: Recovery

    /// Skips a run of tokens that cannot appear here, reporting the run once.
    ///
    /// Tokens are skipped until one satisfies the stop condition outside braces. A brace pair
    /// is skipped as a whole. At least one token is skipped. Runs of invalid tokens are not
    /// reported again, because the lexer has reported them.
    ///
    /// - Parameters:
    ///   - expectation: What was expected, for diagnostics.
    ///   - stop: Whether a token ends the run.
    private mutating func skipUnexpected(expecting expectation: String, until stop: (KM3Token) -> Bool) {
        let first = current
        let startIndex = position
        var depth = 0
        repeat {
            if current.isSymbol(KM3Symbol.openBrace) { depth += 1 }
            if current.isSymbol(KM3Symbol.closeBrace) {
                if depth == 0 && position > startIndex { break }
                depth = max(depth - 1, 0)
            }
            advance()
        } while !isAtEnd && (depth > 0 || !stop(current))
        let skipped = tokens[startIndex..<position]
        guard !skipped.allSatisfy({ $0.kind == .invalid }) else { return }
        let end = skipped.last?.range.end ?? first.range.end
        report(
            .unexpectedToken, "Expected \(expectation) but found \(describe(first))",
            SourceRange(start: first.range.start, end: end))
    }

    /// Skips the rest of a classifier declaration that could not be parsed.
    ///
    /// Tokens are skipped up to a semicolon (which is consumed), up to the brace that closes
    /// the body of the declaration (consumed), or up to the next declaration or closing brace
    /// of the enclosing package.
    ///
    /// - Parameter startIndex: The index of the first token of the declaration.
    private mutating func recoverDeclaration(startedAt startIndex: Int) {
        var depth = 0
        for token in tokens[startIndex..<position] {
            if token.isSymbol(KM3Symbol.openBrace) { depth += 1 }
            if token.isSymbol(KM3Symbol.closeBrace) { depth -= 1 }
        }
        if position == startIndex { advance() }
        while !isAtEnd {
            if depth == 0 && (Self.startsElement(current) || current.isSymbol(KM3Symbol.closeBrace)) { return }
            if current.isSymbol(KM3Symbol.semicolon) && depth == 0 {
                advance()
                return
            }
            if current.isSymbol(KM3Symbol.openBrace) { depth += 1 }
            if current.isSymbol(KM3Symbol.closeBrace) {
                depth -= 1
                advance()
                if depth == 0 { return }
                continue
            }
            advance()
        }
    }

    /// Skips the rest of a member declaration that could not be parsed.
    ///
    /// Tokens are skipped up to a semicolon (which is consumed), or up to a token that starts
    /// another member, closes the body, or starts a classifier declaration.
    ///
    /// - Parameters:
    ///   - startIndex: The index of the first token of the member.
    ///   - startsMember: Whether a token starts another member.
    private mutating func recoverMember(startedAt startIndex: Int, stopsAt startsMember: (KM3Token) -> Bool) {
        if position == startIndex { advance() }
        while !isAtEnd {
            if startsMember(current) || current.isSymbol(KM3Symbol.closeBrace) || Self.startsElement(current) {
                return
            }
            let token = current
            advance()
            if token.isSymbol(KM3Symbol.semicolon) { return }
        }
    }

    // MARK: Tokens

    /// The current token.
    private var current: KM3Token { tokens[min(position, tokens.count - 1)] }

    /// Whether the current token is the end of the text.
    private var isAtEnd: Bool { current.kind == .eof }

    /// Moves to the next token.
    private mutating func advance() {
        if position < tokens.count - 1 { position += 1 }
    }

    /// The range from a start position to the end of the previous token.
    ///
    /// - Parameter start: The start of the range.
    /// - Returns: The range.
    private func rangeFromStart(_ start: SourcePosition) -> SourceRange {
        let end = position > 0 ? tokens[position - 1].range.end : start
        return SourceRange(start: start, end: max(start, end))
    }

    /// Describes a token for a diagnostic.
    ///
    /// - Parameter token: The token.
    /// - Returns: The quoted text of the token, or a description of the end of the text.
    private func describe(_ token: KM3Token) -> String {
        token.kind == .eof ? "the end of the text" : "'\(token.text)'"
    }

    /// Whether a token starts a declaration inside a package.
    private static func startsElement(_ token: KM3Token) -> Bool {
        if case .keyword(let keyword) = token.kind { return elementStarts.contains(keyword) }
        return false
    }

    /// Whether a token starts a declaration inside a package or closes a body.
    private static func startsElementOrClose(_ token: KM3Token) -> Bool {
        startsElement(token) || token.isSymbol(KM3Symbol.closeBrace)
    }

    /// Whether a token starts a declaration inside a class.
    private static func startsMember(_ token: KM3Token) -> Bool {
        if case .keyword(let keyword) = token.kind { return memberStarts.contains(keyword) }
        return false
    }

    /// Whether a token starts a declaration inside a class or closes a body.
    private static func startsMemberOrClose(_ token: KM3Token) -> Bool {
        startsMember(token) || token.isSymbol(KM3Symbol.closeBrace)
    }

    // MARK: Diagnostics

    /// Records a problem at the current token and returns the failure to throw.
    ///
    /// A problem at an invalid token is not recorded, because the lexer has reported it.
    ///
    /// - Parameters:
    ///   - message: The description of the problem.
    ///   - code: The code of the problem.
    /// - Returns: The failure.
    private mutating func fail(_ message: String, code: KM3DiagnosticCode = .unexpectedToken) -> KM3SyntaxFailure {
        if current.kind != .invalid { report(code, message, current.range) }
        return KM3SyntaxFailure()
    }

    /// Records a problem.
    ///
    /// - Parameters:
    ///   - code: The code of the problem.
    ///   - message: The description of the problem.
    ///   - range: The text the problem concerns.
    ///   - severity: How serious the problem is.
    private mutating func report(
        _ code: KM3DiagnosticCode, _ message: String, _ range: SourceRange, severity: DiagnosticSeverity = .error
    ) {
        diagnostics.append(
            SourceDiagnostic(severity: severity, code: code.rawValue, message: message, range: range, document: document))
    }
}
