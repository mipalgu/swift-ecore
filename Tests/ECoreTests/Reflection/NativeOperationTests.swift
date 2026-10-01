//
// NativeOperationTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Native Operation and Parameter Tests")
struct NativeOperationTests {
    /// A package whose `Book` class declares two operations and inherits one.
    private static func makePackage() -> (package: EPackage, borrow: EOperation, days: EParameter) {
        let int = EcorePackage.dataType(.eInt) ?? EDataType(name: "EInt")
        let boolean = EcorePackage.dataType(.eBoolean) ?? EDataType(name: "EBoolean")
        let string = EcorePackage.dataType(.eString) ?? EDataType(name: "EString")
        let failure = EClass(name: "LoanFailure")
        let days = EParameter(name: "days", eType: int, lowerBound: 1)
        let reason = EParameter(name: "reasons", eType: string, upperBound: -1, ordered: false, unique: false)
        let borrow = EOperation(
            name: "borrow", eType: boolean, lowerBound: 1, eParameters: [days, reason],
            eExceptions: [failure])
        let describe = EOperation(name: "describe", eType: string, upperBound: -1)
        let reset = EOperation(name: "reset")
        let item = EClass(name: "Item", eOperations: [reset])
        let book = EClass(name: "Book", eSuperTypes: [item], eOperations: [borrow, describe])
        let package = EPackage(
            name: "shop", nsURI: "http://example.org/shop", nsPrefix: "shop",
            eClassifiers: [item, book, failure])
        return (package, borrow, days)
    }

    @Test("operations carry their declared properties")
    func properties() throws {
        let (package, _, _) = Self.makePackage()
        let book = try #require(package.getEClass("Book"))
        let borrow = try #require(book.eOperations.first)
        #expect(borrow.name == "borrow")
        #expect(borrow.eType?.name == "EBoolean")
        #expect(borrow.isRequired && !borrow.isMany)
        #expect(borrow.eParameters.map(\.name) == ["days", "reasons"])
        #expect(borrow.eExceptions.map(\.name) == ["LoanFailure"])
        let reasons = try #require(borrow.getParameter(name: "reasons"))
        #expect(reasons.isMany && !reasons.ordered && !reasons.unique)
        #expect(book.eOperations[1].isMany)
        #expect(book.eOperations[1].eType?.name == "EString")
        #expect(try #require(package.getEClass("Item")).eOperations[0].eType == nil)
    }

    @Test("containers are recorded for operations and parameters")
    func containerIdentifiers() throws {
        let (package, _, _) = Self.makePackage()
        let book = try #require(package.getEClass("Book"))
        let borrow = try #require(book.eOperations.first)
        #expect(borrow.eContainerID == book.id)
        #expect(borrow.eParameters.allSatisfy { $0.eContainerID == borrow.id })
    }

    @Test("inherited operations are listed supertype first")
    func allOperations() throws {
        let (package, _, _) = Self.makePackage()
        let book = try #require(package.getEClass("Book"))
        #expect(book.eAllOperations.map(\.name) == ["reset", "borrow", "describe"])
        #expect(book.getOperation(name: "reset")?.name == "reset")
        #expect(book.getOperation(name: "missing") == nil)
    }

    @Test("descriptors identify operations and parameters")
    func descriptors() throws {
        let (_, borrow, days) = Self.makePackage()
        #expect(borrow.eClass.id == EcorePackage.metaClass(.eOperation).id)
        #expect(days.eClass.id == EcorePackage.metaClass(.eParameter).id)
    }

