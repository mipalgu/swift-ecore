//
// ModelDependencyRecorder.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Collects the model reads of nested computations.
///
/// An evaluator holds a recorder while it evaluates incrementally. Each computation whose
/// dependencies are wanted separately, such as a query or a cached helper value, opens a
/// frame with ``begin()`` and closes it with ``end()``, which returns what the computation
/// read. Reads are recorded in the innermost open frame, and closing a frame adds its
/// dependencies to the enclosing frame, so the dependencies of a nested computation are
/// also dependencies of the computations that contain it.
///
/// While no frame is open, ``isRecording`` is `false` and recording does nothing.
public struct ModelDependencyRecorder: Sendable {
    /// The dependencies of the open frames, innermost last.
    private var frames: [ModelDependencies] = []

    /// Creates a recorder without open frames.
    public init() {}

    /// Whether a frame is open.
    public var isRecording: Bool { !frames.isEmpty }

    /// The number of open frames.
    public var depth: Int { frames.count }

    /// Opens a frame for a computation.
    public mutating func begin() {
        frames.append(ModelDependencies())
    }

    /// Closes the innermost frame.
    ///
    /// The dependencies of the frame are added to the frame that encloses it, if any.
    ///
    /// - Returns: The dependencies recorded while the frame was open, or none if no frame
    ///   was open.
    @discardableResult
    public mutating func end() -> ModelDependencies {
        guard let finished = frames.popLast() else { return ModelDependencies() }
        if !frames.isEmpty { frames[frames.count - 1].formUnion(finished) }
        return finished
    }

    /// Records the read of a feature of an object in the innermost open frame.
    ///
    /// - Parameters:
    ///   - feature: The name of the feature.
    ///   - objectID: The identifier of the object.
    public mutating func recordFeature(_ feature: String, of objectID: EUUID) {
        guard !frames.isEmpty else { return }
        frames[frames.count - 1].recordFeature(feature, of: objectID)
    }

    /// Records that any part of an object may have been read, in the innermost open frame.
    ///
    /// - Parameter objectID: The identifier of the object.
    public mutating func recordObject(_ objectID: EUUID) {
        guard !frames.isEmpty else { return }
        frames[frames.count - 1].recordObject(objectID)
    }

    /// Records the enumeration of the instances of a class in the innermost open frame.
    ///
    /// - Parameter className: The name of the class.
    public mutating func recordExtent(_ className: String) {
        guard !frames.isEmpty else { return }
        frames[frames.count - 1].recordExtent(className)
    }

    /// Records the read of the container of an object in the innermost open frame.
    ///
    /// - Parameter objectID: The identifier of the contained object.
    public mutating func recordContainer(of objectID: EUUID) {
        guard !frames.isEmpty else { return }
        frames[frames.count - 1].recordContainer(of: objectID)
    }

    /// Records a dependency on the containment structure in the innermost open frame.
    public mutating func recordContainmentStructure() {
        guard !frames.isEmpty else { return }
        frames[frames.count - 1].recordContainmentStructure()
    }

    /// Records that every change affects the computations of the open frames.
    public mutating func recordUnbounded() {
        guard !frames.isEmpty else { return }
        frames[frames.count - 1].recordUnbounded()
    }

    /// Adds dependencies recorded earlier, such as those of a cached value, to the innermost
    /// open frame.
    ///
    /// - Parameter dependencies: The dependencies to add.
    public mutating func merge(_ dependencies: ModelDependencies) {
        guard !frames.isEmpty, !dependencies.isEmpty else { return }
        frames[frames.count - 1].formUnion(dependencies)
    }
}
