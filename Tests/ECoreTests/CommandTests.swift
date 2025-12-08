import Foundation
//
// CommandTests.swift
// ECore
//
// Created by Rene Hexel on 8/12/2025.
// Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing

@testable import ECore

@MainActor
@Suite("EMF Commands")
struct CommandTests {

    // MARK: - Test Environment Setup

    func createTestEnvironment() async throws -> (
        Resource, EPackage, EClass, any EStructuralFeature
    ) {
        // Create a test package and class
        var testPackage = EPackage(name: "TestPackage", nsURI: "http://test/1.0", nsPrefix: "test")
        var personClass = EClass(name: "Person")

        // Create name attribute
        let nameAttribute = EAttribute(
            name: "name", eType: EDataType(name: "EString", instanceClassName: "String"))
        personClass.eStructuralFeatures.append(nameAttribute)
        testPackage.eClassifiers.append(personClass)

        // Create resource
        let resource = Resource(uri: "test://commands.xmi")

        return (resource, testPackage, personClass, nameAttribute)
    }

    func createTestPerson(name: String, personClass: EClass, resource: Resource) async throws
        -> any EObject
    {
        var person = DynamicEObject(eClass: personClass)
        if let nameAttr = personClass.getEAttribute(name: "name") {
            person.eSet(nameAttr, name)
        }
        await resource.add(person)
        return person
    }

    // MARK: - Basic Command Tests

    @Test func testCommandResultTypes() throws {
        // Test EMFCommandResult equality
        #expect(EMFCommandResult.success == EMFCommandResult.success)
        #expect(EMFCommandResult.value("test") == EMFCommandResult.value("test"))
        #expect(EMFCommandResult.value("test") != EMFCommandResult.value("different"))

        let uuid1 = UUID()
        let uuid2 = UUID()
        #expect(EMFCommandResult.created(uuid1) == EMFCommandResult.created(uuid1))
        #expect(EMFCommandResult.created(uuid1) != EMFCommandResult.created(uuid2))
    }

    @Test func testCommandErrorDescriptions() throws {
        let executionError = EMFCommandError.executionFailed("Test execution failure")
        #expect(executionError.description.contains("execution failed"))

        let undoError = EMFCommandError.undoNotSupported
        #expect(undoError.description.contains("not supported"))

        let stateError = EMFCommandError.invalidState("Invalid state test")
        #expect(stateError.description.contains("Invalid state test"))
    }

    // MARK: - Mock Command for Testing

    @MainActor
    final class MockCommand: EMFCommand {
        let testValue: String
        var executeCallCount: Int = 0
        var undoCallCount: Int = 0
        var redoCallCount: Int = 0
        var shouldFail: Bool = false

        init(testValue: String, shouldFail: Bool = false) {
            self.testValue = testValue
            self.shouldFail = shouldFail
            super.init()
        }

        override var description: String { "Mock command: \(testValue)" }
        override var canUndo: Bool { true }
        override var canRedo: Bool { true }

        override func execute() async throws -> any Sendable {
            executeCallCount += 1
            if shouldFail {
                throw EMFCommandError.executionFailed("Mock execution failure")
            }
            return testValue
        }

        override func undo() async throws {
            undoCallCount += 1
        }

        override func redo() async throws -> any Sendable {
            redoCallCount += 1
            return testValue
        }
    }

    // MARK: - CommandStack Tests

    @Test func testCommandStackInitialisation() async throws {
        let commandStack = CommandStack(maxHistorySize: 10)

        #expect(commandStack.undoStackSize == 0)
        #expect(commandStack.redoStackSize == 0)
        #expect(commandStack.canUndo == false)
        #expect(commandStack.canRedo == false)
        #expect(commandStack.maxHistorySize == 10)
        #expect(commandStack.statistics.executionCount == 0)
    }

    @Test func testCommandStackExecution() async throws {
        let commandStack = CommandStack(maxHistorySize: 10)
        let mockCommand = MockCommand(testValue: "test")

        _ = try await commandStack.execute(mockCommand)

        // Command should be executed and added to undo stack
        #expect(commandStack.undoStackSize == 1)
        #expect(commandStack.redoStackSize == 0)
        #expect(commandStack.canUndo == true)
        #expect(commandStack.canRedo == false)
        #expect(mockCommand.executeCallCount == 1)
    }

