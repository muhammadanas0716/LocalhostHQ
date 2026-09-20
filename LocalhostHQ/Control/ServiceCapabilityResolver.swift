import Darwin
import Foundation

/// Computes what may safely be done to a service.
///
/// Concentrating this in one place is what lets the views stay free of rules
/// like "don't offer Restart to Postgres": they read flags, not framework names.
struct ServiceCapabilityResolver: Sendable {

    func capabilities(
        process: ProcessSnapshot,
        origin: ServiceOrigin,
        framework: Framework?,
        listeningPort: ListeningPort,
        controlRoot: ControlRoot?,
        launchDescriptor: LaunchDescriptor?,
        hasCapturedLogs: Bool,
        currentUserID: uid_t = getuid()
    ) -> ServiceCapabilities {
        let canOpen = listeningPort.isReachableViaLocalhost && (framework?.servesHTTP ?? true)
        let canReveal = process.workingDirectory != nil && process.workingDirectory != "/"

        let restriction = self.restriction(
            process: process,
            origin: origin,
            controlRoot: controlRoot
        )
        let canStop = restriction == nil && controlRoot != nil

        return ServiceCapabilities(
            canOpenInBrowser: canOpen,
            canRevealInFinder: canReveal,
            canStop: canStop,
            // Force stop is never independently available: it is the escalation
            // of a stop that did not take.
            canForceStop: canStop,
            // Restart needs both the right to stop it and a command to run.
            canRestart: canStop && (launchDescriptor?.isRestartable ?? false),
            canStreamLogs: hasCapturedLogs,
            restriction: restriction
        )
    }

    private func restriction(
        process: ProcessSnapshot,
        origin: ServiceOrigin,
        controlRoot: ControlRoot?
    ) -> ServiceCapabilities.Restriction? {
        // macOS and installed apps look after their own daemons.
        if origin == .system { return .systemService }

        // Identity cannot be verified, so a destructive action cannot be made
        // safe. `startedAt` is what guards against PID reuse.
        if process.startedAt == nil { return .inspectionDenied }

        // Probes existence and permission without delivering a signal.
        if kill(process.pid, 0) != 0 {
            return errno == EPERM ? .notOwnedByUser : .inspectionDenied
        }

        if controlRoot == nil { return .noSafeControlRoot }
        return nil
    }
}
