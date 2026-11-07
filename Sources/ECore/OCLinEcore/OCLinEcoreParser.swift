//
// OCLinEcoreParser.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OCL

/// Reads the declarations of an OCLinEcore document, recovering from errors.
///
/// The parser follows the `TopLevelCS` rule of the Eclipse OCLinEcore grammar. When a
/// declaration cannot be read, the problem is reported and the parser skips to the end of the
/// declaration (its `;` or its closing brace) and continues with the next one, so that every
/// declaration that can be read is kept.
struct OCLinEcoreParser {
    /// The vocabulary of OCLinEcore.
    typealias Syntax = OCLinEcoreSyntax

    /// The tokens being read.
    var cursor: OCLTokenCursor
    /// The diagnostics collected so far.
    var diagnostics: [SourceDiagnostic] = []
    /// The name of the document, attached to each diagnostic.
    let document: String?
    /// The parser of the expressions inside constraints.
    let expressions = OCLExpressionParser()

    /// Creates a parser.
    ///
    /// - Parameters:
    ///   - cursor: The tokens to read.
    ///   - document: The name of the document, attached to each diagnostic.
    init(cursor: OCLTokenCursor, document: String?) {
        self.cursor = cursor
        self.document = document
    }

    // MARK: - Recovery

    /// Records a syntax error unless the same one is already recorded.
    ///
    /// - Parameter error: The syntax error.
    mutating func report(_ error: OCLSyntaxError) {
        var diagnostic = error.diagnostic
        diagnostic.document = document
        if !diagnostics.contains(where: { $0.range == diagnostic.range && $0.message == diagnostic.message }) {
            diagnostics.append(diagnostic)
        }
    }

    /// Records a warning.
    ///
    /// - Parameters:
    ///   - message: The description of the warning.
    ///   - code: The diagnostic code.
    ///   - range: The source range of the warning, if known.
    mutating func warn(_ message: String, code: String, range: SourceRange?) {
        diagnostics.append(SourceDiagnostic(severity: .warning, code: code, message: message, range: range, document: document))
    }

    /// Skips to the end of the current declaration after an error.
    ///
    /// - Parameter start: The position of the cursor when the declaration started.
    mutating func recover(from start: Int) {
        var depth = 0
        while !cursor.isAtEnd {
            let token = cursor.current
            if depth == 0 {
                if token.isSymbol(";") {
                    cursor.advance()
                    return
                }
                if token.isSymbol("}") { break }
                if cursor.position > start, token.kind == .identifier, Syntax.declarationKeywords.contains(token.text) { break }
            }
            if token.isSymbol("{") { depth += 1 }
            if token.isSymbol("}") {
                depth -= 1
                if depth == 0 {
                    cursor.advance()
                    return
                }
            }
            cursor.advance()
        }
        if cursor.position == start, !cursor.isAtEnd, !cursor.at(symbol: "}") { cursor.advance() }
    }

    /// Reads the members of a braced body until its closing brace, recovering from errors.
    ///
    /// - Parameter member: Reads one member at the cursor.
    mutating func parseBody(_ member: (inout OCLinEcoreParser) throws -> Void) throws {
        try cursor.expect(symbol: "{")
        while !cursor.at(symbol: "}") {
            if cursor.isAtEnd {
                report(cursor.error("Expected '}'"))
                return
            }
            let start = cursor.position
            do {
                try member(&self)
            } catch let error as OCLSyntaxError {
                report(error)
                recover(from: start)
            }
        }
        cursor.advance()
    }

    // MARK: - Document

    /// Reads every declaration of the document, recovering from errors at the next declaration.
    ///
    /// - Returns: The parsed document.
    mutating func parseDocument() -> OCLinEcoreDocumentDeclaration {
        var result = OCLinEcoreDocumentDeclaration()
        while !cursor.isAtEnd {
            let start = cursor.position
            do {
                if cursor.accept(word: Syntax.moduleKeyword) {
                    result.module = try cursor.expectName("module name")
                    cursor.accept(symbol: ";")
                } else if cursor.at(word: Syntax.importKeyword) || cursor.at(word: Syntax.libraryKeyword) {
                    result.imports.append(try parseImport())
                } else if cursor.at(word: Syntax.packageKeyword) {
                    result.packages.append(try parsePackage())
                } else {
                    throw cursor.error("Expected 'import' or 'package'")
                }
            } catch let error as OCLSyntaxError {
                report(error)
                recover(from: start)
                if cursor.at(symbol: "}") { cursor.advance() }
            } catch {}
        }
        return result
    }

