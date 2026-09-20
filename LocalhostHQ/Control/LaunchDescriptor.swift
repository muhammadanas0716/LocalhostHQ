import Foundation

/// How confident we are that a reconstructed command would actually restart
/// the service.
enum LaunchConfidence: Int, Sendable, Hashable, Comparable {
    /// Not reconstructable; restart must not be offered.
    case none = 0
    /// Plausible but unverified — the command is shown, restart stays hidden.
    case low = 1
    /// The executable and directory check out.
    case medium = 2
    /// The full original command line was recovered intact.
    case high = 3

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .none: "Unavailable"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

/// Everything needed to relaunch a service.
///
/// Note on environment: the environment of a running process is **not**
/// recoverable through public macOS APIs — `KERN_PROCARGS2` exposes it only for
/// our own processes, and reading another process's environment would leak
/// secrets besides. A relaunch therefore inherits Localhost HQ's environment
/// plus the recovered working directory, which is correct for the common case
/// of a shell-launched dev server but will not reproduce variables that were
/// exported only in that shell. This is stated in the UI rather than papered
/// over.
struct LaunchDescriptor: Sendable, Hashable {
    let executableURL: URL
    let arguments: [String]
    let workingDirectory: URL
    let confidence: LaunchConfidence
    /// Which process the command was recovered from, for the debug panel.
    let recoveredFrom: String

    /// Shell-style rendering for display only. Never executed — launching goes
    /// through `Process.executableURL` and `arguments`, so no quoting bug can
    /// become a command injection.
    var displayCommand: String {
        ([executableURL.lastPathComponent] + arguments)
            .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
            .joined(separator: " ")
    }

    var isRestartable: Bool { confidence >= .medium }
}

/// Rebuilds a launch command from a running process.
///
/// The command is taken from the *control root* — the top of the job — because
/// that is what the developer actually typed. Relaunching the leaf would
/// restart `next-server` rather than `pnpm dev`, losing the supervisor.
struct LaunchDescriptorBuilder: Sendable {

    private let fileSystem: FileSystemProbing

    init(fileSystem: FileSystemProbing = LiveFileSystem()) {
        self.fileSystem = fileSystem
    }

    func descriptor(for snapshot: ProcessSnapshot) -> LaunchDescriptor? {
        guard let executablePath = snapshot.executablePath,
              let workingDirectory = snapshot.workingDirectory,
              !snapshot.arguments.isEmpty
        else { return nil }

        // A cwd of "/" means the process was started somewhere we cannot
        // reproduce; relaunching there would not find the project.
        guard workingDirectory != "/", fileSystem.directoryExists(atPath: workingDirectory) else { return nil }
        guard fileSystem.fileExists(atPath: executablePath) else { return nil }

        let arguments = Array(snapshot.arguments.dropFirst())
        let confidence = Self.confidence(
            executablePath: executablePath,
            arguments: snapshot.arguments
        )
        guard confidence > .none else { return nil }

        return LaunchDescriptor(
            executableURL: URL(fileURLWithPath: executablePath),
            arguments: arguments,
            workingDirectory: URL(fileURLWithPath: workingDirectory),
            confidence: confidence,
            recoveredFrom: "pid \(snapshot.pid) (\(snapshot.name))"
        )
    }

    /// Grades a recovered command.
    ///
    /// The case that matters is a rewritten process title. Next.js replaces its
    /// worker's `argv` with `next-server (v15.0.3)`, which is a label, not a
    /// command — relaunching it would fail. Such a title is detectable because
    /// it bears no relation to the executable and is not path-like.
    static func confidence(executablePath: String, arguments: [String]) -> LaunchConfidence {
        guard let argv0 = arguments.first else { return .none }

        let executableName = URL(fileURLWithPath: executablePath).lastPathComponent
        let argv0Name = URL(fileURLWithPath: argv0).lastPathComponent

        // argv[0] normally echoes the executable, either as a path or a name.
        let echoesExecutable = argv0Name == executableName
            || argv0.hasPrefix("/")
            || argv0Name.hasPrefix(executableName)
            || executableName.hasPrefix(argv0Name)

        if !echoesExecutable {
            // A rewritten title: spaces or parentheses where a command would
            // have neither.
            let looksLikeLabel = argv0.contains(" ") || argv0.contains("(")
                || arguments.contains { $0.contains("(") && $0.contains(")") }
            if looksLikeLabel { return .none }
            // Unusual but not obviously a label, e.g. a renamed binary.
            return .low
        }

        // A bare executable with no operands is rarely a whole dev command.
        return arguments.count > 1 ? .high : .medium
    }
}
