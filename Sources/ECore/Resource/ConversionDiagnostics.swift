//
// ConversionDiagnostics.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// A condition under which reading or writing a document could not keep all information.
///
/// Parsers and serialisers record a warning wherever they fall back to a less faithful
/// representation instead of failing, for example when a class has to be fabricated
/// because no registered metamodel defines it, or when a value cannot be expressed in
/// the written format.
public struct ConversionWarning: Sendable, Hashable, CustomStringConvertible {
    /// The kinds of lossy conversion.
    public enum Kind: Sendable, Hashable {
        /// No registered metamodel defines the class.
        ///
        /// A parser fabricated the class from the document, or a serialiser wrote it without
        /// the namespace of its package: unqualified in JSON, or in a namespace derived from
        /// the class name in XMI.
        ///
        /// - Parameter name: The name of the class.
        case untypedClass(name: String)

        /// A reference was written as an object identifier rather than as a fragment.
        ///
        /// The reference holds the identifier of the object, which a reader cannot resolve,
        /// because the object is not reachable through containment from a root of any known
        /// resource or because the feature is not declared as a reference.
        ///
        /// - Parameters:
        ///   - feature: The name of the reference.
        ///   - className: The name of the class of the object that holds the reference.
        case referenceWithoutFragment(feature: String, className: String)

        /// The value of a feature could not be written and was left out.
        ///
        /// - Parameters:
        ///   - name: The name of the feature.
        ///   - className: The name of the class of the object that holds the feature.
        case droppedFeature(name: String, className: String)

        /// A contained object is not registered with the resource and was left out.
        ///
        /// - Parameter className: The name of the class of the object, or the declared type
        ///   of the containment reference if the object cannot be found.
        case unregisteredContainedObject(className: String)

        /// A reference names an object that could not be found.
        ///
        /// - Parameters:
        ///   - uri: The URI of the document that the reference names.
        ///   - fragment: The fragment that names no object of that document.
        case unresolvedProxy(uri: String, fragment: String)
    }

    /// What was lost.
    public let kind: Kind

    /// Creates a warning.
    ///
    /// - Parameter kind: What was lost.
    public init(_ kind: Kind) {
        self.kind = kind
    }

    /// A sentence that describes the warning to a person.
    public var message: String {
        switch kind {
        case .untypedClass(let name):
            return "No registered metamodel defines the class '\(name)'"
        case .referenceWithoutFragment(let feature, let className):
            return "Reference '\(feature)' of a '\(className)' was written as an object identifier, not a fragment"
        case .droppedFeature(let name, let className):
            return "Feature '\(name)' of a '\(className)' cannot be written and was left out"
        case .unregisteredContainedObject(let className):
            return "A contained '\(className)' is not registered with the resource and was left out"
        case .unresolvedProxy(let uri, let fragment):
            return "Reference '\(uri)\(CrossReferenceSyntax.fragmentSeparator)\(fragment)' names no object"
        }
    }

    /// The ``message`` of the warning.
    public var description: String { message }
}

/// The warnings collected while a document was read or written.
///
/// Each distinct warning is kept once, in the order in which it was first recorded.
///
/// ```swift
/// var diagnostics = ConversionDiagnostics()
/// let text = try await XMISerializer(options: .emf).serialize(resource, diagnostics: &diagnostics)
/// for warning in diagnostics.warnings { print(warning) }
/// ```
public struct ConversionDiagnostics: Sendable, Equatable {
    /// The distinct warnings in the order in which they were first recorded.
    public private(set) var warnings: [ConversionWarning] = []

    /// The warnings recorded so far, for detecting repetitions.
    private var recorded: Set<ConversionWarning> = []

    /// Creates an empty collection of warnings.
    ///
    /// Pass the collection to a serialiser, or read the `diagnostics` of a parser, to
    /// learn what a conversion could not keep.
    public init() {}

    /// Whether no warning has been recorded.
    ///
    /// An empty collection means that the conversion kept everything it read or wrote.
    public var isEmpty: Bool { warnings.isEmpty }

    /// Records a warning unless the same warning has been recorded before.
    ///
    /// - Parameter kind: What was lost.
    public mutating func record(_ kind: ConversionWarning.Kind) {
        let warning = ConversionWarning(kind)
        guard recorded.insert(warning).inserted else { return }
        warnings.append(warning)
    }

    /// Records the warnings of another collection that this one does not hold yet.
    ///
    /// - Parameter other: The warnings to add, in their order.
    public mutating func merge(_ other: ConversionDiagnostics) {
        for warning in other.warnings { record(warning.kind) }
    }
}
