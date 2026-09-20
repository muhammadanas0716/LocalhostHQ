import Foundation
import OSLog

protocol PortScanning: Sendable {
    /// Every TCP socket in `LISTEN` state, one entry per process/port.
    func listeningPorts() async -> [ListeningPort]
    /// Whoever is listening on one specific port, scanned fresh.
    ///
    /// Used when a restart is about to bind a port: the last discovery snapshot
    /// may be up to a refresh interval stale, which is exactly long enough to
    /// miss the process that just took it.
    func listeners(onPort port: Int) async -> [ListeningPort]
}

/// Discovers listening sockets via `lsof`.
///
/// macOS exposes no public API for enumerating another process's sockets:
/// `proc_pidinfo(PROC_PIDLISTFDS)` plus `PROC_PIDFDSOCKETINFO` works only for
/// processes the caller can inspect and would require walking every PID on the
/// system. `lsof` does that walk in ~40ms in one shot, so it is both the more
/// reliable and the cheaper option. Field output (`-F`) is used so nothing
/// depends on column alignment.
struct LsofPortScanner: PortScanning {
    static let executablePath = "/usr/sbin/lsof"

    private let runner: CommandRunning
    private let executablePath: String
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "PortScanner")

    init(runner: CommandRunning = Shell(), executablePath: String = LsofPortScanner.executablePath) {
        self.runner = runner
        self.executablePath = executablePath
    }

    func listeningPorts() async -> [ListeningPort] {
        await scan(selector: "-iTCP")
    }

    func listeners(onPort port: Int) async -> [ListeningPort] {
        guard (1...65_535).contains(port) else { return [] }
        return await scan(selector: "-iTCP:\(port)")
    }

    private func scan(selector: String) async -> [ListeningPort] {
        let arguments = [
            "-nP",                              // numeric hosts and ports, no DNS
            "-w",                               // suppress warnings about unreadable paths
            "+c", "0",                          // never truncate the command name
            "-F", LsofFieldParser.fieldSelector,
            selector,
            "-sTCP:LISTEN",
        ]

        do {
            let output = try await runner.run(executablePath, arguments: arguments, timeout: .seconds(5))
            // lsof exits non-zero when *some* processes were unreadable while
            // still printing the rest, so stdout is parsed regardless.
            let sockets = LsofFieldParser.parse(output.standardOutput)
            if sockets.isEmpty, !output.succeeded {
                logger.warning("lsof produced no sockets (exit \(output.exitCode)): \(output.standardError, privacy: .public)")
            }
            return LsofFieldParser.deduplicate(sockets)
        } catch {
            logger.error("Port scan failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }
}
