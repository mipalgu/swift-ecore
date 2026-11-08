//
// XcoreParser.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// The declarations read from an Xcore document.
struct XcoreDocument {
    /// The packages of the document: the package, or none if there is no declaration.
    var packages: [DraftPackage] = []

    /// The simple names that explicit imports introduce, with the qualified names they stand for.
    var imports: [String: String] = [:]

    /// The packages imported with a wildcard.
    var wildcards: [String] = []

    /// The ranges of the import directives that name something other than Ecore.
    var externalImports: [SourceRange] = []

    /// The ranges of the bodies kept as text.
    var bodies: [SourceRange] = []
}

/// An annotation as written in Xcore, before its alias is resolved.
struct XcoreAnnotation {
    /// The last segment of the annotation name.
    var alias: String

    /// The details in source order.
    var details: [DraftDetail]

    /// The source range of the annotation.
    var range: SourceRange
}

/// A recursive-descent parser for the structural subset of Xcore that recovers from errors.
///
/// The parser follows the Xcore grammar and produces format-neutral declarations that
/// ``MetamodelAssembler`` turns into native packages. Xbase bodies are not parsed: each
/// is kept verbatim, braces included, in an annotation with the Xcore source.
struct XcoreParser {
    /// The keywords of the Xcore notation.
    private typealias Keyword = XcoreLanguage.Keyword
    /// The Ecore attributes that the `@Ecore` annotation can set.
    private typealias EcoreAttribute = XcoreLanguage.EcoreAttribute

    /// The cursor over the scanned tokens.
    private var cursor: TokenCursor
    /// The comments found while scanning, used to recover documentation.
    private let comments: [TextToken]
    /// The UTF-8 bytes of the source text, from which bodies are taken verbatim.
    private let bytes: [UInt8]

    /// The token kinds assigned by the parser, by the start offset of the token.
    private(set) var tokenKinds: [Int: SourceTokenKind] = [:]

    /// The annotation directives of the document, by alias.
    private var directives: [String: String] = [:]

    /// The aliases of the annotation directives in declaration order.
    private var directiveOrder: [String] = []

    /// The start offsets of annotations whose alias is resolved once all directives are known.
    private var pendingAnnotations: Set<Int> = []

    /// The document that is being assembled.
    private var document = XcoreDocument()

    /// The diagnostics found while parsing.
    var diagnostics: [SourceDiagnostic] { cursor.diagnostics }

    /// The words that can start a classifier declaration.
    private static let classifierStarts: Set<String> = [
        Keyword.class, .abstract, .interface, .type, .enum,
    ].reduce(into: []) { $0.insert($1.rawValue) }

    /// The words that may be used as names without an escape.
    private static let unreservedNames: Set<String> = [
        Keyword.get, .set, .isSet, .unset, .void,
    ].reduce(into: []) { $0.insert($1.rawValue) }

    /// Creates a parser for scanned Xcore text.
    ///
    /// - Parameters:
    ///   - text: The source text, from which bodies are taken verbatim.
    ///   - scan: The scanned text.
    ///   - factory: The factory that creates diagnostics.
    init(text: String, scan: LexicalScan, factory: DiagnosticFactory) {
        cursor = TokenCursor(tokens: scan.tokens, factory: factory)
        comments = scan.comments
        bytes = Array(text.utf8)
    }

    // MARK: Helpers

    /// Records the kind that the parser assigns to a token.
    ///
    /// - Parameters:
    ///   - token: The token to classify.
    ///   - kind: The kind to assign.
    private mutating func mark(_ token: TextToken, as kind: SourceTokenKind) {
        tokenKinds[token.range.start.utf8Offset] = kind
    }

    /// Returns whether a keyword is found at a distance from the current token.
    ///
    /// - Parameters:
    ///   - keyword: The keyword to look for.
    ///   - distance: The number of tokens ahead of the current token.
    /// - Returns: `true` if the token at the distance is the keyword.
    private func isWord(_ keyword: Keyword, at distance: Int = 0) -> Bool {
        cursor.peek(distance).isWord(keyword.rawValue)
    }

    /// Consumes the current token if it is the given keyword.
    ///
    /// - Parameter keyword: The keyword to accept.
    /// - Returns: `true` if the keyword was consumed.
    @discardableResult
    private mutating func acceptWord(_ keyword: Keyword) -> Bool {
        cursor.acceptWord(keyword.rawValue)
    }

    /// Parses a simple name, reporting an error if none is found.
    ///
    /// - Parameter context: A phrase describing where the name is expected, for diagnostics.
    /// - Returns: The unescaped name and its range, or `nil` if no valid name was found.
    private mutating func name(_ context: String) -> (value: String, range: SourceRange)? {
        let token = cursor.current
        guard token.kind == .identifier else {
            cursor.unexpected("a name \(context)")
            return nil
        }
        if !token.isEscaped, XcoreLanguage.keywords.contains(token.text), !Self.unreservedNames.contains(token.text) {
            cursor.report(cursor.factory.error(
                .unexpectedToken,
                "Expected a name \(context) but found the keyword '\(token.text)'; write "
                    + "\(XcoreLanguage.escapeCharacter)\(token.text) to use it as a name",
                at: token.range))
            return nil
        }
        cursor.advance()
        return (token.value, token.range)
    }

