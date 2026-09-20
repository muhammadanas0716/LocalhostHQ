import Foundation

/// Everything known about the process that owns a listening socket.
///
/// This is the single home for process facts — no other model duplicates them.
/// Every field beyond `pid` is optional because macOS denies inspection of
/// processes owned by other users, and because a process can exit between
/// being discovered and being inspected.
struct ProcessSnapshot: Sendable, Hashable {
    let pid: Int32
    let parentPID: Int32?
    /// Best available name: the executable's basename when known, otherwise the
    /// kernel's `p_comm`, otherwise lsof's command field.
    let name: String
    let executablePath: String?
    /// Full `argv`. Empty when `KERN_PROCARGS2` is denied.
    let arguments: [String]
    let workingDirectory: String?
    let startedAt: Date?
    /// True when the kernel denied the richer per-process queries, so the UI can
    /// explain missing fields rather than showing them as blank.
    let isRestricted: Bool

    var commandLine: String? {
        arguments.isEmpty ? nil : arguments.joined(separator: " ")
    }

    var uptime: TimeInterval? {
        startedAt.map { Date().timeIntervalSince($0) }
    }
}
