//
// OppositeFragmentTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that `eOpposite` accepts every same-document reference form that `eType` accepts.
///
/// EMF treats a reference token without `#` as a reference into the same document and
/// resolves it as a fragment or identifier, so `/0/Class/feature`, `#/0/Class/feature`,
/// `//Class/feature` and a bare `xmi:id` all name the same reference.
@Suite("Opposite reference fragments")
struct OppositeFragmentTests {
    /// A document with two root packages whose references name their opposites in every form.
    private static let twoRoots = """
    <?xml version="1.0" encoding="UTF-8"?>
    <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore">
      <ecore:EPackage name="Types">
        <eClassifiers xsi:type="ecore:EDataType" name="Text"/>
      </ecore:EPackage>
      <ecore:EPackage name="Garden" nsURI="http://example.org/garden" nsPrefix="garden">
        <eClassifiers xsi:type="ecore:EClass" name="Bed">
          <eStructuralFeatures xsi:type="ecore:EAttribute" name="label" eType="/0/Text"/>
          <eStructuralFeatures xsi:type="ecore:EReference" name="plants" upperBound="-1" \
    eType="/1/Plant" containment="true" eOpposite="/1/Plant/bed"/>
          <eStructuralFeatures xsi:type="ecore:EReference" name="gardener" eType="/1/Gardener" \
    eOpposite="#/1/Gardener/beds"/>
          <eStructuralFeatures xsi:type="ecore:EReference" name="neighbour" eType="/1/Bed" \
    eOpposite="g7"/>
          <eStructuralFeatures xsi:type="ecore:EReference" xmi:id="g7" name="neighbourOf" eType="/1/Bed" \
    eOpposite="/1/Bed/neighbour"/>
        </eClassifiers>
        <eClassifiers xsi:type="ecore:EClass" name="Plant">
          <eStructuralFeatures xsi:type="ecore:EReference" name="bed" eType="/1/Bed" eOpposite="/1/Bed/plants"/>
        </eClassifiers>
        <eClassifiers xsi:type="ecore:EClass" name="Gardener">
          <eStructuralFeatures xsi:type="ecore:EReference" name="beds" upperBound="-1" eType="/1/Bed" \
    eOpposite="/1/Bed/gardener"/>
        </eClassifiers>
      </ecore:EPackage>
    </xmi:XMI>
    """

    /// A single package whose references name their opposites by fragment paths without `#`.
    private static let singleRoot = """
    <?xml version="1.0" encoding="UTF-8"?>
    <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" \
    name="pond" nsURI="http://example.org/pond" nsPrefix="pond">
      <eClassifiers xsi:type="ecore:EClass" name="Pond">
        <eStructuralFeatures xsi:type="ecore:EReference" name="fish" upperBound="-1" eType="//Fish" \
    containment="true" eOpposite="//Fish/pond"/>
      </eClassifiers>
      <eClassifiers xsi:type="ecore:EClass" name="Fish">
        <eStructuralFeatures xsi:type="ecore:EReference" name="pond" eType="//Pond" eOpposite="#//Pond/fish"/>
      </eClassifiers>
    </ecore:EPackage>
    """

    /// Loads a document and returns the classes of all of its root packages by name.
    private static func classes(in text: String, uri: String) async throws -> [String: EClass] {
        let resource = try await ResourceSet().loadEcoreResource(text: text, uri: uri)
        let packages = await resource.getRootObjects().compactMap { $0 as? EPackage }
        return Dictionary(
            packages.flatMap(\.eClassifiers).compactMap { $0 as? EClass }.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first })
    }

    /// The name of the opposite of a reference, found among the references of the given classes.
    private static func oppositeName(of reference: String, in eClass: EClass?, classes: [String: EClass]) -> String? {
        guard let opposite = eClass?.eReferences.first(where: { $0.name == reference })?.opposite else { return nil }
        return classes.values.flatMap(\.eReferences).first { $0.id == opposite }?.name
    }

    @Test("a root path without # resolves an opposite in a document with several roots")
    func rootPathWithoutHash() async throws {
        let classes = try await Self.classes(in: Self.twoRoots, uri: "memory:/garden.ecore")
        #expect(Self.oppositeName(of: "plants", in: classes["Bed"], classes: classes) == "bed")
        #expect(Self.oppositeName(of: "bed", in: classes["Plant"], classes: classes) == "plants")
        #expect(Self.oppositeName(of: "beds", in: classes["Gardener"], classes: classes) == "gardener")
        #expect(Self.oppositeName(of: "neighbourOf", in: classes["Bed"], classes: classes) == "neighbour")
    }

    @Test("a root path with # and a bare identifier resolve an opposite")
    func hashAndIdentifier() async throws {
        let classes = try await Self.classes(in: Self.twoRoots, uri: "memory:/garden.ecore")
        #expect(Self.oppositeName(of: "gardener", in: classes["Bed"], classes: classes) == "beds")
        #expect(Self.oppositeName(of: "neighbour", in: classes["Bed"], classes: classes) == "neighbourOf")
    }

    @Test("a containment opposite marks the reference as a container reference")
    func containerFlag() async throws {
        let classes = try await Self.classes(in: Self.twoRoots, uri: "memory:/garden.ecore")
        let bed = try #require(classes["Plant"]?.eReferences.first { $0.name == "bed" })
        #expect(bed.container)
    }

    @Test("a fragment path without # resolves an opposite in a single-root document")
    func singleRootPathWithoutHash() async throws {
        let classes = try await Self.classes(in: Self.singleRoot, uri: "memory:/pond.ecore")
        #expect(Self.oppositeName(of: "fish", in: classes["Pond"], classes: classes) == "pond")
        #expect(Self.oppositeName(of: "pond", in: classes["Fish"], classes: classes) == "fish")
    }

    @Test("an opposite in another document still becomes a reference to that document")
    func otherDocument() async throws {
        let parser = XMIParser()
        let text = Self.singleRoot.replacingOccurrences(
            of: "eOpposite=\"#//Pond/fish\"", with: "eOpposite=\"lake.ecore#//Lake/fish\"")
        let resource = try await parser.parse(text, uri: "file:///models/pond.ecore")
        let references = await resource.getAllObjects().compactMap { $0 as? DynamicEObject }
            .filter { $0.eGet("name") as? String == "pond" && $0.eClass.name == "EReference" }
        let proxy = try #require(references.first?.eGet(XMIAttribute.eOpposite.rawValue) as? ResourceProxy)
        #expect(proxy.uri == "file:///models/lake.ecore")
        #expect(proxy.fragment == "//Lake/fish")
    }
}
