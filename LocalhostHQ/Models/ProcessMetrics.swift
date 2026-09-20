import Foundation

/// A CPU/memory sample for one process.
///
/// Uptime is deliberately absent: `ProcessSnapshot.startedAt` is the single
/// source of truth for it.
struct ProcessMetrics: Sendable, Hashable {
    /// Share of **one** CPU core, averaged over the interval between the two
    /// most recent samples. A process saturating four cores reports ~400%, so
    /// this value is never clamped to 100.
    ///
    /// `nil` until a second sample exists — a rate needs two points.
    let cpuPercent: Double?
    let residentMemoryBytes: UInt64
    let sampledAt: Date
}

/// Raw counters read from `proc_pid_rusage`, from which a rate is derived.
struct ProcessCPUSample: Sendable, Hashable {
    /// Cumulative user + system CPU time, in nanoseconds.
    let cpuNanoseconds: UInt64
    let residentMemoryBytes: UInt64
    let takenAt: Date
}
