import Foundation
import Testing
@testable import LocalhostHQ

@Suite("CPU rate calculation")
struct MetricsCollectorTests {

    private func sample(cpuNanoseconds: UInt64, at offset: TimeInterval, base: Date) -> ProcessCPUSample {
        ProcessCPUSample(
            cpuNanoseconds: cpuNanoseconds,
            residentMemoryBytes: 1_000_000,
            takenAt: base.addingTimeInterval(offset)
        )
    }

    @Test("One core fully consumed over the interval reads as 100%")
    func fullCore() {
        let base = Date()
        let percent = MetricsCollector.cpuPercent(
            from: sample(cpuNanoseconds: 0, at: 0, base: base),
            to: sample(cpuNanoseconds: 1_000_000_000, at: 1, base: base)
        )
        #expect(percent == 100)
    }

    /// A multi-threaded process can exceed one core; the value must not clamp.
    @Test("Four cores consumed reads as 400%")
    func multipleCores() {
        let base = Date()
        let percent = MetricsCollector.cpuPercent(
            from: sample(cpuNanoseconds: 0, at: 0, base: base),
            to: sample(cpuNanoseconds: 4_000_000_000, at: 1, base: base)
        )
        #expect(percent == 400)
    }

    @Test("An idle process reads as zero")
    func idle() {
        let base = Date()
        let percent = MetricsCollector.cpuPercent(
            from: sample(cpuNanoseconds: 5_000_000, at: 0, base: base),
            to: sample(cpuNanoseconds: 5_000_000, at: 2, base: base)
        )
        #expect(percent == 0)
    }

    /// Counters are monotonic, so a decrease means the PID was recycled.
    @Test("A counter going backwards yields no rate")
    func recycledPID() {
        let base = Date()
        let percent = MetricsCollector.cpuPercent(
            from: sample(cpuNanoseconds: 9_000_000_000, at: 0, base: base),
            to: sample(cpuNanoseconds: 1_000, at: 1, base: base)
        )
        #expect(percent == nil)
    }

    @Test("Too short an interval yields no rate")
    func intervalTooShort() {
        let base = Date()
        let percent = MetricsCollector.cpuPercent(
            from: sample(cpuNanoseconds: 0, at: 0, base: base),
            to: sample(cpuNanoseconds: 1_000_000, at: 0.01, base: base)
        )
        #expect(percent == nil)
    }

    @Test("The first sample of a process reports no CPU rate")
    func firstSampleHasNoRate() {
        let collector = MetricsCollector(inspector: StubProcessInspector(cpuNanoseconds: 1_000_000))
        #expect(collector.metrics(for: 1)?.cpuPercent == nil)
        // Memory is available immediately, though.
        #expect(collector.metrics(for: 1)?.residentMemoryBytes == 64_000_000)
    }
}

// MARK: - Pipeline

/// Returns canned lsof output.
private struct StubPortScanner: PortScanning {
    let ports: [ListeningPort]
    func listeningPorts() async -> [ListeningPort] { ports }
    func listeners(onPort port: Int) async -> [ListeningPort] {
        ports.filter { $0.port == port }
    }
}

private struct StubProcessInspector: ProcessInspecting {
    var snapshots: [Int32: ProcessSnapshot] = [:]
    var cpuNanoseconds: UInt64 = 0

    init(snapshots: [Int32: ProcessSnapshot] = [:], cpuNanoseconds: UInt64 = 0) {
        self.snapshots = snapshots
        self.cpuNanoseconds = cpuNanoseconds
    }

    func snapshot(pid: Int32) -> ProcessSnapshot? { snapshots[pid] }

    func cpuSample(pid: Int32) -> ProcessCPUSample? {
        ProcessCPUSample(cpuNanoseconds: cpuNanoseconds, residentMemoryBytes: 64_000_000, takenAt: Date())
    }
}

private struct StubGitInspector: GitInspecting {
    let branch: String?
    func inspect(directory: String) async -> GitInfo? {
        branch.map { GitInfo(repositoryRoot: directory, head: .branch($0)) }
    }
}

@Suite("Discovery pipeline")
struct DiscoveryPipelineTests {

