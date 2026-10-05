//
// InstanceEditingDomain.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// A token that ends an observation of an ``InstanceEditingDomain`` when cancelled.
@MainActor
public final class InstanceObservation {
    private weak var domain: InstanceEditingDomain?
    private let identifier: UUID

    fileprivate init(domain: InstanceEditingDomain, identifier: UUID) {
        self.domain = domain
        self.identifier = identifier
    }

    /// Whether the observation has ended.
    public var isCancelled: Bool { domain?.handlers[identifier] == nil }

    /// Ends the observation; the handler is not called again.
    public func cancel() {
        domain?.handlers.removeValue(forKey: identifier)
    }
}

/// An editing domain for the dynamic instances of one resource, for use by view models.
///
/// The domain wraps a ``BasicEditingDomain`` and keeps the latest ``ResourceSnapshot`` of the
/// resource, so user interfaces on the main actor can read the model synchronously. It runs
/// commands against the resource, supports undo and redo, tracks whether there are unsaved
/// changes, and tells observers which objects changed.
///
/// ```swift
/// let domain = await InstanceEditingDomain(resource: resource, resourceSet: resourceSet)
/// let token = domain.observe { changes in refresh(changes.affectedObjectIDs) }
/// try await domain.perform(domain.setCommand(object: person, feature: name, value: "Eve"))
/// try await domain.undo()
/// ```
@MainActor
public final class InstanceEditingDomain {

    /// An opaque marker for a captured instance model state.
    ///
    /// Capture it with ``snapshot`` before starting a write, then mark that
    /// state saved when the write succeeds. Later commands remain dirty.
    public struct SavePoint: Sendable, Hashable {
        fileprivate let domainIdentifier: UUID
        fileprivate let stateIdentifier: UUID
    }

    /// The resource that the domain edits.
    public let resource: Resource

    /// The underlying editing domain.
    public let editingDomain: BasicEditingDomain

    /// The latest snapshot of the resource, updated after every change.
    public private(set) var snapshot: ResourceSnapshot

    /// The metamodels that the instances conform to.
    public private(set) var metamodels: [EPackage]

    fileprivate var handlers: [UUID: @MainActor (ResourceChangeSet) -> Void] = [:]
    private var relay: Relay?
    private let domainIdentifier = UUID()
    private var savedStateIdentifier: UUID

    /// Creates a domain for a resource.
    ///
    /// - Parameters:
    ///   - resource: The resource to edit.
    ///   - resourceSet: The resource set whose metamodels apply; the resource's own set, or
    ///     a new empty one, by default.
    ///   - maxCommandHistory: The number of commands to keep for undo.
    public init(resource: Resource, resourceSet: ResourceSet? = nil, maxCommandHistory: Int = 100) async {
        let owner: ResourceSet
        if let resourceSet {
            owner = resourceSet
        } else if let existing = await resource.resourceSet {
            owner = existing
        } else {
            owner = ResourceSet()
        }
        self.resource = resource
        self.editingDomain = BasicEditingDomain(resourceSet: owner, maxCommandHistory: maxCommandHistory)
        self.savedStateIdentifier = editingDomain.commandStack.stateIdentifier
        self.snapshot = await resource.snapshot()
        self.metamodels = await Self.registeredMetamodels(of: owner)
        let relay = Relay(domain: self)
        self.relay = relay
        editingDomain.addObserver(relay)
    }

    // MARK: - Commands

    /// Creates a command that sets a feature of an object.
    ///
    /// - Parameters:
    ///   - object: The object to modify.
    ///   - feature: The feature to set.
    ///   - value: The new value.
    /// - Returns: A command bound to the domain's resource.
    public func setCommand(object: any EObject, feature: any EStructuralFeature, value: (any EcoreValue)?) -> SetCommand {
        SetCommand(object: object, feature: feature, value: value, in: resource)
    }