    /// Reads an `import` or `library` declaration.
    ///
    /// - Returns: The import.
    /// - Throws: ``OCLSyntaxError`` if the declaration is malformed.
    mutating func parseImport() throws -> OCLinEcoreImport {
        let start = cursor.startPosition
        let isLibrary = cursor.at(word: Syntax.libraryKeyword)
        cursor.advance()
        var alias: String?
        if cursor.current.isName, cursor.peek().isSymbol(":"), !cursor.peek().isSymbol("::") {
            alias = cursor.current.value
            cursor.advance()
            cursor.advance()
        }
        var target: String
        if cursor.current.kind == .string {
            target = cursor.current.value
            cursor.advance()
        } else {
            target = try cursor.expectName("imported name")
        }
        while cursor.accept(symbol: OCLSyntax.pathSeparator) {
            if cursor.accept(symbol: "*") { break }
            target += OCLSyntax.pathSeparator + (try cursor.expectName("name after '::'"))
        }
        try cursor.expect(symbol: ";")
        return OCLinEcoreImport(alias: alias, target: target, isLibrary: isLibrary, range: cursor.range(from: start))
    }

    // MARK: - Packages

    /// Reads a `package` declaration and everything inside it.
    ///
    /// - Returns: The package declaration.
    /// - Throws: ``OCLSyntaxError`` if the declaration is malformed.
    mutating func parsePackage() throws -> PackageDeclaration {
        let start = cursor.startPosition
        try cursor.expect(word: Syntax.packageKeyword)
        let nameStart = cursor.startPosition
        let name = try cursor.expectName("package name")
        var package = PackageDeclaration(header: DeclarationHeader(name: name, nameRange: cursor.range(from: nameStart), range: cursor.range(from: start)))
        if cursor.accept(symbol: ":") { package.nsPrefix = try cursor.expectName("namespace prefix") }
        if cursor.accept(symbol: "=") { package.nsURI = try string("namespace URI") }
        if !cursor.accept(symbol: ";") {
            try parseBody { parser in
                if parser.isAnnotationStart {
                    package.annotations.append(try parser.parseAnnotation())
                } else if parser.cursor.at(word: Syntax.packageKeyword) {
                    package.packages.append(try parser.parsePackage())
                } else {
                    package.classifiers.append(try parser.parseClassifier())
                }
            }
        }
        package.header.range = cursor.range(from: start)
        return package
    }

    /// Reads a string token.
    ///
    /// - Parameter description: A description of the expected string, used in error messages.
    /// - Returns: The value of the string.
    /// - Throws: ``OCLSyntaxError`` if the current token is not a string.
    mutating func string(_ description: String) throws -> String {
        guard cursor.current.kind == .string else { throw cursor.error("Expected \(description)") }
        defer { cursor.advance() }
        return cursor.current.value
    }

    /// Whether the current token starts an annotation.
    var isAnnotationStart: Bool {
        cursor.at(word: Syntax.annotationKeyword) || cursor.at(word: Syntax.documentationKeyword)
            || cursor.at(word: Syntax.sysmlKeyword)
    }

    // MARK: - Annotations

