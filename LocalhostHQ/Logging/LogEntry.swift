import Foundation

enum LogStream: String, Sendable, Hashable {
    case stdout
    case stderr
}

/// Heuristic severity. Never authoritative — most dev-server output is
/// unstructured text, and the raw line is always preserved.
enum LogLevel: String, Sendable, Hashable, CaseIterable {
    case debug
    case info
    case warning
    case error
}

struct LogEntry: Identifiable, Sendable, Hashable {
    let id: UInt64
    let timestamp: Date
    let stream: LogStream
    /// The line exactly as emitted, minus its trailing newline.
    let message: String
    let level: LogLevel?
}

/// A deterministic explanation of a common failure.
///
/// Pattern matching only — no model calls, no guessing. If a known signature is
/// absent, there is no diagnosis rather than a vague one.
struct LogDiagnosis: Sendable, Hashable {
    let summary: String
    let detail: String
    /// Set when the failure is a port collision, so the UI can go and find out
    /// who actually owns the port.
    let conflictingPort: Int?
}

/// Where a service's output comes from.
///
/// Modelled explicitly because the honest answer is usually "nowhere": macOS
/// offers no way to attach to the stdout of a process we did not start.
enum LogSource: Sendable, Hashable {
    /// Localhost HQ launched the process and holds its pipes.
    case capturedProcess
    /// Not launched by us, so its output is unreachable.
    case unavailable

    var isLive: Bool { self == .capturedProcess }
}