    @Test("reflection reads operation and parameter features")
    func reflectiveGet() throws {
        let (package, _, _) = Self.makePackage()
        let book = try #require(package.getEClass("Book"))
        let borrow = try #require(book.eOperations.first)
        let operations = try ReflectionFixtures.value(of: book, "eOperations")
        #expect(ReflectionFixtures.names(operations) == ["borrow", "describe"])
        let allOperations = try ReflectionFixtures.value(of: book, "eAllOperations")
        #expect(ReflectionFixtures.names(allOperations) == ["reset", "borrow", "describe"])
        #expect(try ReflectionFixtures.value(of: borrow, "name") as? String == "borrow")
        #expect(try ReflectionFixtures.value(of: borrow, "lowerBound") as? Int == 1)
        #expect(try ReflectionFixtures.value(of: borrow, "upperBound") as? Int == 1)
        #expect(try ReflectionFixtures.value(of: borrow, "required") as? Bool == true)
        #expect(try ReflectionFixtures.value(of: borrow, "many") as? Bool == false)
        let type = try ReflectionFixtures.value(of: borrow, "eType") as? any ENamedElement
        #expect(type?.name == "EBoolean")
        #expect(
            ReflectionFixtures.names(try ReflectionFixtures.value(of: borrow, "eParameters"))
                == ["days", "reasons"])
        #expect(
            ReflectionFixtures.names(try ReflectionFixtures.value(of: borrow, "eExceptions"))
                == ["LoanFailure"])
        #expect(try ReflectionFixtures.value(of: borrow, "eContainingClass") as? EUUID == book.id)
        let reasons = try #require(borrow.getParameter(name: "reasons"))
        #expect(try ReflectionFixtures.value(of: reasons, "ordered") as? Bool == false)
        #expect(try ReflectionFixtures.value(of: reasons, "eOperation") as? EUUID == borrow.id)
        let voidOperation = try #require(package.getEClass("Item")?.eOperations.first)
        #expect(try ReflectionFixtures.value(of: voidOperation, "eType") == nil)
    }

    @Test("reflection modifies operations")
    func reflectiveSet() throws {
        var operation = EOperation(name: "old")
        let nameFeature = try #require(EcorePackage.feature(.name, of: .eOperation))
        operation.set(nameFeature, "new")
        #expect(operation.name == "new")
        let parametersFeature = try #require(EcorePackage.feature(.eParameters, of: .eOperation))
        operation.set(parametersFeature, EcoreValueArray([EParameter(name: "p")]))
        #expect(operation.eParameters.map(\.name) == ["p"])
        #expect(operation.eParameters[0].eContainerID == operation.id)
        let upper = try #require(EcorePackage.feature(.upperBound, of: .eOperation))
        operation.set(upper, -1)
        #expect(operation.isMany)
        #expect(operation.isSet(upper))
        operation.unset(upper)
        #expect(operation.upperBound == 1)
        var parameter = EParameter(name: "q")
        let typeFeature = try #require(EcorePackage.feature(.eType, of: .eTypedElement))
        parameter.set(typeFeature, EDataType(name: "EInt"))
        #expect(parameter.eType?.name == "EInt")
        var typed = EClass(name: "C")
        let operationsFeature = try #require(EcorePackage.feature(.eOperations, of: .eClass))
        typed.set(operationsFeature, EcoreValueArray([operation]))
        #expect(typed.eOperations.count == 1)
        #expect(typed.eOperations[0].eContainerID == typed.id)
    }

    @Test("a class lists its operations among its contents")
    func containedObjects() throws {
        let (package, _, _) = Self.makePackage()
        let book = try #require(package.getEClass("Book"))
        #expect(book.eContents.map { ($0 as? any ENamedElement)?.name } == ["borrow", "describe"])
        let borrow = try #require(book.eOperations.first)
        #expect(borrow.eContents.compactMap { ($0 as? any ENamedElement)?.name } == ["days", "reasons"])
    }

    @Test("a resource enumerates, contains, and resolves operations")
    func resourceNavigation() async throws {
        let (package, borrow, days) = Self.makePackage()
        let resource = Resource(uri: "file:///shop.ecore")
        await resource.registerNativePackage(package)
        let operations = await resource.getAllInstancesOf(EcorePackage.metaClass(.eOperation))
        #expect(operations.compactMap { ($0 as? EOperation)?.name } == ["reset", "borrow", "describe"])
        let parameters = await resource.getAllInstancesOf(EcorePackage.metaClass(.eParameter))
        #expect(parameters.count == 2)
        let typed = await resource.getAllInstancesOf(EcorePackage.metaClass(.eTypedElement))
        #expect(typed.count == 3 + 2)
        let container = try #require(await resource.eContainer(of: days) as? EOperation)
        #expect(container.id == borrow.id)
        let feature = try #require(await resource.eContainingFeature(of: days))
        #expect(feature.name == "eParameters")
        let book = try #require(package.getEClass("Book"))
        let operationContainer = try #require(await resource.eContainer(of: borrow) as? EClass)
        #expect(operationContainer.id == book.id)
        #expect(try #require(await resource.eContainingFeature(of: borrow)).name == "eOperations")
        let contents = await resource.eAllContents(of: book).compactMap { ($0 as? any ENamedElement)?.name }
        #expect(contents == ["borrow", "days", "reasons", "describe"])
    }

    @Test("name-based fragments identify operations and parameters")
    func fragments() async throws {
        let (package, borrow, days) = Self.makePackage()
        let resource = Resource(uri: "file:///shop.ecore")
        await resource.registerNativePackage(package)
        let navigator = FragmentNavigator(resource: resource)
        #expect(await navigator.resolve("//Book/borrow")?.id == borrow.id)
        #expect(await navigator.resolve("//Book/borrow/days")?.id == days.id)
        #expect(await navigator.fragment(for: days.id) == "//Book/borrow/days")
        #expect(await navigator.fragment(for: borrow.id) == "//Book/borrow")
    }
}