    /// Reads an annotation.
    ///
    /// - Returns: The annotation declaration.
    /// - Throws: ``OCLSyntaxError`` if the annotation is malformed.
    mutating func parseAnnotation() throws -> AnnotationDeclaration {
        let start = cursor.startPosition
        if cursor.accept(word: Syntax.sysmlKeyword) {
            var annotation = AnnotationDeclaration(kind: .sysml, range: cursor.range(from: start))
            if cursor.accept(symbol: "{") {
                while !cursor.accept(symbol: "}") {
                    annotation.details.append(try parseDetail())
                    try cursor.expect(symbol: ";")
                }
            } else {
                annotation.details.append(try parseDetail())
                try cursor.expect(symbol: ";")
            }
            annotation.range = cursor.range(from: start)
            warn("SysML annotations are not read", code: OCLDiagnosticCode.unsupportedConstruct, range: annotation.range)
            return annotation
        }
        if cursor.accept(word: Syntax.documentationKeyword) {
            var text: String?
            if cursor.current.kind == .string { text = try string("documentation") }
            var annotation = AnnotationDeclaration(kind: .documentation(text: text), range: cursor.range(from: start))
            annotation.details = try parseDetails()
            try cursor.expect(symbol: ";")
            annotation.range = cursor.range(from: start)
            return annotation
        }
        try cursor.expect(word: Syntax.annotationKeyword)
        var source: String?
        if cursor.current.kind == .string || cursor.current.isName {
            source = cursor.current.value
            cursor.advance()
        }
        var annotation = AnnotationDeclaration(kind: .annotation(source: source), range: cursor.range(from: start))
        annotation.details = try parseDetails()
        if !cursor.accept(symbol: ";") {
            try parseBody { parser in
                if parser.isAnnotationStart {
                    annotation.children.append(try parser.parseAnnotation())
                } else {
                    let range = parser.cursor.current.range
                    parser.recover(from: parser.cursor.position)
                    parser.warn(
                        "Model elements and references inside annotations are not read",
                        code: OCLDiagnosticCode.unsupportedConstruct, range: range)
                }
            }
        }
        annotation.range = cursor.range(from: start)
        return annotation
    }

    /// Reads the parenthesised details of an annotation.
    ///
    /// - Returns: The keys and values of the details, which is empty if there are none.
    /// - Throws: ``OCLSyntaxError`` if the details are malformed.
    mutating func parseDetails() throws -> [(key: String, value: String)] {
        guard cursor.accept(symbol: "(") else { return [] }
        var details: [(key: String, value: String)] = []
        repeat {
            details.append(try parseDetail())
        } while cursor.accept(symbol: ",")
        try cursor.expect(symbol: ")")
        return details
    }

    /// Reads one detail of an annotation.
    ///
    /// - Returns: The key and value.
    /// - Throws: ``OCLSyntaxError`` if the detail is malformed.
    mutating func parseDetail() throws -> (key: String, value: String) {
        let key: String
        if cursor.current.kind == .string {
            key = try string("detail key")
        } else {
            key = try cursor.expectName("detail key")
        }
        try cursor.expect(symbol: "=")
        var value = ""
        while cursor.current.kind == .string || cursor.current.kind == .multiLineString {
            value += cursor.current.value
            cursor.advance()
        }
        return (key, value)
    }

    // MARK: - Classifiers

    /// Reads a class, datatype or enumeration declaration and its members.
    ///
    /// - Returns: The classifier declaration.
    /// - Throws: ``OCLSyntaxError`` if the declaration is malformed.
    mutating func parseClassifier() throws -> ClassifierDeclaration {
        let start = cursor.startPosition
        let isAbstract = cursor.accept(word: Syntax.abstractKeyword)
        let isPrimitive = !isAbstract && cursor.accept(word: Syntax.primitiveKeyword)
        let kind: ClassifierDeclaration.Kind
        if !isPrimitive, cursor.accept(word: Syntax.classKeyword) {
            kind = .class(isAbstract: isAbstract, isInterface: false)
        } else if !isAbstract, cursor.accept(word: Syntax.datatypeKeyword) {
            kind = .dataType(isPrimitive: isPrimitive)
        } else if !isAbstract, !isPrimitive, cursor.accept(word: Syntax.enumKeyword) {
            kind = .enumeration
        } else {
            throw cursor.error("Expected 'class', 'datatype' or 'enum'")
        }
        let nameStart = cursor.startPosition
        let name = try cursor.expectName("classifier name")
        var classifier = ClassifierDeclaration(
            kind: kind, header: DeclarationHeader(name: name, nameRange: cursor.range(from: nameStart), range: cursor.range(from: start)))
        try skipTemplateSignature()
        if case .class = kind, cursor.accept(word: Syntax.extendsKeyword) {
            repeat {
                classifier.superTypes.append(try expressions.parseType(&cursor, allowsMultiplicity: false))
            } while cursor.accept(symbol: ",")
        }
        if cursor.accept(symbol: ":") { classifier.instanceClassName = try string("instance class name") }
        if case .class(let abstract, _) = kind, isQualifierBlock(words: [Syntax.interfaceKeyword]) {
            cursor.advance()
            let isInterface = cursor.accept(word: Syntax.interfaceKeyword)
            try cursor.expect(symbol: "}")
            classifier.kind = .class(isAbstract: abstract, isInterface: isInterface)
        } else if isQualifierBlock(words: [Syntax.serializableKeyword]) {
            cursor.advance()
            if cursor.accept(word: Syntax.serializableKeyword) {
                classifier.isSerializable = true
            } else if cursor.accept(symbol: Syntax.negation) {
                try cursor.expect(word: Syntax.serializableKeyword)
                classifier.isSerializable = false
            }
            try cursor.expect(symbol: "}")
        }
        if !cursor.accept(symbol: ";") {
            try parseBody { parser in try parser.parseClassifierMember(of: &classifier) }
        }
        classifier.header.range = cursor.range(from: start)
        return classifier
    }

