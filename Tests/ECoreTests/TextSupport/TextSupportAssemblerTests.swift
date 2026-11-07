//
// TextSupportAssemblerTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore




/// Tests for turning drafts into Ecore packages.
@Suite("Metamodel assembler")
struct AssemblerTests {
    // MARK: Classifiers

    /// A package with a class, data type and enumeration is assembled with its details.
    @Test func assemblesClassifiers() throws {
        var item = classDraft("Item", features: [featureDraft(.attribute, "title", "String")])
        item.isAbstract = true
        var money = DraftClassifier(kind: .dataType, name: "Money")
        money.instanceTypeName = "java.math.BigDecimal"
        money.serialisable = false
        var category = DraftClassifier(kind: .enumeration, name: "Category")
        category.literals = [
            DraftLiteral(name: "FOOD", value: 0), DraftLiteral(name: "TOYS", value: 1, literal: "toys"),
        ]
        var draft = packageDraft("shop", [item, money, category])
        draft.annotations = [DraftAnnotation(source: "doc", details: [DraftDetail(key: "k", value: "v")])]
        let result = assemble([draft])
        #expect(result.diagnostics.isEmpty)
        let package = try #require(result.packages.first)
        #expect(package.name == "shop")
        #expect(package.nsURI == "http://example.org/shop")
        #expect(package.nsPrefix == "shop")
        #expect(package.eAnnotations.first?.source == "doc")
        #expect(package.eAnnotations.first?.details["k"] == "v")
        #expect(package.eClassifiers.map(\.name) == ["Item", "Money", "Category"])
        let itemClass = try #require(eClass(package, "Item"))
        #expect(itemClass.isAbstract)
        let title = try #require(attribute(itemClass, "title"))
        #expect(title.eType.id == EcorePackage.classifier(named: "EString")?.id)
        let moneyType = try #require(package.eClassifiers[1] as? EDataType)
        #expect(!moneyType.serialisable)
        #expect(moneyType.instanceClassName == "java.math.BigDecimal")
        let categoryEnum = try #require(package.eClassifiers[2] as? EEnum)
        #expect(categoryEnum.literals.map(\.literal) == ["FOOD", "toys"])
        #expect(categoryEnum.literals.map(\.value) == [0, 1])
        #expect(categoryEnum.serialisable)
    }

    /// The assembler can also be driven as a value, exposing its diagnostics afterwards.
    @Test func exposesFoundDiagnostics() {
        var assembler = MetamodelAssembler(factory: shopFactory, external: shopExternal())
        let packages = assembler.assemble([packageDraft("shop", [classDraft("A", features: [featureDraft(.attribute, "x", "Missing")])])])
        #expect(packages.count == 1)
        #expect(assembler.foundDiagnostics.count == 1)
    }

    /// Classifiers resolve through enclosing package scopes and qualified names.
    @Test func resolvesThroughNestedScopesAndQualifiedNames() throws {
        let item = classDraft("Item")
        let shelf = classDraft(
            "Shelf",
            features: [
                featureDraft(.reference, "plain", "Item"), featureDraft(.reference, "qualified", "shop.Item"),
                featureDraft(.reference, "sibling", "stock.Shelf"),
                featureDraft(.reference, "inner", "Bin"),
            ])
        var stock = packageDraft("stock", [shelf, classDraft("Bin")])
        stock.subpackages = []
        var root = packageDraft("shop", [item])
        root.subpackages = [stock]
        let package = try #require(assemble([root]).packages.first)
        let result = assemble([root])
        #expect(result.diagnostics.isEmpty)
        let stockPackage = try #require(package.eSubpackages.first)
        let shelfClass = try #require(eClass(stockPackage, "Shelf"))
        let itemID = try #require(eClass(package, "Item")?.id)
        #expect(reference(shelfClass, "plain")?.eType.id == itemID)
        #expect(reference(shelfClass, "qualified")?.eType.id == itemID)
        #expect(reference(shelfClass, "sibling")?.eType.id == shelfClass.id)
        #expect(reference(shelfClass, "inner")?.eType.name == "Bin")
    }

