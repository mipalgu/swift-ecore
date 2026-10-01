//
// SampleModel.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

@testable import GenModel

/// Builds generator models programmatically from hand-built native Ecore classes.
///
/// Generator objects are created through the factory of the loaded generator metamodel,
/// the Ecore side is built with the native Ecore types, and the two are tied together by
/// element identifiers.
struct SampleModel {
    let genModelPackage: EPackage
    private(set) var objects: [DynamicEObject] = []
    private(set) var ecorePackages: [EPackage] = []

    init() async throws {
        genModelPackage = try await GenModelPackage.load()
    }

    // MARK: - Ecore helpers

    static let stringType = EDataType(name: "EString")
    static let intType = EDataType(name: "EInt")
    static let boolType = EDataType(name: "EBoolean")

    static func attribute(
        _ name: String, type: EDataType = stringType, upper: Int = 1, defaultValue: String? = nil
    ) -> EAttribute {
        EAttribute(name: name, eType: type, upperBound: upper, defaultValueLiteral: defaultValue)
    }

    // MARK: - Generator objects

    mutating func make(_ className: String) throws -> DynamicEObject {
        let eClass = try #require(genModelPackage.getEClass(className))
        let object = genModelPackage.eFactoryInstance.create(eClass)
        return object
    }

    mutating func add(_ object: DynamicEObject) {
        objects.append(object)
    }

    mutating func addPackage(_ package: EPackage) {
        ecorePackages.append(package)
    }

    /// Creates a generator model owning the given packages.
    mutating func genModel(name: String = "Sample", packages: [DynamicEObject]) throws
        -> DynamicEObject
    {
        var model = try make("GenModel")
        model.eSet("modelName", value: name)
        model.eSet("genPackages", value: packages.map(\.id))
        add(model)
        return model
    }

    /// Creates a generator package.
    mutating func genPackage(
        _ ecore: EPackage, prefix: String, classes: [DynamicEObject] = [],
        enums: [DynamicEObject] = [], dataTypes: [DynamicEObject] = [],
        nested: [DynamicEObject] = []
    ) throws -> DynamicEObject {
        var package = try make("GenPackage")
        package.eSet("prefix", value: prefix)
        package.eSet("ecorePackage", value: ecore.id)
        package.eSet("genClasses", value: classes.map(\.id))
        package.eSet("genEnums", value: enums.map(\.id))
        package.eSet("genDataTypes", value: dataTypes.map(\.id))
        package.eSet("nestedGenPackages", value: nested.map(\.id))
        add(package)
        return package
    }

    /// Creates a generator class with generator features for every feature of the Ecore class.
    mutating func genClass(
        _ eClass: EClass, operations: [DynamicEObject] = [], labelFeature: DynamicEObject? = nil
    ) throws -> (genClass: DynamicEObject, features: [DynamicEObject]) {
        var features: [DynamicEObject] = []
        for feature in eClass.eStructuralFeatures {
            var genFeature = try make("GenFeature")
            genFeature.eSet("ecoreFeature", value: feature.id)
            add(genFeature)
            features.append(genFeature)
        }
        var genClass = try make("GenClass")
        genClass.eSet("ecoreClass", value: eClass.id)
        genClass.eSet("genFeatures", value: features.map(\.id))
        genClass.eSet("genOperations", value: operations.map(\.id))
        if let labelFeature { genClass.eSet("labelFeature", value: labelFeature.id) }
        add(genClass)
        return (genClass, features)
    }

    /// Creates a generator operation referring to an operation by textual reference.
    mutating func genOperation(_ reference: String, parameters: Int = 0) throws -> DynamicEObject {
        var parameterObjects: [DynamicEObject] = []
        for index in 0..<parameters {
            var parameter = try make("GenParameter")
            parameter.eSet("ecoreParameter", value: "\(reference)/p\(index)")
            add(parameter)
            parameterObjects.append(parameter)
        }
        var operation = try make("GenOperation")
        operation.eSet("ecoreOperation", value: reference)
        operation.eSet("genParameters", value: parameterObjects.map(\.id))
        add(operation)
        return operation
    }

    mutating func genEnum(_ eEnum: EEnum) throws -> DynamicEObject {
        var literals: [DynamicEObject] = []
        for literal in eEnum.literals {
            var genLiteral = try make("GenEnumLiteral")
            genLiteral.eSet("ecoreEnumLiteral", value: literal.id)
            add(genLiteral)
            literals.append(genLiteral)
        }
        var genEnum = try make("GenEnum")
        genEnum.eSet("ecoreEnum", value: eEnum.id)
        genEnum.eSet("genEnumLiterals", value: literals.map(\.id))
        add(genEnum)
        return genEnum
    }

