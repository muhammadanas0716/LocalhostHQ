import Foundation
import Testing
@testable import LocalhostHQ

@Suite("Log classification")
struct LogClassifierTests {
    private let classifier = LogClassifier()

    @Test("Errors are recognised", arguments: [
        "ERROR database unavailable",
        "Error: connection lost",
        "Uncaught Exception in handler",
        "FATAL: could not bind",
        "Traceback (most recent call last):",
        "build failed",
    ])
    func errors(line: String) {
        #expect(classifier.level(of: line) == .error)
    }

    @Test("Warnings are recognised", arguments: [
        "WARN deprecated option",
        "warning: unused variable",
        "This API is deprecated",
    ])
    func warnings(line: String) {
        #expect(classifier.level(of: line) == .warning)
    }

    @Test("Ordinary output is not flagged", arguments: [
        "Ready in 812ms",
        "Compiled successfully",
        "Listening on http://localhost:3000",
    ])
    func neutral(line: String) {
        let level = classifier.level(of: line)
        #expect(level != .error)
        #expect(level != .warning)
    }

    /// An access log for a path containing "error" is not an error.
    @Test("Successful access logs are not errors")
    func accessLogsNotErrors() {
        #expect(classifier.level(of: "GET /api/error-page 200") == .info)
        #expect(classifier.level(of: "POST /users 201") == .info)
    }

    @Test("Port conflicts are diagnosed with the port extracted")
    func diagnosesPortConflict() {
        let diagnosis = classifier.diagnose([
            "Starting dev server",
            "Error: listen EADDRINUSE: address already in use :::3000",
        ])
        #expect(diagnosis?.summary == "Port already in use")
        #expect(diagnosis?.conflictingPort == 3_000)
    }

    @Test("Human-worded port conflicts are also diagnosed")
    func diagnosesWordedPortConflict() {
        let diagnosis = classifier.diagnose(["Port 4000 is already in use."])
        #expect(diagnosis?.conflictingPort == 4_000)
    }

    @Test("Other known failures are diagnosed", arguments: [
        ("Error: Cannot find module 'express'", "Missing dependency"),
        ("zsh: command not found: pnpm", "Launch command not found"),
        ("EACCES: permission denied, open '/etc/hosts'", "Permission denied"),
        ("FATAL ERROR: JavaScript heap out of memory", "Out of memory"),
    ])
    func diagnoses(line: String, expected: String) {
        #expect(classifier.diagnose([line])?.summary == expected)
    }

    @Test("Unrecognised output produces no diagnosis")
    func noFalseDiagnosis() {
        #expect(classifier.diagnose(["Ready in 812ms", "GET / 200"]) == nil)
    }

    @Test("The most recent matching line wins")
    func mostRecentWins() {
        let diagnosis = classifier.diagnose([
            "Error: Cannot find module 'x'",
            "Error: listen EADDRINUSE :::5173",
        ])
        #expect(diagnosis?.summary == "Port already in use")
    }

    @Test("Port extraction ignores numbers outside the port range")
    func portExtractionBounds() {
        #expect(LogClassifier.extractPort(from: "took 45ms on :::8080") == 8_080)
        #expect(LogClassifier.extractPort(from: "no numbers here") == nil)
    }
}

@Suite("Log buffering")
struct LogBufferTests {

    private func entry(_ id: UInt64) -> LogEntry {
        LogEntry(id: id, timestamp: Date(), stream: .stdout, message: "line \(id)", level: nil)
    }

    @Test("Entries come back in order")
    func preservesOrder() {
        var buffer = LogBuffer(capacity: 10)
        for index in 0..<5 { buffer.append(entry(UInt64(index))) }
        #expect(buffer.entries.map(\.id) == [0, 1, 2, 3, 4])
    }

    /// The property that keeps a chatty dev server from exhausting memory.
    @Test("Exceeding capacity drops the oldest entries")
    func evictsOldest() {
        var buffer = LogBuffer(capacity: 100)
        for index in 0..<250 { buffer.append(entry(UInt64(index))) }

        #expect(buffer.count == 100)
        #expect(buffer.entries.first?.id == 150)
        #expect(buffer.entries.last?.id == 249)
        #expect(buffer.hasDroppedEntries)
        #expect(buffer.droppedCount == 150)
    }

