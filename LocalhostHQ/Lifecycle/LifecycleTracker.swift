import Foundation
import Observation

/// Tracks runtime state and recent events for every service seen this session.
///
/// Its job is to answer one question Part 1 could not: when a service vanishes,
/// *why*. Discovery only reports what is listening now, so an intentional stop
/// and a crash look identical from there. The difference is intent, which only
/// this type knows, because operations declare themselves before acting.
@MainActor
@Observable
final class LifecycleTracker {

    /// Enough history to explain a recent problem, not an audit log.
    static let maximumEvents = 200

    private(set) var events: [ServiceEvent] = []
    private(set) var states: [ServiceKey: ServiceRuntimeState] = [:]

    /// Last known good snapshot per key, so a vanished service can still be
    /// described after it is gone from discovery.
    private(set) var lastKnown: [ServiceKey: LocalService] = [:]

    /// Keys with a deliberate stop in flight. The reason a disappearance is
    /// reported as "Stopped" rather than "Exited unexpectedly".
    private var intentionalTransitions: Set<ServiceKey> = []

    /// Exit statuses for processes Localhost HQ launched, which are the only
    /// ones whose status macOS will tell us.
    private var recordedExitCodes: [ServiceKey: Int32] = [:]

    // MARK: - Queries

    func state(for key: ServiceKey) -> ServiceRuntimeState {
        states[key] ?? .running
    }

    func events(for key: ServiceKey) -> [ServiceEvent] {
        events.filter { $0.serviceKey == key }
    }

    /// Services that have terminated but are still worth showing, so a crash
    /// does not simply vanish from the dashboard.
    var terminatedServices: [LocalService] {
        states
            .filter { $0.value.isTerminated }
            .compactMap { lastKnown[$0.key] }
            .sorted { $0.port < $1.port }
    }

    // MARK: - Operation intent

    /// Declares that a disappearance is expected.
    func beginIntentionalTransition(_ key: ServiceKey, state: ServiceRuntimeState) {
        intentionalTransitions.insert(key)
        states[key] = state
    }

    func endIntentionalTransition(_ key: ServiceKey) {
        intentionalTransitions.remove(key)
    }

    func setState(_ state: ServiceRuntimeState, for key: ServiceKey) {
        states[key] = state
    }

    func recordExitCode(_ code: Int32, for key: ServiceKey) {
        recordedExitCodes[key] = code
    }

    func record(_ event: ServiceEvent) {
        events.append(event)
        if events.count > Self.maximumEvents {
            events.removeFirst(events.count - Self.maximumEvents)
        }
    }

    // MARK: - Reconciliation

    /// Folds a discovery result into lifecycle state.
    ///
    /// Called on every refresh. Must tolerate services appearing and vanishing
    /// mid-operation without producing spurious crash reports.
    func reconcile(with services: [LocalService], diagnoses: [ServiceKey: LogDiagnosis] = [:]) {
        let currentKeys = Set(services.map(\.key))

        for service in services {
            let key = service.key
            let previous = states[key]
            lastKnown[key] = service

            switch previous {
            case .none:
                states[key] = .running
                record(ServiceEvent(
                    kind: .discovered,
                    serviceKey: key,
                    serviceName: service.displayName,
                    message: "Discovered on port \(service.port)"
                ))

            case .starting, .restarting:
                // The relaunch came back.
                states[key] = .running
                intentionalTransitions.remove(key)
                record(ServiceEvent(
                    kind: .restarted,
                    serviceKey: key,
                    serviceName: service.displayName,
                    message: "Running again on port \(service.port) as PID \(service.pid)"
                ))

            case .stopped, .failed, .unknown:
                // Came back on its own, or was restarted outside the app.
                states[key] = .running
                record(ServiceEvent(
                    kind: .started,
                    serviceKey: key,
                    serviceName: service.displayName,
                    message: "Started on port \(service.port)"
                ))

            case .running, .stopping:
                // `.stopping` stays until the process actually disappears.
                if previous == .running { states[key] = .running }
            }
        }

        for (key, state) in states where !currentKeys.contains(key) {
            handleDisappearance(key: key, state: state, diagnosis: diagnoses[key])
        }
    }

    private func handleDisappearance(
        key: ServiceKey,
        state: ServiceRuntimeState,
        diagnosis: LogDiagnosis?
    ) {
        guard let service = lastKnown[key] else { return }

        switch state {
        case .stopped, .failed:
            return    // already accounted for

        case .restarting, .starting:
            // Expected: the old process is gone and the new one has not bound
            // its port yet. Not a crash, and not an error.
            return

        case .stopping:
            states[key] = .stopped(.requested, exitInfo(for: key, service: service, diagnosis: nil))
            intentionalTransitions.remove(key)
            record(ServiceEvent(
                kind: .stopped,
                serviceKey: key,
                serviceName: service.displayName,
                message: "Stopped"
            ))

        case .running, .unknown:
            // No operation was in flight, so this was not our doing.
            let info = exitInfo(for: key, service: service, diagnosis: diagnosis)
            states[key] = .stopped(.unexpected, info)
            record(ServiceEvent(
                kind: .crashed,
                serviceKey: key,
                serviceName: service.displayName,
                message: crashMessage(info: info, diagnosis: diagnosis)
            ))
        }
    }

    private func crashMessage(info: ExitInfo, diagnosis: LogDiagnosis?) -> String {
        var parts = ["Exited unexpectedly"]
        if let code = info.exitCode { parts.append("exit code \(code)") }
        if let diagnosis { parts.append(diagnosis.summary.lowercased()) }
        return parts.joined(separator: " · ")
    }

    private func exitInfo(
        for key: ServiceKey,
        service: LocalService,
        diagnosis: LogDiagnosis?
    ) -> ExitInfo {
        ExitInfo(
            terminatedAt: Date(),
            exitCode: recordedExitCodes[key],
            runtime: service.process.startedAt.map { Date().timeIntervalSince($0) },
            diagnosis: diagnosis
        )
    }

    /// Forgets a terminated service, when the user dismisses it.
    func forget(_ key: ServiceKey) {
        states.removeValue(forKey: key)
        lastKnown.removeValue(forKey: key)
        recordedExitCodes.removeValue(forKey: key)
        intentionalTransitions.remove(key)
    }
}
