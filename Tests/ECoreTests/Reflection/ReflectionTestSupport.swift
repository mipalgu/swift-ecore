//
// ReflectionTestSupport.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Failures raised while locating test fixtures.
enum ReflectionFixtureError: Error {
    /// The bundled test resources could not be found.
    case resourcesNotFound
}

/// Shared helpers for the reflective metamodel tests.
enum ReflectionFixtures {
    /// The test resources directory.
    static func resourcesURL() throws -> URL {
        guard let bundleResourcesURL = Bundle.module.resourceURL else {
            throw ReflectionFixtureError.resourcesNotFound
        }
        let nested = bundleResourcesURL.appendingPathComponent("Resources")
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: nested.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        {
            return nested
        }
        return bundleResourcesURL
    }

    /// Loads a metamodel fixture as a native package.
    static func loadPackage(_ relativePath: String) async throws -> EPackage {
        let url = try resourcesURL().appendingPathComponent(relativePath)
        return try await EPackage(url: url)
    }

    /// A small hand-built metamodel with an enum, an operation-free class hierarchy,
    /// containment, an opposite pair, and a nested package.
    static func makeLibraryPackage() -> EPackage {
        let string = EDataType(name: "EString")
        let int = EDataType(name: "EInt")
        let genre = EEnum(
            name: "Genre",
            literals: [
                EEnumLiteral(name: "fiction", value: 0),
                EEnumLiteral(name: "history", value: 1, literal: "HISTORY"),
            ])
        let itemID = EUUID()
        let libraryID = EUUID()
        let item = EClass(
            id: itemID, name: "Item", isAbstract: true,
            eStructuralFeatures: [
                EAttribute(name: "title", eType: string, lowerBound: 1, isID: true),
                EAttribute(name: "pages", eType: int, defaultValueLiteral: "1"),
            ])
        let book = EClass(
            name: "Book", eSuperTypes: [item],
            eStructuralFeatures: [
                EAttribute(name: "genre", eType: genre),
                EAttribute(name: "tags", eType: string, upperBound: -1),
            ])
        let library = EClass(
            id: libraryID, name: "Library",
            eStructuralFeatures: [
                EReference(
                    name: "items", eType: EClass(id: itemID, name: "Item"), upperBound: -1,
                    containment: true),
                EReference(
                    name: "featured", eType: EClass(id: itemID, name: "Item"),
                    resolveProxies: false),
            ])
        let archive = EPackage(
            name: "archive", nsURI: "http://example.org/library/archive", nsPrefix: "arc",
            eClassifiers: [EClass(name: "Box")])
        return EPackage(
            name: "library", nsURI: "http://example.org/library", nsPrefix: "lib",
            eClassifiers: [item, book, library, genre, string, int],
            eSubpackages: [archive],
            eAnnotations: [EAnnotation(source: "doc", details: ["b": "2", "a": "1"])])
    }

    /// Reads a feature of a metamodel object by name.
    static func value(of object: some EObject, _ name: String) throws -> (any EcoreValue)? {
        let eClass = try #require(object.eClass as? EClass)
        let feature = try #require(eClass.getStructuralFeature(name: name))
        return object.value(feature)
    }

    /// The names of the named elements in a collection value.
    static func names(_ value: (any EcoreValue)?) -> [String] {
        guard let array = value as? EcoreValueArray else { return [] }
        return array.values.compactMap { ($0 as? any ENamedElement)?.name }
    }
}

extension EObject {
    /// Sets a feature given as an existential, for use in tests.
    mutating func set(_ feature: any EStructuralFeature, _ value: (any EcoreValue)?) {
        eSet(feature, value)
    }

    /// Checks whether a feature given as an existential is set, for use in tests.
    func isSet(_ feature: any EStructuralFeature) -> Bool {
        eIsSet(feature)
    }

    /// Unsets a feature given as an existential, for use in tests.
    mutating func unset(_ feature: any EStructuralFeature) {
        eUnset(feature)
    }

    /// Reads a feature given as an existential, for use in tests.
    func value(_ feature: any EStructuralFeature) -> (any EcoreValue)? {
        eGet(feature)
    }
}
