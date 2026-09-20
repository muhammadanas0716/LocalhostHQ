import Foundation

/// Identifies one concrete running process, precisely enough to be safe to
/// signal.
///
/// A PID alone is not safe: PIDs are recycled, and the window between
/// discovering a service and acting on it is easily long enough for the
/// original process to exit and its number to be reissued. Start time is the
/// discriminator — the kernel's `p_starttime` is fixed for the life of a
/// process and differs for any replacement.
///
/// Every destructive operation re-reads the live process and compares against
/// the identity captured at discovery. A mismatch aborts the operation.
struct ProcessInstanceIdentity: Sendable, Hashable {
    let pid: Int32
    /// The discriminator. `nil` only when the kernel refused the query, in
    /// which case verification cannot succeed and control is refused.
    let startedAt: Date?
    let executablePath: String?

    /// Start times come from a `timeval`, so compare with microsecond
    /// tolerance rather than for exact equality.
    private static let tolerance: TimeInterval = 0.000_002

    /// Whether `other` is the same running process.
    func matches(_ other: ProcessInstanceIdentity) -> Bool {
        guard pid == other.pid else { return false }

        // Without a start time on either side there is nothing to distinguish a
        // recycled PID, so the match is refused rather than assumed.
        guard let mine = startedAt, let theirs = other.startedAt else { return false }
        guard abs(mine.timeIntervalSince(theirs)) <= Self.tolerance else { return false }

        // The executable can legitimately be unknown on one side (a restricted
        // process), but a *different* known path means a different program.
        if let a = executablePath, let b = other.executablePath, a != b { return false }
        return true
    }
}

extension ProcessSnapshot {
    var instanceIdentity: ProcessInstanceIdentity {
        ProcessInstanceIdentity(pid: pid, startedAt: startedAt, executablePath: executablePath)
    }
}
