//
// TextSupportTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore



/// Creates a draft location whose ranges span the given offsets.
private func span(_ start: Int, _ end: Int) -> DraftLocation {
    func position(_ offset: Int) -> SourcePosition { SourcePosition(utf8Offset: offset, line: 1, column: offset + 1) }
    let whole = SourceRange(start: position(start), end: position(end))
    return DraftLocation(range: whole, nameRange: SourceRange(start: position(start + 1), end: position(end - 1)))
}

/// Tests for the outline of drafts.
@Suite("Outline builder")
struct OutlineBuilderTests {
    /// Creates a shop draft with every kind of classifier and member.
    private func shopDraft() -> DraftPackage {
        var item = classDraft("Item", supers: ["Base", "Tagged"])
        item.features = [featureDraft(.attribute, "title", "String"), featureDraft(.inferred, "peer", "Item")]
        item.features[0].lowerBound = 1
        item.features[0].upperBound = -1
        item.features.append(featureDraft(.reference, "owner", "Shop"))
        var operation = DraftOperation(name: "price", location: span(70, 80))
        operation.parameters = [
            DraftParameter(name: "count", type: DraftType(name: "Int")),
            {
                var many = DraftParameter(name: "tags", type: DraftType(name: "String"))
                many.upperBound = -1
                return many
            }(),
        ]
        operation.returnType = DraftType(name: "Money")
        operation.upperBound = -1
        item.operations = [operation, DraftOperation(name: "reset")]
        item.location = span(10, 60)
        var interface = classDraft("Tagged")
        interface.isInterface = true
        var money = DraftClassifier(kind: .dataType, name: "Money")
        money.instanceTypeName = "java.math.BigDecimal"
        var plain = DraftClassifier(kind: .dataType, name: "Plain")
        plain.instanceTypeName = nil
        var category = DraftClassifier(kind: .enumeration, name: "Category")
        category.literals = [DraftLiteral(name: "FOOD", value: 3, location: span(90, 96))]
        var shop = packageDraft("shop", [item, interface, money, plain, category, classDraft("Item")])
        shop.location = span(0, 100)
        shop.subpackages = [packageDraft("stock", [classDraft("Shelf")])]
        shop.subpackages[0].nsURI = ""
        return shop
    }

    /// Identifiers combine kinds, names and parent paths, and repeated identifiers get a numbered suffix.
    @Test func buildsIdentifiersAndKinds() throws {
        let outline = OutlineBuilder.outline(of: [shopDraft(), shopDraft()])
        let first = try #require(outline.first)
        #expect(first.id == "package:shop")
        #expect(first.kind == OutlineKind.package)
        #expect(first.detail == "http://example.org/shop")
        #expect(first.range == span(0, 100).range)
        #expect(first.selectionRange == span(0, 100).nameRange)
        #expect(outline[1].id == "package:shop#2")
        #expect(
            first.children.map(\.id) == [
                "package:shop/class:Item", "package:shop/interface:Tagged", "package:shop/datatype:Money",
                "package:shop/datatype:Plain", "package:shop/enum:Category", "package:shop/class:Item#2",
                "package:shop/package:stock",
            ])
        #expect(first.children.map(\.kind) == ["class", "interface", "datatype", "datatype", "enum", "class", "package"])
        #expect(outline[1].children.first?.id == "package:shop#2/class:Item")
    }

    /// Details describe supertypes, instance types, literal values, features and operations.
    @Test func buildsDetails() throws {
        let first = try #require(OutlineBuilder.outline(of: [shopDraft()]).first)
        let item = first.children[0]
        #expect(item.detail == "Base, Tagged")
        #expect(item.range == span(10, 60).range)
        #expect(first.children[1].detail == nil)
        #expect(first.children[2].detail == "java.math.BigDecimal")
        #expect(first.children[3].detail == nil)
        #expect(first.children[4].children.first?.detail == "3")
        #expect(first.children[4].children.first?.kind == OutlineKind.literal)
        #expect(first.children[4].children.first?.selectionRange == span(90, 96).nameRange)
        #expect(first.children[6].detail == nil)
        let members = item.children
        #expect(members.map(\.kind) == ["attribute", "attribute", "reference", "operation", "operation"])
        #expect(members.map(\.detail) == ["String[+]", "Item", "Shop", "(Int, String[*]) : Money[*]", "()"])
        #expect(members[3].id == "package:shop/class:Item/operation:price")
        #expect(members[3].selectionRange == span(70, 80).nameRange)
    }

    /// Multiplicity suffixes are empty for the default and bracketed otherwise.
    @Test func multiplicitySuffix() {
        #expect(OutlineBuilder.multiplicity(0, 1).isEmpty)
        #expect(OutlineBuilder.multiplicity(0, -1) == "[*]")
        #expect(OutlineBuilder.multiplicity(2, 5) == "[2..5]")
    }
}

