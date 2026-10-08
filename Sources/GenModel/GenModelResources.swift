import Foundation

/// Resolves packaged WASI resources without SwiftPM's build-time bundle paths.
/// Native platforms retain the standard SwiftPM accessor.
enum GenModelResources {
    /// Finds a file or directory in this target's resource bundle.
    ///
    /// - Parameters:
    ///   - name: The resource name without its extension.
    ///   - ext: The extension, or `nil` for a directory or extensionless file.
    ///   - subdirectory: An optional directory within the resource bundle.
    /// - Returns: The resource URL, or `nil` when no accessible resource exists.
    static func url(forResource name: String, withExtension ext: String?, subdirectory: String? = nil) -> URL? {
        #if os(WASI)
        let roots = [
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent(),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        ]
        for root in roots {
            var resource = root.appendingPathComponent("swift-ecore_GenModel.resources", isDirectory: true)
            if let subdirectory { resource.appendPathComponent(subdirectory, isDirectory: true) }
            resource.appendPathComponent(name)
            if let ext { resource.appendPathExtension(ext) }
            if FileManager.default.fileExists(atPath: resource.path) { return resource }
        }
        return nil
        #else
        return Bundle.module.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
        #endif
    }
}
