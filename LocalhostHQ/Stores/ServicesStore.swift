import Foundation
import Observation
import OSLog

/// Observable state backing every view.
///
/// Owns the refresh loop and is the only type that touches the discovery actor.
/// `@MainActor` so SwiftUI state is mutated on the main thread by construction;
/// the discovery itself runs on the actor's executor and only its result
/// crosses back.
@MainActor
@Observable
final class ServicesStore {

    // MARK: - Published state

    private(set) var services: [LocalService] = []
    private(set) var groups: [ServiceGroup] = []
    private(set) var isRefreshing = false
    private(set) var lastRefreshedAt: Date?
    /// Set when discovery yields nothing and lsof looks unavailable, so the
    /// empty state can distinguish "nothing running" from "cannot scan".
    private(set) var scannerUnavailable = false

    var searchQuery: String = "" {
        didSet { guard searchQuery != oldValue else { return }; rebuildGroups() }
    }

    var showsSystemServices: Bool = false {
        didSet { guard showsSystemServices != oldValue else { return }; rebuildGroups() }
    }

    /// Services after filtering, flattened. Used by the menu bar and for counts.
    private(set) var visibleServices: [LocalService] = []

    /// The count shown in the menu bar: the developer's own services.
    var developerServiceCount: Int {
        services.count { $0.origin == .developer }
    }

    // MARK: - Dependencies

    private let discovery: LocalhostDiscoveryService
    private let grouper: ServiceGrouper
    private let filter: ServiceFilter
    private let refreshInterval: Duration
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "Store")

    private var refreshTask: Task<Void, Never>?

    /// Set once the control layer exists. The store drives lifecycle
    /// reconciliation because it is what knows when a refresh completed.
    private weak var lifecycle: LifecycleTracker?
    private weak var controller: ServiceController?
    private weak var logs: LogManager?

    init(
        discovery: LocalhostDiscoveryService = LocalhostDiscoveryService(),
        grouper: ServiceGrouper = ServiceGrouper(),
        filter: ServiceFilter = ServiceFilter(),
        refreshInterval: Duration = .seconds(2)
    ) {
        self.discovery = discovery
        self.grouper = grouper
        self.filter = filter
        self.refreshInterval = refreshInterval
    }

    /// Connects the Part 2 systems. Kept separate from `init` to avoid a
    /// circular dependency: the controller needs the tracker, and the store
    /// needs both.
    func connect(lifecycle: LifecycleTracker, controller: ServiceController, logs: LogManager) {
        self.lifecycle = lifecycle
        self.controller = controller
        self.logs = logs
    }

    /// The process tree for a service, for the inspector.
    func processTree(for service: LocalService) async -> ProcessNode? {
        let ports = Dictionary(services.map { ($0.pid, $0.port) }, uniquingKeysWith: { first, _ in first })
        return await discovery.processTree(for: service.pid, listeningPorts: ports)
    }

    // MARK: - Preview seam

    /// Builds a store populated with fixed data and no refresh loop, for
    /// previews and tests.
    static func preview(services: [LocalService]) -> ServicesStore {
        let store = ServicesStore()
        store.applyForPreview(services)
        return store
    }

    /// Seeds fixed services without running lifecycle reconciliation.
    func applyForPreview(_ sample: [LocalService]) {
        services = sample
        lastRefreshedAt = Date()
        rebuildGroups()
    }

    // MARK: - Lifecycle

    /// Starts the periodic refresh. Safe to call repeatedly.
    func startMonitoring() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                // Sleeping *after* the refresh keeps the interval measured from
                // completion, so a slow scan cannot queue up overlapping work.
                do {
                    try await Task.sleep(for: self.refreshInterval)
                } catch {
                    return  // cancelled
                }
            }
        }
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// One refresh, awaited. Overlapping calls are dropped rather than queued.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Capability resolution needs to know which services we are capturing
        // output for, since that is what makes live logs possible.
        if let controller {
            await discovery.setCapturedLogKeys(controller.capturedKeys)
        }

        let discovered = await discovery.discover()
        guard !Task.isCancelled else { return }
        apply(discovered)
    }

    func frameworkRanking(for service: LocalService) async -> [FrameworkDetection] {
        await discovery.frameworkRanking(for: service.id)
    }

    // MARK: - Derivation

    private func apply(_ discovered: [LocalService]) {
        services = discovered
        lastRefreshedAt = Date()
        scannerUnavailable = discovered.isEmpty
            && !FileManager.default.isExecutableFile(atPath: LsofPortScanner.executablePath)

        // Order matters: restarts are matched to their new process before the
        // tracker decides whether anything disappeared, so a relaunched service
        // is never reported as having crashed.
        controller?.reconcileRestarts(with: discovered)
        lifecycle?.reconcile(with: discovered, diagnoses: currentDiagnoses(for: discovered))

        rebuildGroups()
    }

    /// Latest diagnosis per service, so a crash can be explained from whatever
    /// the process last printed.
    private func currentDiagnoses(for discovered: [LocalService]) -> [ServiceKey: LogDiagnosis] {
        guard let logs, let lifecycle else { return [:] }
        var result: [ServiceKey: LogDiagnosis] = [:]
        for key in lifecycle.states.keys {
            if let diagnosis = logs.existingStore(for: key)?.diagnosis {
                result[key] = diagnosis
            }
        }
        return result
    }

    private func rebuildGroups() {
        let candidates = showsSystemServices ? services : services.filter { $0.origin != .system }
        let matching = filter.apply(query: searchQuery, to: candidates)
        visibleServices = matching
        groups = grouper.group(matching)
    }
}