/// Tests for multiplicity text.
@Suite("Multiplicity text")
struct MultiplicityTextTests {
    /// Bounds use the shortest notation.
    @Test(arguments: [
        (0, -1, "*"), (1, -1, "+"), (0, 1, "?"), (2, 2, "2"), (1, 4, "1..4"), (2, -1, "2..*"), (2, -2, "2..?"),
        (0, 0, "0"),
    ])
    func formatsBounds(lower: Int, upper: Int, expected: String) {
        #expect(MultiplicityText.bounds(lower, upper) == expected)
    }

    /// Upper bounds render the unbounded and unspecified markers.
    @Test func formatsBound() {
        #expect(MultiplicityText.bound(-1) == "*")
        #expect(MultiplicityText.bound(-2) == "?")
        #expect(MultiplicityText.bound(7) == "7")
    }

    /// Values parse markers and integers with underscores.
    @Test func parsesValues() {
        #expect(MultiplicityText.value(of: "*") == -1)
        #expect(MultiplicityText.value(of: "+") == -1)
        #expect(MultiplicityText.value(of: "?") == -2)
        #expect(MultiplicityText.value(of: "1_000") == 1000)
        #expect(MultiplicityText.value(of: "x") == nil)
    }
}

/// Tests for the token classifier.
@Suite("Token classifier")
struct TokenClassifierTests {
    /// The classifier under test, with a few words of each kind.
    private let classifier = TokenClassifier(keywords: ["class", "true2"], operators: ["->"], typeNames: ["String"])

    /// Scans the text with a small configuration.
    private func scan(_ text: String) -> LexicalScan {
        TextLexer.scan(
            text,
            configuration: LexicalConfiguration(
                identifierEscape: "~", punctuation: ["->", "{", ";"], stringDelimiters: ["\""], characterDelimiter: "'"))
    }

    /// Every token kind maps to its source token kind.
    @Test func classifiesKinds() {
        let text = "class ~class true false String name \"s\" 'c' 1 2.5 -> { // l\n/* b */ /** d */ #"
        let kinds = classifier.sourceTokens(of: scan(text)).map(\.kind)
        #expect(
            kinds == [
                .keyword, .identifier, .boolean, .boolean, .typeName, .identifier, .string, .string, .number, .number,
                .operator, .punctuation, .comment, .comment, .documentation, .invalid,
            ])
    }

    /// An invalid or end-of-file token is classified as invalid.
    @Test func classifiesInvalidAndEndOfFile() {
        let range = SourceRange(start: .start, end: .start)
        #expect(classifier.kind(of: TextToken(kind: .endOfFile, text: "", range: range)) == .invalid)
        #expect(classifier.kind(of: TextToken(kind: .invalid, text: "#", range: range)) == .invalid)
        #expect(TokenClassifier.booleans == ["true", "false"])
    }

    /// Overrides replace the classification of the token at an offset.
    @Test func appliesOverrides() {
        let result = classifier.sourceTokens(of: scan("name String"), overrides: [5: .enumLiteral, 0: .typeName])
        #expect(result.map(\.kind) == [.typeName, .enumLiteral])
        #expect(result[1].range.start.utf8Offset == 5)
    }
}

