//
// GenElementTests.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import GenModel

@Suite("GenElement facade")
struct GenElementTests {
    private func names(_ elements: [GenElement]) -> [String] { elements.map(\.name) }

    // MARK: - Navigation

    @Test("model, package and class navigation")
    func navigation() async throws {
        let model = try await ShapesModel()
        #expect(model.context.genModels == [model.genModel])
        #expect(model.genModel.name == "Sample")
        #expect(model.genModel.genPackages == [model.package])
        #expect(model.genModel.allGenPackages == [model.package])
        #expect(model.package.name == "shapes")
        #expect(model.package.genModel == model.genModel)
        #expect(model.package.genPackage == model.package)
        #expect(model.package.parentGenPackage == nil)
        #expect(
            names(model.package.genClasses)
                == ["Circle", "Shape", "Named", "Drawable", "Square", "Point", "Tagged"])
        #expect(names(model.package.genEnums) == ["Colour"])
        #expect(names(model.package.genDataTypes) == ["Hex"])
        #expect(model.circle.genPackage == model.package)
        #expect(model.circle.genModel == model.genModel)
        #expect(model.circle.container == model.package)
        let radius = try #require(model.circle.genFeatures.first)
        #expect(radius.genClass == model.circle)
        #expect(radius.genPackage == model.package)
        #expect(radius.genModel == model.genModel)
    }

    @Test("kinds respect the metaclass hierarchy")
    func kinds() async throws {
        let model = try await ShapesModel()
        #expect(model.circle.className == "GenClass")
        #expect(model.circle.isKind(of: "GenClass"))
        #expect(model.circle.isKind(of: "GenClassifier"))
        #expect(model.circle.isKind(of: "GenBase"))
        #expect(!model.circle.isKind(of: "GenEnum"))
        #expect(model.colour.isKind(of: "GenDataType"))
        #expect(model.context.elements(ofKind: "GenClassifier").count == 9)
        #expect(model.context.elements(ofKind: "GenFeature").count == 13)
    }

    @Test("queries that do not apply yield empty results")
    func nonApplicable() async throws {
        let model = try await ShapesModel()
        #expect(model.genModel.genClasses.isEmpty)
        #expect(model.circle.genPackages.isEmpty)
        #expect(model.circle.parentGenPackage == nil)
        #expect(model.package.genClass == nil)
        #expect(model.genModel.classifierID == nil)
        #expect(model.genModel.classifierIDName == nil)
        #expect(model.colour.allGenFeatures.isEmpty)
        #expect(model.colour.baseGenClass == nil)
        #expect(model.genModel.stringValue("nonexistent") == nil)
        #expect(!model.colour.isMapEntry)
        #expect(!model.colour.isInterface)
        #expect(!model.colour.isAbstract)
        #expect(!model.colour.isReferenceType)
        #expect(model.colour.defaultValueLiteral == nil)
        #expect(!model.colour.hasDefault)
        #expect(model.colour.upperBound == 1)
        #expect(model.colour.lowerBound == 0)
        #expect(model.colour.isChangeable)
    }

    @Test("nested packages are listed depth first")
    func nestedPackages() async throws {
        var sample = try await SampleModel()
        let inner = EPackage(name: "inner", nsURI: "http://example.org/inner", nsPrefix: "in")
        let outer = EPackage(name: "outer", nsURI: "http://example.org/outer", nsPrefix: "out")
        sample.addPackage(outer)
        sample.addPackage(inner)
        let deep = try sample.genPackage(inner, prefix: "Inner")
        let top = try sample.genPackage(outer, prefix: "Outer", nested: [deep])
        let other = try sample.genPackage(outer, prefix: "Other")
        let model = try sample.genModel(packages: [top, other])
        let context = sample.context
        let genModel = try #require(context.element(id: model.id))
        let topElement = try #require(context.element(id: top.id))
        let deepElement = try #require(context.element(id: deep.id))
        #expect(genModel.allGenPackages.map(\.object.id) == [top.id, deep.id, other.id])
        #expect(topElement.nestedGenPackages == [deepElement])
        #expect(deepElement.parentGenPackage == topElement)
        #expect(deepElement.genModel == genModel)
    }

    @Test("many-valued and single-valued storage are both accepted")
    func storageShapes() async throws {
        var sample = try await SampleModel()
        let eClass = EClass(name: "Only", eStructuralFeatures: [SampleModel.attribute("a")])
        let ecore = EPackage(name: "p", nsURI: "http://example.org/p", nsPrefix: "p", eClassifiers: [eClass])
        sample.addPackage(ecore)
        let (genClass, features) = try sample.genClass(eClass)
        var single = genClass
        single.eSet("genFeatures", value: features[0].id)
        let package = try sample.genPackage(ecore, prefix: "P", classes: [single])
        _ = try sample.genModel(packages: [package])
        let context = sample.context
        let element = try #require(context.element(id: genClass.id))
        #expect(element.genFeatures.count == 1)
    }

    // MARK: - Values

    @Test("attribute accessors convert between stored representations")
    func valueAccessors() async throws {
        var sample = try await SampleModel()
        var model = try sample.make("GenModel")
        model.eSet("modelName", value: "M")
        model.eSet("importOrganizing", value: true)
        model.eSet("copyrightFields", value: "false")
        model.eSet("booleanFlagsReservedBits", value: 7)
        model.eSet("complianceLevel", value: "17.0")
        model.eSet("foreignModel", value: ["a.ecore", "b.ecore"])
        model.eSet("modelPluginID", value: 42)
        sample.add(model)
        let element = try #require(sample.context.element(id: model.id))
        #expect(element.stringValue("modelName") == "M")
        #expect(element.stringValue("importOrganizing") == "true")
        #expect(element.stringValue("booleanFlagsReservedBits") == "7")
        #expect(element.stringValue("modelPluginID") == "42")
        #expect(element.boolValue("importOrganizing"))
        #expect(!element.boolValue("copyrightFields", default: true))
        #expect(element.boolValue("unsetFlag", default: true))
        #expect(element.intValue("booleanFlagsReservedBits") == 7)
        #expect(element.intValue("complianceLevel", default: -1) == -1)
        #expect(element.intValue("modelPluginID", default: 3) == 42)
        #expect(element.intValue("missing", default: 3) == 3)
        #expect(element.stringValues("foreignModel") == ["a.ecore", "b.ecore"])
        #expect(element.stringValues("modelName") == ["M"])
        #expect(element.stringValues("missing").isEmpty)
    }

    // MARK: - Class hierarchy

    @Test("base classes are listed ancestors first")
    func baseClasses() async throws {
        let model = try await ShapesModel()
        #expect(names(model.circle.baseGenClasses) == ["Shape"])
        #expect(names(model.shape.baseGenClasses) == ["Named", "Drawable"])
        #expect(names(model.circle.allBaseGenClasses) == ["Named", "Drawable", "Shape"])
        #expect(model.circle.baseGenClass == model.shape)
        #expect(model.shape.baseGenClass == model.named)
        #expect(model.named.baseGenClass == nil)
        #expect(model.circle.classExtendsGenClass == model.shape)
        #expect(model.shape.classExtendsGenClass == model.named)
        #expect(model.named.classExtendsGenClass == nil)
    }

    @Test("a class whose first base is an interface extends the next non-interface base")
    func extendsSkipsInterfaces() async throws {
        var sample = try await SampleModel()
        let iface = EClass(
            name: "Iface", isAbstract: true, isInterface: true,
            eStructuralFeatures: [SampleModel.attribute("i")])
        let base = EClass(name: "Base", eStructuralFeatures: [SampleModel.attribute("b")])
        let mid = EClass(
            name: "Mid", eSuperTypes: [iface, base], eStructuralFeatures: [SampleModel.attribute("m")])
        let leaf = EClass(
            name: "Leaf", eSuperTypes: [mid], eStructuralFeatures: [SampleModel.attribute("l")])
        let ecore = EPackage(
            name: "p", nsURI: "http://example.org/p", nsPrefix: "p", eClassifiers: [iface, base, mid, leaf])
        sample.addPackage(ecore)
        let ifaceGen = try sample.genClass(iface)
        let baseGen = try sample.genClass(base)
        let midGen = try sample.genClass(mid)
        let leafGen = try sample.genClass(leaf)
        let package = try sample.genPackage(
            ecore, prefix: "P",
            classes: [ifaceGen.genClass, baseGen.genClass, midGen.genClass, leafGen.genClass])
        _ = try sample.genModel(packages: [package])
        let context = sample.context
        let midElement = try #require(context.element(id: midGen.genClass.id))
        let leafElement = try #require(context.element(id: leafGen.genClass.id))
        // The first base of Mid is an interface, so Mid extends nothing; it implements all.
        #expect(midElement.baseGenClass?.name == "Iface")
        #expect(midElement.classExtendsGenClass == nil)
        #expect(midElement.allBaseGenClasses.map(\.name) == ["Iface", "Base"])
        #expect(midElement.implementedGenClasses.map(\.name) == ["Iface", "Base", "Mid"])
        #expect(midElement.implementedGenFeatures.map(\.name) == ["i", "b", "m"])
        #expect(leafElement.classExtendsGenClass == midElement)
        #expect(leafElement.implementedGenFeatures.map(\.name) == ["l"])
        #expect(leafElement.allGenFeatures.map(\.name) == ["i", "b", "m", "l"])
    }

    @Test("a diamond lists each base once")
    func diamond() async throws {
        var sample = try await SampleModel()
        let top = EClass(name: "Top", eStructuralFeatures: [SampleModel.attribute("t")])
        let left = EClass(name: "Left", eSuperTypes: [top], eStructuralFeatures: [SampleModel.attribute("l")])
        let right = EClass(name: "Right", eSuperTypes: [top], eStructuralFeatures: [SampleModel.attribute("r")])
        let bottom = EClass(
            name: "Bottom", eSuperTypes: [left, right], eStructuralFeatures: [SampleModel.attribute("b")])
        let ecore = EPackage(
            name: "d", nsURI: "http://example.org/d", nsPrefix: "d", eClassifiers: [top, left, right, bottom])
        sample.addPackage(ecore)
        let generated = try [top, left, right, bottom].map { try sample.genClass($0) }
        let package = try sample.genPackage(ecore, prefix: "D", classes: generated.map(\.genClass))
        _ = try sample.genModel(packages: [package])
        let context = sample.context
        let bottomElement = try #require(context.element(id: generated[3].genClass.id))
        #expect(bottomElement.allBaseGenClasses.map(\.name) == ["Top", "Left", "Right"])
        #expect(bottomElement.allGenFeatures.map(\.name) == ["t", "l", "r", "b"])
        #expect(bottomElement.featureCount == 4)
    }

    @Test("a class cycle does not loop")
    func cycle() async throws {
        var sample = try await SampleModel()
        var first = EClass(name: "First")
        let second = EClass(name: "Second", eSuperTypes: [first])
        first.eSuperTypes = [second]
        let ecore = EPackage(
            name: "c", nsURI: "http://example.org/c", nsPrefix: "c", eClassifiers: [first, second])
        sample.addPackage(ecore)
        let firstGen = try sample.genClass(first)
        let secondGen = try sample.genClass(second)
        let package = try sample.genPackage(ecore, prefix: "C", classes: [firstGen.genClass, secondGen.genClass])
        _ = try sample.genModel(packages: [package])
        let context = sample.context
        let element = try #require(context.element(id: firstGen.genClass.id))
        #expect(element.allBaseGenClasses.count <= 2)
        #expect(element.classExtendsGenClass != nil)
        #expect(element.orderedGenClasses.isEmpty)
    }

    // MARK: - Features and IDs

    @Test("features list inherited ones first")
    func allFeatures() async throws {
        let model = try await ShapesModel()
        #expect(names(model.named.allGenFeatures) == ["name"])
        #expect(names(model.drawable.allGenFeatures) == ["visible", "layer"])
        #expect(names(model.shape.allGenFeatures) == ["name", "visible", "layer", "colour"])
        #expect(
            names(model.circle.allGenFeatures) == ["name", "visible", "layer", "colour", "radius"])
        #expect(names(model.circle.inheritedGenFeatures) == ["name", "visible", "layer", "colour"])
        #expect(
            names(model.square.allGenFeatures) == ["name", "visible", "layer", "colour", "side"])
    }

    @Test("feature identifiers continue after the inherited count")
    func featureIDs() async throws {
        let model = try await ShapesModel()
        #expect(model.named.featureCount == 1)
        #expect(model.drawable.featureCount == 2)
        #expect(model.shape.featureCount == 4)
        #expect(model.circle.featureCount == 5)
        let radius = try #require(model.circle.genFeatures.first)
        let side = try #require(model.square.genFeatures.first)
        let colour = try #require(model.shape.genFeatures.first)
        #expect(model.circle.featureID(of: radius) == 4)
        #expect(model.square.featureID(of: side) == 4)
        #expect(model.circle.featureID(of: colour) == 3)
        #expect(model.shape.featureID(of: colour) == 3)
        #expect(model.shape.featureID(of: radius) == nil)
        let inheritedName = try #require(model.named.genFeatures.first)
        #expect(model.circle.featureID(of: inheritedName) == 0)
        #expect(model.shape.featureID(of: inheritedName) == 0)
    }

    @Test("implemented features exclude those of the extended class")
    func implementedFeatures() async throws {
        let model = try await ShapesModel()
        #expect(names(model.circle.implementedGenFeatures) == ["radius"])
        #expect(names(model.shape.implementedGenFeatures) == ["visible", "layer", "colour"])
        #expect(names(model.named.implementedGenFeatures) == ["name"])
        #expect(names(model.drawable.implementedGenFeatures) == ["visible", "layer"])
        #expect(names(model.circle.implementedGenClasses) == ["Circle"])
        #expect(names(model.shape.implementedGenClasses) == ["Drawable", "Shape"])
    }

    // MARK: - Operations

    @Test("operations list inherited ones first and drop overrides")
    func operations() async throws {
        let model = try await ShapesModel()
        let shapeOps = model.shape.genOperations
        #expect(names(shapeOps) == ["scale", "draw"])
        #expect(names(model.circle.genOperations) == ["draw", "area"])
        #expect(names(model.circle.allGenOperations) == ["scale", "draw", "area"])
        #expect(
            names(model.circle.allGenOperations(excludeOverrides: false))
                == ["scale", "draw", "draw", "area"])
        #expect(model.circle.operationCount == 4)
        #expect(model.shape.operationCount == 2)
        let area = try #require(model.circle.genOperations.last)
        let override = try #require(model.circle.genOperations.first)
        #expect(model.circle.operationID(of: area) == 3)
        #expect(model.circle.operationID(of: override) == 2)
        #expect(model.circle.operationID(of: shapeOps[0]) == 0)
        #expect(model.shape.operationID(of: area) == nil)
    }

    @Test("override detection compares names and parameter counts")
    func overrideDetection() async throws {
        let model = try await ShapesModel()
        let scale = model.shape.genOperations[0]
        let draw = model.shape.genOperations[1]
        let circleDraw = model.circle.genOperations[0]
        #expect(circleDraw.isOverride(of: draw))
        #expect(!circleDraw.isOverride(of: scale))
        #expect(scale.genParameters.count == 1)
        #expect(names(scale.genParameters) == ["p0"])
        #expect(scale.name == "scale")
    }

    @Test("operation names come from name-based references only")
    func operationNames() async throws {
        var sample = try await SampleModel()
        var positional = try sample.make("GenOperation")
        positional.eSet("ecoreOperation", value: "m.ecore#//Shape/@eOperations.0")
        var overloaded = try sample.make("GenOperation")
        overloaded.eSet("ecoreOperation", value: "m.ecore#//Shape/scale.1")
        var typeParameter = try sample.make("GenTypeParameter")
        typeParameter.eSet("ecoreTypeParameter", value: "m.ecore#//Shape/T")
        var unrelated = try sample.make("GenOperation")
        for object in [positional, overloaded, typeParameter, unrelated] { sample.add(object) }
        unrelated.eSet("ecoreOperation", value: 3)
        let context = sample.context
        #expect(try #require(context.element(id: positional.id)).name == "")
        #expect(try #require(context.element(id: overloaded.id)).name == "scale")
        #expect(try #require(context.element(id: typeParameter.id)).name == "T")
        #expect(try #require(context.element(id: unrelated.id)).name == "")
    }

    // MARK: - Classifiers

    @Test("classifier identifiers number classes, then enumerations, then data types")
    func classifierIDs() async throws {
        let model = try await ShapesModel()
        #expect(
            names(model.package.genClassifiers)
                == [
                    "Circle", "Shape", "Named", "Drawable", "Square", "Point", "Tagged", "Colour",
                    "Hex",
                ])
        #expect(model.circle.classifierID == 0)
        #expect(model.shape.classifierID == 1)
        #expect(model.tagged.classifierID == 6)
        #expect(model.colour.classifierID == 7)
        #expect(model.hex.classifierID == 8)
    }

    @Test("ordered classifiers place base classes before derived classes")
    func orderedClassifiers() async throws {
        let model = try await ShapesModel()
        #expect(
            names(model.package.orderedGenClasses)
                == ["Named", "Shape", "Circle", "Drawable", "Square", "Point", "Tagged"])
        #expect(
            names(model.package.orderedGenClassifiers)
                == [
                    "Named", "Shape", "Circle", "Drawable", "Square", "Point", "Tagged", "Colour",
                    "Hex",
                ])
    }

    @Test("symbolic classifier identifiers use the package prefix")
    func classifierIDNames() async throws {
        let model = try await ShapesModel()
        #expect(model.circle.classifierIDName == "CIRCLE")
        #expect(model.colour.classifierIDName == "COLOUR")
        #expect(model.hex.classifierIDName == "HEX")
    }

    @Test("base classes in another package are not reordered into this package")
    func foreignBaseClass() async throws {
        var sample = try await SampleModel()
        let base = EClass(name: "Base")
        let derived = EClass(name: "Derived", eSuperTypes: [base])
        let packageA = EPackage(name: "a", nsURI: "http://example.org/a", nsPrefix: "a", eClassifiers: [base])
        let packageB = EPackage(name: "b", nsURI: "http://example.org/b", nsPrefix: "b", eClassifiers: [derived])
        sample.addPackage(packageA)
        sample.addPackage(packageB)
        let baseGen = try sample.genClass(base)
        let derivedGen = try sample.genClass(derived)
        let genA = try sample.genPackage(packageA, prefix: "A", classes: [baseGen.genClass])
        let genB = try sample.genPackage(packageB, prefix: "B", classes: [derivedGen.genClass])
        _ = try sample.genModel(packages: [genA, genB])
        let context = sample.context
        let packageElement = try #require(context.element(id: genB.id))
        #expect(packageElement.orderedGenClasses.map(\.name) == ["Derived"])
        let derivedElement = try #require(context.element(id: derivedGen.genClass.id))
        #expect(derivedElement.allBaseGenClasses.map(\.name) == ["Base"])
    }

    // MARK: - Label feature

    @Test("label feature prefers name, then id, then name suffix, then name infix, then first")
    func labelFeature() async throws {
        let model = try await ShapesModel()
        #expect(model.circle.labelFeature?.name == "name")
        #expect(model.point.labelFeature?.name == "id")
        #expect(model.tagged.labelFeature?.name == "filename")
        #expect(model.drawable.labelFeature?.name == "visible")
        #expect(names(model.tagged.labelFeatureCandidates) == ["x", "filename", "namedThing"])
    }

    @Test("an explicit label feature wins")
    func explicitLabelFeature() async throws {
        var sample = try await SampleModel()
        let eClass = EClass(
            name: "Item",
            eStructuralFeatures: [SampleModel.attribute("name"), SampleModel.attribute("code")])
        let ecore = EPackage(name: "i", nsURI: "http://example.org/i", nsPrefix: "i", eClassifiers: [eClass])
        sample.addPackage(ecore)
        let plain = try sample.genClass(eClass)
        let explicit = try sample.genClass(eClass, labelFeature: nil)
        var item = explicit.genClass
        item.eSet("labelFeature", value: explicit.features[1].id)
        sample.add(item)
        let package = try sample.genPackage(ecore, prefix: "I", classes: [plain.genClass])
        _ = try sample.genModel(packages: [package])
        let context = sample.context
        #expect(try #require(context.element(id: item.id)).labelFeature?.name == "code")
        #expect(try #require(context.element(id: plain.genClass.id)).labelFeature?.name == "name")
    }

    @Test("a class without candidates has no label feature")
    func noLabelFeature() async throws {
        var sample = try await SampleModel()
        let eClass = EClass(name: "Empty")
        let ecore = EPackage(name: "e", nsURI: "http://example.org/e", nsPrefix: "e", eClassifiers: [eClass])
        sample.addPackage(ecore)
        let generated = try sample.genClass(eClass)
        let package = try sample.genPackage(ecore, prefix: "E", classes: [generated.genClass])
        _ = try sample.genModel(packages: [package])
        let element = try #require(sample.context.element(id: generated.genClass.id))
        #expect(element.labelFeature == nil)
    }

    // MARK: - Map entries

    @Test("map entries need an instance type and key and value features")
    func mapEntry() async throws {
        var sample = try await SampleModel()
        let entry = EClass(
            name: "Entry",
            eStructuralFeatures: [SampleModel.attribute("key"), SampleModel.attribute("value")])
        let incomplete = EClass(name: "Half", eStructuralFeatures: [SampleModel.attribute("key")])
        let plain = EClass(
            name: "Plain",
            eStructuralFeatures: [SampleModel.attribute("key"), SampleModel.attribute("value")])
        let ecore = EPackage(
            name: "m", nsURI: "http://example.org/m", nsPrefix: "m", eClassifiers: [entry, incomplete, plain])
        sample.addPackage(ecore)
        let entryGen = try sample.genClass(entry)
        let halfGen = try sample.genClass(incomplete)
        let plainGen = try sample.genClass(plain)
        let package = try sample.genPackage(
            ecore, prefix: "M", classes: [entryGen.genClass, halfGen.genClass, plainGen.genClass])
        _ = try sample.genModel(packages: [package])
        let context = GenModelContext(
            objects: sample.objects, ecorePackages: [ecore],
            instanceTypeNames: [
                entry.id: "java.util.Map$Entry", incomplete.id: "java.util.Map$Entry",
                plain.id: "java.lang.Object",
            ])
        #expect(try #require(context.element(id: entryGen.genClass.id)).isMapEntry)
        #expect(!(try #require(context.element(id: halfGen.genClass.id)).isMapEntry))
        #expect(!(try #require(context.element(id: plainGen.genClass.id)).isMapEntry))
        #expect(!(try #require(sample.context.element(id: entryGen.genClass.id)).isMapEntry))
    }

    // MARK: - Naming shortcuts

    @Test("naming shortcuts use the Ecore name")
    func namingShortcuts() async throws {
        let model = try await ShapesModel()
        let radius = try #require(model.circle.genFeatures.first)
        let layer = try #require(model.drawable.genFeatures.last)
        #expect(radius.capName == "Radius")
        #expect(radius.uncapName == "radius")
        #expect(radius.upperName == "RADIUS")
        #expect(layer.upperName == "LAYER")
        #expect(model.circle.capName == "Circle")
        #expect(model.circle.uncapName == "circle")
        #expect(model.circle.uncapPrefixedName == "circle")
        #expect(model.circle.upperName == "CIRCLE")
        let tags = try #require(model.tagged.genFeatures.first { $0.name == "namedThing" })
        #expect(tags.upperName == "NAMED_THING")
    }

    @Test("literals, data types and enumerations expose their Ecore names")
    func enumerationElements() async throws {
        let model = try await ShapesModel()
        #expect(names(model.colour.genEnumLiterals) == ["Red", "Blue"])
        #expect(model.colour.ecoreEnum?.literals.count == 2)
        #expect(model.hex.ecoreDataType?.name == "Hex")
        #expect(model.colour.genEnumLiterals[1].ecoreEnumLiteral?.value == 1)
        #expect(model.package.ecorePackage?.nsURI == "http://example.org/shapes")
    }

    @Test("label feature falls back to a name infix over a plain attribute")
    func labelFeatureInfix() async throws {
        var sample = try await SampleModel()
        let eClass = EClass(
            name: "Thing",
            eStructuralFeatures: [SampleModel.attribute("x"), SampleModel.attribute("nameTag")])
        let ecore = EPackage(name: "t", nsURI: "http://example.org/t", nsPrefix: "t", eClassifiers: [eClass])
        sample.addPackage(ecore)
        let generated = try sample.genClass(eClass)
        let package = try sample.genPackage(ecore, prefix: "T", classes: [generated.genClass])
        _ = try sample.genModel(packages: [package])
        let element = try #require(sample.context.element(id: generated.genClass.id))
        #expect(element.labelFeature?.name == "nameTag")
    }

    @Test("used packages, type parameters and annotations are navigable")
    func otherContainments() async throws {
        var sample = try await SampleModel()
        let ecore = EPackage(name: "u", nsURI: "http://example.org/u", nsPrefix: "u")
        sample.addPackage(ecore)
        let used = try sample.genPackage(ecore, prefix: "Used")
        var annotation = try sample.make("GenAnnotation")
        annotation.eSet("source", value: "doc")
        sample.add(annotation)
        var typeParameter = try sample.make("GenTypeParameter")
        sample.add(typeParameter)
        var owner = try sample.genPackage(ecore, prefix: "Owner")
        owner.eSet("genAnnotations", value: [annotation.id])
        sample.add(owner)
        var model = try sample.genModel(packages: [owner])
        model.eSet("usedGenPackages", value: [used.id])
        sample.add(model)
        typeParameter.eSet("documentation", value: "t")
        let context = sample.context
        let ownerElement = try #require(context.element(id: owner.id))
        let modelElement = try #require(context.element(id: model.id))
        #expect(ownerElement.genAnnotations.map { $0.stringValue("source") } == ["doc"])
        #expect(ownerElement.genTypeParameters.isEmpty)
        #expect(modelElement.usedGenPackages.map(\.object.id) == [used.id])
    }
}
