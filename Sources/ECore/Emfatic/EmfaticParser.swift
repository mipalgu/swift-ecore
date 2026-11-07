//
// EmfaticParser.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// The declarations read from an Emfatic document.
struct EmfaticDocument {
    /// The packages of the document: the root package, or none if there is no declaration.
    var packages: [DraftPackage] = []

    /// The ranges of the import statements.
    var imports: [SourceRange] = []
}

/// An annotation as written, before its label is resolved to a source URI.
struct EmfaticAnnotation {
    /// The label or source as written.
    var label: String

    /// Whether the label was written as a string literal.
    var isQuoted: Bool

    /// The details in source order.
    var details: [DraftDetail]

    /// The source range of the annotation.
    var range: SourceRange
}

/// A modifier as written before a feature, operation or parameter.
struct EmfaticModifier {
    /// The modifier keyword.
    var word: EmfaticLanguage.Keyword

    /// Whether the modifier is negated with `!`.
    var isNegated: Bool

    /// The source range of the modifier.
    var range: SourceRange
}

/// A recursive-descent parser for Emfatic that recovers from errors.
///
/// The parser follows the Emfatic grammar and produces format-neutral declarations that
/// ``MetamodelAssembler`` turns into native packages. It records the role of type names,
/// annotation labels and enumeration literals so that tokens can be classified.
struct EmfaticParser {
    /// The keyword vocabulary of the Emfatic language.
    private typealias Keyword = EmfaticLanguage.Keyword

    /// The cursor over the scanned tokens.
    private var cursor: TokenCursor

    /// The token kinds assigned by the parser, by the start offset of the token.
    private(set) var tokenKinds: [Int: SourceTokenKind] = [:]

    /// The annotation labels known so far, by lower-case label.
    private var labels: [String: (source: String, implicitKeys: [String])] = [:]

    /// The diagnostics found while parsing.
    var diagnostics: [SourceDiagnostic] { cursor.diagnostics }

    /// The tokens at which a top-level declaration can start.
    private static let declarationStarts: Set<String> = [
        Keyword.package, .abstract, .class, .interface, .datatype, .transient, .enum, .mapentry, .import,
    ].reduce(into: []) { $0.insert($1.rawValue) }

    /// Creates a parser for scanned Emfatic text.
    ///
    /// - Parameters:
    ///   - scan: The scanned text.
    ///   - factory: The factory that creates diagnostics.
    init(scan: LexicalScan, factory: DiagnosticFactory) {
        cursor = TokenCursor(tokens: scan.tokens, factory: factory)
        for (label, source) in EmfaticLanguage.annotationLabels { labels[label.lowercased()] = (source, []) }
    }

    // MARK: Helpers

    /// Records the role of a token.
    ///
    /// - Parameters:
    ///   - token: The token to classify.
    ///   - kind: The role assigned to the token.
    private mutating func mark(_ token: TextToken, as kind: SourceTokenKind) {
        tokenKinds[token.range.start.utf8Offset] = kind
    }

    /// Returns whether a token is the given keyword.
    ///
    /// - Parameters:
    ///   - keyword: The keyword to look for.
    ///   - distance: The number of tokens ahead of the current token to inspect.
    /// - Returns: `true` if the inspected token is the keyword.
    private func isWord(_ keyword: Keyword, at distance: Int = 0) -> Bool {
        cursor.peek(distance).isWord(keyword.rawValue)
    }

    /// Consumes the current token if it is the given keyword.
    ///
    /// - Parameter keyword: The keyword to accept.
    /// - Returns: `true` if the keyword was found and consumed.
    @discardableResult
    private mutating func acceptWord(_ keyword: Keyword) -> Bool {
        cursor.acceptWord(keyword.rawValue)
    }

    /// Reads a simple name, reporting a keyword used without its escape.
    private mutating func name(_ context: String) -> (value: String, range: SourceRange)? {
        let token = cursor.current
        guard token.kind == .identifier else {
            cursor.unexpected("a name \(context)")
            return nil
        }
        cursor.advance()
        if !token.isEscaped, EmfaticLanguage.keywords.contains(token.text) {
            cursor.report(cursor.factory.error(
                .unexpectedToken,
                "'\(token.text)' is a keyword; write \(EmfaticLanguage.escapeCharacter)\(token.text) to use it as a name",
                at: token.range))
        }
        return (token.value, token.range)
    }

