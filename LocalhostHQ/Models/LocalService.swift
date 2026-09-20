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
    /// Which processes belong to this service and may be signalled.
    /// `nil` when no safe root could be established.
    var controlRoot: ControlRoot?
    /// Reconstructed launch command, when one could be recovered.
    var launchDescriptor: LaunchDescriptor?
    /// What the UI is allowed to offer.
    var capabilities: ServiceCapabilities = .none

    /// Identity to verify before any destructive action.
    var instanceIdentity: ProcessInstanceIdentity { process.instanceIdentity }

    var port: Int { listeningPort.port }
    var pid: Int32 { process.pid }
    var framework: Framework? { detection?.framework }
    var category: ServiceCategory { framework?.category ?? .generic }
    var uptime: TimeInterval? { process.uptime }

    /// The name shown in the UI: manifest name, then package directory, then
    /// repository directory, then the recognised framework, then the process.
    ///
    /// A recognised framework outranks the executable because it is what the
    /// developer actually calls the thing — "Jupyter" rather than
    /// `python3.12`, "PostgreSQL" rather than `postgres`.
    var displayName: String {
        if let name = project?.displayName, !name.isEmpty { return name }
        if let framework { return framework.displayName }
        return process.name
    }

    /// Subtitle line: `Next.js · main`.
    ///
    /// The framework is omitted when it already supplied the title, so an
    /// infrastructure service does not read "PostgreSQL / PostgreSQL".
    var subtitle: String {
        var parts: [String] = []
        if let framework, framework.displayName != displayName {
            parts.append(framework.displayName)
        }
        if let branch = git?.branchName { parts.append(branch) }
        return parts.joined(separator: " · ")
    }

    /// Only offered for services that actually speak HTTP and are reachable
    /// through `localhost`.
    var supportsBrowserOpen: Bool {
        Self.servesBrowsableHTTP(listeningPort: listeningPort, framework: framework)
    }

    /// The single definition of the rule, shared with
    /// `ServiceCapabilityResolver` so it is not restated there.
    static func servesBrowsableHTTP(listeningPort: ListeningPort, framework: Framework?) -> Bool {
        guard listeningPort.isReachableViaLocalhost else { return false }
        // An unrecognised process on a local port is more likely to be a web
        // server than not, so the benefit of the doubt goes to offering it.
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
