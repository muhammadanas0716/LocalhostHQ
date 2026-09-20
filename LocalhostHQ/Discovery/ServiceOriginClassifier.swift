import Foundation

/// Decides whether a listening service is the developer's own work or part of
/// macOS / an installed app.
///
/// A typical Mac has a dozen daemons listening at any moment — `rapportd`,
/// Control Centre's AirPlay receiver on :5000 and :7000, Spotify's discovery
/// port. They are still discovered and still shown behind a toggle, but they
/// are not what the dashboard is about, so they are separated rather than
/// padding out the developer's project list.
struct ServiceOriginClassifier: Sendable {

    /// Executable prefixes owned by the operating system.
    private static let systemPrefixes = [
        "/System/",
        "/usr/libexec/",
        "/usr/sbin/",
        "/Library/Apple/",
        "/Library/PrivilegedHelperTools/",
    ]

    /// Infrastructure that lives in system-ish locations but is unambiguously
    /// something a developer installed and cares about.
    private static let alwaysDeveloper: Set<String> = [
        "postgres", "mysql", "mongodb", "redis", "docker", "supabase",
    ]

    func classify(process: ProcessSnapshot, project: ProjectContext?, framework: Framework?) -> ServiceOrigin {
        if let framework, Self.alwaysDeveloper.contains(framework.id) { return .developer }

        // Anything resolved to a real project on disk is the developer's.
        if project?.packageRoot != nil || project?.repositoryRoot != nil { return .developer }

        guard let executablePath = process.executablePath else {
            // Inspection was denied, which in practice means a root daemon.
            return process.isRestricted ? .system : .developer
        }

        if Self.systemPrefixes.contains(where: executablePath.hasPrefix) { return .system }

        // A GUI app listening on a port without any project context is doing
        // its own thing (Spotify Connect, AirPlay, IDE helpers).
        if executablePath.contains(".app/Contents/") { return .system }

        return .developer
    }
}
