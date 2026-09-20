import Foundation

/// Decides whether a listening service is the developer's own work or part of
/// macOS / an installed app.
///
/// A typical Mac has a dozen daemons listening at any moment — `rapportd`,
/// Control Centre's AirPlay receiver on :5000 and :7000, Spotify's discovery
/// port. They are still discovered and still shown behind a toggle, but they
/// are not what the dashboard is about, so they are separated rather than
/// padding out the developer's project list.
///
/// The rules are ordered deliberately and err towards `.developer`: wrongly
/// hiding a developer's own server is far worse than showing one extra daemon.
struct ServiceOriginClassifier: Sendable {

    /// Executable prefixes owned by the operating system.
    private static let systemPrefixes = [
        "/System/",
        "/usr/libexec/",
        "/usr/sbin/",
        "/Library/Apple/",
        "/Library/PrivilegedHelperTools/",
    ]

    /// Directories that hold installed applications. An `.app` bundle here is a
    /// shipped product, so its helpers are not the developer's own servers.
    private static let applicationDirectories = [
        "/Applications/",
        "/System/Applications/",
    ]

    /// Infrastructure that lives in system-ish locations but is unambiguously
    /// something a developer installed and cares about.
    private static let alwaysDeveloper: Set<String> = [
        "postgres", "mysql", "mongodb", "redis", "docker", "supabase",
    ]

    func classify(process: ProcessSnapshot, project: ProjectContext?, framework: Framework?) -> ServiceOrigin {
        if let framework, Self.alwaysDeveloper.contains(framework.id) { return .developer }

        if let executablePath = process.executablePath {
            if Self.systemPrefixes.contains(where: executablePath.hasPrefix) { return .system }
            if isBundledApplicationHelper(executablePath) { return .system }
        }

        // Resolved to a real project on disk: unambiguously the developer's.
        if project?.packageRoot != nil || project?.repositoryRoot != nil { return .developer }

        // No executable path means the kernel denied inspection, which in
        // practice means a daemon owned by root.
        guard process.executablePath != nil else { return .system }

        return .developer
    }

    /// True only for executables inside an `.app` bundle that sits in an
    /// applications directory.
    ///
    /// Testing for `.app/Contents/` alone is not enough: python.org ships its
    /// interpreter as `Python.framework/.../Resources/Python.app/Contents/MacOS/Python`,
    /// so that test would hide every Flask, Django and FastAPI server run on a
    /// python.org build.
    private func isBundledApplicationHelper(_ executablePath: String) -> Bool {
        guard executablePath.contains(".app/Contents/") else { return false }
        if Self.applicationDirectories.contains(where: executablePath.hasPrefix) { return true }
        // Per-user installs, e.g. ~/Applications/Foo.app.
        let userApplications = NSHomeDirectory() + "/Applications/"
        return executablePath.hasPrefix(userApplications)
    }
}
