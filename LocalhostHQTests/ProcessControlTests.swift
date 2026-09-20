import Darwin
import Foundation
import Testing
@testable import LocalhostHQ

/// In-memory process table.
struct FakeProcessTable: ProcessTableReading {
    var entries: [ProcessTableEntry] = []
    /// pid -> session id. Anything absent is treated as its own session leader,
    /// which is the conservative default.
    var sessions: [Int32: Int32] = [:]

    func snapshot() -> [ProcessTableEntry] { entries }
    func sessionID(of pid: Int32) -> Int32 { sessions[pid] ?? pid }
}

extension ProcessTableEntry {
    static func make(
        pid: Int32,
        parent: Int32,
        group: Int32,
        name: String,
        uid: uid_t = 501,
        startedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> ProcessTableEntry {
        ProcessTableEntry(
            pid: pid, parentPID: parent, groupID: group, userID: uid,
            name: name, startedAt: startedAt, isZombie: false
        )
    }
}

@Suite("Process instance identity")
struct ProcessInstanceIdentityTests {

    @Test("The same process matches itself")
    func matchesSelf() {
        let date = Date()
        let identity = ProcessInstanceIdentity(pid: 100, startedAt: date, executablePath: "/bin/node")
        #expect(identity.matches(identity))
    }

    /// The reason start time is part of identity at all.
    @Test("A recycled PID does not match")
    func recycledPIDRejected() {
        let original = ProcessInstanceIdentity(
            pid: 100, startedAt: Date(timeIntervalSince1970: 1_000), executablePath: "/bin/node"
        )
        let replacement = ProcessInstanceIdentity(
            pid: 100, startedAt: Date(timeIntervalSince1970: 5_000), executablePath: "/bin/node"
        )
        #expect(original.matches(replacement) == false)
    }

    @Test("A different PID never matches")
    func differentPID() {
        let date = Date()
        let a = ProcessInstanceIdentity(pid: 100, startedAt: date, executablePath: "/bin/node")
        let b = ProcessInstanceIdentity(pid: 101, startedAt: date, executablePath: "/bin/node")
        #expect(a.matches(b) == false)
    }

    @Test("A different executable at the same PID does not match")
    func differentExecutable() {
        let date = Date()
        let a = ProcessInstanceIdentity(pid: 100, startedAt: date, executablePath: "/bin/node")
        let b = ProcessInstanceIdentity(pid: 100, startedAt: date, executablePath: "/bin/python3")
        #expect(a.matches(b) == false)
    }

    /// Without a start time there is no way to rule out reuse, so control is
    /// refused rather than risked.
    @Test("A missing start time refuses the match")
    func missingStartTimeRefuses() {
        let known = ProcessInstanceIdentity(pid: 100, startedAt: Date(), executablePath: "/bin/node")
        let unknown = ProcessInstanceIdentity(pid: 100, startedAt: nil, executablePath: "/bin/node")
        #expect(known.matches(unknown) == false)
        #expect(unknown.matches(unknown) == false)
    }

    @Test("Sub-microsecond differences still match")
    func toleratesTimevalPrecision() {
        let base = Date(timeIntervalSince1970: 1_700_000_000.123_456)
        let a = ProcessInstanceIdentity(pid: 1, startedAt: base, executablePath: nil)
        let b = ProcessInstanceIdentity(pid: 1, startedAt: base.addingTimeInterval(0.000_001), executablePath: nil)
        #expect(a.matches(b))
    }
}

@Suite("Control root selection")
struct ProcessTreeInspectorTests {

    /// The canonical dev-server tree:
    /// ```
    /// zsh (interactive, own group, session leader)
    /// └── pnpm ┐
    ///     └── node │ job group 200
    ///         └── next-server ┘
    /// ```
    private func devServerTable() -> FakeProcessTable {
        FakeProcessTable(
            entries: [
                .make(pid: 1, parent: 0, group: 1, name: "launchd", uid: 0),
                .make(pid: 100, parent: 1, group: 100, name: "zsh"),
                .make(pid: 200, parent: 100, group: 200, name: "pnpm"),
                .make(pid: 201, parent: 200, group: 200, name: "node"),
                .make(pid: 202, parent: 201, group: 200, name: "next-server"),
            ],
            // The interactive shell leads its own session; the job does not.
            sessions: [100: 100, 200: 100, 201: 100, 202: 100]
        )
    }

