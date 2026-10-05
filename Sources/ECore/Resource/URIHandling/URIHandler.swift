//
// URIHandler.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// Reads and writes the documents that URIs name.
///
/// A resource set asks its handlers, in order, for the first one that can handle a URI and
/// uses it to read documents (for loading, including documents that other documents refer
/// to) and to write them (for saving). Hosts without a file system, such as sandboxed
/// applications and browsers, install handlers that serve documents from memory or from
/// their own storage.
///
/// Handlers receive the physical URI: the URI after the mappings of the resource set have
/// been applied.
public protocol URIHandler: Sendable {
    /// Whether this handler serves the URI.
    ///
    /// - Parameter uri: The physical URI of a document.
    /// - Returns: `true` if this handler reads and writes the document.
    func canHandle(_ uri: String) -> Bool

    /// Reads the document that a URI names.
    ///
    /// - Parameter uri: The physical URI of the document.
    /// - Returns: The bytes of the document.
    /// - Throws: An error if the document cannot be read.
    func read(_ uri: String) async throws -> Data

    /// Writes the document that a URI names.
    ///
    /// - Parameters:
    ///   - data: The bytes of the document.
    ///   - uri: The physical URI of the document.
    /// - Throws: An error if the document cannot be written.
    func write(_ data: Data, to uri: String) async throws

    /// Whether the document that a URI names exists.
    ///
    /// - Parameter uri: The physical URI of the document.
    /// - Returns: `true` if the document can be read.
    func exists(_ uri: String) async -> Bool
}

/// The ways in which reading and writing through URI handlers fails.
public enum URIHandlerError: Error, Sendable, Equatable {
    /// The URI is not a valid location for the handler.
    case invalidURI(String)

    /// No document exists at the URI.
    case notFound(String)

    /// The handler failed to read the document at the URI.
    ///
    /// The associated values are the URI and a description of the underlying failure.
    case readFailed(String, String)

    /// The handler failed to write the document at the URI.
    ///
    /// The associated values are the URI and a description of the underlying failure.
    case writeFailed(String, String)
}

// MARK: - File handler

/// Reads and writes documents in the file system.
///
/// This is the handler that a resource set falls back to when no installed handler serves a
/// URI. It handles URIs without a scheme and `file:` URIs, and it reads any other
/// well-formed URL in the way that `Data(contentsOf:)` does, so that it behaves as loading
/// has always behaved.
public struct FileURIHandler: URIHandler {
    /// The scheme of file URIs.
    public static let scheme = "file"

    /// Creates a file handler.
    public init() {}

    /// Whether the URI is a file URI or has no scheme.
    ///
    /// - Parameter uri: The URI to test.
    /// - Returns: `true` for `file:` URIs and URIs without a scheme.
    public func canHandle(_ uri: String) -> Bool {
        guard let scheme = URL(string: uri)?.scheme else { return true }
        return scheme.lowercased() == Self.scheme
    }

    /// Reads a file.
    ///
    /// - Parameter uri: The URI of the file.
    /// - Returns: The contents of the file.
    /// - Throws: ``URIHandlerError/invalidURI(_:)`` if the URI is malformed, or the error
    ///   that reading the file raises.
    public func read(_ uri: String) async throws -> Data {
        try Data(contentsOf: try location(of: uri))
    }

    /// Writes a file atomically.
    ///
    /// - Parameters:
    ///   - data: The contents of the file.
    ///   - uri: The URI of the file.
    /// - Throws: ``URIHandlerError/invalidURI(_:)`` if the URI is malformed, or the error
    ///   that writing the file raises.
    public func write(_ data: Data, to uri: String) async throws {
        try data.write(to: try location(of: uri), options: .atomic)
    }