    /// Whether `{` at the cursor starts a block of the given qualifier words rather than a body.
    func isQualifierBlock(words: Set<String>) -> Bool {
        guard cursor.at(symbol: "{") else { return false }
        var offset = 1
        if cursor.peek(offset).isSymbol(Syntax.negation) { offset += 1 }
        let token = cursor.peek(offset)
        if token.kind == .identifier, words.contains(token.text) { return cursor.peek(offset + 1).isSymbol("}") }
        guard offset == 1, token.isSymbol("}") else { return false }
        let after = cursor.peek(2)
        return after.isSymbol("{") || after.isSymbol(";")
    }

    /// Skips a template signature in parentheses or angle brackets.
    ///
    /// - Throws: ``OCLSyntaxError`` if the signature is not closed.
    mutating func skipTemplateSignature() throws {
        guard cursor.at(symbol: "(") || cursor.at(symbol: "<") else { return }
        let start = cursor.startPosition
        let closing = cursor.at(symbol: "(") ? ")" : ">"
        cursor.advance()
        var depth = 1
        while depth > 0 {
            if cursor.isAtEnd { throw cursor.error("Expected '\(closing)'") }
            if cursor.at(symbol: "(") || cursor.at(symbol: "<") { depth += 1 }
            if cursor.at(symbol: ")") || cursor.at(symbol: ">") { depth -= 1 }
            cursor.advance()
        }
        warn("Template parameters are not read", code: OCLDiagnosticCode.unsupportedConstruct, range: cursor.range(from: start))
    }

    /// Reads one member of a classifier body and adds it to the classifier.
    ///
    /// - Parameter classifier: The classifier that receives the member.
    /// - Throws: ``OCLSyntaxError`` if the member is malformed.
    mutating func parseClassifierMember(of classifier: inout ClassifierDeclaration) throws {
        if isAnnotationStart {
            classifier.annotations.append(try parseAnnotation())
            return
        }
        if cursor.at(word: Syntax.invariantKeyword) || cursor.at(word: Syntax.callableKeyword) {
            classifier.invariants.append(try parseInvariant())
            return
        }
        switch classifier.kind {
        case .class:
            let memberStart = cursor.startPosition
            var prefixes: [String] = []
            while cursor.at(word: Syntax.staticKeyword) || cursor.at(word: Syntax.definitionKeyword) {
                prefixes.append(cursor.current.text)
                cursor.advance()
            }
            if cursor.at(word: Syntax.operationKeyword) {
                classifier.operations.append(try parseOperation())
            } else if cursor.at(word: Syntax.attributeKeyword) || cursor.at(word: Syntax.propertyKeyword) {
                var feature = try parseFeature()
                feature.prefixes = prefixes
                classifier.features.append(feature)
            } else {
                throw cursor.error("Expected 'attribute', 'property', 'operation' or 'invariant'")
            }
            if !prefixes.isEmpty {
                warn("'static' and 'definition' have no counterpart in Ecore", code: OCLDiagnosticCode.unsupportedConstruct, range: cursor.range(from: memberStart))
            }
        case .enumeration:
            classifier.literals.append(try parseLiteral())
        case .dataType:
            throw cursor.error("Expected 'invariant' or an annotation")
        }
    }