    @Test("A buffer below capacity has dropped nothing")
    func noDropsBelowCapacity() {
        var buffer = LogBuffer(capacity: 50)
        for index in 0..<50 { buffer.append(entry(UInt64(index))) }
        #expect(buffer.hasDroppedEntries == false)
        #expect(buffer.droppedCount == 0)
    }

    @Test("Wrapping many times stays correct and bounded")
    func repeatedWrapping() {
        var buffer = LogBuffer(capacity: 8)
        for index in 0..<1_000 { buffer.append(entry(UInt64(index))) }
        #expect(buffer.count == 8)
        #expect(buffer.entries.map(\.id) == Array(992...999))
    }

    @Test("Clearing empties the buffer but remembers the volume")
    func clearing() {
        var buffer = LogBuffer(capacity: 10)
        for index in 0..<20 { buffer.append(entry(UInt64(index))) }
        buffer.removeAll()
        #expect(buffer.entries.isEmpty)
        #expect(buffer.totalAppended == 20)
    }

    @Test("A capacity of zero is clamped rather than crashing")
    func clampsCapacity() {
        var buffer = LogBuffer(capacity: 0)
        buffer.append(entry(1))
        #expect(buffer.count == 1)
    }

    @Test("suffix returns the newest entries")
    func suffix() {
        var buffer = LogBuffer(capacity: 50)
        for index in 0..<20 { buffer.append(entry(UInt64(index))) }
        #expect(buffer.suffix(3).map(\.id) == [17, 18, 19])
    }
}

@Suite("ANSI stripping")
struct ANSIStrippingTests {

    @Test("Colour codes are removed")
    func stripsColour() {
        #expect("\u{1B}[32mReady\u{1B}[0m".strippingANSIEscapes() == "Ready")
    }

    @Test("Plain text is untouched")
    func leavesPlainText() {
        #expect("Ready in 812ms".strippingANSIEscapes() == "Ready in 812ms")
    }

    @Test("Cursor sequences are removed")
    func stripsCursorMovement() {
        #expect("\u{1B}[2K\u{1B}[1Gcompiling".strippingANSIEscapes() == "compiling")
    }
}

@Suite("Service keys")
struct ServiceKeyTests {

    @Test("A package root anchors the key")
    func prefersPackageRoot() {
        let anchor = LocalService.anchor(
            project: ProjectContext(
                workingDirectory: "/proj/apps/web", packageRoot: "/proj/apps/web",
                repositoryRoot: "/proj", manifest: nil, markerFiles: []
            ),
            process: ProcessSnapshot(
                pid: 1, parentPID: nil, name: "node", executablePath: "/bin/node",
                arguments: [], workingDirectory: "/proj/apps/web", startedAt: nil, isRestricted: false
            )
        )
        #expect(anchor == .package("/proj/apps/web"))
    }

    @Test("Without a project the executable anchors the key")
    func fallsBackToExecutable() {
        let anchor = LocalService.anchor(
            project: nil,
            process: ProcessSnapshot(
                pid: 1, parentPID: nil, name: "postgres", executablePath: "/opt/bin/postgres",
                arguments: [], workingDirectory: "/", startedAt: nil, isRestricted: false
            )
        )
        #expect(anchor == .executable("/opt/bin/postgres"))
    }

    /// What makes a service survive coming back on a different port.
    @Test("Keys on the same anchor but different ports are related")
    func sharesAnchorAcrossPorts() {
        let a = ServiceKey(anchor: .package("/proj"), port: 3_000)
        let b = ServiceKey(anchor: .package("/proj"), port: 3_001)
        #expect(a != b)
        #expect(a.sharesAnchor(with: b))
    }

    @Test("A port-only anchor is never treated as related")
    func portAnchorNotRelated() {
        let a = ServiceKey(anchor: .port, port: 3_000)
        let b = ServiceKey(anchor: .port, port: 3_001)
        #expect(a.sharesAnchor(with: b) == false)
    }
}