    @Test("The control root is the top of the job, never the shell")
    func choosesJobRoot() {
        let table = devServerTable()
        let inspector = ProcessTreeInspector(table: table)

        let root = inspector.controlRoot(for: 202, in: table.entries, currentUserID: 501)
        #expect(root?.pid == 200)
        #expect(root?.name == "pnpm")
        // Crucially: the shell is not in the blast radius.
        #expect(root?.memberPIDs.contains(100) == false)
        #expect(Set(root?.memberPIDs ?? []) == [200, 201, 202])
    }

    @Test("An interactive shell is never adopted, even as a direct parent")
    func neverAdoptsInteractiveShell() {
        // A server started straight from the shell, sharing no job group.
        let table = FakeProcessTable(
            entries: [
                .make(pid: 100, parent: 1, group: 100, name: "zsh"),
                .make(pid: 201, parent: 100, group: 201, name: "node"),
            ],
            sessions: [100: 100, 201: 100]
        )
        let inspector = ProcessTreeInspector(table: table)

        let root = inspector.controlRoot(for: 201, in: table.entries, currentUserID: 501)
        #expect(root?.pid == 201)
        #expect(root?.memberPIDs == [201])
    }

    /// A wrapper shell inside the job *is* part of it and must be stopped, or
    /// it is left orphaned.
    @Test("A wrapper script in the same job is adopted")
    func adoptsWrapperScript() {
        let table = FakeProcessTable(
            entries: [
                .make(pid: 100, parent: 1, group: 100, name: "zsh"),
                .make(pid: 200, parent: 100, group: 200, name: "zsh"),      // ./run.sh
                .make(pid: 201, parent: 200, group: 200, name: "python3"),
            ],
            sessions: [100: 100, 200: 100, 201: 100]
        )
        let inspector = ProcessTreeInspector(table: table)

        let root = inspector.controlRoot(for: 201, in: table.entries, currentUserID: 501)
        #expect(root?.pid == 200)
        #expect(Set(root?.memberPIDs ?? []) == [200, 201])
    }

    @Test("A session leader is never adopted even inside the job group")
    func refusesSessionLeader() {
        let table = FakeProcessTable(
            entries: [
                .make(pid: 200, parent: 1, group: 200, name: "bash"),
                .make(pid: 201, parent: 200, group: 200, name: "node"),
            ],
            // The wrapper leads the session, so it is a login/interactive shell.
            sessions: [200: 200, 201: 200]
        )
        let inspector = ProcessTreeInspector(table: table)

        let root = inspector.controlRoot(for: 201, in: table.entries, currentUserID: 501)
        #expect(root?.pid == 201)
    }

    @Test("Another user's process is never controllable")
    func refusesOtherUsers() {
        let table = FakeProcessTable(entries: [
            .make(pid: 300, parent: 1, group: 300, name: "postgres", uid: 0),
        ])
        let inspector = ProcessTreeInspector(table: table)
        #expect(inspector.controlRoot(for: 300, in: table.entries, currentUserID: 501) == nil)
    }

    @Test("Never-control processes are refused outright", arguments: ["launchd", "sshd", "login", "Terminal"])
    func refusesDenyListed(name: String) {
        let table = FakeProcessTable(entries: [
            .make(pid: 400, parent: 1, group: 400, name: name),
        ])
        let inspector = ProcessTreeInspector(table: table)
        #expect(inspector.controlRoot(for: 400, in: table.entries, currentUserID: 501) == nil)
    }

    @Test("An ancestor owned by another user stops the walk")
    func stopsAtForeignAncestor() {
        let table = FakeProcessTable(
            entries: [
                .make(pid: 200, parent: 1, group: 200, name: "supervisor", uid: 0),
                .make(pid: 201, parent: 200, group: 200, name: "node", uid: 501),
            ],
            sessions: [200: 1, 201: 1]
        )
        let inspector = ProcessTreeInspector(table: table)
        #expect(inspector.controlRoot(for: 201, in: table.entries, currentUserID: 501)?.pid == 201)
    }

    @Test("A missing PID yields no control root")
    func missingPID() {
        let table = FakeProcessTable(entries: [])
        let inspector = ProcessTreeInspector(table: table)
        #expect(inspector.controlRoot(for: 999, in: table.entries, currentUserID: 501) == nil)
    }

    @Test("The tree nests correctly and marks the listening process")
    func buildsTree() {
        let table = devServerTable()
        let inspector = ProcessTreeInspector(table: table)

        let tree = inspector.tree(rootedAt: 200, in: table.entries, listeningPorts: [202: 3_000])
        #expect(tree?.name == "pnpm")
        #expect(tree?.children.first?.name == "node")
        #expect(tree?.children.first?.children.first?.listeningPort == 3_000)
        #expect(tree?.flattened().count == 3)
    }

