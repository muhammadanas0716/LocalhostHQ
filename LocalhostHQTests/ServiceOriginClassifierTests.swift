import Foundation
import Testing
@testable import LocalhostHQ

@Suite("Service origin classification")
struct ServiceOriginClassifierTests {
    private let classifier = ServiceOriginClassifier()

    private func snapshot(executable: String?, restricted: Bool = false) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: 100,
            parentPID: 1,
            name: executable.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "unknown",
            executablePath: executable,
            arguments: [],
            workingDirectory: nil,
            startedAt: Date(),
            isRestricted: restricted
        )
    }

    private func project(packageRoot: String?, repositoryRoot: String?) -> ProjectContext {
        ProjectContext(
            workingDirectory: packageRoot ?? "/tmp",
            packageRoot: packageRoot,
            repositoryRoot: repositoryRoot,
            manifest: nil,
            markerFiles: []
        )
    }

    /// python.org ships its interpreter inside `Python.app`, so a naive
    /// `.app/Contents/` test would hide every Flask, Django and FastAPI server
    /// run on that build. This is a real path observed on macOS.
    @Test("A python.org interpreter is the developer's, despite living in an .app bundle")
    func pythonFrameworkIsNotSystem() {
        let executable = "/Library/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python"
        let origin = classifier.classify(
            process: snapshot(executable: executable),
            project: nil,
            framework: .python
        )
        #expect(origin == .developer)
    }

    @Test("A helper inside an installed app is a system service")
    func applicationHelperIsSystem() {
        let executable = "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"
        // Even with a package root — an IDE's language server runs from its own
        // extension folder, which contains a package.json.
        let origin = classifier.classify(
            process: snapshot(executable: executable),
            project: project(packageRoot: "/Users/dev/.vscode/extensions/pylance", repositoryRoot: nil),
            framework: .node
        )
        #expect(origin == .system)
    }

    @Test("Apple daemons are system services", arguments: [
        "/usr/libexec/rapportd",
        "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
        "/usr/sbin/bluetoothd",
    ])
    func appleDaemonsAreSystem(executable: String) {
        #expect(classifier.classify(process: snapshot(executable: executable), project: nil, framework: nil) == .system)
    }

    @Test("A dev server in a real repository is the developer's")
    func projectServiceIsDeveloper() {
        let origin = classifier.classify(
            process: snapshot(executable: "/opt/homebrew/bin/node"),
            project: project(packageRoot: "/Users/dev/Code/app", repositoryRoot: "/Users/dev/Code/app"),
            framework: .nextJS
        )
        #expect(origin == .developer)
    }

    /// Homebrew's Postgres runs from /opt, but a Postgres in a system location
    /// still matters to the developer.
    @Test("Infrastructure is always the developer's concern", arguments: [
        Framework.postgres, .redis, .mysql, .docker,
    ])
    func infrastructureIsAlwaysDeveloper(framework: Framework) {
        let origin = classifier.classify(
            process: snapshot(executable: "/usr/libexec/something"),
            project: nil,
            framework: framework
        )
        #expect(origin == .developer)
    }

    @Test("A process that denied inspection is treated as a system daemon")
    func restrictedProcessIsSystem() {
        #expect(classifier.classify(process: snapshot(executable: nil, restricted: true), project: nil, framework: nil) == .system)
    }

    @Test("An unknown binary outside system locations is the developer's")
    func unknownBinaryDefaultsToDeveloper() {
        let origin = classifier.classify(
            process: snapshot(executable: "/opt/homebrew/bin/some-server"),
            project: nil,
            framework: nil
        )
        #expect(origin == .developer)
    }
}

@Suite("Binding display")
struct BindingDisplayTests {

    /// A dual-stack listener binds the same textual address twice; showing
    /// `*:5000, *:5000` was a real defect.
    @Test("Duplicate textual bindings collapse")
    func collapsesDuplicateAddresses() {
        let port = ListeningPort(
            pid: 1, processName: "ControlCenter", port: 5000,
            bindings: [
                SocketBinding(address: "*", family: .ipv4),
                SocketBinding(address: "*", family: .ipv6),
            ]
        )
        #expect(port.bindingDescription == "*:5000")
        #expect(port.familyDescription == "IPv4/IPv6")
    }

    @Test("Genuinely distinct bindings are all shown")
    func keepsDistinctAddresses() {
        let port = ListeningPort(
            pid: 1, processName: "node", port: 3000,
            bindings: [
                SocketBinding(address: "127.0.0.1", family: .ipv4),
                SocketBinding(address: "::1", family: .ipv6),
            ]
        )
        #expect(port.bindingDescription == "127.0.0.1:3000, ::1:3000")
    }
}
