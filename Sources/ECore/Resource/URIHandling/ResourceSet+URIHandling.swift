//
// ResourceSet+URIHandling.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

extension ResourceSet {
    /// Installs the handlers that read and write the documents of this set.
    ///
    /// For each URI the first handler that can handle it is used. URIs that no handler
    /// serves are handled by a ``FileURIHandler``, which is also what a set without
    /// installed handlers uses for every URI.
    ///
    /// - Parameter handlers: The handlers, in order of precedence.
    public func setURIHandlers(_ handlers: [any URIHandler]) {
        installedURIHandlers = handlers
    }

    /// The installed handlers, in order of precedence.
    ///
    /// The file handler that serves URIs that no installed handler serves is not included.
    public var uriHandlers: [any URIHandler] {
        installedURIHandlers
    }

    /// The handler that serves a physical URI.
    ///
    /// - Parameter uri: The physical URI.
    /// - Returns: The first installed handler that can handle the URI, or a file handler.
    func uriHandler(for uri: String) -> any URIHandler {
        installedURIHandlers.first { $0.canHandle(uri) } ?? FileURIHandler()
    }

    /// Reads a document through the handler chain.
    ///
    /// The URI is mapped to its physical form (see ``convertURI(_:)``) before a handler is
    /// chosen. Errors of file handlers are passed on unchanged; the errors of other
    /// handlers are reported as ``URIHandlerError/readFailed(_:_:)`` with the URI.
    ///
    /// - Parameter uri: The logical URI of the document.
    /// - Returns: The bytes of the document.
    /// - Throws: ``URIHandlerError`` or the error of a file read.
    func readDocument(uri: String) async throws -> Data {
        let physical = convertURI(uri)
        let handler = uriHandler(for: physical)
        do {
            return try await handler.read(physical)
        } catch let error as URIHandlerError {
            throw error
        } catch {
            if handler is FileURIHandler { throw error }
            throw URIHandlerError.readFailed(physical, String(describing: error))
        }
    }

    /// Writes a document through the handler chain.
    ///
    /// - Parameters:
    ///   - data: The bytes of the document.
    ///   - uri: The logical URI of the document.
    /// - Throws: ``URIHandlerError`` or the error of a file write.
    func writeDocument(_ data: Data, to uri: String) async throws {
        let physical = convertURI(URIReference.canonicalise(uri))
        let handler = uriHandler(for: physical)
        do {
            try await handler.write(data, to: physical)
        } catch let error as URIHandlerError {
            throw error
        } catch {
            if handler is FileURIHandler { throw error }
            throw URIHandlerError.writeFailed(physical, String(describing: error))
        }
    }

    /// Whether the document that a URI names exists.
    ///
    /// - Parameter uri: The logical URI of the document.
    /// - Returns: `true` if the handler that serves the URI reports that it exists.
    public func documentExists(uri: String) async -> Bool {
        let physical = convertURI(URIReference.canonicalise(uri))
        return await uriHandler(for: physical).exists(physical)
    }

    // MARK: - Loading from text

    /// Loads an Ecore document from text as native metamodel objects.
    ///
    /// This behaves like ``loadEcoreResource(uri:)`` for a document whose text the caller
    /// holds, which may be an `.ecore` document or a JSON metamodel. References to other
    /// documents are resolved through the installed handlers. A resource that is already
    /// loaded under the URI is returned unchanged.
    ///
    /// - Parameters:
    ///   - text: The text of the `.ecore` document or JSON metamodel.
    ///   - uri: The URI that the document has.
    /// - Returns: The resource holding the native package as its root object.
    /// - Throws: ``XMIError`` if the document cannot be parsed or has no root package, or
    ///   ``JSONError`` if a JSON document is not a well-formed metamodel.
    public func loadEcoreResource(text: String, uri: String) async throws -> Resource {
        try await loadEcoreResource(text: text, uri: uri, options: EcoreLoadOptions())
    }

    /// Loads native Ecore packages from text with explicit loading policies.
    ///
    /// References to other documents resolve through the resource set's URI handlers.
    /// A previously loaded resource is returned unchanged.
    ///
    /// - Parameters:
    ///   - text: The document text.
    ///   - uri: The URI used to resolve relative references.
    ///   - options: The policies for unresolved references and incomplete elements.
    /// - Returns: The resource containing every root package and load diagnostics.
    /// - Throws: ``XMIError`` if the document cannot be parsed or converted.
    public func loadEcoreResource(text: String, uri: String, options: EcoreLoadOptions) async throws -> Resource {
        try await loadEcoreResource(
            data: Data(text.utf8), uri: URIReference.canonicalise(uri), enableDebugging: false, options: options)
    }

