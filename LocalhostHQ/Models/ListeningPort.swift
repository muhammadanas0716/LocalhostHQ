import Foundation

enum AddressFamily: String, Sendable, Hashable {
    case ipv4
    case ipv6
}

/// One address a socket is bound to.
struct SocketBinding: Sendable, Hashable {
    /// As reported by `lsof -n`: `127.0.0.1`, `::1`, `*`, `192.168.1.4`, …
    let address: String
    let family: AddressFamily

    /// `lsof -n` renders both `0.0.0.0` and `::` as `*`.
    var isWildcard: Bool {
        address == "*" || address == "0.0.0.0" || address == "::"
    }

    var isLoopback: Bool {
        address == "::1" || address.hasPrefix("127.")
    }

    /// Wildcard and loopback binds are both reachable through `localhost`; a
    /// bind to one specific LAN address is not.
    var isReachableViaLocalhost: Bool { isWildcard || isLoopback }
}

/// A single `LISTEN` socket row, before de-duplication.
struct ListeningSocket: Sendable, Hashable {
    let pid: Int32
    /// Command name as reported by lsof. Superseded by `ProcessSnapshot.name`
    /// once the process has been inspected.
    let processName: String
    let port: Int
    let binding: SocketBinding
}

/// A port a process listens on, with every interface it was seen bound to
/// collapsed into one entry. Dual-stack servers bind IPv4 *and* IPv6 to the
/// same port and must not appear twice.
struct ListeningPort: Sendable, Hashable {
    let pid: Int32
    let processName: String
    let port: Int
    let bindings: [SocketBinding]

    var isReachableViaLocalhost: Bool {
        bindings.contains(\.isReachableViaLocalhost)
    }

    /// What to show as the host. Anything reachable locally is presented as
    /// `localhost`, which is what the developer actually types.
    var displayHost: String {
        isReachableViaLocalhost ? "localhost" : (bindings.first?.address ?? "localhost")
    }

    /// `IPv4`, `IPv6` or `IPv4/IPv6`, for the inspector.
    var familyDescription: String {
        let families = Set(bindings.map(\.family))
        if families.count > 1 { return "IPv4/IPv6" }
        return families.first == .ipv6 ? "IPv6" : "IPv4"
    }

    var bindingDescription: String {
        bindings
            .map { "\($0.address):\(port)" }
            .sorted()
            .joined(separator: ", ")
    }
}

private extension Collection {
    func contains(_ keyPath: KeyPath<Element, Bool>) -> Bool {
        contains { $0[keyPath: keyPath] }
    }
}