    /// Reads an enumeration literal.
    ///
    /// - Returns: The header, literal text, value and annotations of the literal.
    /// - Throws: ``OCLSyntaxError`` if the literal is malformed.
    mutating func parseLiteral() throws -> (header: DeclarationHeader, literal: String?, value: Int?, annotations: [AnnotationDeclaration]) {
        let start = cursor.startPosition
        if cursor.at(word: Syntax.literalKeyword), cursor.peek().isName { cursor.advance() }
        let nameStart = cursor.startPosition
        let name = try cursor.expectName("enumeration literal")
        let nameRange = cursor.range(from: nameStart)
        var literal: String?
        var value: Int?
        if cursor.accept(symbol: ":") { literal = try string("literal string") }
        if cursor.accept(symbol: "=") {
            let negative = cursor.accept(symbol: "-")
            guard cursor.current.kind == .integer, let number = Int(cursor.current.text) else {
                throw cursor.error("Expected a whole number")
            }
            cursor.advance()
            value = negative ? -number : number
        }
        var annotations: [AnnotationDeclaration] = []
        if !cursor.accept(symbol: ";") {
            try parseBody { parser in annotations.append(try parser.parseAnnotation()) }
        }
        return (DeclarationHeader(name: name, nameRange: nameRange, range: cursor.range(from: start)), literal, value, annotations)
    }

    // MARK: - Constraints

    /// Reads an `invariant`, including a `callable` one.
    ///
    /// - Returns: The constraint.
    /// - Throws: ``OCLSyntaxError`` if the invariant is malformed.
    mutating func parseInvariant() throws -> SpecificationDeclaration {
        let start = cursor.startPosition
        let isCallable = cursor.accept(word: Syntax.callableKeyword)
        try cursor.expect(word: Syntax.invariantKeyword)
        if isCallable {
            warn("'callable' invariants are read as plain invariants", code: OCLDiagnosticCode.unsupportedConstruct, range: cursor.range(from: start))
        }
        var specification = SpecificationDeclaration(range: cursor.range(from: start))
        if cursor.current.isName {
            specification.name = cursor.current.value
            cursor.advance()
            specification.message = try parseMessage()
        }
        if cursor.accept(symbol: ":") {
            specification.text = try parseSpecificationText()
        }
        try cursor.expect(symbol: ";")
        specification.range = cursor.range(from: start)
        return specification
    }

    /// Reads the optional parenthesised message of a constraint.
    ///
    /// - Returns: The text of the message, or `nil` if there is none.
    /// - Throws: ``OCLSyntaxError`` if the message is malformed.
    mutating func parseMessage() throws -> String? {
        guard cursor.accept(symbol: "(") else { return nil }
        let text = try parseSpecificationText(terminator: ")")
        try cursor.expect(symbol: ")")
        return text
    }

    /// Parses a condition such as `precondition name: expr;` or `body: expr;`.
    ///
    /// - Parameters:
    ///   - keyword: The keyword that starts the condition.
    ///   - allowsMessage: Whether a message may follow the name.
    /// - Returns: The specification.
    mutating func parseCondition(_ keyword: String, allowsMessage: Bool) throws -> SpecificationDeclaration {
        let start = cursor.startPosition
        try cursor.expect(word: keyword)
        var specification = SpecificationDeclaration(range: cursor.range(from: start))
        if cursor.current.isName {
            specification.name = cursor.current.value
            cursor.advance()
            if allowsMessage { specification.message = try parseMessage() }
        }
        try cursor.expect(symbol: ":")
        specification.text = try parseSpecificationText()
        try cursor.expect(symbol: ";")
        specification.range = cursor.range(from: start)
        return specification
    }

    /// Reads the verbatim text of an OCL expression up to its terminator.
    ///
    /// The expression is parsed to find where it ends and to report its errors. When it cannot
    /// be parsed, the text up to the next terminator at the same nesting depth is kept.
    ///
    /// - Parameter terminator: The symbol that ends the specification.
    /// - Returns: The text, or `nil` if the specification is empty.
    mutating func parseSpecificationText(terminator: String = ";") throws -> String? {
        if cursor.at(symbol: terminator) { return nil }
        let start = cursor.position
        let startPosition = cursor.startPosition
        do {
            var probe = cursor
            let expression = try expressions.parseExpression(&probe)
            if probe.at(symbol: terminator) {
                cursor = probe
                return cursor.text(of: expression.range)
            }
            throw probe.error("Expected '\(terminator)'")
        } catch let error as OCLSyntaxError {
            var diagnostic = error.diagnostic
            diagnostic.code = OCLDiagnosticCode.invalidExpression
            report(OCLSyntaxError(diagnostic))
            cursor.position = start
            var depth = 0
            while !cursor.isAtEnd {
                if depth == 0, cursor.at(symbol: terminator) { break }
                if cursor.at(symbol: "(") || cursor.at(symbol: "{") || cursor.at(symbol: "[") { depth += 1 }
                if cursor.at(symbol: ")") || cursor.at(symbol: "}") || cursor.at(symbol: "]") {
                    if depth == 0 { break }
                    depth -= 1
                }
                cursor.advance()
            }
            let text = cursor.text(of: cursor.range(from: startPosition))
            return text.isEmpty ? nil : text
        }
    }

