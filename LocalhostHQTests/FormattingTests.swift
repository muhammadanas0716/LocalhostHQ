import Foundation
import Testing
@testable import LocalhostHQ

@Suite("Formatting")
struct FormattingTests {

    @Test("Memory sizes", arguments: [
        (UInt64(512), "512 B"),
        (UInt64(72_000), "72 KB"),
        (UInt64(72_000_000), "72 MB"),
        (UInt64(428_000_000), "428 MB"),
        (UInt64(1_400_000_000), "1.4 GB"),
        (UInt64(0), "0 B"),
    ])
    func memory(bytes: UInt64, expected: String) {
        #expect(Format.memory(bytes) == expected)
    }

    @Test("CPU percentages are not capped at 100")
    func cpu() {
        #expect(Format.cpu(0) == "0%")
        #expect(Format.cpu(0.4) == "<1%")
        #expect(Format.cpu(3.2) == "3%")
        #expect(Format.cpu(27.0) == "27%")
        // A multi-threaded process legitimately exceeds one core.
        #expect(Format.cpu(135.0) == "135%")
        #expect(Format.cpu(412.6) == "413%")
    }

    @Test("CPU handles non-finite input")
    func cpuNonFinite() {
        #expect(Format.cpu(.nan) == "0%")
        #expect(Format.cpu(-5) == "0%")
        #expect(Format.cpuPrecise(.infinity) == "0.0%")
    }

    @Test("Precise CPU carries one decimal")
    func cpuPrecise() {
        #expect(Format.cpuPrecise(7.24) == "7.2%")
        #expect(Format.cpuPrecise(0) == "0.0%")
    }

    @Test("Uptime", arguments: [
        (TimeInterval(43), "43s"),
        (TimeInterval(60), "1m"),
        (TimeInterval(12 * 60), "12m"),
        (TimeInterval(2 * 3600 + 13 * 60), "2h 13m"),
        (TimeInterval(3600), "1h"),
        (TimeInterval(86_400 + 4 * 3600), "1d 4h"),
        (TimeInterval(86_400), "1d"),
        (TimeInterval(0), "0s"),
    ])
    func uptime(interval: TimeInterval, expected: String) {
        #expect(Format.uptime(interval) == expected)
    }

    @Test("Uptime rejects nonsense input")
    func uptimeInvalid() {
        #expect(Format.uptime(-1) == "—")
        #expect(Format.uptime(.nan) == "—")
    }

    @Test("Home directory abbreviates to a tilde")
    func pathAbbreviation() {
        #expect(Format.path("/Users/anas/Code/dicee", home: "/Users/anas") == "~/Code/dicee")
        #expect(Format.path("/Users/anas", home: "/Users/anas") == "~")
        // A different user's path is left alone.
        #expect(Format.path("/Users/other/Code", home: "/Users/anas") == "/Users/other/Code")
        // A prefix that is not a path boundary must not be abbreviated.
        #expect(Format.path("/Users/anastasia/Code", home: "/Users/anas") == "/Users/anastasia/Code")
        #expect(Format.path("/opt/homebrew/bin", home: "/Users/anas") == "/opt/homebrew/bin")
    }
}

@Suite("Localhost URLs")
struct LocalhostURLTests {

    @Test("Standard ports")
    func standardPorts() {
        #expect(LocalhostURL.displayString(port: 3000) == "http://localhost:3000")
        #expect(LocalhostURL.displayString(port: 8787) == "http://localhost:8787")
    }

    @Test("Default ports are implied by the scheme")
    func defaultPorts() {
        #expect(LocalhostURL.displayString(port: 80) == "http://localhost")
        #expect(LocalhostURL.displayString(port: 443, preferringTLS: true) == "https://localhost")
    }

    @Test("TLS is honoured when requested")
    func tls() {
        #expect(LocalhostURL.displayString(port: 3000, preferringTLS: true) == "https://localhost:3000")
    }

    @Test("Out-of-range ports produce no URL")
    func invalidPorts() {
        #expect(LocalhostURL.make(port: 0) == nil)
        #expect(LocalhostURL.make(port: 70_000) == nil)
    }
}

@Suite("Service capabilities")
struct ServiceCapabilityTests {

    @Test("Databases and caches never offer a browser action")
    func infrastructureHasNoBrowserAction() {
        #expect(SampleData.postgres.supportsBrowserOpen == false)
        #expect(SampleData.postgres.browserURL == nil)
        #expect(SampleData.redis.supportsBrowserOpen == false)
    }

    @Test("Web services offer a localhost URL")
    func webServicesOpenInBrowser() {
        #expect(SampleData.web.supportsBrowserOpen)
        #expect(SampleData.web.browserURL?.absoluteString == "http://localhost:3000/")
    }

    @Test("A service bound only to a LAN address is not browsable")
    func lanOnlyBindIsNotBrowsable() {
        let service = LocalService(
            id: ServiceIdentifier(pid: 1, port: 9000),
            listeningPort: ListeningPort(
                pid: 1, processName: "node", port: 9000,
                bindings: [SocketBinding(address: "192.168.1.20", family: .ipv4)]
            ),
            process: ProcessSnapshot(pid: 1, parentPID: nil, name: "node", executablePath: nil,
                                     arguments: [], workingDirectory: nil, startedAt: nil, isRestricted: false),
            project: nil,
            detection: FrameworkDetection(framework: .node, confidence: 0.5),
            git: nil,
            metrics: nil,
            origin: .developer
        )
        #expect(service.supportsBrowserOpen == false)
    }

    @Test("A TLS flag on the command line produces an https URL")
    func tlsFromCommandLine() {
        let service = LocalService(
            id: ServiceIdentifier(pid: 1, port: 3000),
            listeningPort: ListeningPort(
                pid: 1, processName: "node", port: 3000,
                bindings: [SocketBinding(address: "127.0.0.1", family: .ipv4)]
            ),
            process: ProcessSnapshot(pid: 1, parentPID: nil, name: "node", executablePath: nil,
                                     arguments: ["next", "dev", "--experimental-https"],
                                     workingDirectory: nil, startedAt: nil, isRestricted: false),
            project: nil,
            detection: FrameworkDetection(framework: .nextJS, confidence: 0.9),
            git: nil,
            metrics: nil,
            origin: .developer
        )
        #expect(service.browserURL?.scheme == "https")
    }

    @Test("Display name falls back through the priority chain")
    func displayNameFallback() {
        #expect(SampleData.web.displayName == "web")      // from @dicee/web
        #expect(SampleData.postgres.displayName == "postgres")  // no project: process name
    }
}
