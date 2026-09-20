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

    // MARK: - Preview seam

    /// Builds a store populated with fixed data and no refresh loop, for
    /// previews and tests.
    static func preview(services: [LocalService]) -> ServicesStore {
        let store = ServicesStore()
        store.apply(services)
        return store
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
        rebuildGroups()
    }

    private func rebuildGroups() {
        let candidates = showsSystemServices ? services : services.filter { $0.origin != .system }
        let matching = filter.apply(query: searchQuery, to: candidates)
        visibleServices = matching
        groups = grouper.group(matching)
    }
}