    // MARK: - Features

    /// Reads a braced list of qualifiers, each of which may be negated.
    ///
    /// - Parameter allowed: The qualifiers that may appear.
    /// - Returns: Whether each written qualifier is set.
    /// - Throws: ``OCLSyntaxError`` if a qualifier is malformed or not allowed.
    mutating func parseQualifiers(allowed: [String]) throws -> [String: Bool] {
        var qualifiers: [String: Bool] = [:]
        try cursor.expect(symbol: "{")
        while !cursor.accept(symbol: "}") {
            let negated = cursor.accept(symbol: Syntax.negation)
            let token = cursor.current
            guard token.kind == .identifier, allowed.contains(token.text) else {
                throw cursor.error("Expected a qualifier (\(allowed.joined(separator: ", ")))")
            }
            qualifiers[token.text] = !negated
            cursor.advance()
            cursor.accept(symbol: ",")
        }
        return qualifiers
    }

    /// Whether `{` at the cursor starts a block of qualifiers rather than a body.
    func isQualifierList(_ allowed: [String]) -> Bool {
        guard cursor.at(symbol: "{") else { return false }
        let next = cursor.peek()
        if next.isSymbol(Syntax.negation) { return true }
        if next.kind == .identifier, allowed.contains(next.text) { return true }
        return false
    }

    /// Reads an `attribute` or `property` declaration.
    ///
    /// - Returns: The feature declaration.
    /// - Throws: ``OCLSyntaxError`` if the declaration is malformed.
    mutating func parseFeature() throws -> FeatureDeclaration {
        let start = cursor.startPosition
        let isAttribute = cursor.at(word: Syntax.attributeKeyword)
        cursor.advance()
        let nameStart = cursor.startPosition
        let name = try cursor.expectName("feature name")
        var feature = FeatureDeclaration(
            isAttribute: isAttribute, header: DeclarationHeader(name: name, nameRange: cursor.range(from: nameStart), range: cursor.range(from: start)))
        if !isAttribute, cursor.accept(symbol: "#") { feature.opposite = try cursor.expectName("opposite name") }
        if cursor.accept(symbol: ":") { feature.type = try expressions.parseType(&cursor, allowsMultiplicity: true) }
        if cursor.accept(symbol: "=") { feature.defaultValue = try string("default value") }
        let allowed = isAttribute ? Syntax.attributeQualifiers : Syntax.referenceQualifiers
        if isQualifierList(allowed) { feature.qualifiers = try parseQualifiers(allowed: allowed) }
        if !cursor.accept(symbol: ";") {
            try parseBody { parser in try parser.parseFeatureMember(of: &feature) }
        }
        feature.header.range = cursor.range(from: start)
        return feature
    }

