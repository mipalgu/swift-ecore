import Testing
@testable import ECore

@Suite("Captured instance save points")
@MainActor
struct InstanceSavePointTests {
    @Test("A delayed save retains subsequent commands and their dirty state")
    func delayedSave() async throws {
        let world = try await LibraryWorld()
        let domain = await InstanceEditingDomain(resource: world.resource, resourceSet: world.resourceSet)
        try await setTitle("One", in: domain, world: world)
        let saved = domain.savePoint
        try await setTitle("Two", in: domain, world: world)
        #expect(domain.markSaved(at: saved))
        #expect(domain.isDirty)
        #expect(domain.undoLabel == "Set title = Two")
        #expect(domain.snapshot.value(of: world.book1.id, feature: "title") as? String == "Two")
        try await domain.undo()
        #expect(!domain.isDirty)
        try await domain.redo()
        #expect(domain.isDirty)
    }

    @Test("Foreign domains cannot change the saved state")
    func foreignDomain() async throws {
        let world = try await LibraryWorld()
        let domain = await InstanceEditingDomain(resource: world.resource, resourceSet: world.resourceSet)
        let foreign = await InstanceEditingDomain(resource: world.resource, resourceSet: world.resourceSet)
        try await setTitle("One", in: domain, world: world)
        #expect(!domain.markSaved(at: foreign.savePoint))
        #expect(domain.isDirty)
        try await domain.undo()
        #expect(!domain.isDirty)
    }

    @Test("Saving an undone state preserves redo commands")
    func undoneState() async throws {
        let world = try await LibraryWorld()
        let domain = await InstanceEditingDomain(resource: world.resource, resourceSet: world.resourceSet)
        let initial = domain.savePoint
        try await setTitle("One", in: domain, world: world)
        #expect(domain.markSaved(at: initial))
        #expect(domain.isDirty)
        try await domain.undo()
        #expect(domain.savePoint == initial)
        #expect(!domain.isDirty)
        #expect(domain.canRedo)
        try await domain.redo()
        #expect(domain.isDirty)
    }

    @Test("A discarded branch cannot become clean at a reused history position")
    func discardedBranch() async throws {
        let world = try await LibraryWorld()
        let domain = await InstanceEditingDomain(resource: world.resource, resourceSet: world.resourceSet)
        try await setTitle("One", in: domain, world: world)
        let saved = domain.savePoint
        try await domain.undo()
        try await setTitle("Two", in: domain, world: world)
        #expect(domain.savePoint != saved)
        #expect(domain.markSaved(at: saved))
        #expect(domain.isDirty)
        try await domain.undo()
        #expect(domain.isDirty)
        try await domain.redo()
        #expect(domain.isDirty)
    }

    @Test("Undoing the oldest retained command reaches its captured prior state")
    func trimmedBoundary() async throws {
        let world = try await LibraryWorld()
        let domain = await InstanceEditingDomain(
            resource: world.resource, resourceSet: world.resourceSet, maxCommandHistory: 1)
        let initial = domain.savePoint
        try await setTitle("One", in: domain, world: world)
        let saved = domain.savePoint
        try await setTitle("Two", in: domain, world: world)
        #expect(domain.markSaved(at: saved))
        try await domain.undo()
        #expect(!domain.canUndo)
        #expect(domain.savePoint == saved)
        #expect(domain.savePoint != initial)
        #expect(!domain.isDirty)
        #expect(domain.markSaved(at: initial))
        #expect(domain.isDirty)
        try await domain.redo()
        #expect(domain.isDirty)
    }

    @Test("Flushing command history preserves the current state's identity")
    func flush() async throws {
        let world = try await LibraryWorld()
        let domain = await InstanceEditingDomain(resource: world.resource, resourceSet: world.resourceSet)
        try await setTitle("One", in: domain, world: world)
        let saved = domain.savePoint
        domain.editingDomain.commandStack.flush()
        #expect(domain.savePoint == saved)
        #expect(domain.markSaved(at: saved))
        #expect(!domain.isDirty)
        try await setTitle("Two", in: domain, world: world)
        #expect(domain.isDirty)
        try await domain.undo()
        #expect(domain.savePoint == saved)
        #expect(!domain.isDirty)
    }

    @Test("Repeated capture and save operations retain token identity")
    func repeatedCapture() async throws {
        let world = try await LibraryWorld()
        let domain = await InstanceEditingDomain(resource: world.resource, resourceSet: world.resourceSet)
        let saved = domain.savePoint
        #expect(Set([saved, domain.savePoint]).count == 1)
        #expect(domain.markSaved(at: saved))
        #expect(domain.markSaved(at: saved))
        #expect(!domain.isDirty)
    }

    /// Changes the fixture's book title through its editing domain.
    ///
    /// - Parameters:
    ///   - title: The new title.
    ///   - domain: The editing domain to use.
    ///   - world: The fixture containing the book and its metamodel.
    private func setTitle(_ title: String, in domain: InstanceEditingDomain, world: LibraryWorld) async throws {
        try await domain.perform(domain.setCommand(object: world.book1, feature: world.model.title, value: title))
    }
}