    /// A package with a qualified name is keyed by that name.
    @Test func qualifiedNameRootKeys() throws {
        var shop = packageDraft("shop", [classDraft("Item")])
        shop.qualifiedName = "org.shop"
        let till = packageDraft("till", [classDraft("Sale", features: [featureDraft(.reference, "item", "org.shop.Item")])])
        let result = assemble([shop, till])
        #expect(result.diagnostics.isEmpty)
        let sale = try #require(eClass(result.packages[1], "Sale"))
        #expect(reference(sale, "item")?.eType.name == "Item")
        let missing = assemble([till])
        #expect(missing.diagnostics.map(\.code) == ["shop.unresolvedType"])
    }

    /// Aliases map names to packages and to external type names.
    @Test func resolvesAliases() throws {
        let root = packageDraft(
            "shop",
            [
                classDraft("Item"),
                classDraft(
                    "Entry",
                    features: [
                        featureDraft(.reference, "viaPackage", "S.Item"), featureDraft(.attribute, "label", "Text"),
                        featureDraft(.attribute, "unknown", "Other"),
                    ]),
            ])
        let result = assemble([root], aliases: ["S": "shop", "Text": "String", "Other": "Gone"])
        let entry = try #require(eClass(result.packages[0], "Entry"))
        #expect(reference(entry, "viaPackage")?.eType.name == "Item")
        #expect(attribute(entry, "label")?.eType.id == EcorePackage.classifier(named: "EString")?.id)
        #expect(attribute(entry, "unknown")?.eType.name == "Gone")
        #expect(result.diagnostics.count == 1)
    }

    // MARK: Unresolved types

    /// Unresolved types become placeholders with an error at the type's range.
    @Test func unresolvedTypesBecomePlaceholders() throws {
        var attributeFeature = featureDraft(.attribute, "a", "Missing")
        attributeFeature.type.range = range(3)
        var referenceFeature = featureDraft(.reference, "r", "Missing")
        referenceFeature.type.range = range(8)
        let root = packageDraft("shop", [classDraft("Item", features: [attributeFeature, referenceFeature])])
        let result = assemble([root])
        let item = try #require(eClass(result.packages[0], "Item"))
        #expect(attribute(item, "a")?.eType is EDataType)
        #expect(attribute(item, "a")?.eType.name == "Missing")
        #expect(reference(item, "r")?.eType is EClass)
        #expect(result.diagnostics.count == 2)
        #expect(result.diagnostics.allSatisfy { $0.severity == .error && $0.code == "shop.unresolvedType" })
        #expect(result.diagnostics.map(\.range) == [range(3), range(8)])
        #expect(result.diagnostics[0].document == "shop.txt")
    }

    /// The severity of unresolved type diagnostics is configurable, and placeholders are shared.
    @Test func unresolvedSeverityAndPlaceholderSharing() throws {
        let item = classDraft(
            "Item", features: [featureDraft(.attribute, "a", "Missing"), featureDraft(.attribute, "b", "Missing")])
        let result = assemble([packageDraft("shop", [item])], severity: .warning)
        #expect(result.diagnostics.count == 2)
        #expect(result.diagnostics.allSatisfy { $0.severity == .warning })
        let built = try #require(eClass(result.packages[0], "Item"))
        #expect(attribute(built, "a")?.eType.id == attribute(built, "b")?.eType.id)
    }

    // MARK: Generics

