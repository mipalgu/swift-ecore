//
// Resource+Identifiers.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

extension Resource {
    /// Finds the object that an identifier names in this resource.
    ///
    /// As in EMF, an identifier names the object whose explicit `xmi:id` it is, or else the
    /// object whose ID attribute (the attribute that its class declares as its ID) holds it.
    /// If several objects hold the same ID attribute value, the first in resource order is
    /// returned. Fragments that do not start with `/` are identifiers (see
    /// ``XPathResolver/identifier(inFragment:)``).
    ///
    /// - Parameter identifier: The identifier, without a leading `#`.
    /// - Returns: The identifier of the object, or `nil` if no object of the resource has it.
    public func object(identifiedBy identifier: String) -> EUUID? {
        if let id = xmlIdentifierTargets[identifier], objects[id] != nil { return id }
        return objects.object(identifiedBy: identifier)
    }

    /// Returns the identifier that names an object of this resource in a fragment.
    ///
    /// The identifier is the explicit `xmi:id` of the object, or else the value of its ID
    /// attribute. Writers use it in place of a path fragment, as EMF does. Values that are
    /// empty or start with `/` cannot be told apart from a path and identify no object.
    ///
    /// - Parameter id: The identifier of the object.
    /// - Returns: The identifier text, or `nil` if the resource holds no such object or the
    ///   object has no identifier.
    public func identifier(of id: EUUID) -> String? {
        guard let object = objects[id] else { return nil }
        if let text = xmlIdentifier(of: id).flatMap(ObjectTable.usableIdentifier) { return text }
        return ObjectTable.intrinsicIdentifier(of: object)
    }

    /// Returns the explicit `xmi:id` of an object of this resource.
    ///
    /// - Parameter id: The identifier of the object.
    /// - Returns: The `xmi:id` read with the object, or `nil` if it had none.
    public func xmlIdentifier(of id: EUUID) -> String? {
        ecoreDocumentMetadata.xmlIdentifiers[id]
    }
}
