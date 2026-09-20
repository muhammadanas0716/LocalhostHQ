import Darwin
import Foundation

protocol ProcessInspecting: Sendable {
    /// `nil` when the process has already exited.
    func snapshot(pid: Int32) -> ProcessSnapshot?
    /// `nil` when the process exited or the kernel denied the query.
    func cpuSample(pid: Int32) -> ProcessCPUSample?
}

/// Reads process metadata through libproc and sysctl.
///
/// Every call is a direct syscall — no subprocesses — so a refresh over a few
/// dozen PIDs costs well under a millisecond.
///
/// Processes owned by another user (root daemons, for instance) return
/// `EPERM` for the richer queries. That is normal, not an error: the snapshot
/// keeps whatever the kernel did surrender and sets `isRestricted`.
struct ProcessInspector: ProcessInspecting {

    func snapshot(pid: Int32) -> ProcessSnapshot? {
        // kinfo_proc is readable for every process, so its absence is the
        // authoritative signal that the PID is gone.
        guard let kernelInfo = Self.kernelInfo(pid: pid) else { return nil }

        let executablePath = Self.executablePath(pid: pid)
        let workingDirectory = Self.workingDirectory(pid: pid)
        let arguments = Self.arguments(pid: pid)

        let name = executablePath.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? kernelInfo.command

        return ProcessSnapshot(
            pid: pid,
            parentPID: kernelInfo.parentPID == 0 ? nil : kernelInfo.parentPID,
            name: name,
            executablePath: executablePath,
            arguments: arguments,
            workingDirectory: workingDirectory,
            startedAt: kernelInfo.startedAt,
            isRestricted: executablePath == nil || workingDirectory == nil
        )
    }

    func cpuSample(pid: Int32) -> ProcessCPUSample? {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        guard status == 0 else { return nil }

        return ProcessCPUSample(
            cpuNanoseconds: usage.ri_user_time &+ usage.ri_system_time,
            residentMemoryBytes: usage.ri_resident_size,
            takenAt: Date()
        )
    }

    // MARK: - libproc / sysctl

    /// `proc_pidpath` — absolute path of the running executable.
    private static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PROC_PIDPATHINFO_MAXSIZE))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : path
    }

    /// `proc_pidinfo(PROC_PIDVNODEPATHINFO)` — the current working directory.
    /// Denied with `EPERM` for processes owned by other users.
    private static func workingDirectory(pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let written = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, pointer, size)
        }
        guard written == size else { return nil }

        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw -> String in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
        return path.isEmpty ? nil : path
    }

    private struct KernelInfo {
        let parentPID: Int32
        let command: String
        let startedAt: Date?
    }

    /// `sysctl(KERN_PROC_PID)` — parent, short name and start time.
    private static func kernelInfo(pid: Int32) -> KernelInfo? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size

        let status = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        // `size == 0` means the PID vanished between the scan and this call.
        guard status == 0, size > 0 else { return nil }

        let command = withUnsafeBytes(of: &info.kp_proc.p_comm) { raw -> String in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }

        let started = info.kp_proc.p_starttime
        let startedAt: Date? = started.tv_sec > 0
            ? Date(timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000)
            : nil

        return KernelInfo(
            parentPID: info.kp_eproc.e_ppid,
            command: command.isEmpty ? "pid \(pid)" : command,
            startedAt: startedAt
        )
    }

    /// `sysctl(KERN_PROCARGS2)` — the full argument vector.
    ///
    /// Layout: `argc` (Int32), the exec path, NUL padding, then `argc`
    /// NUL-terminated arguments, then the environment. Only the arguments are
    /// read; the environment is skipped because it routinely holds secrets.
    private static func arguments(pid: Int32) -> [String] {
        var argumentMax: Int32 = 0
        var maxSize = MemoryLayout<Int32>.size
        var maxMIB: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&maxMIB, 2, &argumentMax, &maxSize, nil, 0) == 0, argumentMax > 0 else { return [] }

        var buffer = [CChar](repeating: 0, count: Int(argumentMax))
        var bufferSize = Int(argumentMax)
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &bufferSize, nil, 0) == 0 else { return [] }

        let headerSize = MemoryLayout<Int32>.size
        guard bufferSize > headerSize else { return [] }

        var count: Int32 = 0
        withUnsafeMutableBytes(of: &count) { destination in
            buffer.withUnsafeBytes { source in
                destination.copyMemory(from: UnsafeRawBufferPointer(rebasing: source[0..<headerSize]))
            }
        }
        guard count > 0 else { return [] }

        var index = headerSize
        // Skip the exec path and the NUL padding that follows it.
        while index < bufferSize, buffer[index] != 0 { index += 1 }
        while index < bufferSize, buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        arguments.reserveCapacity(Int(count))
        while index < bufferSize, arguments.count < Int(count) {
            let start = index
            while index < bufferSize, buffer[index] != 0 { index += 1 }
            if index > start {
                let slice = buffer[start..<index].map { UInt8(bitPattern: $0) }
                arguments.append(String(decoding: slice, as: UTF8.self))
            }
            index += 1
        }
        return arguments
    }
}