    /// Features typed by a type parameter get a generic type and the bound as raw type.
    @Test func typeParametersTypeFeatures() throws {
        var box = classDraft(
            "Box",
            features: [featureDraft(.reference, "bounded", "T"), featureDraft(.attribute, "anything", "T")])
        box.typeParameters = [DraftTypeParameter(name: "T", bounds: [DraftType(name: "Item")])]
        var bag = classDraft("Bag", features: [featureDraft(.attribute, "anything", "U")])
        bag.typeParameters = [DraftTypeParameter(name: "U")]
        let result = assemble([packageDraft("shop", [classDraft("Item"), box, bag])])
        #expect(result.diagnostics.isEmpty)
        let boxClass = try #require(eClass(result.packages[0], "Box"))
        let parameter = try #require(boxClass.eTypeParameters.first)
        let bounded = try #require(reference(boxClass, "bounded"))
        #expect(bounded.eGenericType?.eTypeParameter == parameter.id)
        #expect(bounded.eType.name == "Item")
        #expect(parameter.eBounds.first?.eClassifier?.name == "Item")
        let bagClass = try #require(eClass(result.packages[0], "Bag"))
        let anything = try #require(attribute(bagClass, "anything"))
        #expect(anything.eGenericType?.eTypeParameter == bagClass.eTypeParameters.first?.id)
        #expect(anything.eType.name == "EJavaObject")
    }

    /// Generic supertypes and type arguments are kept alongside the raw supertypes.
    @Test func genericSuperTypes() throws {
        var box = classDraft("Box")
        box.typeParameters = [DraftTypeParameter(name: "T")]
        var sub = classDraft("Sub")
        sub.superTypes = [DraftType(name: "Box", arguments: [DraftType(name: "Item")])]
        var plain = classDraft("Plain", supers: ["Item"])
        plain.features = [featureDraft(.reference, "boxes", "Box")]
        var many = classDraft("Many")
        many.features = [
            DraftFeature(kind: .reference, name: "boxes", type: DraftType(name: "Box", arguments: [DraftType(name: "Item")]))
        ]
        let result = assemble([packageDraft("shop", [classDraft("Item"), box, sub, plain, many])])
        #expect(result.diagnostics.isEmpty)
        let subClass = try #require(eClass(result.packages[0], "Sub"))
        #expect(subClass.eSuperTypes.map(\.name) == ["Box"])
        #expect(subClass.eGenericSuperTypes.first?.eTypeArguments.first?.eClassifier?.name == "Item")
        let plainClass = try #require(eClass(result.packages[0], "Plain"))
        #expect(plainClass.eGenericSuperTypes.isEmpty)
        #expect(reference(plainClass, "boxes")?.eGenericType == nil)
        let manyClass = try #require(eClass(result.packages[0], "Many"))
        #expect(reference(manyClass, "boxes")?.eGenericType?.eTypeArguments.count == 1)
    }

    /// Wildcard type arguments keep their bounds.
    @Test func wildcards() throws {
        let item = DraftType(name: "Item")
        let arguments = [
            DraftType(name: "", wildcard: .unbounded), DraftType(name: "", wildcard: .upper, bounds: [item]),
            DraftType(name: "", wildcard: .lower, bounds: [item]),
        ]
        var box = classDraft("Box")
        box.typeParameters = [DraftTypeParameter(name: "A"), DraftTypeParameter(name: "B"), DraftTypeParameter(name: "C")]
        let holder = classDraft(
            "Holder", features: [DraftFeature(kind: .reference, name: "box", type: DraftType(name: "Box", arguments: arguments))])
        let result = assemble([packageDraft("shop", [classDraft("Item"), box, holder])])
        #expect(result.diagnostics.isEmpty)
        let generic = try #require(reference(eClass(result.packages[0], "Holder"), "box")?.eGenericType)
        #expect(generic.eTypeArguments.count == 3)
        #expect(generic.eTypeArguments[0].eClassifier == nil)
        #expect(generic.eTypeArguments[1].eUpperBound?.eClassifier?.name == "Item")
        #expect(generic.eTypeArguments[2].eLowerBound?.eClassifier?.name == "Item")
    }