    /// A malformed table must not hang the UI.
    @Test("A parent cycle terminates")
    func toleratesCycles() {
        let table = FakeProcessTable(entries: [
            .make(pid: 10, parent: 11, group: 10, name: "a"),
            .make(pid: 11, parent: 10, group: 10, name: "b"),
        ])
        let inspector = ProcessTreeInspector(table: table)
        #expect(inspector.ancestors(of: 10, in: table.entries).count <= 24)
        #expect(inspector.subtreePIDs(of: 10, in: table.entries).count == 2)
    }
}

@Suite("Launch descriptors")
struct LaunchDescriptorTests {

    private func builder(_ files: [String: String], directories: [String]) -> LaunchDescriptorBuilder {
        LaunchDescriptorBuilder(fileSystem: FakeFileSystem(files: files, emptyDirectories: directories))
    }

    private func snapshot(
        executable: String?,
        arguments: [String],
        cwd: String?
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: 100, parentPID: 1, name: "proc", executablePath: executable,
            arguments: arguments, workingDirectory: cwd,
            startedAt: Date(), isRestricted: false
        )
    }

    @Test("Recovers a package-manager command", arguments: [
        ["/opt/homebrew/bin/pnpm", "dev"],
        ["/opt/homebrew/bin/npm", "run", "dev"],
        ["/opt/homebrew/bin/bun", "dev"],
    ])
    func packageManagerCommands(argv: [String]) {
        let executable = argv[0]
        let build = builder([executable: "", "/proj/package.json": "{}"], directories: ["/proj"])
        let descriptor = build.descriptor(for: snapshot(executable: executable, arguments: argv, cwd: "/proj"))

        #expect(descriptor?.confidence == .high)
        #expect(descriptor?.arguments == Array(argv.dropFirst()))
        #expect(descriptor?.workingDirectory.path == "/proj")
        #expect(descriptor?.isRestartable == true)
    }

    @Test("Recovers interpreter commands", arguments: [
        ["uvicorn", "main:app", "--reload"],
        ["python", "manage.py", "runserver"],
    ])
    func interpreterCommands(argv: [String]) {
        let executable = "/usr/bin/\(argv[0])"
        let build = builder([executable: ""], directories: ["/proj"])
        let descriptor = build.descriptor(for: snapshot(executable: executable, arguments: argv, cwd: "/proj"))

        #expect(descriptor?.confidence == .high)
        #expect(descriptor?.displayCommand.contains(argv[1]) == true)
    }

    @Test("Recovers cargo and go commands", arguments: [
        ("/usr/bin/cargo", ["cargo", "run"]),
        ("/usr/local/go/bin/go", ["go", "run", "."]),
    ])
    func compiledLanguageCommands(executable: String, argv: [String]) {
        let build = builder([executable: ""], directories: ["/proj"])
        let descriptor = build.descriptor(for: snapshot(executable: executable, arguments: argv, cwd: "/proj"))
        #expect(descriptor?.isRestartable == true)
    }

    /// The case that makes naive restart dangerous: Next.js overwrites its
    /// worker's argv with a label, which would fail if rerun.
    @Test("A rewritten process title is refused")
    func rejectsRewrittenTitle() {
        let build = builder(["/opt/homebrew/bin/node": ""], directories: ["/proj"])
        let descriptor = build.descriptor(
            for: snapshot(
                executable: "/opt/homebrew/bin/node",
                arguments: ["next-server", "(v15.0.3)"],
                cwd: "/proj"
            )
        )
        #expect(descriptor == nil)
    }

    @Test("A bare executable is only medium confidence")
    func bareExecutable() {
        let build = builder(["/usr/bin/redis-server": ""], directories: ["/proj"])
        let descriptor = build.descriptor(
            for: snapshot(executable: "/usr/bin/redis-server", arguments: ["redis-server"], cwd: "/proj")
        )
        #expect(descriptor?.confidence == .medium)
    }

    @Test("A missing working directory yields no descriptor")
    func missingWorkingDirectory() {
        let build = builder(["/usr/bin/node": ""], directories: [])
        #expect(build.descriptor(for: snapshot(executable: "/usr/bin/node", arguments: ["node", "x.js"], cwd: "/gone")) == nil)
    }

    @Test("A root working directory yields no descriptor")
    func rootWorkingDirectory() {
        let build = builder(["/usr/bin/node": ""], directories: ["/"])
        #expect(build.descriptor(for: snapshot(executable: "/usr/bin/node", arguments: ["node"], cwd: "/")) == nil)
    }

