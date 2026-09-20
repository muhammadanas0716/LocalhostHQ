import Foundation

/// Turns cumulative CPU counters into a rate.
///
/// `proc_pid_rusage` reports total CPU time consumed since launch, so a
/// percentage only exists relative to a previous sample. The first observation
/// of a process therefore reports `nil` CPU rather than a fabricated zero or a
/// since-launch average, which would badly misrepresent a server that was busy
/// during startup and is idle now.
///
/// Not thread-safe by design: it is owned by `LocalhostDiscoveryService`, whose
/// actor isolation already serialises access.
final class MetricsCollector {
    private let inspector: ProcessInspecting
    private var previousSamples: [Int32: ProcessCPUSample] = [:]

    init(inspector: ProcessInspecting = ProcessInspector()) {
        self.inspector = inspector
    }

    /// Samples one process. `nil` when the process exited or denied inspection.
    func metrics(for pid: Int32) -> ProcessMetrics? {
        guard let sample = inspector.cpuSample(pid: pid) else {
            previousSamples.removeValue(forKey: pid)
            return nil
        }
        defer { previousSamples[pid] = sample }

        return ProcessMetrics(
            cpuPercent: previousSamples[pid].flatMap { Self.cpuPercent(from: $0, to: sample) },
            residentMemoryBytes: sample.residentMemoryBytes,
            sampledAt: sample.takenAt
        )
    }

    /// Discards state for processes that are no longer listening.
    func retain(pids: Set<Int32>) {
        previousSamples = previousSamples.filter { pids.contains($0.key) }
    }

    /// Percentage of a single core between two samples.
    ///
    /// Exposed for testing; the arithmetic is the part worth pinning down.
    static func cpuPercent(from previous: ProcessCPUSample, to current: ProcessCPUSample) -> Double? {
        let elapsed = current.takenAt.timeIntervalSince(previous.takenAt)
        // Too small an interval makes the quotient meaningless.
        guard elapsed > 0.05 else { return nil }
        // Counters are monotonic; a decrease means the PID was recycled.
        guard current.cpuNanoseconds >= previous.cpuNanoseconds else { return nil }

        let consumedSeconds = Double(current.cpuNanoseconds - previous.cpuNanoseconds) / 1_000_000_000
        return max(0, consumedSeconds / elapsed * 100)
    }
}