    /// Reads a qualified name whose segments are separated by `.` or `$`.
    private mutating func qualifiedName(_ context: String, role: SourceTokenKind? = nil)
        -> (value: String, range: SourceRange)?
    {
        let first = cursor.current
        guard let head = name(context) else { return nil }
        if let role { mark(first, as: role) }
        var value = head.value
        var range = head.range
        while cursor.current.kind == .punctuation, EmfaticLanguage.nameSeparators.contains(cursor.current.text),
            cursor.peek(1).kind == .identifier
        {
            let separator = cursor.advance().text
            let segment = cursor.current
            guard let next = name(context) else { break }
            if let role { mark(segment, as: role) }
            value += separator + next.value
            range = range.union(next.range)
        }
        return (value, range)
    }

    /// Skips to the end of a malformed declaration or member.
    private mutating func recover(words: Set<String> = []) {
        let start = cursor.position
        cursor.skip(untilAny: [";"], orWords: words)
        if cursor.accept(";") { return }
        if cursor.position == start, !cursor.current.isPunctuation("}") { cursor.advance() }
    }

    // MARK: Document

    /// Parses a whole Emfatic document.
    ///
    /// - Returns: The declarations of the document.
    mutating func parseDocument() -> EmfaticDocument {
        var document = EmfaticDocument()
        let start = cursor.current.range.start
        let annotations = parseAnnotations()
        var package: DraftPackage
        if acceptWord(.package) {
            let name = qualifiedName("for the package") ?? ("", cursor.current.range)
            cursor.expect(";", "after the package name")
            package = DraftPackage(name: name.value, location: DraftLocation(range: cursor.range(from: start), nameRange: name.range))
        } else {
            if cursor.isAtEnd && annotations.isEmpty {
                cursor.report(cursor.factory.error(.missingPackage, "The document declares no package", at: cursor.current.range))
                return document
            }
            cursor.report(cursor.factory.error(
                .missingPackage, "Expected 'package' to start the document", at: cursor.current.range))
            package = DraftPackage(name: "", location: DraftLocation(range: cursor.current.range, nameRange: cursor.current.range))
        }
        applyPackageAnnotations(annotations, to: &package)
        while !cursor.isAtEnd {
            if isWord(.import) {
                if !package.classifiers.isEmpty || !package.subpackages.isEmpty {
                    cursor.report(cursor.factory.error(
                        .unexpectedToken, "Imports must precede the declarations", at: cursor.current.range))
                }
                document.imports.append(parseImport())
            } else if cursor.current.isPunctuation("}") {
                cursor.unexpected("a declaration")
                cursor.advance()
            } else {
                parseDeclaration(into: &package, imports: &document.imports)
            }
        }
        package.location.range = SourceRange(start: start, end: cursor.current.range.end)
        document.packages = [package]
        return document
    }

    /// Parses an import declaration.
    ///
    /// - Returns: The source range of the import.
    private mutating func parseImport() -> SourceRange {
        let start = cursor.advance().range.start
        if cursor.current.kind == .identifier, cursor.peek(1).isPunctuation("=") {
            cursor.advance()
            cursor.advance()
        }
        if cursor.current.kind == .string {
            cursor.advance()
        } else if qualifiedName("or URI to import") == nil {
            recover()
            return cursor.range(from: start)
        }
        cursor.expect(";", "after the import")
        return cursor.range(from: start)
    }