/// Tests for the indented text builder.
@Suite("Indented text")
struct IndentedTextTests {
    /// Lines are indented by the current depth and outdenting never goes below zero.
    @Test func indentsAndOutdents() {
        var text = IndentedText(indentUnit: "  ")
        text.line("a")
        text.indent()
        text.line("b")
        text.indent()
        text.line("c")
        text.outdent()
        text.outdent()
        text.outdent()
        #expect(text.depth == 0)
        text.line("d")
        #expect(text.lines == ["a", "  b", "    c", "d"])
        #expect(IndentedText().indentUnit == "\t")
    }

    /// Multi-line text indents each non-empty line, and an empty line stays empty.
    @Test func multiLineLines() {
        var text = IndentedText()
        text.indent()
        text.line("one\n\ntwo")
        text.line()
        #expect(text.lines == ["\tone", "", "\ttwo", ""])
    }

    /// Verbatim text indents only its first line.
    @Test func verbatimIndentsFirstLineOnly() {
        var text = IndentedText()
        text.indent()
        text.verbatim("first\n  second\nthird")
        #expect(text.lines == ["\tfirst", "  second", "third"])
    }

    /// Separating adds a single blank line, and never at the start.
    @Test func separatesOnce() {
        var text = IndentedText()
        text.separate()
        #expect(text.lines.isEmpty)
        text.line("a")
        text.separate()
        text.separate()
        text.line("b")
        #expect(text.lines == ["a", "", "b"])
    }

    /// Trailing empty lines can be trimmed, and the text ends with a newline when not empty.
    @Test func trimsAndRendersText() {
        var text = IndentedText()
        #expect(text.text.isEmpty)
        text.line("a")
        text.line()
        text.line()
        text.trimTrailingEmptyLines()
        #expect(text.lines == ["a"])
        text.line("b")
        #expect(text.text == "a\nb\n")
    }
}

/// Builds a shop and a till package for the naming tests.
private func namingPackages() -> [EPackage] {
    let stock = EPackage(
        name: "stock", nsURI: "u:stock", nsPrefix: "stock",
        eClassifiers: [EClass(name: "Shelf"), EClass(name: "Order")])
    let shop = EPackage(
        name: "shop", nsURI: "u:shop", nsPrefix: "shop",
        eClassifiers: [EClass(name: "Item"), EClass(name: "Order")], eSubpackages: [stock])
    let till = EPackage(name: "till", nsURI: "u:till", nsPrefix: "till", eClassifiers: [EClass(name: "Sale")])
    return [shop, till]
}

/// Tests for classifier naming.
@Suite("Classifier naming")
struct ClassifierNamingTests {
    /// Classifiers are named with the shortest name that resolves from the given package.
    @Test func usesShortestName() throws {
        let packages = namingPackages()
        let naming = ClassifierNaming(packages: packages)
        let shelf = try #require(packages[0].eSubpackages.first?.eClassifiers.first { $0.name == "Shelf" })
        let item = try #require(packages[0].eClassifiers.first { $0.name == "Item" })
        let sale = try #require(packages[1].eClassifiers.first)
        #expect(naming.name(of: shelf, from: "shop.stock") == "Shelf")
        #expect(naming.name(of: shelf, from: "shop") == "stock.Shelf")
        #expect(naming.name(of: shelf, from: "till") == "shop.stock.Shelf")
        #expect(naming.name(of: shelf, from: "") == "shop.stock.Shelf")
        #expect(naming.name(of: item, from: "shop.stock") == "Item")
        #expect(naming.name(of: sale, from: "shop") == "till.Sale")
        #expect(naming.isLocal(shelf))
    }

    /// Names that another classifier hides are qualified.
    @Test func qualifiesHiddenNames() throws {
        let packages = namingPackages()
        let naming = ClassifierNaming(packages: packages)
        let order = try #require(packages[0].eClassifiers.first { $0.name == "Order" })
        #expect(naming.name(of: order, from: "shop.stock") == "shop.Order")
        #expect(naming.name(of: order, from: "shop") == "Order")
    }