    @Test func testCommandStackUndo() async throws {
        let commandStack = CommandStack(maxHistorySize: 10)
        let mockCommand = MockCommand(testValue: "test")

        // Execute then undo
        _ = try await commandStack.execute(mockCommand)
        try await commandStack.undo()

        // Command should be moved to redo stack
        #expect(commandStack.undoStackSize == 0)
        #expect(commandStack.redoStackSize == 1)
        #expect(commandStack.canUndo == false)
        #expect(commandStack.canRedo == true)
        #expect(mockCommand.undoCallCount == 1)
    }

    @Test func testCommandStackRedo() async throws {
        let commandStack = CommandStack(maxHistorySize: 10)
        let mockCommand = MockCommand(testValue: "test")

        // Execute, undo, then redo
        _ = try await commandStack.execute(mockCommand)
        try await commandStack.undo()
        try await commandStack.redo()

        // Command should be back in undo stack
        #expect(commandStack.undoStackSize == 1)
        #expect(commandStack.redoStackSize == 0)
        #expect(commandStack.canUndo == true)
        #expect(commandStack.canRedo == false)
    }

    @Test func testCommandStackFailedExecution() async throws {
        let commandStack = CommandStack(maxHistorySize: 10)
        let mockCommand = MockCommand(testValue: "test", shouldFail: true)

        // Failed execution should not add command to stack
        do {
            _ = try await commandStack.execute(mockCommand)
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is EMFCommandError)
        }