    /// Loads an XMI document from text.
    ///
    /// This behaves like ``loadXMIResource(uri:referenceParsing:)`` for a document whose
    /// text the caller holds. A resource that is already loaded under the URI is returned
    /// unchanged.
    ///
    /// - Parameters:
    ///   - text: The text of the document.
    ///   - uri: The URI that the document has.
    ///   - referenceParsing: How reference attributes of registered metamodels are read
    ///     (default ``XMIReferenceParsing/interpreted``).
    /// - Returns: The loaded resource.
    /// - Throws: ``XMIError`` if parsing fails.
    public func loadXMIResource(
        text: String, uri documentURI: String, referenceParsing: XMIReferenceParsing = .interpreted
    ) async throws -> Resource {
        let uri = URIReference.canonicalise(documentURI)
        if let existing = resources[uri] {
            return existing
        }
        let parser = XMIParser(resourceSet: self, referenceParsing: referenceParsing)
        let resource = try await parser.parse(text, uri: uri)
        resources[uri] = resource
        return resource
    }

    /// Loads a JSON document from text.
    ///
    /// - Parameters:
    ///   - text: The text of the document.
    ///   - uri: The URI that the document has.
    /// - Returns: The loaded resource.
    /// - Throws: ``JSONError`` if parsing fails.
    public func loadJSONResource(text: String, uri documentURI: String) async throws -> Resource {
        let uri = URIReference.canonicalise(documentURI)
        if let existing = resources[uri] {
            return existing
        }
        let resource = try await JSONParser(resourceSet: self).parse(Data(text.utf8), uri: uri)
        resources[uri] = resource
        return resource
    }

    // MARK: - Saving

    /// Saves a resource as an XMI document through the handler chain.
    ///
    /// The document is the one that ``XMISerializer/serialize(_:to:)`` writes to a file. It is
    /// a copy: the resource keeps its URI. ``saveAs(_:to:options:)`` gives the resource the
    /// URI of the document instead.
    ///
    /// - Parameters:
    ///   - resource: The resource to save.
    ///   - uri: The URI of the document to write.
    ///   - options: The layout options (default ``XMISerializationOptions/legacy``).
    /// - Throws: ``XMIError`` if serialisation fails, or the error of the handler.
    public func save(
        _ resource: Resource, to uri: String, options: XMISerializationOptions = .legacy
    ) async throws {
        var diagnostics = ConversionDiagnostics()
        let text = try await XMISerializer(options: options).serialize(
            resource, documentURI: URIReference.canonicalise(uri), diagnostics: &diagnostics)
        try await writeDocument(Data(text.utf8), to: uri)
    }

    /// Saves a native metamodel package as an `.ecore` document through the handler chain.
    ///
    /// References to classifiers of other documents are written relative to the URI, as
    /// ``XMISerializer/serialize(_:to:)-(EPackage,URL)`` does for a file.
    ///
    /// - Parameters:
    ///   - package: The package to save.
    ///   - uri: The URI of the document to write.
    ///   - options: The layout options (default ``XMISerializationOptions/legacy``).
    /// - Throws: The error of the handler.
    public func save(
        _ package: EPackage, to uri: String, options: XMISerializationOptions = .legacy
    ) async throws {
        let serializer = XMISerializer(options: options)
        let text: String
        if let url = URL(string: URIReference.canonicalise(uri)) {
            text = serializer.serialize(package, relativeTo: url)
        } else {
            text = serializer.serialize(package)
        }
        try await writeDocument(Data(text.utf8), to: uri)
    }

    /// Saves a resource as a JSON document through the handler chain.
    ///
    /// The URIs of other documents are written relative to the URI of the document that is
    /// written, as ``JSONSerializer/serialize(_:relativeTo:)-(Resource,_)`` writes them. The
    /// document is a copy: the resource keeps its URI. ``saveJSONAs(_:to:)`` gives the
    /// resource the URI of the document instead.
    ///
    /// - Parameters:
    ///   - resource: The resource to save.
    ///   - uri: The URI of the document to write.
    /// - Throws: ``JSONError`` if serialisation fails, or the error of the handler.
    public func saveJSON(_ resource: Resource, to uri: String) async throws {
        var diagnostics = ConversionDiagnostics()
        let text = try await JSONSerializer().serialize(
            resource, documentURI: URIReference.canonicalise(uri), diagnostics: &diagnostics)
        try await writeDocument(Data(text.utf8), to: uri)
    }