    /// Shadowing names, such as type parameters, force a longer name.
    @Test func shadowedNamesAreQualified() throws {
        let packages = namingPackages()
        let naming = ClassifierNaming(packages: packages)
        let shelf = try #require(packages[0].eSubpackages.first?.eClassifiers.first)
        #expect(naming.name(of: shelf, from: "shop.stock", shadowing: ["Shelf"]) == "stock.Shelf")
        #expect(naming.name(of: shelf, from: "shop.stock", shadowing: ["Shelf", "stock.Shelf"]) == "shop.stock.Shelf")
    }

    /// Foreign classifiers have no local name.
    @Test func foreignClassifiersHaveNoName() throws {
        let naming = ClassifierNaming(packages: namingPackages())
        let string = try #require(EcorePackage.classifier(named: "EString"))
        #expect(!naming.isLocal(string))
        #expect(naming.name(of: string, from: "shop") == nil)
    }

    /// The root key function changes how packages are keyed.
    @Test func customRootKeys() throws {
        let packages = namingPackages()
        let naming = ClassifierNaming(packages: packages) { "org." + $0.name }
        let item = try #require(packages[0].eClassifiers.first)
        #expect(naming.name(of: item, from: "org.shop") == "Item")
        #expect(naming.name(of: item, from: "org.till") == "shop.Item")
    }

    /// Scopes list enclosing packages from the innermost to the root.
    @Test func listsScopes() {
        #expect(ClassifierNaming.scopes(of: "a.b.c") == ["a.b.c", "a.b", "a", ""])
        #expect(ClassifierNaming.scopes(of: "a") == ["a", ""])
    }

    /// Names resolve through scopes from the innermost out.
    @Test func resolvesThroughScopes() {
        let naming = ClassifierNaming(packages: namingPackages())
        let scopes = ClassifierNaming.scopes(of: "shop.stock")
        #expect(naming.resolve("Shelf", scopes: scopes) == "shop.stock.Shelf")
        #expect(naming.resolve("Order", scopes: scopes) == "shop.stock.Order")
        #expect(naming.resolve("Item", scopes: scopes) == "shop.Item")
        #expect(naming.resolve("Nothing", scopes: scopes) == nil)
    }

    /// External names skip candidates that a local classifier would capture, then fall back to the last.
    @Test func choosesExternalNames() {
        let naming = ClassifierNaming(packages: namingPackages())
        #expect(naming.externalName(["String", "EString"], from: "shop") == "String")
        #expect(naming.externalName(["Item", "EItem"], from: "shop") == "EItem")
        #expect(naming.externalName(["String", "EString"], from: "shop", shadowing: ["String"]) == "EString")
        #expect(naming.externalName(["Item", "Order"], from: "shop") == "Order")
        #expect(naming.externalName([], from: "shop") == nil)
    }
}

/// Tests for the Ecore built-in check and the feature facts.
@Suite("Ecore built-ins and feature facts")
struct EcoreSupportTests {
    /// Only the identical Ecore classifiers count as built in.
    @Test func recognisesBuiltins() throws {
        let string = try #require(EcorePackage.classifier(named: "EString"))
        #expect(EcoreBuiltins.isBuiltin(string))
        #expect(!EcoreBuiltins.isBuiltin(EDataType(name: "EString")))
        #expect(!EcoreBuiltins.isBuiltin(EClass(name: "Item")))
    }

    /// The facts of an attribute are exposed uniformly.
    @Test func attributeFacts() throws {
        let string = try #require(EcorePackage.classifier(named: "EString"))
        let attribute = EAttribute(
            name: "title", eType: string, lowerBound: 1, upperBound: 3, changeable: false, volatile: true,
            transient: true, defaultValueLiteral: "x", isID: true,
            eAnnotations: [EAnnotation(source: "note")], ordered: false, unique: false, unsettable: true, derived: true)
        let facts = try #require(FeatureFacts(attribute))
        #expect(facts.attribute != nil && facts.reference == nil)
        #expect(facts.name == "title")
        #expect(facts.eType.id == string.id)
        #expect(facts.eGenericType == nil)
        #expect(facts.lowerBound == 1 && facts.upperBound == 3)
        #expect(!facts.changeable && facts.volatile && facts.transient && facts.unsettable && facts.derived)
        #expect(!facts.unique && !facts.ordered)
        #expect(facts.defaultValueLiteral == "x")
        #expect(facts.eAnnotations.first?.source == "note")
        #expect(facts.isMany)
    }