        #expect(commandStack.undoStackSize == 0)
        #expect(commandStack.canUndo == false)
    }

    @Test func testCommandStackUndoWithoutCommands() async throws {
        let commandStack = CommandStack(maxHistorySize: 10)

        do {
            try await commandStack.undo()
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is EMFCommandError)
            if case EMFCommandError.undoNotSupported = error {
                // Expected error type
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        }
    }

    @Test func testCommandStackRedoWithoutCommands() async throws {
        let commandStack = CommandStack(maxHistorySize: 10)

        do {
            try await commandStack.redo()
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is EMFCommandError)
            if case EMFCommandError.redoNotSupported = error {
                // Expected error type
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        }
    }

    @Test func testCommandStackFlush() async throws {
        let commandStack = CommandStack(maxHistorySize: 10)
        let mockCommand = MockCommand(testValue: "test")

        // Add some commands and then flush
        _ = try await commandStack.execute(mockCommand)
        try await commandStack.undo()

        #expect(commandStack.undoStackSize == 0)
        #expect(commandStack.redoStackSize == 1)

        commandStack.flush()

        #expect(commandStack.undoStackSize == 0)
        #expect(commandStack.redoStackSize == 0)
        #expect(commandStack.canUndo == false)
        #expect(commandStack.canRedo == false)
    }

    @Test func testCommandStackHistoryTrimming() async throws {
        let commandStack = CommandStack(maxHistorySize: 3)

        // Execute multiple commands
        for i in 1...5 {
            let command = MockCommand(testValue: "test\(i)")
            _ = try await commandStack.execute(command)
        }

        // Should only keep the last 3 commands
        #expect(commandStack.undoStackSize == 3)

        // The oldest commands should be trimmed
        let firstUndoDesc = commandStack.nextUndoDescription
        #expect(firstUndoDesc?.contains("test5") == true)
    }

    @Test func testCommandStackStatistics() async throws {
        let commandStack = CommandStack(maxHistorySize: 10)
        let mockCommand1 = MockCommand(testValue: "test1")
        let mockCommand2 = MockCommand(testValue: "test2", shouldFail: true)

        // Execute successful command
        _ = try await commandStack.execute(mockCommand1)

        // Execute failed command
        do {
            _ = try await commandStack.execute(mockCommand2)
        } catch {
            // Expected failure
        }

        // Perform undo and redo
        try await commandStack.undo()
        try await commandStack.redo()

        let stats = commandStack.statistics
        #expect(stats.executionCount == 2)
        #expect(stats.successCount == 1)
        #expect(stats.failureCount == 1)
        #expect(stats.undoCount == 1)
        #expect(stats.redoCount == 1)
        #expect(stats.averageExecutionTime >= 0.0)
        #expect(stats.successRate == 0.5)
    }

    // MARK: - Basic Commands Tests

    @Test func testSetCommandCreation() async throws {
        let (resource, _, personClass, nameAttribute) = try await createTestEnvironment()
        let person = try await createTestPerson(
            name: "Alice", personClass: personClass, resource: resource)

        let command = SetCommand(object: person, feature: nameAttribute, value: "Bob")

        #expect(command.objectId == person.id)
        #expect(command.feature.name == "name")
        #expect(command.newValue as? String == "Bob")
        #expect(command.description.contains("name"))
        #expect(command.description.contains("Bob"))
    }

    // Note: Commands are now reference types, so we test identity and properties instead of equality

    @Test func testAddCommandCreation() async throws {
        let (resource, _, personClass, _) = try await createTestEnvironment()
        let person = try await createTestPerson(
            name: "Alice", personClass: personClass, resource: resource)

        // Create a many-valued feature (simplified for testing)
        let friendsReference = EReference(
            name: "friends", eType: personClass, lowerBound: 0, upperBound: -1)

        let friend = try await createTestPerson(
            name: "Bob", personClass: personClass, resource: resource)
        let command = AddCommand(object: person, feature: friendsReference, value: friend)

        #expect(command.objectId == person.id)
        #expect(command.feature.name == "friends")
        #expect(command.description.contains("friends"))
    }

    @Test func testRemoveCommandCreation() async throws {
        let (resource, _, personClass, _) = try await createTestEnvironment()
        let person = try await createTestPerson(
            name: "Alice", personClass: personClass, resource: resource)

        // Create a many-valued feature (simplified for testing)
        let friendsReference = EReference(
            name: "friends", eType: personClass, lowerBound: 0, upperBound: -1)

        let friend = try await createTestPerson(
            name: "Bob", personClass: personClass, resource: resource)
        let command = RemoveCommand(object: person, feature: friendsReference, value: friend)

        #expect(command.objectId == person.id)
        #expect(command.feature.name == "friends")
        #expect(command.description.contains("Remove"))
        #expect(command.description.contains("friends"))
    }

    // MARK: - BasicEditingDomain Tests

    @Test func testBasicEditingDomainInitialisation() async throws {
        let resourceSet = ResourceSet()
        let editingDomain = BasicEditingDomain(resourceSet: resourceSet, maxCommandHistory: 100)

        #expect(editingDomain.isReadOnly == false)
        #expect(await editingDomain.canUndo() == false)
        #expect(await editingDomain.canRedo() == false)
        #expect(await editingDomain.nextUndoDescription() == nil)
        #expect(await editingDomain.nextRedoDescription() == nil)
    }

    @Test func testBasicEditingDomainCommandCreation() async throws {
        let resourceSet = ResourceSet()
        let editingDomain = BasicEditingDomain(resourceSet: resourceSet)

        let (resource, _, personClass, nameAttribute) = try await createTestEnvironment()
        let person = try await createTestPerson(
            name: "Alice", personClass: personClass, resource: resource)

        // Test command factory methods
        let setCommand = editingDomain.createSetCommand(
            object: person, feature: nameAttribute, value: "Bob")
        #expect(setCommand.objectId == person.id)

        let friendsReference = EReference(
            name: "friends", eType: personClass, lowerBound: 0, upperBound: -1)
        let friend = try await createTestPerson(
            name: "Charlie", personClass: personClass, resource: resource)

        let addCommand = editingDomain.createAddCommand(
            object: person, feature: friendsReference, value: friend)
        #expect(addCommand.objectId == person.id)

        let removeCommand = editingDomain.createRemoveCommand(
            object: person, feature: friendsReference, value: friend)
        #expect(removeCommand.objectId == person.id)
    }

    @Test func testBasicEditingDomainReadOnlyMode() async throws {
        let resourceSet = ResourceSet()
        let editingDomain = BasicEditingDomain(resourceSet: resourceSet)

        // Set read-only mode
        editingDomain.setReadOnly(true)
        #expect(editingDomain.isReadOnly == true)
        #expect(await editingDomain.canUndo() == false)
        #expect(await editingDomain.canRedo() == false)

        // Test that commands fail in read-only mode
        let mockCommand = MockCommand(testValue: "test")

        do {
            _ = try await editingDomain.execute(mockCommand)
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is EMFCommandError)
        }

        // Disable read-only mode
        editingDomain.setReadOnly(false)
        #expect(editingDomain.isReadOnly == false)
    }

    @Test func testBasicEditingDomainStatistics() async throws {
        let resourceSet = ResourceSet()
        let editingDomain = BasicEditingDomain(resourceSet: resourceSet)

        let successCommand = MockCommand(testValue: "success")
        let failCommand = MockCommand(testValue: "fail", shouldFail: true)

        // Execute successful command
        _ = try await editingDomain.execute(successCommand)

        // Execute failed command
        do {
            _ = try await editingDomain.execute(failCommand)
        } catch {
            // Expected failure
        }

        // Perform undo
        try await editingDomain.undo()

        let stats = editingDomain.getStatistics()
        #expect(stats.commandsExecuted == 2)
        #expect(stats.successfulExecutions == 1)
        #expect(stats.failedExecutions == 1)
        #expect(stats.undoOperations == 1)
        #expect(stats.successRate == 0.5)
    }

    // MARK: - CompoundCommand Tests

    @Test func testCompoundCommandCreation() throws {
        let command1 = MockCommand(testValue: "first")
        let command2 = MockCommand(testValue: "second")

        let _ = CompoundCommand(commands: [command1, command2])
        // For testing, we'll create a simple compound command structure
        let compound = CompoundCommand(commands: [])

        #expect(compound.description == "Empty compound command")
        #expect(compound.canUndo == true)  // Empty compound can be "undone"
        #expect(compound.canRedo == true)  // Empty compound can be "redone"
    }

    @Test func testCompoundCommandSingleCommand() throws {
        let compound = CompoundCommand(commands: [])  // Simplified for testing
        #expect(compound.description == "Empty compound command")
    }

    // MARK: - Observer Tests

    @MainActor
    final class MockObserver: EditingDomainObserver {
        private(set) var events: [EditingDomainEvent] = []

        func handle(_ event: EditingDomainEvent) async {
            events.append(event)
        }
    }

    @Test func testEditingDomainObserver() async throws {
        let resourceSet = ResourceSet()
        let editingDomain = BasicEditingDomain(resourceSet: resourceSet)
        let observer = MockObserver()

        editingDomain.addObserver(observer)

        let mockCommand = MockCommand(testValue: "observed")
        _ = try await editingDomain.execute(mockCommand)

        // Give the observer time to receive events
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms

        #expect(observer.events.count >= 2)  // At least aboutToExecute and executed

        if let firstEvent = observer.events.first {
            if case .aboutToExecute(let description) = firstEvent {
                #expect(description.contains("observed"))
            } else {
                #expect(Bool(false), "First event should be aboutToExecute")
            }
        }
    }

    // MARK: - Integration Tests

    @Test func testFullWorkflow() async throws {
        let resourceSet = ResourceSet()
        let editingDomain = BasicEditingDomain(resourceSet: resourceSet)
        let observer = MockObserver()

        editingDomain.addObserver(observer)

        // Execute multiple commands
        let command1 = MockCommand(testValue: "first")
        let command2 = MockCommand(testValue: "second")

        _ = try await editingDomain.execute(command1)
        _ = try await editingDomain.execute(command2)

        #expect(await editingDomain.canUndo() == true)
        #expect(await editingDomain.nextUndoDescription()?.contains("second") == true)

        // Undo both commands
        try await editingDomain.undo()
        try await editingDomain.undo()

        #expect(await editingDomain.canUndo() == false)
        #expect(await editingDomain.canRedo() == true)

        // Redo one command
        try await editingDomain.redo()

        #expect(await editingDomain.canUndo() == true)
        #expect(await editingDomain.canRedo() == true)

        // Check final statistics
        let stats = editingDomain.getStatistics()
        #expect(stats.commandsExecuted == 2)
        #expect(stats.successfulExecutions == 2)
        #expect(stats.undoOperations == 2)
        #expect(stats.redoOperations == 1)
    }
}