    /// Applies the namespace annotations of a package to its draft.
    ///
    /// - Parameters:
    ///   - annotations: The annotations written before the package.
    ///   - package: The draft package that receives the annotations.
    private mutating func applyPackageAnnotations(_ annotations: [EmfaticAnnotation], to package: inout DraftPackage) {
        var nsURI: String?
        var nsPrefix: String?
        for annotation in annotations {
            guard !annotation.isQuoted, annotation.label.lowercased() == EmfaticLanguage.namespaceLabel else {
                package.annotations.append(resolve(annotation))
                continue
            }
            for detail in annotation.details {
                switch EmfaticLanguage.NamespaceKey(rawValue: detail.key.lowercased()) {
                case .uri: nsURI = detail.value
                case .prefix: nsPrefix = detail.value
                case nil:
                    cursor.report(cursor.factory.warning(
                        .unsupportedConstruct, "Ignoring '\(detail.key)' in @\(EmfaticLanguage.namespaceLabel)",
                        at: annotation.range))
                }
            }
        }
        package.nsURI = nsURI ?? package.name
        package.nsPrefix = nsPrefix ?? ""
    }

    // MARK: Declarations

    /// Parses one declaration inside a package.
    ///
    /// - Parameters:
    ///   - package: The draft package that receives the declaration.
    ///   - imports: The collected source ranges of import declarations.
    private mutating func parseDeclaration(into package: inout DraftPackage, imports: inout [SourceRange]) {
        let start = cursor.current.range.start
        let annotations = parseAnnotations()
        if isWord(.package) {
            parseSubpackage(annotations, start: start, into: &package, imports: &imports)
        } else if isWord(.abstract) || isWord(.class) || isWord(.interface) {
            package.classifiers.append(parseClass(annotations, start: start))
        } else if isWord(.datatype) || (isWord(.transient) && isWord(.datatype, at: 1)) {
            package.classifiers.append(parseDataType(annotations, start: start))
        } else if isWord(.enum) {
            package.classifiers.append(parseEnum(annotations, start: start))
        } else if isWord(.mapentry) {
            package.classifiers.append(parseMapEntry(annotations, start: start))
        } else if isWord(.import) {
            cursor.report(cursor.factory.error(
                .unexpectedToken, "Imports must precede the declarations", at: cursor.current.range))
            imports.append(parseImport())
        } else {
            cursor.unexpected("a declaration")
            recover(words: Self.declarationStarts)
        }
    }

    /// Parses a nested package declaration.
    ///
    /// - Parameters:
    ///   - annotations: The annotations written before the package.
    ///   - start: The position at which the declaration starts.
    ///   - parent: The draft package that receives the nested package.
    ///   - imports: The collected source ranges of import declarations.
    private mutating func parseSubpackage(
        _ annotations: [EmfaticAnnotation], start: SourcePosition, into parent: inout DraftPackage,
        imports: inout [SourceRange]
    ) {
        cursor.advance()
        let name = self.name("for the subpackage") ?? ("", cursor.current.range)
        var package = DraftPackage(name: name.value, location: DraftLocation(range: name.range, nameRange: name.range))
        applyPackageAnnotations(annotations, to: &package)
        if cursor.expect("{", "to open the subpackage") {
            while !cursor.isAtEnd, !cursor.current.isPunctuation("}") {
                parseDeclaration(into: &package, imports: &imports)
            }
            cursor.expect("}", "to close the subpackage")
        } else {
            recover(words: Self.declarationStarts)
        }
        package.location.range = cursor.range(from: start)
        parent.subpackages.append(package)
    }

    /// Parses a class or interface declaration.
    ///
    /// - Parameters:
    ///   - annotations: The annotations written before the declaration.
    ///   - start: The position at which the declaration starts.
    /// - Returns: The draft classifier.
    private mutating func parseClass(_ annotations: [EmfaticAnnotation], start: SourcePosition) -> DraftClassifier {
        let isAbstract = acceptWord(.abstract)
        var isInterface = false
        if acceptWord(.interface) {
            isInterface = true
        } else {
            cursor.expectWord(Keyword.class.rawValue, "to declare a class")
        }
        let name = self.name("for the class") ?? ("", cursor.current.range)
        var classifier = DraftClassifier(kind: .class, name: name.value, location: DraftLocation(range: name.range, nameRange: name.range))
        classifier.isAbstract = isAbstract
        classifier.isInterface = isInterface
        classifier.annotations = annotations.map { resolve($0) }
        classifier.typeParameters = parseTypeParameters()
        if acceptWord(.extends) {
            repeat {
                if let type = parseType() { classifier.superTypes.append(type) }
            } while cursor.accept(",")
        }
        if cursor.accept(":") { classifier.instanceTypeName = parseInstanceName() }
        if cursor.expect("{", "to open the class body") {
            while !cursor.isAtEnd, !cursor.current.isPunctuation("}") { parseMember(into: &classifier) }
            cursor.expect("}", "to close the class body")
        } else {
            recover(words: Self.declarationStarts)
        }
        classifier.location.range = cursor.range(from: start)
        return classifier
    }

