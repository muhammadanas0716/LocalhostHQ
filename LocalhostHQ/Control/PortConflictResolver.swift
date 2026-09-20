import Darwin
import Foundation

/// Who currently holds a port, described well enough to act on.
struct PortConflict: Sendable, Hashable {
    let port: Int
    let ownerPID: Int32
    let ownerName: String
    /// Present when the owner is itself a discovered service, which gives the
    /// project, uptime and metrics for free.
    let ownerService: LocalService?
    /// Identity captured at detection, so a later "Stop Process" acts on
    /// exactly this process and not a recycled PID.
    let ownerIdentity: ProcessInstanceIdentity?
    let ownerDirectory: String?
    let ownerStartedAt: Date?
    /// Whether this process may be signalled — ours, and not a system service.
    let isStoppable: Bool

    var ownerDisplayName: String {
        ownerService?.displayName ?? ownerName
    }

    var uptime: TimeInterval? {
        ownerStartedAt.map { Date().timeIntervalSince($0) }
    }
}

/// Works out who owns a port, and whether it is safe to free.
///
/// Used in two directions: before a restart, to explain why a relaunch would
/// fail; and after a crash whose output mentions `EADDRINUSE`, to turn a raw
/// stderr line into "port 3000 is held by this other project".
struct PortConflictResolver: Sendable {

    private let scanner: PortScanning
    private let inspector: ProcessInspecting
    private let classifier: ServiceOriginClassifier

    init(
        scanner: PortScanning = LsofPortScanner(),
        inspector: ProcessInspecting = ProcessInspector(),
        classifier: ServiceOriginClassifier = ServiceOriginClassifier()
    ) {
        self.scanner = scanner
        self.inspector = inspector
        self.classifier = classifier
    }

    /// Current owner of `port`, if any.
    ///
    /// - Parameter excluding: PIDs that belong to the service being restarted,
    ///   which must not be reported as conflicting with themselves.
    func conflict(
        onPort port: Int,
        excluding excludedPIDs: Set<Int32> = [],
        knownServices: [LocalService] = []
    ) async -> PortConflict? {
        let listeners = await scanner.listeners(onPort: port)
        guard let owner = listeners.first(where: { !excludedPIDs.contains($0.pid) }) else { return nil }

        let snapshot = inspector.snapshot(pid: owner.pid)
        let service = knownServices.first { $0.pid == owner.pid && $0.port == port }

        // Only claim it is stoppable when it is genuinely ours to signal.
        let isOurs = kill(owner.pid, 0) == 0
        let isSystem = service?.origin == .system
        let stoppable = isOurs && !isSystem && snapshot != nil

        return PortConflict(
            port: port,
            ownerPID: owner.pid,
            ownerName: snapshot?.name ?? owner.processName,
            ownerService: service,
            ownerIdentity: snapshot?.instanceIdentity,
            ownerDirectory: service?.actionableDirectory ?? snapshot?.workingDirectory,
            ownerStartedAt: snapshot?.startedAt,
            isStoppable: stoppable
        )
    }

    /// Correlates a crash diagnosis that mentions a port with its real owner.
    func conflict(
        matching diagnosis: LogDiagnosis,
        fallbackPort: Int,
        excluding excludedPIDs: Set<Int32> = [],
        knownServices: [LocalService] = []
    ) async -> PortConflict? {
        guard diagnosis.conflictingPort != nil || diagnosis.summary.lowercased().contains("port") else {
            return nil
        }
        let port = diagnosis.conflictingPort ?? fallbackPort
        return await conflict(onPort: port, excluding: excludedPIDs, knownServices: knownServices)
    }
}