    mutating func genDataType(_ dataType: EDataType) throws -> DynamicEObject {
        var genDataType = try make("GenDataType")
        genDataType.eSet("ecoreDataType", value: dataType.id)
        add(genDataType)
        return genDataType
    }

    var context: GenModelContext {
        GenModelContext(objects: objects, ecorePackages: ecorePackages)
    }
}

/// A model of shapes with multiple inheritance, an interface, an enumeration and a data type.
///
/// Model order of classes is `Circle`, `Shape`, `Named`, `Drawable`, `Square`, `Point`, `Tagged`.
struct ShapesModel {
    let context: GenModelContext
    let genModel: GenElement
    let package: GenElement
    let circle: GenElement
    let shape: GenElement
    let named: GenElement
    let drawable: GenElement
    let square: GenElement
    let point: GenElement
    let tagged: GenElement
    let colour: GenElement
    let hex: GenElement

    init() async throws {
        var sample = try await SampleModel()
        let string = SampleModel.stringType
        let int = SampleModel.intType
        let bool = SampleModel.boolType

        let namedClass = EClass(
            name: "Named", isAbstract: true, eStructuralFeatures: [SampleModel.attribute("name", type: string)])
        let drawableClass = EClass(
            name: "Drawable", isAbstract: true, isInterface: true,
            eStructuralFeatures: [
                SampleModel.attribute("visible", type: bool),
                SampleModel.attribute("layer", type: int, defaultValue: "0"),
            ])
        let colourEnum = EEnum(
            name: "Colour",
            literals: [EEnumLiteral(name: "Red", value: 0), EEnumLiteral(name: "Blue", value: 1)])
        let hexType = EDataType(name: "Hex")
        let shapeClass = EClass(
            name: "Shape", isAbstract: true, eSuperTypes: [namedClass, drawableClass],
            eStructuralFeatures: [SampleModel.attribute("colour", type: string)])
        let circleClass = EClass(
            name: "Circle", eSuperTypes: [shapeClass],
            eStructuralFeatures: [SampleModel.attribute("radius", type: int)])
        let squareClass = EClass(
            name: "Square", eSuperTypes: [shapeClass],
            eStructuralFeatures: [SampleModel.attribute("side", type: int)])
        let pointClass = EClass(
            name: "Point",
            eStructuralFeatures: [
                SampleModel.attribute("x", type: int), SampleModel.attribute("id"),
                SampleModel.attribute("nickname"),
            ])
        let taggedClass = EClass(
            name: "Tagged",
            eStructuralFeatures: [
                SampleModel.attribute("x", type: int), SampleModel.attribute("filename"),
                SampleModel.attribute("tags", upper: -1), SampleModel.attribute("namedThing"),
            ])
        let ecore = EPackage(
            name: "shapes", nsURI: "http://example.org/shapes", nsPrefix: "shp",
            eClassifiers: [
                namedClass, drawableClass, shapeClass, circleClass, squareClass, pointClass,
                taggedClass, colourEnum, hexType,
            ])
        sample.addPackage(ecore)

        let scale = try sample.genOperation("shapes.ecore#//Shape/scale", parameters: 1)
        let drawBase = try sample.genOperation("shapes.ecore#//Shape/draw")
        let drawOverride = try sample.genOperation("shapes.ecore#//Circle/draw")
        let area = try sample.genOperation("shapes.ecore#//Circle/area")

        let circleGen = try sample.genClass(circleClass, operations: [drawOverride, area])
        let shapeGen = try sample.genClass(shapeClass, operations: [scale, drawBase])
        let namedGen = try sample.genClass(namedClass)
        let drawableGen = try sample.genClass(drawableClass)
        let squareGen = try sample.genClass(squareClass)
        let pointGen = try sample.genClass(pointClass)
        let taggedGen = try sample.genClass(taggedClass)
        let colourGen = try sample.genEnum(colourEnum)
        let hexGen = try sample.genDataType(hexType)
        let genPackage = try sample.genPackage(
            ecore, prefix: "Shapes",
            classes: [
                circleGen.genClass, shapeGen.genClass, namedGen.genClass, drawableGen.genClass,
                squareGen.genClass, pointGen.genClass, taggedGen.genClass,
            ], enums: [colourGen], dataTypes: [hexGen])
        let model = try sample.genModel(packages: [genPackage])

        let built = sample.context
        func element(_ object: DynamicEObject) throws -> GenElement {
            try #require(built.element(id: object.id))
        }
        context = built
        genModel = try element(model)
        package = try element(genPackage)
        circle = try element(circleGen.genClass)
        shape = try element(shapeGen.genClass)
        named = try element(namedGen.genClass)
        drawable = try element(drawableGen.genClass)
        square = try element(squareGen.genClass)
        point = try element(pointGen.genClass)
        tagged = try element(taggedGen.genClass)
        colour = try element(colourGen)
        hex = try element(hexGen)
    }
}

import Testing
