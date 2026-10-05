//
// MetamodelDocument.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

/// A metamodel that is being edited: its root packages, an index over them, and its location.
///
/// A document is a value. Applying an edit changes the document and reports what changed;
/// every earlier copy of the document keeps the state it had, which is what makes undo and
/// redo a matter of keeping documents (see ``EditHistory``). Editors, labels, and validators
/// should always read elements through the ``index``, which is rebuilt after every edit and
/// never goes stale, and not through the class snapshots that elements hold.
///
/// ```swift
/// var document = MetamodelDocument(roots: [package])
/// let changes = try document.apply(.set(classID, .name, "Book"))
/// let label = EcoreLabelProvider().label(for: classID, in: document.index)
/// ```
public struct MetamodelDocument: Sendable {
    /// The root packages of the document.
    public private(set) var roots: [EPackage]

    /// The index over the roots, rebuilt after every edit.
    public private(set) var index: MetamodelIndex

    /// The location of the document, if it has one.
    public var uri: String?

    /// Creates a document.
    ///
    /// - Parameters:
    ///   - roots: The root packages.
    ///   - externals: Packages that the roots refer to; they can be looked up but not edited.
    ///   - uri: The location of the document.
    public init(roots: [EPackage], externals: [EPackage] = [], uri: String? = nil) {
        self.roots = roots
        self.index = MetamodelIndex(roots: roots, externals: externals)
        self.uri = uri
    }

    /// Replaces the roots and index after an edit.
    fileprivate mutating func adopt(_ editor: MetamodelEditor) {
        roots = editor.roots
        index = editor.index
    }

    /// Applies an edit.
    ///
    /// The edit changes the roots, the class snapshots are refreshed from the canonical
    /// elements by identifier, and the index is rebuilt. If the edit is refused, the
    /// document is not changed.
    ///
    /// - Parameters:
    ///   - edit: The edit to apply.
    ///   - policy: What to do about edits that break rules of Ecore (supertype cycles are
    ///     rejected by default).
    /// - Returns: What the edit changed. The change set is empty when the edit changed nothing,
    ///   for instance when it set a property to the value that it already had.
    /// - Throws: ``MetamodelEditError`` if the edit is refused.
    @discardableResult
    public mutating func apply(_ edit: MetamodelEdit, policy: EditPolicy = .default)
        throws(MetamodelEditError) -> MetamodelChangeSet
    {
        var editor = MetamodelEditor(roots: roots, index: index, policy: policy)
        try editor.apply(edit)
        let changes = editor.finish(label: edit.label)
        if !changes.isEmpty { adopt(editor) }
        return changes
    }

    /// Whether an edit would be accepted.
    ///
    /// - Parameters:
    ///   - edit: The edit to test.
    ///   - policy: What to do about edits that break rules of Ecore.
    /// - Returns: `true` if ``apply(_:policy:)`` would not throw. The document is not changed.
    public func canApply(_ edit: MetamodelEdit, policy: EditPolicy = .default) -> Bool {
        var copy = self
        return (try? copy.apply(edit, policy: policy)) != nil
    }

    /// Copies elements for pasting.
    ///
    /// - Parameter ids: The elements to copy, each with everything it contains. Unknown
    ///   identifiers are skipped, and so are elements that lie inside another copied element.
    /// - Returns: The clipboard.
    public func copy(_ ids: [EUUID]) -> EcoreClipboard {
        let wanted = Set(ids)
        var seen: Set<EUUID> = []
        var elements: [EcoreElement] = []
        for identifier in ids {
            guard let element = index.element(identifier), seen.insert(identifier).inserted,
                !index.ancestors(of: identifier).contains(where: wanted.contains)
            else { continue }
            elements.append(element)
        }
        let copy = EcoreCopier.copy(elements)
        return EcoreClipboard(elements: copy.elements, identifiers: copy.identifiers)
    }

    /// The elements of the root packages, in document order.
    public var elements: [EcoreElement] { index.allElements }
}

extension MetamodelDocument: Equatable {
    /// Whether two documents hold the same metamodel.
    ///
    /// Documents are equal when they have the same location, the same roots in the same order,
    /// and every element has the same place and the same property values. Elements are
    /// compared by their content, not just by identifier.
    public static func == (lhs: MetamodelDocument, rhs: MetamodelDocument) -> Bool {
        lhs.uri == rhs.uri && lhs.roots.map(\.id) == rhs.roots.map(\.id)
            && MetamodelDiff.changeSet(from: lhs, to: rhs, label: "").isEmpty
    }
}
