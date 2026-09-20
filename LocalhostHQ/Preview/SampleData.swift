#if DEBUG
import Foundation

/// Fixed services for previews and UI work, so neither needs live discovery.
enum SampleData {

    static let all: [LocalService] = [web, api, postgres, redis, jupyter, vite]

    static let web = make(
        pid: 4_812,
        port: 3_000,
        processName: "node",
        executablePath: "/opt/homebrew/bin/node",
        arguments: ["next-server", "(v15.0.3)"],
        workingDirectory: "/Users/anas/Code/dicee/apps/web",
        packageRoot: "/Users/anas/Code/dicee/apps/web",
        repositoryRoot: "/Users/anas/Code/dicee",
        declaredName: "@dicee/web",
        framework: .nextJS,
        branch: "main",
        cpu: 7.2,
        memory: 428 * 1_000_000,
        uptime: 6_120
    )

    static let api = make(
        pid: 4_813,
        port: 8_787,
        processName: "node",
        executablePath: "/opt/homebrew/bin/node",
        arguments: ["node", "dist/index.js"],
        workingDirectory: "/Users/anas/Code/dicee/apps/api",
        packageRoot: "/Users/anas/Code/dicee/apps/api",
        repositoryRoot: "/Users/anas/Code/dicee",
        declaredName: "@dicee/api",
        framework: .hono,
        branch: "main",
        cpu: 2.1,
        memory: 91 * 1_000_000,
        uptime: 6_000
    )

    static let vite = make(
        pid: 5_120,
        port: 5_173,
        processName: "node",
        executablePath: "/opt/homebrew/bin/node",
        arguments: ["vite"],
        workingDirectory: "/Users/anas/Code/portfolio",
        packageRoot: "/Users/anas/Code/portfolio",
        repositoryRoot: "/Users/anas/Code/portfolio",
        declaredName: "portfolio",
        framework: .vite,
        branch: "redesign",
        cpu: 0.4,
        memory: 158 * 1_000_000,
        uptime: 240
    )

    static let postgres = make(
        pid: 992,
        port: 5_432,
        processName: "postgres",
        executablePath: "/opt/homebrew/opt/postgresql@16/bin/postgres",
        arguments: ["postgres", "-D", "/opt/homebrew/var/postgresql@16"],
        workingDirectory: nil,
        packageRoot: nil,
        repositoryRoot: nil,
        declaredName: nil,
        framework: .postgres,
        branch: nil,
        cpu: 0.1,
        memory: 46 * 1_000_000,
        uptime: 320_400
    )

    static let redis = make(
        pid: 1_421,
        port: 6_379,
        processName: "redis-server",
        executablePath: "/opt/homebrew/bin/redis-server",
        arguments: ["redis-server", "127.0.0.1:6379"],
        workingDirectory: nil,
        packageRoot: nil,
        repositoryRoot: nil,
        declaredName: nil,
        framework: .redis,
        branch: nil,
        cpu: 0.6,
        memory: 12 * 1_000_000,
        uptime: 320_100
    )

    static let jupyter = make(
        pid: 7_733,
        port: 8_888,
        processName: "python3.12",
        executablePath: "/opt/homebrew/bin/python3.12",
        arguments: ["python3", "-m", "jupyter", "lab"],
        workingDirectory: "/Users/anas/Notebooks",
        packageRoot: nil,
        repositoryRoot: nil,
        declaredName: nil,
        framework: .jupyter,
        branch: nil,
        cpu: 1.4,
        memory: 210 * 1_000_000,
        uptime: 1_800
    )

    // MARK: - Builder

    private static func make(
        pid: Int32,
        port: Int,
        processName: String,
        executablePath: String?,
        arguments: [String],
        workingDirectory: String?,
        packageRoot: String?,
        repositoryRoot: String?,
        declaredName: String?,
        framework: Framework,
        branch: String?,
        cpu: Double?,
        memory: UInt64,
        uptime: TimeInterval
    ) -> LocalService {
        let project = workingDirectory.map { directory in
            ProjectContext(
                workingDirectory: directory,
                packageRoot: packageRoot,
                repositoryRoot: repositoryRoot,
                manifest: packageRoot.map {
                    ProjectManifest(
                        kind: .packageJSON,
                        path: $0 + "/package.json",
                        declaredName: declaredName,
                        dependencies: []
                    )
                },
                markerFiles: []
            )
        }

        return LocalService(
            id: ServiceIdentifier(pid: pid, port: port),
            listeningPort: ListeningPort(
                pid: pid,
                processName: processName,
                port: port,
                bindings: [
                    SocketBinding(address: "127.0.0.1", family: .ipv4),
                    SocketBinding(address: "::1", family: .ipv6),
                ]
            ),
            process: ProcessSnapshot(
                pid: pid,
                parentPID: 1,
                name: processName,
                executablePath: executablePath,
                arguments: arguments,
                workingDirectory: workingDirectory,
                startedAt: Date().addingTimeInterval(-uptime),
                isRestricted: false
            ),
            project: project,
            detection: FrameworkDetection(framework: framework, confidence: 0.97),
            git: repositoryRoot.flatMap { root in
                branch.map { GitInfo(repositoryRoot: root, head: .branch($0)) }
            },
            metrics: ProcessMetrics(
                cpuPercent: cpu,
                residentMemoryBytes: memory,
                sampledAt: Date()
            ),
            origin: .developer
        )
    }
}
#endif
