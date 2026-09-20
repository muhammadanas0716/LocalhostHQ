import Foundation
import OSLog

/// Composes the discovery pipeline:
///
/// ```
/// listening socket → process → cwd → project → framework → git → metrics
/// ```
///
/// An actor because a refresh touches mutable caches and may overlap with the
/// previous one; isolation removes that race without any locking.
///
/// The work is split by cost. Metrics are pure syscalls and are resampled every
/// tick. Project, manifest, framework and git resolution touch the filesystem
/// and are therefore cached: per service identity for as long as the process
/// lives, and per repository path on a short TTL so a branch switch still shows
/// up. In the steady state a tick runs one `lsof` and a handful of syscalls.
actor LocalhostDiscoveryService {

    /// Static metadata held for the lifetime of a process.
    private struct EnrichedMetadata: Sendable {
        /// Guards against PID reuse: a recycled PID has a different start time
        /// and must not inherit the previous process's project.
        let startedAt: Date?
        let project: ProjectContext?
        let detection: FrameworkDetection?
        let ranking: [FrameworkDetection]
        let origin: ServiceOrigin
        let controlRoot: ControlRoot?
        let launchDescriptor: LaunchDescriptor?
    }

    private let portScanner: PortScanning
    private let processInspector: ProcessInspecting
    private let projectDetector: ProjectDetector
    private let manifestLoader: ManifestLoader
    private let frameworkDetector: FrameworkDetector
    private let gitInspector: GitInspecting
    private let originClassifier: ServiceOriginClassifier
    private let metricsCollector: MetricsCollector
    private let processTable: ProcessTableReading
    private let treeInspector: ProcessTreeInspector
    private let launchBuilder: LaunchDescriptorBuilder
    private let capabilityResolver: ServiceCapabilityResolver
    /// Keys whose logs Localhost HQ is capturing, set by the controller.
    private var capturedLogKeys: Set<ServiceKey> = []

    private var metadataCache: [ServiceIdentifier: EnrichedMetadata] = [:]
    /// Keyed by the directory queried, since git resolves any path to its root.
    private var gitCache: TimedCache<String, GitInfo?>
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "Discovery")

    init(
        portScanner: PortScanning = LsofPortScanner(),
        processInspector: ProcessInspecting = ProcessInspector(),
        projectDetector: ProjectDetector = ProjectDetector(),
        manifestLoader: ManifestLoader = ManifestLoader(),
        frameworkDetector: FrameworkDetector = FrameworkDetector(),
        gitInspector: GitInspecting = GitInspector(),
        originClassifier: ServiceOriginClassifier = ServiceOriginClassifier(),
        processTable: ProcessTableReading = SystemProcessTable(),
        launchBuilder: LaunchDescriptorBuilder = LaunchDescriptorBuilder(),
        capabilityResolver: ServiceCapabilityResolver = ServiceCapabilityResolver(),
        gitCacheLifetime: Duration = .seconds(20)
    ) {
        self.portScanner = portScanner
        self.processInspector = processInspector
        self.projectDetector = projectDetector
        self.manifestLoader = manifestLoader
        self.frameworkDetector = frameworkDetector
        self.gitInspector = gitInspector
        self.originClassifier = originClassifier
        self.metricsCollector = MetricsCollector(inspector: processInspector)
        self.processTable = processTable
        self.treeInspector = ProcessTreeInspector(table: processTable)
        self.launchBuilder = launchBuilder
        self.capabilityResolver = capabilityResolver
        self.gitCache = TimedCache(lifetime: gitCacheLifetime)
    }

    /// Told by the controller which services it is capturing output for, so
    /// capabilities can report live logs accurately.
    func setCapturedLogKeys(_ keys: Set<ServiceKey>) {
        capturedLogKeys = keys
    }

    /// The process tree for a service, for the inspector's tree view.
    func processTree(for pid: Int32, listeningPorts: [Int32: Int]) -> ProcessNode? {
        treeInspector.tree(rootedAt: pid, in: processTable.snapshot(), listeningPorts: listeningPorts)
    }

    /// One full refresh. Never throws: a failure of any single stage degrades
    /// that service's detail rather than the whole scan.
    func discover() async -> [LocalService] {
        let ports = await portScanner.listeningPorts()
        guard !ports.isEmpty else {
            metadataCache.removeAll()
            metricsCollector.retain(pids: [])
            return []
        }

        // One table read per refresh (~0.8 ms), shared by every service's
        // control-root resolution.
        let tableSnapshot = processTable.snapshot()

        var services: [LocalService] = []
        services.reserveCapacity(ports.count)

        for port in ports {
            // The process may have exited between the scan and now. That race
            // is constant and entirely expected, so the port is simply dropped.
            guard let process = processInspector.snapshot(pid: port.pid) else { continue }

            let identity = ServiceIdentifier(pid: port.pid, port: port.port)
            let metadata = await metadata(
                for: identity,
                process: process,
                port: port,
                tableSnapshot: tableSnapshot
            )

            let git = await gitInfo(for: metadata.project)
            let key = ServiceKey(
                anchor: LocalService.anchor(project: metadata.project, process: process),
                port: port.port
            )

            var service = LocalService(
                id: identity,
                listeningPort: port,
                process: process,
                project: metadata.project,
                detection: metadata.detection,
                git: git,
                metrics: metricsCollector.metrics(for: port.pid),
                origin: metadata.origin
            )
            service.controlRoot = metadata.controlRoot
            service.launchDescriptor = metadata.launchDescriptor
            service.capabilities = capabilityResolver.capabilities(
                process: process,
                origin: metadata.origin,
                framework: metadata.detection?.framework,
                listeningPort: port,
                controlRoot: metadata.controlRoot,
                launchDescriptor: metadata.launchDescriptor,
                hasCapturedLogs: capturedLogKeys.contains(key)
            )
            services.append(service)
        }

        prune(to: services)
        return services
    }

    /// The full framework ranking behind a service's chosen label, for the
    /// debug inspector.
    func frameworkRanking(for identity: ServiceIdentifier) -> [FrameworkDetection] {
        metadataCache[identity]?.ranking ?? []
    }

    // MARK: - Enrichment

    private func metadata(
        for identity: ServiceIdentifier,
        process: ProcessSnapshot,
        port: ListeningPort,
        tableSnapshot: [ProcessTableEntry]
    ) async -> EnrichedMetadata {
        if let cached = metadataCache[identity], cached.startedAt == process.startedAt {
            return cached
        }

        var project = process.workingDirectory.flatMap { projectDetector.detect(workingDirectory: $0) }
        if let packageRoot = project?.packageRoot, let resolved = project {
            project = ProjectContext(
                workingDirectory: resolved.workingDirectory,
                packageRoot: resolved.packageRoot,
                repositoryRoot: resolved.repositoryRoot,
                manifest: manifestLoader.load(packageRoot: packageRoot),
                markerFiles: resolved.markerFiles
            )
        }

        // The parent's argv recovers commands that the child has overwritten.
        let parentArguments = process.parentPID
            .flatMap { processInspector.snapshot(pid: $0) }?
            .arguments ?? []

        let context = DetectionContext(
            processName: process.name,
            executablePath: process.executablePath,
            arguments: process.arguments,
            parentArguments: parentArguments,
            port: port.port,
            manifest: project?.manifest,
            markerFiles: project?.markerFiles ?? []
        )

        let ranking = frameworkDetector.ranked(in: context)
        let detection = ranking.first
        let origin = originClassifier.classify(
            process: process,
            project: project,
            framework: detection?.framework
        )

        // Control root and launch command are static for the life of the
        // process, so they are cached alongside the rest of the metadata rather
        // than recomputed every two seconds.
        let controlRoot = origin == .developer
            ? treeInspector.controlRoot(for: process.pid, in: tableSnapshot)
            : nil

        // The command is recovered from the control root, not the leaf: that is
        // what the developer actually typed, and relaunching the leaf would
        // drop the supervisor above it.
        let launchSource = controlRoot.flatMap { root in
            root.pid == process.pid ? process : processInspector.snapshot(pid: root.pid)
        }
        let launchDescriptor = launchSource.flatMap { launchBuilder.descriptor(for: $0) }

        let metadata = EnrichedMetadata(
            startedAt: process.startedAt,
            project: project,
            detection: detection,
            ranking: ranking,
            origin: origin,
            controlRoot: controlRoot,
            launchDescriptor: launchDescriptor
        )
        metadataCache[identity] = metadata
        return metadata
    }

    private func gitInfo(for project: ProjectContext?) async -> GitInfo? {
        guard let project else { return nil }
        // Only ask git about directories the project walk already found a
        // repository marker in; otherwise every stray cwd spawns a subprocess.
        guard let repositoryRoot = project.repositoryRoot else { return nil }

        if let cached = gitCache[repositoryRoot] { return cached }
        let info = await gitInspector.inspect(directory: repositoryRoot)
        gitCache.insert(info, for: repositoryRoot)
        return info
    }

    // MARK: - Cache hygiene

    private func prune(to services: [LocalService]) {
        let liveIdentities = Set(services.map(\.id))
        metadataCache = metadataCache.filter { liveIdentities.contains($0.key) }
        metricsCollector.retain(pids: Set(services.map(\.pid)))
        gitCache.purgeExpired()
    }
}
