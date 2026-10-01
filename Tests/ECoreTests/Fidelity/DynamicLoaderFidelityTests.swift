//
// DynamicLoaderFidelityTests.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

@Suite("Dynamic Ecore Loader Fidelity Tests")
struct DynamicLoaderFidelityTests {
    private func parse(_ name: String = "library-full.ecore") async throws -> Resource {
        try await XMIParser().parse(try FidelityFixtures.url(name))
    }

    private func element(
        _ fragment: String, in resource: Resource
    ) async throws -> DynamicEObject {
        try #require(await FragmentNavigator(resource: resource).resolve(fragment) as? DynamicEObject)
    }

    private func identifiers(_ value: (any EcoreValue)?) -> [EUUID] {
        switch value {
        case let identifier as EUUID: return [identifier]
        case let identifiers as [EUUID]: return identifiers
        default: return []
        }
    }

    private func first(_ value: (any EcoreValue)?) throws -> EUUID {
        try #require(identifiers(value).first)
    }

    private func name(of identifier: EUUID?, in resource: Resource) async -> String? {
        guard let identifier, let object = await resource.resolve(identifier) else { return nil }
        return (object as? DynamicEObject)?.eGet("name") as? String ?? (object as? any ENamedElement)?.name
    }

    // MARK: Supertypes

    @Test("multi-valued eSuperTypes keep all supertypes in order")
    func multipleSupertypes() async throws {
        let resource = try await parse()
        let book = try await element("//Book", in: resource)
        let supertypes = identifiers(book.eGet("eSuperTypes"))
        #expect(supertypes.count == 2)
        var names: [String] = []
        for identifier in supertypes { names.append(await name(of: identifier, in: resource) ?? "?") }
        #expect(names == ["Named", "Lendable"])
        let writer = try await element("//Writer", in: resource)
        #expect(identifiers(writer.eGet("eSuperTypes")).count == 1)
    }

    // MARK: Types

