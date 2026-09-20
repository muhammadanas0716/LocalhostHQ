import Foundation
import Observation

/// Composition root.
///
/// Owns the four systems Part 2 keeps deliberately separate — discovery
/// (what exists), control (what we may do to it), logging (what it is saying)
/// and lifecycle (what happened to it) — and wires them together in one place
/// so no view has to.
@MainActor
@Observable
final class AppEnvironment {
    let services: ServicesStore
    let logs: LogManager
    let lifecycle: LifecycleTracker
    let controller: ServiceController

    init() {
        let logs = LogManager()
        let lifecycle = LifecycleTracker()
        let services = ServicesStore()
        let controller = ServiceController(logs: logs, lifecycle: lifecycle)

        self.logs = logs
        self.lifecycle = lifecycle
        self.services = services
        self.controller = controller

        services.connect(lifecycle: lifecycle, controller: controller, logs: logs)
    }

    /// Preview/testing seam: fixed services, no refresh loop.
    static func preview(services sample: [LocalService]) -> AppEnvironment {
        let environment = AppEnvironment()
        environment.services.applyForPreview(sample)
        return environment
    }

    func start() {
        services.startMonitoring()
    }

    /// Stops services Localhost HQ launched, so they are not orphaned without
    /// their logs when the app quits.
    func shutdown() async {
        services.stopMonitoring()
        await controller.shutdown()
    }
}