    /// Parses the name of an instance class, written either as a string or as a type name.
    ///
    /// - Returns: The instance class name, or `nil` if none could be read.
    private mutating func parseInstanceName() -> String? {
        if cursor.current.kind == .string { return cursor.advance().value }
        return parseType().map(\.text)
    }

    /// Parses a data type declaration.
    ///
    /// - Parameters:
    ///   - annotations: The annotations written before the declaration.
    ///   - start: The position at which the declaration starts.
    /// - Returns: The draft classifier.
    private mutating func parseDataType(_ annotations: [EmfaticAnnotation], start: SourcePosition) -> DraftClassifier {
        let isTransient = acceptWord(.transient)
        cursor.advance()
        let name = self.name("for the data type") ?? ("", cursor.current.range)
        var classifier = DraftClassifier(kind: .dataType, name: name.value, location: DraftLocation(range: name.range, nameRange: name.range))
        classifier.serialisable = !isTransient
        classifier.annotations = annotations.map { resolve($0) }
        if cursor.expect(":", "before the instance class name of the data type") {
            classifier.instanceTypeName = parseInstanceName()
        }
        if !cursor.expect(";", "after the data type") { recover(words: Self.declarationStarts) }
        classifier.location.range = cursor.range(from: start)
        return classifier
    }

    /// Parses an enumeration declaration.
    ///
    /// - Parameters:
    ///   - annotations: The annotations written before the declaration.
    ///   - start: The position at which the declaration starts.
    /// - Returns: The draft classifier.
    private mutating func parseEnum(_ annotations: [EmfaticAnnotation], start: SourcePosition) -> DraftClassifier {
        cursor.advance()
        let name = self.name("for the enumeration") ?? ("", cursor.current.range)
        var classifier = DraftClassifier(kind: .enumeration, name: name.value, location: DraftLocation(range: name.range, nameRange: name.range))
        classifier.annotations = annotations.map { resolve($0) }
        var next = 0
        if cursor.expect("{", "to open the enumeration") {
            while !cursor.isAtEnd, !cursor.current.isPunctuation("}") {
                let literalStart = cursor.current.range.start
                var literalAnnotations = parseAnnotations()
                let nameToken = cursor.current
                guard let literalName = self.name("for the enumeration literal") else {
                    recover()
                    continue
                }
                mark(nameToken, as: .enumLiteral)
                var value = next
                if cursor.accept("=") {
                    let negative = cursor.accept("-")
                    if cursor.current.kind == .integer, let number = Int(cursor.current.text) {
                        value = negative ? -number : number
                        cursor.advance()
                    } else {
                        cursor.unexpected("an integer value for the literal")
                    }
                }
                literalAnnotations += parseAnnotations()
                if !cursor.expect(";", "after the enumeration literal") { recover() }
                var literal = DraftLiteral(
                    name: literalName.value, value: value,
                    location: DraftLocation(range: cursor.range(from: literalStart), nameRange: literalName.range))
                literal.annotations = literalAnnotations.map { resolve($0) }
                classifier.literals.append(literal)
                next = value + 1
            }
            cursor.expect("}", "to close the enumeration")
        } else {
            recover(words: Self.declarationStarts)
        }
        classifier.location.range = cursor.range(from: start)
        return classifier
    }