    private func monorepoFileSystem() -> FakeFileSystem {
        var fs = FakeFileSystem()
        fs.addDirectory("/Users/dev/Code/dicee/.git")
        fs.addFile("/Users/dev/Code/dicee/pnpm-workspace.yaml", contents: "packages:\n  - apps/*")
        fs.addFile("/Users/dev/Code/dicee/apps/web/package.json",
                   contents: #"{"name":"@dicee/web","dependencies":{"next":"15.0.0"}}"#)
        fs.addFile("/Users/dev/Code/dicee/apps/web/next.config.js", contents: "module.exports={}")
        return fs
    }

    private func makeService(
        scanner: StubPortScanner,
        inspector: StubProcessInspector,
        fileSystem: FakeFileSystem,
        branch: String? = "main"
    ) -> LocalhostDiscoveryService {
        LocalhostDiscoveryService(
            portScanner: scanner,
            processInspector: inspector,
            projectDetector: ProjectDetector(fileSystem: fileSystem, homeDirectory: "/Users/dev"),
            manifestLoader: ManifestLoader(fileSystem: fileSystem),
            frameworkDetector: FrameworkDetector(),
            gitInspector: StubGitInspector(branch: branch)
        )
    }

    @Test("A Next.js dev server is resolved end to end")
    func fullPipeline() async throws {
        let port = ListeningPort(
            pid: 4812, processName: "node", port: 3000,
            bindings: [SocketBinding(address: "*", family: .ipv6)]
        )
        let process = ProcessSnapshot(
            pid: 4812, parentPID: 4811, name: "node",
            executablePath: "/opt/homebrew/bin/node",
            // The rewritten title Next.js actually presents.
            arguments: ["next-server", "(v15.0.3)"],
            workingDirectory: "/Users/dev/Code/dicee/apps/web",
            startedAt: Date().addingTimeInterval(-600),
            isRestricted: false
        )

        let discovery = makeService(
            scanner: StubPortScanner(ports: [port]),
            inspector: StubProcessInspector(snapshots: [4812: process]),
            fileSystem: monorepoFileSystem()
        )

        let services = await discovery.discover()
        #expect(services.count == 1)

        let service = try #require(services.first)
        #expect(service.port == 3000)
        #expect(service.pid == 4812)
        #expect(service.framework == .nextJS)
        #expect(service.displayName == "web")
        #expect(service.project?.packageRoot == "/Users/dev/Code/dicee/apps/web")
        #expect(service.project?.repositoryRoot == "/Users/dev/Code/dicee")
        #expect(service.git?.branchName == "main")
        #expect(service.origin == .developer)
        #expect(service.browserURL?.absoluteString == "http://localhost:3000/")
    }

    /// The scan-then-inspect race happens constantly and must simply drop the
    /// port rather than surfacing an error.
    @Test("A process that exits between scan and inspection is dropped")
    func processExitsDuringInspection() async {
        let port = ListeningPort(
            pid: 999, processName: "ghost", port: 4000,
            bindings: [SocketBinding(address: "127.0.0.1", family: .ipv4)]
        )
        let discovery = makeService(
            scanner: StubPortScanner(ports: [port]),
            inspector: StubProcessInspector(snapshots: [:]),   // already gone
            fileSystem: FakeFileSystem()
        )

        #expect(await discovery.discover().isEmpty)
    }

    @Test("Sibling services in one repository are both resolved")
    func siblingServices() async {
        var fs = monorepoFileSystem()
        fs.addFile("/Users/dev/Code/dicee/apps/api/package.json",
                   contents: #"{"name":"@dicee/api","dependencies":{"hono":"4.0.0"}}"#)

        let ports = [
            ListeningPort(pid: 1, processName: "node", port: 3000,
                          bindings: [SocketBinding(address: "*", family: .ipv4)]),
            ListeningPort(pid: 2, processName: "node", port: 8787,
                          bindings: [SocketBinding(address: "*", family: .ipv4)]),
        ]
        let snapshots: [Int32: ProcessSnapshot] = [
            1: ProcessSnapshot(pid: 1, parentPID: nil, name: "node", executablePath: "/opt/homebrew/bin/node",
                               arguments: ["next-server"], workingDirectory: "/Users/dev/Code/dicee/apps/web",
                               startedAt: Date(), isRestricted: false),
            2: ProcessSnapshot(pid: 2, parentPID: nil, name: "node", executablePath: "/opt/homebrew/bin/node",
                               arguments: ["node", "dist/index.js"], workingDirectory: "/Users/dev/Code/dicee/apps/api",
                               startedAt: Date(), isRestricted: false),
        ]

        let discovery = makeService(
            scanner: StubPortScanner(ports: ports),
            inspector: StubProcessInspector(snapshots: snapshots),
            fileSystem: fs
        )

        let services = await discovery.discover()
        #expect(services.count == 2)

        let groups = ServiceGrouper().group(services)
        #expect(groups.count == 1)
        #expect(groups.first?.title == "dicee")
        #expect(groups.first?.services.map(\.displayName) == ["web", "api"])
    }

    @Test("A restricted process still yields a usable service")
    func restrictedProcessDegradesGracefully() async throws {
        let port = ListeningPort(
            pid: 992, processName: "postgres", port: 5432,
            bindings: [SocketBinding(address: "127.0.0.1", family: .ipv4)]
        )
        // Root-owned: no executable path, no cwd, no arguments.
        let process = ProcessSnapshot(
            pid: 992, parentPID: 1, name: "postgres", executablePath: nil,
            arguments: [], workingDirectory: nil,
            startedAt: Date().addingTimeInterval(-3600), isRestricted: true
        )

        let discovery = makeService(
            scanner: StubPortScanner(ports: [port]),
            inspector: StubProcessInspector(snapshots: [992: process]),
            fileSystem: FakeFileSystem()
        )

        let service = try #require(await discovery.discover().first)
        #expect(service.framework == .postgres)
        #expect(service.supportsBrowserOpen == false)
        #expect(service.project == nil)
        #expect(service.uptime != nil)
        // The framework names it, since no project could be resolved.
        #expect(service.displayName == "PostgreSQL")
    }

    @Test("Identity stays stable across refreshes")
    func stableIdentityAcrossRefreshes() async {
        let port = ListeningPort(
            pid: 4812, processName: "node", port: 3000,
            bindings: [SocketBinding(address: "*", family: .ipv4)]
        )
        let process = ProcessSnapshot(
            pid: 4812, parentPID: nil, name: "node", executablePath: "/opt/homebrew/bin/node",
            arguments: ["next-server"], workingDirectory: "/Users/dev/Code/dicee/apps/web",
            startedAt: Date().addingTimeInterval(-60), isRestricted: false
        )
        let discovery = makeService(
            scanner: StubPortScanner(ports: [port]),
            inspector: StubProcessInspector(snapshots: [4812: process]),
            fileSystem: monorepoFileSystem()
        )

        let first = await discovery.discover()
        // Spaced past the minimum sampling interval; back-to-back refreshes are
        // deliberately too close together to yield a meaningful rate.
        try? await Task.sleep(for: .milliseconds(80))
        let second = await discovery.discover()

        #expect(first.map(\.id) == second.map(\.id))
        // The second pass has a prior CPU sample, so a rate now exists.
        #expect(second.first?.metrics?.cpuPercent != nil)
    }
}