    // MARK: - Saving as a new document

    /// Saves a resource of this set as an XMI document and gives the resource the URI of
    /// that document.
    ///
    /// This is EMF's save as: the document is written as
    /// ``save(_:to:options:)-(Resource,_,_)`` writes it, with the URIs of other documents
    /// relative to the new URI where the options ask for relative URIs, and the resource then
    /// takes the new URI as ``Resource/setURI(_:)`` gives it. Thereafter the set finds the
    /// resource under the new URI only, and the other resources of the set refer to its
    /// objects at the new location when they are saved.
    /// ``save(_:to:options:)-(Resource,_,_)`` writes a copy instead and leaves the URI
    /// unchanged.
    ///
    /// The URI is checked before anything is written. If the document cannot be rendered
    /// or written, the resource keeps its URI.
    ///
    /// - Parameters:
    ///   - resource: The resource to save.
    ///   - uri: The URI of the document to write, which the resource then has.
    ///   - options: The layout options (default ``XMISerializationOptions/legacy``).
    /// - Throws: ``ResourceSetError/notInResourceSet(_:)`` if the resource belongs to another
    ///   set or none, ``ResourceSetError/uriInUse(_:)`` if another resource of the set has
    ///   the URI, ``XMIError`` if serialisation fails, or the error of the handler.
    public func saveAs(
        _ resource: Resource, to uri: String, options: XMISerializationOptions = .legacy
    ) async throws {
        let target = try await prepareSaveAs(resource, to: uri)
        try await save(resource, to: target, options: options)
        try await moveResource(resource, to: target)
    }

    /// Saves a resource of this set as a JSON document and gives the resource the URI of
    /// that document.
    ///
    /// The document is written as ``saveJSON(_:to:)`` writes it, with the URIs of other
    /// documents relative to the new URI, and the resource then takes the new URI as
    /// ``saveAs(_:to:options:)`` describes. ``saveJSON(_:to:)`` writes a copy instead and
    /// leaves the URI unchanged.
    ///
    /// - Parameters:
    ///   - resource: The resource to save.
    ///   - uri: The URI of the document to write, which the resource then has.
    /// - Throws: ``ResourceSetError/notInResourceSet(_:)`` if the resource belongs to another
    ///   set or none, ``ResourceSetError/uriInUse(_:)`` if another resource of the set has
    ///   the URI, ``JSONError`` if serialisation fails, or the error of the handler.
    public func saveJSONAs(_ resource: Resource, to uri: String) async throws {
        let target = try await prepareSaveAs(resource, to: uri)
        try await saveJSON(resource, to: target)
        try await moveResource(resource, to: target)
    }

    /// Checks that a resource of this set can be saved as a document with a URI.
    ///
    /// - Parameters:
    ///   - resource: The resource to save.
    ///   - uri: The URI of the document.
    /// - Returns: The canonical form of the URI.
    /// - Throws: ``ResourceSetError/notInResourceSet(_:)`` if the resource belongs to another
    ///   set or none, or ``ResourceSetError/uriInUse(_:)`` if another resource of the set has
    ///   the URI.
    private func prepareSaveAs(_ resource: Resource, to uri: String) async throws -> String {
        let target = URIReference.canonicalise(uri)
        if resources[resource.uri] !== resource, await resource.resourceSet !== self {
            throw ResourceSetError.notInResourceSet(resource.uri)
        }
        try checkURIAvailable(target, for: resource)
        return target
    }
}

extension EPackage {
    /// Loads an EPackage from the text of an `.ecore` document.
    ///
    /// Types that refer to other documents are resolved relative to the URI through the
    /// handlers of the resource set.
    ///
    /// - Parameters:
    ///   - text: The text of the `.ecore` document.
    ///   - uri: The URI that the document has.
    ///   - resourceSet: The set to load into; by default a new set with a file handler.
    /// - Throws: ``XMIError`` if the document cannot be parsed or has no root package.
    public init(text: String, uri: String, resourceSet: ResourceSet = ResourceSet()) async throws {
        let resource = try await resourceSet.loadEcoreResource(text: text, uri: uri)
        guard let package = await resource.getRootObjects().first as? EPackage else {
            throw XMIError.noRootObject
        }
        self = package
    }
}
