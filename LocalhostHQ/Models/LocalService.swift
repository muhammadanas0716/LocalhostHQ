import Foundation

/// Stable identity for a discovered service.
///
/// PID plus port survives refreshes for as long as the process keeps listening,
/// which is what keeps rows from reordering or losing selection. The start time
/// is not part of the identity but *is* checked before reusing cached metadata,
/// so a recycled PID never inherits the previous process's project.
struct ServiceIdentifier: Sendable, Hashable, CustomStringConvertible {
    let pid: Int32
    let port: Int

    var description: String { "\(pid):\(port)" }
}

/// Whether a service looks like the developer's own work or part of the OS.
///
/// macOS has a dozen daemons listening at any moment (`rapportd`, Control
/// Centre's AirPlay receiver, …). They are discovered like anything else but
/// hidden by default so the dashboard stays about the developer's own servers.
enum ServiceOrigin: String, Sendable, Hashable {
    case developer
    case system
}

/// A fully enriched localhost service: the join of a listening port, its owning
/// process, and everything inferred from them.
struct LocalService: Identifiable, Sendable, Hashable {
    let id: ServiceIdentifier
    let listeningPort: ListeningPort
    let process: ProcessSnapshot
    let project: ProjectContext?
    let detection: FrameworkDetection?
    let git: GitInfo?
    let metrics: ProcessMetrics?
    let origin: ServiceOrigin

    var port: Int { listeningPort.port }
    var pid: Int32 { process.pid }
    var framework: Framework? { detection?.framework }
    var category: ServiceCategory { framework?.category ?? .generic }
    var uptime: TimeInterval? { process.uptime }

    /// The name shown in the UI, in the priority order the product specifies:
    /// manifest name, then package directory, then repository directory, then
    /// the process name.
    var displayName: String {
        if let name = project?.displayName, !name.isEmpty { return name }
        return process.name
    }

    /// Subtitle line: `Next.js · main`.
    var subtitle: String {
        var parts: [String] = []
        if let framework { parts.append(framework.displayName) }
        if let branch = git?.branchName { parts.append(branch) }
        return parts.joined(separator: " · ")
    }

    /// Only offered for services that actually speak HTTP and are reachable
    /// through `localhost`.
    var supportsBrowserOpen: Bool {
        guard listeningPort.isReachableViaLocalhost else { return false }
        return framework?.servesHTTP ?? true
    }

    var browserURL: URL? {
        guard supportsBrowserOpen else { return nil }
        return LocalhostURL.make(port: port, preferringTLS: prefersTLS)
    }

    /// Only a handful of dev servers serve TLS locally, and they all say so on
    /// the command line.
    private var prefersTLS: Bool {
        let flags = ["--https", "--experimental-https", "--ssl", "--tls"]
        let command = process.arguments.joined(separator: " ").lowercased()
        return flags.contains { command.contains($0) }
    }

    /// Directory the Finder and Terminal actions act on.
    var actionableDirectory: String? {
        project?.primaryDirectory ?? process.workingDirectory
    }

    /// Repository this service belongs to, if any. Drives grouping.
    var repositoryRoot: String? { project?.repositoryRoot }
}
