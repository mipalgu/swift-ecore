import ECore
import Foundation

/// Resolves packaged WASI resources without SwiftPM's build-time bundle paths.
/// Native platforms retain the standard SwiftPM accessor.
enum GenModelResources {
    /// The resource directory that SwiftPM builds for this target.
    static let bundleName = ResourceBundleName(package: "swift-ecore", target: "GenModel")

    /// Finds a file or directory in this target's resource bundle.
    ///
    /// - Parameters:
    ///   - name: The resource name without its extension.
    ///   - ext: The extension, or `nil` for a directory or extensionless file.
    ///   - subdirectory: An optional directory within the resource bundle.
    /// - Returns: The resource URL, or `nil` when no accessible resource exists.
    static func url(forResource name: String, withExtension ext: String?, subdirectory: String? = nil) -> URL? {
        #if os(WASI)
        return BundledResources.url(
            forResource: name, withExtension: ext, subdirectory: subdirectory, in: nil, bundleName: bundleName)
        #else
        return BundledResources.url(forResource: name, withExtension: ext, subdirectory: subdirectory, in: .module)
        #endif
    }
}
