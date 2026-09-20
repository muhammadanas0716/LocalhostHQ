import Foundation
@testable import LocalhostHQ

/// In-memory filesystem for detector tests.
///
/// Directories are implied by the paths of the files added to it, so a fixture
/// reads as the tree it represents.
struct FakeFileSystem: FileSystemProbing {
    private var files: [String: Data] = [:]
    private var directories: Set<String> = ["/"]

    init(files: [String: String] = [:], emptyDirectories: [String] = []) {
        for (path, contents) in files { addFile(path, contents: contents) }
        for path in emptyDirectories { addDirectory(path) }
    }

    mutating func addFile(_ path: String, contents: String = "") {
        files[path] = Data(contents.utf8)
        if let parent = ProjectDetector.parent(of: path) { addDirectory(parent) }
    }

    mutating func addDirectory(_ path: String) {
        var current = ProjectDetector.normalize(path)
        while true {
            directories.insert(current)
            guard let parent = ProjectDetector.parent(of: current), parent != current else { break }
            current = parent
        }
    }

    func fileExists(atPath path: String) -> Bool {
        files[path] != nil
    }

    func directoryExists(atPath path: String) -> Bool {
        directories.contains(ProjectDetector.normalize(path))
    }

    func contents(atPath path: String) -> Data? {
        files[path]
    }

    func childNames(atPath path: String) -> Set<String> {
        let prefix = ProjectDetector.normalize(path) + "/"
        var names: Set<String> = []
        for candidate in files.keys.map(String.init) + directories.map(String.init) {
            guard candidate.hasPrefix(prefix) else { continue }
            let remainder = candidate.dropFirst(prefix.count)
            guard !remainder.isEmpty else { continue }
            names.insert(String(remainder.split(separator: "/")[0]))
        }
        return names
    }
}
