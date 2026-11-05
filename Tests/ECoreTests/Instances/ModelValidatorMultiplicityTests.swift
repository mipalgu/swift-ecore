//
// ModelValidatorMultiplicityTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// A small shelf metamodel built in code, whose features cover every kind of multiplicity.
///
/// A shelf holds at least one book and exactly one sign, refers to one favourite book and
/// to one or two picks, and carries one or two tags. A book requires a title, a kind and a
/// page count. A catalogue card has one required single-valued feature for each way that
/// an unset feature can read: without a default, with an intrinsic or literal default, and
/// as an unsettable feature.
struct ShelfModel {
    /// The namespace URI of the shelf package.
    static let nsURI = "http://example.org/shelf"

    /// The shelf package.
    let package: EPackage
    /// The class of shelves.
    let shelf: EClass
    /// The class of signs that shelves contain.
    let sign: EClass
    /// The class of books that shelves contain.
    let book: EClass
    /// The class of catalogue cards.
    let card: EClass
    /// The enumeration of kinds of book.
    let kind: EEnum

    /// Creates the shelf metamodel.
    init() {
        let string = EDataType(name: "EString", instanceClassName: "java.lang.String")
        let int = EDataType(name: "EInt", instanceClassName: "int")
        let integer = EDataType(name: "EIntegerObject", instanceClassName: "java.lang.Integer")
        let kind = EEnum(
            name: "Kind",
            literals: [EEnumLiteral(name: "fiction", value: 0), EEnumLiteral(name: "reference", value: 1)])
        let sign = EClass(name: "Sign")
        let book = EClass(
            name: "Book",
            eStructuralFeatures: [
                EAttribute(name: "title", eType: string, lowerBound: 1),
                EAttribute(name: "kind", eType: kind, lowerBound: 1),
                EAttribute(name: "pages", eType: int, lowerBound: 1),
            ])
        let shelf = EClass(
            name: "Shelf",
            eStructuralFeatures: [
                EReference(name: "books", eType: book, lowerBound: 1, upperBound: -1, containment: true),
                EReference(name: "sign", eType: sign, lowerBound: 1, containment: true),
                EReference(name: "favourite", eType: book, lowerBound: 1),
                EReference(name: "picks", eType: book, lowerBound: 1, upperBound: 2),
                EAttribute(name: "tags", eType: string, lowerBound: 1, upperBound: 2),
                EAttribute(name: "notes", eType: string, upperBound: -1),
            ])
        let card = EClass(
            name: "Card",
            eStructuralFeatures: [
                EAttribute(name: "label", eType: string, lowerBound: 1),
                EAttribute(name: "copies", eType: integer, lowerBound: 1),
                EAttribute(name: "genre", eType: kind, lowerBound: 1),
                EAttribute(name: "count", eType: int, lowerBound: 1),
                EAttribute(name: "shelfmark", eType: string, lowerBound: 1, defaultValueLiteral: "unshelved"),
                EAttribute(name: "format", eType: kind, lowerBound: 1, unsettable: true),
                EAttribute(name: "loans", eType: int, lowerBound: 1, unsettable: true),
                EAttribute(
                    name: "status", eType: string, lowerBound: 1, defaultValueLiteral: "open", unsettable: true),
                EReference(name: "book", eType: book, lowerBound: 1),
                EReference(name: "cover", eType: sign, lowerBound: 1, containment: true),
                EReference(name: "location", eType: shelf, lowerBound: 1, unsettable: true),
            ])
        self.package = EPackage(
            name: "shelf", nsURI: Self.nsURI, nsPrefix: "shelf",
            eClassifiers: [shelf, sign, book, card, kind])
        self.shelf = shelf
        self.sign = sign
        self.book = book
        self.card = card
        self.kind = kind
    }

    /// Validates a resource against the shelf metamodel.
    ///
    /// - Parameter resource: The resource to validate.
    /// - Returns: The diagnostics of the validation.
    func validate(_ resource: Resource) async -> [ModelDiagnostic] {
        ModelValidator(metamodels: [package]).validate(await resource.snapshot())
    }