    /// Parses a dot-separated qualified name.
    ///
    /// - Parameters:
    ///   - context: A phrase describing where the name is expected, for diagnostics.
    ///   - role: The kind to assign to the first token of the name, if any.
    /// - Returns: The qualified name and its range, or `nil` if no valid name was found.
    private mutating func qualifiedName(_ context: String, role: SourceTokenKind? = nil)
        -> (value: String, range: SourceRange)?
    {
        let first = cursor.current
        guard let head = name(context) else { return nil }
        if let role { mark(first, as: role) }
        var value = head.value
        var range = head.range
        while cursor.current.isPunctuation("."), cursor.peek(1).kind == .identifier {
            cursor.advance()
            let segment = cursor.current
            guard let next = name(context) else { break }
            if let role { mark(segment, as: role) }
            value += "." + next.value
            range = range.union(next.range)
        }
        return (value, range)
    }

    /// The text of a source range, exactly as written.
    private func sourceText(_ range: SourceRange) -> String {
        let start = max(0, min(range.start.utf8Offset, bytes.count))
        let end = max(start, min(range.end.utf8Offset, bytes.count))
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// Skips the rest of a malformed member, up to the next line or the end of the class.
    private mutating func recoverMember(from line: Int) {
        let start = cursor.position
        var depth = 0
        while !cursor.isAtEnd {
            let token = cursor.current
            if depth == 0 {
                if token.isPunctuation("}") { break }
                if token.range.start.line > line, cursor.position > start { break }
            }
            if token.isPunctuation("{") { depth += 1 }
            if token.isPunctuation("}") { depth -= 1 }
            cursor.advance()
        }
    }

    /// Skips a malformed declaration up to the next classifier keyword or annotation.
    private mutating func recoverDeclaration() {
        let start = cursor.position
        var depth = 0
        while !cursor.isAtEnd {
            let token = cursor.current
            if depth == 0, cursor.position > start {
                if token.isPunctuation("@") { break }
                if token.kind == .identifier, !token.isEscaped, Self.classifierStarts.contains(token.text) { break }
            }
            if token.isPunctuation("{") { depth += 1 }
            if token.isPunctuation("}") { depth = max(0, depth - 1) }
            cursor.advance()
        }
    }

    // MARK: Documentation

    /// The documentation that the first block comment before the current token holds.
    ///
    /// As in EMF, the comment delimiters are removed, the leading `*` of continuation lines
    /// and trailing white space are dropped, and leading and trailing empty lines are
    /// removed.
    private func documentation() -> String? {
        let end = cursor.current.range.start.utf8Offset
        let start = cursor.previous?.range.end.utf8Offset ?? 0
        guard let comment = comments.first(where: {
            ($0.kind == .blockComment || $0.kind == .documentationComment)
                && $0.range.start.utf8Offset >= start && $0.range.end.utf8Offset <= end
        }) else { return nil }
        return Self.documentation(fromComment: comment.text)
    }

    /// Extracts documentation from the text of a block comment.
    ///
    /// - Parameter text: The comment, including its delimiters.
    /// - Returns: The documentation, or `nil` if the comment holds none.
    static func documentation(fromComment text: String) -> String? {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count > 4 else { return nil }
        var body = String.UnicodeScalarView()
        body.append(contentsOf: scalars[2..<(scalars.count - 2)])
        var lines = String(body).replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n", omittingEmptySubsequences: false
        ).map(String.init)
        for index in lines.indices {
            var line = Substring(lines[index])
            if index > 0 {
                let trimmed = line.drop { $0 == " " || $0 == "\t" }
                if trimmed.first == "*" {
                    line = trimmed.dropFirst()
                    if let first = line.first, first == " " || first == "\t" { line = line.dropFirst() }
                }
            }
            while let last = line.last, last.isWhitespace { line = line.dropLast() }
            lines[index] = String(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    // MARK: Annotations

    /// Parses the annotations that precede a declaration.
    ///
    /// - Returns: The annotations in source order.
    private mutating func parseAnnotations() -> [XcoreAnnotation] {
        var annotations: [XcoreAnnotation] = []
        while cursor.current.isPunctuation("@") {
            let at = cursor.advance()
            mark(at, as: .directive)
            guard let name = qualifiedName("for the annotation", role: .directive) else {
                recoverMember(from: at.range.start.line)
                continue
            }
            var details: [DraftDetail] = []
            if cursor.accept("(") {
                while !cursor.isAtEnd, !cursor.current.isPunctuation(")") {
                    guard let key = qualifiedName("for the annotation key") else {
                        cursor.skip(untilAny: [",", ")"])
                        if !cursor.accept(",") { break }
                        continue
                    }
                    cursor.expect("=", "after the annotation key")
                    details.append(DraftDetail(key: key.value, value: annotationValue() ?? ""))
                    if !cursor.accept(",") { break }
                }
                cursor.expect(")", "to close the annotation")
            }
            let alias = name.value.split(separator: ".").last.map(String.init) ?? name.value
            annotations.append(XcoreAnnotation(alias: alias, details: details, range: cursor.range(from: at.range.start)))
        }
        return annotations
    }

    /// Parses the value of an annotation detail.
    ///
    /// - Returns: The value text, or `nil` if no value could be read.
    private mutating func annotationValue() -> String? {
        let token = cursor.current
        switch token.kind {
        case .string:
            cursor.advance()
            return token.value
        case .integer, .real:
            cursor.advance()
            return token.text
        case .identifier:
            return qualifiedName("for the annotation value")?.value
        default:
            cursor.unexpected("a string value for the annotation")
            return nil
        }
    }

    /// Converts the annotations of an element into draft annotations.
    ///
    /// Annotations with a predefined alias are merged into one annotation per source, and
    /// the documentation comment opens the GenModel annotation. A detail of an `Ecore`
    /// annotation that names an attribute of the element sets that attribute instead.
    ///
    /// - Parameters:
    ///   - annotations: The annotations as written.
    ///   - documentation: The documentation comment of the element, if any.
    ///   - apply: Sets an attribute of the element and reports whether it has one of that name.
    /// - Returns: The draft annotations of the element.
    private mutating func attach(
        _ annotations: [XcoreAnnotation], documentation: String?,
        apply: (EcoreAttribute, String) -> Bool = { _, _ in false }
    ) -> [DraftAnnotation] {
        var result: [DraftAnnotation] = []
        var merged: [String: Int] = [:]
        if let documentation {
            result.append(DraftAnnotation(
                source: AnnotationSource.genModel,
                details: [DraftDetail(key: XcoreLanguage.documentationKey, value: documentation)]))
            merged[AnnotationSource.genModel] = 0
        }
        for annotation in annotations {
            guard let predefined = XcoreLanguage.annotationAliases.first(where: { $0.alias == annotation.alias }) else {
                pendingAnnotations.insert(annotation.range.start.utf8Offset)
                result.append(DraftAnnotation(source: annotation.alias, details: annotation.details, range: annotation.range))
                continue
            }
            let index: Int
            if let existing = merged[predefined.source] {
                index = existing
            } else {
                index = result.count
                merged[predefined.source] = index
                result.append(DraftAnnotation(source: predefined.source, range: annotation.range))
            }
            for detail in annotation.details {
                if predefined.alias == XcoreLanguage.ecoreAlias, let attribute = EcoreAttribute(rawValue: detail.key),
                    apply(attribute, detail.value)
                {
                    continue
                }
                Self.put(detail, into: &result[index])
            }
        }
        return result.filter { $0.source != AnnotationSource.ecore || !$0.details.isEmpty }
    }

    /// Sets a detail, replacing the value of an existing key in place.
    private static func put(_ detail: DraftDetail, into annotation: inout DraftAnnotation) {
        if let index = annotation.details.firstIndex(where: { $0.key == detail.key }) {
            annotation.details[index].value = detail.value
        } else {
            annotation.details.append(detail)
        }
    }

    /// Adds a body to the Xcore annotation of an element.
    private mutating func addBody(_ key: XcoreLanguage.BodyKey, range: SourceRange, to annotations: inout [DraftAnnotation]) {
        document.bodies.append(range)
        cursor.report(cursor.factory.warning(
            .bodyNotExecuted, "The Xbase \(key.phrase) is kept as text but not executed", at: range))
        let detail = DraftDetail(key: key.rawValue, value: sourceText(range))
        if let index = annotations.firstIndex(where: { $0.source == XcoreLanguage.namespaceURI }) {
            Self.put(detail, into: &annotations[index])
        } else {
            annotations.append(DraftAnnotation(source: XcoreLanguage.namespaceURI, details: [detail]))
        }
    }

    /// Interprets the text of an attribute value as a flag.
    ///
    /// - Parameter text: The attribute value.
    /// - Returns: `true` if the text is `true`, ignoring case.
    private static func flag(_ text: String) -> Bool { text.lowercased() == "true" }

    // MARK: Document

    /// Parses a whole Xcore document.
    ///
    /// - Returns: The declarations of the document.
    mutating func parseDocument() -> XcoreDocument {
        let start = cursor.current.range.start
        let documentation = self.documentation()
        let annotations = parseAnnotations()
        guard acceptWord(.package) else {
            if cursor.isAtEnd && annotations.isEmpty {
                cursor.report(cursor.factory.error(.missingPackage, "The document declares no package", at: cursor.current.range))
                return document
            }
            cursor.report(cursor.factory.error(
                .missingPackage, "Expected 'package' to start the document", at: cursor.current.range))
            var package = DraftPackage(name: "_", location: DraftLocation(range: cursor.current.range, nameRange: cursor.current.range))
            parseContents(into: &package)
            finish(&package, annotations: annotations, documentation: documentation, qualifiedName: nil, start: start)
            return document
        }
        let name = qualifiedName("for the package") ?? ("_", cursor.current.range)
        let simple = name.value.split(separator: ".").last.map(String.init) ?? name.value
        var package = DraftPackage(name: simple, location: DraftLocation(range: name.range, nameRange: name.range))
        parseContents(into: &package)
        finish(&package, annotations: annotations, documentation: documentation, qualifiedName: name.value, start: start)
        return document
    }

    /// Completes a package declaration from its annotations and name.
    ///
    /// - Parameters:
    ///   - package: The package to complete.
    ///   - annotations: The annotations that precede the package.
    ///   - documentation: The documentation comment of the package, if any.
    ///   - qualifiedName: The qualified name of the package, if declared.
    ///   - start: The position where the package declaration starts.
    private mutating func finish(
        _ package: inout DraftPackage, annotations: [XcoreAnnotation], documentation: String?, qualifiedName: String?,
        start: SourcePosition
    ) {
        var nsURI: String?
        var nsPrefix: String?
        package.annotations = attach(annotations, documentation: documentation) { attribute, value in
            switch attribute {
            case .nsURI: nsURI = value
            case .nsPrefix: nsPrefix = value
            case .name: break
            default: return false
            }
            return true
        }
        if let qualifiedName, let dot = qualifiedName.lastIndex(of: ".") {
            package.qualifiedName = qualifiedName
            let base = DraftDetail(key: XcoreLanguage.basePackageKey, value: String(qualifiedName[..<dot]))
            if let index = package.annotations.firstIndex(where: { $0.source == AnnotationSource.genModel }) {
                Self.put(base, into: &package.annotations[index])
            } else {
                package.annotations.append(DraftAnnotation(source: AnnotationSource.genModel, details: [base]))
            }
        }
        let qualified = qualifiedName ?? package.name
        package.nsURI = nsURI ?? (qualified == XcoreLanguage.ecorePackageName ? EcorePackage.nsURI : qualified)
        package.nsPrefix = nsPrefix ?? XcoreLanguage.defaultPrefix(for: package.name)
        if !directiveOrder.isEmpty {
            let details = directiveOrder.map { DraftDetail(key: $0, value: directives[$0] ?? "") }
            if let index = package.annotations.firstIndex(where: { $0.source == XcoreLanguage.namespaceURI }) {
                for detail in details { Self.put(detail, into: &package.annotations[index]) }
            } else {
                package.annotations.append(DraftAnnotation(source: XcoreLanguage.namespaceURI, details: details))
            }
        }
        resolveAnnotations(in: &package)
        package.location.range = SourceRange(start: start, end: cursor.current.range.end)
        document.packages = [package]
    }

    /// Parses the imports, directives and classifiers of a package.
    ///
    /// - Parameter package: The package that receives the classifiers.
    private mutating func parseContents(into package: inout DraftPackage) {
        while !cursor.isAtEnd {
            let isHeader = isWord(.import) || (isWord(.annotation) && cursor.peek(1).kind == .string)
            if isHeader, !package.classifiers.isEmpty {
                cursor.report(cursor.factory.error(
                    .unexpectedToken, "Imports and annotation directives must precede the classifiers",
                    at: cursor.current.range))
            }
            if isWord(.import) {
                parseImport()
            } else if isHeader {
                parseDirective()
            } else {
                parseClassifier(into: &package)
            }
        }
    }

    /// Parses an import declaration.
    private mutating func parseImport() {
        let start = cursor.advance().range.start
        guard let name = qualifiedName("to import", role: .typeName) else {
            recoverDeclaration()
            return
        }
        var value = name.value
        if cursor.current.isPunctuation("."), cursor.peek(1).isPunctuation("*") {
            cursor.advance()
            cursor.advance()
            value += XcoreLanguage.wildcardSuffix
        }
        let range = cursor.range(from: start)
        if value.hasSuffix(XcoreLanguage.wildcardSuffix) {
            let prefix = String(value.dropLast(XcoreLanguage.wildcardSuffix.count))
            document.wildcards.append(prefix)
            if prefix != XcoreLanguage.ecorePackageName { document.externalImports.append(range) }
        } else {
            let simple = value.split(separator: ".").last.map(String.init) ?? value
            document.imports[simple] = value
            if !value.hasPrefix(XcoreLanguage.ecorePackageName + ".") { document.externalImports.append(range) }
        }
        cursor.accept(";")
    }

    /// Parses an annotation directive that binds an alias to an annotation source.
    private mutating func parseDirective() {
        cursor.advance()
        let uri = cursor.advance()
        mark(uri, as: .string)
        guard acceptWord(.as), let alias = name("for the annotation alias") else {
            cursor.unexpected("'as' and an alias for the annotation")
            recoverDeclaration()
            return
        }
        if directives[alias.value] == nil { directiveOrder.append(alias.value) }
        directives[alias.value] = uri.value
        cursor.accept(";")
    }

    /// Resolves the aliases of the annotations that the directives define.
    private mutating func resolveAnnotations(in package: inout DraftPackage) {
        resolve(&package.annotations)
        for index in package.classifiers.indices {
            resolve(&package.classifiers[index].annotations)
            for parameter in package.classifiers[index].typeParameters.indices {
                resolve(&package.classifiers[index].typeParameters[parameter].annotations)
            }
            for literal in package.classifiers[index].literals.indices {
                resolve(&package.classifiers[index].literals[literal].annotations)
            }
            for feature in package.classifiers[index].features.indices {
                resolve(&package.classifiers[index].features[feature].annotations)
            }
            for operation in package.classifiers[index].operations.indices {
                resolve(&package.classifiers[index].operations[operation].annotations)
                for parameter in package.classifiers[index].operations[operation].parameters.indices {
                    resolve(&package.classifiers[index].operations[operation].parameters[parameter].annotations)
                }
                for parameter in package.classifiers[index].operations[operation].typeParameters.indices {
                    resolve(&package.classifiers[index].operations[operation].typeParameters[parameter].annotations)
                }
            }
        }
    }

    /// Resolves annotation aliases once all directives are known.
    ///
    /// - Parameter annotations: The annotations whose aliases are resolved.
    private mutating func resolve(_ annotations: inout [DraftAnnotation]) {
        for index in annotations.indices {
            guard let offset = annotations[index].range?.start.utf8Offset, pendingAnnotations.contains(offset) else {
                continue
            }
            let alias = annotations[index].source
            if let source = directives[alias] {
                annotations[index].source = source
            } else {
                cursor.report(cursor.factory.error(
                    .unresolvedAnnotation, "No annotation directive declares the alias '\(alias)'",
                    at: annotations[index].range))
            }
        }
    }

    // MARK: Classifiers

    /// Parses a classifier declaration and adds it to the package.
    ///
    /// - Parameter package: The package that receives the classifier.
    private mutating func parseClassifier(into package: inout DraftPackage) {
        let start = cursor.current.range.start
        let documentation = self.documentation()
        let annotations = parseAnnotations()
        if isWord(.abstract) || isWord(.class) || isWord(.interface) {
            package.classifiers.append(parseClass(annotations, documentation: documentation, start: start))
        } else if isWord(.type) {
            package.classifiers.append(parseDataType(annotations, documentation: documentation, start: start))
        } else if isWord(.enum) {
            package.classifiers.append(parseEnum(annotations, documentation: documentation, start: start))
        } else {
            if isWord(.import) || isWord(.annotation) {
                cursor.report(cursor.factory.error(
                    .unexpectedToken, "Imports and annotation directives must precede the classifiers",
                    at: cursor.current.range))
            } else {
                cursor.unexpected("'class', 'interface', 'type' or 'enum'")
            }
            recoverDeclaration()
        }
    }

    /// Applies an `@Ecore` attribute to a classifier.
    ///
    /// - Parameters:
    ///   - attribute: The attribute to apply.
    ///   - value: The attribute value.
    ///   - classifier: The classifier to update.
    /// - Returns: `true` if the attribute applies to the classifier.
    private static func applyClassifierAttribute(_ attribute: EcoreAttribute, _ value: String, to classifier: inout DraftClassifier) -> Bool {
        switch attribute {
        case .name: classifier.name = value
        case .instanceClassName, .instanceTypeName: classifier.instanceTypeName = value.isEmpty ? nil : value
        case .abstract where classifier.kind == .class: classifier.isAbstract = Self.flag(value)
        case .interface where classifier.kind == .class: classifier.isInterface = Self.flag(value)
        case .serializable where classifier.kind != .class: classifier.serialisable = Self.flag(value)
        default: return false
        }
        return true
    }

    /// Parses a class or interface declaration.
    ///
    /// - Parameters:
    ///   - annotations: The annotations that precede the declaration.
    ///   - documentation: The documentation comment, if any.
    ///   - start: The position where the declaration starts.
    /// - Returns: The parsed class.
    private mutating func parseClass(_ annotations: [XcoreAnnotation], documentation: String?, start: SourcePosition) -> DraftClassifier {
        var isAbstract = acceptWord(.abstract)
        var isInterface = false
        if acceptWord(.interface) {
            isInterface = true
            isAbstract = true
        } else {
            cursor.expectWord(Keyword.class.rawValue, "to declare a class")
        }
        let name = self.name("for the class") ?? ("_", cursor.current.range)
        var classifier = DraftClassifier(kind: .class, name: name.value, location: DraftLocation(range: name.range, nameRange: name.range))
        classifier.isAbstract = isAbstract
        classifier.isInterface = isInterface
        classifier.typeParameters = parseTypeParameters()
        if acceptWord(.extends) {
            repeat {
                if let type = parseType() { classifier.superTypes.append(type) }
            } while cursor.accept(",")
        }
        if acceptWord(.wraps) { classifier.instanceTypeName = parseInstanceType() }
        if cursor.expect("{", "to open the class body") {
            while !cursor.isAtEnd, !cursor.current.isPunctuation("}") { parseMember(into: &classifier) }
            cursor.expect("}", "to close the class body")
        } else {
            recoverDeclaration()
        }
        classifier.annotations = attach(annotations, documentation: documentation) { attribute, value in
            Self.applyClassifierAttribute(attribute, value, to: &classifier)
        }
        classifier.location.range = cursor.range(from: start)
        return classifier
    }

    /// Parses a data type declaration.
    ///
    /// - Parameters:
    ///   - annotations: The annotations that precede the declaration.
    ///   - documentation: The documentation comment, if any.
    ///   - start: The position where the declaration starts.
    /// - Returns: The parsed data type.
    private mutating func parseDataType(_ annotations: [XcoreAnnotation], documentation: String?, start: SourcePosition) -> DraftClassifier {
        cursor.advance()
        let name = self.name("for the data type") ?? ("_", cursor.current.range)
        var classifier = DraftClassifier(kind: .dataType, name: name.value, location: DraftLocation(range: name.range, nameRange: name.range))
        classifier.typeParameters = parseTypeParameters()
        if cursor.expectWord(Keyword.wraps.rawValue, "before the instance type of the data type") {
            classifier.instanceTypeName = parseInstanceType()
        }
        var bodies: [DraftAnnotation] = []
        while (isWord(.create) || isWord(.convert)) && cursor.peek(1).isPunctuation("{") {
            let key: XcoreLanguage.BodyKey = isWord(.create) ? .create : .convert
            cursor.advance()
            if let range = cursor.skipBlock() { addBody(key, range: range, to: &bodies) }
        }
        classifier.annotations = attach(annotations, documentation: documentation) { attribute, value in
            Self.applyClassifierAttribute(attribute, value, to: &classifier)
        } + bodies
        classifier.location.range = cursor.range(from: start)
        return classifier
    }

    /// Parses an enumeration declaration.
    ///
    /// - Parameters:
    ///   - annotations: The annotations that precede the declaration.
    ///   - documentation: The documentation comment, if any.
    ///   - start: The position where the declaration starts.
    /// - Returns: The parsed enumeration.
    private mutating func parseEnum(_ annotations: [XcoreAnnotation], documentation: String?, start: SourcePosition) -> DraftClassifier {
        cursor.advance()
        let name = self.name("for the enumeration") ?? ("_", cursor.current.range)
        var classifier = DraftClassifier(kind: .enumeration, name: name.value, location: DraftLocation(range: name.range, nameRange: name.range))
        if cursor.expect("{", "to open the enumeration") {
            while !cursor.isAtEnd, !cursor.current.isPunctuation("}") {
                let literalStart = cursor.current.range.start
                let literalDocumentation = self.documentation()
                let literalAnnotations = parseAnnotations()
                let nameToken = cursor.current
                guard let literalName = self.name("for the enumeration literal") else {
                    recoverMember(from: nameToken.range.start.line)
                    continue
                }
                mark(nameToken, as: .enumLiteral)
                var literal = DraftLiteral(
                    name: literalName.value, value: 0,
                    location: DraftLocation(range: literalName.range, nameRange: literalName.range))
                if acceptWord(.as) {
                    if cursor.current.kind == .string {
                        literal.literal = cursor.advance().value
                    } else {
                        cursor.unexpected("a string literal after 'as'")
                    }
                }
                if cursor.accept("=") {
                    let negative = cursor.accept("-")
                    if cursor.current.kind == .integer, let number = Int(cursor.current.text.replacingOccurrences(of: "_", with: "")) {
                        literal.value = negative ? -number : number
                        cursor.advance()
                    } else {
                        cursor.unexpected("an integer value for the literal")
                    }
                }
                literal.annotations = attach(literalAnnotations, documentation: literalDocumentation) { attribute, value in
                    switch attribute {
                    case .name: literal.name = value
                    case .value: literal.value = Int(value) ?? literal.value
                    case .literal: literal.literal = value
                    default: return false
                    }
                    return true
                }
                literal.location.range = cursor.range(from: literalStart)
                classifier.literals.append(literal)
                cursor.accept(",")
            }
            cursor.expect("}", "to close the enumeration")
        } else {
            recoverDeclaration()
        }
        classifier.annotations = attach(annotations, documentation: documentation) { attribute, value in
            Self.applyClassifierAttribute(attribute, value, to: &classifier)
        }
        classifier.location.range = cursor.range(from: start)
        return classifier
    }

    // MARK: Members

    /// Parses an attribute, reference or operation of a classifier.
    ///
    /// - Parameter classifier: The classifier that receives the member.
    private mutating func parseMember(into classifier: inout DraftClassifier) {
        let start = cursor.current.range.start
        let documentation = self.documentation()
        let annotations = parseAnnotations()
        if acceptWord(.op) {
            parseOperation(annotations, documentation: documentation, start: start, into: &classifier)
            return
        }
        var modifiers: [(word: Keyword, range: SourceRange)] = []
        while cursor.current.kind == .identifier, !cursor.current.isEscaped,
            XcoreLanguage.featureModifiers.contains(cursor.current.text), let word = Keyword(rawValue: cursor.current.text)
        {
            modifiers.append((word, cursor.advance().range))
        }
        if cursor.accept(";") { return }
        let words = Set(modifiers.map(\.word))
        let isReference = !words.isDisjoint(with: [.contains, .container, .refers])
        let errorLine = cursor.current.range.start.line
        guard let type = parseType() else {
            recoverMember(from: errorLine)
            return
        }
        let bounds = cursor.multiplicity()
        guard let name = name("for the feature") else {
            recoverMember(from: errorLine)
            return
        }
        var feature = DraftFeature(
            kind: isReference ? .reference : .attribute, name: name.value, type: type,
            location: DraftLocation(range: name.range, nameRange: name.range))
        if let bounds {
            feature.lowerBound = bounds.lower
            feature.upperBound = bounds.upper
        }
        feature.unique = isReference
        for modifier in modifiers { apply(modifier.word, range: modifier.range, words: words, to: &feature) }
        if isReference {
            if acceptWord(.opposite), let opposite = self.name("for the opposite reference") {
                feature.opposite = opposite.value
                feature.oppositeRange = opposite.range
            }
            if acceptWord(.keys) {
                repeat {
                    guard let key = self.name("for the key attribute") else { break }
                    feature.keys.append(key.value)
                    feature.keyRanges.append(key.range)
                } while cursor.accept(",")
            }
        } else if cursor.accept("=") {
            feature.defaultValue = defaultValue()
        }
        var bodies: [DraftAnnotation] = []
        var accessors: Set<Keyword> = []
        while let accessor = XcoreLanguage.accessorKeywords.first(where: { isWord($0) }), cursor.peek(1).isPunctuation("{") {
            cursor.advance()
            accessors.insert(accessor)
            if let range = cursor.skipBlock(), let key = XcoreLanguage.BodyKey(rawValue: accessor.rawValue) {
                addBody(key, range: range, to: &bodies)
            }
        }
        if accessors.contains(.get) {
            feature.transient = true
            feature.volatile = true
            feature.derived = true
            if !accessors.contains(.set) { feature.changeable = false }
        }
        cursor.accept(";")
        feature.annotations = attach(annotations, documentation: documentation) { attribute, value in
            Self.applyFeatureAttribute(attribute, value, to: &feature)
        } + bodies
        feature.location.range = cursor.range(from: start)
        classifier.features.append(feature)
    }

    /// Applies a modifier keyword to a feature.
    ///
    /// - Parameters:
    ///   - word: The modifier keyword.
    ///   - range: The source range of the keyword.
    ///   - words: The modifier keywords seen so far.
    ///   - feature: The feature to update.
    private mutating func apply(_ word: Keyword, range: SourceRange, words: Set<Keyword>, to feature: inout DraftFeature) {
        switch word {
        case .unordered: feature.ordered = false
        case .unique: feature.unique = true
        case .readonly: feature.changeable = false
        case .transient: feature.transient = true
        case .volatile: feature.volatile = true
        case .unsettable: feature.unsettable = true
        case .derived: feature.derived = true
        case .id where feature.kind == .attribute: feature.isID = true
        case .contains:
            feature.containment = true
            feature.resolveProxies = words.contains(.resolving)
        case .local where words.contains(.refers): feature.resolveProxies = false
        case .resolving where words.contains(.contains) || words.contains(.container): break
        case .refers, .container: break
        default:
            cursor.report(cursor.factory.warning(
                .unsupportedConstruct, "The modifier '\(word.rawValue)' does not apply here and is ignored", at: range))
        }
    }

    /// Applies the multiplicity and collection attributes of an `@Ecore` annotation.
    ///
    /// - Parameters:
    ///   - attribute: The attribute to apply.
    ///   - value: The attribute value.
    ///   - ordered: Whether the element is ordered.
    ///   - unique: Whether the element is unique.
    ///   - lower: The lower bound.
    ///   - upper: The upper bound.
    /// - Returns: `true` if the attribute is one of these and was applied.
    private static func applyTypedAttribute(
        _ attribute: EcoreAttribute, _ value: String, ordered: inout Bool, unique: inout Bool, lower: inout Int,
        upper: inout Int
    ) -> Bool {
        switch attribute {
        case .ordered: ordered = flag(value)
        case .unique: unique = flag(value)
        case .lowerBound: lower = Int(value) ?? lower
        case .upperBound: upper = Int(value) ?? upper
        default: return false
        }
        return true
    }

    /// Applies an `@Ecore` attribute to a feature.
    ///
    /// - Parameters:
    ///   - attribute: The attribute to apply.
    ///   - value: The attribute value.
    ///   - feature: The feature to update.
    /// - Returns: `true` if the attribute applies to the feature.
    private static func applyFeatureAttribute(_ attribute: EcoreAttribute, _ value: String, to feature: inout DraftFeature) -> Bool {
        if applyTypedAttribute(
            attribute, value, ordered: &feature.ordered, unique: &feature.unique, lower: &feature.lowerBound,
            upper: &feature.upperBound)
        {
            return true
        }
        switch attribute {
        case .name: feature.name = value
        case .changeable: feature.changeable = flag(value)
        case .volatile: feature.volatile = flag(value)
        case .transient: feature.transient = flag(value)
        case .unsettable: feature.unsettable = flag(value)
        case .derived: feature.derived = flag(value)
        case .defaultValueLiteral: feature.defaultValue = value
        case .iD where feature.kind == .attribute: feature.isID = flag(value)
        case .containment where feature.kind == .reference: feature.containment = flag(value)
        case .resolveProxies where feature.kind == .reference: feature.resolveProxies = flag(value)
        default: return false
        }
        return true
    }

    /// Parses the default value of a feature.
    ///
    /// - Returns: The default value text, or `nil` if none could be read.
    private mutating func defaultValue() -> String? {
        let token = cursor.current
        switch token.kind {
        case .string:
            cursor.advance()
            return token.value
        case .integer, .real:
            cursor.advance()
            return token.text
        case .identifier where !token.isEscaped && TokenClassifier.booleans.contains(token.text):
            cursor.advance()
            return token.text
        case .punctuation where token.text == "-" && (cursor.peek(1).kind == .integer || cursor.peek(1).kind == .real):
            cursor.advance()
            return "-" + cursor.advance().text
        default:
            cursor.unexpected("a string default value")
            return nil
        }
    }

    /// Parses the `unordered` and `unique` modifiers of a type.
    ///
    /// - Parameters:
    ///   - ordered: Set to `false` if `unordered` is found.
    ///   - unique: Set to `true` if `unique` is found.
    private mutating func collectionModifiers(ordered: inout Bool, unique: inout Bool) {
        while true {
            if acceptWord(.unordered) {
                ordered = false
            } else if acceptWord(.unique) {
                unique = true
            } else {
                return
            }
        }
    }

    /// Parses an operation and adds it to a classifier.
    ///
    /// - Parameters:
    ///   - annotations: The annotations that precede the operation.
    ///   - documentation: The documentation comment, if any.
    ///   - start: The position where the operation starts.
    ///   - classifier: The classifier that receives the operation.
    private mutating func parseOperation(
        _ annotations: [XcoreAnnotation], documentation: String?, start: SourcePosition,
        into classifier: inout DraftClassifier
    ) {
        let errorLine = cursor.current.range.start.line
        var ordered = true
        var unique = false
        collectionModifiers(ordered: &ordered, unique: &unique)
        let typeParameters = parseTypeParameters()
        var returnType: DraftType?
        var bounds: (lower: Int, upper: Int)?
        if !acceptWord(.void) {
            guard let type = parseType() else {
                recoverMember(from: errorLine)
                return
            }
            returnType = type
        }
        bounds = cursor.multiplicity()
        guard let name = name("for the operation") else {
            recoverMember(from: errorLine)
            return
        }
        var operation = DraftOperation(name: name.value, location: DraftLocation(range: name.range, nameRange: name.range))
        operation.typeParameters = typeParameters
        operation.returnType = returnType
        operation.ordered = ordered
        operation.unique = unique
        if let bounds {
            operation.lowerBound = bounds.lower
            operation.upperBound = bounds.upper
        }
        if cursor.expect("(", "to open the parameters") {
            if !cursor.current.isPunctuation(")") {
                repeat {
                    if let parameter = parseParameter() { operation.parameters.append(parameter) }
                } while cursor.accept(",")
            }
            if !cursor.expect(")", "to close the parameters") {
                cursor.skip(untilAny: [")"])
                cursor.accept(")")
            }
        }
        if acceptWord(.throws) {
            repeat {
                if let type = parseType() { operation.exceptions.append(type) }
            } while cursor.accept(",")
        }
        var bodies: [DraftAnnotation] = []
        if cursor.current.isPunctuation("{"), let range = cursor.skipBlock() { addBody(.body, range: range, to: &bodies) }
        cursor.accept(";")
        operation.annotations = attach(annotations, documentation: documentation) { attribute, value in
            if attribute == .name {
                operation.name = value
                return true
            }
            return Self.applyTypedAttribute(
                attribute, value, ordered: &operation.ordered, unique: &operation.unique,
                lower: &operation.lowerBound, upper: &operation.upperBound)
        } + bodies
        operation.location.range = cursor.range(from: start)
        classifier.operations.append(operation)
    }

    /// Parses an operation parameter.
    ///
    /// - Returns: The parameter, or `nil` if it could not be read.
    private mutating func parseParameter() -> DraftParameter? {
        let start = cursor.current.range.start
        let documentation = self.documentation()
        let annotations = parseAnnotations()
        var ordered = true
        var unique = false
        collectionModifiers(ordered: &ordered, unique: &unique)
        guard let type = parseType() else { return nil }
        let bounds = cursor.multiplicity()
        guard let name = name("for the parameter") else { return nil }
        var parameter = DraftParameter(name: name.value, type: type, location: DraftLocation(range: name.range, nameRange: name.range))
        parameter.ordered = ordered
        parameter.unique = unique
        if let bounds {
            parameter.lowerBound = bounds.lower
            parameter.upperBound = bounds.upper
        }
        parameter.annotations = attach(annotations, documentation: documentation) { attribute, value in
            if attribute == .name {
                parameter.name = value
                return true
            }
            return Self.applyTypedAttribute(
                attribute, value, ordered: &parameter.ordered, unique: &parameter.unique,
                lower: &parameter.lowerBound, upper: &parameter.upperBound)
        }
        parameter.location.range = cursor.range(from: start)
        return parameter
    }

    // MARK: Types

    /// Parses a type reference with optional type arguments.
    ///
    /// - Returns: The type, or `nil` if it could not be read.
    private mutating func parseType() -> DraftType? {
        let start = cursor.current.range.start
        guard let name = qualifiedName("for a type", role: .typeName) else { return nil }
        var type = DraftType(name: name.value)
        if cursor.accept("<") {
            repeat {
                if let argument = parseTypeArgument() { type.arguments.append(argument) }
            } while cursor.accept(",")
            cursor.expect(">", "to close the type arguments")
        }
        type.range = cursor.range(from: start)
        return type
    }

    /// Parses a type argument, which may be a wildcard.
    ///
    /// - Returns: The type argument, or `nil` if it could not be read.
    private mutating func parseTypeArgument() -> DraftType? {
        let start = cursor.current.range.start
        guard cursor.accept("?") else { return parseType() }
        var type = DraftType(name: "", wildcard: .unbounded)
        if acceptWord(.extends) {
            type.wildcard = .upper
            type.bounds = parseType().map { [$0] } ?? []
        } else if acceptWord(.super) {
            type.wildcard = .lower
            type.bounds = parseType().map { [$0] } ?? []
        }
        type.range = cursor.range(from: start)
        return type
    }

    /// Reads a Java type reference, as after `wraps`, and returns its text.
    private mutating func parseInstanceType() -> String? {
        guard var text = parseType()?.text else { return nil }
        while cursor.current.isPunctuation("["), cursor.peek(1).isPunctuation("]") {
            cursor.advance()
            cursor.advance()
            text += "[]"
        }
        return text
    }

    /// Parses an optional list of type parameters.
    ///
    /// - Returns: The type parameters, empty if there are none.
    private mutating func parseTypeParameters() -> [DraftTypeParameter] {
        guard cursor.accept("<") else { return [] }
        var parameters: [DraftTypeParameter] = []
        repeat {
            let start = cursor.current.range.start
            let documentation = self.documentation()
            let annotations = parseAnnotations()
            guard let name = name("for the type parameter") else { break }
            var parameter = DraftTypeParameter(name: name.value)
            if acceptWord(.extends) {
                repeat {
                    if let bound = parseType() { parameter.bounds.append(bound) }
                } while cursor.accept("&")
            }
            parameter.annotations = attach(annotations, documentation: documentation)
            parameter.range = cursor.range(from: start)
            parameters.append(parameter)
        } while cursor.accept(",")
        cursor.expect(">", "to close the type parameters")
        return parameters
    }
}
