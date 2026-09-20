import Foundation

/// The narrow slice of filesystem access that project detection needs.
///
/// Exists so `ProjectDetector` and `ManifestLoader` can be driven by an
/// in-memory tree in tests instead of scattering fixtures across temp folders.
protocol FileSystemProbing: Sendable {
    func fileExists(atPath path: String) -> Bool
    func directoryExists(atPath path: String) -> Bool
    func contents(atPath path: String) -> Data?
    /// Immediate children (names only). Empty when the path is unreadable.
    func childNames(atPath path: String) -> Set<String>
}

struct LiveFileSystem: FileSystemProbing {
    /// Manifests are small; anything larger is not a manifest we care about.
    private static let maximumManifestBytes = 4 * 1024 * 1024

    func fileExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    func directoryExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    func contents(atPath path: String) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: Self.maximumManifestBytes)
    }

    func childNames(atPath path: String) -> Set<String> {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return Set(names)
    }
}