    /// Creates a command that adds a value to a many-valued feature.
    ///
    /// - Parameters:
    ///   - object: The object to modify.
    ///   - feature: The many-valued feature.
    ///   - value: The value to add.
    ///   - index: The position to insert at; the end by default.
    /// - Returns: A command bound to the domain's resource.
    public func addCommand(object: any EObject, feature: any EStructuralFeature, value: any EcoreValue, at index: Int? = nil) -> AddCommand {
        AddCommand(object: object, feature: feature, value: value, at: index, in: resource)
    }

    /// Creates a command that removes a value from a many-valued feature.
    ///
    /// - Parameters:
    ///   - object: The object to modify.
    ///   - feature: The many-valued feature.
    ///   - value: The value to remove.
    /// - Returns: A command bound to the domain's resource.
    public func removeCommand(object: any EObject, feature: any EStructuralFeature, value: any EcoreValue) -> RemoveCommand {
        RemoveCommand(object: object, feature: feature, value: value, in: resource)
    }

    /// Creates a command that deletes objects with their contents.
    ///
    /// - Parameters:
    ///   - objects: The objects to delete.
    ///   - cleaningReferences: Whether to remove references to them.
    /// - Returns: A command bound to the domain's resource.
    public func deleteCommand(objects: [any EObject], cleaningReferences: Bool = true) -> DeleteCommand {
        DeleteCommand(objects: objects, cleaningReferences: cleaningReferences, in: resource)
    }

    /// Creates a command that creates a child object.
    ///
    /// - Parameters:
    ///   - container: The containing object.
    ///   - descriptor: The kind of child to create.
    ///   - index: The position within a many-valued reference; the end by default.
    /// - Returns: A command bound to the domain's resource.
    public func createChildCommand(container: any EObject, descriptor: InstanceChildDescriptor, index: Int? = nil) -> CreateChildCommand {
        CreateChildCommand(
            container: container, reference: descriptor.reference, eClass: descriptor.eClass,
            factory: factory(for: descriptor.eClass), index: index, in: resource)
    }

    /// Creates a command that creates a root object.
    ///
    /// - Parameter eClass: The class to instantiate.
    /// - Returns: A command bound to the domain's resource.
    public func createRootCommand(eClass: EClass) -> CreateChildCommand {
        CreateChildCommand(rootClass: eClass, factory: factory(for: eClass), in: resource)
    }

    /// Lists the children that can be created inside an object.
    ///
    /// - Parameter object: The prospective container.
    /// - Returns: The legal children, given the object's current contents.
    public func legalChildren(of object: any EObject) -> [InstanceChildDescriptor] {
        let current = snapshot.object(id: object.id) ?? object
        return InstanceChildDescriptor.legalChildren(of: current, in: metamodels)
    }

    /// Checks the model against its metamodels.
    ///
    /// - Returns: The problems found, in object order.
    public func validate() -> [ModelDiagnostic] {
        ModelValidator(metamodels: metamodels).validate(snapshot)
    }

    private func factory(for eClass: EClass) -> EFactory? {
        func owner(_ package: EPackage) -> EPackage? {
            if package.eClassifiers.contains(where: { $0.id == eClass.id }) { return package }
            return package.eSubpackages.lazy.compactMap(owner).first
        }
        return metamodels.lazy.compactMap(owner).first?.eFactoryInstance
    }

    // MARK: - History

    /// Executes a command and records it for undo.
    ///
    /// - Parameter command: The command to execute.
    /// - Returns: The command's result.
    /// - Throws: ``EMFCommandError`` if the command cannot be executed.
    @discardableResult
    public func perform(_ command: EMFCommand) async throws -> any Sendable {
        command.bind(to: resource)
        let result = try await editingDomain.execute(command)
        snapshot = await resource.snapshot()
        return result
    }

    /// Undoes the most recent command.
    ///
    /// - Throws: ``EMFCommandError`` if there is nothing to undo.
    public func undo() async throws {
        try await editingDomain.undo()
        snapshot = await resource.snapshot()
    }