    /// Parses a map entry declaration.
    ///
    /// - Parameters:
    ///   - annotations: The annotations written before the declaration.
    ///   - start: The position at which the declaration starts.
    /// - Returns: The draft classifier.
    private mutating func parseMapEntry(_ annotations: [EmfaticAnnotation], start: SourcePosition) -> DraftClassifier {
        cursor.advance()
        let name = self.name("for the map entry") ?? ("", cursor.current.range)
        var classifier = DraftClassifier(kind: .class, name: name.value, location: DraftLocation(range: name.range, nameRange: name.range))
        classifier.instanceTypeName = EmfaticLanguage.mapEntryInstanceClassName
        classifier.annotations = annotations.map { resolve($0) }
        cursor.expect(":", "before the key type of the map entry")
        for feature in EmfaticLanguage.MapEntryFeature.allCases {
            if feature == .value { cursor.expect("->", "between the key and value types of the map entry") }
            let typeStart = cursor.current.range
            guard let type = parseType() else { break }
            var draft = DraftFeature(
                kind: .inferred, name: feature.rawValue, type: type,
                location: DraftLocation(range: type.range ?? typeStart, nameRange: type.range ?? typeStart))
            if let bounds = cursor.multiplicity() {
                draft.lowerBound = bounds.lower
                draft.upperBound = bounds.upper
                draft.location.range = cursor.range(from: typeStart.start)
            }
            classifier.features.append(draft)
        }
        if !cursor.expect(";", "after the map entry") { recover(words: Self.declarationStarts) }
        classifier.location.range = cursor.range(from: start)
        return classifier
    }

    // MARK: Members

    /// Parses the modifiers written before a member.
    ///
    /// - Returns: The modifiers in source order.
    private mutating func parseModifiers() -> [EmfaticModifier] {
        var modifiers: [EmfaticModifier] = []
        while true {
            let start = cursor.current.range.start
            let negated = cursor.current.isPunctuation(EmfaticLanguage.negation)
            let wordToken = cursor.peek(negated ? 1 : 0)
            guard wordToken.kind == .identifier, !wordToken.isEscaped,
                EmfaticLanguage.modifiers.contains(wordToken.text), let keyword = Keyword(rawValue: wordToken.text)
            else { break }
            if negated { cursor.advance() }
            cursor.advance()
            modifiers.append(EmfaticModifier(word: keyword, isNegated: negated, range: cursor.range(from: start)))
        }
        return modifiers
    }

    /// Parses one member of a class.
    ///
    /// - Parameter classifier: The draft classifier that receives the member.
    private mutating func parseMember(into classifier: inout DraftClassifier) {
        let start = cursor.current.range.start
        let annotations = parseAnnotations().map { resolve($0) }
        let modifiers = parseModifiers()
        if acceptWord(.attr) {
            guard var feature = parseFeature(kind: .attribute, start: start) else { return }
            if cursor.accept("=") { feature.defaultValue = parseDefaultValue() }
            finishFeature(&feature, annotations: annotations, modifiers: modifiers, start: start, into: &classifier)
        } else if isWord(.ref) || isWord(.val) {
            let containment = isWord(.val)
            cursor.advance()
            guard var feature = parseFeature(kind: .reference, start: start) else { return }
            feature.containment = containment
            finishFeature(&feature, annotations: annotations, modifiers: modifiers, start: start, into: &classifier)
        } else if acceptWord(.op) {
            parseOperation(annotations: annotations, modifiers: modifiers, start: start, into: &classifier)
        } else {
            cursor.unexpected("'attr', 'ref', 'val' or 'op'")
            recover()
        }
    }

    /// Reads the type, multiplicity, opposite and name of a feature.
    private mutating func parseFeature(kind: DraftFeature.Kind, start: SourcePosition) -> DraftFeature? {
        guard let type = parseType() else {
            recover()
            return nil
        }
        let bounds = cursor.multiplicity()
        var opposite: (value: String, range: SourceRange)?
        if kind == .reference, cursor.accept("#") { opposite = name("for the opposite reference") }
        guard let name = name("for the feature") else {
            recover()
            return nil
        }
        var feature = DraftFeature(kind: kind, name: name.value, type: type, location: DraftLocation(range: name.range, nameRange: name.range))
        if let bounds {
            feature.lowerBound = bounds.lower
            feature.upperBound = bounds.upper
        }
        feature.opposite = opposite?.value
        feature.oppositeRange = opposite?.range
        return feature
    }

