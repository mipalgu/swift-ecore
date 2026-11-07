//
// ResourceChangeObservation.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
public import Foundation
import OrderedCollections
import Synchronization

/// A registration of a change observer with a ``Resource``.
///
/// The value returned by ``Resource/addChangeObserver(_:)`` identifies the registration, so
/// that ``Resource/removeChangeObserver(_:)`` can end it.
public struct ResourceChangeObservation: Hashable, Sendable {
    /// The identifier of the registration.
    public let identifier: UUID

    /// Creates a registration identifier.
    ///
    /// - Parameter identifier: The identifier of the registration; a new one by default.
    public init(identifier: UUID = UUID()) {
        self.identifier = identifier
    }
}

extension Resource {

    // MARK: - Change observation

    /// Registers a handler that receives the changes made to this resource.
    ///
    /// After each editing operation that reports changes (``eSetWithChanges(objectId:feature:value:)``,
    /// ``eAdd(objectId:feature:value:at:)``, ``eRemove(objectId:feature:value:)``,
    /// ``removeValue(objectId:feature:value:)``, ``eMove(objectId:feature:from:to:)``,
    /// ``delete(_:cleaningReferences:)``, ``eCreate(_:)`` and ``rebind(to:from:)``), the handler
    /// is called with the changes of that operation, in the order in which they were made. The
    /// changes are the ones that the operation returns and that ``recordingChanges(_:)``
    /// collects: setting, adding, removing and moving feature values, and creating, deleting
    /// and rebinding objects.
    ///
    /// The handler runs synchronously, isolated to this resource, before the operation
    /// returns. It must not wait for the resource and should hand the changes on quickly, for
    /// example to a ``ResourceChangeQueue``. Operations that do not report changes, such as
    /// ``eSet(objectId:feature:value:)``, ``add(_:)``, ``remove(id:)``, ``clear()`` and
    /// ``restore(_:)``, do not call observers.
    ///
    /// While no observer is registered, the editing operations only check that the set of
    /// observers is empty.
    ///
    /// - Parameter handler: The handler to call with the changes of each operation.
    /// - Returns: The registration, for ``removeChangeObserver(_:)``.
    @discardableResult
    public func addChangeObserver(
        _ handler: @escaping @Sendable ([ResourceChange]) -> Void
    ) -> ResourceChangeObservation {
        let observation = ResourceChangeObservation()
        changeObservers[observation.identifier] = handler
        return observation
    }

    /// Ends a registration made with ``addChangeObserver(_:)``.
    ///
    /// - Parameter observation: The registration to end.
    /// - Returns: `true` if the registration was active, otherwise `false`.
    @discardableResult
    public func removeChangeObserver(_ observation: ResourceChangeObservation) -> Bool {
        changeObservers.removeValue(forKey: observation.identifier) != nil
    }

    /// The number of registered change observers.
    public var changeObserverCount: Int { changeObservers.count }

    /// Calls every registered observer with the changes of one operation.
    ///
    /// - Parameter changes: The changes, in the order in which they were made.
    func notifyChangeObservers(_ changes: [ResourceChange]) {
        guard !changes.isEmpty else { return }
        for handler in changeObservers.values { handler(changes) }
    }

    /// Arranges the root objects of the resource in a given order.
    ///
    /// The root objects named in `order` come first, in that order. Root objects that `order`
    /// does not name follow in their current order. Identifiers in `order` that are not
    /// root objects of the resource are ignored. The arrangement takes time proportional to
    /// the number of root objects and the length of `order`.
    ///
    /// - Parameter order: The identifiers of root objects in the order they should take.
    /// - Returns: `true` if the order of the root objects changed, otherwise `false`.
    @discardableResult
    public func reorderRoots(_ order: [EUUID]) -> Bool {
        var arranged = OrderedSet<EUUID>()
        arranged.reserveCapacity(rootObjects.count)
        for id in order where rootObjects.contains(id) {
            arranged.append(id)
        }
        for id in rootObjects where !arranged.contains(id) {
            arranged.append(id)
        }
        guard arranged != rootObjects else { return false }
        rootObjects = arranged
        return true
    }

    /// The identifiers of the root objects, in order.
    ///
    /// - Returns: The identifiers of the objects that no object of the resource contains.
    public func rootIdentifiers() -> [EUUID] {
        rootObjects.elements
    }
}

/// A thread-safe queue that collects resource changes for later processing.
///
/// A queue serves as the handler of one or more resource observations: register it with
/// ``observe(_:)`` (or pass ``enqueue(_:)`` to ``Resource/addChangeObserver(_:)``), and take the
/// changes collected so far with ``drain()`` whenever it is convenient, for example before
/// bringing a derived result up to date. Changes from several resources are kept in the
/// order in which they were reported.
///
/// ```swift
/// let queue = ResourceChangeQueue()
/// let observation = await queue.observe(resource)
/// try await resource.eSetWithChanges(objectId: id, feature: "name", value: "New")
/// let changes = queue.drain()   // the change of the name
/// await resource.removeChangeObserver(observation)
/// ```
public final class ResourceChangeQueue: Sendable {
    /// The changes reported and not yet drained.
    private let pending = Mutex<[ResourceChange]>([])

    /// Creates an empty queue.
    public init() {}

    /// Appends changes to the queue.
    ///
    /// - Parameter changes: The changes to append, in order.
    public func enqueue(_ changes: [ResourceChange]) {
        pending.withLock { $0.append(contentsOf: changes) }
    }

    /// Removes and returns every change collected so far.
    ///
    /// - Returns: The changes, oldest first.
    public func drain() -> [ResourceChange] {
        pending.withLock { queued in
            defer { queued = [] }
            return queued
        }
    }

    /// Whether the queue holds no changes.
    public var isEmpty: Bool {
        pending.withLock { $0.isEmpty }
    }

    /// The number of changes in the queue.
    public var count: Int {
        pending.withLock { $0.count }
    }

    /// Registers the queue as a change observer of a resource.
    ///
    /// - Parameter resource: The resource to observe.
    /// - Returns: The registration, for ``Resource/removeChangeObserver(_:)``.
    @discardableResult
    public func observe(_ resource: Resource) async -> ResourceChangeObservation {
        await resource.addChangeObserver { [self] changes in self.enqueue(changes) }
    }
}
