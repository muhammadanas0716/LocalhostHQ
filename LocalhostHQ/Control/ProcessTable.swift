import Darwin
import Foundation

/// One row of the kernel process table.
struct ProcessTableEntry: Sendable, Hashable, Identifiable {
    let pid: Int32
    let parentPID: Int32
    /// Process group. Shells put each job in its own group, which makes this
    /// the boundary of "the thing the developer started".
    let groupID: Int32
    let userID: uid_t
    let name: String
    let startedAt: Date
    /// A terminated process not yet reaped. Still in the table, but gone.
    let isZombie: Bool

    var id: Int32 { pid }
}

protocol ProcessTableReading: Sendable {
    func snapshot() -> [ProcessTableEntry]
    /// Session id for a pid, or `-1`. Injected so control-root selection can be
    /// tested without live processes.
    func sessionID(of pid: Int32) -> Int32
}

/// Reads the whole process table in one `sysctl` call.
///
/// Measured at ~0.8 ms for 750 processes, so this is affordable on the
/// discovery cadence.
struct SystemProcessTable: ProcessTableReading {

    func snapshot() -> [ProcessTableEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]

        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        // The table can grow between sizing and reading, so over-allocate and
        // trust the size sysctl reports back rather than the one we asked for.
        let stride = MemoryLayout<kinfo_proc>.stride
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
        size = buffer.count * stride
        guard sysctl(&mib, 4, &buffer, &size, nil, 0) == 0 else { return [] }

        let count = min(size / stride, buffer.count)
        return (0..<count).compactMap { index in
            var entry = buffer[index]
            guard entry.kp_proc.p_pid > 0 else { return nil }

            let name = withUnsafeBytes(of: &entry.kp_proc.p_comm) { raw -> String in
                guard let base = raw.baseAddress else { return "" }
                return String(cString: base.assumingMemoryBound(to: CChar.self))
            }
            let started = entry.kp_proc.p_starttime

            return ProcessTableEntry(
                pid: entry.kp_proc.p_pid,
                parentPID: entry.kp_eproc.e_ppid,
                groupID: entry.kp_eproc.e_pgid,
                userID: entry.kp_eproc.e_ucred.cr_uid,
                name: name,
                startedAt: Date(
                    timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000
                ),
                isZombie: entry.kp_proc.p_stat == SZOMB
            )
        }
    }

    func sessionID(of pid: Int32) -> Int32 {
        getsid(pid)
    }
}
