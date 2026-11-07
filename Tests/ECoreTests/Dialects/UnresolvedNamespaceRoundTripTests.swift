//
// UnresolvedNamespaceRoundTripTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that objects of classes that no registered metamodel defines are not written in
/// the Ecore namespace when a class is named like an Ecore metaclass, and that stereotype
/// applications of a UML model keep the namespace of their profile.
@Suite("Objects of unresolved namespaces")
struct UnresolvedNamespaceRoundTripTests {
    /// The namespace of the profile that the tagged fixture applies but does not contain.
    static let taggingProfile = "http:///schemas/Tagging/_t1/0"

    /// The namespace of the instance document that no metamodel defines.
    static let notesNamespace = "http://example.org/notes"

    /// An instance document whose classes no registered metamodel defines.
    static let notesDocument = """
        <?xml version="1.0" encoding="UTF-8"?>
        <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:notes="\(notesNamespace)">
          <notes:EClass title="Reminder"/>
          <notes:Note title="Shopping"/>
        </xmi:XMI>
        """

    /// The names of the classes of the objects of a resource, with their counts.
    static func classCounts(in resource: Resource) async -> [String: Int] {
        var counts: [String: Int] = [:]
        for object in await resource.getAllObjects() { counts[object.eClass.name, default: 0] += 1 }
        return counts
    }

    @Test("A stereotype application without its profile is written in the namespace of the profile")
    func stereotypeApplicationKeepsProfileNamespace() async throws {
        let url = OMGXMIDialectTests.directory.appendingPathComponent("garden-tagged.uml")
        let read = try await UMLFormat.read(url: url, resourceSet: ResourceSet())
        #expect(read.diagnostics.contains { $0.code == ModelDocumentDiagnostic.unresolvedProfile })
        let written = try await UMLFormat.write(read.resource, relativeTo: url)
        #expect(written.text.contains("xmlns:Tagging=\"\(Self.taggingProfile)\""))
        #expect(written.text.contains("<Tagging:EPackage "))
        #expect(written.text.contains("<Tagging:EDataType "))
        #expect(written.text.contains("<Tagging:Seasonal "))
        #expect(!written.text.contains("<ecore:EPackage "))
        let reread = try await UMLFormat.read(
            data: Data(written.text.utf8), uri: url.absoluteString + ".copy", resourceSet: ResourceSet())
        let counts = await Self.classCounts(in: read.resource)
        let rereadCounts = await Self.classCounts(in: reread.resource)
        #expect(rereadCounts == counts)
    }

    @Test("An object of an unknown namespace named like an Ecore metaclass round-trips as XMI")
    func unknownNamespaceKeepsItsPrefix() async throws {
        let parser = XMIParser(resourceSet: ResourceSet())
        let resource = try await parser.parse(Data(Self.notesDocument.utf8), uri: "memory:/notes.xmi")
        let roots = await resource.getRootObjects()
        #expect(roots.map { $0.eClass.name } == ["EClass", "Note"])
        let text = try await XMISerializer(options: .emf).serialize(resource)
        #expect(text.contains("xmlns:notes=\"\(Self.notesNamespace)\""))
        #expect(text.contains("<notes:EClass "))
        #expect(!text.contains("<ecore:EClass"))
        let reread = try await XMIParser(resourceSet: ResourceSet())
            .parse(Data(text.utf8), uri: "memory:/notes-copy.xmi")
        let counts = await Self.classCounts(in: resource)
        let rereadCounts = await Self.classCounts(in: reread)
        #expect(rereadCounts == counts)
        let rereadRoots = await reread.getRootObjects()
        let first = try #require(rereadRoots.first)
        let title = await reread.eGet(objectId: first.id, feature: "title") as? String
        #expect(title == "Reminder")
    }
}