    /// Completes a feature and adds it to its class.
    ///
    /// - Parameters:
    ///   - feature: The feature to complete.
    ///   - annotations: The annotations written before the feature.
    ///   - modifiers: The modifiers written before the feature.
    ///   - start: The position at which the feature starts.
    ///   - classifier: The draft classifier that receives the feature.
    private mutating func finishFeature(
        _ feature: inout DraftFeature, annotations: [DraftAnnotation], modifiers: [EmfaticModifier],
        start: SourcePosition, into classifier: inout DraftClassifier
    ) {
        if !cursor.expect(";", "after the feature") { recover() }
        feature.annotations = annotations
        for modifier in modifiers { apply(modifier, to: &feature) }
        feature.location.range = cursor.range(from: start)
        classifier.features.append(feature)
    }

    /// Applies a modifier to a feature, reporting modifiers that do not apply.
    ///
    /// - Parameters:
    ///   - modifier: The modifier to apply.
    ///   - feature: The feature to change.
    private mutating func apply(_ modifier: EmfaticModifier, to feature: inout DraftFeature) {
        let value = !modifier.isNegated
        switch modifier.word {
        case .readonly: feature.changeable = !value
        case .volatile: feature.volatile = value
        case .transient: feature.transient = value
        case .unsettable: feature.unsettable = value
        case .derived: feature.derived = value
        case .unique: feature.unique = value
        case .ordered: feature.ordered = value
        case .resolve where feature.kind == .reference: feature.resolveProxies = value
        case .id where feature.kind == .attribute: feature.isID = value
        default: ignore(modifier, on: feature.kind == .attribute ? "attributes" : "references")
        }
    }

    /// Reports a modifier that does not apply to the elements it was written on.
    ///
    /// - Parameters:
    ///   - modifier: The modifier that is ignored.
    ///   - elements: A description of the elements, for the diagnostic.
    private mutating func ignore(_ modifier: EmfaticModifier, on elements: String) {
        cursor.report(cursor.factory.warning(
            .unsupportedConstruct, "The modifier '\(modifier.word.rawValue)' does not apply to \(elements) and is ignored",
            at: modifier.range))
    }

    /// Applies the ordering and uniqueness modifiers of an operation or parameter.
    ///
    /// - Parameters:
    ///   - modifiers: The modifiers to apply.
    ///   - ordered: Set according to the `ordered` modifier.
    ///   - unique: Set according to the `unique` modifier.
    ///   - elements: A description of the elements, for diagnostics.
    private mutating func applyMultiplicityModifiers(
        _ modifiers: [EmfaticModifier], ordered: inout Bool, unique: inout Bool, on elements: String
    ) {
        for modifier in modifiers {
            switch modifier.word {
            case .ordered: ordered = !modifier.isNegated
            case .unique: unique = !modifier.isNegated
            default: ignore(modifier, on: elements)
            }
        }
    }

    /// Parses a default value initialiser.
    ///
    /// - Returns: The default value text, or `nil` if there is none.
    private mutating func parseDefaultValue() -> String? {
        let token = cursor.current
        switch token.kind {
        case .string, .character:
            cursor.advance()
            return Self.decodedText(token.value)
        case .integer, .real:
            cursor.advance()
            return token.text
        case .punctuation where token.text == "-":
            cursor.advance()
            guard cursor.current.kind == .integer || cursor.current.kind == .real else {
                cursor.unexpected("a number after '-'")
                return nil
            }
            return "-" + cursor.advance().text
        case .identifier where !token.isEscaped && TokenClassifier.booleans.contains(token.text):
            cursor.advance()
            return token.text
        case .identifier:
            return qualifiedName("for the default value")?.value
        default:
            cursor.unexpected("a default value")
            return nil
        }
    }

