import Foundation
import Observation
import OSLog

/// High-level service control.
///
/// Views call `stop`, `forceStop` and `restart` here; nothing in the UI ever
/// sees a PID or a signal. The controller owns the safety rules — verify
/// identity, resolve a control root, never escalate silently — and the
/// bookkeeping that keeps overlapping operations from colliding.
@MainActor
@Observable
final class ServiceController {

    // MARK: - Observable state

    private(set) var operations: [ServiceKey: ServiceOperation] = [:]
    /// Set when a graceful stop timed out and the user must choose.
    var forceStopPrompt: ForceStopPrompt?
    /// Set when a restart could not bind its port.
    var portConflict: PortConflict?
    /// Result of the most recent project-wide operation.
    var projectReport: ProjectOperationReport?

    // MARK: - Dependencies

    private let processController: ProcessController
    private let launcher: ProcessLauncher
    private let conflictResolver: PortConflictResolver
    private let logs: LogManager
    private let lifecycle: LifecycleTracker
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "ServiceController")

    /// Restarts waiting for their new process to appear in discovery.
    private var pendingRestarts: [ServiceKey: PendingRestart] = [:]
    /// Services whose output Localhost HQ is capturing.
    private(set) var capturedKeys: Set<ServiceKey> = []

    private struct PendingRestart {
        let anchor: ServiceKey.Anchor
        let originalPort: Int
        let launchedPID: Int32
        let serviceName: String
        let deadline: Date
    }

    init(
        processController: ProcessController = ProcessController(),
        launcher: ProcessLauncher = ProcessLauncher(),
        conflictResolver: PortConflictResolver = PortConflictResolver(),
        logs: LogManager,
        lifecycle: LifecycleTracker
    ) {
        self.processController = processController
        self.launcher = launcher
        self.conflictResolver = conflictResolver
        self.logs = logs
        self.lifecycle = lifecycle
    }

    // MARK: - Queries

    func operation(for key: ServiceKey) -> ServiceOperation? { operations[key] }
    func isBusy(_ key: ServiceKey) -> Bool { operations[key] != nil }

    // MARK: - Stop

    func stop(_ service: LocalService) async {
        let key = service.key
        guard operations[key] == nil, service.capabilities.canStop else { return }

        begin(.stopping, for: key)
        lifecycle.beginIntentionalTransition(key, state: .stopping)
        defer { finish(key) }

        do {
            try await processController.stop(service.instanceIdentity)
            lifecycle.setState(.stopped(.requested, nil), for: key)
            lifecycle.record(ServiceEvent(
                kind: .stopped,
                serviceKey: key,
                serviceName: service.displayName,
                message: "Stopped by request"
            ))
            logs.existingStore(for: key)?.appendNotice("Stopped by Localhost HQ")
        } catch let error as ProcessControlError {
            handleStopFailure(error, service: service, key: key)
        } catch {
            fail(key, service: service, message: error.localizedDescription)
        }
    }

    private func handleStopFailure(_ error: ProcessControlError, service: LocalService, key: ServiceKey) {
        switch error {
        case .didNotExit(let remaining):
            // Do not escalate silently — ask.
            lifecycle.setState(.running, for: key)
            lifecycle.endIntentionalTransition(key)
            forceStopPrompt = ForceStopPrompt(
                service: service,
                remainingPIDs: remaining,
                waitedFor: .seconds(5)
            )
        case .alreadyGone:
            // Raced with the process exiting on its own: the goal is met.
            lifecycle.setState(.stopped(.requested, nil), for: key)
        default:
            fail(key, service: service, message: error.explanation)
        }
    }

    /// SIGKILL. Only reachable from an explicit user confirmation.
    func forceStop(_ prompt: ForceStopPrompt) async {
        let key = prompt.service.key
        forceStopPrompt = nil
        guard operations[key] == nil else { return }

        begin(.forceStopping, for: key)
        lifecycle.beginIntentionalTransition(key, state: .stopping)
        defer { finish(key) }

        do {
            try await processController.forceStop(pids: prompt.remainingPIDs)
            lifecycle.setState(.stopped(.requested, nil), for: key)
            lifecycle.record(ServiceEvent(
                kind: .stopped,
                serviceKey: key,
                serviceName: prompt.service.displayName,
                message: "Force stopped"
            ))
            logs.existingStore(for: key)?.appendNotice("Force stopped by Localhost HQ")
        } catch let error as ProcessControlError {
            fail(key, service: prompt.service, message: error.explanation)
        } catch {
            fail(key, service: prompt.service, message: error.localizedDescription)
        }
    }

    // MARK: - Restart

    func restart(_ service: LocalService) async {
        let key = service.key
        guard operations[key] == nil,
              service.capabilities.canRestart,
              let descriptor = service.launchDescriptor
        else { return }

        begin(.restarting, for: key)
        lifecycle.beginIntentionalTransition(key, state: .restarting)

        let store = logs.store(for: key)
        store.appendNotice("Restarting: \(descriptor.displayCommand)")

        do {
            // 1. Stop the existing instance, verifying identity first.
            let stoppedPIDs = try await stopForRestart(service)

            // 2. Make sure the port is actually free. A framework that falls
            // back to another port would otherwise look like a silent success.
            if let conflict = await conflictResolver.conflict(
                onPort: service.port,
                excluding: Set(stoppedPIDs)
            ) {
                portConflict = conflict
                lifecycle.record(ServiceEvent(
                    kind: .portConflict,
                    serviceKey: key,
                    serviceName: service.displayName,
                    message: "Port \(service.port) is held by \(conflict.ownerDisplayName) (PID \(conflict.ownerPID))"
                ))
                store.appendNotice("Port \(service.port) is in use by \(conflict.ownerDisplayName)")
                lifecycle.setState(
                    .failed("Port \(service.port) is already in use by \(conflict.ownerDisplayName)."),
                    for: key
                )
                finish(key)
                return
            }

            // 3. Relaunch, capturing output this time.
            let launched = try await launch(descriptor, key: key, store: store)

            lifecycle.setState(.starting, for: key)
            pendingRestarts[key] = PendingRestart(
                anchor: key.anchor,
                originalPort: service.port,
                launchedPID: launched.pid,
                serviceName: service.displayName,
                // Generous: a cold Next.js build can take a while.
                deadline: Date().addingTimeInterval(45)
            )
            lifecycle.record(ServiceEvent(
                kind: .restarted,
                serviceKey: key,
                serviceName: service.displayName,
                message: "Relaunched as PID \(launched.pid)"
            ))
        } catch let error as ProcessControlError {
            if case .didNotExit(let remaining) = error {
                lifecycle.endIntentionalTransition(key)
                lifecycle.setState(.running, for: key)
                forceStopPrompt = ForceStopPrompt(
                    service: service,
                    remainingPIDs: remaining,
                    waitedFor: .seconds(5)
                )
            } else {
                fail(key, service: service, message: error.explanation)
            }
        } catch let error as LaunchError {
            store.appendNotice("Restart failed: \(error.explanation)")
            fail(key, service: service, message: error.explanation)
        } catch {
            fail(key, service: service, message: error.localizedDescription)
        }

        finish(key)
    }

    /// Stops an instance as part of a restart, returning the PIDs signalled.
    private func stopForRestart(_ service: LocalService) async throws -> [Int32] {
        do {
            let root = try await processController.stop(service.instanceIdentity)
            return root.memberPIDs
        } catch ProcessControlError.alreadyGone {
            // It exited on its own first; nothing to stop.
            return service.controlRoot?.memberPIDs ?? [service.pid]
        }
    }

    private func launch(
        _ descriptor: LaunchDescriptor,
        key: ServiceKey,
        store: LogStore
    ) async throws -> LaunchedProcess {
        let launched = try await launcher.launch(
            descriptor,
            onOutput: { [weak self] lines, stream in
                Task { @MainActor [weak self] in
                    guard self != nil else { return }
                    store.append(lines: lines, stream: stream)
                }
            },
            onExit: { [weak self] code in
                Task { @MainActor [weak self] in
                    self?.handleLaunchedExit(key: key, code: code, store: store)
                }
            }
        )
        capturedKeys.insert(key)
        store.setSource(.capturedProcess)
        return launched
    }

    /// A process we launched has exited, so its status is genuinely knowable.
    private func handleLaunchedExit(key: ServiceKey, code: Int32, store: LogStore) {
        capturedKeys.remove(key)
        lifecycle.recordExitCode(code, for: key)
        store.appendNotice(code == 0 ? "Process exited" : "Process exited with code \(code)")

        // A non-zero exit during startup is a failed restart, not a crash of a
        // running service.
        if let pending = pendingRestarts[key], code != 0 {
            pendingRestarts.removeValue(forKey: key)
            let diagnosis = store.diagnosis
            lifecycle.setState(
                .failed(diagnosis?.summary ?? "Exited with code \(code) during startup."),
                for: key
            )
            lifecycle.record(ServiceEvent(
                kind: .operationFailed,
                serviceKey: key,
                serviceName: pending.serviceName,
                message: "Restart failed: \(diagnosis?.summary ?? "exit code \(code)")"
            ))
            Task { await correlatePortConflict(diagnosis: diagnosis, port: pending.originalPort) }
        }
    }

    /// Turns an `EADDRINUSE` in the output into a named owner.
    private func correlatePortConflict(diagnosis: LogDiagnosis?, port: Int) async {
        guard let diagnosis else { return }
        guard let conflict = await conflictResolver.conflict(
            matching: diagnosis,
            fallbackPort: port
        ) else { return }
        portConflict = conflict
    }

    // MARK: - Restart association

    /// Matches relaunched services back to their logical identity.
    ///
    /// Called after every discovery refresh. A framework that fell back to
    /// another port (`3000 in use, trying 3001`) still shares its anchor, so it
    /// is recognised and its logs follow it.
    func reconcileRestarts(with services: [LocalService]) {
        guard !pendingRestarts.isEmpty else { return }

        for (key, pending) in pendingRestarts {
            if services.contains(where: { $0.key == key }) {
                pendingRestarts.removeValue(forKey: key)
                continue
            }

            // Same place on disk, different port.
            if let moved = services.first(where: { candidate in
                candidate.key.anchor == pending.anchor && candidate.port != pending.originalPort
            }) {
                pendingRestarts.removeValue(forKey: key)
                logs.rekey(from: key, to: moved.key)
                if capturedKeys.remove(key) != nil { capturedKeys.insert(moved.key) }
                lifecycle.setState(.running, for: moved.key)
                lifecycle.record(ServiceEvent(
                    kind: .restarted,
                    serviceKey: moved.key,
                    serviceName: moved.displayName,
                    message: "Restarted on port \(moved.port) (was \(pending.originalPort))"
                ))
                continue
            }

            if Date() > pending.deadline {
                pendingRestarts.removeValue(forKey: key)
                lifecycle.setState(.failed("The service did not start listening within 45 seconds."), for: key)
                lifecycle.record(ServiceEvent(
                    kind: .operationFailed,
                    serviceKey: key,
                    serviceName: pending.serviceName,
                    message: "Restart timed out"
                ))
            }
        }
    }

    // MARK: - Port conflicts

    /// Stops whichever process is holding a port, after explicit confirmation.
    func freePort(_ conflict: PortConflict) async {
        guard conflict.isStoppable, let identity = conflict.ownerIdentity else { return }
        do {
            try await processController.stop(identity)
            portConflict = nil
        } catch let error as ProcessControlError {
            if case .didNotExit = error, let service = conflict.ownerService {
                forceStopPrompt = ForceStopPrompt(
                    service: service,
                    remainingPIDs: [conflict.ownerPID],
                    waitedFor: .seconds(5)
                )
                portConflict = nil
            } else {
                logger.error("free port failed: \(error.explanation, privacy: .public)")
            }
        } catch {
            logger.error("free port failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Project operations

    func restartProject(named title: String, services: [LocalService]) async {
        let eligible = services.filter { $0.capabilities.canRestart }
        guard !eligible.isEmpty else { return }

        var items: [ProjectOperationReport.Item] = []
        // Sequential on purpose: parallel restarts inside one project fight
        // over ports and saturate the machine.
        for service in eligible {
            await restart(service)
            let state = lifecycle.state(for: service.key)
            if case .failed(let message) = state {
                items.append(.init(name: service.displayName, succeeded: false, detail: message))
            } else {
                items.append(.init(name: service.displayName, succeeded: true, detail: nil))
            }
        }

        for skipped in services where !skipped.capabilities.canRestart {
            items.append(.init(
                name: skipped.displayName,
                succeeded: false,
                detail: skipped.capabilities.restriction?.explanation ?? "No reliable launch command was recovered."
            ))
        }

        projectReport = ProjectOperationReport(title: "Restart \(title)", items: items)
    }

    func stopProject(named title: String, services: [LocalService]) async {
        let eligible = services.filter { $0.capabilities.canStop }
        guard !eligible.isEmpty else { return }

        var items: [ProjectOperationReport.Item] = []
        for service in eligible {
            await stop(service)
            let state = lifecycle.state(for: service.key)
            if case .failed(let message) = state {
                items.append(.init(name: service.displayName, succeeded: false, detail: message))
            } else {
                items.append(.init(name: service.displayName, succeeded: true, detail: nil))
            }
        }
        projectReport = ProjectOperationReport(title: "Stop \(title)", items: items)
    }

    /// Terminates everything Localhost HQ launched. Called on quit so captured
    /// dev servers are not orphaned.
    func shutdown() async {
        await launcher.terminateAll()
    }

    // MARK: - Bookkeeping

    private func begin(_ kind: ServiceOperation.Kind, for key: ServiceKey) {
        operations[key] = ServiceOperation(serviceKey: key, kind: kind, startedAt: Date())
    }

    private func finish(_ key: ServiceKey) {
        operations.removeValue(forKey: key)
    }

    private func fail(_ key: ServiceKey, service: LocalService, message: String) {
        lifecycle.endIntentionalTransition(key)
        lifecycle.setState(.failed(message), for: key)
        lifecycle.record(ServiceEvent(
            kind: .operationFailed,
            serviceKey: key,
            serviceName: service.displayName,
            message: message
        ))
        logger.error("operation failed for \(key.description, privacy: .public): \(message, privacy: .public)")
    }
}