    /// A supertype that is not a class is reported.
    @Test func nonClassSuperTypeIsReported() {
        var enumeration = DraftClassifier(kind: .enumeration, name: "Category")
        enumeration.literals = [DraftLiteral(name: "A", value: 0)]
        var sub = classDraft("Sub", supers: ["Category"])
        sub.superTypes[0].range = range(5)
        let result = assemble([packageDraft("shop", [enumeration, sub])])
        #expect(result.diagnostics.map(\.code) == ["shop.unresolvedType"])
        #expect(result.diagnostics.first?.message.contains("is not a class") == true)
        #expect(result.diagnostics.first?.range == range(5))
    }

    /// Supertypes may be type parameters or unresolved, and are reported accordingly.
    @Test func unusualSuperTypes() {
        var sub = classDraft("Sub", supers: ["T", "Missing"])
        sub.typeParameters = [DraftTypeParameter(name: "T")]
        let result = assemble([packageDraft("shop", [sub])])
        #expect(result.diagnostics.map(\.code) == ["shop.unresolvedType", "shop.unresolvedType"])
        #expect(result.packages[0].eClassifiers.count == 1)
    }

    // MARK: Duplicates

    /// Duplicate packages, classifiers, features, literals and parameters are reported.
    @Test func duplicateNamesAreReported() throws {
        var first = classDraft("Item", features: [featureDraft(.attribute, "x", "String")])
        first.features.append(featureDraft(.attribute, "x", "Int"))
        first.features[1].location = location(10)
        var second = classDraft("Item")
        second.location = location(20)
        var colours = DraftClassifier(kind: .enumeration, name: "Colour")
        colours.literals = [DraftLiteral(name: "RED", value: 0), DraftLiteral(name: "RED", value: 1, location: location(30))]
        var operation = DraftOperation(name: "add")
        operation.parameters = [
            DraftParameter(name: "n", type: DraftType(name: "Int")),
            DraftParameter(name: "n", type: DraftType(name: "Int"), location: location(40)),
        ]
        first.operations = [operation]
        var again = packageDraft("shop", [classDraft("Other")])
        again.location = location(50)
        let result = assemble([packageDraft("shop", [first, second, colours]), again])
        let messages = result.diagnostics.map(\.message)
        #expect(result.diagnostics.allSatisfy { $0.code == "shop.duplicateName" })
        #expect(messages.contains { $0.contains("Duplicate package name 'shop'") })
        #expect(messages.contains { $0.contains("Duplicate classifier name 'Item'") })
        #expect(messages.contains { $0.contains("Duplicate feature name 'x'") })
        #expect(messages.contains { $0.contains("Duplicate literal name 'RED'") })
        #expect(messages.contains { $0.contains("Duplicate parameter name 'n'") })
        #expect(result.diagnostics.compactMap(\.range).contains(range(10)))
        #expect(result.diagnostics.compactMap(\.range).contains(range(40)))
        let item = try #require(eClass(result.packages[0], "Item"))
        #expect(item.eStructuralFeatures.count == 1)
        #expect(attribute(item, "x")?.eType.name == "EString")
        let colour = try #require(result.packages[0].eClassifiers.last as? EEnum)
        #expect(colour.literals.count == 1)
    }

    // MARK: Opposites and keys

    /// Opposites link both ways, including inherited features and containment.
    @Test func resolvesOpposites() throws {
        var shelf = classDraft("Shelf")
        var items = featureDraft(.reference, "items", "Item")
        items.containment = true
        items.opposite = "shelf"
        items.upperBound = -1
        shelf.features = [items]
        let base = classDraft("Base", features: [featureDraft(.reference, "shelf", "Shelf")])
        var inheritedBase = base
        inheritedBase.features[0].opposite = "items"
        let item = classDraft("Item", supers: ["Base"])
        let result = assemble([packageDraft("shop", [shelf, inheritedBase, item])])
        #expect(result.diagnostics.isEmpty)
        let shelfClass = try #require(eClass(result.packages[0], "Shelf"))
        let baseClass = try #require(eClass(result.packages[0], "Base"))
        let itemsReference = try #require(reference(shelfClass, "items"))
        let shelfReference = try #require(reference(baseClass, "shelf"))
        #expect(itemsReference.opposite == shelfReference.id)
        #expect(shelfReference.opposite == itemsReference.id)
        #expect(shelfReference.container)
        #expect(!itemsReference.container)
    }