    /// The facts of a reference are exposed uniformly.
    @Test func referenceFacts() throws {
        let target = EClass(name: "Item")
        var reference = EReference(name: "peer", eType: target, lowerBound: 0, upperBound: 1)
        reference.defaultValueLiteral = "d"
        let facts = try #require(FeatureFacts(reference))
        #expect(facts.reference != nil && facts.attribute == nil)
        #expect(facts.name == "peer")
        #expect(facts.eType.id == target.id)
        #expect(facts.changeable && !facts.volatile && !facts.transient && !facts.unsettable && !facts.derived)
        #expect(facts.unique && facts.ordered)
        #expect(facts.defaultValueLiteral == "d")
        #expect(!facts.isMany)
        reference.upperBound = -1
        #expect(try #require(FeatureFacts(reference)).isMany)
    }
}

/// Tests for the structural metamodel signature.
@Suite("Metamodel signature")
struct MetamodelSignatureTests {
    /// Creates a rich shop draft, optionally with a changed flag or annotation.
    private func richDraft(volatile: Bool = false, unique: Bool = true, annotation: Bool = false) -> DraftPackage {
        var box = classDraft("Box")
        box.typeParameters = [DraftTypeParameter(name: "T", bounds: [DraftType(name: "Item")])]
        var value = featureDraft(.reference, "value", "T")
        value.volatile = volatile
        box.features = [value]
        var wildcard = DraftOperation(name: "peek")
        wildcard.typeParameters = [DraftTypeParameter(name: "E")]
        wildcard.parameters = [
            DraftParameter(
                name: "other",
                type: DraftType(
                    name: "Box",
                    arguments: [
                        DraftType(name: "", wildcard: .upper, bounds: [DraftType(name: "Item")]),
                        DraftType(name: "", wildcard: .lower, bounds: [DraftType(name: "Item")]),
                        DraftType(name: "", wildcard: .unbounded),
                    ]))
        ]
        wildcard.returnType = DraftType(name: "E")
        wildcard.exceptions = [DraftType(name: "Failure"), DraftType(name: "Box", arguments: [DraftType(name: "Item")])]
        wildcard.annotations = [DraftAnnotation(source: "op", details: [DraftDetail(key: "k", value: "v")])]
        box.operations = [wildcard, DraftOperation(name: "reset")]
        var sub = classDraft("Sub")
        sub.superTypes = [DraftType(name: "Box", arguments: [DraftType(name: "Item")])]
        var plainSub = classDraft("PlainSub", supers: ["Item"])
        plainSub.instanceTypeName = "java.util.List<String>"
        var title = featureDraft(.attribute, "title", "String")
        title.unique = unique
        title.isID = true
        title.defaultValue = "none"
        var tags = featureDraft(.attribute, "tags", "String")
        tags.upperBound = -1
        tags.unique = unique
        var parent = featureDraft(.reference, "parent", "Item")
        parent.opposite = "children"
        var children = featureDraft(.reference, "children", "Item")
        children.containment = true
        children.opposite = "parent"
        children.keys = ["title"]
        children.upperBound = -1
        var item = classDraft("Item", features: [title, tags, parent, children, featureDraft(.reference, "lost", "Missing")])
        item.annotations = [DraftAnnotation(source: "doc", details: [DraftDetail(key: "text", value: "x")])]
        var category = DraftClassifier(kind: .enumeration, name: "Category")
        category.literals = [DraftLiteral(name: "FOOD", value: 1, literal: "food")]
        category.annotations = [DraftAnnotation(source: "doc")]
        var money = DraftClassifier(kind: .dataType, name: "Money")
        money.typeParameters = [DraftTypeParameter(name: "V")]
        money.annotations = [DraftAnnotation(source: "doc")]
        var package = packageDraft("shop", [item, box, sub, plainSub, classDraft("Failure"), category, money])
        package.subpackages = [packageDraft("stock", [classDraft("Shelf", features: [featureDraft(.reference, "item", "Item")])])]
        if annotation { package.annotations = [DraftAnnotation(source: "extra")] }
        return package
    }