    @Test("A missing executable yields no descriptor")
    func missingExecutable() {
        let build = builder([:], directories: ["/proj"])
        #expect(build.descriptor(for: snapshot(executable: "/usr/bin/gone", arguments: ["gone"], cwd: "/proj")) == nil)
    }

    @Test("Display commands quote arguments containing spaces")
    func quotesDisplayCommand() {
        let descriptor = LaunchDescriptor(
            executableURL: URL(fileURLWithPath: "/usr/bin/node"),
            arguments: ["script.js", "--name", "my app"],
            workingDirectory: URL(fileURLWithPath: "/proj"),
            confidence: .high,
            recoveredFrom: "test"
        )
        #expect(descriptor.displayCommand == "node script.js --name \"my app\"")
    }
}

@Suite("Capability resolution")
struct CapabilityResolverTests {
    private let resolver = ServiceCapabilityResolver()

    private func snapshot(restricted: Bool = false, startedAt: Date? = Date()) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: Int32(getpid()), parentPID: 1, name: "node",
            executablePath: "/opt/homebrew/bin/node", arguments: ["node", "server.js"],
            workingDirectory: "/proj", startedAt: startedAt, isRestricted: restricted
        )
    }

    private func port() -> ListeningPort {
        ListeningPort(
            pid: Int32(getpid()), processName: "node", port: 3_000,
            bindings: [SocketBinding(address: "127.0.0.1", family: .ipv4)]
        )
    }

    private func controlRoot() -> ControlRoot {
        ControlRoot(pid: Int32(getpid()), name: "node", memberPIDs: [Int32(getpid())], reason: "test")
    }

    private func descriptor(_ confidence: LaunchConfidence) -> LaunchDescriptor {
        LaunchDescriptor(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/node"),
            arguments: ["server.js"],
            workingDirectory: URL(fileURLWithPath: "/proj"),
            confidence: confidence,
            recoveredFrom: "test"
        )
    }

    @Test("A dev server with a good command can stop, force stop and restart")
    func devServerFullyControllable() {
        let capabilities = resolver.capabilities(
            process: snapshot(), origin: .developer, framework: .nextJS,
            listeningPort: port(), controlRoot: controlRoot(),
            launchDescriptor: descriptor(.high), hasCapturedLogs: false
        )
        #expect(capabilities.canStop)
        #expect(capabilities.canForceStop)
        #expect(capabilities.canRestart)
        #expect(capabilities.canOpenInBrowser)
        // Logs only after Localhost HQ launches it.
        #expect(capabilities.canStreamLogs == false)
    }

    @Test("System services get conservative capabilities")
    func systemServiceRestricted() {
        let capabilities = resolver.capabilities(
            process: snapshot(), origin: .system, framework: nil,
            listeningPort: port(), controlRoot: controlRoot(),
            launchDescriptor: descriptor(.high), hasCapturedLogs: false
        )
        #expect(capabilities.canStop == false)
        #expect(capabilities.canRestart == false)
        #expect(capabilities.restriction == .systemService)
    }

    @Test("A low-confidence command disables restart but not stop")
    func lowConfidenceBlocksRestart() {
        let capabilities = resolver.capabilities(
            process: snapshot(), origin: .developer, framework: .node,
            listeningPort: port(), controlRoot: controlRoot(),
            launchDescriptor: descriptor(.low), hasCapturedLogs: false
        )
        #expect(capabilities.canStop)
        #expect(capabilities.canRestart == false)
    }

    @Test("No launch descriptor means no restart")
    func noDescriptorBlocksRestart() {
        let capabilities = resolver.capabilities(
            process: snapshot(), origin: .developer, framework: .node,
            listeningPort: port(), controlRoot: controlRoot(),
            launchDescriptor: nil, hasCapturedLogs: false
        )
        #expect(capabilities.canRestart == false)
    }

    @Test("An unverifiable process cannot be controlled")
    func unverifiableProcess() {
        let capabilities = resolver.capabilities(
            process: snapshot(restricted: true, startedAt: nil), origin: .developer,
            framework: .node, listeningPort: port(), controlRoot: controlRoot(),
            launchDescriptor: descriptor(.high), hasCapturedLogs: false
        )
        #expect(capabilities.canStop == false)
        #expect(capabilities.restriction == .inspectionDenied)
    }

    @Test("Databases never offer a browser action")
    func databaseNoBrowser() {
        let capabilities = resolver.capabilities(
            process: snapshot(), origin: .developer, framework: .postgres,
            listeningPort: port(), controlRoot: controlRoot(),
            launchDescriptor: nil, hasCapturedLogs: false
        )
        #expect(capabilities.canOpenInBrowser == false)
    }
}
