//
// FragmentSegmentRule.swift
// ECore
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// A rule that names the fragment segment of objects of one metaclass.
///
/// Ecore elements are identified by their own names in name-based fragments. Other
/// metamodels sometimes name their objects by something else, for example by a
/// property of a related object. A package registers a rule with
/// ``ResourceSet/registerFragmentSegmentRule(_:)``, after which the
/// ``FragmentNavigator`` writes and resolves fragments such as `#//library` for the
/// objects of that metaclass that are contained in a root object or in each other.
public struct FragmentSegmentRule: Sendable {
    /// The name of the metaclass whose objects the rule names.
    public let className: String

    /// Computes the segment of an object.
    ///
    /// The closure receives the object and the resource that holds it, and returns the
    /// segment (without `/`), or `nil` if the object has no usable name.
    public let segmentName: @Sendable (_ object: DynamicEObject, _ resource: Resource) async -> String?

    /// Creates a rule.
    ///
    /// - Parameters:
    ///   - className: The name of the metaclass whose objects the rule names.
    ///   - segmentName: The closure that computes the segment of an object.
    public init(
        className: String,
        segmentName: @escaping @Sendable (_ object: DynamicEObject, _ resource: Resource) async -> String?
    ) {
        self.className = className
        self.segmentName = segmentName
    }
}

extension ResourceSet {
    /// Registers a fragment segment naming rule for a metaclass.
    ///
    /// A rule registered for a metaclass name replaces an earlier rule for the same name.
    ///
    /// - Parameter rule: The rule to register.
    public func registerFragmentSegmentRule(_ rule: FragmentSegmentRule) {
        fragmentSegmentRules[rule.className] = rule
    }

    /// Returns the fragment segment naming rule of a metaclass.
    ///
    /// - Parameter className: The name of the metaclass.
    /// - Returns: The registered rule, or `nil` if there is none.
    public func fragmentSegmentRule(forClass className: String) -> FragmentSegmentRule? {
        fragmentSegmentRules[className]
    }
}