@Suite("Lifecycle transitions")
@MainActor
struct LifecycleTrackerTests {

    private func service(port: Int = 3_000, name: String = "web") -> LocalService {
        var built = SampleData.web
        built = LocalService(
            id: ServiceIdentifier(pid: 4_812, port: port),
            listeningPort: ListeningPort(
                pid: 4_812, processName: "node", port: port,
                bindings: [SocketBinding(address: "*", family: .ipv4)]
            ),
            process: built.process,
            project: built.project,
            detection: built.detection,
            git: built.git,
            metrics: built.metrics,
            origin: .developer
        )
        return built
    }

    @Test("A newly seen service is running and recorded as discovered")
    func discovery() {
        let tracker = LifecycleTracker()
        let service = service()
        tracker.reconcile(with: [service])

        #expect(tracker.state(for: service.key).isRunning)
        #expect(tracker.events(for: service.key).first?.kind == .discovered)
    }

    /// running → stopping → stopped
    @Test("A requested stop reports as stopped, not a crash")
    func requestedStop() {
        let tracker = LifecycleTracker()
        let service = service()
        tracker.reconcile(with: [service])

        tracker.beginIntentionalTransition(service.key, state: .stopping)
        tracker.reconcile(with: [])

        #expect(tracker.state(for: service.key) == .stopped(.requested, nil) || {
            if case .stopped(.requested, _) = tracker.state(for: service.key) { return true }
            return false
        }())
        #expect(tracker.events(for: service.key).last?.kind == .stopped)
    }

    /// running → (vanishes with no request) → exited unexpectedly
    @Test("An unannounced disappearance is an unexpected exit")
    func unexpectedExit() {
        let tracker = LifecycleTracker()
        let service = service()
        tracker.reconcile(with: [service])
        tracker.reconcile(with: [])

        guard case .stopped(.unexpected, let info) = tracker.state(for: service.key) else {
            Issue.record("expected an unexpected exit, got \(tracker.state(for: service.key))")
            return
        }
        #expect(info != nil)
        #expect(tracker.events(for: service.key).last?.kind == .crashed)
    }

    @Test("An exit code is reported when one is known")
    func reportsExitCode() {
        let tracker = LifecycleTracker()
        let service = service()
        tracker.reconcile(with: [service])
        tracker.recordExitCode(1, for: service.key)
        tracker.reconcile(with: [])

        guard case .stopped(.unexpected, let info) = tracker.state(for: service.key) else {
            Issue.record("expected an unexpected exit")
            return
        }
        #expect(info?.exitCode == 1)
    }

    /// The restart window: the old process is gone and the new one has not
    /// bound its port. This must not be reported as a crash.
    @Test("A service mid-restart is not reported as crashed")
    func restartWindowIsNotACrash() {
        let tracker = LifecycleTracker()
        let service = service()
        tracker.reconcile(with: [service])

        tracker.beginIntentionalTransition(service.key, state: .restarting)
        tracker.reconcile(with: [])   // gone, mid-restart

        #expect(tracker.state(for: service.key) == .restarting)
        #expect(tracker.events(for: service.key).contains { $0.kind == .crashed } == false)
    }

    /// restarting → running
    @Test("A service that comes back after a restart is running again")
    func restartCompletes() {
        let tracker = LifecycleTracker()
        let service = service()
        tracker.reconcile(with: [service])
        tracker.beginIntentionalTransition(service.key, state: .restarting)
        tracker.reconcile(with: [])
        tracker.reconcile(with: [service])

        #expect(tracker.state(for: service.key).isRunning)
        #expect(tracker.events(for: service.key).last?.kind == .restarted)
    }

    @Test("A failed operation leaves the service failed")
    func failedState() {
        let tracker = LifecycleTracker()
        let service = service()
        tracker.reconcile(with: [service])
        tracker.setState(.failed("Port in use"), for: service.key)
        tracker.reconcile(with: [])

        #expect(tracker.state(for: service.key) == .failed("Port in use"))
    }

    @Test("A diagnosis is attached to an unexpected exit")
    func attachesDiagnosis() {
        let tracker = LifecycleTracker()
        let service = service()
        tracker.reconcile(with: [service])

        let diagnosis = LogDiagnosis(summary: "Port already in use", detail: "d", conflictingPort: 3_000)
        tracker.reconcile(with: [], diagnoses: [service.key: diagnosis])

        guard case .stopped(.unexpected, let info) = tracker.state(for: service.key) else {
            Issue.record("expected an unexpected exit")
            return
        }
        #expect(info?.diagnosis?.summary == "Port already in use")
    }

    @Test("Event history stays bounded")
    func boundedEvents() {
        let tracker = LifecycleTracker()
        let service = service()
        for index in 0..<(LifecycleTracker.maximumEvents + 60) {
            tracker.record(ServiceEvent(
                kind: .discovered, serviceKey: service.key,
                serviceName: "web", message: "event \(index)"
            ))
        }
        #expect(tracker.events.count == LifecycleTracker.maximumEvents)
        #expect(tracker.events.last?.message == "event \(LifecycleTracker.maximumEvents + 59)")
    }

    @Test("Busy states block further operations")
    func busyStates() {
        #expect(ServiceRuntimeState.stopping.isBusy)
        #expect(ServiceRuntimeState.restarting.isBusy)
        #expect(ServiceRuntimeState.starting.isBusy)
        #expect(ServiceRuntimeState.running.isBusy == false)
        #expect(ServiceRuntimeState.stopped(.requested, nil).isBusy == false)
    }
}