    /// Reads one member of a feature body and adds it to the feature.
    ///
    /// - Parameter feature: The feature that receives the member.
    /// - Throws: ``OCLSyntaxError`` if the member is malformed.
    mutating func parseFeatureMember(of feature: inout FeatureDeclaration) throws {
        if isAnnotationStart {
            feature.annotations.append(try parseAnnotation())
        } else if cursor.at(word: Syntax.initialKeyword) {
            feature.initial = try parseCondition(Syntax.initialKeyword, allowsMessage: false)
        } else if cursor.at(word: Syntax.derivationKeyword) {
            feature.derivation = try parseCondition(Syntax.derivationKeyword, allowsMessage: false)
        } else if !feature.isAttribute, cursor.accept(word: Syntax.keyKeyword) {
            repeat {
                let start = cursor.startPosition
                let key = try cursor.expectName("key name")
                feature.keys.append((key, cursor.range(from: start)))
            } while cursor.accept(symbol: ",")
            try cursor.expect(symbol: ";")
        } else if !feature.isAttribute, cursor.at(word: Syntax.oppositeKeyword) {
            let start = cursor.startPosition
            cursor.advance()
            _ = try cursor.expectName("opposite name")
            try cursor.expect(symbol: ":")
            _ = try expressions.parseType(&cursor, allowsMultiplicity: true)
            if isQualifierList(Syntax.parameterQualifiers) { _ = try parseQualifiers(allowed: Syntax.parameterQualifiers) }
            try cursor.expect(symbol: ";")
            warn("Implicit opposites are not read", code: OCLDiagnosticCode.unsupportedConstruct, range: cursor.range(from: start))
        } else {
            throw cursor.error("Expected 'initial', 'derivation' or an annotation")
        }
    }

    // MARK: - Operations

    /// Reads an `operation` declaration.
    ///
    /// - Returns: The operation declaration.
    /// - Throws: ``OCLSyntaxError`` if the declaration is malformed.
    mutating func parseOperation() throws -> OperationDeclaration {
        let start = cursor.startPosition
        try cursor.expect(word: Syntax.operationKeyword)
        try skipTemplateSignature()
        let nameStart = cursor.startPosition
        let name = try cursor.expectName("operation name")
        var operation = OperationDeclaration(
            header: DeclarationHeader(name: name, nameRange: cursor.range(from: nameStart), range: cursor.range(from: start)))
        try cursor.expect(symbol: "(")
        if !cursor.at(symbol: ")") {
            repeat {
                operation.parameters.append(try parseParameter())
            } while cursor.accept(symbol: ",")
        }
        try cursor.expect(symbol: ")")
        if cursor.accept(symbol: ":") { operation.type = try expressions.parseType(&cursor, allowsMultiplicity: true) }
        if cursor.accept(word: Syntax.throwsKeyword) {
            repeat {
                operation.exceptions.append(try expressions.parseType(&cursor, allowsMultiplicity: false))
            } while cursor.accept(symbol: ",")
        }
        if isQualifierList(Syntax.operationQualifiers) { operation.qualifiers = try parseQualifiers(allowed: Syntax.operationQualifiers) }
        if !cursor.accept(symbol: ";") {
            try parseBody { parser in
                if parser.isAnnotationStart {
                    operation.annotations.append(try parser.parseAnnotation())
                } else if parser.cursor.at(word: Syntax.preconditionKeyword) {
                    operation.preconditions.append(try parser.parseCondition(Syntax.preconditionKeyword, allowsMessage: true))
                } else if parser.cursor.at(word: Syntax.postconditionKeyword) {
                    operation.postconditions.append(try parser.parseCondition(Syntax.postconditionKeyword, allowsMessage: true))
                } else if parser.cursor.at(word: Syntax.bodyKeyword) {
                    operation.body = try parser.parseCondition(Syntax.bodyKeyword, allowsMessage: false)
                } else {
                    throw parser.cursor.error("Expected 'body', 'precondition', 'postcondition' or an annotation")
                }
            }
        }
        operation.header.range = cursor.range(from: start)
        return operation
    }

    /// Reads an operation parameter.
    ///
    /// - Returns: The parameter declaration.
    /// - Throws: ``OCLSyntaxError`` if the parameter is malformed.
    mutating func parseParameter() throws -> ParameterDeclaration {
        let start = cursor.startPosition
        let name = try cursor.expectName("parameter name")
        var parameter = ParameterDeclaration(
            header: DeclarationHeader(name: name, nameRange: cursor.range(from: start), range: cursor.range(from: start)))
        if cursor.accept(symbol: ":") { parameter.type = try expressions.parseType(&cursor, allowsMultiplicity: true) }
        if isQualifierList(Syntax.parameterQualifiers) { parameter.qualifiers = try parseQualifiers(allowed: Syntax.parameterQualifiers) }
        if cursor.at(symbol: "{") {
            try parseBody { parser in parameter.annotations.append(try parser.parseAnnotation()) }
        }
        parameter.header.range = cursor.range(from: start)
        return parameter
    }
}