    @Test("attribute types resolve to local enumerations and data types")
    func localTypes() async throws {
        let resource = try await parse()
        let category = try await element("//Book/category", in: resource)
        let enumeration = try #require(
            await resource.resolve(try first(category.eGet("eType"))) as? DynamicEObject)
        #expect(enumeration.eClass.name == "EEnum" && enumeration.eGet("name") as? String == "BookCategory")
        let isbn = try await element("//Book/isbn", in: resource)
        let isbnType = try #require(
            await resource.resolve(try first(isbn.eGet("eType"))) as? DynamicEObject)
        #expect(isbnType.eClass.name == "EDataType" && isbnType.eGet("name") as? String == "ISBN")
        #expect(isbnType.eGet("instanceClassName") as? String == "java.lang.String")
        let path = try await element("//Path", in: resource)
        #expect(path.eGet("serializable") as? Bool == false)
        #expect(path.eGet("instanceClassName") as? String == "java.nio.file.Path")
        let location = try await element("//Book/location", in: resource)
        #expect(identifiers(location.eGet("eType")) == [path.id])
    }

    @Test("attribute types resolve into nested packages")
    func nestedPackageTypes() async throws {
        let resource = try await parse()
        let shelf = try await element("//catalogue/Shelf", in: resource)
        let bookShelf = try await element("//Book/shelf", in: resource)
        #expect(identifiers(bookShelf.eGet("eType")) == [shelf.id])
        let sectionShelf = try await element("//catalogue/Section/shelf", in: resource)
        #expect(identifiers(sectionShelf.eGet("eType")) == [shelf.id])
        let section = try await element("//catalogue/Section", in: resource)
        let sections = try await element("//Library/sections", in: resource)
        #expect(identifiers(sections.eGet("eType")) == [section.id])
        let box = try await element("//catalogue/archive/Box", in: resource)
        #expect(box.eGet("name") as? String == "Box")
    }

    @Test("built-in data types and metaclasses resolve to the Ecore package")
    func builtIns() async throws {
        let resource = try await parse()
        let name = try await element("//Named/name", in: resource)
        let stringID = try first(name.eGet("eType"))
        #expect(stringID == EcorePackage.dataType(.eString)?.id)
        #expect(await resource.resolve(stringID) is EDataType)
        let metaclass = try await element("//Book/metaclass", in: resource)
        #expect(identifiers(metaclass.eGet("eType")) == [EcorePackage.metaClass(.eClass).id])
        let feature = try await element("//Writer/feature", in: resource)
        #expect(identifiers(feature.eGet("eType")) == [EcorePackage.metaClass(.eStructuralFeature).id])
        let resolved = try #require(await resource.resolve(EcorePackage.metaClass(.ePackage).id) as? EClass)
        #expect(resolved.name == "EPackage")
        #expect(resolved.eAllStructuralFeatures.map(\.name).contains("nsURI"))
    }

    // MARK: Flags

    @Test("feature flags and bounds are kept")
    func flags() async throws {
        let resource = try await parse()
        let onLoan = try await element("//Lendable/onLoan", in: resource)
        #expect(onLoan.eGet("changeable") as? Bool == false)
        for flag in ["volatile", "transient", "derived"] { #expect(onLoan.eGet(flag) as? Bool == true) }
        let nameAttribute = try await element("//Named/name", in: resource)
        #expect(nameAttribute.eGet("iD") as? Bool == true)
        #expect(nameAttribute.eGet("lowerBound") as? Int == 1)
        let loanDays = try await element("//Lendable/loanDays", in: resource)
        #expect(loanDays.eGet("defaultValueLiteral") as? String == "14")
        let tags = try await element("//Book/tags", in: resource)
        #expect(tags.eGet("upperBound") as? Int == -1 && tags.eGet("unique") as? Bool == false)
        let subtitle = try await element("//Book/subtitle", in: resource)
        #expect(subtitle.eGet("unsettable") as? Bool == true)
        let related = try await element("//Book/related", in: resource)
        #expect(related.eGet("ordered") as? Bool == false)
        #expect(related.eGet("unique") as? Bool == false)
        #expect(related.eGet("resolveProxies") as? Bool == false)
        let books = try await element("//Library/books", in: resource)
        #expect(books.eGet("containment") as? Bool == true)
        let library = try await element("//Book/library", in: resource)
        #expect(identifiers(library.eGet("eOpposite")) == [books.id])
        #expect(identifiers(books.eGet("eOpposite")) == [library.id])
    }

    @Test("instance class names of classes are kept")
    func instanceClassNames() async throws {
        let resource = try await parse()
        let entry = try await element("//StringToBookEntry", in: resource)
        #expect(entry.eGet("instanceClassName") as? String == "java.util.Map$Entry")
        #expect(try await element("//Book", in: resource).eGet("instanceClassName") == nil)
    }

    // MARK: Operations

    @Test("operations keep types, parameters, bounds, and exceptions")
    func operations() async throws {
        let resource = try await parse()
        let borrow = try await element("//Lendable/borrow", in: resource)
        #expect(borrow.eClass.id == EcorePackage.metaClass(.eOperation).id)
        #expect(borrow.eGet("lowerBound") as? Int == 1)
        #expect(identifiers(borrow.eGet("eType")) == [EcorePackage.dataType(.eBoolean)?.id].compactMap { $0 })
        let failure = try await element("//LoanFailure", in: resource)
        #expect(identifiers(borrow.eGet("eExceptions")) == [failure.id])
        #expect(identifiers(borrow.eGet("eParameters")).count == 2)
        let notes = try await element("//Lendable/borrow/notes", in: resource)
        #expect(notes.eClass.id == EcorePackage.metaClass(.eParameter).id)
        #expect(notes.eGet("ordered") as? Bool == false && notes.eGet("unique") as? Bool == false)
        #expect(notes.eGet("upperBound") as? Int == -1)
        let holder = try await element("//Lendable/holder", in: resource)
        let writer = try await element("//Writer", in: resource)
        #expect(identifiers(holder.eGet("eType")) == [writer.id])
        #expect(await resource.getAllInstancesOf(EcorePackage.metaClass(.eOperation)).count == 3)
        #expect(await resource.getAllInstancesOf(EcorePackage.metaClass(.eParameter)).count == 2)
    }

    // MARK: Cross-document references

    @Test("types and supertypes of other documents resolve through the resource set")
    func crossDocument() async throws {
        let set = ResourceSet()
        let consumer = try await set.loadReferencedResource(
            uri: try FidelityFixtures.url("consumer.ecore").absoluteString)
        let widget = try await element("//Widget", in: consumer)
        let proxies = try #require(widget.eGet("eSuperTypes") as? [ResourceProxy])
        #expect(proxies.map(\.fragment) == ["//Audited"])
        #expect(proxies[0].uri.hasSuffix("shared.ecore"))
        let colour = try await element("//Widget/colour", in: consumer)
        let proxy = try #require(colour.eGet("eType") as? ResourceProxy)
        #expect(proxy.fragment == "//Colour")
        let report = await consumer.resolveProxies()
        #expect(report.unresolved.isEmpty)
        let refreshed = try await element("//Widget/colour", in: consumer)
        let resolved = try #require(await set.resolve(try first(refreshed.eGet("eType"))))
        #expect((resolved.object as? DynamicEObject)?.eGet("name") as? String == "Colour")
    }

    // MARK: Generic types

    @Test("eGenericType children supply the type")
    func genericTypes() async throws {
        let url = try FidelityFixtures.writeDocument(
            """
              <eClassifiers xsi:type="ecore:EClass" name="Base"/>
              <eClassifiers xsi:type="ecore:EClass" name="Holder">
                <eGenericSuperTypes eClassifier="#//Base"/>
                <eStructuralFeatures xsi:type="ecore:EReference" name="items" upperBound="-1">
                  <eGenericType eClassifier="#//Base"/>
                </eStructuralFeatures>
              </eClassifiers>
            """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let resource = try await XMIParser().parse(url)
        let base = try await element("//Base", in: resource)
        let holder = try await element("//Holder", in: resource)
        #expect(identifiers(holder.eGet("eSuperTypes")) == [base.id])
        let items = try await element("//Holder/items", in: resource)
        #expect(identifiers(items.eGet("eType")) == [base.id])
    }
}