    /// Opposites that cannot be found are reported at the opposite's range.
    @Test func unresolvedOppositeIsReported() throws {
        var missing = featureDraft(.reference, "owner", "Owner")
        missing.opposite = "nothing"
        missing.oppositeRange = range(7)
        var onData = featureDraft(.reference, "tag", "Item")
        onData.opposite = "title"
        onData.location = location(9)
        var typed = featureDraft(.attribute, "title", "String")
        typed.name = "title"
        let item = classDraft("Item", features: [typed])
        let owner = classDraft("Owner", features: [featureDraft(.attribute, "title", "String")])
        let holder = classDraft("Holder", features: [missing, onData])
        let result = assemble([packageDraft("shop", [item, owner, holder])])
        #expect(result.diagnostics.map(\.code) == ["shop.unresolvedOpposite", "shop.unresolvedOpposite"])
        #expect(result.diagnostics[0].range == range(7))
        #expect(result.diagnostics[1].range == range(9))
        #expect(result.diagnostics[0].message.contains("'nothing'"))
    }

    /// An opposite on a reference to a data type is unresolved.
    @Test func oppositeToDataTypeIsUnresolved() {
        var feature = featureDraft(.reference, "x", "String")
        feature.opposite = "y"
        let result = assemble([packageDraft("shop", [classDraft("A", features: [feature])])])
        #expect(result.diagnostics.map(\.code) == ["shop.unresolvedOpposite"])
    }

    /// Keys resolve to attributes of the target, and bad keys are reported with their own range.
    @Test func resolvesKeys() throws {
        let book = classDraft(
            "Book", features: [featureDraft(.attribute, "isbn", "String"), featureDraft(.reference, "author", "Book")])
        var books = featureDraft(.reference, "books", "Book")
        books.keys = ["isbn", "author", "missing"]
        books.keyRanges = [range(1), range(2)]
        books.location = location(60)
        let library = classDraft("Library", features: [books])
        let result = assemble([packageDraft("shop", [book, library])])
        #expect(result.diagnostics.map(\.code) == ["shop.unresolvedKey", "shop.unresolvedKey"])
        #expect(result.diagnostics.map(\.range) == [range(2), range(60)])
        let bookClass = try #require(eClass(result.packages[0], "Book"))
        let libraryClass = try #require(eClass(result.packages[0], "Library"))
        #expect(reference(libraryClass, "books")?.eKeys == [attribute(bookClass, "isbn")?.id].compactMap { $0 })
    }

    // MARK: Inferred features

    /// Inferred features become attributes for data types and references for classes, including unresolved types.
    @Test func infersFeatureKinds() throws {
        var kind = DraftClassifier(kind: .enumeration, name: "Kind")
        kind.literals = [DraftLiteral(name: "A", value: 0)]
        var holder = classDraft(
            "Holder",
            features: [
                featureDraft(.inferred, "name", "String"), featureDraft(.inferred, "kind", "Kind"),
                featureDraft(.inferred, "peer", "Holder"), featureDraft(.inferred, "value", "T"),
                featureDraft(.inferred, "mystery", "Missing"),
            ])
        holder.typeParameters = [DraftTypeParameter(name: "T", bounds: [DraftType(name: "Holder")])]
        holder.features[4].type.range = range(4)
        let result = assemble([packageDraft("shop", [kind, holder])])
        let built = try #require(eClass(result.packages[0], "Holder"))
        #expect(attribute(built, "name") != nil)
        #expect(attribute(built, "kind") != nil)
        #expect(reference(built, "peer") != nil)
        #expect(attribute(built, "value") != nil)
        #expect(reference(built, "mystery")?.eType is EClass)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.range == range(4))
    }

