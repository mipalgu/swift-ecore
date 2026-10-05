//
// EclipseGenModelOracleTests.swift
// GenModelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import Testing

@testable import GenModel

@Suite(
    "Eclipse-written generator models",
    .enabled(if: EclipseOracle.isAvailable, Comment(rawValue: EclipseOracle.skipNotice)))
struct EclipseGenModelOracleTests {
    @Test(
        "a loaded and saved generator model equals the original bytes",
        arguments: EclipseOracle.files(withExtension: "genmodel"))
    func roundTrip(relativePath: String) async throws {
        let root = try #require(EclipseOracle.root)
        let url = root.appendingPathComponent(relativePath)
        let original = EclipseOracle.normalised(try String(contentsOf: url, encoding: .utf8))
        let resourceSet = ResourceSet()
        let document = try await GenModelResource.loadDocument(
            url: url, resourceSet: resourceSet, resolution: .nameFragments)
        let written = try await GenModelResource.serialised(
            document.resource, for: url, rootLayout: XMIRootLayout.detect(in: original))
        if written != original { EclipseOracle.recordFailure(written, for: relativePath) }
        #expect(written == original)
    }
}

@Suite(
    "Eclipse-written metamodels",
    .enabled(if: EclipseOracle.isAvailable, Comment(rawValue: EclipseOracle.skipNotice)))
struct EclipseEcoreOracleTests {
    @Test(
        "a loaded and saved metamodel equals the original bytes",
        arguments: EclipseOracle.files(withExtension: "ecore"))
    func roundTrip(relativePath: String) async throws {
        let root = try #require(EclipseOracle.root)
        let url = root.appendingPathComponent(relativePath)
        let original = EclipseOracle.normalised(try String(contentsOf: url, encoding: .utf8))
        let resourceSet = ResourceSet()
        let resource = try await resourceSet.loadEcoreResource(
            uri: URIReference.canonicalise(url.absoluteString))
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        let width = XMISerializationOptions.emfLineWidth
        let options = XMISerializationOptions(
            lineWidth: width, rootLayout: XMIRootLayout.detect(in: original))
        let written = XMISerializer(options: options)
            .serialize(package, relativeTo: url)
        if written != original { EclipseOracle.recordFailure(written, for: relativePath) }
        #expect(written == original)
    }
}