    /// Parses an operation.
    ///
    /// - Parameters:
    ///   - annotations: The annotations written before the operation.
    ///   - modifiers: The modifiers written before the operation.
    ///   - start: The position at which the operation starts.
    ///   - classifier: The draft classifier that receives the operation.
    private mutating func parseOperation(
        annotations: [DraftAnnotation], modifiers: [EmfaticModifier], start: SourcePosition,
        into classifier: inout DraftClassifier
    ) {
        let typeParameters = parseTypeParameters()
        var returnType: DraftType?
        var bounds: (lower: Int, upper: Int)?
        if !acceptWord(.void) {
            guard let type = parseType() else {
                recover()
                return
            }
            returnType = type
            bounds = cursor.multiplicity()
        }
        guard let name = name("for the operation") else {
            recover()
            return
        }
        var operation = DraftOperation(name: name.value, location: DraftLocation(range: name.range, nameRange: name.range))
        operation.typeParameters = typeParameters
        operation.returnType = returnType
        if let bounds {
            operation.lowerBound = bounds.lower
            operation.upperBound = bounds.upper
        }
        operation.annotations = annotations
        applyMultiplicityModifiers(modifiers, ordered: &operation.ordered, unique: &operation.unique, on: "operations")
        if cursor.expect("(", "to open the parameters") {
            if !cursor.current.isPunctuation(")") {
                repeat {
                    if let parameter = parseParameter() { operation.parameters.append(parameter) }
                } while cursor.accept(",")
            }
            if !cursor.expect(")", "to close the parameters") { cursor.skip(untilAny: [")", ";"]); cursor.accept(")") }
        }
        if acceptWord(.throws) {
            repeat {
                if let type = parseType() { operation.exceptions.append(type) }
            } while cursor.accept(",")
        }
        if !cursor.expect(";", "after the operation") { recover() }
        operation.location.range = cursor.range(from: start)
        classifier.operations.append(operation)
    }

    /// Parses an operation parameter.
    ///
    /// - Returns: The draft parameter, or `nil` if it could not be read.
    private mutating func parseParameter() -> DraftParameter? {
        let start = cursor.current.range.start
        var annotations = parseAnnotations()
        let modifiers = parseModifiers()
        guard let type = parseType() else { return nil }
        let bounds = cursor.multiplicity()
        guard let name = name("for the parameter") else { return nil }
        annotations += parseAnnotations()
        var parameter = DraftParameter(name: name.value, type: type, location: DraftLocation(range: name.range, nameRange: name.range))
        if let bounds {
            parameter.lowerBound = bounds.lower
            parameter.upperBound = bounds.upper
        }
        parameter.annotations = annotations.map { resolve($0) }
        applyMultiplicityModifiers(modifiers, ordered: &parameter.ordered, unique: &parameter.unique, on: "parameters")
        parameter.location.range = cursor.range(from: start)
        return parameter
    }

    // MARK: Types

    /// Reads a type with optional type arguments.
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

    /// Parses a type argument, including wildcards.
    ///
    /// - Returns: The draft type, or `nil` if it could not be read.
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

    /// Parses a list of type parameters.
    ///
    /// - Returns: The draft type parameters; empty if none are written.
    private mutating func parseTypeParameters() -> [DraftTypeParameter] {
        guard cursor.accept("<") else { return [] }
        var parameters: [DraftTypeParameter] = []
        repeat {
            let start = cursor.current.range.start
            guard let name = name("for the type parameter") else { break }
            var parameter = DraftTypeParameter(name: name.value)
            if acceptWord(.extends) {
                repeat {
                    if let bound = parseType() { parameter.bounds.append(bound) }
                } while cursor.accept("&")
            }
            parameter.range = cursor.range(from: start)
            parameters.append(parameter)
        } while cursor.accept(",")
        cursor.expect(">", "to close the type parameters")
        return parameters
    }

    // MARK: Annotations