    /// Feature flags and annotations are carried onto attributes and references.
    @Test func copiesFeatureFlags() throws {
        var title = featureDraft(.attribute, "title", "String")
        title.lowerBound = 1
        title.upperBound = -1
        title.changeable = false
        title.volatile = true
        title.transient = true
        title.unsettable = true
        title.derived = true
        title.unique = false
        title.ordered = false
        title.isID = true
        title.defaultValue = "none"
        title.annotations = [DraftAnnotation(source: "note", details: [DraftDetail(key: "a", value: "b")])]
        var link = featureDraft(.reference, "link", "Item")
        link.containment = true
        link.resolveProxies = false
        link.defaultValue = "x"
        let result = assemble([packageDraft("shop", [classDraft("Item", features: [title, link])])])
        let item = try #require(eClass(result.packages[0], "Item"))
        let titleAttribute = try #require(attribute(item, "title"))
        #expect(titleAttribute.lowerBound == 1 && titleAttribute.upperBound == -1)
        #expect(!titleAttribute.changeable && titleAttribute.volatile && titleAttribute.transient)
        #expect(titleAttribute.unsettable && titleAttribute.derived && !titleAttribute.unique && !titleAttribute.ordered)
        #expect(titleAttribute.isID)
        #expect(titleAttribute.defaultValueLiteral == "none")
        #expect(titleAttribute.eAnnotations.first?.details["a"] == "b")
        let linkReference = try #require(reference(item, "link"))
        #expect(linkReference.containment && !linkReference.resolveProxies)
        #expect(linkReference.defaultValueLiteral == "x")
    }

    // MARK: Operations

    /// Operations keep their type parameters, parameters, return type and exceptions.
    @Test func assemblesOperations() throws {
        var operation = DraftOperation(name: "find")
        operation.typeParameters = [DraftTypeParameter(name: "E", bounds: [DraftType(name: "Item")])]
        operation.returnType = DraftType(name: "E")
        operation.upperBound = -1
        operation.ordered = false
        operation.unique = false
        var parameter = DraftParameter(name: "key", type: DraftType(name: "String"))
        parameter.lowerBound = 1
        parameter.annotations = [DraftAnnotation(source: "p")]
        var generic = DraftParameter(
            name: "boxes", type: DraftType(name: "Box", arguments: [DraftType(name: "Item")]))
        generic.upperBound = -1
        operation.parameters = [parameter, generic]
        operation.exceptions = [DraftType(name: "Failure"), DraftType(name: "Box", arguments: [DraftType(name: "Item")])]
        operation.annotations = [DraftAnnotation(source: "op")]
        var box = classDraft("Box")
        box.typeParameters = [DraftTypeParameter(name: "T")]
        var plain = DraftOperation(name: "reset")
        plain.parameters = []
        let holder = DraftClassifier(kind: .class, name: "Holder")
        var withOperations = holder
        withOperations.operations = [operation, plain]
        let result = assemble([packageDraft("shop", [classDraft("Item"), classDraft("Failure"), box, withOperations])])
        #expect(result.diagnostics.isEmpty)
        let built = try #require(eClass(result.packages[0], "Holder"))
        let find = try #require(built.eOperations.first)
        #expect(find.eTypeParameters.count == 1)
        #expect(find.eGenericType?.eTypeParameter == find.eTypeParameters.first?.id)
        #expect(find.eType?.name == "Item")
        #expect(find.upperBound == -1 && !find.ordered && !find.unique)
        #expect(find.eParameters.map(\.name) == ["key", "boxes"])
        #expect(find.eParameters[0].lowerBound == 1)
        #expect(find.eParameters[0].eAnnotations.first?.source == "p")
        #expect(find.eParameters[1].eGenericType?.eTypeArguments.count == 1)
        #expect(find.eExceptions.map(\.name) == ["Failure", "Box"])
        #expect(find.eGenericExceptions.count == 2)
        #expect(find.eAnnotations.first?.source == "op")
        let reset = try #require(built.eOperations.last)
        #expect(reset.eType == nil)
        #expect(reset.eGenericExceptions.isEmpty)
    }

