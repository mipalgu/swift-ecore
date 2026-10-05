//
// MetamodelEditError.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

/// The reasons why an edit of a metamodel document is refused.
///
/// A refused edit leaves the document exactly as it was.
public enum MetamodelEditError: Error, Sendable, Hashable, CustomStringConvertible {
    /// No element of the document has the identifier.
    case unknownElement(EUUID)

    /// The element belongs to an external package, which cannot be edited.
    case externalElement(EUUID)

    /// The container does not accept elements of that kind in that feature.
    case illegalChild(container: EUUID, feature: EcoreFeatureName, kind: EcoreClassifier)

    /// The element's metaclass has no such feature.
    case unknownFeature(EUUID, EcoreFeatureName)

    /// The feature is derived, read-only, or a containment (use create, move, or delete).
    case notSettable(EcoreFeatureName)

    /// The value does not suit the feature.
    case invalidValue(EcoreFeatureName)

    /// The identifier does not name a classifier or element that the value can refer to.
    case unresolvedReference(EUUID)

    /// The position is outside the range of the feature.
    case indexOutOfRange(Int, count: Int)

    /// The supertypes would make a class inherit from itself; the identifiers are the cycle.
    case supertypeCycle([EUUID])

    /// An element cannot be moved into itself or one of its descendants.
    case moveIntoDescendant(EUUID)

    /// A root package has no container to move out of.
    case cannotMoveRoot(EUUID)

    /// Annotation details can only be moved within their annotation.
    case cannotMoveDetail(EUUID)

    /// The element is not a reference, or cannot be the opposite of that reference.
    case invalidOpposite(EUUID)

    /// The annotation already has a detail with the key.
    case duplicateDetailKey(String)

    /// The annotation has no detail with the key.
    case missingDetailKey(String)

    /// The clipboard is empty or holds elements that the container does not accept.
    case incompatibleClipboard

    /// A description of the problem.
    public var description: String {
        switch self {
        case .unknownElement(let identifier): return "No element has the identifier \(identifier)."
        case .externalElement(let identifier): return "The element \(identifier) belongs to an external package."
        case .illegalChild(let container, let feature, let kind):
            return "The element \(container) does not accept an \(kind.rawValue) in \(feature.rawValue)."
        case .unknownFeature(let identifier, let feature):
            return "The element \(identifier) has no feature \(feature.rawValue)."
        case .notSettable(let feature): return "The feature \(feature.rawValue) cannot be set."
        case .invalidValue(let feature): return "The value does not suit the feature \(feature.rawValue)."
        case .unresolvedReference(let identifier): return "The identifier \(identifier) cannot be referred to."
        case .indexOutOfRange(let position, let count): return "The position \(position) is outside 0...\(count)."
        case .supertypeCycle: return "The supertypes would form a cycle."
        case .moveIntoDescendant(let identifier): return "The element \(identifier) cannot be moved into itself."
        case .cannotMoveRoot(let identifier): return "The root package \(identifier) cannot be moved."
        case .cannotMoveDetail(let identifier):
            return "The detail \(identifier) can only be moved within its annotation."
        case .invalidOpposite(let identifier): return "The element \(identifier) cannot be an opposite."
        case .duplicateDetailKey(let key): return "The annotation already has the detail key \(key)."
        case .missingDetailKey(let key): return "The annotation has no detail key \(key)."
        case .incompatibleClipboard: return "The clipboard content cannot be pasted there."
        }
    }
}

/// What an edit does when it would break a rule of Ecore that the validator also checks.
public struct EditPolicy: Sendable, Hashable {
    /// How an edit that makes a class inherit from itself is treated.
    public enum SupertypeCycles: Sendable, Hashable {
        /// Refuse the edit with ``MetamodelEditError/supertypeCycle(_:)``.
        case reject
        /// Apply the edit and report a diagnostic in the change set.
        case allowAndDiagnose
    }

    /// How supertype cycles are treated.
    public var supertypeCycles: SupertypeCycles

    /// Creates a policy.
    ///
    /// - Parameter supertypeCycles: How supertype cycles are treated (rejected by default).
    public init(supertypeCycles: SupertypeCycles = .reject) {
        self.supertypeCycles = supertypeCycles
    }

    /// The default policy: supertype cycles are rejected.
    public static let `default` = EditPolicy()

    /// A policy that applies edits that break rules, and reports them as diagnostics.
    public static let permissive = EditPolicy(supertypeCycles: .allowAndDiagnose)
}