@Suite("Log store")
@MainActor
struct LogStoreTests {
    private let key = ServiceKey(anchor: .package("/proj"), port: 3_000)

    @Test("Batched lines become entries")
    func appendsBatch() {
        let store = LogStore(key: key)
        store.append(lines: ["one", "two"], stream: .stdout)
        #expect(store.entries.count == 2)
        #expect(store.entries.map(\.message) == ["one", "two"])
    }

    @Test("Errors are surfaced and diagnosed")
    func detectsErrors() {
        let store = LogStore(key: key)
        store.append(lines: ["Error: listen EADDRINUSE :::3000"], stream: .stderr)

        #expect(store.errorEntries.count == 1)
        #expect(store.diagnosis?.conflictingPort == 3_000)
    }

    @Test("Filtering matches case-insensitively")
    func filtering() {
        let store = LogStore(key: key)
        store.append(lines: ["Ready in 812ms", "GET /api/user 200", "ERROR timeout"], stream: .stdout)

        #expect(store.filtered(query: "api", levels: nil).count == 1)
        #expect(store.filtered(query: "READY", levels: nil).count == 1)
        #expect(store.filtered(query: "", levels: [.error]).count == 1)
        #expect(store.filtered(query: "nothing", levels: nil).isEmpty)
    }

    @Test("Heavy output stays bounded")
    func boundedUnderLoad() {
        let store = LogStore(key: key, capacity: 500)
        for batch in 0..<20 {
            store.append(lines: (0..<200).map { "batch \(batch) line \($0)" }, stream: .stdout)
        }
        #expect(store.entries.count == 500)
        #expect(store.droppedCount == 3_500)
    }

    @Test("Clearing empties the store")
    func clearing() {
        let store = LogStore(key: key)
        store.append(lines: ["a", "b"], stream: .stdout)
        store.clear()
        #expect(store.isEmpty)
        #expect(store.diagnosis == nil)
    }

    @Test("Sources start unavailable and become live on capture")
    func sourceTransitions() {
        let store = LogStore(key: key)
        #expect(store.source == .unavailable)
        #expect(store.source.isLive == false)
        store.setSource(.capturedProcess)
        #expect(store.source.isLive)
    }

    @Test("A manager reuses one store per key and rekeys on port change")
    func managerRekeying() {
        let manager = LogManager()
        let store = manager.store(for: key)
        store.append(lines: ["hello"], stream: .stdout)

        #expect(manager.store(for: key) === store)

        let moved = ServiceKey(anchor: .package("/proj"), port: 3_001)
        manager.rekey(from: key, to: moved)

        #expect(manager.existingStore(for: key) == nil)
        #expect(manager.existingStore(for: moved)?.entries.map(\.message) == ["hello"])
    }
}