    /// Computes the signature of the draft after assembling it.
    private func signature(
        _ draft: DraftPackage, options: MetamodelSignature.Options = .init()
    ) -> String {
        MetamodelSignature.of(assemble([draft], severity: .warning).packages, options: options)
    }

    /// Structurally equal packages have equal signatures despite different identifiers.
    @Test func equalForStructurallyEqualPackages() {
        let first = assemble([richDraft()], severity: .warning).packages
        let second = assemble([richDraft()], severity: .warning).packages
        #expect(first[0].id != second[0].id)
        #expect(MetamodelSignature.of(first) == MetamodelSignature.of(second))
    }

    /// The signature describes classifiers, members, generics, opposites and keys.
    @Test func describesStructure() {
        let text = signature(richDraft())
        #expect(text.hasPrefix("package shop uri=http://example.org/shop prefix=shop"))
        #expect(text.contains("class Box<T extends shop.Item>"))
        #expect(text.contains("reference value : param:T"))
        #expect(text.contains("supers=[shop.Box<shop.Item>]"))
        #expect(text.contains("attribute title : ecore.EString [0..1]"))
        #expect(text.contains("default=none id=true"))
        #expect(text.contains("opposite=Item.parent keys=[Item.title]"))
        #expect(text.contains("container=true"))
        #expect(text.contains("reference lost : external.Missing"))
        #expect(text.contains("enum Category serialisable=true"))
        #expect(text.contains("literal FOOD=1 \"food\""))
        #expect(text.contains("datatype Money<V>"))
        #expect(text.contains("operation <E>peek(other : shop.Box<? extends shop.Item, ? super shop.Item, ?> [0..1]"))
        #expect(text.contains(" : param:E [0..1]"))
        #expect(text.contains("throws=[shop.Failure, shop.Box<shop.Item>]"))
        #expect(text.contains("operation reset() : void"))
        #expect(text.contains("instance=java.util.List/java.util.List<String>"))
        #expect(text.contains("@doc(text=x)"))
        #expect(text.contains("@op(k=v)"))
        #expect(text.contains("package stock"))
        #expect(text.contains("reference item : shop.Item"))
        #expect(text.contains("\n  "))
    }

    /// A differing flag changes the signature.
    @Test func differsWhenAFlagDiffers() {
        #expect(signature(richDraft()) != signature(richDraft(volatile: true)))
        #expect(signature(richDraft()) != signature(richDraft(annotation: true)))
    }

    /// Single-valued collection flags can be ignored, but many-valued ones still count.
    @Test func ignoresSingleValuedCollectionFlags() {
        let options = MetamodelSignature.Options(ignoresSingleValuedCollectionFlags: true)
        #expect(signature(richDraft()) != signature(richDraft(unique: false)))
        #expect(signature(richDraft(), options: options) != signature(richDraft(unique: false), options: options))
        var single = richDraft()
        single.classifiers[0].features = [featureDraft(.attribute, "title", "String")]
        var singleUnordered = single
        singleUnordered.classifiers[0].features[0].unique = false
        singleUnordered.classifiers[0].features[0].ordered = false
        #expect(signature(single) != signature(singleUnordered))
        #expect(signature(single, options: options) == signature(singleUnordered, options: options))
    }

    /// Ignored annotation sources do not contribute to the signature.
    @Test func ignoresAnnotationSources() {
        let options = MetamodelSignature.Options(ignoredAnnotationSources: ["extra"])
        #expect(signature(richDraft(), options: options) == signature(richDraft(annotation: true), options: options))
        let all = MetamodelSignature.Options(ignoredAnnotationSources: ["extra", "doc", "op"])
        #expect(!signature(richDraft(annotation: true), options: all).contains("@"))
    }

    /// Type parameter annotations and bounds are part of the signature.
    @Test func includesTypeParameterAnnotations() {
        var draft = richDraft()
        draft.classifiers[1].typeParameters[0].annotations = [DraftAnnotation(source: "tp")]
        #expect(signature(draft).contains("@tp()"))
    }
}
