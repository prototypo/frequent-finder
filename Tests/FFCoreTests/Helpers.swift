import Foundation

/// A new empty directory under the system temp folder.
func makeTempDir() throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.path
}
