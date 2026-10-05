import Foundation
import Testing

@testable import ECore

/// Verifies file-writing behaviour on each supported runtime.
@Suite("File handler portability")
struct FileURIHandlerPortabilityTests {
    /// Checks that the selected writing mode is supported by the runtime.
    @Test("The file writing mode supports the current runtime")
    func writingMode() {
        #if os(WASI)
        #expect(FileURIHandler.writingOptions.isEmpty)
        #else
        #expect(FileURIHandler.writingOptions == .atomic)
        #endif
    }

    /// Checks that replacing a file truncates the previous contents.
    @Test("Writing replaces the complete contents of an existing file")
    func replacesContents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let uri = directory.appendingPathComponent("document.ecore").absoluteString
        let handler = FileURIHandler()
        try await handler.write(Data("previous contents".utf8), to: uri)
        try await handler.write(Data("new".utf8), to: uri)
        #expect(try await handler.read(uri) == Data("new".utf8))
    }
}
