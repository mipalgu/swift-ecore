import ECore
import Foundation

/// Resolves the resources of this target.
///
/// The bundle of the target is used where Foundation supports it; on WASI the resource
/// directory named by ``bundleName`` is found beside the executable.
enum GenModelResources {
    /// The name of the resource directory of this target.
    static let bundleName = ResourceBundleName(
        package: GenModelConstants.resourcePackageName, target: GenModelConstants.resourceTargetName)

    /// Finds a file or directory in this target's resource bundle.
    ///
    /// - Parameters:
    ///   - name: The resource name without its extension.
    ///   - ext: The extension, or `nil` for a directory or extensionless file.
    ///   - subdirectory: An optional directory within the resource bundle.
    /// - Returns: The resource URL, or `nil` when no accessible resource exists.
    static func url(forResource name: String, withExtension ext: String?, subdirectory: String? = nil) -> URL? {
        BundledResources.url(
            forResource: name, withExtension: ext, subdirectory: subdirectory, in: .module,
            bundleName: bundleName)
    }
}
