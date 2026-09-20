import Foundation

/// How a service terminated.
struct ExitInfo: Sendable, Hashable {
    let terminatedAt: Date
    /// Known only for processes Localhost HQ launched itself. The kernel does
    /// not expose the exit status of a process we are not the parent of, and
    /// inventing one would be worse than admitting it is unknown.
    let exitCode: Int32?
    /// How long the process ran, when its start time was known.
    let runtime: TimeInterval?
    /// Deterministic explanation derived from the service's last output, if any.
    let diagnosis: LogDiagnosis?
}

/// Why a service is no longer running.
enum StopReason: Sendable, Hashable {
    /// Localhost HQ asked it to stop and it did.
    case requested
    /// It vanished without a stop request.
    case unexpected
}

/// Lifecycle state of a service.
///
/// Deliberately not a Boolean: the UI has to distinguish "stopping" from
/// "stopped", and an intentional stop from a crash, and must never offer
/// Restart to something already restarting.
enum ServiceRuntimeState: Sendable, Hashable {
    case running
    /// A graceful stop is in flight.
    case stopping
    case stopped(StopReason, ExitInfo?)
    /// Stop phase of a restart.
    case restarting
    /// Relaunched; waiting for the port to be listening again.
    case starting
    /// An operation failed. Carries a message already fit to show a person.
    case failed(String)
    /// The process is gone and we cannot say why (discovery lost it while an
    /// operation was in flight).
    case unknown

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    /// True while an operation owns the service, so controls must be disabled.
    var isBusy: Bool {
        switch self {
        case .stopping, .restarting, .starting: true
        case .running, .stopped, .failed, .unknown: false
        }
    }

    var isTerminated: Bool {
        switch self {
        case .stopped, .failed: true
        case .running, .stopping, .restarting, .starting, .unknown: false
        }
    }

    var label: String {
        switch self {
        case .running: "Running"
        case .stopping: "Stopping…"
        case .restarting: "Restarting…"
        case .starting: "Starting…"
        case .stopped(.requested, _): "Stopped"
        case .stopped(.unexpected, _): "Exited unexpectedly"
        case .failed: "Failed"
        case .unknown: "Unknown"
        }
    }
}
