//
// SerialiserReferenceTests.swift
// ECoreTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Tests for how the legacy and EMF writers serialise proxies, many-valued references,
/// and many-valued attributes.
@Suite("Serialiser Reference and Many-Valued Tests")
struct SerialiserReferenceTests {
    /// The namespace URI that the legacy writer derives for the `Club` class.
    private static let clubNamespace = "http://swift-modelling.org/test/club"

    private static func makeMetamodel() -> EPackage {
        let string = EcorePackage.dataType(.eString) ?? EDataType(name: "EString")
        let int = EcorePackage.dataType(.eInt) ?? EDataType(name: "EInt")
        let person = EClass(
            name: "Person",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EAttribute(name: "tags", eType: string, upperBound: -1),
                EAttribute(name: "scores", eType: int, upperBound: -1),
            ])
        var personWithReferences = person
        personWithReferences.eStructuralFeatures.append(
            EReference(name: "partner", eType: person))
        personWithReferences.eStructuralFeatures.append(
            EReference(name: "friends", eType: person, upperBound: -1))
        let club = EClass(
            name: "Club",
            eStructuralFeatures: [
                EReference(name: "members", eType: personWithReferences, upperBound: -1, containment: true),
                EReference(name: "sponsor", eType: personWithReferences),
                EReference(name: "alumni", eType: personWithReferences, upperBound: -1),
            ])
        return EPackage(
            name: "club", nsURI: clubNamespace, nsPrefix: "club",
            eClassifiers: [club, personWithReferences])
    }

    /// Builds a club with three members and returns the resource and the object identifiers.
    private func makeClub(
        configure: (inout DynamicEObject, [DynamicEObject]) -> Void
    ) async throws -> (set: ResourceSet, resource: Resource, members: [EUUID]) {
        let set = ResourceSet()
        let package = Self.makeMetamodel()
        await set.registerMetamodel(package, uri: package.nsURI)
        let personClass = try #require(package.getEClass("Person"))
        var people = (0..<3).map { index -> DynamicEObject in
            var person = DynamicEObject(eClass: personClass)
            person.eSet("name", value: "person\(index)")
            return person
        }
        var club = DynamicEObject(eClass: try #require(package.getEClass("Club")))
        configure(&club, people)
        people[0].eSet("tags", value: ["alpha", "beta & gamma"])
        people[0].eSet("scores", value: [3, 5, 8])
        club.eSet("members", value: people.map(\.id))
        let resource = await set.createResource(uri: "file:///club.xmi")
        for person in people { await resource.register(person) }
        await resource.add(club)
        return (set, resource, people.map(\.id))
    }

    // MARK: Legacy writer

    @Test("a proxy is written as an href and not as an attribute")
    func legacyProxy() async throws {
        let (_, resource, _) = try await makeClub { club, _ in
            club.eSet(
                "sponsor", value: ResourceProxy(uri: "other.xmi", fragment: "//@members.0"))
        }
        let text = try await XMISerializer().serialize(resource)
        #expect(text.contains("<sponsor href=\"other.xmi#//@members.0\"/>"))
        #expect(!text.contains("ResourceProxy"))
        #expect(!text.contains("sponsor=\""))
    }

    @Test("a proxy on a contained element is written as an href and not as an attribute")
    func legacyProxyOnChild() async throws {
        let set = ResourceSet()
        let package = Self.makeMetamodel()
        await set.registerMetamodel(package, uri: package.nsURI)
        var person = DynamicEObject(eClass: try #require(package.getEClass("Person")))
        person.eSet("name", value: "alone")
        person.eSet("partner", value: ResourceProxy(uri: "other.xmi", fragment: "//@members.2"))
        var club = DynamicEObject(eClass: try #require(package.getEClass("Club")))
        club.eSet("members", value: [person.id])
        let resource = await set.createResource(uri: "file:///single.xmi")
        await resource.register(person)
        await resource.add(club)
        let text = try await XMISerializer().serialize(resource)
        #expect(text.contains("<partner href=\"other.xmi#//@members.2\"/>"))
        #expect(!text.contains("ResourceProxy"))
        #expect(!text.contains("partner=\""))
    }

    @Test("many-valued proxies are written as one href each, in order")
    func legacyManyProxies() async throws {
        let (_, resource, _) = try await makeClub { club, _ in
            club.eSet(
                "alumni",
                value: [
                    ResourceProxy(uri: "other.xmi", fragment: "//@members.1"),
                    ResourceProxy(uri: "other.xmi", fragment: "//@members.0"),
                ])
        }
        let text = try await XMISerializer().serialize(resource)
        let first = try #require(text.range(of: "<alumni href=\"other.xmi#//@members.1\"/>"))
        let second = try #require(text.range(of: "<alumni href=\"other.xmi#//@members.0\"/>"))
        #expect(first.lowerBound < second.lowerBound)
        #expect(!text.contains("alumni=\""))
        #expect(!text.contains("ResourceProxy"))
    }

    @Test("many-valued same-document references are written as one href each")
    func legacyManyLocalReferences() async throws {
        let (_, resource, members) = try await makeClub { club, people in
            club.eSet("alumni", value: [people[2].id, people[0].id])
        }
        #expect(members.count == 3)
        let text = try await XMISerializer().serialize(resource)
        let first = try #require(text.range(of: "<alumni href=\"#//@members.2\"/>"))
        let second = try #require(text.range(of: "<alumni href=\"#//@members.0\"/>"))
        #expect(first.lowerBound < second.lowerBound)
    }

    @Test("many-valued attributes are written as one child element per value")
    func legacyManyAttributes() async throws {
        let (_, resource, _) = try await makeClub { _, _ in }
        let text = try await XMISerializer().serialize(resource)
        #expect(text.contains("<tags>alpha</tags>"))
        #expect(text.contains("<tags>beta &amp; gamma</tags>"))
        #expect(text.contains("<scores>3</scores>"))
        #expect(text.contains("<scores>8</scores>"))
        #expect(!text.contains("tags=\""))
        #expect(!text.contains("scores=\""))
        #expect(!text.contains("[\""))
    }

    @Test("legacy output with many-valued values loads back unchanged")
    func legacyRoundTrip() async throws {
        let (set, resource, _) = try await makeClub { club, people in
            club.eSet("alumni", value: [people[1].id, people[2].id])
        }
        let text = try await XMISerializer().serialize(resource)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("club.xmi")
        try text.write(to: url, atomically: true, encoding: .utf8)
        let reloaded = try await set.loadXMIResource(uri: url.absoluteString)
        let root = try #require(await reloaded.getRootObjects().first as? DynamicEObject)
        let members = try #require(root.eGet("members") as? [EUUID])
        #expect(members.count == 3)
        let first = try #require(await reloaded.resolve(members[0]) as? DynamicEObject)
        #expect(first.eGet("tags") as? [String] == ["alpha", "beta & gamma"])
        #expect(first.eGet("scores") as? [Int] == [3, 5, 8])
        #expect((root.eGet("alumni") as? [EUUID])?.count == 2)
    }

    // MARK: EMF writer

    @Test("the EMF writer writes proxies and many-valued references without junk attributes")
    func emfReferences() async throws {
        let (_, resource, _) = try await makeClub { club, people in
            club.eSet("sponsor", value: ResourceProxy(uri: "other.xmi", fragment: "//@members.0"))
            club.eSet(
                "alumni",
                value: [
                    ResourceProxy(uri: "other.xmi", fragment: "//@members.1"),
                    ResourceProxy(uri: "other.xmi", fragment: "//@members.2"),
                ])
        }
        let text = try await XMISerializer(options: .emf).serialize(resource)
        #expect(!text.contains("ResourceProxy"))
        #expect(text.contains("sponsor=\"other.xmi#//@members.0\""))
        #expect(text.contains("alumni=\"other.xmi#//@members.1 other.xmi#//@members.2\""))
    }

    @Test("the EMF writer writes many-valued same-document references")
    func emfLocalReferences() async throws {
        let (_, resource, _) = try await makeClub { club, people in
            club.eSet("alumni", value: [people[2].id, people[0].id])
        }
        let text = try await XMISerializer(options: .emf).serialize(resource)
        #expect(text.contains("alumni=\"#//@members.2 #//@members.0\""))
    }

    @Test("the EMF writer writes many-valued attributes as child elements")
    func emfManyAttributes() async throws {
        let (_, resource, _) = try await makeClub { _, _ in }
        let text = try await XMISerializer(options: .emf).serialize(resource)
        #expect(text.contains("<tags>alpha</tags>"))
        #expect(text.contains("<tags>beta &amp; gamma</tags>"))
        #expect(text.contains("<scores>5</scores>"))
        let joined = XMISerializationOptions(attributeStyleReferences: true)
        let attributeText = try await XMISerializer(options: joined).serialize(resource)
        #expect(attributeText.contains("tags=\"alpha beta &amp; gamma\""))
    }
}
