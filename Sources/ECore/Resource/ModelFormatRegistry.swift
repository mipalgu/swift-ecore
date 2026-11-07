//
// ModelFormatRegistry.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// The document formats that ``ModelIO`` reads and writes, by identifier, file extension and content.
///
/// A registry holds one ``ModelFormatHandler`` per format identifier. It starts with the
/// handlers of the formats that ``ModelFormat`` names, and ``register(_:)`` adds further
/// formats or replaces a handler. ``shared`` is the registry that ``ModelIO`` uses unless it
/// is given another one.
///
/// A registry is an actor, so handlers can be registered and looked up from any task.
///
/// ## Lookup
///
/// - ``handler(for:)-(ModelFormat)`` and ``handler(identifier:)`` find a format by name.
/// - ``handler(forFileExtension:)`` and ``handler(for:)-(URL)`` find a format by file
///   extension, regardless of case. When several handlers claim an extension, the one
///   registered last is chosen.
/// - ``handler(recognising:)`` asks the handlers whether they recognise the start of a
///   document, in descending order of ``ModelFormatHandler/priority`` and, among handlers of
///   equal priority, starting with the one registered last. With only the built-in
///   handlers, it finds the format that ``ModelFormat/detect(data:)`` detects.
/// - ``handler(for:contents:)`` finds the format of a file as ``ModelIO`` does: by its
///   extension, unless the extension names a generic format such as XMI and a handler of
///   higher priority recognises the contents, and otherwise by its contents.
///
/// ```swift
/// await ModelFormatRegistry.shared.register(NotationHandler())
/// let loaded = try await ModelIO.load(url: notationURL, resourceSet: ResourceSet())
/// ```
public actor ModelFormatRegistry {
    /// The registry that ``ModelIO`` uses by default, which starts with the built-in handlers.
    public static let shared = ModelFormatRegistry()

    /// The handlers of the formats that ``ModelFormat`` names, in the order of its cases.
    public static let builtInHandlers: [any ModelFormatHandler] = ModelFormat.allCases.map(\.builtInHandler)

    /// The number of bytes at the start of a document that handlers examine to recognise it.
    public static let recognitionPrefixLength = ModelFormatSniffing.prefixLength

    /// The registered handlers, in the order in which they were registered.
    public private(set) var handlers: [any ModelFormatHandler]

    /// Creates a registry.
    ///
    /// - Parameter handlers: The handlers to start with, in registration order (default
    ///   ``builtInHandlers``). A later handler replaces an earlier one with the same identifier.
    public init(handlers: [any ModelFormatHandler] = ModelFormatRegistry.builtInHandlers) {
        var registered: [any ModelFormatHandler] = []
        for handler in handlers { Self.insert(handler, into: &registered) }
        self.handlers = registered
    }

    /// Registers a handler.
    ///
    /// A handler that is registered under the identifier of an earlier one, regardless of
    /// case, replaces it. The handler counts as the one registered last.
    ///
    /// - Parameter handler: The handler to register.
    public func register(_ handler: any ModelFormatHandler) {
        Self.insert(handler, into: &handlers)
    }

    /// The handler with an identifier, regardless of case.
    ///
    /// - Parameter identifier: The identifier of the format, such as `xmi`.
    /// - Returns: The handler, or `nil` if no handler has the identifier.
    public func handler(identifier: String) -> (any ModelFormatHandler)? {
        let key = identifier.lowercased()
        return handlers.first { $0.identifier.lowercased() == key }
    }

    /// The handler of a format.
    ///
    /// - Parameter format: The format.
    /// - Returns: The handler whose identifier is the raw value of the format, or `nil` if
    ///   none is registered.
    public func handler(for format: ModelFormat) -> (any ModelFormatHandler)? {
        handler(identifier: format.rawValue)
    }

    /// The handler of a format, which must be registered.
    ///
    /// - Parameter format: The format.
    /// - Returns: The handler whose identifier is the raw value of the format.
    /// - Throws: ``ModelFormatError/unsupportedFormat(_:)`` if no handler is registered for
    ///   the format.
    func requiredHandler(for format: ModelFormat) throws -> any ModelFormatHandler {
        guard let handler = handler(for: format) else { throw ModelFormatError.unsupportedFormat(format.rawValue) }
        return handler
    }

    /// The handler that claims a file extension, regardless of case.
    ///
    /// - Parameter fileExtension: An extension without the leading dot, such as `ecore`.
    /// - Returns: The handler registered last that claims the extension, or `nil` if none does.
    public func handler(forFileExtension fileExtension: String) -> (any ModelFormatHandler)? {
        let key = fileExtension.lowercased()
        guard !key.isEmpty else { return nil }
        return handlers.last { $0.fileExtensions.contains { $0.lowercased() == key } }
    }

    /// The handler that claims the extension of a file name.
    ///
    /// The contents of the file are not examined; use ``handler(recognising:)`` for that.
    ///
    /// - Parameter url: The location of the file.
    /// - Returns: The handler registered last that claims the extension, or `nil` if none does.
    public func handler(for url: URL) -> (any ModelFormatHandler)? {
        handler(forFileExtension: url.pathExtension)
    }

    /// The handler of a file, found from its extension and its contents.
    ///
    /// The handler that claims the extension of the file is chosen, unless it has
    /// ``ModelFormatPriority/generic`` priority or lower, as the handlers of XMI, JSON and
    /// Ecore have: such a format accepts any document of its syntax, so a handler of higher
    /// priority that recognises the contents is more precise and is chosen instead. This is
    /// how an EMOF metamodel or an OMG UML model in an `.xmi` file is read as EMOF or UML,
    /// while every other XMI document is still read as XMI. A file whose extension no
    /// handler claims is recognised by its contents alone (see ``handler(recognising:)``).
    ///
    /// - Parameters:
    ///   - url: The location of the file.
    ///   - data: The contents of the file, or at least their beginning.
    /// - Returns: The handler of the file, or `nil` if neither its extension nor its
    ///   contents determine one.
    public func handler(for url: URL, contents data: Data) -> (any ModelFormatHandler)? {
        guard let claiming = handler(for: url) else { return handler(recognising: data) }
        guard claiming.priority <= .generic,
            let recognising = handler(recognising: data, above: claiming.priority)
        else { return claiming }
        return recognising
    }

    /// The handler that recognises a document by its start.
    ///
    /// Only the first ``recognitionPrefixLength`` bytes are passed to the handlers, which are
    /// asked in descending order of priority and, among equal priorities, starting with the
    /// handler registered last.
    ///
    /// - Parameter data: The document, or at least its beginning.
    /// - Returns: The first handler that recognises the document, or `nil` if none does.
    public func handler(recognising data: Data) -> (any ModelFormatHandler)? {
        handler(recognising: data, above: nil)
    }

    /// The handler that recognises a document by its start, among handlers above a priority.
    ///
    /// - Parameters:
    ///   - data: The document, or at least its beginning.
    ///   - floor: The priority that a handler must exceed, or `nil` to ask every handler.
    /// - Returns: The first handler that recognises the document, or `nil` if none does.
    private func handler(recognising data: Data, above floor: ModelFormatPriority?) -> (any ModelFormatHandler)? {
        let prefix = Data(data.prefix(Self.recognitionPrefixLength))
        let candidates = handlers.reversed().enumerated()
            .filter { candidate in floor.map { candidate.element.priority > $0 } ?? true }
            .sorted {
                $0.element.priority != $1.element.priority
                    ? $0.element.priority > $1.element.priority : $0.offset < $1.offset
            }
        return candidates.first { $0.element.recognises(prefix) }?.element
    }

    /// Adds a handler at the end of a list, removing one with the same identifier.
    ///
    /// - Parameters:
    ///   - handler: The handler to add.
    ///   - handlers: The list of handlers in registration order.
    private static func insert(_ handler: any ModelFormatHandler, into handlers: inout [any ModelFormatHandler]) {
        let key = handler.identifier.lowercased()
        handlers.removeAll { $0.identifier.lowercased() == key }
        handlers.append(handler)
    }
}