    /// Whether a file exists.
    ///
    /// - Parameter uri: The URI of the file.
    /// - Returns: `true` if a file exists at the URI.
    public func exists(_ uri: String) async -> Bool {
        guard let url = try? location(of: uri), url.isFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// The location that a URI names.
    private func location(of uri: String) throws -> URL {
        guard let url = URL(string: uri) else { throw URIHandlerError.invalidURI(uri) }
        return url
    }
}

// MARK: - In-memory handler

/// Serves documents from a dictionary held in memory.
///
/// Tests, browsers, and sandboxed applications seed the handler with the text of their
/// documents and load models from them without touching the file system. Writing a
/// document stores it in the dictionary.
public actor InMemoryURIHandler: URIHandler {
    /// The scheme that this handler is restricted to, or `nil` if it serves every URI.
    public nonisolated let scheme: String?

    /// The documents, by URI.
    private var documents: [String: Data]

    /// Creates a handler.
    ///
    /// - Parameters:
    ///   - documents: The initial documents, by URI.
    ///   - scheme: The scheme of the URIs that the handler serves (for example `memory`),
    ///     or `nil` (the default) to serve every URI. A handler that serves every URI
    ///     reports a missing document as ``URIHandlerError/notFound(_:)`` instead of
    ///     leaving it to the next handler.
    public init(documents: [String: Data] = [:], scheme: String? = nil) {
        self.documents = documents
        self.scheme = scheme
    }

    /// Creates a handler from the text of its documents.
    ///
    /// - Parameters:
    ///   - texts: The initial documents as UTF-8 text, by URI.
    ///   - scheme: The scheme of the URIs that the handler serves, or `nil` for all.
    public init(texts: [String: String], scheme: String? = nil) {
        self.init(documents: texts.mapValues { Data($0.utf8) }, scheme: scheme)
    }

    /// Whether the handler serves the URI.
    ///
    /// - Parameter uri: The URI to test.
    /// - Returns: `true` if the handler has no scheme restriction or the URI has its scheme.
    public nonisolated func canHandle(_ uri: String) -> Bool {
        guard let scheme else { return true }
        return URL(string: uri)?.scheme?.lowercased() == scheme.lowercased()
    }

    /// Reads a document.
    ///
    /// - Parameter uri: The URI of the document.
    /// - Returns: The bytes of the document.
    /// - Throws: ``URIHandlerError/notFound(_:)`` if there is no such document.
    public func read(_ uri: String) async throws -> Data {
        guard let data = documents[uri] else { throw URIHandlerError.notFound(uri) }
        return data
    }

    /// Stores a document, replacing any document at the URI.
    ///
    /// - Parameters:
    ///   - data: The bytes of the document.
    ///   - uri: The URI of the document.
    public func write(_ data: Data, to uri: String) async {
        documents[uri] = data
    }

    /// Whether a document exists.
    ///
    /// - Parameter uri: The URI of the document.
    /// - Returns: `true` if the handler holds a document at the URI.
    public func exists(_ uri: String) async -> Bool {
        documents[uri] != nil
    }

    /// The URIs of the documents held, in ascending order.
    public var uris: [String] {
        documents.keys.sorted()
    }

    /// Stores a document from text.
    ///
    /// - Parameters:
    ///   - text: The UTF-8 text of the document.
    ///   - uri: The URI of the document.
    public func set(_ text: String, for uri: String) {
        documents[uri] = Data(text.utf8)
    }

    /// The text of a document.
    ///
    /// - Parameter uri: The URI of the document.
    /// - Returns: The document decoded as UTF-8, or `nil` if there is no such document or it
    ///   is not valid UTF-8.
    public func text(for uri: String) -> String? {
        documents[uri].flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Removes a document.
    ///
    /// - Parameter uri: The URI of the document.
    public func remove(_ uri: String) {
        documents.removeValue(forKey: uri)
    }
}

// MARK: - Closure handler

/// Delegates reading, writing, and existence checks to closures that a host supplies.
///
/// A host that stores documents somewhere else (a database, a document picker, the network
/// of a browser) supplies closures instead of implementing the protocol.
public struct ClosureURIHandler: URIHandler {
    /// The closure that tells whether the handler serves a URI.
    private let handles: @Sendable (String) -> Bool

    /// The closure that reads a document.
    private let reader: @Sendable (String) async throws -> Data

    /// The closure that writes a document.
    private let writer: @Sendable (Data, String) async throws -> Void

    /// The closure that tells whether a document exists.
    private let existence: @Sendable (String) async -> Bool

    /// Creates a handler from closures.
    ///
    /// - Parameters:
    ///   - canHandle: Whether the handler serves a URI (default: every URI).
    ///   - read: Reads a document.
    ///   - write: Writes a document (default: fails with ``URIHandlerError/writeFailed(_:_:)``).
    ///   - exists: Whether a document exists (default: tries to read it).
    public init(
        canHandle: @escaping @Sendable (String) -> Bool = { _ in true },
        read: @escaping @Sendable (String) async throws -> Data,
        write: (@Sendable (Data, String) async throws -> Void)? = nil,
        exists: (@Sendable (String) async -> Bool)? = nil
    ) {
        handles = canHandle
        reader = read
        writer =
            write ?? { _, uri in throw URIHandlerError.writeFailed(uri, "Writing is not supported") }
        existence = exists ?? { uri in (try? await read(uri)) != nil }
    }

    /// Whether the handler serves the URI.
    ///
    /// - Parameter uri: The URI to test.
    /// - Returns: The answer of the supplied closure.
    public func canHandle(_ uri: String) -> Bool { handles(uri) }

    /// Reads a document with the supplied closure.
    ///
    /// - Parameter uri: The URI of the document.
    /// - Returns: The bytes of the document.
    /// - Throws: The error that the closure throws.
    public func read(_ uri: String) async throws -> Data { try await reader(uri) }

    /// Writes a document with the supplied closure.
    ///
    /// - Parameters:
    ///   - data: The bytes of the document.
    ///   - uri: The URI of the document.
    /// - Throws: The error that the closure throws.
    public func write(_ data: Data, to uri: String) async throws { try await writer(data, uri) }

    /// Whether a document exists, according to the supplied closure.
    ///
    /// - Parameter uri: The URI of the document.
    /// - Returns: The answer of the closure.
    public func exists(_ uri: String) async -> Bool { await existence(uri) }
}
