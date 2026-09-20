import Darwin
import Foundation
import OSLog

enum ProcessControlError: Error, Sendable, Equatable {
    /// The PID no longer refers to the process that was discovered.
    case identityChanged
    case notPermitted
    case alreadyGone
    case noSafeControlRoot
    /// SIGTERM was delivered but the process was still alive at the deadline.
    case didNotExit(remaining: [Int32])

    /// Message fit to show a person, per the product's error guidance.
    var explanation: String {
        switch self {
        case .identityChanged:
            "This process has changed since it was discovered. Refresh before controlling it."
        case .notPermitted:
            "Localhost HQ does not have permission to signal this process."
        case .alreadyGone:
            "The process had already exited."
        case .noSafeControlRoot:
            "Localhost HQ could not determine which processes belong to this service, so it did not signal any of them."
        case .didNotExit:
            "The service did not stop when asked."
        }
    }
}

/// Sends signals to verified processes and waits for them to exit.
///
/// Every destructive call re-reads the live process and compares it against the
/// identity captured at discovery. Nothing is signalled on the strength of a
/// PID or a process name alone.
///
/// An actor so that two overlapping operations cannot interleave signals
/// against the same process.
actor ProcessController {

    private let table: ProcessTableReading
    private let treeInspector: ProcessTreeInspector
    private let inspector: ProcessInspecting
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "ProcessController")

    init(
        table: ProcessTableReading = SystemProcessTable(),
        treeInspector: ProcessTreeInspector? = nil,
        inspector: ProcessInspecting = ProcessInspector()
    ) {
        self.table = table
        self.treeInspector = treeInspector ?? ProcessTreeInspector(table: table)
        self.inspector = inspector
    }

    // MARK: - Identity

    /// Confirms the PID still refers to the same process.
    func verify(_ identity: ProcessInstanceIdentity) -> Bool {
        guard let live = inspector.snapshot(pid: identity.pid) else { return false }
        return identity.matches(live.instanceIdentity)
    }

    /// True when the process exists and we may signal it.
    nonisolated func isSignalable(pid: Int32) -> Bool {
        // Signal 0 performs the permission and existence checks without
        // delivering anything.
        kill(pid, 0) == 0
    }

    func isRunning(pid: Int32) -> Bool {
        guard let entry = table.snapshot().first(where: { $0.pid == pid }) else { return false }
        // A zombie has terminated; it merely has not been reaped.
        return !entry.isZombie
    }

    // MARK: - Control root

    /// Resolves what may be signalled for a service, verifying identity first.
    func controlRoot(for identity: ProcessInstanceIdentity) throws -> ControlRoot {
        guard verify(identity) else {
            throw inspector.snapshot(pid: identity.pid) == nil
                ? ProcessControlError.alreadyGone
                : ProcessControlError.identityChanged
        }
        guard let root = treeInspector.controlRoot(for: identity.pid, in: table.snapshot()) else {
            throw ProcessControlError.noSafeControlRoot
        }
        return root
    }

    // MARK: - Stopping

    /// Asks a service to stop, and waits.
    ///
    /// SIGTERM only — escalation to SIGKILL is never automatic, because a dev
    /// server killed outright can leave a corrupt build cache or an orphaned
    /// child. `forceStop` is a separate, explicit action.
    @discardableResult
    func stop(
        _ identity: ProcessInstanceIdentity,
        timeout: Duration = .seconds(5)
    ) async throws -> ControlRoot {
        let root = try controlRoot(for: identity)
        try send(SIGTERM, to: root.memberPIDs)

        let remaining = await waitForExit(of: root.memberPIDs, timeout: timeout)
        guard remaining.isEmpty else {
            throw ProcessControlError.didNotExit(remaining: remaining)
        }
        return root
    }

    /// Last resort: SIGKILL, which cannot be caught.
    @discardableResult
    func forceStop(
        _ identity: ProcessInstanceIdentity,
        timeout: Duration = .seconds(3)
    ) async throws -> ControlRoot {
        let root = try controlRoot(for: identity)
        try send(SIGKILL, to: root.memberPIDs)

        let remaining = await waitForExit(of: root.memberPIDs, timeout: timeout)
        guard remaining.isEmpty else {
            throw ProcessControlError.didNotExit(remaining: remaining)
        }
        return root
    }

    /// Kills a set of PIDs already resolved by a previous `stop` attempt.
    /// Used by the escalation path so the tree is not re-resolved after the
    /// service has partially exited.
    func forceStop(pids: [Int32], timeout: Duration = .seconds(3)) async throws {
        let alive = pids.filter { isSignalable(pid: $0) }
        guard !alive.isEmpty else { return }
        try send(SIGKILL, to: alive)

        let remaining = await waitForExit(of: alive, timeout: timeout)
        guard remaining.isEmpty else {
            throw ProcessControlError.didNotExit(remaining: remaining)
        }
    }

    // MARK: - Primitives

    /// Signals children before parents, so a supervisor does not restart a
    /// child in the window between the two signals.
    private func send(_ signal: Int32, to pids: [Int32]) throws {
        var sawPermissionFailure = false
        var delivered = 0

        for pid in pids.reversed() {
            guard pid > 1 else { continue }
            if kill(pid, signal) == 0 {
                delivered += 1
                continue
            }
            switch errno {
            case ESRCH:
                continue    // already gone; entirely normal mid-teardown
            case EPERM:
                sawPermissionFailure = true
            default:
                logger.error("signal \(signal) to \(pid) failed: errno \(errno)")
            }
        }

        if delivered == 0 {
            if sawPermissionFailure { throw ProcessControlError.notPermitted }
            throw ProcessControlError.alreadyGone
        }
    }

    /// Polls until every PID has exited, or the deadline passes.
    /// Returns whichever are still alive.
    private func waitForExit(of pids: [Int32], timeout: Duration) async -> [Int32] {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var alive = pids

        while ContinuousClock.now < deadline {
            alive = alive.filter { isSignalable(pid: $0) && isRunning(pid: $0) }
            if alive.isEmpty { return [] }
            try? await Task.sleep(for: .milliseconds(60))
        }
        return alive.filter { isSignalable(pid: $0) && isRunning(pid: $0) }
    }
}