    /// Parses the annotations written before a declaration.
    ///
    /// - Returns: The annotations in source order.
    private mutating func parseAnnotations() -> [EmfaticAnnotation] {
        var annotations: [EmfaticAnnotation] = []
        while cursor.current.isPunctuation("@") {
            let at = cursor.advance()
            mark(at, as: .directive)
            let start = at.range.start
            var label: String
            var isQuoted = false
            if cursor.current.kind == .string {
                let token = cursor.advance()
                mark(token, as: .directive)
                label = Self.decodedText(token.value)
                isQuoted = true
            } else if let name = qualifiedName("for the annotation", role: .directive) {
                label = name.value
            } else {
                recover()
                continue
            }
            var details: [DraftDetail] = []
            if cursor.accept("(") {
                var implicit = 0
                while !cursor.isAtEnd, !cursor.current.isPunctuation(")") {
                    guard let first = annotationValue() else {
                        cursor.skip(untilAny: [",", ")", ";"])
                        if !cursor.accept(",") { break }
                        continue
                    }
                    if cursor.accept("=") {
                        details.append(DraftDetail(key: first, value: annotationValue() ?? ""))
                    } else {
                        let keys = isQuoted ? [] : labels[label.lowercased()]?.implicitKeys ?? []
                        let extra = implicit - keys.count
                        let key = extra < 0
                            ? keys[implicit] : EmfaticLanguage.implicitKey + (extra == 0 ? "" : String(extra + 1))
                        if implicit >= keys.count {
                            cursor.report(cursor.factory.warning(
                                .unsupportedConstruct, "The annotation value '\(first)' has no key; using '\(key)'",
                                at: cursor.previous?.range))
                        }
                        details.append(DraftDetail(key: key, value: first))
                        implicit += 1
                    }
                    if !cursor.accept(",") { break }
                }
                cursor.expect(")", "to close the annotation")
            }
            let annotation = EmfaticAnnotation(label: label, isQuoted: isQuoted, details: details, range: cursor.range(from: start))
            if resolveSource(of: annotation) == EmfaticLanguage.annotationMapSource { define(labelsIn: annotation) }
            annotations.append(annotation)
        }
        return annotations
    }

    /// Reads a key or value of an annotation detail.
    private mutating func annotationValue() -> String? {
        let token = cursor.current
        switch token.kind {
        case .string:
            cursor.advance()
            return Self.decodedText(token.value)
        case .integer, .real:
            cursor.advance()
            return token.text
        case .identifier where !token.isEscaped && TokenClassifier.booleans.contains(token.text):
            cursor.advance()
            return token.text
        case .identifier:
            return qualifiedName("in the annotation")?.value
        case .punctuation where token.text == "-" && (cursor.peek(1).kind == .integer || cursor.peek(1).kind == .real):
            cursor.advance()
            return "-" + cursor.advance().text
        default:
            cursor.unexpected("an annotation key or value")
            return nil
        }
    }

    /// Decodes the one escape sequence that Emfatic resolves, an escaped double quote.
    ///
    /// Emfatic keeps every other escape sequence of a literal as written.
    ///
    /// - Parameter raw: The text between the quotes of a literal.
    /// - Returns: The text with `\"` replaced by `"`.
    static func decodedText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\\"", with: "\"")
    }

    /// Registers the labels that an `EmfaticAnnotationMap` annotation defines.
    private mutating func define(labelsIn annotation: EmfaticAnnotation) {
        for detail in annotation.details {
            var label = detail.key
            var keys: [String] = []
            if let open = label.firstIndex(of: "("), label.hasSuffix(")") {
                keys = label[label.index(after: open)..<label.index(before: label.endIndex)]
                    .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                label = String(label[..<open])
            }
            labels[label.lowercased()] = (detail.value, keys)
        }
    }

    /// Determines the source URI of an annotation.
    ///
    /// - Parameter annotation: The annotation to resolve.
    /// - Returns: The source named by a known label, or the written text otherwise.
    private func resolveSource(of annotation: EmfaticAnnotation) -> String {
        if annotation.isQuoted { return annotation.label }
        return labels[annotation.label.lowercased()]?.source ?? annotation.label
    }

    /// Converts an annotation into a draft annotation with a resolved source.
    private func resolve(_ annotation: EmfaticAnnotation) -> DraftAnnotation {
        DraftAnnotation(source: resolveSource(of: annotation), details: annotation.details, range: annotation.range)
    }
}