    /// Redoes the most recently undone command.
    ///
    /// - Throws: ``EMFCommandError`` if there is nothing to redo.
    public func redo() async throws {
        try await editingDomain.redo()
        snapshot = await resource.snapshot()
    }

    /// Whether a command can be undone.
    public var canUndo: Bool { editingDomain.commandStack.canUndo }

    /// Whether a command can be redone.
    public var canRedo: Bool { editingDomain.commandStack.canRedo }

    /// The label of the command that undo would reverse.
    public var undoLabel: String? { editingDomain.commandStack.nextUndoDescription }

    /// The label of the command that redo would re-apply.
    public var redoLabel: String? { editingDomain.commandStack.nextRedoDescription }

    // MARK: - Saving

    /// Whether the model differs from the state recorded by ``markSaved()``.
    ///
    /// A model that has never been marked saved counts as saved while no command has run.
    /// Undoing back to the saved state makes the model clean again, unless the saved state
    /// was discarded by running a new command after undoing past it.
    public var isDirty: Bool {
        editingDomain.commandStack.stateIdentifier != savedStateIdentifier
    }

    /// Records the current state as saved.
    public func markSaved() {
        savedStateIdentifier = editingDomain.commandStack.stateIdentifier
    }

    /// A marker for the current model state, suitable for a pending save.
    ///
    /// The marker remains valid through undo, redo and history trimming.
    /// Capture it alongside the snapshot to be written.
    public var savePoint: SavePoint {
        SavePoint(domainIdentifier: domainIdentifier, stateIdentifier: editingDomain.commandStack.stateIdentifier)
    }

    /// Records a captured model state as saved.
    ///
    /// Later commands and both history stacks are preserved. Markers from
    /// another domain are rejected without changing the saved state.
    ///
    /// - Parameter point: The marker captured with the snapshot that was written.
    /// - Returns: Whether the marker belongs to this domain.
    @discardableResult
    public func markSaved(at point: SavePoint) -> Bool {
        guard point.domainIdentifier == domainIdentifier else { return false }
        savedStateIdentifier = point.stateIdentifier
        return true
    }

    // MARK: - Observation

    /// Registers a handler for changes to the model.
    ///
    /// The handler is called on the main actor after each execution, undo, and redo that
    /// changed the model, once ``snapshot`` shows the new state.
    ///
    /// - Parameter handler: The handler to call with each change set.
    /// - Returns: A token whose ``InstanceObservation/cancel()`` ends the observation.
    public func observe(_ handler: @escaping @MainActor (ResourceChangeSet) -> Void) -> InstanceObservation {
        let identifier = UUID()
        handlers[identifier] = handler
        return InstanceObservation(domain: self, identifier: identifier)
    }

    /// Re-reads the resource, for changes that did not come through the domain.
    ///
    /// - Parameter resourceSet: A resource set to take the metamodels from, if they changed.
    public func reload(metamodelsFrom resourceSet: ResourceSet? = nil) async {
        snapshot = await resource.snapshot()
        metamodels = await Self.registeredMetamodels(of: resourceSet ?? editingDomain.resourceSet)
    }

    fileprivate func deliver(_ changeSet: ResourceChangeSet) async {
        snapshot = await resource.snapshot()
        for handler in Array(handlers.values) { handler(changeSet) }
    }

    private static func registeredMetamodels(of resourceSet: ResourceSet) async -> [EPackage] {
        var result: [EPackage] = []
        for uri in await resourceSet.getMetamodelURIs() {
            if let package = await resourceSet.getMetamodel(uri: uri) { result.append(package) }
        }
        return result
    }

    @MainActor
    private final class Relay: EditingDomainObserver {
        private weak var domain: InstanceEditingDomain?

        init(domain: InstanceEditingDomain) { self.domain = domain }

        func handle(_ event: EditingDomainEvent) async {}

        func changed(_ changeSet: ResourceChangeSet) async {
            await domain?.deliver(changeSet)
        }
    }
}
