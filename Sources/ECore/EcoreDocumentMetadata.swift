public import EMFBase

/// XML metadata retained alongside a native Ecore document.
///
/// Identifiers associate comments and explicit XML identities with model elements, so
/// metadata follows edits and disappears from the output when its element is deleted.
public struct EcoreDocumentMetadata: Sendable, Hashable {
    /// The default XML encoding declaration for new documents.
    public static let defaultEncoding = "UTF-8"

    /// The encoding spelling in the XML declaration.
    public var encoding: String

    /// Comments preceding the document's root element.
    public var leadingComments: [String]

    /// Comments following the document's root element.
    public var trailingComments: [String]

    /// Comments after the final package inside a multi-root XMI wrapper.
    public var wrapperTrailingComments: [String]

    /// Comments immediately preceding each model element.
    public var commentsBefore: [EUUID: [String]]

    /// Comments following the final child of each model element.
    public var commentsAtEnd: [EUUID: [String]]

    /// Retained attribute names for elements with alternative source attribute ordering.
    public var attributeNames: [EUUID: [String]]

    /// Explicit `xmi:id` values, keyed by model element identity.
    public var xmlIdentifiers: [EUUID: String]

    /// Creates metadata for an Ecore document.
    ///
    /// - Parameters:
    ///   - encoding: The declaration's encoding spelling, defaulting to UTF-8.
    ///   - leadingComments: Comments preceding the root.
    ///   - trailingComments: Comments following the root.
    ///   - wrapperTrailingComments: Comments after the last package inside an XMI wrapper.
    ///   - commentsBefore: Comments preceding model elements.
    ///   - commentsAtEnd: Comments after the final child of model elements.
    ///   - attributeNames: Attribute names in source order, by model element.
    ///   - xmlIdentifiers: Explicit XML identifiers.
    public init(encoding: String = EcoreDocumentMetadata.defaultEncoding, leadingComments: [String] = [], trailingComments: [String] = [],
        wrapperTrailingComments: [String] = [], commentsBefore: [EUUID: [String]] = [:], commentsAtEnd: [EUUID: [String]] = [:],
        attributeNames: [EUUID: [String]] = [:], xmlIdentifiers: [EUUID: String] = [:]) {
        self.encoding = encoding
        self.leadingComments = leadingComments
        self.trailingComments = trailingComments
        self.wrapperTrailingComments = wrapperTrailingComments
        self.commentsBefore = commentsBefore
        self.commentsAtEnd = commentsAtEnd
        self.attributeNames = attributeNames
        self.xmlIdentifiers = xmlIdentifiers
    }
}
