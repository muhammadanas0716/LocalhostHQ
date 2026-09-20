import Testing
@testable import LocalhostHQ

@Suite("lsof field parser")
struct LsofFieldParserTests {

    @Test("Parses a single IPv4 listener")
    func singleIPv4() {
        let output = """
        p992
        cpostgres
        f7
        tIPv4
        PTCP
        n127.0.0.1:5432
        """

        let sockets = LsofFieldParser.parse(output)
        #expect(sockets.count == 1)
        #expect(sockets[0].pid == 992)
        #expect(sockets[0].processName == "postgres")
        #expect(sockets[0].port == 5432)
        #expect(sockets[0].binding.address == "127.0.0.1")
        #expect(sockets[0].binding.family == .ipv4)
    }

    @Test("Parses IPv6 loopback in bracket form")
    func ipv6Loopback() {
        let output = """
        p25640
        cPython
        f3
        tIPv6
        PTCP
        n[::1]:8002
        """

        let sockets = LsofFieldParser.parse(output)
        #expect(sockets.count == 1)
        #expect(sockets[0].binding.address == "::1")
        #expect(sockets[0].binding.family == .ipv6)
        #expect(sockets[0].binding.isLoopback)
        #expect(sockets[0].port == 8002)
    }

    @Test("Wildcard binds are recognised on both families")
    func wildcard() {
        let output = """
        p4812
        cnode
        f13
        tIPv6
        PTCP
        n*:3000
        """

        let sockets = LsofFieldParser.parse(output)
        #expect(sockets.count == 1)
        #expect(sockets[0].binding.isWildcard)
        #expect(sockets[0].binding.isReachableViaLocalhost)
    }

    @Test("One process listening on several ports yields one socket each")
    func multiplePorts() {
        let output = """
        p1089
        cControlCenter
        f9
        tIPv4
        PTCP
        n*:7000
        f11
        tIPv4
        PTCP
        n*:5000
        """

        let sockets = LsofFieldParser.parse(output)
        #expect(sockets.count == 2)
        #expect(Set(sockets.map(\.port)) == [7000, 5000])
        #expect(sockets.allSatisfy { $0.processName == "ControlCenter" })
    }

    @Test("Process names containing spaces survive field parsing")
    func nameWithSpaces() {
        let output = """
        p22483
        cCode Helper (Plugin)
        f34
        tIPv4
        PTCP
        n127.0.0.1:60800
        """

        let sockets = LsofFieldParser.parse(output)
        #expect(sockets.count == 1)
        #expect(sockets[0].processName == "Code Helper (Plugin)")
    }

    @Test("Malformed and unknown lines are skipped without losing valid ones")
    func malformedInput() {
        let output = """
        garbage
        pNOTANUMBER
        cbroken
        f1
        tIPv4
        PTCP
        n127.0.0.1:1234
        p700
        credis-server
        f6
        tIPv4
        PTCP
        nnot-an-endpoint
        f7
        tIPv4
        PTCP
        n127.0.0.1:6379

        """

        let sockets = LsofFieldParser.parse(output)
        // Only the well-formed redis row survives: the first block has no valid
        // PID, and the endpoint-less row is dropped.
        #expect(sockets.count == 1)
        #expect(sockets[0].pid == 700)
        #expect(sockets[0].port == 6379)
    }

    @Test("Empty output produces no sockets")
    func emptyInput() {
        #expect(LsofFieldParser.parse("").isEmpty)
        #expect(LsofFieldParser.parse("\n\n\n").isEmpty)
    }

    @Test("Connected sockets are rejected")
    func rejectsConnectedSockets() {
        #expect(LsofFieldParser.parseEndpoint("127.0.0.1:52344->140.82.113.4:443") == nil)
    }

    @Test("Endpoint parsing rejects out-of-range and non-numeric ports")
    func rejectsBadPorts() {
        #expect(LsofFieldParser.parseEndpoint("127.0.0.1:0") == nil)
        #expect(LsofFieldParser.parseEndpoint("127.0.0.1:99999") == nil)
        #expect(LsofFieldParser.parseEndpoint("127.0.0.1:http") == nil)
        #expect(LsofFieldParser.parseEndpoint("3000") == nil)
        #expect(LsofFieldParser.parseEndpoint(":3000") == nil)
    }

    @Test("IPv6 zone identifiers are preserved")
    func ipv6Zone() {
        let endpoint = LsofFieldParser.parseEndpoint("[fe80::1%en0]:8080")
        #expect(endpoint?.address == "fe80::1%en0")
        #expect(endpoint?.port == 8080)
    }
}

@Suite("Socket de-duplication")
struct LsofDeduplicationTests {

    @Test("A dual-stack listener collapses into one entry")
    func dualStack() {
        let sockets = [
            ListeningSocket(pid: 4812, processName: "node", port: 3000,
                            binding: SocketBinding(address: "*", family: .ipv4)),
            ListeningSocket(pid: 4812, processName: "node", port: 3000,
                            binding: SocketBinding(address: "*", family: .ipv6)),
        ]

        let ports = LsofFieldParser.deduplicate(sockets)
        #expect(ports.count == 1)
        #expect(ports[0].port == 3000)
        #expect(ports[0].bindings.count == 2)
        #expect(ports[0].familyDescription == "IPv4/IPv6")
    }

    @Test("Identical rows repeated by lsof collapse to one binding")
    func exactDuplicates() {
        let binding = SocketBinding(address: "127.0.0.1", family: .ipv4)
        let sockets = Array(repeating: ListeningSocket(pid: 1, processName: "x", port: 80, binding: binding), count: 4)

        let ports = LsofFieldParser.deduplicate(sockets)
        #expect(ports.count == 1)
        #expect(ports[0].bindings == [binding])
    }

    @Test("Different processes on different ports stay separate")
    func distinctServices() {
        let sockets = [
            ListeningSocket(pid: 1, processName: "node", port: 3000,
                            binding: SocketBinding(address: "*", family: .ipv4)),
            ListeningSocket(pid: 2, processName: "postgres", port: 5432,
                            binding: SocketBinding(address: "127.0.0.1", family: .ipv4)),
            // Same process, second port.
            ListeningSocket(pid: 1, processName: "node", port: 3001,
                            binding: SocketBinding(address: "*", family: .ipv4)),
        ]

        let ports = LsofFieldParser.deduplicate(sockets)
        #expect(ports.count == 3)
    }

    @Test("Bindings are ordered deterministically regardless of input order")
    func stableOrdering() {
        let forward = [
            ListeningSocket(pid: 1, processName: "n", port: 3000, binding: SocketBinding(address: "::1", family: .ipv6)),
            ListeningSocket(pid: 1, processName: "n", port: 3000, binding: SocketBinding(address: "127.0.0.1", family: .ipv4)),
        ]
        let reversed = Array(forward.reversed())

        #expect(LsofFieldParser.deduplicate(forward)[0].bindings
                == LsofFieldParser.deduplicate(reversed)[0].bindings)
    }

    @Test("A LAN-only bind is not reachable via localhost")
    func lanOnlyBind() {
        let sockets = [
            ListeningSocket(pid: 9, processName: "svc", port: 9000,
                            binding: SocketBinding(address: "192.168.1.20", family: .ipv4)),
        ]
        let ports = LsofFieldParser.deduplicate(sockets)
        #expect(ports[0].isReachableViaLocalhost == false)
        #expect(ports[0].displayHost == "192.168.1.20")
    }
}
