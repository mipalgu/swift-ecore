//
// WindowsURIReferenceTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Testing

@testable import ECore

@Suite("Windows file URI references")
struct WindowsURIReferenceTests {
    private let base = "file:///C:/models/a/library.genmodel"

    @Test("a relative reference resolves within the drive of the base")
    func resolvesWithinDrive() {
        #expect(URIReference.resolve("library.ecore", against: base) == "file:///C:/models/a/library.ecore")
        #expect(URIReference.resolve("../b/x.ecore", against: base) == "file:///C:/models/b/x.ecore")
    }

    @Test("a reference cannot ascend above the drive")
    func doesNotAscendAboveDrive() {
        #expect(URIReference.resolve("../../../../x.ecore", against: base) == "file:///C:/x.ecore")
    }

    @Test("a drive-lettered path is absolute, not a scheme")
    func driveIsNotScheme() {
        #expect(URIReference.resolve("D:/other/x.ecore", against: base) == "D:/other/x.ecore")
        #expect(URIReference.resolve("C:/x.ecore", against: "C:/models/a.genmodel") == "C:/x.ecore")
    }

    @Test("targets are relativised against a base on the same drive")
    func relativisesOnSameDrive() {
        #expect(URIReference.relativise("file:///C:/models/a/library.ecore", against: base) == "library.ecore")
        #expect(URIReference.relativise("file:///C:/models/b/x.ecore", against: base) == "../b/x.ecore")
    }

    @Test("a single-letter scheme is treated as a drive in a bare path")
    func bareDrivePathsRelativise() {
        #expect(URIReference.relativise("/C:/m/b/x.ecore", against: "/C:/m/a/y.ecore") == "../b/x.ecore")
    }

    @Test("canonical file URIs collapse empty and dot segments")
    func canonicalisesFileURIs() {
        #expect(
            URIReference.canonicalise("file:///C:/a//b/./c/../library.ecore")
                == "file:///C:/a/b/library.ecore")
        #expect(URIReference.canonicalise("file:///c:/a/x.ecore") == "file:///C:/a/x.ecore")
        #expect(URIReference.canonicalise("file:///tmp/Resources//x.ecore") == "file:///tmp/Resources/x.ecore")
    }

    @Test("canonicalisation leaves other URIs unchanged")
    func canonicalisationIgnoresOtherURIs() {
        for uri in ["http://example.com/a//b", "test://simple", "platform:/resource/p//m.ecore", "relative//x", ""] {
            #expect(URIReference.canonicalise(uri) == uri)
        }
    }

    @Test("a document reached by two spellings is one resource")
    func spellingsShareOneResource() async {
        let resourceSet = ResourceSet()
        let first = await resourceSet.createResource(uri: "file:///C:/m//a.ecore")
        let second = await resourceSet.createResource(uri: "file:///C:/m/a.ecore")
        #expect(first === second)
        #expect(first.uri == "file:///C:/m/a.ecore")
    }
}