    /// Type parameters keep their bounds and annotations on classes and data types.
    @Test func typeParameterDetails() throws {
        var list = classDraft("Shelf")
        list.typeParameters = [
            DraftTypeParameter(
                name: "E", bounds: [DraftType(name: "Item"), DraftType(name: "Tagged")],
                annotations: [DraftAnnotation(source: "tp")])
        ]
        var data = DraftClassifier(kind: .dataType, name: "Holder")
        data.typeParameters = [DraftTypeParameter(name: "V")]
        data.instanceTypeName = "java.util.List<V>"
        var enumeration = DraftClassifier(kind: .enumeration, name: "Kind")
        enumeration.typeParameters = [DraftTypeParameter(name: "W")]
        let result = assemble([packageDraft("shop", [classDraft("Item"), classDraft("Tagged"), list, data, enumeration])])
        let shelf = try #require(eClass(result.packages[0], "Shelf"))
        let parameter = try #require(shelf.eTypeParameters.first)
        #expect(parameter.eBounds.count == 2)
        #expect(parameter.eAnnotations.first?.source == "tp")
        let dataType = try #require(result.packages[0].eClassifiers[3] as? EDataType)
        #expect(dataType.eTypeParameters.map(\.name) == ["V"])
        #expect(dataType.instanceClassName == "java.util.List")
        #expect(dataType.instanceTypeName == "java.util.List<V>")
    }

    /// Classes keep their interface flag, instance type names and annotations.
    @Test func classMetadata() throws {
        var item = classDraft("Item")
        item.isInterface = true
        item.instanceTypeName = "org.example.Item"
        item.annotations = [DraftAnnotation(source: "meta", details: [DraftDetail(key: "k", value: "1"), DraftDetail(key: "k", value: "2")])]
        let result = assemble([packageDraft("shop", [item])])
        let built = try #require(eClass(result.packages[0], "Item"))
        #expect(built.isInterface)
        #expect(built.instanceClassName == "org.example.Item")
        #expect(built.instanceTypeName == nil)
        #expect(built.eAnnotations.first?.details["k"] == "2")
    }

    // MARK: Instance names

    /// Instance type names split into an erased class name and a full type name.
    @Test func splitsInstanceNames() {
        let generic = MetamodelAssembler.instanceNames("java.util.List<String>")
        #expect(generic.className == "java.util.List")
        #expect(generic.typeName == "java.util.List<String>")
        let plain = MetamodelAssembler.instanceNames("java.lang.String")
        #expect(plain.className == "java.lang.String")
        #expect(plain.typeName == nil)
        let array = MetamodelAssembler.instanceNames("java.util.List<String>[]")
        #expect(array.className == "java.util.List[]")
        #expect(array.typeName == "java.util.List<String>[]")
        let spaced = MetamodelAssembler.instanceNames("Map <K, V> ")
        #expect(spaced.className == "Map")
        let empty = MetamodelAssembler.instanceNames("")
        #expect(empty.className == nil && empty.typeName == nil)
        let absent = MetamodelAssembler.instanceNames(nil)
        #expect(absent.className == nil && absent.typeName == nil)
    }

    /// Draft type text renders arguments and wildcards.
    @Test func draftTypeText() {
        let item = DraftType(name: "Item")
        #expect(item.text == "Item")
        #expect(DraftType(name: "Map", arguments: [item, DraftType(name: "List", arguments: [item])]).text == "Map<Item, List<Item>>")
        #expect(DraftType(name: "", wildcard: .unbounded).text == "?")
        #expect(DraftType(name: "", wildcard: .upper, bounds: [item]).text == "? extends Item")
        #expect(DraftType(name: "", wildcard: .lower, bounds: [item]).text == "? super Item")
        #expect(DraftType(name: "", wildcard: .upper).text == "? extends ")
    }
}
