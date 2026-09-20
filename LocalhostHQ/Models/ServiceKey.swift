import Foundation

/// Logical identity of a service, stable across restarts.
///
/// `ServiceIdentifier` (PID + port) identifies one *process instance* and by
/// design changes when a service restarts. Logs, lifecycle history, runtime
/// state and the dashboard selection all need to survive that, so they are
/// keyed by this instead.
///
/// The anchor is the most durable thing known about where the service lives.
/// A package root is preferred because it outlives both the PID and the port —
/// a dev server that comes back on 3001 because 3000 was taken is still the
/// same logical service.
struct ServiceKey: Sendable, Hashable, CustomStringConvertible {

    enum Anchor: Sendable, Hashable {
        /// The package directory the service runs from — the strongest anchor.
        case package(String)
        /// No package, but a known working directory.
        case directory(String)
        /// Neither: an infrastructure daemon, anchored on its binary.
        case executable(String)
        /// Nothing durable is known; falls back to the port alone.
        case port
    }

    let anchor: Anchor
    let port: Int

    var description: String {
        switch anchor {
        case .package(let path): "package:\(path):\(port)"
        case .directory(let path): "dir:\(path):\(port)"
        case .executable(let path): "exec:\(path):\(port)"
        case .port: "port:\(port)"
        }
    }

    /// True when both keys describe the same place on disk, ignoring the port.
    ///
    /// Used to re-associate a service that came back on a different port.
    func sharesAnchor(with other: ServiceKey) -> Bool {
        guard anchor != .port else { return false }
        return anchor == other.anchor
    }
}

extension LocalService {
    /// Logical key for this service.
    var key: ServiceKey {
        ServiceKey(anchor: Self.anchor(project: project, process: process), port: port)
    }

    static func anchor(project: ProjectContext?, process: ProcessSnapshot) -> ServiceKey.Anchor {
        if let packageRoot = project?.packageRoot { return .package(packageRoot) }
        if let directory = project?.workingDirectory ?? process.workingDirectory,
           directory != "/" {
            return .directory(directory)
        }
        if let executable = process.executablePath { return .executable(executable) }
        return .port
    }
}

/// `Codable` so the key can address a `WindowGroup` value scene — SwiftUI
/// requires window payloads to be codable.
extension ServiceKey: Codable {
    private enum CodingKeys: String, CodingKey { case kind, path, port }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        port = try container.decode(Int.self, forKey: .port)
        anchor = switch kind {
        case "package": .package(path)
        case "directory": .directory(path)
        case "executable": .executable(path)
        default: .port
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(port, forKey: .port)
        switch anchor {
        case .package(let path):
            try container.encode("package", forKey: .kind)
            try container.encode(path, forKey: .path)
        case .directory(let path):
            try container.encode("directory", forKey: .kind)
            try container.encode(path, forKey: .path)
        case .executable(let path):
            try container.encode("executable", forKey: .kind)
            try container.encode(path, forKey: .path)
        case .port:
            try container.encode("port", forKey: .kind)
        }
    }
}