    /// Reads an XMI document whose root and contents conform to the shelf metamodel.
    ///
    /// - Parameter body: The XMI elements and attributes that follow the root element name,
    ///   without the namespace declarations.
    /// - Returns: The resource that holds the document.
    func read(_ body: String) async throws -> Resource {
        let set = ResourceSet()
        await set.registerMetamodel(package, uri: package.nsURI)
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <shelf:Shelf xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
            xmlns:shelf="\(Self.nsURI)" \(body)
            """
        return try await XMIParser(resourceSet: set).parse(text, uri: "memory:/shelf.xmi")
    }

    /// A resource holding the given objects as roots.
    ///
    /// - Parameter objects: The objects to add.
    /// - Returns: The resource.
    func resource(with objects: [DynamicEObject]) async -> Resource {
        let set = ResourceSet()
        await set.registerMetamodel(package, uri: package.nsURI)
        let resource = await set.createResource(uri: "memory:/shelf.xmi")
        await resource.add(contentsOf: objects)
        return resource
    }

    /// A complete book.
    ///
    /// - Parameter title: The title of the book.
    /// - Returns: A book with a title, a kind and a page count.
    func book(_ title: String) -> DynamicEObject {
        var book = DynamicEObject(eClass: book)
        book.eSet("title", value: title)
        book.eSet("kind", value: "fiction")
        book.eSet("pages", value: 100 as EInt)
        return book
    }
}

/// How a test stores the values of a many-valued feature.
enum ValueForm: String, CaseIterable, Sendable, CustomTestStringConvertible {
    /// A single value, not wrapped in a list.
    case single
    /// A typed Swift array.
    case array
    /// A heterogeneous Ecore value list.
    case valueArray

    /// The description of the form in test output.
    var testDescription: String { rawValue }

    /// Stores values in this form.
    ///
    /// - Parameter values: The values to store; a single value is stored on its own only
    ///   in the ``single`` form and when there is exactly one.
    /// - Returns: The stored value.
    func store<T: EcoreValue>(_ values: [T]) -> any EcoreValue {
        switch self {
        case .single where values.count == 1: return values[0]
        case .single, .array: return values
        case .valueArray: return EcoreValueArray(values.map { $0 as any EcoreValue })
        }
    }
}

@Suite("Model validator multiplicities")
struct ModelValidatorMultiplicityTests {
    let model = ShelfModel()

    /// A shelf with one book, one sign, one favourite, one pick and one tag, in a value form.
    private func shelf(_ form: ValueForm) async -> (Resource, DynamicEObject, DynamicEObject) {
        let book = model.book("Emma")
        let sign = DynamicEObject(eClass: model.sign)
        var shelf = DynamicEObject(eClass: model.shelf)
        shelf.eSet("books", value: form.store([book.id]))
        shelf.eSet("sign", value: sign.id)
        shelf.eSet("favourite", value: book.id)
        shelf.eSet("picks", value: form.store([book.id]))
        shelf.eSet("tags", value: form.store(["classics"]))
        return (await model.resource(with: [shelf, book, sign]), shelf, book)
    }

    @Test("an XMI shelf with one child in a required many-valued containment is valid")
    func singleChildInXMI() async throws {
        let resource = try await model.read(
            """
                favourite="//@books.0" picks="//@books.0" tags="classics">
              <books title="Emma" kind="fiction" pages="474"/>
              <sign/>
            </shelf:Shelf>
            """)
        #expect(await model.validate(resource) == [])
    }

    @Test("an XMI shelf with one tag element and one book is valid")
    func singleElementsInXMI() async throws {
        let resource = try await model.read(
            """
                favourite="//@books.0" picks="//@books.0">
              <tags>classics</tags>
              <books title="Emma" kind="fiction" pages="0"/>
              <sign/>
            </shelf:Shelf>
            """)
        #expect(await model.validate(resource) == [])
    }

    @Test("each value of a many-valued feature counts once, however it is stored", arguments: ValueForm.allCases)
    func everyFormCounts(_ form: ValueForm) async throws {
        let (resource, _, _) = await shelf(form)
        #expect(await model.validate(resource) == [])
    }

    @Test("a single value of a many-valued feature counts as one value against a higher lower bound")
    func singleValueCountsOnce() async throws {
        var stricter = model.shelf
        let tags = try #require(stricter.eStructuralFeatures.firstIndex { $0.name == "tags" })
        stricter.eStructuralFeatures[tags] = EAttribute(
            id: stricter.eStructuralFeatures[tags].id, name: "tags", eType: EDataType(name: "EString"),
            lowerBound: 2, upperBound: 3)
        let package = EPackage(
            name: "shelf", nsURI: ShelfModel.nsURI,
            eClassifiers: [stricter, model.sign, model.book, model.card, model.kind])
        let (resource, shelf, _) = await shelf(.single)
        let found = ModelValidator(metamodels: [package]).validate(await resource.snapshot())
        #expect(found.map(\.code) == [.lowerBound])
        #expect(found.first?.objectID == shelf.id)
        #expect(found.first?.message == "Feature 'tags' needs at least 2 value(s) but has 1")
    }

    @Test("a single reference of a many-valued feature is checked for its target", arguments: ValueForm.allCases)
    func singleReferenceTargets(_ form: ValueForm) async throws {
        let book = model.book("Emma")
        let sign = DynamicEObject(eClass: model.sign)
        let missing = EUUID()
        var shelf = DynamicEObject(eClass: model.shelf)
        shelf.eSet("books", value: form.store([sign.id]))
        shelf.eSet("sign", value: sign.id)
        shelf.eSet("favourite", value: book.id)
        shelf.eSet("picks", value: form.store([missing]))
        shelf.eSet("tags", value: form.store(["classics"]))
        let found = await model.validate(await model.resource(with: [shelf, book, sign]))
        #expect(found.map(\.code) == [.referenceTypeMismatch, .danglingReference])
        #expect(found.first?.message == "Feature 'books' refers to an instance of Sign, which is not a Book")
    }

    @Test("an empty shelf reports every required feature in feature order")
    func emptyShelf() async throws {
        let shelf = DynamicEObject(eClass: model.shelf)
        let found = await model.validate(await model.resource(with: [shelf]))
        #expect(found.map(\.code) == Array(repeating: .lowerBound, count: 5))
        #expect(found.compactMap(\.feature) == ["books", "sign", "favourite", "picks", "tags"])
        #expect(found.map(\.message).allSatisfy { $0.hasSuffix("needs at least 1 value(s) but has 0") })
    }

    @Test("empty lists count as no values", arguments: [ValueForm.array, .valueArray])
    func emptyLists(_ form: ValueForm) async throws {
        let (resource, shelf, _) = await shelf(form)
        try await resource.eSetWithChanges(objectId: shelf.id, feature: "picks", value: form.store([EUUID]()))
        try await resource.eSetWithChanges(objectId: shelf.id, feature: "tags", value: form.store([String]()))
        let found = await model.validate(resource)
        #expect(found.map(\.code) == [.lowerBound, .lowerBound])
        #expect(found.compactMap(\.feature) == ["picks", "tags"])
    }

    @Test("many-valued features with more values than their upper bound are reported", arguments: ValueForm.allCases)
    func upperBounds(_ form: ValueForm) async throws {
        let books = ["Emma", "Persuasion", "Atlas"].map { model.book($0) }
        let sign = DynamicEObject(eClass: model.sign)
        var shelf = DynamicEObject(eClass: model.shelf)
        shelf.eSet("books", value: form.store(books.map(\.id)))
        shelf.eSet("sign", value: sign.id)
        shelf.eSet("favourite", value: books[0].id)
        shelf.eSet("picks", value: form.store(books.map(\.id)))
        shelf.eSet("tags", value: form.store(["classics", "novels", "loans"]))
        shelf.eSet("notes", value: form.store(["a", "b", "c", "d"]))
        let found = await model.validate(await model.resource(with: [shelf, sign] + books))
        #expect(found.map(\.code) == [.upperBound, .upperBound])
        #expect(
            found.map(\.message) == [
                "Feature 'picks' allows at most 2 value(s) but has 3",
                "Feature 'tags' allows at most 2 value(s) but has 3",
            ])
    }

    @Test(
        "an unset required single-valued feature is reported unless it reads as a default",
        arguments: [
            ("label", true), ("copies", true), ("genre", false), ("count", false), ("shelfmark", false),
            ("format", true), ("loans", true), ("status", true), ("book", true), ("cover", true),
            ("location", true),
        ])
    func unsetSingleValues(_ feature: String, _ reported: Bool) async throws {
        let card = DynamicEObject(eClass: model.card)
        let found = await model.validate(await model.resource(with: [card]))
        let diagnostic = found.first { $0.feature == feature }
        #expect((diagnostic != nil) == reported)
        #expect(found.allSatisfy { $0.code == .lowerBound })
        if reported {
            #expect(diagnostic?.message == "Feature '\(feature)' needs at least 1 value(s) but has 0")
        }
    }

    @Test("a required feature set to the default of its type is satisfied")
    func explicitDefaults() async throws {
        let book = model.book("Emma")
        let sign = DynamicEObject(eClass: model.sign)
        let shelf = DynamicEObject(eClass: model.shelf)
        var card = DynamicEObject(eClass: model.card)
        card.eSet("label", value: "")
        card.eSet("copies", value: 0 as EInt)
        card.eSet("genre", value: "fiction")
        card.eSet("count", value: 0 as EInt)
        card.eSet("shelfmark", value: "unshelved")
        card.eSet("format", value: "fiction")
        card.eSet("loans", value: 0 as EInt)
        card.eSet("status", value: "open")
        card.eSet("book", value: book.id)
        card.eSet("cover", value: sign.id)
        card.eSet("location", value: shelf.id)
        let found = await model.validate(await model.resource(with: [card, book, sign, shelf]))
        #expect(found.filter { $0.objectID == card.id } == [])
    }

    @Test("an unset required unsettable feature is reported after it has been unset again")
    func unsetAgain() async throws {
        let shelf = DynamicEObject(eClass: model.shelf)
        var card = DynamicEObject(eClass: model.card)
        card.eSet("format", value: "reference")
        card.eSet("loans", value: 3 as EInt)
        card.eSet("location", value: shelf.id)
        let resource = await model.resource(with: [card, shelf])
        #expect(await model.validate(resource).filter { ["format", "loans", "location"].contains($0.feature) } == [])
        for feature in ["format", "loans", "location"] {
            try await resource.eSetWithChanges(objectId: card.id, feature: feature, value: nil)
        }
        let found = await model.validate(resource).filter { $0.objectID == card.id }
        #expect(found.compactMap(\.feature).filter { ["format", "loans", "location"].contains($0) } == [
            "format", "loans", "location",
        ])
    }

    // MARK: - Explicit values

    /// A validator of the shelf metamodel that requires explicit values.
    private var strict: ModelValidator {
        ModelValidator(metamodels: [model.package], options: .init(requiresExplicitValues: true))
    }

    @Test("by default, unset features that read as a default are satisfied, as in Eclipse")
    func defaultOptions() {
        let validator = ModelValidator(metamodels: [model.package])
        #expect(validator.options == ModelValidator.Options())
        #expect(validator.options.requiresExplicitValues == false)
    }

    @Test(
        "requiring explicit values reports every unset required single-valued feature",
        arguments: [
            "label", "copies", "genre", "count", "shelfmark", "format", "loans", "status", "book", "cover",
            "location",
        ])
    func explicitValuesRequired(_ feature: String) async throws {
        let card = DynamicEObject(eClass: model.card)
        let found = strict.validate(await model.resource(with: [card]).snapshot())
        #expect(found.count == 11)
        #expect(found.allSatisfy { $0.code == .lowerBound })
        let diagnostic = found.first { $0.feature == feature }
        #expect(diagnostic?.message == "Feature '\(feature)' needs at least 1 value(s) but has 0")
    }

    @Test("requiring explicit values accepts features set to the default of their type")
    func explicitDefaultsWhenRequired() async throws {
        let book = model.book("Emma")
        let sign = DynamicEObject(eClass: model.sign)
        let shelf = DynamicEObject(eClass: model.shelf)
        var card = DynamicEObject(eClass: model.card)
        for (name, value) in [
            ("label", ""), ("genre", "fiction"), ("shelfmark", "unshelved"), ("format", "fiction"), ("status", "open"),
        ] {
            card.eSet(name, value: value)
        }
        for name in ["copies", "count", "loans"] { card.eSet(name, value: 0 as EInt) }
        card.eSet("book", value: book.id)
        card.eSet("cover", value: sign.id)
        card.eSet("location", value: shelf.id)
        let found = strict.validate(await model.resource(with: [card, book, sign, shelf]).snapshot())
        #expect(found.filter { $0.objectID == card.id } == [])
    }

    @Test("requiring explicit values does not change how many-valued features count", arguments: ValueForm.allCases)
    func explicitValuesKeepLists(_ form: ValueForm) async throws {
        let (resource, shelf, book) = await shelf(form)
        #expect(strict.validate(await resource.snapshot()) == [])
        try await resource.eSetWithChanges(objectId: book.id, feature: "kind", value: nil)
        try await resource.eSetWithChanges(objectId: shelf.id, feature: "tags", value: nil)
        #expect(await model.validate(resource).compactMap(\.feature) == ["tags"])
        #expect(strict.validate(await resource.snapshot()).compactMap(\.feature) == ["tags", "kind"])
    }

    // MARK: - Defaults of types

    /// The lower bound diagnostics of an object whose one required attribute is unset.
    ///
    /// - Parameters:
    ///   - type: The type of the attribute.
    ///   - literal: The default value literal of the attribute, if any.
    ///   - unsettable: Whether the attribute is unsettable.
    /// - Returns: The lower bound diagnostics of the default validation.
    private func unsetRequired(
        _ type: any EClassifier, literal: String? = nil, unsettable: Bool = false
    ) async -> [ModelDiagnostic] {
        let attribute = EAttribute(
            name: "value", eType: type, lowerBound: 1, defaultValueLiteral: literal, unsettable: unsettable)
        let entry = EClass(name: "Entry", eStructuralFeatures: [attribute])
        let package = EPackage(
            name: "entries", nsURI: "http://example.org/entries", nsPrefix: "entries", eClassifiers: [entry, type])
        let resource = await ResourceSet().createResource(uri: "memory:/entries.xmi")
        _ = await resource.add(DynamicEObject(eClass: entry))
        return ModelValidator(metamodels: [package]).validate(await resource.snapshot()).filter {
            $0.code == .lowerBound
        }
    }

    @Test(
        "an unset required data type attribute reads as a value as in Eclipse",
        arguments: [
            ("EChar", nil, nil, false), ("ECharacterObject", nil, nil, true), ("EBoolean", nil, nil, false),
            ("ELong", nil, nil, false), ("EBigInteger", nil, nil, true), ("EDate", nil, nil, true),
            ("Count", "int", nil, false), ("Count", "long", nil, false), ("Count", "short", nil, false),
            ("Count", "byte", nil, false), ("Count", "float", nil, false), ("Count", "double", nil, false),
            ("Count", "boolean", nil, false), ("Count", "char", nil, false),
            ("Count", "java.lang.Integer", nil, true), ("Count", nil, nil, true),
            ("Count", "java.lang.Integer", "7", false), ("EInt", nil, "7", false), ("EInt", nil, "many", true),
            ("EString", nil, "", false), ("EDate", nil, "2026-11-05", false), ("EDate", nil, "soon", true),
        ] as [(String, String?, String?, Bool)])
    func dataTypeDefaults(_ name: String, _ instanceClassName: String?, _ literal: String?, _ reported: Bool) async {
        let type = EDataType(name: name, instanceClassName: instanceClassName)
        let found = await unsetRequired(type, literal: literal)
        #expect(found.count == (reported ? 1 : 0))
        #expect(await unsetRequired(type, literal: literal, unsettable: true).count == 1)
    }

    @Test(
        "an unset required enumeration attribute reads as its default literal as in Eclipse",
        arguments: [
            (true, nil, false), (true, "reference", false), (true, "unknown", true), (false, nil, true),
        ] as [(Bool, String?, Bool)])
    func enumerationDefaults(_ hasLiterals: Bool, _ literal: String?, _ reported: Bool) async {
        let kind = EEnum(name: "Kind", literals: hasLiterals ? model.kind.literals : [])
        #expect(await unsetRequired(kind, literal: literal).count == (reported ? 1 : 0))
    }

    // MARK: - Conformance of unset values

    /// The diagnostics of an object of a class with one attribute.
    ///
    /// - Parameters:
    ///   - attribute: The only attribute of the class.
    ///   - value: The value to set, or `nil` to leave the attribute unset.
    ///   - options: The settings of the validation.
    /// - Returns: The diagnostics of the validation.
    private func diagnostics(
        _ attribute: EAttribute, value: (any EcoreValue)? = nil, options: ModelValidator.Options = .init()
    ) async -> [ModelDiagnostic] {
        let entry = EClass(name: "Entry", eStructuralFeatures: [attribute])
        let package = EPackage(
            name: "entries", nsURI: "http://example.org/entries", nsPrefix: "entries",
            eClassifiers: [entry, attribute.eType])
        var object = DynamicEObject(eClass: entry)
        if let value { object.eSet(attribute, value) }
        let resource = await ResourceSet().createResource(uri: "memory:/entries.xmi")
        _ = await resource.add(object)
        return ModelValidator(metamodels: [package], options: options).validate(await resource.snapshot())
    }

    @Test(
        "an unset attribute whose default does not conform to its type is not checked",
        arguments: [0, 1])
    func unsetDefaultsAreNotChecked(_ lowerBound: Int) async {
        let count = EAttribute(
            name: "count", eType: EDataType(name: "EInt"), lowerBound: lowerBound, defaultValueLiteral: "many")
        let shade = EAttribute(
            name: "shade", eType: EEnum(name: "Kind", literals: model.kind.literals), lowerBound: lowerBound,
            defaultValueLiteral: "unknown")
        let expected: [ModelDiagnosticCode] = lowerBound > 0 ? [.lowerBound] : []
        #expect(await diagnostics(count).map(\.code) == expected)
        #expect(await diagnostics(shade).map(\.code) == expected)
    }

    @Test("requiring explicit values reports an unset attribute only as missing, not as its default's type")
    func explicitValuesDoNotCheckDefaults() async {
        let strict = ModelValidator.Options(requiresExplicitValues: true)
        let count = EAttribute(name: "count", eType: EDataType(name: "EInt"), lowerBound: 1, defaultValueLiteral: "many")
        let shade = EAttribute(
            name: "shade", eType: EEnum(name: "Kind", literals: model.kind.literals), lowerBound: 1,
            defaultValueLiteral: "unknown")
        #expect(await diagnostics(count, options: strict).map(\.code) == [.lowerBound])
        #expect(await diagnostics(shade, options: strict).map(\.code) == [.lowerBound])
    }

    @Test("a set attribute is checked against its type whatever its default", arguments: [false, true])
    func setValuesAreChecked(_ requiresExplicitValues: Bool) async {
        let options = ModelValidator.Options(requiresExplicitValues: requiresExplicitValues)
        let count = EAttribute(name: "count", eType: EDataType(name: "EInt"), lowerBound: 1, defaultValueLiteral: "many")
        let shade = EAttribute(
            name: "shade", eType: EEnum(name: "Kind", literals: model.kind.literals), lowerBound: 1,
            defaultValueLiteral: "unknown")
        #expect(await diagnostics(count, value: "many", options: options).map(\.code) == [.invalidValue])
        #expect(await diagnostics(count, value: 3 as EInt, options: options) == [])
        #expect(await diagnostics(shade, value: "unknown", options: options).map(\.code) == [.invalidEnumLiteral])
        #expect(await diagnostics(shade, value: "fiction", options: options) == [])
    }
}
