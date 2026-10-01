//
// XMIReferenceParsing.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// How the XMI parser reads attribute values of reference features.
///
/// When a document's metamodel is registered, attributes that hold values of
/// non-containment references can be read as references or kept as the text that was
/// written. Interpreting them is the default; keeping the text is lossless and leaves
/// every decision about resolution to the caller.
public enum XMIReferenceParsing: Sendable, Equatable {
    /// Reference attributes of registered metamodels become references.
    ///
    /// References within the document become object identifiers and references to other
    /// documents become ``ResourceProxy`` values.
    case interpreted

    /// Reference attributes are stored as the uninterpreted text of the document.
    ///
    /// The text, including any type qualifier and relative URI, is kept exactly as
    /// written in the attribute.
    case rawText
}
